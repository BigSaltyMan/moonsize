///|
pub fn render_function_locals(
  report : FunctionLocalsReport,
  top : Int,
) -> String {
  let out = StringBuilder()
  out.write_string(
    "FUNCTION LOCAL DECLARATIONS\n\nTarget: #\{report.target.index} " +
    search_terminal_string(report.target.name) +
    " (local)\n",
  )
  out.write_string(
    "Input: \{report.file_size} B; SHA-256 \{report.sha256}\nGroups: \{report.group_count}; declared variables (excluding parameters): \{report.declared_count}\n",
  )
  out.write_string(
    "Entry: file offset \{report.entry.file_offset}, size \{report.entry.size} B\nBody: file offset \{report.body.file_offset}, size \{report.body.size} B\nLocals: file offset \{report.locals_encoding.file_offset}, size \{report.locals_encoding.size} B\nGroup count: file offset \{report.group_count_encoding.file_offset}, size \{report.group_count_encoding.size} B\nBody remainder (undecoded): file offset \{report.body_remainder.file_offset}, size \{report.body_remainder.size} B\n",
  )
  out.write_string(
    "Encoded bytes: \{report.entry.size} = prefix \{report.prefix.size} + body \{report.body.size}\nBody bytes: \{report.body.size} = locals \{report.locals_encoding.size} + undecoded remainder \{report.body_remainder.size}\nLocals bytes: \{report.locals_encoding.size} = group count \{report.group_count_encoding.size} + quantities \{report.quantity_encoding_bytes} + types \{report.type_encoding_bytes}\n",
  )
  let shown = top.max(0).min(report.groups.length())
  out.write_string(
    "\nGROUPS: showing \{shown} of \{report.group_count}\nGROUP  QUANTITY  DECLARED ORDINALS (EXCLUDING PARAMETERS)  TYPE  HEX  FILE RANGE  SIZE\n",
  )
  if report.groups.is_empty() {
    out.write_string(
      "Zero declaration groups; the group-count field is still encoded. Parameter count is not inspected.\n",
    )
  } else if report.declared_count == 0UL {
    out.write_string("Declaration groups exist, but all quantities are zero.\n")
  }
  for i in 0..<shown {
    let group = report.groups[i]
    out.write_string(
      "\{group.group_index}  \{group.quantity}  [\{group.declared_ordinal_start},\{group.declared_ordinal_end})  " +
      (match group.type_label {
        Some(label) => label
        None => "unknown"
      }) +
      "  " +
      group.type_hex +
      "  [\{group.encoding.file_offset},\{group.encoding.file_offset + group.encoding.size})  \{group.encoding.size}\n",
    )
  }
  out.write_string("\n" + report.scope + "\n")
  out.to_string()
}

///|
pub fn render_function_locals_json(report : FunctionLocalsReport) -> String {
  function_locals_json_value(report).stringify(indent=2) + "\n"
}

///|
fn function_locals_json_value(report : FunctionLocalsReport) -> Json {
  let root : Map[String, Json] = Map([])
  root.set("format", Json::string("moonsize-function-locals"))
  root.set("schema_version", int_json(1))
  root.set("file_size", int_json(report.file_size))
  root.set("sha256", Json::string(report.sha256))
  root.set("target", path_node_json(report.target))
  root.set("entry", function_instruction_range_json(report.entry))
  root.set("prefix", function_instruction_range_json(report.prefix))
  root.set("body", function_instruction_range_json(report.body))
  root.set(
    "locals_encoding",
    function_instruction_range_json(report.locals_encoding),
  )
  root.set(
    "group_count_encoding",
    function_instruction_range_json(report.group_count_encoding),
  )
  root.set(
    "body_remainder",
    function_instruction_range_json(report.body_remainder),
  )
  root.set("group_count", int_json(report.group_count))
  root.set(
    "declared_count_decimal",
    Json::string(report.declared_count.to_string()),
  )
  root.set("quantity_encoding_bytes", int_json(report.quantity_encoding_bytes))
  root.set("type_encoding_bytes", int_json(report.type_encoding_bytes))
  root.set(
    "groups",
    Json::array(
      report.groups.map(fn(group) {
        let row : Map[String, Json] = Map([])
        row.set("group_index", int_json(group.group_index))
        row.set("quantity", Json::number(group.quantity.to_double()))
        row.set(
          "declared_ordinal_start_decimal",
          Json::string(group.declared_ordinal_start.to_string()),
        )
        row.set(
          "declared_ordinal_end_decimal",
          Json::string(group.declared_ordinal_end.to_string()),
        )
        row.set("encoding", function_instruction_range_json(group.encoding))
        row.set(
          "quantity_encoding",
          function_instruction_range_json(group.quantity_encoding),
        )
        row.set(
          "type_encoding",
          function_instruction_range_json(group.type_encoding),
        )
        row.set("type_hex", Json::string(group.type_hex))
        row.set(
          "type_label",
          match group.type_label {
            Some(label) => Json::string(label)
            None => Json::null()
          },
        )
        Json::object(row)
      }),
    ),
  )
  root.set("scope", Json::string(report.scope))
  Json::object(root)
}
