///|
fn imports_diff_test_module(
  entries : Bytes,
  count : Int,
  wide? : Bool = false,
) -> Bytes raise {
  // Two valid () -> () types let type indices change without invalid fixtures.
  let prefix = b"\x00asm\x01\x00\x00\x00\x01\x07\x02\x60\x00\x00\x60\x00\x00"
  let payload = (if wide {
      Bytes::from_array([(count | 128).to_byte(), 0])
    } else {
      Bytes::from_array([count.to_byte()])
    }) +
    entries
  assert_true(payload.length() < 128)
  prefix +
  (if wide {
    b"\x02" +
    Bytes::from_array([(payload.length() | 128).to_byte(), 0]) +
    payload
  } else {
    imports_test_section(payload)
  })
}

///|
fn imports_diff_test_before_entries() -> Array[Bytes] raise {
  [
    imports_test_entry(b"env", b"same", b"\x00\x00"),
    imports_test_entry(b"env", b"same", b"\x00\x00"),
    imports_test_entry(b"env", b"grow", b"\x01\x70\x00\x00"),
    imports_test_entry(b"env", b"flip", b"\x00\x00"),
    imports_test_entry(b"a|b", b"c", b"\x00\x00"),
    imports_test_entry(b"a", b"b|c", b"\x00\x00"),
    imports_test_entry(b"", @utf8.encode("\n\"雪"), b"\x03\x7f\x00"),
    imports_test_entry(b"env", b"gone", b"\x03\x7e\x00"),
    imports_test_entry(b"env", b"stable", b"\x02\x00\x00"),
  ]
}

///|
fn imports_diff_test_join(entries : Array[Bytes]) -> Bytes {
  let mut data = b""
  for entry in entries {
    data = data + entry
  }
  data
}

///|
fn imports_diff_test_pair() -> (Bytes, Bytes) raise {
  let before = imports_diff_test_before_entries()
  let after = [
    before[4],
    imports_test_entry(b"env", b"same", b"\x00\x81\x00", wide=true),
    imports_test_entry(b"env", b"grow", b"\x01\x70\x01\x00\x01"),
    imports_test_entry(b"env", b"flip", b"\x03\x7f\x00"),
    before[5],
    imports_test_entry(b"env", b"grow", b"\x01\x6f\x00\x00"),
    imports_test_entry(b"", @utf8.encode("\n\"雪"), b"\x03\x7f\x01"),
    imports_test_entry(b"env", b"stable", b"\x02\x01\x00\x02"),
    imports_test_entry(b"env", b"fresh", b"\x04\x00\x00"),
  ]
  (
    imports_diff_test_module(imports_diff_test_join(before), 9),
    imports_diff_test_module(imports_diff_test_join(after), 9, wide=true),
  )
}

///|
fn imports_diff_test_compare(
  before : Bytes,
  after : Bytes,
) -> ImportsComparison raise {
  match compare_imports(before, after) {
    Ok(r) => r
    Err(e) => fail(describe_imports_comparison_error(e))
  }
}

///|
fn imports_diff_test_ledger(report : ImportsComparison) -> Unit raise {
  let c = report.counts
  assert_eq(c.baseline_entry_count, c.overlap_count + c.removed_count)
  assert_eq(c.current_entry_count, c.overlap_count + c.added_count)
  assert_eq(c.count_delta, c.added_count - c.removed_count)
  for s in [report.baseline.ledger, report.current.ledger, report.delta] {
    assert_eq(
      s.import_section_total_bytes,
      s.section_header_bytes + s.count_prefix_bytes + s.entry_bytes,
    )
    assert_eq(
      s.entry_bytes,
      s.module_name_encoding_bytes +
      s.field_name_encoding_bytes +
      s.descriptor_bytes,
    )
    assert_eq(
      s.module_name_encoding_bytes,
      s.module_length_prefix_bytes + s.module_utf8_bytes,
    )
    assert_eq(
      s.field_name_encoding_bytes,
      s.field_length_prefix_bytes + s.field_utf8_bytes,
    )
  }
  let mut b = 0
  let mut a = 0
  let mut delta = 0
  let mut overlap = 0
  let mut added = 0
  let mut removed = 0
  for g in report.groups {
    assert_eq(g.baseline_count, g.baseline_ordinals.length())
    assert_eq(g.current_count, g.current_ordinals.length())
    assert_eq(g.overlap_count, g.baseline_count.min(g.current_count))
    b += g.baseline_entry_bytes
    a += g.current_entry_bytes
    delta += g.entry_bytes_delta
    overlap += g.overlap_count
    added += g.added_count
    removed += g.removed_count
    for
      (ordinals, entries) in [
        (g.baseline_ordinals, report.baseline.entries),
        (g.current_ordinals, report.current.entries),
      ] {
      let mut previous = -1
      for ordinal in ordinals {
        assert_true(ordinal > previous)
        previous = ordinal
        assert_eq(entries[ordinal].module_name, g.module_name)
        assert_eq(entries[ordinal].field, g.field)
        assert_eq(entries[ordinal].kind, g.kind)
      }
    }
  }
  assert_eq(b, report.baseline.ledger.entry_bytes)
  assert_eq(a, report.current.ledger.entry_bytes)
  assert_eq(delta, report.delta.entry_bytes)
  assert_eq(overlap, c.overlap_count)
  assert_eq(added, c.added_count)
  assert_eq(removed, c.removed_count)
}

///|
test "imports-diff: structured keys, duplicate counts, kind changes, reorder and signed ledgers" {
  let (before, after) = imports_diff_test_pair()
  let report = imports_diff_test_compare(before, after)
  imports_diff_test_ledger(report)
  assert_true(report.inventory_changed)
  assert_eq(report.groups.length(), 10)
  assert_eq(report.counts, {
    baseline_entry_count: 9,
    current_entry_count: 9,
    overlap_count: 6,
    removed_count: 3,
    added_count: 3,
    count_delta: 0,
  })
  assert_eq(report.baseline.ledger.entry_bytes, 98)
  assert_eq(report.current.ledger.entry_bytes, 107)
  assert_eq(report.delta.import_section_total_bytes, 11)
  assert_eq(report.delta.section_header_bytes, 1)
  assert_eq(report.delta.count_prefix_bytes, 1)
  assert_eq(report.delta.entry_bytes, 9)
  assert_eq(report.groups[0].field, "grow")
  assert_eq(report.groups[0].status, "count_increased")
  assert_eq(report.groups[0].baseline_ordinals, [2])
  assert_eq(report.groups[0].current_ordinals, [2, 5])
  assert_eq(report.groups[1].field, "fresh")
  assert_eq(report.groups[2].field, "flip")
  assert_eq(report.groups[2].kind, "global")
  let mut separated = 0
  for g in report.groups {
    if (g.module_name == "a|b" && g.field == "c") ||
      (g.module_name == "a" && g.field == "b|c") {
      separated += 1
      assert_eq(g.status, "same_count")
      assert_eq(g.overlap_count, 1)
    }
    if g.field == "same" {
      assert_eq(g.status, "count_decreased")
      assert_eq(g.baseline_ordinals, [0, 1])
      assert_eq(g.current_ordinals, [1])
      assert_eq(g.removed_count, 1)
    }
  }
  assert_eq(separated, 2)
  let entries = imports_diff_test_before_entries()
  let reordered = imports_diff_test_module(
    imports_diff_test_join([
      entries[8],
      entries[6],
      entries[5],
      entries[4],
      entries[3],
      entries[2],
      entries[1],
      entries[0],
      entries[7],
    ]),
    9,
  )
  let reorder = imports_diff_test_compare(before, reordered)
  imports_diff_test_ledger(reorder)
  assert_false(reorder.inventory_changed)
  assert_eq(reorder.counts.overlap_count, 9)
  assert_eq(reorder.counts.added_count, 0)
  assert_eq(reorder.counts.removed_count, 0)
  let reverse = imports_diff_test_compare(after, before)
  imports_diff_test_ledger(reverse)
  assert_eq(reverse.delta.import_section_total_bytes, -11)
}

///|
test "imports-diff: type boundaries, empty-state bytes, complete JSON and Top scope" {
  let before = imports_diff_test_module(
    imports_test_entry(b"x", b"f", b"\x00\x00") +
    imports_test_entry(b"x", b"g", b"\x03\x7f\x00"),
    2,
  )
  let after = imports_diff_test_module(
    imports_test_entry(b"x", b"g", b"\x03\x7f\x01") +
    imports_test_entry(b"x", b"f", b"\x00\x01"),
    2,
  )
  let report = imports_diff_test_compare(before, after)
  imports_diff_test_ledger(report)
  assert_false(report.inventory_changed)
  assert_eq(report.groups.map(fn(g) { g.status }), ["same_count", "same_count"])
  assert_eq(report.baseline.entries[0].type_index, Some(0U))
  assert_eq(report.current.entries[1].type_index, Some(1U))
  assert_eq(report.baseline.entries[1].mutability, Some(0))
  assert_eq(report.current.entries[0].mutability, Some(1))
  let text = render_imports_diff(report, 0)
  assert_true(
    text.contains(
      "No changes to names, kinds or declaration counts; type compatibility is not evaluated.",
    ),
  )
  assert_true(text.contains("IMPORT GROUPS: showing 0 of 2"))
  let json = render_imports_diff_json(report)
  assert_true(json.contains("moonsize-imports-diff"))
  assert_true(json.contains("\"type_compatibility\": \"not_evaluated\""))
  assert_true(json.contains("\"type_index\": 1"))
  assert_true(json.contains("\"mutability\": 0"))
  assert_true(json.contains("\"mutability\": 1"))
  let empty = imports_diff_test_compare(
    b"\x00asm\x01\x00\x00\x00", b"\x00asm\x01\x00\x00\x00\x02\x01\x00",
  )
  imports_diff_test_ledger(empty)
  assert_false(empty.inventory_changed)
  assert_eq(empty.baseline.section, None)
  assert_eq(empty.current.section, Some({ offset: 8, size: 3, }))
  assert_eq(empty.delta.import_section_total_bytes, 3)
  assert_eq(empty.delta.entry_bytes, 0)
}

///|
test "imports-diff: side-specific original errors and independent CLI requirements" {
  let good = b"\x00asm\x01\x00\x00\x00"
  match compare_imports(b"bad!\x01\x00\x00\x00", good) {
    Err(ImportsBaselineError(BadMagic)) => ()
    _ => fail("expected original baseline magic error")
  }
  let unsupported = good + imports_test_section(b"\x01\x00\x00\x02\x04\x00")
  match compare_imports(good, unsupported) {
    Err(ImportsCurrentError(InvalidImportEncoding(offset, reason))) => {
      assert_eq(offset, 14)
      assert_true(reason.contains("unsupported memory64"))
    }
    _ => fail("expected original current memory64 error")
  }
  assert_true(
    describe_imports_comparison_error(
      ImportsBaselineError(UnexpectedEnd(18, 1)),
    ).contains("baseline: unexpected end of input at offset 18"),
  )
  let options = parse_options([
    "moonsize", "missing.wasm", "--baseline", "before.wasm", "--diff-imports", "--imports",
    "--imports-json", "new.json", "--top", "0",
  ]).unwrap()
  assert_true(options.imports && options.diff_imports)
  assert_eq(options.imports_json, Some("new.json"))
  assert_false(Options::default("x.wasm").diff_imports)
  for
    args in [
      ["--diff-imports"],
      ["--diff-imports", "--baseline", ""],
      ["--imports", "--baseline", "before.wasm"],
      ["--diff-imports", "--baseline", "b.wasm", "--strict"],
      ["--diff-imports", "--baseline", "b.wasm", "--metadata"],
      ["--diff-imports", "--baseline", "b.wasm", "--html", "new.html"],
    ] {
    assert_true(parse_options(["moonsize", "missing.wasm"] + args) is Err(_))
  }
}
