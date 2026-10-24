///|
fn search_test_leb(value : Int) -> Bytes {
  let bytes : Array[Byte] = []
  let mut remaining = value
  while remaining >= 128 {
    bytes.push(((remaining & 127) | 128).to_byte())
    remaining = remaining >> 7
  }
  bytes.push(remaining.to_byte())
  Bytes::from_array(bytes)
}

///|
fn search_test_section(id : Int, payload : Bytes) -> Bytes {
  Bytes::from_array([id.to_byte()]) +
  search_test_leb(payload.length()) +
  payload
}

///|
fn search_test_module(
  bodies : Array[Bytes],
  names : Array[(Int, String)],
) -> Bytes {
  let mut declarations = search_test_leb(bodies.length())
  let mut code = search_test_leb(bodies.length())
  for ordinal, body in bodies {
    declarations += b"\x00"
    code += (if ordinal == 1 {
        Bytes::from_array([(body.length() | 128).to_byte(), 0])
      } else {
        search_test_leb(body.length())
      }) +
      body
  }
  let mut data = b"\x00asm\x01\x00\x00\x00\x01\x04\x01\x60\x00\x00\x02\x07\x01\x01m\x01f\x00\x00" +
    search_test_section(3, declarations) +
    search_test_section(10, code)
  if !names.is_empty() {
    let mut entries = search_test_leb(names.length())
    for (index, name) in names {
      let bytes = @utf8.encode(name)
      entries += search_test_leb(index) +
        search_test_leb(bytes.length()) +
        bytes
    }
    data += search_test_section(
      0,
      b"\x04name" + search_test_section(1, entries),
    )
  }
  data
}

///|
fn search_test_report(
  data : Bytes,
  query : String,
) -> FunctionSearchReport raise {
  match search_local_functions(data, query) {
    Ok(report) => report
    Err(error) => fail(describe_function_search_error(error))
  }
}

///|
test "function-search: raw/display literal matches preserve indices, duplicate names, case and Unicode" {
  let raw = "_M0FP34demo6sample3src8classify"
  let data = search_test_module(
    [b"\x00\x0b", b"\x00\x0b", b"\x00\x0b", b"\x00\x0b", b"\x00\x0b"],
    [
      (0, "classify"),
      (1, raw),
      (2, raw),
      (3, "Classify*[.雪"),
      (4, "café"),
      (5, "cafe\u0301"),
    ],
  )
  let both = search_test_report(data, "classify")
  assert_eq(both.matches.map(fn(m) { m.index }), [2, 1])
  for item in both.matches {
    assert_true(item.matched_raw_name && item.matched_display_name)
    assert_eq(item.raw_name, raw)
    assert_eq(item.name, "demo::sample::src::classify")
    assert_eq(item.module_name, "demo::sample::src")
  }
  let raw_only = search_test_report(data, "_M0FP3")
  assert_eq(raw_only.match_count, 2)
  for item in raw_only.matches {
    assert_true(item.matched_raw_name && !item.matched_display_name)
  }
  let display_only = search_test_report(data, "demo::sample")
  assert_eq(display_only.match_count, 2)
  for item in display_only.matches {
    assert_true(!item.matched_raw_name && item.matched_display_name)
  }
  for query in ["Classify", "*[.", "雪"] {
    assert_eq(search_test_report(data, query).matches.map(fn(m) { m.index }), [
      3,
    ])
  }
  assert_eq(search_test_report(data, "CLASSIFY").match_count, 0)
  assert_eq(search_test_report(data, "café").matches[0].index, 4)
  assert_eq(search_test_report(data, "cafe\u0301").matches[0].index, 5)
}

///|
test "function-search: name coverage, real unnamed name, empty states and untrimmed query" {
  let no_names = search_test_module([b"\x00\x0b"], [])
  let absent = search_test_report(no_names, "(unnamed)")
  assert_eq(absent.local_function_count, 1)
  assert_eq(absent.named_count, 0)
  assert_eq(absent.unnamed_count, 1)
  assert_eq(absent.match_count, 0)
  assert_true(
    render_function_search(absent, 1).contains(
      "No usable local function names available.",
    ),
  )
  let data = search_test_module(
    [b"\x00\x0b", b"\x00\x0b", b"\x00\x0b", b"\x00\x0b"],
    [(1, "(unnamed)"), (2, ""), (3, " padded "), (4, "padded")],
  )
  let real = search_test_report(data, "(unnamed)")
  assert_eq(real.match_count, 1)
  assert_eq(real.matches[0].index, 1)
  assert_eq(real.named_count, 3)
  assert_eq(real.unnamed_count, 1)
  let padded = search_test_report(data, " padded ")
  assert_eq(padded.query, " padded ")
  assert_eq(padded.matches.map(fn(m) { m.index }), [3])
  assert_eq(search_test_report(data, "padded").match_count, 2)
  let none = search_test_report(data, "missing")
  assert_eq(none.match_count, 0)
  assert_true(
    render_function_search(none, 1).contains(
      "No matches in the available local function names.",
    ),
  )
  assert_true(render_function_search_json(none).contains("\"matches\": []"))
  let empty = search_test_report(b"\x00asm\x01\x00\x00\x00", "x")
  assert_eq(empty.local_function_count, 0)
  assert_true(
    render_function_search(empty, 1).contains("No local function definitions."),
  )
  for query in ["", " ", "\t\r\n"] {
    assert_true(
      search_local_functions(data, query) is Err(InvalidFunctionSearchQuery),
    )
  }
  assert_eq(Options::default("x").find_functions, None)
  assert_eq(Options::default("x").find_functions_json, None)
  match
    parse_options([
      "moonsize", "missing.wasm", "--find-functions", " padded ", "--find-functions-json",
      "new.json", "--top", "1",
    ]) {
    Ok(options) => {
      assert_eq(options.find_functions, Some(" padded "))
      assert_eq(options.top, 1)
    }
    Err(error) => fail(error)
  }
  for
    args in [
      ["--find-functions"],
      ["--find-functions", ""],
      ["--find-functions", "  "],
      ["--find-functions-json", "new.json"],
      ["--find-functions", "--top"],
      ["--find-functions", "x", "--find-functions-json"],
      ["--find-functions", "x", "--find-functions-json", "new.txt"],
      ["--find-functions", "x", "--strict"],
      ["--find-functions", "x", "--instructions", "1"],
      ["--find-functions", "x", "--callers", "1"],
      ["--find-functions", "x", "--why-index", "1"],
      ["--find-functions", "x", "--baseline", "old.wasm"],
      ["--find-functions", "x", "--html", "new.html"],
      ["--find-functions", "x", "--generics"],
      ["--find-functions", "x", "--budget-json", "new.json"],
    ] {
    assert_true(parse_options(["moonsize", "missing.wasm"] + args) is Err(_))
  }
}

///|
test "function-search: complete ledger and JSON, Top, terminal escaping, errors and no opcode decoding" {
  let raw = "_M0FP34demo6sample3src8classify"
  let unsafe_name = "classify\nrow\t\u001b\u0085\u2028雪"
  let data = search_test_module(
    [
      b"\x00\x0b", b"\x00\x01\x0b", b"\x00\x01\x01\x0b", b"\x00\x0b", b"\x00\x0b",
    ],
    [
      (0, "classify-import"),
      (1, raw),
      (2, raw),
      (3, unsafe_name),
      (4, "Classify"),
    ],
  )
  let r = search_test_report(data, "classify")
  assert_eq(r.matches.map(fn(m) { m.index }), [2, 3, 1])
  assert_eq(r.local_function_count, 5)
  assert_eq(r.named_count, 4)
  assert_eq(r.unnamed_count, 1)
  assert_eq(r.match_count, 3)
  assert_eq(r.unmatched_named_count, 1)
  assert_eq(r.local_function_count, r.named_count + r.unnamed_count)
  assert_eq(r.named_count, r.match_count + r.unmatched_named_count)
  assert_eq(r.matched_body_bytes, 9)
  assert_eq(r.matched_prefix_bytes, 4)
  assert_eq(r.matched_encoded_bytes, 13)
  assert_eq(
    r.matched_encoded_bytes,
    r.matched_body_bytes + r.matched_prefix_bytes,
  )
  assert_eq(r.sha256, experiment_sha256(data))
  assert_eq(r.file_size, data.length())
  let text = render_function_search(r, 1)
  assert_true(text.contains("MATCHES: showing 1 of 3"))
  assert_true(text.contains("2  3  5  raw+display"))
  assert_true(!text.contains("classify\\nrow"))
  let full = render_function_search(r, 3)
  assert_true(full.contains("classify\\nrow\\t\\u001b\\u0085\\u2028雪"))
  assert_true(!full.contains(unsafe_name))
  let query = search_test_report(data, "classify\n")
  assert_true(
    render_function_search(query, 1).contains("Query: \"classify\\n\""),
  )
  let json = render_function_search_json(r)
  assert_true(json.contains("moonsize-function-search"))
  assert_true(json.contains("\"index\": 1"))
  assert_true(json.contains("\"index\": 2"))
  assert_true(json.contains("\"index\": 3"))
  assert_true(json.contains("\"matched_encoded_bytes\": 13"))
  // JSON retains C1/Unicode content instead of terminal-escaped replacements.
  assert_true(json.contains("\u0085\u2028雪"))
  assert_true(!json.contains("graph_complete"))
  let undecoded = search_test_module([b"\x00\xff"], [(1, raw)])
  assert_eq(search_test_report(undecoded, "classify").matches[0].body_size, 2)
  let invalid = b"\x00asm\x02\x00\x00\x00"
  match (search_local_functions(invalid, "x"), parse_module(invalid)) {
    (Err(FunctionSearchInputError(error)), Err(original)) =>
      assert_eq(describe_error(error), describe_error(original))
    _ => fail("expected the original version error")
  }
}
