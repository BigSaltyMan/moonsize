///|
fn html_data_analysis(bytes : Bytes) -> Analysis raise {
  let parsed = match parse_module(bytes) {
    Ok(value) => value
    Err(error) => fail(describe_error(error))
  }
  match analyze(bytes, parsed) {
    Ok(value) => value
    Err(error) => fail(describe_error(error))
  }
}

///|
test "HTML data entry point embeds the same metadata and precise static ledger" {
  let bytes = b"\x00asm\x01\x00\x00\x00" + data_mixed_sections()
  let analysis = html_data_analysis(bytes)
  let report = data_inspected(data_mixed_sections())
  let html = render_html_with_data_segments(
    analysis,
    "input<&\"</script>.wasm",
    report,
    echarts="fixed library",
  )
  assert_true(
    html.contains("\"dataSegments\":" + data_segments_json(report).stringify()),
  )
  assert_true(
    html.contains(
      "Complete data 22 B = payload 6 B + entry metadata 13 B + section overhead 3 B",
    ),
  )
  assert_true(html.contains("Showing 3 of 3 entries"))
  assert_true(html.contains("[20, 23)"))
  assert_true(html.contains("not_evaluated (includes end)"))
  assert_true(html.contains("not_applicable"))
  assert_true(html.contains("input&lt;&amp;&quot;&lt;/script&gt;.wasm"))
  assert_false(html.contains("input<&\"</script>.wasm"))
  assert_false(
    render_html(analysis, "input", echarts="fixed library").contains(
      "\"dataSegments\":",
    ),
  )
  assert_false(render_html(analysis, "input").contains("id=\"data-segments\""))
}

///|
test "HTML data missing empty section and zero payload states are distinct" {
  for
    (sections, text) in [
      (b"", "No data section in this input."),
      (b"\x0b\x01\x00", "Data section is present with zero entries."),
      (b"\x0b\x03\x01\x01\x00", "Showing 1 of 1 entries"),
    ] {
    let html = render_html_with_data_segments(
      html_data_analysis(b"\x00asm\x01\x00\x00\x00" + sections),
      "input",
      data_inspected(sections),
    )
    assert_true(html.contains(text))
  }
}

///|
test "HTML data static batch is bounded but embedded metadata is complete" {
  let mut entries = b""
  for i = 0; i < 25; i = i + 1 {
    entries += b"\x01\x00"
  }
  let sections = b"\x0b\x33\x19" + entries
  let report = data_inspected(sections)
  let html = render_html_with_data_segments(
    html_data_analysis(b"\x00asm\x01\x00\x00\x00" + sections),
    "input",
    report,
  )
  assert_true(html.contains("Showing 20 of 25 entries"))
  assert_true(html.contains("data-segment-index=\"19\""))
  assert_false(html.contains("data-segment-index=\"20\""))
  assert_true(
    html.contains("\"dataSegments\":" + data_segments_json(report).stringify()),
  )
  assert_true(
    html.contains(
      "id=\"data-more\" type=\"button\" aria-controls=\"data-rows\" hidden",
    ),
  )
}
