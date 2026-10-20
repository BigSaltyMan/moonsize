///|
fn data_inspected(sections : Bytes) -> DataSegmentsReport raise {
  match inspect_data_segments(b"\x00asm\x01\x00\x00\x00" + sections) {
    Ok(report) => report
    Err(error) => fail(describe_error(error))
  }
}

///|
fn data_mixed_sections() -> Bytes {
  // One memory, three data entries: active implicit, empty passive, active explicit.
  b"\x05\x03\x01\x00\x01\x0c\x01\x03\x0b\x14\x03\x00\x41\x0b\x0b\x03abc\x01\x00\x02\x00\x41\x00\x0b\x03xyz"
}

///|
fn assert_data_ledger(report : DataSegmentsReport) -> Unit raise {
  let mut total = 0
  let mut payload = 0
  for entry in report.entries {
    let expression_size = entry.offset_expression
      .map(fn(range) { range.size })
      .unwrap_or(0)
    assert_eq(
      entry.encoding.size,
      entry.mode_size +
      entry.memory_index_size +
      expression_size +
      entry.payload_length_size +
      entry.payload.size,
    )
    assert_eq(
      entry.payload.offset + entry.payload.size,
      entry.encoding.offset + entry.encoding.size,
    )
    payload += entry.payload.size
    total += entry.encoding.size
  }
  assert_eq(report.section_size, report.header_size + report.count_size + total)
  assert_eq(report.payload_size, payload)
  assert_eq(total, report.entry_metadata_size + payload)
}

///|
test "data segments distinguish missing, empty section and empty payload" {
  let absent = data_inspected(b"")
  assert_true(absent.section is None)
  assert_eq(absent.entries.length(), 0)
  assert_data_ledger(absent)
  let empty = data_inspected(b"\x0c\x01\x00\x0b\x01\x00")
  assert_true(empty.section is Some(_))
  assert_eq(empty.section_size, 3)
  assert_eq(empty.count_size, 1)
  assert_eq(empty.entries.length(), 0)
  assert_data_ledger(empty)
  let entry = data_inspected(b"\x0b\x03\x01\x01\x00")
  assert_eq(entry.entries.length(), 1)
  assert_eq(entry.entries[0].payload.size, 0)
  assert_eq(entry.entries[0].encoding.size, 2)
  assert_data_ledger(entry)
}

///|
test "data segments three modes and immediate 0b have exact file ranges" {
  let report = data_inspected(data_mixed_sections())
  assert_eq(report.file_size, 38)
  assert_eq(report.section_size, 22)
  assert_eq(report.datacount, Some(3))
  assert_eq(report.payload_size, 6)
  assert_eq(report.entry_metadata_size, 13)
  assert_eq(report.entries[0].encoding, { offset: 19, size: 8, })
  assert_eq(report.entries[0].offset_expression, Some({ offset: 20, size: 3, }))
  assert_eq(report.entries[0].payload, { offset: 24, size: 3, })
  assert_eq(report.entries[0].memory_index, Some(0))
  assert_eq(report.entries[1].mode, Passive)
  assert_eq(report.entries[1].offset_expression, None)
  assert_eq(report.entries[1].memory_index, None)
  assert_eq(report.entries[2].mode, Active)
  assert_eq(report.entries[2].memory_index, Some(0))
  assert_eq(report.entries[2].memory_index_size, 1)
  assert_eq(report.entries[2].encoding, { offset: 29, size: 9, })
  assert_data_ledger(report)
}

///|
test "data segments preserve multibyte and nonshortest field widths" {
  let report = data_inspected(
    b"\x0b\x87\x81\x00\x81\x00\x81\x00\x80\x81\x00" + Bytes::make(128, 65),
  )
  assert_eq(report.section_size, 139)
  assert_eq(report.header_size, 4)
  assert_eq(report.count_size, 2)
  assert_eq(report.entries[0].mode_size, 2)
  assert_eq(report.entries[0].payload_length_size, 3)
  assert_eq(report.entries[0].payload, { offset: 19, size: 128, })
  assert_data_ledger(report)
  // This inspection deliberately does not validate that memory 128 exists.
  let explicit = data_inspected(
    b"\x0c\x02\x81\x00\x0b\x08\x01\x02\x80\x01\x41\x00\x0b\x00",
  )
  assert_eq(explicit.datacount, Some(1))
  assert_eq(explicit.entries[0].memory_index, Some(128))
  assert_eq(explicit.entries[0].memory_index_size, 2)
  assert_data_ledger(explicit)
}

///|
test "data segments reject bad mode, truncation, decoder failures and trailing bytes" {
  for
    (payload, expected) in [
      (b"\x0b\x02\x01\x03", "unsupported data segment mode 3"),
      (b"\x0b\x04\x01\x01\x02a", "unexpected end"),
      (b"\x0b\x03\x01\x00\x41", "unexpected end"),
      (b"\x0b\x03\x01\x00\xff", "opcode"),
      (b"\x0b\x02\x00\x00", "trailing bytes in data section at offset 11"),
      (b"\x0c\x02\x00\x00", "trailing bytes in datacount section at offset 11"),
      (b"\x0c\x01\x01", "datacount mismatch: 1 declared, 0 data entries"),
      (
        b"\x0c\x01\x00\x0b\x03\x01\x01\x00", "datacount mismatch: 0 declared, 1 data entries",
      ),
    ] {
    match inspect_data_segments(b"\x00asm\x01\x00\x00\x00" + payload) {
      Err(error) => assert_true(describe_error(error).contains(expected))
      Ok(_) => fail("bad data encoding accepted")
    }
  }
  match inspect_data_segments(b"\x00asm\x01\x00\x00\x00\x0b\x02\x01\x03") {
    Err(InvalidDataEncoding(11, _)) => ()
    _ => fail("mode error must identify the mode field")
  }
}

///|
test "data segments render Top without changing full JSON or summary" {
  let report = data_inspected(data_mixed_sections())
  let text = render_data_segments(report, 1)
  assert_true(text.contains("Showing 1 of 3 entries"))
  assert_true(
    text.contains("payload 6 B; entry metadata 13 B; section overhead 3 B"),
  )
  assert_true(text.contains("payload file offset 24"))
  assert_false(text.contains("payload file offset 35"))
  assert_true(text.contains("not_evaluated"))
  assert_true(text.contains("not memory addresses"))
  assert_true(
    render_data_segments(report, 0).contains("Showing 0 of 3 entries"),
  )
  let json = @json.parse(render_data_segments_json(report)) catch {
    _ => fail("invalid JSON")
  }
  match json {
    Object(fields) => {
      assert_eq(fields.get("schema_version"), Some(int_json(1)))
      match fields.get("entries") {
        Some(Array(entries)) => {
          assert_eq(entries.length(), 3)
          for i = 0; i < 3; i = i + 1 {
            match entries[i] {
              Object(row) => assert_eq(row.get("index"), Some(int_json(i)))
              _ => fail("expected entry object")
            }
          }
        }
        _ => fail("expected complete entry array")
      }
    }
    _ => fail("expected report object")
  }
  assert_eq(report.entries[1].index, 1)
}
