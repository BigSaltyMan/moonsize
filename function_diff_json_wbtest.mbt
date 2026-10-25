///|
fn diff_json_test_module(
  functions : Array[(String?, Int)],
  wide? : Bool = false,
) -> Bytes {
  let mut declarations = search_test_leb(functions.length())
  let mut code = if wide {
    Bytes::from_array([(functions.length() | 128).to_byte(), 0])
  } else {
    search_test_leb(functions.length())
  }
  let mut names = b""
  let mut named = 0
  for i, (name, nops) in functions {
    declarations += b"\x00"
    let body = b"\x00" + Bytes::make(nops, 1) + b"\x0b"
    code += search_test_leb(body.length()) + body
    if name is Some(name) {
      let raw = @utf8.encode(name)
      names += search_test_leb(i + 1) + search_test_leb(raw.length()) + raw
      named += 1
    }
  }
  let mut data = b"\x00asm\x01\x00\x00\x00\x01\x04\x01\x60\x00\x00\x02\x07\x01\x01m\x01f\x00\x00" +
    search_test_section(3, declarations) +
    (if wide {
      Bytes::from_array([10, (code.length() | 128).to_byte(), 0]) + code
    } else {
      search_test_section(10, code)
    })
  if named > 0 {
    data += search_test_section(
      0,
      b"\x04name" + search_test_section(1, search_test_leb(named) + names),
    )
  }
  if wide {
    data += search_test_section(0, b"\x03pad\x00")
  }
  data
}

///|
fn diff_json_test_pair() -> (Bytes, Bytes) {
  (
    diff_json_test_module([
      (Some("pkg/keep\"\n雪"), 0),
      (Some("old/gone"), 1),
      (Some("dup/shared"), 0),
      (Some("dup/shared"), 2),
      (None, 1),
    ]),
    diff_json_test_module(
      [
        (Some("new/added"), 2),
        (Some("dup/shared"), 1),
        (Some("pkg/keep\"\n雪"), 2),
        (Some("dup/shared"), 0),
        (None, 0),
        (None, 1),
      ],
      wide=true,
    ),
  )
}

///|
fn diff_json_test_compare(
  before : Bytes,
  after : Bytes,
) -> ModuleSizeDiff raise {
  match compare_modules(before, after) {
    Ok(diff) => diff
    Err(_) => fail("expected fixture comparison to succeed")
  }
}

///|
fn diff_json_test_root(
  diff : ModuleSizeDiff,
  before : Bytes,
  after : Bytes,
) -> Map[String, Json] raise {
  json_object(
    @json.parse(
      render_function_diff_json(
        diff,
        experiment_sha256(before),
        experiment_sha256(after),
      ),
    ),
  )
}

///|
test "function-diff-json: five statuses, side-specific nulls, full nested identities and coverage" {
  let (before, after) = diff_json_test_pair()
  let diff = diff_json_test_compare(before, after)
  let root = diff_json_test_root(diff, before, after)
  assert_eq(root.get("format"), Some(Json::string("moonsize-function-diff")))
  assert_eq(root.get("schema_version"), Some(int_json(1)))
  assert_eq(
    json_object(root.get("baseline").unwrap()).get("sha256"),
    Some(Json::string(experiment_sha256(before))),
  )
  assert_eq(
    json_object(root.get("current").unwrap()).get("sha256"),
    Some(Json::string(experiment_sha256(after))),
  )
  let rows = json_array(root.get("functions").unwrap())
  assert_eq(rows.length(), 10)
  let counts : Map[String, Int] = Map([])
  let mut total = 0
  for i, change in diff.functions {
    let row = json_object(rows[i])
    let status = change_status_text(change.status)
    counts.set(status, counts.get(status).unwrap_or(0) + 1)
    assert_eq(row.get("status"), Some(Json::string(status)))
    assert_eq(row.get("raw_name"), Some(path_optional_string(change.raw_name)))
    assert_eq(row.get("delta"), Some(int_json(change.delta)))
    total += change.delta
    for
      (key, stat) in [
        ("baseline", change.baseline),
        ("current", change.current),
      ] {
      match stat {
        None => assert_eq(row.get(key), Some(Json::null()))
        Some(stat) => {
          let value = json_object(row.get(key).unwrap())
          assert_eq(value.get("index"), Some(int_json(stat.index)))
          assert_eq(value.get("name"), Some(Json::string(stat.name)))
          assert_eq(
            value.get("raw_name"),
            Some(path_optional_string(stat.raw_name)),
          )
          assert_eq(
            value.get("module_name"),
            Some(Json::string(stat.module_name)),
          )
          assert_eq(value.get("offset"), Some(int_json(stat.offset)))
          assert_eq(value.get("body_size"), Some(int_json(stat.body_size)))
          assert_eq(value.get("total_size"), Some(int_json(stat.total_size)))
          assert_eq(
            value.get("prefix_size"),
            Some(int_json(stat.total_size - stat.body_size)),
          )
        }
      }
    }
    if change.status == Matched {
      assert_eq(change.baseline.unwrap().index, 1)
      assert_eq(change.current.unwrap().index, 3)
    }
  }
  for
    (key, count) in [
      ("matched", 1),
      ("added-symbol", 1),
      ("removed-symbol", 1),
      ("ambiguous", 4),
      ("missing-symbol", 3),
    ] {
    assert_eq(counts.get(key), Some(count))
  }
  assert_eq(total, 5)
  let matching = json_object(root.get("matching").unwrap())
  for
    (key, count, bytes) in [
      ("matched_baseline", 1, 3),
      ("matched_current", 1, 5),
      ("removed_symbols", 1, 4),
      ("added_symbols", 1, 5),
      ("ambiguous_baseline", 2, 8),
      ("ambiguous_current", 2, 7),
      ("missing_baseline", 1, 4),
      ("missing_current", 2, 7),
    ] {
    let coverage = json_object(matching.get(key).unwrap())
    assert_eq(coverage.get("count"), Some(int_json(count)))
    assert_eq(coverage.get("bytes"), Some(int_json(bytes)))
  }
  assert_eq(matching.get("matched_delta"), Some(int_json(2)))
  assert_eq(diff.baseline_code.function_bytes, 3 + 4 + 8 + 4)
  assert_eq(diff.current_code.function_bytes, 5 + 5 + 7 + 7)
  assert_eq(diff.baseline_code.function_count, 1 + 1 + 2 + 1)
  assert_eq(diff.current_code.function_count, 1 + 1 + 2 + 2)
}

///|
test "function-diff-json: code overhead, non-code and package ledgers, determinism and uncertain self comparison" {
  let (before, after) = diff_json_test_pair()
  let diff = diff_json_test_compare(before, after)
  let sha_before = experiment_sha256(before)
  let sha_after = experiment_sha256(after)
  let json = render_function_diff_json(diff, sha_before, sha_after)
  assert_eq(json, render_function_diff_json(diff, sha_before, sha_after))
  assert_true(render_function_diff(diff, 1).contains("MATCHING SUMMARY"))
  assert_eq(
    json_array(json_object(@json.parse(json)).get("functions").unwrap()).length(),
    10,
  )
  let root = json_object(@json.parse(json))
  for
    (key, size, code) in [
      ("baseline", 112, diff.baseline_code),
      ("current", 128, diff.current_code),
    ] {
    let side = json_object(root.get(key).unwrap())
    assert_eq(side.get("file_size"), Some(int_json(size)))
    assert_eq(code.code_size, code.function_bytes + code.overhead)
    assert_eq(side.get("code"), Some(diff_code_json(code)))
  }
  let d = json_object(root.get("delta").unwrap())
  for
    (key, value) in [
      ("file_bytes", 16),
      ("code_bytes", 7),
      ("function_bytes", 5),
      ("code_overhead_bytes", 2),
      ("non_code_bytes", 9),
    ] {
    assert_eq(d.get(key), Some(int_json(value)))
  }
  let packages = json_array(root.get("packages").unwrap())
  assert_eq(packages.length(), 5)
  let mut b = 0
  let mut a = 0
  let mut delta = 0
  for i, pkg_row in diff.packages {
    let row = json_object(packages[i])
    assert_eq(row.get("name"), Some(Json::string(pkg_row.name)))
    assert_eq(
      row.get("baseline_functions"),
      Some(int_json(pkg_row.baseline_functions)),
    )
    assert_eq(
      row.get("current_functions"),
      Some(int_json(pkg_row.current_functions)),
    )
    assert_eq(row.get("baseline_size"), Some(int_json(pkg_row.baseline_size)))
    assert_eq(row.get("current_size"), Some(int_json(pkg_row.current_size)))
    assert_eq(row.get("delta"), Some(int_json(pkg_row.delta)))
    b += pkg_row.baseline_size
    a += pkg_row.current_size
    delta += pkg_row.delta
  }
  assert_eq(b, 19)
  assert_eq(a, 24)
  assert_eq(delta, a - b)
  assert_true(json.contains("pkg/keep\\\"\\n雪"))
  let self_diff = diff_json_test_compare(before, before)
  let self_root = diff_json_test_root(self_diff, before, before)
  assert_eq(
    json_object(self_root.get("delta").unwrap()).get("file_bytes"),
    Some(int_json(0)),
  )
  let uncertain = self_diff.functions.filter(fn(row) {
    row.status == AmbiguousSymbol || row.status == MissingSymbol
  })
  assert_eq(uncertain.length(), 6)
  assert_true(uncertain.filter(fn(row) { row.delta > 0 }).length() > 0)
  assert_true(uncertain.filter(fn(row) { row.delta < 0 }).length() > 0)
  assert_true(json.contains("not cross-build semantic identity"))
  for key in ["retained", "graph_complete", "gzip"] {
    assert_true(root.get(key) is None)
  }
}

///|
test "function-diff-json: implicit comparison, bounded option scope and complete empty structures" {
  assert_eq(Options::default("x").diff_functions_json, None)
  match
    parse_options([
      "moonsize", "after.wasm", "--baseline", "before.wasm", "--diff-functions-json",
      "new.json", "--diff-functions", "--top", "1", "--retained", "--dead-code",
      "--strict", "--max-size", "0B",
    ]) {
    Ok(options) => {
      assert_true(options.diff_functions)
      assert_eq(options.diff_functions_json, Some("new.json"))
    }
    Err(error) => fail(error)
  }
  for
    args in [
      ["--diff-functions-json"],
      ["--diff-functions-json", ""],
      ["--diff-functions-json", "new.txt"],
      ["--diff-functions-json", "new.json"],
      ["--baseline", " ", "--diff-functions-json", "new.json"],
    ] {
    assert_true(parse_options(["moonsize", "missing.wasm"] + args) is Err(_))
  }
  for
    args in [
      ["--summary-json", "s.json"],
      ["--compress"],
      ["--callers", "1"],
      ["--html", "x.html"],
      ["--call-graph", "x.json"],
      ["--data-segments"],
      ["--budget-json", "x.json"],
      ["--baseline-instructions", "1"],
      ["--experiment", "x.json"],
    ] {
    assert_true(
      parse_options(
        [
          "moonsize", "missing.wasm", "--baseline", "before.wasm", "--diff-functions-json",
          "new.json",
        ] +
        args,
      )
      is Err(_),
    )
  }
  // The narrower JSON contract must not tighten the old text-only combination.
  assert_true(
    parse_options([
      "moonsize", "missing.wasm", "--baseline", "before.wasm", "--diff-functions",
      "--compress",
    ])
    is Ok(_),
  )
  let bytes = b"\x00asm\x01\x00\x00\x00"
  let empty = diff_json_test_compare(bytes, bytes)
  let root = diff_json_test_root(empty, bytes, bytes)
  for key in ["functions", "packages"] {
    assert_eq(root.get(key), Some(Json::array([])))
  }
  for key in ["baseline", "current"] {
    let code = json_object(
      json_object(root.get(key).unwrap()).get("code").unwrap(),
    )
    for key in ["code_size", "function_count", "function_bytes", "overhead"] {
      assert_eq(code.get(key), Some(int_json(0)))
    }
  }
  assert_eq(empty.matching.matched_delta, 0)
}
