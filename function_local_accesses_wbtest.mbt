///|
fn local_accesses_test_body() -> Bytes {
  // One group, 130 i32 locals; access indices 127/128; non-shortest tee index.
  b"\x01\x82\x01\x7f\x20\x7f\x1a\x41\x00\x21\x80\x01\x41\x01\x22\xff\x00\x1a\x20\x80\x01\x1a\x20\x7f\x1a\x0b"
}

///|
fn local_accesses_test_report(
  data : Bytes,
  index : Int,
) -> FunctionLocalAccessesReport raise {
  match inspect_function_local_accesses(data, index) {
    Ok(report) => report
    Err(error) => fail(describe_function_local_accesses_error(error))
  }
}

///|
test "function-local-accesses: original ordinals, three opcodes, widths and complete ledgers" {
  let data = instructions_test_module(
    local_accesses_test_body(),
    b"\x01\x01\x7f\x0b",
    named=true,
  )
  let r = local_accesses_test_report(data, 1)
  assert_eq(r.target.index, 1)
  assert_false(r.target.imported)
  assert_eq(r.target.raw_name, Some("target\"<&"))
  assert_eq(r.sha256, experiment_sha256(data))
  assert_eq(r.entry.file_offset, 31)
  assert_eq(r.prefix.size, 2)
  assert_eq(r.body.file_offset, 33)
  assert_eq(r.body.size, 26)
  assert_eq(r.locals_encoding.size, 4)
  assert_eq(r.instruction_count, 12)
  assert_eq(r.instruction_bytes, 22)
  assert_eq(r.access_count, 5)
  assert_eq(r.get_count, 3)
  assert_eq(r.set_count, 1)
  assert_eq(r.tee_count, 1)
  assert_eq(r.distinct_local_index_count, 2)
  assert_eq(r.access_encoding_bytes, 13)
  assert_eq(r.index_encoding_bytes, 8)
  assert_eq(r.other_instruction_bytes, 9)
  let ordinals = [0, 3, 5, 7, 9]
  let offsets = [37, 42, 47, 51, 55]
  let sizes = [2, 3, 3, 3, 2]
  let indices = [127, 128, 127, 128, 127]
  let opcodes = [LocalGet, LocalSet, LocalTee, LocalGet, LocalGet]
  for i, access in r.accesses {
    assert_eq(access.instruction_ordinal, ordinals[i])
    assert_eq(access.opcode.name(), opcodes[i].name())
    assert_eq(access.local_index, indices[i])
    assert_eq(access.file_offset, offsets[i])
    assert_eq(access.body_relative_offset, offsets[i] - 33)
    assert_eq(access.encoded_size, sizes[i])
    assert_eq(access.index_encoding.file_offset, offsets[i] + 1)
    assert_eq(access.index_encoding.size, sizes[i] - 1)
  }
  assert_eq(data_preview_hex(data[48:50]), "ff00")
  let a = r.groups[0]
  assert_eq(a.local_index, 127)
  assert_eq(a.instruction_ordinals, [0, 5, 9])
  assert_eq(a.access_count, 3)
  assert_eq(a.get_count, 2)
  assert_eq(a.set_count, 0)
  assert_eq(a.tee_count, 1)
  assert_eq(a.encoded_bytes, 7)
  assert_eq(a.index_encoding_bytes, 4)
  let b = r.groups[1]
  assert_eq(b.local_index, 128)
  assert_eq(b.instruction_ordinals, [3, 7])
  assert_eq(b.get_count, 1)
  assert_eq(b.set_count, 1)
  assert_eq(b.tee_count, 0)
  assert_eq(r.entry.size, r.prefix.size + r.body.size)
  assert_eq(r.body.size, r.locals_encoding.size + r.instruction_bytes)
  assert_eq(r.access_count, r.get_count + r.set_count + r.tee_count)
  assert_eq(
    r.instruction_bytes,
    r.access_encoding_bytes + r.other_instruction_bytes,
  )
  assert_eq(r.access_encoding_bytes, r.access_count + r.index_encoding_bytes)
  assert_eq(a.access_count + b.access_count, r.access_count)
  assert_eq(a.encoded_bytes + b.encoded_bytes, r.access_encoding_bytes)
  let text = render_function_local_accesses(r, 1)
  assert_true(text.contains("GROUPS: showing 1 of 2"))
  assert_true(text.contains("ACCESS SITES: showing 1 of 5"))
  assert_true(text.contains("[0,5,9]"))
  assert_false(text.contains("\n3  local.set"))
  assert_false(text.contains("\n128  2  1"))
  let json = match @json.parse(render_function_local_accesses_json(r)) {
    Object(fields) => fields
    _ => fail("object expected")
  }
  match json.get("accesses") {
    Some(Array(records)) => assert_eq(records.length(), 5)
    _ => fail("all accesses expected")
  }
  match json.get("groups") {
    Some(Array(groups)) => assert_eq(groups.length(), 2)
    _ => fail("all groups expected")
  }
}

///|
test "function-local-accesses: selective decode, empty result, sparse large indices and failures" {
  let data = instructions_test_module(
    local_accesses_test_body(),
    b"\x01\x01\x7f\x0b",
  )
  let empty = local_accesses_test_report(data, 2)
  assert_eq(empty.access_count, 0)
  assert_eq(empty.groups.length(), 0)
  assert_eq(empty.locals_encoding.size, 3)
  assert_eq(empty.instruction_bytes, 1)
  assert_true(
    inspect_function_local_accesses(data, 0)
    is Err(ImportedLocalAccessesTarget(0)),
  )
  assert_true(
    inspect_function_local_accesses(data, -1)
    is Err(InvalidLocalAccessesTarget(-1, 3)),
  )
  assert_true(
    inspect_function_local_accesses(data, 3)
    is Err(InvalidLocalAccessesTarget(3, 3)),
  )
  for
    body in [
      b"\x00\xff", b"\x00\x20", b"\x00\x20\x80", b"\x00\x20\x00\xff", b"\x00\x20\xff\xff\xff\xff\x10",
    ] {
    let result = inspect_function_local_accesses(
      instructions_test_module(body, b"\x00\x0b"),
      1,
    )
    assert_true(result is Err(LocalAccessesInputError(_)))
    assert_true(
      !describe_function_local_accesses_error(result.unwrap_err()).is_empty(),
    )
  }
  assert_true(
    inspect_function_local_accesses(
      instructions_test_module(b"\x00\x20\x80\x80\x80\x80\x08\x0b", b"\x00\x0b"),
      1,
    )
    is Err(LocalAccessesInputError(ValueOutOfRange(35, 2147483648U))),
  )
  let other_bad = instructions_test_module(
    local_accesses_test_body(),
    b"\x00\xff",
  )
  assert_eq(local_accesses_test_report(other_bad, 1).access_count, 5)
  // Encoded-index inspection only; not a semantically valid local binding.
  let huge = local_accesses_test_report(
    instructions_test_module(
      b"\x00\x20\xff\xff\xff\xff\x07\x1a\x0b", b"\x00\xff",
    ),
    1,
  )
  assert_eq(huge.groups.length(), 1)
  assert_eq(huge.groups[0].local_index, 2147483647)
  assert_eq(huge.accesses[0].index_encoding.size, 5)
  assert_eq(huge.access_encoding_bytes, 6)
  assert_true(
    inspect_function_local_accesses(b"bad", 1)
    is Err(LocalAccessesInputError(_)),
  )
}

///|
test "function-local-accesses: parameter routing, numeric ordering, safe names and empty text" {
  assert_eq(Options::default("x").local_accesses_index, None)
  assert_eq(Options::default("x").local_accesses_json, None)
  let args = [
    "moonsize", "--local-accesses", "1", "--local-accesses-json", "new.json", "--top",
    "1", "--", "--help",
  ]
  assert_eq(help_request(args).unwrap(), None)
  let options = parse_options(args).unwrap()
  assert_eq(options.local_accesses_index, Some(1))
  assert_eq(options.local_accesses_json, Some("new.json"))
  assert_eq(options.path, "--help")
  assert_eq(options.top, 1)
  assert_eq(
    parse_options(["moonsize", "x", "--local-accesses", "2147483647"]).unwrap().local_accesses_index,
    Some(2147483647),
  )
  for
    flags in [
      ["--local-accesses-json", "new.json"],
      ["--local-accesses"],
      ["--local-accesses", "-1"],
      ["--local-accesses", "2147483648"],
      ["--local-accesses", "0x1"],
      ["--local-accesses", "1.5"],
      ["--local-accesses", "1", "--local-accesses-json"],
      ["--local-accesses", "1", "--local-accesses-json", ""],
      ["--local-accesses", "1", "--local-accesses-json", "bad.txt"],
      ["--local-accesses", "1", "--locals", "1"],
      ["--local-accesses", "1", "--baseline-locals", "1"],
      ["--local-accesses", "1", "--baseline", "b"],
      ["--local-accesses", "1", "--strict"],
      ["--local-accesses", "1", "--calls", "1"],
      ["--local-accesses", "1", "--instructions", "1"],
      ["--local-accesses", "1", "--locate-decode"],
      ["--local-accesses", "1", "--data-preview", "0"],
      ["--local-accesses", "1", "--html", "new.html"],
      ["--local-accesses", "1", "--budget", "b.json"],
    ] {
    assert_true(parse_options(["moonsize", "x"] + flags) is Err(_))
  }
  assert_true(
    parse_options(["moonsize", "--local-accesses", "1", "--", "x", "--top", "1"])
    is Err(_),
  )
  assert_true(help_request(["moonsize", "--help"]).unwrap() is Some(_))
  let name = "line\n\u001b\u0085雪"
  let bytes = @utf8.encode(name)
  let data = instructions_test_module(
      b"\x00\x20\x0a\x1a\x22\x02\x1a\x20\x0a\x1a\x0b", b"\x00\xff",
    ) +
    instructions_test_section(
      0,
      b"\x04name" +
      instructions_test_section(
        1,
        b"\x01\x01" + search_test_leb(bytes.length()) + bytes,
      ),
    )
  let r = local_accesses_test_report(data, 1)
  assert_eq(r.groups.map(fn(group) { group.local_index }), [2, 10])
  assert_eq(r.groups[1].instruction_ordinals, [0, 4])
  let text = render_function_local_accesses(r, 1)
  assert_true(text.contains(search_terminal_string(name)))
  assert_false(text.contains(name))
  let json = render_function_local_accesses_json(r)
  assert_true(json.contains("\"format\": \"moonsize-function-local-accesses\""))
  assert_false(json.contains("\"graph_complete\""))
  assert_false(json.contains("\"variable_name\""))
  let empty = local_accesses_test_report(
    instructions_test_module(b"\x01\x01\x7f\x0b", b"\x00\xff"),
    1,
  )
  assert_true(
    render_function_local_accesses(empty, 1).contains(
      "No local.get/local.set/local.tee access instructions",
    ),
  )
  assert_true(
    render_function_local_accesses(empty, 1).contains(
      "does not imply no variables",
    ),
  )
}
