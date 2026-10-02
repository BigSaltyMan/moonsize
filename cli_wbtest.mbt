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
