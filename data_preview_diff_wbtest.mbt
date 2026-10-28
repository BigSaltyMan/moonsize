///|
fn data_preview_diff_test_module(payloads : Array[Bytes]) -> Bytes {
  let mut payload = search_test_leb(payloads.length())
  for bytes in payloads {
    payload = payload + b"\x01" + search_test_leb(bytes.length()) + bytes
  }
  b"\x00asm\x01\x00\x00\x00" + search_test_section(11, payload)
}

///|
fn data_preview_diff_test_before() -> Bytes {
  data_preview_diff_test_module([b"unused", b"\x99\x00\xffAB\x00", b"end"])
}

///|
fn data_preview_diff_test_after() -> Bytes {
  data_preview_diff_test_module([
    b"x", b"yz", b"\x55\x66\x77\x00\x7fAB\x00\x10\x11\x12\x13\x14\x15\x16\x17\x18\x19\x1a\x1b\x1c",
  ])
}

///|
fn data_preview_diff_test_report() -> DataPreviewComparison raise {
  match
    compare_data_previews(
      data_preview_diff_test_before(),
      1,
      1,
      data_preview_diff_test_after(),
      2,
      3,
      32,
    ) {
    Ok(report) => report
    Err(error) => fail(describe_data_preview_comparison_error(error))
  }
}

///|
fn data_preview_diff_test_ledger(r : DataPreviewComparison) -> Unit raise {
  assert_eq(
    r.compared_positions,
    r.baseline.returned_size.max(r.current.returned_size),
  )
  assert_eq(r.compared_positions, r.positions.length())
  assert_eq(
    r.compared_positions,
    r.same_count +
    r.different_count +
    r.baseline_only_count +
    r.current_only_count,
  )
  assert_eq(
    r.baseline.returned_size,
    r.same_count + r.different_count + r.baseline_only_count,
  )
  assert_eq(
    r.current.returned_size,
    r.same_count + r.different_count + r.current_only_count,
  )
  assert_eq(r.returned_size_delta, r.current_only_count - r.baseline_only_count)
  assert_eq(
    r.returned_size_delta,
    r.current.returned_size - r.baseline.returned_size,
  )
  for side in [r.baseline, r.current] {
    assert_eq(
      side.segment.payload.size,
      side.payload_offset + side.returned_size + side.remaining_bytes,
    )
    assert_eq(
      side.window.offset,
      side.segment.payload.offset + side.payload_offset,
    )
    assert_eq(side.returned_size, side.bytes.length())
    assert_eq(side.window.size, side.returned_size)
  }
}

///|
test "data-preview-diff: explicit choices, byte/null positions and signed presence ledgers" {
  let b = data_preview_diff_test_before()
  let c = data_preview_diff_test_after()
  assert_eq(b.length(), 32)
  assert_eq(c.length(), 41)
  let r = data_preview_diff_test_report()
  data_preview_diff_test_ledger(r)
  assert_eq(r.baseline.sha256, experiment_sha256(b))
  assert_eq(r.current.sha256, experiment_sha256(c))
  assert_eq(r.baseline.segment.index, 1)
  assert_eq(r.current.segment.index, 2)
  assert_eq(r.baseline.payload_offset, 1)
  assert_eq(r.current.payload_offset, 3)
  assert_eq(r.baseline.window, { offset: 22, size: 5, })
  assert_eq(r.current.window, { offset: 23, size: 18, })
  assert_eq(r.baseline.bytes, b"\x00\xffAB\x00")
  assert_eq(
    r.current.bytes,
    b"\x00\x7fAB\x00\x10\x11\x12\x13\x14\x15\x16\x17\x18\x19\x1a\x1b\x1c",
  )
  assert_eq(r.same_count, 4)
  assert_eq(r.different_count, 1)
  assert_eq(r.baseline_only_count, 0)
  assert_eq(r.current_only_count, 13)
  assert_eq(r.returned_size_delta, 13)
  assert_eq(r.compared_positions, 18)
  let before = b"\x00\xffAB\x00"
  let after = b"\x00\x7fAB\x00\x10\x11\x12\x13\x14\x15\x16\x17\x18\x19\x1a\x1b\x1c"
  for i, p in r.positions {
    assert_eq(p.window_relative_offset, i)
    assert_eq(p.current_byte, Some(after[i].to_int()))
    assert_eq(p.current_file_offset, Some(23 + i))
    assert_eq(c[23 + i], after[i])
    if i < 5 {
      assert_eq(p.baseline_byte, Some(before[i].to_int()))
      assert_eq(p.baseline_file_offset, Some(22 + i))
      assert_eq(b[22 + i], before[i])
      assert_eq(p.status, if i == 1 { "different_byte" } else { "same_byte" })
    } else {
      assert_eq(p.baseline_byte, None)
      assert_eq(p.baseline_file_offset, None)
      assert_eq(p.status, "current_only")
    }
  }
  let reversed = compare_data_previews(c, 2, 3, b, 1, 1, 32).unwrap()
  data_preview_diff_test_ledger(reversed)
  assert_eq(reversed.baseline_only_count, 13)
  assert_eq(reversed.current_only_count, 0)
  assert_eq(reversed.returned_size_delta, -13)
  assert_eq(reversed.same_count, 4)
  assert_eq(reversed.different_count, 1)
  assert_eq(reversed.positions[17].baseline_byte, Some(28))
  assert_eq(reversed.positions[17].current_byte, None)
}

///|
test "data-preview-diff: empty windows, bounds, side errors and complete hex/null rendering" {
  let b = data_preview_diff_test_before()
  let c = data_preview_diff_test_after()
  let empty = compare_data_previews(b, 1, 6, c, 2, 21, 256).unwrap()
  data_preview_diff_test_ledger(empty)
  assert_eq(empty.compared_positions, 0)
  assert_eq(empty.positions.length(), 0)
  assert_true(
    render_data_preview_comparison(empty).contains(
      "Both selected windows are empty",
    ),
  )
  let one_empty = compare_data_previews(b, 1, 6, c, 2, 3, 32).unwrap()
  data_preview_diff_test_ledger(one_empty)
  assert_eq(one_empty.current_only_count, 18)
  assert_eq(one_empty.same_count, 0)
  let self = compare_data_previews(b, 1, 1, b, 1, 1, 32).unwrap()
  data_preview_diff_test_ledger(self)
  assert_eq(self.same_count, 5)
  assert_eq(
    self.different_count + self.baseline_only_count + self.current_only_count,
    0,
  )
  let clipped = compare_data_previews(b, 1, 1, c, 2, 3, 2).unwrap()
  data_preview_diff_test_ledger(clipped)
  assert_eq(clipped.baseline.returned_size, 2)
  assert_eq(clipped.current.returned_size, 2)
  assert_eq(clipped.baseline.remaining_bytes, 3)
  assert_eq(clipped.current.remaining_bytes, 16)
  let large = data_preview_diff_test_module([Bytes::make(4100, 0)])
  let maximum = compare_data_previews(large, 0, 0, large, 0, 0, 4096).unwrap()
  data_preview_diff_test_ledger(maximum)
  assert_eq(maximum.compared_positions, 4096)
  assert_eq(maximum.same_count, 4096)
  assert_eq(maximum.baseline.remaining_bytes, 4)
  assert_true(
    render_data_preview_comparison(maximum).contains("\n         4080  "),
  )
  assert_true(
    compare_data_previews(b, 1, 7, c, 2, 3, 32)
    is Err(BaselineDataPreviewError(InvalidDataPreviewOffset(7, 6))),
  )
  assert_true(
    compare_data_previews(b, 1, 1, c, 9, 0, 32)
    is Err(CurrentDataPreviewError(InvalidDataPreviewIndex(9, 3))),
  )
  assert_true(
    compare_data_previews(b, 1, 1, c, 2, 3, 4097)
    is Err(BaselineDataPreviewError(InvalidDataPreviewLimit(4097))),
  )
  let bad_before = compare_data_previews(b"bad", 0, 0, c, 2, 3, 32).unwrap_err()
  let bad_after = compare_data_previews(b, 1, 1, b"bad", 0, 0, 32).unwrap_err()
  assert_true(bad_before is BaselineDataPreviewError(DataPreviewInputError(_)))
  assert_true(bad_after is CurrentDataPreviewError(DataPreviewInputError(_)))
  assert_true(
    describe_data_preview_comparison_error(bad_before).contains("baseline:"),
  )
  assert_true(
    describe_data_preview_comparison_error(bad_after).contains("current:"),
  )
  let insertion = compare_data_previews(
    data_preview_diff_test_module([b"ABC"]),
    0,
    0,
    data_preview_diff_test_module([b"XABC"]),
    0,
    0,
    16,
  ).unwrap()
  assert_eq(insertion.same_count, 0)
  assert_eq(insertion.different_count, 3)
  assert_eq(insertion.current_only_count, 1)
  let r = data_preview_diff_test_report()
  let text = render_data_preview_comparison(r)
  assert_true(text.contains("DATA PAYLOAD WINDOW COMPARISON"))
  assert_true(text.contains("00 ff 41 42 00 --"))
  assert_true(text.contains(". ^ . . . C"))
  assert_true(text.contains("\n           16  -- --"))
  assert_false(text.contains("\n           32  "))
  let fields = match @json.parse(render_data_preview_comparison_json(r)) {
    Object(fields) => fields
    _ => fail("object expected")
  }
  assert_eq(fields.get("baseline"), Some(data_preview_json_value(r.baseline)))
  assert_eq(fields.get("current"), Some(data_preview_json_value(r.current)))
  match fields.get("positions") {
    Some(Array(positions)) => assert_eq(positions.length(), 18)
    _ => fail("all positions expected")
  }
  let json = render_data_preview_comparison_json(r)
  assert_true(json.contains("\"format\": \"moonsize-data-preview-diff\""))
  assert_true(json.contains("\"baseline_byte\": null"))
  assert_true(json.contains("\"baseline_byte\": 0"))
  assert_true(json.contains("\"memory_index\": null"))
  assert_true(
    render_data_preview_json(r.baseline).contains(
      "\"format\": \"moonsize-data-preview\"",
    ),
  )
}

///|
test "data-preview-diff: explicit CLI pair, independent defaults and early option rejection" {
  assert_eq(Options::default("x").baseline_data_preview_index, None)
  assert_eq(Options::default("x").baseline_data_offset, None)
  let pair = [
    "moonsize", "--data-preview", "2", "--data-offset", "3", "--baseline", "b", "--baseline-data-preview",
    "1", "--baseline-data-offset", "1", "--data-limit", "32", "--data-preview-json",
    "new.json", "--", "--help",
  ]
  assert_eq(help_request(pair).unwrap(), None)
  let options = parse_options(pair).unwrap()
  assert_eq(options.path, "--help")
  assert_eq(options.data_preview_index, Some(2))
  assert_eq(options.baseline_data_preview_index, Some(1))
  assert_eq(options.data_offset, Some(3))
  assert_eq(options.baseline_data_offset, Some(1))
  assert_eq(options.data_limit, Some(32))
  let minimal = parse_options([
    "moonsize", "c", "--data-preview", "2", "--baseline", "b", "--baseline-data-preview",
    "1",
  ]).unwrap()
  assert_eq(minimal.data_offset.unwrap_or(0), 0)
  assert_eq(minimal.baseline_data_offset.unwrap_or(0), 0)
  assert_eq(minimal.data_limit.unwrap_or(256), 256)
  let current_offset = parse_options([
    "moonsize", "c", "--data-preview", "2", "--data-offset", "3", "--baseline", "b",
    "--baseline-data-preview", "1",
  ]).unwrap()
  assert_eq(current_offset.baseline_data_offset.unwrap_or(0), 0)
  for
    flags in [
      ["--baseline-data-preview", "1"],
      ["--data-preview", "2", "--baseline-data-preview", "1"],
      ["--baseline", "b", "--baseline-data-preview", "1"],
      ["--data-preview", "2", "--baseline", "b"],
      ["--data-preview", "2", "--baseline-data-offset", "0"],
      ["--baseline-data-offset", "0"],
      ["--data-preview", "2", "--baseline", "", "--baseline-data-preview", "1"],
      [
        "--data-preview", "2", "--baseline", "b", "--baseline-data-preview", "-1",
      ],
      [
        "--data-preview", "2", "--baseline", "b", "--baseline-data-preview", "1",
        "--baseline-data-offset", "1.5",
      ],
      [
        "--data-preview", "2", "--baseline", "b", "--baseline-data-preview", "1",
        "--baseline-data-offset", "2147483648",
      ],
      [
        "--data-preview", "2", "--baseline", "b", "--baseline-data-preview", "1",
        "--data-limit", "0",
      ],
      [
        "--data-preview", "2", "--baseline", "b", "--baseline-data-preview", "1",
        "--top", "10",
      ],
      [
        "--data-preview", "2", "--baseline", "b", "--baseline-data-preview", "1",
        "--strict",
      ],
      [
        "--data-preview", "2", "--baseline", "b", "--baseline-data-preview", "1",
        "--find-data-hex", "00",
      ],
      [
        "--data-preview", "2", "--baseline", "b", "--baseline-data-preview", "1",
        "--html", "new.html",
      ],
    ] {
    assert_true(parse_options(["moonsize", "missing.wasm"] + flags) is Err(_))
  }
  assert_true(parse_options(["moonsize", "x", "--data-preview", "0"]) is Ok(_))
  assert_true(help_request(["moonsize", "--help"]).unwrap() is Some(_))
  assert_true(
    parse_options([
      "moonsize", "--data-preview", "2", "--baseline", "b", "--baseline-data-preview",
      "1", "--", "x", "--data-offset", "3",
    ])
    is Err(_),
  )
}
