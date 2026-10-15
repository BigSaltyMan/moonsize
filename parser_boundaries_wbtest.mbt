///|
/// A section-stream fixture. Malformed payloads below deliberately are not valid
/// Wasm modules; metadata-only and Reader tests are not full-module validators.
fn parser_fixture(sections : Bytes) -> Bytes {
  b"\x00asm\x01\x00\x00\x00" + sections
}

///|
fn parsed_fixture(data : Bytes) -> WasmModule raise {
  match parse_module(data) {
    Ok(parsed) => parsed
    Err(error) => fail(describe_error(error))
  }
}

///|
test "section lengths distinguish malformed encoding from supported range limits" {
  for
    bytes in [
      b"\x80\x80\x80\x80\x10", b"\xff\xff\xff\xff\x7f", b"\x80\x80\x80\x80\x80\x00",
    ] {
    match parse_module(parser_fixture(b"\x01" + bytes)) {
      Err(LebOverflow(9)) => ()
      _ => fail("expected invalid encoding at offset 9")
    }
  }
  let cases : Array[(Bytes, UInt)] = [
    (b"\x80\x80\x80\x80\x08", 2147483648),
    (b"\xff\xff\xff\xff\x0f", 4294967295),
  ]
  for (bytes, expected) in cases {
    match parse_module(parser_fixture(b"\x01" + bytes)) {
      Err(ValueOutOfRange(9, value)) => assert_eq(value, expected)
      _ => fail("valid u32 encoding must have a separate range error")
    }
  }
}

///|
test "section length checks subtraction rather than overflowing the file end" {
  assert_input_end(
    parse_module(parser_fixture(b"\x01\xff\xff\xff\xff\x07")),
    14,
    2147483647,
  )
  assert_input_end(parse_module(parser_fixture(b"\x01\x04\x01")), 10, 4)
}

///|
test "outer custom names are structural and cannot borrow from another section" {
  assert_input_end(parse_module(parser_fixture(b"\x00\x00\x00\x01\x00")), 10, 1)
  assert_input_end(
    parse_module(parser_fixture(b"\x00\x01\x80\x00\x01\x00")),
    10,
    1,
  )
  assert_input_end(
    parse_module(parser_fixture(b"\x00\x02\x03a\x00\x01\x00")),
    11,
    3,
  )
}

///|
test "code body lengths cannot wrap or leave their code section" {
  for
    (code, needed) in [
      (b"\x0a\x06\x01\xff\xff\xff\xff\x07", 2147483647),
      (b"\x0a\x03\x01\x03\x00", 3),
    ] {
    let data = parser_fixture(
      b"\x01\x04\x01\x60\x00\x00\x03\x02\x01\x00" + code + b"\x00\x01\x00",
    )
    let parsed = parsed_fixture(data)
    let body_start = if needed == 3 { 22 } else { 26 }
    assert_input_end(
      parse_code_section(data, section_of(parsed, Code)),
      body_start,
      needed,
    )
    assert_input_end(analyze(data, parsed), body_start, needed)
  }
}

///|
test "import strings and descriptors cannot consume the following custom section" {
  // Outside bytes would make the old reader see an empty field name and a
  // complete global descriptor (kind 3, type 0, mutability 0).
  let data = parser_fixture(b"\x02\x03\x01\x01m\x00\x03\x00\x00\x00")
  let parsed = parsed_fixture(data)
  assert_input_end(
    count_imported_functions(data, section_of(parsed, Import)),
    13,
    1,
  )
  assert_input_end(analyze(data, parsed), 13, 1)
}

///|
test "export string length cannot be satisfied by the next section id" {
  let data = parser_fixture(b"\x07\x03\x01\x02x\x00\x03\x00\x00\x00")
  let parsed = parsed_fixture(data)
  assert_input_end(
    parse_export_section(data, section_of(parsed, Export)),
    12,
    2,
  )
  assert_input_end(analyze(data, parsed), 12, 2)
}

///|
test "table minimum and start index readers obey payload bounds" {
  let data = parser_fixture(b"\x04\x03\x01\x70\x00\x00\x01\x00")
  assert_input_end(
    parse_table_section(data, section_of(parsed_fixture(data), Table)),
    13,
    1,
  )
  let start = parser_fixture(b"\x08\x00\x00\x01\x00")
  assert_input_end(
    parse_start_section(start, section_of(parsed_fixture(start), Start)),
    10,
    1,
  )
}

///|
test "element constant expressions cannot decode immediates in another section" {
  let data = parser_fixture(b"\x09\x04\x01\x00\x41\x80\x00\x01\x00")
  let parsed = parsed_fixture(data)
  assert_input_end(
    parse_element_section(data, section_of(parsed, Element)),
    13,
    1,
  )
  assert_input_end(analyze(data, parsed), 13, 1)
}

///|
test "name metadata cannot borrow subsequent subsection bytes or overwrite earlier names" {
  // Optional debug metadata test, not a complete executable-module fixture.
  // First name map is valid; the second has a string with no bytes in its range.
  let data = parser_fixture(
    b"\x00\x13\x04name\x01\x04\x01\x00\x01a\x01\x03\x01\x00\x03\x02\x01\x00",
  )
  let names = parse_name_section(
    data,
    find_sections(parsed_fixture(data)).names.unwrap(),
  ).unwrap()
  assert_eq(names.length(), 1)
  assert_eq(names.get(0), Some("a"))
}

///|
test "name subsection length cannot exceed its parent custom payload" {
  // Preserve the valid prefix and stop at an oversized optional subsection.
  let data = parser_fixture(
    b"\x00\x0d\x04name\x01\x04\x01\x00\x01a\x01\x40\x00\x03\x00\x00\x00",
  )
  let names = parse_name_section(
    data,
    find_sections(parsed_fixture(data)).names.unwrap(),
  ).unwrap()
  assert_eq(names.length(), 1)
  assert_eq(names.get(0), Some("a"))
}

///|
test "bounded instructions cannot finish call indices using the next body prefix" {
  for opcode in [b"\x10", b"\x12", b"\x14", b"\x15"] {
    let data = tail_module([b"\x00" + opcode + b"\x80", b"\x00\x0b"])
    let parsed = parsed_fixture(data)
    // The next body prefix is 02, which could terminate the LEB as 256.
    assert_input_end(analyze(data, parsed), 34, 1)
    assert_input_end(scan_calls(data, 32, 3), 34, 1)
  }
}

///|
test "locals signed immediates and fixed bits share the function body boundary" {
  assert_input_end(decode_instructions(b"\xaa\x80\x00", 1, 1), 1, 1)
  assert_input_end(decode_instructions(b"\xaa\x01\x01\x63\x80\x00", 1, 4), 4, 1)
  assert_input_end(decode_instructions(b"\xaa\x00\x41\x80\x00", 1, 3), 3, 1)
  assert_input_end(
    decode_instructions(b"\xaa\x00\x44\x01\x02\x03\x04\x05\x06\x07\x08", 1, 4),
    3,
    8,
  )
}

///|
test "public instruction APIs reject invalid positions without slicing or seeking" {
  assert_read_range(decode_instruction(b"\x0b", -1), -1, 0, 0, 1)
  assert_read_range(decode_instruction(b"\x0b", 2), 2, 0, 0, 1)
  assert_input_end(decode_instruction(b"\x0b", 1), 1, 1)
  for (offset, length) in [(-1, 1), (0, -1), (1, 2147483647)] {
    assert_read_range(
      decode_instructions(b"\x00\x0b", offset, length),
      offset,
      length,
      0,
      2,
    )
  }
}

///|
test "large counts on short input consume input or return errors promptly" {
  let maximum = b"\xff\xff\xff\xff\x07"
  let imports = parser_fixture(b"\x02\x05" + maximum)
  assert_input_end(analyze(imports, parsed_fixture(imports)), 15, 1)
  let code = parser_fixture(b"\x0a\x05" + maximum)
  assert_input_end(analyze(code, parsed_fixture(code)), 15, 1)
  // br_table and select_t vectors are bounded instruction-reader tests.
  assert_input_end(decode_instructions(b"\x00\x0e" + maximum, 0, 7), 7, 1)
  assert_input_end(decode_instructions(b"\x00\x1c" + maximum, 0, 7), 7, 1)
}

///|
test "function base index addition is checked before constructing a body record" {
  let data = tail_module([b"\x00\x0b", b"\x00\x0b"])
  let section = section_of(parsed_fixture(data), Code)
  match parse_code_section(data, section, base_index=2147483647) {
    Err(ValueOutOfRange(34, value)) => assert_eq(value, 2147483648U)
    _ => fail("expected function index addition range error")
  }
  assert_read_range(
    parse_code_section(data, section, base_index=-1),
    section.offset,
    -1,
    0,
    2147483647,
  )
}

///|
test "length count and instruction indices use the same checked u32 conversion" {
  let large = b"\x80\x80\x80\x80\x08"
  match decode_instruction(b"\x10" + large, 0) {
    Err(ValueOutOfRange(1, value)) => assert_eq(value, 2147483648U)
    _ => fail("expected operand range error")
  }
  let data = parser_fixture(b"\x07\x05" + large)
  match analyze(data, parsed_fixture(data)) {
    Err(ValueOutOfRange(10, value)) => assert_eq(value, 2147483648U)
    _ => fail("expected count range error")
  }
}
