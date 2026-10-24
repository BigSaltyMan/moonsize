///|
fn data_duplicates_test_module(
  entries : Array[Bytes],
  wide? : Bool = false,
) -> Bytes raise {
  let count = entries.length()
  assert_true(count < 128)
  let mut payload = if wide {
    Bytes::from_array([(count | 128).to_byte(), 0])
  } else {
    Bytes::from_array([count.to_byte()])
  }
  for entry in entries {
    payload = payload + entry
  }
  assert_true(payload.length() < 128)
  let section = if wide {
    b"\x0b" +
    Bytes::from_array([(payload.length() | 128).to_byte(), 0]) +
    payload
  } else {
    duplicate_test_section(11, payload)
  }
  // Two local memories, matching DataCount, and then the data section.
  b"\x00asm\x01\x00\x00\x00\x05\x05\x02\x00\x01\x00\x01\x0c\x01" +
  Bytes::from_array([count.to_byte()]) +
  section
}

///|
fn data_duplicates_test_mixed() -> Bytes raise {
  data_duplicates_test_module(
    [
      b"\x00\x41\x0b\x0b\x03abc", // Implicit memory 0, immediate contains 0b.
       b"\x81\x00\x83\x00abc", // Passive, wide mode and payload-length fields.
       b"\x02\x81\x00\x41\x16\x0b\x03abc", // Explicit memory 1, wide index.
       b"\x01\x02xy", b"\x82\x00\x00\x41\x00\x0b\x02xy", // Explicit memory 0, wide mode.
       b"\x01\x03xyz", // Same payload length as abc, different bytes, singleton.
       b"\x01\x00", b"\x00\x41\x00\x0b\x80\x00", // Empty active payload with wide length.
    ],
    wide=true,
  )
}

///|
fn data_duplicates_test_inspect(data : Bytes) -> DuplicateDataReport raise {
  match inspect_duplicate_data(data) {
    Ok(r) => r
    Err(e) => fail(describe_error(e))
  }
}

///|
fn data_duplicates_test_ledger(
  report : DuplicateDataReport,
  data : Bytes,
) -> Unit raise {
  let s = report.summary
  assert_eq(s.segment_count, s.duplicate_member_count + s.singleton_count)
  assert_eq(
    s.total_payload_bytes,
    s.duplicate_member_payload_bytes + s.singleton_payload_bytes,
  )
  assert_eq(
    s.total_entry_encoded_bytes,
    s.total_payload_bytes + s.total_entry_metadata_bytes,
  )
  assert_eq(
    s.data_section_bytes,
    s.section_header_bytes + s.count_prefix_bytes + s.total_entry_encoded_bytes,
  )
  assert_eq(
    s.total_entry_encoded_bytes,
    s.duplicate_member_encoded_bytes + s.singleton_encoded_bytes,
  )
  assert_eq(
    s.total_entry_metadata_bytes,
    s.duplicate_member_metadata_bytes + s.singleton_metadata_bytes,
  )
  let mut payload = 0
  let mut encoded = 0
  let mut metadata = 0
  let mut members = 0
  let seen : Map[Int, Bool] = Map([])
  for group in report.groups {
    assert_true(group.member_count >= 2)
    assert_eq(group.id, group.member_indices[0])
    assert_eq(group.member_count, group.member_indices.length())
    assert_eq(
      group.member_payload_bytes,
      group.payload_size * group.member_count,
    )
    assert_eq(
      group.member_encoded_bytes,
      group.member_payload_bytes + group.member_metadata_bytes,
    )
    let mut previous = -1
    let mut group_encoded = 0
    for index in group.member_indices {
      assert_true(index > previous)
      previous = index
      assert_false(seen.get(index) is Some(_))
      seen.set(index, true)
      let entry = report.data_segments.entries[index]
      assert_eq(entry.index, index)
      assert_eq(entry.payload.size, group.payload_size)
      assert_true(
        Reader::new_range(data, entry.payload.offset, entry.payload.size)
        is Ok(_),
      )
      group_encoded += entry.encoding.size
    }
    assert_eq(group_encoded, group.member_encoded_bytes)
    payload += group.member_payload_bytes
    encoded += group.member_encoded_bytes
    metadata += group.member_metadata_bytes
    members += group.member_count
  }
  assert_eq(members, s.duplicate_member_count)
  assert_eq(payload, s.duplicate_member_payload_bytes)
  assert_eq(encoded, s.duplicate_member_encoded_bytes)
  assert_eq(metadata, s.duplicate_member_metadata_bytes)
  assert_eq(report.data_segments.payload_size, s.total_payload_bytes)
  assert_eq(
    report.data_segments.entry_metadata_size,
    s.total_entry_metadata_bytes,
  )
}

///|
test "data-duplicates: three encodings, exact payload groups, retained member metadata and byte ledger" {
  let data = data_duplicates_test_mixed()
  let report = data_duplicates_test_inspect(data)
  data_duplicates_test_ledger(report, data)
  let s = report.summary
  assert_eq(data.length(), 74)
  assert_eq(s.segment_count, 8)
  assert_eq(s.duplicate_group_count, 3)
  assert_eq(s.duplicate_member_count, 7)
  assert_eq(s.singleton_count, 1)
  assert_eq(s.total_payload_bytes, 16)
  assert_eq(s.duplicate_member_payload_bytes, 13)
  assert_eq(s.singleton_payload_bytes, 3)
  assert_eq(s.total_entry_encoded_bytes, 51)
  assert_eq(s.total_entry_metadata_bytes, 35)
  assert_eq(s.duplicate_member_encoded_bytes, 46)
  assert_eq(s.data_section_bytes, 56)
  assert_eq(report.data_segments.datacount, Some(8))
  assert_eq(report.groups.map(fn(g) { g.id }), [0, 3, 6])
  assert_eq(report.groups[0].member_indices, [0, 1, 2])
  assert_eq(report.groups[1].member_indices, [3, 4])
  assert_eq(report.groups[2].member_indices, [6, 7])
  assert_eq(report.groups[2].payload_size, 0)
  let entries = report.data_segments.entries
  assert_eq(entries[0].memory_index, Some(0))
  assert_eq(entries[1].mode, Passive)
  assert_eq(entries[1].offset_expression, None)
  assert_eq(entries[1].mode_size, 2)
  assert_eq(entries[1].payload_length_size, 2)
  assert_eq(entries[2].memory_index, Some(1))
  assert_eq(entries[2].memory_index_size, 2)
  assert_eq(entries[4].mode_size, 2)
  assert_eq(entries[0].offset_expression, Some({ offset: 24, size: 3, }))
  assert_eq(entries[2].offset_expression, Some({ offset: 41, size: 3, }))
  assert_eq(entries[7].payload, { offset: 74, size: 0, })
  assert_true(render_duplicate_data(report, 3).contains("Group #6;"))
}

///|
test "data-duplicates: absent, empty, singleton, zero-byte groups, stable ties and complete JSON" {
  let absent_data = b"\x00asm\x01\x00\x00\x00"
  let absent = data_duplicates_test_inspect(absent_data)
  data_duplicates_test_ledger(absent, absent_data)
  assert_eq(absent.summary.data_section_bytes, 0)
  assert_true(absent.data_segments.section is None)
  assert_true(
    render_duplicate_data(absent, 1).contains(
      "No identical data payload groups found.",
    ),
  )
  let empty_data = b"\x00asm\x01\x00\x00\x00\x0c\x01\x00\x0b\x01\x00"
  let empty = data_duplicates_test_inspect(empty_data)
  data_duplicates_test_ledger(empty, empty_data)
  assert_eq(empty.summary.data_section_bytes, 3)
  assert_eq(empty.summary.segment_count, 0)
  let singleton_data = data_duplicates_test_module([b"\x01\x01a"])
  let singleton = data_duplicates_test_inspect(singleton_data)
  assert_eq(singleton.groups.length(), 0)
  assert_eq(singleton.summary.singleton_count, 1)
  let entries : Array[Bytes] = []
  for _ in 0..<21 {
    entries.push(b"\x01\x00")
  }
  let zeros_data = data_duplicates_test_module(entries)
  let zeros = data_duplicates_test_inspect(zeros_data)
  data_duplicates_test_ledger(zeros, zeros_data)
  assert_eq(zeros.groups.length(), 1)
  assert_eq(zeros.groups[0].member_count, 21)
  assert_eq(zeros.groups[0].member_payload_bytes, 0)
  assert_eq(zeros.groups[0].member_encoded_bytes, 42)
  assert_true(
    render_duplicate_data(zeros, 1).contains("Members: showing 20 of 21"),
  )
  assert_true(render_duplicate_data_json(zeros).contains("\"index\": 20"))
  let ties = data_duplicates_test_inspect(
    data_duplicates_test_module([
      b"\x01\x02aa", b"\x01\x02aa", b"\x01\x02bb", b"\x01\x02bb", b"\x01\x01c", b"\x01\x01c",
      b"\x01\x01c", b"\x01\x01c",
    ]),
  )
  assert_eq(ties.groups.map(fn(g) { g.id }), [0, 2, 4])
  assert_eq(ties.groups.map(fn(g) { g.member_payload_bytes }), [4, 4, 4])
  let full = data_duplicates_test_inspect(data_duplicates_test_mixed())
  assert_true(
    render_duplicate_data(full, 1).contains("DUPLICATE GROUPS: showing 1 of 3"),
  )
  assert_true(
    render_duplicate_data_json(full).contains("moonsize-data-duplicates"),
  )
  assert_eq(full.data_segments.entries.length(), 8)
  let options = parse_options([
    "moonsize", "missing.wasm", "--data-duplicates-json", "new.json", "--top", "0",
  ]).unwrap()
  assert_true(options.data_duplicates)
  assert_eq(options.data_duplicates_json, Some("new.json"))
  assert_false(Options::default("x.wasm").data_duplicates)
  assert_eq(Options::default("x.wasm").data_duplicates_json, None)
  for
    args in [
      ["--data-duplicates-json"],
      ["--data-duplicates-json", "bad.txt"],
      ["--data-duplicates", "--strict"],
      ["--data-duplicates", "--duplicates"],
      ["--data-duplicates", "--data-json", "n.json"],
      ["--data-duplicates", "--baseline", "b.wasm"],
      ["--data-duplicates", "--html", "n.html"],
    ] {
    assert_true(parse_options(["moonsize", "missing.wasm"] + args) is Err(_))
  }
}

///|
test "data-duplicates: private collision confirmation and original structural error propagation" {
  let data = data_duplicates_test_module([
    b"\x01\x03abc", b"\x01\x03abc", b"\x01\x03xyz", b"\x01\x03xyz",
  ])
  let source = inspect_data_segments(data).unwrap()
  let buckets : Array[DuplicateDataBucket] = []
  let by_digest : Map[DuplicateDataKey, Array[Int]] = Map([])
  for entry in source.entries {
    let reader = Reader::new_range(
      data,
      entry.payload.offset,
      entry.payload.size,
    ).unwrap()
    let bytes = reader.read_bytes(entry.payload.size).unwrap()
    assert_true(
      duplicate_data_insert(
        buckets, by_digest, "forced-collision", bytes, entry,
      )
      is Ok(_),
    )
  }
  let groups = duplicate_data_groups(buckets)
  assert_eq(groups.length(), 2)
  assert_eq(groups[0].sha256, groups[1].sha256)
  assert_eq(groups[0].member_indices, [0, 1])
  assert_eq(groups[1].member_indices, [2, 3])
  assert_eq(groups[0].id, 0)
  assert_eq(groups[1].id, 2)
  assert_true(
    duplicate_data_add(2147483647, 1, 8) is Err(ValueOutOfRange(8, 2147483648U)),
  )
  match
    inspect_duplicate_data(
      b"\x00asm\x01\x00\x00\x00\x0c\x01\x02\x0b\x03\x01\x01\x00",
    ) {
    Err(InvalidDataEncoding(offset, reason)) => {
      assert_eq(offset, 10)
      assert_true(
        reason.contains("datacount mismatch: 2 declared, 1 data entries"),
      )
    }
    _ => fail("expected the original DataCount mismatch")
  }
}
