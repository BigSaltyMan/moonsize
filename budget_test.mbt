///|
fn budget_test_rule(
  metric : String,
  mode : String,
  maximum : Int,
  package_name? : String,
  id? : String = "rule",
) -> Json {
  let fields : Map[String, Json] = {
    "id": Json::string(id),
    "metric": Json::string(metric),
    "mode": Json::string(mode),
    "max_bytes": Json::number(maximum.to_double()),
  }
  if package_name is Some(name) {
    fields.set("package", Json::string(name))
  }
  Json::object(fields)
}

///|
fn budget_test_config(rules : Array[Json]) -> Json {
  Json::object({ "version": Json::number(1), "rules": Json::array(rules) })
}

///|
fn budget_test_compile(rules : Array[Json]) -> @moonsize.CompiledBudget raise {
  match @moonsize.compile_budget(budget_test_config(rules)) {
    Ok(compiled) => compiled
    Err(_) => fail("valid test budget rejected")
  }
}

///|
fn budget_test_run(
  rules : Array[Json],
  current : Bytes,
  baseline? : Bytes,
) -> @moonsize.BudgetReport raise {
  match
    @moonsize.evaluate_budget(
      budget_test_compile(rules),
      current,
      baseline_data?=baseline,
    ) {
    Ok(report) => report
    Err(error) => fail(@moonsize.describe_budget_error(error))
  }
}

///|
test "budget file equality overflow and zero are byte comparisons" {
  let data = diff_module([(Some("pkg.target"), 2)])
  for
    (maximum, code) in [
      (data.length(), 0),
      (data.length() - 1, 3),
      (0, 3),
      (2147483647, 0),
    ] {
    let report = budget_test_run(
      [budget_test_rule("file.raw", "absolute", maximum)],
      data,
    )
    assert_eq(report.exit_code, code)
    assert_eq(report.rules[0].current, Some(data.length()))
    assert_true(report.rules[0].delta is None)
  }
}

///|
test "budget growth retains signed shrinkage and equality for all four metrics" {
  let before = diff_module([(Some("pkg.target"), 40)])
  let after = diff_module([(Some("pkg.target"), 2)])
  for metric in ["file.raw", "file.gzip", "code.raw", "package.raw"] {
    let package_name = if metric == "package.raw" { Some("pkg") } else { None }
    let report = budget_test_run(
      [budget_test_rule(metric, "growth", 0, package_name?)],
      after,
      baseline=before,
    )
    assert_eq(report.exit_code, 0)
    assert_true(report.rules[0].delta.unwrap() <= 0)
    assert_eq(
      report.rules[0].delta,
      Some(report.rules[0].current.unwrap() - report.rules[0].baseline.unwrap()),
    )
    let same = budget_test_run(
      [budget_test_rule(metric, "growth", 0, package_name?)],
      before,
      baseline=before,
    )
    assert_eq(same.exit_code, 0)
    assert_eq(same.rules[0].delta, Some(0))
  }
}

///|
test "code budget includes section header and counts whereas packages use total_size" {
  let data = diff_module([(Some("pkg.target"), 126)])
  let report = budget_test_run(
    [
      budget_test_rule("code.raw", "absolute", 2147483647, id="code"),
      budget_test_rule(
        "package.raw",
        "absolute",
        129,
        package_name="pkg",
        id="package",
      ),
    ],
    data,
  )
  // Locals + NOPs + end = 128; size LEB is 2 bytes, not part of body_size.
  assert_eq(report.rules[1].current, Some(130))
  assert_true(report.rules[1].status is BudgetExceeded)
  assert_eq(report.rules[0].current, Some(134))
}

///|
test "empty modules provide real zero code but no invented package" {
  let empty = b"\x00asm\x01\x00\x00\x00"
  let report = budget_test_run(
    [
      budget_test_rule("code.raw", "absolute", 0, id="code"),
      budget_test_rule(
        "package.raw",
        "absolute",
        100,
        package_name="absent",
        id="package",
      ),
    ],
    empty,
  )
  assert_eq(report.rules[0].current, Some(0))
  assert_true(report.rules[0].status is BudgetPassed)
  assert_eq(report.exit_code, 1)
  assert_true(report.rules[1].current is None)
  assert_true(report.rules[1].reason.contains("label not found"))
}

///|
test "whole gzip budgets agree with public measurement and repeated rules" {
  let data = diff_module([(Some("pkg.target"), 100)])
  let gzip = match @moonsize.compressed_size(data) {
    Ok(n) => n
    Err(e) => fail(e)
  }
  let report = budget_test_run(
    [
      budget_test_rule("file.gzip", "absolute", gzip, id="equal"),
      budget_test_rule("file.gzip", "absolute", gzip - 1, id="exceed"),
    ],
    data,
  )
  assert_eq(report.rules[0].current, Some(gzip))
  assert_eq(report.rules[1].current, Some(gzip))
  assert_eq(report.exit_code, 3)
}

///|
test "package label appearance disappearance and both absent stay distinct" {
  let empty = diff_module([])
  let present = diff_module([(Some("pkg.target"), 4)])
  let rule = budget_test_rule("package.raw", "growth", 0, package_name="pkg")
  let gone = budget_test_run([rule], empty, baseline=present)
  assert_eq(gone.exit_code, 0)
  assert_eq(gone.rules[0].current, Some(0))
  assert_eq(gone.rules[0].baseline, Some(7))
  assert_eq(gone.rules[0].current_package_present, Some(false))
  assert_true(gone.rules[0].reason.contains("label disappeared"))
  let added = budget_test_run([rule], present, baseline=empty)
  assert_eq(added.exit_code, 3)
  assert_eq(added.rules[0].baseline, Some(0))
  assert_true(added.rules[0].reason.contains("newly observed"))
  let absent = budget_test_run([rule], empty, baseline=empty)
  assert_eq(absent.exit_code, 1)
  assert_true(absent.rules[0].current is None)
  assert_true(absent.rules[0].baseline is None)
}

///|
test "unknown attribution never hides file and code results or exceeds priority" {
  let data = diff_module([(Some("pkg.target"), 4), (None, 0)])
  let report = budget_test_run(
    [
      budget_test_rule("file.raw", "absolute", 0, id="file"),
      budget_test_rule(
        "package.raw",
        "absolute",
        2147483647,
        package_name="pkg",
        id="package",
      ),
      budget_test_rule("code.raw", "absolute", 2147483647, id="code"),
    ],
    data,
  )
  assert_eq(report.exit_code, 1)
  assert_true(report.status is BudgetUnavailable)
  assert_true(report.rules[0].status is BudgetExceeded)
  assert_true(report.rules[2].status is BudgetPassed)
  assert_eq(report.rules[1].current_package_present, Some(true))
  assert_true(report.rules[1].current is None)
  assert_true(report.rules[1].reason.contains("coverage insufficient"))
  assert_eq(report.current.coverage.unwrap().unattributed_functions, 1)
  assert_eq(report.current.coverage.unwrap().unattributed_bytes, 3)
}

///|
test "absolute package does not request unrelated baseline attribution" {
  let known = diff_module([(Some("pkg.target"), 0)])
  let unknown = diff_module([(None, 0)])
  let report = budget_test_run(
    [
      budget_test_rule(
        "package.raw",
        "absolute",
        3,
        package_name="pkg",
        id="package",
      ),
      budget_test_rule("file.raw", "growth", 2147483647, id="growth"),
    ],
    known,
    baseline=unknown,
  )
  assert_eq(report.exit_code, 0)
  assert_true(report.baseline.unwrap().coverage is None)
  assert_true(report.rules[0].baseline is None)
  // Unneeded baseline bytes are not parsed by library absolute evaluation.
  let absolute = budget_test_run(
    [budget_test_rule("file.raw", "absolute", 2147483647)],
    known,
    baseline=b"bad",
  )
  assert_eq(absolute.exit_code, 0)
}

///|
test "budget inputs preserve current and baseline error sides and require baseline" {
  let compiled = budget_test_compile([budget_test_rule("file.raw", "growth", 0)])
  let valid = diff_module([])
  assert_true(@moonsize.budget_requires_baseline(compiled))
  assert_true(
    @moonsize.evaluate_budget(compiled, valid) is Err(BudgetBaselineRequired),
  )
  assert_true(
    @moonsize.evaluate_budget(compiled, b"bad", baseline_data=valid)
    is Err(BudgetCurrentInput(_)),
  )
  assert_true(
    @moonsize.evaluate_budget(compiled, valid, baseline_data=b"bad")
    is Err(BudgetBaselineInput(_)),
  )
}

///|
test "compiled budget snapshots validated scalar rules rather than exposing config arrays" {
  let rule = budget_test_rule("file.raw", "absolute", 0)
  let array = [rule]
  let compiled = match @moonsize.compile_budget(budget_test_config(array)) {
    Ok(c) => c
    Err(_) => fail("compile")
  }
  if rule is Object(fields) {
    fields.set("max_bytes", Json::number(2147483647))
  }
  array.clear()
  let report = match @moonsize.evaluate_budget(compiled, diff_module([])) {
    Ok(r) => r
    Err(_) => fail("evaluate")
  }
  assert_eq(report.exit_code, 3)
  assert_eq(report.rules.length(), 1)
  assert_eq(report.rules[0].max_bytes, 0)
}

///|
test "budget configuration rejects types thresholds and unsupported fields" {
  let invalid : Array[(String, Json)] = [
    ("max_bytes", Json::number(-1)),
    ("max_bytes", Json::number(0.5)),
    ("max_bytes", Json::number(2147483648.0)),
    ("max_bytes", Json::string("1KB")),
    ("max_bytes", Json::null()),
    ("metric", Json::string("file.br")),
    ("mode", Json::string("percent")),
    ("id", Json::string("  ")),
    ("package", Json::null()),
    ("unknown", Json::boolean(true)),
  ]
  for (key, value) in invalid {
    let rule = budget_test_rule("file.raw", "absolute", 0)
    if rule is Object(fields) {
      fields.set(key, value)
    }
    match @moonsize.compile_budget(budget_test_config([rule])) {
      Ok(_) => fail("invalid config passed")
      Err(problems) => {
        assert_true(!problems.is_empty())
        assert_eq(problems[0].rule_index, Some(0))
        assert_true(problems[0].reason.length() > 0)
      }
    }
  }
  for
    config in [
      Json::null(),
      Json::array([]),
      budget_test_config([]),
      budget_test_config([Json::null()]),
    ] {
    assert_true(@moonsize.compile_budget(config) is Err(_))
  }
}

///|
test "budget validation reports duplicate ids versions and required package fields" {
  let rule = budget_test_rule("file.raw", "absolute", 0)
  assert_true(
    @moonsize.compile_budget(budget_test_config([rule, rule])) is Err(_),
  )
  for
    version in [
      Json::number(0),
      Json::number(2),
      Json::string("1"),
      Json::number(1.5),
    ] {
    let config = budget_test_config([rule])
    if config is Object(fields) {
      fields.set("version", version)
    }
    assert_true(@moonsize.compile_budget(config) is Err(_))
  }
  for package_name in [None, Some(""), Some("  ")] {
    assert_true(
      @moonsize.compile_budget(
        budget_test_config([
          budget_test_rule("package.raw", "absolute", 0, package_name?),
        ]),
      )
      is Err(_),
    )
  }
}

///|
test "budget text JSON Markdown and exit statuses agree and escape evidence" {
  let data = diff_module([(Some("pkg.target"), 0)])
  let report = budget_test_run(
    [budget_test_rule("file.raw", "absolute", 0, id="x|`<tag>\n*")],
    data,
  )
  let text = @moonsize.render_budget(report)
  let json = @moonsize.render_budget_json(report, "x<|`\n.wasm")
  let md = @moonsize.render_budget_markdown(report, "x<|`\n.wasm")
  assert_true(text.contains("Overall: exceeded; exit code 3"))
  assert_true(json.contains("\"format\": \"moonsize-budget\""))
  assert_true(json.contains("\"baseline\": null"))
  assert_true(json.contains("\"exit_code\": 3"))
  for escaped in ["&#124;", "&#96;", "&lt;", "&#10;", "&#42;"] {
    assert_true(md.contains(escaped))
  }
  assert_false(md.contains("<tag>"))
  assert_true(md.contains(report.current.sha256))
}

///|
test "budget default options and CLI conflicts remain explicit" {
  let options = @moonsize.Options::default("a.wasm")
  assert_true(
    options.budget is None &&
    options.budget_json is None &&
    options.budget_md is None,
  )
  for
    extra in [
      ["--max-size", "1KB"],
      ["--html", "a.html"],
      ["--call-graph", "a.json"],
      ["--why-index", "0"],
      ["--experiment", "a.json"],
    ] {
    let args = ["moonsize", "absent.wasm", "--budget", "config.json"]
    for arg in extra {
      args.push(arg)
    }
    assert_true(@moonsize.parse_options(args) is Err(_))
  }
}

///|
test "growth positive thresholds are inclusive for every metric" {
  let before = diff_module([(Some("pkg.target"), 1)])
  let after = diff_module([(Some("pkg.target"), 500)])
  for metric in ["file.raw", "file.gzip", "code.raw", "package.raw"] {
    let package_name = if metric == "package.raw" { Some("pkg") } else { None }
    let measured = budget_test_run(
      [budget_test_rule(metric, "growth", 2147483647, package_name?)],
      after,
      baseline=before,
    )
    let growth = measured.rules[0].delta.unwrap()
    assert_true(growth > 0)
    assert_eq(
      budget_test_run(
        [budget_test_rule(metric, "growth", growth, package_name?)],
        after,
        baseline=before,
      ).exit_code,
      0,
    )
    assert_eq(
      budget_test_run(
        [budget_test_rule(metric, "growth", growth - 1, package_name?)],
        after,
        baseline=before,
      ).exit_code,
      3,
    )
  }
}

///|
test "budget source preflight rejects fraction rounding and accepts escaped keys" {
  let prefix = "{\"version\":1,\"rules\":[{\"id\":\"number 1.2 and -9\\\"\",\"metric\":\"file.raw\",\"mode\":\"absolute\",\"max_bytes\":"
  let suffix = "}]}"
  for
    raw in [
      "1.0", "1e0", "1.00000000000000000001", "2147483647.000000000000001", "-0",
      "2147483648", "0.5",
    ] {
    assert_true(@moonsize.compile_budget_text(prefix + raw + suffix) is Err(_))
  }
  for raw in ["0", "2147483647"] {
    assert_true(@moonsize.compile_budget_text(prefix + raw + suffix) is Ok(_))
  }
  let escaped = "{\"rules\":[{\"id\":\"ok\",\"metric\":\"file.raw\",\"mode\":\"absolute\",\"\\u006dax_bytes\":0}],\"version\":1}"
  assert_true(@moonsize.compile_budget_text(escaped) is Ok(_))
  assert_true(@moonsize.compile_budget_text("{") is Err(_))
}

///|
test "package attribution uses local full indices and rejects malformed mangled symbols" {
  let imported = diff_module([(Some("pkg.target"), 2)], imported=3)
  let report = budget_test_run(
    [budget_test_rule("package.raw", "absolute", 5, package_name="pkg")],
    imported,
  )
  assert_eq(report.exit_code, 0)
  assert_eq(report.rules[0].current, Some(5))
  assert_eq(report.current.coverage.unwrap().functions, 1)
  for raw in ["_M0broken", "__M0broken", "M0broken"] {
    let malformed = diff_module([(Some("pkg.target"), 2), (Some(raw), 0)])
    let unknown = budget_test_run(
      [budget_test_rule("package.raw", "absolute", 100, package_name="pkg")],
      malformed,
    )
    assert_eq(unknown.exit_code, 1)
    assert_eq(unknown.current.coverage.unwrap().unattributed_functions, 1)
  }
}

///|
test "required baseline attribution fails without erasing current measurements" {
  let before = diff_module([(None, 2)])
  let after = diff_module([(Some("pkg.target"), 2)])
  let report = budget_test_run(
    [
      budget_test_rule("file.raw", "growth", 2147483647, id="file"),
      budget_test_rule(
        "package.raw",
        "growth",
        2147483647,
        package_name="pkg",
        id="package",
      ),
    ],
    after,
    baseline=before,
  )
  assert_eq(report.exit_code, 1)
  assert_true(report.rules[0].status is BudgetPassed)
  assert_eq(report.rules[1].current, Some(5))
  assert_true(report.rules[1].baseline is None)
  assert_true(
    report.rules[1].reason.contains(
      "baseline: package attribution coverage insufficient",
    ),
  )
}

///|
test "unavailable report keeps null values and reasons in every format" {
  let report = budget_test_run(
    [budget_test_rule("package.raw", "absolute", 100, package_name="pkg")],
    diff_module([(None, 0)]),
  )
  assert_eq(report.exit_code, 1)
  let json = @moonsize.render_budget_json(report, "input")
  assert_true(json.contains("\"current\": null"))
  assert_true(json.contains("\"exit_code\": 1"))
  for
    text in [
      @moonsize.render_budget(report),
      json,
      @moonsize.render_budget_markdown(report, "input"),
    ] {
    assert_true(text.contains("unavailable"))
    assert_true(text.contains("coverage insufficient"))
  }
}
