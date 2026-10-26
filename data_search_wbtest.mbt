///|
fn data_search_test_fixture() -> Bytes raise {
  data_duplicates_test_module([
    b"\x01\x03aaa",
    b"\x01\x0b\x00\xff" + @utf8.encode("雪雪") + b"aa\x00",
    b"\x01\x02ab",
    b"\x01\x01c",
    b"\x00\x41\x61\x0b\x00", // Empty payload: 'a' in expression is excluded.
  ]) +
  search_test_section(0, b"\x08onlymeta")
}

///|
fn data_search_test_report(
  data : Bytes,
  query : String,
) -> DataSearchReport raise {
  match search_data_segments(data, query) {
    Ok(report) => report
    Err(error) => fail(describe_data_search_error(error))
  }
}

///|
test "data-search: exact payload byte matches, overlaps, Unicode and boundaries" {
  let data = data_search_test_fixture()
  let report = data_search_test_report(data, "aa")
  assert_eq(
    report.matches.map(fn(hit) { (hit.segment_index, hit.payload_offset) }),
    [(0, 0), (0, 1), (1, 8)],
  )
  assert_eq(report.query_size, 2)
  assert_eq(report.segment_count, 5)
  assert_eq(report.matched_segment_count, 2)
  assert_eq(report.unmatched_segment_count, 3)
  for hit in report.matches {
    let entry = report.data_segments.entries[hit.segment_index]
    assert_eq(hit.file_offset, entry.payload.offset + hit.payload_offset)
    assert_eq(hit.size, 2)
    assert_eq(data[hit.file_offset:hit.file_offset + hit.size], b"aa"[:])
  }
  let chinese = data_search_test_report(data, "雪")
  assert_eq(chinese.query_size, 3)
  assert_eq(
    chinese.matches.map(fn(hit) { (hit.segment_index, hit.payload_offset) }),
    [(1, 2), (1, 5)],
  )
  for hit in chinese.matches {
    assert_eq(
      data[hit.file_offset:hit.file_offset + hit.size],
      @utf8.encode("雪")[:],
    )
  }
  assert_eq(data_search_test_report(data, "\u0000").occurrence_count, 2)
  for query in ["abc", "onlymeta", "A", "AA", "\\u0000"] {
    assert_eq(data_search_test_report(data, query).occurrence_count, 0)
  }
  // 0x61 appears in the active expression but only payload occurrences count.
  assert_eq(data_search_test_report(data, "a").occurrence_count, 6)
}

///|
test "data-search: complete reports, empty states, query escaping and errors" {
  let data = data_search_test_fixture()
  assert_true(search_data_segments(b"bad", "") is Err(EmptyDataSearchQuery))
  assert_true(
    describe_data_search_error(EmptyDataSearchQuery).contains("empty"),
  )
  assert_true(
    search_data_segments(b"\x00asm\x01", "x") is Err(DataSearchInputError(_)),
  )
  let report = data_search_test_report(data, "aa")
  assert_eq(report.sha256, experiment_sha256(data))
  assert_eq(report.file_size, data.length())
  assert_eq(report.occurrence_count, 3)
  assert_eq(
    report.segment_count,
    report.matched_segment_count + report.unmatched_segment_count,
  )
  assert_data_ledger(report.data_segments)
  let text = render_data_search(report, 1)
  assert_true(text.contains("MATCHES: showing 1 of 3"))
  assert_true(!text.contains("1  8  "))
  assert_true(text.contains("Input SHA-256: " + report.sha256))
  let json = @json.parse(render_data_search_json(report))
  match json {
    Object(fields) => {
      assert_eq(
        fields.get("format"),
        Some(Json::string("moonsize-data-search")),
      )
      assert_eq(fields.get("query"), Some(Json::string("aa")))
      assert_eq(
        fields.get("data_segments"),
        Some(data_segments_json(report.data_segments)),
      )
      match fields.get("matches") {
        Some(Array(hits)) => assert_eq(hits.length(), 3)
        _ => fail("expected complete matches array")
      }
    }
    _ => fail("expected object")
  }
  assert_true(
    render_data_search_json(report).contains("\"memory_index\": null"),
  )
  let absent = data_search_test_report(b"\x00asm\x01\x00\x00\x00", " ")
  assert_eq(absent.query, " ")
  assert_eq(absent.query_size, 1)
  assert_true(render_data_search(absent, 1).contains("No data section."))
  let empty = data_search_test_report(
    b"\x00asm\x01\x00\x00\x00\x0b\x01\x00", "x",
  )
  assert_true(render_data_search(empty, 1).contains("Empty data section"))
  let empty_payload = data_search_test_report(
    data_duplicates_test_module([b"\x01\x00"]),
    "x",
  )
  assert_eq(empty_payload.unmatched_segment_count, 1)
  assert_true(
    render_data_search(empty_payload, 1).contains(
      "No matches in data payloads.",
    ),
  )
  let query = " \n\u0000\u001b\u0085\u2028雪"
  let bytes = @utf8.encode(query)
  let escaped = data_search_test_report(
    data_duplicates_test_module([
      b"\x01" + search_test_leb(bytes.length()) + bytes,
    ]),
    query,
  )
  assert_eq(escaped.occurrence_count, 1)
  assert_true(
    render_data_search(escaped, 1).contains(search_terminal_string(query)),
  )
  assert_true(!render_data_search(escaped, 1).contains(query))
  assert_true(render_data_search_json(escaped).contains("\"query\""))
}

///|
test "data-search: independent CLI mode, values, separator and help routing" {
  assert_eq(Options::default("x").find_data, None)
  assert_eq(Options::default("x").find_data_json, None)
  let argv = [
    "moonsize", "--find-data", " ", "--find-data-json", "new.json", "--top", "1",
    "--", "--help",
  ]
  assert_true(help_request(argv) is Ok(None))
  let options = parse_options(argv).unwrap()
  assert_eq(options.path, "--help")
  assert_eq(options.find_data, Some(" "))
  assert_eq(options.find_data_json, Some("new.json"))
  assert_eq(options.top, 1)
  assert_eq(
    parse_options(["moonsize", "x", "--find-data", "-a"]).unwrap().find_data,
    Some("-a"),
  )
  assert_true(
    help_request(["moonsize", "--find-data", "--help", "x"]) is Ok(None),
  )
  for
    args in [
      ["--find-data"],
      ["--find-data", ""],
      ["--find-data", "--help"],
      ["--find-data-json", "new.json"],
      ["--find-data", "a", "--find-data-json"],
      ["--find-data", "a", "--find-data-json", ""],
      ["--find-data", "a", "--find-data-json", "new.txt"],
      ["--find-data", "a", "--strict"],
      ["--find-data", "a", "--baseline", "b"],
      ["--find-data", "a", "--data-segments"],
      ["--find-data", "a", "--max-size", "1KB"],
      ["--find-data", "a", "--html", "n.html"],
      ["--find-data", "a", "--budget", "n.json"],
      ["--find-data", "a", "--find-functions", "a"],
      ["--find-data", "a", "--summary-json", "n.json"],
      ["--find-data", "a", "--exports"],
      ["--find-data", "a", "--instructions", "0"],
    ] {
    assert_true(parse_options(["moonsize", "missing.wasm"] + args) is Err(_))
  }
  assert_true(help_request(["moonsize", "--help"]) is Ok(Some(_)))
  assert_true(
    parse_options(["moonsize", "--find-data", "a", "--", "x", "--top", "1"])
    is Err(_),
  )
}
