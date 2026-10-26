///|
fn help_test_text(args : Array[String]) -> String raise {
  match help_request(args) {
    Ok(Some(text)) => text
    Ok(None) => fail("expected a help request")
    Err(message) => fail(message)
  }
}

///|
test "help-topics: first-argument dispatch, exact IDs, errors and business-value isolation" {
  assert_eq(help_test_text(["moonsize", "--help"]), usage())
  assert_eq(help_test_text(["moonsize", "-h"]), usage())
  assert_true(
    help_test_text(["moonsize", "--help-topic", "functions"]).contains(
      "--instructions",
    ),
  )
  for
    args in [
      ["moonsize", "--help", "functions"],
      ["moonsize", "-h", "app.wasm"],
      ["moonsize", "--help-topic"],
      ["moonsize", "--help-topic", ""],
      ["moonsize", "--help-topic", " \t "],
      ["moonsize", "--help-topic", "nonexistent"],
      ["moonsize", "--help-topic", "Functions"],
      ["moonsize", "--help-topic", "functions "],
      ["moonsize", "--help-topic", "ci", "--summary-json", "new.json"],
    ] {
    match help_request(args) {
      Err(message) => {
        assert_true(message.contains("moonsize --help-topic <topic>"))
        assert_true(message.contains("Available topics"))
        for
          id in [
            "overview", "functions", "data", "interfaces", "metadata", "baseline",
            "ci",
          ] {
          assert_true(message.contains("  " + id + "  "))
        }
      }
      _ => fail("expected help syntax error")
    }
  }
  for
    args in [
      [],
      ["moonsize"],
      ["moonsize", "--HELP"],
      ["moonsize", "app.wasm", "--top", "20"],
      ["moonsize", "app.wasm", "--find-functions", "--help"],
      ["moonsize", "app.wasm", "--html", "--help"],
      ["moonsize", "--top", "20", "--help-topic", "ci"],
    ] {
    match help_request(args) {
      Ok(None) => ()
      _ => fail("business argv was intercepted")
    }
  }
  // The existing query parser rejects flag-shaped values; it is still in charge.
  assert_true(
    parse_options(["moonsize", "app.wasm", "--find-functions", "--help"])
    is Err(_),
  )
  assert_true(parse_options(["moonsize"]) is Err(_))
}

///|
test "help-topics: seven discoverable structured topics, complete usage and scope boundaries" {
  let topics = help_topics()
  let ids = topics.map(fn(topic) { topic.id })
  assert_eq(ids, [
    "overview", "functions", "data", "interfaces", "metadata", "baseline", "ci",
  ])
  let complete = help_test_text(["moonsize", "--help"])
  assert_true(complete.has_prefix("usage: moonsize <file.wasm>"))
  assert_true(complete.contains("--why-json"))
  assert_true(complete.contains("--diff-exports"))
  assert_true(complete.contains("Exit codes: 0 completed"))
  for topic in topics {
    let args = ["moonsize", "--help-topic", topic.id]
    let text = help_test_text(args)
    assert_eq(text, help_test_text(args))
    assert_true(text.contains(topic.title))
    assert_true(topic.summary.length() > 0 && topic.options.length() > 0)
    assert_true(topic.examples.length() >= 2 && topic.examples.length() <= 3)
    for
      label in [
        "Options", "Examples", "Limits", "Related topics", "placeholders", "new output paths",
      ] {
      assert_true(text.contains(label))
    }
    for related in topic.related {
      assert_eq(ids.filter(fn(id) { id == related }).length(), 1)
    }
    assert_true(complete.contains("  " + topic.id + "  "))
    match topic.id {
      "overview" => {
        assert_true(text.contains("not additive"))
        assert_true(text.contains("--summary-json does not support --baseline"))
      }
      "functions" => {
        for
          flag in [
            "--find-functions", "--instructions-json", "--callers", "--why-index",
            "--retained", "--dead-code", "--duplicates", "--generics", "--entrypoints",
          ] {
          assert_true(text.contains(flag))
        }
        assert_true(text.contains("not execution traces"))
        assert_true(text.contains("recompiled savings"))
      }
      "data" => {
        assert_true(text.contains("safely merged"))
        assert_true(text.contains("--html --diff-data is rejected"))
      }
      "interfaces" => assert_true(text.contains("Full ABI"))
      "metadata" => {
        assert_true(text.contains("outer byte ledger can be complete"))
        assert_true(text.contains("partial"))
      }
      "baseline" => assert_true(text.contains("both explicit indices"))
      "ci" => {
        assert_true(
          text.contains(
            "3 budget exceeded, incomplete strict graph, or path search limited",
          ),
        )
        assert_true(text.contains("not universal"))
        assert_true(text.contains("Top does not truncate JSON"))
      }
      _ => fail("unexpected registered topic")
    }
  }
}

///|
test "help-topics: every displayed example obeys the real parameter contract without I/O" {
  // Stored argv is also used for rendering; no shell parser or analyzer runs.
  for topic in help_topics() {
    for i in 0..<topic.examples.length() {
      let args = topic.examples[i]
      match help_request(args) {
        Ok(None) => ()
        _ => fail("analysis example intercepted as help")
      }
      match parse_options(args) {
        Ok(_) => ()
        Err(message) => fail("topic \{topic.id}, example \{i}: " + message)
      }
    }
  }
}
