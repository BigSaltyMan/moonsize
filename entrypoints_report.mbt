///|
pub fn render_entrypoints_json(report : EntrypointsReport) -> String {
  let root : Map[String, Json] = Map([])
  root.set("format", Json::string("moonsize-entrypoints"))
  root.set("schema_version", int_json(1))
  root.set("file_size", int_json(report.file_size))
  root.set("sha256", Json::string(report.sha256))
  root.set("export_name_count", int_json(report.export_name_count))
  root.set("entrypoint_count", int_json(report.entrypoint_count))
  root.set("modeling_scope", Json::string(report.modeling_scope))
  root.set("graph_complete", Json::boolean(report.graph_complete))
  root.set("diagnostics", diagnostic_records_json(report.diagnostics))
  root.set(
    "other_exports",
    Json::array(
      report.other_exports.map(fn(item) {
        let value : Map[String, Json] = Map([])
        value.set("name", Json::string(item.name))
        value.set("kind", int_json(item.kind))
        value.set("index", int_json(item.index))
        Json::object(value)
      }),
    ),
  )
  let ledger : Map[String, Json] = Map([])
  let l = report.ledger
  ledger.set("local_function_count", int_json(l.local_function_count))
  ledger.set("total_local_bytes", int_json(l.total_local_bytes))
  ledger.set("export_union_local_count", int_json(l.export_union_local_count))
  ledger.set("export_union_bytes", int_json(l.export_union_bytes))
  ledger.set(
    "not_export_reachable_bytes",
    int_json(l.not_export_reachable_bytes),
  )
  ledger.set("exclusive_model_bytes", int_json(l.exclusive_model_bytes))
  ledger.set("shared_model_bytes", int_json(l.shared_model_bytes))
  root.set("ledger", Json::object(ledger))
  root.set(
    "entrypoints",
    Json::array(
      report.entrypoints.map(fn(group) {
        let value : Map[String, Json] = Map([])
        value.set("index", int_json(group.index))
        value.set("aliases", Json::array(group.aliases.map(Json::string)))
        value.set("reachable", Json::array(group.reachable.map(int_json)))
        value.set("local_function_count", int_json(group.local_function_count))
        value.set(
          "imported_function_count",
          int_json(group.imported_function_count),
        )
        value.set(
          "reachable_model_bytes",
          int_json(group.reachable_model_bytes),
        )
        value.set(
          "exclusive_model_bytes",
          int_json(group.exclusive_model_bytes),
        )
        value.set("shared_model_bytes", int_json(group.shared_model_bytes))
        Json::object(value)
      }),
    ),
  )
  root.set(
    "functions",
    Json::array(
      report.functions.map(fn(function) {
        let value : Map[String, Json] = Map([])
        value.set("node", path_node_json(function.node))
        value.set(
          "entrypoints",
          Json::array(function.entrypoints.map(int_json)),
        )
        value.set(
          "other_root_reachable",
          Json::boolean(function.other_root_reachable),
        )
        Json::object(value)
      }),
    ),
  )
  root.set(
    "other_roots",
    Json::array(
      report.other_roots.map(fn(item) {
        let value : Map[String, Json] = Map([])
        value.set("index", int_json(item.index))
        value.set("reasons", Json::array(item.reasons.map(path_reason_json)))
        Json::object(value)
      }),
    ),
  )
  root.set(
    "other_root_reachable",
    Json::array(report.other_root_reachable.map(int_json)),
  )
  root.set(
    "shared_local_functions",
    Json::array(report.shared_local_functions.map(int_json)),
  )
  Json::object(root).stringify(indent=2) + "\n"
}

///|
pub fn render_entrypoints(report : EntrypointsReport, top : Int) -> String {
  let out = StringBuilder()
  out.write_string("EXPORTED ENTRYPOINT DEPENDENCIES\n\n")
  out.write_string(
    "Input: \{report.file_size} bytes; SHA-256 \{report.sha256}\n",
  )
  out.write_string(report.modeling_scope + "\n")
  if !report.graph_warning.is_empty() {
    out.write_string("\n" + report.graph_warning + "\n")
  }
  out.write_string(
    "\nFunction export names: \{report.export_name_count}; unique entrypoint groups: \{report.entrypoint_count}\n",
  )
  out.write_string(
    "Other exports: \{report.other_exports.length()} (no function-body weight assigned)\n",
  )
  for item in report.other_exports {
    out.write_string(
      "  " +
      Json::string(item.name).stringify() +
      " kind=\{item.kind} index=\{item.index}\n",
    )
  }
  let l = report.ledger
  out.write_string(
    "\nLOCAL FUNCTION ENCODING LEDGER (bytes, not whole-module size)\n",
  )
  out.write_string(
    "All local: \{l.total_local_bytes} B = function-export union \{l.export_union_bytes} B + not export-reachable \{l.not_export_reachable_bytes} B\n",
  )
  out.write_string(
    "Export union: \{l.export_union_bytes} B = sum of group-exclusive \{l.exclusive_model_bytes} B + shared (counted once) \{l.shared_model_bytes} B\n",
  )
  out.write_string(
    "Local definitions: \{l.local_function_count}; export-reachable local definitions: \{l.export_union_local_count}\n",
  )
  let shown = top.max(0).min(report.entrypoints.length())
  out.write_string(
    "\nENTRYPOINT GROUPS: showing \{shown} of \{report.entrypoint_count}\n",
  )
  out.write_string(
    "INDEX  LOCAL  IMPORTED  REACHABLE B  EXCLUSIVE B  SHARED B  ALL EXPORT ALIASES\n",
  )
  for i in 0..<shown {
    let g = report.entrypoints[i]
    out.write_string(
      "\{g.index}  \{g.local_function_count}  \{g.imported_function_count}  \{g.reachable_model_bytes}  \{g.exclusive_model_bytes}  \{g.shared_model_bytes}  " +
      Json::array(g.aliases.map(Json::string)).stringify() +
      "\n",
    )
  }
  if report.entrypoints.is_empty() {
    out.write_string(
      "No function exports. This does not prove that any function can be removed.\n",
    )
  }
  let shared_shown = top.max(0).min(report.shared_local_functions.length())
  out.write_string(
    "\nSHARED LOCAL FUNCTIONS: showing \{shared_shown} of \{report.shared_local_functions.length()}\n",
  )
  out.write_string(
    "INDEX  ENCODED B  ENTRYPOINT INDICES  START/ELEMENT REACHABLE  NAME\n",
  )
  for i in 0..<shared_shown {
    let index = report.shared_local_functions[i]
    let f = report.functions[index]
    out.write_string(
      "\{index}  " +
      f.node.encoded_size.unwrap_or(0).to_string() +
      "  " +
      Json::array(f.entrypoints.map(int_json)).stringify() +
      "  " +
      f.other_root_reachable.to_string() +
      "  " +
      Json::string(f.node.name).stringify() +
      "\n",
    )
  }
  out.write_string(
    "\nPer-entry reachable/shared bytes overlap; do not add them as module size.\n",
  )
  out.to_string()
}
