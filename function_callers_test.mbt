///|
// Reuse the existing binary fixture builder; only this new test file is run locally.
fn callers_fixture() -> PathFixture {
  path_fixture(
    [
      b"\x00\x10\x00\xd2\x00\x1a\x41\x00\x11\x00\x00\x10\x00\x0b", b"\x00\x12\x00\x0b",
      b"\x00\xd2\x00\x14\x00\x41\x00\x13\x00\x00\x0b", b"\x00\x10\x04\x0b", b"\x00\x0b",
    ],
    imported=1,
    exports=[("entry", 5)],
    elements=[(0, [0])],
    names=[(0, "target\"\\\n雪"), (1, "same"), (2, "same")],
  )
}

///|
fn query_callers(
  fixture : PathFixture,
  index : Int,
) -> @moonsize.FunctionCallersReport raise {
  match @moonsize.function_callers(fixture.data, index) {
    Ok(report) => report
    Err(error) => fail(@moonsize.describe_function_callers_error(error))
  }
}

///|
test "callers: positions, identity, types and module gaps survive grouping and Top" {
  let fixture = callers_fixture()
  let report = query_callers(fixture, 0)
  assert_true(report.target.imported)
  assert_eq(report.target.encoded_size, None)
  assert_eq(report.file_size, fixture.data.length())
  assert_eq(report.sha256.length(), 64)
  assert_eq(report.caller_count, 3)
  assert_eq(report.source_count, 7)
  assert_eq(report.callers.map(fn(g) { g.caller.index }), [1, 2, 3])
  assert_eq(report.callers[0].caller.name, report.callers[1].caller.name)
  assert_eq(
    report.callers[0].sources.map(fn(s) { s.offset }),
    [1, 3, 8, 11].map(fn(n) { fixture.bodies[0] + n }),
  )
  assert_eq(report.callers[0].sources.map(fn(s) { s.opcode.name() }), [
    "call", "ref.func", "call_indirect", "call",
  ])
  assert_eq(report.callers[0].sources[2].type_index, Some(0))
  assert_eq(report.callers[0].sources[2].table_index, Some(0))
  assert_eq(report.callers[1].sources[0].opcode.name(), "return_call")
  assert_eq(report.callers[2].sources[1].opcode.name(), "return_call_indirect")
  assert_false(report.graph_complete)
  assert_eq(report.diagnostics.length(), 1)
  assert_eq(report.diagnostics[0].opcode.name(), "call_ref")
  assert_eq(report.diagnostics[0].offset, fixture.bodies[2] + 3)
  let text = @moonsize.render_function_callers(report, 1)
  assert_true(text.contains("Showing 1 of 3 caller groups"))
  assert_true(text.contains("source instructions: 7"))
  assert_true(text.contains("indirect candidate"))
  assert_false(text.contains("Caller #2"))
  let json = @moonsize.render_function_callers_json(report)
  assert_true(json.contains("moonsize-function-callers"))
  assert_true(json.contains("return_call_indirect"))
  assert_true(json.contains("\"encoded_size\": null"))
  assert_true(json.contains("\\n"))
  assert_true(report.modeling_scope.contains("unreachable functions"))
}

///|
test "callers: empty roots, self references, bad targets and inputs" {
  let fixture = callers_fixture()
  let empty = query_callers(fixture, 5)
  assert_eq(empty.caller_count, 0)
  assert_eq(empty.source_count, 0)
  let text = @moonsize.render_function_callers(empty, 10)
  assert_true(
    text.contains(
      "No incoming instruction references recorded in the current model.",
    ),
  )
  assert_true(
    text.contains("This does not prove the function is unused or removable."),
  )
  assert_eq(empty.diagnostics.length(), 1) // Module gap does not invent a row for #5.
  let self = query_callers(fixture, 4)
  assert_eq(self.caller_count, 1)
  assert_eq(self.callers[0].sources[0].caller, 4)
  assert_eq(self.callers[0].sources[0].callee, 4)
  for index in [-1, 6, 2147483647] {
    match @moonsize.function_callers(fixture.data, index) {
      Err(InvalidCallersTarget(actual, count)) => {
        assert_eq(actual, index)
        assert_eq(count, 6)
      }
      _ => fail("invalid target accepted")
    }
  }
  match @moonsize.function_callers(b"bad", 0) {
    Err(CallersInputError(_)) => ()
    _ => fail("bad input accepted")
  }
}

///|
test "callers: CLI accepts only Top, JSON and strict with full-range indices" {
  let options = @moonsize.parse_options([
    "moonsize", "missing.wasm", "--callers", "2147483647", "--top", "0", "--callers-json",
    "new.json", "--strict",
  ]).unwrap()
  assert_eq(options.callers_index, Some(2147483647))
  assert_eq(options.top, 0)
  assert_eq(options.callers_json, Some("new.json"))
  assert_true(options.strict)
  assert_eq(@moonsize.Options::default("app.wasm").callers_index, None)
  assert_eq(@moonsize.Options::default("app.wasm").callers_json, None)
  for
    args in [
      ["--callers"],
      ["--callers", "-1"],
      ["--callers", "1.0"],
      ["--callers", "2147483648"],
      ["--callers-json", "new.json"],
      ["--callers", "0", "--callers-json", "old.txt"],
      ["--callers", "0", "--callers-json", ""],
    ] {
    assert_true(
      @moonsize.parse_options(["moonsize", "missing.wasm"] + args) is Err(_),
    )
  }
  for
    conflicting in [
      ["--html", "new.html"],
      ["--call-graph", "new.dot"],
      ["--retained"],
      ["--dead-code"],
      ["--compress"],
      ["--baseline", "before.wasm"],
      ["--max-size", "1KB"],
      ["--why-index", "0"],
      ["--why-root", "0"],
      ["--why-json", "why.json"],
      ["--data-segments"],
      ["--data-json", "data.json"],
      ["--diff-data"],
      ["--diff-functions"],
      ["--experiment", "new.json"],
      ["--experiment-context", "context.json"],
      ["--budget", "budget.json"],
      ["--budget-json", "budget.json"],
      ["--budget-md", "budget.md"],
    ] {
    assert_true(
      @moonsize.parse_options(
        ["moonsize", "missing.wasm", "--callers", "0"] + conflicting,
      )
      is Err(_),
    )
  }
}
