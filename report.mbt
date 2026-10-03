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
  "                 [--call-graph <path>] [--html <path>]\n" +
  "                 [--max-size <size>] [--baseline <path.wasm>] [--compress]\n\n" +
  "Report the section table of a WebAssembly binary, rank its heaviest\n" +
  "functions, roll the bytes up by module, and follow the call graph to\n" +
  "find what can be deleted.\n\n" +
  "  --top <n>            how many functions to rank (default 10)\n" +
  "  --retained           what deleting each function would free\n" +
  "  --dead-code          functions no root can reach\n" +
  "  --compress           what the file and each section cost gzip-compressed\n" +
  "  --call-graph <path>  write the call graph as .dot or .json\n" +
  "  --html <path>        write the charts as a self-contained HTML report\n" +
  "  --max-size <size>    fail with exit code 3 above this size, where size is\n" +
  "                       bytes or a KB/MB/GB count such as 10KB or 1.5MB\n" +
  "  --baseline <path>    compare against another module and print the change;\n" +
  "                       --max-size then bounds the growth, not the file\n\n" +
  "Exit codes: 0 ok, 1 unreadable input, 2 bad command line, 3 over budget."
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
/// The retained-size table: what deleting each function would free.
///
/// `SIZE` is the function on its own and `RETAINED` is that plus every function
/// that becomes unreachable with it, with `DIES` counting how many others that
/// is. A row where the two sizes match is load-bearing only for itself; a row
/// where `RETAINED` dwarfs `SIZE` is a good place to look when shrinking a
/// binary, because removing it takes everything underneath with it.
pub fn render_retained(
  stats : Array[FunctionStat],
  retained : Array[RetainedSize],
  indirect : Set[Int],
  file_size : Int,
  top : Int,
) -> String {
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
    "\n  DIES counts the other functions that become unreachable with this one.\n" +
    "  IND marks a function a call_indirect could reach."
  out
}

///|
/// The dead-code section: functions no root can reach.
///
/// This is the report that pays for the analysis. Anything listed here cannot
/// run: no export, no start function, no table entry and no path of calls leads
/// to it, so its bytes are already paid for and never used.
pub fn render_dead_code(
  stats : Array[FunctionStat],
  reachable : Set[Int],
  file_size : Int,
  top : Int,
) -> String {
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
/// The compression report: what the file costs as a transfer, and which sections
/// that cost is made of.
///
/// `SHARE(GZIP)` is a section's compressed size as a share of the whole file's
/// compressed size, not of its raw size, because that is the distribution a
/// network pays for. A section that is large raw and small compressed is not the
/// expensive one, and only this column says so.
///
/// The totals and the per-section numbers come from compressing each piece on its
/// own, so the sections do not add up to the total. Two effects are at work:
/// gzip finds redundancy between sections that compressing one in isolation
/// cannot see, and every stream pays its own header and trailer — about 20 bytes
/// — which a section smaller than that shows up as a ratio below 1. The shares
/// barely move for the same reason: 20 bytes against a table of kilobytes.
pub fn render_compression(
  raw_size : Int,
  gzip_size : Int,
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
    gzip_width = number_width(section.gzip, gzip_width)
    let ratio = ratio_text(section.raw, section.gzip)
    if ratio.length() > ratio_width {
      ratio_width = ratio.length()
    }
    ratios.push(ratio)
  }
  let share_width = "SHARE(GZIP)".length()
  let total_width = number_width(gzip_size, number_width(raw_size, 1))
  let mut out = "COMPRESSED SIZE\n  " +
    pad_right("raw", 4) +
    "  " +
    pad_left(raw_size.to_string(), total_width) +
    " B\n  " +
    pad_right("gzip", 4) +
    "  " +
    pad_left(gzip_size.to_string(), total_width) +
    " B  (" +
    share_text(gzip_size, raw_size) +
    " of raw, ratio " +
    ratio_text(raw_size, gzip_size) +
    ")\n\n  BY SECTION\n"
  if sections.length() == 0 {
    return out + "\n  no sections"
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
    "  " +
    pad_left("SHARE(GZIP)", share_width) +
    "\n"
  let mut i = 0
  for section in sections {
    out = out +
      "  " +
      pad_right(section.label, label_width) +
      "  " +
      pad_left(section.raw.to_string(), raw_width) +
      "  " +
      pad_left(section.gzip.to_string(), gzip_width) +
      "  " +
      pad_left(ratios[i], ratio_width) +
      "  " +
      pad_left(share_text(section.gzip, gzip_size), share_width) +
      "\n"
    i = i + 1
  }
  out
}
