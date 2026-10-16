///|
test "compressor failure is unavailable not zero or budget refusal" {
  let rule = Json::object({
    "id": Json::string("gzip"),
    "metric": Json::string("file.gzip"),
    "mode": Json::string("absolute"),
    "max_bytes": int_json(0),
  })
  let budget = match
    compile_budget(
      Json::object({ "version": int_json(1), "rules": Json::array([rule]) }),
    ) {
    Ok(b) => b
    Err(_) => fail("valid budget")
  }
  let measured = match budget_side(b"\x00asm\x01\x00\x00\x00", true, false) {
    Ok(s) => s
    Err(_) => fail("valid module")
  }
  let failed : BudgetSide = {
    packages: measured.packages,
    artifact: {
      ..measured.artifact,
      gzip: Some(Err("injected compressor failure")),
    },
  }
  let report = evaluate_budget_sides(budget, failed, None)
  assert_eq(report.exit_code, 1)
  assert_true(report.rules[0].status is BudgetUnavailable)
  assert_true(report.rules[0].current is None)
  assert_true(report.rules[0].reason.contains("injected compressor failure"))
  let json = render_budget_json(report, "input.wasm")
  assert_true(json.contains("\"whole_gzip_bytes\": null"))
  assert_true(json.contains("injected compressor failure"))
  assert_false(render_budget(report).contains("Overall: exceeded"))
}
