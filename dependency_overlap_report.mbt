///|
pub fn render_dependency_overlap(
  report : DependencyOverlapReport,
  top : Int,
) -> String {
  let out = StringBuilder()
  out.write_string(
    "FUNCTION DEPENDENCY SET COMPARISON\n\nLeft #\{report.left_index}: " +
    search_terminal_string(report.functions[report.left_index].name) +
    "\nRight #\{report.right_index}: " +
    search_terminal_string(report.functions[report.right_index].name) +
    "\nInput: \{report.file_size} B; SHA-256 \{report.sha256}\n",
  )
  if !report.graph_warning.is_empty() {
    out.write_string(report.graph_warning + "\n")
  }
  out.write_string("\nGROUP  FUNCTIONS  LOCAL  IMPORTED  LOCAL ENCODED BYTES\n")
  for group in report.groups {
    out.write_string(
      "\{group.kind}  \{group.function_count}  \{group.local_count}  \{group.imported_count}  \{group.local_encoded_bytes}\n",
    )
  }
  let s = report.groups[0]
  let l = report.groups[1]
  let r = report.groups[2]
  let n = report.groups[3]
  out.write_string(
    "\nFunction ledger: all \{report.function_count} = shared \{s.function_count} + left_only \{l.function_count} + right_only \{r.function_count} + neither \{n.function_count}\nLeft functions: \{report.left_function_count} = left_only \{l.function_count} + shared \{s.function_count}\nRight functions: \{report.right_function_count} = right_only \{r.function_count} + shared \{s.function_count}\nUnion functions: \{report.union_function_count} = left_only \{l.function_count} + right_only \{r.function_count} + shared \{s.function_count}\nAll functions: \{report.function_count} = union \{report.union_function_count} + neither \{n.function_count}\nLocal encoded bytes: all \{report.local_encoded_bytes} = shared \{s.local_encoded_bytes} + left_only \{l.local_encoded_bytes} + right_only \{r.local_encoded_bytes} + neither \{n.local_encoded_bytes}\nLeft local bytes: \{report.left_local_encoded_bytes} = left_only \{l.local_encoded_bytes} + shared \{s.local_encoded_bytes}\nRight local bytes: \{report.right_local_encoded_bytes} = right_only \{r.local_encoded_bytes} + shared \{s.local_encoded_bytes}\nUnion local bytes: \{report.union_local_encoded_bytes} = left_only \{l.local_encoded_bytes} + right_only \{r.local_encoded_bytes} + shared \{s.local_encoded_bytes}\nAll local bytes: \{report.local_encoded_bytes} = union \{report.union_local_encoded_bytes} + neither \{n.local_encoded_bytes}\nComplete closure edges: left \{report.left_edges.length()}, right \{report.right_edges.length()} (not additive as unique call sites)\nUnresolved table call sites (no static candidates): \{report.unresolved_count}\n",
  )
  for i in 0..<3 {
    let group = report.groups[i]
    let order = group.indices.map(fn(index) { index })
    order.sort_by(fn(a, b) {
      let x = report.functions[a]
      let y = report.functions[b]
      if x.imported != y.imported {
        return if x.imported { 1 } else { -1 }
      }
      let size = y.encoded_size.unwrap_or(0) - x.encoded_size.unwrap_or(0)
      if size != 0 {
        size
      } else {
        a - b
      }
    })
    let shown = top.max(0).min(order.length())
    out.write_string(
      "\n\{group.kind}: showing \{shown} of \{group.function_count}\nINDEX  IDENTITY  ENCODED BYTES  NAME\n",
    )
    for j in 0..<shown {
      let node = report.functions[order[j]]
      let size = match node.encoded_size {
        Some(size) => size.to_string()
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
  }
  out.write_string(
    "\nNeither members are summary-only here; complete indices are in JSON.\n" +
    report.modeling_scope +
    "\n",
  )
  out.to_string()
}

///|
pub fn render_dependency_overlap_json(
  report : DependencyOverlapReport,
) -> String {
  let root : Map[String, Json] = Map([])
  root.set("format", Json::string("moonsize-dependency-overlap"))
  root.set("schema_version", int_json(1))
  root.set("file_size", int_json(report.file_size))
  root.set("sha256", Json::string(report.sha256))
  root.set("left_index", int_json(report.left_index))
  root.set("right_index", int_json(report.right_index))
  root.set("functions", Json::array(report.functions.map(path_node_json)))
  root.set("left_reachable", Json::array(report.left_reachable.map(int_json)))
  root.set("right_reachable", Json::array(report.right_reachable.map(int_json)))
  root.set("left_edges", Json::array(report.left_edges.map(cycle_edge_json)))
  root.set("right_edges", Json::array(report.right_edges.map(cycle_edge_json)))
  root.set(
    "groups",
    Json::array(
      report.groups.map(fn(group) {
        let row : Map[String, Json] = Map([])
        row.set("kind", Json::string(group.kind))
        row.set("indices", Json::array(group.indices.map(int_json)))
        row.set("function_count", int_json(group.function_count))
        row.set("local_count", int_json(group.local_count))
        row.set("imported_count", int_json(group.imported_count))
        row.set("local_encoded_bytes", int_json(group.local_encoded_bytes))
        Json::object(row)
      }),
    ),
  )
  root.set("function_count", int_json(report.function_count))
  root.set("local_function_count", int_json(report.local_function_count))
  root.set("imported_function_count", int_json(report.imported_function_count))
  root.set("local_encoded_bytes", int_json(report.local_encoded_bytes))
  root.set("left_function_count", int_json(report.left_function_count))
  root.set("left_local_count", int_json(report.left_local_count))
  root.set("left_imported_count", int_json(report.left_imported_count))
  root.set(
    "left_local_encoded_bytes",
    int_json(report.left_local_encoded_bytes),
  )
  root.set("right_function_count", int_json(report.right_function_count))
  root.set("right_local_count", int_json(report.right_local_count))
  root.set("right_imported_count", int_json(report.right_imported_count))
  root.set(
    "right_local_encoded_bytes",
    int_json(report.right_local_encoded_bytes),
  )
  root.set("union_function_count", int_json(report.union_function_count))
  root.set("union_local_count", int_json(report.union_local_count))
  root.set("union_imported_count", int_json(report.union_imported_count))
  root.set(
    "union_local_encoded_bytes",
    int_json(report.union_local_encoded_bytes),
  )
  root.set("graph_complete", Json::boolean(report.graph_complete))
  root.set("unresolved_count", int_json(report.unresolved_count))
  root.set("diagnostics", diagnostic_records_json(report.diagnostics))
  root.set("graph_warning", Json::string(report.graph_warning))
  root.set("modeling_scope", Json::string(report.modeling_scope))
  Json::object(root).stringify(indent=2) + "\n"
}
