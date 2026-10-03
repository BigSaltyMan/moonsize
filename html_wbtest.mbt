///|
/// An analysis of a tiny module carrying exactly the function sizes a test wants
/// to look at. Building it by hand rather than parsing a fixture is what lets a
/// test put a five-thousand-character name, or a `</script>` tag, into a report.
fn analysis_of_stats(stats : Array[FunctionStat]) -> Analysis raise {
  let data = minimal_module()
  let parsed = match parse_module(data) {
    Ok(parsed) => parsed
    Err(error) => fail(describe_error(error))
  }
  let reachable : Set[Int] = Set([])
  let retained : Array[RetainedSize] = []
  for stat in stats {
    reachable.add(stat.index)
    retained.push({
      index: stat.index,
      own_size: stat.total_size,
      retained: stat.total_size,
      retained_functions: 0,
    })
  }
  {
    data,
    parsed,
    stats,
    graph: graph_of([]),
    roots: reachable,
    reachable,
    retained,
    indirect: Set([]),
  }
}

///|
/// One function with the given name, so a test can choose what goes in it.
fn analysis_with_name(name : String) -> Analysis raise {
  analysis_of_stats([
    {
      index: 1,
      name,
      module_name: "demo",
      body_size: 120,
      total_size: 122,
      offset: 0,
    },
  ])
}

///|
/// A string of `count` copies of one character.
fn repeat_text(text : String, count : Int) -> String {
  let out = StringBuilder(size_hint=text.length() * count)
  let mut i = 0
  while i < count {
    out.write_string(text)
    i = i + 1
  }
  out.to_string()
}

///|
test "the report is one complete html document" {
  let html = render_html(analysis_with_name("demo::fib"), "app.wasm")
  assert_true(html.contains("<!DOCTYPE html>"))
  assert_true(html.contains("</html>"))
  assert_true(html.contains("<title>moonsize"))
  assert_true(html.contains("id=\"sections\""))
  assert_true(html.contains("id=\"functions\""))
  assert_true(html.contains("id=\"modules\""))
  assert_true(html.contains("id=\"treemap\""))
}

///|
test "the data blob carries the file, its sizes and the functions" {
  let analysis = analysis_with_name("demo::fib")
  let html = render_html(analysis, "app.wasm")
  assert_true(html.contains("\"file\":\"app.wasm\""))
  assert_true(
    html.contains("\"fileSize\":" + analysis.parsed.file_size.to_string()),
  )
  assert_true(html.contains("\"name\":\"demo::fib\""))
  assert_true(html.contains("\"bodySize\":120"))
  assert_true(html.contains("\"size\":122"))
  assert_true(html.contains("\"module\":\"demo\""))
}

///|
test "the three headline numbers are rendered as cards" {
  let html = render_html(analysis_with_name("demo::fib"), "app.wasm")
  assert_true(html.contains(">File size<"))
  assert_true(html.contains(">Code section<"))
  assert_true(html.contains(">Dead code<"))
  assert_true(html.contains(">24 B<"))
}

///|
test "a module with no functions still produces a whole document" {
  let html = render_html(analysis_of_stats([]), "empty.wasm")
  assert_true(html.contains("<!DOCTYPE html>"))
  assert_true(html.contains("</html>"))
  assert_true(html.contains("\"functions\":[]"))
  assert_true(html.contains("\"modules\":[]"))
}

///|
test "a single function does not break the treemap or the pie" {
  let html = render_html(analysis_with_name("only::one"), "one.wasm")
  assert_true(html.contains("\"name\":\"only::one\""))
  assert_true(html.contains("</html>"))
  // One module holding one child, which is what the treemap walks.
  assert_true(html.contains("\"children\":[{\"name\":\"only::one\""))
}

///|
test "an extremely long name is carried through without breaking the page" {
  let name = repeat_text("verylongmodulename", 300)
  let html = render_html(analysis_with_name(name), "long.wasm")
  assert_true(html.contains(name))
  assert_true(html.contains("</html>"))
}

///|
test "html metacharacters in a name reach the page only as data" {
  let html = render_html(analysis_with_name("a<b>&\"c"), "esc.wasm")
  // A function name is drawn on a canvas and shown in tooltips, never written
  // into the document as markup, so the only place it appears is the data blob,
  // where `<` is escaped so it cannot open an element.
  assert_true(html.contains("a\\u003cb>&\\\"c"))
  assert_true(!html.contains(">a<b>&\"c<"))
}

///|
test "the file path is escaped where it is written as html" {
  let html = render_html(analysis_with_name("demo::fib"), "a<b>&\"c.wasm")
  assert_true(
    html.contains("<title>moonsize — a&lt;b&gt;&amp;&quot;c.wasm</title>"),
  )
}

///|
test "a name that tries to close the script element cannot" {
  let attack = "</script><script>alert(1)</script>"
  let html = render_html(analysis_with_name(attack), "attack.wasm")
  assert_true(!html.contains("</script><script>"))
  assert_true(html.contains("\\u003c/script>"))
  assert_true(html.contains("</html>"))
}

///|
test "the chart library is inlined when it is supplied" {
  let library = "var echarts={init:function(){return{setOption:function(){}}}};"
  let html = render_html(
    analysis_with_name("demo::fib"),
    "app.wasm",
    echarts=library,
  )
  assert_true(html.contains(library))
  assert_true(!html.contains("cdn.jsdelivr.net"))
}

///|
test "the report falls back to a CDN when the library is missing" {
  let html = render_html(analysis_with_name("demo::fib"), "app.wasm")
  assert_true(html.contains("cdn.jsdelivr.net/npm/echarts"))
}

///|
test "an inlined library cannot close its own script element" {
  let library = "var s = \"</script>\";"
  let html = render_html(
    analysis_with_name("demo::fib"),
    "app.wasm",
    echarts=library,
  )
  assert_true(html.contains("<\\/script>"))
  // The only real closing tag is the one this generator wrote.
  assert_true(!html.contains("</script>\";"))
}

///|
test "the report draws on the analysis rather than reparsing" {
  // A module whose functions are all unreachable: the dead-code card must say so
  // from the reachability set the analysis already computed.
  let data = named_module()
  let parsed = match parse_module(data) {
    Ok(parsed) => parsed
    Err(error) => fail(describe_error(error))
  }
  let analysis = match analyze(data, parsed) {
    Ok(analysis) => analysis
    Err(error) => fail(describe_error(error))
  }
  inspect(
    analysis.reachable.length(),
    content=(
      #|0
    ),
  )
  let html = render_html(analysis, "named.wasm")
  assert_true(html.contains("card alert"))
  assert_true(html.contains("moonbit.println"))
  assert_true(html.contains("\"dead\":true"))
}

///|
/// A module group for the pie tests, with no children: only the name and the
/// total matter to `pie_slices`.
fn pie_group(name : String, size : Int) -> ModuleGroup {
  { name, size, functions: 1, children: [], }
}

///|
test "the section chart is ordered heaviest first" {
  // named_module: import 24, function 5, code 11, custom (name) 69 bytes.
  let parsed = match parse_module(named_module()) {
    Ok(parsed) => parsed
    Err(error) => fail(describe_error(error))
  }
  let ordered = ordered_sections(parsed)
  inspect(
    ordered.length(),
    content=(
      #|4
    ),
  )
  inspect(
    ordered[0].total_size,
    content=(
      #|69
    ),
  )
  inspect(
    ordered[0].kind.name(),
    content=(
      #|custom
    ),
  )
  inspect(
    ordered[1].total_size,
    content=(
      #|24
    ),
  )
  inspect(
    ordered[1].kind.name(),
    content=(
      #|import
    ),
  )
  inspect(
    ordered[2].kind.name(),
    content=(
      #|code
    ),
  )
  inspect(
    ordered[3].kind.name(),
    content=(
      #|function
    ),
  )
}

///|
test "sections of equal size keep their order in the file" {
  // minimal_module: type and code both total six bytes; type comes first.
  let parsed = match parse_module(minimal_module()) {
    Ok(parsed) => parsed
    Err(error) => fail(describe_error(error))
  }
  let ordered = ordered_sections(parsed)
  inspect(
    ordered[0].total_size,
    content=(
      #|6
    ),
  )
  inspect(
    ordered[0].kind.name(),
    content=(
      #|type
    ),
  )
  inspect(
    ordered[1].total_size,
    content=(
      #|6
    ),
  )
  inspect(
    ordered[1].kind.name(),
    content=(
      #|code
    ),
  )
  inspect(
    ordered[2].kind.name(),
    content=(
      #|function
    ),
  )
}

///|
test "the pie rolls slices below half a percent into one" {
  let slices = pie_slices([
    pie_group("big", 9000),
    pie_group("small", 8),
    pie_group("tiny", 4),
  ])
  inspect(
    slices.length(),
    content=(
      #|2
    ),
  )
  inspect(
    slices[0].name,
    content=(
      #|big
    ),
  )
  inspect(
    slices[1].name,
    content=(
      #|other (2)
    ),
  )
  inspect(
    slices[1].size,
    content=(
      #|12
    ),
  )
  assert_eq(slices[1].members, ["small", "tiny"])
}

///|
test "a slice exactly at the threshold keeps its own name" {
  // These total 10,000 bytes, so half a percent is exactly 50.
  let slices = pie_slices([
    pie_group("big", 9901),
    pie_group("edge", 50),
    pie_group("under", 49),
  ])
  inspect(
    slices.length(),
    content=(
      #|3
    ),
  )
  inspect(
    slices[1].name,
    content=(
      #|edge
    ),
  )
  inspect(
    slices[2].name,
    content=(
      #|other (1)
    ),
  )
}

///|
test "nothing is bucketed when every slice is comfortably sized" {
  let slices = pie_slices([
    pie_group("a", 1000),
    pie_group("b", 900),
    pie_group("c", 800),
  ])
  inspect(
    slices.length(),
    content=(
      #|3
    ),
  )
  for slice in slices {
    assert_eq(slice.members, [])
  }
}

///|
test "a pie made only of tiny slices is left alone" {
  // Bucketing here would replace the whole chart with one grey slice.
  let slices = pie_slices([pie_group("a", 30), pie_group("b", 20)])
  inspect(
    slices.length(),
    content=(
      #|2
    ),
  )
  inspect(
    slices[0].name,
    content=(
      #|a
    ),
  )
}

///|
test "the data blob carries the pie roster beside the raw modules" {
  let html = render_html(analysis_with_name("demo::fib"), "app.wasm")
  assert_true(html.contains("\"pie\":["))
  assert_true(html.contains("\"modules\":["))
}

///|
test "the page reports the compressed size the tool actually computes" {
  // The card's number has to be the compressor's, not a second opinion: the
  // test computes it the same way and looks for it in the JSON and in the card.
  let analysis = analysis_with_name("demo::fib")
  let gzip_size = compressed_size(analysis.data)
  let html = render_html(analysis, "app.wasm")
  assert_true(html.contains("\"gzipSize\":" + gzip_size.to_string()))
  assert_true(html.contains("<span class=\"label\">Gzip size</span>"))
  assert_true(
    html.contains("<span class=\"value\">" + grouped(gzip_size) + " B</span>"),
  )
  // The share of raw and the ratio ride underneath it.
  assert_true(
    html.contains(
      share_text(gzip_size, analysis.parsed.file_size) + " of raw · ",
    ),
  )
}

///|
test "every section and function carries its compressed size" {
  // A real module this time, so the numbers are the compressor's own rather
  // than a fixture's stand-ins.
  let data = named_module()
  let parsed = match parse_module(data) {
    Ok(parsed) => parsed
    Err(error) => fail(decode_failure(error))
  }
  let analysis = match analyze(data, parsed) {
    Ok(analysis) => analysis
    Err(error) => fail(decode_failure(error))
  }
  let json = report_data(analysis, "named.wasm").stringify()
  let html = render_html(analysis, "named.wasm")
  // The headline is the compressor's number for the whole file.
  assert_true(
    json.contains("\"gzipSize\":" + compressed_size(data).to_string()),
  )
  // A section's number is the compressor's number for that section's own bytes,
  // not a share of the total dressed up as one.
  let section = parsed.sections[0]
  assert_true(
    json.contains(
      "\"gzip\":" +
      compressed_span(data, section.offset, section.total_size).to_string(),
    ),
  )
  // And a function's, off the offsets the decoder recorded.
  let stat = analysis.stats[0]
  assert_true(
    json.contains(
      "\"gzip\":" +
      compressed_span(data, stat.offset, stat.total_size).to_string(),
    ),
  )
  assert_true(html.contains("\"gzip\":"))
}

///|
test "the sections chart offers both views of the same bars" {
  let html = render_html(analysis_with_name("demo::fib"), "app.wasm")
  // Two series over one axis, with the compressed one hidden until it is asked
  // for, so switching shows the drop rather than rescaling the axis.
  assert_true(html.contains("data: ['raw', 'gzip']"))
  assert_true(html.contains("selected: { raw: true, gzip: false }"))
  assert_true(html.contains("barGap: '-100%'"))
  assert_true(html.contains("'#a78bfa')"))
}

///|
test "non-ASCII text survives escaping" {
  // Escaping walks the document byte by byte; copying one byte of a multi-byte
  // character would replace it with a replacement character.
  let html = render_html(analysis_with_name("demo::fib"), "/tmp/示例.wasm")
  assert_true(html.contains("<title>moonsize — /tmp/示例.wasm</title>"))
  assert_true(html.contains("<p class=\"file\">/tmp/示例.wasm</p>"))
  assert_false(html.contains("\u{fffd}"))
}
