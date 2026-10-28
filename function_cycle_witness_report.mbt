///|
pub fn render_function_cycle_witnesses(
  report : FunctionCycleWitnessReport,
  top : Int,
) -> String {
  let out = StringBuilder()
  out.write_string(render_function_cycles(report.cycles, top))
  out.write_string("\nCLOSED MODEL WITNESS\n\n" + report.scope + "\n")
  let shown = top.max(0).min(report.witnesses.length())
  out.write_string(
    "\nWITNESSES: showing \{shown} of \{report.witnesses.length()}\n",
  )
  for i in 0..<shown {
    let witness = report.witnesses[i]
    out.write_string(
      "\nComponent #\{witness.component_id}: " +
      witness.nodes.map(fn(n) { n.to_string() }).join(" -> ") +
      "\n",
    )
    out.write_string(
      "Witness edges: \{witness.edge_count} = direct \{witness.direct_edges} + reference \{witness.reference_edges} + indirect candidates \{witness.indirect_edges}\n",
    )
    let names : Map[Int, String] = Map([])
    for node in report.cycles.components[i].members {
      names.set(node.index, node.name)
    }
    for edge in witness.edges {
      let kind = match edge.kind {
        Direct => "direct"
        Reference => "reference taken"
        Indirect => "indirect candidate"
      }
      out.write_string(
        "  \{edge.caller} -> \{edge.callee}  " +
        kind +
        "  file offset \{edge.offset}\n",
      )
      out.write_string(
        "    " +
        search_terminal_string(names.get(edge.caller).unwrap()) +
        " -> " +
        search_terminal_string(names.get(edge.callee).unwrap()) +
        "\n",
      )
    }
  }
  out.to_string()
}

///|
pub fn render_function_cycle_witnesses_json(
  report : FunctionCycleWitnessReport,
) -> String {
  let root : Map[String, Json] = Map([])
  root.set("format", Json::string("moonsize-function-cycle-witnesses"))
  root.set("schema_version", int_json(1))
  root.set("cycles", function_cycles_json_value(report.cycles))
  root.set("scope", Json::string(report.scope))
  root.set(
    "witnesses",
    Json::array(
      report.witnesses.map(fn(witness) {
        let row : Map[String, Json] = Map([])
        row.set("component_id", int_json(witness.component_id))
        row.set("start_index", int_json(witness.start_index))
        row.set("nodes", Json::array(witness.nodes.map(int_json)))
        row.set("edges", Json::array(witness.edges.map(cycle_edge_json)))
        row.set("edge_count", int_json(witness.edge_count))
        row.set("direct_edges", int_json(witness.direct_edges))
        row.set("reference_edges", int_json(witness.reference_edges))
        row.set("indirect_edges", int_json(witness.indirect_edges))
        Json::object(row)
      }),
    ),
  )
  Json::object(root).stringify(indent=2) + "\n"
}
