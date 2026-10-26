///|
fn boundary_test_error(args : Array[String]) -> String raise {
  match parse_options(["moonsize"] + args) {
    Err(message) => message
    Ok(_) => fail("expected argument rejection")
  }
}

///|
test "cli-option-boundary: unknown ASCII flags before and after input, no abbreviations" {
  for
    (args, flag) in [
      (["--summry-json"], "--summry-json"),
      (["-x"], "-x"),
      (["--summ"], "--summ"),
      (["--top=1"], "--top=1"),
      (["app.wasm", "--summry-json"], "--summry-json"),
      (["app.wasm", "-x"], "-x"),
    ] {
    let message = boundary_test_error(args)
    assert_true(message.has_prefix("moonsize: unknown option " + flag + ";"))
    assert_true(message.contains("--help"))
  }
  let second = boundary_test_error(["first.wasm", "second.wasm"])
  assert_true(second.has_prefix("moonsize: unexpected argument second.wasm"))
  assert_false(second.contains("unknown option"))
  assert_eq(parse_options(["moonsize", "-"]).unwrap().path, "-")
  assert_eq(
    parse_options(["moonsize", "–file.wasm"]).unwrap().path,
    "–file.wasm",
  ) // Non-ASCII dash is a path.
}

///|
test "cli-option-boundary: separator switches permanently to unique positional input" {
  for name in ["--help", "--", "--top", "--app.wasm", "-"] {
    let options = parse_options(["moonsize", "--", name]).unwrap()
    assert_eq(options.path, name)
    assert_eq(options.top, DEFAULT_TOP)
  }
  let options = parse_options([
    "moonsize", "--top", "1", "--summary-json", "new-summary.json", "--", "--app.wasm",
  ]).unwrap()
  assert_eq(options.path, "--app.wasm")
  assert_eq(options.top, 1)
  assert_eq(options.summary_json, Some("new-summary.json"))
  assert_eq(
    parse_options(["moonsize", "app.wasm", "--"]).unwrap().path,
    "app.wasm",
  )
  assert_true(boundary_test_error(["--"]).has_prefix("usage:"))
  for
    (args, extra) in [
      (["--", "one.wasm", "two.wasm"], "two.wasm"),
      (["one.wasm", "--", "two.wasm"], "two.wasm"),
      (["--", "--top", "1"], "1"),
      (["--", "--", "--"], "--"),
      (["app.wasm", "--", "--top", "1"], "--top"),
    ] {
    let message = boundary_test_error(args)
    assert_true(message.has_prefix("moonsize: unexpected argument " + extra))
    assert_false(message.contains("unknown option"))
  }
  // The separator does not skip the existing post-parse mode validation.
  assert_true(
    boundary_test_error(["--exports", "--strict", "--", "--help"]).contains(
      "exports modes allow only",
    ),
  )
  assert_true(
    boundary_test_error(["--budget-json", "new.json", "--", "app.wasm"]).contains(
      "require --budget",
    ),
  )
}

///|
test "cli-option-boundary: consumed values, help isolation and ordinary ordering stay intact" {
  let options = parse_options([
    "moonsize", "--baseline", "-before.wasm", "--", "-after.wasm",
  ]).unwrap()
  assert_eq(options.baseline, Some("-before.wasm"))
  assert_eq(options.path, "-after.wasm")
  // A token consumed by a known value branch never reaches separator handling.
  let literal_value = parse_options(["moonsize", "--baseline", "--", "app.wasm"]).unwrap()
  assert_eq(literal_value.baseline, Some("--"))
  assert_eq(literal_value.path, "app.wasm")
  assert_eq(
    parse_options(["moonsize", "app.wasm", "--find-functions", "-"]).unwrap().find_functions,
    Some("-"),
  )
  assert_true(
    boundary_test_error(["app.wasm", "--find-functions", "--help"]).has_prefix(
      "moonsize: --find-functions needs",
    ),
  )
  assert_true(
    boundary_test_error(["--top", "-1", "app.wasm"]).has_prefix(
      "moonsize: --top wants",
    ),
  )
  assert_true(
    boundary_test_error(["--summary-json", "--", "--help"]).has_prefix(
      "moonsize: --summary-json needs",
    ),
  )
  match help_request(["moonsize", "--", "--help"]) {
    Ok(None) => ()
    _ => fail("separator request intercepted as help")
  }
  assert_eq(parse_options(["moonsize", "--", "--help"]).unwrap().path, "--help")
  match help_request(["moonsize", "--help"]) {
    Ok(Some(_)) => ()
    _ => fail("normal help no longer handled")
  }
  assert_eq(
    parse_options(["moonsize", "app.wasm", "--top", "1"]).unwrap().top,
    1,
  )
  assert_eq(
    parse_options(["moonsize", "--top", "1", "app.wasm"]).unwrap().top,
    1,
  )
  assert_eq(parse_options(["moonsize", "./--help"]).unwrap().path, "./--help")
}
