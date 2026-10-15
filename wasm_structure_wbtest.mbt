///|
fn structure_module(sections : Bytes) -> Bytes {
  b"\x00asm\x01\x00\x00\x00" + sections
}

///|
fn structure_ok(sections : Bytes) -> WasmModule raise {
  match parse_module(structure_module(sections)) {
    Ok(parsed) => parsed
    Err(error) => fail(describe_error(error))
  }
}

///|
test "only Core binary version one is accepted before reading sections" {
  assert_eq(structure_ok(b"").version, 1)
  for
    (version, value) in [
      (b"\x00\x00\x00\x00", 0U),
      (b"\x02\x00\x00\x00", 2U),
      (b"\xff\xff\xff\xff", 4294967295U),
    ] {
    // Invalid section id must not hide the earlier unsupported version.
    match parse_module(b"\x00asm" + version + b"\xff") {
      Err(UnsupportedVersion(4, actual)) => assert_eq(actual, value)
      _ => fail("expected unsupported version at its field start")
    }
    assert_eq(
      describe_error(UnsupportedVersion(4, value)),
      "unsupported WebAssembly version " + value.to_string() + " at offset 4",
    )
  }
}

///|
test "standard section duplicates identify the second id byte" {
  for
    (section, kind) in [
      (b"\x01\x01\x00", Type),
      (b"\x0a\x01\x00", Code),
      (b"\x0c\x01\x00", DataCount),
    ] {
    match parse_module(structure_module(section + section)) {
      Err(DuplicateSection(11, actual)) => assert_true(same_kind(actual, kind))
      _ => fail("expected duplicate standard section")
    }
  }
  let prefix = b"\x01\x04\x01\x60\x00\x00\x03\x02\x01\x00"
  match
    parse_module(
      structure_module(
        prefix + b"\x08\x01\x00\x08\x01\x00\x0a\x04\x01\x02\x00\x0b",
      ),
    ) {
    Err(DuplicateSection(21, Start)) => ()
    _ => fail("expected duplicate start section at its second id")
  }
}

///|
test "every standard kind is unique even with custom sections in between" {
  for id = 1; id <= 13; id = id + 1 {
    let kind = match SectionId::from_id(id) {
      Some(kind) => kind
      None => fail("expected standard id")
    }
    let standard = Bytes::from_array([id.to_byte(), b'\x01', b'\x00'])
    match
      parse_module(structure_module(standard + b"\x00\x02\x01x" + standard)) {
      Err(DuplicateSection(15, actual)) => assert_true(same_kind(actual, kind))
      _ => fail("expected duplicate irrespective of custom placement")
    }
  }
}

///|
test "same-name custom sections may repeat and do not affect standard order" {
  let custom = b"\x00\x02\x01x"
  let parsed = structure_ok(
    custom +
    b"\x01\x01\x00" +
    custom +
    b"\x03\x01\x00" +
    custom +
    b"\x0a\x01\x00" +
    custom,
  )
  assert_eq(parsed.sections.length(), 7)
  assert_eq(structure_ok(custom + custom).sections.length(), 2)
  match
    parse_module(structure_module(b"\x03\x01\x00" + custom + b"\x02\x01\x00")) {
    Err(InvalidSectionOrder(15, Import, Function)) => ()
    _ => fail("custom must not reset the standard section order")
  }
}

///|
test "import after function is rejected at the import id" {
  match parse_module(structure_module(b"\x03\x01\x00\x02\x01\x00")) {
    Err(InvalidSectionOrder(11, Import, Function)) => ()
    _ => fail("expected import/function ordering error")
  }
}

///|
test "datacount precedes code despite its larger numeric id" {
  let _ = structure_ok(b"\x0c\x01\x00\x0a\x01\x00")
  match parse_module(structure_module(b"\x0a\x01\x00\x0c\x01\x00")) {
    Err(InvalidSectionOrder(11, DataCount, Code)) => ()
    _ => fail("expected datacount before code")
  }
}

///|
test "tag is ordered between memory and global rather than by id" {
  let _ = structure_ok(
    b"\x01\x04\x01\x60\x00\x00\x05\x01\x00\x0d\x03\x01\x00\x00\x06\x01\x00",
  )
  match parse_module(structure_module(b"\x06\x01\x00\x0d\x01\x00")) {
    Err(InvalidSectionOrder(11, Tag, Global)) => ()
    _ => fail("expected tag/global ordering error")
  }
}

///|
test "missing and explicitly empty function code sections each count as zero" {
  for
    sections in [
      b"", b"\x03\x01\x00", b"\x0a\x01\x00", b"\x03\x01\x00\x0a\x01\x00",
    ] {
    let _ = structure_ok(sections)
  }
}

///|
test "function code mismatch covers missing empty and unequal sections" {
  for
    (sections, offset, kind, declarations, bodies) in [
      (b"\x03\x02\x01\x00", 8, Function, 1, 0),
      (b"\x03\x02\x01\x00\x0a\x01\x00", 12, Code, 1, 0),
      (b"\x0a\x04\x01\x02\x00\x0b", 8, Code, 0, 1),
      (b"\x03\x01\x00\x0a\x04\x01\x02\x00\x0b", 11, Code, 0, 1),
      (b"\x03\x03\x02\x00\x00\x0a\x04\x01\x02\x00\x0b", 13, Code, 2, 1),
    ] {
    match parse_module(structure_module(sections)) {
      Err(FunctionCodeCountMismatch(at, section, declared, actual)) => {
        assert_eq(at, offset)
        assert_true(same_kind(section, kind))
        assert_eq(declared, declarations)
        assert_eq(actual, bodies)
      }
      _ => fail("expected local declaration/body mismatch")
    }
  }
  let _ = structure_ok(
    b"\x03\x03\x02\x00\x00\x0a\x07\x02\x02\x00\x0b\x02\x00\x0b",
  )
}

///|
test "imports do not contribute to the local declaration count" {
  let types_import = b"\x01\x04\x01\x60\x00\x00\x02\x07\x01\x01m\x01f\x00\x00"
  let _ = structure_ok(types_import)
  let data = structure_module(
    types_import + b"\x03\x02\x01\x00\x0a\x04\x01\x02\x00\x0b",
  )
  let parsed = match parse_module(data) {
    Ok(parsed) => parsed
    Err(error) => fail(describe_error(error))
  }
  match analyze(data, parsed) {
    Ok(analysis) => {
      assert_eq(analysis.stats.length(), 1)
      assert_eq(analysis.stats[0].index, 1)
    }
    Err(error) => fail(describe_error(error))
  }
}

///|
test "function declarations consume every type index inside their payload" {
  match parse_module(structure_module(b"\x03\x02\x02\x00")) {
    Err(UnexpectedEnd(12, 1)) => ()
    _ => fail("must read the second declared type index")
  }
  // A valid non-short encoding is still accepted for counts and type indices.
  let _ = structure_ok(b"\x03\x04\x81\x00\x80\x00\x0a\x04\x01\x02\x00\x0b")
}

///|
test "function and code payloads reject the first unconsumed byte" {
  for
    (section, kind) in [
      (b"\x03\x02\x00\x00", Function),
      (b"\x0a\x02\x00\x00", Code),
    ] {
    match parse_module(structure_module(section)) {
      Err(TrailingSectionBytes(11, actual)) =>
        assert_true(same_kind(actual, kind))
      _ => fail("expected first trailing byte position")
    }
  }
  // Count agrees with function declarations; the body itself is truncated.
  match
    parse_module(structure_module(b"\x03\x02\x01\x00\x0a\x03\x01\x03\x00")) {
    Err(UnexpectedEnd(16, 3)) => ()
    _ => fail("matching counts must not skip the body bounds")
  }
}

///|
test "public code parser shares complete payload consumption checks" {
  let data = structure_module(b"\x0a\x02\x00\x00")
  let section = {
    id: 10,
    kind: Code,
    offset: 8,
    payload_size: 2,
    total_size: 4,
    custom_name: None,
  }
  match parse_code_section(data, section) {
    Err(TrailingSectionBytes(11, Code)) => ()
    _ => fail("public code parser must reject trailing bytes too")
  }
}

///|
test "structure error messages include sections positions and both local counts" {
  assert_eq(
    describe_error(DuplicateSection(11, Type)),
    "duplicate type section at offset 11",
  )
  assert_eq(
    describe_error(InvalidSectionOrder(24, Function, Code)),
    "function section appears after code section at offset 24",
  )
  assert_eq(
    describe_error(FunctionCodeCountMismatch(19, Code, 2, 1)),
    "function/code count mismatch: 2 declarations, 1 body (code section at offset 19)",
  )
  assert_eq(
    describe_error(FunctionCodeCountMismatch(19, Code, 1, 2)),
    "function/code count mismatch: 1 declaration, 2 bodies (code section at offset 19)",
  )
  assert_eq(
    describe_error(TrailingSectionBytes(18, Function)),
    "unexpected trailing bytes in function section at offset 18",
  )
}
