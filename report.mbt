///|
/// Left-pad to `width` so numeric columns line up.
fn pad_left(text : String, width : Int) -> String {
  let mut out = ""
  let mut i = text.length()
  while i < width {
    out = out + " "
    i = i + 1
  }
  out + text
}

///|
/// Right-pad to `width` so the section-name column is a stable gutter.
fn pad_right(text : String, width : Int) -> String {
  let mut out = text
  while out.length() < width {
    out = out + " "
  }
  out
}

///|
/// The module's sections, heaviest first.
///
/// The chart is about size, so the reader should be able to see which sections
/// matter without scanning the whole list. Ties keep file order, which is the
/// only other ordering the section table has.
fn ordered_sections(parsed : WasmModule) -> Array[Section] {
  let ordered = parsed.sections.copy()
  ordered.sort_by(fn(a, b) {
    if a.total_size != b.total_size {
      b.total_size - a.total_size
    } else {
      a.offset - b.offset
    }
  })
  ordered
}

///|
/// The label a section is known by in the report.
fn section_label(section : Section) -> String {
  match section.custom_name {
    Some(name) => section.kind.name() + " (" + name + ")"
    None => section.kind.name()
  }
}

///|
/// Render a ratio as a percentage with one decimal, using double arithmetic so
/// large module sizes cannot overflow the multiplication.
fn share_text(part : Int, whole : Int) -> String {
  if whole <= 0 {
    return "n/a"
  }
  let tenths = (part.to_double() / whole.to_double() * 1000.0).to_int()
  (tenths / 10).to_string() + "." + (tenths % 10).to_string() + "%"
}

///|
/// Name the binary format version, not just its number.
fn version_label(version : Int) -> String {
  if version == 1 {
    "1 (WebAssembly MVP)"
  } else {
    version.to_string()
  }
}

///|
/// The user-facing report: one line per section, each with its byte count.
///
/// The result carries no trailing newline, so the caller decides how to end it.
pub fn format_report(parsed : WasmModule, path : String) -> String {
  let mut accounted = 0
  for section in parsed.sections {
    accounted = accounted + section.total_size
  }
  let mut out = "moonsize — WebAssembly section report\n\n"
  out = out + "  file      " + path + "\n"
  out = out + "  size      " + parsed.file_size.to_string() + " bytes\n"
  out = out + "  version   " + version_label(parsed.version) + "\n"
  out = out + "  sections  " + parsed.sections.length().to_string() + "\n\n"
  out = out +
    "  " +
    pad_left("ID", 3) +
    "  " +
    pad_right("SECTION", 12) +
    "  " +
    pad_left("PAYLOAD", 10) +
    "  " +
    pad_left("TOTAL", 10) +
    "  " +
    pad_left("SHARE", 7) +
    "\n"
  for section in parsed.sections {
    let annotation = match section.custom_name {
      Some(name) => "  " + name
      None => ""
    }
    out = out +
      "  " +
      pad_left(section.id.to_string(), 3) +
      "  " +
      pad_right(section.kind.name(), 12) +
      "  " +
      pad_left(section.payload_size.to_string(), 10) +
      "  " +
      pad_left(section.total_size.to_string(), 10) +
      "  " +
      pad_left(share_text(section.payload_size, parsed.file_size), 7) +
      annotation +
      "\n"
  }
  out = out +
    "\n  accounted  " +
    accounted.to_string() +
    " bytes in sections (" +
    share_text(accounted, parsed.file_size) +
    " of file)"
  out
}

///|
/// `1 module` reads better than `1 modules`, and a report is prose too.
fn plural(count : Int, noun : String) -> String {
  if count == 1 {
    count.to_string() + " " + noun
  } else {
    count.to_string() + " " + noun + "s"
  }
}

///|
/// The width a right-aligned decimal column needs, never below `minimum`.
fn number_width(value : Int, minimum : Int) -> Int {
  let digits = value.to_string().length()
  if digits < minimum {
    minimum
  } else {
    digits
  }
}

///|
/// One function's byte budget, with the name and package the binary gives it.
pub struct FunctionStat {
  /// Index in the function index space, where imported functions come first.
  index : Int
  /// Display name: demangled when the binary mangles it.
  name : String
  /// Original nonempty symbol from the name section, before display demangling.
  /// None means missing or empty; the literal symbol `(unnamed)` is Some.
  raw_name : String?
  /// Package attributed by `module_of`.
  module_name : String
  /// Locals plus instruction bytes, i.e. what a compiler can still shrink.
  body_size : Int
  /// The body's size prefix plus the body: what the file actually spends.
  total_size : Int
  /// Offset of that size prefix from the start of the file.
  offset : Int
}

///|
/// Every function attributed to one package, rolled up.
priv struct ModuleStat {
  name : String
  functions : Int
  body_size : Int
  total_size : Int
}

///|
/// Attribute a body to a name and a package.
///
/// Attribution is best effort by design: a release binary keeps no function
/// names, and the sizes are still worth reporting, so unnamed functions come
/// back labelled `(unnamed)` rather than failing the run.
pub fn function_stats(
  bodies : Array[FunctionBody],
  names : Map[Int, String]?,
) -> Array[FunctionStat] {
  let stats : Array[FunctionStat] = []
  for body in bodies {
    let raw = match names {
      Some(names) =>
        match names.get(body.index) {
          Some(name) => name
          None => ""
        }
      None => ""
    }
    stats.push({
      index: body.index,
      raw_name: if raw.is_empty() {
        None
      } else {
        Some(raw)
      },
      name: if raw.length() == 0 {
        UNNAMED_FUNCTION
      } else {
        display_name(raw)
      },
      module_name: module_of(raw),
      body_size: body.body_size,
      total_size: body.total_size,
      offset: body.offset,
    })
  }
  stats
}

///|
/// Read a module's function names and sizes.
///
/// A convenience over `analyze` for callers that only want the size table; the
/// two share `function_stats`, so they cannot disagree about attribution.
pub fn collect_function_stats(
  parsed : WasmModule,
  data : Bytes,
) -> Result[Array[FunctionStat], WasmError] {
  let sections = find_sections(parsed)
  let imported = match sections.imports {
    Some(section) =>
      match count_imported_functions(data, section) {
        Ok(count) => count
        Err(error) => return Err(error)
      }
    None => 0
  }
  // The code section lists defined functions only, and imported functions hold
  // the first index slots, so the import count is what lines the two up.
  let bodies = match sections.code {
    Some(section) =>
      match parse_code_section(data, section, base_index=imported) {
        Ok(bodies) => bodies
        Err(error) => return Err(error)
      }
    None => []
  }
  let names = match sections.names {
    Some(section) => parse_name_section(data, section)
    None => None
  }
  Ok(function_stats(bodies, names))
}

///|
/// Rank functions by the bytes they cost, heaviest first, breaking ties by index
/// so equal-size functions keep a stable order.
fn rank_functions(stats : Array[FunctionStat]) -> Array[FunctionStat] {
  let ranked = stats.copy()
  ranked.sort_by(fn(a, b) {
    if a.total_size != b.total_size {
      b.total_size - a.total_size
    } else {
      a.index - b.index
    }
  })
  ranked
}

///|
/// Group functions by package, heaviest total first.
fn aggregate_by_module(stats : Array[FunctionStat]) -> Array[ModuleStat] {
  let rows : Array[ModuleStat] = []
  let seen : Map[String, Int] = Map([])
  for stat in stats {
    match seen.get(stat.module_name) {
      Some(at) => {
        let row = rows[at]
        rows[at] = {
          name: row.name,
          functions: row.functions + 1,
          body_size: row.body_size + stat.body_size,
          total_size: row.total_size + stat.total_size,
        }
      }
      None => {
        seen.set(stat.module_name, rows.length())
        rows.push({
          name: stat.module_name,
          functions: 1,
          body_size: stat.body_size,
          total_size: stat.total_size,
        })
      }
    }
  }
  rows.sort_by(fn(a, b) {
    if a.total_size != b.total_size {
      b.total_size - a.total_size
    } else {
      String::compare(a.name, b.name)
    }
  })
  rows
}

///|
/// The Top-N function table, heaviest first.
///
/// Shares are of the whole file, so a row here can be read against the section
/// table above it. `top` is clamped to the number of functions available.
pub fn render_top_functions(
  stats : Array[FunctionStat],
  file_size : Int,
  top : Int,
) -> String {
  let ranked = rank_functions(stats)
  let shown = if top < 0 {
    0
  } else if top > ranked.length() {
    ranked.length()
  } else {
    top
  }
  let mut index_width = 5
  let mut total_width = 10
  let mut body_width = 10
  for stat in stats {
    index_width = number_width(stat.index, index_width)
    body_width = number_width(stat.body_size, body_width)
    total_width = number_width(stat.total_size, total_width)
  }
  let rank_width = number_width(shown, 3)
  let mut out = "Top " +
    shown.to_string() +
    " of " +
    stats.length().to_string() +
    " functions by size\n"
  if shown == 0 {
    let reason = if stats.length() == 0 {
      "no functions in this binary"
    } else {
      "--top 0 requested, nothing to rank"
    }
    return out + "\n  " + reason
  }
  out = out +
    "\n  " +
    pad_left("#", rank_width) +
    "  " +
    pad_left("INDEX", index_width) +
    "  " +
    pad_left("BODY", body_width) +
    "  " +
    pad_left("TOTAL", total_width) +
    "  " +
    pad_left("SHARE", 7) +
    "  FUNCTION\n"
  let mut covered = 0
  let mut rank = 0
  while rank < shown {
    let stat = ranked[rank]
    covered = covered + stat.total_size
    out = out +
      "  " +
      pad_left((rank + 1).to_string(), rank_width) +
      "  " +
      pad_left(stat.index.to_string(), index_width) +
      "  " +
      pad_left(stat.body_size.to_string(), body_width) +
      "  " +
      pad_left(stat.total_size.to_string(), total_width) +
      "  " +
      pad_left(share_text(stat.total_size, file_size), 7) +
      "  " +
      stat.name +
      "\n"
    rank = rank + 1
  }
  out = out +
    "\n  these " +
    shown.to_string() +
    " hold " +
    covered.to_string() +
    " bytes (" +
    share_text(covered, file_size) +
    " of file)"
  out
}

///|
/// The per-package roll-up of every function in the binary.
pub fn render_module_summary(
  stats : Array[FunctionStat],
  file_size : Int,
) -> String {
  let modules = aggregate_by_module(stats)
  // The name column is the only variable-width one, so the gutter it needs is
  // simply the longest name; every other column keeps a fixed width.
  let mut gutter = "MODULE".length()
  let mut functions = 0
  let mut covered = 0
  for group in modules {
    if group.name.length() > gutter {
      gutter = group.name.length()
    }
    functions = functions + group.functions
    covered = covered + group.total_size
  }
  let mut out = "Size by module\n"
  if modules.length() == 0 {
    return out + "\n  no functions in this binary"
  }
  out = out +
    "\n  " +
    pad_right("MODULE", gutter) +
    "  " +
    pad_left("FUNCS", 5) +
    "  " +
    pad_left("BODY", 10) +
    "  " +
    pad_left("TOTAL", 10) +
    "  " +
    pad_left("SHARE", 7) +
    "\n"
  for group in modules {
    out = out +
      "  " +
      pad_right(group.name, gutter) +
      "  " +
      pad_left(group.functions.to_string(), 5) +
      "  " +
      pad_left(group.body_size.to_string(), 10) +
      "  " +
      pad_left(group.total_size.to_string(), 10) +
      "  " +
      pad_left(share_text(group.total_size, file_size), 7) +
      "\n"
  }
  out = out +
    "\n  " +
    plural(modules.length(), "module") +
    ", " +
    plural(functions, "function") +
    ", " +
    covered.to_string() +
    " bytes (" +
    share_text(covered, file_size) +
    " of file)"
  out
}

///|
/// Printed when the tool is invoked without a file, or with arguments it cannot
/// make sense of.
pub fn usage() -> String {
  "usage: moonsize <file.wasm> [--top <n>] [--retained] [--dead-code]\n" +
  "                 [--compress] [--strict] [--call-graph <path>] [--html <path>]\n" +
  "                 [--max-size <size>] [--baseline <path.wasm>] [--diff-functions]\n" +
  "                 [--data-segments] [--diff-data] [--data-json <new-path.json>]\n" +
  "                 [--budget <config.json>] [--budget-json <path.json>] [--budget-md <path.md>]\n" +
  "                 [--experiment <report.html|report.json>] [--experiment-context <context.json>]\n" +
  "       moonsize <file.wasm> --imports [--top <n>] [--imports-json <new.json>]\n" +
  "       moonsize <file.wasm> --why-index <n> [--why-root <n>] [--why-json <path.json>] [--strict]\n\n" +
  "Report the section table of a WebAssembly binary, rank its heaviest\n" +
  "functions, roll the bytes up by module, and follow the call graph to\n" +
  "identify candidates for investigation.\n\n" +
  "  --top <n>            how many functions to rank (default 10)\n" +
  "  --retained           dominated function bytes in the current graph model\n" +
  "  --dead-code          functions no root can reach\n" +
  "  --compress           whole-file gzip and independent section gzip sizes\n" +
  "  --data-segments      append data-entry file bytes (payload-ranked by --top)\n" +
  "  --data-json <path>   enable details and write all entries to a new .json file\n" +
  "                       offset expressions are recorded, not evaluated\n" +
  "  --diff-data          compare exact payload content groups; requires --baseline\n" +
  "                       --data-json then writes the data comparison format\n" +
  "  --strict             refuse to report when the call graph is incomplete,\n" +
  "                       instead of reporting it with a warning\n" +
  "  --call-graph <path>  write a new .dot or .json call graph; refuses existing paths\n" +
  "  --html <path>        write a new self-contained HTML report; refuses existing paths\n" +
  "                       --data-segments or --data-json adds current-input data details\n" +
  "  --max-size <size>    fail with exit code 3 above this size, where size is\n" +
  "                       bytes or a KB/MB/GB count such as 10KB or 1.5MB\n" +
  "  --budget <path>      validated multi-metric byte budgets; growth needs --baseline\n" +
  "  --budget-json <path> write budget JSON; requires --budget, refuses existing paths\n" +
  "  --budget-md <path>   write CI Markdown summary; requires --budget, refuses existing paths\n" +
  "  --baseline <path>    compare against another module and print the change;\n" +
  "                       --max-size then bounds the growth, not the file\n" +
  "  --diff-functions     append function and package changes; requires --baseline\n" +
  "  --experiment <path>  write measured before/after results; requires --baseline\n" +
  "                       refuses to overwrite an existing path\n" +
  "  --experiment-context <path>  attach declared build settings and validation\n" +
  "  --imports           list host import declarations and their file encoding bytes\n" +
  "  --imports-json <path> write complete imports JSON to a new .json file\n" +
  "                       only --top and --imports-json allowed; unsupported encodings fail\n" +
  "  --metadata          account for custom/name physical file bytes\n" +
  "  --metadata-json <path> write complete metadata JSON to a new .json file\n" +
  "                       only --top and --metadata-json allowed; partial details use exit 0\n" +
  "  --duplicates        group byte-identical local bodies (locals + instructions)\n" +
  "  --duplicates-json <path> write complete groups to a new .json file\n" +
  "                       only --top and --duplicates-json allowed; no savings estimate\n" +
  "  --entrypoints       analyze function-export reachable, exclusive and shared bytes\n" +
  "  --entrypoints-json <path> write complete entrypoint JSON to a new .json file\n" +
  "                       only --top, --entrypoints-json and --strict allowed\n" +
  "  --generics          group supported raw generic symbols by encoded function bytes\n" +
  "  --generics-json <path> write full groups to a new .json file; implies --generics\n" +
  "                       independent mode: only --top and --generics-json allowed\n" +
  "  --callers <n>        list recorded one-hop instruction references to function n\n" +
  "  --callers-json <path> write full callers JSON to a new .json file\n" +
  "                       only --top, --callers-json and --strict may accompany --callers\n" +
  "  --why-index <n>      explain a shortest model reference path to function n\n" +
  "  --why-root <n>       search from one actual model root (requires --why-index)\n" +
  "  --why-json <path>    write path JSON; refuses existing paths\n" +
  "                       query mode allows only these flags and --strict\n" +
  "                       element functions are conservative roots; paths are\n" +
  "                       not execution traces or predictions of savings\n\n" +
  "All report outputs refuse existing files, directories and link aliases.\n" +
  "Targets are checked together; each file is created exclusively. Output errors use exit 1.\n" +
  "Multiple files are not a transaction; a later failure may leave earlier new outputs.\n\n" +
  "Exit codes: 0 completed, 1 input/query/output/unavailable measurement, 2 bad arguments/config,\n" +
  "            3 over budget, incomplete strict graph, or path search limited."
}

///|
/// A lookup from function index to the name to print for it.
fn names_by_index(stats : Array[FunctionStat]) -> Map[Int, String] {
  let names : Map[Int, String] = Map([])
  for stat in stats {
    names.set(stat.index, stat.name)
  }
  names
}

///|
/// The name to print for an index, with a fallback for anything the size table
/// does not know about.
fn name_of(names : Map[Int, String], index : Int) -> String {
  match names.get(index) {
    Some(name) => name
    None => UNNAMED_FUNCTION
  }
}

///|
/// The line a section prints under its title when the call graph has holes, or
/// `""` when it does not, so a complete graph's report reads exactly as before.
fn incomplete_note(graph : CallGraph) -> String {
  let count = graph.diagnostics.length()
  if count == 0 {
    return ""
  }
  "  (graph incomplete: " +
  count.to_string() +
  " analysis " +
  (if count == 1 { "gap" } else { "gaps" }) +
  ")\n" +
  render_graph_warning(graph) +
  "\n"
}

///|
/// A copy so rendering never reorders the caller's diagnostic records.
fn sorted_diagnostics(graph : CallGraph) -> Array[GraphDiagnostic] {
  let diagnostics = graph.diagnostics.copy()
  diagnostics.sort_by(fn(a, b) {
    if a.caller != b.caller {
      a.caller - b.caller
    } else if a.offset != b.offset {
      a.offset - b.offset
    } else {
      let reason = String::compare(
        diagnostic_code(a.kind),
        diagnostic_code(b.kind),
      )
      if reason != 0 {
        reason
      } else {
        let left = match a.source {
          Some(source) => source.offset
          None => -1
        }
        let right = match b.source {
          Some(source) => source.offset
          None => -1
        }
        left - right
      }
    }
  })
  diagnostics
}

///|
fn diagnostic_code(kind : GraphDiagnosticKind) -> String {
  match kind {
    NoStaticTableTargets => "no_static_table_targets"
    UnmodeledReferenceCall => "unmodeled_reference_call"
    ImportedTableContents => "imported_table_contents"
    ExportedTableContents => "exported_table_contents"
    RuntimeTableMutation => "runtime_table_mutation"
    UnmodeledTableInitializer => "unmodeled_table_initializer"
    UnknownTableContents => "unknown_table_contents"
  }
}

///|
fn diagnostic_reason(kind : GraphDiagnosticKind) -> String {
  match kind {
    NoStaticTableTargets => "no static table targets are resolvable."
    UnmodeledReferenceCall =>
      "reference-call target analysis is not implemented."
    ImportedTableContents =>
      "imported table contents are supplied or shared by the host."
    ExportedTableContents =>
      "exported table contents may be changed by the host."
    RuntimeTableMutation => "runtime table contents may change."
    UnmodeledTableInitializer =>
      "explicit table initializer contents are not modelled."
    UnknownTableContents =>
      "target table is absent from the parsed table context."
  }
}

///|
fn diagnostic_details(diagnostic : GraphDiagnostic) -> String {
  let reason = diagnostic_reason(diagnostic.kind)
  match diagnostic.source {
    Some(source) => {
      let table = match diagnostic.table_index {
        Some(index) => "table " + index.to_string()
        None => "table"
      }
      match (source.caller, source.opcode) {
        (Some(caller), Some(opcode)) =>
          table +
          " contents may change through " +
          opcode.name() +
          " at function " +
          caller.to_string() +
          ", offset " +
          source.offset.to_string() +
          "."
        _ =>
          table +
          ": " +
          reason +
          " Source offset " +
          source.offset.to_string() +
          "."
      }
    }
    None => reason
  }
}

///|
fn graph_modeling_scope() -> String {
  "Direct calls, including direct tail calls, use exact targets; table calls use static element candidates. " +
  "Reference-call targets and dynamic table contents are not solved. " +
  "Imported/exported tables, runtime writes and explicit initializers are conservatively diagnosed, even with static candidates. " +
  "Element references are conservative roots, including private, passive and declarative segments. " +
  "graph_complete means no gaps detected within this scope, not full Wasm certification. " +
  retained_modeling_scope()
}

///|
fn retained_modeling_scope() -> String {
  "RETAINED sums dominated encoded function bytes within the current graph/root model. " +
  "It does not predict recompiled file reduction or whole-file gzip savings, even when --strict passes."
}

///|
/// The warning a report carries when the call graph could not follow every call,
/// or `""` when there is nothing to warn about.
///
/// It belongs above the whole report rather than beside the sections it
/// undermines: those sections are spread through the output, and a reader who
/// skips one of them still has to see this. Saying it is the point — a tool that
/// silently reports an incomplete graph as a fact is how a function in use gets
/// deleted.
pub fn render_graph_warning(graph : CallGraph) -> String {
  let diagnostics = sorted_diagnostics(graph)
  let count = diagnostics.length()
  if count == 0 {
    return ""
  }
  let mut warning = "WARNING: the call graph has " +
    count.to_string() +
    " analysis " +
    (if count == 1 { "gap" } else { "gaps" }) +
    ".\n"
  for diagnostic in diagnostics {
    warning = warning +
      "  function " +
      diagnostic.caller.to_string() +
      ", offset " +
      diagnostic.offset.to_string() +
      ": " +
      diagnostic.opcode.name() +
      ": " +
      diagnostic_details(diagnostic) +
      "\n"
  }
  warning +
  "\n" +
  "Dead-code and retained-size results may be inaccurate; " +
  "do not use them as proof that a function can be removed."
}

///|
/// The retained-size table, computed within the current graph model.
///
/// `SIZE` is the function's encoded bytes. `RETAINED` sums the encoded bytes of
/// reachable defined functions it dominates in this graph/root model, including
/// itself. `DIES` counts the other members of that model set. None of these
/// numbers predicts a source edit's recompiled file or gzip reduction.
pub fn render_retained(analysis : Analysis, top : Int) -> String {
  let stats = analysis.stats
  let retained = analysis.retained
  let indirect = analysis.indirect
  let file_size = analysis.parsed.file_size
  let names = names_by_index(stats)
  let ranked = retained.copy()
  ranked.sort_by(fn(a, b) {
    if a.retained != b.retained {
      b.retained - a.retained
    } else {
      a.index - b.index
    }
  })
  let shown = if top < 0 {
    0
  } else if top > ranked.length() {
    ranked.length()
  } else {
    top
  }
  let mut index_width = 5
  let mut size_width = 4
  let mut retained_width = 8
  for entry in retained {
    size_width = number_width(entry.own_size, size_width)
    retained_width = number_width(entry.retained, retained_width)
    index_width = number_width(entry.index, index_width)
  }
  let mut out = "Retained size\n"
  out = out + "  " + retained_modeling_scope() + "\n"
  out = out + incomplete_note(analysis.graph)
  if shown == 0 {
    return out + "\n  no reachable functions to rank"
  }
  let rank_width = number_width(shown, 3)
  out = out +
    "\n  " +
    pad_left("#", rank_width) +
    "  " +
    pad_left("INDEX", index_width) +
    "  " +
    pad_left("SIZE", size_width) +
    "  " +
    pad_left("RETAINED", retained_width) +
    "  " +
    pad_left("DIES", 4) +
    "  " +
    pad_left("SHARE", 7) +
    "  IND  FUNCTION\n"
  let mut rank = 0
  while rank < shown {
    let entry = ranked[rank]
    out = out +
      "  " +
      pad_left((rank + 1).to_string(), rank_width) +
      "  " +
      pad_left(entry.index.to_string(), index_width) +
      "  " +
      pad_left(entry.own_size.to_string(), size_width) +
      "  " +
      pad_left(entry.retained.to_string(), retained_width) +
      "  " +
      pad_left(entry.retained_functions.to_string(), 4) +
      "  " +
      pad_left(share_text(entry.retained, file_size), 7) +
      "  " +
      pad_left(if indirect.contains(entry.index) { "*" } else { "" }, 3) +
      "  " +
      name_of(names, entry.index) +
      "\n"
    rank = rank + 1
  }
  out = out +
    "\n  DIES counts other functions dominated by this function in the current model.\n" +
    "  IND marks a function an indirect call could reach."
  out
}

///|
/// The dead-code section: functions no root can reach.
///
/// Unreachable means no path within the current model. Detected gaps are always
/// shown, so a caller cannot omit the warning by forgetting an optional count.
pub fn render_dead_code(analysis : Analysis, top : Int) -> String {
  let stats = analysis.stats
  let reachable = analysis.reachable
  let file_size = analysis.parsed.file_size
  let dead : Array[FunctionStat] = []
  let mut bytes = 0
  for stat in stats {
    if !reachable.contains(stat.index) {
      dead.push(stat)
      bytes = bytes + stat.total_size
    }
  }
  dead.sort_by(fn(a, b) {
    if a.total_size != b.total_size {
      b.total_size - a.total_size
    } else {
      a.index - b.index
    }
  })
  let mut out = "Dead code\n"
  out = out + incomplete_note(analysis.graph)
  if stats.length() == 0 {
    return out + "\n  no functions in this binary"
  }
  out = out +
    "\n  " +
    dead.length().to_string() +
    " of " +
    stats.length().to_string() +
    " functions are unreachable from the roots\n" +
    "  " +
    bytes.to_string() +
    " bytes (" +
    share_text(bytes, file_size) +
    " of file)\n"
  if dead.length() == 0 {
    return out + "\n  every function is reachable"
  }
  let shown = if top < 0 {
    0
  } else if top > dead.length() {
    dead.length()
  } else {
    top
  }
  let mut size_width = 4
  for stat in dead {
    size_width = number_width(stat.total_size, size_width)
  }
  out = out +
    "\n  Top " +
    plural(shown, "dead function") +
    "\n\n  " +
    pad_left("SIZE", size_width) +
    "  " +
    pad_left("SHARE", 7) +
    "  FUNCTION\n"
  let mut rank = 0
  while rank < shown {
    let stat = dead[rank]
    if rank > 0 {
      out = out + "\n"
    }
    out = out +
      "  " +
      pad_left(stat.total_size.to_string(), size_width) +
      "  " +
      pad_left(share_text(stat.total_size, file_size), 7) +
      "  " +
      stat.name
    rank = rank + 1
  }
  out
}

///|
/// A compression ratio with two decimals, or `n/a` when there is nothing to
/// divide by.
fn ratio_text(raw : Int, gzip : Int) -> String {
  if gzip <= 0 {
    return "n/a"
  }
  let hundredths = (raw.to_double() / gzip.to_double() * 100.0).to_int()
  let fraction = hundredths % 100
  let fraction_text = if fraction < 10 {
    "0" + fraction.to_string()
  } else {
    fraction.to_string()
  }
  (hundredths / 100).to_string() + "." + fraction_text + "x"
}

///|
/// Whole-file gzip and independent full-section streams. Each ratio divides
/// that row's raw bytes by its own gzip bytes. Independent streams neither add
/// up to nor represent shares of whole-file gzip. Failures retain their reasons.
pub fn render_compression(
  raw_size : Int,
  gzip : Result[Int, String],
  sections : Array[SectionCompression],
) -> String {
  let mut label_width = "SECTION".length()
  let mut raw_width = "RAW".length()
  let mut gzip_width = "GZIP".length()
  let mut ratio_width = "RATIO".length()
  let ratios : Array[String] = []
  for section in sections {
    if section.label.length() > label_width {
      label_width = section.label.length()
    }
    raw_width = number_width(section.raw, raw_width)
    match section.gzip {
      Ok(size) => {
        gzip_width = number_width(size, gzip_width)
        let ratio = ratio_text(section.raw, size)
        if ratio.length() > ratio_width {
          ratio_width = ratio.length()
        }
        ratios.push(ratio)
      }
      Err(_) => {
        // The column has to fit the word as well as the numbers under it.
        if gzip_width < "failed".length() {
          gzip_width = "failed".length()
        }
        ratios.push("-")
      }
    }
  }
  let mut total_width = number_width(raw_size, 1)
  let total_text = match gzip {
    Ok(size) => {
      total_width = number_width(size, total_width)
      pad_left(size.to_string(), total_width) +
      " B  (" +
      share_text(size, raw_size) +
      " of raw, ratio " +
      ratio_text(raw_size, size) +
      ")"
    }
    Err(message) => "failed: " + message
  }
  let mut out = "COMPRESSED SIZE\n  " +
    pad_right("raw", 4) +
    "  " +
    pad_left(raw_size.to_string(), total_width) +
    " B\n  " +
    pad_right("gzip", 4) +
    "  " +
    total_text +
    "\n\n  BY SECTION — INDEPENDENT GZIP STREAMS\n"
  let note = "\n  Section gzip sizes are measured independently and are not additive.\n" +
    "  They do not represent shares of the whole-file gzip size.\n"
  if sections.length() == 0 {
    return out + "\n  no sections\n" + note
  }
  out = out +
    "\n  " +
    pad_right("SECTION", label_width) +
    "  " +
    pad_left("RAW", raw_width) +
    "  " +
    pad_left("GZIP", gzip_width) +
    "  " +
    pad_left("RATIO", ratio_width) +
    "\n"
  let mut i = 0
  for section in sections {
    let (gzip_cell, ratio_cell) = match section.gzip {
      Ok(size) =>
        (
          pad_left(size.to_string(), gzip_width),
          pad_left(ratios[i], ratio_width),
        )
      Err(_) => (pad_left("failed", gzip_width), pad_left("-", ratio_width))
    }
    out = out +
      "  " +
      pad_right(section.label, label_width) +
      "  " +
      pad_left(section.raw.to_string(), raw_width) +
      "  " +
      gzip_cell +
      "  " +
      ratio_cell +
      "\n"
    i = i + 1
  }
  out = out + note
  for section in sections {
    if section.gzip is Err(message) {
      out = out + "  gzip failed for " + section.label + ": " + message + "\n"
    }
  }
  out
}
