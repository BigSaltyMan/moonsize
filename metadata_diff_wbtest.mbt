///|
fn metadata_diff_test_compare(
  before : Bytes,
  after : Bytes,
) -> MetadataComparison raise {
  match compare_metadata(before, after) {
    Ok(r) => r
    Err(Baseline(e)) => fail("baseline: " + describe_error(e))
    Err(Current(e)) => fail("current: " + describe_error(e))
  }
}

///|
fn metadata_diff_test_ledger(report : MetadataComparison) -> Unit raise {
  for groups in [report.categories, report.name_groups] {
    let mut before = 0
    let mut after = 0
    let mut change = 0
    let mut before_count = 0
    let mut after_count = 0
    let mut count_change = 0
    for group in groups {
      for totals in [group.baseline, group.current, group.delta] {
        assert_eq(
          totals.custom_encoded_bytes,
          totals.section_header_bytes +
          totals.name_encoding_bytes +
          totals.content_bytes,
        )
      }
      assert_eq(group.delta, metadata_diff_delta(group.baseline, group.current))
      assert_eq(group.baseline_ordinals.length(), group.baseline.custom_count)
      assert_eq(group.current_ordinals.length(), group.current.custom_count)
      before += group.baseline.custom_encoded_bytes
      after += group.current.custom_encoded_bytes
      change += group.delta.custom_encoded_bytes
      before_count += group.baseline.custom_count
      after_count += group.current.custom_count
      count_change += group.delta.custom_count
    }
    assert_eq(before, report.baseline.summary.custom_bytes)
    assert_eq(after, report.current.summary.custom_bytes)
    assert_eq(change, report.delta.custom_encoded_bytes)
    assert_eq(before_count, report.baseline.customs.length())
    assert_eq(after_count, report.current.customs.length())
    assert_eq(count_change, report.delta.custom_count)
  }
  assert_eq(
    report.delta_file_bytes,
    report.delta.custom_encoded_bytes + report.delta_non_custom_bytes,
  )
  assert_eq(
    report.baseline.file_size,
    report.baseline_non_custom_bytes + report.baseline.summary.custom_bytes,
  )
  assert_eq(
    report.current.file_size,
    report.current_non_custom_bytes + report.current.summary.custom_bytes,
  )
}

///|
test "metadata-diff: duplicate instances, reordered names, actual prefix widths and closed ledgers" {
  let head = b"\x00asm\x01\x00\x00\x00"
  let before = head +
    metadata_test_custom(b"x", b"a") +
    metadata_test_custom(b"x", b"b") +
    metadata_test_custom(b".debug_info", b"")
  let reordered = head +
    metadata_test_custom(b".debug_info", b"") +
    metadata_test_custom(b"x", b"b") +
    metadata_test_custom(b"x", b"a")
  let unchanged = metadata_diff_test_compare(before, reordered)
  assert_eq(unchanged.delta.custom_encoded_bytes, 0)
  assert_eq(unchanged.name_groups[1].baseline_ordinals, [0, 1])
  assert_eq(unchanged.name_groups[1].current_ordinals, [1, 2])
  let after = head +
    duplicate_test_section(5, b"\x01\x00\x00") +
    metadata_test_custom(b".debug_info", b"") +
    metadata_test_custom(b"x", b"a", wide=true) +
    metadata_test_custom(b"x", b"b")
  let report = metadata_diff_test_compare(before, after)
  metadata_diff_test_ledger(report)
  assert_eq(report.delta.custom_encoded_bytes, 2)
  assert_eq(report.delta.section_header_bytes, 1)
  assert_eq(report.delta.name_encoding_bytes, 1)
  assert_eq(report.delta.content_bytes, 0)
  assert_eq(report.delta_non_custom_bytes, 5)
  assert_eq(report.delta_file_bytes, 7)
  assert_eq(report.name_groups[0].name, Some("x"))
  assert_eq(report.name_groups[0].baseline_ordinals, [0, 1])
  assert_eq(report.name_groups[0].current_ordinals, [1, 2])
  metadata_diff_test_ledger(metadata_diff_test_compare(after, before))
  metadata_diff_test_ledger(unchanged)
}

///|
test "metadata-diff: absent, empty, unavailable and literal names, optional partial retained" {
  let head = b"\x00asm\x01\x00\x00\x00"
  let empty = metadata_diff_test_compare(head, head)
  assert_eq(empty.name_groups.length(), 0)
  assert_eq(empty.categories.length(), 5)
  metadata_diff_test_ledger(empty)
  // Invalid UTF-8 tests legacy parser tolerance only, not V8 validity.
  let data = head +
    metadata_test_custom(b"", b"") +
    metadata_test_custom(b"\xff", b"") +
    metadata_test_custom(b"(unavailable)", b"") +
    metadata_test_custom(@utf8.encode("�"), b"") +
    metadata_test_custom(b"name", b"\x01\x80")
  let report = metadata_diff_test_compare(data, data)
  metadata_diff_test_ledger(report)
  assert_eq(report.name_groups.length(), 5)
  assert_eq(report.name_groups[0].name, Some(""))
  assert_eq(report.name_groups[4].kind, "unavailable_names")
  assert_eq(report.name_groups[4].name, None)
  assert_eq(
    report.name_groups
    .filter(fn(g) { g.name == Some("(unavailable)") })
    .length(),
    1,
  )
  assert_eq(
    report.name_groups.filter(fn(g) { g.name == Some("�") }).length(),
    1,
  )
  for input in [report.baseline, report.current] {
    assert_true(input.byte_ledger_complete)
    assert_eq(input.custom_name_status, "partial")
    assert_eq(input.name_details_status, "partial")
    assert_true(input.diagnostics.length() > 0)
    assert_true(
      input.customs.filter(fn(c) { c.unbounded_tail is Some(_) }).length() > 0,
    )
  }
  let text = render_metadata_diff(report, 0)
  assert_true(text.contains("name details: partial"))
  assert_true(text.contains("Unbounded name tail"))
  assert_true(text.contains("internal name details are not compared"))
}

///|
test "metadata-diff: deterministic complete JSON, Top, side errors and mode grammar" {
  let head = b"\x00asm\x01\x00\x00\x00"
  let data = head +
    metadata_test_custom(b"z", b"a") +
    metadata_test_custom(b"aa", b"b") +
    metadata_test_custom(b"aa", b"c")
  let report = metadata_diff_test_compare(data, data)
  assert_eq(report.name_groups[0].name, Some("aa")) // Lexical, not shortlex.
  let json = render_metadata_diff_json(report)
  assert_eq(
    json,
    render_metadata_diff_json(metadata_diff_test_compare(data, data)),
  )
  let root = json_object(@json.parse(json))
  assert_eq(root.get("format"), Some(Json::string("moonsize-metadata-diff")))
  let before = json_object(root.get("baseline").unwrap())
  assert_eq(json_array(before.get("customs").unwrap()).length(), 3)
  assert_eq(json_array(root.get("name_groups").unwrap()).length(), 2)
  assert_eq(
    root.get("baseline"),
    Some(@json.parse(render_metadata_json(report.baseline))),
  )
  assert_true(
    render_metadata_diff(report, 1).contains("FULL-NAME GROUPS: showing 1 of 2"),
  )
  assert_true(
    render_metadata_diff(report, 1).contains("CATEGORY TOTALS (all categories"),
  )
  assert_true(compare_metadata(b"bad", data) is Err(Baseline(_)))
  assert_true(compare_metadata(data, b"bad") is Err(Current(_)))
  match compare_metadata(data, head + b"\x00\x03\x05ab") {
    Err(Current(cause)) => assert_true(describe_error(cause).length() > 0)
    _ => fail("expected current outer error")
  }
  let options = parse_options([
    "moonsize", "after.wasm", "--diff-metadata", "--metadata", "--baseline", "before.wasm",
    "--metadata-json", "new.json", "--top", "1",
  ]).unwrap()
  assert_true(options.diff_metadata && options.metadata)
  assert_false(Options::default("a.wasm").diff_metadata)
  for
    args in [
      ["--diff-metadata"],
      ["--diff-metadata", "--baseline", ""],
      ["--metadata", "--baseline", "b.wasm"],
      ["--diff-metadata", "--baseline", "b.wasm", "--strict"],
      ["--diff-metadata", "--baseline", "b.wasm", "--compress"],
      ["--diff-metadata", "--baseline", "b.wasm", "--max-size", "1KB"],
      ["--diff-metadata", "--baseline", "b.wasm", "--diff-functions"],
      ["--diff-metadata", "--baseline", "b.wasm", "--html", "n.html"],
      ["--diff-metadata", "--baseline", "b.wasm", "--metadata-json", "n.txt"],
      ["--diff-metadata", "--baseline", "b.wasm", "--summary-json", "n.json"],
      ["--diff-metadata", "--baseline", "b.wasm", "--budget", "b.json"],
    ] {
    assert_true(parse_options(["moonsize", "missing.wasm"] + args) is Err(_))
  }
}
