///|
fn exports_diff_test_data(
  rows : Array[(Bytes, Bytes)],
  wide? : Bool = false,
) -> Bytes raise {
  assert_true(rows.length() < 128)
  let count = if wide {
    Bytes::from_array([(rows.length() | 128).to_byte(), 0])
  } else {
    Bytes::from_array([rows.length().to_byte()])
  }
  let mut payload = count
  for (name, descriptor) in rows {
    payload += exports_test_entry(name, descriptor, wide~)
  }
  assert_true(payload.length() < 128)
  let head = b"\x00asm\x01\x00\x00\x00"
  if wide {
    head +
    b"\x07" +
    Bytes::from_array([(payload.length() | 128).to_byte(), 0]) +
    payload
  } else {
    head + duplicate_test_section(7, payload)
  }
}

///|
fn exports_diff_test_compare(
  before : Bytes,
  after : Bytes,
) -> ExportsComparison raise {
  match compare_exports(before, after) {
    Ok(report) => report
    Err(Baseline(e)) => fail("baseline: " + describe_error(e))
    Err(Current(e)) => fail("current: " + describe_error(e))
  }
}

///|
fn exports_diff_test_ledger(r : ExportsComparison) -> Unit raise {
  let c = r.counts
  assert_eq(
    r.baseline.summary.export_count,
    c.removed_count + c.kind_changed_count + c.same_kind_count,
  )
  assert_eq(
    r.current.summary.export_count,
    c.added_count + c.kind_changed_count + c.same_kind_count,
  )
  assert_eq(r.rows.length(), c.row_count)
  assert_eq(
    c.row_count,
    c.added_count + c.removed_count + c.kind_changed_count + c.same_kind_count,
  )
  let d = r.delta
  assert_eq(
    d.export_section_bytes,
    d.section_header_bytes + d.count_prefix_bytes + d.declaration_bytes,
  )
  assert_eq(d.declaration_bytes, d.name_encoding_bytes + d.descriptor_bytes)
  assert_eq(
    d.name_encoding_bytes,
    d.name_length_prefix_bytes + d.name_utf8_bytes,
  )
  assert_eq(d.descriptor_bytes, d.kind_bytes + d.target_index_prefix_bytes)
  let mut row_bytes = 0
  for row in r.rows {
    let before = row.baseline.map(fn(e) { e.encoding.size }).unwrap_or(0)
    let after = row.current.map(fn(e) { e.encoding.size }).unwrap_or(0)
    assert_eq(row.declaration_bytes_delta, after - before)
    row_bytes += row.declaration_bytes_delta
  }
  assert_eq(row_bytes, d.declaration_bytes)
  assert_eq(
    d.declaration_bytes,
    r.current.ledger.declaration_bytes - r.baseline.ledger.declaration_bytes,
  )
  assert_eq(
    r.baseline.file_size,
    r.baseline_non_export_bytes + r.baseline.ledger.export_section_bytes,
  )
  assert_eq(
    r.current.file_size,
    r.current_non_export_bytes + r.current.ledger.export_section_bytes,
  )
  assert_eq(
    r.delta_file_bytes,
    d.export_section_bytes + r.delta_non_export_bytes,
  )
}

///|
test "exports-diff: four states, exact names, alias inventories and closed ledgers" {
  let special = @utf8.encode("雪\"\n")
  let before = exports_diff_test_data([
    (b"", b"\x00\x00"),
    (b"removed", b"\x00\x00"),
    (b"switch", b"\x00\x00"),
    (special, b"\x00\x00"),
    (b"stable", b"\x01\x00"),
  ])
  let after = exports_diff_test_data([
    (b"", b"\x00\x01"),
    (b"new", b"\x00\x01"),
    (b"switch", b"\x03\x00"),
    (special, b"\x00\x01"),
    (b"stable", b"\x01\x00"),
  ])
  let r = exports_diff_test_compare(before, after)
  exports_diff_test_ledger(r)
  assert_eq(r.counts, {
    added_count: 1,
    removed_count: 1,
    kind_changed_count: 1,
    same_kind_count: 3,
    row_count: 6,
  })
  assert_eq(r.rows.map(fn(row) { row.status }), [
    "removed", "kind_changed", "added", "same_kind", "same_kind", "same_kind",
  ])
  assert_eq(r.rows[0].current.map(fn(e) { e.name }), None)
  assert_eq(r.rows[1].name, "switch")
  assert_eq(r.rows[1].baseline.map(fn(e) { e.target_index }), Some(0U))
  assert_eq(r.rows[1].current.map(fn(e) { e.target_index }), Some(0U))
  assert_eq(r.rows[1].target_index_changed, None)
  assert_eq(r.baseline.targets[0].entry_ordinals, [0, 1, 2, 3])
  assert_eq(r.current.targets[0].entry_ordinals, [0, 1, 3])
  assert_eq(r.baseline.entries[3].name, "雪\"\n")
  assert_eq(r.current.entries[0].name, "")
  let root = json_object(@json.parse(render_exports_diff_json(r)))
  assert_eq(
    root.get("baseline"),
    Some(@json.parse(render_exports_json(r.baseline))),
  )
  assert_eq(
    root.get("current"),
    Some(@json.parse(render_exports_json(r.current))),
  )
  assert_eq(json_array(root.get("rows").unwrap()).length(), 6)
  let rows = json_array(root.get("rows").unwrap())
  assert_eq(json_object(rows[0]).get("current"), Some(Json::null()))
  assert_eq(json_object(rows[2]).get("baseline"), Some(Json::null()))
  assert_true(
    render_exports_diff(r, 20).contains(Json::string("雪\"\n").stringify()),
  )
  exports_diff_test_ledger(exports_diff_test_compare(after, before))
}

///|
test "exports-diff: full UInt numeric changes, same-kind widths and no compatibility verdict" {
  // Structural fixtures only: out-of-range targets are not claimed V8-valid.
  let before = exports_diff_test_data([
    (b"renumber", b"\x00\xff\xff\xff\xff\x0f"),
    (b"switch", b"\x00\xff\xff\xff\xff\x0f"),
    (b"stable", b"\x00\x00"),
  ])
  let after = exports_diff_test_data(
    [
      (b"renumber", b"\x00\x80\x80\x80\x80\x08"),
      (b"switch", b"\x03\xff\xff\xff\xff\x0f"),
      (b"stable", b"\x00\x80\x00"),
    ],
    wide=true,
  )
  let r = exports_diff_test_compare(before, after)
  exports_diff_test_ledger(r)
  assert_eq(r.counts.same_kind_count, 2)
  assert_eq(r.counts.kind_changed_count, 1)
  assert_eq(r.rows[0].name, "switch")
  assert_eq(r.rows[0].target_index_changed, None)
  let renumber = r.rows.filter(fn(row) { row.name == "renumber" })[0]
  assert_eq(renumber.status, "same_kind")
  assert_eq(renumber.target_index_changed, Some(true))
  assert_eq(renumber.baseline.map(fn(e) { e.target_index }), Some(4294967295U))
  assert_eq(renumber.current.map(fn(e) { e.target_index }), Some(2147483648U))
  let stable = r.rows.filter(fn(row) { row.name == "stable" })[0]
  assert_eq(stable.target_index_changed, Some(false))
  assert_eq(stable.declaration_bytes_delta, 2)
  assert_eq(r.delta.declaration_bytes, 4)
  assert_eq(r.delta.name_encoding_bytes, 3)
  assert_eq(r.delta.target_index_prefix_bytes, 1)
  assert_eq(r.delta.export_section_bytes, 6)
  let text = render_exports_diff(r, 20)
  assert_true(text.contains("4294967295"))
  assert_false(text.contains("compatible"))
  assert_false(text.contains("unchanged"))
  assert_false(text.contains("breaking"))
}

///|
test "exports-diff: absent versus empty, lexical order, full JSON, side errors and mode grammar" {
  let head = b"\x00asm\x01\x00\x00\x00"
  let empty = head + duplicate_test_section(7, b"\x00")
  let r = exports_diff_test_compare(head, empty)
  exports_diff_test_ledger(r)
  assert_eq(r.counts.row_count, 0)
  assert_eq(r.delta.export_section_bytes, 3)
  assert_eq(r.delta.declaration_bytes, 0)
  assert_eq(r.delta_file_bytes, 3)
  assert_eq(r.baseline.section, None)
  assert_eq(r.current.section, Some({ offset: 8, size: 3, }))
  let data = exports_diff_test_data([
    (b"z", b"\x00\x00"),
    (b"aa", b"\x00\x00"),
    (b"A", b"\x00\x00"),
    (b" a ", b"\x00\x00"),
  ])
  let same = exports_diff_test_compare(data, data)
  assert_eq(same.rows.map(fn(row) { row.name }), [" a ", "A", "aa", "z"])
  assert_eq(same.counts.same_kind_count, 4)
  assert_true(render_exports_diff(same, 1).contains("NAMES: showing 1 of 4"))
  let json = render_exports_diff_json(same)
  assert_eq(
    json,
    render_exports_diff_json(exports_diff_test_compare(data, data)),
  )
  let root = json_object(@json.parse(json))
  assert_eq(root.get("format"), Some(Json::string("moonsize-exports-diff")))
  assert_eq(json_array(root.get("rows").unwrap()).length(), 4)
  let duplicate = head +
    duplicate_test_section(7, b"\x02\x01x\x00\x00\x01x\x01\x00")
  match compare_exports(duplicate, data) {
    Err(Baseline(InvalidExportEncoding(15, reason))) =>
      assert_true(reason.contains("first declaration at file offset 11"))
    _ => fail("expected original baseline duplicate-name cause")
  }
  assert_true(compare_exports(data, b"nonsense") is Err(Current(BadMagic)))
  let options = parse_options([
    "moonsize", "after.wasm", "--diff-exports", "--exports", "--baseline", "before.wasm",
    "--exports-json", "n.json",
  ]).unwrap()
  assert_true(options.exports && options.diff_exports)
  assert_false(Options::default("x").diff_exports)
  for
    args in [
      ["--diff-exports"],
      ["--diff-exports", "--baseline", ""],
      ["--exports", "--baseline", "b.wasm"],
      ["--diff-exports", "--baseline", "b.wasm", "--strict"],
      ["--diff-exports", "--baseline", "b.wasm", "--max-size", "1KB"],
      ["--diff-exports", "--baseline", "b.wasm", "--compress"],
      ["--diff-exports", "--baseline", "b.wasm", "--html", "n.html"],
      ["--diff-exports", "--baseline", "b.wasm", "--budget", "b.json"],
      ["--diff-exports", "--baseline", "b.wasm", "--entrypoints"],
      ["--diff-exports", "--baseline", "b.wasm", "--imports"],
      ["--diff-exports", "--baseline", "b.wasm", "--summary-json", "n.json"],
    ] {
    assert_true(parse_options(["moonsize", "missing.wasm"] + args) is Err(_))
  }
}
