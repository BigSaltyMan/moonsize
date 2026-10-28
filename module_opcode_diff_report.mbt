///|
pub fn render_module_opcode_comparison_json(
  report : ModuleOpcodeComparison,
) -> String {
  let root : Map[String, Json] = Map([])
  root.set("format", Json::string("moonsize-module-opcodes-diff"))
  root.set("schema_version", int_json(1))
  root.set("baseline", module_opcodes_json_value(report.baseline))
  root.set("current", module_opcodes_json_value(report.current))
  root.set("scope", Json::string(report.scope))
  let d = report.delta
  let delta : Map[String, Json] = Map([])
  delta.set("file_bytes", int_json(d.file_bytes))
  delta.set("code_bytes", int_json(d.code_bytes))
  delta.set("non_code_bytes", int_json(d.non_code_bytes))
  delta.set("code_header_bytes", int_json(d.code_header_bytes))
  delta.set("count_encoding_bytes", int_json(d.count_encoding_bytes))
  delta.set("body_prefix_bytes", int_json(d.body_prefix_bytes))
  delta.set("locals_encoding_bytes", int_json(d.locals_encoding_bytes))
  delta.set("instruction_bytes", int_json(d.instruction_bytes))
  delta.set("instruction_count", int_json(d.instruction_count))
  delta.set("imported_function_count", int_json(d.imported_function_count))
  delta.set("local_function_count", int_json(d.local_function_count))
  root.set("delta", Json::object(delta))
  root.set(
    "opcodes",
    Json::array(
      report.opcodes.map(fn(row) {
        let item : Map[String, Json] = Map([])
        item.set("mnemonic", Json::string(row.mnemonic))
        item.set("status", Json::string(row.status))
        item.set("baseline_count", int_json(row.baseline_count))
        item.set("current_count", int_json(row.current_count))
        item.set("count_delta", int_json(row.count_delta))
        item.set("baseline_encoded_bytes", int_json(row.baseline_encoded_bytes))
        item.set("current_encoded_bytes", int_json(row.current_encoded_bytes))
        item.set("encoded_bytes_delta", int_json(row.encoded_bytes_delta))
        item.set(
          "baseline_function_count",
          int_json(row.baseline_function_count),
        )
        item.set("current_function_count", int_json(row.current_function_count))
        item.set("function_count_delta", int_json(row.function_count_delta))
        Json::object(item)
      }),
    ),
  )
  Json::object(root).stringify(indent=2) + "\n"
}

///|
pub fn render_module_opcode_comparison(
  report : ModuleOpcodeComparison,
  top : Int,
) -> String {
  let out = StringBuilder()
  out.write_string("MODULE FUNCTION OPCODE COMPARISON\n\n")
  for (side, r) in [("Baseline", report.baseline), ("Current", report.current)] {
    out.write_string(
      "\{side}: \{r.file_size} B; SHA-256 \{r.sha256}\nImported functions: \{r.imported_function_count}; local functions: \{r.local_function_count}\n",
    )
    if r.code_section is None {
      out.write_string("No code section; code/count ranges are absent.\n")
    }
  }
  let b = report.baseline
  let c = report.current
  let d = report.delta
  out.write_string(
    "\nBYTE AND COUNT LEDGER (delta = current - baseline)\nMETRIC  BASELINE  CURRENT  DELTA\n",
  )
  for
    (label, before, after, change) in [
      ("file_bytes", b.file_size, c.file_size, d.file_bytes),
      (
        "code_bytes",
        module_opcode_code_bytes(b),
        module_opcode_code_bytes(c),
        d.code_bytes,
      ),
      (
        "non_code_bytes",
        b.file_size - module_opcode_code_bytes(b),
        c.file_size - module_opcode_code_bytes(c),
        d.non_code_bytes,
      ),
      (
        "code_header_bytes",
        b.code_header_bytes,
        c.code_header_bytes,
        d.code_header_bytes,
      ),
      (
        "count_encoding_bytes",
        b.count_encoding_bytes,
        c.count_encoding_bytes,
        d.count_encoding_bytes,
      ),
      (
        "body_prefix_bytes",
        b.body_prefix_bytes,
        c.body_prefix_bytes,
        d.body_prefix_bytes,
      ),
      (
        "locals_encoding_bytes",
        b.locals_encoding_bytes,
        c.locals_encoding_bytes,
        d.locals_encoding_bytes,
      ),
      (
        "instruction_bytes",
        b.instruction_bytes,
        c.instruction_bytes,
        d.instruction_bytes,
      ),
      (
        "instruction_count",
        b.instruction_count,
        c.instruction_count,
        d.instruction_count,
      ),
      (
        "imported_function_count",
        b.imported_function_count,
        c.imported_function_count,
        d.imported_function_count,
      ),
      (
        "local_function_count",
        b.local_function_count,
        c.local_function_count,
        d.local_function_count,
      ),
    ] {
    out.write_string("\{label}  \{before}  \{after}  \{change}\n")
  }
  out.write_string(
    "File delta: \{d.file_bytes} = code \{d.code_bytes} + non-code \{d.non_code_bytes}\n",
  )
  out.write_string(
    "Code delta: \{d.code_bytes} = header \{d.code_header_bytes} + count encoding \{d.count_encoding_bytes} + body prefixes \{d.body_prefix_bytes} + locals \{d.locals_encoding_bytes} + instructions \{d.instruction_bytes}\n",
  )
  let shown = top.max(0).min(report.opcodes.length())
  out.write_string(
    "\nOPCODE COMPOSITION: showing \{shown} of \{report.opcodes.length()}\nMNEMONIC  STATUS  BEFORE COUNT  AFTER COUNT  COUNT DELTA  BEFORE B  AFTER B  BYTE DELTA  BEFORE FUNCTIONS  AFTER FUNCTIONS  FUNCTION DELTA\n",
  )
  for i in 0..<shown {
    let r = report.opcodes[i]
    out.write_string(
      "\{r.mnemonic}  \{r.status}  \{r.baseline_count}  \{r.current_count}  \{r.count_delta}  \{r.baseline_encoded_bytes}  \{r.current_encoded_bytes}  \{r.encoded_bytes_delta}  \{r.baseline_function_count}  \{r.current_function_count}  \{r.function_count_delta}\n",
    )
  }
  out.write_string("\n" + report.scope + "\n")
  out.to_string()
}
