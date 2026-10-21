///|
fn html_data_range(range : DataByteRange) -> String {
  "[" +
  range.offset.to_string() +
  ", " +
  (range.offset + range.size).to_string() +
  ")"
}

///|
/// One bounded metadata row. Keep this wording in sync with appendDataEntry.
fn html_data_entry(entry : DataSegment) -> String {
  let out = StringBuilder()
  out.write_string(
    "<tr data-segment-index=\"" +
    entry.index.to_string() +
    "\"><th scope=\"row\" class=\"number\">" +
    entry.index.to_string() +
    "</th>",
  )
  out.write_string(
    "<td>" +
    html_escape(data_mode_text(entry.mode)) +
    "</td><td class=\"number\">" +
    (match entry.memory_index {
      Some(index) => index.to_string()
      None => "n/a"
    }) +
    "</td>",
  )
  out.write_string(
    "<td class=\"number\">" +
    grouped(entry.payload.size) +
    "</td><td class=\"number\">" +
    grouped(entry.encoding.size) +
    "</td>",
  )
  out.write_string(
    "<td><details class=\"data-entry-details\"><summary>" +
    html_data_range(entry.encoding) +
    "</summary><p>Payload file range " +
    html_data_range(entry.payload) +
    "</p>",
  )
  out.write_string(
    match entry.offset_expression {
      Some(range) =>
        "<p>Offset expression file range " +
        html_data_range(range) +
        "; not_evaluated (includes end).</p>"
      None => "<p>Offset expression not_applicable.</p>"
    },
  )
  out.write_string("</details></td></tr>\n")
  out.to_string()
}

///|
/// Static first batch is readable without JavaScript or the chart library.
fn html_data_segments_panel(report : DataSegmentsReport) -> String {
  let out = StringBuilder()
  out.write_string(
    "<section id=\"data-segments\" class=\"panel data-segments\" aria-labelledby=\"data-title\"><div class=\"section-heading\"><h2 id=\"data-title\">Data segment encodings · Current input</h2><p>File byte ledger · no baseline entry comparison</p></div>\n",
  )
  out.write_string("<dl class=\"data-summary\">")
  for
    (label, size) in [
      ("Data complete B", report.section_size),
      ("Payload B", report.payload_size),
      ("Entry metadata B", report.entry_metadata_size),
      ("Section overhead B", report.header_size + report.count_size),
      ("Entries", report.entries.length()),
    ] {
    out.write_string(
      "<div><dt>" + label + "</dt><dd>" + grouped(size) + "</dd></div>",
    )
  }
  out.write_string(
    "</dl><p class=\"panel-note\" id=\"data-ledger\">Complete data " +
    grouped(report.section_size) +
    " B = payload " +
    grouped(report.payload_size) +
    " B + entry metadata " +
    grouped(report.entry_metadata_size) +
    " B + section overhead " +
    grouped(report.header_size + report.count_size) +
    " B (header " +
    grouped(report.header_size) +
    " B + count field " +
    grouped(report.count_size) +
    " B). Datacount: " +
    (match report.datacount {
      Some(n) => n.to_string()
      None => "absent"
    }) +
    " (independent section; excluded).</p>\n",
  )
  out.write_string(
    "<p class=\"panel-note\" id=\"data-scope\">" +
    html_escape(data_scope()) +
    "</p>",
  )
  let entries = report.entries.copy()
  entries.sort_by(fn(a, b) {
    if a.payload.size != b.payload.size {
      b.payload.size - a.payload.size
    } else {
      a.index - b.index
    }
  })
  let shown = if entries.length() < 20 { entries.length() } else { 20 }
  out.write_string(
    "<p class=\"panel-note\" id=\"data-shown\" aria-live=\"polite\">Showing " +
    shown.to_string() +
    " of " +
    entries.length().to_string() +
    " entries. Printing includes only the displayed subset.</p>",
  )
  out.write_string(
    "<div class=\"table-scroll\" tabindex=\"0\" role=\"region\" aria-label=\"Current data entries, scroll horizontally on narrow screens\"><table class=\"data-table\"><caption>Current input only. Payload descending, original index ascending. All ranges are file offsets [start, end). Open a range for initialization details.</caption>",
  )
  out.write_string(
    "<colgroup><col style=\"width:8%\"><col style=\"width:12%\"><col style=\"width:10%\"><col style=\"width:14%\"><col style=\"width:14%\"><col style=\"width:42%\"></colgroup><thead><tr><th scope=\"col\" class=\"number\">Index</th><th scope=\"col\">Mode</th><th scope=\"col\" class=\"number\">Memory</th><th scope=\"col\" class=\"number\">Payload B</th><th scope=\"col\" class=\"number\">Encoded B</th><th scope=\"col\">File range</th></tr></thead><tbody id=\"data-rows\">",
  )
  for i = 0; i < shown; i = i + 1 {
    out.write_string(html_data_entry(entries[i]))
  }
  if entries.is_empty() {
    out.write_string(
      "<tr><td colspan=\"6\">" +
      (if report.section is None {
        "No data section in this input."
      } else {
        "Data section is present with zero entries."
      }) +
      "</td></tr>",
    )
  }
  out.write_string(
    "</tbody></table></div><button id=\"data-more\" type=\"button\" aria-controls=\"data-rows\" hidden>Show 20 more data entries</button><noscript><p class=\"panel-note\">Only the first 20 entries are included without JavaScript. Use single-file data JSON for all metadata.</p></noscript></section>\n",
  )
  out.to_string()
}
