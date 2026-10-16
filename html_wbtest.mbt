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
    graph_complete: true,
    unresolved_count: 0,
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
      raw_name: None,
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
  let gzip_size = match compressed_size(analysis.data) {
    Ok(size) => size
    Err(message) => fail(message)
  }
  let html = render_html(analysis, "app.wasm")
  assert_true(html.contains("\"gzipSize\":" + gzip_size.to_string()))
  assert_true(html.contains("<span class=\"label\">Whole-file gzip</span>"))
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
  let whole = match compressed_size(data) {
    Ok(size) => size.to_string()
    Err(message) => fail(message)
  }
  assert_true(json.contains("\"gzipSize\":" + whole))
  // A section's number is the compressor's number for that section's own bytes,
  // not a share of the total dressed up as one.
  let section = parsed.sections[0]
  let section_gzip = match
    compressed_span(data, section.offset, section.total_size) {
    Ok(size) => size.to_string()
    Err(message) => fail(message)
  }
  assert_true(json.contains("\"gzip\":" + section_gzip))
  // And a function's, off the offsets the decoder recorded.
  let stat = analysis.stats[0]
  let stat_gzip = match compressed_span(data, stat.offset, stat.total_size) {
    Ok(size) => size.to_string()
    Err(message) => fail(message)
  }
  assert_true(json.contains("\"gzip\":" + stat_gzip))
  assert_true(html.contains("\"gzip\":"))
}

///|
test "HTML always explains model retention versus actual savings" {
  let analysis = analysis_of_module(static_table_module())
  assert_true(is_graph_complete(analysis.graph))
  let html = render_html(analysis, "complete.wasm")
  assert_true(html.contains("does not predict recompiled file reduction"))
  assert_true(html.contains("even when --strict passes"))
  assert_true(html.contains("not a safe-deletion list"))
}

///|
test "the sections chart offers both views of the same bars" {
  let html = render_html(analysis_with_name("demo::fib"), "app.wasm")
  // Two series over one axis, with the compressed one hidden until it is asked
  // for, so switching shows the drop rather than rescaling the axis.
  assert_true(html.contains("data: ['raw', 'independent gzip']"))
  assert_true(
    html.contains("selected: { raw: true, 'independent gzip': false }"),
  )
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

///|
test "every headline card is one well-formed element" {
  let html = render_html(analysis_with_name("demo::fib"), "app.wasm")
  // A mistyped string concatenation once emitted `<div class="card">card">`,
  // which every substring assertion above is happy to accept. This one looks at
  // the tag itself.
  assert_true(!html.contains("card\">card"))
  for label in ["File size", "Code section", "Whole-file gzip", "Dead code"] {
    assert_true(
      html.contains(
        "      <div class=\"card\">\n        <span class=\"label\">" +
        label +
        "</span>",
      ),
    )
  }
}

///|
fn assert_gzip_pair(row : Json, size : Json, error : Json) -> Unit raise {
  let object = json_object(row)
  assert_eq(object.get("gzip"), Some(size))
  assert_eq(object.get("gzipError"), Some(error))
}

///|
test "HTML range failures originate from the actual function measurement" {
  // This existing rendering fixture deliberately claims 122 bytes in a 24-byte file.
  let analysis = analysis_with_name("oversized")
  let data = json_object(report_data(analysis, "range.wasm"))
  let reason = Json::string(
    "invalid compression range: offset 0, length 122, file length 24",
  )
  assert_eq(data.get("gzipError"), Some(Json::null()))
  assert_gzip_pair(json_array(data["functions"])[0], Json::null(), reason)
  let group = json_object(json_array(data["modules"])[0])
  assert_gzip_pair(json_array(group["children"])[0], Json::null(), reason)
  for row in json_array(data["sections"]) {
    assert_eq(json_object(row).get("gzipError"), Some(Json::null()))
  }
}

///|
test "HTML local compression errors keep their own reasons beside a successful whole file" {
  let analysis = analysis_of(minimal_module())
  let measured = measure_compression(analysis)
  measured.sections[0] = Err("section-only <failure>")
  measured.functions.set(analysis.stats[0].index, Err("function-only failure"))
  let data = json_object(
    report_data(analysis, "app.wasm", compression=measured),
  )
  assert_eq(data.get("gzipError"), Some(Json::null()))
  assert_eq(data.get("gzipSize"), Some(gzip_json(measured.whole_file)))
  let sections = json_array(data["sections"])
  assert_gzip_pair(
    sections[0],
    Json::null(),
    Json::string("section-only <failure>"),
  )
  assert_gzip_pair(sections[1], gzip_json(measured.sections[1]), Json::null())
  let functions = json_array(data["functions"])
  assert_gzip_pair(
    functions[0],
    Json::null(),
    Json::string("function-only failure"),
  )
  let group = json_object(json_array(data["modules"])[0])
  assert_gzip_pair(
    json_array(group["children"])[0],
    Json::null(),
    Json::string("function-only failure"),
  )
  let html = render_html_measured(analysis, "app.wasm", measured, "")
  assert_true(html.contains("section-only \\u003cfailure>"))
  assert_true(html.contains("function-only failure"))
  assert_false(html.contains(">N/A<"))
  assert_true(
    html.contains("else if (r.gzipError !== null && r.gzipError !== undefined)"),
  )
  assert_true(
    html.contains(
      "else if (p.data && p.data.gzipError !== null && p.data.gzipError !== undefined)",
    ),
  )
  assert_false(html.contains("esc(DATA.gzipError)"))
  assert_true(
    html.contains("if (v === null || v === undefined) return 'failed'"),
  )
}

///|
test "HTML whole-file failure leaves successful local measurements available" {
  let analysis = analysis_of(minimal_module())
  let measured = measure_compression(analysis)
  let failed : CompressionMeasurements = {
    whole_file: Err("whole-only failure"),
    sections: measured.sections,
    functions: measured.functions,
  }
  let data = json_object(report_data(analysis, "app.wasm", compression=failed))
  assert_eq(data.get("gzipSize"), Some(Json::null()))
  assert_eq(data.get("gzipError"), Some(Json::string("whole-only failure")))
  for i, row in json_array(data["sections"]) {
    assert_gzip_pair(row, gzip_json(measured.sections[i]), Json::null())
  }
  let stat = analysis.stats[0]
  assert_gzip_pair(
    json_array(data["functions"])[0],
    gzip_json(measured.functions[stat.index]),
    Json::null(),
  )
  let html = render_html_measured(analysis, "app.wasm", failed, "")
  assert_true(html.contains(">N/A<"))
  assert_true(html.contains("title=\"whole-only failure\""))
  assert_true(
    html.contains(
      "Each section is compressed separately. These sizes are not additive and do not represent whole-file transfer shares.",
    ),
  )
}

///|
test "HTML function gzip and treemap use total encoded bytes as their raw denominator" {
  let analysis = analysis_of(minimal_module())
  let stat = analysis.stats[0]
  assert_eq(stat.total_size, 3)
  assert_eq(stat.body_size, 2)
  let measured = measure_compression(analysis)
  assert_eq(measured.functions[stat.index], compressed_size(b"\x02\x00\x0b"))
  let data = json_object(
    report_data(analysis, "app.wasm", compression=measured),
  )
  let function = json_object(json_array(data["functions"])[0])
  assert_eq(function.get("size"), Some(int_json(3)))
  assert_eq(function.get("bodySize"), Some(int_json(2)))
  assert_gzip_pair(
    Json::object(function),
    gzip_json(measured.functions[stat.index]),
    Json::null(),
  )
  let group = json_object(json_array(data["modules"])[0])
  let leaf = json_array(group["children"])[0]
  assert_eq(json_object(leaf).get("value"), Some(int_json(3)))
  assert_gzip_pair(
    leaf,
    gzip_json(measured.functions[stat.index]),
    Json::null(),
  )
  let html = render_html_measured(analysis, "app.wasm", measured, "")
  assert_true(html.contains("gzipRawSize: f.size"))
  assert_true(html.contains("RATIO(gzipRaw, r.gzip)"))
  assert_true(html.contains("RATIO(p.value, p.data.gzip)"))
  assert_true(html.contains("value: c.value"))
  assert_true(html.contains("gzip: c.gzip"))
  assert_true(html.contains("gzipError: c.gzipError"))
  assert_true(html.contains("\"compression_scope\":"))
}
