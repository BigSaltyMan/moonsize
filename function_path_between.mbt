///|
pub enum FunctionPathBetweenStatus {
  BetweenPathFound
  BetweenPathNotFound
} derive(Eq)

///|
pub struct FunctionPathBetweenReport {
  source : FunctionPathNode
  target_index : Int
  file_size : Int
  sha256 : String
  function_count : Int
  status : FunctionPathBetweenStatus
  path_nodes : Array[FunctionPathNode]
  path_edges : Array[CallEdge]
  hop_count : Int?
  prepared_closure_function_count : Int
  graph_complete : Bool
  unresolved_count : Int
  diagnostics : Array[GraphDiagnostic]
  graph_warning : String
  modeling_scope : String
}

///|
pub enum FunctionPathBetweenError {
  BetweenDependenciesError(FunctionDependenciesError)
  InvalidBetweenTarget(Int, Int)
  /// Optional caller, callee and file offset belong to actual edge evidence only.
  InvalidBetweenEvidence(Int?, Int?, Int?, String)
}

///|
pub fn describe_function_path_between_error(
  error : FunctionPathBetweenError,
) -> String {
  match error {
    BetweenDependenciesError(error) =>
      describe_function_dependencies_error(error)
    InvalidBetweenTarget(index, count) =>
      "path destination function index \{index} is outside the function index space of \{count}"
    InvalidBetweenEvidence(caller, callee, offset, reason) =>
      "invalid function-to-function path evidence" +
      (match (caller, callee, offset) {
        (Some(a), Some(b), Some(n)) => " for \{a} -> \{b} at file offset \{n}"
        _ => " (no edge position available)"
      }) +
      ": " +
      reason
  }
}

///|
fn between_scope() -> String {
  "One deterministic minimum-hop FROM -> TO path in the current reference model, allowing any valid full indices, including imports; the source need not be a model root or root-reachable. " +
  "Direct means a recorded call dependency; Reference is a reference taken by ref.func; Indirect is a static candidate, not a known execution. Edges keep original caller -> callee direction. CallEdge has no opcode: call/return_call are not guessed; inspect file offsets separately with --locate-offset --locate-decode. " +
  "This prepares the complete original function_dependencies closure exactly once and reconstructs its deterministic first-discovery predecessors; it does not stop at the destination, run another BFS, decode instructions or apply why-index resource limits. Preparation and evidence memory depend on the complete closure and graph. " +
  "Zero hops only means identical source/destination, not a nonempty cycle. Not found means no recorded path in this direction within the current model, not proof of no dependency or host behavior. A missing destination identity is not fabricated. " +
  "Diagnostics and graph_complete describe the entire module, including sites outside this path. No path byte sum, retained, execution frequency, stack depth, recompilation or gzip/deletion savings are computed. " +
  graph_modeling_scope()
}

///|
/// Reconstruct only. One node map and edge-tuple set, no graph build or search.
/// The node-count bound and strictly decreasing depths reject partial/bad chains.
fn between_reconstruct(
  source_node : FunctionPathNode,
  function_count : Int,
  prepared_nodes : Array[FunctionDependencyNode],
  prepared_edges : Array[CallEdge],
  target_index : Int,
) -> Result[
  (FunctionPathBetweenStatus, Array[FunctionPathNode], Array[CallEdge], Int?),
  FunctionPathBetweenError,
] {
  if target_index < 0 || target_index >= function_count {
    return Err(InvalidBetweenTarget(target_index, function_count))
  }
  let indexed : Map[Int, FunctionDependencyNode] = Map([])
  for entry in prepared_nodes {
    if indexed.contains(entry.node.index) {
      return Err(
        InvalidBetweenEvidence(
          None,
          None,
          None,
          "duplicate closure node \{entry.node.index}",
        ),
      )
    }
    indexed.set(entry.node.index, entry)
  }
  let source = match indexed.get(source_node.index) {
    Some(entry) => entry
    None =>
      return Err(
        InvalidBetweenEvidence(
          None,
          None,
          None,
          "source absent from prepared closure",
        ),
      )
  }
  if source.depth != 0 || source.predecessor is Some(_) {
    return Err(
      InvalidBetweenEvidence(
        None,
        None,
        None,
        "source must have depth zero and no predecessor",
      ),
    )
  }
  let destination = match indexed.get(target_index) {
    Some(entry) => entry
    None => return Ok((BetweenPathNotFound, [], [], None))
  }
  if destination.depth < 0 || destination.depth >= prepared_nodes.length() {
    return Err(
      InvalidBetweenEvidence(
        None,
        None,
        None,
        "destination depth outside prepared node bound",
      ),
    )
  }
  let evidence : Set[(Int, Int, Int, Int)] = Set([])
  for edge in prepared_edges {
    evidence.add(
      (edge.caller, edge.callee, path_edge_rank(edge.kind), edge.offset),
    )
  }
  let backwards_nodes : Array[FunctionPathNode] = []
  let backwards_edges : Array[CallEdge] = []
  let mut current = destination
  // At most the prepared node count. No recursive paths or second BFS.
  for _ in 0..<prepared_nodes.length() {
    backwards_nodes.push(current.node)
    if current.node.index == source_node.index {
      if current.depth != 0 ||
        current.predecessor is Some(_) ||
        backwards_edges.length() != destination.depth {
        return Err(
          InvalidBetweenEvidence(
            None,
            None,
            None,
            "path did not end at the depth-zero source with expected hops",
          ),
        )
      }
      let nodes : Array[FunctionPathNode] = []
      let edges : Array[CallEdge] = []
      for i in 0..<backwards_nodes.length() {
        nodes.push(backwards_nodes[backwards_nodes.length() - 1 - i])
      }
      for i in 0..<backwards_edges.length() {
        edges.push(backwards_edges[backwards_edges.length() - 1 - i])
      }
      return Ok((BetweenPathFound, nodes, edges, Some(edges.length())))
    }
    let edge = match current.predecessor {
      Some(edge) => edge
      None =>
        return Err(
          InvalidBetweenEvidence(
            None,
            None,
            None,
            "missing predecessor at function \{current.node.index}",
          ),
        )
    }
    if edge.callee != current.node.index {
      return Err(
        InvalidBetweenEvidence(
          Some(edge.caller),
          Some(edge.callee),
          Some(edge.offset),
          "predecessor callee differs from current node",
        ),
      )
    }
    if !evidence.contains(
        (edge.caller, edge.callee, path_edge_rank(edge.kind), edge.offset),
      ) {
      return Err(
        InvalidBetweenEvidence(
          Some(edge.caller),
          Some(edge.callee),
          Some(edge.offset),
          "predecessor not present in complete closure evidence",
        ),
      )
    }
    let parent = match indexed.get(edge.caller) {
      Some(entry) => entry
      None =>
        return Err(
          InvalidBetweenEvidence(
            Some(edge.caller),
            Some(edge.callee),
            Some(edge.offset),
            "predecessor caller absent from prepared closure",
          ),
        )
    }
    if current.depth <= 0 || parent.depth != current.depth - 1 {
      return Err(
        InvalidBetweenEvidence(
          Some(edge.caller),
          Some(edge.callee),
          Some(edge.offset),
          "predecessor depth does not decrease by one",
        ),
      )
    }
    backwards_edges.push(edge)
    current = parent
  }
  Err(
    InvalidBetweenEvidence(
      None,
      None,
      None,
      "path failed to reach source within prepared node bound",
    ),
  )
}

///|
/// Exactly one dependencies query. No second parse, build, BFS or opcode lookup.
pub fn function_path_between(
  data : Bytes,
  source_index : Int,
  target_index : Int,
) -> Result[FunctionPathBetweenReport, FunctionPathBetweenError] {
  let closure = match function_dependencies(data, source_index) {
    Ok(report) => report
    Err(error) => return Err(BetweenDependenciesError(error))
  }
  let (status, path_nodes, path_edges, hop_count) = match
    between_reconstruct(
      closure.target,
      closure.function_count,
      closure.nodes,
      closure.edges,
      target_index,
    ) {
    Ok(result) => result
    Err(error) => return Err(error)
  }
  Ok({
    source: closure.target,
    target_index,
    file_size: closure.file_size,
    sha256: closure.sha256,
    function_count: closure.function_count,
    status,
    path_nodes,
    path_edges,
    hop_count,
    prepared_closure_function_count: closure.nodes.length(),
    graph_complete: closure.graph_complete,
    unresolved_count: closure.unresolved_count,
    diagnostics: closure.diagnostics,
    graph_warning: closure.graph_warning,
    modeling_scope: between_scope(),
  })
}
