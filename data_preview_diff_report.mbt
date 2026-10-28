///|
fn data_preview_diff_hex(value : Int?) -> String {
  match value {
    Some(byte) => byte.to_byte().to_hex()
    None => "--"
  }
}

///|
pub fn render_data_preview_comparison(report : DataPreviewComparison) -> String {
  let out = StringBuilder()
  out.write_string("DATA PAYLOAD WINDOW COMPARISON\n\n")
  for (side, r) in [("Baseline", report.baseline), ("Current", report.current)] {
    out.write_string("\{side}: \{r.file_size} B; SHA-256 \{r.sha256}\n")
    out.write_string(
      "Segment: \{r.segment.index}; payload offset: \{r.payload_offset}; limit: \{r.requested_limit}\n",
    )
    out.write_string(
      "Window file range: offset \{r.window.offset}, size \{r.window.size} bytes\nReturned: \{r.returned_size} bytes; remaining: \{r.remaining_bytes} bytes\n",
    )
    out.write_string(
      "Payload byte ledger: \{r.segment.payload.size} = offset \{r.payload_offset} + returned \{r.returned_size} + remaining \{r.remaining_bytes}\n\n",
    )
  }
  out.write_string(
    "Compared positions: \{report.compared_positions} = same \{report.same_count} + different \{report.different_count} + baseline-only \{report.baseline_only_count} + current-only \{report.current_only_count}\n",
  )
  out.write_string(
    "Returned-size delta: \{report.returned_size_delta} = current-only \{report.current_only_count} - baseline-only \{report.baseline_only_count}\n",
  )
  out.write_string(
    "\nOffsets are decimal window-relative bytes. -- means absent; 00 is an actual zero byte.\nMarkers: . same, ^ different, B baseline-only, C current-only; not edit operations.\nWINDOW OFFSET  BASELINE HEX                                     CURRENT HEX                                      MARKERS\n",
  )
  if report.compared_positions == 0 {
    out.write_string("Both selected windows are empty.\n")
  }
  let mut pos = 0
  while pos < report.positions.length() {
    let count = (report.positions.length() - pos).min(16)
    let before = StringBuilder()
    let after = StringBuilder()
    let marks = StringBuilder()
    for i in 0..<count {
      if i > 0 {
        before.write_string(" ")
        after.write_string(" ")
        marks.write_string(" ")
      }
      let p = report.positions[pos + i]
      before.write_string(data_preview_diff_hex(p.baseline_byte))
      after.write_string(data_preview_diff_hex(p.current_byte))
      marks.write_string(
        match p.status {
          "same_byte" => "."
          "different_byte" => "^"
          "baseline_only" => "B"
          "current_only" => "C"
          _ => "?"
        },
      )
    }
    out.write_string(
      pad_left(pos.to_string(), 13) +
      "  " +
      pad_right(before.to_string(), 47) +
      "  " +
      pad_right(after.to_string(), 47) +
      "  " +
      marks.to_string() +
      "\n",
    )
    pos += count
  }
  out.write_string("\n" + report.scope + "\n")
  out.to_string()
}

///|
pub fn render_data_preview_comparison_json(
  report : DataPreviewComparison,
) -> String {
  let root : Map[String, Json] = Map([])
  root.set("format", Json::string("moonsize-data-preview-diff"))
  root.set("schema_version", int_json(1))
  root.set("baseline", data_preview_json_value(report.baseline))
  root.set("current", data_preview_json_value(report.current))
  root.set("scope", Json::string(report.scope))
  root.set("same_count", int_json(report.same_count))
  root.set("different_count", int_json(report.different_count))
  root.set("baseline_only_count", int_json(report.baseline_only_count))
  root.set("current_only_count", int_json(report.current_only_count))
  root.set("compared_positions", int_json(report.compared_positions))
  root.set("returned_size_delta", int_json(report.returned_size_delta))
  root.set(
    "positions",
    Json::array(
      report.positions.map(fn(p) {
        let row : Map[String, Json] = Map([])
        row.set("window_relative_offset", int_json(p.window_relative_offset))
        row.set("status", Json::string(p.status))
        row.set("baseline_byte", optional_index_json(p.baseline_byte))
        row.set("current_byte", optional_index_json(p.current_byte))
        row.set(
          "baseline_file_offset",
          optional_index_json(p.baseline_file_offset),
        )
        row.set(
          "current_file_offset",
          optional_index_json(p.current_file_offset),
        )
        Json::object(row)
      }),
    ),
  )
  Json::object(root).stringify(indent=2) + "\n"
}
