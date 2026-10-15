///|
test "public parse_module rejects the reproduced version 2 header" {
  match @moonsize.parse_module(b"\x00asm\x02\x00\x00\x00") {
    Err(@moonsize.WasmError::UnsupportedVersion(4, 2U)) => ()
    Err(error) => fail(@moonsize.describe_error(error))
    Ok(_) => fail("unsupported version must not produce a successful module")
  }
}

///|
test "public parse_module rejects the reproduced duplicate type sections" {
  match
    @moonsize.parse_module(b"\x00asm\x01\x00\x00\x00\x01\x01\x00\x01\x01\x00") {
    Err(@moonsize.WasmError::DuplicateSection(11, @moonsize.SectionId::Type)) =>
      ()
    Err(error) => fail(@moonsize.describe_error(error))
    Ok(_) => fail("duplicate standard sections must not produce a module")
  }
}

///|
test "public analyze revalidates data instead of trusting a stale section table" {
  let parsed = match @moonsize.parse_module(b"\x00asm\x01\x00\x00\x00") {
    Ok(parsed) => parsed
    Err(error) => fail(@moonsize.describe_error(error))
  }
  let bytes = b"\x00asm\x01\x00\x00\x00\x03\x01\x00\x02\x01\x00"
  match @moonsize.analyze(bytes, parsed) {
    Err(
      @moonsize.WasmError::InvalidSectionOrder(
        11,
        @moonsize.SectionId::Import,
        @moonsize.SectionId::Function
      )
    ) => ()
    Err(error) => fail(@moonsize.describe_error(error))
    Ok(_) => fail("stale metadata must not bypass section-order checks")
  }
}

///|
test "public module errors expose local counts and trailing-byte positions" {
  match @moonsize.parse_module(b"\x00asm\x01\x00\x00\x00\x03\x02\x01\x00") {
    Err(
      @moonsize.WasmError::FunctionCodeCountMismatch(
        8,
        @moonsize.SectionId::Function,
        1,
        0
      )
    ) => ()
    _ => fail("missing code must expose its declaration/body mismatch")
  }
  match @moonsize.parse_module(b"\x00asm\x01\x00\x00\x00\x0a\x02\x00\x00") {
    Err(
      @moonsize.WasmError::TrailingSectionBytes(11, @moonsize.SectionId::Code)
    ) => ()
    _ => fail("trailing code bytes must not produce an analysis")
  }
}

///|
test "public analysis accepts repeated custom names and preserves tail-call sizes" {
  let data = direct_tail_fixture() + b"\x00\x02\x01x\x00\x02\x01x"
  let analysis = public_tail_analysis(data)
  assert_eq(analysis.parsed.version, 1)
  assert_true(analysis.graph_complete)
  assert_eq(analysis.stats.length(), 2)
  assert_true(analysis.reachable.contains(1))
  assert_eq(analysis.retained.filter(entry => entry.index == 0)[0].retained, 8)
}

///|
test "public analysis derives canonical sections even when metadata is empty" {
  let empty = match @moonsize.parse_module(b"\x00asm\x01\x00\x00\x00") {
    Ok(parsed) => parsed
    Err(error) => fail(@moonsize.describe_error(error))
  }
  match @moonsize.analyze(direct_tail_fixture(), empty) {
    Ok(analysis) => {
      assert_eq(analysis.stats.length(), 2)
      assert_true(analysis.reachable.contains(1))
      assert_eq(analysis.parsed.file_size, 39)
    }
    Err(error) => fail(@moonsize.describe_error(error))
  }
}
