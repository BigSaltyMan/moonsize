///|
pub fn render_imports_diff_json(report : ImportsComparison) -> String {
  let root : Map[String, Json] = Map([])
  root.set("format", Json::string("moonsize-imports-diff"))
  root.set("schema_version", int_json(1))
  root.set(
    "comparison_key",
    Json::array([
      Json::string("module_name"),
      Json::string("field"),
      Json::string("kind"),
    ]),
  )
  root.set("comparison_scope", Json::string(report.comparison_scope))
  root.set("type_compatibility", Json::string("not_evaluated"))
  root.set("inventory_changed", Json::boolean(report.inventory_changed))
  root.set("delta_direction", Json::string("current - baseline"))
  root.set("baseline", imports_json(report.baseline))
  root.set("current", imports_json(report.current))
  let c = report.counts
  root.set(
    "counts",
    Json::object({
      "baseline_entry_count": int_json(c.baseline_entry_count),
      "current_entry_count": int_json(c.current_entry_count),
      "overlap_count": int_json(c.overlap_count),
      "removed_count": int_json(c.removed_count),
      "added_count": int_json(c.added_count),
      "count_delta": int_json(c.count_delta),
    }),
  )
  root.set("delta", imports_ledger_json(report.delta))
  root.set(
    "groups",
    Json::array(
      report.groups.map(fn(group) {
        Json::object({
          "module": Json::string(group.module_name),
          "field": Json::string(group.field),
          "kind": Json::string(group.kind),
          "status": Json::string(group.status),
          "baseline_ordinals": Json::array(
            group.baseline_ordinals.map(int_json),
          ),
          "current_ordinals": Json::array(group.current_ordinals.map(int_json)),
          "baseline_count": int_json(group.baseline_count),
          "current_count": int_json(group.current_count),
          "overlap_count": int_json(group.overlap_count),
          "removed_count": int_json(group.removed_count),
          "added_count": int_json(group.added_count),
          "count_delta": int_json(group.count_delta),
          "baseline_entry_bytes": int_json(group.baseline_entry_bytes),
          "current_entry_bytes": int_json(group.current_entry_bytes),
          "entry_bytes_delta": int_json(group.entry_bytes_delta),
        })
      }),
    ),
  )
  Json::object(root).stringify(indent=2) + "\n"
}

///|
fn imports_diff_ledger_text(
  out : StringBuilder,
  label : String,
  s : ImportsLedger,
) -> Unit {
  out.write_string(
    label +
    " import section bytes: \{s.import_section_total_bytes} B = header \{s.section_header_bytes} B + count prefix \{s.count_prefix_bytes} B + declarations \{s.entry_bytes} B\n",
  )
  out.write_string(
    label +
    " declaration bytes: \{s.entry_bytes} B = module names \{s.module_name_encoding_bytes} B + field names \{s.field_name_encoding_bytes} B + descriptors \{s.descriptor_bytes} B\n",
  )
  out.write_string(
    label +
    " module-name bytes: \{s.module_name_encoding_bytes} B = prefixes \{s.module_length_prefix_bytes} B + UTF-8 \{s.module_utf8_bytes} B\n",
  )
  out.write_string(
    label +
    " field-name bytes: \{s.field_name_encoding_bytes} B = prefixes \{s.field_length_prefix_bytes} B + UTF-8 \{s.field_utf8_bytes} B\n",
  )
}

///|
pub fn render_imports_diff(report : ImportsComparison, top : Int) -> String {
  let out = StringBuilder()
  let c = report.counts
  out.write_string("HOST IMPORT INVENTORY COMPARISON\n\n")
  out.write_string(
    "Baseline: \{report.baseline.file_size} B; SHA-256 \{report.baseline.sha256}\n",
  )
  out.write_string(
    "Current: \{report.current.file_size} B; SHA-256 \{report.current.sha256}\n",
  )
  out.write_string(
    "Declarations: baseline \{c.baseline_entry_count}, current \{c.current_entry_count}; overlap \{c.overlap_count}, removed \{c.removed_count}, added \{c.added_count}; delta \{c.count_delta}\n",
  )
  if !report.inventory_changed {
    out.write_string(
      "No changes to names, kinds or declaration counts; type compatibility is not evaluated.\n",
    )
  } else {
    out.write_string(
      "Inventory counts changed; type compatibility is not evaluated.\n",
    )
  }
  out.write_string(
    "\nENCODING LEDGERS (delta = current - baseline; not file ranges)\n",
  )
  imports_diff_ledger_text(out, "Baseline", report.baseline.ledger)
  imports_diff_ledger_text(out, "Current", report.current.ledger)
  imports_diff_ledger_text(out, "Delta", report.delta)
  for
    (label, side) in [
      ("Baseline", report.baseline),
      ("Current", report.current),
    ] {
    out.write_string(
      label +
      " import section: " +
      side.section.map(imports_range_text).unwrap_or("absent") +
      "\n",
    )
  }
  let shown = top.max(0).min(report.groups.length())
  out.write_string(
    "\nIMPORT GROUPS: showing \{shown} of \{report.groups.length()}\n",
  )
  out.write_string(
    "MODULE  FIELD  KIND  STATUS  BEFORE  AFTER  OVERLAP  REMOVED  ADDED  COUNT DELTA  ENCODED DELTA B\n",
  )
  for i in 0..<shown {
    let g = report.groups[i]
    out.write_string(
      Json::string(g.module_name).stringify() +
      "  " +
      Json::string(g.field).stringify() +
      "  \{g.kind}  \{g.status}  \{g.baseline_count}  \{g.current_count}  \{g.overlap_count}  \{g.removed_count}  \{g.added_count}  \{g.count_delta}  \{g.entry_bytes_delta}\n",
    )
    out.write_string(
      "  baseline ordinals " +
      Json::array(g.baseline_ordinals.map(int_json)).stringify() +
      "; current ordinals " +
      Json::array(g.current_ordinals.map(int_json)).stringify() +
      "; baseline \{g.baseline_entry_bytes} B, current \{g.current_entry_bytes} B\n",
    )
  }
  out.write_string("\n" + report.comparison_scope + "\n")
  out.to_string()
}
