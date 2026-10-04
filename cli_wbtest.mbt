///|
test "defaults to the ten heaviest functions" {
  match parse_options(["moonsize", "app.wasm"]) {
    Ok(options) => {
      inspect(options.path, content="app.wasm")
      inspect(options.top, content="10")
    }
    Err(message) => fail(message)
  }
}

///|
test "reads --top before or after the file" {
  match parse_options(["moonsize", "--top", "3", "app.wasm"]) {
    Ok(options) => {
      inspect(options.path, content="app.wasm")
      inspect(options.top, content="3")
    }
    Err(message) => fail(message)
  }
  match parse_options(["moonsize", "app.wasm", "--top", "25"]) {
    Ok(options) => inspect(options.top, content="25")
    Err(message) => fail(message)
  }
}

///|
test "keeps the last --top when it is repeated" {
  match parse_options(["moonsize", "app.wasm", "--top", "2", "--top", "7"]) {
    Ok(options) => inspect(options.top, content="7")
    Err(message) => fail(message)
  }
}

///|
test "accepts --top 0, which asks for the summary on its own" {
  match parse_options(["moonsize", "app.wasm", "--top", "0"]) {
    Ok(options) => inspect(options.top, content="0")
    Err(message) => fail(message)
  }
}

///|
test "rejects a --top that is not a whole number" {
  match parse_options(["moonsize", "app.wasm", "--top", "many"]) {
    Err(message) =>
      inspect(message.contains("--top wants a whole number"), content="true")
    Ok(_) => fail("expected a rejected --top")
  }
}

///|
test "rejects a --top with no value after it" {
  match parse_options(["moonsize", "app.wasm", "--top"]) {
    Err(message) =>
      inspect(message.contains("--top needs a number"), content="true")
    Ok(_) => fail("expected a rejected --top")
  }
}

///|
test "rejects a second file, so a typo never analyzes the wrong one" {
  match parse_options(["moonsize", "a.wasm", "b.wasm"]) {
    Err(message) =>
      inspect(message.contains("unexpected argument b.wasm"), content="true")
    Ok(_) => fail("expected a rejected second path")
  }
}

///|
test "asks for usage when there is no file at all" {
  match parse_options(["moonsize"]) {
    Err(message) => inspect(message.contains("usage: moonsize"), content="true")
    Ok(_) => fail("expected usage")
  }
}

///|
test "counts decimal text and nothing else" {
  assert_eq(parse_count("0"), Some(0))
  assert_eq(parse_count("10"), Some(10))
  assert_eq(parse_count("0042"), Some(42))
  assert_eq(parse_count(""), None)
  assert_eq(parse_count("-1"), None)
  assert_eq(parse_count("1.5"), None)
  assert_eq(parse_count("0x10"), None)
  assert_eq(parse_count("12 "), None)
}

///|
test "rejects a count large enough to overflow the accumulation" {
  assert_eq(parse_count("99999999999999999999"), None)
}

///|
test "the report flags default to off" {
  match parse_options(["moonsize", "app.wasm"]) {
    Ok(options) => {
      inspect(
        options.retained,
        content=(
          #|false
        ),
      )
      inspect(
        options.dead_code,
        content=(
          #|false
        ),
      )
      assert_eq(options.call_graph, None)
    }
    Err(message) => fail(message)
  }
}

///|
test "the report flags turn their sections on, together or apart" {
  match parse_options(["moonsize", "app.wasm", "--retained"]) {
    Ok(options) => {
      inspect(
        options.retained,
        content=(
          #|true
        ),
      )
      inspect(
        options.dead_code,
        content=(
          #|false
        ),
      )
    }
    Err(message) => fail(message)
  }
  match parse_options(["moonsize", "app.wasm", "--dead-code"]) {
    Ok(options) => {
      inspect(
        options.retained,
        content=(
          #|false
        ),
      )
      inspect(
        options.dead_code,
        content=(
          #|true
        ),
      )
    }
    Err(message) => fail(message)
  }
  match
    parse_options([
      "moonsize", "--retained", "app.wasm", "--dead-code", "--top", "5",
    ]) {
    Ok(options) => {
      inspect(
        options.retained,
        content=(
          #|true
        ),
      )
      inspect(
        options.dead_code,
        content=(
          #|true
        ),
      )
      inspect(
        options.top,
        content=(
          #|5
        ),
      )
    }
    Err(message) => fail(message)
  }
}

///|
test "the call graph flag takes a path" {
  match parse_options(["moonsize", "app.wasm", "--call-graph", "graph.dot"]) {
    Ok(options) => assert_eq(options.call_graph, Some("graph.dot"))
    Err(message) => fail(message)
  }
}

///|
test "writing a graph excludes the report sections" {
  match
    parse_options([
      "moonsize", "app.wasm", "--call-graph", "graph.dot", "--retained",
    ]) {
    Err(message) =>
      inspect(
        message.contains("cannot be combined"),
        content=(
          #|true
        ),
      )
    Ok(_) => fail("expected the combination to be rejected")
  }
  match
    parse_options([
      "moonsize", "app.wasm", "--dead-code", "--call-graph", "graph.json",
    ]) {
    Err(message) =>
      inspect(
        message.contains("cannot be combined"),
        content=(
          #|true
        ),
      )
    Ok(_) => fail("expected the combination to be rejected")
  }
}

///|
test "the call graph flag needs a path" {
  match parse_options(["moonsize", "app.wasm", "--call-graph"]) {
    Err(message) =>
      inspect(
        message.contains("--call-graph needs a path"),
        content=(
          #|true
        ),
      )
    Ok(_) => fail("expected a rejected --call-graph")
  }
}

///|
test "the html flag takes a path" {
  match parse_options(["moonsize", "app.wasm", "--html", "report.html"]) {
    Ok(options) => assert_eq(options.html, Some("report.html"))
    Err(message) => fail(message)
  }
}

///|
test "the html flag defaults to off" {
  match parse_options(["moonsize", "app.wasm"]) {
    Ok(options) => assert_eq(options.html, None)
    Err(message) => fail(message)
  }
}

///|
test "the html flag needs a path" {
  match parse_options(["moonsize", "app.wasm", "--html"]) {
    Err(message) =>
      inspect(
        message.contains("--html needs a path"),
        content=(
          #|true
        ),
      )
    Ok(_) => fail("expected a rejected --html")
  }
}

///|
test "writing an html report excludes the text sections" {
  match
    parse_options(["moonsize", "app.wasm", "--html", "r.html", "--retained"]) {
    Err(message) =>
      inspect(
        message.contains("cannot be combined"),
        content=(
          #|true
        ),
      )
    Ok(_) => fail("expected the combination to be rejected")
  }
  match
    parse_options(["moonsize", "app.wasm", "--dead-code", "--html", "r.html"]) {
    Err(message) =>
      inspect(
        message.contains("cannot be combined"),
        content=(
          #|true
        ),
      )
    Ok(_) => fail("expected the combination to be rejected")
  }
}

///|
test "the two file outputs are mutually exclusive" {
  match
    parse_options([
      "moonsize", "app.wasm", "--call-graph", "g.dot", "--html", "r.html",
    ]) {
    Err(message) =>
      inspect(
        message.contains("cannot be combined"),
        content=(
          #|true
        ),
      )
    Ok(_) => fail("expected the combination to be rejected")
  }
}

///|
test "reads --max-size in bytes, kilobytes and megabytes" {
  match parse_options(["moonsize", "app.wasm", "--max-size", "1024"]) {
    Ok(options) => assert_eq(options.max_size, Some(1024))
    Err(message) => fail(message)
  }
  // A bare suffix is binary: 10KB is 10240 bytes, not 10000.
  match parse_options(["moonsize", "app.wasm", "--max-size", "10KB"]) {
    Ok(options) => assert_eq(options.max_size, Some(10240))
    Err(message) => fail(message)
  }
  assert_eq(parse_size("1.5MB"), Some(1572864))
  // The suffix is not case sensitive.
  assert_eq(parse_size("2mb"), Some(2097152))
  assert_eq(parse_size("1GB"), Some(1073741824))
  assert_eq(parse_size("512b"), Some(512))
}

///|
test "rejects a --max-size that is not a size" {
  for text in ["abc", "", "10XB", "KB", "1.5", "1.2.3MB", "-1", "10 KB"] {
    assert_eq(parse_size(text), None)
  }
  match parse_options(["moonsize", "app.wasm", "--max-size", "abc"]) {
    Ok(_) => fail("--max-size abc should be rejected")
    Err(message) =>
      assert_true(message.contains("--max-size wants a byte count"))
  }
  match parse_options(["moonsize", "app.wasm", "--max-size"]) {
    Ok(_) => fail("a bare --max-size should be rejected")
    Err(message) => assert_true(message.contains("--max-size needs a size"))
  }
}

///|
test "refuses a size past what an Int can hold" {
  // The ceiling is what keeps a long digit run from wrapping round instead of
  // being rejected.
  assert_eq(parse_size("99999999999999999999"), None)
  assert_eq(parse_size("999999GB"), None)
}

///|
test "reads --baseline as a path" {
  match parse_options(["moonsize", "app.wasm", "--baseline", "main.wasm"]) {
    Ok(options) => {
      inspect(options.path, content="app.wasm")
      assert_eq(options.baseline, Some("main.wasm"))
    }
    Err(message) => fail(message)
  }
  match parse_options(["moonsize", "app.wasm", "--baseline"]) {
    Ok(_) => fail("a bare --baseline should be rejected")
    Err(message) => assert_true(message.contains("--baseline needs a path"))
  }
}

///|
test "--max-size and --baseline can be used together" {
  match
    parse_options([
      "moonsize", "app.wasm", "--max-size", "2KB", "--baseline", "main.wasm",
    ]) {
    Ok(options) => {
      assert_eq(options.max_size, Some(2048))
      assert_eq(options.baseline, Some("main.wasm"))
      // The size gate is orthogonal to the output modes, so it combines with
      // them rather than being rejected the way two output modes are.
      inspect(options.retained, content="false")
    }
    Err(message) => fail(message)
  }
  match
    parse_options([
      "moonsize", "app.wasm", "--baseline", "main.wasm", "--max-size", "512B", "--retained",
      "--dead-code",
    ]) {
    Ok(options) => {
      assert_eq(options.max_size, Some(512))
      inspect(options.retained, content="true")
    }
    Err(message) => fail(message)
  }
}

///|
/// A library caller builds its options here, because `Options` is read-only:
/// nothing outside this package can write one with a record literal. The values
/// have to agree with what an absent flag means on the command line, or the two
/// entry points would drift apart.
test "Options::default matches an absent flag" {
  let options = Options::default("app.wasm")
  // Compared with `assert_eq` rather than `inspect`, because inspecting an
  // `Options` would need it to implement `Show`, and the core library has
  // deprecated that in favour of `Debug`.
  assert_eq(options.path, "app.wasm")
  assert_eq(options.top, 10)
  assert_eq(options.retained, false)
  assert_eq(options.dead_code, false)
  assert_eq(options.call_graph, None)
  assert_eq(options.html, None)
  assert_eq(options.max_size, None)
  assert_eq(options.baseline, None)
  assert_eq(options.compress, false)
  // The same starting point the parser uses, so `moonsize app.wasm` and
  // `Options::default("app.wasm")` cannot disagree.
  match parse_options(["moonsize", "app.wasm"]) {
    Ok(parsed) => {
      assert_eq(parsed.path, options.path)
      assert_eq(parsed.top, options.top)
      assert_eq(parsed.retained, options.retained)
      assert_eq(parsed.dead_code, options.dead_code)
      assert_eq(parsed.call_graph, options.call_graph)
      assert_eq(parsed.html, options.html)
      assert_eq(parsed.max_size, options.max_size)
      assert_eq(parsed.baseline, options.baseline)
      assert_eq(parsed.compress, options.compress)
    }
    Err(message) => fail(message)
  }
}
