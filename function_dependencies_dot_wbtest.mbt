///|
test "dependencies-dot: complete graph evidence and immutable ordering" {
  let r = dependencies_test_report(overlap_test_fixture(), 1)
  r.nodes.sort_by(fn(a, b) { b.node.index - a.node.index })
  r.edges.sort_by(fn(a, b) { b.offset - a.offset })
  let before = render_function_dependencies_json(r)
  let dot = render_function_dependencies_dot(r)
  assert_eq(render_function_dependencies_json(r), before)
  assert_eq(dot, render_function_dependencies_dot(r))
  let nodes = dot
    .split("\n")
    .filter(fn(s) { s.has_prefix("  fn_") && !s.contains(" -> ") })
    .collect()
  let edges = dot.split("\n").filter(fn(s) { s.contains(" -> ") }).collect()
  assert_eq(nodes.length(), 4)
  let indices = [0, 1, 3, 4]
  for i in 0..<indices.length() {
    let index = indices[i]
    assert_true(nodes[i].has_prefix("  fn_\{index} ["))
  }
  assert_eq(edges, [
    "  fn_1 -> fn_3 [style=solid, label=\"direct; file offset 68\"];", "  fn_1 -> fn_3 [style=solid, label=\"direct; file offset 70\"];",
    "  fn_1 -> fn_4 [style=dashed, label=\"reference; file offset 72\"];", "  fn_1 -> fn_4 [style=dotted, label=\"indirect candidate; file offset 77\"];",
    "  fn_1 -> fn_1 [style=solid, label=\"direct; file offset 80\"];", "  fn_3 -> fn_4 [style=solid, label=\"direct; file offset 92\"];",
    "  fn_3 -> fn_0 [style=solid, label=\"direct; file offset 94\"];", "  fn_4 -> fn_3 [style=solid, label=\"direct; file offset 99\"];",
  ])
  assert_true(edges.length() > r.dependency_function_count)
  assert_true(
    nodes[0].contains("shape=ellipse") && nodes[0].contains("not measured"),
  )
  assert_true(
    nodes[1].contains("query target") &&
    nodes[1].contains("BFS depth 0") &&
    nodes[1].contains("17 B"),
  )
  assert_true(dot.has_prefix("digraph ") && dot.contains("rankdir=LR"))
  assert_true(!dot.contains("strict digraph") && !dot.contains("concentrate="))
  for index in [0, 5] {
    let single = render_function_dependencies_dot(
      dependencies_test_report(overlap_test_fixture(), index),
    )
    assert_true(single.contains("nodes 1; edges 0") && !single.contains(" -> "))
    assert_true(single.contains("query target"))
  }
}

///|
test "dependencies-dot: exact escaping and full module diagnostics" {
  let hostile = "雪\"\\N\\G\\E\\n\\l\\r\n\r\t\u001b\u0000\u007f\u0085\u2028\"]; evil -> fn_0; //"
  let expected = "\"雪\\\"\\\\N\\\\G\\\\E\\\\n\\\\l\\\\r\\\\u000a\\\\u000d\\\\u0009\\\\u001b\\\\u0000\\\\u007f\\\\u0085\\\\u2028\\\"]; evil -> fn_0; //\""
  assert_eq(dependencies_dot_quote(hostile), expected)
  assert_eq(
    dependencies_dot_label(["one\ntwo", "\\n"]),
    "\"one\\\\u000atwo\\n\\\\n\"",
  )
  let r = dependencies_test_report(overlap_test_fixture(gap=true), 1)
  let entry = r.nodes[0]
  r.nodes[0] = { ..entry, node: { ..entry.node, name: hostile, }, }
  let dot = render_function_dependencies_dot(r)
  assert_true(
    dot.contains(
      dependencies_dot_label([
        "#1: " + hostile,
        "local; encoded size 17 B",
        "BFS depth 0",
        "query target",
      ]),
    ),
  )
  for ch in dot.iter() {
    let n = ch.to_int()
    assert_true(n == 10 || (n >= 32 && !(n >= 127 && n <= 159) && n != 0x2028))
  }
  assert_true(dot.contains("WARNING: incomplete graph; diagnostics 1"))
  assert_true(
    dot.contains("graph_complete=\"false\"") &&
    dot.contains("unresolved_count=\"0\""),
  )
  assert_true(
    dot.contains(
      "diagnostics_json=" +
      dependencies_dot_quote(diagnostic_records_json(r.diagnostics).stringify()),
    ),
  )
  assert_true(
    dot.contains("graph_warning=" + dependencies_dot_quote(r.graph_warning)),
  )
  assert_true(dot.contains("input_sha256=\"" + r.sha256 + "\""))
  assert_true(
    dot.contains("call_ref") && dot.contains("109") && !dot.contains("  fn_6 ["),
  )
  assert_true(
    dot.contains("imported; encoded size not measured") &&
    !dot.contains("imported; encoded size 0 B"),
  )
}

///|
test "dependencies-dot: parameters and old routing compatibility" {
  assert_eq(Options::default("x").dependencies_dot, None)
  let args = [
    "moonsize", "--dependencies", "1", "--dependencies-dot", "new.dot", "--strict",
    "--top", "1", "--", "--help",
  ]
  assert_true(help_request(args) is Ok(None))
  let o = parse_options(args).unwrap()
  assert_eq(o.dependencies_dot, Some("new.dot"))
  assert_true(
    o.strict && o.top == 1 && o.path == "--help" && o.dependencies == Some(1),
  )
  for
    tail in [
      ["--dependencies-dot", "x.dot"],
      ["--dependencies", "1", "--dependencies-dot"],
      ["--dependencies", "1", "--dependencies-dot", ""],
      ["--dependencies", "1", "--dependencies-dot", " "],
      ["--dependencies", "1", "--dependencies-dot", "x.json"],
      ["--dependencies", "1", "--dependencies-dot", "--help"],
      [
        "--dependencies", "1", "--dependencies-dot", "x.dot", "--dependencies-json",
        "x.json",
      ],
    ] {
    assert_true(parse_options(["moonsize", "x"] + tail) is Err(_))
  }
  for
    tail in [
      ["--html", "x.html"],
      ["--call-graph", "x.dot"],
      ["--baseline", "x"],
      ["--retained"],
      ["--path-between", "1", "2"],
      ["--compare-dependencies", "1", "2"],
      ["--dependents", "1"],
    ] {
    assert_true(
      parse_options(
        ["moonsize", "x", "--dependencies", "1", "--dependencies-dot", "x.dot"] +
        tail,
      )
      is Err(_),
    )
  }
  let text = parse_options(["moonsize", "x", "--dependencies", "1"]).unwrap()
  assert_true(text.dependencies_dot is None && text.dependencies_json is None)
  let json = parse_options([
    "moonsize", "x", "--dependencies", "1", "--dependencies-json", "x.json",
  ]).unwrap()
  assert_true(
    json.dependencies_dot is None && json.dependencies_json == Some("x.json"),
  )
  assert_true(
    help_request(["moonsize", "--help"])
    .unwrap()
    .unwrap()
    .contains("--dependencies-dot"),
  )
  assert_true(
    help_request(["moonsize", "--help-topic", "functions"])
    .unwrap()
    .unwrap()
    .contains("--dependencies-dot"),
  )
}
