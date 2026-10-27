///|
pub fn render_module_opcodes(report : ModuleOpcodeReport, top : Int) -> String {
  let out = StringBuilder()
  out.write_string(
    "MODULE FUNCTION OPCODE STATISTICS\n\nInput: \{report.file_size} B; SHA-256 \{report.sha256}\nImported functions: \{report.imported_function_count}; local functions: \{report.local_function_count}\n",
  )
  match report.code_section {
    None => out.write_string("No code section; no code/count ranges.\n")
    Some(code) => {
      out.write_string(
        "Code section: file offset \{code.offset}, total \{code.total_size} B, payload \{code.payload_size} B\n",
      )
      if report.local_function_count == 0 {
        out.write_string(
          "Explicit empty code section; its header and zero-count encoding are retained.\n",
        )
      }
    }
  }
  match report.count_encoding {
    Some(span) =>
      out.write_string(
        "Function count encoding: file offset \{span.file_offset}, size \{span.size} B\n",
      )
    None => ()
  }
  let code_size = match report.code_section {
    Some(code) => code.total_size
    None => 0
  }
  out.write_string(
    "Code bytes: \{code_size} = header \{report.code_header_bytes} + count encoding \{report.count_encoding_bytes} + body prefixes \{report.body_prefix_bytes} + locals \{report.locals_encoding_bytes} + instructions \{report.instruction_bytes}\n",
  )
  out.write_string(
    "Instructions: \{report.instruction_count}; complete instruction encoding bytes: \{report.instruction_bytes}\n",
  )
  let shown = top.max(0).min(report.groups.length())
  out.write_string(
    "\nOPCODE GROUPS: showing \{shown} of \{report.groups.length()} (encoded bytes descending, count descending, mnemonic ascending)\nMNEMONIC  COUNT  FUNCTIONS  ENCODED BYTES\n",
  )
  if report.groups.is_empty() {
    out.write_string(
      "No function instructions recorded. This is not full function-termination or semantic validation.\n",
    )
  }
  for i in 0..<shown {
    let group = report.groups[i]
    out.write_string(
      "\{group.mnemonic}  \{group.count}  \{group.function_count}  \{group.encoded_bytes}\n",
    )
  }
  out.write_string("\n" + report.scope + "\n")
  out.to_string()
}

///|
pub fn render_module_opcodes_json(report : ModuleOpcodeReport) -> String {
  let root : Map[String, Json] = Map([])
  root.set("format", Json::string("moonsize-module-opcodes"))
  root.set("schema_version", int_json(1))
  root.set("file_size", int_json(report.file_size))
  root.set("sha256", Json::string(report.sha256))
  root.set(
    "code_section",
    match report.code_section {
      None => Json::null()
      Some(code) => {
        let value : Map[String, Json] = Map([])
        value.set("id", int_json(code.id))
        value.set("kind", Json::string(code.kind.name()))
        value.set("offset", int_json(code.offset))
        value.set("payload_size", int_json(code.payload_size))
        value.set("total_size", int_json(code.total_size))
        Json::object(value)
      }
    },
  )
  root.set(
    "count_encoding",
    match report.count_encoding {
      Some(span) => function_instruction_range_json(span)
      None => Json::null()
    },
  )
  for
    (key, value) in [
      ("imported_function_count", report.imported_function_count),
      ("local_function_count", report.local_function_count),
      ("code_header_bytes", report.code_header_bytes),
      ("count_encoding_bytes", report.count_encoding_bytes),
      ("body_prefix_bytes", report.body_prefix_bytes),
      ("locals_encoding_bytes", report.locals_encoding_bytes),
      ("instruction_bytes", report.instruction_bytes),
      ("instruction_count", report.instruction_count),
    ] {
    root.set(key, int_json(value))
  }
  root.set(
    "groups",
    Json::array(
      report.groups.map(fn(group) {
        let row : Map[String, Json] = Map([])
        row.set("mnemonic", Json::string(group.mnemonic))
        row.set("count", int_json(group.count))
        row.set("encoded_bytes", int_json(group.encoded_bytes))
        row.set("function_count", int_json(group.function_count))
        Json::object(row)
      }),
    ),
  )
  root.set(
    "functions",
    Json::array(
      report.functions.map(fn(summary) {
        let row : Map[String, Json] = Map([])
        let stat = summary.stat
        let value : Map[String, Json] = Map([])
        value.set("index", int_json(stat.index))
        value.set(
          "name",
          match stat.raw_name {
            Some(_) => Json::string(stat.name)
            None => Json::null()
          },
        )
        value.set("raw_name", path_optional_string(stat.raw_name))
        value.set("display_name", Json::string(stat.name))
        value.set("module_name", Json::string(stat.module_name))
        value.set("body_size", int_json(stat.body_size))
        value.set("total_size", int_json(stat.total_size))
        value.set("offset", int_json(stat.offset))
        row.set("stat", Json::object(value))
        row.set(
          "locals_encoding",
          function_instruction_range_json(summary.locals_encoding),
        )
        row.set("instruction_count", int_json(summary.instruction_count))
        row.set("instruction_bytes", int_json(summary.instruction_bytes))
        Json::object(row)
      }),
    ),
  )
  root.set("scope", Json::string(report.scope))
  Json::object(root).stringify(indent=2) + "\n"
}
