///|
pub fn render_file_offset_decoded(report : FileOffsetDecodedReport) -> String {
  let out = StringBuilder()
  out.write_string(
    render_file_offset(report.location) + "\nDECODED FUNCTION LOCATION\n",
  )
  match report.detail {
    None =>
      out.write_string(
        "Status: not_applicable. This byte is not in a local function body; no function was instruction-decoded.\n",
      )
    Some(detail) => {
      out.write_string(
        "Status: decoded\nDetail: " +
        (match detail.kind {
          LocalsEncoding => "locals_encoding"
          Instruction => "instruction"
        }) +
        "\nDetail file range: offset \{detail.file_offset}, size \{detail.size} bytes (half-open)\nDetail relative offset: \{detail.relative_offset} bytes\n",
      )
      if detail.instruction is Some(instruction) {
        out.write_string(
          "Instruction ordinal: \{instruction.ordinal}; mnemonic: " +
          search_terminal_string(instruction.mnemonic) +
          "\nBody-relative offset: \{instruction.body_relative_offset} bytes\n",
        )
      }
    }
  }
  out.write_string("\n" + report.scope + "\n")
  out.to_string()
}

///|
pub fn render_file_offset_decoded_json(
  report : FileOffsetDecodedReport,
) -> String {
  let root : Map[String, Json] = Map([])
  root.set("format", Json::string("moonsize-file-offset-decoded"))
  root.set("schema_version", int_json(1))
  root.set("location", file_offset_json_value(report.location))
  root.set(
    "decode_status",
    Json::string(
      match report.decode_status {
        NotApplicable => "not_applicable"
        Decoded => "decoded"
      },
    ),
  )
  root.set(
    "detail",
    match report.detail {
      None => Json::null()
      Some(detail) => {
        let row : Map[String, Json] = Map([])
        row.set(
          "kind",
          Json::string(
            match detail.kind {
              LocalsEncoding => "locals_encoding"
              Instruction => "instruction"
            },
          ),
        )
        row.set("file_offset", int_json(detail.file_offset))
        row.set("size", int_json(detail.size))
        row.set("relative_offset", int_json(detail.relative_offset))
        row.set(
          "instruction",
          match detail.instruction {
            None => Json::null()
            Some(instruction) => {
              let item : Map[String, Json] = Map([])
              item.set("ordinal", int_json(instruction.ordinal))
              item.set("mnemonic", Json::string(instruction.mnemonic))
              item.set("file_offset", int_json(instruction.file_offset))
              item.set(
                "body_relative_offset",
                int_json(instruction.body_relative_offset),
              )
              item.set("encoded_size", int_json(instruction.encoded_size))
              Json::object(item)
            }
          },
        )
        Json::object(row)
      }
    },
  )
  root.set("scope", Json::string(report.scope))
  Json::object(root).stringify(indent=2) + "\n"
}
