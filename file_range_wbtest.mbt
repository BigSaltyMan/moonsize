///|
fn file_range_test_report(
  data : Bytes,
  offset : Int,
  length : Int,
) -> FileRangeReport raise {
  match locate_file_range(data, offset, length) {
    Ok(value) => value
    Err(error) => fail(describe_file_range_error(error))
  }
}

///|
fn file_range_test_ledger(report : FileRangeReport) -> Unit raise {
  let mut cursor = report.query.offset
  let mut sum = 0
  for part in report.parts {
    assert_eq(part.overlap_range.offset, cursor)
    assert_true(part.overlap_range.size > 0)
    assert_true(file_offset_within(part.overlap_range, part.owner_range))
    assert_true(file_offset_within(part.overlap_range, report.query))
    assert_eq(part.query_relative_offset, cursor - report.query.offset)
    assert_eq(part.owner_relative_offset, cursor - part.owner_range.offset)
    cursor += part.overlap_range.size
    sum += part.overlap_range.size
  }
  assert_eq(cursor, report.query.offset + report.query.size)
  assert_eq(sum, report.query.size)
  assert_eq(sum, report.covered_size)
}

///|
test "file-range: crossings and exact structural ledger" {
  let data = file_offset_test_fixture()
  let report = file_range_test_report(data, 45, 32)
  assert_eq(report.sha256, experiment_sha256(data))
  let expected = [
    (SectionHeader, 44, 3, 45, 2, Some(7), None, None),
    (CodeCount, 47, 2, 47, 2, Some(7), None, None),
    (FunctionSizePrefix, 49, 2, 49, 2, Some(7), Some(1), None),
    (FunctionBodyBytes, 51, 2, 51, 2, Some(7), Some(1), None),
    (FunctionSizePrefix, 53, 1, 53, 1, Some(7), Some(2), None),
    (FunctionBodyBytes, 54, 2, 54, 2, Some(7), Some(2), None),
    (SectionHeader, 56, 3, 56, 3, Some(8), None, None),
    (DataEntryCount, 59, 2, 59, 2, Some(8), None, None),
    (DataEntryMetadata, 61, 4, 61, 4, Some(8), None, Some(0)),
    (DataPayload, 65, 3, 65, 3, Some(8), None, Some(0)),
    (DataEntryMetadata, 68, 6, 68, 6, Some(8), None, Some(1)),
    (SectionHeader, 74, 2, 74, 2, Some(9), None, None),
    (SectionPayload, 76, 2, 76, 1, Some(9), None, None),
  ]
  assert_eq(report.parts.length(), expected.length())
  for i, (kind, start, size, hit, covered, section, function, entry) in expected {
    let part = report.parts[i]
    assert_eq(part.kind, kind)
    assert_eq(part.owner_range, { offset: start, size, })
    assert_eq(part.overlap_range, { offset: hit, size: covered, })
    assert_eq(part.section_index, section)
    assert_eq(part.function.map(fn(f) { f.index }), function)
    assert_eq(part.data_segment.map(fn(e) { e.index }), entry)
  }
  file_range_test_ledger(report)
  let middle = file_range_test_report(data, 66, 1)
  assert_eq(middle.parts[0].owner_range, { offset: 65, size: 3, })
  assert_eq(middle.parts[0].overlap_range, { offset: 66, size: 1, })
  assert_eq(middle.parts[0].owner_relative_offset, 1)
  file_range_test_ledger(middle)
  let all = file_range_test_report(data, 0, data.length())
  let customs = all.parts.filter(fn(p) {
    p.kind == SectionPayload && p.section.unwrap().id == 0
  })
  assert_eq(customs.map(fn(p) { p.section_index.unwrap() }), [0, 5, 9])
  file_range_test_ledger(all)
  for offset in [0, 50, 52, 66, 73, 76] {
    let point = file_offset_test_report(data, offset)
    let part = file_range_test_report(data, offset, 1).parts[0]
    assert_eq(part.kind, point.region.kind)
    assert_eq(part.owner_range, {
      offset: point.region.file_offset,
      size: point.region.size,
    })
  }
}

///|
test "file-range: empty bounds and selective refinement" {
  let data = file_offset_test_fixture()
  for offset in [0, 52, 78] {
    let report = file_range_test_report(data, offset, 0)
    assert_eq(report.parts.length(), 0)
    file_range_test_ledger(report)
  }
  for
    (offset, length) in [
      (-1, 0),
      (0, -1),
      (79, 0),
      (78, 1),
      (77, 2),
      (1, 2147483647),
    ] {
    assert_true(
      locate_file_range(data, offset, length)
      is Err(FileRangeOutOfRange(_, _, 78)),
    )
  }
  assert_eq(file_range_test_report(data, 77, 1).covered_size, 1)
  assert_true(locate_file_offset(data, 78) is Err(FileOffsetOutOfRange(_, _)))
  assert_true(
    locate_file_range(b"bad", 0, 0)
    is Err(FileRangeOwnershipError(_, _, _, FileOffsetInputError(_))),
  )
  let bad = b"\x00asm\x01\x00\x00\x00\x0b\x02\x01\x03"
  assert_eq(file_range_test_report(bad, 8, 2).parts[0].kind, SectionHeader)
  assert_eq(file_range_test_report(bad, 11, 0).parts.length(), 0)
  assert_true(
    locate_file_range(bad, 10, 1)
    is Err(
      FileRangeOwnershipError(
        _,
        _,
        _,
        FileOffsetInputError(InvalidDataEncoding(11, _))
      )
    ),
  )
  let undecoded = data[0:52].to_owned() + b"\xff" + data[53:].to_owned()
  assert_eq(
    file_range_test_report(undecoded, 51, 2).parts[0].kind,
    FunctionBodyBytes,
  )
  let zero_body = b"\x00asm\x01\x00\x00\x00\x03\x02\x01\x00\x0a\x02\x01\x00"
  let report = file_range_test_report(zero_body, 12, 4)
  assert_eq(report.parts.length(), 3) // header, count, prefix; no zero body row
  file_range_test_ledger(report)
  for
    error in [
      FileRangeOutOfRange(0, 9, 8),
      FileRangeOwnershipError(0, 0, 3, FileOffsetInputError(BadMagic)),
      InconsistentFileRange(1, 2, 8, "gap"),
    ] {
    assert_true(!describe_file_range_error(error).is_empty())
  }
}

///|
test "file-range: CLI and full safe rendering" {
  let args = [
    "moonsize", "--locate-range", "45", "32", "--top", "1", "--locate-range-json",
    "new.json", "--", "--help",
  ]
  assert_true(help_request(args) is Ok(None))
  let options = parse_options(args).unwrap()
  assert_eq(options.path, "--help")
  assert_eq(options.locate_range_offset, Some(45))
  assert_eq(options.locate_range_length, Some(32))
  assert_eq(options.locate_range_json, Some("new.json"))
  assert_eq(options.top, 1)
  assert_eq(Options::default("x").locate_range_offset, None)
  for
    tail in [
      ["--locate-range"],
      ["--locate-range", "0"],
      ["--locate-range", "-1", "0"],
      ["--locate-range", "0", "0x1"],
      ["--locate-range", "0", "2147483648"],
      ["--locate-range-json", "new.json"],
      ["--locate-range", "0", "1", "--locate-range-json", "x.txt"],
    ] {
    assert_true(parse_options(["moonsize", "x"] + tail) is Err(_))
  }
  for
    tail in [
      ["--strict"],
      ["--baseline", "b"],
      ["--html", "n.html"],
      ["--budget", "b.json"],
      ["--max-size", "1KB"],
      ["--locate-offset", "1"],
      ["--locate-decode"],
      ["--data-preview", "0"],
      ["--find-opcode", "nop"],
      ["--opcode-stats"],
      ["--compress"],
      ["--locals", "0"],
    ] {
    assert_true(
      parse_options(["moonsize", "x", "--locate-range", "0", "0"] + tail)
      is Err(_),
    )
  }
  assert_true(help_request(["moonsize", "--help"]) is Ok(Some(_)))
  let name = "bad\n\u001b雪"
  let bytes = @utf8.encode(name)
  let data = file_offset_test_fixture() +
    search_test_section(0, search_test_leb(bytes.length()) + bytes)
  let report = file_range_test_report(data, 45, data.length() - 45)
  let text = render_file_range(report, 1)
  assert_true(text.contains("PARTS: showing 1 of 15"))
  assert_true(!text.contains("\ncode_count  "))
  assert_true(text.contains("Covered size: 44 B (all parts)"))
  assert_true(render_file_range(report, 99).contains("bad\\n\\u001b雪"))
  let root = match @json.parse(render_file_range_json(report)) {
    Object(fields) => fields
    _ => fail("object")
  }
  assert_eq(root.get("format"), Some(Json::string("moonsize-file-range")))
  let rows = match root.get("parts") {
    Some(Array(rows)) => rows
    _ => fail("array")
  }
  assert_eq(rows.length(), 15)
  let header = match
    @json.parse(render_file_range_json(file_range_test_report(data, 0, 1))) {
    Object(fields) => fields
    _ => fail("object")
  }
  let rows = match header.get("parts") {
    Some(Array(rows)) => rows
    _ => fail("array")
  }
  let first = match rows[0] {
    Object(fields) => fields
    _ => fail("object")
  }
  for key in ["section_index", "section", "function", "data_segment"] {
    assert_eq(first.get(key), Some(Json::null()))
  }
  assert_true(!render_file_range_json(report).contains("\"opcode\""))
}
