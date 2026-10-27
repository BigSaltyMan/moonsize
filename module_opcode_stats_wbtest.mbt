///|
fn module_opcodes_test_second() -> Bytes {
  b"\x00\x41\x01\x1a\x41\x80\x01\x1a\x0b"
}

///|
fn module_opcodes_test_module(second : Bytes, named? : Bool = false) -> Bytes {
  let first = instructions_test_body()
  let prefix = instructions_test_module(first, second)[0:28].to_owned()
  let code = b"\x82\x00" +
    Bytes::from_array([(first.length() | 128).to_byte(), 0]) +
    first +
    Bytes::from_array([second.length().to_byte()]) +
    second
  let data = prefix + instructions_test_section(10, code)
  if named {
    data +
    instructions_test_section(
      0,
      b"\x04name" + instructions_test_section(1, b"\x01\x01\x09target\"<&"),
    )
  } else {
    data
  }
}

///|
fn module_opcodes_test_report(data : Bytes) -> ModuleOpcodeReport raise {
  match inspect_module_opcodes(data) {
    Ok(report) => report
    Err(error) => fail(describe_module_opcode_error(error))
  }
}

///|
test "module-opcodes: mixed aggregate counts, distinct functions, ordering and code ledger" {
  let data = module_opcodes_test_module(
    module_opcodes_test_second(),
    named=true,
  )
  let r = module_opcodes_test_report(data)
  assert_eq(r.sha256, experiment_sha256(data))
  assert_eq(r.imported_function_count, 1)
  assert_eq(r.local_function_count, 2)
  assert_eq(r.code_section.unwrap().offset, 28)
  assert_eq(r.code_section.unwrap().total_size, 49)
  assert_eq(r.count_encoding.unwrap().file_offset, 30)
  assert_eq(r.count_encoding.unwrap().size, 2)
  assert_eq(r.code_header_bytes, 2)
  assert_eq(r.count_encoding_bytes, 2)
  assert_eq(r.body_prefix_bytes, 3)
  assert_eq(r.locals_encoding_bytes, 4)
  assert_eq(r.instruction_bytes, 38)
  assert_eq(r.instruction_count, 20)
  assert_eq(r.functions.map(fn(f) { f.stat.index }), [1, 2])
  assert_eq(r.functions[0].stat.offset, 32)
  assert_eq(r.functions[0].stat.total_size, 35)
  assert_eq(r.functions[0].stat.raw_name, Some("target\"<&"))
  assert_eq(r.functions[0].locals_encoding.file_offset, 34)
  assert_eq(r.functions[0].instruction_count, 15)
  assert_eq(r.functions[0].instruction_bytes, 30)
  assert_eq(r.functions[1].stat.offset, 67)
  assert_eq(r.functions[1].locals_encoding.file_offset, 68)
  assert_eq(r.functions[1].instruction_count, 5)
  let names = [
    "i32.const", "f32.const", "drop", "end", "block", "i32.trunc_sat_f32_s", "i32.trunc_sat_f32_u",
    "loop",
  ]
  let counts = [4, 2, 6, 4, 1, 1, 1, 1]
  let sizes = [10, 10, 6, 4, 2, 2, 2, 2]
  let functions = [2, 1, 2, 2, 1, 1, 1, 1]
  assert_eq(r.groups.map(fn(g) { g.mnemonic }), names)
  let mut group_bytes = 0
  let mut group_count = 0
  for i, group in r.groups {
    assert_eq(group.count, counts[i])
    assert_eq(group.encoded_bytes, sizes[i])
    assert_eq(group.function_count, functions[i])
    assert_true(
      group.function_count > 0 &&
      group.function_count <= r.local_function_count &&
      group.function_count <= group.count,
    )
    group_bytes += group.encoded_bytes
    group_count += group.count
  }
  assert_eq(
    r.code_section.unwrap().total_size,
    r.code_header_bytes +
    r.count_encoding_bytes +
    r.body_prefix_bytes +
    r.locals_encoding_bytes +
    r.instruction_bytes,
  )
  assert_eq(
    r.functions[0].stat.total_size + r.functions[1].stat.total_size,
    r.body_prefix_bytes + r.locals_encoding_bytes + r.instruction_bytes,
  )
  assert_eq(group_bytes, r.instruction_bytes)
  assert_eq(group_count, r.instruction_count)
  assert_eq(
    r.functions[0].instruction_bytes + r.functions[1].instruction_bytes,
    r.instruction_bytes,
  )
  let initialized = data[0:28].to_owned() +
    b"\x06\x06\x01\x7f\x00\x41\x00\x0b" +
    data[28:].to_owned() +
    b"\x0b\x05\x01\x01\x02\x41\x00"
  let excluded = module_opcodes_test_report(initialized)
  assert_eq(excluded.instruction_count, 20)
  assert_eq(excluded.groups[0].count, 4)
  assert_true(render_module_opcodes(r, 1).contains("showing 1 of 8"))
  assert_false(render_module_opcodes(r, 1).contains("\nf32.const  2"))
}

///|
test "module-opcodes: missing and empty code, imports, zero instructions and indexed failures" {
  let header = b"\x00asm\x01\x00\x00\x00"
  let absent = module_opcodes_test_report(header)
  assert_true(absent.code_section is None)
  assert_true(absent.count_encoding is None)
  assert_eq(absent.local_function_count, 0)
  assert_eq(absent.instruction_bytes, 0)
  let empty = module_opcodes_test_report(header + b"\x0a\x02\x80\x00")
  assert_eq(empty.code_section.unwrap().total_size, 4)
  assert_eq(empty.count_encoding_bytes, 2)
  assert_eq(empty.code_header_bytes, 2)
  assert_eq(empty.functions.length(), 0)
  let only_import = module_opcodes_test_report(
    module_opcodes_test_module(b"\x00\x0b")[0:23].to_owned(),
  )
  assert_eq(only_import.imported_function_count, 1)
  assert_eq(only_import.functions.length(), 0)
  let no_instructions = instructions_test_module(b"\x00", b"\x00")
  let structural = module_opcodes_test_report(no_instructions)
  assert_eq(structural.groups.length(), 0)
  assert_eq(structural.functions.length(), 2)
  assert_eq(structural.locals_encoding_bytes, 2)
  assert_eq(structural.instruction_count, 0)
  assert_true(
    render_module_opcodes(structural, 1).contains(
      "not full function-termination",
    ),
  )
  let bad = module_opcodes_test_module(b"\x00\xff")
  // One selective public call as a control within this new test, not old suites.
  assert_true(inspect_function_instructions(bad, 1) is Ok(_))
  for
    (input, offset) in [
      (bad, 69),
      (module_opcodes_test_module(b"\x00\x41\x80"), 70),
    ] {
    let result = inspect_module_opcodes(input)
    assert_true(result is Err(ModuleOpcodeBodyError(2, _)))
    let message = describe_module_opcode_error(result.unwrap_err())
    assert_true(message.contains("function 2"))
    assert_true(message.contains(offset.to_string()))
  }
  assert_true(inspect_module_opcodes(b"bad") is Err(ModuleOpcodeInputError(_)))
}

///|
test "module-opcodes: standalone parameters, safe names, null ranges and complete summary JSON" {
  assert_false(Options::default("x").opcode_stats)
  assert_eq(Options::default("x").opcode_stats_json, None)
  let args = [
    "moonsize", "--opcode-stats-json", "new.json", "--top", "1", "--", "--help",
  ]
  assert_eq(help_request(args).unwrap(), None)
  let options = parse_options(args).unwrap()
  assert_true(options.opcode_stats)
  assert_eq(options.opcode_stats_json, Some("new.json"))
  assert_eq(options.path, "--help")
  assert_eq(options.top, 1)
  assert_true(
    parse_options(["moonsize", "x", "--opcode-stats"]).unwrap().opcode_stats,
  )
  for
    flags in [
      ["--opcode-stats-json"],
      ["--opcode-stats-json", ""],
      ["--opcode-stats-json", "bad.txt"],
      ["--opcode-stats", "--strict"],
      ["--opcode-stats", "--baseline", "b"],
      ["--opcode-stats", "--budget", "b.json"],
      ["--opcode-stats", "--html", "new.html"],
      ["--opcode-stats", "--locals", "1"],
      ["--opcode-stats", "--baseline-locals", "1"],
      ["--opcode-stats", "--local-accesses", "1"],
      ["--opcode-stats", "--calls", "1"],
      ["--opcode-stats", "--instructions", "1"],
      ["--opcode-stats", "--locate-decode"],
      ["--opcode-stats", "--data-preview", "0"],
    ] {
    assert_true(parse_options(["moonsize", "x"] + flags) is Err(_))
  }
  assert_true(
    parse_options(["moonsize", "--opcode-stats", "--", "x", "--top", "1"])
    is Err(_),
  )
  assert_true(help_request(["moonsize", "--help"]).unwrap() is Some(_))
  let name = "name\n\u001b雪\""
  let bytes = @utf8.encode(name)
  let data = module_opcodes_test_module(module_opcodes_test_second()) +
    instructions_test_section(
      0,
      b"\x04name" +
      instructions_test_section(
        1,
        b"\x01\x01" + search_test_leb(bytes.length()) + bytes,
      ),
    )
  let r = module_opcodes_test_report(data)
  assert_eq(r.functions[0].stat.raw_name, Some(name))
  let root = match @json.parse(render_module_opcodes_json(r)) {
    Object(fields) => fields
    _ => fail("expected object")
  }
  match root.get("groups") {
    Some(Array(groups)) => assert_eq(groups.length(), 8)
    _ => fail("all groups expected")
  }
  match root.get("functions") {
    Some(Array(functions)) => assert_eq(functions.length(), 2)
    _ => fail("all summaries expected")
  }
  let json = render_module_opcodes_json(r)
  assert_false(json.contains(name))
  assert_true(json.contains("\"name\": null"))
  assert_true(json.contains("\"raw_name\": null"))
  assert_false(json.contains("\"instructions\":"))
  assert_false(json.contains("\"graph_complete\""))
  let empty_json = render_module_opcodes_json(
    module_opcodes_test_report(b"\x00asm\x01\x00\x00\x00"),
  )
  assert_true(empty_json.contains("\"code_section\": null"))
  assert_true(empty_json.contains("\"count_encoding\": null"))
}
