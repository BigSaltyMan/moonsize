///|
test "public parser rejects the reproduced overflowing section length at offset 9" {
  let data = b"\x00asm\x01\x00\x00\x00\x01\x80\x80\x80\x80\x10"
  match @moonsize.parse_module(data) {
    Err(LebOverflow(9)) => ()
    _ =>
      fail(
        "expected LebOverflow at the section length, not an empty type section",
      )
  }
}

///|
test "public analysis cannot borrow a start index from the next section" {
  // Empty start payload, followed by a valid custom section. The old reader
  // takes the following custom-section id (0) as the missing start index.
  let data = b"\x00asm\x01\x00\x00\x00\x08\x00\x00\x01\x00"
  let parsed = match @moonsize.parse_module(data) {
    Ok(parsed) => parsed
    Err(error) => fail(@moonsize.describe_error(error))
  }
  match @moonsize.analyze(data, parsed) {
    Err(UnexpectedEnd(10, 1)) => ()
    _ => fail("expected a bounded start-section error")
  }
}

///|
test "public u32 reader and parser distinguish valid large values from encoding errors" {
  let maximum : UInt = 4294967295
  match @moonsize.Reader::new(b"\xff\xff\xff\xff\x0f").read_u32_leb() {
    Ok(value) => assert_eq(value, maximum)
    Err(error) => fail(@moonsize.describe_error(error))
  }
  match
    @moonsize.parse_module(b"\x00asm\x01\x00\x00\x00\x01\xff\xff\xff\xff\x0f") {
    Err(ValueOutOfRange(9, value)) => assert_eq(value, maximum)
    _ => fail("expected an implementation range error for a valid u32 encoding")
  }
}

///|
test "public parser and analyzer accept a valid module with non shortest u32 encodings" {
  let data = b"\x00asm\x01\x00\x00\x00\x01\x85\x00\x81\x00\x60\x00\x00" +
    b"\x03\x02\x01\x00\x07\x07\x81\x00\x01r\x00\x80\x00" +
    b"\x0a\x86\x00\x81\x00\x82\x00\x00\x0b"
  let parsed = match @moonsize.parse_module(data) {
    Ok(parsed) => parsed
    Err(error) => fail(@moonsize.describe_error(error))
  }
  match @moonsize.analyze(data, parsed) {
    Ok(analysis) => {
      assert_eq(analysis.stats.length(), 1)
      assert_true(analysis.reachable.contains(0))
      assert_true(analysis.graph_complete)
    }
    Err(error) => fail(@moonsize.describe_error(error))
  }
}

///|
test "public bounded Reader reports range errors without changing position" {
  let reader = match @moonsize.Reader::new_range(b"abc", 1, 1) {
    Ok(reader) => reader
    Err(error) => fail(@moonsize.describe_error(error))
  }
  match reader.seek(0) {
    Err(InvalidReadRange(0, 0, 1, 2)) => ()
    _ => fail("expected invalid seek")
  }
  match reader.read_bytes(-1) {
    Err(InvalidReadRange(1, -1, 1, 2)) => ()
    _ => fail("expected negative count error")
  }
  assert_eq(reader.position(), 1)
}
