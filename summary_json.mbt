///|
/// Existing diagnostic fields and provenance, plus readable reasons in this new
/// format. Sorting and record encoding are shared with the graph reports.
fn summary_diagnostics(graph : CallGraph) -> Json {
  let ordered = sorted_diagnostics(graph)
  let value = diagnostic_records_json(ordered)
  if value is Array(rows) {
    for i, row in rows {
      if row is Object(fields) {
        fields.set("reason", Json::string(diagnostic_details(ordered[i])))
      }
    }
  }
  value
}

///|
/// Render only existing analysis results. No parsing, inspectors, graph,
/// instruction decoding, compression or retained calculation; hash once.
pub fn render_summary_json(analysis : Analysis) -> String {
  let root : Map[String, Json] = Map([])
  root.set("format", Json::string("moonsize-summary"))
  root.set("schema_version", int_json(1))
  let input : Map[String, Json] = Map([])
  input.set("file_size", int_json(analysis.parsed.file_size))
  input.set("sha256", Json::string(experiment_sha256(analysis.data)))
  input.set("wasm_version", int_json(analysis.parsed.version))
  root.set("input", Json::object(input))
  let sections : Array[Json] = []
  let ordered = analysis.parsed.sections.copy()
  ordered.sort_by(fn(a, b) { a.offset.compare(b.offset) })
  let mut section_bytes = 0
  for ordinal, section in ordered {
    let row : Map[String, Json] = Map([])
    row.set("ordinal", int_json(ordinal))
    row.set("id", int_json(section.id))
    row.set("kind", Json::string(section.kind.name()))
    row.set("offset", int_json(section.offset))
    row.set("payload_size", int_json(section.payload_size))
    row.set("total_size", int_json(section.total_size))
    row.set(
      "section_header_bytes",
      int_json(section.total_size - section.payload_size),
    )
    row.set("custom_name_display", path_optional_string(section.custom_name))
    sections.push(Json::object(row))
    section_bytes += section.total_size
  }
  root.set("sections", Json::array(sections))
  let retained : Map[Int, RetainedSize] = Map([])
  for entry in analysis.retained {
    retained.set(entry.index, entry)
  }
  let stats = analysis.stats.copy()
  stats.sort_by(fn(a, b) { a.index.compare(b.index) })
  let functions : Array[Json] = []
  let by_module : Map[String, Array[FunctionStat]] = Map([])
  let mut body_bytes = 0
  let mut prefix_bytes = 0
  let mut encoded_bytes = 0
  let mut reachable_count = 0
  let mut reachable_bytes = 0
  for stat in stats {
    let row : Map[String, Json] = Map([])
    row.set("index", int_json(stat.index))
    row.set("name", Json::string(stat.name))
    row.set("raw_name", path_optional_string(stat.raw_name))
    row.set("module_name", Json::string(stat.module_name))
    row.set("offset", int_json(stat.offset))
    row.set("body_size", int_json(stat.body_size))
    row.set("prefix_size", int_json(stat.total_size - stat.body_size))
    row.set("total_size", int_json(stat.total_size))
    row.set(
      "model_reachable",
      Json::boolean(analysis.reachable.contains(stat.index)),
    )
    row.set("model_root", Json::boolean(analysis.roots.contains(stat.index)))
    row.set(
      "model_indirect_candidate",
      Json::boolean(analysis.indirect.contains(stat.index)),
    )
    row.set(
      "model_retained",
      match retained.get(stat.index) {
        None => Json::null()
        Some(entry) => {
          let fields : Map[String, Json] = Map([])
          fields.set("own_encoded_bytes", int_json(entry.own_size))
          fields.set("dominated_encoded_bytes", int_json(entry.retained))
          fields.set(
            "other_dominated_function_count",
            int_json(entry.retained_functions),
          )
          Json::object(fields)
        }
      },
    )
    functions.push(Json::object(row))
    let members = by_module.get(stat.module_name).unwrap_or([])
    members.push(stat)
    by_module.set(stat.module_name, members)
    body_bytes += stat.body_size
    prefix_bytes += stat.total_size - stat.body_size
    encoded_bytes += stat.total_size
    if analysis.reachable.contains(stat.index) {
      reachable_count += 1
      reachable_bytes += stat.total_size
    }
  }
  root.set("functions", Json::array(functions))
  let labels : Array[String] = []
  for label, _ in by_module {
    labels.push(label)
  }
  labels.sort_by(fn(a, b) { a.lexical_compare(b) })
  let modules : Array[Json] = []
  for label in labels {
    let members = by_module.get(label).unwrap_or([])
    let indices : Array[Json] = []
    let mut body = 0
    let mut prefix = 0
    let mut encoded = 0
    // Groups were built from the copied, index-sorted stats.
    for stat in members {
      indices.push(int_json(stat.index))
      body += stat.body_size
      prefix += stat.total_size - stat.body_size
      encoded += stat.total_size
    }
    let row : Map[String, Json] = Map([])
    row.set("module_name", Json::string(label))
    row.set("function_count", int_json(members.length()))
    row.set("body_bytes", int_json(body))
    row.set("prefix_bytes", int_json(prefix))
    row.set("encoded_bytes", int_json(encoded))
    row.set("function_indices", Json::array(indices))
    modules.push(Json::object(row))
  }
  root.set("modules", Json::array(modules))
  let summary : Map[String, Json] = Map([])
  summary.set("wasm_header_bytes", int_json(8))
  summary.set("section_count", int_json(sections.length()))
  summary.set("section_bytes", int_json(section_bytes))
  summary.set("defined_function_count", int_json(stats.length()))
  summary.set("defined_body_bytes", int_json(body_bytes))
  summary.set("defined_prefix_bytes", int_json(prefix_bytes))
  summary.set("defined_encoded_bytes", int_json(encoded_bytes))
  summary.set("reachable_defined_count", int_json(reachable_count))
  summary.set(
    "unreachable_defined_count",
    int_json(stats.length() - reachable_count),
  )
  summary.set("reachable_encoded_bytes", int_json(reachable_bytes))
  summary.set(
    "unreachable_encoded_bytes",
    int_json(encoded_bytes - reachable_bytes),
  )
  summary.set("module_count", int_json(labels.length()))
  root.set("summary", Json::object(summary))
  let roots : Array[Int] = []
  for index in analysis.roots {
    roots.push(index)
  }
  roots.sort_by(fn(a, b) { a.compare(b) })
  let model : Map[String, Json] = Map([])
  model.set("graph_complete", Json::boolean(analysis.graph_complete))
  model.set("unresolved_count", int_json(analysis.unresolved_count))
  model.set("diagnostic_count", int_json(analysis.graph.diagnostics.length()))
  model.set("diagnostics", summary_diagnostics(analysis.graph))
  model.set(
    "root_indices",
    Json::array(roots.map(fn(index) { int_json(index) })),
  )
  model.set(
    "modeling_scope",
    Json::string(
      graph_modeling_scope() +
      " Model reachability does not prove actual execution or safe removal. Module names are existing symbol attribution labels, not verified source packages or dependencies. Function/module bytes are contained within sections; these views must not be added together.",
    ),
  )
  model.set(
    "retained_scope",
    Json::string(
      retained_modeling_scope() +
      " dominated_encoded_bytes includes the function itself; other_dominated_function_count excludes it. Missing results remain null, never inferred as zero. Retained sets may overlap; do not sum retained values.",
    ),
  )
  root.set("model", Json::object(model))
  Json::object(root).stringify(indent=2) + "\n"
}
