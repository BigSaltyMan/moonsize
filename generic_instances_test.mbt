///|
// Reuse the existing complete-module encoder; run only this new file locally.
fn generics_inspected(data : Bytes) -> @moonsize.GenericInstancesReport raise {
  match @moonsize.inspect_generic_instances(data) {
    Ok(report) => report
    Err(error) => fail(@moonsize.describe_error(error))
  }
}

///|
fn generics_ledger(report : @moonsize.GenericInstancesReport) -> Unit raise {
  let c = report.coverage
  assert_eq(
    c.total_functions,
    c.grouped_functions + c.named_ungrouped_functions + c.unnamed_functions,
  )
  assert_eq(
    c.total_size,
    c.grouped_size + c.named_ungrouped_size + c.unnamed_size,
  )
  let mut size = 0
  let mut count = 0
  for family in report.families {
    let mut family_size = 0
    for instance in family.instances {
      family_size += instance.total_size
    }
    assert_eq(family.total_size, family_size)
    assert_eq(family.definition_count, family.instances.length())
    size += family_size
    count += family.definition_count
  }
  assert_eq(size, c.grouped_size)
  assert_eq(count, c.grouped_functions)
}

///|
test "generics: raw identity, duplicate encodings, size ledger and full JSON" {
  let stem = "_M0FP25probe8generics13generic__keep"
  let data = diff_module(
    [
      (Some(stem + "GiE"), 0),
      (Some(stem + "GdE"), 2),
      (Some(stem + "GiE"), 1), // Distinct index, same symbol: count both.
      (Some("_M0MP25probe8generics6Holder3getGiE"), 128),
      (Some("_M0FP25other8generics13generic__keepGiE"), 0),
      (Some("_M0MP25probe8generics6Holder3getGdE"), 0),
      (Some("_M0FP25probe8generics13generic__keepGqE"), 0),
      (Some(stem + "GiEC1l2"), 0),
      (Some("_M0IP25probe8generics13generic__keepGiE"), 0),
      (Some("_M0FP25probe8generics13generic__keepGiEjunk"), 0),
      (Some("_M0FP25probe8generics13generic__keepGi"), 0),
      (Some("plain\"\\\n雪"), 0),
      (None, 0),
      // G/i/E inside a length-prefixed identifier is not a generic suffix.
      (Some("_M0FP25probe8generics3GiE"), 0),
      // Two complete path interpretations; never choose one heuristically.
      (Some("_M0FP111a1b1c1d1e1f1gGiE"), 0),
    ],
    imported=2,
  )
  let report = generics_inspected(data)
  assert_eq(report.file_size, data.length())
  assert_eq(report.sha256.length(), 64)
  assert_eq(report.name_status, "available")
  generics_ledger(report)
  assert_eq(report.families.length(), 3)
  assert_eq(report.coverage.grouped_functions, 6)
  assert_eq(report.coverage.named_ungrouped_functions, 8)
  assert_eq(report.coverage.unnamed_functions, 1)
  let method_family = report.families[0]
  assert_eq(method_family.family_key, "_M0MP25probe8generics6Holder3get")
  assert_eq(method_family.total_size, 135) // 130-byte body + 2-byte prefix, then 3.
  assert_eq(method_family.definition_count, 2)
  let family = report.families[1]
  assert_eq(family.family_key, stem)
  assert_eq(family.definition_count, 3)
  assert_eq(family.type_encoding_count, 2)
  assert_eq(family.total_size, 12)
  assert_eq(family.instances.map(fn(i) { i.index }), [2, 3, 4])
  assert_eq(family.instances[1].raw_type_arguments, "GdE")
  assert_eq(family.instances[1].type_labels, ["Double"])
  let text = @moonsize.render_generic_instances(report, 1)
  assert_true(text.contains("Showing 1 of 3 families"))
  assert_true(text.contains("Grouped generic: 6 / 150 B"))
  assert_false(text.contains("Family: \"probe::generics::generic_keep\""))
  let json = @moonsize.render_generic_instances_json(report)
  assert_true(json.contains("moonsize-generic-instances"))
  assert_true(json.contains(stem + "GdE"))
  assert_true(json.contains("other::generics::generic_keep"))
  assert_false(json.contains("graph_complete"))
  // Equal weights have stable raw-key ordering, independent of input order.
  let tied = generics_inspected(
    diff_module([
      (Some("_M0FP25probe8generics1zGiE"), 0),
      (Some("_M0FP25probe8generics1aGdE"), 0),
    ]),
  )
  assert_eq(tied.families.map(fn(f) { f.family_key }), [
    "_M0FP25probe8generics1a", "_M0FP25probe8generics1z",
  ])
}

///|
test "generics: missing, unreadable and unsupported names never imply no generics" {
  let unnamed = diff_module([(None, 0)])
  let missing = generics_inspected(unnamed)
  assert_eq(missing.name_status, "missing")
  assert_eq(missing.coverage.unnamed_size, 3)
  generics_ledger(missing)
  assert_true(
    @moonsize.render_generic_instances(missing, 10).contains(
      "does not establish that the project has no generics",
    ),
  )
  let damaged = generics_inspected(unnamed + b"\x00\x08\x04name\x01\x05\x01")
  assert_eq(damaged.name_status, "unreadable")
  assert_eq(damaged.coverage.unnamed_functions, 1)
  generics_ledger(damaged)
  let ordinary = generics_inspected(diff_module([(Some("ordinary"), 0)]))
  assert_eq(ordinary.name_status, "available")
  assert_eq(ordinary.coverage.named_ungrouped_functions, 1)
  assert_eq(ordinary.families.length(), 0)
  generics_ledger(ordinary)
  assert_true(@moonsize.inspect_generic_instances(b"bad") is Err(_))
}

///|
test "generics: independent CLI mode, defaults, JSON dependency and Top" {
  let options = @moonsize.parse_options([
    "moonsize", "missing.wasm", "--generics-json", "new.json", "--top", "0",
  ]).unwrap()
  assert_true(options.generics)
  assert_eq(options.generics_json, Some("new.json"))
  assert_eq(options.top, 0)
  assert_false(@moonsize.Options::default("app.wasm").generics)
  assert_eq(@moonsize.Options::default("app.wasm").generics_json, None)
  for
    args in [
      ["--generics-json"],
      ["--generics-json", ""],
      ["--generics-json", "new.txt"],
      ["--generics", "--strict"],
      ["--generics", "--html", "new.html"],
      ["--generics", "--data-segments"],
      ["--generics", "--callers", "0"],
      ["--generics", "--why-index", "0"],
      ["--generics", "--budget", "b.json"],
      ["--generics", "--compress"],
    ] {
    assert_true(
      @moonsize.parse_options(["moonsize", "missing.wasm"] + args) is Err(_),
    )
  }
}
