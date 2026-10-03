///|
/// A module exercising every stage-2 parser at once: an import section holding
/// one function and one memory, a function section of two definitions, a code
/// section of two bodies, and a `name` section that labels all three functions.
///
/// Generated from the spec encoding, so the expected sizes below can be checked
/// by reading the bytes rather than by trusting the decoder.
fn named_module() -> Bytes {
  b"\x00\x61\x73\x6d\x01\x00\x00\x00\x02\x16\x02\x03\x65\x6e\x76\x03\x6c\x6f\x67\x00" +
  b"\x00\x03\x65\x6e\x76\x03\x6d\x65\x6d\x02\x00\x01\x03\x03\x02\x00\x00\x0a\x09\x02" +
  b"\x02\x00\x0b\x04\x00\x41\x00\x0b\x00\x43\x04\x6e\x61\x6d\x65\x01\x37\x03\x00\x07" +
  b"\x65\x6e\x76\x2e\x6c\x6f\x67\x01\x0f\x6d\x6f\x6f\x6e\x62\x69\x74\x2e\x70\x72\x69" +
  b"\x6e\x74\x6c\x6e\x02\x1a\x5f\x4d\x30\x46\x50\x33\x34\x64\x65\x6d\x6f\x36\x73\x61" +
  b"\x6d\x70\x6c\x65\x33\x73\x72\x63\x33\x66\x69\x62\x02\x03\x01\x01\x00"
}

///|
/// A module whose single body is 200 bytes, so its size prefix needs two LEB128
/// groups and cannot be mistaken for a single byte.
fn big_body_module() -> Bytes {
  b"\x00\x61\x73\x6d\x01\x00\x00\x00\x03\x02\x01\x00\x0a\xcb\x01\x01\xc8\x01\x00\x41" +
  b"\x00\x1a\x41\x00\x1a\x41\x00\x1a\x41\x00\x1a\x41\x00\x1a\x41\x00\x1a\x41\x00\x1a" +
  b"\x41\x00\x1a\x41\x00\x1a\x41\x00\x1a\x41\x00\x1a\x41\x00\x1a\x41\x00\x1a\x41\x00" +
  b"\x1a\x41\x00\x1a\x41\x00\x1a\x41\x00\x1a\x41\x00\x1a\x41\x00\x1a\x41\x00\x1a\x41" +
  b"\x00\x1a\x41\x00\x1a\x41\x00\x1a\x41\x00\x1a\x41\x00\x1a\x41\x00\x1a\x41\x00\x1a" +
  b"\x41\x00\x1a\x41\x00\x1a\x41\x00\x1a\x41\x00\x1a\x41\x00\x1a\x41\x00\x1a\x41\x00" +
  b"\x1a\x41\x00\x1a\x41\x00\x1a\x41\x00\x1a\x41\x00\x1a\x41\x00\x1a\x41\x00\x1a\x41" +
  b"\x00\x1a\x41\x00\x1a\x41\x00\x1a\x41\x00\x1a\x41\x00\x1a\x41\x00\x1a\x41\x00\x1a" +
  b"\x41\x00\x1a\x41\x00\x1a\x41\x00\x1a\x41\x00\x1a\x41\x00\x1a\x41\x00\x1a\x41\x00" +
  b"\x1a\x41\x00\x1a\x41\x00\x1a\x41\x00\x1a\x41\x00\x1a\x41\x00\x1a\x41\x00\x1a\x41" +
  b"\x00\x1a\x41\x00\x1a\x41\x00\x1a\x41\x00\x1a\x41\x00\x1a\x41\x00\x1a\x0b"
}

///|
/// The first section of the given kind, or a failure explaining the fixture.
fn section_of(parsed : WasmModule, kind : SectionId) -> Section raise {
  let mut found : Section? = None
  for section in parsed.sections {
    if same_kind(section.kind, kind) {
      found = Some(section)
    }
  }
  match found {
    Some(section) => section
    None => fail("fixture has no " + kind.name() + " section")
  }
}

///|
test "counts function imports and skips the others" {
  match parse_module(named_module()) {
    Ok(parsed) =>
      match
        count_imported_functions(named_module(), section_of(parsed, Import)) {
        // The section holds an `env.log` function and an `env.mem` memory; only
        // the function takes a slot in the function index space.
        Ok(count) => inspect(count, content="1")
        Err(error) => fail(decode_failure(error))
      }
    Err(error) => fail(decode_failure(error))
  }
}

///|
test "decodes one body per function with its size prefix" {
  match parse_module(named_module()) {
    Ok(parsed) =>
      match parse_code_section(named_module(), section_of(parsed, Code)) {
        Ok(bodies) => {
          inspect(bodies.length(), content="2")
          // Without a base index the bodies are numbered from zero.
          inspect(bodies[0].index, content="0")
          inspect(bodies[0].body_size, content="2")
          inspect(bodies[0].total_size, content="3")
          inspect(bodies[1].index, content="1")
          inspect(bodies[1].body_size, content="4")
          inspect(bodies[1].total_size, content="5")
        }
        Err(error) => fail(decode_failure(error))
      }
    Err(error) => fail(decode_failure(error))
  }
}

///|
test "offsets body indices past the imported functions" {
  match parse_module(named_module()) {
    Ok(parsed) =>
      match
        parse_code_section(
          named_module(),
          section_of(parsed, Code),
          base_index=1,
        ) {
        Ok(bodies) => {
          inspect(bodies[0].index, content="1")
          inspect(bodies[1].index, content="2")
        }
        Err(error) => fail(decode_failure(error))
      }
    Err(error) => fail(decode_failure(error))
  }
}

///|
test "measures a body whose size prefix spans two LEB128 bytes" {
  match parse_module(big_body_module()) {
    Ok(parsed) =>
      match parse_code_section(big_body_module(), section_of(parsed, Code)) {
        Ok(bodies) => {
          inspect(bodies.length(), content="1")
          inspect(bodies[0].body_size, content="200")
          inspect(bodies[0].total_size, content="202")
        }
        Err(error) => fail(decode_failure(error))
      }
    Err(error) => fail(decode_failure(error))
  }
}

///|
test "reads the function name map out of the name section" {
  match parse_module(named_module()) {
    Ok(parsed) => {
      let names = parse_name_section(named_module(), section_of(parsed, Custom))
      match names {
        Some(names) => {
          assert_eq(names.get(0), Some("env.log"))
          assert_eq(names.get(1), Some("moonbit.println"))
          assert_eq(names.get(2), Some("_M0FP34demo6sample3src3fib"))
          // Subsection 2 holds local names and must not leak into this map.
          assert_eq(names.get(3), None)
        }
        None => fail("expected a name section")
      }
    }
    Err(error) => fail(decode_failure(error))
  }
}

///|
test "returns no names for a custom section that is not the name section" {
  // A `producers` custom section: a nine-byte name and three payload bytes.
  let data = b"\x00\x61\x73\x6d\x01\x00\x00\x00\x00\x0d\x09producers\x01\x02\x03"
  match parse_module(data) {
    Ok(parsed) => {
      inspect(parsed.sections.length(), content="1")
      assert_true(parse_name_section(data, parsed.sections[0]) is None)
    }
    Err(error) => fail(decode_failure(error))
  }
}

///|
test "reads a name section whose function names subsection is empty" {
  // `name` with a single namemap claiming no entries.
  let data = b"\x00\x61\x73\x6d\x01\x00\x00\x00\x00\x08\x04name\x01\x01\x00"
  match parse_module(data) {
    Ok(parsed) =>
      match parse_name_section(data, parsed.sections[0]) {
        Some(names) => assert_true(names.is_empty())
        None => fail("expected an empty name section, not a rejected one")
      }
    Err(error) => fail(decode_failure(error))
  }
}

///|
test "reports a body that overruns the section payload" {
  // One body declaring five bytes while the payload supplies two.
  let data = b"\x00\x61\x73\x6d\x01\x00\x00\x00\x0a\x04\x01\x05\x00\x0b"
  match parse_module(data) {
    Ok(parsed) =>
      match parse_code_section(data, parsed.sections[0]) {
        Err(WasmError::UnexpectedEnd(_, 5)) => ()
        Ok(_) => fail("expected UnexpectedEnd")
        Err(_) => fail("expected UnexpectedEnd")
      }
    Err(error) => fail(decode_failure(error))
  }
}

///|
test "rejects an import descriptor with an unassigned kind" {
  // `evil`/`thing` imported with kind 9, which the spec does not assign.
  let data = b"\x00\x61\x73\x6d\x01\x00\x00\x00\x02\x0d\x01\x04evil\x05thing\x09"
  match parse_module(data) {
    Ok(parsed) =>
      match count_imported_functions(data, parsed.sections[0]) {
        Err(WasmError::InvalidImportKind(9)) => ()
        Ok(_) => fail("expected InvalidImportKind")
        Err(_) => fail("expected InvalidImportKind")
      }
    Err(error) => fail(decode_failure(error))
  }
}
