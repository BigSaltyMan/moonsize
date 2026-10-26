///|
fn function_call_kind_text(kind : FunctionCallKind) -> String {
  match kind {
    DirectCall => "direct"
    IndirectCall => "indirect"
    ReferenceCall => "reference_call"
  }
}

///|
pub fn render_function_calls(report : FunctionCallsReport, top : Int) -> String {
  let out = StringBuilder()
  out.write_string(
    "FUNCTION CALL SITES\n\nCaller: #\{report.caller.index} " +
    search_terminal_string(report.caller.name) +
    " (local)\nInput: \{report.file_size} B; SHA-256 \{report.sha256}\n",
  )
  out.write_string(
    "Entry: file offset \{report.entry.file_offset}, size \{report.entry.size} B\nBody: file offset \{report.body.file_offset}, size \{report.body.size} B\n",
  )
  out.write_string(
    "Encoded bytes: \{report.entry.size} B = prefix \{report.prefix.size} B + body \{report.body.size} B\nBody bytes: \{report.body.size} B = locals \{report.locals_encoding.size} B + instructions \{report.instruction_bytes} B\n",
  )
  out.write_string(
    "Instructions: \{report.instruction_count}\nCalls: \{report.call_count} = direct \{report.direct_count} + indirect \{report.indirect_count} + reference_call \{report.reference_call_count}\nTail calls: \{report.tail_count} (subset)\nInstruction bytes: \{report.instruction_bytes} B = call encodings \{report.call_encoding_bytes} B + other instructions \{report.other_instruction_bytes} B\n",
  )
  let shown = top.max(0).min(report.calls.length())
  out.write_string(
    "\nCALLS: showing \{shown} of \{report.call_count}\nORDINAL  OPCODE  KIND  TAIL  FILE OFFSET  BODY OFFSET  SIZE  TARGET  TYPE  TABLE\n",
  )
  if report.calls.is_empty() {
    out.write_string("No call instructions in this local function.\n")
  }
  for i in 0..<shown {
    let call = report.calls[i]
    let target = match call.target {
      None => "unknown"
      Some(node) =>
        "#\{node.index} " +
        search_terminal_string(node.name) +
        (if node.imported {
          " (import " +
          search_terminal_string(node.import_module.unwrap()) +
          "." +
          search_terminal_string(node.import_name.unwrap()) +
          ")"
        } else {
          " (local)"
        })
    }
    out.write_string(
      "\{call.instruction_ordinal}  " +
      call.opcode.name() +
      "  " +
      function_call_kind_text(call.kind) +
      "  " +
      (if call.is_tail { "yes" } else { "no" }) +
      "  \{call.file_offset}  \{call.body_relative_offset}  \{call.encoded_size}  " +
      target +
      "  " +
      (match call.type_index {
        Some(index) => index.to_string()
        None => "n/a"
      }) +
      "  " +
      (match call.table_index {
        Some(index) => index.to_string()
        None => "n/a"
      }) +
      "\n",
    )
  }
  out.write_string("\n" + report.scope + "\n")
  out.to_string()
}

///|
pub fn render_function_calls_json(report : FunctionCallsReport) -> String {
  let root : Map[String, Json] = Map([])
  root.set("format", Json::string("moonsize-function-calls"))
  root.set("schema_version", int_json(1))
  root.set("file_size", int_json(report.file_size))
  root.set("sha256", Json::string(report.sha256))
  root.set("caller", path_node_json(report.caller))
  root.set("entry", function_instruction_range_json(report.entry))
  root.set("prefix", function_instruction_range_json(report.prefix))
  root.set("body", function_instruction_range_json(report.body))
  root.set(
    "locals_encoding",
    function_instruction_range_json(report.locals_encoding),
  )
  root.set("instruction_count", int_json(report.instruction_count))
  root.set("instruction_bytes", int_json(report.instruction_bytes))
  root.set("call_count", int_json(report.call_count))
  root.set("direct_count", int_json(report.direct_count))
  root.set("indirect_count", int_json(report.indirect_count))
  root.set("reference_call_count", int_json(report.reference_call_count))
  root.set("tail_count", int_json(report.tail_count))
  root.set("call_encoding_bytes", int_json(report.call_encoding_bytes))
  root.set("other_instruction_bytes", int_json(report.other_instruction_bytes))
  root.set(
    "calls",
    Json::array(
      report.calls.map(fn(call) {
        let row : Map[String, Json] = Map([])
        row.set("instruction_ordinal", int_json(call.instruction_ordinal))
        row.set("opcode", Json::string(call.opcode.name()))
        row.set("kind", Json::string(function_call_kind_text(call.kind)))
        row.set("is_tail", Json::boolean(call.is_tail))
        row.set("file_offset", int_json(call.file_offset))
        row.set("body_relative_offset", int_json(call.body_relative_offset))
        row.set("encoded_size", int_json(call.encoded_size))
        row.set("target_index", optional_index_json(call.target_index))
        row.set("type_index", optional_index_json(call.type_index))
        row.set("table_index", optional_index_json(call.table_index))
        row.set(
          "target",
          match call.target {
            Some(node) => path_node_json(node)
            None => Json::null()
          },
        )
        Json::object(row)
      }),
    ),
  )
  root.set("scope", Json::string(report.scope))
  Json::object(root).stringify(indent=2) + "\n"
}
