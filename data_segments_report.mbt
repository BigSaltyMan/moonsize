///|
fn data_mode_text(mode : DataSegmentMode) -> String {
  match mode {
    Active => "active"
    Passive => "passive"
  }
}

///|
fn data_scope() -> String {
  "File offsets are not memory addresses; file bytes are not runtime memory usage. " +
  "Active offset expressions are not_evaluated; passive offsets are not_applicable. " +
  "No source attribution or deletion savings are inferred. This is structural inspection, not full type, constant-expression, memory-index or instantiation validation."
}

///|
/// Payload descending, then original index. Sorting and Top affect display only.
pub fn render_data_segments(report : DataSegmentsReport, top : Int) -> String {
  let ordered = report.entries.copy()
  ordered.sort_by(fn(a, b) {
    if a.payload.size != b.payload.size {
      b.payload.size - a.payload.size
    } else {
      a.index - b.index
    }
  })
  let shown = if top < 0 {
    0
  } else if top < ordered.length() {
    top
  } else {
    ordered.length()
  }
  let mut out = "DATA SEGMENT ENCODINGS\n"
  out += "  data section: " +
    (if report.section is Some(_) { "present" } else { "absent" }) +
    "; total " +
    report.section_size.to_string() +
    " B\n"
  out += "  payload " +
    report.payload_size.to_string() +
    " B; entry metadata " +
    report.entry_metadata_size.to_string() +
    " B; section overhead " +
    (report.header_size + report.count_size).to_string() +
    " B\n"
  out += "  section header " +
    report.header_size.to_string() +
    " B; count field " +
    report.count_size.to_string() +
    " B; datacount " +
    (match report.datacount {
      Some(count) => count.to_string()
      None => "absent"
    }) +
    " (separate section)\n"
  out += "  Showing " +
    shown.to_string() +
    " of " +
    ordered.length().to_string() +
    " entries (payload descending, index ascending)\n\n"
  out += "  INDEX  MODE     MEMORY  FILE OFFSET  ENCODED B  PAYLOAD B\n"
  for i = 0; i < shown; i = i + 1 {
    let entry = ordered[i]
    out += "  " +
      pad_left(entry.index.to_string(), 5) +
      "  " +
      pad_right(data_mode_text(entry.mode), 7) +
      "  " +
      pad_left(
        match entry.memory_index {
          Some(index) => index.to_string()
          None => "n/a"
        },
        6,
      ) +
      "  " +
      pad_left(entry.encoding.offset.to_string(), 11) +
      "  " +
      pad_left(entry.encoding.size.to_string(), 9) +
      "  " +
      pad_left(entry.payload.size.to_string(), 9) +
      "\n"
    out += "         payload file offset " + entry.payload.offset.to_string()
    out += match entry.offset_expression {
      Some(range) =>
        "; expression file offset " +
        range.offset.to_string() +
        ", " +
        range.size.to_string() +
        " B (not_evaluated, includes end)\n"
      None => "; expression not_applicable\n"
    }
  }
  out + "\n  " + data_scope()
}

///|
fn data_range_json(range : DataByteRange) -> Json {
  let fields : Map[String, Json] = Map([])
  fields.set("file_offset", int_json(range.offset))
  fields.set("size", int_json(range.size))
  Json::object(fields)
}

///|
/// Independent schema. All entries in original order; no payload contents.
fn data_segments_json(report : DataSegmentsReport) -> Json {
  let root : Map[String, Json] = Map([])
  root.set("schema_version", int_json(1))
  root.set("format", Json::string("moonsize-data-segments"))
  root.set("scope", Json::string(data_scope()))
  root.set("file_size", int_json(report.file_size))
  let summary : Map[String, Json] = Map([])
  summary.set("present", Json::boolean(report.section is Some(_)))
  summary.set(
    "file_offset",
    optional_index_json(report.section.map(fn(section) { section.offset })),
  )
  summary.set("total_size", int_json(report.section_size))
  summary.set("header_size", int_json(report.header_size))
  summary.set("count_size", int_json(report.count_size))
  summary.set("entry_count", int_json(report.entries.length()))
  summary.set("payload_size", int_json(report.payload_size))
  summary.set("entry_metadata_size", int_json(report.entry_metadata_size))
  summary.set(
    "section_overhead_size",
    int_json(report.header_size + report.count_size),
  )
  root.set("summary", Json::object(summary))
  root.set("datacount", optional_index_json(report.datacount))
  root.set(
    "entries",
    Json::array(
      report.entries.map(fn(entry) {
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
        Json::object(row)
      }),
    ),
  )
  Json::object(root)
}

///|
/// The original single-file format and signature are unchanged.
pub fn render_data_segments_json(report : DataSegmentsReport) -> String {
  data_segments_json(report).stringify(indent=2) + "\n"
}
