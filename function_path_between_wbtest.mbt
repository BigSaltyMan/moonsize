///|
fn between_test_report(
  data : Bytes,
  source : Int,
  target : Int,
) -> FunctionPathBetweenReport raise {
  match function_path_between(data, source, target) {
    Ok(report) => report
    Err(error) => fail(describe_function_path_between_error(error))
  }
}

///|
fn between_test_edges(edges : Array[CallEdge]) -> Array[(Int, Int, Int, Int)] {
  edges.map(fn(e) { (e.caller, e.callee, path_edge_rank(e.kind), e.offset) })
}

///|
fn between_test_path(report : FunctionPathBetweenReport) -> Unit raise {
  match report.status {
    BetweenPathNotFound => {
      assert_true(report.path_nodes.is_empty() && report.path_edges.is_empty())
      assert_true(report.hop_count is None)
    }
    BetweenPathFound => {
      assert_eq(report.path_nodes.length(), report.path_edges.length() + 1)
      assert_eq(report.hop_count, Some(report.path_edges.length()))
      assert_eq(report.path_nodes[0].index, report.source.index)
      assert_eq(
        report.path_nodes[report.path_nodes.length() - 1].index,
        report.target_index,
      )
      for i in 0..<report.path_edges.length() {
        assert_eq(report.path_edges[i].caller, report.path_nodes[i].index)
        assert_eq(report.path_edges[i].callee, report.path_nodes[i + 1].index)
      }
    }
  }
}

///|
test "function-path-between: stable shortest paths zero hops and imports" {
  let data = dependencies_test_fixture()
  // The byte fixture exports only local5, no start; elements reference3 and0.
  // Source1 is explicitly not a model root, without running an old why query.
  let parsed = parse_module(data).unwrap()
  let sections = find_sections(parsed)
  let exports = match sections.exports {
    Some(s) => parse_export_section(data, s).unwrap()
    None => []
  }
  assert_eq(exports.map(fn(e) { (e.kind, e.index) }), [(0, 5)])
  assert_true(sections.start is None)
  let elements = match sections.elements {
    Some(s) => parse_element_section(data, s).unwrap()
    None => []
  }
  assert_true(!elements.any(fn(e) { e.functions.contains(1) }))
  let report = between_test_report(data, 1, 4)
  assert_true(report.status is BetweenPathFound)
  assert_eq(report.source.index, 1)
  assert_eq(report.path_nodes.map(fn(n) { n.index }), [1, 2, 4])
  assert_eq(between_test_edges(report.path_edges), [
    (1, 2, 0, 67),
    (2, 4, 0, 84),
  ])
  assert_eq(report.hop_count, Some(2))
  assert_eq(report.prepared_closure_function_count, 5)
  assert_eq(report.sha256, experiment_sha256(data))
  assert_eq(report.file_size, 130)
  between_test_path(report)
  let imported = between_test_report(data, 1, 0)
  assert_eq(imported.path_nodes.map(fn(n) { n.index }), [1, 2, 0])
  assert_eq(between_test_edges(imported.path_edges), [
    (1, 2, 0, 67),
    (2, 0, 0, 86),
  ])
  assert_true(
    imported.path_nodes[2].imported &&
    imported.path_nodes[2].encoded_size is None,
  )
  between_test_path(imported)
  let reference = between_test_report(data, 1, 3)
  assert_eq(between_test_edges(reference.path_edges), [(1, 3, 1, 71)])
  // Stable dependencies order is reused: Reference71 wins over candidate76.
  let again = between_test_report(data, 1, 4)
  assert_eq(
    render_function_path_between_json(report),
    render_function_path_between_json(again),
  )
  let back = between_test_report(data, 4, 1)
  assert_eq(between_test_edges(back.path_edges), [(4, 1, 0, 98)])
  between_test_path(back)
  for pair in [(0, 1), (1, 5)] {
    let (source, target) = pair
    let absent = between_test_report(data, source, target)
    assert_true(absent.status is BetweenPathNotFound)
    assert_eq(absent.target_index, target)
    between_test_path(absent)
  }
  for index in [0, 1] {
    let same = between_test_report(data, index, index)
    assert_true(same.status is BetweenPathFound)
    assert_eq(same.path_nodes.length(), 1)
    assert_eq(same.hop_count, Some(0))
    between_test_path(same)
  }
}

///|
test "function-path-between: reconstruction failures and module diagnostics" {
  let data = dependencies_test_fixture()
  let closure = function_dependencies(data, 1).unwrap()
  let reconstruct = fn(nodes, edges) {
    between_reconstruct(closure.target, closure.function_count, nodes, edges, 4)
  }
  // Node4 is at position4 in the prepared closure [1,2,3,0,4].
  let original = closure.nodes[4]
  for
    entry in [
      FunctionDependencyNode::{
        node: original.node,
        depth: 2,
        predecessor: None,
      },
      FunctionDependencyNode::{
        node: original.node,
        depth: 2,
        predecessor: Some({ caller: 2, callee: 3, kind: Direct, offset: 84, }),
      },
      FunctionDependencyNode::{
        node: original.node,
        depth: 1,
        predecessor: original.predecessor,
      },
      FunctionDependencyNode::{
        node: original.node,
        depth: 2,
        predecessor: Some({ caller: 2, callee: 4, kind: Direct, offset: 85, }),
      },
      FunctionDependencyNode::{
        node: original.node,
        depth: 5,
        predecessor: original.predecessor,
      },
    ] {
    let nodes = closure.nodes.map(fn(n) { n })
    nodes[4] = entry
    assert_true(
      reconstruct(nodes, closure.edges)
      is Err(InvalidBetweenEvidence(_, _, _, _)),
    )
  }
  // Real edge tuple but absent caller: cannot walk back to source.
  let nodes = closure.nodes.filter(fn(n) { n.node.index != 2 })
  assert_true(
    reconstruct(nodes, closure.edges)
    is Err(InvalidBetweenEvidence(Some(2), Some(4), Some(84), _)),
  )
  // A cycle in a corrupted predecessor chain is rejected, never partly returned.
  let cycle_nodes = closure.nodes.map(fn(n) { n })
  cycle_nodes[1] = {
    node: closure.nodes[1].node,
    depth: 1,
    predecessor: Some({ caller: 4, callee: 2, kind: Direct, offset: 84, }),
  }
  assert_true(
    reconstruct(
      cycle_nodes,
      closure.edges + [{ caller: 4, callee: 2, kind: Direct, offset: 84, }],
    )
    is Err(InvalidBetweenEvidence(_, _, _, _)),
  )
  let bad_source = closure.nodes.map(fn(n) { n })
  bad_source[0] = {
    node: closure.nodes[0].node,
    depth: 0,
    predecessor: Some({ caller: 1, callee: 1, kind: Direct, offset: 79, }),
  }
  assert_true(
    reconstruct(bad_source, closure.edges)
    is Err(InvalidBetweenEvidence(None, None, None, _)),
  )
  assert_true(
    reconstruct(
      closure.nodes.filter(fn(n) { n.node.index != 1 }),
      closure.edges,
    )
    is Err(InvalidBetweenEvidence(None, None, None, _)),
  )
  for index in [-1, 7, 2147483647] {
    assert_true(
      function_path_between(data, 1, index) is Err(InvalidBetweenTarget(_, 7)),
    )
    assert_true(
      function_path_between(data, index, 1)
      is Err(BetweenDependenciesError(InvalidDependenciesTarget(_, 7))),
    )
  }
  assert_true(
    function_path_between(b"bad", 1, 4)
    is Err(BetweenDependenciesError(DependenciesInputError(_))),
  )
  assert_true(
    function_path_between(b"\x00asm\x01\x00\x00\x00", 0, 0)
    is Err(BetweenDependenciesError(InvalidDependenciesTarget(0, 0))),
  )
  for pair in [(1, 4), (0, 1), (1, 1)] {
    let (source, target) = pair
    let gap = between_test_report(
      dependencies_test_fixture(gap=true),
      source,
      target,
    )
    assert_true(!gap.graph_complete)
    assert_eq(gap.unresolved_count, 0)
    assert_eq((gap.diagnostics[0].caller, gap.diagnostics[0].offset), (6, 108))
    assert_eq(gap.diagnostics[0].opcode.name(), "call_ref")
    assert_true(!gap.path_nodes.any(fn(n) { n.index == 6 }))
    between_test_path(gap)
  }
  let text = describe_function_path_between_error(
    InvalidBetweenEvidence(None, None, None, "broken chain"),
  )
  assert_true(
    text.contains("no edge position available") && !text.contains("offset 0"),
  )
  assert_true(
    describe_function_path_between_error(
      InvalidBetweenEvidence(Some(2), Some(4), Some(84), "broken edge"),
    ).contains("2 -> 4 at file offset 84"),
  )
}

///|
test "function-path-between: CLI contracts rendering null and zero" {
  assert_eq(Options::default("x").path_between, None)
  assert_eq(Options::default("x").path_between_json, None)
  let args = [
    "moonsize", "--path-between", "1", "4", "--path-between-json", "new.json", "--strict",
    "--", "--help",
  ]
  assert_true(help_request(args) is Ok(None))
  let options = parse_options(args).unwrap()
  assert_eq(options.path_between, Some((1, 4)))
  assert_eq(options.path_between_json, Some("new.json"))
  assert_true(options.strict && options.path == "--help")
  for
    tail in [
      ["--path-between"],
      ["--path-between", "1"],
      ["--path-between", "-1", "4"],
      ["--path-between", "1", "0x4"],
      ["--path-between", "1", "2147483648"],
      ["--path-between-json", "x.json"],
      ["--path-between", "1", "4", "--path-between-json"],
      ["--path-between", "1", "4", "--path-between-json", " "],
      ["--path-between", "1", "4", "--path-between-json", "x.txt"],
    ] {
    assert_true(parse_options(["moonsize", "missing.wasm"] + tail) is Err(_))
  }
  for
    tail in [
      ["--top", "20"],
      ["--baseline", "b"],
      ["--html", "x.html"],
      ["--retained"],
      ["--dependencies", "1"],
      ["--dependents", "4"],
      ["--cycles"],
      ["--why-index", "4"],
      ["--callers", "4"],
      ["--budget", "b.json"],
      ["--max-size", "1KB"],
      ["--compress"],
    ] {
    assert_true(
      parse_options(
        ["moonsize", "missing.wasm", "--path-between", "1", "4"] + tail,
      )
      is Err(_),
    )
  }
  assert_true(help_request(["moonsize", "--help"]) is Ok(Some(_)))
  let data = dependencies_test_fixture()
  let found = between_test_report(data, 1, 4)
  let text = render_function_path_between(found)
  assert_true(
    text.contains("FUNCTION-TO-FUNCTION MODEL PATH") &&
    text.contains("Query: 1 -> 4"),
  )
  assert_true(text.contains("shared\\n\\u001b雪") && text.contains("Hops: 2"))
  assert_true(
    text.contains("1  2  direct  67") && text.contains("2  4  direct  84"),
  )
  let root = match @json.parse(render_function_path_between_json(found)) {
    Object(fields) => fields
    _ => fail("object")
  }
  assert_eq(
    root.get("format"),
    Some(Json::string("moonsize-function-path-between")),
  )
  assert_eq(root.get("hop_count"), Some(int_json(2)))
  let rows = match root.get("path_nodes") {
    Some(Array(rows)) => rows
    _ => fail("nodes")
  }
  assert_eq(rows.length(), 3)
  let absent = between_test_report(data, 0, 1)
  let absent_json = render_function_path_between_json(absent)
  assert_true(
    absent_json.contains("not-found-within-model") &&
    absent_json.contains("\"hop_count\": null"),
  )
  assert_true(!absent_json.contains("\"target\":")) // no invented destination identity
  assert_true(
    render_function_path_between(absent).contains(
      "No path recorded in this direction within the current model.",
    ),
  )
  let zero = between_test_report(data, 0, 0)
  let zero_json = render_function_path_between_json(zero)
  assert_true(
    zero_json.contains("\"hop_count\": 0") &&
    zero_json.contains("\"encoded_size\": null"),
  )
  assert_true(render_function_path_between(zero).contains("Zero-step path"))
  let reference = render_function_path_between(between_test_report(data, 1, 3))
  assert_true(reference.contains("reference taken"))
}
