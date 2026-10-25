///|
fn exports_range_json(range : ExportByteRange) -> Json {
  let row : Map[String, Json] = Map([])
  row.set("offset", int_json(range.offset))
  row.set("size", int_json(range.size))
  Json::object(row)
}

///|
fn exports_optional_range_json(range : ExportByteRange?) -> Json {
  match range {
    Some(range) => exports_range_json(range)
    None => Json::null()
  }
}

///|
pub fn render_exports_json(report : ExportsReport) -> String {
  let root : Map[String, Json] = Map([])
  root.set("format", Json::string("moonsize-exports"))
  root.set("schema_version", int_json(1))
  root.set("file_size", int_json(report.file_size))
  root.set("sha256", Json::string(report.sha256))
  root.set("section", exports_optional_range_json(report.section))
  root.set("count_encoding", exports_optional_range_json(report.count_encoding))
  let summary : Map[String, Json] = Map([])
  let s = report.summary
  summary.set("export_count", int_json(s.export_count))
  summary.set("distinct_target_count", int_json(s.distinct_target_count))
  summary.set("alias_group_count", int_json(s.alias_group_count))
  summary.set("alias_member_count", int_json(s.alias_member_count))
  summary.set("singleton_target_count", int_json(s.singleton_target_count))
  let counts : Map[String, Json] = Map([])
  for
    (kind, count) in [
      ("function", s.kind_counts.functions),
      ("table", s.kind_counts.tables),
      ("memory", s.kind_counts.memories),
      ("global", s.kind_counts.globals),
      ("tag", s.kind_counts.tags),
    ] {
    counts.set(kind, int_json(count))
  }
  summary.set("kind_counts", Json::object(counts))
  root.set("summary", Json::object(summary))
  let ledger : Map[String, Json] = Map([])
  let l = report.ledger
  for
    (key, value) in [
      ("export_section_bytes", l.export_section_bytes),
      ("section_header_bytes", l.section_header_bytes),
      ("count_prefix_bytes", l.count_prefix_bytes),
      ("declaration_bytes", l.declaration_bytes),
      ("name_encoding_bytes", l.name_encoding_bytes),
      ("name_length_prefix_bytes", l.name_length_prefix_bytes),
      ("name_utf8_bytes", l.name_utf8_bytes),
      ("descriptor_bytes", l.descriptor_bytes),
      ("kind_bytes", l.kind_bytes),
      ("target_index_prefix_bytes", l.target_index_prefix_bytes),
    ] {
    ledger.set(key, int_json(value))
  }
  root.set("ledger", Json::object(ledger))
  root.set(
    "entries",
    Json::array(
      report.entries.map(fn(entry) {
        let row : Map[String, Json] = Map([])
        row.set("ordinal", int_json(entry.ordinal))
        row.set("name", Json::string(entry.name))
        row.set("kind", Json::string(entry.kind))
        row.set("kind_code", int_json(entry.kind_code))
        row.set("target_index", metadata_uint_json(entry.target_index))
        row.set("encoding", exports_range_json(entry.encoding))
        row.set("name_encoding", exports_range_json(entry.name_encoding))
        row.set(
          "name_length_prefix_bytes",
          int_json(entry.name_length_prefix_bytes),
        )
        row.set("name_utf8_bytes", int_json(entry.name_utf8_bytes))
        row.set("descriptor", exports_range_json(entry.descriptor))
        row.set(
          "target_index_prefix_bytes",
          int_json(entry.target_index_prefix_bytes),
        )
        Json::object(row)
      }),
    ),
  )
  root.set(
    "targets",
    Json::array(
      report.targets.map(fn(target) {
        let row : Map[String, Json] = Map([])
        row.set("kind", Json::string(target.kind))
        row.set("kind_code", int_json(target.kind_code))
        row.set("target_index", metadata_uint_json(target.target_index))
        row.set(
          "entry_ordinals",
          Json::array(target.entry_ordinals.map(int_json)),
        )
        row.set("member_count", int_json(target.member_count))
        row.set("declaration_bytes", int_json(target.declaration_bytes))
        row.set("is_alias", Json::boolean(target.is_alias))
        Json::object(row)
      }),
    ),
  )
  root.set("supported_scope", Json::string(report.supported_scope))
  Json::object(root).stringify(indent=2) + "\n"
}

///|
pub fn render_exports(report : ExportsReport, top : Int) -> String {
  let out = StringBuilder()
  let s = report.summary
  let c = s.kind_counts
  let l = report.ledger
  out.write_string(
    "EXPORT DECLARATIONS\n\nInput: \{report.file_size} B; SHA-256 \{report.sha256}\n",
  )
  out.write_string(
    "Kinds: function \{c.functions}; table \{c.tables}; memory \{c.memories}; global \{c.globals}; tag \{c.tags}\n",
  )
  out.write_string(
    "Declarations: \{s.export_count}; distinct declared targets: \{s.distinct_target_count}\nAlias groups: \{s.alias_group_count}; alias members: \{s.alias_member_count}; singleton targets: \{s.singleton_target_count}\n",
  )
  if report.section is None {
    out.write_string("No export section.\n")
  } else if s.export_count == 0 {
    out.write_string("Export section has zero declarations.\n")
  }
  out.write_string(
    "\nENCODING LEDGER\nExport section: \{l.export_section_bytes} B = headers \{l.section_header_bytes} B + count \{l.count_prefix_bytes} B + declarations \{l.declaration_bytes} B\n",
  )
  out.write_string(
    "Declarations: \{l.declaration_bytes} B = name encodings \{l.name_encoding_bytes} B + descriptors \{l.descriptor_bytes} B\nName encodings: \{l.name_encoding_bytes} B = length prefixes \{l.name_length_prefix_bytes} B + UTF-8 \{l.name_utf8_bytes} B\nDescriptors: \{l.descriptor_bytes} B = kind \{l.kind_bytes} B + index prefixes \{l.target_index_prefix_bytes} B\n",
  )
  let entries = report.entries.copy()
  entries.sort_by(fn(a, b) {
    let order = b.encoding.size.compare(a.encoding.size)
    if order != 0 {
      order
    } else {
      a.ordinal.compare(b.ordinal)
    }
  })
  let shown = top.max(0).min(entries.length())
  out.write_string(
    "\nDECLARATIONS: showing \{shown} of \{entries.length()} (encoded size descending)\nORDINAL  KIND  TARGET INDEX  ENCODED B  FILE OFFSET  NAME\n",
  )
  for i in 0..<shown {
    let e = entries[i]
    out.write_string(
      "\{e.ordinal}  \{e.kind}  \{e.target_index}  \{e.encoding.size}  \{e.encoding.offset}  " +
      Json::string(e.name).stringify() +
      "\n",
    )
  }
  let aliases = report.targets.filter(fn(target) { target.is_alias })
  aliases.sort_by(fn(a, b) {
    let count_order = b.member_count.compare(a.member_count)
    if count_order != 0 {
      return count_order
    }
    let kind_order = a.kind_code.compare(b.kind_code)
    if kind_order != 0 {
      kind_order
    } else {
      a.target_index.compare(b.target_index)
    }
  })
  let aliases_shown = top.max(0).min(aliases.length())
  out.write_string(
    "\nALIAS GROUPS: showing \{aliases_shown} of \{aliases.length()}\nKIND  TARGET INDEX  MEMBERS  DECLARATION B\n",
  )
  for i in 0..<aliases_shown {
    let group = aliases[i]
    out.write_string(
      "\{group.kind}  \{group.target_index}  \{group.member_count}  \{group.declaration_bytes}\n",
    )
    let names_shown = group.member_count.min(20)
    out.write_string(
      "  Names: showing \{names_shown} of \{group.member_count}\n",
    )
    for j in 0..<names_shown {
      let ordinal = group.entry_ordinals[j]
      out.write_string(
        "  ordinal \{ordinal}: " +
        Json::string(report.entries[ordinal].name).stringify() +
        "\n",
      )
    }
  }
  out.write_string(
    "\nSCOPE\n" +
    report.supported_scope +
    "\nUse --entrypoints for model reachability; use function target indices with --instructions or --callers only after checking their validity and local-body requirements.\n",
  )
  out.to_string()
}
