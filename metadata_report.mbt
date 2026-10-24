///|
fn metadata_range_json(range : MetadataRange) -> Json {
  let row : Map[String, Json] = Map([])
  row.set("offset", int_json(range.offset))
  row.set("size", int_json(range.size))
  Json::object(row)
}

///|
fn metadata_optional_range_json(range : MetadataRange?) -> Json {
  match range {
    Some(r) => metadata_range_json(r)
    None => Json::null()
  }
}

///|
/// All u32 values are exact in Double (53 significant bits); repr preserves the
/// unsigned decimal spelling, including values above the signed Int maximum.
fn metadata_uint_json(value : UInt) -> Json {
  Json::number(value.to_double(), repr=value.to_string())
}

///|
pub fn render_metadata_json(report : MetadataReport) -> String {
  let root : Map[String, Json] = Map([])
  root.set("format", Json::string("moonsize-metadata"))
  root.set("schema_version", int_json(1))
  root.set("file_size", int_json(report.file_size))
  root.set("sha256", Json::string(report.sha256))
  root.set(
    "custom_fraction",
    Json::number(
      report.summary.custom_bytes.to_double() / report.file_size.to_double(),
    ),
  )
  root.set("byte_ledger_complete", Json::boolean(report.byte_ledger_complete))
  root.set("custom_name_status", Json::string(report.custom_name_status))
  root.set("name_details_status", Json::string(report.name_details_status))
  root.set("modeling_scope", Json::string(report.modeling_scope))
  let s = report.summary
  let summary : Map[String, Json] = Map([])
  summary.set("custom_count", int_json(s.custom_count))
  summary.set("custom_bytes", int_json(s.custom_bytes))
  summary.set("section_header_bytes", int_json(s.section_header_bytes))
  summary.set(
    "custom_name_encoding_bytes",
    int_json(s.custom_name_encoding_bytes),
  )
  summary.set("content_bytes", int_json(s.content_bytes))
  summary.set("unavailable_custom_count", int_json(s.unavailable_custom_count))
  summary.set("unavailable_custom_bytes", int_json(s.unavailable_custom_bytes))
  summary.set("name_custom_count", int_json(s.name_custom_count))
  summary.set("name_content_bytes", int_json(s.name_content_bytes))
  summary.set("name_subsection_bytes", int_json(s.name_subsection_bytes))
  summary.set(
    "unbounded_name_tail_bytes",
    int_json(s.unbounded_name_tail_bytes),
  )
  summary.set(
    "function_name_payload_bytes",
    int_json(s.function_name_payload_bytes),
  )
  summary.set(
    "function_name_count_prefix_bytes",
    int_json(s.function_name_count_prefix_bytes),
  )
  summary.set(
    "parsed_function_record_count",
    int_json(s.parsed_function_record_count),
  )
  summary.set(
    "parsed_function_record_bytes",
    int_json(s.parsed_function_record_bytes),
  )
  summary.set(
    "function_name_unparsed_bytes",
    int_json(s.function_name_unparsed_bytes),
  )
  summary.set(
    "function_index_prefix_bytes",
    int_json(s.function_index_prefix_bytes),
  )
  summary.set(
    "function_name_length_prefix_bytes",
    int_json(s.function_name_length_prefix_bytes),
  )
  summary.set("function_name_utf8_bytes", int_json(s.function_name_utf8_bytes))
  summary.set(
    "unavailable_function_name_count",
    int_json(s.unavailable_function_name_count),
  )
  root.set("summary", Json::object(summary))
  root.set(
    "categories",
    Json::array(
      report.categories.map(fn(group) {
        let row : Map[String, Json] = Map([])
        row.set("category", Json::string(group.category))
        row.set(
          "custom_ordinals",
          Json::array(group.custom_ordinals.map(int_json)),
        )
        row.set("total_bytes", int_json(group.total_bytes))
        Json::object(row)
      }),
    ),
  )
  root.set(
    "name_groups",
    Json::array(
      report.name_groups.map(fn(group) {
        let row : Map[String, Json] = Map([])
        row.set("name", path_optional_string(group.name))
        row.set(
          "custom_ordinals",
          Json::array(group.custom_ordinals.map(int_json)),
        )
        row.set("total_bytes", int_json(group.total_bytes))
        Json::object(row)
      }),
    ),
  )
  root.set(
    "customs",
    Json::array(
      report.customs.map(fn(item) {
        let row : Map[String, Json] = Map([])
        row.set("ordinal", int_json(item.ordinal))
        row.set("section_ordinal", int_json(item.section_ordinal))
        row.set("encoding", metadata_range_json(item.encoding))
        row.set("section_header_bytes", int_json(item.section_header_bytes))
        row.set("name_encoding", metadata_range_json(item.name_encoding))
        row.set(
          "name_length_prefix_bytes",
          int_json(item.name_length_prefix_bytes),
        )
        row.set("name_bytes", metadata_range_json(item.name_bytes))
        row.set("name", path_optional_string(item.name))
        row.set("category", Json::string(item.category))
        row.set("content", metadata_range_json(item.content))
        row.set("status", Json::string(item.status))
        row.set("name_subsection_bytes", int_json(item.name_subsection_bytes))
        row.set(
          "unbounded_tail",
          metadata_optional_range_json(item.unbounded_tail),
        )
        Json::object(row)
      }),
    ),
  )
  root.set(
    "subsections",
    Json::array(
      report.subsections.map(fn(sub) {
        let row : Map[String, Json] = Map([])
        row.set("custom_ordinal", int_json(sub.custom_ordinal))
        row.set("ordinal", int_json(sub.ordinal))
        row.set("id", int_json(sub.id))
        row.set("encoding", metadata_range_json(sub.encoding))
        row.set("header_bytes", int_json(sub.header_bytes))
        row.set("payload", metadata_range_json(sub.payload))
        row.set("status", Json::string(sub.status))
        row.set(
          "declared_count",
          match sub.declared_count {
            Some(n) => metadata_uint_json(n)
            None => Json::null()
          },
        )
        row.set("count_prefix_bytes", int_json(sub.count_prefix_bytes))
        row.set("parsed_record_bytes", int_json(sub.parsed_record_bytes))
        row.set("unparsed", metadata_optional_range_json(sub.unparsed))
        Json::object(row)
      }),
    ),
  )
  root.set(
    "function_names",
    Json::array(
      report.function_names.map(fn(record) {
        let row : Map[String, Json] = Map([])
        row.set("custom_ordinal", int_json(record.custom_ordinal))
        row.set("subsection_ordinal", int_json(record.subsection_ordinal))
        row.set("ordinal", int_json(record.ordinal))
        row.set("function_index", metadata_uint_json(record.function_index))
        row.set("encoding", metadata_range_json(record.encoding))
        row.set("index_prefix_bytes", int_json(record.index_prefix_bytes))
        row.set(
          "name_length_prefix_bytes",
          int_json(record.name_length_prefix_bytes),
        )
        row.set("name_bytes", metadata_range_json(record.name_bytes))
        row.set("name", path_optional_string(record.name))
        Json::object(row)
      }),
    ),
  )
  root.set(
    "diagnostics",
    Json::array(
      report.diagnostics.map(fn(diagnostic) {
        let row : Map[String, Json] = Map([])
        row.set("offset", int_json(diagnostic.offset))
        row.set("custom_ordinal", int_json(diagnostic.custom_ordinal))
        row.set(
          "subsection_ordinal",
          optional_index_json(diagnostic.subsection_ordinal),
        )
        row.set("reason", Json::string(diagnostic.reason))
        Json::object(row)
      }),
    ),
  )
  Json::object(root).stringify(indent=2) + "\n"
}

///|
fn metadata_range_text(range : MetadataRange) -> String {
  "file offset \{range.offset}, \{range.size} B"
}

///|
pub fn render_metadata(report : MetadataReport, top : Int) -> String {
  let out = StringBuilder()
  let s = report.summary
  out.write_string("METADATA FILE BYTES\n\n")
  out.write_string("Input: \{report.file_size} B; SHA-256 \{report.sha256}\n")
  out.write_string(
    "Custom sections: \{s.custom_count}; \{s.custom_bytes} B (" +
    share_text(s.custom_bytes, report.file_size) +
    " of file)\n",
  )
  out.write_string(
    "Custom bytes: \{s.custom_bytes} B = section headers \{s.section_header_bytes} B + custom-name encodings \{s.custom_name_encoding_bytes} B + contents \{s.content_bytes} B\n",
  )
  out.write_string("\nCATEGORY SUMMARY (all instances)\n")
  for group in report.categories {
    out.write_string(
      "\{group.category}: \{group.custom_ordinals.length()} instances, \{group.total_bytes} B\n",
    )
  }
  out.write_string(
    "\nFULL-NAME SUMMARY (unavailable is a separate accounting bucket)\n",
  )
  for group in report.name_groups {
    out.write_string(
      path_optional_string(group.name).stringify() +
      "  \{group.custom_ordinals.length()} instances  \{group.total_bytes} B\n",
    )
  }
  let customs_shown = top.max(0).min(report.customs.length())
  out.write_string(
    "\nCUSTOM INSTANCES: showing \{customs_shown} of \{report.customs.length()}\n",
  )
  for i in 0..<customs_shown {
    let c = report.customs[i]
    out.write_string(
      "Custom #\{c.ordinal}; section #\{c.section_ordinal}; " +
      metadata_range_text(c.encoding) +
      "; " +
      path_optional_string(c.name).stringify() +
      " [\{c.category}, \{c.status}]\n",
    )
    out.write_string(
      "  header \{c.section_header_bytes} B; name encoding \{c.name_encoding.size} B = prefix \{c.name_length_prefix_bytes} B + UTF-8 \{c.name_bytes.size} B; content " +
      metadata_range_text(c.content) +
      "\n",
    )
    out.write_string(
      "  name encoding " +
      metadata_range_text(c.name_encoding) +
      "; name UTF-8 " +
      metadata_range_text(c.name_bytes) +
      "\n",
    )
  }
  let sub_shown = top.max(0).min(report.subsections.length())
  out.write_string(
    "\nNAME SUBSECTIONS: showing \{sub_shown} of \{report.subsections.length()} (physical order)\n",
  )
  for i in 0..<sub_shown {
    let sub = report.subsections[i]
    out.write_string(
      "Custom #\{sub.custom_ordinal}, subsection #\{sub.ordinal}, id \{sub.id}: " +
      metadata_range_text(sub.encoding) +
      "; header \{sub.header_bytes} B; payload " +
      metadata_range_text(sub.payload) +
      "; \{sub.status}\n",
    )
    if sub.id == 1 {
      out.write_string(
        "  declared count " +
        (match sub.declared_count {
          Some(n) => n.to_string()
          None => "unavailable"
        }) +
        "; count prefix \{sub.count_prefix_bytes} B; parsed records \{sub.parsed_record_bytes} B; unparsed " +
        sub.unparsed.map(metadata_range_text).unwrap_or("none") +
        "\n",
      )
    }
  }
  let records_shown = top.max(0).min(report.function_names.length())
  out.write_string(
    "\nFUNCTION-NAME RECORDS: showing \{records_shown} of \{report.function_names.length()} (encoded size descending)\n",
  )
  out.write_string(
    "CUSTOM  SUB  RECORD  DECLARED INDEX  ENCODED B  INDEX PREFIX B  NAME PREFIX B  UTF8 B  FILE OFFSET  NAME\n",
  )
  for i in 0..<records_shown {
    let r = report.function_names[i]
    out.write_string(
      "\{r.custom_ordinal}  \{r.subsection_ordinal}  \{r.ordinal}  \{r.function_index}  \{r.encoding.size}  \{r.index_prefix_bytes}  \{r.name_length_prefix_bytes}  \{r.name_bytes.size}  \{r.encoding.offset}  " +
      path_optional_string(r.name).stringify() +
      "\n",
    )
  }
  out.write_string(
    "\nPARSING COVERAGE\nByte ledger: complete; custom-name decoding: \{report.custom_name_status}; name details: \{report.name_details_status}\n",
  )
  out.write_string(
    "Name contents: \{s.name_content_bytes} B = bounded subsections \{s.name_subsection_bytes} B + unbounded tails \{s.unbounded_name_tail_bytes} B\n",
  )
  out.write_string(
    "Function-name payloads: \{s.function_name_payload_bytes} B = count prefixes \{s.function_name_count_prefix_bytes} B + parsed records \{s.parsed_function_record_bytes} B + unparsed \{s.function_name_unparsed_bytes} B\n",
  )
  out.write_string(
    "Parsed record bytes: \{s.parsed_function_record_bytes} B = index prefixes \{s.function_index_prefix_bytes} B + name-length prefixes \{s.function_name_length_prefix_bytes} B + name UTF-8 \{s.function_name_utf8_bytes} B\n",
  )
  out.write_string(
    "Parsed physical records: \{s.parsed_function_record_count}; unavailable function-name UTF-8: \{s.unavailable_function_name_count}\n",
  )
  for c in report.customs {
    if c.unbounded_tail is Some(r) {
      out.write_string(
        "Unbounded tail: custom #\{c.ordinal}, " + metadata_range_text(r) + "\n",
      )
    }
  }
  for sub in report.subsections {
    if sub.unparsed is Some(r) {
      out.write_string(
        "Unparsed payload: custom #\{sub.custom_ordinal}, subsection #\{sub.ordinal}, " +
        metadata_range_text(r) +
        "\n",
      )
    }
  }
  out.write_string(
    "\nDiagnostics: \{report.diagnostics.length()} (not limited by Top)\n",
  )
  for d in report.diagnostics {
    out.write_string(
      "file offset \{d.offset}, custom #\{d.custom_ordinal}, subsection " +
      d.subsection_ordinal.map(fn(n) { "#" + n.to_string() }).unwrap_or("n/a") +
      ": \{d.reason}\n",
    )
  }
  out.write_string("\n" + report.modeling_scope + "\n")
  out.to_string()
}
