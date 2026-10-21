///|
fn data_diff_fixture(entries : Array[Bytes]) -> Bytes {
  // Tiny combined fixtures only; larger integer encodings have their own tests.
  let mut payload = Bytes::from_array([entries.length().to_byte()])
  for entry in entries {
    payload += entry
  }
  b"\x00asm\x01\x00\x00\x00\x05\x03\x01\x00\x01\x0b" +
  Bytes::from_array([payload.length().to_byte()]) +
  payload
}

///|
fn data_compared(before : Bytes, after : Bytes) -> DataSegmentsComparison raise {
  match compare_data_segments(before, after) {
    Ok(report) => report
    Err(Baseline(error)) => fail("baseline: " + describe_error(error))
    Err(Current(error)) => fail("current: " + describe_error(error))
  }
}

///|
fn assert_data_diff_ledger(report : DataSegmentsComparison) -> Unit raise {
  assert_data_ledger(report.baseline)
  assert_data_ledger(report.current)
  assert_eq(
    report.delta.section_size,
    report.delta.payload_size +
    report.delta.entry_metadata_size +
    report.delta.section_overhead_size,
  )
  let mut payload = 0
  let mut metadata = 0
  let mut encoded = 0
  for group in report.groups {
    payload += group.delta.payload_size
    metadata += group.delta.metadata_size
    encoded += group.delta.encoded_size
    assert_eq(group.baseline.count, group.baseline_indices.length())
    assert_eq(group.current.count, group.current_indices.length())
    assert_eq(group.delta.count, group.current.count - group.baseline.count)
    for side in [group.baseline, group.current] {
      assert_eq(side.payload_size, side.count * group.payload_length)
      assert_eq(side.encoded_size, side.payload_size + side.metadata_size)
    }
  }
  assert_eq(payload, report.delta.payload_size)
  assert_eq(metadata, report.delta.entry_metadata_size)
  assert_eq(encoded, payload + metadata)
}

///|
test "data content self and reorder comparisons have no fictional additions" {
  let before = data_diff_fixture([b"\x01\x03abc", b"\x01\x00", b"\x01\x03abc"])
  let after = data_diff_fixture([b"\x01\x03abc", b"\x01\x03abc", b"\x01\x00"])
  for current in [before, after] {
    let report = data_compared(before, current)
    assert_eq(report.groups.length(), 2)
    for group in report.groups {
      assert_eq(group.kind, SharedPayload)
      assert_eq(group.delta, {
        count: 0,
        payload_size: 0,
        encoded_size: 0,
        metadata_size: 0,
      })
    }
    assert_eq(report.delta.section_size, 0)
    assert_data_diff_ledger(report)
  }
  let report = data_compared(before, after)
  assert_eq(report.groups[0].baseline_indices, [0, 2])
  assert_eq(report.groups[0].current_indices, [0, 1])
  assert_false(report.baseline_sha256 == report.current_sha256)
  assert_eq(
    data_compared(before, before).baseline_sha256,
    data_compared(before, before).current_sha256,
  )
}

///|
test "data content removing one duplicate subtracts exactly one occurrence" {
  let before = data_diff_fixture([b"\x01\x03abc", b"\x01\x03abc", b"\x01\x00"])
  let after = data_diff_fixture([b"\x01\x00", b"\x01\x03abc"])
  let report = data_compared(before, after)
  let group = report.groups[0]
  assert_eq(group.kind, SharedPayload)
  assert_eq(group.baseline.count, 2)
  assert_eq(group.current.count, 1)
  assert_eq(group.delta, {
    count: -1,
    payload_size: -3,
    encoded_size: -5,
    metadata_size: -2,
  })
  assert_eq(report.delta.section_size, -5)
  assert_data_diff_ledger(report)
  let reverse = data_compared(after, before)
  assert_eq(reverse.delta.section_size, 5)
  assert_data_diff_ledger(reverse)
}

///|
test "data content shared payload preserves differing initialization and widths" {
  let before = data_diff_fixture([b"\x00\x41\x00\x0b\x03abc"])
  let after = data_diff_fixture([b"\x81\x00\x83\x00abc"])
  let report = data_compared(before, after)
  assert_eq(report.groups[0].kind, SharedPayload)
  assert_eq(report.groups[0].delta.payload_size, 0)
  assert_eq(report.groups[0].delta.metadata_size, -1)
  assert_eq(report.baseline.entries[0].mode, Active)
  assert_eq(report.current.entries[0].mode, Passive)
  assert_true(report.baseline.entries[0].offset_expression is Some(_))
  assert_eq(report.current.entries[0].offset_expression, None)
  assert_eq(report.current.entries[0].mode_size, 2)
  assert_data_diff_ledger(report)
}

///|
test "data content changes are exclusive groups not modified entry identities" {
  let before = data_diff_fixture([b"\x01\x03abc", b"\x01\x00"])
  let after = data_diff_fixture([b"\x01\x03xyz", b"\x01\x00"])
  let report = data_compared(before, after)
  assert_eq(report.groups.length(), 3)
  assert_eq(report.groups[0].kind, BaselineOnly)
  assert_eq(report.groups[1].kind, SharedPayload)
  assert_eq(report.groups[2].kind, CurrentOnly)
  assert_eq(report.delta.section_size, 0)
  assert_data_diff_ledger(report)
  let ranked = ranked_data_groups(report)
  assert_eq(ranked[0].delta.encoded_size, 5) // xyz hash sorts before abc.
  assert_eq(ranked[1].delta.encoded_size, -5)
  let text = render_data_segments_diff(report, "before", "after", 1)
  assert_true(text.contains("Showing 1 of 3 content groups"))
  assert_true(text.contains("not source or stable entry identities"))
  assert_true(
    text.contains("not predict recompiled or whole-file gzip savings"),
  )
  assert_eq(report.groups[0].id, 0) // Ranking must not mutate report order.
}

///|
test "data content missing empty sections and side errors remain distinct" {
  let absent = b"\x00asm\x01\x00\x00\x00"
  let empty = absent + b"\x0c\x01\x00\x0b\x01\x00"
  let report = data_compared(absent, empty)
  assert_true(report.baseline.section is None)
  assert_true(report.current.section is Some(_))
  assert_eq(report.current.datacount, Some(0))
  assert_eq(report.delta, {
    section_size: 3,
    payload_size: 0,
    entry_metadata_size: 0,
    section_overhead_size: 3,
  })
  assert_data_diff_ledger(report)
  let payload = data_compared(empty, data_diff_fixture([b"\x01\x00"]))
  assert_eq(payload.groups[0].payload_length, 0)
  assert_eq(payload.groups[0].kind, CurrentOnly)
  assert_eq(payload.delta.entry_metadata_size, 2)
  assert_data_diff_ledger(payload)
  let bad = absent + b"\x0b\x02\x01\x03"
  match compare_data_segments(bad, absent) {
    Err(Baseline(InvalidDataEncoding(11, _))) => ()
    _ => fail("expected baseline encoding error")
  }
  match compare_data_segments(absent, bad) {
    Err(Current(InvalidDataEncoding(11, _))) => ()
    _ => fail("expected current encoding error")
  }
}

///|
test "data content byte equality splits collisions without a public hash switch" {
  // Exercise the actual membership predicate used after digest lookup.
  assert_true(data_payload_equal(b"abc"[:], b"abc"[:]))
  assert_false(data_payload_equal(b"abc"[:], b"abd"[:]))
  assert_false(data_payload_equal(b"abc"[:], b"ab"[:]))
}
