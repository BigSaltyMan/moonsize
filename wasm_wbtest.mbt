///|
/// A hand-assembled module: preamble, type section, function section and code
/// section, so the expected sizes can be checked by reading the spec.
fn minimal_module() -> Bytes {
  b"\x00\x61\x73\x6d\x01\x00\x00\x00\x01\x04\x01\x60\x00\x00\x03\x02\x01\x00\x0a\x04\x01\x02\x00\x0b"
}

///|
/// Turn a decode failure into a message a failing test can print.
fn decode_failure(error : WasmError) -> String {
  "unexpected decode error: " + describe_error(error)
}

///|
test "parses a minimal module section table" {
  match parse_module(minimal_module()) {
    Ok(parsed) => {
      inspect(parsed.version, content="1")
      inspect(parsed.file_size, content="24")
      inspect(parsed.sections.length(), content="3")
      inspect(parsed.sections[0].kind.name(), content="type")
      inspect(parsed.sections[0].payload_size, content="4")
      inspect(parsed.sections[0].total_size, content="6")
      inspect(parsed.sections[1].kind.name(), content="function")
      inspect(parsed.sections[2].kind.name(), content="code")
      inspect(parsed.sections[2].payload_size, content="4")
    }
    Err(error) => fail(decode_failure(error))
  }
}

///|
test "rejects input without the wasm magic number" {
  match parse_module(b"not a wasm module at all") {
    Err(WasmError::BadMagic) => ()
    Ok(_) => fail("expected BadMagic")
    Err(_) => fail("expected BadMagic")
  }
}

///|
test "rejects a truncated preamble" {
  match parse_module(b"\x00\x61\x73") {
    Err(WasmError::UnexpectedEnd(0, 8)) => ()
    Ok(_) => fail("expected UnexpectedEnd")
    Err(_) => fail("expected UnexpectedEnd")
  }
}

///|
test "reads custom section names alongside their size" {
  // id 0, payload 8: name length 4, "meta", then three payload bytes.
  let data = b"\x00\x61\x73\x6d\x01\x00\x00\x00\x00\x08\x04meta\x01\x02\x03"
  match parse_module(data) {
    Ok(parsed) => {
      inspect(parsed.sections.length(), content="1")
      inspect(parsed.sections[0].kind.name(), content="custom")
      inspect(parsed.sections[0].payload_size, content="8")
      inspect(parsed.sections[0].total_size, content="10")
      assert_eq(parsed.sections[0].custom_name, Some("meta"))
    }
    Err(error) => fail(decode_failure(error))
  }
}

///|
test "decodes a multi-byte LEB128 section size" {
  // 200 encodes as 0xc8 0x01, so this size field occupies two bytes.
  let reader = Reader::new(b"\xc8\x01")
  match reader.read_u32_leb() {
    Ok(value) => inspect(value, content="200")
    Err(_) => fail("expected a decodable LEB128 value")
  }
  inspect(reader.position(), content="2")
}

///|
test "rejects an unterminated LEB128" {
  let reader = Reader::new(b"\x80\x80\x80\x80\x80\x80")
  match reader.read_u32_leb() {
    Err(WasmError::LebOverflow(_)) => ()
    Ok(_) => fail("expected LebOverflow")
    Err(_) => fail("expected LebOverflow")
  }
}

///|
test "reports a section whose payload runs past the end of the file" {
  // Declares a 9-byte data section but supplies only three payload bytes.
  let data = b"\x00\x61\x73\x6d\x01\x00\x00\x00\x0b\x09\x01\x02\x03"
  match parse_module(data) {
    Err(WasmError::UnexpectedEnd(10, 9)) => ()
    Ok(_) => fail("expected UnexpectedEnd")
    Err(_) => fail("expected UnexpectedEnd")
  }
}
