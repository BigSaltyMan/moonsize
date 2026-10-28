///|
fn opcode_search_stat_json(stat : FunctionStat) -> Json {
  let row : Map[String, Json] = Map([])
  row.set("index", int_json(stat.index))
  row.set("name", Json::string(stat.name))
  row.set("raw_name", path_optional_string(stat.raw_name))
  row.set("module_name", Json::string(stat.module_name))
  row.set("offset", int_json(stat.offset))
  row.set("body_size", int_json(stat.body_size))
  row.set("total_size", int_json(stat.total_size))
  Json::object(row)
}

///|
pub fn render_opcode_search_json(report : OpcodeSearchReport) -> String {
  let root : Map[String, Json] = Map([])
  root.set("format", Json::string("moonsize-opcode-search"))
  root.set("schema_version", int_json(1))
  root.set("query", Json::string(report.query))
  root.set("sha256", Json::string(report.sha256))
  root.set("matching_rule", Json::string(report.matching_rule))
  root.set("scope", Json::string(report.scope))
  root.set("file_size", int_json(report.file_size))
  root.set("imported_function_count", int_json(report.imported_function_count))
  root.set(
    "scanned_local_function_count",
    int_json(report.scanned_local_function_count),
  )
  root.set("matched_function_count", int_json(report.matched_function_count))
  root.set(
    "unmatched_function_count",
    int_json(report.unmatched_function_count),
  )
  root.set("instruction_count", int_json(report.instruction_count))
  root.set("instruction_bytes", int_json(report.instruction_bytes))
  root.set("match_count", int_json(report.match_count))
  root.set("matched_encoded_bytes", int_json(report.matched_encoded_bytes))
  root.set("other_instruction_bytes", int_json(report.other_instruction_bytes))
  root.set(
    "functions",
    Json::array(
      report.functions.map(fn(f) {
        let row : Map[String, Json] = Map([])
        row.set("stat", opcode_search_stat_json(f.stat))
        row.set("match_count", int_json(f.match_count))
        row.set("matched_encoded_bytes", int_json(f.matched_encoded_bytes))
        row.set(
          "sites",
          Json::array(
            f.sites.map(fn(site) {
              let value : Map[String, Json] = Map([])
              value.set("ordinal", int_json(site.ordinal))
              value.set("mnemonic", Json::string(site.mnemonic))
              value.set("file_offset", int_json(site.file_offset))
              value.set(
                "body_relative_offset",
                int_json(site.body_relative_offset),
              )
              value.set("encoded_size", int_json(site.encoded_size))
              Json::object(value)
            }),
          ),
        )
        Json::object(row)
      }),
    ),
  )
  Json::object(root).stringify(indent=2) + "\n"
}

///|
pub fn render_opcode_search(report : OpcodeSearchReport, top : Int) -> String {
  let out = StringBuilder()
  out.write_string("OPCODE LOCATION SEARCH\n\n")
  out.write_string("Query: " + search_terminal_string(report.query) + "\n")
  out.write_string("Input: \{report.file_size} B; SHA-256 \{report.sha256}\n")
  out.write_string(report.matching_rule + "\n")
  out.write_string("Imported functions: \{report.imported_function_count}\n")
  out.write_string(
    "Scanned local functions: \{report.scanned_local_function_count} = matched \{report.matched_function_count} + unmatched \{report.unmatched_function_count}\n",
  )
  out.write_string(
    "Instructions: \{report.instruction_count}; matches: \{report.match_count}\n",
  )
  out.write_string(
    "Instruction bytes: \{report.instruction_bytes} = matched \{report.matched_encoded_bytes} + other \{report.other_instruction_bytes}\n",
  )
  let shown = top.max(0).min(report.match_count)
  out.write_string(
    "\nMATCHES: showing \{shown} of \{report.match_count} (file order)\nFUNCTION INDEX  ORDINAL  FILE OFFSET  BODY OFFSET  SIZE  NAME\n",
  )
  if report.scanned_local_function_count == 0 {
    out.write_string("No local function definitions to search.\n")
  } else if report.match_count == 0 {
    out.write_string(
      "No matching mnemonic in the decoded local function instructions.\n",
    )
  }
  let mut emitted = 0
  for f in report.functions {
    if emitted >= shown {
      break
    }
    for site in f.sites {
      if emitted >= shown {
        break
      }
      out.write_string(
        "\{f.stat.index}  \{site.ordinal}  \{site.file_offset}  \{site.body_relative_offset}  \{site.encoded_size}  " +
        search_terminal_string(f.stat.name) +
        "\n",
      )
      emitted += 1
    }
  }
  out.write_string("\n" + report.scope + "\n")
  out.to_string()
}
