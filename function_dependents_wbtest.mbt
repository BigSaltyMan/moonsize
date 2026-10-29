///|
fn dependents_test_report(
  data : Bytes,
  index : Int,
) -> FunctionDependentsReport raise {
  match function_dependents(data, index) {
    Ok(report) => report
    Err(error) => fail(describe_function_dependents_error(error))
  }
}

///|
fn dependents_test_edges(
  edges : Array[CallEdge],
) -> Array[(Int, Int, Int, Int)] {
  edges.map(fn(e) { (e.caller, e.callee, path_edge_rank(e.kind), e.offset) })
}

///|
fn dependents_test_ledger(report : FunctionDependentsReport) -> Unit raise {
  assert_eq(
    report.function_count,
    report.local_function_count + report.imported_function_count,
  )
  assert_eq(
    report.function_count,
    report.reaching_function_count + report.other_function_count,
  )
  assert_eq(
    report.reaching_function_count,
    report.reaching_local_count + report.reaching_imported_count,
  )
  assert_eq(report.dependent_function_count, report.reaching_function_count - 1)
  assert_eq(
    report.local_encoded_bytes,
    report.reaching_local_encoded_bytes + report.other_local_encoded_bytes,
  )
  assert_eq(
    report.reaching_local_encoded_bytes,
    report.target_local_encoded_bytes + report.dependent_local_encoded_bytes,
  )
  assert_eq(
    report.edge_count,
    report.direct_edges + report.reference_edges + report.indirect_edges,
  )
  assert_eq(report.nodes.length(), report.reaching_function_count)
  assert_eq(report.edges.length(), report.edge_count)
  let depths : Map[Int, Int] = Map([])
  let next : Map[Int, CallEdge] = Map([])
  let mut bytes = 0
  let mut tree = 0
  for entry in report.nodes {
    assert_true(!depths.contains(entry.node.index))
    depths.set(entry.node.index, entry.depth)
    bytes += entry.node.encoded_size.unwrap_or(0)
    if entry.node.index == report.target.index {
      assert_eq(entry.depth, 0)
      assert_true(entry.next_edge is None)
    } else {
      let edge = entry.next_edge.unwrap()
      assert_eq(edge.caller, entry.node.index)
      next.set(entry.node.index, edge)
      tree += 1
      assert_true(
        report.edges.any(fn(e) {
          e.caller == edge.caller &&
          e.callee == edge.callee &&
          path_edge_rank(e.kind) == path_edge_rank(edge.kind) &&
          e.offset == edge.offset
        }),
      )
    }
  }
  for entry in report.nodes {
    let mut cursor = entry.node.index
    for _ in 0..<entry.depth {
      let edge = next.get(cursor).unwrap()
      assert_eq(
        depths.get(edge.callee).unwrap(),
        depths.get(cursor).unwrap() - 1,
      )
      cursor = edge.callee
    }
    assert_eq(cursor, report.target.index)
  }
  for edge in report.edges {
    assert_true(depths.contains(edge.caller) && depths.contains(edge.callee))
  }
  assert_eq(tree, report.nodes.length() - 1)
  assert_eq(bytes, report.reaching_local_encoded_bytes)
}

///|
test "function-dependents: topology direction and closed byte ledgers" {
  let data = dependencies_test_fixture()
  let report = dependents_test_report(data, 2)
  assert_eq(data.length(), 130)
  assert_eq(report.nodes.map(fn(e) { (e.node.index, e.depth) }), [
    (2, 0),
    (1, 1),
    (3, 1),
    (4, 2),
  ])
  assert_eq(
    dependents_test_edges(
      report.nodes
      .filter(fn(e) { e.next_edge is Some(_) })
      .map(fn(e) { e.next_edge.unwrap() }),
    ),
    [(1, 2, 0, 67), (3, 2, 0, 93), (4, 1, 0, 98)],
  )
  assert_eq(dependents_test_edges(report.edges), [
    (1, 2, 0, 67),
    (1, 2, 0, 69),
    (1, 3, 1, 71),
    (1, 3, 2, 76),
    (1, 1, 0, 79),
    (2, 4, 0, 84),
    (3, 4, 0, 91),
    (3, 2, 0, 93),
    (4, 1, 0, 98),
  ])
  // Real target2 -> import0 @86 exists, but is an outgoing edge outside R.
  assert_true(
    build(data).unwrap().edges.any(fn(e) {
      e.caller == 2 && e.callee == 0 && e.offset == 86
    }),
  )
  assert_true(!report.nodes.any(fn(e) { e.node.index == 0 }))
  assert_true(!report.edges.any(fn(e) { e.offset == 86 }))
  assert_eq(
    (
      report.function_count,
      report.reaching_function_count,
      report.other_function_count,
    ),
    (7, 4, 3),
  )
  assert_eq(
    (report.reaching_local_count, report.reaching_imported_count),
    (4, 0),
  )
  assert_eq(
    (
      report.local_encoded_bytes,
      report.reaching_local_encoded_bytes,
      report.other_local_encoded_bytes,
    ),
    (42, 36, 6),
  )
  assert_eq(
    (report.target_local_encoded_bytes, report.dependent_local_encoded_bytes),
    (7, 29),
  )
  assert_eq(
    (
      report.edge_count,
      report.direct_edges,
      report.reference_edges,
      report.indirect_edges,
    ),
    (9, 7, 1, 1),
  )
  assert_true(report.graph_complete)
  assert_eq(report.sha256, experiment_sha256(data))
  dependents_test_ledger(report)
  let imported = dependents_test_report(data, 0)
  assert_true(imported.target.imported && imported.target.encoded_size is None)
  assert_eq(imported.nodes.map(fn(e) { (e.node.index, e.depth) }), [
    (0, 0),
    (2, 1),
    (1, 2),
    (3, 2),
    (4, 3),
  ])
  assert_eq(imported.target_local_encoded_bytes, 0)
  assert_eq(imported.dependent_local_encoded_bytes, 36)
  assert_eq(imported.edge_count, 10)
  dependents_test_ledger(imported)
  let self = dependents_test_report(data, 1)
  assert_true(self.nodes[0].next_edge is None && self.nodes[0].depth == 0)
  dependents_test_ledger(self)
  let isolated = dependents_test_report(data, 5)
  assert_eq(
    (
      isolated.dependent_function_count,
      isolated.dependent_local_encoded_bytes,
      isolated.edge_count,
    ),
    (0, 0, 0),
  )
  assert_eq(isolated.reaching_local_encoded_bytes, 3)
  dependents_test_ledger(isolated)
}

///|
test "function-dependents: deterministic next edges and whole-module failures" {
  let data = dependencies_test_fixture()
  let inventory = path_inventory(data, parse_module(data).unwrap()).unwrap()
  let original = build(data).unwrap().edges
  let reversed : Array[CallEdge] = []
  for i in 0..<original.length() {
    reversed.push(original[original.length() - 1 - i])
  }
  for target in [0, 2, 3] {
    let (nodes, edges) = dependents_closure(
      inventory,
      reversed,
      target,
      data.length(),
    ).unwrap()
    let report = dependents_test_report(data, target)
    assert_eq(dependents_test_edges(edges), dependents_test_edges(report.edges))
    assert_eq(
      nodes.map(fn(e) {
        (
          e.node.index,
          e.depth,
          e.next_edge.map(fn(p) {
            (p.caller, p.callee, path_edge_rank(p.kind), p.offset)
          }),
        )
      }),
      report.nodes.map(fn(e) {
        (
          e.node.index,
          e.depth,
          e.next_edge.map(fn(p) {
            (p.caller, p.callee, path_edge_rank(p.kind), p.offset)
          }),
        )
      }),
    )
  }
  let tie = dependents_test_report(data, 3)
  assert_true(tie.nodes[1].next_edge.unwrap().kind is Reference)
  assert_eq(tie.nodes[1].next_edge.unwrap().offset, 71)
  for index in [-1, 7, 2147483647] {
    assert_true(
      function_dependents(data, index) is Err(InvalidDependentsTarget(_, 7)),
    )
  }
  assert_true(
    function_dependents(b"\x00asm\x01\x00\x00\x00", 0)
    is Err(InvalidDependentsTarget(0, 0)),
  )
  assert_true(function_dependents(b"bad", 0) is Err(DependentsInputError(_)))
  for
    edge in [
      { caller: 6, callee: 7, kind: Direct, offset: 105, },
      { caller: -1, callee: 6, kind: Direct, offset: 105, },
      { caller: 0, callee: 6, kind: Direct, offset: 105, },
      { caller: 6, callee: 6, kind: Direct, offset: 130, },
      { caller: 6, callee: 6, kind: Direct, offset: -1, },
    ] {
    // Target5 has no sources; invalid evidence elsewhere must still fail.
    assert_true(
      dependents_closure(inventory, original + [edge], 5, 130)
      is Err(InvalidDependentsEvidence(_, _, _)),
    )
  }
  let gap = dependents_test_report(dependencies_test_fixture(gap=true), 2)
  assert_true(!gap.graph_complete)
  assert_eq(gap.unresolved_count, 0)
  assert_eq(gap.diagnostics.length(), 1)
  assert_eq((gap.diagnostics[0].caller, gap.diagnostics[0].offset), (6, 108))
  assert_eq(gap.diagnostics[0].opcode.name(), "call_ref")
  assert_true(!gap.nodes.any(fn(e) { e.node.index == 6 }))
  assert_true(
    render_function_dependents_json(gap).contains("unmodeled_reference_call"),
  )
  dependents_test_ledger(gap)
  for
    error in [
      DependentsInputError(BadMagic),
      InvalidDependentsTarget(7, 7),
      InvalidDependentsEvidence(6, 130, "outside input"),
    ] {
    assert_true(!describe_function_dependents_error(error).is_empty())
  }
}

///|
test "function-dependents: parameters rendering safe names and full JSON" {
  assert_eq(Options::default("x").dependents, None)
  assert_eq(Options::default("x").dependents_json, None)
  let args = [
    "moonsize", "--dependents", "2", "--dependents-json", "new.json", "--top", "1",
    "--strict", "--", "--help",
  ]
  assert_true(help_request(args) is Ok(None))
  let options = parse_options(args).unwrap()
  assert_eq(options.dependents, Some(2))
  assert_eq(options.dependents_json, Some("new.json"))
  assert_true(options.strict && options.path == "--help" && options.top == 1)
  for
    tail in [
      ["--dependents"],
      ["--dependents", "-1"],
      ["--dependents", "0x2"],
      ["--dependents", "2147483648"],
      ["--dependents-json", "new.json"],
      ["--dependents", "2", "--dependents-json"],
      ["--dependents", "2", "--dependents-json", "x.txt"],
      ["--dependents", "2", "--dependents-json", " "],
    ] {
    assert_true(parse_options(["moonsize", "missing.wasm"] + tail) is Err(_))
  }
  for
    tail in [
      ["--baseline", "b"],
      ["--html", "x.html"],
      ["--retained"],
      ["--dependencies", "2"],
      ["--cycles"],
      ["--cycles", "--cycle-witness"],
      ["--why-index", "2"],
      ["--callers", "2"],
      ["--calls", "2"],
      ["--entrypoints"],
      ["--budget", "b.json"],
      ["--max-size", "1KB"],
      ["--compress"],
    ] {
    assert_true(
      parse_options(["moonsize", "missing.wasm", "--dependents", "2"] + tail)
      is Err(_),
    )
  }
  assert_true(help_request(["moonsize", "--help"]) is Ok(Some(_)))
  let report = dependents_test_report(dependencies_test_fixture(), 2)
  let text = render_function_dependents(report, 1)
  assert_true(text.contains("FUNCTION TRANSITIVE MODEL REFERRERS"))
  assert_true(text.contains("REFERRERS: showing 1 of 3 (target excluded)"))
  assert_true(text.contains("shared\\n\\u001b雪"))
  assert_true(!text.contains("\n3  1  local"))
  assert_true(
    text.contains("Complete closure edges: 9") &&
    text.contains("Next-edge tree edges: 3"),
  )
  assert_true(text.contains("1  1  local  17"))
  let root = match @json.parse(render_function_dependents_json(report)) {
    Object(fields) => fields
    _ => fail("object")
  }
  assert_eq(
    root.get("format"),
    Some(Json::string("moonsize-function-dependents")),
  )
  let rows = match root.get("nodes") {
    Some(Array(rows)) => rows
    _ => fail("nodes")
  }
  assert_eq(rows.length(), 4)
  let target = match rows[0] {
    Object(fields) => fields
    _ => fail("target")
  }
  assert_eq(target.get("next_edge"), Some(Json::null()))
  let edges = match root.get("edges") {
    Some(Array(rows)) => rows
    _ => fail("edges")
  }
  assert_eq(edges.length(), 9)
  assert_true(
    render_function_dependents_json(report).contains("\"candidate\": true"),
  )
  let imported = dependents_test_report(dependencies_test_fixture(), 0)
  let import_json = render_function_dependents_json(imported)
  assert_true(import_json.contains("\"encoded_size\": null"))
  assert_true(
    render_function_dependents(imported, 1).contains(
      "imported; encoded size not measured (null)",
    ),
  )
  let empty = render_function_dependents(
    dependents_test_report(dependencies_test_fixture(), 5),
    1,
  )
  assert_true(
    empty.contains(
      "No path from another function to this target is recorded in the current model.",
    ),
  )
}
