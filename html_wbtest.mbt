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
    { index: 1, name, module_name: "demo", body_size: 120, total_size: 122, },
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
