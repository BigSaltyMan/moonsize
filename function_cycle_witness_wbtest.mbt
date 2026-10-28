///|
fn witness_test_component(
  indices : Array[Int],
  edges : Array[CallEdge],
) -> FunctionCycleComponent {
  let mut direct = 0
  let mut reference = 0
  let mut indirect = 0
  for edge in edges {
    match edge.kind {
      Direct => direct += 1
      Reference => reference += 1
      Indirect => indirect += 1
    }
  }
  {
    component_id: if indices.is_empty() {
      0
    } else {
      indices[0]
    },
    members: indices.map(fn(index) {
      {
        index,
        name: if index == 20 {
          "bad\n\u001b雪"
        } else {
          "n\{index}"
        },
        raw_name: None,
        imported: false,
        encoded_size: Some(3),
        import_module: None,
        import_name: None,
      }
    }),
    internal_edges: edges,
    node_count: indices.length(),
    internal_edge_count: edges.length(),
    direct_edges: direct,
    reference_edges: reference,
    indirect_edges: indirect,
    local_encoded_bytes: indices.length() * 3,
  }
}

///|
fn witness_test_edges() -> Array[CallEdge] {
  [
    { caller: 10, callee: 20, kind: Indirect, offset: 90, },
    { caller: 10, callee: 20, kind: Direct, offset: 99, },
    { caller: 10, callee: 40, kind: Direct, offset: 1, }, // shorter global cycle, not the selected successor
    { caller: 20, callee: 30, kind: Indirect, offset: 50, },
    { caller: 20, callee: 40, kind: Direct, offset: 2, },
    { caller: 30, callee: 10, kind: Reference, offset: 60, },
    { caller: 40, callee: 10, kind: Direct, offset: 3, },
  ]
}

///|
fn witness_test_signature(
  witness : FunctionCycleWitness,
) -> Array[(Int, Int, Int, Int)] {
  witness.edges.map(fn(e) {
    (e.caller, e.callee, path_edge_rank(e.kind), e.offset)
  })
}

///|
fn witness_test_check(
  component : FunctionCycleComponent,
  witness : FunctionCycleWitness,
) -> Unit raise {
  assert_eq(witness.component_id, component.component_id)
  assert_eq(witness.start_index, component.component_id)
  assert_eq(witness.edge_count, witness.edges.length())
  assert_true(witness.edge_count >= 1)
  assert_eq(witness.nodes.length(), witness.edge_count + 1)
  assert_eq(witness.nodes[0], witness.start_index)
  assert_eq(witness.nodes[witness.nodes.length() - 1], witness.start_index)
  assert_eq(
    witness.edge_count,
    witness.direct_edges + witness.reference_edges + witness.indirect_edges,
  )
  let seen : Set[Int] = Set([])
  for i, edge in witness.edges {
    assert_eq(edge.caller, witness.nodes[i])
    assert_eq(edge.callee, witness.nodes[i + 1])
    assert_true(component.members.any(fn(n) { n.index == edge.caller }))
    assert_true(component.members.any(fn(n) { n.index == edge.callee }))
    assert_true(
      component.internal_edges.any(fn(e) {
        e.caller == edge.caller &&
        e.callee == edge.callee &&
        path_edge_rank(e.kind) == path_edge_rank(edge.kind) &&
        e.offset == edge.offset
      }),
    )
    assert_true(!seen.contains(edge.caller))
    seen.add(edge.caller)
  }
}

///|
test "cycle-witness: path facts priority and original evidence" {
  let component = witness_test_component([10, 20, 30, 40], witness_test_edges())
  let witness = cycle_component_witness(component).unwrap()
  assert_eq(witness.nodes, [10, 20, 30, 10]) // callee then kind; BFS tie uses smaller callee
  assert_eq(witness_test_signature(witness), [
    (10, 20, 0, 99),
    (20, 30, 2, 50),
    (30, 10, 1, 60),
  ])
  assert_eq(
    (witness.direct_edges, witness.reference_edges, witness.indirect_edges),
    (1, 1, 1),
  )
  witness_test_check(component, witness)
  let self_component = witness_test_component(
    [10, 20, 30, 40],
    witness_test_edges() +
    [
      { caller: 10, callee: 10, kind: Indirect, offset: 0, },
      { caller: 10, callee: 10, kind: Reference, offset: 10, },
      { caller: 10, callee: 10, kind: Direct, offset: 80, },
      { caller: 10, callee: 10, kind: Direct, offset: 50, },
    ],
  )
  let self_witness = cycle_component_witness(self_component).unwrap()
  assert_eq(self_witness.nodes, [10, 10])
  assert_eq(witness_test_signature(self_witness), [(10, 10, 0, 50)])
  assert_eq(self_component.internal_edge_count, 11)
  assert_eq(self_component.node_count, 4)
  witness_test_check(self_component, self_witness)
  let report = function_cycle_witnesses(cycles_test_fixture()).unwrap()
  assert_eq(report.witnesses.map(fn(w) { w.nodes }), [[2, 3, 2], [1, 1], [6, 6]])
  assert_eq(report.witnesses.map(fn(w) { w.edge_count }), [2, 1, 1])
  assert_eq(report.cycles.components.map(fn(c) { c.internal_edge_count }), [
    3, 2, 1,
  ])
  for i, w in report.witnesses {
    witness_test_check(report.cycles.components[i], w)
  }
}

///|
test "cycle-witness: determinism boundaries query errors and diagnostics" {
  let edges = witness_test_edges()
  let before = cycle_component_witness(
    witness_test_component([10, 20, 30, 40], edges),
  ).unwrap()
  let after = cycle_component_witness(
    witness_test_component([10, 20, 30, 40], [
      edges[6],
      edges[5],
      edges[4],
      edges[3],
      edges[2],
      edges[1],
      edges[0],
    ]),
  ).unwrap()
  assert_eq(witness_test_signature(before), witness_test_signature(after))
  let sparse = witness_test_component([1000000, 2000000], [
    { caller: 1000000, callee: 2000000, kind: Direct, offset: 1, },
    { caller: 2000000, callee: 1000000, kind: Reference, offset: 2, },
  ])
  assert_eq(cycle_component_witness(sparse).unwrap().nodes, [
    1000000, 2000000, 1000000,
  ])
  for
    component in [
      witness_test_component([], []),
      witness_test_component([-1], []),
      witness_test_component([10, 10], []),
      witness_test_component([20, 10], []),
      witness_test_component([10, 20], [
        { caller: 10, callee: 99, kind: Direct, offset: 42, },
      ]),
      witness_test_component([10, 20], [
        { caller: 10, callee: 20, kind: Direct, offset: 42, },
      ]),
      witness_test_component([10], [
        { caller: 10, callee: 10, kind: Direct, offset: -1, },
      ]),
    ] {
    assert_true(
      cycle_component_witness(component) is Err(InvalidCycleWitness(_, _, _)),
    )
  }
  let cross = cycle_component_witness(
    witness_test_component([10, 20], [
      { caller: 10, callee: 99, kind: Direct, offset: 42, },
    ]),
  )
  assert_true(cross is Err(InvalidCycleWitness(10, Some(42), _)))
  let empty = function_cycle_witnesses(b"\x00asm\x01\x00\x00\x00").unwrap()
  assert_eq(empty.witnesses.length(), 0)
  assert_eq(empty.cycles.component_count, 0)
  assert_true(
    function_cycle_witnesses(b"bad")
    is Err(CycleWitnessQueryError(CyclesInputError(_))),
  )
  let data = cycles_test_fixture(gap=true)
  let report = function_cycle_witnesses(data).unwrap()
  assert_eq(
    render_function_cycles_json(report.cycles),
    render_function_cycles_json(function_cycles(data).unwrap()),
  )
  assert_true(!report.cycles.graph_complete)
  assert_eq(report.cycles.unresolved_count, 0)
  assert_eq(report.cycles.diagnostics.length(), 1)
  assert_eq(report.cycles.diagnostics[0].caller, 7)
  assert_eq(report.cycles.diagnostics[0].offset, 108)
  assert_true(
    render_function_cycle_witnesses_json(report).contains(
      "unmodeled_reference_call",
    ),
  )
  for
    error in [
      CycleWitnessQueryError(CyclesInputError(BadMagic)),
      InvalidCycleWitness(10, Some(42), "crossed boundary"),
      InvalidCycleWitness(10, None, "missing root"),
    ] {
    assert_true(!describe_function_cycle_witness_error(error).is_empty())
  }
}

///|
test "cycle-witness: modifier rendering full JSON and default contract" {
  assert_true(!Options::default("x").cycle_witness)
  let args = [
    "moonsize", "--cycle-witness", "--cycles-json", "new.json", "--top", "1", "--strict",
    "--", "--help",
  ]
  assert_true(help_request(args) is Ok(None))
  let options = parse_options(args).unwrap()
  assert_true(options.cycles && options.cycle_witness && options.strict)
  assert_eq(options.cycles_json, Some("new.json"))
  assert_eq(options.path, "--help")
  assert_eq(options.top, 1)
  for
    tail in [
      ["--cycle-witness"],
      ["--cycle-witness", "--strict"],
      ["--cycle-witness", "--cycles-json", "x.txt"],
      ["--cycle-witness", "--cycles", "--html", "x.html"],
      ["--cycle-witness", "--cycles", "--baseline", "b"],
      ["--cycle-witness", "--cycles", "--locate-decode"],
      ["--cycle-witness", "--cycles", "--find-data", "a"],
    ] {
    assert_true(parse_options(["moonsize", "missing.wasm"] + tail) is Err(_))
  }
  assert_true(
    !parse_options(["moonsize", "x", "--cycles"]).unwrap().cycle_witness,
  )
  assert_true(help_request(["moonsize", "--help"]) is Ok(Some(_)))
  let report = function_cycle_witnesses(cycles_test_fixture()).unwrap()
  let text = render_function_cycle_witnesses(report, 1)
  assert_true(text.contains("CLOSED MODEL WITNESS"))
  assert_true(text.contains("Component #2: 2 -> 3 -> 2"))
  assert_true(
    text.contains("file offset 76") && text.contains("file offset 87"),
  )
  assert_true(!text.contains("Component #1:"))
  assert_true(text.contains("pair\\n\\u001b雪"))
  let root = match @json.parse(render_function_cycle_witnesses_json(report)) {
    Object(fields) => fields
    _ => fail("object")
  }
  assert_eq(
    root.get("format"),
    Some(Json::string("moonsize-function-cycle-witnesses")),
  )
  let cycles = match root.get("cycles") {
    Some(Object(fields)) => fields
    _ => fail("nested object")
  }
  assert_eq(
    cycles.get("format"),
    Some(Json::string("moonsize-function-cycles")),
  )
  let rows = match root.get("witnesses") {
    Some(Array(rows)) => rows
    _ => fail("full array")
  }
  assert_eq(rows.length(), report.cycles.component_count)
  assert_eq(rows.length(), 3)
  let component = witness_test_component([10, 20, 30, 40], witness_test_edges())
  let witness = cycle_component_witness(component).unwrap()
  let base = FunctionCyclesReport::{
    file_size: 100,
    sha256: "render-boundary",
    function_count: 4,
    imported_function_count: 0,
    local_function_count: 4,
    cyclic_function_count: 4,
    non_cyclic_function_count: 0,
    component_count: 1,
    components: [component],
    local_encoded_bytes: 12,
    cyclic_local_encoded_bytes: 12,
    other_local_encoded_bytes: 0,
    graph_complete: true,
    unresolved_count: 0,
    diagnostics: [],
    graph_warning: "",
    modeling_scope: "render-boundary",
  }
  let controlled = FunctionCycleWitnessReport::{
    cycles: base,
    witnesses: [witness],
    scope: cycle_witness_scope(),
  }
  let controlled_text = render_function_cycle_witnesses(controlled, 1)
  assert_true(controlled_text.contains("indirect candidate"))
  assert_true(controlled_text.contains("10 -> 20 -> 30 -> 10"))
  assert_true(controlled_text.contains("bad\\n\\u001b雪"))
  assert_true(
    render_function_cycle_witnesses_json(controlled).contains(
      "\"candidate\": true",
    ),
  )
  assert_true(
    !render_function_cycles_json(report.cycles).contains("\"witnesses\""),
  )
  assert_true(
    render_function_cycles_json(report.cycles).contains(
      "\"format\": \"moonsize-function-cycles\"",
    ),
  )
}
