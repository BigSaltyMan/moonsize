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
/// The label a section is known by in the report.
fn section_label(section : Section) -> String {
  match section.custom_name {
    Some(name) => section.kind.name() + " (" + name + ")"
    None => section.kind.name()
  }
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
/// The payload the page draws from, as one JSON object.
fn report_data(analysis : Analysis, file_path : String) -> Json {
  let parsed = analysis.parsed
  let members : Map[String, Json] = Map([])
  members.set("file", Json::string(file_path))
  members.set("fileSize", int_json(parsed.file_size))
  members.set("codeSize", int_json(section_size(parsed, Code)))
  members.set("deadSize", int_json(dead_size(analysis)))
  let sections : Array[Json] = []
  for section in parsed.sections {
    let row : Map[String, Json] = Map([])
    row.set("name", Json::string(section_label(section)))
    row.set("total", int_json(section.total_size))
    row.set("payload", int_json(section.payload_size))
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
    row.set("dead", Json::boolean(!analysis.reachable.contains(stat.index)))
    functions.push(Json::object(row))
  }
  members.set("functions", Json::array(functions))
  let modules : Array[Json] = []
  for group in group_modules(analysis.stats) {
    let children : Array[Json] = []
    for child in group.children {
      let leaf : Map[String, Json] = Map([])
      leaf.set("name", Json::string(child.name))
      leaf.set("value", int_json(child.total_size))
      leaf.set("dead", Json::boolean(!analysis.reachable.contains(child.index)))
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
  Json::object(members)
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
      out.write_string(@utf8.decode_lossy(bytes[i:i + 1]))
      i = i + 1
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
/// The document's styling.
const HTML_STYLE : String = "      :root {\n      --bg: #f6f8fb; --panel: #ffffff; --ink: #0f172a;\n      --muted: #64748b; --line: #e2e8f0; --accent: #2563eb;\n    }\n    * { box-sizing: border-box; }\n    body {\n      margin: 0; background: var(--bg); color: var(--ink);\n      font: 14px/1.5 ui-sans-serif, system-ui, -apple-system, \"Segoe UI\", Roboto, sans-serif;\n    }\n    header { padding: 26px 28px 6px; }\n    h1 { margin: 0; font-size: 20px; font-weight: 600; letter-spacing: -0.01em; }\n    h1 span { color: var(--muted); font-weight: 400; }\n    .file {\n      margin: 5px 0 0; color: var(--muted); font-size: 12px; word-break: break-all;\n      font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;\n    }\n    .cards {\n      display: grid; gap: 12px; padding: 16px 28px 4px;\n      grid-template-columns: repeat(auto-fit, minmax(190px, 1fr));\n    }\n    .card {\n      background: var(--panel); border: 1px solid var(--line);\n      border-radius: 10px; padding: 14px 16px;\n    }\n    .card .label {\n      display: block; color: var(--muted); font-size: 11px; font-weight: 600;\n      text-transform: uppercase; letter-spacing: 0.07em;\n    }\n    .card .value {\n      display: block; margin-top: 7px; font-size: 23px; font-weight: 600;\n      font-variant-numeric: tabular-nums;\n    }\n    .card .sub { display: block; margin-top: 1px; color: var(--muted); font-size: 12px; }\n    .charts {\n      display: grid; gap: 12px; padding: 12px 28px 28px;\n      grid-template-columns: repeat(auto-fit, minmax(430px, 1fr));\n    }\n    .panel {\n      background: var(--panel); border: 1px solid var(--line);\n      border-radius: 10px; padding: 14px 16px 6px; overflow: hidden;\n    }\n    .panel.wide { grid-column: 1 / -1; }\n    .panel h2 {\n      margin: 0 0 8px; font-size: 12px; font-weight: 600; color: var(--muted);\n      text-transform: uppercase; letter-spacing: 0.07em;\n    }\n    .chart { width: 100%; height: 320px; }\n    .chart.tall { height: 440px; }\n    .empty {\n      height: 320px; display: flex; align-items: center; justify-content: center;\n      color: var(--muted); font-size: 13px;\n    }\n    .card.alert .value { color: #dc2626; }\n    footer { padding: 0 28px 30px; color: var(--muted); font-size: 12px; }"

///|
/// The page's script: number formatting, four chart builders, and the wiring.
const HTML_SCRIPT : String = "    const DATA = __DATA__;\n\n    const esc = (s) => String(s).replace(/[&<>\"']/g, (c) => ({\n      '&': '&amp;', '<': '&lt;', '>': '&gt;', '\"': '&quot;', \"'\": '&#39;',\n    }[c]));\n\n    const BYTES = (v) => {\n      if (v >= 1048576) return (v / 1048576).toFixed(2) + ' MB';\n      if (v >= 1024) return (v / 1024).toFixed(1) + ' KB';\n      return v + ' B';\n    };\n\n    const NUM = (v) => v.toLocaleString('en-US');\n    const PCT = (part, whole) => whole > 0 ? (part / whole * 100).toFixed(1) + '%' : 'n/a';\n\n    const INK = '#334155';\n    const LINE = '#e2e8f0';\n    const MONO = 'ui-monospace, SFMono-Regular, Menlo, Consolas, monospace';\n\n    const axis = (extra) => Object.assign({\n      axisLine: { lineStyle: { color: '#cbd5e1' } },\n      axisTick: { show: false },\n      axisLabel: { color: INK, fontSize: 11 },\n      splitLine: { lineStyle: { color: LINE } },\n    }, extra || {});\n\n    // A static report: the grow-in animation would leave a chart empty in a\n    // screenshot, a print, or any capture that does not run animation frames.\n    const base = {\n      animation: false,\n      textStyle: { fontFamily: 'ui-sans-serif, system-ui, -apple-system, \"Segoe UI\", Roboto, sans-serif' },\n    };\n\n    function barOption(rows, color) {\n      return Object.assign({}, base, {\n        grid: { left: 4, right: 96, top: 12, bottom: 4, containLabel: true },\n        tooltip: {\n          trigger: 'axis',\n          axisPointer: { type: 'shadow' },\n          formatter: (ps) => {\n            const r = rows[ps[0].dataIndex];\n            return '<b>' + esc(r.name) + '</b><br/>' + NUM(r.size) + ' B (' + PCT(r.size, DATA.fileSize) + ' of file)';\n          },\n        },\n        xAxis: axis({ type: 'value', axisLabel: { color: INK, fontSize: 11, formatter: BYTES } }),\n        yAxis: axis({\n          type: 'category',\n          inverse: true,\n          data: rows.map((r) => r.name),\n          axisLabel: { color: INK, fontSize: 11, fontFamily: MONO, width: 190, overflow: 'truncate' },\n          splitLine: { show: false },\n        }),\n        series: [{\n          type: 'bar',\n          data: rows.map((r) => r.size),\n          itemStyle: { color: color, borderRadius: [0, 3, 3, 0] },\n          label: {\n            show: true, position: 'right', color: INK, fontSize: 11,\n            formatter: (p) => BYTES(p.value),\n          },\n        }],\n      });\n    }\n\n    function pieOption(rows) {\n      return Object.assign({}, base, {\n        tooltip: {\n          trigger: 'item',\n          formatter: (p) => '<b>' + esc(p.name) + '</b><br/>' + NUM(p.value) + ' B<br/>' + p.percent + '% of the code section',\n        },\n        legend: {\n          type: 'scroll', bottom: 0, icon: 'circle', itemWidth: 8, itemHeight: 8,\n          textStyle: { color: INK, fontSize: 11 },\n        },\n        series: [{\n          type: 'pie',\n          radius: ['40%', '68%'],\n          center: ['50%', '45%'],\n          avoidLabelOverlap: true,\n          itemStyle: { borderColor: '#fff', borderWidth: 1 },\n          label: { fontSize: 11, color: INK, formatter: '{b}\\n{d}%' },\n          labelLine: { length: 8, length2: 8 },\n          data: rows.map((r) => ({ name: r.name, value: r.size })),\n        }],\n      });\n    }\n\n    function treemapOption(rows) {\n      return Object.assign({}, base, {\n        tooltip: {\n          formatter: (p) => '<b>' + esc(p.name) + '</b><br/>' + NUM(p.value) + ' B'\n            + (p.data && p.data.dead ? '<br/>unreachable' : ''),\n        },\n        series: [{\n          type: 'treemap',\n          roam: false,\n          nodeClick: false,\n          breadcrumb: { show: false },\n          width: '100%',\n          height: '100%',\n          top: 2,\n          left: 2,\n          right: 2,\n          bottom: 2,\n          upperLabel: { show: true, height: 22, fontSize: 11, color: '#fff' },\n          itemStyle: { borderColor: '#fff', borderWidth: 1, gapWidth: 1 },\n          levels: [\n            { itemStyle: { borderWidth: 0, gapWidth: 3 }, colorSaturation: [0.4, 0.55] },\n            { itemStyle: { borderWidth: 1, gapWidth: 1 }, colorSaturation: [0.35, 0.5] },\n          ],\n          data: rows.map((m) => ({\n            name: m.name,\n            value: m.size,\n            children: m.children.map((c) => ({\n              name: c.name,\n              value: c.value,\n              dead: c.dead,\n              itemStyle: c.dead ? { color: '#f87171' } : undefined,\n            })),\n          })),\n        }],\n      });\n    }\n\n    function emptyInto(id, message) {\n      const el = document.getElementById(id);\n      el.className = 'empty';\n      el.textContent = message;\n    }\n\n    const charts = [];\n\n    function mount(id, option) {\n      const chart = echarts.init(document.getElementById(id));\n      chart.setOption(option);\n      charts.push(chart);\n    }\n\n    function main() {\n      const sections = DATA.sections.map((s) => ({ name: s.name, size: s.total, payload: s.payload }));\n      if (sections.length) mount('sections', barOption(sections, '#60a5fa'));\n      else emptyInto('sections', 'no sections');\n\n      const top = DATA.functions.slice(0, 20).map((f) => ({ name: f.name, size: f.bodySize }));\n      if (top.length) mount('functions', barOption(top, '#34d399'));\n      else emptyInto('functions', 'no functions');\n\n      const modules = DATA.modules.filter((m) => m.size > 0);\n      if (modules.length) mount('modules', pieOption(modules));\n      else emptyInto('modules', 'no functions');\n\n      if (modules.length) mount('treemap', treemapOption(modules));\n      else emptyInto('treemap', 'no functions');\n\n      window.addEventListener('resize', () => charts.forEach((c) => c.resize()));\n    }\n\n    main();"

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
fn card(label : String, value : String, sub : String, alert : Bool) -> String {
  let klass = if alert { "card alert" } else { "card" }
  "      <div class=\"" +
  klass +
  "\">\n        <span class=\"label\">" +
  html_escape(label) +
  "</span>\n        <span class=\"value\">" +
  html_escape(value) +
  "</span>\n        <span class=\"sub\">" +
  html_escape(sub) +
  "</span>\n      </div>\n"
}

///|
/// Render the whole analysis as one HTML document.
///
/// `echarts` is the chart library's source. Passing it inlines the library, so
/// the report opens from any directory with no network and no sibling file;
/// leaving it empty emits a CDN `<script src>` instead, which keeps the command
/// working for someone who has the binary but not the repository around it. The
/// library does no I/O, so reading `assets/echarts.min.js` is the caller's job.
pub fn render_html(
  analysis : Analysis,
  file_path : String,
  echarts? : String = "",
) -> String {
  let parsed = analysis.parsed
  let file_size = parsed.file_size
  let code_size = section_size(parsed, Code)
  let dead = dead_size(analysis)
  let json = escape_for_script(report_data(analysis, file_path).stringify())
  let script = replace_all(HTML_SCRIPT, "__DATA__", json)
  let title = html_escape(file_path)
  let out = StringBuilder(size_hint=json.length() + echarts.length() + 16384)
  out.write_string(
    "<!DOCTYPE html>\n<html lang=\"en\">\n<head>\n<meta charset=\"utf-8\">\n" +
    "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n" +
    "<title>moonsize — " +
    title +
    "</title>\n<style>\n" +
    HTML_STYLE +
    "\n</style>\n</head>\n<body>\n",
  )
  out.write_string(
    "<header>\n  <h1>moonsize <span>· size report</span></h1>\n" +
    "  <p class=\"file\">" +
    title +
    "</p>\n</header>\n",
  )
  out.write_string("<section class=\"cards\">\n")
  out.write_string(
    card("File size", grouped(file_size) + " B", human_bytes(file_size), false),
  )
  out.write_string(
    card(
      "Code section",
      grouped(code_size) + " B",
      share_text(code_size, file_size) + " of file",
      false,
    ),
  )
  out.write_string(
    card(
      "Dead code",
      grouped(dead) + " B",
      if dead == 0 {
        "nothing unreachable"
      } else {
        share_text(dead, file_size) + " of file"
      },
      dead > 0,
    ),
  )
  out.write_string("</section>\n")
  out.write_string(
    "<section class=\"charts\">\n" +
    "  <div class=\"panel\"><h2>Sections</h2><div id=\"sections\" class=\"chart\"></div></div>\n" +
    "  <div class=\"panel\"><h2>Top 20 functions by body size</h2>" +
    "<div id=\"functions\" class=\"chart\"></div></div>\n" +
    "  <div class=\"panel\"><h2>Modules — share of the code section</h2>" +
    "<div id=\"modules\" class=\"chart\"></div></div>\n" +
    "  <div class=\"panel wide\"><h2>Treemap — module → function, area is bytes</h2>" +
    "<div id=\"treemap\" class=\"chart tall\"></div></div>\n" +
    "</section>\n",
  )
  out.write_string(
    "<footer>\n  " +
    plural(analysis.stats.length(), "function") +
    " analysed, " +
    plural(group_modules(analysis.stats).length(), "module") +
    ", " +
    grouped(analysis.graph.edges.length()) +
    " references in the call graph. Red cells in the treemap are unreachable.\n" +
    "</footer>\n",
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
