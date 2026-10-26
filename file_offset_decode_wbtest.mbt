///|
fn file_offset_decode_test_report(
  data : Bytes,
  offset : Int,
) -> FileOffsetDecodedReport raise {
  match locate_file_offset_decoded(data, offset) {
    Ok(value) => value
    Err(error) => fail(describe_file_offset_decode_error(error))
  }
}

///|
test "file-offset-decode: known locals, whole instruction and immediate boundaries" {
  let data = instructions_test_module(instructions_test_body(), b"\x00\x0b")
  for
    (query, kind, start, size, relative, ordinal, mnemonic) in [
      (33, LocalsEncoding, 33, 3, 0, None, None),
      (35, LocalsEncoding, 33, 3, 2, None, None),
      (36, Instruction, 36, 2, 0, Some(0), Some("block")),
      (37, Instruction, 36, 2, 1, Some(0), Some("block")),
      (42, Instruction, 42, 1, 0, Some(3), Some("drop")),
      (43, Instruction, 43, 3, 0, Some(4), Some("i32.const")),
      (44, Instruction, 43, 3, 1, Some(4), Some("i32.const")),
      (45, Instruction, 43, 3, 2, Some(4), Some("i32.const")),
      (46, Instruction, 46, 1, 0, Some(5), Some("drop")),
      (52, Instruction, 52, 2, 0, Some(7), Some("i32.trunc_sat_f32_s")),
      (53, Instruction, 52, 2, 1, Some(7), Some("i32.trunc_sat_f32_s")),
      (65, Instruction, 65, 1, 0, Some(14), Some("end")),
    ] {
    let report = file_offset_decode_test_report(data, query)
    assert_eq(report.decode_status, Decoded)
    assert_eq(report.location.region.kind, FunctionBodyBytes)
    assert_eq(report.location.region.file_offset, 33)
    assert_eq(report.location.region.size, 33)
    assert_eq(report.location.function.unwrap().index, 1)
    assert_eq(report.location.function.unwrap().offset, 31)
    assert_eq(report.location.function.unwrap().total_size, 35)
    let detail = report.detail.unwrap()
    assert_eq(detail.kind, kind)
    assert_eq(detail.file_offset, start)
    assert_eq(detail.size, size)
    assert_eq(detail.relative_offset, relative)
    assert_eq(detail.relative_offset, query - start)
    assert_true(start <= query && query < start + size)
    assert_eq(detail.instruction.map(fn(i) { i.ordinal }), ordinal)
    assert_eq(detail.instruction.map(fn(i) { i.mnemonic }), mnemonic)
    if detail.instruction is Some(instruction) {
      assert_eq(instruction.file_offset, start)
      assert_eq(instruction.encoded_size, size)
      assert_eq(instruction.body_relative_offset, start - 33)
    }
  }
  // Independent fixture ledger, no boundary discovery from the tested locator.
  let decoded = inspect_function_instructions(data, 1).unwrap()
  assert_eq(decoded.locals_encoding.size, 3)
  let mut instruction_bytes = 0
  for instruction in decoded.instructions {
    instruction_bytes += instruction.encoded_size
  }
  assert_eq(instruction_bytes, 30)
  assert_eq(decoded.body.size, decoded.locals_encoding.size + instruction_bytes)
}

///|
test "file-offset-decode: not-applicable ranges, full target failure and selective decoding" {
  let data = instructions_test_module(instructions_test_body(), b"\x00\x0b")
  for offset in [0, 28, 30, 31, 32] {
    let report = file_offset_decode_test_report(data, offset)
    assert_eq(report.decode_status, NotApplicable)
    assert_true(report.detail is None)
    assert_true(
      render_file_offset_decoded(report).contains(
        "no function was instruction-decoded",
      ),
    )
    assert_true(
      render_file_offset_decoded_json(report).contains("\"detail\": null"),
    )
  }
  assert_eq(
    file_offset_decode_test_report(file_offset_test_fixture(), 66).decode_status,
    NotApplicable,
  )
  let bad = instructions_test_module(b"\x00\xff", b"\x00\x0b")
  assert_eq(locate_file_offset(bad, 33).unwrap().region.kind, FunctionBodyBytes)
  assert_true(
    locate_file_offset_decoded(bad, 33)
    is Err(FileOffsetDecodeInstructionsError(_)),
  )
  assert_true(
    locate_file_offset_decoded(bad, 34)
    is Err(FileOffsetDecodeInstructionsError(_)),
  )
  assert_eq(
    file_offset_decode_test_report(bad, 31).decode_status,
    NotApplicable,
  )
  let truncated = instructions_test_module(b"\x00\x41\x80", b"\x00\x0b")
  assert_true(
    locate_file_offset_decoded(truncated, 33)
    is Err(FileOffsetDecodeInstructionsError(_)),
  )
  let other_bad = instructions_test_module(
    instructions_test_body(),
    b"\x00\xff",
  )
  assert_eq(
    file_offset_decode_test_report(other_bad, 44).decode_status,
    Decoded,
  )
  assert_true(
    locate_file_offset_decoded(data, data.length())
    is Err(FileOffsetDecodeLocationError(FileOffsetOutOfRange(_, _))),
  )
  assert_true(
    file_offset_decode_detail(
      locate_file_offset(data, 44).unwrap(),
      inspect_function_instructions(other_bad, 1).unwrap(),
    )
    is Err(InconsistentFileOffsetDecode(_, _)),
  )
  let report = file_offset_decode_test_report(data, 44)
  let root = match @json.parse(render_file_offset_decoded_json(report)) {
    Object(fields) => fields
    _ => fail("expected decoded object")
  }
  assert_eq(
    root.get("location"),
    Some(@json.parse(render_file_offset_json(report.location))),
  )
  assert_eq(root.get("decode_status"), Some(Json::string("decoded")))
  let base = match @json.parse(render_file_offset_json(report.location)) {
    Object(fields) => fields
    _ => fail("expected base object")
  }
  assert_eq(base.get("format"), Some(Json::string("moonsize-file-offset")))
  assert_eq(base.get("decode_status"), None)
  for
    error in [
      FileOffsetDecodeLocationError(FileOffsetOutOfRange(8, 8)),
      FileOffsetDecodeInstructionsError(InstructionsInputError(BadMagic)),
      InconsistentFileOffsetDecode(1, "identity mismatch"),
    ] {
    assert_true(!describe_file_offset_decode_error(error).is_empty())
  }
}

///|
test "file-offset-decode: opt-in CLI contract and three render states" {
  assert_false(Options::default("x").locate_decode)
  assert_false(
    parse_options(["moonsize", "x", "--locate-offset", "44"]).unwrap().locate_decode,
  )
  let args = [
    "moonsize", "--locate-decode", "--locate-offset", "34", "--locate-offset-json",
    "new.json", "--", "--help",
  ]
  assert_true(help_request(args) is Ok(None))
  let options = parse_options(args).unwrap()
  assert_eq(options.path, "--help")
  assert_true(options.locate_decode)
  assert_eq(options.locate_offset, Some(34))
  assert_eq(options.locate_offset_json, Some("new.json"))
  for
    args in [
      ["--locate-decode"],
      ["--locate-decode", "--instructions", "1"],
      ["--locate-offset", "34", "--locate-decode", "--top", "10"],
      ["--locate-offset", "34", "--locate-decode", "--strict"],
      ["--locate-offset", "34", "--locate-decode", "--baseline", "b"],
      ["--locate-offset", "34", "--locate-decode", "--data-preview", "1"],
      ["--locate-offset", "34", "--locate-decode", "--html", "n.html"],
      [
        "--locate-offset", "34", "--locate-decode", "--locate-offset-json", "bad.txt",
      ],
    ] {
    assert_true(parse_options(["moonsize", "missing.wasm"] + args) is Err(_))
  }
  assert_true(help_request(["moonsize", "--help"]) is Ok(Some(_)))
  assert_true(
    parse_options([
      "moonsize", "--locate-offset", "34", "--", "x", "--locate-decode",
    ])
    is Err(_),
  )
  let name = "target\n\u001b\u0085雪"
  let bytes = @utf8.encode(name)
  let data = instructions_test_module(instructions_test_body(), b"\x00\x0b") +
    instructions_test_section(
      0,
      b"\x04name" +
      instructions_test_section(
        1,
        b"\x01\x01" + search_test_leb(bytes.length()) + bytes,
      ),
    )
  let locals_report = file_offset_decode_test_report(data, 34)
  let locals_text = render_file_offset_decoded(locals_report)
  assert_true(locals_text.contains("DECODED FUNCTION LOCATION"))
  assert_true(locals_text.contains("Detail: locals_encoding"))
  assert_true(!locals_text.contains("Instruction ordinal:"))
  assert_true(locals_text.contains(search_terminal_string(name)))
  assert_true(!locals_text.contains(name))
  let json = match @json.parse(render_file_offset_decoded_json(locals_report)) {
    Object(fields) => fields
    _ => fail("expected JSON object")
  }
  assert_eq(
    json.get("format"),
    Some(Json::string("moonsize-file-offset-decoded")),
  )
  match json.get("detail") {
    Some(Object(detail)) => {
      assert_eq(detail.get("kind"), Some(Json::string("locals_encoding")))
      assert_eq(detail.get("instruction"), Some(Json::null()))
      assert_eq(detail.get("file_offset"), Some(int_json(33)))
      assert_eq(detail.get("relative_offset"), Some(int_json(1)))
    }
    _ => fail("expected locals detail object")
  }
  let instruction = render_file_offset_decoded(
    file_offset_decode_test_report(data, 45),
  )
  assert_true(instruction.contains("Detail: instruction"))
  assert_true(
    instruction.contains("Instruction ordinal: 4; mnemonic: \"i32.const\""),
  )
  assert_true(instruction.contains("Body-relative offset: 10 bytes"))
  assert_true(instruction.contains("Detail relative offset: 2 bytes"))
  assert_true(
    !render_file_offset_decoded_json(locals_report).contains("\"byte_role\""),
  )
}
