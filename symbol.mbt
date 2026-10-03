///|
/// Symbol naming: turn the raw names a WebAssembly binary carries into
/// something a size report can read and group by.
///
/// MoonBit has no published specification for the symbols it emits, so the rules
/// here were recovered by reading the name section of real builds back. The
/// grammar that produced them (moonc 0.1.20260920, the `wasm` backend) is:
///
/// ```text
/// symbol    := "_M0" kind path generic? closure?
/// kind      := "F"          free function
///            | "M"          method, a `Type::name` definition
///            | "I"          trait implementation
/// path      := package component*
/// package   := "B"          the builtin package
///            | "C"          moonbitlang/core
///            | "P" digits   a package index, whose digits run into the first
///                           component's own length (`P55probe6mangle4...`)
/// component := digits name  digits counts the *mangled* name
/// generic   := "G" type* "E"
/// type      := a single letter for a builtin, `U` type* `E` for a tuple, or
///              `R` path for a named type
/// closure   := "C" digits "l" digits    closure id and the line it came from
/// ```
///
/// A name escapes anything that cannot appear in an identifier as `_` plus the
/// byte in hex, and doubles a literal underscore: `to__string_2einner` is
/// `to_string.inner`, `_24default__impl` is `$default_impl`, and a non-ASCII
/// character is escaped one byte at a time, so `中` arrives as `_e4_b8_ad`.
///
/// The backward walk below is what makes this workable: it never has to decide
/// where a package index ends and a component length begins, because it matches
/// components from the end and leaves whatever prefix is left over. It is a
/// display aid, not a codec — anything it cannot decode is returned untouched.

///|
/// The longest symbol worth decoding. Beyond this the walk is refused outright,
/// so a name forged into a binary cannot drive it into a deep recursion; the
/// symbol is then reported exactly as it was found.
const MAX_SYMBOL_LEN : Int = 4096

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
/// Every `<length><identifier>` reading that could end at `end`, as pairs of the
/// identifier's start and the start of its digit run.
///
/// The digits in front of an identifier are not always just its length: a
/// package index sits in front of the first component, so `P55probe` is index
/// `5` followed by `5probe`, and a name long enough to be 55 characters reads
/// as a single segment too. Both readings are locally valid, so they are all
/// returned and the caller decides.
fn segment_candidates(bytes : Bytes, end : Int) -> Array[(Int, Int)] {
  let found : Array[(Int, Int)] = []
  // Everything the walk could possibly match ends inside one run of identifier
  // characters, which is what keeps this linear instead of quadratic.
  let mut run_start = end
  while run_start > 0 && is_ident_char(bytes[run_start - 1]) {
    run_start = run_start - 1
  }
  let mut start = run_start
  while start < end {
    if is_ident_start(bytes[start]) {
      let length = end - start
      let mut digit_start = start
      while digit_start > run_start && is_ascii_digit(bytes[digit_start - 1]) {
        digit_start = digit_start - 1
      }
      if digit_start < start {
        let target = length.to_string()
        let mut cursor = digit_start
        while cursor < start {
          if @utf8.decode_lossy(bytes[cursor:start]) == target {
            found.push((start, cursor))
            break
          }
          cursor = cursor + 1
        }
      }
    }
    start = start + 1
  }
  found
}

///|
/// Where the walk may resume when the text it is holding ends with a package
/// marker.
///
/// A marker is otherwise always consumed together with the component that
/// follows it, but a symbol can carry two paths — a trait implementation names
/// its type's package and then its trait's (`P..CircleP..Shape`) — and then the
/// first marker is left stranded between the two, with nothing that can match
/// it. `None` means the text does not end with a marker.
fn marker_skip(bytes : Bytes, end : Int) -> Int? {
  let mut cursor = end
  while cursor > 0 && is_ascii_digit(bytes[cursor - 1]) {
    cursor = cursor - 1
  }
  if cursor > 0 && (bytes[cursor - 1] == b'B' || bytes[cursor - 1] == b'C') {
    cursor = cursor - 1
  }
  if cursor > 0 && bytes[cursor - 1] == b'P' {
    Some(cursor - 1)
  } else {
    None
  }
}

///|
/// The way to cut `bytes[0:end]` into the most segments, which is what a real
/// path looks like: one segment per component.
///
/// Taking the longest match at each step is what the first version of this did,
/// and it is wrong — `P55probe6mangle...` reads as one 55-character segment when
/// the package index is taken as the length. Counting segments instead picks the
/// reading that spells out every component. `memo` keeps the search linear in
/// the symbol's length, since every candidate resumes at a smaller `end`.
fn best_split(
  bytes : Bytes,
  end : Int,
  memo : Map[Int, Array[(Int, Int)]],
) -> Array[(Int, Int)] {
  match memo.get(end) {
    Some(cached) => cached
    None => {
      let mut best : Array[(Int, Int)] = []
      for candidate in segment_candidates(bytes, end) {
        let rest = best_split(bytes, candidate.1, memo)
        if rest.length() + 1 > best.length() {
          let combined : Array[(Int, Int)] = []
          for part in rest {
            combined.push(part)
          }
          combined.push((candidate.0, end))
          best = combined
        }
      }
      match marker_skip(bytes, end) {
        Some(next) => {
          // A skip claims no component of its own, so it only wins when it lets
          // the walk spell out more of the path than stopping here would.
          let rest = best_split(bytes, next, memo)
          if rest.length() > best.length() {
            best = rest
          }
        }
        None => ()
      }
      memo.set(end, best)
      best
    }
  }
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
  walk_segments(
    strip_generic_suffix(@utf8.decode_lossy(bytes[start:bytes.length()])),
  )
}

///|
/// Walk `<length><identifier>` segments backwards from the end of a mangled
/// path, so the innermost name comes last.
///
/// `None` means the text does not end in any segment the walk recognises, which
/// is not a failure: imported host functions and hand-written modules are named
/// plainly.
fn walk_segments(text : String) -> Array[String]? {
  let bytes = @utf8.encode(text)
  if bytes.length() > MAX_SYMBOL_LEN {
    return None
  }
  let split = best_split(bytes, bytes.length(), Map([]))
  if split.length() == 0 {
    return None
  }
  let segments : Array[String] = []
  for part in split {
    segments.push(@utf8.decode_lossy(bytes[part.0:part.1]))
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

///|
/// The value of one hexadecimal digit, or `None` when the byte is not one.
///
/// Named apart from `export.mbt`'s `hex_digit`, which renders a digit the other
/// way round.
fn hex_value(value : Byte) -> Int? {
  if value >= b'0' && value <= b'9' {
    Some((value - b'0').to_int())
  } else if value >= b'a' && value <= b'f' {
    Some((value - b'a').to_int() + 10)
  } else if value >= b'A' && value <= b'F' {
    Some((value - b'A').to_int() + 10)
  } else {
    None
  }
}

///|
/// Resolve the escapes inside one mangled name.
///
/// `__` is taken before `_` plus hex, which is what keeps `int__to__string__dec`
/// reading as `int_to_string_dec`: the doubled form is the encoding of a literal
/// underscore, so a run of them is not a run of escapes. Escaped bytes are
/// collected and decoded together, because one non-ASCII character arrives as
/// several escapes (`_e4_b8_ad` is `中`).
fn decode_escapes(text : String) -> String {
  let bytes = @utf8.encode(text)
  let out : Array[Byte] = []
  let mut i = 0
  while i < bytes.length() {
    if bytes[i] == b'_' && i + 1 < bytes.length() && bytes[i + 1] == b'_' {
      out.push(b'_')
      i = i + 2
    } else if bytes[i] == b'_' && i + 2 < bytes.length() {
      match (hex_value(bytes[i + 1]), hex_value(bytes[i + 2])) {
        (Some(high), Some(low)) => {
          out.push((high * 16 + low).to_byte())
          i = i + 3
        }
        _ => {
          out.push(bytes[i])
          i = i + 1
        }
      }
    } else {
      out.push(bytes[i])
      i = i + 1
    }
  }
  @utf8.decode_lossy(Bytes::from_array(out))
}

///|
/// The builtin types the mangling spells with a single letter.
///
/// Every letter here was read back from a build that instantiates one generic
/// function per builtin type, so they are observed rather than inferred (see
/// `symbol_wbtest.mbt`). A code that is missing is one no build produced, and it
/// stays undecoded: printing a type the binary never mentioned would be a lie.
fn builtin_type_name(code : Byte) -> String? {
  if code == b'i' {
    Some("Int")
  } else if code == b'd' {
    Some("Double")
  } else if code == b's' {
    Some("String")
  } else if code == b'b' {
    Some("Bool")
  } else if code == b'c' {
    Some("Char")
  } else if code == b'y' {
    Some("Byte")
  } else if code == b'f' {
    Some("Float")
  } else if code == b'l' {
    Some("Int64")
  } else if code == b'm' {
    Some("UInt64")
  } else if code == b'u' {
    Some("Unit")
  } else {
    None
  }
}

///|
/// Decode one type code, returning how it reads and where the next one starts.
fn decode_type(bytes : Bytes, index : Int, stop : Int) -> (String, Int)? {
  match builtin_type_name(bytes[index]) {
    Some(name) => Some((name, index + 1))
    None =>
      if bytes[index] == b'U' {
        match decode_types(bytes, index + 1, stop) {
          Some((items, next)) =>
            if next < stop && bytes[next] == b'E' {
              Some(("(" + items.join(", ") + ")", next + 1))
            } else {
              None
            }
          None => None
        }
      } else if bytes[index] == b'R' {
        decode_named_type(bytes, index + 1, stop)
      } else {
        None
      }
  }
}

///|
/// Decode a named type argument: `R` and then its path, optionally followed by
/// the type's own `G...E` argument list (`Array[Int]` arrives as
/// `R` `B5Array` `GiE`).
///
/// Neither the path nor the list it may be followed by carries a terminator, so
/// the only way to find the split is to try every `G` and keep the one where the
/// text before it is a path and the text after it is a complete list. `stop` is
/// the `E` that closes the caller's list, which is the last position that can
/// end this type.
fn decode_named_type(bytes : Bytes, start : Int, stop : Int) -> (String, Int)? {
  let mut split = start
  while split <= stop {
    if split == stop || bytes[split] == b'G' {
      match walk_segments(@utf8.decode_lossy(bytes[start:split])) {
        Some(segments) => {
          let name = segments.join("::")
          if split == stop {
            return Some((name, stop))
          }
          match decode_types(bytes, split + 1, stop) {
            Some((items, next)) =>
              if next < stop && bytes[next] == b'E' && items.length() > 0 {
                return Some((name + "[" + items.join(", ") + "]", next + 1))
              }
            None => ()
          }
        }
        None => ()
      }
    }
    split = split + 1
  }
  None
}

///|
/// Decode a run of type codes, stopping at the `E` that closes the list.
fn decode_types(
  bytes : Bytes,
  start : Int,
  stop : Int,
) -> (Array[String], Int)? {
  let items : Array[String] = []
  let mut i = start
  while i < stop && bytes[i] != b'E' {
    match decode_type(bytes, i, stop) {
      Some((name, next)) => {
        items.push(name)
        i = next
      }
      None => return None
    }
  }
  Some((items, i))
}

///|
/// Split a trailing `G<type codes>E` off a symbol, returning it and the types it
/// named.
///
/// The closing `E` does not point at its own `G` — type codes nest and a named
/// type carries a whole path — so every `G` is tried and the first whose body
/// decodes completely wins. `None` means the suffix was not understood.
fn split_generic_suffix(text : String) -> (String, Array[String])? {
  let bytes = @utf8.encode(text)
  let end = bytes.length()
  if end < 3 || bytes[end - 1] != b'E' {
    return None
  }
  let mut i = 0
  while i < end {
    if bytes[i] == b'G' {
      match decode_types(bytes, i + 1, end - 1) {
        Some((items, next)) =>
          if next == end - 1 && items.length() > 0 {
            return Some((@utf8.decode_lossy(bytes[0:i]), items))
          }
        None => ()
      }
    }
    i = i + 1
  }
  None
}

///|
/// Split the `C<closure id>l<line>` suffix a lifted closure carries, returning
/// the symbol without it and the line the closure was written on.
fn split_closure_suffix(text : String) -> (String, String?) {
  let bytes = @utf8.encode(text)
  let end = bytes.length()
  let mut line_start = end
  while line_start > 0 && is_ascii_digit(bytes[line_start - 1]) {
    line_start = line_start - 1
  }
  if line_start == end || line_start == 0 || bytes[line_start - 1] != b'l' {
    return (text, None)
  }
  let id_end = line_start - 1
  let mut id_start = id_end
  while id_start > 0 && is_ascii_digit(bytes[id_start - 1]) {
    id_start = id_start - 1
  }
  if id_start == id_end || id_start == 0 || bytes[id_start - 1] != b'C' {
    return (text, None)
  }
  (
    @utf8.decode_lossy(bytes[0:id_start - 1]),
    Some(@utf8.decode_lossy(bytes[line_start:end])),
  )
}

///|
/// The marker the compiler puts in front of the environment it synthesizes for a
/// closure. A name carrying it is not something the source ever wrote.
const CLOSURE_MARKER : String = "__moonbit_"

///|
/// The full decoded name for a symbol: escapes resolved, generic arguments
/// spelled out, lifted closures marked.
///
/// This is a display transform, not a codec. Every step is allowed to give up,
/// and when one does the original symbol is returned unchanged, because a size
/// report that invents a name is worse than one that shows a raw symbol.
///
/// Known limits, all of which fall back to the raw symbol: a type code outside
/// the builtin letters, a named type argument that is not the last one in a list
/// (its path has no terminator, so it cannot be told apart from what follows),
/// and any symbol that is not mangled by MoonBit in the first place.
pub fn demangle_full(symbol : String) -> String {
  let (stem_with_types, line) = split_closure_suffix(symbol)
  let (stem, arguments) = match split_generic_suffix(stem_with_types) {
    Some(split) => (split.0, Some(split.1))
    // The suffix may still be there in a shape the decoder does not know, and it
    // has to come off either way or the path cannot be walked at all.
    None => (strip_generic_suffix(stem_with_types), None)
  }
  let bytes = @utf8.encode(stem)
  // Mach-O style symbols may arrive with extra leading underscores.
  let mut start = 0
  while start < bytes.length() && bytes[start] == b'_' {
    start = start + 1
  }
  if bytes.length() - start < 3 ||
    bytes[start] != b'M' ||
    bytes[start + 1] != b'0' {
    return symbol
  }
  let tag = bytes[start + 2]
  if tag < b'A' || tag > b'Z' {
    return symbol
  }
  let segments = match walk_segments(stem) {
    Some(segments) => segments
    None => return symbol
  }
  let rendered : Array[String] = []
  for segment in segments {
    rendered.push(decode_escapes(segment))
  }
  // The last segment is the function itself; the compiler's closure environment
  // is named after the function it belongs to.
  let last = rendered.length() - 1
  if rendered[last].has_prefix(CLOSURE_MARKER) {
    rendered[last] = "[closure]" +
      rendered[last][CLOSURE_MARKER.length():].to_owned()
  }
  let mut name = rendered.join("::")
  match arguments {
    Some(items) => name = name + "[" + items.join(", ") + "]"
    None => ()
  }
  match line {
    Some(value) => name + "[closure@" + value + "]"
    None => name
  }
}
