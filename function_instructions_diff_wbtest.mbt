///|
fn instruction_diff_test_compare(
  before : Bytes,
  bi : Int,
  after : Bytes,
  ci : Int,
) -> FunctionInstructionsComparison raise {
  match compare_function_instructions(before, bi, after, ci) {
    Ok(report) => report
    Err(error) => fail(describe_function_instructions_comparison_error(error))
  }
}

///|
fn instruction_diff_test_ledger(
  r : FunctionInstructionsComparison,
) -> Unit raise {
  for side in [r.baseline, r.current] {
    assert_eq(side.entry.size, side.prefix.size + side.body.size)
    assert_eq(
      side.body.size,
      side.locals_encoding.size + side.instruction_bytes,
    )
    let mut bytes = 0
    for instruction in side.instructions {
      bytes += instruction.encoded_size
    }
    assert_eq(side.instruction_bytes, bytes)
  }
  let d = r.delta
  assert_eq(d.entry_bytes, r.current.entry.size - r.baseline.entry.size)
  assert_eq(d.entry_bytes, d.prefix_bytes + d.body_bytes)
  assert_eq(d.body_bytes, d.locals_bytes + d.instruction_bytes)
  let mut bytes = 0
  let mut count = 0
  for row in r.opcodes {
    assert_eq(row.count_delta, row.current_count - row.baseline_count)
    assert_eq(
      row.encoded_bytes_delta,
      row.current_encoded_bytes - row.baseline_encoded_bytes,
    )
    bytes += row.encoded_bytes_delta
    count += row.count_delta
  }
  assert_eq(bytes, d.instruction_bytes)
  assert_eq(count, d.instruction_count)
}

///|
test "function-instructions-diff: explicit different targets, real prefixes, locals, opcode union and signed ledgers" {
  let before = instructions_test_module(
    b"\x00\x41\x00\x1a\x01\x0b",
    b"\x00\x0b",
    named=true,
  )
  let after = instructions_test_module(
    b"\x00\x0b", b"\x01\x02\x7f\x41\x80\x01\x1a\x41\x01\x1a\x0b",
  )
  let r = instruction_diff_test_compare(before, 1, after, 2)
  instruction_diff_test_ledger(r)
  assert_eq(r.baseline.index, 1)
  assert_eq(r.current.index, 2)
  assert_eq(r.baseline.raw_name, Some("target\"<&"))
  assert_eq(r.current.raw_name, None)
  assert_eq(r.baseline.sha256, experiment_sha256(before))
  assert_eq(r.current.sha256, experiment_sha256(after))
  assert_eq(r.baseline.entry.size, 8)
  assert_eq(r.current.entry.size, 12)
  assert_eq(r.baseline.prefix.size, 2)
  assert_eq(r.current.prefix.size, 1)
  assert_eq(r.delta.entry_bytes, 4)
  assert_eq(r.delta.prefix_bytes, -1)
  assert_eq(r.delta.body_bytes, 5)
  assert_eq(r.delta.locals_bytes, 2)
  assert_eq(r.delta.instruction_bytes, 3)
  assert_eq(r.delta.instruction_count, 1)
  assert_eq(r.opcodes.map(fn(row) { row.mnemonic }), [
    "i32.const", "drop", "nop", "end",
  ])
  assert_eq(r.opcodes.map(fn(row) { row.count_delta }), [1, 1, -1, 0])
  assert_eq(r.opcodes.map(fn(row) { row.encoded_bytes_delta }), [3, 1, -1, 0])
  let reverse = instruction_diff_test_compare(after, 2, before, 1)
  instruction_diff_test_ledger(reverse)
  assert_eq(reverse.delta.entry_bytes, -4)
  assert_eq(reverse.delta.prefix_bytes, 1)
  assert_eq(reverse.delta.instruction_count, -1)
  assert_eq(Options::default("x").baseline_instructions_index, None)
  match
    parse_options([
      "moonsize", "after.wasm", "--instructions", "2", "--baseline", "before.wasm",
      "--baseline-instructions", "1", "--instructions-json", "new.json", "--top",
      "1",
    ]) {
    Ok(options) => {
      assert_eq(options.instructions_index, Some(2))
      assert_eq(options.baseline_instructions_index, Some(1))
    }
    Err(error) => fail(error)
  }
  for
    args in [
      ["--baseline-instructions"],
      ["--baseline-instructions", "-1"],
      ["--baseline-instructions", "x"],
      ["--baseline-instructions", "2147483648"],
      ["--baseline-instructions", "1"],
      ["--instructions", "2", "--baseline-instructions", "1"],
      ["--instructions", "2", "--baseline", "before.wasm"],
      ["--instructions", "2", "--baseline", "", "--baseline-instructions", "1"],
      [
        "--instructions", "2", "--baseline", "before.wasm", "--baseline-instructions",
        "1", "--strict",
      ],
      [
        "--instructions", "2", "--baseline", "before.wasm", "--baseline-instructions",
        "1", "--html", "new.html",
      ],
      ["--find-functions", "x", "--baseline-instructions", "1"],
    ] {
    assert_true(parse_options(["moonsize", "missing.wasm"] + args) is Err(_))
  }
}

///|
test "function-instructions-diff: widths, zero statistics with different sequences, extension keys, Top and JSON objects" {
  let narrow = instructions_test_module(b"\x00\x41\x00\x1a\x0b", b"\x00\x0b")
  let wide = instructions_test_module(b"\x00\x41\x80\x01\x1a\x0b", b"\x00\x0b")
  let widths = instruction_diff_test_compare(narrow, 1, wide, 1)
  instruction_diff_test_ledger(widths)
  assert_eq(widths.delta.instruction_count, 0)
  assert_eq(widths.opcodes[0].mnemonic, "i32.const")
  assert_eq(widths.opcodes[0].count_delta, 0)
  assert_eq(widths.opcodes[0].encoded_bytes_delta, 1)
  let before = instructions_test_module(
    b"\x00\x41\x00\x1a\x01\x0b", b"\x00\x0b",
  )
  let after = instructions_test_module(b"\x00\x01\x41\x01\x1a\x0b", b"\x00\x0b")
  let zero = instruction_diff_test_compare(before, 1, after, 1)
  instruction_diff_test_ledger(zero)
  assert_eq(zero.delta.entry_bytes, 0)
  assert_eq(zero.delta.instruction_count, 0)
  for row in zero.opcodes {
    assert_eq(row.count_delta, 0)
    assert_eq(row.encoded_bytes_delta, 0)
  }
  assert_eq(zero.baseline.instructions[0].mnemonic, "i32.const")
  assert_eq(zero.current.instructions[0].mnemonic, "nop")
  let text = render_function_instructions_diff(zero, 1)
  assert_true(text.contains("OPCODE COMPOSITION: showing 1 of 4"))
  assert_true(
    text.contains("instruction sequences and immediate values are not compared"),
  )
  assert_true(
    text.contains("Zero aggregate deltas do not prove equal sequences"),
  )
  assert_true(!text.contains("function unchanged"))
  let json = @json.parse(render_function_instructions_diff_json(zero)[:])
  match json {
    Object(root) => {
      assert_true(root.get("baseline") is Some(Object(_)))
      assert_true(root.get("current") is Some(Object(_)))
      assert_eq(
        root.get("baseline"),
        Some(function_instructions_json_value(zero.baseline)),
      )
      assert_eq(
        root.get("current"),
        Some(function_instructions_json_value(zero.current)),
      )
      match root.get("opcodes") {
        Some(Array(rows)) => assert_eq(rows.length(), 4)
        _ => fail("expected complete opcode array")
      }
    }
    _ => fail("expected comparison object")
  }
  assert_eq(
    @json.parse(render_function_instructions_json(zero.baseline)[:]),
    function_instructions_json_value(zero.baseline),
  )
  let signed = instructions_test_module(
    b"\x00\x43\x00\x00\x00\x00\xfc\x00\x1a\x0b", b"\x00\x0b",
  )
  let unsigned = instructions_test_module(
    b"\x00\x43\x00\x00\x00\x00\xfc\x01\x1a\x0b", b"\x00\x0b",
  )
  let extensions = instruction_diff_test_compare(signed, 1, unsigned, 1)
  assert_eq(extensions.opcodes[0].mnemonic, "i32.trunc_sat_f32_s")
  assert_eq(extensions.opcodes[1].mnemonic, "i32.trunc_sat_f32_u")
  assert_eq(extensions.opcodes[0].encoded_bytes_delta, -2)
  assert_eq(extensions.opcodes[1].encoded_bytes_delta, 2)
}

///|
test "function-instructions-diff: baseline and current errors preserve explicit targets and original offsets" {
  let good = instructions_test_module(b"\x00\x0b", b"\x00\x0b")
  for (bi, ci, baseline_side) in [(0, 1, true), (1, 3, false), (1, 0, false)] {
    match compare_function_instructions(good, bi, good, ci) {
      Err(error) => {
        let message = describe_function_instructions_comparison_error(error)
        assert_true(
          message.contains(
            if baseline_side {
              "baseline function 0"
            } else {
              "current function \{ci}"
            },
          ),
        )
        if bi == 0 || ci == 0 {
          assert_true(message.contains("imported and has no local body"))
        } else {
          assert_true(message.contains("outside the function index space"))
        }
      }
      _ => fail("expected explicit target error, no fallback")
    }
  }
  let unknown = instructions_test_module(b"\x00\xff", b"\x00\x0b")
  match compare_function_instructions(unknown, 1, good, 1) {
    Err(
      BaselineInstructionsError(
        1,
        InstructionsInputError(UnknownOpcode(offset, opcode))
      )
    ) => {
      assert_eq(offset, 34)
      assert_eq(opcode, 255)
    }
    _ => fail("expected original baseline opcode position")
  }
  let truncated = instructions_test_module(b"\x00\x41\x80", b"\x00\x0b")
  match compare_function_instructions(good, 1, truncated, 1) {
    Err(CurrentInstructionsError(1, cause)) => {
      let message = describe_function_instructions_error(cause)
      match inspect_function_instructions(truncated, 1) {
        Err(original) =>
          assert_eq(message, describe_function_instructions_error(original))
        _ => fail("expected bounded current decode error")
      }
    }
    _ => fail("expected wrapped current decode error")
  }
  // Non-target unknown opcodes do not block the selected pair.
  let partial = instruction_diff_test_compare(unknown, 2, unknown, 2)
  assert_eq(partial.delta.entry_bytes, 0)
}
