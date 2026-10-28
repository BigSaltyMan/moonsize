///|
fn opcode_search_test_module(
  second? : Bytes = b"\x00\x41\x01\x1a\x41\x80\x01\x1a\x0b",
  named? : Bool = true,
) -> Bytes {
  // f32 immediate includes 0x41, which must never become an i32.const site.
  let first = b"\x01\x02\x7f\x02\x40\x03\x40\x41\x00\x1a\x41\x80\x01\x1a\x43\x41\x00\x00\x00\xfc\x00\x1a\x43\x00\x00\x00\x00\xfc\x01\x1a\x0b\x0b\x0b"
  let prefix = instructions_test_module(first, second)[0:28].to_owned()
  let code = b"\x82\x00\xa1\x00" +
    first +
    Bytes::from_array([second.length().to_byte()]) +
    second
  let data = prefix +
    b"\x06\x06\x01\x7f\x00\x41\x00\x0b" +
    instructions_test_section(10, code)
  let name = b"same\ni32.const\"<&"
  let names = if named {
    instructions_test_section(
      0,
      b"\x04name" +
      instructions_test_section(1, b"\x02\x01\x11" + name + b"\x02\x11" + name),
    )
  } else {
    b""
  }
  data +
  names +
  instructions_test_section(0, b"\x09i32.consti32.const") +
  instructions_test_section(11, b"\x01\x01\x09i32.const")
}

///|
fn opcode_search_test_report(
  data : Bytes,
  query? : String = "i32.const",
) -> OpcodeSearchReport raise {
  match search_opcode(data, query) {
    Ok(report) => report
    Err(error) => fail(describe_opcode_search_error(error))
  }
}

///|
test "opcode-search: decoded multi-function sites, extension isolation and complete ledgers" {
  let data = opcode_search_test_module()
  let r = opcode_search_test_report(data)
  assert_eq(data.length(), 168)
  assert_eq(r.file_size, 168)
  assert_eq(r.sha256, experiment_sha256(data))
  assert_eq(r.imported_function_count, 1)
  assert_eq(r.scanned_local_function_count, 2)
  assert_eq(r.matched_function_count, 2)
  assert_eq(r.unmatched_function_count, 0)
  assert_eq(r.instruction_count, 20)
  assert_eq(r.instruction_bytes, 38)
  assert_eq(r.match_count, 4)
  assert_eq(r.matched_encoded_bytes, 10)
  assert_eq(r.other_instruction_bytes, 28)
  assert_eq(r.functions.map(fn(f) { f.stat.index }), [1, 2])
  assert_eq(r.functions[0].stat.raw_name, Some("same\ni32.const\"<&"))
  assert_eq(r.functions[0].stat.raw_name, r.functions[1].stat.raw_name)
  assert_eq(r.functions[0].stat.offset, 40)
  assert_eq(r.functions[1].stat.offset, 75)
  let ordinals = [[2, 4], [0, 2]]
  let offsets = [[49, 52], [77, 80]]
  let relative = [[7, 10], [1, 4]]
  let sizes = [2, 3]
  let expected = [b"\x41\x00", b"\x41\x80\x01", b"\x41\x01", b"\x41\x80\x01"]
  let mut all_count = 0
  let mut all_bytes = 0
  for i, f in r.functions {
    assert_eq(f.match_count, 2)
    assert_eq(f.matched_encoded_bytes, 5)
    assert_eq(f.match_count, f.sites.length())
    for j, site in f.sites {
      assert_eq(site.ordinal, ordinals[i][j])
      assert_eq(site.file_offset, offsets[i][j])
      assert_eq(site.body_relative_offset, relative[i][j])
      assert_eq(site.encoded_size, sizes[j])
      assert_eq(site.mnemonic, "i32.const")
      assert_eq(
        data[site.file_offset:site.file_offset + site.encoded_size].to_owned(),
        expected[i * 2 + j],
      )
      all_bytes += site.encoded_size
      all_count += 1
    }
  }
  assert_eq(all_count, r.match_count)
  assert_eq(all_bytes, r.matched_encoded_bytes)
  assert_eq(
    r.scanned_local_function_count,
    r.matched_function_count + r.unmatched_function_count,
  )
  assert_eq(
    r.instruction_bytes,
    r.matched_encoded_bytes + r.other_instruction_bytes,
  )
  let s = opcode_search_test_report(data, query="i32.trunc_sat_f32_s")
  let u = opcode_search_test_report(data, query="i32.trunc_sat_f32_u")
  assert_eq(s.match_count, 1)
  assert_eq(s.functions[0].sites[0].file_offset, 61)
  assert_eq(s.functions[0].sites[0].ordinal, 7)
  assert_eq(u.match_count, 1)
  assert_eq(u.functions[0].sites[0].file_offset, 69)
  assert_eq(u.functions[0].sites[0].ordinal, 10)
  assert_eq(s.matched_encoded_bytes, 2)
}

///|
test "opcode-search: exact names, empty states and whole-query indexed failures" {
  let header = b"\x00asm\x01\x00\x00\x00"
  for data in [header, header + b"\x0a\x01\x00"] {
    let r = opcode_search_test_report(data)
    assert_eq(r.scanned_local_function_count, 0)
    assert_eq(r.functions.length(), 0)
    assert_eq(r.instruction_count, 0)
    assert_true(
      render_opcode_search(r, 1).contains("No local function definitions"),
    )
  }
  for
    query in [
      "i64.const", "not-a-mnemonic", "I32.CONST", " i32.const", "i32.const ", "0x41",
      "const", "i32.",
    ] {
    let r = opcode_search_test_report(opcode_search_test_module(), query~)
    assert_eq(r.query, query)
    assert_eq(r.scanned_local_function_count, 2)
    assert_eq(r.unmatched_function_count, 2)
    assert_eq(r.match_count, 0)
    assert_true(
      render_opcode_search(r, 1).contains(
        "No matching mnemonic in the decoded local function instructions",
      ),
    )
  }
  for query in ["", " \t\n"] {
    assert_true(search_opcode(b"bad", query) is Err(InvalidOpcodeSearchQuery))
  }
  assert_true(
    search_opcode(b"bad", "i32.const")
    is Err(OpcodeSearchInputError(ModuleOpcodeInputError(_))),
  )
  for second in [b"\x00\xff", b"\x00\xfc\x7f", b"\x00\x41\x80"] {
    let result = search_opcode(opcode_search_test_module(second~), "i32.const")
    assert_true(
      result is Err(OpcodeSearchInputError(ModuleOpcodeBodyError(2, _))),
    )
    assert_true(
      describe_opcode_search_error(result.unwrap_err()).contains("function 2"),
    )
  }
  let unknown = search_opcode(
    opcode_search_test_module(second=b"\x00\xff"),
    "i32.const",
  ).unwrap_err()
  assert_true(describe_opcode_search_error(unknown).contains("77"))
}

///|
test "opcode-search: independent options, global Top, safe text and complete JSON" {
  assert_eq(Options::default("x").find_opcode, None)
  assert_eq(Options::default("x").find_opcode_json, None)
  let args = [
    "moonsize", "--find-opcode", "i32.const", "--find-opcode-json", "new.json", "--top",
    "1", "--", "--help",
  ]
  assert_eq(help_request(args).unwrap(), None)
  let opts = parse_options(args).unwrap()
  assert_eq(opts.path, "--help")
  assert_eq(opts.find_opcode, Some("i32.const"))
  assert_eq(opts.find_opcode_json, Some("new.json"))
  assert_eq(opts.top, 1)
  for
    flags in [
      ["--find-opcode"],
      ["--find-opcode", ""],
      ["--find-opcode", " \t"],
      ["--find-opcode-json", "new.json"],
      ["--find-opcode", "--help"],
      ["--find-opcode", "i32.const", "--find-opcode-json"],
      ["--find-opcode", "i32.const", "--find-opcode-json", "bad.txt"],
      ["--find-opcode", "i32.const", "--opcode-stats"],
      ["--find-opcode", "i32.const", "--baseline", "b", "--diff-opcodes"],
      ["--find-opcode", "i32.const", "--strict"],
      ["--find-opcode", "i32.const", "--budget", "budget.json"],
      ["--find-opcode", "i32.const", "--html", "new.html"],
      ["--find-opcode", "i32.const", "--instructions", "1"],
    ] {
    assert_true(parse_options(["moonsize", "x"] + flags) is Err(_))
  }
  assert_true(help_request(["moonsize", "--help"]).unwrap() is Some(_))
  let data = opcode_search_test_module()
  let r = opcode_search_test_report(data)
  let text = render_opcode_search(r, 1)
  assert_true(text.contains("showing 1 of 4"))
  assert_true(text.contains("1  2  49  7  2  "))
  assert_false(text.contains("1  4  52  10  3  "))
  assert_false(text.contains("same\ni32.const"))
  assert_true(text.contains("same\\ni32.const\\\"<&"))
  let escaped = render_opcode_search(
    opcode_search_test_report(data, query="i32.const\n\u001b"),
    1,
  )
  assert_true(escaped.contains("i32.const\\n\\u001b"))
  let fields = match @json.parse(render_opcode_search_json(r)) {
    Object(fields) => fields
    _ => fail("object expected")
  }
  assert_eq(fields.get("match_count"), Some(int_json(4)))
  assert_true(fields.get("sites") is None)
  match fields.get("functions") {
    Some(Array(functions)) => {
      assert_eq(functions.length(), 2)
      for function in functions {
        match function {
          Object(value) =>
            match value.get("sites") {
              Some(Array(sites)) => assert_eq(sites.length(), 2)
              _ => fail("complete sites expected")
            }
          _ => fail("function expected")
        }
      }
    }
    _ => fail("functions expected")
  }
  let unnamed = opcode_search_test_report(
    opcode_search_test_module(named=false),
  )
  assert_true(render_opcode_search_json(unnamed).contains("\"raw_name\": null"))
  assert_false(render_opcode_search_json(r).contains("\"operands\""))
  assert_false(render_opcode_search_json(r).contains("\"graph_complete\""))
}
