///|
fn data_preview_hex(bytes : BytesView) -> String {
  let out = StringBuilder()
  for byte in bytes {
    out.write_string(byte.to_hex())
  }
  out.to_string()
}

///|
pub fn render_data_preview(report : DataPreviewReport) -> String {
  let out = StringBuilder()
  let entry = report.segment
  let memory = match entry.memory_index {
    Some(index) => index.to_string()
    None => "n/a"
  }
  out.write_string("DATA PAYLOAD BYTE PREVIEW\n\n")
  out.write_string(
    "Input: \{report.file_size} B\nInput SHA-256: \{report.sha256}\n",
  )
  out.write_string(
    "Segment: \{entry.index} of \{report.segment_count} entries (zero-based); mode: " +
    data_mode_text(entry.mode) +
    "; memory index: " +
    memory +
    "\n",
  )
  out.write_string(
    "Payload file range: offset \{entry.payload.offset}, size \{entry.payload.size} bytes\n",
  )
  out.write_string(
    "Requested payload offset: \{report.payload_offset}; limit: \{report.requested_limit} bytes\n",
  )
  out.write_string(
    "Window file range: offset \{report.window.offset}, size \{report.window.size} bytes\nReturned: \{report.returned_size} bytes; remaining: \{report.remaining_bytes} bytes\n",
  )
  out.write_string(
    "Payload byte ledger: \{entry.payload.size} = offset \{report.payload_offset} + returned \{report.returned_size} + remaining \{report.remaining_bytes}\n",
  )
  out.write_string(
    "\nOffsets are decimal bytes. ASCII shows only 0x20..0x7e; other bytes are dots.\nPAYLOAD OFFSET  FILE OFFSET  HEX BYTES                                        ASCII\n",
  )
  if report.returned_size == 0 {
    out.write_string("Empty window (at payload end).\n")
  }
  let mut pos = 0
  while pos < report.bytes.length() {
    let count = (report.bytes.length() - pos).min(16)
    let hex = StringBuilder()
    let ascii = StringBuilder()
    for i in 0..<count {
      let byte = report.bytes[pos + i]
      if i > 0 {
        hex.write_string(" ")
      }
      hex.write_string(byte.to_hex())
      ascii.write_string(
        if byte >= 0x20 && byte <= 0x7e {
          byte.to_char().to_string()
        } else {
          "."
        },
      )
    }
    out.write_string(
      pad_left((report.payload_offset + pos).to_string(), 14) +
      "  " +
      pad_left((report.window.offset + pos).to_string(), 11) +
      "  " +
      pad_right(hex.to_string(), 47) +
      "  " +
      ascii.to_string() +
      "\n",
    )
    pos += count
  }
  out.write_string("\n" + report.scope + "\n")
  out.to_string()
}

///|
/// Contains the selected entry only, plus the entire returned bounded window.
pub fn render_data_preview_json(report : DataPreviewReport) -> String {
  let root : Map[String, Json] = Map([])
  root.set("format", Json::string("moonsize-data-preview"))
  root.set("schema_version", int_json(1))
  root.set("file_size", int_json(report.file_size))
  root.set("sha256", Json::string(report.sha256))
  root.set("segment_count", int_json(report.segment_count))
  let entry = report.segment
  let row : Map[String, Json] = Map([])
  row.set("index", int_json(entry.index))
  row.set("mode", Json::string(data_mode_text(entry.mode)))
  row.set("memory_index", optional_index_json(entry.memory_index))
  row.set("encoding", data_range_json(entry.encoding))
  row.set("payload", data_range_json(entry.payload))
  row.set(
    "offset_expression",
    match entry.offset_expression {
      Some(range) => data_range_json(range)
      None => Json::null()
    },
  )
  row.set(
    "offset_status",
    Json::string(
      if entry.mode == Active {
        "not_evaluated"
      } else {
        "not_applicable"
      },
    ),
  )
  row.set("mode_size", int_json(entry.mode_size))
  row.set("memory_index_size", int_json(entry.memory_index_size))
  row.set("payload_length_size", int_json(entry.payload_length_size))
  root.set("segment", Json::object(row))
  root.set("payload_offset", int_json(report.payload_offset))
  root.set("requested_limit", int_json(report.requested_limit))
  root.set("window", data_range_json(report.window))
  root.set("returned_size", int_json(report.returned_size))
  root.set("remaining_bytes", int_json(report.remaining_bytes))
  root.set("hex", Json::string(data_preview_hex(report.bytes[:])))
  root.set("scope", Json::string(report.scope))
  Json::object(root).stringify(indent=2) + "\n"
}
