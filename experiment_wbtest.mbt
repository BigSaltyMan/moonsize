///|
fn experiment_test_report(
  before : Bytes,
  after : Bytes,
  context? : Json = Json::null(),
  top? : Int = 10,
) -> Json raise {
  match
    experiment_report(before, after, "before.wasm", "after.wasm", context, top~) {
    Ok(report) => report
    Err(error) => fail(error)
  }
}

///|
fn experiment_test_context() -> Json {
  let build = Json::object({
    "revision": Json::string("source-sha"),
    "command": Json::string("moon build --target wasm --release"),
    "toolchain": Json::string("pinned-toolchain"),
    "target": Json::string("wasm"),
    "mode": Json::string("release"),
    "strip": Json::boolean(true),
    "features": Json::array([]),
  })
  Json::object({
    "title": Json::string("Remove optional branch"),
    "hypothesis": Json::string(
      "Base behavior remains; optional output is intentionally removed",
    ),
    "baseline": build,
    "current": build,
    "validation": Json::object({
      "status": Json::string("passed"),
      "command": Json::string("project regression command"),
      "notes": Json::string("Self-reported"),
    }),
  })
}

///|
test "experiments measure both files and whole streams without inventing context" {
  let b = minimal_module()
  let a = named_module()
  let forward = experiment_test_report(b, a)
  let backward = experiment_test_report(a, b)
  assert_eq(
    experiment_get(forward, "raw_delta"),
    int_json(a.length() - b.length()),
  )
  assert_eq(
    experiment_get(backward, "raw_delta"),
    int_json(b.length() - a.length()),
  )
  match (compressed_size(b), compressed_size(a)) {
    (Ok(b), Ok(a)) => {
      assert_eq(experiment_get(forward, "whole_gzip_delta"), int_json(a - b))
      assert_eq(experiment_get(backward, "whole_gzip_delta"), int_json(b - a))
    }
    _ => fail("fixture compression failed")
  }
  assert_eq(
    experiment_get(forward, "build_comparability"),
    Json::string("not-recorded"),
  )
  assert_eq(
    experiment_get(forward, "validation_status"),
    Json::string("not-recorded"),
  )
}

///|
test "experiment context rejects misleading malformed declarations" {
  let invalid = [
    Json::array([]),
    Json::object({ "unknown": Json::string("typo") }),
    Json::object({ "title": Json::string("title") }),
  ]
  for context in invalid {
    match check_experiment_context(context) {
      Err(_) => ()
      Ok(_) => fail("invalid context accepted")
    }
  }
  let context = experiment_test_context()
  assert_eq(check_experiment_context(context), Ok(()))
  if context is Object(fields) {
    if experiment_get(context, "current") is Object(settings) {
      settings.set("strip", Json::string("false"))
    }
    fields.set(
      "validation",
      Json::object({
        "status": Json::string("passed"),
        "command": Json::string(""),
        "notes": Json::string(""),
      }),
    )
  }
  match check_experiment_context(context) {
    Err(error) => assert_true(error.contains(".strip"))
    Ok(_) => fail("string masquerading as boolean accepted")
  }
}

///|
test "different builds and failed validation remain explicit even if a file shrinks" {
  let context = experiment_test_context()
  // Replacing the side avoids mutating the shared baseline declaration.
  if context is Object(fields) {
    let changed = Json::object({
      "revision": Json::string("after-sha"),
      "command": Json::string("moon build --target wasm --release"),
      "toolchain": Json::string("pinned-toolchain"),
      "target": Json::string("wasm"),
      "mode": Json::string("debug"),
      "strip": Json::boolean(false),
      "features": Json::array([]),
    })
    fields.set("current", changed)
    fields.set(
      "validation",
      Json::object({
        "status": Json::string("failed"),
        "command": Json::string("regression"),
        "notes": Json::string("Mismatch"),
      }),
    )
  }
  let report = experiment_test_report(
    named_module(),
    minimal_module(),
    context~,
  )
  assert_eq(
    experiment_get(report, "build_comparability"),
    Json::string("different-declared-settings"),
  )
  assert_eq(
    experiment_get(report, "different_build_fields"),
    Json::array([Json::string("mode"), Json::string("strip")]),
  )
  assert_eq(experiment_get(report, "validation_status"), Json::string("failed"))
  assert_true(
    render_experiment_html(report).contains(
      "A smaller artifact alone does not establish a successful optimization",
    ),
  )
}

///|
test "top zero suppresses rankings but keeps matching coverage and actual sizes" {
  let report = experiment_test_report(named_module(), named_module(), top=0)
  assert_eq(experiment_get(report, "functions"), Json::array([]))
  assert_eq(experiment_get(report, "packages"), Json::array([]))
  assert_eq(experiment_get(report, "raw_delta"), int_json(0))
  assert_eq(experiment_get(report, "whole_gzip_delta"), int_json(0))
  assert_true(experiment_get(report, "matching") != Json::null())
  assert_true(experiment_get(report, "function_record_count") != int_json(0))
}

///|
test "experiment parsing failures identify the input side" {
  for
    (before, after, side) in [
      (b"bad", minimal_module(), "baseline:"),
      (minimal_module(), b"bad", "current:"),
    ] {
    match experiment_report(before, after, "b", "a", Json::null()) {
      Err(error) => assert_true(error.has_prefix(side))
      Ok(_) => fail("malformed module accepted")
    }
  }
}

///|
test "experiment HTML escapes supplied markup and contains no executable scripts" {
  let context = experiment_test_context()
  if context is Object(fields) {
    fields.set("title", Json::string("<script>alert('test')</script> & report"))
  }
  let report = experiment_test_report(
    minimal_module(),
    minimal_module(),
    context~,
  )
  let html = render_experiment_html(report)
  assert_false(html.contains("<script>"))
  assert_false(html.contains("</script>"))
  assert_true(html.contains("&lt;script&gt;"))
  assert_true(html.contains("Self-reported"))
  assert_true(html.contains("SHA") || html.contains("sha256"))
}
