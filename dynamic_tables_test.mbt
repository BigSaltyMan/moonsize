///|
fn dynamic_set_fixture() -> Bytes {
  // Two () -> () functions, private table 0, active element with function 1.
  // The indirect call precedes table.set in the same body.
  b"\x00asm\x01\x00\x00\x00\x01\x04\x01\x60\x00\x00" +
  b"\x03\x03\x02\x00\x00\x04\x04\x01\x70\x00\x01" +
  b"\x07\x07\x01\x03run\x00\x00\x09\x07\x01\x00\x41\x00\x0b\x01\x01" +
  b"\x0a\x12\x02\x0d\x00\x41\x00\x11\x00\x00\x41\x00\xd2\x01\x26\x00\x0b\x02\x00\x0b"
}

///|
test "static candidates cannot hide a later runtime table write" {
  let analysis = reference_analysis(dynamic_set_fixture())
  assert_eq(analysis.graph.indirect_sites[0].candidates, [1])
  assert_eq(analysis.unresolved_count, 0)
  assert_true(
    analysis.graph.edges.any(edge => edge.caller == 0 && edge.callee == 1),
  )
  assert_true(!analysis.graph_complete)
}

///|
fn table_u32(value : Int) -> Bytes {
  let bytes : Array[Byte] = []
  let mut rest = value
  while rest >= 128 {
    bytes.push(((rest & 127) | 128).to_byte())
    rest = rest >> 7
  }
  bytes.push(rest.to_byte())
  Bytes::from_array(bytes)
}

///|
fn table_section(id : Int, payload : Bytes) -> Bytes {
  Bytes::from_array([id.to_byte()]) + table_u32(payload.length()) + payload
}

///|
/// Complete module: caller, candidate, and an uncalled writer. Active and
/// passive elements declare the candidate; all fixtures also go through V8 in
/// test-graph-diagnostics.sh. Imports advance function/table spaces separately.
fn table_module(
  writer : Bytes,
  tail? : Bool = false,
  call_table? : Int = 0,
  imported? : Bool = false,
  mixed? : Bool = false,
  reference_global? : Bool = false,
  exported? : Bool = false,
  aliases? : Bool = false,
  explicit? : Bool = false,
  typed? : Bool = false,
  static_targets? : Bool = true,
  same_body? : Bool = false,
) -> Bytes {
  let header = b"\x00asm\x01\x00\x00\x00"
  let ref_type = if typed { b"\x63\x70" } else { b"\x70" }
  let table_type = ref_type + b"\x00\x01"
  let imports = if mixed {
    table_section(
      2,
      (if reference_global {
        b"\x05\x01m\x01g\x03\x63\x70\x00"
      } else {
        b"\x04"
      }) +
      b"\x01m\x01a\x00\x00\x01m\x01t\x01" +
      table_type +
      b"\x01m\x01b\x00\x00\x01m\x01s\x01" +
      table_type,
    )
  } else if imported {
    table_section(2, b"\x01\x01m\x01t\x01" + table_type)
  } else {
    b""
  }
  let base = if mixed { 2 } else { 0 }
  let target = table_u32(base + 1)
  let first_table = if explicit {
    b"\x40\x00" + table_type + b"\xd0\x70\x0b"
  } else {
    table_type
  }
  let table_bytes = table_section(4, b"\x02" + first_table + table_type)
  let table_export = b"\x03tab\x01" + table_u32(call_table)
  let alias_export = b"\x05alias\x01" + table_u32(call_table)
  let exports = table_section(
    7,
    table_u32(
      1 + (if exported { 1 } else { 0 }) + (if aliases { 1 } else { 0 }),
    ) +
    b"\x03run\x00" +
    table_u32(base) +
    (if exported { table_export } else { b"" }) +
    (if aliases { alias_export } else { b"" }),
  )
  let active = b"\x02" +
    table_u32(call_table) +
    b"\x41\x00\x0b\x00\x01" +
    target
  let passive = b"\x01\x00\x01" + target
  let elements = table_section(
    9,
    if static_targets {
      b"\x02" + active + passive
    } else {
      b"\x01" + passive
    },
  )
  let call = b"\x41\x00" +
    (if tail { b"\x13" } else { b"\x11" }) +
    b"\x00" +
    table_u32(call_table)
  let caller = b"\x00" + call + (if same_body { writer } else { b"" }) + b"\x0b"
  let writing = b"\x00" + (if same_body { b"" } else { writer }) + b"\x0b"
  let code = table_section(
    10,
    b"\x03" +
    table_u32(caller.length()) +
    caller +
    b"\x02\x00\x0b" +
    table_u32(writing.length()) +
    writing,
  )
  header +
  table_section(1, b"\x01\x60\x00\x00") +
  imports +
  table_section(3, b"\x03\x00\x00\x00") +
  table_bytes +
  exports +
  elements +
  code
}

///|
fn table_codes(graph : @moonsize.CallGraph) -> Array[String] {
  // Text comparison of public enum variants without relying on internal helpers.
  graph.diagnostics.map(diagnostic => {
    match diagnostic.kind {
      NoStaticTableTargets => "empty"
      UnmodeledReferenceCall => "reference"
      ImportedTableContents => "import"
      ExportedTableContents => "export"
      RuntimeTableMutation => "write"
      UnmodeledTableInitializer => "initializer"
      UnknownTableContents => "unknown"
    }
  })
}

///|
fn assert_table_candidate(
  analysis : @moonsize.Analysis,
  table : Int,
  target : Int,
  caller : Int,
) -> Unit raise {
  let sites = analysis.graph.indirect_sites
  assert_eq(sites.length(), 1)
  assert_eq(sites[0].table_index, table)
  assert_eq(sites[0].type_index, 0)
  assert_eq(sites[0].caller, caller)
  assert_eq(sites[0].candidates, [target])
  assert_eq(analysis.unresolved_count, 0)
  assert_eq(analysis.graph.edges.length(), 1)
  let edge = analysis.graph.edges[0]
  assert_eq(edge.caller, caller)
  assert_eq(edge.callee, target)
  assert_eq(edge.offset, sites[0].offset)
  match edge.kind {
    Indirect => ()
    _ => fail("expected a retained indirect candidate edge")
  }
}

///|
test "private static tables and read-only table instructions remain complete" {
  for reads in [b"", b"\x41\x00\x25\x00\x1a\xfc\x10\x00\x1a"] {
    let analysis = reference_analysis(table_module(reads))
    assert_table_candidate(analysis, 0, 1, 0)
    assert_true(analysis.graph_complete)
    assert_eq(analysis.graph.diagnostics.length(), 0)
  }
}

///|
test "all five runtime writers keep static edges and distinct source positions" {
  for
    (writer, name) in [
      (b"\x41\x00\xd0\x70\x26\x00", "table.set"),
      (b"\x41\x00\x41\x00\x41\x01\xfc\x0c\x01\x00", "table.init"),
      (b"\x41\x00\x41\x00\x41\x01\xfc\x0e\x00\x01", "table.copy"),
      (b"\xd0\x70\x41\x01\xfc\x0f\x00\x1a", "table.grow"),
      (b"\x41\x00\xd0\x70\x41\x01\xfc\x11\x00", "table.fill"),
    ] {
    let analysis = reference_analysis(table_module(writer))
    assert_table_candidate(analysis, 0, 1, 0)
    assert_eq(table_codes(analysis.graph), ["write"])
    assert_true(!analysis.graph_complete)
    let diagnostic = analysis.graph.diagnostics[0]
    assert_eq(diagnostic.caller, 0)
    assert_eq(diagnostic.offset, analysis.graph.indirect_sites[0].offset)
    assert_eq(diagnostic.opcode.name(), "call_indirect")
    assert_eq(diagnostic.type_index, Some(0))
    assert_eq(diagnostic.table_index, Some(0))
    let source = diagnostic.source.unwrap()
    assert_eq(source.caller, Some(2))
    assert_eq(source.opcode.unwrap().name(), name)
    let stat = analysis.stats[2]
    let start = stat.offset + stat.total_size - stat.body_size
    let instructions = match
      @moonsize.decode_instructions(analysis.data, start, stat.body_size) {
      Ok(value) => value
      Err(error) => fail(@moonsize.describe_error(error))
    }
    let actual = instructions.filter(instruction => {
      instruction.opcode.name() == name
    })
    assert_eq(actual.length(), 1)
    assert_eq(source.offset, actual[0].offset)
    assert_true(source.offset > diagnostic.offset)
    assert_true(!analysis.reachable.contains(2)) // Conservative rejection of an uncalled writer.
  }
}

///|
test "copy source and unrelated table writes are not destination mutations" {
  for
    writer in [
      b"\x41\x00\x41\x00\x41\x01\xfc\x0e\x01\x00", b"\x41\x00\xd0\x70\x26\x01", b"\x41\x00\x41\x00\x41\x01\xfc\x0c\x01\x01",
    ] {
    let analysis = reference_analysis(table_module(writer))
    assert_table_candidate(analysis, 0, 1, 0)
    assert_true(analysis.graph_complete)
  }
}

///|
test "ordinary and tail calls see writes later in their own body" {
  for tail in [false, true] {
    let analysis = reference_analysis(
      table_module(b"\x41\x00\xd0\x70\x26\x00", same_body=true, tail~),
    )
    assert_table_candidate(analysis, 0, 1, 0)
    assert_eq(table_codes(analysis.graph), ["write"])
    let diagnostic = analysis.graph.diagnostics[0]
    assert_eq(
      diagnostic.opcode.name(),
      if tail {
        "return_call_indirect"
      } else {
        "call_indirect"
      },
    )
    assert_eq(diagnostic.source.unwrap().caller, Some(0))
    assert_true(diagnostic.source.unwrap().offset > diagnostic.offset)
  }
}

///|
test "imported and exported tables remain incomplete with active elements" {
  let imported = reference_analysis(table_module(b"", imported=true))
  assert_table_candidate(imported, 0, 1, 0)
  assert_eq(table_codes(imported.graph), ["import"])
  let exported = reference_analysis(table_module(b"", exported=true))
  assert_table_candidate(exported, 0, 1, 0)
  assert_eq(table_codes(exported.graph), ["export"])
  for analysis in [imported, exported] {
    assert_true(!analysis.graph_complete)
    let source = analysis.graph.diagnostics[0].source.unwrap()
    assert_eq(source.caller, None)
    assert_true(source.opcode is None)
    assert_true(source.offset < analysis.graph.indirect_sites[0].offset)
  }
}

///|
test "mixed imports use separate complete table and function index spaces" {
  for call_table in [0, 1, 2, 3] {
    let data = table_module(b"", mixed=true, typed=true, call_table~)
    let analysis = reference_analysis(data)
    assert_table_candidate(analysis, call_table, 3, 2)
    assert_eq(analysis.graph_complete, call_table >= 2)
    assert_eq(
      table_codes(analysis.graph),
      if call_table < 2 {
        ["import"]
      } else {
        []
      },
    )
    let section = @moonsize.find_sections(analysis.parsed).imports.unwrap()
    match @moonsize.count_imported_functions(data, section) {
      Ok(count) => assert_eq(count, 2)
      Err(error) => fail(@moonsize.describe_error(error))
    }
  }
}

///|
test "typed global imports cannot shift later table descriptors or function counts" {
  let analysis = reference_analysis(
    table_module(
      b"",
      mixed=true,
      typed=true,
      reference_global=true,
      call_table=2,
    ),
  )
  assert_table_candidate(analysis, 2, 3, 2)
  assert_true(analysis.graph_complete)
}

///|
test "writer provenance includes imported functions and targets the full local table index" {
  let analysis = reference_analysis(
    table_module(
      b"\x41\x00\xd0\x70\x26\x02",
      mixed=true,
      typed=true,
      call_table=2,
    ),
  )
  assert_table_candidate(analysis, 2, 3, 2)
  assert_eq(table_codes(analysis.graph), ["write"])
  let diagnostic = analysis.graph.diagnostics[0]
  assert_eq(diagnostic.source.unwrap().caller, Some(4))
  assert_eq(diagnostic.table_index, Some(2))
}

///|
test "non-null function-reference initializer stays unknown instead of guessing its target" {
  let data = b"\x00asm\x01\x00\x00\x00" +
    table_section(1, b"\x01\x60\x00\x00") +
    table_section(3, b"\x02\x00\x00") +
    table_section(4, b"\x02\x40\x00\x64\x00\x00\x01\xd2\x01\x0b\x70\x00\x01") +
    table_section(7, b"\x01\x03run\x00\x00") +
    table_section(9, b"\x01\x03\x00\x01\x01") +
    table_section(10, b"\x02\x07\x00\x41\x00\x11\x00\x00\x0b\x02\x00\x0b")
  let analysis = reference_analysis(data)
  assert_eq(table_codes(analysis.graph), ["empty", "initializer"])
  assert_eq(analysis.graph.indirect_sites[0].candidates.length(), 0)
  assert_eq(analysis.graph.edges.length(), 0)
  assert_eq(analysis.unresolved_count, 1)
  let section = @moonsize.find_sections(analysis.parsed).tables.unwrap()
  match @moonsize.parse_table_section(data, section) {
    Ok(tables) => {
      assert_eq(tables.length(), 2)
      assert_eq(tables[0].element_type, 0)
      assert_eq(tables[1].element_type, 0x70)
    }
    Err(error) => fail(@moonsize.describe_error(error))
  }
}

///|
test "independent risks accumulate and repeated export aliases do not duplicate a reason" {
  let write = b"\x41\x00\xd0\x70\x26\x00"
  let analysis = reference_analysis(
    table_module(write + write, imported=true, exported=true, aliases=true),
  )
  assert_table_candidate(analysis, 0, 1, 0)
  assert_eq(table_codes(analysis.graph), ["import", "export", "write", "write"])
  assert_eq(analysis.graph.indirect_sites.length(), 1)
  let writers = analysis.graph.diagnostics.filter(d => {
    match d.kind {
      RuntimeTableMutation => true
      _ => false
    }
  })
  assert_eq(writers.length(), 2)
  assert_true(
    writers[0].source.unwrap().offset != writers[1].source.unwrap().offset,
  )
  let warning = @moonsize.render_graph_warning(analysis.graph)
  assert_true(warning.contains("4 analysis gaps"))
  assert_true(warning.contains("table.set at function 2, offset"))
}

///|
test "empty static candidates do not suppress independent dynamic reasons" {
  let analysis = reference_analysis(
    table_module(
      b"\x41\x00\xd0\x70\x26\x00",
      imported=true,
      static_targets=false,
    ),
  )
  assert_eq(analysis.graph.indirect_sites[0].candidates.length(), 0)
  assert_eq(analysis.graph.edges.length(), 0)
  assert_eq(analysis.unresolved_count, 1)
  assert_eq(table_codes(analysis.graph), ["empty", "import", "write"])
}

///|
test "explicit initializer is fully consumed before the second table" {
  for call_table in [0, 1] {
    let data = table_module(b"", explicit=true, typed=true, call_table~)
    let analysis = reference_analysis(data)
    assert_table_candidate(analysis, call_table, 1, 0)
    assert_eq(
      table_codes(analysis.graph),
      if call_table == 0 {
        ["initializer"]
      } else {
        []
      },
    )
    assert_eq(analysis.graph_complete, call_table == 1)
    let section = @moonsize.find_sections(analysis.parsed).tables.unwrap()
    match @moonsize.parse_table_section(data, section) {
      Ok(tables) => {
        assert_eq(tables.length(), 2)
        assert_eq(tables[0].element_type, 0)
        assert_eq(tables[1].element_type, 0)
        assert_eq(tables[0].minimum, 1)
        assert_eq(tables[1].minimum, 1)
      }
      Err(error) => fail(@moonsize.describe_error(error))
    }
  }
}

///|
test "public build parses complete module context and agrees with analyze" {
  for
    data in [
      table_module(b"", imported=true),
      table_module(b"\x41\x00\xd0\x70\x26\x00"),
      table_module(b"", explicit=true),
    ] {
    let analysis = reference_analysis(data)
    match @moonsize.build(data) {
      Ok(graph) => {
        assert_eq(table_codes(graph), table_codes(analysis.graph))
        assert_eq(graph.indirect_sites[0].candidates, [1])
        assert_true(!@moonsize.is_graph_complete(graph))
        assert_eq(
          graph.diagnostics[0].offset,
          analysis.graph.diagnostics[0].offset,
        )
        assert_eq(
          graph.diagnostics[0].source.unwrap().offset,
          analysis.graph.diagnostics[0].source.unwrap().offset,
        )
      }
      Err(error) => fail(@moonsize.describe_error(error))
    }
  }
}

///|
test "table metadata safely consumes multi-byte heap indices and following tables" {
  let mut types = table_u32(129)
  for i = 0; i < 129; i = i + 1 {
    types = types + b"\x60\x00\x00"
  }
  let data = b"\x00asm\x01\x00\x00\x00" +
    table_section(1, types) +
    table_section(4, b"\x02\x63\x80\x01\x01\x01\x02\x70\x00\x01")
  let analysis = reference_analysis(data)
  assert_true(analysis.graph_complete)
  let section = @moonsize.find_sections(analysis.parsed).tables.unwrap()
  match @moonsize.parse_table_section(data, section) {
    Ok(tables) => {
      assert_eq(tables.length(), 2)
      assert_eq(tables[0].minimum, 1)
      assert_eq(tables[0].maximum, Some(2))
      assert_eq(tables[1].minimum, 1)
      assert_eq(tables[1].maximum, None)
    }
    Err(error) => fail(@moonsize.describe_error(error))
  }
}

///|
test "unsafe table encodings return input errors through both graph entrances" {
  for
    (payload, offset) in [
      (b"\x01\x40\x01\x70\x00\x01\xd0\x70\x0b", 12),
      (b"\x01\x7f\x00\x01", 11),
      (b"\x01\x70\x04\x01", 12), // Unsupported table64, not declared invalid Wasm.
    ] {
    let data = b"\x00asm\x01\x00\x00\x00" + table_section(4, payload)
    let parsed = comparison_module(data)
    let section = @moonsize.find_sections(parsed).tables.unwrap()
    for
      result in [
        @moonsize.parse_table_section(data, section).map(_ => ()),
        @moonsize.analyze(data, parsed).map(_ => ()),
        @moonsize.build(data).map(_ => ()),
      ] {
      match result {
        Err(@moonsize.WasmError::InvalidTableEncoding(at, _)) =>
          assert_eq(at, offset)
        _ => fail("expected explicit unsupported/malformed table error")
      }
    }
  }
}

///|
test "truncated initializers and reference types cannot consume following sections" {
  for
    (payload, offset) in [
      (b"\x01\x63\x80", 12), // Signed LEB errors point to the immediate's start.
      (b"\x01\x40\x00\x70\x00\x01\xd0", 17),
      (b"\x01\x40\x00\x70\x00\x01\xd0\x70", 18),
    ] {
    let data = b"\x00asm\x01\x00\x00\x00" +
      table_section(4, payload) +
      b"\x00\x02\x01x"
    let parsed = comparison_module(data)
    match @moonsize.analyze(data, parsed) {
      Err(@moonsize.WasmError::UnexpectedEnd(at, 1)) => assert_eq(at, offset)
      _ => fail("expected initializer/reference truncation at table boundary")
    }
  }
}

///|
test "a missing table never implies a known private table context" {
  // Semantically invalid index, kept separate from independently valid fixtures.
  // Full index validation is out of scope, so record the missing context.
  let analysis = reference_analysis(
    table_module(b"", call_table=7, static_targets=false),
  )
  assert_eq(table_codes(analysis.graph), ["empty", "unknown"])
  assert_eq(analysis.unresolved_count, 1)
  assert_true(!analysis.graph_complete)
}
