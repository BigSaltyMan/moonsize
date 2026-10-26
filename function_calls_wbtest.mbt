///|
fn function_calls_test_body() -> Bytes {
  // locals; unreachable; call; ref.func/drop; repeated/import/local calls;
  // two table calls; two reference calls; direct tail call; end.
  b"\x00\x00\x10\x00\xd2\x00\x1a\x10\x00\x10\x02\x11\x00\x00\x13\x00\x00\x14\x00\x15\x00\x12\x00\x0b"
}

///|
fn function_calls_test_module(first : Bytes, second : Bytes) -> Bytes {
  let base = instructions_test_module(first, second, named=true)
  // Add one table and an element declaration for ref.func 0 before code.
  base[0:28].to_owned() +
  b"\x04\x04\x01\x70\x00\x01\x09\x07\x01\x00\x41\x00\x0b\x01\x00" +
  base[28:].to_owned()
}

///|
fn function_calls_test_report(
  data : Bytes,
  index : Int,
) -> FunctionCallsReport raise {
  match inspect_function_calls(data, index) {
    Ok(value) => value
    Err(error) => fail(describe_function_calls_error(error))
  }
}

///|
test "function-calls: six opcodes, repeated sites, complete ordinals and byte ledgers" {
  let data = function_calls_test_module(function_calls_test_body(), b"\x00\x0b")
  let report = function_calls_test_report(data, 1)
  assert_eq(report.caller.index, 1)
  assert_false(report.caller.imported)
  assert_eq(report.caller.encoded_size, Some(26))
  assert_eq(report.body.file_offset, 48)
  assert_eq(report.body.size, 24)
  assert_eq(report.prefix.size, 2)
  assert_eq(report.locals_encoding.size, 1)
  assert_eq(report.instruction_count, 12)
  assert_eq(report.instruction_bytes, 23)
  assert_eq(report.call_count, 8)
  assert_eq(report.direct_count, 4)
  assert_eq(report.indirect_count, 2)
  assert_eq(report.reference_call_count, 2)
  assert_eq(report.tail_count, 3)
  assert_eq(report.call_encoding_bytes, 18)
  assert_eq(report.other_instruction_bytes, 5)
  assert_eq(report.entry.size, report.prefix.size + report.body.size)
  assert_eq(
    report.body.size,
    report.locals_encoding.size + report.instruction_bytes,
  )
  assert_eq(
    report.call_count,
    report.direct_count + report.indirect_count + report.reference_call_count,
  )
  assert_eq(
    report.instruction_bytes,
    report.call_encoding_bytes + report.other_instruction_bytes,
  )
  assert_eq(report.calls.map(fn(c) { c.instruction_ordinal }), [
    1, 4, 5, 6, 7, 8, 9, 10,
  ])
  assert_eq(report.calls.map(fn(c) { c.opcode.name() }), [
    "call", "call", "call", "call_indirect", "return_call_indirect", "call_ref",
    "return_call_ref", "return_call",
  ])
  assert_eq(report.calls.map(fn(c) { c.file_offset }), [
    50, 55, 57, 59, 62, 65, 67, 69,
  ])
  assert_eq(report.calls.map(fn(c) { c.encoded_size }), [2, 2, 2, 3, 3, 2, 2, 2])
  assert_eq(report.calls.map(fn(c) { c.is_tail }), [
    false, false, false, false, true, false, true, true,
  ])
  assert_eq(report.calls.map(fn(c) { c.target_index }), [
    Some(0),
    Some(0),
    Some(2),
    None,
    None,
    None,
    None,
    Some(0),
  ])
  for call in report.calls {
    assert_eq(call.body_relative_offset, call.file_offset - 48)
    assert_true(
      call.file_offset >= 49 && call.file_offset + call.encoded_size <= 72,
    )
    match call.kind {
      DirectCall => {
        assert_eq(call.type_index, None)
        assert_eq(call.table_index, None)
        let target = call.target.unwrap()
        assert_eq(Some(target.index), call.target_index)
        if target.index == 0 {
          assert_true(target.imported)
          assert_eq(target.encoded_size, None)
          assert_eq(target.import_module, Some("m"))
          assert_eq(target.import_name, Some("f"))
        } else {
          assert_false(target.imported)
          assert_eq(target.encoded_size, Some(3))
        }
      }
      IndirectCall => {
        assert_true(call.target is None)
        assert_eq(call.type_index, Some(0))
        assert_eq(call.table_index, Some(0))
      }
      ReferenceCall => {
        assert_true(call.target is None)
        assert_eq(call.type_index, Some(0))
        assert_eq(call.table_index, None)
      }
    }
  }
  assert_eq(data[52], 0xd2)
  assert_eq(report.calls.filter(fn(c) { c.file_offset == 52 }).length(), 0)
  assert_eq(report.sha256, experiment_sha256(data))
  assert_true(
    render_function_calls(report, 1).contains("CALLS: showing 1 of 8"),
  )
  assert_true(!render_function_calls(report, 1).contains("\n4  call"))
  let fields = match @json.parse(render_function_calls_json(report)) {
    Object(fields) => fields
    _ => fail("expected JSON object")
  }
  match fields.get("calls") {
    Some(Array(calls)) => assert_eq(calls.length(), 8)
    _ => fail("expected complete calls array")
  }
  assert_eq(fields.get("graph_complete"), None)
  assert_eq(fields.get("unresolved_count"), None)
}

///|
test "function-calls: selective decoding, empty local body, targets and complete failure" {
  let data = function_calls_test_module(function_calls_test_body(), b"\x00\x0b")
  let empty = function_calls_test_report(data, 2)
  assert_eq(empty.call_count, 0)
  assert_eq(empty.caller.encoded_size, Some(3))
  assert_eq(empty.instruction_count, 1)
  assert_eq(empty.other_instruction_bytes, 1)
  assert_true(
    render_function_calls(empty, 1).contains(
      "No call instructions in this local function.",
    ),
  )
  assert_true(inspect_function_calls(data, 0) is Err(ImportedCallsTarget(0)))
  for index in [-1, 3, 2147483647] {
    assert_true(
      inspect_function_calls(data, index) is Err(InvalidCallsTarget(_, 3)),
    )
  }
  let bad_target = function_calls_test_module(b"\x00\x10\x63\x0b", b"\x00\x0b")
  match inspect_function_calls(bad_target, 1) {
    Err(InvalidCallsEvidence(Some(49), reason)) =>
      assert_true(reason.contains("index 99"))
    _ => fail("expected direct target error at the call instruction")
  }
  for first in [b"\x00\x10\x00\xff", b"\x00\x10\x80"] {
    assert_true(
      inspect_function_calls(function_calls_test_module(first, b"\x00\x0b"), 1)
      is Err(CallsInputError(_)),
    )
  }
  let other_bad = function_calls_test_module(
    function_calls_test_body(),
    b"\x00\xff",
  )
  assert_eq(function_calls_test_report(other_bad, 1).call_count, 8)
  let dynamic = function_calls_test_report(
    function_calls_test_module(b"\x00\x11\x07\x09\x15\x06\x0b", b"\x00\x0b"),
    1,
  )
  assert_eq(dynamic.call_count, 2)
  assert_eq(dynamic.calls[0].type_index, Some(7))
  assert_eq(dynamic.calls[0].table_index, Some(9))
  assert_eq(dynamic.calls[1].type_index, Some(6))
  for call in dynamic.calls {
    assert_true(call.target is None && call.target_index is None)
  }
  assert_true(inspect_function_calls(b"bad", 1) is Err(CallsInputError(_)))
  for
    error in [
      CallsInputError(BadMagic),
      InvalidCallsTarget(9, 3),
      ImportedCallsTarget(0),
      InvalidCallsEvidence(None, "missing range"),
    ] {
    assert_true(!describe_function_calls_error(error).is_empty())
  }
}

///|
test "function-calls: independent CLI grammar, terminal escaping and full JSON" {
  assert_eq(Options::default("x").calls_index, None)
  assert_eq(Options::default("x").calls_json, None)
  let args = [
    "moonsize", "--calls", "1", "--calls-json", "new.json", "--top", "1", "--", "--help",
  ]
  assert_true(help_request(args) is Ok(None))
  let options = parse_options(args).unwrap()
  assert_eq(options.path, "--help")
  assert_eq(options.calls_index, Some(1))
  assert_eq(options.calls_json, Some("new.json"))
  assert_eq(options.top, 1)
  assert_eq(
    parse_options(["moonsize", "x", "--calls", "2147483647"]).unwrap().calls_index,
    Some(2147483647),
  )
  for
    args in [
      ["--calls-json", "new.json"],
      ["--calls"],
      ["--calls", "-1"],
      ["--calls", "2147483648"],
      ["--calls", "0x10"],
      ["--calls", "1.5"],
      ["--calls", "1", "--calls-json"],
      ["--calls", "1", "--calls-json", "bad.txt"],
      ["--calls", "1", "--strict"],
      ["--calls", "1", "--callers", "0"],
      ["--calls", "1", "--instructions", "1"],
      ["--calls", "1", "--locate-offset", "31"],
      ["--calls", "1", "--locate-decode"],
      ["--calls", "1", "--data-preview", "0"],
      ["--calls", "1", "--find-data", "a"],
      ["--calls", "1", "--baseline", "b"],
      ["--calls", "1", "--budget", "b.json"],
      ["--calls", "1", "--html", "n.html"],
    ] {
    assert_true(parse_options(["moonsize", "missing.wasm"] + args) is Err(_))
  }
  assert_true(help_request(["moonsize", "--help"]) is Ok(Some(_)))
  assert_true(
    parse_options(["moonsize", "--calls", "1", "--", "x", "--top", "1"])
    is Err(_),
  )
  let name = "host\n\u001b\u0085雪"
  let bytes = @utf8.encode(name)
  let data = function_calls_test_module(function_calls_test_body(), b"\x00\x0b") +
    instructions_test_section(
      0,
      b"\x04name" +
      instructions_test_section(
        1,
        b"\x01\x00" + search_test_leb(bytes.length()) + bytes,
      ),
    )
  let report = function_calls_test_report(data, 1)
  let text = render_function_calls(report, 8)
  assert_true(text.contains(search_terminal_string(name)))
  assert_true(!text.contains(name))
  assert_true(text.contains("unknown"))
  assert_true(text.contains("\n1  call") && text.contains("\n4  call"))
  let json = render_function_calls_json(report)
  assert_true(json.contains("\"target_index\": null"))
  assert_true(json.contains("\"target\": null"))
  assert_true(json.contains("\"encoded_size\": null"))
  assert_true(json.contains("\"kind\": \"reference_call\""))
}
