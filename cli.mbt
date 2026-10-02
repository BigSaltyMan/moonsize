///|
/// Command-line decoding.
///
/// The library owns this rather than the entry point, so the argument grammar
/// can be tested without a process around it. `main` supplies the real
/// environment and nothing else.

///|
/// What to analyze and how much of it to show.
pub struct Options {
  path : String
  top : Int
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
/// The grammar is `moonsize <file.wasm> [--top <n>]`: exactly one positional
/// path, and a repeat of `--top` keeps the last value. Anything else is
/// reported as an error so a typo never silently analyses the wrong thing.
pub fn parse_options(args : Array[String]) -> Result[Options, String] {
  let mut path : String? = None
  let mut top = DEFAULT_TOP
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
    } else if path is None {
      path = Some(arg)
      i = i + 1
    } else {
      return Err("moonsize: unexpected argument " + arg + "\n\n" + usage())
    }
  }
  match path {
    Some(path) => Ok({ path, top, })
    None => Err(usage())
  }
}
