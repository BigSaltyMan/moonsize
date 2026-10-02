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
/// Attribute every code-section body to a name and a package.
///
/// Attribution is best effort by design: a release binary keeps no function
/// names, and the sizes are still worth reporting, so unnamed functions come
/// back labelled `(unnamed)` rather than failing the run.
pub fn collect_function_stats(
  parsed : WasmModule,
  data : Bytes,
) -> Result[Array[FunctionStat], WasmError] {
  let mut code_section : Section? = None
  let mut imported_functions = 0
  let mut names : Map[Int, String] = Map([])
  for section in parsed.sections {
    match section.kind {
      Code => code_section = Some(section)
      Import =>
        match count_imported_functions(data, section) {
          Ok(count) => imported_functions = count
          Err(error) => return Err(error)
        }
      Custom =>
        match parse_name_section(data, section) {
          Some(found) => names = found
          None => ()
        }
      _ => ()
    }
  }
  // The code section lists defined functions only, and imported functions hold
  // the first index slots, so the import count is what lines the two up.
  let bodies : Array[FunctionBody] = match code_section {
    Some(section) =>
      match parse_code_section(data, section, base_index=imported_functions) {
        Ok(bodies) => bodies
        Err(error) => return Err(error)
      }
    None => []
  }
  let stats : Array[FunctionStat] = []
  for body in bodies {
    let raw = match names.get(body.index) {
      Some(name) => name
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
    })
  }
  Ok(stats)
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
  "usage: moonsize <file.wasm> [--top <n>]\n\n" +
  "Report the section table of a WebAssembly binary, rank its heaviest\n" +
  "functions and roll the bytes up by module.\n\n" +
  "  --top <n>  how many functions to rank (default 10)"
}
