///|
fn locals_diff_test_before_body() -> Bytes {
  b"\x04\x02\x7f\x00\x7f\x01\x7e\x00\x63\x70\xff"
}

///|
fn locals_diff_test_after_body() -> Bytes {
  b"\x85\x00\x82\x00\x7f\x00\x7f\x01\x7f\x00\x63\x70\x03\x63\x80\x00\xff\xff"
}

///|
fn locals_diff_test_current() -> Bytes {
  let base = instructions_test_module(
    b"\x00\xff",
    locals_diff_test_after_body(),
  )
  // Two function imports, so the selected second local has full index 3.
  base[0:14].to_owned() +
  b"\x02\x0d\x02\x01m\x01f\x00\x00\x01m\x01g\x00\x00" +
  base[23:].to_owned()
}

///|
fn locals_diff_test_compare(
  before : Bytes,
  bi : Int,
  after : Bytes,
  ci : Int,
) -> FunctionLocalsComparison raise {
  match compare_function_locals(before, bi, after, ci) {
    Ok(value) => value
    Err(error) => fail(describe_function_locals_comparison_error(error))
  }
}

///|
test "function-locals-diff: explicit targets, raw encoding buckets and closing ledgers" {
  let before = instructions_test_module(
    locals_diff_test_before_body(),
    b"\x00\xff",
  )
  let after = locals_diff_test_current()
  let r = locals_diff_test_compare(before, 1, after, 3)
  assert_eq(r.baseline.target.index, 1)
  assert_eq(r.current.target.index, 3)
  assert_eq(r.baseline.sha256, experiment_sha256(before))
  assert_eq(r.current.sha256, experiment_sha256(after))
  assert_eq(r.baseline.groups.length(), 4)
  assert_eq(r.current.groups.length(), 5)
  assert_eq(r.baseline.body_remainder.size, 1)
  assert_eq(r.current.body_remainder.size, 2)
  assert_eq(r.delta.entry_bytes, 6)
  assert_eq(r.delta.prefix_bytes, -1)
  assert_eq(r.delta.body_bytes, 7)
  assert_eq(r.delta.locals_bytes, 6)
  assert_eq(r.delta.group_count_encoding_bytes, 1)
  assert_eq(r.delta.quantity_encoding_bytes, 2)
  assert_eq(r.delta.type_encoding_bytes, 3)
  assert_eq(r.delta.group_count, 1)
  assert_eq(r.delta.declared_count_delta_decimal, "3")
  assert_eq(r.delta.entry_bytes, r.delta.prefix_bytes + r.delta.body_bytes)
  assert_eq(
    r.delta.body_bytes,
    r.delta.locals_bytes + r.delta.body_remainder_bytes,
  )
  assert_eq(
    r.delta.locals_bytes,
    r.delta.group_count_encoding_bytes +
    r.delta.quantity_encoding_bytes +
    r.delta.type_encoding_bytes,
  )
  assert_eq(r.type_encodings.map(fn(row) { row.type_hex }), [
    "6370", "638000", "7e", "7f",
  ])
  let zero = r.type_encodings[0]
  assert_eq(zero.presence, "shared_encoding")
  assert_eq(zero.type_label, None)
  assert_eq(zero.baseline.declared_count, 0UL)
  assert_eq(zero.current.declared_count, 0UL)
  assert_eq(zero.baseline.group_indices, [3])
  assert_eq(zero.current.group_indices, [3])
  assert_eq(r.type_encodings[1].presence, "current_only")
  assert_eq(r.type_encodings[2].presence, "baseline_only")
  let shared = r.type_encodings[3]
  assert_eq(shared.baseline.group_indices, [0, 1])
  assert_eq(shared.current.group_indices, [0, 1, 2])
  assert_eq(shared.delta.group_bytes, 3)
  let mut before_bytes = 0
  let mut after_bytes = 0
  let mut difference = 0
  let mut before_quantity = 0UL
  let mut after_quantity = 0UL
  let mut before_groups = 0
  let mut after_groups = 0
  for row in r.type_encodings {
    before_bytes += row.baseline.group_bytes
    after_bytes += row.current.group_bytes
    difference += row.delta.group_bytes
    before_quantity += row.baseline.declared_count
    after_quantity += row.current.declared_count
    before_groups += row.baseline.group_count
    after_groups += row.current.group_count
    assert_eq(
      row.delta.declared_count_delta_decimal,
      locals_count_delta(
        row.baseline.declared_count,
        row.current.declared_count,
      ),
    )
  }
  assert_eq(
    before_bytes,
    r.baseline.locals_encoding.size - r.baseline.group_count_encoding.size,
  )
  assert_eq(
    after_bytes,
    r.current.locals_encoding.size - r.current.group_count_encoding.size,
  )
  assert_eq(
    difference,
    r.delta.locals_bytes - r.delta.group_count_encoding_bytes,
  )
  assert_eq(before_quantity, r.baseline.declared_count)
  assert_eq(after_quantity, r.current.declared_count)
  assert_eq(
    locals_count_delta(before_quantity, after_quantity),
    r.delta.declared_count_delta_decimal,
  )
  assert_eq(before_groups, r.baseline.group_count)
  assert_eq(after_groups, r.current.group_count)
  let narrow = instructions_test_module(b"\x01\x02\x7f\xff", b"\x00\xff")
  let wide = instructions_test_module(b"\x01\x82\x00\x7f\xff", b"\x00\xff")
  let width_only = locals_diff_test_compare(narrow, 1, wide, 1)
  assert_eq(width_only.delta.declared_count_delta_decimal, "0")
  assert_eq(width_only.delta.quantity_encoding_bytes, 1)
  assert_eq(width_only.type_encodings.length(), 1)
  assert_eq(
    width_only.type_encodings[0].delta.declared_count_delta_decimal,
    "0",
  )
}

///|
test "function-locals-diff: exact signed quantities, zero groups and side-specific failures" {
  let empty = instructions_test_module(b"\x00\xff", b"\x00\xff")
  let huge = instructions_test_module(
    b"\x02\xff\xff\xff\xff\x0f\x7f\xff\xff\xff\xff\x0f\x7f\xff", b"\x00\xff",
  )
  let positive = locals_diff_test_compare(empty, 1, huge, 1)
  assert_eq(positive.current.groups.length(), 2)
  assert_eq(positive.current.declared_count, 8589934590UL)
  assert_eq(positive.delta.declared_count_delta_decimal, "8589934590")
  assert_eq(
    locals_diff_test_compare(huge, 1, empty, 1).delta.declared_count_delta_decimal,
    "-8589934590",
  )
  assert_eq(locals_count_delta(0UL, 9007199254740993UL), "9007199254740993")
  assert_eq(
    locals_count_delta(18446744073709551615UL, 1UL),
    "-18446744073709551614",
  )
  assert_eq(
    locals_count_delta(1UL, 18446744073709551615UL),
    "18446744073709551614",
  )
  assert_eq(
    locals_count_delta(18446744073709551615UL, 18446744073709551615UL),
    "0",
  )
  let self_report = locals_diff_test_compare(huge, 1, huge, 1)
  assert_eq(self_report.delta.entry_bytes, 0)
  assert_eq(self_report.delta.locals_bytes, 0)
  assert_eq(self_report.delta.declared_count_delta_decimal, "0")
  assert_eq(self_report.type_encodings[0].baseline.group_indices, [0, 1])
  let both_empty = locals_diff_test_compare(empty, 1, empty, 1)
  assert_eq(both_empty.type_encodings.length(), 0)
  let zero_group = instructions_test_module(b"\x01\x00\x7f\xff", b"\x00\xff")
  let zero = locals_diff_test_compare(empty, 1, zero_group, 1)
  assert_eq(zero.type_encodings[0].presence, "current_only")
  assert_eq(zero.delta.declared_count_delta_decimal, "0")
  for
    result in [
      compare_function_locals(b"bad", 1, empty, 1),
      compare_function_locals(empty, 0, empty, 1),
    ] {
    assert_true(result is Err(BaselineLocalsError(_, _)))
    assert_true(
      describe_function_locals_comparison_error(result.unwrap_err()).contains(
        "baseline function",
      ),
    )
  }
  for
    (data, index) in [
      (b"bad", 1),
      (empty, 99),
      (instructions_test_module(b"\x01\x01\x63", b"\x00\x0b"), 1),
    ] {
    let result = compare_function_locals(empty, 1, data, index)
    assert_true(result is Err(CurrentLocalsError(_, _)))
    assert_true(
      describe_function_locals_comparison_error(result.unwrap_err()).contains(
        "current function \{index}",
      ),
    )
  }
}

///|
test "function-locals-diff: parameter pairing, complete nested JSON, Top and single format" {
  assert_eq(Options::default("x").baseline_locals_index, None)
  let args = [
    "moonsize", "--locals", "3", "--baseline", "b", "--baseline-locals", "1", "--locals-json",
    "new.json", "--top", "1", "--", "--help",
  ]
  assert_eq(help_request(args).unwrap(), None)
  let options = parse_options(args).unwrap()
  assert_eq(options.locals_index, Some(3))
  assert_eq(options.baseline_locals_index, Some(1))
  assert_eq(options.locals_json, Some("new.json"))
  assert_eq(options.path, "--help")
  assert_eq(
    parse_options([
      "moonsize", "x", "--locals", "1", "--baseline", "b", "--baseline-locals", "2147483647",
    ]).unwrap().baseline_locals_index,
    Some(2147483647),
  )
  for
    flags in [
      ["--baseline-locals", "1"],
      ["--baseline", "b", "--baseline-locals", "1"],
      ["--locals", "1", "--baseline-locals", "1"],
      ["--locals", "1", "--baseline", "b"],
      ["--locals", "1", "--baseline", "", "--baseline-locals", "1"],
      ["--baseline-locals"],
      ["--baseline-locals", "-1"],
      ["--baseline-locals", "2147483648"],
      ["--baseline-locals", "1.5"],
      ["--baseline-locals", "0x1"],
      ["--locals", "1", "--baseline", "b", "--baseline-locals", "1", "--strict"],
      [
        "--locals", "1", "--baseline", "b", "--baseline-locals", "1", "--baseline-instructions",
        "1",
      ],
      [
        "--locals", "1", "--baseline", "b", "--baseline-locals", "1", "--calls",
        "1",
      ],
      [
        "--locals", "1", "--baseline", "b", "--baseline-locals", "1", "--html", "n.html",
      ],
      [
        "--locals", "1", "--baseline", "b", "--baseline-locals", "1", "--max-size",
        "1KB",
      ],
    ] {
    assert_true(parse_options(["moonsize", "x"] + flags) is Err(_))
  }
  assert_eq(
    parse_options(["moonsize", "x", "--locals", "1"]).unwrap().baseline_locals_index,
    None,
  )
  let before = instructions_test_module(
    locals_diff_test_before_body(),
    b"\x00\xff",
    named=true,
  )
  let report = locals_diff_test_compare(
    before,
    1,
    locals_diff_test_current(),
    3,
  )
  let text = render_function_locals_comparison(report, 1)
  assert_true(text.contains("TYPE ENCODINGS: showing 1 of 4"))
  assert_true(text.contains("\n6370  unknown  shared_encoding"))
  assert_false(text.contains("\n638000  "))
  assert_true(text.contains(search_terminal_string("target\"<&")))
  assert_true(text.contains("Prefix bytes  2  1  -1"))
  let root = match @json.parse(render_function_locals_comparison_json(report)) {
    Object(fields) => fields
    _ => fail("object expected")
  }
  assert_eq(
    root.get("format"),
    Some(Json::string("moonsize-function-locals-diff")),
  )
  assert_eq(
    root.get("baseline"),
    Some(function_locals_json_value(report.baseline)),
  )
  assert_eq(
    root.get("current"),
    Some(function_locals_json_value(report.current)),
  )
  match root.get("type_encodings") {
    Some(Array(rows)) => assert_eq(rows.length(), 4)
    _ => fail("complete rows expected")
  }
  let json = render_function_locals_comparison_json(report)
  assert_true(json.contains("\"type_label\": null"))
  assert_true(json.contains("\"declared_count_delta_decimal\": \"-1\""))
  assert_eq(
    render_function_locals_json(report.baseline),
    function_locals_json_value(report.baseline).stringify(indent=2) + "\n",
  )
  assert_true(
    render_function_locals_json(report.baseline).contains(
      "\"format\": \"moonsize-function-locals\"",
    ),
  )
  assert_false(json.contains("\"graph_complete\""))
}
