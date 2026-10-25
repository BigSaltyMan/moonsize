///|
fn summary_test_module() -> Bytes {
  let mut names = b"\x03"
  for (index, name) in [(1, "z/root\"\n雪"), (2, "alpha/leaf"), (3, "z/dead")] {
    let bytes = @utf8.encode(name)
    names += search_test_leb(index) + search_test_leb(bytes.length()) + bytes
  }
  b"\x00asm\x01\x00\x00\x00\x01\x04\x01\x60\x00\x00\x02\x07\x01\x01m\x01f\x00\x00" +
  search_test_section(3, b"\x04\x00\x00\x00\x00") +
  search_test_section(7, b"\x02\x04host\x00\x00\x03run\x00\x01") +
  search_test_section(
    10, b"\x04\x04\x00\x10\x02\x0b\x82\x00\x00\x0b\x03\x00\x01\x0b\x02\x00\x0b",
  ) +
  search_test_section(0, b"\x04same\xaa") +
  search_test_section(0, b"\x04same\xbb") +
  search_test_section(0, b"\x04name" + search_test_section(1, names))
}

///|
fn summary_test_dynamic() -> Bytes {
  // Existing graph fixture, adding a table export: static candidates coexist
  // with two independently explained risks, not two unresolved call sites.
  b"\x00asm\x01\x00\x00\x00\x01\x04\x01\x60\x00\x00" +
  b"\x03\x03\x02\x00\x00\x04\x04\x01\x70\x00\x01" +
  b"\x07\x0d\x02\x03run\x00\x00\x03tbl\x01\x00\x09\x07\x01\x00\x41\x00\x0b\x01\x01" +
  b"\x0a\x12\x02\x0d\x00\x41\x00\x11\x00\x00\x41\x00\xd2\x01\x26\x00\x0b\x02\x00\x0b"
}

///|
fn summary_test_object(analysis : Analysis) -> Map[String, Json] raise {
  json_object(@json.parse(render_summary_json(analysis)))
}

///|
test "summary-json: complete local definitions, module and byte ledgers, special names and nullable retained" {
  let data = summary_test_module()
  let analysis = analysis_of_module(data)
  let root = summary_test_object(analysis)
  assert_eq(root.get("format"), Some(Json::string("moonsize-summary")))
  assert_eq(root.get("schema_version"), Some(int_json(1)))
  let input = json_object(root.get("input").unwrap())
  assert_eq(input.get("file_size"), Some(int_json(data.length())))
  assert_eq(input.get("sha256"), Some(Json::string(experiment_sha256(data))))
  assert_eq(input.get("wasm_version"), Some(int_json(1)))
  let s = json_object(root.get("summary").unwrap())
  for
    (key, value) in [
      ("wasm_header_bytes", 8),
      ("section_count", 8),
      ("section_bytes", 116),
      ("defined_function_count", 4),
      ("defined_body_bytes", 11),
      ("defined_prefix_bytes", 5),
      ("defined_encoded_bytes", 16),
      ("reachable_defined_count", 2),
      ("unreachable_defined_count", 2),
      ("reachable_encoded_bytes", 9),
      ("unreachable_encoded_bytes", 7),
      ("module_count", 3),
    ] {
    assert_eq(s.get(key), Some(int_json(value)))
  }
  assert_eq(data.length(), 124)
  let functions = json_array(root.get("functions").unwrap())
  assert_eq(functions.length(), 4)
  for ordinal, stat in analysis.stats {
    let row = json_object(functions[ordinal])
    assert_eq(row.get("index"), Some(int_json(stat.index)))
    assert_eq(row.get("body_size"), Some(int_json(stat.body_size)))
    assert_eq(
      row.get("prefix_size"),
      Some(int_json(stat.total_size - stat.body_size)),
    )
    assert_eq(row.get("offset"), Some(int_json(stat.offset)))
    assert_eq(row.get("model_reachable"), Some(Json::boolean(stat.index <= 2)))
    assert_eq(row.get("model_root"), Some(Json::boolean(stat.index == 1)))
    assert_eq(row.get("model_indirect_candidate"), Some(Json::boolean(false)))
  }
  let first = json_object(functions[0])
  assert_eq(first.get("name"), Some(Json::string("z/root\"\n雪")))
  assert_eq(first.get("raw_name"), first.get("name"))
  let retained = json_object(first.get("model_retained").unwrap())
  assert_eq(retained.get("own_encoded_bytes"), Some(int_json(5)))
  assert_eq(retained.get("dominated_encoded_bytes"), Some(int_json(9)))
  assert_eq(retained.get("other_dominated_function_count"), Some(int_json(1)))
  let child = json_object(
    json_object(functions[1]).get("model_retained").unwrap(),
  )
  assert_eq(child.get("dominated_encoded_bytes"), Some(int_json(4)))
  assert_eq(child.get("other_dominated_function_count"), Some(int_json(0)))
  assert_eq(json_object(functions[2]).get("model_retained"), Some(Json::null()))
  assert_eq(json_object(functions[3]).get("raw_name"), Some(Json::null()))
  let modules = json_array(root.get("modules").unwrap())
  for
    (ordinal, label, indices, body, prefix, encoded) in [
      (0, "(unnamed)", [4], 2, 1, 3),
      (1, "alpha", [2], 2, 2, 4),
      (2, "z", [1, 3], 7, 2, 9),
    ] {
    let row = json_object(modules[ordinal])
    assert_eq(row.get("module_name"), Some(Json::string(label)))
    assert_eq(
      row.get("function_indices"),
      Some(Json::array(indices.map(fn(i) { int_json(i) }))),
    )
    assert_eq(row.get("function_count"), Some(int_json(indices.length())))
    assert_eq(row.get("body_bytes"), Some(int_json(body)))
    assert_eq(row.get("prefix_bytes"), Some(int_json(prefix)))
    assert_eq(row.get("encoded_bytes"), Some(int_json(encoded)))
  }
  let model = json_object(root.get("model").unwrap())
  assert_eq(
    model.get("root_indices"),
    Some(Json::array([int_json(0), int_json(1)])),
  )
  assert_eq(model.get("graph_complete"), Some(Json::boolean(true)))
  assert_eq(model.get("diagnostic_count"), Some(int_json(0)))
  let sections = json_array(root.get("sections").unwrap())
  for ordinal, section in analysis.parsed.sections {
    let row = json_object(sections[ordinal])
    assert_eq(row.get("ordinal"), Some(int_json(ordinal)))
    assert_eq(
      row.get("section_header_bytes"),
      Some(int_json(section.total_size - section.payload_size)),
    )
    assert_eq(
      row.get("custom_name_display"),
      Some(path_optional_string(section.custom_name)),
    )
  }
  // Absence in an existing result stays absent, even for a reachable function.
  let sparse : Analysis = { ..analysis, retained: [], }
  let sparse_functions = json_array(
    summary_test_object(sparse).get("functions").unwrap(),
  )
  assert_eq(
    json_object(sparse_functions[0]).get("model_retained"),
    Some(Json::null()),
  )
}

///|
test "summary-json: empty module, deterministic sorting, complete types and CLI contract" {
  let empty = analysis_of_module(b"\x00asm\x01\x00\x00\x00")
  let json = render_summary_json(empty)
  assert_eq(json, render_summary_json(empty))
  let root = json_object(@json.parse(json))
  for key in ["sections", "functions", "modules"] {
    assert_eq(root.get(key), Some(Json::array([])))
  }
  let s = json_object(root.get("summary").unwrap())
  assert_eq(s.get("wasm_header_bytes"), Some(int_json(8)))
  for
    key in [
      "section_bytes", "defined_function_count", "defined_encoded_bytes", "reachable_encoded_bytes",
      "unreachable_encoded_bytes",
    ] {
    assert_eq(s.get(key), Some(int_json(0)))
  }
  assert_true(root.get("data") is None)
  assert_true(root.get("gzip") is None)
  assert_true(!json.contains("\"gzip_size\""))
  let analysis = analysis_of_module(summary_test_module())
  let text = render_summary_json(analysis)
  assert_eq(text, render_summary_json(analysis))
  // Rendering sorts copies, not the caller's arrays or graph evidence.
  let shuffled : Analysis = {
    ..analysis,
    stats: [
      analysis.stats[3],
      analysis.stats[1],
      analysis.stats[0],
      analysis.stats[2],
    ],
  }
  assert_eq(text, render_summary_json(shuffled))
  assert_eq(shuffled.stats[0].index, 4)
  assert_eq(Options::default("x").summary_json, None)
  match
    parse_options([
      "moonsize", "missing.wasm", "--summary-json", "new.json", "--top", "1", "--retained",
      "--dead-code", "--strict", "--max-size", "100KB",
    ]) {
    Ok(options) => {
      assert_eq(options.summary_json, Some("new.json"))
      assert_eq(options.top, 1)
    }
    Err(error) => fail(error)
  }
  for
    args in [
      ["--summary-json"],
      ["--summary-json", ""],
      ["--summary-json", "  "],
      ["--summary-json", "new.txt"],
      ["--summary-json", "--strict"],
    ] {
    assert_true(parse_options(["moonsize", "missing.wasm"] + args) is Err(_))
  }
  for
    args in [
      ["--compress"],
      ["--baseline", "before.wasm"],
      ["--html", "x.html"],
      ["--call-graph", "x.json"],
      ["--data-segments"],
      ["--data-json", "x.json"],
      ["--budget-json", "x.json"],
      ["--experiment", "x.json"],
      ["--instructions", "1"],
      ["--baseline-instructions", "1"],
      ["--callers", "1"],
      ["--why-index", "1"],
      ["--generics"],
      ["--find-functions", "x"],
      ["--imports"],
    ] {
    assert_true(
      parse_options(
        ["moonsize", "missing.wasm", "--summary-json", "new.json"] + args,
      )
      is Err(_),
    )
  }
}

///|
test "summary-json: static candidates retain dynamic and exported table diagnostics with full nullable provenance" {
  let analysis = analysis_of_module(summary_test_dynamic())
  let root = summary_test_object(analysis)
  let model = json_object(root.get("model").unwrap())
  assert_eq(model.get("graph_complete"), Some(Json::boolean(false)))
  assert_eq(model.get("unresolved_count"), Some(int_json(0)))
  assert_eq(model.get("diagnostic_count"), Some(int_json(2)))
  assert_eq(analysis.graph.indirect_sites[0].candidates, [1])
  let rows = json_array(model.get("diagnostics").unwrap())
  let original = json_array(diagnostics_json(analysis.graph))
  assert_eq(rows.length(), 2)
  for i, row in rows {
    let fields = json_object(row)
    assert_eq(fields.get("caller"), Some(int_json(0)))
    assert_eq(fields.get("offset"), Some(int_json(56)))
    assert_eq(fields.get("opcode"), Some(Json::string("call_indirect")))
    assert_eq(fields.get("type_index"), Some(int_json(0)))
    assert_eq(fields.get("table_index"), Some(int_json(0)))
    assert_true(fields.get("reason") is Some(String(_)))
    let source = json_object(fields.get("source").unwrap())
    match fields.get("code") {
      Some(String("runtime_table_mutation")) => {
        assert_eq(source.get("caller"), Some(int_json(0)))
        assert_eq(source.get("offset"), Some(int_json(63)))
        assert_eq(source.get("opcode"), Some(Json::string("table.set")))
      }
      Some(String("exported_table_contents")) => {
        assert_eq(source.get("caller"), Some(Json::null()))
        assert_eq(source.get("offset"), Some(int_json(38)))
        assert_eq(source.get("opcode"), Some(Json::null()))
      }
      _ => fail("expected precise dynamic/exported table reason")
    }
    let old = json_object(original[i])
    for
      key in [
        "code", "caller", "offset", "opcode", "type_index", "table_index", "source",
      ] {
      assert_eq(fields.get(key), old.get(key))
    }
  }
  let functions = json_array(root.get("functions").unwrap())
  assert_eq(
    json_object(functions[1]).get("model_indirect_candidate"),
    Some(Json::boolean(true)),
  )
  assert_eq(render_summary_json(analysis), render_summary_json(analysis))
}
