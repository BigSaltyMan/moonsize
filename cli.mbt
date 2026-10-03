///|
/// Command-line decoding.
///
/// The library owns this rather than the entry point, so the argument grammar
/// can be tested without a process around it. `main` supplies the real
/// environment and nothing else.

///|
/// What to analyze, how much of it to show, and which reports to produce.
pub struct Options {
  path : String
  top : Int
  /// Print the retained-size section.
  retained : Bool
  /// Print the dead-code section.
  dead_code : Bool
  /// Write the call graph to this path instead of printing the text report.
  call_graph : String?
  /// Write the HTML report to this path instead of printing the text report.
  html : String?
}

///|
/// How many functions `--top` ranks when the flag is absent.
pub const DEFAULT_TOP : Int = 10

///|
/// A guard that keeps the decimal scan from overflowing on long input; no real
/// module has a million functions, let alone this many.
const MAX_TOP : Int = 1000000

///|
/// Parse a non-negative decimal integer, or `None` for anything else.
///
/// This toolchain's core library ships no string-to-`Int` parser, and the only
/// number the CLI accepts is `--top`, so the grammar stays deliberately narrow:
/// one or more ASCII digits, saturating into a rejection rather than an
/// overflow.
pub fn parse_count(text : String) -> Int? {
  if text.length() == 0 {
    return None
  }
  let bytes = @utf8.encode(text)
  let mut value = 0
  let mut i = 0
  while i < bytes.length() {
    let digit = bytes[i]
    if !is_ascii_digit(digit) {
      return None
    }
    if value > MAX_TOP {
      return None
    }
    value = value * 10 + (digit - b'0').to_int()
    i = i + 1
  }
  Some(value)
}

///|
/// Parse a full `argv`, including the program name in slot zero.
///
/// The grammar is `moonsize <file.wasm> [--top <n>] [--retained] [--dead-code]
/// [--call-graph <path>] [--html <path>]`: exactly one positional path, and a
/// repeat of a flag keeps the last value. Anything else is reported as an error
/// so a typo never silently analyses the wrong thing.
///
/// `--call-graph` and `--html` each write a file rather than a report, so
/// combining either with another output mode is rejected instead of quietly
/// ignoring one of them.
pub fn parse_options(args : Array[String]) -> Result[Options, String] {
  let mut path : String? = None
  let mut top = DEFAULT_TOP
  let mut retained = false
  let mut dead_code = false
  let mut call_graph : String? = None
  let mut html : String? = None
  let mut i = 1
  while i < args.length() {
    let arg = args[i]
    if arg == "--top" {
      if i + 1 >= args.length() {
        return Err("moonsize: --top needs a number\n\n" + usage())
      }
      match parse_count(args[i + 1]) {
        Some(count) => top = count
        None =>
          return Err(
            "moonsize: --top wants a whole number, got " +
            args[i + 1] +
            "\n\n" +
            usage(),
          )
      }
      i = i + 2
    } else if arg == "--retained" {
      retained = true
      i = i + 1
    } else if arg == "--dead-code" {
      dead_code = true
      i = i + 1
    } else if arg == "--call-graph" {
      if i + 1 >= args.length() {
        return Err("moonsize: --call-graph needs a path\n\n" + usage())
      }
      call_graph = Some(args[i + 1])
      i = i + 2
    } else if arg == "--html" {
      if i + 1 >= args.length() {
        return Err("moonsize: --html needs a path\n\n" + usage())
      }
      html = Some(args[i + 1])
      i = i + 2
    } else if path is None {
      path = Some(arg)
      i = i + 1
    } else {
      return Err("moonsize: unexpected argument " + arg + "\n\n" + usage())
    }
  }
  let path = match path {
    Some(path) => path
    None => return Err(usage())
  }
  match call_graph {
    Some(target) =>
      if retained || dead_code || html is Some(_) {
        return Err(
          "moonsize: --call-graph writes the graph to " +
          target +
          ", so it cannot be combined with --retained, --dead-code or --html\n\n" +
          usage(),
        )
      }
    None => ()
  }
  match html {
    Some(target) =>
      if retained || dead_code {
        return Err(
          "moonsize: --html writes the report to " +
          target +
          ", so it cannot be combined with --retained or --dead-code\n\n" +
          usage(),
        )
      }
    None => ()
  }
  Ok({ path, top, retained, dead_code, call_graph, html, })
}
