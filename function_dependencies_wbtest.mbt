///|
fn dependencies_test_fixture(gap? : Bool = false) -> Bytes {
  let bodies = [
    b"\x00\x10\x02\x10\x02\xd2\x03\x1a\x41\x00\x11\x00\x00\x10\x01\x0b",
    b"\x00\x10\x04\x10\x00\x0b",
    b"\x00\x10\x04\x10\x02\x0b",
    b"\x00\x10\x01\x0b",
    b"\x00\x0b",
    if gap {
      b"\x00\xd2\x00\x14\x00\x0b"
    } else {
      b"\x00\x0b"
    },
  ]
  let mut code = search_test_leb(bodies.length())
  for body in bodies {
    code = code + search_test_leb(body.length()) + body
  }
  let name = @utf8.encode("shared\n\u001b雪")
  b"\x00asm\x01\x00\x00\x00" +
  search_test_section(1, b"\x01\x60\x00\x00") +
  search_test_section(2, b"\x01\x01m\x01f\x00\x00") +
  search_test_section(3, b"\x06\x00\x00\x00\x00\x00\x00") +
  search_test_section(4, b"\x01\x70\x00\x01") +
  search_test_section(7, b"\x01\x05entry\x00\x05") +
  search_test_section(9, b"\x02\x00\x41\x00\x0b\x01\x03\x03\x00\x01\x00") +
  search_test_section(10, code) +
  search_test_section(
    0,
    b"\x04name" +
    search_test_section(1, b"\x01\x02" + search_test_leb(name.length()) + name),
  )
}

///|
fn dependencies_test_report(
  data : Bytes,
  index : Int,
) -> FunctionDependenciesReport raise {
  match function_dependencies(data, index) {
    Ok(report) => report
    Err(error) => fail(describe_function_dependencies_error(error))
  }
}

///|
fn dependencies_test_edges(
  edges : Array[CallEdge],
) -> Array[(Int, Int, Int, Int)] {
  edges.map(fn(e) { (e.caller, e.callee, path_edge_rank(e.kind), e.offset) })
}

///|
fn dependencies_test_ledger(report : FunctionDependenciesReport) -> Unit raise {
  assert_eq(
    report.function_count,
    report.local_function_count + report.imported_function_count,
  )
  assert_eq(
    report.function_count,
    report.reachable_function_count + report.other_function_count,
  )
  assert_eq(
    report.reachable_function_count,
    report.reachable_local_count + report.reachable_imported_count,
  )
  assert_eq(
    report.dependency_function_count,
    report.reachable_function_count - 1,
  )
  assert_eq(
    report.local_encoded_bytes,
    report.reachable_local_encoded_bytes + report.other_local_encoded_bytes,
  )
  assert_eq(
    report.reachable_local_encoded_bytes,
    report.target_local_encoded_bytes + report.dependency_local_encoded_bytes,
  )
  assert_eq(
    report.edge_count,
    report.direct_edges + report.reference_edges + report.indirect_edges,
  )
  assert_eq(report.nodes.length(), report.reachable_function_count)
  assert_eq(report.edges.length(), report.edge_count)
  let seen : Set[Int] = Set([])
  let depths : Map[Int, Int] = Map([])
  let mut bytes = 0
  let mut tree = 0
  for entry in report.nodes {
    assert_true(!seen.contains(entry.node.index))
    seen.add(entry.node.index)
    depths.set(entry.node.index, entry.depth)
    bytes += entry.node.encoded_size.unwrap_or(0)
    if entry.node.index == report.target.index {
      assert_eq(entry.depth, 0)
      assert_true(entry.predecessor is None)
    } else {
      let edge = entry.predecessor.unwrap()
      assert_eq(edge.callee, entry.node.index)
      assert_true(
        report.edges.any(fn(e) {
          e.caller == edge.caller &&
          e.callee == edge.callee &&
          path_edge_rank(e.kind) == path_edge_rank(edge.kind) &&
          e.offset == edge.offset
        }),
      )
      tree += 1
    }
  }
  for entry in report.nodes {
    if entry.predecessor is Some(edge) {
      assert_eq(entry.depth, depths.get(edge.caller).unwrap() + 1)
    }
  }
  for edge in report.edges {
    assert_true(seen.contains(edge.caller) && seen.contains(edge.callee))
  }
  assert_eq(bytes, report.reachable_local_encoded_bytes)
  assert_eq(tree, report.dependency_function_count)
}

///|
test "function-dependencies: closure depths unique counts and byte ledgers" {
  let data = dependencies_test_fixture()
  let report = dependencies_test_report(data, 1)
  assert_eq(data.length(), 130)
  assert_eq(report.function_count, 7)
  assert_eq(report.nodes.map(fn(e) { (e.node.index, e.depth) }), [
    (1, 0),
    (2, 1),
    (3, 1),
    (0, 2),
    (4, 2),
  ])
  assert_eq(report.nodes[1].predecessor.unwrap().offset, 67) // earlier parallel direct edge
  let reference = report.nodes[2].predecessor.unwrap()
  assert_true(reference.kind is Reference)
  assert_eq(reference.offset, 71) // reference before parallel indirect candidate
  assert_eq(report.nodes[3].predecessor.unwrap().caller, 2)
  assert_eq(report.nodes[3].predecessor.unwrap().offset, 86)
  assert_eq(report.nodes[4].predecessor.unwrap().caller, 2) // deterministic first diamond route
  assert_eq(report.nodes[4].predecessor.unwrap().offset, 84)
  assert_eq(
    (
      report.reachable_local_count,
      report.reachable_imported_count,
      report.other_function_count,
    ),
    (4, 1, 2),
  )
  assert_eq(
    (
      report.local_encoded_bytes,
      report.reachable_local_encoded_bytes,
      report.other_local_encoded_bytes,
    ),
    (42, 36, 6),
  )
  assert_eq(
    (report.target_local_encoded_bytes, report.dependency_local_encoded_bytes),
    (17, 19),
  )
  assert_eq(
    (
      report.edge_count,
      report.direct_edges,
      report.reference_edges,
      report.indirect_edges,
    ),
    (10, 8, 1, 1),
  )
  assert_eq(
    report.edges.filter(fn(e) { e.caller == 1 && e.callee == 2 }).length(),
    2,
  )
  assert_true(report.nodes[0].predecessor is None) // self and back edge must not overwrite target
  assert_true(
    report.nodes[3].node.imported && report.nodes[3].node.encoded_size is None,
  )
  assert_true(report.graph_complete)
  assert_eq(report.sha256, experiment_sha256(data))
  dependencies_test_ledger(report)
  let imported = dependencies_test_report(data, 0)
  assert_eq(imported.reachable_function_count, 1)
  assert_eq(imported.target_local_encoded_bytes, 0)
  assert_eq(imported.dependency_local_encoded_bytes, 0)
  assert_true(imported.target.encoded_size is None)
  assert_eq(imported.edge_count, 0)
  dependencies_test_ledger(imported)
  let isolated = dependencies_test_report(data, 5)
  assert_eq(isolated.dependency_function_count, 0)
  assert_eq(isolated.reachable_local_encoded_bytes, 3)
  dependencies_test_ledger(isolated)
}

///|
test "function-dependencies: deterministic evidence and whole-graph errors" {
  let data = dependencies_test_fixture()
  let inventory = path_inventory(data, parse_module(data).unwrap()).unwrap()
  let report = dependencies_test_report(data, 1)
  let reordered : Array[CallEdge] = []
  for i in 0..<report.edges.length() {
    reordered.push(report.edges[report.edges.length() - 1 - i])
  }
  let (nodes, edges) = dependencies_closure(
    inventory,
    reordered,
    1,
    data.length(),
  ).unwrap()
  assert_eq(
    dependencies_test_edges(edges),
    dependencies_test_edges(report.edges),
  )
  assert_eq(
    nodes.map(fn(e) {
      (
        e.node.index,
        e.depth,
        e.predecessor.map(fn(p) {
          (p.caller, p.callee, path_edge_rank(p.kind), p.offset)
        }),
      )
    }),
    report.nodes.map(fn(e) {
      (
        e.node.index,
        e.depth,
        e.predecessor.map(fn(p) {
          (p.caller, p.callee, path_edge_rank(p.kind), p.offset)
        }),
      )
    }),
  )
  for index in [-1, 7, 2147483647] {
    assert_true(
      function_dependencies(data, index) is Err(InvalidDependenciesTarget(_, 7)),
    )
  }
  assert_true(
    function_dependencies(b"\x00asm\x01\x00\x00\x00", 0)
    is Err(InvalidDependenciesTarget(0, 0)),
  )
  assert_true(
    function_dependencies(b"bad", 0) is Err(DependenciesInputError(_)),
  )
  for
    edge in [
      { caller: 5, callee: 7, kind: Direct, offset: 102, },
      { caller: -1, callee: 1, kind: Direct, offset: 102, },
      { caller: 0, callee: 1, kind: Direct, offset: 102, },
      { caller: 5, callee: 1, kind: Direct, offset: 130, },
      { caller: 5, callee: 1, kind: Direct, offset: -1, },
    ] {
    // Target0 has no outgoing edges: invalid evidence elsewhere must still fail.
    assert_true(
      dependencies_closure(inventory, report.edges + [edge], 0, 130)
      is Err(InvalidDependenciesEvidence(_, _, _)),
    )
  }
  let gap = dependencies_test_report(dependencies_test_fixture(gap=true), 1)
  assert_true(!gap.graph_complete)
  assert_eq(gap.unresolved_count, 0)
  assert_eq(gap.diagnostics.length(), 1)
  assert_eq(gap.diagnostics[0].caller, 6)
  assert_eq(gap.diagnostics[0].offset, 108)
  assert_eq(gap.diagnostics[0].opcode.name(), "call_ref")
  assert_true(!gap.nodes.any(fn(e) { e.node.index == 6 }))
  assert_true(
    render_function_dependencies_json(gap).contains("unmodeled_reference_call"),
  )
  let gap_import = dependencies_test_report(
    dependencies_test_fixture(gap=true),
    0,
  )
  assert_true(
    !gap_import.graph_complete && gap_import.reachable_function_count == 1,
  )
  dependencies_test_ledger(gap)
  for
    error in [
      DependenciesInputError(BadMagic),
      InvalidDependenciesTarget(7, 7),
      InvalidDependenciesEvidence(7, 102, "outside inventory"),
    ] {
    assert_true(!describe_function_dependencies_error(error).is_empty())
  }
}

///|
test "function-dependencies: CLI rendering null and full JSON" {
  assert_eq(Options::default("x").dependencies, None)
  assert_eq(Options::default("x").dependencies_json, None)
  let args = [
    "moonsize", "--dependencies", "1", "--dependencies-json", "new.json", "--top",
    "1", "--strict", "--", "--help",
  ]
  assert_true(help_request(args) is Ok(None))
  let options = parse_options(args).unwrap()
  assert_eq(options.dependencies, Some(1))
  assert_eq(options.dependencies_json, Some("new.json"))
  assert_true(options.strict && options.path == "--help" && options.top == 1)
  for
    tail in [
      ["--dependencies"],
      ["--dependencies", "-1"],
      ["--dependencies", "0x1"],
      ["--dependencies", "2147483648"],
      ["--dependencies-json", "new.json"],
      ["--dependencies", "0", "--dependencies-json"],
      ["--dependencies", "0", "--dependencies-json", "x.txt"],
    ] {
    assert_true(parse_options(["moonsize", "missing.wasm"] + tail) is Err(_))
  }
  for
    tail in [
      ["--baseline", "b"],
      ["--html", "x.html"],
      ["--retained"],
      ["--cycles"],
      ["--cycles", "--cycle-witness"],
      ["--why-index", "0"],
      ["--callers", "0"],
      ["--calls", "0"],
      ["--entrypoints"],
      ["--budget", "b.json"],
      ["--max-size", "1KB"],
      ["--compress"],
    ] {
    assert_true(
      parse_options(["moonsize", "missing.wasm", "--dependencies", "0"] + tail)
      is Err(_),
    )
  }
  assert_true(help_request(["moonsize", "--help"]) is Ok(Some(_)))
  let report = dependencies_test_report(dependencies_test_fixture(), 1)
  let text = render_function_dependencies(report, 1)
  assert_true(text.contains("FUNCTION TRANSITIVE MODEL DEPENDENCIES"))
  assert_true(text.contains("DEPENDENCIES: showing 1 of 4 (target excluded)"))
  assert_true(text.contains("shared\\n\\u001b雪"))
  assert_true(!text.contains("\n3  1  local"))
  assert_true(
    text.contains("Complete closure edges: 10") &&
    text.contains("Predecessor tree edges: 4"),
  )
  let root = match @json.parse(render_function_dependencies_json(report)) {
    Object(fields) => fields
    _ => fail("object")
  }
  assert_eq(
    root.get("format"),
    Some(Json::string("moonsize-function-dependencies")),
  )
  let rows = match root.get("nodes") {
    Some(Array(rows)) => rows
    _ => fail("nodes")
  }
  assert_eq(rows.length(), 5)
  let target = match rows[0] {
    Object(fields) => fields
    _ => fail("target")
  }
  assert_eq(target.get("predecessor"), Some(Json::null()))
  let imported = match rows[3] {
    Object(fields) => fields
    _ => fail("import")
  }
  let node = match imported.get("node") {
    Some(Object(fields)) => fields
    _ => fail("node")
  }
  assert_eq(node.get("encoded_size"), Some(Json::null()))
  let edges = match root.get("edges") {
    Some(Array(rows)) => rows
    _ => fail("edges")
  }
  assert_eq(edges.length(), 10)
  assert_true(
    render_function_dependencies_json(report).contains("\"candidate\": true"),
  )
  let empty = render_function_dependencies(
    dependencies_test_report(dependencies_test_fixture(), 0),
    1,
  )
  assert_true(
    empty.contains(
      "No path from this target to another function is recorded in the current model.",
    ),
  )
  assert_true(empty.contains("imported; encoded size not measured (null)"))
}
