///|
/// Growable byte buffer backed by FixedArray[Byte].
/// All internal access is bounds-check free.
struct Buffer {
  mut buf : FixedArray[Byte]
  mut pos : Int
}

///|
/// Create a new buffer with the given initial capacity.
pub fn Buffer::new(size_hint? : Int = 256) -> Buffer {
  { buf: make_uninit(size_hint), pos: 0, }
}

///|
/// Ensure space for at least `additional` more bytes. Grows with doubling strategy.
pub fn Buffer::ensure_capacity(self : Buffer, additional : Int) -> Unit {
  let required = self.pos + additional
  if required > self.buf.length() {
    let mut new_cap = self.buf.length() * 2
    if new_cap < required {
      new_cap = required
    }
    let new_buf = make_uninit(new_cap)
    blit_fixed_array(new_buf, 0, self.buf, 0, self.pos)
    self.buf = new_buf
  }
}

///|
/// Append a single byte.
pub fn Buffer::write_byte(self : Buffer, b : Byte) -> Unit {
  self.ensure_capacity(1)
  self.buf.unsafe_set(self.pos, b)
  self.pos += 1
}

///|
/// Append a single byte without capacity check. Caller must ensure capacity.
pub fn Buffer::write_byte_unchecked(self : Buffer, b : Byte) -> Unit {
  self.buf.unsafe_set(self.pos, b)
  self.pos += 1
}

///|
/// Append all bytes from `src`.
pub fn Buffer::write_bytes(self : Buffer, src : Bytes) -> Unit {
  let len = src.length()
  self.ensure_capacity(len)
  blit_bytes(self.buf, self.pos, src, 0, len)
  self.pos += len
}

///|
/// Append all bytes from `src`.
pub fn Buffer::write_bytesview(self : Buffer, src : BytesView) -> Unit {
  let len = src.length()
  self.ensure_capacity(len)
  blit_bytesview(self.buf, self.pos, src, src.start_offset(), len)
  self.pos += len
}

///|
/// Append `len` bytes from `src` starting at `offset`.
pub fn Buffer::write_fixed(
  self : Buffer,
  src : FixedArray[Byte],
  offset : Int,
  len : Int,
) -> Unit {
  self.ensure_capacity(len)
  blit_fixed_array(self.buf, self.pos, src, offset, len)
  self.pos += len
}

///|
/// Read byte at absolute position. Bounds-check free.
pub fn Buffer::get_byte(self : Buffer, pos : Int) -> Byte {
  self.buf.unsafe_get(pos)
}

///|
/// Copy `len` bytes from `src_pos` in the buffer to the current write position.
/// Handles overlapping regions correctly.
pub fn Buffer::copy_from_self(self : Buffer, src_pos : Int, len : Int) -> Unit {
  self.ensure_capacity(len)
  let distance = self.pos - src_pos
  if distance >= len {
    blit_fixed_array(self.buf, self.pos, self.buf, src_pos, len)
    self.pos += len
  } else {
    let buf = self.buf
    let mut dst = self.pos
    let mut src = src_pos
    for _ in 0..<len {
      buf.unsafe_set(dst, buf.unsafe_get(src))
      dst += 1
      src += 1
    }
    self.pos = dst
  }
}

///|
/// Current number of bytes written.
pub fn Buffer::length(self : Buffer) -> Int {
  self.pos
}

///|
/// Direct access to backing array.
pub fn Buffer::data(self : Buffer) -> FixedArray[Byte] {
  self.buf
}

///|
/// Finalize: allocate exact-size uninit array, blit, reinterpret as Bytes.
pub fn Buffer::to_bytes(self : Buffer) -> Bytes {
  let result = make_uninit(self.pos)
  blit_fixed_array(result, 0, self.buf, 0, self.pos)
  result.unsafe_reinterpret_as_bytes()
}

///|
/// Advance write position by `n`. Caller must have written directly to `data()`.
pub fn Buffer::unsafe_advance(self : Buffer, n : Int) -> Unit {
  self.pos += n
}

///|
/// Reset write position to 0. Reuses allocated memory.
pub fn Buffer::reset(self : Buffer) -> Unit {
  self.pos = 0
}
