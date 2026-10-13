///|
/// A module built to exercise every kind of reference the graph knows about:
/// a direct call, a `call_indirect` whose target comes from the table, and a
/// `ref.func` that only takes a reference. Function 3 has no body worth running
/// and nothing points at it, so it is dead.
fn graph_module() -> Bytes {
  b"\x00\x61\x73\x6d\x01\x00\x00\x00\x01\x04\x01\x60\x00\x00\x03\x05\x04\x00\x00" +
  b"\x00\x00\x04\x04\x01\x70\x00\x01\x07\x07\x01\x03\x72\x75\x6e\x00\x00\x08\x01" +
  b"\x01\x09\x07\x01\x00\x41\x00\x0b\x01\x02\x0a\x17\x04\x04\x00\x10\x01\x0b\x07" +
  b"\x00\x41\x00\x11\x00\x00\x0b\x05\x00\xd2\x01\x1a\x0b\x02\x00\x0b"
}

///|
/// A graph from `caller -> callee` pairs, every edge taken as a direct call.
fn graph_of(pairs : Array[(Int, Int)]) -> CallGraph {
  graph_of_kind(pairs, Direct)
}

///|
/// A graph from `caller -> callee` pairs of one kind.
fn graph_of_kind(pairs : Array[(Int, Int)], kind : EdgeKind) -> CallGraph {
  let calls : Map[Int, Set[Int]] = Map([])
  let called_by : Map[Int, Set[Int]] = Map([])
  let edges : Array[CallEdge] = []
  for pair in pairs {
    add_edge(calls, called_by, edges, pair.0, pair.1, kind, 0)
  }
  { calls, called_by, indirect_sites: [], unresolved_indirect: [], edges, }
}

///|
/// A set of indices.
fn set_of(values : Array[Int]) -> Set[Int] {
  let set : Set[Int] = Set([])
  for value in values {
    set.add(value)
  }
  set
}

///|
/// A size table from `index -> bytes` pairs.
fn sizes_of(pairs : Array[(Int, Int)]) -> Map[Int, Int] {
  let sizes : Map[Int, Int] = Map([])
  for pair in pairs {
    sizes.set(pair.0, pair.1)
  }
  sizes
}

///|
/// The retained total for one function, or `-1` when it has no entry.
fn retained_of(entries : Array[RetainedSize], index : Int) -> Int {
  for entry in entries {
    if entry.index == index {
      return entry.retained
    }
  }
  -1
}

///|
/// How many functions die with one function, or `-1` when it has no entry.
fn dies_of(entries : Array[RetainedSize], index : Int) -> Int {
  for entry in entries {
    if entry.index == index {
      return entry.retained_functions
    }
  }
  -1
}

///|
/// Analyse the fixture module, failing loudly if it does not parse.
fn analysis_of(data : Bytes) -> Analysis raise {
  let parsed = match parse_module(data) {
    Ok(parsed) => parsed
    Err(error) => fail(describe_error(error))
  }
  match analyze(data, parsed) {
    Ok(analysis) => analysis
    Err(error) => fail(describe_error(error))
  }
}

///|
test "reachability follows the edges and keeps the roots" {
  let graph = graph_of([(1, 2), (2, 3)])
  let reachable = reachable_from_roots(graph, set_of([1]))
  inspect(
    reachable.length(),
    content=(
      #|3
    ),
  )
  assert_true(reachable.contains(3))
  assert_true(!reachable.contains(4))
}

///|
test "a cycle and a self loop do not trap the walk" {
  let graph = graph_of([(1, 2), (2, 1), (3, 3)])
  let reachable = reachable_from_roots(graph, set_of([1, 3]))
  inspect(
    reachable.length(),
    content=(
      #|3
    ),
  )
}

///|
test "a chain retains everything below it" {
  let graph = graph_of([(1, 2), (2, 3)])
  let sizes = sizes_of([(1, 100), (2, 200), (3, 300)])
  let retained = retained_sizes(graph, sizes, set_of([1]))
  inspect(
    retained_of(retained, 1),
    content=(
      #|600
    ),
  )
  inspect(
    retained_of(retained, 2),
    content=(
      #|500
    ),
  )
  inspect(
    retained_of(retained, 3),
    content=(
      #|300
    ),
  )
  inspect(
    dies_of(retained, 1),
    content=(
      #|2
    ),
  )
  inspect(
    dies_of(retained, 3),
    content=(
      #|0
    ),
  )
}

///|
/// The diamond is the case that separates an exact retained size from the
/// tempting local rule "count a successor only when this function is its sole
/// predecessor". Under that rule 4 has two predecessors, so deleting 1 would
/// appear to free 1, 2 and 3 and spare 4. It is not spared: 2 and 3 die first,
/// and the last paths into 4 die with them. The 1000 asserted below is the
/// reachability answer, not an approximation of it.
test "a diamond loses the branch only the deleted function reached" {
  // 1 -> 2 -> 4 and 1 -> 3 -> 4, with 1 the only root.
  let graph = graph_of([(1, 2), (1, 3), (2, 4), (3, 4)])
  let sizes = sizes_of([(1, 100), (2, 200), (3, 300), (4, 400)])
  let retained = retained_sizes(graph, sizes, set_of([1]))
  // Deleting 1 strands 2 and 3, and with them the last paths to 4.
  inspect(
    retained_of(retained, 1),
    content=(
      #|1000
    ),
  )
  // Deleting 2 leaves 1 -> 3 -> 4 intact, so nothing else dies with it.
  inspect(
    retained_of(retained, 2),
    content=(
      #|200
    ),
  )
  inspect(
    retained_of(retained, 3),
    content=(
      #|300
    ),
  )
  inspect(
    retained_of(retained, 4),
    content=(
      #|400
    ),
  )
}

///|
test "a second root keeps a branch alive" {
  let graph = graph_of([(1, 2), (1, 3), (2, 4), (3, 4)])
  let sizes = sizes_of([(1, 100), (2, 200), (3, 300), (4, 400)])
  let retained = retained_sizes(graph, sizes, set_of([1, 3]))
  // 3 is reachable without 1, so 3 and 4 survive and only 2 dies with it.
  inspect(
    retained_of(retained, 1),
    content=(
      #|300
    ),
  )
  inspect(
    dies_of(retained, 1),
    content=(
      #|1
    ),
  )
}

///|
test "a cycle retains its members together" {
  let graph = graph_of([(1, 2), (2, 1)])
  let sizes = sizes_of([(1, 100), (2, 200)])
  let retained = retained_sizes(graph, sizes, set_of([1]))
  // Deleting 1 takes 2 with it, and deleting 2 leaves the root 1 alive.
  inspect(
    retained_of(retained, 1),
    content=(
      #|300
    ),
  )
  inspect(
    retained_of(retained, 2),
    content=(
      #|200
    ),
  )
}

///|
test "an indirect edge carries reachability like any other" {
  let graph = graph_of_kind([(1, 2)], Indirect)
  let reachable = reachable_from_roots(graph, set_of([1]))
  assert_true(reachable.contains(2))
}

///|
test "build reads every kind of reference out of real bodies" {
  let analysis = analysis_of(graph_module())
  inspect(
    analysis.graph.edges.length(),
    content=(
      #|3
    ),
  )
  // call 1 from function 0, through the table into 2, and a ref.func back to 1.
  inspect(
    analysis.graph.edges[0].caller,
    content=(
      #|0
    ),
  )
  inspect(
    analysis.graph.edges[0].callee,
    content=(
      #|1
    ),
  )
  inspect(
    analysis.graph.edges[1].callee,
    content=(
      #|2
    ),
  )
  inspect(
    analysis.graph.edges[2].caller,
    content=(
      #|2
    ),
  )
  inspect(
    analysis.graph.edges[2].callee,
    content=(
      #|1
    ),
  )
  inspect(
    analysis.graph.indirect_sites.length(),
    content=(
      #|1
    ),
  )
  assert_eq(analysis.graph.indirect_sites[0].candidates, [2])
}

///|
test "roots are the exports, the start function and the table" {
  let analysis = analysis_of(graph_module())
  inspect(
    analysis.roots.length(),
    content=(
      #|3
    ),
  )
  assert_true(analysis.roots.contains(0))
  assert_true(analysis.roots.contains(1))
  assert_true(analysis.roots.contains(2))
  assert_true(!analysis.roots.contains(3))
}

///|
test "a function nothing points at is not reachable" {
  let analysis = analysis_of(graph_module())
  inspect(
    analysis.reachable.length(),
    content=(
      #|3
    ),
  )
  assert_true(!analysis.reachable.contains(3))
  inspect(
    analysis.indirect.contains(2),
    content=(
      #|true
    ),
  )
}

///|
test "the fixture's dead code is reported with its size" {
  let analysis = analysis_of(graph_module())
  let parsed = match parse_module(graph_module()) {
    Ok(parsed) => parsed
    Err(error) => fail(describe_error(error))
  }
  inspect(
    render_dead_code(analysis.stats, analysis.reachable, parsed.file_size, 10),
    content=(
      #|Dead code
      #|
      #|  1 of 4 functions are unreachable from the roots
      #|  3 bytes (4.1% of file)
      #|
      #|  Top 1 dead function
      #|
      #|  SIZE    SHARE  FUNCTION
      #|     3     4.1%  (unnamed)
    ),
  )
}

///|
test "dead code names the heaviest functions first" {
  let stats : Array[FunctionStat] = [
    {
      index: 1,
      name: "live::root",
      module_name: "live",
      body_size: 10,
      total_size: 11,
      offset: 0,
    },
    {
      index: 2,
      name: "dead::small",
      module_name: "dead",
      body_size: 20,
      total_size: 21,
      offset: 0,
    },
    {
      index: 3,
      name: "dead::big",
      module_name: "dead",
      body_size: 300,
      total_size: 301,
      offset: 0,
    },
  ]
  inspect(
    render_dead_code(stats, set_of([1]), 1000, 10),
    content=(
      #|Dead code
      #|
      #|  2 of 3 functions are unreachable from the roots
      #|  322 bytes (32.2% of file)
      #|
      #|  Top 2 dead functions
      #|
      #|  SIZE    SHARE  FUNCTION
      #|   301    30.1%  dead::big
      #|    21     2.1%  dead::small
    ),
  )
}

///|
test "retained size is reported as a table of two numbers" {
  let stats : Array[FunctionStat] = [
    {
      index: 1,
      name: "app::main",
      module_name: "app",
      body_size: 100,
      total_size: 101,
      offset: 0,
    },
    {
      index: 2,
      name: "app::helper",
      module_name: "app",
      body_size: 200,
      total_size: 201,
      offset: 0,
    },
  ]
  let retained : Array[RetainedSize] = [
    { index: 1, own_size: 101, retained: 302, retained_functions: 1, },
    { index: 2, own_size: 201, retained: 201, retained_functions: 0, },
  ]
  inspect(
    render_retained(stats, retained, Set([]), 1000, 10),
    content=(
      #|Retained size
      #|
      #|    #  INDEX  SIZE  RETAINED  DIES    SHARE  IND  FUNCTION
      #|    1      1   101       302     1    30.2%       app::main
      #|    2      2   201       201     0    20.1%       app::helper
      #|
      #|  DIES counts the other functions that become unreachable with this one.
      #|  IND marks a function a call_indirect could reach.
    ),
  )
}

///|
/// A 54-byte module whose only call is a `call_indirect` through a table that no
/// element segment fills: the table is declared so the call is legal, but its
/// contents are only knowable at run time.
///
/// `func 0` is exported, so it is the root; `func 1` can be reached only through
/// the table.
fn dynamic_table_module() -> Bytes {
  b"\x00\x61\x73\x6d\x01\x00\x00\x00\x01\x0a\x02\x60" +
  b"\x00\x01\x7f\x60\x01\x7f\x01\x7f\x03\x03\x02\x01" +
  b"\x00\x04\x04\x01\x70\x00\x02\x07\x05\x01\x01\x67" +
  b"\x00\x00\x0a\x0e\x02\x07\x00\x41\x00\x11\x00\x00" +
  b"\x0b\x04\x00\x20\x00\x0b"
}

///|
/// The same module with its element segment written, so the table's contents are
/// known: 64 bytes. The pair is the regression — one graph is complete, the
/// other is not, and only the difference between them is under test.
fn static_table_module() -> Bytes {
  b"\x00\x61\x73\x6d\x01\x00\x00\x00\x01\x0a\x02\x60" +
  b"\x00\x01\x7f\x60\x01\x7f\x01\x7f\x03\x03\x02\x01" +
  b"\x00\x04\x04\x01\x70\x00\x02\x07\x05\x01\x01\x67" +
  b"\x00\x00\x09\x08\x01\x00\x41\x00\x0b\x02\x00\x01" +
  b"\x0a\x0e\x02\x07\x00\x41\x00\x11\x00\x00\x0b\x04" +
  b"\x00\x20\x00\x0b"
}

///|
/// Parse and analyse a fixture, or fail the test that asked for it.
fn analysis_of_module(data : Bytes) -> Analysis raise {
  let parsed = match parse_module(data) {
    Ok(parsed) => parsed
    Err(error) => fail(describe_error(error))
  }
  match analyze(data, parsed) {
    Ok(analysis) => analysis
    Err(error) => fail(describe_error(error))
  }
}

///|
test "a call_indirect with no candidates is recorded, not dropped" {
  let analysis = analysis_of_module(dynamic_table_module())
  // The site is kept and counted even though it contributed no edge: that record
  // is the difference between a warning and a wrong answer.
  inspect(analysis.graph.indirect_sites.length(), content="1")
  inspect(analysis.graph.unresolved_indirect.length(), content="1")
  inspect(analysis.unresolved_count, content="1")
  inspect(analysis.graph_complete, content="false")
  inspect(is_graph_complete(analysis.graph), content="false")
  // And this is what it costs: the function the call could reach is invisible to
  // reachability, which is exactly how it used to be reported as dead code.
  assert_true(!analysis.reachable.contains(1))
}

///|
test "an incomplete graph says so, in the report and in each section it touches" {
  let analysis = analysis_of_module(dynamic_table_module())
  let warning = render_graph_warning(analysis.unresolved_count)
  assert_true(
    warning.contains(
      "WARNING: 1 call_indirect site has no resolvable target (table filled at runtime).",
    ),
  )
  assert_true(
    warning.contains(
      "Dead-code and retained-size results may be inaccurate; treat them as lower bounds.",
    ),
  )
  // The two sections whose numbers are lower bounds repeat it under their titles.
  let dead = render_dead_code(
    analysis.stats,
    analysis.reachable,
    54,
    5,
    unresolved=analysis.unresolved_count,
  )
  assert_true(
    dead.contains("  (graph incomplete: 1 unresolved indirect call)\n"),
  )
  let retained = render_retained(
    analysis.stats,
    analysis.retained,
    analysis.indirect,
    54,
    5,
    unresolved=analysis.unresolved_count,
  )
  assert_true(
    retained.contains("  (graph incomplete: 1 unresolved indirect call)\n"),
  )
}

///|
test "a complete graph warns about nothing" {
  let analysis = analysis_of_module(static_table_module())
  inspect(analysis.graph.indirect_sites.length(), content="1")
  inspect(analysis.graph.unresolved_indirect.length(), content="0")
  inspect(analysis.unresolved_count, content="0")
  inspect(analysis.graph_complete, content="true")
  inspect(render_graph_warning(0), content="")
  // Both functions are reachable through the table once its contents are known.
  assert_true(analysis.reachable.contains(1))
  // Nothing to declare, so the sections read exactly as they always did.
  assert_true(
    !render_dead_code(analysis.stats, analysis.reachable, 64, 5).contains(
      "graph incomplete",
    ),
  )
  assert_true(
    !render_retained(
      analysis.stats,
      analysis.retained,
      analysis.indirect,
      64,
      5,
    ).contains("graph incomplete"),
  )
}

///|
test "--strict refuses an incomplete graph, and only then" {
  let strict = match parse_options(["moonsize", "app.wasm", "--strict"]) {
    Ok(options) => options
    Err(message) => fail(message)
  }
  let lax = match parse_options(["moonsize", "app.wasm"]) {
    Ok(options) => options
    Err(message) => fail(message)
  }
  inspect(strict.strict, content="true")
  inspect(lax.strict, content="false")
  // Incomplete + strict is the only combination that fails.
  inspect(strict_exit_code(strict, false), content="3")
  inspect(strict_exit_code(strict, true), content="0")
  inspect(strict_exit_code(lax, false), content="0")
  inspect(strict_exit_code(lax, true), content="0")
}
