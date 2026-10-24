///|
// Tiny fixtures only; reuse the existing small section encoder. Wide prefixes
// here are explicit valid non-shortest encodings, not an integer test matrix.
fn metadata_test_custom(
  name : Bytes,
  content : Bytes,
  wide? : Bool = false,
) -> Bytes raise {
  assert_true(name.length() < 128)
  let prefix = if wide {
    Bytes::from_array([(name.length() | 128).to_byte(), 0])
  } else {
    Bytes::from_array([name.length().to_byte()])
  }
  let payload = prefix + name + content
  assert_true(payload.length() < 128)
  if wide {
    b"\x00" +
    Bytes::from_array([(payload.length() | 128).to_byte(), 0]) +
    payload
  } else {
    duplicate_test_section(0, payload)
  }
}

///|
fn metadata_test_valid() -> Bytes raise {
  // First map: non-shortest count, duplicate index/name, full u32 index and a
  // two-byte length for a three-byte UTF-8 name. Header size is also non-shortest.
  let records = b"\x83\x00\x01\x03dup\x01\x03dup\xff\xff\xff\xff\x0f\x83\x00" +
    @utf8.encode("雪")
  let first = b"\x01" +
    Bytes::from_array([(records.length() | 128).to_byte(), 0]) +
    records
  b"\x00asm\x01\x00\x00\x00" +
  metadata_test_custom(b"name", first, wide=true) +
  metadata_test_custom(b".debug_info", b"\x01\x02\x03") +
  metadata_test_custom(b"producers", b"\x09\x08") +
  metadata_test_custom(
    b"name",
    duplicate_test_section(1, b"\x01\x02\x0blonger-name") +
    duplicate_test_section(42, b"\xff\x80"),
  ) +
  metadata_test_custom(@utf8.encode("说明"), b"\x07") +
  metadata_test_custom(@utf8.encode("说明"), b"") +
  metadata_test_custom(b"", b"\x01")
}

///|
fn metadata_test_partial() -> Bytes raise {
  let first = duplicate_test_section(1, b"\x02\x01\x02ok\x02\x03x") +
    duplicate_test_section(7, b"\x01") +
    duplicate_test_section(1, b"\x02\x03\x01\xff\x04\x01z") +
    duplicate_test_section(1, b"\x80") +
    duplicate_test_section(1, b"\x00\x7f") +
    b"\x01\x05\x00"
  b"\x00asm\x01\x00\x00\x00" +
  metadata_test_custom(b"name", first) +
  metadata_test_custom(
    b"name",
    duplicate_test_section(1, b"\x01\x05\x05later") + b"\x01\x80",
  ) +
  metadata_test_custom(b"name", duplicate_test_section(1, b"\x01\x06\x04done")) +
  metadata_test_custom(b".debug_\xff", b"") +
  metadata_test_custom(@utf8.encode(".debug_�"), b"")
}

///|
fn metadata_test_inspect(data : Bytes) -> MetadataReport raise {
  match inspect_metadata(data) {
    Ok(r) => r
    Err(e) => fail(describe_error(e))
  }
}

///|
fn metadata_test_ledger(report : MetadataReport, data : Bytes) -> Unit raise {
  let s = report.summary
  assert_true(report.byte_ledger_complete)
  assert_eq(
    s.custom_bytes,
    s.section_header_bytes + s.custom_name_encoding_bytes + s.content_bytes,
  )
  assert_eq(
    s.name_content_bytes,
    s.name_subsection_bytes + s.unbounded_name_tail_bytes,
  )
  assert_eq(
    s.function_name_payload_bytes,
    s.function_name_count_prefix_bytes +
    s.parsed_function_record_bytes +
    s.function_name_unparsed_bytes,
  )
  assert_eq(
    s.parsed_function_record_bytes,
    s.function_index_prefix_bytes +
    s.function_name_length_prefix_bytes +
    s.function_name_utf8_bytes,
  )
  let mut categories = 0
  let mut groups = 0
  let mut customs = 0
  for c in report.categories {
    categories += c.total_bytes
  }
  for g in report.name_groups {
    groups += g.total_bytes
  }
  assert_eq(categories, s.custom_bytes)
  assert_eq(groups, s.custom_bytes)
  for c in report.customs {
    customs += c.encoding.size
    assert_eq(
      c.encoding.size,
      c.section_header_bytes + c.name_encoding.size + c.content.size,
    )
    assert_eq(
      c.name_encoding.size,
      c.name_length_prefix_bytes + c.name_bytes.size,
    )
    assert_eq(
      c.name_encoding.offset,
      c.encoding.offset + c.section_header_bytes,
    )
    assert_eq(
      c.content.offset + c.content.size,
      c.encoding.offset + c.encoding.size,
    )
    assert_true(
      Reader::new_range(data, c.encoding.offset, c.encoding.size) is Ok(_),
    )
    if c.category == "name" {
      let mut bounded = 0
      for sub in report.subsections {
        if sub.custom_ordinal == c.ordinal {
          bounded += sub.encoding.size
        }
      }
      assert_eq(bounded, c.name_subsection_bytes)
      assert_eq(
        c.content.size,
        bounded + c.unbounded_tail.map(fn(r) { r.size }).unwrap_or(0),
      )
    }
  }
  assert_eq(customs, s.custom_bytes)
  for sub in report.subsections {
    assert_eq(sub.encoding.size, sub.header_bytes + sub.payload.size)
    assert_true(
      Reader::new_range(data, sub.payload.offset, sub.payload.size) is Ok(_),
    )
    if sub.id == 1 {
      let mut parsed = 0
      for r in report.function_names {
        if r.custom_ordinal == sub.custom_ordinal &&
          r.subsection_ordinal == sub.ordinal {
          parsed += r.encoding.size
        }
      }
      assert_eq(parsed, sub.parsed_record_bytes)
      assert_eq(
        sub.payload.size,
        sub.count_prefix_bytes +
        parsed +
        sub.unparsed.map(fn(r) { r.size }).unwrap_or(0),
      )
    }
  }
  for r in report.function_names {
    assert_eq(
      r.encoding.size,
      r.index_prefix_bytes + r.name_length_prefix_bytes + r.name_bytes.size,
    )
    assert_eq(
      r.name_bytes.offset + r.name_bytes.size,
      r.encoding.offset + r.encoding.size,
    )
    assert_true(
      Reader::new_range(data, r.encoding.offset, r.encoding.size) is Ok(_),
    )
  }
}

///|
test "metadata: physical instances, UTF-8, wide prefixes, repeated records and closed ledgers" {
  let data = metadata_test_valid()
  let report = metadata_test_inspect(data)
  metadata_test_ledger(report, data)
  assert_eq(report.custom_name_status, "complete")
  assert_eq(report.name_details_status, "complete")
  assert_eq(report.summary.custom_count, 7)
  assert_eq(report.summary.name_custom_count, 2)
  assert_eq(report.summary.custom_bytes, 115)
  assert_eq(report.summary.name_content_bytes, 45)
  assert_eq(report.summary.parsed_function_record_bytes, 33)
  assert_eq(report.summary.function_name_payload_bytes, 36)
  assert_eq(report.customs.map(fn(c) { c.ordinal }), [0, 3, 1, 2, 4, 5, 6])
  assert_eq(report.function_names.map(fn(r) { r.encoding.size }), [13, 10, 5, 5])
  assert_eq(report.function_names[1].function_index, 4294967295U)
  assert_eq(report.function_names[1].index_prefix_bytes, 5)
  assert_eq(report.function_names[1].name_length_prefix_bytes, 2)
  assert_eq(report.function_names[1].name, Some("雪"))
  assert_eq(report.function_names[2].function_index, 1U)
  assert_eq(report.function_names[3].function_index, 1U)
  assert_true(
    report.function_names[2].encoding.offset <
    report.function_names[3].encoding.offset,
  )
  assert_eq(report.function_names[2].name, report.function_names[3].name)
  assert_eq(report.customs[0].section_header_bytes, 3)
  assert_eq(report.customs[0].name_length_prefix_bytes, 2)
  assert_eq(report.customs[4].name_bytes.size, 6) // Two characters, six UTF-8 bytes.
  assert_eq(report.name_groups[0].custom_ordinals, [0, 3])
  assert_eq(report.name_groups[1].name, Some("说明"))
  assert_eq(report.name_groups[1].custom_ordinals, [4, 5])
  assert_eq(report.subsections[0].header_bytes, 3)
  assert_eq(report.subsections[0].count_prefix_bytes, 2)
  assert_eq(report.subsections[2].status, "opaque")
  assert_eq(report.diagnostics.length(), 0)
}

///|
test "metadata: optional partial records, failed counts, unbounded tails and strict names" {
  let data = metadata_test_partial()
  let report = metadata_test_inspect(data)
  metadata_test_ledger(report, data)
  assert_eq(report.name_details_status, "partial")
  assert_eq(report.custom_name_status, "partial")
  assert_eq(report.summary.parsed_function_record_count, 5)
  assert_eq(report.summary.name_content_bytes, 53)
  assert_eq(report.summary.name_subsection_bytes, 48)
  assert_eq(report.summary.unbounded_name_tail_bytes, 5)
  assert_eq(report.summary.function_name_payload_bytes, 33)
  assert_eq(report.summary.function_name_count_prefix_bytes, 5)
  assert_eq(report.summary.parsed_function_record_bytes, 23)
  assert_eq(report.summary.function_name_unparsed_bytes, 5)
  assert_eq(report.summary.unavailable_function_name_count, 1)
  assert_eq(report.diagnostics.length(), 7)
  let records = report.function_names.copy()
  records.sort_by(fn(a, b) { a.function_index.compare(b.function_index) })
  assert_eq(records.map(fn(r) { r.function_index }), [1U, 3U, 4U, 5U, 6U])
  assert_eq(records[1].name, None)
  assert_eq(records[2].name, Some("z")) // Continues after invalid UTF-8.
  assert_eq(records[4].name, Some("done")) // Continues after another custom's tail.
  let first = report.subsections[0]
  assert_eq(first.unparsed.map(fn(r) { r.size }), Some(3))
  assert_eq(data[first.unparsed.unwrap().offset], b'\x02') // Entire failed record.
  assert_eq(report.subsections[1].status, "opaque")
  let count_failed = report.subsections[3]
  assert_eq(count_failed.declared_count, None)
  assert_eq(count_failed.count_prefix_bytes, 0)
  assert_eq(count_failed.unparsed, Some(count_failed.payload))
  assert_eq(data[count_failed.unparsed.unwrap().offset], b'\x80')
  assert_eq(report.subsections[4].unparsed.map(fn(r) { r.size }), Some(1))
  assert_eq(report.categories[2].custom_ordinals, [4]) // Literal U+FFFD is valid.
  assert_eq(report.categories[4].custom_ordinals, [3]) // Lossy label is never used.
  assert_eq(report.summary.unavailable_custom_count, 1)
  for d in report.diagnostics {
    assert_true(d.offset >= 8 && d.offset <= data.length())
  }
  let text = render_metadata(report, 0)
  assert_true(text.contains("name details: partial"))
  assert_true(text.contains("Diagnostics: 7")) // Diagnostics not cut by Top=0.
  assert_true(text.contains("unparsed 5 B"))
}

///|
test "metadata: absent and opaque states, complete JSON, outer errors and mode grammar" {
  let empty = metadata_test_inspect(b"\x00asm\x01\x00\x00\x00")
  assert_eq(empty.summary.custom_bytes, 0)
  assert_eq(empty.name_details_status, "absent")
  let opaque_data = b"\x00asm\x01\x00\x00\x00" +
    metadata_test_custom(b"producers", b"\xff\x80")
  let opaque_report = metadata_test_inspect(opaque_data)
  metadata_test_ledger(opaque_report, opaque_data)
  assert_eq(opaque_report.name_details_status, "absent")
  assert_eq(opaque_report.customs[0].status, "opaque")
  assert_eq(opaque_report.diagnostics.length(), 0)
  let full = metadata_test_inspect(metadata_test_valid())
  let text = render_metadata(full, 1)
  assert_true(text.contains("CUSTOM INSTANCES: showing 1 of 7"))
  assert_true(text.contains("FUNCTION-NAME RECORDS: showing 1 of 4"))
  assert_true(
    text.contains(
      "33 B = index prefixes 8 B + name-length prefixes 5 B + name UTF-8 20 B",
    ),
  )
  let json = render_metadata_json(full)
  assert_true(json.contains("moonsize-metadata"))
  assert_true(json.contains("4294967295"))
  assert_true(json.contains("longer-name"))
  assert_true(json.contains("producers"))
  assert_true(
    inspect_metadata(b"\x00asm\x01\x00\x00\x00\x00\x03\x05ab") is Err(_),
  )
  assert_true(inspect_metadata(b"bad") is Err(_))
  let options = parse_options([
    "moonsize", "missing.wasm", "--metadata-json", "new.json", "--top", "0",
  ]).unwrap()
  assert_true(options.metadata)
  assert_eq(options.metadata_json, Some("new.json"))
  assert_eq(options.top, 0)
  assert_false(Options::default("x.wasm").metadata)
  assert_eq(Options::default("x.wasm").metadata_json, None)
  for
    args in [
      ["--metadata-json"],
      ["--metadata-json", ""],
      ["--metadata-json", "old.txt"],
      ["--metadata", "--strict"],
      ["--metadata", "--duplicates"],
      ["--metadata", "--baseline", "b.wasm"],
      ["--metadata", "--html", "n.html"],
    ] {
    assert_true(parse_options(["moonsize", "missing.wasm"] + args) is Err(_))
  }
}
