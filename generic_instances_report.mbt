///|
/// Independent format; all families and instances survive text Top limits.
pub fn render_generic_instances_json(report : GenericInstancesReport) -> String {
  let root : Map[String, Json] = Map([])
  root.set("format", Json::string("moonsize-generic-instances"))
  root.set("schema_version", int_json(1))
  root.set("file_size", int_json(report.file_size))
  root.set("sha256", Json::string(report.sha256))
  root.set("name_status", Json::string(report.name_status))
  root.set("recognition_scope", Json::string(report.recognition_scope))
  let c = report.coverage
  let coverage : Map[String, Json] = Map([])
  coverage.set("total_functions", int_json(c.total_functions))
  coverage.set("total_size", int_json(c.total_size))
  coverage.set("grouped_functions", int_json(c.grouped_functions))
  coverage.set("grouped_size", int_json(c.grouped_size))
  coverage.set(
    "named_ungrouped_functions",
    int_json(c.named_ungrouped_functions),
  )
  coverage.set("named_ungrouped_size", int_json(c.named_ungrouped_size))
  coverage.set("unnamed_functions", int_json(c.unnamed_functions))
  coverage.set("unnamed_size", int_json(c.unnamed_size))
  root.set("coverage", Json::object(coverage))
  root.set(
    "families",
    Json::array(
      report.families.map(fn(family) {
        let row : Map[String, Json] = Map([])
        row.set("family_key", Json::string(family.family_key))
        row.set("display_name", Json::string(family.display_name))
        row.set("definition_count", int_json(family.definition_count))
        row.set("type_encoding_count", int_json(family.type_encoding_count))
        row.set("total_size", int_json(family.total_size))
        row.set(
          "instances",
          Json::array(
            family.instances.map(fn(instance) {
              let item : Map[String, Json] = Map([])
              item.set("index", int_json(instance.index))
              item.set("raw_name", Json::string(instance.raw_name))
              item.set(
                "raw_type_arguments",
                Json::string(instance.raw_type_arguments),
              )
              item.set(
                "type_labels",
                Json::array(instance.type_labels.map(Json::string)),
              )
              item.set("total_size", int_json(instance.total_size))
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
pub fn render_generic_instances(
  report : GenericInstancesReport,
  top : Int,
) -> String {
  let out = StringBuilder()
  let shown = top.max(0).min(report.families.length())
  let c = report.coverage
  out.write_string("MOONBIT GENERIC INSTANCES\n\n")
  out.write_string(
    "Input: \{report.file_size} bytes; SHA-256 \{report.sha256}\n",
  )
  out.write_string("Name information: \{report.name_status}\n")
  if report.name_status == "unreadable" {
    out.write_string(
      "Name information could not be read completely; no names are trusted for grouping.\n",
    )
  } else if report.name_status == "missing" {
    out.write_string(
      "No name section is present; grouping requires usable raw symbols.\n",
    )
  }
  out.write_string(
    "\nCOVERAGE LEDGER (local function definitions / encoded bytes)\n",
  )
  out.write_string("All: \{c.total_functions} / \{c.total_size} B\n")
  out.write_string(
    "Grouped generic: \{c.grouped_functions} / \{c.grouped_size} B\n",
  )
  out.write_string(
    "Named, ungrouped: \{c.named_ungrouped_functions} / \{c.named_ungrouped_size} B\n",
  )
  out.write_string(
    "Without usable names: \{c.unnamed_functions} / \{c.unnamed_size} B\n",
  )
  out.write_string(
    "All = grouped generic + named ungrouped + without usable names.\n",
  )
  out.write_string(
    "\nShowing \{shown} of \{report.families.length()} families; Top limits text only.\n",
  )
  if report.families.is_empty() {
    out.write_string(
      "No instances recognized within the supported encoding scope; this does not establish that the project has no generics.\n",
    )
  }
  for i in 0..<shown {
    let family = report.families[i]
    out.write_string(
      "\nFamily: " + Json::string(family.display_name).stringify() + "\n",
    )
    out.write_string(
      "Raw family key: " + Json::string(family.family_key).stringify() + "\n",
    )
    out.write_string(
      "Definitions: \{family.definition_count}; distinct type encodings: \{family.type_encoding_count}; encoded bytes: \{family.total_size} B\n",
    )
    out.write_string(
      "INDEX  ENCODED B  RAW TYPE ARGUMENTS  TYPE LABELS  RAW SYMBOL\n",
    )
    for instance in family.instances {
      out.write_string(
        "\{instance.index}  \{instance.total_size}  " +
        Json::string(instance.raw_type_arguments).stringify() +
        "  " +
        instance.type_labels.join(", ") +
        "  " +
        Json::string(instance.raw_name).stringify() +
        "\n",
      )
    }
  }
  out.write_string("\n" + report.recognition_scope + "\n")
  out.to_string()
}
