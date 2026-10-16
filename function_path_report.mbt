///|
fn function_path_status_text(status : FunctionPathStatus) -> String {
  match status {
    PathFound => "found"
    PathNotFound => "not-found-within-model"
    PathSearchLimited => "search-limited"
  }
}

///|
fn function_path_scope() -> String {
  "This is a path in the current reference model, not an execution trace or a prediction of recompiled or gzip savings. " +
  graph_modeling_scope()
}

///|
fn path_root_kind(kind : FunctionRootKind) -> String {
  match kind {
    ExportRoot => "export"
    StartRoot => "start"
    ElementRoot => "conservative-element"
  }
}

///|
fn path_edge_kind(kind : EdgeKind) -> String {
  match kind {
    Direct => "direct"
    Reference => "reference"
    Indirect => "indirect"
  }
}

///|
fn path_optional_string(text : String?) -> Json {
  match text {
    Some(text) => Json::string(text)
    None => Json::null()
  }
}

///|
fn path_node_json(node : FunctionPathNode) -> Json {
  let row : Map[String, Json] = Map([])
  row.set("index", int_json(node.index))
  row.set("name", Json::string(node.name))
  row.set("raw_name", path_optional_string(node.raw_name))
  row.set("imported", Json::boolean(node.imported))
  row.set("encoded_size", optional_index_json(node.encoded_size))
  row.set("import_module", path_optional_string(node.import_module))
  row.set("import_name", path_optional_string(node.import_name))
  Json::object(row)
}

///|
fn path_reason_json(reason : FunctionRootReason) -> Json {
  let row : Map[String, Json] = Map([])
  row.set("function_index", int_json(reason.function_index))
  row.set("kind", Json::string(path_root_kind(reason.kind)))
  row.set("name", path_optional_string(reason.name))
  row.set("section_offset", int_json(reason.section_offset))
  row.set("position_granularity", Json::string("section"))
  row.set("ordinal", optional_index_json(reason.ordinal))
  row.set("table_index", optional_index_json(reason.table_index))
  row.set("element_mode", path_optional_string(reason.element_mode))
  row.set("conservative", Json::boolean(reason.kind == ElementRoot))
  Json::object(row)
}

///|
/// Independent format version; existing call-graph JSON is unchanged.
pub fn render_function_path_json(report : FunctionPathReport) -> String {
  let root : Map[String, Json] = Map([])
  root.set("schema_version", int_json(1))
  root.set("format", Json::string("moonsize-function-path"))
  let query : Map[String, Json] = Map([])
  query.set("target_index", int_json(report.target.index))
  query.set("root_index", optional_index_json(report.requested_root))
  query.set(
    "scope",
    Json::string(
      if report.requested_root is Some(_) {
        "selected-root"
      } else {
        "all-model-roots"
      },
    ),
  )
  root.set("query", Json::object(query))
  root.set("status", Json::string(function_path_status_text(report.status)))
  root.set("target", path_node_json(report.target))
  root.set("path_root", optional_index_json(report.path_root))
  root.set("selected_roots", Json::array(report.selected_roots.map(int_json)))
  let model_roots : Array[Json] = []
  let selected_reasons : Array[Json] = []
  let selected = Set::from_array(report.selected_roots)
  for item in report.roots {
    let row : Map[String, Json] = Map([])
    let reasons = item.reasons.map(path_reason_json)
    row.set("index", int_json(item.index))
    row.set("reasons", Json::array(reasons))
    model_roots.push(Json::object(row))
    if selected.contains(item.index) {
      for reason in reasons {
        selected_reasons.push(reason)
      }
    }
  }
  root.set("model_roots", Json::array(model_roots))
  root.set(
    "root_ledger_complete",
    Json::boolean(report.search_stats.phase != "root-preparation"),
  )
  root.set("root_reasons", Json::array(selected_reasons))
  root.set("nodes", Json::array(report.nodes.map(path_node_json)))
  root.set(
    "steps",
    Json::array(
      report.steps.map(fn(step) {
        let row : Map[String, Json] = Map([])
        row.set("caller", int_json(step.caller))
        row.set("callee", int_json(step.callee))
        row.set("kind", Json::string(path_edge_kind(step.kind)))
        row.set("candidate", Json::boolean(path_edge_rank(step.kind) == 2))
        row.set("opcode", Json::string(step.opcode.name()))
        row.set("offset", int_json(step.offset))
        row.set("type_index", optional_index_json(step.type_index))
        row.set("table_index", optional_index_json(step.table_index))
        Json::object(row)
      }),
    ),
  )
  root.set("graph_complete", Json::boolean(report.graph_complete))
  root.set("diagnostics", diagnostic_records_json(report.diagnostics))
  root.set("modeling_scope", Json::string(function_path_scope()))
  let limits : Map[String, Json] = Map([])
  limits.set("max_nodes", int_json(report.limits.max_nodes))
  limits.set("max_edges", int_json(report.limits.max_edges))
  limits.set("max_depth", int_json(report.limits.max_depth))
  root.set("limits", Json::object(limits))
  let stats : Map[String, Json] = Map([])
  stats.set("root_sources", int_json(report.search_stats.root_sources))
  stats.set("prepared_roots", int_json(report.search_stats.prepared_roots))
  stats.set("indexed_edges", int_json(report.search_stats.indexed_edges))
  stats.set("visited_nodes", int_json(report.search_stats.visited_nodes))
  stats.set("checked_edges", int_json(report.search_stats.checked_edges))
  stats.set("max_depth", int_json(report.search_stats.max_depth))
  stats.set("phase", Json::string(report.search_stats.phase))
  stats.set(
    "limit_reason",
    path_optional_string(report.search_stats.limit_reason),
  )
  root.set("search_stats", Json::object(stats))
  Json::object(root).stringify(indent=2) + "\n"
}

///|
pub fn render_function_path(report : FunctionPathReport) -> String {
  let out = StringBuilder()
  out.write_string(
    "FUNCTION REFERENCE PATH\n\nTarget: #" +
    report.target.index.to_string() +
    " " +
    Json::string(report.target.name).stringify() +
    "\n",
  )
  out.write_string(
    "Identity: " +
    (if report.target.imported {
      "imported; no local body (encoded size is not measured)\n"
    } else {
      "local; encoded bytes " +
      report.target.encoded_size.unwrap_or(0).to_string() +
      "\n"
    }),
  )
  out.write_string(
    "Scope: " +
    (match report.requested_root {
      Some(index) => "selected model root #" + index.to_string()
      None =>
        "all model roots (" +
        report.selected_roots.length().to_string() +
        " selected)"
    }) +
    "\n",
  )
  out.write_string("Status: " + function_path_status_text(report.status) + "\n")
  if report.search_stats.phase == "root-preparation" {
    out.write_string(
      "Root preparation stopped early; the recorded root ledger is only a bounded prefix.\n",
    )
  }
  if report.status == PathNotFound {
    out.write_string(
      if report.requested_root is Some(_) {
        "No path from the selected root within this model. Other roots may still reach the target.\n"
      } else {
        "Search completed without a path from the model roots. This is not proof that the function can be removed.\n"
      },
    )
  }
  let selected = Set::from_array(report.selected_roots)
  for item in report.roots {
    if selected.contains(item.index) {
      out.write_string("Search root #" + item.index.to_string() + "\n")
      for reason in item.reasons {
        out.write_string("Root reason: " + path_root_kind(reason.kind))
        if reason.name is Some(name) {
          out.write_string(" " + Json::string(name).stringify())
        }
        out.write_string(
          "; section offset " + reason.section_offset.to_string(),
        )
        if reason.ordinal is Some(ordinal) {
          out.write_string("; entry/segment ordinal " + ordinal.to_string())
        }
        if reason.element_mode is Some(mode) {
          out.write_string(
            "; " +
            mode +
            "; conservatively retained, not evidence of a business call",
          )
        }
        out.write_string("\n")
      }
    }
  }
  if !report.nodes.is_empty() {
    out.write_string(
      "\n#" +
      report.nodes[0].index.to_string() +
      " " +
      Json::string(report.nodes[0].name).stringify() +
      "\n",
    )
    for i, step in report.steps {
      out.write_string(
        "  -- " +
        step.opcode.name() +
        " [" +
        (match step.kind {
          Indirect => "indirect candidate"
          Reference => "reference taken, not a call"
          Direct => "direct"
        }) +
        "]",
      )
      if step.table_index is Some(table) {
        out.write_string(" table " + table.to_string())
      }
      if step.type_index is Some(signature) {
        out.write_string(" type " + signature.to_string())
      }
      out.write_string(
        " at file offset " +
        step.offset.to_string() +
        " --> #" +
        step.callee.to_string() +
        " " +
        Json::string(report.nodes[i + 1].name).stringify() +
        "\n",
      )
    }
    if report.steps.is_empty() {
      out.write_string(
        "Zero-step path: the target itself is a selected model root.\n",
      )
    }
  }
  if report.search_stats.limit_reason is Some(reason) {
    out.write_string(
      "Search stopped: " +
      reason +
      " during " +
      report.search_stats.phase +
      "; no completed not-found conclusion.\n",
    )
  }
  if !report.graph_complete {
    out.write_string(
      "\nWARNING: graph incomplete; unmodelled references cannot be excluded, even if this query found a path.\n",
    )
    for diagnostic in report.diagnostics {
      out.write_string(
        "  function " +
        diagnostic.caller.to_string() +
        ", offset " +
        diagnostic.offset.to_string() +
        ": " +
        diagnostic.opcode.name() +
        " [" +
        diagnostic_code(diagnostic.kind) +
        "]: " +
        diagnostic_details(diagnostic) +
        "\n",
      )
    }
  }
  out.write_string(
    "\nSearch counts: roots " +
    report.search_stats.prepared_roots.to_string() +
    ", root sources " +
    report.search_stats.root_sources.to_string() +
    ", indexed edges " +
    report.search_stats.indexed_edges.to_string() +
    ", visited nodes " +
    report.search_stats.visited_nodes.to_string() +
    ", checked edges " +
    report.search_stats.checked_edges.to_string() +
    ", depth " +
    report.search_stats.max_depth.to_string() +
    ".\n",
  )
  out.write_string(
    "Limits: nodes " +
    report.limits.max_nodes.to_string() +
    ", edges/root sources " +
    report.limits.max_edges.to_string() +
    ", depth " +
    report.limits.max_depth.to_string() +
    ".\n\n" +
    function_path_scope() +
    "\n",
  )
  out.to_string()
}
