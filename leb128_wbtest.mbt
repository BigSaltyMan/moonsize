///|
fn bounded_reader(data : Bytes, start : Int, length : Int) -> Reader raise {
  match Reader::new_range(data, start, length) {
    Ok(reader) => reader
    Err(error) => fail(describe_error(error))
  }
}

///|
fn[T] assert_input_end(
  result : Result[T, WasmError],
  offset : Int,
  needed : Int,
) -> Unit raise {
  match result {
    Err(UnexpectedEnd(actual, count)) => {
      assert_eq(actual, offset)
      assert_eq(count, needed)
    }
    Err(error) => fail("expected UnexpectedEnd: " + describe_error(error))
    Ok(_) => fail("expected UnexpectedEnd")
  }
}

///|
fn[T] assert_read_range(
  result : Result[T, WasmError],
  offset : Int,
  length : Int,
  start : Int,
  end : Int,
) -> Unit raise {
  match result {
    Err(InvalidReadRange(actual, count, lower, upper)) => {
      assert_eq(actual, offset)
      assert_eq(count, length)
      assert_eq(lower, start)
      assert_eq(upper, end)
    }
    Err(error) => fail("expected InvalidReadRange: " + describe_error(error))
    Ok(_) => fail("expected InvalidReadRange")
  }
}

///|
test "u32 LEB decodes the entire unsigned range without signed truncation" {
  let cases : Array[(Bytes, UInt)] = [
    (b"\x00", 0),
    (b"\x7f", 127),
    (b"\x80\x01", 128),
    (b"\xff\x7f", 16383),
    (b"\x80\x80\x01", 16384),
    (b"\xff\xff\xff\xff\x07", 2147483647),
    (b"\x80\x80\x80\x80\x08", 2147483648),
    (b"\xff\xff\xff\xff\x0f", 4294967295),
  ]
  for (bytes, expected) in cases {
    let reader = Reader::new(bytes)
    match reader.read_u32_leb() {
      Ok(value) => assert_eq(value, expected)
      Err(error) => fail(describe_error(error))
    }
    assert_eq(reader.position(), bytes.length())
  }
}

///|
test "u32 LEB accepts non shortest encodings within five bytes" {
  for bytes in [b"\x80\x00", b"\x80\x80\x80\x80\x00"] {
    match Reader::new(bytes).read_u32_leb() {
      Ok(value) => assert_eq(value, 0U)
      Err(error) => fail(describe_error(error))
    }
  }
  match Reader::new(b"\xff\x80\x80\x80\x00").read_u32_leb() {
    Ok(value) => assert_eq(value, 127U)
    Err(error) => fail(describe_error(error))
  }
}

///|
test "u32 LEB rejects every illegal fifth byte before combining high bits" {
  for last = 0x10; last <= 0xff; last = last + 1 {
    let bytes = b"\xaa\x80\x80\x80\x80" +
      Bytes::from_array([last.to_byte()]) +
      b"\x00"
    let reader = bounded_reader(bytes, 1, bytes.length() - 1)
    match reader.read_u32_leb() {
      Err(LebOverflow(1)) => ()
      _ => fail("expected LebOverflow at nonzero field start")
    }
    assert_eq(reader.position(), 6)
  }
}

///|
test "u32 LEB rejects overlong encodings without consuming a sixth byte" {
  let reader = Reader::new(b"\x80\x80\x80\x80\x80\x00")
  match reader.read_u32_leb() {
    Err(LebOverflow(0)) => ()
    _ => fail("expected LebOverflow")
  }
  assert_eq(reader.position(), 5)
  assert_eq(reader.remaining(), 1)
}

///|
test "u32 LEB reports every truncation position at the absolute field start" {
  let bytes = b"\xaa\xbb\xff\xff\xff\xff\x0f"
  for length = 0; length < 5; length = length + 1 {
    let reader = bounded_reader(bytes, 2, length)
    assert_input_end(reader.read_u32_leb(), 2, 1)
    assert_eq(reader.position(), 2 + length)
  }
}

///|
test "checked u32 conversion accepts Int maximum and rejects larger valid values" {
  match read_u32_as_int(Reader::new(b"\xff\xff\xff\xff\x07")) {
    Ok(value) => assert_eq(value, 2147483647)
    Err(error) => fail(describe_error(error))
  }
  let cases : Array[(Bytes, UInt)] = [
    (b"\x80\x80\x80\x80\x08", 2147483648),
    (b"\xff\xff\xff\xff\x0f", 4294967295),
  ]
  for (bytes, expected) in cases {
    match read_u32_as_int(bounded_reader(b"\xaa\xbb" + bytes, 2, 5)) {
      Err(ValueOutOfRange(offset, value)) => {
        assert_eq(offset, 2)
        assert_eq(value, expected)
      }
      _ => fail("expected ValueOutOfRange, not LebOverflow or a truncated Int")
    }
  }
}

///|
test "checked u32 conversion preserves malformed and truncated error categories" {
  match read_u32_as_int(Reader::new(b"\x80\x80\x80\x80\x10")) {
    Err(LebOverflow(0)) => ()
    _ => fail("expected encoding error")
  }
  assert_input_end(read_u32_as_int(Reader::new(b"\x80")), 0, 1)
}

///|
test "Reader range construction rejects negative and overflowing requests" {
  for
    (start, length) in [
      (-1, 1),
      (0, -1),
      (4, 0),
      (1, 2147483647),
      (2147483647, 2147483647),
    ] {
    assert_read_range(
      Reader::new_range(b"abc", start, length),
      start,
      length,
      0,
      3,
    )
  }
}

///|
test "Reader accepts the empty range at the file end" {
  let reader = bounded_reader(b"abc", 3, 0)
  assert_eq(reader.position(), 3)
  assert_eq(reader.remaining(), 0)
  assert_true(reader.at_end())
  assert_input_end(reader.read_byte(), 3, 1)
  assert_input_end(reader.read_bytes(1), 3, 1)
  match reader.read_bytes(0) {
    Ok(bytes) => assert_eq(bytes.length(), 0)
    Err(error) => fail(describe_error(error))
  }
}

///|
test "Reader seek respects both bounds and leaves the cursor unchanged on error" {
  let reader = bounded_reader(b"abcde", 1, 2)
  match reader.seek(2) {
    Ok(_) => ()
    Err(error) => fail(describe_error(error))
  }
  for offset in [-1, 0, 4, 2147483647] {
    assert_read_range(reader.seek(offset), offset, 0, 1, 3)
    assert_eq(reader.position(), 2)
  }
  match reader.seek(3) {
    Ok(_) => ()
    Err(error) => fail(describe_error(error))
  }
  assert_input_end(reader.read_byte(), 3, 1)
}

///|
test "Reader read_bytes rejects negative and excessive counts without moving" {
  let reader = bounded_reader(b"abcd", 1, 2)
  assert_read_range(reader.read_bytes(-1), 1, -1, 1, 3)
  assert_eq(reader.position(), 1)
  assert_input_end(reader.read_bytes(2147483647), 1, 2147483647)
  assert_eq(reader.position(), 1)
  match reader.read_bytes(2) {
    Ok(bytes) => assert_eq(@utf8.decode_lossy(bytes), "bc")
    Err(error) => fail(describe_error(error))
  }
  assert_true(reader.at_end())
  assert_input_end(reader.read_byte(), 3, 1)
}

///|
test "bounded signed LEB and fixed width bits cannot consume following bytes" {
  assert_input_end(
    bounded_reader(b"\xaa\x80\x00", 1, 1).read_signed_leb(32),
    1,
    1,
  )
  let reader = bounded_reader(b"\xaa\x01\x02\x03\x04", 1, 2)
  assert_input_end(reader.read_bits(4), 1, 4)
  assert_eq(reader.position(), 1)
  assert_read_range(reader.read_bits(-1), 1, -1, 1, 3)
  assert_eq(reader.position(), 1)
}

///|
test "new parse errors have distinct descriptions and absolute positions" {
  let maximum : UInt = 4294967295
  assert_true(
    describe_error(ValueOutOfRange(9, maximum)).contains(
      "unsigned value at offset 9 exceeds the supported integer range",
    ),
  )
  assert_true(
    describe_error(LebOverflow(9)).contains("LEB128 integer at offset 9"),
  )
  assert_true(
    describe_error(InvalidReadRange(-1, 2, 0, 3)).contains("offset -1"),
  )
}
