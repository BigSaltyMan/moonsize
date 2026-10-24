///|
fn imports_range_json(range : ImportByteRange) -> Json {
  let row : Map[String, Json] = Map([])
  row.set("offset", int_json(range.offset))
  row.set("size", int_json(range.size))
  Json::object(row)
}

///|
fn imports_optional_range_json(range : ImportByteRange?) -> Json {
  match range {
    Some(r) => imports_range_json(r)
    None => Json::null()
  }
}

///|
fn imports_uint_json(value : UInt) -> Json {
  Json::number(value.to_double(), repr=value.to_string())
}

///|
fn imports_optional_uint_json(value : UInt?) -> Json {
  match value {
    Some(n) => imports_uint_json(n)
    None => Json::null()
  }
}

///|
fn imports_counts_json(counts : ImportKindCounts) -> Json {
  let row : Map[String, Json] = Map([])
  row.set("function", int_json(counts.functions))
  row.set("table", int_json(counts.tables))
  row.set("memory", int_json(counts.memories))
  row.set("global", int_json(counts.globals))
  row.set("tag", int_json(counts.tags))
  Json::object(row)
}

///|
fn imports_limits_json(limits : ImportLimits?) -> Json {
  match limits {
    None => Json::null()
    Some(limits) => {
      let row : Map[String, Json] = Map([])
      row.set("flags", int_json(limits.flags))
      row.set("minimum", imports_uint_json(limits.minimum))
      row.set("maximum", imports_optional_uint_json(limits.maximum))
      Json::object(row)
    }
  }
}

///|
pub fn render_imports_json(report : ImportsReport) -> String {
  let root : Map[String, Json] = Map([])
  root.set("format", Json::string("moonsize-imports"))
  root.set("schema_version", int_json(1))
  root.set("file_size", int_json(report.file_size))
  root.set("sha256", Json::string(report.sha256))
  root.set("supported_scope", Json::string(report.supported_scope))
  root.set("section", imports_optional_range_json(report.section))
  root.set("count_encoding", imports_optional_range_json(report.count_encoding))
  root.set("entry_count", int_json(report.entry_count))
  root.set("kind_counts", imports_counts_json(report.kind_counts))
  let s = report.ledger
  let ledger : Map[String, Json] = Map([])
  ledger.set(
    "import_section_total_bytes",
    int_json(s.import_section_total_bytes),
  )
  ledger.set("section_header_bytes", int_json(s.section_header_bytes))
  ledger.set("count_prefix_bytes", int_json(s.count_prefix_bytes))
  ledger.set("entry_bytes", int_json(s.entry_bytes))
  ledger.set(
    "module_name_encoding_bytes",
    int_json(s.module_name_encoding_bytes),
  )
  ledger.set(
    "module_length_prefix_bytes",
    int_json(s.module_length_prefix_bytes),
  )
  ledger.set("module_utf8_bytes", int_json(s.module_utf8_bytes))
  ledger.set("field_name_encoding_bytes", int_json(s.field_name_encoding_bytes))
  ledger.set("field_length_prefix_bytes", int_json(s.field_length_prefix_bytes))
  ledger.set("field_utf8_bytes", int_json(s.field_utf8_bytes))
  ledger.set("descriptor_bytes", int_json(s.descriptor_bytes))
  root.set("ledger", Json::object(ledger))
  root.set(
    "modules",
    Json::array(
      report.modules.map(fn(group) {
        let row : Map[String, Json] = Map([])
        row.set("module", Json::string(group.module_name))
        row.set("entry_count", int_json(group.entry_count))
        row.set("kind_counts", imports_counts_json(group.kind_counts))
        row.set("entry_bytes", int_json(group.entry_bytes))
        row.set("ordinals", Json::array(group.ordinals.map(int_json)))
        Json::object(row)
      }),
    ),
  )
  root.set(
    "entries",
    Json::array(
      report.entries.map(fn(entry) {
        let row : Map[String, Json] = Map([])
        row.set("ordinal", int_json(entry.ordinal))
        row.set("kind", Json::string(entry.kind))
        row.set("kind_index", int_json(entry.kind_index))
        row.set("module", Json::string(entry.module_name))
        row.set("field", Json::string(entry.field))
        row.set("encoding", imports_range_json(entry.encoding))
        row.set("module_encoding", imports_range_json(entry.module_encoding))
        row.set("field_encoding", imports_range_json(entry.field_encoding))
        row.set("descriptor", imports_range_json(entry.descriptor))
        row.set(
          "module_length_prefix_bytes",
          int_json(entry.module_length_prefix_bytes),
        )
        row.set("module_utf8_bytes", int_json(entry.module_utf8_bytes))
        row.set(
          "field_length_prefix_bytes",
          int_json(entry.field_length_prefix_bytes),
        )
        row.set("field_utf8_bytes", int_json(entry.field_utf8_bytes))
        row.set("type_index", imports_optional_uint_json(entry.type_index))
        row.set("limits", imports_limits_json(entry.limits))
        row.set("value_type", path_optional_string(entry.value_type))
        row.set("mutability", optional_index_json(entry.mutability))
        Json::object(row)
      }),
    ),
  )
  Json::object(root).stringify(indent=2) + "\n"
}

///|
fn imports_counts_text(c : ImportKindCounts) -> String {
  "function \{c.functions}, table \{c.tables}, memory \{c.memories}, global \{c.globals}, tag \{c.tags}"
}

///|
fn imports_range_text(r : ImportByteRange) -> String {
  "file offset \{r.offset}, \{r.size} B"
}

///|
pub fn render_imports(report : ImportsReport, top : Int) -> String {
  let out = StringBuilder()
  let s = report.ledger
  out.write_string("HOST IMPORT DECLARATIONS\n\n")
  out.write_string("Input: \{report.file_size} B; SHA-256 \{report.sha256}\n")
  out.write_string(
    "Declarations: \{report.entry_count}; " +
    imports_counts_text(report.kind_counts) +
    "\n",
  )
  out.write_string(
    "Import section: " +
    report.section.map(imports_range_text).unwrap_or("absent") +
    "\n",
  )
  out.write_string(
    "Import section bytes: \{s.import_section_total_bytes} B = section header \{s.section_header_bytes} B + count prefix \{s.count_prefix_bytes} B + declarations \{s.entry_bytes} B\n",
  )
  out.write_string(
    "Declaration encoding bytes: \{s.entry_bytes} B = module names \{s.module_name_encoding_bytes} B + field names \{s.field_name_encoding_bytes} B + descriptors \{s.descriptor_bytes} B\n",
  )
  out.write_string(
    "Module-name encodings: \{s.module_name_encoding_bytes} B = length prefixes \{s.module_length_prefix_bytes} B + UTF-8 \{s.module_utf8_bytes} B\n",
  )
  out.write_string(
    "Field-name encodings: \{s.field_name_encoding_bytes} B = length prefixes \{s.field_length_prefix_bytes} B + UTF-8 \{s.field_utf8_bytes} B\n",
  )
  out.write_string(
    "\nMODULE SUMMARY (all modules; section header and count not apportioned)\n",
  )
  for group in report.modules {
    out.write_string(
      Json::string(group.module_name).stringify() +
      "  \{group.entry_count} declarations  \{group.entry_bytes} B; " +
      imports_counts_text(group.kind_counts) +
      "; ordinals " +
      group.ordinals.map(fn(n) { n.to_string() }).join(", ") +
      "\n",
    )
  }
  let sorted = report.entries.copy()
  sorted.sort_by(fn(a, b) {
    let order = b.encoding.size.compare(a.encoding.size)
    if order == 0 {
      a.ordinal.compare(b.ordinal)
    } else {
      order
    }
  })
  let shown = top.max(0).min(sorted.length())
  out.write_string(
    "\nIMPORT ENTRIES: showing \{shown} of \{report.entry_count} (encoding size descending)\n",
  )
  out.write_string(
    "ORDINAL  KIND  KIND INDEX  ENCODED B  FILE OFFSET  MODULE  FIELD  TYPE INDEX\n",
  )
  for i in 0..<shown {
    let entry = sorted[i]
    out.write_string(
      "\{entry.ordinal}  \{entry.kind}  \{entry.kind_index}  \{entry.encoding.size}  \{entry.encoding.offset}  " +
      Json::string(entry.module_name).stringify() +
      "  " +
      Json::string(entry.field).stringify() +
      "  " +
      entry.type_index.map(fn(n) { n.to_string() }).unwrap_or("null") +
      "\n",
    )
    out.write_string(
      "  module name " +
      imports_range_text(entry.module_encoding) +
      "; field name " +
      imports_range_text(entry.field_encoding) +
      "; descriptor (including kind) " +
      imports_range_text(entry.descriptor) +
      "\n",
    )
    if entry.limits is Some(limits) {
      out.write_string(
        "  32-bit limits: flags \{limits.flags}, minimum \{limits.minimum}, maximum " +
        limits.maximum.map(fn(n) { n.to_string() }).unwrap_or("none") +
        "\n",
      )
    }
    if entry.value_type is Some(value_type) {
      out.write_string(
        "  declared value type: " +
        value_type +
        "; mutability " +
        entry.mutability
        .map(fn(n) { n.to_string() })
        .unwrap_or("not applicable") +
        "\n",
      )
    }
  }
  if report.entry_count == 0 {
    out.write_string("No import declarations.\n")
  }
  out.write_string(
    "\nSUPPORT AND INTERPRETATION\n" + report.supported_scope + "\n",
  )
  out.to_string()
}
