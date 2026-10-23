///|
pub fn render_duplicate_functions_json(
  report : DuplicateFunctionsReport,
) -> String {
  let root : Map[String, Json] = Map([])
  root.set("format", Json::string("moonsize-duplicate-function-bodies"))
  root.set("schema_version", int_json(1))
  root.set("file_size", int_json(report.file_size))
  root.set("sha256", Json::string(report.sha256))
  root.set("comparison_scope", Json::string(report.comparison_scope))
  let s = report.summary
  let summary : Map[String, Json] = Map([])
  summary.set("local_function_count", int_json(s.local_function_count))
  summary.set("duplicate_group_count", int_json(s.duplicate_group_count))
  summary.set("duplicate_member_count", int_json(s.duplicate_member_count))
  summary.set("singleton_function_count", int_json(s.singleton_function_count))
  summary.set("total_body_bytes", int_json(s.total_body_bytes))
  summary.set("duplicate_body_bytes", int_json(s.duplicate_body_bytes))
  summary.set("singleton_body_bytes", int_json(s.singleton_body_bytes))
  summary.set("total_prefix_bytes", int_json(s.total_prefix_bytes))
  summary.set("total_encoded_bytes", int_json(s.total_encoded_bytes))
  root.set("summary", Json::object(summary))
  root.set(
    "groups",
    Json::array(
      report.groups.map(fn(group) {
        let row : Map[String, Json] = Map([])
        row.set("sha256", Json::string(group.sha256))
        row.set("body_size", int_json(group.body_size))
        row.set("member_count", int_json(group.member_count))
        row.set("member_body_bytes", int_json(group.member_body_bytes))
        row.set("member_prefix_bytes", int_json(group.member_prefix_bytes))
        row.set("member_total_bytes", int_json(group.member_total_bytes))
        row.set(
          "members",
          Json::array(
            group.members.map(fn(definition) {
              let item : Map[String, Json] = Map([])
              item.set("index", int_json(definition.index))
              item.set("name", Json::string(definition.name))
              item.set("raw_name", path_optional_string(definition.raw_name))
              item.set("type_index", int_json(definition.type_index))
              item.set("offset", int_json(definition.offset))
              item.set("body_offset", int_json(definition.body_offset))
              item.set("body_size", int_json(definition.body_size))
              item.set("prefix_size", int_json(definition.prefix_size))
              item.set("total_size", int_json(definition.total_size))
              Json::object(item)
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
pub fn render_duplicate_functions(
  report : DuplicateFunctionsReport,
  top : Int,
) -> String {
  let out = StringBuilder()
  out.write_string(
    "IDENTICAL FUNCTION BODIES\n\n" + report.comparison_scope + "\n",
  )
  out.write_string(
    "Input: \{report.file_size} bytes; SHA-256 \{report.sha256}\n",
  )
  let s = report.summary
  out.write_string("\nLOCAL FUNCTION BYTE LEDGER\n")
  out.write_string(
    "Local definitions: \{s.local_function_count} = duplicate-group members \{s.duplicate_member_count} + singletons \{s.singleton_function_count}\n",
  )
  out.write_string("Duplicate groups: \{s.duplicate_group_count}\n")
  out.write_string(
    "Body bytes: \{s.total_body_bytes} B = duplicate-group members \{s.duplicate_body_bytes} B + singletons \{s.singleton_body_bytes} B\n",
  )
  out.write_string(
    "Encoded bytes: \{s.total_encoded_bytes} B = body \{s.total_body_bytes} B + length prefixes \{s.total_prefix_bytes} B\n",
  )
  let shown = top.max(0).min(report.groups.length())
  out.write_string(
    "\nShowing \{shown} of \{report.groups.length()} duplicate groups; Top limits text only.\n",
  )
  if report.groups.is_empty() {
    out.write_string("No identical function bodies found.\n")
  }
  for i in 0..<shown {
    let g = report.groups[i]
    out.write_string("\nGroup SHA-256: " + g.sha256 + "\n")
    out.write_string(
      "Body length: \{g.body_size} B; members: \{g.member_count}; definition body bytes: \{g.member_body_bytes} B\n",
    )
    out.write_string(
      "Member encoded bytes: \{g.member_total_bytes} B = body \{g.member_body_bytes} B + prefixes \{g.member_prefix_bytes} B\n",
    )
    out.write_string(
      "INDEX  TYPE INDEX  PREFIX B  TOTAL B  ENTRY FILE OFFSET  BODY FILE OFFSET  BODY B  NAME  RAW NAME\n",
    )
    for definition in g.members {
      out.write_string(
        "\{definition.index}  \{definition.type_index}  \{definition.prefix_size}  \{definition.total_size}  \{definition.offset}  \{definition.body_offset}  \{definition.body_size}  " +
        Json::string(definition.name).stringify() +
        "  " +
        path_optional_string(definition.raw_name).stringify() +
        "\n",
      )
    }
  }
  out.to_string()
}
