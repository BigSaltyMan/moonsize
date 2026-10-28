///|
pub fn render_data_hex_search(
  report : DataHexSearchReport,
  top : Int,
) -> String {
  let out = StringBuilder()
  out.write_string("DATA PAYLOAD HEX SEARCH\n\n")
  out.write_string("Query hex: " + report.query_hex + "\n")
  out.write_string("Query bytes: \{report.query_size} bytes\n")
  out.write_string(
    "Input: \{report.file_size} B\nInput SHA-256: \{report.sha256}\n",
  )
  out.write_string(report.matching_rule + "\n")
  let source = report.data_segments
  out.write_string(
    "\nData encoded bytes: \{source.section_size} = payload \{source.payload_size} + entry metadata \{source.entry_metadata_size} + section overhead \{source.header_size + source.count_size}\n",
  )
  out.write_string(
    "Segments: \{report.segment_count} = matched \{report.matched_segment_count} + unmatched \{report.unmatched_segment_count}\nOccurrences: \{report.occurrence_count}\n",
  )
  let shown = top.max(0).min(report.occurrence_count)
  out.write_string(
    "\nMATCHES: showing \{shown} of \{report.occurrence_count}\nSEGMENT  PAYLOAD OFFSET  FILE OFFSET  LENGTH\n",
  )
  if source.section is None {
    out.write_string("No data section.\n")
  } else if source.entries.is_empty() {
    out.write_string("Empty data section (zero entries).\n")
  } else if report.matches.is_empty() {
    out.write_string("No matches in data payloads.\n")
  }
  for i in 0..<shown {
    let hit = report.matches[i]
    out.write_string(
      "\{hit.segment_index}  \{hit.payload_offset}  \{hit.file_offset}  \{hit.size}\n",
    )
  }
  out.write_string("\n" + report.scope + "\n")
  out.to_string()
}

///|
/// Independent schema: nested original ledger and complete ordered matches.
pub fn render_data_hex_search_json(report : DataHexSearchReport) -> String {
  let root : Map[String, Json] = Map([])
  root.set("format", Json::string("moonsize-data-hex-search"))
  root.set("schema_version", int_json(1))
  root.set("file_size", int_json(report.file_size))
  root.set("sha256", Json::string(report.sha256))
  root.set("query_hex", Json::string(report.query_hex))
  root.set("query_size", int_json(report.query_size))
  root.set("matching_rule", Json::string(report.matching_rule))
  root.set("scope", Json::string(report.scope))
  root.set("data_segments", data_segments_json(report.data_segments))
  root.set("segment_count", int_json(report.segment_count))
  root.set("matched_segment_count", int_json(report.matched_segment_count))
  root.set("unmatched_segment_count", int_json(report.unmatched_segment_count))
  root.set("occurrence_count", int_json(report.occurrence_count))
  root.set(
    "matches",
    Json::array(
      report.matches.map(fn(hit) {
        let row : Map[String, Json] = Map([])
        row.set("segment_index", int_json(hit.segment_index))
        row.set("payload_offset", int_json(hit.payload_offset))
        row.set("file_offset", int_json(hit.file_offset))
        row.set("size", int_json(hit.size))
        Json::object(row)
      }),
    ),
  )
  Json::object(root).stringify(indent=2) + "\n"
}
