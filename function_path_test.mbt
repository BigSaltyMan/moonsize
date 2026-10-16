///|
priv struct PathFixture {
  data : Bytes
  /// Absolute first byte of each local body (the locals-vector byte).
  bodies : Array[Int]
}

///|
fn path_fixture(
  bodies : Array[Bytes],
  exports? : Array[(String, Int)] = [("run", 0)],
  imported? : Int = 0,
  start? : Int,
  elements? : Array[(Int, Array[Int])] = [],
  names? : Array[(Int, String)] = [],
) -> PathFixture {
  let out : Array[Byte] = [0, 97, 115, 109, 1, 0, 0, 0]
  diff_section(out, 1, [1, 96, 0, 0])
  if imported > 0 {
    let payload = diff_leb(imported)
    for _ in 0..<imported {
      diff_append(payload, [1, 109, 1, 102, 0, 0])
    }
    diff_section(out, 2, payload)
  }
  let declarations = diff_leb(bodies.length())
  for _ in bodies {
    declarations.push(0)
  }
  diff_section(out, 3, declarations)
  diff_section(out, 4, [1, 0x70, 0, 2])
  if !exports.is_empty() {
    let payload = diff_leb(exports.length())
    for (name, index) in exports {
      diff_name(payload, name)
      payload.push(0)
      diff_append(payload, diff_leb(index))
    }
    diff_section(out, 7, payload)
  }
  if start is Some(index) {
    diff_section(out, 8, diff_leb(index))
  }
  if !elements.is_empty() {
    let payload = diff_leb(elements.length())
    for (mode, functions) in elements {
      payload.push(mode.to_byte())
      if mode == 0 {
        diff_append(payload, [0x41, 0, 0x0b])
      } else {
        payload.push(0)
      }
      diff_append(payload, diff_leb(functions.length()))
      for index in functions {
        diff_append(payload, diff_leb(index))
      }
    }
    diff_section(out, 9, payload)
  }
  let payload = diff_leb(bodies.length())
  let relative : Array[Int] = []
  for body in bodies {
    diff_append(payload, diff_leb(body.length()))
    relative.push(payload.length())
    for byte in body {
      payload.push(byte)
    }
  }
  let body_start = out.length() + 1 + diff_leb(payload.length()).length()
  let offsets = relative.map(fn(offset) { body_start + offset })
  diff_section(out, 10, payload)
  if !names.is_empty() {
    let entries = diff_leb(names.length())
    for (index, name) in names {
      diff_append(entries, diff_leb(index))
      diff_name(entries, name)
    }
    let payload : Array[Byte] = [4, 110, 97, 109, 101]
    diff_section(payload, 1, entries)
    diff_section(out, 0, payload)
  }
  { data: Bytes::from_array(out), bodies: offsets, }
}

///|
fn query_path(
  fixture : PathFixture,
  target : Int,
  root? : Int,
  limits? : @moonsize.PathLimits,
) -> @moonsize.FunctionPathReport raise {
  match @moonsize.explain_function(fixture.data, target, root?, limits?) {
    Ok(report) => report
    Err(error) => fail(@moonsize.describe_function_path_error(error))
  }
}

///|
fn assert_path_indices(
  report : @moonsize.FunctionPathReport,
  expected : Array[Int],
) -> Unit raise {
  assert_true(report.status is PathFound)
  assert_eq(report.nodes.map(fn(node) { node.index }), expected)
  assert_eq(report.steps.length() + 1, report.nodes.length())
  let seen : Set[Int] = Set([])
  for i, node in report.nodes {
    assert_false(seen.contains(node.index))
    seen.add(node.index)
    if i > 0 {
      assert_eq(report.steps[i - 1].caller, report.nodes[i - 1].index)
      assert_eq(report.steps[i - 1].callee, node.index)
    }
  }
}

///|
test "public path query retains direct and tail opcodes and actual file offsets" {
  let fixture = path_fixture([
    b"\x00\x10\x01\x0b", b"\x00\x12\x02\x0b", b"\x00\x0b",
  ])
  let report = query_path(fixture, 2)
  assert_path_indices(report, [0, 1, 2])
  assert_eq(report.steps[0].opcode.name(), "call")
  assert_eq(report.steps[1].opcode.name(), "return_call")
  for i, step in report.steps {
    assert_eq(step.offset, fixture.bodies[i] + 1)
    assert_true(step.kind is Direct)
  }
  assert_eq(report.nodes[0].encoded_size, Some(5))
  assert_eq(report.search_stats.visited_nodes, 3)
  assert_eq(report.search_stats.checked_edges, 2)
}

///|
test "BFS is shortest and resolves diamond and multi-root ties deterministically" {
  let fixture = path_fixture([
    b"\x00\x10\x02\x10\x01\x0b", b"\x00\x10\x03\x0b", b"\x00\x10\x03\x0b", b"\x00\x0b",
  ])
  for _ in 0..<4 {
    assert_path_indices(query_path(fixture, 3), [0, 1, 3])
  }
  let multiple = path_fixture(
    [b"\x00\x10\x03\x0b", b"\x00\x0b", b"\x00\x10\x03\x0b", b"\x00\x0b"],
    exports=[("z", 2), ("a", 0)],
  )
  assert_path_indices(query_path(multiple, 3), [0, 3])
  let shorter = path_fixture([
    b"\x00\x10\x01\x10\x03\x0b", b"\x00\x10\x02\x0b", b"\x00\x10\x03\x0b", b"\x00\x0b",
  ])
  assert_path_indices(query_path(shorter, 3), [0, 3])
}

///|
test "cycles recursion and self loops terminate without parent cycles" {
  let fixture = path_fixture([
    b"\x00\x10\x00\x10\x01\x0b", b"\x00\x10\x02\x0b", b"\x00\x10\x01\x10\x03\x0b",
    b"\x00\x0b",
  ])
  assert_path_indices(query_path(fixture, 3), [0, 1, 2, 3])
}

///|
test "zero-step paths preserve every export start and element root reason" {
  let fixture = path_fixture(
    [b"\x00\x0b"],
    exports=[("one", 0), ("two", 0)],
    start=0,
    elements=[(0, [0, 0])],
  )
  let report = query_path(fixture, 0)
  assert_path_indices(report, [0])
  assert_eq(report.roots.length(), 1)
  assert_eq(report.roots[0].reasons.length(), 4)
  assert_eq(report.roots[0].reasons[0].name, Some("one"))
  assert_eq(report.roots[0].reasons[1].name, Some("two"))
  assert_true(report.roots[0].reasons[2].kind is StartRoot)
  assert_true(report.roots[0].reasons[3].kind is ElementRoot)
  assert_eq(report.roots[0].reasons[3].element_mode, Some("active"))
  assert_eq(report.search_stats.checked_edges, 0)
  assert_true(@moonsize.render_function_path(report).contains("Zero-step path"))
}

///|
test "real conservative element roots remain zero-step by default and indirect only from a selected root" {
  for body in [b"\x00\x41\x00\x11\x00\x00\x0b", b"\x00\x41\x00\x13\x00\x00\x0b"] {
    let fixture = path_fixture([body, b"\x00\x0b"], elements=[(0, [1])])
    assert_path_indices(query_path(fixture, 1), [1])
    let report = query_path(fixture, 1, root=0)
    assert_path_indices(report, [0, 1])
    assert_true(report.steps[0].kind is Indirect)
    assert_eq(
      report.steps[0].opcode.name(),
      if body[3] == 0x11 {
        "call_indirect"
      } else {
        "return_call_indirect"
      },
    )
    assert_eq(report.steps[0].offset, fixture.bodies[0] + 3)
    assert_eq(report.steps[0].table_index, Some(0))
    assert_eq(report.steps[0].type_index, Some(0))
    assert_true(report.graph_complete)
    let parsed = match @moonsize.parse_module(fixture.data) {
      Ok(v) => v
      Err(_) => fail("parse")
    }
    let analysis = match @moonsize.analyze(fixture.data, parsed) {
      Ok(v) => v
      Err(_) => fail("analysis")
    }
    assert_eq(
      Set::from_array(report.roots.map(fn(r) { r.index })),
      analysis.roots,
    )
  }
}

///|
test "selected-root reference edges and passive/declarative origins are honest" {
  for mode in [1, 3] {
    let fixture = path_fixture([b"\x00\xd2\x01\x1a\x0b", b"\x00\x0b"], elements=[
      (mode, [1]),
    ])
    assert_path_indices(query_path(fixture, 1), [1])
    let report = query_path(fixture, 1, root=0)
    assert_path_indices(report, [0, 1])
    assert_true(report.steps[0].kind is Reference)
    assert_eq(report.steps[0].opcode.name(), "ref.func")
    assert_eq(report.steps[0].offset, fixture.bodies[0] + 1)
    assert_eq(
      report.roots[1].reasons[0].element_mode,
      Some("passive-or-declarative"),
    )
    assert_eq(report.roots[1].reasons[0].table_index, None)
  }
}

///|
test "parallel edge tie rule prefers direct then reference then candidate and offset" {
  let fixture = path_fixture(
    [b"\x00\xd2\x01\x1a\x10\x01\x12\x01\x0b", b"\x00\x0b"],
    elements=[(3, [1])],
  )
  let report = query_path(fixture, 1, root=0)
  assert_path_indices(report, [0, 1])
  assert_true(report.steps[0].kind is Direct)
  assert_eq(report.steps[0].opcode.name(), "call")
  assert_eq(report.steps[0].offset, fixture.bodies[0] + 4)
}

///|
test "selected-root absence is not global unreachability and no-root search completes" {
  let fixture = path_fixture([b"\x00\x0b", b"\x00\x0b"], exports=[
    ("a", 0),
    ("b", 1),
  ])
  let report = query_path(fixture, 1, root=0)
  assert_true(report.status is PathNotFound)
  assert_true(report.nodes.is_empty() && report.steps.is_empty())
  assert_true(
    @moonsize.render_function_path(report).contains(
      "Other roots may still reach",
    ),
  )
  assert_path_indices(query_path(fixture, 1), [1])
  let no_roots = query_path(path_fixture([b"\x00\x0b"], exports=[]), 0)
  assert_true(no_roots.status is PathNotFound)
  assert_eq(no_roots.search_stats.visited_nodes, 0)
}

///|
test "imported functions use full indices and null encoded sizes" {
  let fixture = path_fixture([b"\x00\x10\x01\x0b"], imported=2, exports=[
    ("run", 2),
    ("host", 0),
  ])
  let report = query_path(fixture, 1, root=2)
  assert_path_indices(report, [2, 1])
  assert_true(report.target.imported)
  assert_eq(report.target.encoded_size, None)
  assert_eq(report.target.import_module, Some("m"))
  assert_eq(report.target.import_name, Some("f"))
  assert_eq(report.steps[0].offset, fixture.bodies[0] + 1)
  assert_true(@moonsize.render_function_path(report).contains("no local body"))
  assert_true(
    @moonsize.render_function_path_json(report).contains(
      "\"encoded_size\": null",
    ),
  )
  let host_root = query_path(fixture, 0)
  assert_path_indices(host_root, [0])
  assert_true(host_root.target.imported)
}

///|
test "public query rejects nonexistent targets roots and invalid limits" {
  let fixture = path_fixture([b"\x00\x0b", b"\x00\x0b"])
  for index in [-1, 2, 2147483647] {
    assert_true(
      @moonsize.explain_function(fixture.data, index)
      is Err(InvalidPathTarget(_, _)),
    )
    assert_true(
      @moonsize.explain_function(fixture.data, 0, root=index)
      is Err(InvalidPathRoot(_)),
    )
  }
  assert_true(
    @moonsize.explain_function(fixture.data, 0, root=1)
    is Err(InvalidPathRoot(1)),
  )
  for
    limits in [
      @moonsize.PathLimits::new(max_nodes=0),
      @moonsize.PathLimits::new(max_edges=-1),
      @moonsize.PathLimits::new(max_depth=-1),
    ] {
    assert_true(
      @moonsize.explain_function(fixture.data, 0, limits~)
      is Err(InvalidPathLimits(_)),
    )
  }
  assert_true(
    @moonsize.explain_function(b"\x00asm\x01\x00\x00\x00", 0)
    is Err(InvalidPathTarget(0, 0)),
  )
  assert_true(@moonsize.explain_function(b"bad", 0) is Err(PathInputError(_)))
}

///|
test "ghost root and graph indices are rejected rather than trusted" {
  let edge = path_fixture([b"\x00\x10\x09\x0b"])
  assert_true(
    @moonsize.explain_function(edge.data, 0) is Err(InvalidPathEdgeIndex(9, _)),
  )
  let exported = path_fixture([b"\x00\x0b"], exports=[("ghost", 9)])
  assert_true(
    @moonsize.explain_function(exported.data, 0)
    is Err(InvalidPathRootReference(9, _)),
  )
  let element = path_fixture([b"\x00\x0b"], elements=[(3, [9])])
  assert_true(
    @moonsize.explain_function(element.data, 0)
    is Err(InvalidPathRootReference(9, _)),
  )
  let started = path_fixture([b"\x00\x0b"], start=9)
  assert_true(
    @moonsize.explain_function(started.data, 0)
    is Err(InvalidPathRootReference(9, _)),
  )
}

///|
test "node edge and depth bounds distinguish exact completion and truncation" {
  let fixture = path_fixture([
    b"\x00\x10\x01\x0b", b"\x00\x10\x02\x0b", b"\x00\x0b",
  ])
  let exact = @moonsize.PathLimits::new(max_nodes=3, max_edges=2, max_depth=2)
  assert_path_indices(query_path(fixture, 2, limits=exact), [0, 1, 2])
  for
    limits in [
      @moonsize.PathLimits::new(max_nodes=2),
      @moonsize.PathLimits::new(max_edges=1),
      @moonsize.PathLimits::new(max_depth=1),
    ] {
    let report = query_path(fixture, 2, limits~)
    assert_true(report.status is PathSearchLimited)
    assert_true(report.nodes.is_empty() && report.steps.is_empty())
    assert_true(report.search_stats.limit_reason is Some(_))
    assert_true(report.search_stats.visited_nodes <= limits.max_nodes)
    assert_true(report.search_stats.indexed_edges <= limits.max_edges)
    assert_true(report.search_stats.checked_edges <= limits.max_edges)
  }
  let self_loop = path_fixture([b"\x00\x10\x00\x0b", b"\x00\x0b"])
  let complete = query_path(
    self_loop,
    1,
    limits=@moonsize.PathLimits::new(max_nodes=1, max_edges=1, max_depth=0),
  )
  assert_true(complete.status is PathNotFound)
  assert_eq(complete.search_stats.checked_edges, 1)
  assert_path_indices(
    query_path(fixture, 0, limits=@moonsize.PathLimits::new(max_depth=0)),
    [0],
  )
}

///|
test "root preparation is limited before expanding an unbounded source ledger" {
  let fixture = path_fixture([b"\x00\x0b", b"\x00\x0b"], exports=[
    ("a", 0),
    ("b", 1),
  ])
  let roots = query_path(
    fixture,
    0,
    limits=@moonsize.PathLimits::new(max_nodes=1),
  )
  assert_true(roots.status is PathSearchLimited)
  assert_eq(roots.search_stats.phase, "root-preparation")
  assert_eq(roots.search_stats.prepared_roots, 1)
  let sources = query_path(
    path_fixture([b"\x00\x0b"], exports=[("a", 0), ("b", 0)]),
    0,
    limits=@moonsize.PathLimits::new(max_edges=1),
  )
  assert_true(sources.status is PathSearchLimited)
  assert_eq(sources.search_stats.root_sources, 1)
  assert_eq(sources.search_stats.limit_reason, Some("root-source-limit"))
  assert_true(
    @moonsize.render_function_path_json(sources).contains(
      "\"root_ledger_complete\": false",
    ),
  )
  assert_true(sources.selected_roots.is_empty())
}

///|
test "reference-call gaps are kept without guessing their unmodelled target" {
  let fixture = path_fixture([b"\x00\xd0\x00\x14\x00\x0b", b"\x00\x0b"])
  let report = query_path(fixture, 1)
  assert_true(report.status is PathNotFound)
  assert_false(report.graph_complete)
  assert_eq(report.diagnostics.length(), 1)
  assert_true(report.diagnostics[0].kind is UnmodeledReferenceCall)
  assert_true(
    @moonsize.render_function_path_json(report).contains(
      "unmodeled_reference_call",
    ),
  )
  assert_true(
    @moonsize.render_function_path(report).contains(
      "unmodelled references cannot be excluded",
    ),
  )
  let known = path_fixture(
    [b"\x00\xd2\x01\x1a\xd0\x00\x14\x00\x0b", b"\x00\x0b"],
    elements=[(3, [1])],
  )
  let found = query_path(known, 1, root=0)
  assert_path_indices(found, [0, 1])
  assert_false(found.graph_complete)
  assert_true(found.steps[0].kind is Reference)
}

///|
test "static candidates retain paths and complete dynamic-table provenance" {
  let fixture = path_fixture(
    [
      b"\x00\x41\x00\x11\x00\x00\x0b", b"\x00\x0b", b"\x00\x41\x00\xd0\x70\x26\x00\x0b",
    ],
    elements=[(0, [1])],
  )
  let report = query_path(fixture, 1, root=0)
  assert_path_indices(report, [0, 1])
  assert_false(report.graph_complete)
  assert_true(report.diagnostics[0].kind is RuntimeTableMutation)
  assert_eq(report.diagnostics[0].offset, fixture.bodies[0] + 3)
  assert_eq(report.diagnostics[0].source.unwrap().caller, Some(2))
  assert_eq(report.diagnostics[0].source.unwrap().offset, fixture.bodies[2] + 5)
  let json = @moonsize.render_function_path_json(report)
  assert_true(json.contains("runtime_table_mutation"))
  assert_true(json.contains("table.set"))
}

///|
test "index identity survives duplicate unnamed unicode and escaped display text" {
  let fixture = path_fixture(
    [b"\x00\x10\x01\x10\x02\x0b", b"\x00\x0b", b"\x00\x0b"],
    exports=[("入口\"\n", 0)],
    names=[(0, "same"), (1, "same"), (2, "函数\"\n")],
  )
  let duplicate = query_path(fixture, 1)
  assert_path_indices(duplicate, [0, 1])
  assert_eq(duplicate.nodes[0].name, duplicate.nodes[1].name)
  let escaped = query_path(fixture, 2)
  assert_eq(escaped.target.raw_name, Some("函数\"\n"))
  let json = @moonsize.render_function_path_json(escaped)
  assert_true(json.contains("函数\\\"\\n"))
  assert_true(json.contains("入口\\\"\\n"))
  assert_true(json.contains("\"schema_version\": 1"))
  assert_true(json.contains("\"position_granularity\": \"section\""))
  assert_true(json.contains("not an execution trace"))
}

///|
test "path options keep defaults and accept the full nonnegative Int domain" {
  let defaults = @moonsize.Options::default("app.wasm")
  assert_true(defaults.why_index is None)
  assert_true(defaults.why_root is None)
  assert_true(defaults.why_json is None)
  let options = match
    @moonsize.parse_options([
      "moonsize", "app.wasm", "--why-index", "2147483647", "--why-root", "0", "--why-json",
      "path.json", "--strict",
    ]) {
    Ok(options) => options
    Err(error) => fail(error)
  }
  assert_eq(options.why_index, Some(2147483647))
  assert_eq(options.why_root, Some(0))
  assert_eq(options.why_json, Some("path.json"))
  assert_true(options.strict)
}
