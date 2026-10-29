///|
pub fn render_function_dependencies(
  report : FunctionDependenciesReport,
  top : Int,
) -> String {
  let out = StringBuilder()
  out.write_string("FUNCTION TRANSITIVE MODEL DEPENDENCIES\n\n")
  if !report.graph_warning.is_empty() {
    out.write_string(report.graph_warning + "\n\n")
  }
  out.write_string(
    "Target #\{report.target.index}: " +
    search_terminal_string(report.target.name) +
    "\n",
  )
  out.write_string(
    "Target identity: " +
    (if report.target.imported {
      "imported; encoded size not measured (null)"
    } else {
      "local; encoded \{report.target_local_encoded_bytes} B"
    }) +
    "; depth 0; predecessor n/a\n",
  )
  out.write_string(
    "Input: \{report.file_size} B; SHA-256 \{report.sha256}\nFunctions: \{report.function_count} = local \{report.local_function_count} + imports \{report.imported_function_count}\nFunctions: \{report.function_count} = reachable \{report.reachable_function_count} + other \{report.other_function_count}\nReachable: \{report.reachable_function_count} = local \{report.reachable_local_count} + imports \{report.reachable_imported_count}\nDependency functions: \{report.dependency_function_count} = reachable \{report.reachable_function_count} - target 1\nLocal encoded bytes: \{report.local_encoded_bytes} = reachable \{report.reachable_local_encoded_bytes} + other \{report.other_local_encoded_bytes}\nReachable local encoded bytes: \{report.reachable_local_encoded_bytes} = target \{report.target_local_encoded_bytes} + dependencies \{report.dependency_local_encoded_bytes}\nComplete closure edges: \{report.edge_count} = direct \{report.direct_edges} + reference \{report.reference_edges} + indirect candidates \{report.indirect_edges}\nPredecessor tree edges: \{report.dependency_function_count}; complete edges also retain parallel sites, cross edges, self-loops and back references.\nUnresolved table call sites (no static candidates): \{report.unresolved_count}\n",
  )
  let shown = top.max(0).min(report.dependency_function_count)
  out.write_string(
    "\nDEPENDENCIES: showing \{shown} of \{report.dependency_function_count} (target excluded)\nINDEX  DEPTH  IDENTITY  ENCODED BYTES  NAME  PREDECESSOR CALLER / KIND / FILE OFFSET\n",
  )
  let mut rows = 0
  for entry in report.nodes {
    if entry.node.index == report.target.index {
      continue
    }
    if rows >= shown {
      break
    }
    let node = entry.node
    let size = match node.encoded_size {
      Some(n) => n.to_string()
      None => "n/a (not measured)"
    }
    let predecessor = match entry.predecessor {
      Some(edge) =>
        "\{edge.caller} / " +
        (match edge.kind {
          Direct => "direct"
          Reference => "reference taken"
          Indirect => "indirect candidate"
        }) +
        " / \{edge.offset}"
      None => "n/a"
    }
    out.write_string(
      "\{node.index}  \{entry.depth}  " +
      (if node.imported { "imported" } else { "local" }) +
      "  " +
      size +
      "  " +
      search_terminal_string(node.name) +
      "  " +
      predecessor +
      "\n",
    )
    rows += 1
  }
  if report.dependency_function_count == 0 {
    out.write_string(
      "\nNo path from this target to another function is recorded in the current model. This does not prove absence of host dependencies or costs.\n",
    )
  }
  out.write_string("\n" + report.modeling_scope + "\n")
  out.to_string()
}

///|
pub fn render_function_dependencies_json(
  report : FunctionDependenciesReport,
) -> String {
  let root : Map[String, Json] = Map([])
  root.set("format", Json::string("moonsize-function-dependencies"))
  root.set("schema_version", int_json(1))
  root.set("target", path_node_json(report.target))
  root.set("file_size", int_json(report.file_size))
  root.set("sha256", Json::string(report.sha256))
  root.set("function_count", int_json(report.function_count))
  root.set("local_function_count", int_json(report.local_function_count))
  root.set("imported_function_count", int_json(report.imported_function_count))
  root.set(
    "reachable_function_count",
    int_json(report.reachable_function_count),
  )
  root.set("other_function_count", int_json(report.other_function_count))
  root.set("reachable_local_count", int_json(report.reachable_local_count))
  root.set(
    "reachable_imported_count",
    int_json(report.reachable_imported_count),
  )
  root.set(
    "dependency_function_count",
    int_json(report.dependency_function_count),
  )
  root.set("local_encoded_bytes", int_json(report.local_encoded_bytes))
  root.set(
    "reachable_local_encoded_bytes",
    int_json(report.reachable_local_encoded_bytes),
  )
  root.set(
    "other_local_encoded_bytes",
    int_json(report.other_local_encoded_bytes),
  )
  root.set(
    "target_local_encoded_bytes",
    int_json(report.target_local_encoded_bytes),
  )
  root.set(
    "dependency_local_encoded_bytes",
    int_json(report.dependency_local_encoded_bytes),
  )
  root.set("edge_count", int_json(report.edge_count))
  root.set("direct_edges", int_json(report.direct_edges))
  root.set("reference_edges", int_json(report.reference_edges))
  root.set("indirect_edges", int_json(report.indirect_edges))
  root.set(
    "nodes",
    Json::array(
      report.nodes.map(fn(entry) {
        let row : Map[String, Json] = Map([])
        row.set("node", path_node_json(entry.node))
        row.set("depth", int_json(entry.depth))
        row.set(
          "predecessor",
          match entry.predecessor {
            Some(edge) => cycle_edge_json(edge)
            None => Json::null()
          },
        )
        Json::object(row)
      }),
    ),
  )
  root.set("edges", Json::array(report.edges.map(cycle_edge_json)))
  root.set("graph_complete", Json::boolean(report.graph_complete))
  root.set("unresolved_count", int_json(report.unresolved_count))
  root.set("diagnostics", diagnostic_records_json(report.diagnostics))
  root.set("graph_warning", Json::string(report.graph_warning))
  root.set("modeling_scope", Json::string(report.modeling_scope))
  Json::object(root).stringify(indent=2) + "\n"
}
