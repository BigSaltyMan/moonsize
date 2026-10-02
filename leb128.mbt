///|
/// Every failure mode the decoder can report, with the offset that explains it.
pub enum WasmError {
  /// The buffer ended before `needed` bytes were available at `offset`.
  UnexpectedEnd(Int, Int)
  /// The leading four bytes are not `\0asm`.
  BadMagic
  /// A section id outside the range assigned by the core specification.
  InvalidSectionId(Int)
  /// A LEB128 integer that does not terminate within its encoded width.
  LebOverflow(Int)
  /// An import descriptor whose kind byte is outside the assigned range.
  InvalidImportKind(Int)
}

///|
/// A forward-only cursor over a byte buffer.
///
/// The shape follows `jtenner/starshine`'s `src/binary` decoder, where a decode
/// step takes `(bytes, offset)` and reports how far it advanced, so callers can
/// walk a stream without hidden global state.
pub struct Reader {
  data : Bytes
  mut pos : Int
}

///|
pub fn Reader::new(data : Bytes) -> Reader {
  { data, pos: 0, }
}

///|
pub fn Reader::position(self : Reader) -> Int {
  self.pos
}

///|
pub fn Reader::remaining(self : Reader) -> Int {
  self.data.length() - self.pos
}

///|
pub fn Reader::at_end(self : Reader) -> Bool {
  self.pos >= self.data.length()
}

///|
/// Move the cursor to an absolute offset.
pub fn Reader::seek(self : Reader, offset : Int) -> Unit {
  self.pos = offset
}

///|
/// Read a single byte, or report the offset that ran out of input.
pub fn Reader::read_byte(self : Reader) -> Result[Int, WasmError] {
  if self.pos >= self.data.length() {
    return Err(WasmError::UnexpectedEnd(self.pos, 1))
  }
  let value = self.data[self.pos].to_int()
  self.pos = self.pos + 1
  Ok(value)
}

///|
/// Read `count` raw bytes and advance past them.
///
/// A view is enough for every caller here: names are decoded straight from it
/// and section payloads are skipped by size rather than copied.
pub fn Reader::read_bytes(
  self : Reader,
  count : Int,
) -> Result[BytesView, WasmError] {
  if self.remaining() < count {
    return Err(WasmError::UnexpectedEnd(self.pos, count))
  }
  let slice = self.data[self.pos:self.pos + count]
  self.pos = self.pos + count
  Ok(slice)
}

///|
/// Read an unsigned LEB128 integer of at most 32 significant bits.
///
/// WebAssembly encodes section payload lengths, vector counts and custom
/// section name lengths this way. Five groups of seven bits cover `u32`, so a
/// sixth continuation bit means the value is malformed.
pub fn Reader::read_u32_leb(self : Reader) -> Result[Int, WasmError] {
  let start = self.pos
  let mut result = 0
  let mut shift = 0
  let mut more = true
  while more {
    if self.pos >= self.data.length() {
      return Err(WasmError::UnexpectedEnd(start, 1))
    }
    let byte = self.data[self.pos].to_int()
    self.pos = self.pos + 1
    result = result | ((byte & 0x7F) << shift)
    if (byte & 0x80) == 0 {
      more = false
    } else {
      shift = shift + 7
      if shift >= 35 {
        return Err(WasmError::LebOverflow(start))
      }
    }
  }
  Ok(result)
}
