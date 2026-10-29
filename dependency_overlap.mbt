///|
pub struct DependencyOverlapGroup {
  /// shared, left_only, right_only or neither; relative to these two starts only.
  kind : String
  indices : Array[Int]
  function_count : Int
  local_count : Int
  imported_count : Int
  local_encoded_bytes : Int
}

///|
pub struct DependencyOverlapReport {
  file_size : Int
  sha256 : String
  left_index : Int
  right_index : Int
  functions : Array[FunctionPathNode]
  left_reachable : Array[Int]
  right_reachable : Array[Int]
  left_edges : Array[CallEdge]
  right_edges : Array[CallEdge]
  groups : Array[DependencyOverlapGroup]
  function_count : Int
  local_function_count : Int
  imported_function_count : Int
  local_encoded_bytes : Int
  left_function_count : Int
  left_local_count : Int
  left_imported_count : Int
  left_local_encoded_bytes : Int
  right_function_count : Int
  right_local_count : Int
  right_imported_count : Int
  right_local_encoded_bytes : Int
  union_function_count : Int
  union_local_count : Int
  union_imported_count : Int
  union_local_encoded_bytes : Int
  graph_complete : Bool
  unresolved_count : Int
  diagnostics : Array[GraphDiagnostic]
  graph_warning : String
  modeling_scope : String
}

///|
pub enum DependencyOverlapError {
  OverlapInputError(WasmError)
  InvalidOverlapTarget(String, Int, Int)
  OverlapEvidenceError(FunctionDependenciesError)
}

///|
pub fn describe_dependency_overlap_error(
  error : DependencyOverlapError,
) -> String {
  match error {
    OverlapInputError(error) => describe_error(error)
    InvalidOverlapTarget(side, index, count) =>
      "dependency comparison \{side} function index \{index} is outside the function index space of \{count}"
    OverlapEvidenceError(error) =>
      "dependency comparison evidence: " +
      describe_function_dependencies_error(error)
  }
}

///|
fn overlap_scope() -> String {
  "Four disjoint partitions of the full function index space for two outgoing reference-model closures in this single input. Each closure includes its own start, and starts may themselves be shared. Any valid local/imported index is allowed, regardless of export or model-root reachability. " +
  "shared is intersection; left_only/right_only are relative only to these two starts, not global exclusivity. A third export, start or element root may still reach a single-side member. neither is not dead code. Shared does not mean simultaneous execution or entrypoint attribution. " +
  "One inventory and one graph build, at most two existing closure BFS calls; identical starts reuse one result. Each helper may validate and sort graph evidence again. This is not a parse-once or prepare-everything-once claim. Complete left/right edges preserve parallel sites, kinds, candidates and loops; their counts cannot be added as unique call sites. " +
  "Unique local bytes use total_size including body length prefixes, excluding code header/count and data/type/name/other sections. Imported encoded_size remains null, with no body contribution in this file, not a measured zero-cost host. No extra left-plus-right byte sum, retained, deduplication, splitting, removal, recompilation or gzip savings are computed. " +
  "Direct, ref.func references taken and static indirect candidates keep their model meanings, not actual execution. Diagnostics and graph_complete cover the whole module, even outside both closures; unresolved_count retains its table-site meaning. Top limits each of the first three text tables only, not traversal, full indices/edges or JSON; neither has summary only in text. " +
  graph_modeling_scope()
}

///|
/// One inventory scan. Indices, not names or byte fingerprints, define identity.
fn overlap_partition(
  inventory : Array[FunctionPathNode],
  left : Array[Int],
  right : Array[Int],
) -> Array[DependencyOverlapGroup] {
  let a : Set[Int] = Set(left)
  let b : Set[Int] = Set(right)
  let members : Array[Array[Int]] = Array::makei(4, fn(_) { [] })
  let locals = Array::make(4, 0)
  let imports = Array::make(4, 0)
  let sizes = Array::make(4, 0)
  for node in inventory {
    let group = if a.contains(node.index) {
      if b.contains(node.index) {
        0
      } else {
        1
      }
    } else if b.contains(node.index) {
      2
    } else {
      3
    }
    members[group].push(node.index)
    if node.imported {
      imports[group] += 1
    } else {
      locals[group] += 1
      sizes[group] += node.encoded_size.unwrap_or(0)
    }
  }
  let kinds = ["shared", "left_only", "right_only", "neither"]
  Array::makei(4, fn(i) {
    members[i].sort()
    DependencyOverlapGroup::{
      kind: kinds[i],
      indices: members[i],
      function_count: members[i].length(),
      local_count: locals[i],
      imported_count: imports[i],
      local_encoded_bytes: sizes[i],
    }
  })
}

///|
/// One build; different starts invoke the old helper twice, equal starts once.
pub fn compare_function_dependencies(
  data : Bytes,
  left_index : Int,
  right_index : Int,
) -> Result[DependencyOverlapReport, DependencyOverlapError] {
  let parsed = match parse_module(data) {
    Ok(value) => value
    Err(error) => return Err(OverlapInputError(error))
  }
  let inventory = match path_inventory(data, parsed) {
    Ok(value) => value
    Err(error) => return Err(OverlapInputError(error))
  }
  for pair in [("left", left_index), ("right", right_index)] {
    let (side, index) = pair
    if index < 0 || index >= inventory.length() {
      return Err(InvalidOverlapTarget(side, index, inventory.length()))
    }
  }
  let graph = match build(data) {
    Ok(value) => value
    Err(error) => return Err(OverlapInputError(error))
  }
  let (left_nodes, left_edges) = match
    dependencies_closure(inventory, graph.edges, left_index, data.length()) {
    Ok(value) => value
    Err(error) => return Err(OverlapEvidenceError(error))
  }
  let (right_nodes, right_edges) = if left_index == right_index {
    (left_nodes, left_edges)
  } else {
    match
      dependencies_closure(inventory, graph.edges, right_index, data.length()) {
      Ok(value) => value
      Err(error) => return Err(OverlapEvidenceError(error))
    }
  }
  let left_reachable = left_nodes.map(fn(n) { n.node.index })
  let right_reachable = right_nodes.map(fn(n) { n.node.index })
  left_reachable.sort()
  right_reachable.sort()
  let groups = overlap_partition(inventory, left_reachable, right_reachable)
  let shared = groups[0]
  let left = groups[1]
  let right = groups[2]
  let neither = groups[3]
  let union_count = shared.function_count +
    left.function_count +
    right.function_count
  let union_locals = shared.local_count + left.local_count + right.local_count
  let union_imports = shared.imported_count +
    left.imported_count +
    right.imported_count
  let union_bytes = shared.local_encoded_bytes +
    left.local_encoded_bytes +
    right.local_encoded_bytes
  Ok({
    file_size: data.length(),
    sha256: experiment_sha256(data),
    left_index,
    right_index,
    functions: inventory,
    left_reachable,
    right_reachable,
    left_edges,
    right_edges,
    groups,
    function_count: inventory.length(),
    local_function_count: union_locals + neither.local_count,
    imported_function_count: union_imports + neither.imported_count,
    local_encoded_bytes: union_bytes + neither.local_encoded_bytes,
    left_function_count: shared.function_count + left.function_count,
    left_local_count: shared.local_count + left.local_count,
    left_imported_count: shared.imported_count + left.imported_count,
    left_local_encoded_bytes: shared.local_encoded_bytes +
    left.local_encoded_bytes,
    right_function_count: shared.function_count + right.function_count,
    right_local_count: shared.local_count + right.local_count,
    right_imported_count: shared.imported_count + right.imported_count,
    right_local_encoded_bytes: shared.local_encoded_bytes +
    right.local_encoded_bytes,
    union_function_count: union_count,
    union_local_count: union_locals,
    union_imported_count: union_imports,
    union_local_encoded_bytes: union_bytes,
    graph_complete: is_graph_complete(graph),
    unresolved_count: graph.unresolved_indirect.length(),
    diagnostics: sorted_diagnostics(graph),
    graph_warning: render_graph_warning(graph),
    modeling_scope: overlap_scope(),
  })
}
