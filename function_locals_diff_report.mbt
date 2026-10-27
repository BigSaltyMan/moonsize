///|
fn locals_type_totals_json(totals : FunctionLocalsTypeTotals) -> Json {
  let value : Map[String, Json] = Map([])
  value.set("group_indices", Json::array(totals.group_indices.map(int_json)))
  value.set("group_count", int_json(totals.group_count))
  value.set(
    "declared_count_decimal",
    Json::string(totals.declared_count.to_string()),
  )
  value.set("quantity_encoding_bytes", int_json(totals.quantity_encoding_bytes))
  value.set("type_encoding_bytes", int_json(totals.type_encoding_bytes))
  value.set("group_bytes", int_json(totals.group_bytes))
  Json::object(value)
}

///|
pub fn render_function_locals_comparison_json(
  report : FunctionLocalsComparison,
) -> String {
  let root : Map[String, Json] = Map([])
  root.set("format", Json::string("moonsize-function-locals-diff"))
  root.set("schema_version", int_json(1))
  root.set("baseline", function_locals_json_value(report.baseline))
  root.set("current", function_locals_json_value(report.current))
  let d = report.delta
  let delta : Map[String, Json] = Map([])
  for
    (key, value) in [
      ("entry_bytes", d.entry_bytes),
      ("prefix_bytes", d.prefix_bytes),
      ("body_bytes", d.body_bytes),
      ("locals_bytes", d.locals_bytes),
      ("group_count_encoding_bytes", d.group_count_encoding_bytes),
      ("quantity_encoding_bytes", d.quantity_encoding_bytes),
      ("type_encoding_bytes", d.type_encoding_bytes),
      ("body_remainder_bytes", d.body_remainder_bytes),
      ("group_count", d.group_count),
    ] {
    delta.set(key, int_json(value))
  }
  delta.set(
    "declared_count_delta_decimal",
    Json::string(d.declared_count_delta_decimal),
  )
  root.set("delta", Json::object(delta))
  root.set(
    "type_encodings",
    Json::array(
      report.type_encodings.map(fn(row) {
        let value : Map[String, Json] = Map([])
        value.set("type_hex", Json::string(row.type_hex))
        value.set("type_label", path_optional_string(row.type_label))
        value.set("presence", Json::string(row.presence))
        value.set("baseline", locals_type_totals_json(row.baseline))
        value.set("current", locals_type_totals_json(row.current))
        let delta : Map[String, Json] = Map([])
        delta.set("group_count", int_json(row.delta.group_count))
        delta.set(
          "declared_count_delta_decimal",
          Json::string(row.delta.declared_count_delta_decimal),
        )
        delta.set(
          "quantity_encoding_bytes",
          int_json(row.delta.quantity_encoding_bytes),
        )
        delta.set(
          "type_encoding_bytes",
          int_json(row.delta.type_encoding_bytes),
        )
        delta.set("group_bytes", int_json(row.delta.group_bytes))
        value.set("delta", Json::object(delta))
        Json::object(value)
      }),
    ),
  )
  root.set("scope", Json::string(report.scope))
  Json::object(root).stringify(indent=2) + "\n"
}

///|
pub fn render_function_locals_comparison(
  report : FunctionLocalsComparison,
  top : Int,
) -> String {
  let out = StringBuilder()
  let b = report.baseline
  let c = report.current
  let d = report.delta
  out.write_string(
    "FUNCTION LOCAL DECLARATIONS COMPARISON\n\nExplicit user-selected targets; no automatic function matching.\n",
  )
  for (side, target) in [("Baseline", b), ("Current", c)] {
    out.write_string(
      "\n\{side}: function \{target.target.index} " +
      search_terminal_string(target.target.name) +
      "; SHA-256 \{target.sha256}; input \{target.file_size} B\n",
    )
    out.write_string(
      "Entry: file offset \{target.entry.file_offset}, size \{target.entry.size} B\nLocals: file offset \{target.locals_encoding.file_offset}, size \{target.locals_encoding.size} B\nBody remainder (undecoded): file offset \{target.body_remainder.file_offset}, size \{target.body_remainder.size} B\n",
    )
  }
  out.write_string(
    "\nBYTE AND COUNT LEDGER (delta = current - baseline)\nMETRIC  BASELINE  CURRENT  DELTA\n",
  )
  for
    (label, before, after, change) in [
      ("Entry bytes", b.entry.size, c.entry.size, d.entry_bytes),
      ("Prefix bytes", b.prefix.size, c.prefix.size, d.prefix_bytes),
      ("Body bytes", b.body.size, c.body.size, d.body_bytes),
      (
        "Locals bytes",
        b.locals_encoding.size,
        c.locals_encoding.size,
        d.locals_bytes,
      ),
      (
        "Group-count encoding bytes",
        b.group_count_encoding.size,
        c.group_count_encoding.size,
        d.group_count_encoding_bytes,
      ),
      (
        "Quantity encoding bytes",
        b.quantity_encoding_bytes,
        c.quantity_encoding_bytes,
        d.quantity_encoding_bytes,
      ),
      (
        "Type encoding bytes",
        b.type_encoding_bytes,
        c.type_encoding_bytes,
        d.type_encoding_bytes,
      ),
      (
        "Undecoded remainder bytes",
        b.body_remainder.size,
        c.body_remainder.size,
        d.body_remainder_bytes,
      ),
      ("Group count", b.group_count, c.group_count, d.group_count),
    ] {
    out.write_string("\{label}  \{before}  \{after}  \{change}\n")
  }
  out.write_string(
    "Declared count (excluding parameters)  \{b.declared_count}  \{c.declared_count}  \{d.declared_count_delta_decimal}\n",
  )
  out.write_string(
    "Entry delta: \{d.entry_bytes} = prefix \{d.prefix_bytes} + body \{d.body_bytes}\nBody delta: \{d.body_bytes} = locals \{d.locals_bytes} + undecoded remainder \{d.body_remainder_bytes}\nLocals delta: \{d.locals_bytes} = group count encoding \{d.group_count_encoding_bytes} + quantity encoding \{d.quantity_encoding_bytes} + type encoding \{d.type_encoding_bytes}\n",
  )
  let shown = top.max(0).min(report.type_encodings.length())
  out.write_string(
    "\nTYPE ENCODINGS: showing \{shown} of \{report.type_encodings.length()} (full hex lexical order)\nTYPE HEX  LABEL  PRESENCE  BEFORE GROUPS  AFTER GROUPS  GROUP DELTA  BEFORE QUANTITY  AFTER QUANTITY  QUANTITY DELTA  BEFORE B  AFTER B  BYTE DELTA\n",
  )
  if report.type_encodings.is_empty() {
    out.write_string("No declaration groups on either side.\n")
  }
  for i in 0..<shown {
    let row = report.type_encodings[i]
    out.write_string(
      row.type_hex +
      "  " +
      (match row.type_label {
        Some(label) => label
        None => "unknown"
      }) +
      "  " +
      row.presence +
      "  \{row.baseline.group_count}  \{row.current.group_count}  \{row.delta.group_count}  \{row.baseline.declared_count}  \{row.current.declared_count}  \{row.delta.declared_count_delta_decimal}  \{row.baseline.group_bytes}  \{row.current.group_bytes}  \{row.delta.group_bytes}\n",
    )
    out.write_string(
      "  baseline group indices: " +
      Json::array(row.baseline.group_indices.map(int_json)).stringify() +
      "; current group indices: " +
      Json::array(row.current.group_indices.map(int_json)).stringify() +
      "\n",
    )
    out.write_string(
      "  quantity encoding B: \{row.baseline.quantity_encoding_bytes} -> \{row.current.quantity_encoding_bytes} (delta \{row.delta.quantity_encoding_bytes}); type encoding B: \{row.baseline.type_encoding_bytes} -> \{row.current.type_encoding_bytes} (delta \{row.delta.type_encoding_bytes})\n",
    )
  }
  out.write_string("\n" + report.scope + "\n")
  out.to_string()
}
