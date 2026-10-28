///|
fn module_opcode_diff_test_fixture(current : Bool, second? : Bytes) -> Bytes {
  let header = b"\x00asm\x01\x00\x00\x00\x01\x04\x01\x60\x00\x00\x02\x07\x01\x01m\x01f\x00\x00"
  if current {
    let second = second.unwrap_or(b"\x00\x41\x02\x1a\x0b")
    let payload = b"\x83\x00\x89\x00\x01\x01\x7f\x00\x41\x80\x01\x1a\x0b" +
      Bytes::from_array([second.length().to_byte()]) +
      second +
      b"\x05\x00\x41\x03\x1a\x0b"
    header +
    b"\x03\x04\x03\x00\x00\x00\x0a" +
    Bytes::from_array([(payload.length() | 128).to_byte(), 0]) +
    payload
  } else {
    let second = second.unwrap_or(b"\x00\x41\x01\x1a\x0b")
    header +
    b"\x03\x03\x02\x00\x00" +
    instructions_test_section(
      10,
      b"\x02\x06\x00\x41\x00\x1a\x01\x0b" +
      Bytes::from_array([second.length().to_byte()]) +
      second,
    )
  }
}

///|
fn module_opcode_diff_test_report(
  before : Bytes,
  after : Bytes,
) -> ModuleOpcodeComparison raise {
  match compare_module_opcodes(before, after) {
    Ok(report) => report
    Err(error) => fail(describe_module_opcode_comparison_error(error))
  }
}

///|
test "module-opcode-diff: union, actual widths and complete signed ledgers" {
  let b = module_opcode_diff_test_fixture(false)
  let c = module_opcode_diff_test_fixture(true)
  let r = module_opcode_diff_test_report(b, c)
  assert_eq(r.baseline.file_size, 44)
  assert_eq(r.current.file_size, 57)
  assert_eq(r.baseline.functions.length(), 2)
  assert_eq(r.current.functions.length(), 3)
  assert_eq(r.baseline.sha256, experiment_sha256(b))
  assert_eq(r.current.sha256, experiment_sha256(c))
  let d = r.delta
  assert_eq(d.file_bytes, 13)
  assert_eq(d.code_bytes, 12)
  assert_eq(d.non_code_bytes, 1)
  assert_eq(d.code_header_bytes, 1)
  assert_eq(d.count_encoding_bytes, 1)
  assert_eq(d.body_prefix_bytes, 2)
  assert_eq(d.locals_encoding_bytes, 3)
  assert_eq(d.instruction_bytes, 5)
  assert_eq(d.instruction_count, 3)
  assert_eq(d.imported_function_count, 0)
  assert_eq(d.local_function_count, 1)
  assert_eq(d.file_bytes, d.code_bytes + d.non_code_bytes)
  assert_eq(
    d.code_bytes,
    d.code_header_bytes +
    d.count_encoding_bytes +
    d.body_prefix_bytes +
    d.locals_encoding_bytes +
    d.instruction_bytes,
  )
  assert_eq(r.opcodes.map(fn(g) { g.mnemonic }), [
    "i32.const", "drop", "end", "nop", "unreachable",
  ])
  assert_eq(r.opcodes.map(fn(g) { g.status }), [
    "shared_opcode", "shared_opcode", "shared_opcode", "baseline_only", "current_only",
  ])
  assert_eq(r.opcodes.map(fn(g) { g.count_delta }), [1, 1, 1, -1, 1])
  assert_eq(r.opcodes.map(fn(g) { g.encoded_bytes_delta }), [3, 1, 1, -1, 1])
  assert_eq(r.opcodes.map(fn(g) { g.function_count_delta }), [1, 1, 1, -1, 1])
  let mut count = 0
  let mut bytes = 0
  for row in r.opcodes {
    count += row.count_delta
    bytes += row.encoded_bytes_delta
    assert_eq(row.count_delta, row.current_count - row.baseline_count)
    assert_eq(
      row.encoded_bytes_delta,
      row.current_encoded_bytes - row.baseline_encoded_bytes,
    )
    assert_eq(
      row.function_count_delta,
      row.current_function_count - row.baseline_function_count,
    )
  }
  assert_eq(count, d.instruction_count)
  assert_eq(bytes, d.instruction_bytes)
  // Same mnemonic, count and distribution, but a wider immediate.
  let wide = module_opcode_diff_test_report(
    instructions_test_module(b"\x00\x41\x00\x1a\x0b", b"\x00\x0b"),
    instructions_test_module(b"\x00\x41\x80\x01\x1a\x0b", b"\x00\x0b"),
  )
  assert_eq(wide.opcodes[0].mnemonic, "i32.const")
  assert_eq(wide.opcodes[0].count_delta, 0)
  assert_eq(wide.opcodes[0].encoded_bytes_delta, 1)
  assert_eq(wide.opcodes[0].function_count_delta, 0)
  let reversed = module_opcode_diff_test_report(c, b)
  assert_eq(reversed.delta.code_bytes, -12)
  assert_eq(reversed.delta.instruction_count, -3)
}

///|
test "module-opcode-diff: absent/empty code, zero aggregates and side-specific body failures" {
  let header = b"\x00asm\x01\x00\x00\x00"
  let empty = module_opcode_diff_test_report(
    header,
    header + b"\x0a\x02\x80\x00",
  )
  assert_true(empty.baseline.code_section is None)
  assert_eq(empty.delta.code_bytes, 4)
  assert_eq(empty.delta.code_header_bytes, 2)
  assert_eq(empty.delta.count_encoding_bytes, 2)
  assert_eq(empty.delta.non_code_bytes, 0)
  assert_eq(empty.opcodes.length(), 0)
  assert_true(
    render_module_opcode_comparison(empty, 1).contains(
      "Code delta: 4 = header 2 + count encoding 2",
    ),
  )
  let b = module_opcode_diff_test_fixture(false)
  let self = module_opcode_diff_test_report(b, b)
  assert_eq(self.delta.file_bytes, 0)
  assert_eq(self.delta.instruction_bytes, 0)
  assert_eq(self.opcodes.length(), 4)
  for row in self.opcodes {
    assert_eq(row.status, "shared_opcode")
    assert_eq(row.count_delta, 0)
    assert_eq(row.encoded_bytes_delta, 0)
    assert_eq(row.function_count_delta, 0)
  }
  let changed_constant = module_opcode_diff_test_report(
    instructions_test_module(b"\x00\x41\x00\x1a\x0b", b"\x00\x0b"),
    instructions_test_module(b"\x00\x41\x01\x1a\x0b", b"\x00\x0b"),
  )
  assert_true(
    changed_constant.baseline.sha256 != changed_constant.current.sha256,
  )
  assert_eq(changed_constant.delta.instruction_bytes, 0)
  for row in changed_constant.opcodes {
    assert_eq(row.encoded_bytes_delta, 0)
  }
  assert_true(
    changed_constant.scope.contains(
      "Zero aggregate deltas do not prove equal bytes",
    ),
  )
  let bad = module_opcode_diff_test_fixture(false, second=b"\x00\xff")
  let before_error = compare_module_opcodes(bad, b).unwrap_err()
  let after_error = compare_module_opcodes(b, bad).unwrap_err()
  assert_true(
    before_error is BaselineModuleOpcodeError(ModuleOpcodeBodyError(2, _)),
  )
  assert_true(
    after_error is CurrentModuleOpcodeError(ModuleOpcodeBodyError(2, _)),
  )
  assert_true(
    describe_module_opcode_comparison_error(before_error).contains(
      "baseline: function 2",
    ),
  )
  assert_true(
    describe_module_opcode_comparison_error(after_error).contains(
      "current: function 2",
    ),
  )
  assert_true(
    describe_module_opcode_comparison_error(before_error).contains("40"),
  )
  assert_true(
    compare_module_opcodes(b"bad", b)
    is Err(BaselineModuleOpcodeError(ModuleOpcodeInputError(_))),
  )
  assert_true(
    compare_module_opcodes(b, b"bad")
    is Err(CurrentModuleOpcodeError(ModuleOpcodeInputError(_))),
  )
}

///|
test "module-opcode-diff: parameter routing, full nested JSON and unchanged single format" {
  assert_false(Options::default("x").diff_opcodes)
  let args = [
    "moonsize", "--diff-opcodes", "--opcode-stats", "--baseline", "-before.wasm",
    "--opcode-stats-json", "new.json", "--top", "1", "--", "--help",
  ]
  assert_eq(help_request(args).unwrap(), None)
  let options = parse_options(args).unwrap()
  assert_true(options.opcode_stats && options.diff_opcodes)
  assert_eq(options.baseline, Some("-before.wasm"))
  assert_eq(options.path, "--help")
  assert_eq(options.top, 1)
  for
    flags in [
      ["--diff-opcodes"],
      ["--diff-opcodes", "--baseline", ""],
      ["--diff-opcodes", "--baseline", "--help"],
      ["--opcode-stats", "--baseline", "b"],
      ["--diff-opcodes", "--baseline", "b", "--strict"],
      ["--diff-opcodes", "--baseline", "b", "--instructions", "1"],
      ["--diff-opcodes", "--baseline", "b", "--html", "new.html"],
      ["--diff-opcodes", "--baseline", "b", "--max-size", "100KB"],
      ["--diff-opcodes", "--baseline", "b", "--opcode-stats-json", "bad.txt"],
    ] {
    assert_true(parse_options(["moonsize", "x"] + flags) is Err(_))
  }
  assert_true(help_request(["moonsize", "--help"]).unwrap() is Some(_))
  let r = module_opcode_diff_test_report(
    module_opcode_diff_test_fixture(false),
    module_opcode_diff_test_fixture(true),
  )
  let text = render_module_opcode_comparison(r, 1)
  assert_true(text.contains("showing 1 of 5"))
  assert_true(text.contains("i32.const  shared_opcode"))
  assert_false(text.contains("\ndrop  shared_opcode"))
  assert_true(text.contains("File delta: 13 = code 12 + non-code 1"))
  let json = render_module_opcode_comparison_json(r)
  let fields = match @json.parse(json) {
    Object(fields) => fields
    _ => fail("object expected")
  }
  for key in ["baseline", "current", "delta"] {
    assert_true(fields.get(key) is Some(Object(_)))
  }
  match fields.get("opcodes") {
    Some(Array(rows)) => assert_eq(rows.length(), 5)
    _ => fail("all union rows expected")
  }
  assert_true(json.contains("\"format\": \"moonsize-module-opcodes-diff\""))
  assert_true(json.contains("\"name\": null"))
  assert_false(json.contains("\"matched\""))
  assert_true(
    render_module_opcodes_json(r.baseline).contains(
      "\"format\": \"moonsize-module-opcodes\"",
    ),
  )
  let empty = module_opcode_diff_test_report(
    b"\x00asm\x01\x00\x00\x00", b"\x00asm\x01\x00\x00\x00",
  )
  assert_true(
    render_module_opcode_comparison_json(empty).contains(
      "\"code_section\": null",
    ),
  )
  assert_true(
    render_module_opcode_comparison_json(empty).contains(
      "\"count_encoding\": null",
    ),
  )
}
