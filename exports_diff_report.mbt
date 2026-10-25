///|
fn exports_diff_optional_declaration(entry : ExportDeclaration?) -> Json {
  match entry {
    Some(entry) => exports_declaration_json(entry)
    None => Json::null()
  }
}

///|
pub fn render_exports_diff_json(report : ExportsComparison) -> String {
  let root : Map[String, Json] = Map([])
  root.set("format", Json::string("moonsize-exports-diff"))
  root.set("schema_version", int_json(1))
  root.set("baseline", exports_json_value(report.baseline))
  root.set("current", exports_json_value(report.current))
  let counts : Map[String, Json] = Map([])
  let c = report.counts
  for
    (key, value) in [
      ("added_count", c.added_count),
      ("removed_count", c.removed_count),
      ("kind_changed_count", c.kind_changed_count),
      ("same_kind_count", c.same_kind_count),
      ("row_count", c.row_count),
    ] {
    counts.set(key, int_json(value))
  }
  root.set("counts", Json::object(counts))
  root.set("delta", exports_ledger_json(report.delta))
  root.set(
    "baseline_non_export_bytes",
    int_json(report.baseline_non_export_bytes),
  )
  root.set(
    "current_non_export_bytes",
    int_json(report.current_non_export_bytes),
  )
  root.set("delta_non_export_bytes", int_json(report.delta_non_export_bytes))
  root.set("delta_file_bytes", int_json(report.delta_file_bytes))
  root.set(
    "rows",
    Json::array(
      report.rows.map(fn(change) {
        let row : Map[String, Json] = Map([])
        row.set("name", Json::string(change.name))
        row.set("status", Json::string(change.status))
        row.set("baseline", exports_diff_optional_declaration(change.baseline))
        row.set("current", exports_diff_optional_declaration(change.current))
        row.set(
          "declaration_bytes_delta",
          int_json(change.declaration_bytes_delta),
        )
        row.set(
          "target_index_changed",
          match change.target_index_changed {
            Some(value) => Json::boolean(value)
            None => Json::null()
          },
        )
        Json::object(row)
      }),
    ),
  )
  root.set("comparison_scope", Json::string(report.comparison_scope))
  Json::object(root).stringify(indent=2) + "\n"
}

///|
fn exports_diff_target_text(entry : ExportDeclaration?) -> String {
  match entry {
    Some(e) => "\{e.kind} #\{e.target_index}"
    None => "null"
  }
}

///|
pub fn render_exports_diff(report : ExportsComparison, top : Int) -> String {
  let out = StringBuilder()
  let c = report.counts
  out.write_string("EXPORT DECLARATION COMPARISON (current - baseline)\n\n")
  out.write_string(
    "Baseline: \{report.baseline.file_size} B; SHA-256 \{report.baseline.sha256}\nCurrent: \{report.current.file_size} B; SHA-256 \{report.current.sha256}\n",
  )
  out.write_string(
    "Names: removed \{c.removed_count}; kind_changed \{c.kind_changed_count}; added \{c.added_count}; same_kind \{c.same_kind_count}; rows \{c.row_count}\n",
  )
  out.write_string(
    "Baseline declarations: \{report.baseline.summary.export_count}; current declarations: \{report.current.summary.export_count}\n\nSCOPE\n" +
    report.comparison_scope +
    "\n",
  )
  out.write_string("\nENCODING LEDGER\n")
  for
    (side, input) in [
      ("Baseline", report.baseline),
      ("Current", report.current),
    ] {
    let l = input.ledger
    out.write_string(
      "\{side} export: \{l.export_section_bytes} B = headers \{l.section_header_bytes} B + count \{l.count_prefix_bytes} B + declarations \{l.declaration_bytes} B\n",
    )
  }
  let d = report.delta
  out.write_string(
    "Export delta: \{d.export_section_bytes} B = headers \{d.section_header_bytes} B + count \{d.count_prefix_bytes} B + declarations \{d.declaration_bytes} B\n",
  )
  out.write_string(
    "Declaration delta: \{d.declaration_bytes} B = name encodings \{d.name_encoding_bytes} B + descriptors \{d.descriptor_bytes} B\n",
  )
  out.write_string(
    "Name encoding delta: \{d.name_encoding_bytes} B = length prefixes \{d.name_length_prefix_bytes} B + UTF-8 \{d.name_utf8_bytes} B\n",
  )
  out.write_string(
    "Descriptor delta: \{d.descriptor_bytes} B = kind \{d.kind_bytes} B + index prefixes \{d.target_index_prefix_bytes} B\n",
  )
  out.write_string(
    "Non-export: \{report.baseline_non_export_bytes} -> \{report.current_non_export_bytes} B\nFile delta: \{report.delta_file_bytes} B = export \{d.export_section_bytes} B + non-export \{report.delta_non_export_bytes} B\n",
  )
  let shown = top.max(0).min(report.rows.length())
  out.write_string(
    "\nNAMES: showing \{shown} of \{report.rows.length()} (status order, then absolute byte delta and name)\nNAME  STATUS  BEFORE TARGET  AFTER TARGET  DECLARATION DELTA B  TARGET INDEX CHANGED\n",
  )
  for i in 0..<shown {
    let row = report.rows[i]
    let index_changed = match row.target_index_changed {
      Some(value) => value.to_string()
      None => "null"
    }
    out.write_string(
      Json::string(row.name).stringify() +
      "  \{row.status}  " +
      exports_diff_target_text(row.baseline) +
      "  " +
      exports_diff_target_text(row.current) +
      "  \{row.declaration_bytes_delta}  \{index_changed}\n",
    )
  }
  out.to_string()
}
