///|
/// Symbol naming: turn the raw names a WebAssembly binary carries into
/// something a size report can read and group by.
///
/// MoonBit mangles the symbols it emits (`_M0FP34demo6sample3src8classify`), and
/// the mangling has no published specification. The decoder below follows the
/// heuristic used by pprof-style tooling for the same problem: strip the prefix,
/// drop any generic-instantiation suffix, then walk the remainder backwards
/// matching `<decimal length><identifier>` segments. It is a display aid, not a
/// codec — anything it cannot decode is returned untouched.

///|
/// The longest identifier a mangled segment may carry. Candidates are tried
/// longest-first, so this only has to exceed real symbol names.
const MAX_SEGMENT_LEN : Int = 64

///|
/// A hard stop for the backward walk, so a pathological symbol cannot spin.
const MAX_SEGMENTS : Int = 50

///|
/// Attribution for a function the binary does not name.
const UNNAMED_FUNCTION : String = "(unnamed)"

///|
/// Attribution for a named function whose name carries no package, such as an
/// imported host function like `fd_write`.
const TOP_LEVEL_FUNCTION : String = "(top-level)"

///|
/// True for the ASCII digits, which is the alphabet of the length prefixes.
fn is_ascii_digit(value : Byte) -> Bool {
  value >= b'0' && value <= b'9'
}

///|
/// True for the ASCII letters.
fn is_ascii_letter(value : Byte) -> Bool {
  (value >= b'A' && value <= b'Z') || (value >= b'a' && value <= b'z')
}

///|
/// True when the byte may start an identifier.
fn is_ident_start(value : Byte) -> Bool {
  value == b'_' || is_ascii_letter(value)
}

///|
/// True when the byte may continue an identifier.
fn is_ident_char(value : Byte) -> Bool {
  is_ident_start(value) || is_ascii_digit(value)
}

///|
/// True when `bytes[start:end]` spells a MoonBit identifier.
fn is_ident(bytes : Bytes, start : Int, end : Int) -> Bool {
  if end <= start || !is_ident_start(bytes[start]) {
    return false
  }
  let mut i = start + 1
  while i < end {
    if !is_ident_char(bytes[i]) {
      return false
    }
    i = i + 1
  }
  true
}

///|
/// Match one `<length><identifier>` segment ending at `end`.
///
/// Longest candidates are tried first, which is what makes the backward walk
/// unambiguous. The digit run in front of an identifier may also carry a leading
/// namespace count of its own (`26mizchi` is count `2` then length `6`), so
/// every suffix of the run is tried and the one spelling the identifier's length
/// wins. Returns the identifier's start and where the walk resumes.
fn find_segment_end(bytes : Bytes, end : Int) -> (Int, Int)? {
  let longest = if end - 1 < MAX_SEGMENT_LEN {
    end - 1
  } else {
    MAX_SEGMENT_LEN
  }
  let mut length = longest
  while length >= 1 {
    let start = end - length
    if is_ident(bytes, start, end) {
      let mut digit_start = start
      while digit_start > 0 && is_ascii_digit(bytes[digit_start - 1]) {
        digit_start = digit_start - 1
      }
      if digit_start < start {
        let target = length.to_string()
        let mut cursor = digit_start
        while cursor < start {
          if @utf8.decode_lossy(bytes[cursor:start]) == target {
            return Some((start, cursor))
          }
          cursor = cursor + 1
        }
      }
    }
    length = length - 1
  }
  None
}

///|
/// Drop a trailing `G<letters>E` generic-instantiation marker.
fn strip_generic_suffix(name : String) -> String {
  let bytes = @utf8.encode(name)
  let end = bytes.length()
  if end < 3 || bytes[end - 1] != b'E' {
    return name
  }
  let mut i = end - 1
  while i > 0 && is_ascii_letter(bytes[i - 1]) && bytes[i - 1] != b'G' {
    i = i - 1
  }
  if i > 0 && bytes[i - 1] == b'G' && i - 1 < end - 1 {
    return @utf8.decode_lossy(bytes[0:i - 1])
  }
  name
}

///|
/// The readable segments of a mangled MoonBit symbol, innermost name last.
///
/// `None` means the name is not mangled, which is not a failure: imported host
/// functions and hand-written modules are named plainly.
fn mangled_segments(name : String) -> Array[String]? {
  let bytes = @utf8.encode(name)
  // Mach-O style symbols may arrive with extra leading underscores.
  let mut start = 0
  while start < bytes.length() && bytes[start] == b'_' {
    start = start + 1
  }
  if bytes.length() - start < 3 {
    return None
  }
  if bytes[start] != b'M' || bytes[start + 1] != b'0' {
    return None
  }
  let tag = bytes[start + 2]
  if tag < b'A' || tag > b'Z' {
    return None
  }
  let inner = strip_generic_suffix(
    @utf8.decode_lossy(bytes[start:bytes.length()]),
  )
  let inner_bytes = @utf8.encode(inner)
  let segments : Array[String] = []
  let mut cursor = inner_bytes.length()
  let mut steps = 0
  while cursor > 0 && steps < MAX_SEGMENTS {
    match find_segment_end(inner_bytes, cursor) {
      Some(found) => {
        segments.insert(0, @utf8.decode_lossy(inner_bytes[found.0:cursor]))
        cursor = found.1
      }
      None => break
    }
    steps = steps + 1
  }
  if segments.length() == 0 {
    return None
  }
  Some(segments)
}

///|
/// The name to print for a symbol: demangled when the binary mangles it,
/// otherwise left exactly as the producer wrote it.
pub fn display_name(name : String) -> String {
  match mangled_segments(name) {
    Some(segments) => segments.join("::")
    None => name
  }
}

///|
/// The package a symbol belongs to.
///
/// Everything in the name except the final segment is the package, so
/// `demo::sample::src::fib` lands in `demo::sample::src` and `tlsf/searchBlock`
/// in `tlsf`. Names with no package at all are grouped under `(top-level)`,
/// which keeps the roll-up honest instead of inventing one bucket per function.
pub fn module_of(name : String) -> String {
  if name.length() == 0 {
    return UNNAMED_FUNCTION
  }
  match mangled_segments(name) {
    Some(segments) => {
      if segments.length() < 2 {
        return TOP_LEVEL_FUNCTION
      }
      let prefix : Array[String] = []
      let mut i = 0
      while i < segments.length() - 1 {
        prefix.push(segments[i])
        i = i + 1
      }
      return prefix.join("::")
    }
    None => ()
  }
  // Plain names separate their package with `/` or `.`; the last separator wins,
  // because the final segment is the function itself.
  let bytes = @utf8.encode(name)
  let mut cut = -1
  let mut i = 0
  while i < bytes.length() {
    if bytes[i] == b'/' || bytes[i] == b'.' {
      cut = i
    }
    i = i + 1
  }
  if cut <= 0 {
    return TOP_LEVEL_FUNCTION
  }
  @utf8.decode_lossy(bytes[0:cut])
}
