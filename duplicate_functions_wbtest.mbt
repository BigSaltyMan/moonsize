///|
fn duplicate_test_section(id : Int, payload : Bytes) -> Bytes raise {
  assert_true(payload.length() < 128)
  Bytes::from_array([id.to_byte(), payload.length().to_byte()]) + payload
}

///|
/// Reuse the existing complete body encoder, changing only the tiny type/code
/// payloads needed here. No instruction normalization or compiler probe.
fn duplicate_test_module(named? : Bool = true) -> Bytes raise {
  let bodies = [
    b"\x00\x0b", b"\x00\x0b", b"\x00\x0b", b"\x00\x01\x0b", b"\x00\x01\x0b", b"\x00\x00\x0b",
    b"\x00\x00\x0b", b"\x00\x01\x01\x0b", b"\x00\x01\x01\x0b", b"\x01\x01\x7f\x0b", // Same instructions as the first group, different locals.
  ]
  let base = tail_module(bodies, imported=true)
  let parsed = parse_module(base).unwrap()
  let mut out = b"\x00asm\x01\x00\x00\x00"
  for section in parsed.sections {
    match section.kind {
      Type =>
        out += duplicate_test_section(1, b"\x02\x60\x00\x00\x60\x01\x7f\x00")
      Function =>
        out += duplicate_test_section(
          3, b"\x0a\x00\x01\x00\x00\x01\x00\x00\x00\x01\x00",
        )
      Code => {
        let mut payload = b"\x0a"
        for ordinal, body in bodies {
          payload += (if ordinal == 8 {
              b"\x84\x00"
            } else {
              Bytes::from_array([body.length().to_byte()])
            }) +
            body
        }
        out += duplicate_test_section(10, payload)
      }
      Export => ()
      _ =>
        out += base[section.offset:section.offset + section.total_size].to_owned()
    }
  }
  if named {
    let mut names = b"\x06"
    for
      (index, name) in [
        (1, "alpha"),
        (2, "beta"),
        (4, "same"),
        (6, "same"),
        (8, "prefix-one"),
        (9, "prefix-two\"\n雪"),
      ] {
      let bytes = @utf8.encode(name)
      names += Bytes::from_array([index.to_byte(), bytes.length().to_byte()]) +
        bytes
    }
    out += duplicate_test_section(
      0,
      b"\x04name" + duplicate_test_section(1, names),
    )
  }
  out
}

///|
fn duplicate_test_report(data : Bytes) -> DuplicateFunctionsReport raise {
  match inspect_duplicate_functions(data) {
    Ok(report) => report
    Err(error) => fail(describe_error(error))
  }
}

///|
fn duplicate_test_ledger(report : DuplicateFunctionsReport) -> Unit raise {
  let s = report.summary
  assert_eq(
    s.local_function_count,
    s.duplicate_member_count + s.singleton_function_count,
  )
  assert_eq(s.total_body_bytes, s.duplicate_body_bytes + s.singleton_body_bytes)
  assert_eq(s.total_encoded_bytes, s.total_body_bytes + s.total_prefix_bytes)
  let seen : Set[Int] = Set([])
  let mut body = 0
  for group in report.groups {
    assert_eq(group.member_count, group.members.length())
    assert_eq(group.member_body_bytes, group.member_count * group.body_size)
    assert_eq(
      group.member_total_bytes,
      group.member_body_bytes + group.member_prefix_bytes,
    )
    let mut prefixes = 0
    for definition in group.members {
      assert_false(seen.contains(definition.index))
      seen.add(definition.index)
      assert_eq(
        definition.body_offset,
        definition.offset + definition.prefix_size,
      )
      assert_eq(
        definition.total_size,
        definition.body_size + definition.prefix_size,
      )
      prefixes += definition.prefix_size
    }
    assert_eq(group.member_prefix_bytes, prefixes)
    body += group.member_body_bytes
  }
  assert_eq(seen.length(), s.duplicate_member_count)
  assert_eq(body, s.duplicate_body_bytes)
}

///|
test "duplicates: exact bodies, type/prefix/name independence, sorting and complete JSON" {
  let data = duplicate_test_module()
  let report = duplicate_test_report(data)
  duplicate_test_ledger(report)
  assert_eq(report.file_size, data.length())
  assert_eq(report.sha256.length(), 64)
  assert_eq(report.summary.local_function_count, 10)
  assert_eq(report.summary.duplicate_group_count, 4)
  assert_eq(report.summary.duplicate_member_count, 9)
  assert_eq(report.summary.singleton_function_count, 1)
  assert_eq(report.summary.total_body_bytes, 30)
  assert_eq(report.summary.duplicate_body_bytes, 26)
  assert_eq(report.summary.total_prefix_bytes, 11)
  assert_eq(report.summary.total_encoded_bytes, 41)
  assert_eq(report.groups.map(fn(g) { g.member_body_bytes }), [8, 6, 6, 6])
  assert_eq(report.groups.map(fn(g) { g.body_size }), [4, 3, 3, 2])
  assert_true(report.groups[1].sha256.compare(report.groups[2].sha256) < 0)
  let first = report.groups[0]
  assert_eq(first.members.map(fn(d) { d.index }), [8, 9])
  assert_eq(first.members.map(fn(d) { d.type_index }), [0, 1])
  assert_eq(first.members.map(fn(d) { d.prefix_size }), [1, 2])
  assert_eq(first.members.map(fn(d) { d.total_size }), [5, 6])
  assert_eq(first.member_total_bytes, 11)
  let second = first.members[1]
  assert_eq(data[second.offset:second.body_offset].to_owned(), b"\x84\x00")
  assert_eq(report.groups[3].members.map(fn(d) { d.index }), [1, 2, 3])
  assert_eq(report.groups[3].members[0].raw_name, Some("alpha"))
  assert_eq(report.groups[3].members[1].raw_name, Some("beta"))
  for group in report.groups {
    for definition in group.members {
      let bytes = Reader::new_range(
          data,
          definition.body_offset,
          definition.body_size,
        )
        .unwrap()
        .read_bytes(definition.body_size)
        .unwrap()
      assert_eq(experiment_sha256(bytes.to_owned()), group.sha256)
      assert_true(definition.index != 10) // Locals differ even though end is identical.
    }
  }
  let text = render_duplicate_functions(report, 1)
  assert_true(text.contains("Showing 1 of 4 duplicate groups"))
  assert_true(text.contains("TYPE INDEX  PREFIX B"))
  assert_true(text.contains("prefix-two\\\"\\n雪"))
  let json = render_duplicate_functions_json(report)
  assert_true(json.contains("moonsize-duplicate-function-bodies"))
  assert_true(json.contains("alpha")) // Not in the Top1 text group.
  assert_true(json.contains("\"raw_name\": null"))
  assert_false(json.contains("graph_complete"))
}

///|
test "duplicates: collision candidates require bytes; no names, no groups and safe ranges" {
  let data = duplicate_test_module(named=false)
  let report = duplicate_test_report(data)
  duplicate_test_ledger(report)
  for group in report.groups {
    for definition in group.members {
      assert_eq(definition.raw_name, None)
    }
  }
  let buckets : Array[DuplicateBodyBucket] = []
  let by_digest : Map[String, Array[Int]] = Map([])
  // Force one private digest bucket for two different three-byte bodies. Insert
  // reverse order to exercise the smallest-member-index tie breaker as well.
  for group_index in [2, 1, 2, 1] {
    let group = report.groups[group_index]
    let which = if buckets.length() < 2 { 0 } else { 1 }
    let definition = group.members[which]
    let bytes = Reader::new_range(
        data,
        definition.body_offset,
        definition.body_size,
      )
      .unwrap()
      .read_bytes(definition.body_size)
      .unwrap()
    duplicate_insert(
      buckets, by_digest, "forced-private-collision", bytes, definition,
    )
  }
  assert_eq(buckets.length(), 2)
  let collision_groups = duplicate_groups(buckets)
  assert_eq(collision_groups.length(), 2)
  assert_eq(collision_groups.map(fn(g) { g.members[0].index }), [4, 6])
  let single = duplicate_test_report(minimal_module())
  duplicate_test_ledger(single)
  assert_eq(single.summary.singleton_function_count, 1)
  assert_true(
    render_duplicate_functions(single, 10).contains(
      "No identical function bodies found.",
    ),
  )
  let empty = duplicate_test_report(b"\x00asm\x01\x00\x00\x00")
  duplicate_test_ledger(empty)
  assert_eq(empty.summary.local_function_count, 0)
  let imports = duplicate_test_report(
    b"\x00asm\x01\x00\x00\x00\x01\x04\x01\x60\x00\x00\x02\x07\x01\x01m\x01f\x00\x00",
  )
  assert_eq(imports.summary.local_function_count, 0)
  assert_eq(imports.groups.length(), 0)
  assert_true(inspect_duplicate_functions(b"bad") is Err(_))
  assert_true(
    duplicate_body_view(b"\x02\x00\x0b", {
      index: 0,
      offset: 1,
      total_size: 2147483647,
      body_size: 2,
    })
    is Err(_),
  )
}

///|
test "duplicates: independent CLI accepts only Top and new JSON" {
  let options = parse_options([
    "moonsize", "missing.wasm", "--duplicates-json", "new.json", "--top", "0",
  ]).unwrap()
  assert_true(options.duplicates)
  assert_eq(options.duplicates_json, Some("new.json"))
  assert_eq(options.top, 0)
  assert_false(Options::default("x.wasm").duplicates)
  assert_eq(Options::default("x.wasm").duplicates_json, None)
  for
    args in [
      ["--duplicates-json"],
      ["--duplicates-json", ""],
      ["--duplicates-json", "new.txt"],
      ["--duplicates", "--strict"],
      ["--duplicates", "--entrypoints"],
      ["--duplicates", "--generics"],
      ["--duplicates", "--callers", "0"],
      ["--duplicates", "--html", "new.html"],
      ["--duplicates", "--baseline", "b.wasm"],
    ] {
    assert_true(parse_options(["moonsize", "missing.wasm"] + args) is Err(_))
  }
}
