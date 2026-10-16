///|
/// Every ref.func has a declaration; every call has a () -> () signature.
/// The declarative segment declares the target without filling a table. Active
/// elements instead supply a static candidate when requested.
fn diagnostic_module(
  expression : Bytes,
  imported? : Bool = false,
  table? : Bool = false,
  static_targets? : Bool = false,
) -> Bytes raise {
  let target = if imported { 2 } else { 1 }
  let elements = (if static_targets {
      b"\x09\x07\x01\x00\x41\x00\x0b\x01"
    } else {
      b"\x09\x05\x01\x03\x00\x01"
    }) +
    Bytes::from_array([target.to_byte()])
  tail_module(
    [b"\x00" + expression + b"\x0b", b"\x00\x0b"],
    imported~,
    tables=if table || static_targets {
      b"\x04\x04\x01\x70\x00\x01"
    } else {
      b""
    },
    elements~,
  )
}

///|
fn assert_reference_gap(
  diagnostic : GraphDiagnostic,
  caller : Int,
  offset : Int,
  opcode : String,
) -> Unit raise {
  match diagnostic.kind {
    UnmodeledReferenceCall => ()
    _ => fail("expected UnmodeledReferenceCall")
  }
  assert_eq(diagnostic.caller, caller)
  assert_eq(diagnostic.offset, offset)
  assert_eq(diagnostic.opcode.name(), opcode)
  assert_eq(diagnostic.type_index, Some(0))
  assert_eq(diagnostic.table_index, None)
}

///|
test "reference call sites remain distinct even with identical opcode and type" {
  let analysis = analysis_of(
    diagnostic_module(b"\xd2\x01\x14\x00\xd2\x01\x14\x00"),
  )
  assert_eq(analysis.graph.diagnostics.length(), 2)
  assert_reference_gap(analysis.graph.diagnostics[0], 0, 42, "call_ref")
  assert_reference_gap(analysis.graph.diagnostics[1], 0, 46, "call_ref")
  assert_eq(analysis.unresolved_count, 0)
  assert_true(!analysis.graph_complete)
  assert_eq(analysis.graph.edges.length(), 2)
  for edge in analysis.graph.edges {
    match edge.kind {
      Reference => ()
      _ => fail("reference calls must not fabricate callee edges")
    }
    assert_eq(edge.callee, 1)
  }
}

///|
test "reference and unresolved table calls share diagnostics without double counting" {
  let analysis = analysis_of(
    diagnostic_module(b"\x41\x00\x11\x00\x00\xd2\x01\x14\x00", table=true),
  )
  assert_eq(analysis.graph.diagnostics.length(), 2)
  assert_eq(analysis.unresolved_count, 1)
  assert_eq(analysis.graph.unresolved_indirect.length(), 1)
  assert_eq(analysis.graph.indirect_sites.length(), 1)
  assert_true(!analysis.graph_complete)
  let table = analysis.graph.diagnostics[0]
  match table.kind {
    NoStaticTableTargets => ()
    _ => fail("expected NoStaticTableTargets")
  }
  assert_eq(table.caller, 0)
  assert_eq(table.offset, 48)
  assert_eq(table.opcode.name(), "call_indirect")
  assert_eq(table.type_index, Some(0))
  assert_eq(table.table_index, Some(0))
  assert_reference_gap(analysis.graph.diagnostics[1], 0, 53, "call_ref")
}

///|
test "table tail calls also retain their actual diagnostic opcode" {
  let analysis = analysis_of(
    diagnostic_module(b"\x41\x00\x13\x00\x00", table=true),
  )
  assert_eq(analysis.graph.diagnostics.length(), 1)
  let diagnostic = analysis.graph.diagnostics[0]
  match diagnostic.kind {
    NoStaticTableTargets => ()
    _ => fail("expected NoStaticTableTargets")
  }
  assert_eq(diagnostic.opcode.name(), "return_call_indirect")
  assert_eq(diagnostic.caller, 0)
  assert_eq(diagnostic.offset, 48)
  assert_eq(diagnostic.type_index, Some(0))
  assert_eq(diagnostic.table_index, Some(0))
  assert_eq(analysis.unresolved_count, 1)
}

///|
test "static table candidates do not hide reference call gaps" {
  let analysis = analysis_of(
    diagnostic_module(
      b"\x41\x00\x11\x00\x00\xd2\x01\x15\x00",
      static_targets=true,
    ),
  )
  assert_eq(analysis.graph.diagnostics.length(), 1)
  assert_reference_gap(analysis.graph.diagnostics[0], 0, 55, "return_call_ref")
  assert_eq(analysis.unresolved_count, 0)
  assert_true(!analysis.graph_complete)
  assert_eq(analysis.graph.indirect_sites[0].candidates, [1])
  assert_eq(analysis.graph.edges.length(), 2)
  match analysis.graph.edges[0].kind {
    Indirect => ()
    _ => fail("expected static indirect edge")
  }
}

///|
test "ref.func alone produces an edge without a reference call gap" {
  let analysis = analysis_of(diagnostic_module(b"\xd2\x01\x1a"))
  assert_true(analysis.graph_complete)
  assert_eq(analysis.graph.diagnostics.length(), 0)
  assert_eq(analysis.graph.edges.length(), 1)
  match analysis.graph.edges[0].kind {
    Reference => ()
    _ => fail("expected ref.func reference edge")
  }
}

///|
test "reference diagnostics use full caller indices after imports" {
  let analysis = analysis_of(
    diagnostic_module(b"\xd2\x02\x15\x00", imported=true),
  )
  assert_eq(analysis.graph.diagnostics.length(), 1)
  assert_reference_gap(analysis.graph.diagnostics[0], 1, 51, "return_call_ref")
  assert_eq(analysis.graph.edges[0].callee, 2)
  assert_eq(analysis.unresolved_count, 0)
  assert_true(!analysis.graph_complete)
}

///|
fn json_object(value : Json) -> Map[String, Json] raise {
  match value {
    Object(members) => members
    _ => fail("expected JSON object")
  }
}

///|
fn json_array(value : Json) -> Array[Json] raise {
  match value {
    Array(items) => items
    _ => fail("expected JSON array")
  }
}

///|
test "dynamic writer provenance survives JSON DOT HTML and text rendering" {
  let data = b"\x00asm\x01\x00\x00\x00\x01\x04\x01\x60\x00\x00" +
    b"\x03\x03\x02\x00\x00\x04\x04\x01\x70\x00\x01" +
    b"\x07\x07\x01\x03run\x00\x00\x09\x07\x01\x00\x41\x00\x0b\x01\x01" +
    b"\x0a\x12\x02\x0d\x00\x41\x00\x11\x00\x00\x41\x00\xd2\x01\x26\x00\x0b\x02\x00\x0b"
  let analysis = analysis_of(data)
  let root = json_object(
    @json.parse(render_graph("app.wasm", analysis, "graph.json")),
  )
  let rows = json_array(root.get("diagnostics").unwrap())
  assert_eq(rows.length(), 1)
  let diagnostic = json_object(rows[0])
  assert_eq(
    diagnostic.get("code"),
    Some(Json::string("runtime_table_mutation")),
  )
  assert_eq(diagnostic.get("caller"), Some(int_json(0)))
  assert_eq(diagnostic.get("offset"), Some(int_json(50)))
  assert_eq(diagnostic.get("table_index"), Some(int_json(0)))
  assert_eq(diagnostic.get("type_index"), Some(int_json(0)))
  assert_eq(diagnostic.get("opcode"), Some(Json::string("call_indirect")))
  let source = json_object(diagnostic.get("source").unwrap())
  assert_eq(source.get("caller"), Some(int_json(0)))
  assert_eq(source.get("offset"), Some(int_json(57)))
  assert_eq(source.get("opcode"), Some(Json::string("table.set")))
  assert_eq(root.get("graph_complete"), Some(Json::boolean(false)))
  assert_eq(json_array(root.get("edges").unwrap()).length(), 2)
  let embedded = json_object(report_data(analysis, "app.wasm"))
  assert_eq(embedded.get("diagnostics"), root.get("diagnostics"))
  for
    text in [
      render_graph_warning(analysis.graph),
      render_graph("app.wasm", analysis, "graph.dot"),
      render_html(analysis, "app.wasm"),
      render_dead_code(analysis, 5),
      render_retained(analysis, 5),
    ] {
    assert_true(
      text.contains(
        "table 0 contents may change through table.set at function 0, offset 57.",
      ),
    )
    assert_true(text.contains("function 0, offset 50: call_indirect"))
    assert_true(
      text.contains("do not use them as proof that a function can be removed."),
    )
  }
}

///|
test "JSON exports parse as objects with exact diagnostic fields and old graph data" {
  let analysis = analysis_of(
    diagnostic_module(b"\x41\x00\x11\x00\x00\xd2\x01\x14\x00", table=true),
  )
  let root = json_object(
    @json.parse(render_graph("a\"\n<示例>.wasm", analysis, "graph.json")),
  )
  assert_eq(root.get("schema_version"), Some(int_json(1)))
  assert_eq(root.get("graph_complete"), Some(Json::boolean(false)))
  assert_eq(root.get("module"), Some(Json::string("a\"\n<示例>.wasm")))
  assert_eq(
    root.get("modeling_scope"),
    Some(Json::string(graph_modeling_scope())),
  )
  assert_eq(json_array(root.get("functions").unwrap()).length(), 2)
  assert_eq(json_array(root.get("edges").unwrap()).length(), 1)
  assert_eq(json_array(root.get("roots").unwrap()).length(), 2)
  let diagnostics = json_array(root.get("diagnostics").unwrap())
  assert_eq(diagnostics.length(), 2)
  let table = json_object(diagnostics[0])
  assert_eq(table.get("code"), Some(Json::string("no_static_table_targets")))
  assert_eq(table.get("caller"), Some(int_json(0)))
  assert_eq(table.get("offset"), Some(int_json(48)))
  assert_eq(table.get("opcode"), Some(Json::string("call_indirect")))
  assert_eq(table.get("type_index"), Some(int_json(0)))
  assert_eq(table.get("table_index"), Some(int_json(0)))
  let reference = json_object(diagnostics[1])
  assert_eq(
    reference.get("code"),
    Some(Json::string("unmodeled_reference_call")),
  )
  assert_eq(reference.get("caller"), Some(int_json(0)))
  assert_eq(reference.get("offset"), Some(int_json(53)))
  assert_eq(reference.get("opcode"), Some(Json::string("call_ref")))
  assert_eq(reference.get("type_index"), Some(int_json(0)))
  assert_eq(reference.get("table_index"), Some(Json::null()))
}

///|
test "all four report formats retain reference only and mixed diagnostics" {
  for
    expression in [b"\xd2\x01\x14\x00", b"\x41\x00\x11\x00\x00\xd2\x01\x14\x00"] {
    let mixed = expression.length() > 4
    let analysis = analysis_of(diagnostic_module(expression, table=mixed))
    let count = if mixed { 2 } else { 1 }
    assert_eq(analysis.graph.diagnostics.length(), count)
    assert_eq(analysis.unresolved_count, if mixed { 1 } else { 0 })
    assert_true(!analysis.graph_complete)
    for
      text in [
        render_graph_warning(analysis.graph),
        render_dead_code(analysis, 5),
        render_retained(analysis, 5),
        render_graph("app.wasm", analysis, "graph.dot"),
        render_html(analysis, "<unsafe>.wasm"),
      ] {
      assert_true(
        text.contains("reference-call target analysis is not implemented."),
      )
      assert_true(text.contains("call_ref"))
      assert_true(text.contains("function 0, offset"))
      assert_true(
        text.contains(
          "do not use them as proof that a function can be removed.",
        ),
      )
      if mixed {
        assert_true(
          text.contains(
            "call_indirect: no static table targets are resolvable.",
          ),
        )
      }
    }
    let json = json_object(
      @json.parse(render_graph("app.wasm", analysis, "graph.json")),
    )
    assert_eq(json.get("graph_complete"), Some(Json::boolean(false)))
    assert_eq(json_array(json.get("diagnostics").unwrap()).length(), count)
    let data = json_object(report_data(analysis, "app.wasm"))
    assert_eq(data.get("diagnostics"), json.get("diagnostics"))
    let html = render_html(analysis, "<unsafe>.wasm")
    assert_true(html.contains("<p class=\"warn\">WARNING:"))
    assert_true(html.contains("graph incomplete; results may be inaccurate"))
    assert_true(!html.contains("<unsafe>"))
    let dot = render_graph("app.wasm", analysis, "graph.dot")
    assert_true(dot.contains("graph [labelloc=\"t\", label=\"WARNING:"))
    assert_true(dot.contains("\\n  function 0, offset"))
  }
}

///|
test "complete exports carry empty diagnostics and a modelling scope" {
  let analysis = analysis_of(tail_module([b"\x00\x12\x01\x0b", b"\x00\x0b"]))
  assert_eq(analysis.graph.diagnostics.length(), 0)
  assert_true(analysis.graph_complete)
  assert_eq(retained_of(analysis.retained, 0), 8)
  let json = json_object(
    @json.parse(render_graph("app.wasm", analysis, "graph.json")),
  )
  assert_eq(json.get("graph_complete"), Some(Json::boolean(true)))
  assert_eq(json.get("diagnostics"), Some(Json::array([])))
  assert_eq(
    json.get("modeling_scope"),
    Some(Json::string(graph_modeling_scope())),
  )
  let html = json_object(report_data(analysis, "app.wasm"))
  assert_eq(html.get("diagnostics"), Some(Json::array([])))
  assert_eq(html.get("graph_complete"), Some(Json::boolean(true)))
  assert_eq(render_graph_warning(analysis.graph), "")
  for
    text in [
      render_html(analysis, "app.wasm"),
      render_graph("app.wasm", analysis, "graph.dot"),
    ] {
    assert_true(!text.contains("WARNING:"))
    assert_true(text.contains("not full Wasm certification"))
  }
}

///|
test "diagnostics are sorted by caller and offset without mutating the graph" {
  let analysis = analysis_of(
    tail_module(
      [b"\x00\xd2\x01\x14\x00\xd2\x01\x14\x00\x0b", b"\x00\xd2\x01\x15\x00\x0b"],
      elements=b"\x09\x05\x01\x03\x00\x01\x01",
    ),
  )
  let original = analysis.graph.diagnostics
  assert_eq(original.length(), 3)
  let graph = {
    ..analysis.graph,
    diagnostics: [original[2], original[1], original[0]],
  }
  let expected = diagnostics_json(analysis.graph)
  assert_eq(diagnostics_json(graph), expected)
  assert_eq(render_graph_warning(graph), render_graph_warning(analysis.graph))
  assert_eq(graph.diagnostics[0].caller, 1)
  assert_eq(graph.diagnostics[1].offset, 46)
}
