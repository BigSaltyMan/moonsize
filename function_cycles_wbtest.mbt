///|
fn cycles_test_fixture(gap? : Bool = false) -> Bytes {
  let bodies = [
    b"\x00\x10\x01\x10\x01\x0b", // 1: direct self, two locations
    b"\x00\xd2\x03\x1a\x41\x00\x11\x00\x00\x0b", // 2: reference/indirect -> 3
    b"\x00\x10\x02\x0b", // 3 -> 2
    b"\x00\x10\x05\x0b", // 4 -> 5, no return edge
    b"\x00\x0b", // 5
    b"\x00\xd2\x06\x1a\x0b", // 6: reference self
    if gap {
      b"\x00\xd2\x00\x14\x00\x0b"
    } else {
      b"\x00\x0b"
    }, // 7: no guessed call_ref edge
  ]
  let mut code = search_test_leb(bodies.length())
  for body in bodies {
    code = code + search_test_leb(body.length()) + body
  }
  let name = @utf8.encode("pair\n\u001b雪")
  b"\x00asm\x01\x00\x00\x00" +
  search_test_section(1, b"\x01\x60\x00\x00") +
  search_test_section(2, b"\x01\x01m\x01f\x00\x00") +
  search_test_section(3, b"\x07\x00\x00\x00\x00\x00\x00\x00") +
  search_test_section(4, b"\x01\x70\x00\x01") +
  search_test_section(7, b"\x01\x05entry\x00\x04") +
  search_test_section(9, b"\x02\x00\x41\x00\x0b\x01\x03\x03\x00\x02\x06\x00") +
  search_test_section(10, code) +
  search_test_section(
    0,
    b"\x04name" +
    search_test_section(1, b"\x01\x02" + search_test_leb(name.length()) + name),
  )
}

///|
fn cycles_test_report(data : Bytes) -> FunctionCyclesReport raise {
  match function_cycles(data) {
    Ok(report) => report
    Err(error) => fail(describe_function_cycles_error(error))
  }
}

///|
fn cycles_test_nodes() -> Array[FunctionPathNode] {
  Array::makei(8, fn(index) {
    {
      index,
      name: "f\{index}",
      raw_name: None,
      imported: index == 0,
      encoded_size: if index == 0 {
        None
      } else {
        Some(3)
      },
      import_module: None,
      import_name: None,
    }
  })
}

///|
fn cycles_test_ledger(report : FunctionCyclesReport) -> Unit raise {
  assert_eq(
    report.function_count,
    report.imported_function_count + report.local_function_count,
  )
  assert_eq(
    report.function_count,
    report.cyclic_function_count + report.non_cyclic_function_count,
  )
  assert_eq(
    report.local_encoded_bytes,
    report.cyclic_local_encoded_bytes + report.other_local_encoded_bytes,
  )
  let seen : Set[Int] = Set([])
  let mut size = 0
  let mut count = 0
  for component in report.components {
    assert_eq(component.component_id, component.members[0].index)
    assert_eq(component.node_count, component.members.length())
    assert_eq(component.internal_edge_count, component.internal_edges.length())
    assert_eq(
      component.internal_edge_count,
      component.direct_edges +
      component.reference_edges +
      component.indirect_edges,
    )
    let members : Set[Int] = Set([])
    let mut member_size = 0
    for node in component.members {
      assert_true(!seen.contains(node.index))
      seen.add(node.index)
      members.add(node.index)
      member_size += node.encoded_size.unwrap_or(0)
    }
    for edge in component.internal_edges {
      assert_true(
        members.contains(edge.caller) && members.contains(edge.callee),
      )
    }
    assert_eq(member_size, component.local_encoded_bytes)
    size += component.local_encoded_bytes
    count += component.node_count
  }
  assert_eq(count, report.cyclic_function_count)
  assert_eq(size, report.cyclic_local_encoded_bytes)
}

///|
test "function-cycles: SCC evidence and byte ledgers" {
  let nodes = cycles_test_nodes()
  let edges : Array[CallEdge] = [
    { caller: 1, callee: 1, kind: Direct, offset: 10, },
    { caller: 1, callee: 1, kind: Direct, offset: 12, },
    { caller: 2, callee: 3, kind: Reference, offset: 20, },
    { caller: 2, callee: 3, kind: Indirect, offset: 22, },
    { caller: 3, callee: 2, kind: Direct, offset: 30, },
    { caller: 4, callee: 5, kind: Direct, offset: 40, },
    { caller: 6, callee: 6, kind: Reference, offset: 50, },
  ]
  let components = cycles_components(nodes, edges, 100).unwrap()
  assert_eq(components.map(fn(c) { c.component_id }), [2, 1, 6])
  assert_eq(components.map(fn(c) { c.members.map(fn(n) { n.index }) }), [
    [2, 3],
    [1],
    [6],
  ])
  assert_eq(components.map(fn(c) { c.internal_edge_count }), [3, 2, 1])
  let data = cycles_test_fixture()
  let report = cycles_test_report(data)
  assert_eq(report.function_count, 8)
  assert_eq(report.imported_function_count, 1)
  assert_eq(report.cyclic_function_count, 4)
  assert_eq(report.non_cyclic_function_count, 4)
  assert_eq(report.local_encoded_bytes, 40)
  assert_eq(report.cyclic_local_encoded_bytes, 29)
  assert_eq(report.other_local_encoded_bytes, 11)
  assert_eq(report.components.map(fn(c) { c.component_id }), [2, 1, 6])
  assert_eq(report.components.map(fn(c) { c.local_encoded_bytes }), [16, 7, 6])
  let pair = report.components[0]
  assert_eq(
    (pair.direct_edges, pair.reference_edges, pair.indirect_edges),
    (1, 1, 1),
  )
  assert_true(report.graph_complete)
  assert_eq(report.unresolved_count, 0)
  assert_eq(report.sha256, experiment_sha256(data))
  // #1 is neither exported nor an element target, but its self-loop remains.
  for component in report.components {
    for edge in component.internal_edges {
      assert_eq(
        data[edge.offset].to_int(),
        match edge.kind {
          Direct => 0x10
          Reference => 0xd2
          Indirect => 0x11
        },
      )
    }
  }
  cycles_test_ledger(report)
}

///|
test "function-cycles: model gaps invalid evidence and stable order" {
  let empty = cycles_test_report(b"\x00asm\x01\x00\x00\x00")
  assert_eq(empty.component_count, 0)
  cycles_test_ledger(empty)
  let nodes = cycles_test_nodes()
  assert_true(nodes[0].encoded_size is None)
  assert_eq(
    cycles_components(
      nodes,
      [{ caller: 1, callee: 2, kind: Direct, offset: 10, }],
      100,
    )
    .unwrap()
    .length(),
    0,
  )
  let edges : Array[CallEdge] = [
    { caller: 1, callee: 2, kind: Direct, offset: 20, },
    { caller: 2, callee: 1, kind: Reference, offset: 30, },
    { caller: 1, callee: 2, kind: Indirect, offset: 20, },
    { caller: 1, callee: 2, kind: Reference, offset: 20, },
  ]
  let forward = cycles_components(nodes, edges, 100).unwrap()
  let backward = cycles_components(
    nodes,
    [edges[3], edges[2], edges[1], edges[0]],
    100,
  ).unwrap()
  fn signature(
    groups : Array[FunctionCycleComponent],
  ) -> Array[Array[(Int, Int, Int, Int)]] {
    groups.map(fn(c) {
      c.internal_edges.map(fn(e) {
        (e.caller, e.offset, e.callee, path_edge_rank(e.kind))
      })
    })
  }
  assert_eq(signature(forward), signature(backward))
  assert_eq(forward[0].internal_edge_count, 4)
  for
    edge in [
      { caller: 1, callee: 8, kind: Direct, offset: 10, },
      { caller: -1, callee: 1, kind: Direct, offset: 10, },
      { caller: 0, callee: 1, kind: Reference, offset: 10, },
      { caller: 1, callee: 1, kind: Direct, offset: 100, },
    ] {
    assert_true(
      cycles_components(nodes, [edge], 100)
      is Err(InvalidCyclesEvidence(_, _, _)),
    )
  }
  let gap = cycles_test_report(cycles_test_fixture(gap=true))
  assert_true(!gap.graph_complete)
  assert_eq(gap.unresolved_count, 0) // reference call is not an unresolved table site
  assert_eq(gap.diagnostics.length(), 1)
  assert_eq(gap.diagnostics[0].caller, 7)
  assert_eq(gap.diagnostics[0].opcode.name(), "call_ref")
  assert_eq(gap.components.map(fn(c) { c.component_id }), [2, 1, 6])
  assert_true(
    render_function_cycles_json(gap).contains("unmodeled_reference_call"),
  )
  assert_true(!gap.graph_warning.is_empty())
  let bad = b"\x00asm\x01\x00\x00\x00\x03\x02\x01\x00\x0a\x04\x01\x02\x00\xff"
  assert_true(function_cycles(bad) is Err(CyclesInputError(_)))
  assert_true(function_cycles(b"bad") is Err(CyclesInputError(_)))
  cycles_test_ledger(gap)
  for
    error in [
      CyclesInputError(BadMagic),
      InvalidCyclesEvidence(8, 42, "outside inventory"),
    ] {
    assert_true(!describe_function_cycles_error(error).is_empty())
  }
}

///|
test "function-cycles: parameters text JSON and strict contract" {
  assert_true(!Options::default("x").cycles)
  assert_eq(Options::default("x").cycles_json, None)
  let args = [
    "moonsize", "--cycles-json", "new.json", "--top", "1", "--strict", "--", "--help",
  ]
  assert_true(help_request(args) is Ok(None))
  let options = parse_options(args).unwrap()
  assert_true(options.cycles && options.strict)
  assert_eq(options.top, 1)
  assert_eq(options.path, "--help")
  assert_eq(options.cycles_json, Some("new.json"))
  for
    tail in [
      ["--cycles-json"],
      ["--cycles-json", ""],
      ["--cycles-json", "x.txt"],
      ["--cycles", "--strict", "--baseline", "b"],
      ["--cycles", "--html", "n.html"],
      ["--cycles", "--retained"],
      ["--cycles", "--why-index", "0"],
      ["--cycles", "--callers", "0"],
      ["--cycles", "--generics"],
      ["--cycles", "--locate-range", "0", "0"],
      ["--cycles", "--budget", "b.json"],
      ["--cycles", "--max-size", "1KB"],
      ["--cycles", "--compress"],
    ] {
    assert_true(parse_options(["moonsize", "missing.wasm"] + tail) is Err(_))
  }
  assert_true(help_request(["moonsize", "--help"]) is Ok(Some(_)))
  let report = cycles_test_report(cycles_test_fixture())
  let text = render_function_cycles(report, 1)
  assert_true(text.contains("COMPONENTS: showing 1 of 3"))
  assert_true(text.contains("Member #2") && text.contains("Member #3"))
  assert_true(!text.contains("Member #1"))
  assert_true(text.contains("pair\\n\\u001b雪"))
  assert_true(text.contains("40 = cyclic 29 + other 11"))
  let root = match @json.parse(render_function_cycles_json(report)) {
    Object(fields) => fields
    _ => fail("object")
  }
  assert_eq(root.get("format"), Some(Json::string("moonsize-function-cycles")))
  let components = match root.get("components") {
    Some(Array(rows)) => rows
    _ => fail("array")
  }
  assert_eq(components.length(), 3)
  assert_true(
    render_function_cycles_json(report).contains("\"candidate\": true"),
  )
  assert_true(
    render_function_cycles(cycles_test_report(b"\x00asm\x01\x00\x00\x00"), 1).contains(
      "No cyclic components recorded in the current reference model.",
    ),
  )
}
