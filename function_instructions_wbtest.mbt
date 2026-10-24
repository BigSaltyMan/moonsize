///|
fn instructions_test_section(id : Int, payload : Bytes) -> Bytes {
  Bytes::from_array([id.to_byte(), payload.length().to_byte()]) + payload
}

///|
fn instructions_test_module(
  first : Bytes,
  second : Bytes,
  named? : Bool = false,
) -> Bytes {
  let code = b"\x02" +
    Bytes::from_array([(first.length() | 128).to_byte(), 0]) +
    first +
    Bytes::from_array([second.length().to_byte()]) +
    second
  let base = b"\x00asm\x01\x00\x00\x00\x01\x04\x01\x60\x00\x00\x02\x07\x01\x01m\x01f\x00\x00\x03\x03\x02\x00\x00" +
    instructions_test_section(10, code)
  if named {
    base +
    instructions_test_section(
      0,
      b"\x04name" + instructions_test_section(1, b"\x01\x01\x09target\"<&"),
    )
  } else {
    base
  }
}

///|
fn instructions_test_body() -> Bytes {
  b"\x01\x02\x7f\x02\x40\x03\x40\x41\x00\x1a\x41\x80\x01\x1a\x43\x00\x00\x00\x00\xfc\x00\x1a\x43\x00\x00\x00\x00\xfc\x01\x1a\x0b\x0b\x0b"
}

///|
fn instructions_test_report(
  data : Bytes,
  index : Int,
) -> FunctionInstructionsReport raise {
  match inspect_function_instructions(data, index) {
    Ok(value) => value
    Err(error) => fail(describe_function_instructions_error(error))
  }
}

///|
test "function-instructions: nonempty locals, nested control, immediate widths and extension groups close byte ledger" {
  let data = instructions_test_module(
    instructions_test_body(),
    b"\x00\x0b",
    named=true,
  )
  let r = instructions_test_report(data, 1)
  assert_eq(r.index, 1)
  assert_eq(r.raw_name, Some("target\"<&"))
  assert_eq(r.name, "target\"<&")
  assert_eq(r.entry.file_offset, 31)
  assert_eq(r.entry.size, 35)
  assert_eq(r.prefix.size, 2)
  assert_eq(r.body.file_offset, 33)
  assert_eq(r.body.size, 33)
  assert_eq(r.locals_encoding.size, 3)
  assert_eq(r.instruction_bytes, 30)
  assert_eq(r.instruction_count, 15)
  assert_eq(r.instructions.map(fn(i) { i.encoded_size }), [
    2, 2, 2, 1, 3, 1, 5, 2, 1, 5, 2, 1, 1, 1, 1,
  ])
  assert_eq(r.instructions.map(fn(i) { i.mnemonic }), [
    "block", "loop", "i32.const", "drop", "i32.const", "drop", "f32.const", "i32.trunc_sat_f32_s",
    "drop", "f32.const", "i32.trunc_sat_f32_u", "drop", "end", "end", "end",
  ])
  let mut cursor = r.body.file_offset + r.locals_encoding.size
  let mut bytes = 0
  for ordinal, i in r.instructions {
    assert_eq(i.ordinal, ordinal)
    assert_eq(i.file_offset, cursor)
    assert_eq(i.body_relative_offset, cursor - r.body.file_offset)
    cursor += i.encoded_size
    bytes += i.encoded_size
  }
  assert_eq(cursor, r.body.file_offset + r.body.size)
  assert_eq(bytes, r.instruction_bytes)
  let mut group_bytes = 0
  let mut group_count = 0
  for group in r.groups {
    group_bytes += group.encoded_bytes
    group_count += group.count
  }
  assert_eq(group_bytes, bytes)
  assert_eq(group_count, r.instruction_count)
  assert_eq(r.entry.size, r.prefix.size + r.body.size)
  assert_eq(r.body.size, r.locals_encoding.size + bytes)
  assert_eq(r.groups.map(fn(g) { g.mnemonic }), [
    "f32.const", "i32.const", "drop", "end", "block", "i32.trunc_sat_f32_s", "i32.trunc_sat_f32_u",
    "loop",
  ])
  assert_eq(r.sha256, experiment_sha256(data))
}

///|
test "function-instructions: full indices, unnamed minimal body, target errors, Top and complete JSON, CLI grammar" {
  let data = instructions_test_module(instructions_test_body(), b"\x00\x0b")
  let minimal = instructions_test_report(data, 2)
  assert_eq(minimal.raw_name, None)
  assert_eq(minimal.name, UNNAMED_FUNCTION)
  assert_eq(minimal.body.size, 2)
  assert_eq(minimal.locals_encoding.size, 1)
  assert_eq(minimal.instruction_count, 1)
  assert_eq(minimal.instructions[0].mnemonic, "end")
  assert_eq(minimal.instructions[0].body_relative_offset, 1)
  assert_true(
    inspect_function_instructions(data, 0) is Err(ImportedInstructionsTarget(0)),
  )
  assert_true(
    inspect_function_instructions(data, -1)
    is Err(InvalidInstructionsTarget(-1, 3)),
  )
  assert_true(
    inspect_function_instructions(data, 3)
    is Err(InvalidInstructionsTarget(3, 3)),
  )
  let report = instructions_test_report(data, 1)
  let text = render_function_instructions(report, 1)
  assert_true(text.contains("OPCODE GROUPS: showing 1 of 8"))
  assert_true(text.contains("INSTRUCTIONS: showing 1 of 15"))
  assert_true(!text.contains("i32.trunc_sat_f32_s  1  2"))
  let json = render_function_instructions_json(report)
  assert_true(json.contains("moonsize-function-instructions"))
  assert_true(json.contains("i32.trunc_sat_f32_s"))
  assert_true(json.contains("i32.trunc_sat_f32_u"))
  assert_true(json.contains("\"ordinal\": 14"))
  assert_true(!json.contains("graph_complete"))
  assert_true(!json.contains("operands"))
  let escaped = render_function_instructions_json(
    instructions_test_report(
      instructions_test_module(b"\x00\x0b", b"\x00\x0b", named=true),
      1,
    ),
  )
  assert_true(escaped.contains("target\\\"<&"))
  assert_eq(Options::default("x").instructions_index, None)
  assert_eq(Options::default("x").instructions_json, None)
  match
    parse_options([
      "moonsize", "missing.wasm", "--instructions", "2147483647", "--instructions-json",
      "new.json", "--top", "1",
    ]) {
    Ok(options) => {
      assert_eq(options.instructions_index, Some(2147483647))
      assert_eq(options.top, 1)
    }
    Err(error) => fail(error)
  }
  for
    args in [
      ["--instructions"],
      ["--instructions", "-1"],
      ["--instructions", "2147483648"],
      ["--instructions", "a"],
      ["--instructions-json", "new.json"],
      ["--instructions", "1", "--instructions-json", "new.txt"],
      ["--instructions", "1", "--strict"],
      ["--instructions", "1", "--baseline", "old.wasm"],
      ["--instructions", "1", "--generics"],
      ["--instructions", "1", "--data-duplicates"],
      ["--instructions", "1", "--budget-json", "budget.json"],
      ["--instructions", "1", "--html", "new.html"],
    ] {
    assert_true(parse_options(["moonsize", "missing.wasm"] + args) is Err(_))
  }
}

///|
test "function-instructions: target decoding errors stay bounded and other function opcodes are not decoded" {
  for body in [b"\x00\xff", b"\x00\x41\x80", b"\x00\xfc"] {
    let data = instructions_test_module(body, b"\x00\x0b")
    let error = match inspect_function_instructions(data, 1) {
      Err(InstructionsInputError(error)) => error
      _ => fail("expected original bounded decoder error")
    }
    let message = describe_error(error)
    assert_true(!message.is_empty())
    let stat = collect_function_stats(parse_module(data).unwrap(), data).unwrap()[0]
    let decoded = decode_instructions(data, stat.offset + 2, stat.body_size)
    match decoded {
      Err(original) => assert_eq(describe_error(original), message)
      _ => fail("decoder unexpectedly accepted malformed target")
    }
    assert_eq(instructions_test_report(data, 2).instruction_count, 1)
  }
  let data = instructions_test_module(b"\x00\x0b", b"\x00\xff")
  assert_eq(instructions_test_report(data, 1).instructions[0].mnemonic, "end")
  assert_true(
    inspect_function_instructions(b"bad", 0) is Err(InstructionsInputError(_)),
  )
  // Decoder exhaustion without an instruction is accounted, not certified valid.
  let exhausted = instructions_test_report(
    instructions_test_module(b"\x00", b"\x00\x0b"),
    1,
  )
  assert_eq(exhausted.locals_encoding.size, 1)
  assert_eq(exhausted.instruction_bytes, 0)
  assert_eq(exhausted.instruction_count, 0)
}
