///|
pub fn render_function_instructions_diff_json(
  report : FunctionInstructionsComparison,
) -> String {
  let root : Map[String, Json] = Map([])
  root.set("format", Json::string("moonsize-function-instructions-diff"))
  root.set("schema_version", int_json(1))
  root.set("baseline", function_instructions_json_value(report.baseline))
  root.set("current", function_instructions_json_value(report.current))
  root.set("scope", Json::string(report.scope))
  let d = report.delta
  let delta : Map[String, Json] = Map([])
  delta.set("entry_bytes", int_json(d.entry_bytes))
  delta.set("prefix_bytes", int_json(d.prefix_bytes))
  delta.set("body_bytes", int_json(d.body_bytes))
  delta.set("locals_bytes", int_json(d.locals_bytes))
  delta.set("instruction_bytes", int_json(d.instruction_bytes))
  delta.set("instruction_count", int_json(d.instruction_count))
  root.set("delta", Json::object(delta))
  root.set(
    "opcodes",
    Json::array(
      report.opcodes.map(fn(row) {
        let item : Map[String, Json] = Map([])
        item.set("mnemonic", Json::string(row.mnemonic))
        item.set("baseline_count", int_json(row.baseline_count))
        item.set("current_count", int_json(row.current_count))
        item.set("count_delta", int_json(row.count_delta))
        item.set("baseline_encoded_bytes", int_json(row.baseline_encoded_bytes))
        item.set("current_encoded_bytes", int_json(row.current_encoded_bytes))
        item.set("encoded_bytes_delta", int_json(row.encoded_bytes_delta))
        Json::object(item)
      }),
    ),
  )
  Json::object(root).stringify(indent=2) + "\n"
}

///|
pub fn render_function_instructions_diff(
  report : FunctionInstructionsComparison,
  top : Int,
) -> String {
  let out = StringBuilder()
  out.write_string("FUNCTION INSTRUCTION COMPOSITION COMPARISON\n\n")
  out.write_string(
    "Explicit user-selected targets; no automatic function matching.\n",
  )
  for
    (side, target) in [
      ("Baseline", report.baseline),
      ("Current", report.current),
    ] {
    out.write_string(
      "\n\{side}: \{target.file_size} B; SHA-256 \{target.sha256}; function \{target.index}\n",
    )
    out.write_string(
      "  name: " +
      search_terminal_string(target.name) +
      "; raw_name: " +
      path_optional_string(target.raw_name).stringify() +
      "\n",
    )
    for
      (label, range) in [
        ("entry", target.entry),
        ("body", target.body),
        ("prefix", target.prefix),
        ("locals", target.locals_encoding),
      ] {
      out.write_string(
        "  \{label}: file offset \{range.file_offset}, size \{range.size} B\n",
      )
    }
    out.write_string(
      "  Encoded bytes: \{target.entry.size} B = prefix \{target.prefix.size} B + body \{target.body.size} B\n",
    )
    out.write_string(
      "  Body bytes: \{target.body.size} B = locals \{target.locals_encoding.size} B + instructions \{target.instruction_bytes} B; count \{target.instruction_count}\n",
    )
  }
  let b = report.baseline
  let c = report.current
  let d = report.delta
  out.write_string(
    "\nBYTE AND COUNT LEDGER (delta = current - baseline)\nMETRIC  BASELINE  CURRENT  DELTA\n",
  )
  for
    (label, before, after, change) in [
      ("Entry bytes", b.entry.size, c.entry.size, d.entry_bytes),
      ("Prefix bytes", b.prefix.size, c.prefix.size, d.prefix_bytes),
      ("Body bytes", b.body.size, c.body.size, d.body_bytes),
      (
        "Locals bytes",
        b.locals_encoding.size,
        c.locals_encoding.size,
        d.locals_bytes,
      ),
      (
        "Instruction bytes",
        b.instruction_bytes,
        c.instruction_bytes,
        d.instruction_bytes,
      ),
      (
        "Instruction count",
        b.instruction_count,
        c.instruction_count,
        d.instruction_count,
      ),
    ] {
    out.write_string("\{label}  \{before}  \{after}  \{change}\n")
  }
  out.write_string(
    "Entry delta: \{d.entry_bytes} B = prefix \{d.prefix_bytes} B + body \{d.body_bytes} B\n",
  )
  out.write_string(
    "Body delta: \{d.body_bytes} B = locals \{d.locals_bytes} B + instructions \{d.instruction_bytes} B\n",
  )
  let shown = top.max(0).min(report.opcodes.length())
  out.write_string(
    "\nOPCODE COMPOSITION: showing \{shown} of \{report.opcodes.length()} (absolute byte delta descending, absolute count delta descending, mnemonic ascending)\nMNEMONIC  BEFORE COUNT  AFTER COUNT  COUNT DELTA  BEFORE B  AFTER B  BYTE DELTA\n",
  )
  for i in 0..<shown {
    let row = report.opcodes[i]
    out.write_string(
      "\{row.mnemonic}  \{row.baseline_count}  \{row.current_count}  \{row.count_delta}  \{row.baseline_encoded_bytes}  \{row.current_encoded_bytes}  \{row.encoded_bytes_delta}\n",
    )
  }
  out.write_string("\n" + report.scope + "\n")
  out.to_string()
}
