///|
fn function_locals_test_body() -> Bytes {
  // Non-shortest group count/quantity, zero group, adjacent i32 groups, and a
  // multi-byte heap type. The trailing opcode deliberately remains undecoded.
  b"\x84\x00\x82\x00\x7f\x00\x7f\x01\x7f\x03\x63\x80\x00\xff"
}

///|
fn function_locals_test_report(body : Bytes) -> FunctionLocalsReport raise {
  match
    inspect_function_locals(
      instructions_test_module(body, b"\x00\xff", named=true),
      1,
    ) {
    Ok(report) => report
    Err(error) => fail(describe_function_locals_error(error))
  }
}

///|
test "function-locals: encoding, original groups, ordinals and complete ledgers" {
  let data = instructions_test_module(
    function_locals_test_body(),
    b"\x00\xff",
    named=true,
  )
  let r = function_locals_test_report(function_locals_test_body())
  assert_eq(r.target.index, 1)
  assert_false(r.target.imported)
  assert_eq(r.target.raw_name, Some("target\"<&"))
  assert_eq(r.sha256, experiment_sha256(data))
  assert_eq(r.entry.file_offset, 31)
  assert_eq(r.prefix.size, 2)
  assert_eq(r.body.file_offset, 33)
  assert_eq(r.body.size, 14)
  assert_eq(r.locals_encoding.size, 13)
  assert_eq(r.group_count_encoding.size, 2)
  assert_eq(r.group_count, 4)
  assert_eq(r.declared_count, 6UL)
  assert_eq(r.quantity_encoding_bytes, 5)
  assert_eq(r.type_encoding_bytes, 6)
  let quantities : Array[UInt] = [2U, 0U, 1U, 3U]
  let starts = [0UL, 2UL, 2UL, 3UL]
  let ends = [2UL, 2UL, 3UL, 6UL]
  let offsets = [35, 38, 40, 42]
  let sizes = [3, 2, 2, 4]
  let mut group_bytes = 0
  let mut total = 0UL
  for i, group in r.groups {
    assert_eq(group.group_index, i)
    assert_eq(group.quantity, quantities[i])
    assert_eq(group.declared_ordinal_start, starts[i])
    assert_eq(group.declared_ordinal_end, ends[i])
    assert_eq(group.encoding.file_offset, offsets[i])
    assert_eq(group.encoding.size, sizes[i])
    assert_eq(
      group.encoding.size,
      group.quantity_encoding.size + group.type_encoding.size,
    )
    assert_eq(
      group.type_encoding.file_offset,
      group.quantity_encoding.file_offset + group.quantity_encoding.size,
    )
    let span = group.type_encoding
    assert_eq(
      data_preview_hex(data[span.file_offset:span.file_offset + span.size]),
      group.type_hex,
    )
    assert_eq(group.type_label, if i == 3 { None } else { Some("i32") })
    group_bytes += group.encoding.size
    total += group.quantity.to_uint64()
  }
  assert_eq(r.groups[3].type_hex, "638000")
  assert_eq(r.body_remainder.file_offset, 46)
  assert_eq(r.body_remainder.size, 1)
  assert_eq(r.entry.size, r.prefix.size + r.body.size)
  assert_eq(r.body.size, r.locals_encoding.size + r.body_remainder.size)
  assert_eq(r.locals_encoding.size, r.group_count_encoding.size + group_bytes)
  assert_eq(group_bytes, r.quantity_encoding_bytes + r.type_encoding_bytes)
  assert_eq(total, r.declared_count)
  let text = render_function_locals(r, 1)
  assert_true(text.contains("GROUPS: showing 1 of 4"))
  assert_false(text.contains("\n1  0  ["))
  let fields = match @json.parse(render_function_locals_json(r)) {
    Object(fields) => fields
    _ => fail("expected object")
  }
  assert_eq(fields.get("declared_count_decimal"), Some(Json::string("6")))
  match fields.get("groups") {
    Some(Array(groups)) => assert_eq(groups.length(), 4)
    _ => fail("expected all four groups")
  }
}

///|
test "function-locals: unsigned counts, bounded declarations and no opcode decoding" {
  // Structural inspection fixtures, not claims of fully type-validated modules.
  let huge = function_locals_test_report(b"\x01\xff\xff\xff\xff\x0f\x7f\xff")
  assert_eq(huge.groups.length(), 1)
  assert_eq(huge.groups[0].quantity, 4294967295U)
  assert_eq(huge.declared_count, 4294967295UL)
  assert_eq(huge.groups[0].quantity_encoding.size, 5)
  let sum = function_locals_test_report(
    b"\x02\xff\xff\xff\xff\x0f\x7f\x01\x7f\xff",
  )
  assert_eq(sum.groups.length(), 2)
  assert_eq(sum.declared_count, 4294967296UL)
  assert_eq(sum.groups[1].declared_ordinal_start, 4294967295UL)
  assert_true(
    render_function_locals_json(sum).contains(
      "\"declared_count_decimal\": \"4294967296\"",
    ),
  )
  assert_true(
    render_function_locals_json(huge).contains("\"quantity\": 4294967295"),
  )
  let zero = function_locals_test_report(b"\x00\xff")
  assert_eq(zero.group_count, 0)
  assert_eq(zero.locals_encoding.size, 1)
  assert_eq(zero.body_remainder.size, 1)
  let zero_quantity = function_locals_test_report(b"\x01\x00\x7f\xff")
  assert_eq(zero_quantity.group_count, 1)
  assert_eq(zero_quantity.declared_count, 0UL)
  assert_eq(
    zero_quantity.groups[0].declared_ordinal_start,
    zero_quantity.groups[0].declared_ordinal_end,
  )
  let data = instructions_test_module(b"\x00\xff", b"\x00\xff")
  assert_true(inspect_function_locals(data, 0) is Err(ImportedLocalsTarget(0)))
  assert_true(
    inspect_function_locals(data, -1) is Err(InvalidLocalsTarget(-1, 3)),
  )
  assert_true(
    inspect_function_locals(data, 3) is Err(InvalidLocalsTarget(3, 3)),
  )
  // Groups can't borrow the next function's size/local bytes to finish a type.
  for
    body in [
      b"", b"\x01\x01", b"\x01\x01\x63", b"\x01\x01\x63\x80", b"\x01\xff\xff\xff\xff\x10\x7f",
      b"\xff\xff\xff\xff\x0f",
    ] {
    let result = inspect_function_locals(
      instructions_test_module(body, b"\x00\x0b"),
      1,
    )
    assert_true(result is Err(_))
    assert_true(!describe_function_locals_error(result.unwrap_err()).is_empty())
  }
  assert_true(inspect_function_locals(b"bad", 0) is Err(LocalsInputError(_)))
  // Declared groups may consume the entire body: remainder is simply empty.
  assert_eq(function_locals_test_report(b"\x01\x00\x7f").body_remainder.size, 0)
}

///|
test "function-locals: parameters, safe rendering, null labels and stable decimal strings" {
  assert_eq(Options::default("x").locals_index, None)
  assert_eq(Options::default("x").locals_json, None)
  let args = [
    "moonsize", "--locals", "1", "--locals-json", "new.json", "--top", "1", "--",
    "--help",
  ]
  assert_eq(help_request(args).unwrap(), None)
  let options = parse_options(args).unwrap()
  assert_eq(options.locals_index, Some(1))
  assert_eq(options.locals_json, Some("new.json"))
  assert_eq(options.path, "--help")
  assert_eq(options.top, 1)
  assert_eq(
    parse_options(["moonsize", "x", "--locals", "2147483647"]).unwrap().locals_index,
    Some(2147483647),
  )
  for
    flags in [
      ["--locals-json", "new.json"],
      ["--locals"],
      ["--locals", "-1"],
      ["--locals", "2147483648"],
      ["--locals", "1.0"],
      ["--locals", "0x1"],
      ["--locals", "1", "--locals-json"],
      ["--locals", "1", "--locals-json", "bad.txt"],
      ["--locals", "1", "--locals-json", ""],
      ["--locals", "1", "--strict"],
      ["--locals", "1", "--calls", "1"],
      ["--locals", "1", "--locate-decode"],
      ["--locals", "1", "--locate-offset", "31"],
      ["--locals", "1", "--data-preview", "0"],
      ["--locals", "1", "--instructions", "1"],
      ["--locals", "1", "--baseline", "b"],
      ["--locals", "1", "--budget", "b.json"],
      ["--locals", "1", "--html", "n.html"],
    ] {
    assert_true(parse_options(["moonsize", "x"] + flags) is Err(_))
  }
  assert_true(
    parse_options(["moonsize", "--locals", "1", "--", "x", "--top", "1"])
    is Err(_),
  )
  assert_true(help_request(["moonsize", "--help"]).unwrap() is Some(_))
  let name = "line\n\u001b\u0085雪"
  let bytes = @utf8.encode(name)
  let data = instructions_test_module(function_locals_test_body(), b"\x00\xff") +
    instructions_test_section(
      0,
      b"\x04name" +
      instructions_test_section(
        1,
        b"\x01\x01" + search_test_leb(bytes.length()) + bytes,
      ),
    )
  let report = inspect_function_locals(data, 1).unwrap()
  let text = render_function_locals(report, 1)
  assert_true(text.contains(search_terminal_string(name)))
  assert_false(text.contains(name))
  let json = render_function_locals_json(report)
  assert_true(json.contains("\"type_label\": null"))
  assert_true(json.contains("\"declared_ordinal_start_decimal\": \"0\""))
  assert_false(json.contains("\"graph_complete\""))
  assert_true(
    render_function_locals(function_locals_test_report(b"\x00\xff"), 1).contains(
      "Zero declaration groups",
    ),
  )
  assert_true(
    render_function_locals(function_locals_test_report(b"\x01\x00\x7f\xff"), 1).contains(
      "all quantities are zero",
    ),
  )
}
