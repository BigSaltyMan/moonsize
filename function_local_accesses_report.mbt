///|
pub fn render_function_local_accesses(
  report : FunctionLocalAccessesReport,
  top : Int,
) -> String {
  let out = StringBuilder()
  out.write_string(
    "FUNCTION LOCAL ACCESS ENCODINGS\n\nTarget: #\{report.target.index} " +
    search_terminal_string(report.target.name) +
    " (local)\nInput: \{report.file_size} B; SHA-256 \{report.sha256}\n",
  )
  for
    (label, range) in [
      ("Entry", report.entry),
      ("Prefix", report.prefix),
      ("Body", report.body),
      ("Locals encoding", report.locals_encoding),
    ] {
    out.write_string(
      "\{label}: file offset \{range.file_offset}, size \{range.size} B\n",
    )
  }
  out.write_string(
    "Encoded bytes: \{report.entry.size} = prefix \{report.prefix.size} + body \{report.body.size}\nBody bytes: \{report.body.size} = locals \{report.locals_encoding.size} + instructions \{report.instruction_bytes}\n",
  )
  out.write_string(
    "Instructions: \{report.instruction_count}\nAccesses: \{report.access_count} = get \{report.get_count} + set \{report.set_count} + tee \{report.tee_count}\nDistinct local indices: \{report.distinct_local_index_count}\nInstruction bytes: \{report.instruction_bytes} = access encodings \{report.access_encoding_bytes} + other instructions \{report.other_instruction_bytes}\nAccess encoding bytes: \{report.access_encoding_bytes} = opcode bytes \{report.access_count} + index encoding bytes \{report.index_encoding_bytes}\n",
  )
  let group_shown = top.max(0).min(report.groups.length())
  out.write_string(
    "\nGROUPS: showing \{group_shown} of \{report.groups.length()} (numeric local index order)\nLOCAL INDEX  ACCESS  GET  SET  TEE  ENCODED B  INDEX B  INSTRUCTION ORDINALS\n",
  )
  if report.accesses.is_empty() {
    out.write_string(
      "No local.get/local.set/local.tee access instructions in this local function. This does not imply no variables.\n",
    )
  }
  for i in 0..<group_shown {
    let group = report.groups[i]
    out.write_string(
      "\{group.local_index}  \{group.access_count}  \{group.get_count}  \{group.set_count}  \{group.tee_count}  \{group.encoded_bytes}  \{group.index_encoding_bytes}  " +
      Json::array(group.instruction_ordinals.map(int_json)).stringify() +
      "\n",
    )
  }
  let shown = top.max(0).min(report.accesses.length())
  out.write_string(
    "\nACCESS SITES: showing \{shown} of \{report.access_count} (file order)\nORDINAL  OPCODE  LOCAL INDEX  FILE OFFSET  BODY OFFSET  SIZE  INDEX FILE RANGE  INDEX B\n",
  )
  for i in 0..<shown {
    let access = report.accesses[i]
    let span = access.index_encoding
    out.write_string(
      "\{access.instruction_ordinal}  " +
      access.opcode.name() +
      "  \{access.local_index}  \{access.file_offset}  \{access.body_relative_offset}  \{access.encoded_size}  [\{span.file_offset},\{span.file_offset + span.size})  \{span.size}\n",
    )
  }
  out.write_string("\n" + report.scope + "\n")
  out.to_string()
}

///|
pub fn render_function_local_accesses_json(
  report : FunctionLocalAccessesReport,
) -> String {
  let root : Map[String, Json] = Map([])
  root.set("format", Json::string("moonsize-function-local-accesses"))
  root.set("schema_version", int_json(1))
  root.set("file_size", int_json(report.file_size))
  root.set("sha256", Json::string(report.sha256))
  root.set("target", path_node_json(report.target))
  for
    (label, range) in [
      ("entry", report.entry),
      ("prefix", report.prefix),
      ("body", report.body),
      ("locals_encoding", report.locals_encoding),
    ] {
    root.set(label, function_instruction_range_json(range))
  }
  for
    (label, count) in [
      ("instruction_count", report.instruction_count),
      ("instruction_bytes", report.instruction_bytes),
      ("access_count", report.access_count),
      ("get_count", report.get_count),
      ("set_count", report.set_count),
      ("tee_count", report.tee_count),
      ("distinct_local_index_count", report.distinct_local_index_count),
      ("access_encoding_bytes", report.access_encoding_bytes),
      ("index_encoding_bytes", report.index_encoding_bytes),
      ("other_instruction_bytes", report.other_instruction_bytes),
    ] {
    root.set(label, int_json(count))
  }
  root.set(
    "accesses",
    Json::array(
      report.accesses.map(fn(access) {
        let row : Map[String, Json] = Map([])
        row.set("instruction_ordinal", int_json(access.instruction_ordinal))
        row.set("opcode", Json::string(access.opcode.name()))
        row.set("local_index", int_json(access.local_index))
        row.set("file_offset", int_json(access.file_offset))
        row.set("body_relative_offset", int_json(access.body_relative_offset))
        row.set("encoded_size", int_json(access.encoded_size))
        row.set(
          "index_encoding",
          function_instruction_range_json(access.index_encoding),
        )
        Json::object(row)
      }),
    ),
  )
  root.set(
    "groups",
    Json::array(
      report.groups.map(fn(group) {
        let row : Map[String, Json] = Map([])
        row.set("local_index", int_json(group.local_index))
        row.set("access_count", int_json(group.access_count))
        row.set("get_count", int_json(group.get_count))
        row.set("set_count", int_json(group.set_count))
        row.set("tee_count", int_json(group.tee_count))
        row.set("encoded_bytes", int_json(group.encoded_bytes))
        row.set("index_encoding_bytes", int_json(group.index_encoding_bytes))
        row.set(
          "instruction_ordinals",
          Json::array(group.instruction_ordinals.map(int_json)),
        )
        Json::object(row)
      }),
    ),
  )
  root.set("scope", Json::string(report.scope))
  Json::object(root).stringify(indent=2) + "\n"
}
