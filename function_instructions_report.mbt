///|
fn function_instruction_range_json(range : FunctionInstructionRange) -> Json {
  let item : Map[String, Json] = Map([])
  item.set("file_offset", int_json(range.file_offset))
  item.set("size", int_json(range.size))
  Json::object(item)
}

///|
fn function_instructions_json_value(
  report : FunctionInstructionsReport,
) -> Json {
  let root : Map[String, Json] = Map([])
  root.set("format", Json::string("moonsize-function-instructions"))
  root.set("schema_version", int_json(1))
  root.set("file_size", int_json(report.file_size))
  root.set("sha256", Json::string(report.sha256))
  root.set("index", int_json(report.index))
  root.set("name", Json::string(report.name))
  root.set("raw_name", path_optional_string(report.raw_name))
  root.set("entry", function_instruction_range_json(report.entry))
  root.set("prefix", function_instruction_range_json(report.prefix))
  root.set("body", function_instruction_range_json(report.body))
  root.set(
    "locals_encoding",
    function_instruction_range_json(report.locals_encoding),
  )
  root.set("instruction_bytes", int_json(report.instruction_bytes))
  root.set("instruction_count", int_json(report.instruction_count))
  root.set("scope", Json::string(report.scope))
  root.set(
    "groups",
    Json::array(
      report.groups.map(fn(group) {
        let row : Map[String, Json] = Map([])
        row.set("mnemonic", Json::string(group.mnemonic))
        row.set("count", int_json(group.count))
        row.set("encoded_bytes", int_json(group.encoded_bytes))
        Json::object(row)
      }),
    ),
  )
  root.set(
    "instructions",
    Json::array(
      report.instructions.map(fn(instruction) {
        let row : Map[String, Json] = Map([])
        row.set("ordinal", int_json(instruction.ordinal))
        row.set("mnemonic", Json::string(instruction.mnemonic))
        row.set("file_offset", int_json(instruction.file_offset))
        row.set(
          "body_relative_offset",
          int_json(instruction.body_relative_offset),
        )
        row.set("encoded_size", int_json(instruction.encoded_size))
        Json::object(row)
      }),
    ),
  )
  Json::object(root)
}

///|
pub fn render_function_instructions_json(
  report : FunctionInstructionsReport,
) -> String {
  function_instructions_json_value(report).stringify(indent=2) + "\n"
}

///|
pub fn render_function_instructions(
  report : FunctionInstructionsReport,
  top : Int,
) -> String {
  let out = StringBuilder()
  out.write_string("FUNCTION INSTRUCTION ENCODING\n\n")
  out.write_string(
    "Input: \{report.file_size} bytes; SHA-256 \{report.sha256}\n",
  )
  out.write_string(
    "Function \{report.index}: \{report.name}; raw name: \{report.raw_name.unwrap_or("(unavailable)")}\n",
  )
  for
    (label, range) in [
      ("Entry", report.entry),
      ("Length prefix", report.prefix),
      ("Body", report.body),
      ("Locals encoding", report.locals_encoding),
    ] {
    out.write_string(
      "\{label}: file offset \{range.file_offset}, size \{range.size} B\n",
    )
  }
  out.write_string(
    "\nBYTE LEDGER\nEncoded bytes: \{report.entry.size} B = prefix \{report.prefix.size} B + body \{report.body.size} B\n",
  )
  out.write_string(
    "Body bytes: \{report.body.size} B = locals encoding \{report.locals_encoding.size} B + instructions \{report.instruction_bytes} B\n",
  )
  out.write_string(
    "Instructions: \{report.instruction_count}; grouped bytes: \{report.instruction_bytes} B\n",
  )
  let groups = top.max(0).min(report.groups.length())
  out.write_string(
    "\nOPCODE GROUPS: showing \{groups} of \{report.groups.length()} (bytes descending, count descending, mnemonic ascending)\nMNEMONIC  COUNT  ENCODED B\n",
  )
  for i in 0..<groups {
    let group = report.groups[i]
    out.write_string(
      "\{group.mnemonic}  \{group.count}  \{group.encoded_bytes}\n",
    )
  }
  let shown = top.max(0).min(report.instructions.length())
  out.write_string(
    "\nINSTRUCTIONS: showing \{shown} of \{report.instruction_count} (file order)\nORDINAL  MNEMONIC  FILE OFFSET  BODY RELATIVE OFFSET  ENCODED B\n",
  )
  for i in 0..<shown {
    let instruction = report.instructions[i]
    out.write_string(
      "\{instruction.ordinal}  \{instruction.mnemonic}  \{instruction.file_offset}  \{instruction.body_relative_offset}  \{instruction.encoded_size}\n",
    )
  }
  out.write_string("\n" + report.scope + "\n")
  out.to_string()
}
