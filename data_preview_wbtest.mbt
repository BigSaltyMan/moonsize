///|
fn data_preview_test_payload() -> Bytes {
  b"\x00\x09ABCDEFGHIJKLMNOP\x1b\x7f\x20\xff" +
  @utf8.encode("雪") +
  b"0123456789abcdefghijklmnopqrstuvwxyz"
}

///|
fn data_preview_test_fixture() -> Bytes raise {
  let bytes = data_preview_test_payload()
  data_duplicates_test_module([
    b"\x01" + search_test_leb(bytes.length()) + bytes,
    b"\x01\x00",
    b"\x00\x41\x00\x0b\x08NEIGHBOR",
  ])
}

///|
fn data_preview_test_report(
  data : Bytes,
  index : Int,
  offset : Int,
  limit : Int,
) -> DataPreviewReport raise {
  match preview_data_segment(data, index, offset, limit) {
    Ok(report) => report
    Err(error) => fail(describe_data_preview_error(error))
  }
}

///|
test "data-preview: bounded windows, clipped limits and exact byte ledgers" {
  let data = data_preview_test_fixture()
  let payload = data_preview_test_payload()
  assert_eq(payload.length(), 61)
  for
    (offset, limit, expected_size) in [
      (0, 256, 61),
      (1, 20, 20),
      (23, 1, 1),
      (60, 4096, 1),
      (61, 256, 0),
    ] {
    let report = data_preview_test_report(data, 0, offset, limit)
    assert_eq(report.file_size, data.length())
    assert_eq(report.segment_count, 3)
    assert_eq(report.segment.index, 0)
    assert_eq(report.payload_offset, offset)
    assert_eq(report.requested_limit, limit)
    assert_eq(report.returned_size, expected_size)
    assert_eq(report.bytes[:], payload[offset:offset + expected_size])
    assert_eq(
      data[report.window.offset:report.window.offset + report.window.size],
      report.bytes[:],
    )
    assert_eq(
      report.segment.payload.size,
      report.payload_offset + report.returned_size + report.remaining_bytes,
    )
    assert_eq(
      report.window.offset,
      report.segment.payload.offset + report.payload_offset,
    )
    assert_eq(report.window.size, report.returned_size)
    assert_eq(report.returned_size, report.bytes.length())
  }
  // A single continuation byte is retained as a byte, not repaired as UTF-8.
  assert_eq(data_preview_test_report(data, 0, 23, 1).bytes, b"\x9b")
  let empty = data_preview_test_report(data, 1, 0, 4096)
  assert_eq(empty.bytes.length(), 0)
  assert_eq(empty.remaining_bytes, 0)
  assert_eq(empty.window.offset, empty.segment.payload.offset)
  assert_true(
    render_data_preview(empty).contains("Empty window (at payload end)."),
  )
}

///|
test "data-preview: errors and safe text/JSON show the complete returned window" {
  let data = data_preview_test_fixture()
  for limit in [0, -1, 4097, 2147483647] {
    assert_true(
      preview_data_segment(data, 0, 0, limit) is Err(InvalidDataPreviewLimit(_)),
    )
  }
  for index in [-1, 3, 2147483647] {
    assert_true(
      preview_data_segment(data, index, 0, 1)
      is Err(InvalidDataPreviewIndex(_, 3)),
    )
  }
  for offset in [-1, 62, 2147483647] {
    assert_true(
      preview_data_segment(data, 0, offset, 1)
      is Err(InvalidDataPreviewOffset(_, 61)),
    )
  }
  assert_true(
    preview_data_segment(b"\x00asm\x01", 0, 0, 1)
    is Err(DataPreviewInputError(_)),
  )
  assert_true(
    preview_data_segment(b"\x00asm\x01\x00\x00\x00", 0, 0, 1)
    is Err(InvalidDataPreviewIndex(0, 0)),
  )
  for
    error in [
      InvalidDataPreviewLimit(0),
      InvalidDataPreviewIndex(3, 3),
      InvalidDataPreviewOffset(62, 61),
      DataPreviewInputError(BadMagic),
    ] {
    assert_true(!describe_data_preview_error(error).is_empty())
  }
  let report = data_preview_test_report(data, 0, 1, 20)
  let text = render_data_preview(report)
  assert_true(text.contains("DATA PAYLOAD BYTE PREVIEW"))
  assert_true(
    text.contains(
      "09 41 42 43 44 45 46 47 48 49 4a 4b 4c 4d 4e 4f  .ABCDEFGHIJKLMNO\n",
    ),
  )
  assert_true(text.contains("50 1b 7f 20"))
  assert_true(text.contains("P.. \n"))
  assert_true(!text.contains("\u001b"))
  assert_true(!text.contains("\t"))
  assert_true(!text.contains("雪"))
  let rows : Array[String] = []
  for line in text.split("\n") {
    if line.contains("09 41") || line.contains("50 1b") {
      rows.push(line.to_owned())
    }
  }
  assert_eq(rows.length(), 2)
  assert_true(
    rows[0].has_prefix(
      pad_left("1", 14) + "  " + pad_left(report.window.offset.to_string(), 11),
    ),
  )
  assert_true(
    rows[1].has_prefix(
      pad_left("17", 14) +
      "  " +
      pad_left((report.window.offset + 16).to_string(), 11),
    ),
  )
  assert_eq(report.sha256, experiment_sha256(data))
  let json = @json.parse(render_data_preview_json(report))
  match json {
    Object(fields) => {
      assert_eq(
        fields.get("format"),
        Some(Json::string("moonsize-data-preview")),
      )
      assert_eq(
        fields.get("hex"),
        Some(Json::string("094142434445464748494a4b4c4d4e4f501b7f20")),
      )
      assert_eq(fields.get("window"), Some(data_range_json(report.window)))
      match fields.get("segment") {
        Some(Object(entry)) => {
          assert_eq(entry.get("memory_index"), Some(Json::null()))
          assert_eq(entry.get("offset_expression"), Some(Json::null()))
        }
        _ => fail("expected selected segment object")
      }
    }
    _ => fail("expected JSON object")
  }
  let empty_json = render_data_preview_json(
    data_preview_test_report(data, 0, 61, 1),
  )
  assert_true(empty_json.contains("\"hex\": \"\""))
  let active = data_preview_test_report(data, 2, 0, 256)
  assert_eq(active.bytes, b"NEIGHBOR")
  assert_true(active.segment.offset_expression is Some(_))
  assert_true(render_data_preview_json(active).contains("not_evaluated"))
}

///|
test "data-preview: CLI defaults, strict decimal modifiers and mode isolation" {
  let defaults = Options::default("x")
  assert_eq(defaults.data_preview_index, None)
  assert_eq(defaults.data_offset, None)
  assert_eq(defaults.data_limit, None)
  assert_eq(defaults.data_preview_json, None)
  let options = parse_options(["moonsize", "x", "--data-preview", "1"]).unwrap()
  assert_eq(options.data_preview_index, Some(1))
  assert_eq(options.data_offset.unwrap_or(0), 0)
  assert_eq(options.data_limit.unwrap_or(256), 256)
  let args = [
    "moonsize", "--data-offset", "8", "--data-preview", "1", "--data-limit", "4096",
    "--data-preview-json", "new.json", "--", "--help",
  ]
  assert_true(help_request(args) is Ok(None))
  let explicit = parse_options(args).unwrap()
  assert_eq(explicit.path, "--help")
  assert_eq(explicit.data_offset, Some(8))
  assert_eq(explicit.data_limit, Some(4096))
  assert_eq(explicit.data_preview_json, Some("new.json"))
  assert_eq(
    parse_options([
      "moonsize", "x", "--data-preview", "2147483647", "--data-offset", "2147483647",
    ]).unwrap().data_offset,
    Some(2147483647),
  )
  for
    args in [
      ["--data-offset", "0"],
      ["--data-limit", "256"],
      ["--data-preview-json", "new.json"],
      ["--data-preview"],
      ["--data-preview", "-1"],
      ["--data-preview", "2147483648"],
      ["--data-preview", "0", "--data-offset"],
      ["--data-preview", "0", "--data-offset", "-1"],
      ["--data-preview", "0", "--data-offset", "2147483648"],
      ["--data-preview", "0", "--data-limit"],
      ["--data-preview", "0", "--data-limit", "0"],
      ["--data-preview", "0", "--data-limit", "4097"],
      ["--data-preview", "0", "--data-limit", "1KB"],
      ["--data-preview", "0", "--data-limit", "1.5"],
      ["--data-preview", "0", "--data-preview-json", "bad.txt"],
      ["--data-preview", "0", "--data-preview-json"],
      ["--data-preview", "0", "--top", "10"],
      ["--data-preview", "0", "--strict"],
      ["--data-preview", "0", "--find-data", "a"],
      ["--data-preview", "0", "--baseline", "b"],
      ["--data-preview", "0", "--html", "n.html"],
      ["--data-preview", "0", "--budget", "b.json"],
      ["--data-preview", "0", "--data-segments"],
      ["--data-preview", "0", "--max-size", "1KB"],
    ] {
    assert_true(parse_options(["moonsize", "missing.wasm"] + args) is Err(_))
  }
  assert_true(help_request(["moonsize", "--help"]) is Ok(Some(_)))
  assert_true(
    help_request(["moonsize", "--data-preview-json", "--help"]) is Ok(None),
  )
  assert_true(
    parse_options([
      "moonsize", "--data-preview", "0", "--", "x", "--data-offset", "1",
    ])
    is Err(_),
  )
}
