///|
/// JSON quoting handles C0, quotes and backslashes; also escape C1 and line
/// separators for a single terminal row. Never feed this back into JSON data.
fn search_terminal_string(text : String) -> String {
  let quoted = Json::string(text).stringify()
  let out = StringBuilder()
  for ch in quoted.iter() {
    let code = ch.to_int()
    if (code >= 0x7f && code <= 0x9f) || code == 0x2028 || code == 0x2029 {
      out.write_string("\\u")
      let hex = "0123456789abcdef"
      for shift in [12, 8, 4, 0] {
        out.write_string(
          hex[(code >> shift) & 15:((code >> shift) & 15) + 1].to_owned(),
        )
      }
    } else {
      out.write_string(ch.to_string())
    }
  }
  out.to_string()
}

///|
pub fn render_function_search_json(report : FunctionSearchReport) -> String {
  let root : Map[String, Json] = Map([])
  root.set("format", Json::string("moonsize-function-search"))
  root.set("schema_version", int_json(1))
  root.set("file_size", int_json(report.file_size))
  root.set("sha256", Json::string(report.sha256))
  root.set("query", Json::string(report.query))
  root.set("matching_rule", Json::string(report.matching_rule))
  root.set("scope", Json::string(report.scope))
  root.set("local_function_count", int_json(report.local_function_count))
  root.set("named_count", int_json(report.named_count))
  root.set("unnamed_count", int_json(report.unnamed_count))
  root.set("match_count", int_json(report.match_count))
  root.set("unmatched_named_count", int_json(report.unmatched_named_count))
  root.set("matched_body_bytes", int_json(report.matched_body_bytes))
  root.set("matched_prefix_bytes", int_json(report.matched_prefix_bytes))
  root.set("matched_encoded_bytes", int_json(report.matched_encoded_bytes))
  root.set(
    "matches",
    Json::array(
      report.matches.map(fn(item) {
        let row : Map[String, Json] = Map([])
        row.set("index", int_json(item.index))
        row.set("name", Json::string(item.name))
        row.set("raw_name", Json::string(item.raw_name))
        row.set("module_name", Json::string(item.module_name))
        row.set("offset", int_json(item.offset))
        row.set("body_size", int_json(item.body_size))
        row.set("total_size", int_json(item.total_size))
        row.set("matched_raw_name", Json::boolean(item.matched_raw_name))
        row.set(
          "matched_display_name",
          Json::boolean(item.matched_display_name),
        )
        Json::object(row)
      }),
    ),
  )
  Json::object(root).stringify(indent=2) + "\n"
}

///|
pub fn render_function_search(
  report : FunctionSearchReport,
  top : Int,
) -> String {
  let out = StringBuilder()
  out.write_string("LOCAL FUNCTION NAME SEARCH\n\n")
  out.write_string("Input: \{report.file_size} B; SHA-256 \{report.sha256}\n")
  out.write_string("Query: " + search_terminal_string(report.query) + "\n")
  out.write_string(report.matching_rule + "\n")
  out.write_string("\nNAME COVERAGE AND MATCH BYTE LEDGER\n")
  out.write_string(
    "Local functions: \{report.local_function_count} = named \{report.named_count} + unnamed \{report.unnamed_count}\n",
  )
  out.write_string(
    "Named functions: \{report.named_count} = matched \{report.match_count} + unmatched \{report.unmatched_named_count}\n",
  )
  out.write_string(
    "Matched encoded bytes: \{report.matched_encoded_bytes} B = body \{report.matched_body_bytes} B + length prefixes \{report.matched_prefix_bytes} B\n",
  )
  let shown = top.max(0).min(report.match_count)
  out.write_string(
    "\nMATCHES: showing \{shown} of \{report.match_count} (total bytes descending, index ascending)\nINDEX  BODY B  TOTAL B  MATCH SOURCE  NAME\n",
  )
  if report.local_function_count == 0 {
    out.write_string("No local function definitions.\n")
  } else if report.named_count == 0 {
    out.write_string("No usable local function names available.\n")
  } else if report.match_count == 0 {
    out.write_string("No matches in the available local function names.\n")
  }
  for i in 0..<shown {
    let item = report.matches[i]
    let source = if item.matched_raw_name && item.matched_display_name {
      "raw+display"
    } else if item.matched_raw_name {
      "raw"
    } else {
      "display"
    }
    out.write_string(
      "\{item.index}  \{item.body_size}  \{item.total_size}  \{source}  " +
      search_terminal_string(item.name) +
      "\n",
    )
    out.write_string(
      "  raw_name: " + search_terminal_string(item.raw_name) + "\n",
    )
    out.write_string(
      "  module: " +
      search_terminal_string(item.module_name) +
      "; body-length prefix file offset \{item.offset}\n",
    )
  }
  out.write_string("\n" + report.scope + "\n")
  out.to_string()
}
