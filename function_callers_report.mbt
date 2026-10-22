///|
/// Independent format; Top never truncates this result.
pub fn render_function_callers_json(report : FunctionCallersReport) -> String {
  let root : Map[String, Json] = Map([])
  root.set("format", Json::string("moonsize-function-callers"))
  root.set("schema_version", int_json(1))
  root.set("file_size", int_json(report.file_size))
  root.set("sha256", Json::string(report.sha256))
  root.set("target", path_node_json(report.target))
  root.set("caller_count", int_json(report.caller_count))
  root.set("source_count", int_json(report.source_count))
  root.set("graph_complete", Json::boolean(report.graph_complete))
  root.set("diagnostics", diagnostic_records_json(report.diagnostics))
  root.set("modeling_scope", Json::string(report.modeling_scope))
  root.set(
    "callers",
    Json::array(
      report.callers.map(fn(group) {
        let row : Map[String, Json] = Map([])
        row.set("caller", path_node_json(group.caller))
        row.set(
          "sources",
          Json::array(
            group.sources.map(fn(source) {
              let item : Map[String, Json] = Map([])
              item.set("caller", int_json(source.caller))
              item.set("callee", int_json(source.callee))
              item.set("kind", Json::string(path_edge_kind(source.kind)))
              item.set("candidate", Json::boolean(source.kind is Indirect))
              item.set("opcode", Json::string(source.opcode.name()))
              item.set("file_offset", int_json(source.offset))
              item.set("type_index", optional_index_json(source.type_index))
              item.set("table_index", optional_index_json(source.table_index))
              Json::object(item)
            }),
          ),
        )
        Json::object(row)
      }),
    ),
  )
  Json::object(root).stringify(indent=2) + "\n"
}

///|
pub fn render_function_callers(
  report : FunctionCallersReport,
  top : Int,
) -> String {
  let out = StringBuilder()
  let shown = top.max(0).min(report.callers.length())
  out.write_string(
    "FUNCTION INCOMING REFERENCES\n\nTarget: #" +
    report.target.index.to_string() +
    " " +
    Json::string(report.target.name).stringify() +
    "\n",
  )
  out.write_string(
    "Identity: " +
    (if report.target.imported {
      "imported; no local body (encoded size is not measured)\n"
    } else {
      "local; encoded bytes " +
      report.target.encoded_size.unwrap_or(0).to_string() +
      "\n"
    }),
  )
  out.write_string(
    "Input: " +
    report.file_size.to_string() +
    " bytes; SHA-256 " +
    report.sha256 +
    "\n",
  )
  out.write_string(
    "Unique callers: " +
    report.caller_count.to_string() +
    "; source instructions: " +
    report.source_count.to_string() +
    "\n",
  )
  out.write_string(
    "Showing " +
    shown.to_string() +
    " of " +
    report.caller_count.to_string() +
    " caller groups\n",
  )
  for i in 0..<shown {
    let group = report.callers[i]
    out.write_string(
      "\nCaller #" +
      group.caller.index.to_string() +
      " " +
      Json::string(group.caller.name).stringify() +
      "\n",
    )
    out.write_string("CALLER  KIND  OPCODE  FILE OFFSET  TYPE  TABLE\n")
    for source in group.sources {
      let kind = match source.kind {
        Direct => "direct"
        Reference => "reference taken"
        Indirect => "indirect candidate"
      }
      out.write_string(
        source.caller.to_string() +
        "  " +
        kind +
        "  " +
        source.opcode.name() +
        "  " +
        source.offset.to_string() +
        "  " +
        (match source.type_index {
          Some(n) => n.to_string()
          None => "-"
        }) +
        "  " +
        (match source.table_index {
          Some(n) => n.to_string()
          None => "-"
        }) +
        "\n",
      )
    }
  }
  if report.callers.is_empty() {
    out.write_string(
      "\nNo incoming instruction references recorded in the current model.\nThis does not prove the function is unused or removable.\n",
    )
  }
  if !report.graph_warning.is_empty() {
    out.write_string("\n" + report.graph_warning + "\n")
  }
  out.write_string("\n" + report.modeling_scope + "\n")
  out.to_string()
}
