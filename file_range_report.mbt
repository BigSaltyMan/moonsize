///|
pub fn render_file_range(report : FileRangeReport, top : Int) -> String {
  let out = StringBuilder()
  out.write_string(
    "WASM FILE RANGE OWNERSHIP\n\nInput: \{report.file_size} B\nInput SHA-256: \{report.sha256}\nQuery file range: [\{report.query.offset}, \{report.query.offset + report.query.size}), length \{report.query.size} B\nCovered size: \{report.covered_size} B (all parts)\nParts: \{report.parts.length()}\n",
  )
  let shown = if top < 0 {
    0
  } else if top < report.parts.length() {
    top
  } else {
    report.parts.length()
  }
  out.write_string(
    "\nPARTS: showing \{shown} of \{report.parts.length()}\nKIND  SECTION  OVERLAP OFFSET  LENGTH  OWNER OFFSET  SIZE  FUNCTION  DATA ENTRY\n",
  )
  for i in 0..<shown {
    let part = report.parts[i]
    let section = match part.section_index {
      Some(n) => n.to_string()
      None => "n/a"
    }
    let function = match part.function {
      Some(stat) => stat.index.to_string()
      None => "n/a"
    }
    let entry = match part.data_segment {
      Some(entry) => entry.index.to_string()
      None => "n/a"
    }
    out.write_string(
      file_offset_kind_text(part.kind) +
      "  " +
      section +
      "  \{part.overlap_range.offset}  \{part.overlap_range.size}  \{part.owner_range.offset}  \{part.owner_range.size}  " +
      function +
      "  " +
      entry +
      "\n",
    )
    if part.function is Some(stat) {
      out.write_string(
        "  Function name: " + search_terminal_string(stat.name) + "\n",
      )
    }
    if part.section is Some(section) && section.custom_name is Some(name) {
      out.write_string("  Custom name: " + search_terminal_string(name) + "\n")
    }
  }
  if report.query.size == 0 {
    out.write_string("Empty range: no byte owners.\n")
  }
  out.write_string(
    "\nCoverage ledger uses all parts; displayed rows may be a subset.\n" +
    report.scope +
    "\n",
  )
  out.to_string()
}

///|
pub fn render_file_range_json(report : FileRangeReport) -> String {
  let root : Map[String, Json] = Map([])
  root.set("format", Json::string("moonsize-file-range"))
  root.set("schema_version", int_json(1))
  root.set("file_size", int_json(report.file_size))
  root.set("sha256", Json::string(report.sha256))
  root.set("query", data_range_json(report.query))
  root.set("covered_size", int_json(report.covered_size))
  root.set(
    "parts",
    Json::array(
      report.parts.map(fn(part) {
        let row : Map[String, Json] = Map([])
        row.set("kind", Json::string(file_offset_kind_text(part.kind)))
        row.set("owner_range", data_range_json(part.owner_range))
        row.set("overlap_range", data_range_json(part.overlap_range))
        row.set("query_relative_offset", int_json(part.query_relative_offset))
        row.set("owner_relative_offset", int_json(part.owner_relative_offset))
        row.set("section_index", optional_index_json(part.section_index))
        row.set(
          "section",
          match part.section {
            Some(s) => file_offset_segment_json(s)
            None => Json::null()
          },
        )
        row.set(
          "function",
          match part.function {
            Some(s) => file_offset_function_json(s)
            None => Json::null()
          },
        )
        row.set(
          "data_segment",
          match part.data_segment {
            Some(s) => file_offset_data_segment_json(s)
            None => Json::null()
          },
        )
        Json::object(row)
      }),
    ),
  )
  root.set("scope", Json::string(report.scope))
  Json::object(root).stringify(indent=2) + "\n"
}
