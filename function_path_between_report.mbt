///|
fn between_status_name(status : FunctionPathBetweenStatus) -> String {
  match status {
    BetweenPathFound => "found"
    BetweenPathNotFound => "not-found-within-model"
  }
}

///|
pub fn render_function_path_between(
  report : FunctionPathBetweenReport,
) -> String {
  let out = StringBuilder()
  out.write_string("FUNCTION-TO-FUNCTION MODEL PATH\n\n")
  out.write_string(
    "Query: \{report.source.index} -> \{report.target_index}\nSource: " +
    search_terminal_string(report.source.name) +
    "\nInput: \{report.file_size} B; SHA-256 \{report.sha256}\nStatus: " +
    between_status_name(report.status) +
    "\n",
  )
  if !report.graph_warning.is_empty() {
    out.write_string(report.graph_warning + "\n")
  }
  out.write_string(
    "Prepared closure functions: \{report.prepared_closure_function_count} of \{report.function_count}\nUnresolved table call sites (no static candidates): \{report.unresolved_count}\n",
  )
  match report.status {
    BetweenPathNotFound =>
      out.write_string(
        "No path recorded in this direction within the current model. Destination identity was not re-read or guessed.\nHops: n/a (null)\n",
      )
    BetweenPathFound => {
      out.write_string(
        "Hops: " +
        (match report.hop_count {
          Some(n) => n.to_string()
          None => "n/a (null)"
        }) +
        "\n",
      )
      if report.path_edges.is_empty() {
        out.write_string(
          "Zero-step path: source and destination are the same index; this is not evidence of a nonempty cycle.\n",
        )
      }
      out.write_string(
        "\nNODES (FROM -> TO)\nINDEX  IDENTITY  ENCODED BYTES  NAME\n",
      )
      for node in report.path_nodes {
        let size = match node.encoded_size {
          Some(n) => n.to_string()
          None => "n/a (not measured)"
        }
        out.write_string(
          "\{node.index}  " +
          (if node.imported { "imported" } else { "local" }) +
          "  " +
          size +
          "  " +
          search_terminal_string(node.name) +
          "\n",
        )
      }
      out.write_string(
        "\nEDGES (original caller -> callee)\nCALLER  CALLEE  KIND  FILE OFFSET\n",
      )
      for edge in report.path_edges {
        let kind = match edge.kind {
          Direct => "direct"
          Reference => "reference taken"
          Indirect => "indirect candidate"
        }
        out.write_string(
          "\{edge.caller}  \{edge.callee}  " + kind + "  \{edge.offset}\n",
        )
      }
    }
  }
  out.write_string("\n" + report.modeling_scope + "\n")
  out.to_string()
}

///|
pub fn render_function_path_between_json(
  report : FunctionPathBetweenReport,
) -> String {
  let root : Map[String, Json] = Map([])
  root.set("format", Json::string("moonsize-function-path-between"))
  root.set("schema_version", int_json(1))
  root.set("source", path_node_json(report.source))
  root.set("target_index", int_json(report.target_index))
  root.set("file_size", int_json(report.file_size))
  root.set("sha256", Json::string(report.sha256))
  root.set("function_count", int_json(report.function_count))
  root.set("status", Json::string(between_status_name(report.status)))
  root.set("path_nodes", Json::array(report.path_nodes.map(path_node_json)))
  root.set("path_edges", Json::array(report.path_edges.map(cycle_edge_json)))
  root.set(
    "hop_count",
    match report.hop_count {
      Some(n) => int_json(n)
      None => Json::null()
    },
  )
  root.set(
    "prepared_closure_function_count",
    int_json(report.prepared_closure_function_count),
  )
  root.set("graph_complete", Json::boolean(report.graph_complete))
  root.set("unresolved_count", int_json(report.unresolved_count))
  root.set("diagnostics", diagnostic_records_json(report.diagnostics))
  root.set("graph_warning", Json::string(report.graph_warning))
  root.set("modeling_scope", Json::string(report.modeling_scope))
  Json::object(root).stringify(indent=2) + "\n"
}
