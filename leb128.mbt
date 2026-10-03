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
  /// A byte where an opcode was expected that no instruction uses.
  UnknownOpcode(Int, Int)
  /// A prefixed opcode whose sub-opcode is unassigned: the prefix byte, the
  /// sub-opcode, and where they sit.
  UnknownPrefixedOpcode(Int, Int, Int)
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

///|
/// Read a signed LEB128 integer of at most `bits` significant bits.
///
/// Block types, heap types and the `i32.const`/`i64.const` immediates are all
/// signed, and the sign lives in the last group's bit 6, so leaving it out would
/// turn a small negative constant into a large positive one. The `bits` bound is
/// what makes a non-terminating encoding malformed: a group may only continue
/// while fewer than `bits` bits have been consumed.
pub fn Reader::read_signed_leb(
  self : Reader,
  bits : Int,
) -> Result[Int, WasmError] {
  let start = self.pos
  let mut result = 0
  let mut shift = 0
  let mut byte = 0
  let mut more = true
  while more {
    if self.pos >= self.data.length() {
      return Err(WasmError::UnexpectedEnd(start, 1))
    }
    byte = self.data[self.pos].to_int()
    self.pos = self.pos + 1
    result = result | ((byte & 0x7F) << shift)
    shift = shift + 7
    if (byte & 0x80) == 0 {
      more = false
    } else if shift >= bits {
      return Err(WasmError::LebOverflow(start))
    }
  }
  // The final group's bit 6 is the sign; anything above it has to be filled in.
  if (byte & 0x40) != 0 && shift <= 63 {
    result = result | (-1 << shift)
  }
  Ok(result)
}

///|
/// Read a little-endian bit pattern of `count` bytes as a single integer.
///
/// Floating point constants have no structural meaning for a size analyzer, so
/// they are kept as the bits the file holds rather than converted and back.
pub fn Reader::read_bits(self : Reader, count : Int) -> Result[Int, WasmError] {
  let bytes = match self.read_bytes(count) {
    Ok(bytes) => bytes
    Err(error) => return Err(error)
  }
  let mut value = 0
  let mut i = 0
  while i < count {
    value = value | (bytes[i].to_int() << (8 * i))
    i = i + 1
  }
  Ok(value)
}
