///|
/// The exit code contract, and the size gate that produces it.
///
/// The gate is exercised through `parse_options`, so the flag spelling is part
/// of what is being tested and not just the arithmetic behind it.

///|
/// The options a real invocation would produce, or a failed test.
fn options_of(args : Array[String]) -> Options raise {
  match parse_options(args) {
    Ok(options) => options
    Err(message) => fail(message)
  }
}

///|
test "the exit codes are the documented ones" {
  // A CI job branches on these numbers, so they are a contract rather than an
  // implementation detail.
  inspect(EXIT_OK, content="0")
  inspect(EXIT_INPUT, content="1")
  inspect(EXIT_USAGE, content="2")
  inspect(EXIT_OVER_SIZE, content="3")
}

///|
test "a file under the budget passes and one over it fails" {
  // `examples/fib.wasm` is 10645 bytes, which is what the workflow's
  // `--max-size 100KB` is checked against.
  let roomy = options_of(["moonsize", "fib.wasm", "--max-size", "100KB"])
  inspect(size_exit_code(roomy, 10645, None), content="0")
  let tight = options_of(["moonsize", "fib.wasm", "--max-size", "10KB"])
  inspect(size_exit_code(tight, 10645, None), content="3")
  // The comparison is strict: exactly at the budget is still inside it.
  inspect(size_exit_code(tight, 10240, None), content="0")
  inspect(size_exit_code(tight, 10241, None), content="3")
}

///|
test "without a budget nothing is ever over it" {
  let none = options_of(["moonsize", "fib.wasm"])
  inspect(size_exit_code(none, 0, None), content="0")
  inspect(size_exit_code(none, 10645, None), content="0")
  inspect(size_exit_code(none, 10645, Some(1)), content="0")
}

///|
test "with a baseline the budget bounds the growth, not the file" {
  let generous = options_of([
    "moonsize", "app.wasm", "--baseline", "main.wasm", "--max-size", "1KB",
  ])
  // The file is far bigger than the budget; only the change is measured.
  inspect(size_exit_code(generous, 10645, Some(10000)), content="0")
  // 1000 bytes of growth fits; 1025 does not.
  inspect(size_exit_code(generous, 10645, Some(9645)), content="0")
  inspect(size_exit_code(generous, 10645, Some(9620)), content="3")
  // Growth is the only failure: a file that shrank is never over budget, not
  // even against a budget of nothing.
  let zero = options_of([
    "moonsize", "app.wasm", "--baseline", "main.wasm", "--max-size", "0B",
  ])
  inspect(size_exit_code(zero, 9000, Some(10645)), content="0")
  inspect(size_exit_code(zero, 10645, Some(10645)), content="0")
  inspect(size_exit_code(zero, 10646, Some(10645)), content="3")
}

///|
test "the failure line names the budget that was broken" {
  let absolute = options_of(["moonsize", "app.wasm", "--max-size", "10KB"])
  inspect(
    describe_size_failure(absolute, 10645, None),
    content="moonsize: 10645 bytes is over the budget of 10240 bytes",
  )
  // Nothing to say when the gate passed.
  let generous = options_of(["moonsize", "app.wasm", "--max-size", "100KB"])
  inspect(describe_size_failure(generous, 10645, None), content="")
  inspect(describe_size_failure(generous, 10645, None), content="")
  let grown = options_of([
    "moonsize", "app.wasm", "--baseline", "main.wasm", "--max-size", "100B",
  ])
  inspect(
    describe_size_failure(grown, 11000, Some(10645)),
    content="moonsize: grew by 355 bytes over the baseline, budget 100 bytes",
  )
}

///|
test "the comparison lists both modules' sections, heaviest current first" {
  // minimal_module is 24 bytes of type (6), function (4) and code (6);
  // named_module is 117 bytes of import (24), function (5), code (11) and a
  // custom name section (69). Each side is checked for the sections only it has.
  let baseline = match parse_module(minimal_module()) {
    Ok(parsed) => parsed
    Err(error) => fail(decode_failure(error))
  }
  let current = match parse_module(named_module()) {
    Ok(parsed) => parsed
    Err(error) => fail(decode_failure(error))
  }
  inspect(
    render_size_comparison(baseline, current),
    content=(
      #|SIZE COMPARISON
      #|
      #|                 baseline  current  delta
      #|  total                24      117  +93  (+387.5%)
      #|  custom (name)         0       69  +69  (new)
      #|  import                0       24  +24  (new)
      #|  code                  6       11  +5  (+83.3%)
      #|  function              4        5  +1  (+25.0%)
      #|  type                  6        0  -6  (-100.0%)
      #|
    ),
  )
}

///|
test "a section that did not change reads as a zero delta" {
  // The same module on both sides: every row is a zero, and the label gutter
  // narrows to whatever this module's sections need.
  let parsed = match parse_module(minimal_module()) {
    Ok(parsed) => parsed
    Err(error) => fail(decode_failure(error))
  }
  inspect(
    render_size_comparison(parsed, parsed),
    content=(
      #|SIZE COMPARISON
      #|
      #|            baseline  current  delta
      #|  total           24       24  0  (0.0%)
      #|  type             6        6  0  (0.0%)
      #|  code             6        6  0  (0.0%)
      #|  function         4        4  0  (0.0%)
      #|
    ),
  )
}

///|
/// Encode small complete custom sections; fixed raw/non-short encodings have
/// separate fixtures so the expected byte counts do not depend on this helper.
fn comparison_custom(name : Bytes, contents : Bytes) -> Bytes {
  let payload = Bytes::from_array([name.length().to_byte()]) + name + contents
  b"\x00" + Bytes::from_array([payload.length().to_byte()]) + payload
}

///|
fn comparison_parsed(sections : Bytes) -> WasmModule raise {
  match parse_module(b"\x00asm\x01\x00\x00\x00" + sections) {
    Ok(parsed) => parsed
    Err(error) => fail(describe_error(error))
  }
}

///|
fn comparison_row(rows : Array[SizeRow], key : SectionKey) -> SizeRow raise {
  let matches = rows.filter(row => row.key == key)
  assert_eq(matches.length(), 1)
  matches[0]
}

///|
fn assert_comparison_sizes(
  row : SizeRow,
  baseline : Int,
  current : Int,
) -> Unit raise {
  assert_eq(row.baseline, baseline)
  assert_eq(row.current, current)
  assert_eq(row.current - row.baseline, current - baseline)
}

///|
fn assert_comparison_totals(
  baseline : WasmModule,
  current : WasmModule,
) -> Unit raise {
  let rows = size_rows(baseline, current)
  let mut before = 0
  let mut after = 0
  let mut delta = 0
  for row in rows {
    before += row.baseline
    after += row.current
    delta += row.current - row.baseline
  }
  assert_eq(before + 8, baseline.file_size)
  assert_eq(after + 8, current.file_size)
  assert_eq(delta, current.file_size - baseline.file_size)
}

///|
test "same-name custom self comparison contains one summed numeric row" {
  let parsed = comparison_parsed(b"\x00\x02\x01x\x00\x04\x01x\x00\x00")
  let rows = size_rows(parsed, parsed)
  assert_eq(rows.length(), 1)
  assert_comparison_sizes(comparison_row(rows, CustomSection("x")), 10, 10)
  assert_comparison_totals(parsed, parsed)
}

///|
test "rearranging repeated or tied custom sections changes neither numbers nor row order" {
  let x4 = comparison_custom(b"x", b"")
  let x6 = comparison_custom(b"x", b"\x00\x00")
  let y = comparison_custom(b"y", b"123456")
  let a = comparison_parsed(x4 + x6 + y)
  let b = comparison_parsed(y + x6 + x4)
  assert_eq(render_size_comparison(a, a), render_size_comparison(a, b))
  assert_eq(render_size_comparison(a, a), render_size_comparison(b, a))
  let rows = size_rows(a, b)
  assert_eq(rows[0].label, "custom (x)")
  assert_eq(rows[1].label, "custom (y)")
  assert_comparison_totals(a, b)
}

///|
test "different custom instance counts compare totals rather than pairwise positions" {
  let x4 = comparison_custom(b"x", b"")
  let x5 = comparison_custom(b"x", b"0")
  let x6 = comparison_custom(b"x", b"00")
  let x8 = comparison_custom(b"x", b"0000")
  let baseline = comparison_parsed(x4 + x6)
  for (sections, expected) in [(x5 + x8, 13), (x4 + x5 + x8, 17), (x5, 5)] {
    let current = comparison_parsed(sections)
    let rows = size_rows(baseline, current)
    assert_eq(rows.length(), 1)
    assert_comparison_sizes(rows[0], 10, expected)
    assert_comparison_totals(baseline, current)
  }
}

///|
test "adding and removing a repeated instance includes its complete encoded size" {
  let x4 = comparison_custom(b"x", b"")
  let x6 = comparison_custom(b"x", b"00")
  let a = comparison_parsed(x4)
  let b = comparison_parsed(x4 + x6)
  assert_comparison_sizes(
    comparison_row(size_rows(a, b), CustomSection("x")),
    4,
    10,
  )
  assert_comparison_sizes(
    comparison_row(size_rows(b, a), CustomSection("x")),
    10,
    4,
  )
  assert_comparison_totals(a, b)
}

///|
test "whole groups added or deleted remain visible against zero" {
  let baseline = comparison_parsed(
    comparison_custom(b"gone", b"") + comparison_custom(b"kept", b""),
  )
  let current = comparison_parsed(
    comparison_custom(b"new", b"") + comparison_custom(b"kept", b""),
  )
  let rows = size_rows(baseline, current)
  assert_eq(rows.length(), 3)
  assert_comparison_sizes(comparison_row(rows, CustomSection("gone")), 7, 0)
  assert_comparison_sizes(comparison_row(rows, CustomSection("new")), 0, 6)
  assert_comparison_sizes(comparison_row(rows, CustomSection("kept")), 7, 7)
  assert_eq(rows[2].label, "custom (gone)")
  assert_comparison_totals(baseline, current)
}

///|
test "full custom names preserve case spaces empty names and non-ASCII characters" {
  let names = [
    (b"x", "x"),
    (b"X", "X"),
    (b"", ""),
    (b" x", " x"),
    (b"x ", "x "),
    (b"\xc3\xa9", "é"),
  ]
  let mut sections = b""
  for (name, _) in names {
    sections = sections + comparison_custom(name, b"")
  }
  let parsed = comparison_parsed(sections)
  let rows = size_rows(parsed, parsed)
  assert_eq(rows.length(), names.length())
  for (bytes, name) in names {
    assert_comparison_sizes(
      comparison_row(rows, CustomSection(name)),
      bytes.length() + 3,
      bytes.length() + 3,
    )
  }
  assert_comparison_totals(parsed, parsed)
}

///|
test "custom code and standard code have separate identities" {
  let baseline = comparison_parsed(
    b"\x0a\x01\x00" + comparison_custom(b"code", b""),
  )
  let current = comparison_parsed(comparison_custom(b"code", b"00"))
  let rows = size_rows(baseline, current)
  assert_eq(rows.length(), 2)
  assert_comparison_sizes(comparison_row(rows, StandardSection(10)), 3, 0)
  assert_comparison_sizes(comparison_row(rows, CustomSection("code")), 7, 9)
  assert_comparison_totals(baseline, current)
}

///|
test "ties use baseline size then standard binary order then full custom name" {
  let baseline = comparison_parsed(
    b"\x01\x01\x00\x0c\x01\x00\x0a\x01\x00" +
    comparison_custom(b"z", b"0") +
    comparison_custom(b"a", b"00"),
  )
  let current = comparison_parsed(
    b"\x01\x01\x00\x0c\x01\x00\x0a\x01\x00" +
    comparison_custom(b"z", b"0") +
    comparison_custom(b"a", b"0"),
  )
  let rows = size_rows(baseline, current)
  assert_eq(rows.map(row => row.label), [
    "custom (a)", "custom (z)", "type", "datacount", "code",
  ])
  // Equal sizes for standard and custom groups put standards first.
  let tie = comparison_parsed(b"\x0a\x01\x00" + comparison_custom(b"", b""))
  assert_eq(size_rows(tie, tie).map(row => row.label), ["code", "custom ()"])
}

///|
test "empty module comparison has no section rows and a zero total" {
  let empty = comparison_parsed(b"")
  assert_eq(size_rows(empty, empty).length(), 0)
  assert_comparison_totals(empty, empty)
  assert_true(render_size_comparison(empty, empty).contains("total"))
}

///|
test "comparison self and reverse properties hold across valid module pairs" {
  let modules = [
    comparison_parsed(b""),
    comparison_parsed(b"\x00\x02\x01x\x00\x04\x01x\x00\x00"),
    comparison_parsed(b"\x01\x01\x00\x0c\x01\x00\x0a\x01\x00"),
    comparison_parsed(
      comparison_custom(b"code", b"00") + comparison_custom(b"", b""),
    ),
    comparison_parsed(
      comparison_custom(b"x", b"0") + comparison_custom(b"X", b""),
    ),
  ]
  for a in modules {
    for row in size_rows(a, a) {
      assert_eq(row.current - row.baseline, 0)
    }
    for b in modules {
      let forward = size_rows(a, b)
      let backward = size_rows(b, a)
      assert_eq(forward.length(), backward.length())
      for row in forward {
        let reverse = comparison_row(backward, row.key)
        assert_eq(row.baseline, reverse.current)
        assert_eq(row.current, reverse.baseline)
        assert_eq(
          row.current - row.baseline,
          -(reverse.current - reverse.baseline),
        )
      }
      assert_comparison_totals(a, b)
    }
  }
}
