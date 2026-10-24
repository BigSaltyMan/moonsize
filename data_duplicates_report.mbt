///|
pub fn render_duplicate_data_json(report : DuplicateDataReport) -> String {
  let s = report.summary
  let summary : Map[String, Json] = Map([])
  summary.set("segment_count", int_json(s.segment_count))
  summary.set("duplicate_group_count", int_json(s.duplicate_group_count))
  summary.set("duplicate_member_count", int_json(s.duplicate_member_count))
  summary.set("singleton_count", int_json(s.singleton_count))
  summary.set("total_payload_bytes", int_json(s.total_payload_bytes))
  summary.set(
    "duplicate_member_payload_bytes",
    int_json(s.duplicate_member_payload_bytes),
  )
  summary.set("singleton_payload_bytes", int_json(s.singleton_payload_bytes))
  summary.set(
    "total_entry_encoded_bytes",
    int_json(s.total_entry_encoded_bytes),
  )
  summary.set(
    "total_entry_metadata_bytes",
    int_json(s.total_entry_metadata_bytes),
  )
  summary.set(
    "duplicate_member_metadata_bytes",
    int_json(s.duplicate_member_metadata_bytes),
  )
  summary.set(
    "duplicate_member_encoded_bytes",
    int_json(s.duplicate_member_encoded_bytes),
  )
  summary.set("singleton_metadata_bytes", int_json(s.singleton_metadata_bytes))
  summary.set("singleton_encoded_bytes", int_json(s.singleton_encoded_bytes))
  summary.set("data_section_bytes", int_json(s.data_section_bytes))
  summary.set("section_header_bytes", int_json(s.section_header_bytes))
  summary.set("count_prefix_bytes", int_json(s.count_prefix_bytes))
  Json::object({
    "format": Json::string("moonsize-data-duplicates"),
    "schema_version": int_json(1),
    "file_size": int_json(report.file_size),
    "sha256": Json::string(report.sha256),
    "comparison_scope": Json::string(report.comparison_scope),
    "summary": Json::object(summary),
    "data_segments": data_segments_json(report.data_segments),
    "groups": Json::array(
      report.groups.map(fn(g) {
        Json::object({
          "id": int_json(g.id),
          "sha256": Json::string(g.sha256),
          "payload_size": int_json(g.payload_size),
          "member_count": int_json(g.member_count),
          "member_indices": Json::array(g.member_indices.map(int_json)),
          "member_payload_bytes": int_json(g.member_payload_bytes),
          "member_metadata_bytes": int_json(g.member_metadata_bytes),
          "member_encoded_bytes": int_json(g.member_encoded_bytes),
        })
      }),
    ),
  }).stringify(indent=2) +
  "\n"
}

///|
pub fn render_duplicate_data(report : DuplicateDataReport, top : Int) -> String {
  let out = StringBuilder()
  let s = report.summary
  out.write_string(
    "DUPLICATE DATA PAYLOADS\n\nInput: \{report.file_size} B; SHA-256 \{report.sha256}\n",
  )
  out.write_string(
    "Duplicate groups: \{s.duplicate_group_count}; segments: \{s.segment_count} = duplicate-group members \{s.duplicate_member_count} + singletons \{s.singleton_count}\n",
  )
  out.write_string(
    "Payload bytes: \{s.total_payload_bytes} B = duplicate-group members \{s.duplicate_member_payload_bytes} B + singletons \{s.singleton_payload_bytes} B\n",
  )
  out.write_string(
    "Entry encoding bytes: \{s.total_entry_encoded_bytes} B = payload \{s.total_payload_bytes} B + metadata \{s.total_entry_metadata_bytes} B\n",
  )
  out.write_string(
    "Duplicate-member encoding bytes: \{s.duplicate_member_encoded_bytes} B = payload \{s.duplicate_member_payload_bytes} B + metadata \{s.duplicate_member_metadata_bytes} B\n",
  )
  out.write_string(
    "Singleton encoding bytes: \{s.singleton_encoded_bytes} B = payload \{s.singleton_payload_bytes} B + metadata \{s.singleton_metadata_bytes} B\n",
  )
  out.write_string(
    "Data section bytes: \{s.data_section_bytes} B = section header \{s.section_header_bytes} B + count prefix \{s.count_prefix_bytes} B + entries \{s.total_entry_encoded_bytes} B\n",
  )
  out.write_string(
    "Data section: " +
    (if report.data_segments.section is Some(_) { "present" } else { "absent" }) +
    "; DataCount " +
    report.data_segments.datacount
    .map(fn(n) { n.to_string() })
    .unwrap_or("absent") +
    " (separate from data ledger)\n",
  )
  let shown = top.max(0).min(report.groups.length())
  out.write_string(
    "\nDUPLICATE GROUPS: showing \{shown} of \{report.groups.length()}\n",
  )
  for i in 0..<shown {
    let g = report.groups[i]
    out.write_string(
      "Group #\{g.id}; SHA-256 \{g.sha256}; payload \{g.payload_size} B; members \{g.member_count}\n",
    )
    out.write_string(
      "  All-member bytes: payload \{g.member_payload_bytes} B + metadata \{g.member_metadata_bytes} B = encoded \{g.member_encoded_bytes} B\n",
    )
    let preview = g.member_count.min(20)
    out.write_string(
      "  Members: showing \{preview} of \{g.member_count} (preview limit 20)\n",
    )
    out.write_string(
      "  INDEX  MODE  MEMORY  ENCODED B  PAYLOAD B  FILE OFFSET\n",
    )
    for n in 0..<preview {
      let e = report.data_segments.entries[g.member_indices[n]]
      out.write_string(
        "  \{e.index}  " +
        data_mode_text(e.mode) +
        "  " +
        e.memory_index.map(fn(m) { m.to_string() }).unwrap_or("null") +
        "  \{e.encoding.size}  \{e.payload.size}  \{e.encoding.offset}\n",
      )
      out.write_string(
        "    payload file offset \{e.payload.offset}; mode encoding \{e.mode_size} B; memory index \{e.memory_index_size} B; length prefix \{e.payload_length_size} B; expression " +
        (match e.offset_expression {
          Some(r) =>
            "file offset \{r.offset}, \{r.size} B (not_evaluated, includes end)"
          None => "not_applicable"
        }) +
        "\n",
      )
    }
  }
  if report.groups.is_empty() {
    out.write_string("No identical data payload groups found.\n")
  }
  out.write_string("\n" + report.comparison_scope + "\n")
  out.to_string()
}
