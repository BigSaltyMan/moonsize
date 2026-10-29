///|
fn overlap_test_fixture(gap? : Bool = false, bad? : Bool = false) -> Bytes {
  let bodies = [
    b"\x00\x10" +
    (if bad { b"\x08" } else { b"\x03" }) +
    b"\x10\x03\xd2\x04\x1a\x41\x00\x11\x00\x00\x10\x01\x0b",
    b"\x00\x10\x03\x10\x07\x0b",
    b"\x00\x10\x04\x10\x00\x0b",
    b"\x00\x10\x03\x0b",
    b"\x00\x0b",
    if gap {
      b"\x00\xd2\x00\x14\x00\x0b"
    } else {
      b"\x00\x0b"
    },
    b"\x00\x0b",
  ]
  let mut code = search_test_leb(bodies.length())
  for body in bodies {
    code = code + search_test_leb(body.length()) + body
  }
  let name = @utf8.encode("shared\n\u001b雪")
  b"\x00asm\x01\x00\x00\x00" +
  search_test_section(1, b"\x01\x60\x00\x00") +
  search_test_section(2, b"\x01\x01m\x01f\x00\x00") +
  search_test_section(3, b"\x07\x00\x00\x00\x00\x00\x00\x00") +
  search_test_section(4, b"\x01\x70\x00\x01") +
  search_test_section(7, b"\x01\x05entry\x00\x05") +
  search_test_section(9, b"\x02\x00\x41\x00\x0b\x01\x04\x03\x00\x01\x00") +
  search_test_section(10, code) +
  search_test_section(
    0,
    b"\x04name" +
    search_test_section(1, b"\x01\x02" + search_test_leb(name.length()) + name),
  )
}

///|
fn overlap_test_report(
  data : Bytes,
  left : Int,
  right : Int,
) -> DependencyOverlapReport raise {
  match compare_function_dependencies(data, left, right) {
    Ok(report) => report
    Err(error) => fail(describe_dependency_overlap_error(error))
  }
}

///|
fn overlap_test_edges(edges : Array[CallEdge]) -> Array[(Int, Int, Int, Int)] {
  edges.map(fn(e) { (e.caller, e.callee, path_edge_rank(e.kind), e.offset) })
}

///|
fn overlap_test_ledger(r : DependencyOverlapReport) -> Unit raise {
  assert_eq(r.groups.map(fn(g) { g.kind }), [
    "shared", "left_only", "right_only", "neither",
  ])
  assert_eq(
    r.functions.map(fn(n) { n.index }),
    Array::makei(r.function_count, fn(i) { i }),
  )
  let seen : Set[Int] = Set([])
  let mut all_bytes = 0
  let mut imports = 0
  for group in r.groups {
    assert_eq(group.indices.length(), group.function_count)
    assert_eq(group.function_count, group.local_count + group.imported_count)
    let mut previous = -1
    let mut bytes = 0
    let mut imported = 0
    for index in group.indices {
      assert_true(index > previous && !seen.contains(index))
      previous = index
      seen.add(index)
      let node = r.functions[index]
      assert_eq(node.index, index)
      if node.imported {
        assert_true(node.encoded_size is None)
        imported += 1
      } else {
        bytes += node.encoded_size.unwrap()
      }
    }
    assert_eq(imported, group.imported_count)
    assert_eq(bytes, group.local_encoded_bytes)
    all_bytes += bytes
    imports += imported
  }
  assert_eq(all_bytes, r.local_encoded_bytes)
  assert_eq(imports, r.imported_function_count)
  assert_eq(
    r.function_count,
    r.local_function_count + r.imported_function_count,
  )
  for i in 0..<r.function_count {
    assert_true(seen.contains(i))
  }
  let s = r.groups[0]
  let l = r.groups[1]
  let b = r.groups[2]
  let n = r.groups[3]
  assert_eq(
    r.function_count,
    s.function_count + l.function_count + b.function_count + n.function_count,
  )
  assert_eq(r.left_function_count, l.function_count + s.function_count)
  assert_eq(r.right_function_count, b.function_count + s.function_count)
  assert_eq(
    r.union_function_count,
    l.function_count + b.function_count + s.function_count,
  )
  assert_eq(r.function_count, r.union_function_count + n.function_count)
  assert_eq(
    r.local_encoded_bytes,
    s.local_encoded_bytes +
    l.local_encoded_bytes +
    b.local_encoded_bytes +
    n.local_encoded_bytes,
  )
  assert_eq(
    r.left_local_encoded_bytes,
    l.local_encoded_bytes + s.local_encoded_bytes,
  )
  assert_eq(
    r.right_local_encoded_bytes,
    b.local_encoded_bytes + s.local_encoded_bytes,
  )
  assert_eq(
    r.union_local_encoded_bytes,
    l.local_encoded_bytes + b.local_encoded_bytes + s.local_encoded_bytes,
  )
  assert_eq(
    r.local_encoded_bytes,
    r.union_local_encoded_bytes + n.local_encoded_bytes,
  )
  assert_eq(r.left_function_count, r.left_local_count + r.left_imported_count)
  assert_eq(
    r.right_function_count,
    r.right_local_count + r.right_imported_count,
  )
  assert_eq(
    r.union_function_count,
    r.union_local_count + r.union_imported_count,
  )
  assert_eq(r.left_reachable.length(), r.left_function_count)
  assert_eq(r.right_reachable.length(), r.right_function_count)
  let left_sorted = r.left_reachable.map(fn(i) { i })
  left_sorted.sort()
  let right_sorted = r.right_reachable.map(fn(i) { i })
  right_sorted.sort()
  assert_eq(r.left_reachable, left_sorted)
  assert_eq(r.right_reachable, right_sorted)
  for edge in r.left_edges {
    assert_true(
      r.left_reachable.contains(edge.caller) &&
      r.left_reachable.contains(edge.callee),
    )
  }
  for edge in r.right_edges {
    assert_true(
      r.right_reachable.contains(edge.caller) &&
      r.right_reachable.contains(edge.callee),
    )
  }
}

///|
test "dependency-overlap: four sets complete evidence and byte ledgers" {
  let data = overlap_test_fixture()
  let r = overlap_test_report(data, 1, 2)
  assert_eq(data.length(), 134)
  assert_eq(r.function_count, 8)
  assert_eq(r.left_reachable, [0, 1, 3, 4])
  assert_eq(r.right_reachable, [0, 2, 3, 4, 7])
  assert_eq(r.groups.map(fn(g) { g.indices }), [[0, 3, 4], [1], [2, 7], [5, 6]])
  assert_eq(
    r.groups.map(fn(g) {
      (g.function_count, g.local_count, g.imported_count, g.local_encoded_bytes)
    }),
    [(3, 2, 1, 12), (1, 1, 0, 17), (2, 2, 0, 10), (2, 2, 0, 6)],
  )
  assert_eq(
    (
      r.local_encoded_bytes,
      r.left_local_encoded_bytes,
      r.right_local_encoded_bytes,
      r.union_local_encoded_bytes,
    ),
    (45, 29, 22, 39),
  )
  assert_true(r.functions[0].imported && r.functions[0].encoded_size is None)
  assert_eq(overlap_test_edges(r.left_edges), [
    (1, 3, 0, 68),
    (1, 3, 0, 70),
    (1, 4, 1, 72),
    (1, 4, 2, 77),
    (1, 1, 0, 80),
    (3, 4, 0, 92),
    (3, 0, 0, 94),
    (4, 3, 0, 99),
  ])
  assert_eq(overlap_test_edges(r.right_edges), [
    (2, 3, 0, 85),
    (2, 7, 0, 87),
    (3, 4, 0, 92),
    (3, 0, 0, 94),
    (4, 3, 0, 99),
  ])
  overlap_test_ledger(r)
  let swapped = overlap_test_report(data, 2, 1)
  assert_eq(swapped.groups.map(fn(g) { g.indices }), [
    [0, 3, 4],
    [2, 7],
    [1],
    [5, 6],
  ])
  assert_eq(
    overlap_test_edges(swapped.left_edges),
    overlap_test_edges(r.right_edges),
  )
  overlap_test_ledger(swapped)
  let same = overlap_test_report(data, 1, 1)
  assert_eq(same.groups.map(fn(g) { g.indices }), [
    [0, 1, 3, 4],
    [],
    [],
    [2, 5, 6, 7],
  ])
  assert_eq(
    overlap_test_edges(same.left_edges),
    overlap_test_edges(same.right_edges),
  )
  overlap_test_ledger(same)
  let mutual = overlap_test_report(data, 3, 4)
  assert_eq(mutual.groups.map(fn(g) { g.indices }), [
    [0, 3, 4],
    [],
    [],
    [1, 2, 5, 6, 7],
  ])
  overlap_test_ledger(mutual)
  let imported = overlap_test_report(data, 0, 1)
  assert_eq(imported.groups.map(fn(g) { g.indices }), [
    [0],
    [],
    [1, 3, 4],
    [2, 5, 6, 7],
  ])
  assert_eq(imported.left_local_encoded_bytes, 0)
  overlap_test_ledger(imported)
}

///|
test "dependency-overlap: role errors helper reuse and module gaps" {
  let data = overlap_test_fixture()
  // One preparation in this test: compare the reused private helpers, no old public query.
  let inventory = path_inventory(data, parse_module(data).unwrap()).unwrap()
  let graph = build(data).unwrap()
  let (left, left_edges) = dependencies_closure(
    inventory,
    graph.edges,
    1,
    data.length(),
  ).unwrap()
  let (right, right_edges) = dependencies_closure(
    inventory,
    graph.edges,
    2,
    data.length(),
  ).unwrap()
  let partition = overlap_partition(
    inventory,
    left.map(fn(n) { n.node.index }),
    right.map(fn(n) { n.node.index }),
  )
  assert_eq(partition.map(fn(g) { g.indices }), [[0, 3, 4], [1], [2, 7], [5, 6]])
  assert_eq((left_edges.length(), right_edges.length()), (8, 5))
  let r = overlap_test_report(data, 1, 2)
  assert_eq(overlap_test_edges(r.left_edges), overlap_test_edges(left_edges))
  assert_eq(overlap_test_edges(r.right_edges), overlap_test_edges(right_edges))
  for index in [-1, 8, 2147483647] {
    assert_true(
      compare_function_dependencies(data, index, 2)
      is Err(InvalidOverlapTarget("left", _, 8)),
    )
    assert_true(
      compare_function_dependencies(data, 1, index)
      is Err(InvalidOverlapTarget("right", _, 8)),
    )
  }
  assert_true(
    compare_function_dependencies(b"\x00asm\x01\x00\x00\x00", 0, 0)
    is Err(InvalidOverlapTarget("left", 0, 0)),
  )
  assert_true(
    compare_function_dependencies(b"bad", 1, 2) is Err(OverlapInputError(_)),
  )
  let evidence = compare_function_dependencies(
    overlap_test_fixture(bad=true),
    1,
    2,
  )
  assert_true(
    evidence is Err(OverlapEvidenceError(InvalidDependenciesEvidence(8, 68, _))),
  )
  match evidence {
    Err(error) =>
      assert_true(
        describe_dependency_overlap_error(error).contains("file offset 68"),
      )
    _ => fail("invalid evidence accepted")
  }
  let gap = overlap_test_report(overlap_test_fixture(gap=true), 1, 2)
  assert_true(!gap.graph_complete)
  assert_eq(gap.unresolved_count, 0)
  assert_eq(gap.diagnostics.length(), 1)
  assert_eq((gap.diagnostics[0].caller, gap.diagnostics[0].offset), (6, 109))
  assert_eq(gap.diagnostics[0].opcode.name(), "call_ref")
  assert_true(
    !gap.left_reachable.contains(6) && !gap.right_reachable.contains(6),
  )
  overlap_test_ledger(gap)
  for
    error in [
      OverlapInputError(BadMagic),
      InvalidOverlapTarget("right", 8, 8),
      OverlapEvidenceError(InvalidDependenciesEvidence(8, 68, "bad callee")),
    ] {
    assert_true(!describe_dependency_overlap_error(error).is_empty())
  }
}

///|
test "dependency-overlap: parameters three Top tables and full JSON" {
  assert_eq(Options::default("x").compare_dependencies, None)
  assert_eq(Options::default("x").compare_dependencies_json, None)
  let args = [
    "moonsize", "--compare-dependencies", "1", "2", "--compare-dependencies-json",
    "new.json", "--top", "1", "--strict", "--", "--help",
  ]
  assert_true(help_request(args) is Ok(None))
  let options = parse_options(args).unwrap()
  assert_eq(options.compare_dependencies, Some((1, 2)))
  assert_eq(options.compare_dependencies_json, Some("new.json"))
  assert_true(options.strict && options.top == 1 && options.path == "--help")
  for
    tail in [
      ["--compare-dependencies"],
      ["--compare-dependencies", "1"],
      ["--compare-dependencies", "-1", "2"],
      ["--compare-dependencies", "1", "0x2"],
      ["--compare-dependencies", "2147483648", "2"],
      ["--compare-dependencies-json", "x.json"],
      ["--compare-dependencies", "1", "2", "--compare-dependencies-json"],
      ["--compare-dependencies", "1", "2", "--compare-dependencies-json", " "],
      [
        "--compare-dependencies", "1", "2", "--compare-dependencies-json", "x.txt",
      ],
    ] {
    assert_true(parse_options(["moonsize", "missing.wasm"] + tail) is Err(_))
  }
  for
    tail in [
      ["--baseline", "b"],
      ["--html", "x.html"],
      ["--retained"],
      ["--path-between", "1", "2"],
      ["--dependencies", "1"],
      ["--dependents", "2"],
      ["--cycles"],
      ["--why-index", "2"],
      ["--budget", "b.json"],
      ["--max-size", "1KB"],
      ["--compress"],
    ] {
    assert_true(
      parse_options(
        ["moonsize", "missing.wasm", "--compare-dependencies", "1", "2"] + tail,
      )
      is Err(_),
    )
  }
  assert_true(help_request(["moonsize", "--help"]) is Ok(Some(_)))
  let r = overlap_test_report(overlap_test_fixture(), 1, 2)
  let before = render_dependency_overlap_json(r)
  let text = render_dependency_overlap(r, 1)
  assert_eq(render_dependency_overlap_json(r), before) // presentation sorting must be on copies
  assert_true(text.contains("FUNCTION DEPENDENCY SET COMPARISON"))
  assert_true(
    text.contains("shared: showing 1 of 3") &&
    text.contains("left_only: showing 1 of 1") &&
    text.contains("right_only: showing 1 of 2"),
  )
  assert_true(!text.contains("neither: showing"))
  assert_true(text.contains("shared\\n\\u001b雪"))
  assert_true(
    text.contains("8 = shared 3 + left_only 1 + right_only 2 + neither 2"),
  )
  assert_true(
    text.contains("45 = shared 12 + left_only 17 + right_only 10 + neither 6"),
  )
  let full = render_dependency_overlap(r, 20)
  assert_true(full.contains("0  imported  n/a (not measured)"))
  let root = match @json.parse(before) {
    Object(fields) => fields
    _ => fail("object")
  }
  assert_eq(
    root.get("format"),
    Some(Json::string("moonsize-dependency-overlap")),
  )
  let functions = match root.get("functions") {
    Some(Array(rows)) => rows
    _ => fail("functions")
  }
  assert_eq(functions.length(), 8)
  let imported = match functions[0] {
    Object(fields) => fields
    _ => fail("import")
  }
  assert_eq(imported.get("encoded_size"), Some(Json::null()))
  let groups = match root.get("groups") {
    Some(Array(rows)) => rows
    _ => fail("groups")
  }
  let neither = match groups[3] {
    Object(fields) => fields
    _ => fail("neither")
  }
  assert_eq(
    neither.get("indices"),
    Some(Json::array([int_json(5), int_json(6)])),
  )
  assert_eq(r.groups[0].indices, [0, 3, 4])
}
