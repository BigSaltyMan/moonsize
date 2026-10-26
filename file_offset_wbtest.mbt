///|
fn file_offset_test_fixture() -> Bytes {
  b"\x00asm\x01\x00\x00\x00" +
  b"\x00\x02\x01x" + // physical 0: [8,12), custom x
  b"\x01\x04\x01\x60\x00\x00" + // 1: [12,18), type
  b"\x02\x07\x01\x01m\x01f\x00\x00" + // 2: [18,27), one function import
  b"\x03\x03\x02\x00\x00" + // 3: [27,32), two local definitions
  b"\x05\x03\x01\x00\x01" + // 4: [32,37), memory
  b"\x00\x02\x01x" + // 5: [37,41), another custom x
  b"\x0c\x01\x02" + // 6: [41,44), independent datacount
  b"\x0a\x89\x00\x82\x00\x82\x00\x00\x0b\x02\x00\x0b" + // 7: [44,56), wide section/count/first body prefix
  b"\x0b\x8f\x00\x82\x00\x81\x00\x83\x00abc\x00\x41\x00\x0b\x80\x00" + // 8: [56,74), passive abc and active empty
  b"\x00\x02\x01x" // 9: [74,78), third custom x
}

///|
fn file_offset_test_report(
  data : Bytes,
  offset : Int,
) -> FileOffsetReport raise {
  match locate_file_offset(data, offset) {
    Ok(report) => report
    Err(error) => fail(describe_file_offset_error(error))
  }
}

///|
test "file-offset: nine regions, physical ordinals and actual wide encoding boundaries" {
  let data = file_offset_test_fixture()
  assert_eq(data.length(), 78)
  for
    (query, kind, start, size, section_index) in [
      (0, ModuleHeader, 0, 8, None),
      (7, ModuleHeader, 0, 8, None),
      (8, SectionHeader, 8, 2, Some(0)),
      (10, SectionPayload, 10, 2, Some(0)),
      (37, SectionHeader, 37, 2, Some(5)),
      (39, SectionPayload, 39, 2, Some(5)),
      (43, SectionPayload, 43, 1, Some(6)),
      (44, SectionHeader, 44, 3, Some(7)),
      (46, SectionHeader, 44, 3, Some(7)),
      (47, CodeCount, 47, 2, Some(7)),
      (48, CodeCount, 47, 2, Some(7)),
      (49, FunctionSizePrefix, 49, 2, Some(7)),
      (50, FunctionSizePrefix, 49, 2, Some(7)),
      (51, FunctionBodyBytes, 51, 2, Some(7)),
      (52, FunctionBodyBytes, 51, 2, Some(7)),
      (53, FunctionSizePrefix, 53, 1, Some(7)),
      (54, FunctionBodyBytes, 54, 2, Some(7)),
      (55, FunctionBodyBytes, 54, 2, Some(7)),
      (56, SectionHeader, 56, 3, Some(8)),
      (58, SectionHeader, 56, 3, Some(8)),
      (59, DataEntryCount, 59, 2, Some(8)),
      (60, DataEntryCount, 59, 2, Some(8)),
      (61, DataEntryMetadata, 61, 4, Some(8)),
      (64, DataEntryMetadata, 61, 4, Some(8)),
      (65, DataPayload, 65, 3, Some(8)),
      (67, DataPayload, 65, 3, Some(8)),
      (68, DataEntryMetadata, 68, 6, Some(8)),
      (73, DataEntryMetadata, 68, 6, Some(8)),
      (74, SectionHeader, 74, 2, Some(9)),
      (76, SectionPayload, 76, 2, Some(9)),
    ] {
    let report = file_offset_test_report(data, query)
    assert_eq(report.region, {
      kind,
      file_offset: start,
      size,
      relative_offset: query - start,
    })
    assert_eq(report.section_index, section_index)
    assert_true(start <= query && query < start + size)
    if report.section is Some(section) {
      assert_true(
        section.offset <= start &&
        start + size <= section.offset + section.total_size,
      )
    }
    if report.function is Some(stat) {
      assert_true(stat.index == 1 || stat.index == 2)
      assert_true(
        stat.offset <= start && start + size <= stat.offset + stat.total_size,
      )
      assert_true(report.data_segment is None)
    }
    if report.data_segment is Some(entry) {
      assert_true(
        entry.encoding.offset <= start &&
        start + size <= entry.encoding.offset + entry.encoding.size,
      )
      assert_true(report.function is None)
    }
  }
  assert_eq(file_offset_test_report(data, 51).function.unwrap().index, 1)
  assert_eq(file_offset_test_report(data, 54).function.unwrap().index, 2)
  assert_eq(file_offset_test_report(data, 65).data_segment.unwrap().index, 0)
  let empty = file_offset_test_report(data, 73).data_segment.unwrap()
  assert_eq(empty.index, 1)
  assert_eq(empty.payload, { offset: 74, size: 0, })
  for offset in [10, 39, 76] {
    assert_eq(
      file_offset_test_report(data, offset).section.unwrap().custom_name,
      Some("x"),
    )
  }
}

///|
test "file-offset: errors, nullable ownership, safe rendering and selective inspection" {
  let data = file_offset_test_fixture()
  for offset in [-1, 78, 2147483647] {
    assert_true(
      locate_file_offset(data, offset) is Err(FileOffsetOutOfRange(_, 78)),
    )
  }
  assert_true(
    locate_file_offset(b"\x00asm\x01", 0) is Err(FileOffsetInputError(_)),
  )
  let header = file_offset_test_report(b"\x00asm\x01\x00\x00\x00", 7)
  assert_eq(header.region.kind, ModuleHeader)
  assert_true(
    header.section is None &&
    header.function is None &&
    header.data_segment is None,
  )
  let fields = match @json.parse(render_file_offset_json(header)) {
    Object(fields) => fields
    _ => fail("expected object")
  }
  for key in ["section_index", "section", "function", "data_segment"] {
    assert_eq(fields.get(key), Some(Json::null()))
  }
  let empty = b"\x00asm\x01\x00\x00\x00\x0a\x02\x80\x00\x0b\x02\x80\x00"
  assert_eq(file_offset_test_report(empty, 11).region.kind, CodeCount)
  assert_eq(file_offset_test_report(empty, 15).region.kind, DataEntryCount)
  assert_true(
    locate_file_offset(empty, 16) is Err(FileOffsetOutOfRange(16, 16)),
  )
  let bad_data = b"\x00asm\x01\x00\x00\x00\x0b\x02\x01\x03"
  assert_true(
    locate_file_offset(bad_data, 10)
    is Err(FileOffsetInputError(InvalidDataEncoding(11, _))),
  )
  assert_eq(file_offset_test_report(bad_data, 8).region.kind, SectionHeader)
  let undivided = b"\x00asm\x01\x00\x00\x00\x01\x01\xff"
  assert_eq(file_offset_test_report(undivided, 10).region.kind, SectionPayload)
  // Unknown function opcode is deliberately not decoded by this feature.
  let undecoded = data[0:52].to_owned() + b"\xff" + data[53:].to_owned()
  assert_eq(
    file_offset_test_report(undecoded, 52).region.kind,
    FunctionBodyBytes,
  )
  assert_true(
    file_offset_range(10, 9, 2147483647, 9)
    is Err(InconsistentFileOffsetRange(_, _)),
  )
  let name = "bad\n\u001b\u0085雪"
  let bytes = @utf8.encode(name)
  let named = data +
    search_test_section(
      0,
      b"\x04name" +
      search_test_section(
        1,
        b"\x01\x01" + search_test_leb(bytes.length()) + bytes,
      ),
    )
  let report = file_offset_test_report(named, 52)
  assert_eq(report.sha256, experiment_sha256(named))
  assert_eq(report.function.unwrap().raw_name, Some(name))
  let text = render_file_offset(report)
  assert_true(text.contains("WASM FILE OFFSET LOCATION"))
  assert_true(text.contains("bad\\n\\u001b\\u0085雪"))
  assert_true(!text.contains(name))
  let json = render_file_offset_json(report)
  assert_true(json.contains("\"kind\": \"function_body\""))
  assert_true(json.contains("\"relative_offset\": 1"))
  assert_true(json.contains("\"data_segment\": null"))
  assert_true(!json.contains("\"opcode\""))
  let located_data = file_offset_test_report(data, 66)
  let data_json = render_file_offset_json(located_data)
  assert_true(data_json.contains("\"function\": null"))
  assert_true(data_json.contains("\"memory_index\": null"))
  assert_true(data_json.contains("\"offset_expression\": null"))
  for
    error in [
      FileOffsetOutOfRange(78, 78),
      FileOffsetInputError(BadMagic),
      InconsistentFileOffsetRange(1, "gap"),
    ] {
    assert_true(!describe_file_offset_error(error).is_empty())
  }
}

///|
test "file-offset: strict decimal CLI query, independent mode and help/separator routing" {
  assert_eq(Options::default("x").locate_offset, None)
  assert_eq(Options::default("x").locate_offset_json, None)
  let args = [
    "moonsize", "--locate-offset", "31", "--locate-offset-json", "new.json", "--",
    "--help",
  ]
  assert_true(help_request(args) is Ok(None))
  let options = parse_options(args).unwrap()
  assert_eq(options.path, "--help")
  assert_eq(options.locate_offset, Some(31))
  assert_eq(options.locate_offset_json, Some("new.json"))
  assert_eq(
    parse_options(["moonsize", "x", "--locate-offset", "2147483647"]).unwrap().locate_offset,
    Some(2147483647),
  )
  for
    args in [
      ["--locate-offset-json", "new.json"],
      ["--locate-offset"],
      ["--locate-offset", ""],
      ["--locate-offset", "-1"],
      ["--locate-offset", "0x10"],
      ["--locate-offset", "1KB"],
      ["--locate-offset", "1.5"],
      ["--locate-offset", "2147483648"],
      ["--locate-offset", "1", "--locate-offset-json"],
      ["--locate-offset", "1", "--locate-offset-json", "bad.txt"],
      ["--locate-offset", "1", "--top", "10"],
      ["--locate-offset", "1", "--strict"],
      ["--locate-offset", "1", "--data-preview", "0"],
      ["--locate-offset", "1", "--find-data", "a"],
      ["--locate-offset", "1", "--baseline", "b"],
      ["--locate-offset", "1", "--html", "n.html"],
      ["--locate-offset", "1", "--budget", "b.json"],
      ["--locate-offset", "1", "--max-size", "1KB"],
    ] {
    assert_true(parse_options(["moonsize", "missing.wasm"] + args) is Err(_))
  }
  assert_true(help_request(["moonsize", "--help"]) is Ok(Some(_)))
  assert_true(
    parse_options(["moonsize", "--locate-offset", "1", "--", "x", "--top", "1"])
    is Err(_),
  )
}
