///|
fn file_offset_kind_text(kind : FileOffsetKind) -> String {
  match kind {
    ModuleHeader => "module_header"
    SectionHeader => "section_header"
    SectionPayload => "section_payload"
    CodeCount => "code_count"
    FunctionSizePrefix => "function_size_prefix"
    FunctionBodyBytes => "function_body"
    DataEntryCount => "data_count"
    DataEntryMetadata => "data_entry_metadata"
    DataPayload => "data_payload"
  }
}

///|
pub fn render_file_offset(report : FileOffsetReport) -> String {
  let out = StringBuilder()
  out.write_string(
    "WASM FILE OFFSET LOCATION\n\nQuery file offset: \{report.offset} bytes\nInput: \{report.file_size} B\nInput SHA-256: \{report.sha256}\n",
  )
  match report.section {
    None => out.write_string("Physical section: n/a (module header)\n")
    Some(section) => {
      out.write_string(
        "Physical section index: " +
        report.section_index.unwrap().to_string() +
        "; kind: " +
        section.kind.name() +
        "\n",
      )
      out.write_string(
        "Section file range: offset \{section.offset}, size \{section.total_size}; header \{section.total_size - section.payload_size}, payload \{section.payload_size} bytes\n",
      )
      if section.custom_name is Some(name) {
        out.write_string("Custom name: " + search_terminal_string(name) + "\n")
      }
    }
  }
  let region = report.region
  out.write_string(
    "Region: " +
    file_offset_kind_text(region.kind) +
    "\nRegion file range: offset \{region.file_offset}, size \{region.size} bytes (half-open)\nRelative offset: \{region.relative_offset} bytes\n",
  )
  if report.function is Some(stat) {
    out.write_string(
      "Function index: \{stat.index}; name: " +
      search_terminal_string(stat.name) +
      "\nRaw name: " +
      (match stat.raw_name {
        Some(name) => search_terminal_string(name)
        None => "n/a"
      }) +
      "\n",
    )
    out.write_string(
      "Function encoding: offset \{stat.offset}, size \{stat.total_size}; size prefix \{stat.total_size - stat.body_size}, body \{stat.body_size} bytes\n",
    )
  }
  if report.data_segment is Some(entry) {
    out.write_string(
      "Data segment index: \{entry.index}; mode: " +
      data_mode_text(entry.mode) +
      "; memory index: " +
      (match entry.memory_index {
        Some(index) => index.to_string()
        None => "n/a"
      }) +
      "\n",
    )
    out.write_string(
      "Entry file range: offset \{entry.encoding.offset}, size \{entry.encoding.size}; payload file range: offset \{entry.payload.offset}, size \{entry.payload.size} bytes\n",
    )
  }
  out.write_string("\n" + report.scope + "\n")
  out.to_string()
}

///|
fn file_offset_function_json(stat : FunctionStat) -> Json {
  let row : Map[String, Json] = Map([])
  row.set("index", int_json(stat.index))
  row.set("name", Json::string(stat.name))
  row.set("raw_name", path_optional_string(stat.raw_name))
  row.set("module_name", Json::string(stat.module_name))
  let prefix = stat.total_size - stat.body_size
  row.set(
    "encoding",
    data_range_json({ offset: stat.offset, size: stat.total_size, }),
  )
  row.set(
    "size_prefix",
    data_range_json({ offset: stat.offset, size: prefix, }),
  )
  row.set(
    "body",
    data_range_json({ offset: stat.offset + prefix, size: stat.body_size, }),
  )
  Json::object(row)
}

///|
fn file_offset_segment_json(section : Section) -> Json {
  let row : Map[String, Json] = Map([])
  row.set("id", int_json(section.id))
  row.set("kind", Json::string(section.kind.name()))
  row.set("custom_name", path_optional_string(section.custom_name))
  let header_size = section.total_size - section.payload_size
  row.set(
    "encoding",
    data_range_json({ offset: section.offset, size: section.total_size, }),
  )
  row.set(
    "header",
    data_range_json({ offset: section.offset, size: header_size, }),
  )
  row.set(
    "payload",
    data_range_json({
      offset: section.offset + header_size,
      size: section.payload_size,
    }),
  )
  Json::object(row)
}

///|
fn file_offset_data_segment_json(entry : DataSegment) -> Json {
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
}

///|
/// New independent format, rendering only the already located ownership.
fn file_offset_json_value(report : FileOffsetReport) -> Json {
  let root : Map[String, Json] = Map([])
  root.set("format", Json::string("moonsize-file-offset"))
  root.set("schema_version", int_json(1))
  root.set("file_size", int_json(report.file_size))
  root.set("sha256", Json::string(report.sha256))
  root.set("offset", int_json(report.offset))
  root.set("section_index", optional_index_json(report.section_index))
  root.set(
    "section",
    match report.section {
      Some(section) => file_offset_segment_json(section)
      None => Json::null()
    },
  )
  root.set(
    "function",
    match report.function {
      Some(stat) => file_offset_function_json(stat)
      None => Json::null()
    },
  )
  root.set(
    "data_segment",
    match report.data_segment {
      Some(entry) => file_offset_data_segment_json(entry)
      None => Json::null()
    },
  )
  let region : Map[String, Json] = Map([])
  region.set("kind", Json::string(file_offset_kind_text(report.region.kind)))
  region.set("file_offset", int_json(report.region.file_offset))
  region.set("size", int_json(report.region.size))
  region.set("relative_offset", int_json(report.region.relative_offset))
  root.set("region", Json::object(region))
  root.set("scope", Json::string(report.scope))
  Json::object(root)
}

///|
/// Preserve the original standalone format; refinement nests the same object.
pub fn render_file_offset_json(report : FileOffsetReport) -> String {
  file_offset_json_value(report).stringify(indent=2) + "\n"
}
