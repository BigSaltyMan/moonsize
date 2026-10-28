///|
fn data_hex_search_test_fixture() -> Bytes {
  b"\x00asm\x01\x00\x00\x00" +
  search_test_section(0, b"\x04meta\x00\xff\x00") +
  search_test_section(
    11, b"\x06\x01\x05\x00\xff\x00\xff\x00\x01\x05a\x00\xff\x00b\x01\x02\x00\xff\x01\x01\x00\x01\x00\x01\x03aaa",
  )
}

///|
fn data_hex_search_test_report(
  data : Bytes,
  query : String,
) -> DataHexSearchReport raise {
  match search_data_segments_hex(data, query) {
    Ok(report) => report
    Err(error) => fail(describe_data_hex_search_error(error))
  }
}

///|
test "data-hex-search: binary overlaps, per-payload boundaries and shared UTF-8 facts" {
  let data = data_hex_search_test_fixture()
  let r = data_hex_search_test_report(data, "00FF00")
  assert_eq(r.query_hex, "00ff00")
  assert_eq(r.query_size, 3)
  assert_eq(r.query_hex.length(), r.query_size * 2)
  assert_eq(r.file_size, 49)
  assert_eq(r.sha256, experiment_sha256(data))
  assert_eq(r.segment_count, 6)
  assert_eq(r.matched_segment_count, 2)
  assert_eq(r.unmatched_segment_count, 4)
  assert_eq(r.occurrence_count, 3)
  assert_eq(r.matches, [
    { segment_index: 0, payload_offset: 0, file_offset: 23, size: 3, },
    { segment_index: 0, payload_offset: 2, file_offset: 25, size: 3, },
    { segment_index: 1, payload_offset: 1, file_offset: 31, size: 3, },
  ])
  for hit in r.matches {
    let entry = r.data_segments.entries[hit.segment_index]
    assert_eq(hit.file_offset, entry.payload.offset + hit.payload_offset)
    assert_eq(hit.size, r.query_size)
    assert_true(hit.payload_offset + hit.size <= entry.payload.size)
    assert_eq(
      data[hit.file_offset:hit.file_offset + hit.size],
      b"\x00\xff\x00"[:],
    )
  }
  assert_eq(r.occurrence_count, r.matches.length())
  assert_eq(
    r.segment_count,
    r.matched_segment_count + r.unmatched_segment_count,
  )
  assert_data_ledger(r.data_segments)
  assert_eq(r.data_segments.section_size, 31)
  assert_eq(r.data_segments.payload_size, 16)
  assert_eq(r.data_segments.entry_metadata_size, 12)
  assert_eq(r.data_segments.header_size + r.data_segments.count_size, 3)
  // Only payload zeros: custom/header/entry metadata do not add hits.
  assert_eq(data_hex_search_test_report(data, "00").occurrence_count, 7)
  let hex = data_hex_search_test_report(data, "6161")
  let utf8 = search_data_segments(data, "aa").unwrap()
  assert_eq(hex.matches, utf8.matches)
  assert_eq(hex.occurrence_count, 2)
  assert_eq(hex.matches.map(fn(hit) { hit.file_offset }), [46, 47])
  assert_eq(hex.data_segments.payload_size, utf8.data_segments.payload_size)
  assert_true(
    render_data_search_json(utf8).contains(
      "\"format\": \"moonsize-data-search\"",
    ),
  )
  assert_true(render_data_search_json(utf8).contains("\"query\": \"aa\""))
}

///|
test "data-hex-search: strict ASCII syntax, empty states and complete report JSON" {
  for
    query in [
      "", "0", "000", " 00", "00 ", "00ff 00", "00:ff", "0x00", "\\x00", "??", "００",
      "éé", "00\n",
    ] {
    assert_true(
      search_data_segments_hex(b"bad", query) is Err(InvalidDataHexQuery),
    )
  }
  assert_true(
    describe_data_hex_search_error(InvalidDataHexQuery).contains("ASCII"),
  )
  assert_true(
    search_data_segments_hex(b"\x00asm\x01", "00")
    is Err(DataHexSearchInputError(_)),
  )
  let header = b"\x00asm\x01\x00\x00\x00"
  let absent = data_hex_search_test_report(header, "00")
  assert_true(render_data_hex_search(absent, 1).contains("No data section."))
  let empty = data_hex_search_test_report(header + b"\x0b\x01\x00", "00")
  assert_true(render_data_hex_search(empty, 1).contains("Empty data section"))
  let empty_payload = data_hex_search_test_report(
    header + b"\x0b\x03\x01\x01\x00",
    "00",
  )
  assert_eq(empty_payload.unmatched_segment_count, 1)
  assert_true(
    render_data_hex_search(empty_payload, 1).contains(
      "No matches in data payloads.",
    ),
  )
  let data = data_hex_search_test_fixture()
  for query in ["deadbeef", "00ff00ff00ff00"] {
    assert_eq(data_hex_search_test_report(data, query).occurrence_count, 0)
  }
  let r = data_hex_search_test_report(data, "00ff00")
  let text = render_data_hex_search(r, 1)
  assert_true(text.contains("DATA PAYLOAD HEX SEARCH"))
  assert_true(text.contains("Query hex: 00ff00"))
  assert_true(text.contains("showing 1 of 3"))
  assert_true(text.contains("0  0  23  3"))
  assert_false(text.contains("0  2  25  3"))
  assert_false(text.contains("\u0000"))
  assert_true(
    text.contains("31 = payload 16 + entry metadata 12 + section overhead 3"),
  )
  let fields = match @json.parse(render_data_hex_search_json(r)) {
    Object(fields) => fields
    _ => fail("object expected")
  }
  assert_eq(
    fields.get("format"),
    Some(Json::string("moonsize-data-hex-search")),
  )
  assert_eq(fields.get("query_hex"), Some(Json::string("00ff00")))
  assert_true(fields.get("query") is None)
  assert_eq(
    fields.get("data_segments"),
    Some(data_segments_json(r.data_segments)),
  )
  match fields.get("matches") {
    Some(Array(hits)) => assert_eq(hits.length(), 3)
    _ => fail("all hits expected")
  }
  assert_true(render_data_hex_search_json(r).contains("\"memory_index\": null"))
}

///|
test "data-hex-search: query choice, independent CLI and unchanged separator/help rules" {
  assert_eq(Options::default("x").find_data_hex, None)
  let args = [
    "moonsize", "--find-data-hex", "00FF00", "--find-data-json", "new.json", "--top",
    "1", "--", "--help",
  ]
  assert_eq(help_request(args).unwrap(), None)
  let options = parse_options(args).unwrap()
  assert_eq(options.find_data_hex, Some("00FF00"))
  assert_eq(options.find_data, None)
  assert_eq(options.find_data_json, Some("new.json"))
  assert_eq(options.path, "--help")
  assert_eq(options.top, 1)
  let text = parse_options([
    "moonsize", "x", "--find-data", " ", "--find-data-json", "utf8.json",
  ]).unwrap()
  assert_eq(text.find_data, Some(" "))
  assert_eq(text.find_data_hex, None)
  for
    flags in [
      ["--find-data-hex"],
      ["--find-data-hex", ""],
      ["--find-data-hex", "0"],
      ["--find-data-hex", "0x00"],
      ["--find-data-json", "new.json"],
      ["--find-data", "a", "--find-data-hex", "00"],
      ["--find-data-hex", "00", "--find-data", "a"],
      ["--find-data-hex", "00", "--find-data-json", "bad.txt"],
      ["--find-data-hex", "00", "--strict"],
      ["--find-data-hex", "00", "--baseline", "b"],
      ["--find-data-hex", "00", "--opcode-stats"],
      ["--find-data-hex", "00", "--find-opcode", "end"],
      ["--find-data-hex", "00", "--html", "new.html"],
      ["--find-data-hex", "00", "--data-segments"],
      ["--find-data-hex", "00", "--budget", "b.json"],
      ["--find-data-hex", "00", "--locals", "1"],
      ["--find-data-hex", "00", "--data-preview", "0"],
    ] {
    assert_true(parse_options(["moonsize", "missing.wasm"] + flags) is Err(_))
  }
  assert_true(help_request(["moonsize", "--help"]).unwrap() is Some(_))
  assert_true(
    help_request(["moonsize", "--find-data-hex", "--help", "x"]).unwrap()
    is None,
  )
  assert_true(
    parse_options(["moonsize", "--find-data-hex", "00", "--", "x", "--top", "1"])
    is Err(_),
  )
  let r = data_hex_search_test_report(data_hex_search_test_fixture(), "00FF00")
  assert_true(render_data_hex_search(r, 1).contains("Query hex: 00ff00"))
  assert_false(render_data_hex_search(r, 1).contains("00FF00"))
  assert_false(render_data_hex_search(r, 1).contains("\u0000"))
}
