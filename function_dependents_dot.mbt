///|
/// Render complete incoming-closure evidence in original caller-to-callee direction without analysing or mutating it.
/// Top is deliberately absent. Parallel edges remain separate DOT statements.
pub fn render_function_dependents_dot(
  report : FunctionDependentsReport,
) -> String {
  let out = StringBuilder()
  out.write_string("digraph moonsize_dependents {\n  rankdir=LR;\n")
  let title = [
    "Functions with a modeled path to target #\{report.target.index}; nodes \{report.nodes.length()}; edges \{report.edges.length()}",
    "Direct: solid; reference: dashed; indirect candidate: dotted. Edge labels are file offsets, not call-site counts.",
    "Current reference model, not actual execution, source-change impact or removal savings. No global dead/live classification. Layout cost is not bounded.",
  ]
  if !report.graph_complete {
    title.push(
      "WARNING: incomplete graph; diagnostics \{report.diagnostics.length()}",
    )
  }
  if !report.graph_warning.is_empty() {
    title.push(report.graph_warning)
  }
  out.write_string(
    "  graph [labelloc=\"t\", label=" + dependencies_dot_label(title) + "];\n",
  )
  for
    (key, value) in [
      ("input_sha256", report.sha256),
      ("file_size", report.file_size.to_string()),
      ("target_index", report.target.index.to_string()),
      ("graph_complete", report.graph_complete.to_string()),
      ("unresolved_count", report.unresolved_count.to_string()),
      ("modeling_scope", report.modeling_scope),
      ("graph_warning", report.graph_warning),
      (
        "diagnostics_json",
        diagnostic_records_json(report.diagnostics).stringify(),
      ),
    ] {
    out.write_string("  " + key + "=" + dependencies_dot_quote(value) + ";\n")
  }
  let nodes = report.nodes.copy()
  nodes.sort_by(fn(a, b) { a.node.index - b.node.index })
  for entry in nodes {
    let node = entry.node
    let label = [
      "#\{node.index}: " + node.name,
      if node.imported {
        "imported; encoded size not measured"
      } else {
        "local; encoded size " +
        (match node.encoded_size {
          Some(n) => "\{n} B"
          None => "not measured"
        })
      },
      "depth to target \{entry.depth}",
    ]
    let target = node.index == report.target.index
    if target {
      label.push("query target")
    }
    out.write_string(
      "  fn_\{node.index} [shape=" +
      (if node.imported { "ellipse" } else { "box" }) +
      ", label=" +
      dependencies_dot_label(label) +
      (if target {
        ", penwidth=2, style=filled, fillcolor=\"lightyellow\""
      } else {
        ""
      }) +
      "];\n",
    )
  }
  let edges = report.edges.copy()
  edges.sort_by(fn(a, b) {
    if a.caller != b.caller {
      a.caller - b.caller
    } else if a.offset != b.offset {
      a.offset - b.offset
    } else if a.callee != b.callee {
      a.callee - b.callee
    } else {
      path_edge_rank(a.kind) - path_edge_rank(b.kind)
    }
  })
  for edge in edges {
    let (kind, style) = match edge.kind {
      Direct => ("direct", "solid")
      Reference => ("reference", "dashed")
      Indirect => ("indirect candidate", "dotted")
    }
    out.write_string(
      "  fn_\{edge.caller} -> fn_\{edge.callee} [style=" +
      style +
      ", label=" +
      dependencies_dot_quote(kind + "; file offset \{edge.offset}") +
      "];\n",
    )
  }
  out.write_string("}\n")
  out.to_string()
}
