///|
fn imports_test_name(name : Bytes, wide? : Bool = false) -> Bytes raise {
  assert_true(name.length() < 128)
  let prefix = if wide {
    Bytes::from_array([(name.length() | 128).to_byte(), 0])
  } else {
    Bytes::from_array([name.length().to_byte()])
  }
  prefix + name
}

///|
fn imports_test_entry(
  module_name : Bytes,
  field : Bytes,
  descriptor : Bytes,
  wide? : Bool = false,
) -> Bytes raise {
  imports_test_name(module_name, wide~) +
  imports_test_name(field, wide~) +
  descriptor
}

///|
fn imports_test_section(payload : Bytes) -> Bytes raise {
  assert_true(payload.length() < 16384)
  let size = payload.length()
  let prefix = if size < 128 {
    Bytes::from_array([size.to_byte()])
  } else {
    Bytes::from_array([((size & 127) | 128).to_byte(), (size >> 7).to_byte()])
  }
  b"\x02" + prefix + payload
}

///|
fn imports_test_valid() -> Bytes raise {
  // Both functions and the tag refer to the included () -> () type.
  let entries = imports_test_entry(b"env", b"same", b"\x00\x80\x00", wide=true) +
    imports_test_entry(b"env", b"table", b"\x01\x70\x01\x01\x03") +
    imports_test_entry(b"env", b"same", b"\x00\x00") +
    imports_test_entry(@utf8.encode("宿主"), b"", b"\x02\x03\x01\x02") +
    imports_test_entry(b"", @utf8.encode("line\"\\\n雪"), b"\x03\x7f\x01") +
    imports_test_entry(b"env", b"tag", b"\x04\x00\x00") +
    imports_test_entry(b" spaced.module ", b"t", b"\x01\x6f\x00\x00") +
    imports_test_entry(b" spaced.module ", b"m", b"\x02\x00\x00") +
    imports_test_entry(@utf8.encode("宿主"), b"v", b"\x03\x6f\x00")
  b"\x00asm\x01\x00\x00\x00\x01\x04\x01\x60\x00\x00" +
  imports_test_section(b"\x89\x00" + entries)
}

///|
fn imports_test_inspect(data : Bytes) -> ImportsReport raise {
  match inspect_imports(data) {
    Ok(r) => r
    Err(e) => fail(describe_error(e))
  }
}

///|
fn imports_test_ledger(report : ImportsReport, data : Bytes) -> Unit raise {
  let s = report.ledger
  assert_eq(
    s.import_section_total_bytes,
    s.section_header_bytes + s.count_prefix_bytes + s.entry_bytes,
  )
  assert_eq(
    s.entry_bytes,
    s.module_name_encoding_bytes +
    s.field_name_encoding_bytes +
    s.descriptor_bytes,
  )
  assert_eq(
    s.module_name_encoding_bytes,
    s.module_length_prefix_bytes + s.module_utf8_bytes,
  )
  assert_eq(
    s.field_name_encoding_bytes,
    s.field_length_prefix_bytes + s.field_utf8_bytes,
  )
  let mut entries = 0
  let mut modules = 0
  for group in report.modules {
    modules += group.entry_bytes
    assert_eq(group.entry_count, group.ordinals.length())
  }
  for i, entry in report.entries {
    assert_eq(entry.ordinal, i)
    entries += entry.encoding.size
    assert_true(
      Reader::new_range(data, entry.encoding.offset, entry.encoding.size)
      is Ok(_),
    )
    assert_eq(entry.module_encoding.offset, entry.encoding.offset)
    assert_eq(
      entry.field_encoding.offset,
      entry.module_encoding.offset + entry.module_encoding.size,
    )
    assert_eq(
      entry.descriptor.offset,
      entry.field_encoding.offset + entry.field_encoding.size,
    )
    assert_eq(
      entry.encoding.size,
      entry.module_encoding.size +
      entry.field_encoding.size +
      entry.descriptor.size,
    )
    assert_eq(
      entry.module_encoding.size,
      entry.module_length_prefix_bytes + entry.module_utf8_bytes,
    )
    assert_eq(
      entry.field_encoding.size,
      entry.field_length_prefix_bytes + entry.field_utf8_bytes,
    )
    assert_eq(entry.module_utf8_bytes, @utf8.encode(entry.module_name).length())
    assert_eq(entry.field_utf8_bytes, @utf8.encode(entry.field).length())
  }
  assert_eq(entries, s.entry_bytes)
  assert_eq(modules, entries)
}

///|
test "imports: five kinds, duplicate identities, independent indices and actual byte ledger" {
  let data = imports_test_valid()
  let report = imports_test_inspect(data)
  imports_test_ledger(report, data)
  assert_eq(data.length(), 152)
  assert_eq(report.entry_count, 9)
  assert_eq(report.entries.map(fn(e) { e.kind_index }), [
    0, 0, 1, 0, 0, 0, 1, 1, 1,
  ])
  assert_eq(report.kind_counts, {
    functions: 2,
    tables: 2,
    memories: 2,
    globals: 2,
    tags: 1,
  })
  assert_eq(report.ledger.import_section_total_bytes, 138)
  assert_eq(report.ledger.section_header_bytes, 3)
  assert_eq(report.ledger.count_prefix_bytes, 2)
  assert_eq(report.ledger.entry_bytes, 133)
  assert_eq(report.ledger.module_name_encoding_bytes, 64)
  assert_eq(report.ledger.field_name_encoding_bytes, 39)
  assert_eq(report.ledger.descriptor_bytes, 30)
  assert_eq(report.entries[0].module_length_prefix_bytes, 2)
  assert_eq(report.entries[0].field_length_prefix_bytes, 2)
  assert_eq(report.entries[0].descriptor.size, 3) // Kind plus a wide type index.
  assert_eq(report.entries[0].module_name, report.entries[2].module_name)
  assert_eq(report.entries[0].field, report.entries[2].field)
  assert_eq(report.entries[0].type_index, Some(0U))
  assert_eq(report.entries[5].type_index, Some(0U))
  assert_eq(report.entries[1].type_index, None)
  assert_eq(
    report.entries[3].limits,
    Some({ flags: 3, minimum: 1U, maximum: Some(2U), }),
  )
  assert_eq(report.entries[6].value_type, Some("externref"))
  assert_eq(report.entries[4].mutability, Some(1))
  assert_eq(report.entries[3].module_utf8_bytes, 6)
  assert_eq(report.entries[3].field_utf8_bytes, 0)
  assert_eq(report.modules.map(fn(g) { g.entry_bytes }), [51, 43, 24, 15])
  assert_eq(report.modules[0].ordinals, [0, 1, 2, 5])
  assert_eq(report.modules[1].module_name, " spaced.module ")
}

///|
test "imports: absent and empty sections, full unsigned declarations, sorting, escaping and CLI grammar" {
  let empty = imports_test_inspect(b"\x00asm\x01\x00\x00\x00")
  assert_eq(empty.section, None)
  assert_eq(empty.count_encoding, None)
  assert_eq(empty.ledger.import_section_total_bytes, 0)
  assert_true(render_imports(empty, 1).contains("No import declarations."))
  let zero_data = b"\x00asm\x01\x00\x00\x00\x02\x01\x00"
  let zero = imports_test_inspect(zero_data)
  imports_test_ledger(zero, zero_data)
  assert_eq(zero.section, Some({ offset: 8, size: 3, }))
  assert_eq(zero.ledger.section_header_bytes, 2)
  assert_eq(zero.ledger.count_prefix_bytes, 1)
  // Deliberately only a structural-reading sample: no valid type referent is
  // claimed for u32::MAX, and 32-bit memory semantics are not validated here.
  let unsigned_data = b"\x00asm\x01\x00\x00\x00" +
    imports_test_section(
      b"\x02\x00\x00\x00\xff\xff\xff\xff\x0f\x00\x00\x02\x01\xff\xff\xff\xff\x0f\xff\xff\xff\xff\x0f",
    )
  let unsigned = imports_test_inspect(unsigned_data)
  imports_test_ledger(unsigned, unsigned_data)
  assert_eq(unsigned.entries[0].type_index, Some(4294967295U))
  assert_eq(unsigned.entries[1].limits.unwrap().minimum, 4294967295U)
  assert_true(render_imports_json(unsigned).contains("4294967295"))
  let report = imports_test_inspect(imports_test_valid())
  let top = render_imports(report, 1)
  assert_true(top.contains("IMPORT ENTRIES: showing 1 of 9"))
  assert_true(top.contains("\"env\"  4 declarations  51 B"))
  assert_true(top.contains("6  table  1  22"))
  let text = render_imports(report, 9)
  assert_true(text.contains(Json::string("line\"\\\n雪").stringify()))
  assert_true(text.contains("1  table  0  15"))
  assert_true(text.contains("4  global  0  15"))
  let json = render_imports_json(report)
  assert_true(json.contains("moonsize-imports"))
  assert_true(json.contains(Json::string("line\"\\\n雪").stringify()))
  assert_true(json.contains("\"ordinal\": 8"))
  let options = parse_options([
    "moonsize", "missing.wasm", "--imports-json", "new.json", "--top", "0",
  ]).unwrap()
  assert_true(options.imports)
  assert_eq(options.imports_json, Some("new.json"))
  assert_false(Options::default("x.wasm").imports)
  assert_eq(Options::default("x.wasm").imports_json, None)
  for
    args in [
      ["--imports-json"],
      ["--imports-json", "bad.txt"],
      ["--imports", "--strict"],
      ["--imports", "--metadata"],
      ["--imports", "--baseline", "b.wasm"],
      ["--imports", "--html", "new.html"],
    ] {
    assert_true(parse_options(["moonsize", "missing.wasm"] + args) is Err(_))
  }
}

///|
test "imports: core failures reject truncation, trailing bytes, invalid names and unsupported descriptors" {
  let header = b"\x00asm\x01\x00\x00\x00"
  match inspect_imports(header + imports_test_section(b"\x01\x00\x00\x00")) {
    Err(UnexpectedEnd(_, _)) => ()
    _ => fail("expected bounded truncation")
  }
  match inspect_imports(header + imports_test_section(b"\x00\x7f")) {
    Err(TrailingSectionBytes(offset, kind)) => {
      assert_eq(offset, 11)
      assert_true(same_kind(kind, Import))
    }
    _ => fail("expected trailing import byte")
  }
  for
    (payload, expected_offset, reason) in [
      (b"\x01\x01\xff\x00\x00\x00", 12, "invalid UTF-8"),
      (b"\x01\x00\x00\x02\x04", 14, "unsupported memory64"),
      (b"\x01\x00\x00\x03\x7f\x02", 15, "invalid global mutability"),
      (b"\x01\x00\x00\x04\x01", 14, "unsupported tag attribute"),
      (b"\x01\x00\x00\x09", 13, "unknown import kind"),
      (b"\x01\x00\x00\x02\x01\x02\x01", 14, "minimum exceeds maximum"),
      (b"\x01\x00\x00\x02\x02", 14, "shared memory limits require a maximum"),
      (b"\x01\x00\x00\x01\x63", 14, "unsupported table reference"),
      (b"\x01\x00\x00\x01\x70\x04", 15, "unsupported table64"),
    ] {
    match inspect_imports(header + imports_test_section(payload)) {
      Err(InvalidImportEncoding(offset, message)) => {
        assert_eq(offset, expected_offset)
        assert_true(message.contains(reason))
      }
      _ => fail("expected \{reason} at \{expected_offset}")
    }
  }
}
