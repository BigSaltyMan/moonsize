///|
fn metadata_diff_totals_json(totals : MetadataEncodingTotals) -> Json {
  let row : Map[String, Json] = Map([])
  row.set("custom_count", int_json(totals.custom_count))
  row.set("custom_encoded_bytes", int_json(totals.custom_encoded_bytes))
  row.set("section_header_bytes", int_json(totals.section_header_bytes))
  row.set("name_encoding_bytes", int_json(totals.name_encoding_bytes))
  row.set("content_bytes", int_json(totals.content_bytes))
  Json::object(row)
}

///|
fn metadata_diff_group_json(group : MetadataComparisonGroup) -> Json {
  let row : Map[String, Json] = Map([])
  row.set("kind", Json::string(group.kind))
  row.set("name", path_optional_string(group.name))
  row.set(
    "baseline_ordinals",
    Json::array(group.baseline_ordinals.map(int_json)),
  )
  row.set("current_ordinals", Json::array(group.current_ordinals.map(int_json)))
  row.set("baseline", metadata_diff_totals_json(group.baseline))
  row.set("current", metadata_diff_totals_json(group.current))
  row.set("delta", metadata_diff_totals_json(group.delta))
  Json::object(row)
}

///|
/// Complete reports remain nested objects with the original single-file schema.
pub fn render_metadata_diff_json(report : MetadataComparison) -> String {
  let root : Map[String, Json] = Map([])
  root.set("format", Json::string("moonsize-metadata-diff"))
  root.set("schema_version", int_json(1))
  root.set("baseline", metadata_json_value(report.baseline))
  root.set("current", metadata_json_value(report.current))
  root.set("delta", metadata_diff_totals_json(report.delta))
  root.set(
    "baseline_non_custom_bytes",
    int_json(report.baseline_non_custom_bytes),
  )
  root.set(
    "current_non_custom_bytes",
    int_json(report.current_non_custom_bytes),
  )
  root.set("delta_non_custom_bytes", int_json(report.delta_non_custom_bytes))
  root.set("delta_file_bytes", int_json(report.delta_file_bytes))
  root.set(
    "categories",
    Json::array(report.categories.map(metadata_diff_group_json)),
  )
  root.set(
    "name_groups",
    Json::array(report.name_groups.map(metadata_diff_group_json)),
  )
  root.set("comparison_scope", Json::string(report.comparison_scope))
  Json::object(root).stringify(indent=2) + "\n"
}

///|
fn metadata_diff_coverage(side : String, report : MetadataReport) -> String {
  let out = StringBuilder()
  out.write_string("\{side}: \{report.file_size} B; SHA-256 \{report.sha256}\n")
  out.write_string(
    "Byte ledger complete: \{report.byte_ledger_complete}; custom-name decoding: \{report.custom_name_status}; name details: \{report.name_details_status}\n",
  )
  for row in report.customs {
    if row.unbounded_tail is Some(range) {
      out.write_string(
        "Unbounded name tail, custom #\{row.ordinal}: " +
        metadata_range_text(range) +
        "\n",
      )
    }
  }
  for sub in report.subsections {
    if sub.unparsed is Some(range) {
      out.write_string(
        "Unparsed name payload, custom #\{sub.custom_ordinal}, subsection #\{sub.ordinal}: " +
        metadata_range_text(range) +
        "\n",
      )
    }
  }
  out.write_string("Diagnostics: \{report.diagnostics.length()}\n")
  for d in report.diagnostics {
    out.write_string(
      "custom #\{d.custom_ordinal}, file offset \{d.offset}: \{d.reason}\n",
    )
  }
  out.to_string()
}

///|
fn metadata_diff_group_text(group : MetadataComparisonGroup) -> String {
  let label = if group.kind == "unavailable_names" {
    "unavailable_names (accounting only)"
  } else {
    path_optional_string(group.name).stringify()
  }
  "\{label}  \{group.baseline.custom_count}  \{group.current.custom_count}  \{group.delta.custom_count}  \{group.baseline.custom_encoded_bytes}  \{group.current.custom_encoded_bytes}  \{group.delta.custom_encoded_bytes}  \{group.delta.section_header_bytes}  \{group.delta.name_encoding_bytes}  \{group.delta.content_bytes}\n"
}

///|
pub fn render_metadata_diff(report : MetadataComparison, top : Int) -> String {
  let out = StringBuilder()
  out.write_string("CUSTOM ENCODING COMPARISON (current - baseline)\n\n")
  out.write_string(metadata_diff_coverage("Baseline", report.baseline))
  out.write_string(metadata_diff_coverage("Current", report.current))
  out.write_string(
    "\nOUTER BYTE LEDGER (internal name details are not compared)\n",
  )
  for
    (label, input) in [
      ("Baseline", report.baseline),
      ("Current", report.current),
    ] {
    let s = input.summary
    out.write_string(
      "\{label} custom: \{s.custom_bytes} B = headers \{s.section_header_bytes} B + name encodings \{s.custom_name_encoding_bytes} B + contents \{s.content_bytes} B; \{s.custom_count} instances\n",
    )
  }
  let d = report.delta
  out.write_string(
    "Custom delta: \{d.custom_encoded_bytes} B = headers \{d.section_header_bytes} B + name encodings \{d.name_encoding_bytes} B + contents \{d.content_bytes} B; count delta \{d.custom_count}\n",
  )
  out.write_string(
    "Non-custom: \{report.baseline_non_custom_bytes} -> \{report.current_non_custom_bytes} B\n",
  )
  out.write_string(
    "File delta: \{report.delta_file_bytes} B = custom \{d.custom_encoded_bytes} B + non-custom \{report.delta_non_custom_bytes} B\n",
  )
  let heading = "NAME  BEFORE COUNT  AFTER COUNT  COUNT DELTA  BEFORE B  AFTER B  ENCODED DELTA B  HEADER DELTA B  NAME DELTA B  CONTENT DELTA B\n"
  out.write_string(
    "\nCATEGORY TOTALS (all categories; alternative view)\n" + heading,
  )
  for group in report.categories {
    out.write_string(metadata_diff_group_text(group))
  }
  let shown = top.max(0).min(report.name_groups.length())
  out.write_string(
    "\nFULL-NAME GROUPS: showing \{shown} of \{report.name_groups.length()}\n" +
    heading,
  )
  for i in 0..<shown {
    out.write_string(metadata_diff_group_text(report.name_groups[i]))
  }
  out.write_string("\nSCOPE\n" + report.comparison_scope + "\n")
  out.to_string()
}
