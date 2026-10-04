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
  /// The size budget: a ceiling on the file, or — when `baseline` is set — the
  /// growth the file may show over the baseline.
  max_size : Int?
  /// Compare against this module instead of checking an absolute ceiling.
  baseline : String?
  /// Print what the file and each section cost once gzip-compressed.
  compress : Bool
}

///|
/// How many functions `--top` ranks when the flag is absent.
pub const DEFAULT_TOP : Int = 10

///|
/// The defaults `parse_options` starts from, with one flat report for the module
/// at `path`. For callers that link this module as a library instead of running
/// the CLI: every flag the command line can set is left at its absent value.
pub fn Options::default(path : String) -> Options {
  {
    path,
    top: DEFAULT_TOP,
    retained: false,
    dead_code: false,
    call_graph: None,
    html: None,
    max_size: None,
    baseline: None,
    compress: false,
  }
}

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
/// The byte for an ASCII letter's lowercase form, and anything else unchanged.
fn lower_byte(value : Byte) -> Byte {
  if value >= b'A' && value <= b'Z' {
    value + 32
  } else {
    value
  }
}

///|
/// True when `bytes` spells `text`, ignoring ASCII case.
fn suffix_is(bytes : BytesView, text : String) -> Bool {
  let candidate = @utf8.encode(text)
  if bytes.length() != candidate.length() {
    return false
  }
  let mut i = 0
  while i < bytes.length() {
    if lower_byte(bytes[i]) != lower_byte(candidate[i]) {
      return false
    }
    i = i + 1
  }
  true
}

///|
/// The multiplier a size suffix stands for.
fn size_scale(suffix : BytesView) -> Int? {
  if suffix.length() == 0 || suffix_is(suffix, "b") {
    Some(1)
  } else if suffix_is(suffix, "kb") {
    Some(1024)
  } else if suffix_is(suffix, "mb") {
    Some(1024 * 1024)
  } else if suffix_is(suffix, "gb") {
    Some(1024 * 1024 * 1024)
  } else {
    None
  }
}

///|
/// The largest size the parser will accept. `Int` is 32 bits wide here, so the
/// ceiling is what keeps a long digit run from wrapping instead of being
/// rejected; two gigabytes is far past any WebAssembly module.
const MAX_SIZE : Int = 2000000000

///|
/// Parse a byte size: a decimal count with an optional `KB`, `MB` or `GB`
/// suffix, so `--max-size 10KB` and `--max-size 1.5MB` both work.
///
/// The suffixes are binary — a KB is 1024 bytes — which is what a size report
/// means by the word. A fraction has to be followed by a suffix: `--max-size
/// 1.5` is rejected, because half a byte is not a size.
pub fn parse_size(text : String) -> Int? {
  let bytes = @utf8.encode(text)
  let end = bytes.length()
  if end == 0 {
    return None
  }
  // The suffix, when there is one, is the trailing run of letters.
  let mut count_end = end
  while count_end > 0 && is_ascii_letter(bytes[count_end - 1]) {
    count_end = count_end - 1
  }
  let scale = match size_scale(bytes[count_end:end]) {
    Some(scale) => scale
    None => return None
  }
  // The ceiling is checked before each multiply, not after: once `whole * 10`
  // has wrapped there is nothing left to compare against.
  let whole_limit = MAX_SIZE / 10
  let last_digit = MAX_SIZE % 10
  let mut whole = 0
  let mut i = 0
  while i < count_end && is_ascii_digit(bytes[i]) {
    let digit = (bytes[i] - b'0').to_int()
    if whole > whole_limit || (whole == whole_limit && digit > last_digit) {
      return None
    }
    whole = whole * 10 + digit
    i = i + 1
  }
  if i == 0 {
    return None
  }
  let mut value = whole.to_double()
  if i < count_end && bytes[i] == b'.' {
    if scale == 1 {
      return None
    }
    i = i + 1
    let mut place = 0.1
    let mut digits = 0
    while i < count_end && is_ascii_digit(bytes[i]) {
      value = value + (bytes[i] - b'0').to_int().to_double() * place
      place = place / 10.0
      digits = digits + 1
      i = i + 1
    }
    if digits == 0 {
      return None
    }
  }
  if i != count_end {
    return None
  }
  // The ceiling is checked before the conversion, because rounding a value the
  // `Int` cannot hold is what would wrap it.
  let scaled = value * scale.to_double()
  if scaled > MAX_SIZE.to_double() {
    return None
  }
  Some(scaled.to_int())
}

///|
/// Parse a full `argv`, including the program name in slot zero.
///
/// The grammar is `moonsize <file.wasm> [--top <n>] [--retained] [--dead-code]
/// [--call-graph <path>] [--html <path>] [--max-size <size>] [--baseline
/// <path.wasm>] [--compress]`: exactly one positional path, and a repeat of a flag keeps the
/// last value. Anything else is reported as an error so a typo never silently
/// analyses the wrong thing.
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
  let mut max_size : Int? = None
  let mut baseline : String? = None
  let mut compress = false
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
    } else if arg == "--max-size" {
      if i + 1 >= args.length() {
        return Err("moonsize: --max-size needs a size\n\n" + usage())
      }
      match parse_size(args[i + 1]) {
        Some(size) => max_size = Some(size)
        None =>
          return Err(
            "moonsize: --max-size wants a byte count, optionally with a KB, MB or GB suffix, got " +
            args[i + 1] +
            "\n\n" +
            usage(),
          )
      }
      i = i + 2
    } else if arg == "--compress" {
      compress = true
      i = i + 1
    } else if arg == "--baseline" {
      if i + 1 >= args.length() {
        return Err("moonsize: --baseline needs a path\n\n" + usage())
      }
      baseline = Some(args[i + 1])
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
  Ok({
    path,
    top,
    retained,
    dead_code,
    call_graph,
    html,
    max_size,
    baseline,
    compress,
  })
}
