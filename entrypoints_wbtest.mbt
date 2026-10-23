///|
fn entry_test_section(
  out : Array[Byte],
  id : Int,
  payload : Array[Byte],
) -> Unit raise {
  assert_true(payload.length() < 128)
  out.push(id.to_byte())
  out.push(payload.length().to_byte())
  for byte in payload {
    out.push(byte)
  }
}

///|
/// Reuse the existing full-module body encoder; replace only exports/start.
fn entry_fixture(
  bodies : Array[Bytes],
  exports : Array[Export],
  imported? : Bool = false,
  start? : Int,
  elements? : Bytes = b"",
) -> Bytes raise {
  let base = tail_module(bodies, imported~, elements~)
  let parsed = parse_module(base).unwrap()
  let out : Array[Byte] = [0, 97, 115, 109, 1, 0, 0, 0]
  for section in parsed.sections {
    if same_kind(section.kind, Export) {
      entry_test_section(out, 5, [1, 0, 1]) // One memory for the other export.
      let payload : Array[Byte] = [exports.length().to_byte()]
      for item in exports {
        let name = @utf8.encode(item.name)
        payload.push(name.length().to_byte())
        for byte in name {
          payload.push(byte)
        }
        payload.push(item.kind.to_byte())
        payload.push(item.index.to_byte())
      }
      entry_test_section(out, 7, payload)
      if start is Some(index) {
        entry_test_section(out, 8, [index.to_byte()])
      }
    } else {
      for i in section.offset..<(section.offset + section.total_size) {
        out.push(base[i])
      }
    }
  }
  Bytes::from_array(out)
}

///|
fn entry_shared_fixture(start? : Int = 5) -> Bytes raise {
  entry_fixture(
    [
      b"\x00\x10\x03\x10\x04\x10\x00\xd2\x05\x14\x00\x0b", b"\x00\x10\x03\x0b", b"\x00\x10\x03\x0b",
      b"\x00\x0b", b"\x00\x10\x04\x0b", b"\x00\x0b",
    ],
    [
      { name: "A", kind: 0, index: 1, },
      { name: "alias\"\\\n雪", kind: 0, index: 1, },
      { name: "B", kind: 0, index: 2, },
      { name: "memory", kind: 2, index: 0, },
    ],
    imported=true,
    start~,
    // Passive #5 and declarative #4 are both conservative roots.
    elements=b"\x09\x09\x02\x01\x00\x01\x05\x03\x00\x01\x04",
  )
}

///|
fn entry_inspected(data : Bytes) -> EntrypointsReport raise {
  match inspect_entrypoints(data) {
    Ok(report) => report
    Err(error) => fail(describe_entrypoints_error(error))
  }
}

///|
fn entry_ledger(report : EntrypointsReport) -> Unit raise {
  let l = report.ledger
  assert_eq(
    l.total_local_bytes,
    l.export_union_bytes + l.not_export_reachable_bytes,
  )
  assert_eq(
    l.export_union_bytes,
    l.exclusive_model_bytes + l.shared_model_bytes,
  )
  let mut exclusive = 0
  for group in report.entrypoints {
    assert_eq(
      group.reachable_model_bytes,
      group.exclusive_model_bytes + group.shared_model_bytes,
    )
    let mut size = 0
    for index in group.reachable {
      size += report.functions[index].node.encoded_size.unwrap_or(0)
    }
    assert_eq(size, group.reachable_model_bytes)
    exclusive += group.exclusive_model_bytes
  }
  assert_eq(exclusive, l.exclusive_model_bytes)
}

///|
test "entrypoints: aliases, cycles, shared ownership, diagnostics and complete JSON" {
  let report = entry_inspected(entry_shared_fixture())
  entry_ledger(report)
  assert_eq(report.export_name_count, 3)
  assert_eq(report.entrypoint_count, 2)
  assert_eq(report.other_exports.length(), 1)
  assert_eq(report.entrypoints.map(fn(g) { g.index }), [1, 2])
  let a = report.entrypoints[0]
  assert_eq(a.aliases, ["A", "alias\"\\\n雪"])
  assert_eq(a.reachable, [0, 1, 3, 4, 5])
  assert_eq(a.local_function_count, 4)
  assert_eq(a.imported_function_count, 1)
  assert_eq(a.reachable_model_bytes, 26)
  assert_eq(a.exclusive_model_bytes, 13)
  assert_eq(a.shared_model_bytes, 13)
  assert_eq(report.entrypoints[1].reachable_model_bytes, 10)
  assert_eq(report.entrypoints[1].exclusive_model_bytes, 5)
  assert_eq(report.entrypoints[1].shared_model_bytes, 5)
  assert_eq(report.ledger.total_local_bytes, 34)
  assert_eq(report.ledger.export_union_bytes, 31)
  assert_eq(report.ledger.not_export_reachable_bytes, 3)
  assert_eq(report.shared_local_functions, [3, 5, 4])
  assert_eq(report.functions[0].node.encoded_size, None)
  assert_true(report.functions[0].node.imported)
  assert_eq(report.functions[3].entrypoints, [1, 2])
  assert_eq(report.functions[4].entrypoints, [1])
  assert_true(report.functions[4].other_root_reachable)
  assert_eq(report.other_roots.map(fn(r) { r.index }), [4, 5])
  assert_eq(report.other_roots[1].reasons.length(), 2) // Start and passive element.
  assert_eq(report.other_root_reachable, [4, 5])
  assert_false(report.graph_complete)
  assert_eq(report.diagnostics.length(), 1)
  assert_eq(report.diagnostics[0].opcode.name(), "call_ref")
  let text = render_entrypoints(report, 1)
  assert_true(text.contains("ENTRYPOINT GROUPS: showing 1 of 2"))
  assert_true(text.contains("SHARED LOCAL FUNCTIONS: showing 1 of 3"))
  assert_true(text.contains("alias\\\"\\\\\\n雪"))
  assert_true(
    text.contains(
      "34 B = function-export union 31 B + not export-reachable 3 B",
    ),
  )
  let json = render_entrypoints_json(report)
  assert_true(json.contains("moonsize-entrypoints"))
  assert_true(json.contains("\"encoded_size\": null"))
  assert_true(json.contains("\"B\""))
  assert_true(json.contains("call_ref"))
}

///|
test "entrypoints: exported other roots, imported entries, no entries and deterministic ties" {
  let other = entry_inspected(entry_shared_fixture(start=1))
  entry_ledger(other)
  assert_eq(other.entrypoints[0].exclusive_model_bytes, 0)
  assert_true(other.functions[1].other_root_reachable)
  let imported = entry_inspected(
    entry_fixture(
      [b"\x00\x0b"],
      [
        { name: "host", kind: 0, index: 0, },
        { name: "local", kind: 0, index: 1, },
      ],
      imported=true,
    ),
  )
  entry_ledger(imported)
  assert_eq(imported.entrypoints[1].index, 0)
  assert_eq(imported.entrypoints[1].local_function_count, 0)
  assert_eq(imported.entrypoints[1].imported_function_count, 1)
  assert_eq(imported.entrypoints[1].reachable_model_bytes, 0)
  assert_eq(imported.functions[0].node.encoded_size, None)
  let empty = entry_inspected(
    entry_fixture(
      [b"\x00\x0b"],
      [{ name: "memory", kind: 2, index: 0, }],
      start=0,
      elements=b"\x09\x05\x01\x03\x00\x01\x00",
    ),
  )
  entry_ledger(empty)
  assert_eq(empty.entrypoint_count, 0)
  assert_eq(empty.ledger.not_export_reachable_bytes, 3)
  assert_eq(empty.shared_local_functions.length(), 0)
  assert_true(empty.functions[0].other_root_reachable)
  assert_true(render_entrypoints(empty, 10).contains("No function exports"))
  let tied = entry_inspected(
    entry_fixture([b"\x00\x0b", b"\x00\x0b"], [
      { name: "second", kind: 0, index: 1, },
      { name: "first", kind: 0, index: 0, },
    ]),
  )
  assert_eq(tied.entrypoints.map(fn(g) { g.index }), [0, 1])
}

///|
test "entrypoints: actual index-error evidence and independent CLI grammar" {
  let bad_export = entry_fixture([b"\x00\x0b"], [
    { name: "bad", kind: 0, index: 8, },
  ])
  assert_true(
    inspect_entrypoints(bad_export)
    is Err(InvalidEntrypointExport("bad", 0, 8, 1)),
  )
  assert_true(
    inspect_entrypoints(entry_fixture([b"\x00\x0b"], [], start=8))
    is Err(InvalidEntrypointsRoot("start section", 8, 1)),
  )
  assert_true(
    inspect_entrypoints(
      entry_fixture([b"\x00\x0b"], [], elements=b"\x09\x05\x01\x03\x00\x01\x08"),
    )
    is Err(InvalidEntrypointsRoot("element segment 0", 8, 1)),
  )
  let bad_edge = entry_fixture([b"\x00\x10\x08\x0b"], [])
  match inspect_entrypoints(bad_edge) {
    Err(InvalidEntrypointsEdge(0, 8, offset)) =>
      assert_eq(bad_edge[offset], b'\x10')
    _ => fail("expected actual bad edge evidence")
  }
  assert_true(inspect_entrypoints(b"bad") is Err(EntrypointsInputError(_)))
  let options = parse_options([
    "moonsize", "missing.wasm", "--entrypoints-json", "new.json", "--top", "0", "--strict",
  ]).unwrap()
  assert_true(options.entrypoints)
  assert_true(options.strict)
  assert_eq(options.entrypoints_json, Some("new.json"))
  assert_eq(options.top, 0)
  assert_false(Options::default("x.wasm").entrypoints)
  assert_eq(Options::default("x.wasm").entrypoints_json, None)
  for
    args in [
      ["--entrypoints-json"],
      ["--entrypoints-json", "new.txt"],
      ["--entrypoints", "--generics"],
      ["--entrypoints", "--html", "new.html"],
      ["--entrypoints", "--callers", "0"],
      ["--entrypoints", "--budget", "b.json"],
    ] {
    assert_true(parse_options(["moonsize", "missing.wasm"] + args) is Err(_))
  }
}
