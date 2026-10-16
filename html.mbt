///|
/// The HTML report: one self-contained document with four charts.
///
/// The charts are drawn by Apache ECharts, which is vendored under `assets/` and
/// inlined here by the caller. Inlining rather than linking keeps the promise the
/// rest of the tool makes — everything happens on the machine you run it on, with
/// no network and no second file to keep next to the report.

///|
/// One module with the functions that belong to it, heaviest first.
///
/// The treemap needs the nesting, and the pie needs the totals, so the grouping
/// is done once here rather than twice in the page.
priv struct ModuleGroup {
  name : String
  size : Int
  functions : Int
  children : Array[FunctionStat]
}

///|
/// Group functions by the package their names carry, heaviest total first.
fn group_modules(stats : Array[FunctionStat]) -> Array[ModuleGroup] {
  let order : Array[String] = []
  let index : Map[String, Int] = Map([])
  let groups : Array[ModuleGroup] = []
  for stat in stats {
    let at = match index.get(stat.module_name) {
      Some(at) => at
      None => {
        index.set(stat.module_name, groups.length())
        order.push(stat.module_name)
        groups.push({
          name: stat.module_name,
          size: 0,
          functions: 0,
          children: [],
        })
        groups.length() - 1
      }
    }
    let group = groups[at]
    groups[at] = {
      name: group.name,
      size: group.size + stat.total_size,
      functions: group.functions + 1,
      children: group.children,
    }
    groups[at].children.push(stat)
  }
  for group in groups {
    group.children.sort_by(fn(a, b) {
      if a.total_size != b.total_size {
        b.total_size - a.total_size
      } else {
        a.index - b.index
      }
    })
  }
  groups.sort_by(fn(a, b) {
    if a.size != b.size {
      b.size - a.size
    } else {
      String::compare(a.name, b.name)
    }
  })
  groups
}

///|
/// The bytes spent on a named section, or zero when the module has none.
fn section_size(parsed : WasmModule, kind : SectionId) -> Int {
  let mut total = 0
  for section in parsed.sections {
    if same_kind(section.kind, kind) {
      total = total + section.total_size
    }
  }
  total
}

///|
/// The bytes in functions no root can reach.
fn dead_size(analysis : Analysis) -> Int {
  let mut total = 0
  for stat in analysis.stats {
    if !analysis.reachable.contains(stat.index) {
      total = total + stat.total_size
    }
  }
  total
}

///|
/// An integer as a JSON number.
///
/// The representation is pinned to the decimal text: a file size has no
/// fractional part, and letting the printer choose would turn 10645 into
/// `10645.0` or `1.0645E4` depending on its mood.
fn int_json(value : Int) -> Json {
  Json::number(value.to_double(), repr=value.to_string())
}

///|
/// One measurement per range, reused by the card, data rows and treemap leaves.
/// Kept internal so tests can inject failures at the rendering boundary.
priv struct CompressionMeasurements {
  whole_file : Result[Int, String]
  sections : Array[Result[Int, String]]
  functions : Map[Int, Result[Int, String]]
}

///|
fn measure_compression(analysis : Analysis) -> CompressionMeasurements {
  let functions : Map[Int, Result[Int, String]] = Map([])
  for stat in analysis.stats {
    functions.set(
      stat.index,
      compressed_span(analysis.data, stat.offset, stat.total_size),
    )
  }
  {
    whole_file: compressed_size(analysis.data),
    sections: compress_sections(analysis.data, analysis.parsed).map(fn(row) {
      row.gzip
    }),
    functions,
  }
}

///|
/// The number and error always describe the same measurement result.
fn set_gzip_fields(row : Map[String, Json], gzip : Result[Int, String]) -> Unit {
  row.set("gzip", gzip_json(gzip))
  row.set("gzipError", gzip_error_json(gzip))
}

///|
/// The payload the page draws from, as one JSON object.
fn report_data(
  analysis : Analysis,
  file_path : String,
  compression? : CompressionMeasurements,
) -> Json {
  let measured = match compression {
    Some(measured) => measured
    None => measure_compression(analysis)
  }
  let parsed = analysis.parsed
  let members : Map[String, Json] = Map([])
  members.set("file", Json::string(file_path))
  members.set("fileSize", int_json(parsed.file_size))
  members.set("schema_version", int_json(1))
  members.set(
    "graph_complete",
    Json::boolean(is_graph_complete(analysis.graph)),
  )
  members.set("diagnostics", diagnostics_json(analysis.graph))
  members.set("modeling_scope", Json::string(graph_modeling_scope()))
  members.set("gzipSize", gzip_json(measured.whole_file))
  members.set("gzipError", gzip_error_json(measured.whole_file))
  members.set(
    "compression_scope",
    Json::string(
      "Whole-file gzip is one complete-file stream. Sections include their headers and payloads; functions include their size prefixes (size, not bodySize). Each local range is an independent gzip stream. These sizes are not additive and do not represent whole-file transfer shares or removal savings.",
    ),
  )
  members.set("codeSize", int_json(section_size(parsed, Code)))
  members.set("deadSize", int_json(dead_size(analysis)))
  let sections : Array[Json] = []
  for i, section in ordered_sections(parsed) {
    let row : Map[String, Json] = Map([])
    row.set("name", Json::string(section_label(section)))
    row.set("total", int_json(section.total_size))
    row.set("payload", int_json(section.payload_size))
    set_gzip_fields(row, measured.sections[i])
    sections.push(Json::object(row))
  }
  members.set("sections", Json::array(sections))
  let ranked = analysis.stats.copy()
  ranked.sort_by(fn(a, b) {
    if a.body_size != b.body_size {
      b.body_size - a.body_size
    } else {
      a.index - b.index
    }
  })
  let functions : Array[Json] = []
  for stat in ranked {
    let row : Map[String, Json] = Map([])
    row.set("index", int_json(stat.index))
    row.set("name", Json::string(stat.name))
    row.set("module", Json::string(stat.module_name))
    row.set("bodySize", int_json(stat.body_size))
    row.set("size", int_json(stat.total_size))
    set_gzip_fields(row, measured.functions[stat.index])
    row.set("dead", Json::boolean(!analysis.reachable.contains(stat.index)))
    functions.push(Json::object(row))
  }
  members.set("functions", Json::array(functions))
  let groups = group_modules(analysis.stats)
  let modules : Array[Json] = []
  for group in groups {
    let children : Array[Json] = []
    for child in group.children {
      let leaf : Map[String, Json] = Map([])
      leaf.set("name", Json::string(child.name))
      leaf.set("value", int_json(child.total_size))
      set_gzip_fields(leaf, measured.functions[child.index])
      leaf.set("dead", Json::boolean(!analysis.reachable.contains(child.index)))
      leaf.set("index", int_json(child.index))
      children.push(Json::object(leaf))
    }
    let row : Map[String, Json] = Map([])
    row.set("name", Json::string(group.name))
    row.set("size", int_json(group.size))
    row.set("functions", int_json(group.functions))
    row.set("children", Json::array(children))
    modules.push(Json::object(row))
  }
  members.set("modules", Json::array(modules))
  // The pie gets its own roster: thin slices are rolled up there, while the
  // treemap keeps every module because its cells are drawn to scale.
  let slices : Array[Json] = []
  for slice in pie_slices(groups) {
    let row : Map[String, Json] = Map([])
    row.set("name", Json::string(slice.name))
    row.set("size", int_json(slice.size))
    let names : Array[Json] = []
    for name in slice.members {
      names.push(Json::string(name))
    }
    row.set("members", Json::array(names))
    slices.push(Json::object(row))
  }
  members.set("pie", Json::array(slices))
  Json::object(members)
}

///|
/// One slice of the module pie.
priv struct PieSlice {
  name : String
  size : Int
  /// The modules this slice stands for; empty when it is a module itself.
  members : Array[String]
}

///|
/// A slice below half a percent of attributed function bytes cannot carry a legible label
/// or be aimed at with a pointer, so the ones below it are rolled into a single
/// slice that names them on hover.
const MIN_SLICE_TENTHS : Int = 5

///|
/// The pie's slices: every module at or above the threshold, plus one `other`
/// slice holding the rest.
///
/// The comparison is integer arithmetic — `size / total < 0.5%` is
/// `size * 1000 < total * 5` — so it cannot drift the way a float would.
fn pie_slices(groups : Array[ModuleGroup]) -> Array[PieSlice] {
  let slices : Array[PieSlice] = []
  let mut total = 0
  for group in groups {
    total = total + group.size
  }
  let big : Array[ModuleGroup] = []
  let small : Array[ModuleGroup] = []
  for group in groups {
    if total > 0 && group.size * 1000 < total * MIN_SLICE_TENTHS {
      small.push(group)
    } else {
      big.push(group)
    }
  }
  // Bucketing nothing, or bucketing everything, would both make the chart worse.
  if small.length() == 0 || big.length() == 0 {
    for group in groups {
      slices.push({ name: group.name, size: group.size, members: [], })
    }
    return slices
  }
  for group in big {
    slices.push({ name: group.name, size: group.size, members: [], })
  }
  let mut rest = 0
  let members : Array[String] = []
  for group in small {
    rest = rest + group.size
    members.push(group.name)
  }
  slices.push({
    name: "other (" + small.length().to_string() + ")",
    size: rest,
    members,
  })
  slices
}

///|
/// The length of the UTF-8 sequence a lead byte introduces.
fn utf8_width(lead : Byte) -> Int {
  if lead < b'\x80' {
    1
  } else if lead >= b'\xf0' {
    4
  } else if lead >= b'\xe0' {
    3
  } else if lead >= b'\xc0' {
    2
  } else {
    1
  }
}

///|
/// Replace every occurrence of `needle` in `text`, which must not be empty.
fn replace_all(text : String, needle : String, replacement : String) -> String {
  if needle.length() == 0 {
    return text
  }
  let bytes = @utf8.encode(text)
  let find = @utf8.encode(needle)
  let out = StringBuilder(size_hint=bytes.length())
  let mut i = 0
  while i < bytes.length() {
    if i + find.length() <= bytes.length() && matches_at(bytes, find, i) {
      out.write_string(replacement)
      i = i + find.length()
    } else {
      // A whole character at a time: one byte of a multi-byte character is not
      // decodable on its own, so decoding it lossily would turn every non-ASCII
      // character in the document into a replacement character.
      let width = utf8_width(bytes[i])
      let end = if i + width <= bytes.length() { i + width } else { i + 1 }
      out.write_string(@utf8.decode_lossy(bytes[i:end]))
      i = end
    }
  }
  out.to_string()
}

///|
/// True when `needle` sits in `bytes` at `at`.
fn matches_at(bytes : Bytes, needle : Bytes, at : Int) -> Bool {
  let mut i = 0
  while i < needle.length() {
    if bytes[at + i] != needle[i] {
      return false
    }
    i = i + 1
  }
  true
}

///|
/// Make text safe inside a `<script>` element.
///
/// The HTML parser ends a script at the first `</script`, wherever it appears,
/// so a function name or a library build that contains that sequence would break
/// out of the element. Escaping `<` as a JSON escape covers the data blob, and
/// the same reasoning applied to the library is handled by `escape_script_end`.
fn escape_for_script(text : String) -> String {
  replace_all(text, "<", "\\u003c")
}

///|
/// Break up any `</script` so inlined JavaScript cannot close its own element.
fn escape_script_end(text : String) -> String {
  replace_all(
    replace_all(text, "</script", "<\\/script"),
    "</SCRIPT",
    "<\\/SCRIPT",
  )
}

///|
/// Escape text for use as HTML character data or a quoted attribute.
fn html_escape(text : String) -> String {
  let out = replace_all(text, "&", "&amp;")
  let out = replace_all(out, "<", "&lt;")
  let out = replace_all(out, ">", "&gt;")
  let out = replace_all(out, "\"", "&quot;")
  replace_all(out, "'", "&#39;")
}

///|
/// A compressed size as JSON: the number, or `null` when the compressor gave
/// none. `null` is not `0` and not the raw size — the page has to be able to say
/// "not measured" and have it survive the trip.
fn gzip_json(gzip : Result[Int, String]) -> Json {
  match gzip {
    Ok(size) => int_json(size)
    Err(_) => Json::null()
  }
}

///|
fn gzip_error_json(gzip : Result[Int, String]) -> Json {
  match gzip {
    Ok(_) => Json::null()
    Err(message) => Json::string(message)
  }
}

///|
/// The gzip card's value, sub-line and hover text.
///
/// A failure is `N/A` carrying the compressor's own complaint, rather than the
/// raw size dressed up as a ratio of 1.00x — the two mean opposite things and the
/// page must not make them look alike.
fn gzip_card_fields(
  raw : Int,
  gzip : Result[Int, String],
) -> (String, String, String) {
  match gzip {
    Ok(size) =>
      (
        grouped(size) + " B",
        share_text(size, raw) + " of raw · " + ratio_text(raw, size),
        "",
      )
    Err(message) => ("N/A", "compression failed", message)
  }
}

///|
/// A byte count with thousands separators, for the headline numbers.
fn grouped(value : Int) -> String {
  let digits = value.to_string()
  let out = StringBuilder(size_hint=digits.length() + 4)
  let mut i = 0
  while i < digits.length() {
    if i > 0 && (digits.length() - i) % 3 == 0 {
      out.write_string(",")
    }
    out.write_string(@utf8.decode_lossy(@utf8.encode(digits)[i:i + 1]))
    i = i + 1
  }
  out.to_string()
}

///|
/// A byte count in the units a person reads sizes in.
///
/// Integer arithmetic rather than floating point, so the same number always
/// prints the same way.
fn human_bytes(bytes : Int) -> String {
  if bytes >= 1048576 {
    let tenths = bytes * 10 / 1048576
    (tenths / 10).to_string() + "." + (tenths % 10).to_string() + " MB"
  } else if bytes >= 1024 {
    let tenths = bytes * 10 / 1024
    (tenths / 10).to_string() + "." + (tenths % 10).to_string() + " KB"
  } else {
    bytes.to_string() + " B"
  }
}

///|
/// One headline number.
fn card(
  label : String,
  value : String,
  sub : String,
  alert : Bool,
  title? : String = "",
) -> String {
  let klass = if alert { "card alert" } else { "card" }
  let tooltip = if title.length() == 0 {
    ""
  } else {
    " title=\"" + html_escape(title) + "\""
  }
  "      <div class=\"" +
  klass +
  "\"" +
  tooltip +
  ">\n" +
  "        <span class=\"label\">" +
  html_escape(label) +
  "</span>\n        <span class=\"value\">" +
  html_escape(value) +
  "</span>\n        <span class=\"sub\">" +
  html_escape(sub) +
  "</span>\n" +
  (if title.is_empty() {
    ""
  } else {
    "        <p class=\"measurement-error\">" + html_escape(title) + "</p>\n"
  }) +
  "      </div>\n"
}

///|
/// Render the whole analysis as one HTML document.
///
/// `echarts` is the chart library's source. Passing it inlines the library, so
/// the report opens from any directory with no network and no sibling file;
/// leaving it empty selects the compatible library CDN mode. This library does
/// no I/O. The CLI always supplies its compiled-in vendored source;
/// a library caller can explicitly supply a source or retain the CDN default.
pub fn render_html(
  analysis : Analysis,
  file_path : String,
  echarts? : String = "",
) -> String {
  render_html_measured(
    analysis,
    file_path,
    measure_compression(analysis),
    echarts,
  )
}

///|
fn html_data_field(row : Json, key : String) -> Json {
  match row {
    Object(fields) => fields.get(key).unwrap_or(Json::null())
    _ => Json::null()
  }
}

///|
fn html_data_text(row : Json, key : String) -> String {
  match html_data_field(row, key) {
    String(text) => text
    _ => ""
  }
}

///|
fn html_data_int(row : Json, key : String) -> Int {
  match html_data_field(row, key) {
    Number(n, ..) => n.to_int()
    _ => 0
  }
}

///|
fn html_data_array(row : Json, key : String) -> Array[Json] {
  match html_data_field(row, key) {
    Array(items) => items
    _ => []
  }
}

///|
/// The exact ranked rows and measurements already prepared for the charts.
/// This table is usable without JavaScript or ECharts.
fn html_function_table(data : Json) -> String {
  let out = StringBuilder()
  out.write_string(
    "<details id=\"function-details\" class=\"function-details\" open><summary>Function details · full names and measured bytes</summary>\n",
  )
  out.write_string(
    "<div class=\"table-scroll\" tabindex=\"0\" role=\"region\" aria-label=\"Function details, scroll horizontally on narrow screens\"><table>\n",
  )
  out.write_string(
    "<caption>Same Top 20 local functions as the body-size chart. Encoded B includes the size prefix. Indices use the full function index space, including imports. Reachability is within the current model.</caption>\n",
  )
  out.write_string(
    "<colgroup><col style=\"width:5%\"><col style=\"width:6%\"><col style=\"width:38%\"><col style=\"width:8%\"><col style=\"width:8%\"><col style=\"width:16%\"><col style=\"width:19%\"></colgroup>\n",
  )
  out.write_string(
    "<thead><tr><th scope=\"col\" class=\"number\">Rank</th><th scope=\"col\" class=\"number\">Index</th><th scope=\"col\">Function / module</th><th scope=\"col\" class=\"number\">Body B</th><th scope=\"col\" class=\"number\">Encoded B</th><th scope=\"col\" class=\"number\">Independent gzip B</th><th scope=\"col\">Model reachability</th></tr></thead><tbody>\n",
  )
  let functions = html_data_array(data, "functions")
  for rank, row in functions {
    if rank >= 20 {
      break
    }
    let index = html_data_int(row, "index").to_string()
    let dead = html_data_field(row, "dead") == Json::boolean(true)
    out.write_string(
      "<tr data-function-index=\"" +
      index +
      "\"><th scope=\"row\" class=\"number\">" +
      (rank + 1).to_string() +
      "</th>",
    )
    out.write_string(
      "<td class=\"number\">" +
      index +
      "</td><td><span class=\"function-name\">" +
      html_escape(html_data_text(row, "name")) +
      "</span><span class=\"module-name\">" +
      html_escape(html_data_text(row, "module")) +
      "</span></td>",
    )
    for key in ["bodySize", "size"] {
      out.write_string(
        "<td class=\"number\">" + grouped(html_data_int(row, key)) + "</td>",
      )
    }
    out.write_string("<td class=\"number\">")
    match html_data_field(row, "gzip") {
      Number(n, ..) => out.write_string(grouped(n.to_int()))
      _ =>
        out.write_string(
          "<span class=\"measurement-error\">failed — " +
          html_escape(html_data_text(row, "gzipError")) +
          "</span>",
        )
    }
    out.write_string(
      "</td><td><span class=\"reachability" +
      (if dead { " unreachable" } else { "" }) +
      "\">" +
      (if dead { "Unreachable in model" } else { "Reachable in model" }) +
      "</span></td></tr>\n",
    )
  }
  if functions.is_empty() {
    out.write_string(
      "<tr><td colspan=\"7\">No local functions in this module.</td></tr>\n",
    )
  }
  out.write_string("</tbody></table></div></details>\n")
  out.to_string()
}

///|
fn render_html_measured(
  analysis : Analysis,
  file_path : String,
  compression : CompressionMeasurements,
  echarts : String,
) -> String {
  let parsed = analysis.parsed
  let file_size = parsed.file_size
  let code_size = section_size(parsed, Code)
  let dead = dead_size(analysis)
  let data = report_data(analysis, file_path, compression~)
  let json = escape_for_script(data.stringify())
  let script = replace_all(HTML_SCRIPT, "__DATA__", json)
  let title = html_escape(file_path)
  let out = StringBuilder(size_hint=json.length() + echarts.length() + 24576)
  out.write_string(
    "<!DOCTYPE html>\n<html lang=\"en\">\n<head>\n<meta charset=\"utf-8\">\n<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n<title>moonsize — " +
    title +
    "</title>\n<style>\n" +
    HTML_STYLE +
    "\n</style>\n</head>\n<body>\n",
  )
  out.write_string(
    "<a class=\"skip-link\" href=\"#overview\">Skip to report</a><main class=\"shell\" id=\"report\">\n<header class=\"report-header\"><div class=\"brand\"><span class=\"brand-mark\" aria-hidden=\"true\">m</span>moonsize</div>\n<p class=\"eyebrow\">WebAssembly / size analysis</p><h1>WebAssembly size report</h1>\n<p class=\"file\">" +
    title +
    "</p>\n",
  )
  out.write_string(
    "<p class=\"report-meta\">" +
    grouped(analysis.stats.length()) +
    " local functions · " +
    grouped(html_data_array(data, "modules").length()) +
    " module labels · " +
    grouped(analysis.graph.edges.length()) +
    " modeled references</p>\n",
  )
  out.write_string(
    "<nav class=\"report-nav\" aria-label=\"Report sections\"><a href=\"#overview\">Overview</a><a href=\"#composition\">Composition</a><a href=\"#function-ranking\">Functions</a><a href=\"#module-map\">Module map</a><a href=\"#methodology\">Methods &amp; limits</a></nav></header>\n",
  )
  out.write_string(
    "<section id=\"overview\" class=\"cards\" aria-label=\"Key measurements\" tabindex=\"-1\">\n",
  )
  out.write_string(
    card(
      "File size",
      grouped(file_size) + " B",
      human_bytes(file_size) + " · complete artifact",
      false,
    ),
  )
  out.write_string(
    card(
      "Code section",
      grouped(code_size) + " B",
      share_text(code_size, file_size) + " of file · complete encoding",
      false,
    ),
  )
  let (gzip_value, gzip_sub, gzip_title) = gzip_card_fields(
    file_size,
    compression.whole_file,
  )
  out.write_string(
    card("Whole-file gzip", gzip_value, gzip_sub, false, title=gzip_title),
  )
  let warning = render_graph_warning(analysis.graph)
  out.write_string(
    card(
      "Unreachable in model",
      grouped(dead) + " B",
      if !warning.is_empty() {
        "graph incomplete; results may be inaccurate"
      } else if dead == 0 {
        "no unreachable local function bytes"
      } else {
        "encoded local function bytes · " +
        share_text(dead, file_size) +
        " of file"
      },
      dead > 0,
    ),
  )
  out.write_string(
    "</section>\n<section id=\"analysis-status\" class=\"analysis-status" +
    (if warning.is_empty() { "" } else { " warning" }) +
    "\" aria-label=\"Analysis status\">\n",
  )
  out.write_string(
    if warning.is_empty() {
      "<h2>No detected graph gaps</h2><p>No gaps detected within the current reference model. This is not full Wasm verification.</p>\n"
    } else {
      "<h2>Detected graph gaps</h2><p class=\"warn\">" +
      html_escape(warning) +
      "</p>\n"
    },
  )
  out.write_string(
    "<p class=\"scope-note\">Model results identify investigation candidates, not guaranteed deletion savings.</p><p>Unreachable functions are not a safe-deletion list. <a href=\"#methodology\">Read the model and measurement limits</a>.</p></section>\n",
  )
  out.write_string(
    "<p id=\"chart-status\" class=\"chart-status\" role=\"status\" hidden></p><noscript><p class=\"chart-status\">JavaScript is disabled. Measured cards, full function details and methods below remain readable; charts require JavaScript.</p></noscript>\n",
  )
  out.write_string(
    "<p id=\"chart-resource-mode\" class=\"panel-note\">" +
    (if echarts.is_empty() {
      "CDN chart mode: charts require a network connection. Measured cards, function details and methods are included in this file."
    } else {
      "Chart library and report data are embedded in this file; no network or sibling assets are required."
    }) +
    "</p>\n",
  )
  out.write_string(
    "<section id=\"composition\" aria-labelledby=\"composition-title\"><div class=\"section-heading\"><h2 id=\"composition-title\">Where the bytes go</h2><p>Complete sections, then attributed function encodings</p></div><div id=\"composition-panels\" class=\"composition-grid\">\n",
  )
  out.write_string(
    "<article class=\"panel\"><div class=\"panel-tools\"><h3>Sections</h3><button id=\"section-compare\" type=\"button\" aria-pressed=\"false\" aria-controls=\"sections\">Compare independent gzip</button></div><p class=\"panel-note\">Raw sizes include section headers and payloads. Both views use the same byte axis.</p><p class=\"panel-note\">Each section is compressed separately. These sizes are not additive and do not represent whole-file transfer shares.</p><div id=\"sections\" class=\"chart\" role=\"img\" aria-label=\"Section sizes in encoded bytes\"></div>\n",
  )
  for row in html_data_array(data, "sections") {
    if html_data_field(row, "gzipError") is String(error) {
      out.write_string(
        "<p class=\"measurement-error\">" +
        html_escape(html_data_text(row, "name")) +
        ": independent gzip failed — " +
        html_escape(error) +
        "</p>\n",
      )
    }
  }
  out.write_string(
    "</article><article class=\"panel\"><h3>Modules · attributed function bytes</h3><p class=\"panel-note\">Shares are based on attributed function bytes; code-section overhead is excluded. Small modules may be grouped as other.</p><div id=\"modules\" class=\"chart ring\" role=\"img\" aria-label=\"Module shares of attributed function encodings\"></div><ul class=\"print-legend\" aria-label=\"All module slices in print\">",
  )
  for slice in html_data_array(data, "pie") {
    out.write_string(
      "<li>" +
      html_escape(html_data_text(slice, "name")) +
      " · " +
      grouped(html_data_int(slice, "size")) +
      " B</li>",
    )
  }
  out.write_string("</ul></article></div></section>\n")
  out.write_string(
    "<section id=\"function-ranking\" aria-labelledby=\"functions-title\"><div class=\"section-heading\"><h2 id=\"functions-title\">Functions to investigate</h2><p>Top 20 local functions, ranked by body bytes</p></div><article class=\"panel\"><p class=\"panel-note\">Function gzip uses independent streams including size prefixes, with ratios based on encoded size. It does not measure transfer savings from removal.</p><div id=\"functions\" class=\"chart\" role=\"img\" aria-label=\"Top 20 functions by body bytes; complete names in the table below\"></div>\n",
  )
  out.write_string(html_function_table(data))
  out.write_string(
    "</article></section>\n<section id=\"module-map\" aria-labelledby=\"map-title\"><div class=\"section-heading\"><h2 id=\"map-title\">Module map</h2><p>Module → function · raw encoded bytes</p></div><article class=\"panel\"><p class=\"panel-note\">Area is raw encoded bytes. Tooltip gzip values are independent function streams, not additive transfer shares. Modules keep their ring colors; outlined cells and text identify functions unreachable in the model.</p><div id=\"treemap\" class=\"chart map\" role=\"img\" aria-label=\"Module and function encodings; areas are raw bytes\"></div></article></section>\n",
  )
  out.write_string(
    "<section id=\"methodology\" class=\"methods\"><details id=\"method-details\"><summary>Methods, measurement ranges &amp; model limits</summary><h3>Reference model</h3><p>" +
    html_escape(graph_modeling_scope()) +
    "</p><p>" +
    html_escape(retained_modeling_scope()) +
    "</p><h3>Compression</h3><p>" +
    html_escape(html_data_text(data, "compression_scope")) +
    "</p><h3>Chart availability</h3><p>",
  )
  out.write_string(
    if echarts.is_empty() {
      "CDN fallback mode: charts need a network connection to load ECharts. The measured cards, function details and methods are included in this file and remain readable without it."
    } else {
      "ECharts, styles, scripts and measured data are embedded in this file. No remote fonts, chart assets or sibling files are required; the report can be moved to another directory."
    },
  )
  out.write_string(
    "</p></details></section>\n<footer>Generated by moonsize · " +
    grouped(analysis.stats.length()) +
    " local functions. Model findings guide investigation; verify optimization outcomes by rebuilding and comparing complete artifacts.</footer>\n</main>\n",
  )
  if echarts.length() > 0 {
    out.write_string(
      "<script>\n" + escape_script_end(echarts) + "\n</script>\n",
    )
  } else {
    out.write_string(
      "<script src=\"https://cdn.jsdelivr.net/npm/echarts@5/dist/echarts.min.js\"></script>\n",
    )
  }
  out.write_string("<script>\n" + script + "\n</script>\n</body>\n</html>\n")
  out.to_string()
}
