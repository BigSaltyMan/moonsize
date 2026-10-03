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
