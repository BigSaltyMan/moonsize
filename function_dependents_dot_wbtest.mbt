///|
test "dependents-dot: complete incoming evidence original direction and copies" {
  let data = dependencies_test_fixture()
  let r = dependents_test_report(data, 2)
  r.nodes.sort_by(fn(a, b) { b.node.index - a.node.index })
  r.edges.sort_by(fn(a, b) { b.offset - a.offset })
  let before = render_function_dependents_json(r)
  let dot = render_function_dependents_dot(r)
  assert_eq(render_function_dependents_json(r), before)
  assert_eq(dot, render_function_dependents_dot(r))
  let nodes = dot
    .split("\n")
    .filter(fn(s) { s.has_prefix("  fn_") && !s.contains(" -> ") })
    .collect()
  let edges = dot
    .split("\n")
    .filter(fn(s) { s.has_prefix("  fn_") && s.contains(" -> ") })
    .collect()
  assert_eq(nodes.length(), 4)
  for i in 0..<4 {
    let index = i + 1
    assert_true(nodes[i].has_prefix("  fn_\{index} ["))
  }
  assert_true(
    nodes[0].contains("depth to target 1") && nodes[0].contains("17 B"),
  )
  assert_true(
    nodes[1].contains("depth to target 0") && nodes[1].contains("query target"),
  )
  assert_true(
    nodes[2].contains("depth to target 1") &&
    nodes[3].contains("depth to target 2"),
  )
  assert_eq(edges, [
    "  fn_1 -> fn_2 [style=solid, label=\"direct; file offset 67\"];", "  fn_1 -> fn_2 [style=solid, label=\"direct; file offset 69\"];",
    "  fn_1 -> fn_3 [style=dashed, label=\"reference; file offset 71\"];", "  fn_1 -> fn_3 [style=dotted, label=\"indirect candidate; file offset 76\"];",
    "  fn_1 -> fn_1 [style=solid, label=\"direct; file offset 79\"];", "  fn_2 -> fn_4 [style=solid, label=\"direct; file offset 84\"];",
    "  fn_3 -> fn_4 [style=solid, label=\"direct; file offset 91\"];", "  fn_3 -> fn_2 [style=solid, label=\"direct; file offset 93\"];",
    "  fn_4 -> fn_1 [style=solid, label=\"direct; file offset 98\"];",
  ])
  assert_eq(r.dependent_function_count, 3)
  assert_true(edges.length() > r.dependent_function_count)
  assert_eq(data[86], b'\x10') // real 2 -> 0 outside this reverse closure
  assert_true(!dot.contains("  fn_0 [") && !dot.contains("fn_2 -> fn_0"))
  assert_true(
    dot.has_prefix("digraph moonsize_dependents") && dot.contains("rankdir=LR"),
  )
  assert_true(
    !dot.contains("dir=back") &&
    !dot.contains("strict digraph") &&
    !dot.contains("concentrate="),
  )
  let imported = render_function_dependents_dot(dependents_test_report(data, 0))
  assert_true(
    imported.contains(
      "fn_0 [shape=ellipse, label=\"#0: m.f\\nimported; encoded size not measured\\ndepth to target 0\\nquery target\"",
    ),
  )
  let single = render_function_dependents_dot(dependents_test_report(data, 5))
  assert_true(single.contains("nodes 1; edges 0"))
  assert_true(
    !single
    .split("\n")
    .any(fn(s) { s.has_prefix("  fn_") && s.contains(" -> ") }),
  )
  assert_true(
    single.contains("depth to target 0") && single.contains("query target"),
  )
}

///|
test "dependents-dot: safe names and whole module gap remain visible" {
  let r = dependents_test_report(dependencies_test_fixture(gap=true), 2)
  // Query order is depth/index, so find by identity rather than assuming index slots.
  let mut position = -1
  for n in 0..<r.nodes.length() {
    if r.nodes[n].node.index == 3 {
      position = n
    }
  }
  assert_true(position >= 0)
  let entry = r.nodes[position]
  r.nodes[position] = {
    ..entry,
    node: {
      ..entry.node,
      name: "雪\"\\N\\n\n\t\u001b\"]; injected -> fn_99; //",
    },
  }
  let dot = render_function_dependents_dot(r)
  assert_true(
    dot.contains(
      "  fn_3 [shape=box, label=\"#3: 雪\\\"\\\\N\\\\n\\\\u000a\\\\u0009\\\\u001b\\\"]; injected -> fn_99; //\\nlocal; encoded size 7 B\\ndepth to target 1\"];",
    ),
  )
  for ch in dot.iter() {
    let code = ch.to_int()
    assert_true(code == 10 || code >= 32)
  }
  assert_true(
    !r.graph_complete && r.unresolved_count == 0 && r.diagnostics.length() == 1,
  )
  assert_eq((r.diagnostics[0].caller, r.diagnostics[0].offset), (6, 108))
  assert_eq(r.diagnostics[0].opcode.name(), "call_ref")
  assert_true(dot.contains("WARNING: incomplete graph; diagnostics 1"))
  assert_true(
    dot.contains("function 6, offset 108: call_ref") &&
    !dot.contains("  fn_6 ["),
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
  assert_true(
    dot.contains("input_sha256=\"" + r.sha256 + "\"") &&
    dot.contains("target_index=\"2\""),
  )
  let imported = render_function_dependents_dot(
    dependents_test_report(dependencies_test_fixture(gap=true), 0),
  )
  assert_true(
    imported.contains("not measured") &&
    !imported.contains("imported; encoded size 0 B"),
  )
}

///|
test "dependents-dot: parameters help and prior output routing" {
  assert_eq(Options::default("x").dependents_dot, None)
  let args = [
    "moonsize", "--dependents", "2", "--dependents-dot", "new.dot", "--top", "1",
    "--strict", "--", "--help",
  ]
  assert_true(help_request(args) is Ok(None))
  let options = parse_options(args).unwrap()
  assert_true(options.path == "--help" && options.strict && options.top == 1)
  assert_eq(options.dependents, Some(2))
  assert_eq(options.dependents_dot, Some("new.dot"))
  for
    tail in [
      ["--dependents-dot", "new.dot"],
      ["--dependents", "2", "--dependents-dot"],
      ["--dependents", "2", "--dependents-dot", ""],
      ["--dependents", "2", "--dependents-dot", " "],
      ["--dependents", "2", "--dependents-dot", "new.json"],
      ["--dependents", "2", "--dependents-dot", "--help"],
      [
        "--dependents", "2", "--dependents-dot", "new.dot", "--dependents-json",
        "new.json",
      ],
    ] {
    assert_true(parse_options(["moonsize", "missing"] + tail) is Err(_))
  }
  for
    tail in [
      ["--dependencies", "1"],
      ["--path-between", "1", "2"],
      ["--baseline", "x"],
      ["--html", "x.html"],
      ["--call-graph", "x.dot"],
      ["--retained"],
      ["--budget", "x.json"],
    ] {
    assert_true(
      parse_options(
        [
          "moonsize", "missing", "--dependents", "2", "--dependents-dot", "new.dot",
        ] +
        tail,
      )
      is Err(_),
    )
  }
  let text = parse_options(["moonsize", "x", "--dependents", "2"]).unwrap()
  assert_true(text.dependents_dot is None && text.dependents_json is None)
  let json = parse_options([
    "moonsize", "x", "--dependents", "2", "--dependents-json", "new.json",
  ]).unwrap()
  assert_true(
    json.dependents_dot is None && json.dependents_json == Some("new.json"),
  )
  assert_true(
    help_request(["moonsize", "--help"])
    .unwrap()
    .unwrap()
    .contains("--dependents-dot"),
  )
  assert_true(
    help_request(["moonsize", "--help-topic", "functions"])
    .unwrap()
    .unwrap()
    .contains("--dependents-dot"),
  )
}
