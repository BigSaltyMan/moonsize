///|
pub struct FunctionDependentNode {
  node : FunctionPathNode
  depth : Int
  next_edge : CallEdge?
}

///|
pub struct FunctionDependentsReport {
  target : FunctionPathNode
  file_size : Int
  sha256 : String
  function_count : Int
  local_function_count : Int
  imported_function_count : Int
  nodes : Array[FunctionDependentNode]
  edges : Array[CallEdge]
  reaching_function_count : Int
  other_function_count : Int
  reaching_local_count : Int
  reaching_imported_count : Int
  dependent_function_count : Int
  local_encoded_bytes : Int
  reaching_local_encoded_bytes : Int
  other_local_encoded_bytes : Int
  target_local_encoded_bytes : Int
  dependent_local_encoded_bytes : Int
  edge_count : Int
  direct_edges : Int
  reference_edges : Int
  indirect_edges : Int
  graph_complete : Bool
  unresolved_count : Int
  diagnostics : Array[GraphDiagnostic]
  graph_warning : String
  modeling_scope : String
}

///|
pub enum FunctionDependentsError {
  DependentsInputError(WasmError)
  InvalidDependentsTarget(Int, Int)
  InvalidDependentsEvidence(Int, Int, String)
}

///|
pub fn describe_function_dependents_error(
  error : FunctionDependentsError,
) -> String {
  match error {
    DependentsInputError(error) => describe_error(error)
    InvalidDependentsTarget(index, count) =>
      "dependent target function index \{index} is outside the function index space of \{count}"
    InvalidDependentsEvidence(index, offset, reason) =>
      "invalid dependent graph evidence for function \{index} at file offset \{offset}: " +
      reason
  }
}

///|
fn dependents_scope() -> String {
  "Reverse transitive closure to any valid full function index in the current reference model, including the target itself. Sources need not be exported or reachable from model roots. " +
  "Direct calls, references taken by ref.func and static indirect candidates count as model steps, not actual execution, runtime heat, source-change impact, necessary retention or deletion benefit. Unmodeled call_ref targets remain diagnostics without guessed edges. " +
  "Depth is the minimum number of model edges to the target, not runtime stack depth. Each node keeps one deterministic first-discovery next_edge toward the target, in original caller -> callee direction. No full paths are copied. Target depth is zero with null next_edge. " +
  "Complete internal edges retain parallel sites, kinds, candidates, self-loops, back and cross edges, separately from the next-edge tree. Edges to nodes outside the reverse closure are excluded. " +
  "Local encoded bytes count each full function index once, including the body length prefix but excluding code header/count and type/data/name/other sections. An import's encoded_size remains null; target_local_encoded_bytes=0 for an imported target is only its local-file contribution, not a measured host body or cost. " +
  "Other functions only means functions with no modeled path to this target, not dead code. Source closures for different targets can overlap and their bytes cannot be added as module size. No source modification impact, retained, recompile or gzip savings are computed. " +
  "Diagnostics and graph_complete describe the entire module, including sites outside this closure. Top limits source text rows, not traversal cost or complete JSON; complete evidence memory grows with the graph. To inspect actual opcodes, use edge offsets separately with --locate-offset --locate-decode. " +
  graph_modeling_scope()
}

///|
/// Validate the whole graph, then one reverse head-index BFS. Evidence is never reduced
/// to adjacency sets or tree edges. Every edge keeps caller -> callee direction. No per-node path copies or instruction decode.
fn dependents_closure(
  inventory : Array[FunctionPathNode],
  edges : Array[CallEdge],
  target : Int,
  file_size : Int,
) -> Result[
  (Array[FunctionDependentNode], Array[CallEdge]),
  FunctionDependentsError,
] {
  let count = inventory.length()
  if target < 0 || target >= count {
    return Err(InvalidDependentsTarget(target, count))
  }
  let adjacency : Array[Array[CallEdge]] = Array::makei(count, fn(_) { [] })
  for edge in edges {
    for index in [edge.caller, edge.callee] {
      if index < 0 || index >= count {
        return Err(
          InvalidDependentsEvidence(
            index,
            edge.offset,
            "index outside function inventory",
          ),
        )
      }
    }
    if inventory[edge.caller].imported {
      return Err(
        InvalidDependentsEvidence(
          edge.caller,
          edge.offset,
          "imported caller has no local body",
        ),
      )
    }
    if edge.offset < 0 || edge.offset >= file_size {
      return Err(
        InvalidDependentsEvidence(
          edge.caller,
          edge.offset,
          "instruction offset outside input",
        ),
      )
    }
    adjacency[edge.callee].push(edge)
  }
  for incoming in adjacency {
    incoming.sort_by(fn(a, b) {
      if a.caller != b.caller {
        return a.caller - b.caller
      }
      let kind = path_edge_rank(a.kind) - path_edge_rank(b.kind)
      if kind != 0 {
        kind
      } else {
        a.offset - b.offset
      }
    })
  }
  let depth : Array[Int] = Array::make(count, -1)
  let next_edge : Array[CallEdge?] = Array::make(count, None)
  let queue = [target]
  depth[target] = 0
  let mut head = 0
  while head < queue.length() {
    let callee = queue[head]
    head += 1
    for edge in adjacency[callee] {
      if depth[edge.caller] >= 0 {
        continue
      }
      depth[edge.caller] = depth[callee] + 1
      next_edge[edge.caller] = Some(edge)
      queue.push(edge.caller)
    }
  }
  let closure_edges : Array[CallEdge] = []
  for edge in edges {
    if depth[edge.callee] < 0 {
      continue
    }
    if depth[edge.caller] < 0 {
      return Err(
        InvalidDependentsEvidence(
          edge.caller,
          edge.offset,
          "caller escapes computed reverse closure",
        ),
      )
    }
    closure_edges.push(edge)
  }
  closure_edges.sort_by(fn(a, b) {
    if a.caller != b.caller {
      return a.caller - b.caller
    }
    if a.offset != b.offset {
      return a.offset - b.offset
    }
    if a.callee != b.callee {
      return a.callee - b.callee
    }
    path_edge_rank(a.kind) - path_edge_rank(b.kind)
  })
  let nodes = queue.map(fn(index) {
    FunctionDependentNode::{
      node: inventory[index],
      depth: depth[index],
      next_edge: next_edge[index],
    }
  })
  nodes.sort_by(fn(a, b) {
    if a.depth != b.depth {
      a.depth - b.depth
    } else {
      a.node.index - b.node.index
    }
  })
  Ok((nodes, closure_edges))
}

///|
/// One inventory and one build(data), not analyze, retained, SCC or callers.
/// Existing inventory/build parsing is reused; this is not a parse-once claim.
pub fn function_dependents(
  data : Bytes,
  target_index : Int,
) -> Result[FunctionDependentsReport, FunctionDependentsError] {
  let parsed = match parse_module(data) {
    Ok(value) => value
    Err(error) => return Err(DependentsInputError(error))
  }
  let inventory = match path_inventory(data, parsed) {
    Ok(value) => value
    Err(error) => return Err(DependentsInputError(error))
  }
  if target_index < 0 || target_index >= inventory.length() {
    return Err(InvalidDependentsTarget(target_index, inventory.length()))
  }
  let graph = match build(data) {
    Ok(value) => value
    Err(error) => return Err(DependentsInputError(error))
  }
  let (nodes, edges) = match
    dependents_closure(inventory, graph.edges, target_index, data.length()) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let mut imports = 0
  let mut local_bytes = 0
  for node in inventory {
    if node.imported {
      imports += 1
    } else {
      local_bytes += node.encoded_size.unwrap_or(0)
    }
  }
  let mut reached_imports = 0
  let mut reached_bytes = 0
  for entry in nodes {
    if entry.node.imported {
      reached_imports += 1
    } else {
      reached_bytes += entry.node.encoded_size.unwrap_or(0)
    }
  }
  let mut direct = 0
  let mut reference = 0
  let mut indirect = 0
  for edge in edges {
    match edge.kind {
      Direct => direct += 1
      Reference => reference += 1
      Indirect => indirect += 1
    }
  }
  let target = inventory[target_index]
  let target_bytes = target.encoded_size.unwrap_or(0)
  Ok({
    target,
    file_size: data.length(),
    sha256: experiment_sha256(data),
    function_count: inventory.length(),
    local_function_count: inventory.length() - imports,
    imported_function_count: imports,
    nodes,
    edges,
    reaching_function_count: nodes.length(),
    other_function_count: inventory.length() - nodes.length(),
    reaching_local_count: nodes.length() - reached_imports,
    reaching_imported_count: reached_imports,
    dependent_function_count: nodes.length() - 1,
    local_encoded_bytes: local_bytes,
    reaching_local_encoded_bytes: reached_bytes,
    other_local_encoded_bytes: local_bytes - reached_bytes,
    target_local_encoded_bytes: target_bytes,
    dependent_local_encoded_bytes: reached_bytes - target_bytes,
    edge_count: edges.length(),
    direct_edges: direct,
    reference_edges: reference,
    indirect_edges: indirect,
    graph_complete: is_graph_complete(graph),
    unresolved_count: graph.unresolved_indirect.length(),
    diagnostics: sorted_diagnostics(graph),
    graph_warning: render_graph_warning(graph),
    modeling_scope: dependents_scope(),
  })
}
