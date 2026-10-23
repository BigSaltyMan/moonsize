///|
pub struct EntrypointGroup {
  /// Full function index, also the stable group identifier within this artifact.
  index : Int
  aliases : Array[String]
  reachable : Array[Int]
  local_function_count : Int
  imported_function_count : Int
  reachable_model_bytes : Int
  exclusive_model_bytes : Int
  shared_model_bytes : Int
}

///|
/// One inventory node per function; groups and shared lists refer to its index.
pub struct EntrypointFunction {
  node : FunctionPathNode
  entrypoints : Array[Int]
  other_root_reachable : Bool
}

///|
pub struct EntrypointsLedger {
  local_function_count : Int
  total_local_bytes : Int
  export_union_local_count : Int
  export_union_bytes : Int
  not_export_reachable_bytes : Int
  exclusive_model_bytes : Int
  shared_model_bytes : Int
}

///|
pub struct EntrypointsReport {
  file_size : Int
  sha256 : String
  export_name_count : Int
  entrypoint_count : Int
  other_exports : Array[Export]
  entrypoints : Array[EntrypointGroup]
  /// Full function index order. Imports retain encoded_size=None.
  functions : Array[EntrypointFunction]
  other_roots : Array[FunctionRoot]
  other_root_reachable : Array[Int]
  /// Export-reachable local functions shared with another group or other roots.
  shared_local_functions : Array[Int]
  ledger : EntrypointsLedger
  graph_complete : Bool
  diagnostics : Array[GraphDiagnostic]
  graph_warning : String
  modeling_scope : String
}

///|
pub enum EntrypointsError {
  EntrypointsInputError(WasmError)
  /// Actual export name, export ordinal, function index, function count.
  InvalidEntrypointExport(String, Int, Int, Int)
  /// Actual root description (start/element ordinal), index, function count.
  InvalidEntrypointsRoot(String, Int, Int)
  /// Actual caller/callee and instruction file offset from the graph.
  InvalidEntrypointsEdge(Int, Int, Int)
  InvalidEntrypointsExportKind(String, Int, Int)
}

///|
pub fn describe_entrypoints_error(error : EntrypointsError) -> String {
  match error {
    EntrypointsInputError(error) => describe_error(error)
    InvalidEntrypointExport(name, ordinal, index, count) =>
      "function export " +
      Json::string(name).stringify() +
      " at export ordinal \{ordinal} references index \{index} outside function count \{count}"
    InvalidEntrypointsRoot(source, index, count) =>
      "\{source} references index \{index} outside function count \{count}"
    InvalidEntrypointsEdge(caller, callee, offset) =>
      "invalid function edge \{caller} -> \{callee} at file offset \{offset}"
    InvalidEntrypointsExportKind(name, ordinal, kind) =>
      "export " +
      Json::string(name).stringify() +
      " at export ordinal \{ordinal} has unsupported kind \{kind}"
  }
}

///|
fn entrypoints_scope() -> String {
  "Function exports are grouped by function index; aliases do not repeat traversal. " +
  "Exclusive/shared bytes describe reachability sets in the current reference model, not execution frequency or savings from deleting an export. " +
  "Start and all element functions remain conservative roots, even when exported. " +
  "Indirect candidates and ref.func references do not imply inevitable runtime calls. Module diagnostics need not concern every entry. " +
  "Weights are local total_size bytes (including body length prefixes), excluding code section header/count and data/name/type/other sections. " +
  "Imports have no local body measurement; null does not mean host calls have no cost. " +
  "Per-entry reachable/shared bytes overlap and must not be added as module size. Not reached by function exports does not mean dead or removable. " +
  "No prediction of recompiled or gzip savings; graph_complete and strict success do not establish full semantics. " +
  "Top limits display only, not parsing or traversal costs; more unique entries require more reachability computations. " +
  graph_modeling_scope()
}

///|
fn entrypoints_sorted(set : Set[Int]) -> Array[Int] {
  let indices = set.to_array()
  indices.sort_by(fn(a, b) { a.compare(b) })
  indices
}

///|
fn entrypoints_add_root(
  roots : Map[Int, Array[FunctionRootReason]],
  reason : FunctionRootReason,
) -> Unit {
  let reasons = roots.get(reason.function_index).unwrap_or([])
  reasons.push(reason)
  roots.set(reason.function_index, reasons)
}

///|
/// One graph, one traversal per unique function export, one for all other roots.
/// Parsing/building uses existing safe entry points; no analyze or dominators.
pub fn inspect_entrypoints(
  data : Bytes,
) -> Result[EntrypointsReport, EntrypointsError] {
  let parsed = match parse_module(data) {
    Ok(m) => m
    Err(e) => return Err(EntrypointsInputError(e))
  }
  let inventory = match path_inventory(data, parsed) {
    Ok(v) => v
    Err(e) => return Err(EntrypointsInputError(e))
  }
  let count = inventory.length()
  let sections = find_sections(parsed)
  let exports = match sections.exports {
    None => []
    Some(section) =>
      match parse_export_section(data, section) {
        Ok(v) => v
        Err(e) => return Err(EntrypointsInputError(e))
      }
  }
  let aliases : Map[Int, Array[String]] = Map([])
  let other_exports : Array[Export] = []
  let mut export_name_count = 0
  for ordinal, item in exports {
    if item.kind == 0 {
      if item.index < 0 || item.index >= count {
        return Err(
          InvalidEntrypointExport(item.name, ordinal, item.index, count),
        )
      }
      let names = aliases.get(item.index).unwrap_or([])
      names.push(item.name)
      aliases.set(item.index, names)
      export_name_count += 1
    } else if item.kind >= 1 && item.kind <= 4 {
      other_exports.push(item)
    } else {
      return Err(InvalidEntrypointsExportKind(item.name, ordinal, item.kind))
    }
  }
  let reasons : Map[Int, Array[FunctionRootReason]] = Map([])
  if sections.start is Some(section) {
    let index = match parse_start_section(data, section) {
      Ok(n) => n
      Err(e) => return Err(EntrypointsInputError(e))
    }
    if index < 0 || index >= count {
      return Err(InvalidEntrypointsRoot("start section", index, count))
    }
    entrypoints_add_root(reasons, {
      function_index: index,
      kind: StartRoot,
      name: None,
      section_offset: section.offset,
      ordinal: None,
      table_index: None,
      element_mode: None,
    })
  }
  if sections.elements is Some(section) {
    let segments = match parse_element_section(data, section) {
      Ok(v) => v
      Err(e) => return Err(EntrypointsInputError(e))
    }
    for ordinal, segment in segments {
      let seen : Set[Int] = Set([])
      for index in segment.functions {
        if index < 0 || index >= count {
          return Err(
            InvalidEntrypointsRoot("element segment \{ordinal}", index, count),
          )
        }
        if seen.contains(index) {
          continue
        }
        seen.add(index)
        entrypoints_add_root(reasons, {
          function_index: index,
          kind: ElementRoot,
          name: None,
          section_offset: section.offset,
          ordinal: Some(ordinal),
          table_index: if segment.table_index < 0 {
            None
          } else {
            Some(segment.table_index)
          },
          element_mode: Some(
            if segment.passive {
              "passive-or-declarative"
            } else {
              "active"
            },
          ),
        })
      }
    }
  }
  let graph = match build(data) {
    Ok(g) => g
    Err(e) => return Err(EntrypointsInputError(e))
  }
  for edge in graph.edges {
    if edge.caller < 0 ||
      edge.caller >= count ||
      edge.callee < 0 ||
      edge.callee >= count {
      return Err(InvalidEntrypointsEdge(edge.caller, edge.callee, edge.offset))
    }
  }
  let root_indices = reasons.keys().to_array()
  root_indices.sort_by(fn(a, b) { a.compare(b) })
  let other_roots = root_indices.map(fn(index) {
    { index, reasons: reasons.get(index).unwrap_or([]), }
  })
  let other_reachable = reachable_from_roots(
    graph,
    Set::from_array(root_indices),
  )
  let owners : Array[Array[Int]] = Array::makei(count, fn(_) { [] })
  let indices = aliases.keys().to_array()
  indices.sort_by(fn(a, b) { a.compare(b) })
  let reaches : Map[Int, Array[Int]] = Map([])
  for index in indices {
    let reachable = entrypoints_sorted(
      reachable_from_roots(graph, Set([index])),
    )
    for function in reachable {
      owners[function].push(index)
    }
    reaches.set(index, reachable)
  }
  let functions : Array[EntrypointFunction] = inventory.map(fn(node) {
    {
      node,
      entrypoints: owners[node.index],
      other_root_reachable: other_reachable.contains(node.index),
    }
  })
  let shared : Array[Int] = []
  let mut local_function_count = 0
  let mut total_local_bytes = 0
  let mut export_union_local_count = 0
  let mut export_union_bytes = 0
  let mut exclusive_model_bytes = 0
  let mut shared_model_bytes = 0
  for function in functions {
    if function.node.encoded_size is Some(size) {
      local_function_count += 1
      total_local_bytes += size
      if !function.entrypoints.is_empty() {
        export_union_local_count += 1
        export_union_bytes += size
        if function.entrypoints.length() > 1 || function.other_root_reachable {
          shared.push(function.node.index)
          shared_model_bytes += size
        } else {
          exclusive_model_bytes += size
        }
      }
    }
  }
  shared.sort_by(fn(a, b) {
    let order = inventory[b].encoded_size
      .unwrap_or(0)
      .compare(inventory[a].encoded_size.unwrap_or(0))
    if order == 0 {
      a.compare(b)
    } else {
      order
    }
  })
  let groups : Array[EntrypointGroup] = []
  for index in indices {
    let reachable = reaches.get(index).unwrap_or([])
    let mut local_count = 0
    let mut imported = 0
    let mut exclusive = 0
    let mut common = 0
    for target in reachable {
      let function = functions[target]
      match function.node.encoded_size {
        None => imported += 1
        Some(size) => {
          local_count += 1
          if function.entrypoints.length() > 1 || function.other_root_reachable {
            common += size
          } else {
            exclusive += size
          }
        }
      }
    }
    groups.push({
      index,
      aliases: aliases.get(index).unwrap_or([]),
      reachable,
      local_function_count: local_count,
      imported_function_count: imported,
      reachable_model_bytes: exclusive + common,
      exclusive_model_bytes: exclusive,
      shared_model_bytes: common,
    })
  }
  groups.sort_by(fn(a, b) {
    let order = b.reachable_model_bytes.compare(a.reachable_model_bytes)
    if order == 0 {
      a.index.compare(b.index)
    } else {
      order
    }
  })
  Ok({
    file_size: data.length(),
    sha256: experiment_sha256(data),
    export_name_count,
    entrypoint_count: groups.length(),
    other_exports,
    entrypoints: groups,
    functions,
    other_roots,
    other_root_reachable: entrypoints_sorted(other_reachable),
    shared_local_functions: shared,
    ledger: {
      local_function_count,
      total_local_bytes,
      export_union_local_count,
      export_union_bytes,
      not_export_reachable_bytes: total_local_bytes - export_union_bytes,
      exclusive_model_bytes,
      shared_model_bytes,
    },
    graph_complete: is_graph_complete(graph),
    diagnostics: sorted_diagnostics(graph),
    graph_warning: render_graph_warning(graph),
    modeling_scope: entrypoints_scope(),
  })
}
