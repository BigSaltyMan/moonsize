///|
fn exports_test_entry(
  name : Bytes,
  descriptor : Bytes,
  wide? : Bool = false,
) -> Bytes raise {
  imports_test_name(name, wide~) + descriptor
}

///|
fn exports_test_inspect(data : Bytes) -> ExportsReport raise {
  match inspect_exports(data) {
    Ok(report) => report
    Err(error) => fail(describe_error(error))
  }
}

///|
fn exports_test_ledger(report : ExportsReport, data : Bytes) -> Unit raise {
  let l = report.ledger
  let s = report.summary
  assert_eq(
    l.export_section_bytes,
    l.section_header_bytes + l.count_prefix_bytes + l.declaration_bytes,
  )
  assert_eq(l.declaration_bytes, l.name_encoding_bytes + l.descriptor_bytes)
  assert_eq(
    l.name_encoding_bytes,
    l.name_length_prefix_bytes + l.name_utf8_bytes,
  )
  assert_eq(l.descriptor_bytes, l.kind_bytes + l.target_index_prefix_bytes)
  assert_eq(l.kind_bytes, s.export_count)
  assert_eq(s.export_count, s.alias_member_count + s.singleton_target_count)
  assert_eq(
    s.distinct_target_count,
    s.alias_group_count + s.singleton_target_count,
  )
  let c = s.kind_counts
  assert_eq(
    s.export_count,
    c.functions + c.tables + c.memories + c.globals + c.tags,
  )
  let mut grouped_bytes = 0
  let mut grouped_count = 0
  for target in report.targets {
    let mut bytes = 0
    assert_eq(target.entry_ordinals.length(), target.member_count)
    assert_eq(target.is_alias, target.member_count >= 2)
    for ordinal in target.entry_ordinals {
      let entry = report.entries[ordinal]
      assert_eq(entry.kind_code, target.kind_code)
      assert_eq(entry.target_index, target.target_index)
      bytes += entry.encoding.size
    }
    assert_eq(bytes, target.declaration_bytes)
    grouped_bytes += bytes
    grouped_count += target.member_count
  }
  assert_eq(grouped_bytes, l.declaration_bytes)
  assert_eq(grouped_count, s.export_count)
  let mut cursor = report.count_encoding
    .map(fn(r) { r.offset + r.size })
    .unwrap_or(0)
  for entry in report.entries {
    assert_eq(entry.encoding.offset, cursor)
    assert_true(
      entry.encoding.offset >= 0 && entry.encoding.offset <= data.length(),
    )
    assert_true(entry.encoding.size <= data.length() - entry.encoding.offset)
    assert_eq(
      entry.encoding.size,
      entry.name_encoding.size + entry.descriptor.size,
    )
    assert_eq(entry.name_encoding.offset, entry.encoding.offset)
    assert_eq(
      entry.descriptor.offset,
      entry.name_encoding.offset + entry.name_encoding.size,
    )
    assert_eq(
      entry.name_encoding.size,
      entry.name_length_prefix_bytes + entry.name_utf8_bytes,
    )
    assert_eq(entry.descriptor.size, 1 + entry.target_index_prefix_bytes)
    let name_start = entry.name_encoding.offset + entry.name_length_prefix_bytes
    assert_eq(
      @utf8.decode(data[name_start:name_start + entry.name_utf8_bytes]),
      entry.name,
    )
    assert_eq(data[entry.descriptor.offset].to_int(), entry.kind_code)
    cursor += entry.encoding.size
  }
  if report.section is Some(range) {
    assert_eq(cursor, range.offset + range.size)
  }
}

///|
test "exports: five kinds, imported declared targets, aliases and exact ranges" {
  let rows = exports_test_entry(b"f", b"\x00\x80\x00", wide=true) +
    exports_test_entry(b"f alias", b"\x00\x00") +
    exports_test_entry(b"t", b"\x01\x00") +
    exports_test_entry(b"t.alt", b"\x01\x00") +
    exports_test_entry(b"mem", b"\x02\x00") +
    exports_test_entry(b"g", b"\x03\x00") +
    exports_test_entry(b"tag", b"\x04\x00") +
    exports_test_entry(@utf8.encode("雪\"\n"), b"\x00\x00")
  let payload = b"\x88\x00" + rows
  let data = imports_test_valid() +
    b"\x07" +
    Bytes::from_array([(payload.length() | 128).to_byte(), 0]) +
    payload
  let report = exports_test_inspect(data)
  exports_test_ledger(report, data)
  assert_eq(report.summary.export_count, 8)
  assert_eq(report.summary.kind_counts, {
    functions: 3,
    tables: 2,
    memories: 1,
    globals: 1,
    tags: 1,
  })
  assert_eq(report.summary.distinct_target_count, 5)
  assert_eq(report.summary.alias_group_count, 2)
  assert_eq(report.summary.alias_member_count, 5)
  assert_eq(report.summary.singleton_target_count, 3)
  assert_eq(report.targets.map(fn(t) { t.kind_code }), [0, 1, 2, 3, 4])
  assert_eq(report.targets[0].entry_ordinals, [0, 1, 7])
  assert_eq(report.targets[1].entry_ordinals, [2, 3])
  assert_eq(report.ledger.section_header_bytes, 3)
  assert_eq(report.ledger.count_prefix_bytes, 2)
  assert_eq(report.entries[0].name_length_prefix_bytes, 2)
  assert_eq(report.entries[0].target_index_prefix_bytes, 2)
}

///|
test "exports: empty states, exact names, unsigned indices, sorting, Top and no body decoding" {
  let head = b"\x00asm\x01\x00\x00\x00"
  let absent = exports_test_inspect(head)
  assert_eq(absent.section, None)
  assert_eq(absent.ledger.export_section_bytes, 0)
  assert_true(render_exports(absent, 1).contains("No export section."))
  let empty_data = head + duplicate_test_section(7, b"\x00")
  let empty = exports_test_inspect(empty_data)
  assert_eq(empty.summary.export_count, 0)
  assert_eq(empty.ledger.export_section_bytes, 3)
  exports_test_ledger(empty, empty_data)
  let payload = b"\x05" +
    exports_test_entry(b"", b"\x00\xff\xff\xff\xff\x0f") +
    exports_test_entry(b"A", b"\x00\x80\x80\x80\x80\x08") +
    exports_test_entry(b"a", b"\x00\x00") +
    exports_test_entry(b" a ", b"\x00\x00") +
    exports_test_entry(@utf8.encode("雪\n\""), b"\x00\x00")
  let data = head + duplicate_test_section(7, payload)
  let report = exports_test_inspect(data) // Target existence is intentionally not validated.
  exports_test_ledger(report, data)
  assert_eq(report.entries[0].name, "")
  assert_eq(report.entries[0].target_index, 4294967295U)
  assert_eq(report.targets.map(fn(t) { t.target_index }), [
    0U, 2147483648U, 4294967295U,
  ])
  assert_eq(report.targets[0].entry_ordinals, [2, 3, 4])
  let text = render_exports(report, 1)
  assert_true(text.contains("DECLARATIONS: showing 1 of 5"))
  assert_true(text.contains("ALIAS GROUPS: showing 1 of 1"))
  assert_true(text.contains("Names: showing 3 of 3"))
  assert_true(text.contains(Json::string("雪\n\"").stringify()))
  assert_false(text.contains("雪\n\""))
  let root = json_object(@json.parse(render_exports_json(report)))
  assert_eq(root.get("format"), Some(Json::string("moonsize-exports")))
  let entries = json_array(root.get("entries").unwrap())
  assert_eq(entries.length(), 5)
  assert_eq(
    json_object(entries[0]).get("target_index"),
    Some(metadata_uint_json(4294967295U)),
  )
  assert_eq(json_object(entries[4]).get("name"), Some(Json::string("雪\n\"")))
  assert_eq(json_array(root.get("targets").unwrap()).length(), 3)
  assert_eq(
    render_exports_json(report),
    render_exports_json(exports_test_inspect(data)),
  )
  let unknown_body = head +
    duplicate_test_section(1, b"\x01\x60\x00\x00") +
    duplicate_test_section(3, b"\x01\x00") +
    duplicate_test_section(7, b"\x01\x01f\x00\x00") +
    duplicate_test_section(10, b"\x01\x03\x00\xff\x0b")
  assert_eq(exports_test_inspect(unknown_body).summary.export_count, 1)
}

///|
test "exports: strict name and kind failures, positions, trailing bytes and mode grammar" {
  let head = b"\x00asm\x01\x00\x00\x00"
  let duplicate = head +
    duplicate_test_section(7, b"\x02\x01x\x00\x00\x01x\x01\x00")
  match inspect_exports(duplicate) {
    Err(InvalidExportEncoding(15, reason)) => {
      assert_true(reason.contains("duplicate export name"))
      assert_true(reason.contains("first declaration at file offset 11"))
      assert_true(
        describe_error(InvalidExportEncoding(15, reason)).contains("offset 15"),
      )
    }
    _ => fail("expected strict duplicate across kinds")
  }
  for
    (payload, offset, message) in [
      (b"\x01\x01\xff\x00\x00", 12, "invalid UTF-8"),
      (b"\x01\x01a\x05\x00", 13, "unknown export kind 5"),
    ] {
    match inspect_exports(head + duplicate_test_section(7, payload)) {
      Err(InvalidExportEncoding(actual, reason)) => {
        assert_eq(actual, offset)
        assert_true(reason.contains(message))
      }
      _ => fail("expected export field error")
    }
  }
  match inspect_exports(head + duplicate_test_section(7, b"\x00\x00")) {
    Err(TrailingSectionBytes(11, Export)) => ()
    _ => fail("expected first unconsumed export byte")
  }
  let options = parse_options([
    "moonsize", "missing.wasm", "--exports-json", "new.json", "--top", "1",
  ]).unwrap()
  assert_true(options.exports)
  assert_eq(options.exports_json, Some("new.json"))
  assert_false(Options::default("x").exports)
  assert_eq(Options::default("x").exports_json, None)
  for
    args in [
      ["--exports-json"],
      ["--exports-json", ""],
      ["--exports-json", "n.txt"],
      ["--exports", "--baseline", "b.wasm"],
      ["--exports", "--strict"],
      ["--exports", "--entrypoints"],
      ["--exports", "--imports"],
      ["--exports", "--metadata"],
      ["--exports", "--compress"],
      ["--exports", "--summary-json", "n.json"],
      ["--exports", "--html", "n.html"],
      ["--exports", "--budget", "b.json"],
      ["--exports", "--why-index", "0"],
      ["--exports", "--diff-metadata", "--baseline", "b.wasm"],
    ] {
    assert_true(parse_options(["moonsize", "missing.wasm"] + args) is Err(_))
  }
}
