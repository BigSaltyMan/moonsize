///|
pub fn render_function_cycles(
  report : FunctionCyclesReport,
  top : Int,
) -> String {
  let out = StringBuilder()
  out.write_string("FUNCTION REFERENCE CYCLE COMPONENTS\n\n")
  if !report.graph_warning.is_empty() {
    out.write_string(report.graph_warning + "\n\n")
  }
  out.write_string(report.modeling_scope + "\n\n")
  out.write_string(
    "Input: \{report.file_size} B; SHA-256 \{report.sha256}\nFunctions: \{report.function_count} = imports \{report.imported_function_count} + local \{report.local_function_count}\nFunctions: \{report.function_count} = cyclic \{report.cyclic_function_count} + non-cyclic \{report.non_cyclic_function_count}\nLocal encoded bytes: \{report.local_encoded_bytes} = cyclic \{report.cyclic_local_encoded_bytes} + other \{report.other_local_encoded_bytes}\nCyclic components: \{report.component_count}\nUnresolved table call sites (no static candidates): \{report.unresolved_count}\n",
  )
  let shown = top.max(0).min(report.components.length())
  out.write_string(
    "\nCOMPONENTS: showing \{shown} of \{report.component_count}\nID  MEMBERS  ENCODED B  EDGES  DIRECT  REFERENCE  INDIRECT CANDIDATES\n",
  )
  for i in 0..<shown {
    let c = report.components[i]
    out.write_string(
      "\{c.component_id}  \{c.node_count}  \{c.local_encoded_bytes}  \{c.internal_edge_count}  \{c.direct_edges}  \{c.reference_edges}  \{c.indirect_edges}\n",
    )
    for node in c.members {
      let size = match node.encoded_size {
        Some(n) => n.to_string() + " B"
        None => "n/a (import; no local body)"
      }
      out.write_string(
        "  Member #\{node.index} " +
        search_terminal_string(node.name) +
        "; encoded " +
        size +
        "\n",
      )
    }
  }
  if report.components.is_empty() {
    out.write_string(
      "\nNo cyclic components recorded in the current reference model.\n",
    )
  }
  out.to_string()
}

///|
fn function_cycles_json_value(report : FunctionCyclesReport) -> Json {
  let root : Map[String, Json] = Map([])
  root.set("format", Json::string("moonsize-function-cycles"))
  root.set("schema_version", int_json(1))
  root.set("file_size", int_json(report.file_size))
  root.set("sha256", Json::string(report.sha256))
  root.set("function_count", int_json(report.function_count))
  root.set("imported_function_count", int_json(report.imported_function_count))
  root.set("local_function_count", int_json(report.local_function_count))
  root.set("cyclic_function_count", int_json(report.cyclic_function_count))
  root.set(
    "non_cyclic_function_count",
    int_json(report.non_cyclic_function_count),
  )
  root.set("component_count", int_json(report.component_count))
  root.set("local_encoded_bytes", int_json(report.local_encoded_bytes))
  root.set(
    "cyclic_local_encoded_bytes",
    int_json(report.cyclic_local_encoded_bytes),
  )
  root.set(
    "other_local_encoded_bytes",
    int_json(report.other_local_encoded_bytes),
  )
  root.set("graph_complete", Json::boolean(report.graph_complete))
  root.set("unresolved_count", int_json(report.unresolved_count))
  root.set("diagnostics", diagnostic_records_json(report.diagnostics))
  root.set("graph_warning", Json::string(report.graph_warning))
  root.set("modeling_scope", Json::string(report.modeling_scope))
  root.set(
    "components",
    Json::array(
      report.components.map(fn(c) {
        let row : Map[String, Json] = Map([])
        row.set("component_id", int_json(c.component_id))
        row.set("members", Json::array(c.members.map(path_node_json)))
        row.set("node_count", int_json(c.node_count))
        row.set("internal_edge_count", int_json(c.internal_edge_count))
        row.set("direct_edges", int_json(c.direct_edges))
        row.set("reference_edges", int_json(c.reference_edges))
        row.set("indirect_edges", int_json(c.indirect_edges))
        row.set("local_encoded_bytes", int_json(c.local_encoded_bytes))
        row.set(
          "internal_edges",
          Json::array(c.internal_edges.map(cycle_edge_json)),
        )
        Json::object(row)
      }),
    ),
  )
  Json::object(root)
}

///|
fn cycle_edge_json(edge : CallEdge) -> Json {
  let item : Map[String, Json] = Map([])
  item.set("caller", int_json(edge.caller))
  item.set("callee", int_json(edge.callee))
  item.set("kind", Json::string(path_edge_kind(edge.kind)))
  item.set("offset", int_json(edge.offset))
  item.set("candidate", Json::boolean(edge.kind is Indirect))
  Json::object(item)
}

///|
/// Preserve the standalone schema and serialization; witnesses nest this value.
pub fn render_function_cycles_json(report : FunctionCyclesReport) -> String {
  function_cycles_json_value(report).stringify(indent=2) + "\n"
}
