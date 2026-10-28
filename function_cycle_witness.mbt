///|
pub struct FunctionCycleWitness {
  component_id : Int
  start_index : Int
  nodes : Array[Int]
  edges : Array[CallEdge]
  edge_count : Int
  direct_edges : Int
  reference_edges : Int
  indirect_edges : Int
}

///|
pub struct FunctionCycleWitnessReport {
  cycles : FunctionCyclesReport
  witnesses : Array[FunctionCycleWitness]
  scope : String
}

///|
pub enum FunctionCycleWitnessError {
  CycleWitnessQueryError(FunctionCyclesError)
  InvalidCycleWitness(Int, Int?, String)
}

///|
pub fn describe_function_cycle_witness_error(
  error : FunctionCycleWitnessError,
) -> String {
  match error {
    CycleWitnessQueryError(error) => describe_function_cycles_error(error)
    InvalidCycleWitness(component, offset, reason) =>
      "invalid closed witness for component \{component}" +
      (match offset {
        Some(n) => " at file offset \{n}"
        None => " (no edge position available)"
      }) +
      ": " +
      reason
  }
}

///|
fn cycle_witness_scope() -> String {
  "One deterministic closed reference-model witness per component, starting and ending at its minimum function index. A root self-edge wins by direct/reference/indirect then offset; otherwise choose the first edge by callee, kind priority and offset, then one iterative BFS back to the root using the same adjacency order. " +
  "This is a representative path, possibly visiting only a subset of members, not a tour of all members, a unique cycle or a globally shortest cycle. References taken and indirect candidates are not runtime recursion; even direct edges do not prove execution. " +
  "Every witness edge comes from existing internal evidence. Parallel edges remain in the complete cycles object; witness edge counts never replace component counts. No witness byte total, new target inference or opcode decoding. Module diagnostics and unresolved_count retain their original meanings. " +
  "Top limits displayed components, not complete path steps or JSON. To inspect an actual opcode, separately use the edge file offset with --locate-offset --locate-decode."
}

///|
/// Local maps only. Adjacency records retain original edge objects and keys;
/// no allocation proportional to the module's largest function index.
fn cycle_component_witness(
  component : FunctionCycleComponent,
) -> Result[FunctionCycleWitness, FunctionCycleWitnessError] {
  let start = component.component_id
  let adjacency : Map[Int, Array[CallEdge]] = Map([])
  let original : Set[(Int, Int, Int, Int)] = Set([])
  if component.members.is_empty() ||
    component.node_count != component.members.length() {
    return Err(
      InvalidCycleWitness(start, None, "empty or inconsistent member inventory"),
    )
  }
  let mut minimum = component.members[0].index
  for node in component.members {
    if node.index < 0 || node.imported || adjacency.contains(node.index) {
      return Err(
        InvalidCycleWitness(
          start,
          None,
          "invalid or duplicate local member index \{node.index}",
        ),
      )
    }
    minimum = minimum.min(node.index)
    adjacency.set(node.index, [])
  }
  if minimum != start {
    return Err(
      InvalidCycleWitness(
        start,
        None,
        "component ID is not the minimum member index",
      ),
    )
  }
  for edge in component.internal_edges {
    if edge.offset < 0 ||
      !adjacency.contains(edge.caller) ||
      !adjacency.contains(edge.callee) {
      return Err(
        InvalidCycleWitness(
          start,
          Some(edge.offset),
          "edge has invalid position or crosses member boundary",
        ),
      )
    }
    adjacency.get(edge.caller).unwrap().push(edge)
    original.add(
      (edge.caller, edge.callee, path_edge_rank(edge.kind), edge.offset),
    )
  }
  for _, outgoing in adjacency {
    outgoing.sort_by(fn(a, b) {
      if a.callee != b.callee {
        return a.callee - b.callee
      }
      let kind = path_edge_rank(a.kind) - path_edge_rank(b.kind)
      if kind != 0 {
        kind
      } else {
        a.offset - b.offset
      }
    })
  }
  let outgoing = adjacency.get(start).unwrap()
  if outgoing.is_empty() {
    return Err(
      InvalidCycleWitness(
        start,
        None,
        "start has no outgoing internal evidence",
      ),
    )
  }
  let mut first = outgoing[0]
  for edge in outgoing {
    if edge.callee == start {
      first = edge
      break
    }
  }
  let path : Array[CallEdge] = [first]
  if first.callee != start {
    let source = first.callee
    let queue = [source]
    let visited : Set[Int] = Set([source])
    let predecessor : Map[Int, CallEdge] = Map([])
    let mut head = 0
    while head < queue.length() && !visited.contains(start) {
      let node = queue[head]
      head += 1
      for edge in adjacency.get(node).unwrap() {
        if visited.contains(edge.callee) {
          continue
        }
        visited.add(edge.callee)
        predecessor.set(edge.callee, edge)
        queue.push(edge.callee)
        if edge.callee == start {
          break
        }
      }
    }
    if !visited.contains(start) {
      return Err(
        InvalidCycleWitness(
          start,
          Some(first.offset),
          "selected successor has no return path",
        ),
      )
    }
    let backward : Array[CallEdge] = []
    let mut cursor = start
    while cursor != source {
      if backward.length() >= component.members.length() {
        return Err(
          InvalidCycleWitness(
            start,
            None,
            "predecessor chain does not terminate",
          ),
        )
      }
      let edge = match predecessor.get(cursor) {
        Some(edge) => edge
        None =>
          return Err(
            InvalidCycleWitness(
              start,
              None,
              "broken predecessor chain at function \{cursor}",
            ),
          )
      }
      if edge.callee != cursor {
        return Err(
          InvalidCycleWitness(
            start,
            Some(edge.offset),
            "predecessor edge does not join chain",
          ),
        )
      }
      backward.push(edge)
      cursor = edge.caller
    }
    let mut remaining = backward.length()
    while remaining > 0 {
      remaining -= 1
      path.push(backward[remaining])
    }
  }
  let nodes = [start]
  let seen : Set[Int] = Set([start])
  let mut direct = 0
  let mut reference = 0
  let mut indirect = 0
  for i, edge in path {
    if edge.caller != nodes[nodes.length() - 1] ||
      !original.contains(
        (edge.caller, edge.callee, path_edge_rank(edge.kind), edge.offset),
      ) {
      return Err(
        InvalidCycleWitness(
          start,
          Some(edge.offset),
          "nonjoining edge or missing original evidence",
        ),
      )
    }
    if i == path.length() - 1 {
      if edge.callee != start {
        return Err(
          InvalidCycleWitness(start, Some(edge.offset), "path does not close"),
        )
      }
    } else {
      if !adjacency.contains(edge.callee) || seen.contains(edge.callee) {
        return Err(
          InvalidCycleWitness(
            start,
            Some(edge.offset),
            "invalid or repeated interior node",
          ),
        )
      }
      seen.add(edge.callee)
    }
    nodes.push(edge.callee)
    match edge.kind {
      Direct => direct += 1
      Reference => reference += 1
      Indirect => indirect += 1
    }
  }
  Ok({
    component_id: start,
    start_index: start,
    nodes,
    edges: path,
    edge_count: path.length(),
    direct_edges: direct,
    reference_edges: reference,
    indirect_edges: indirect,
  })
}

///|
/// Exactly one call to the existing cycles query. No parsing, graph building,
/// SCC or instruction decoding is repeated here.
pub fn function_cycle_witnesses(
  data : Bytes,
) -> Result[FunctionCycleWitnessReport, FunctionCycleWitnessError] {
  let cycles = match function_cycles(data) {
    Ok(value) => value
    Err(error) => return Err(CycleWitnessQueryError(error))
  }
  let witnesses : Array[FunctionCycleWitness] = []
  for component in cycles.components {
    match cycle_component_witness(component) {
      Ok(witness) => witnesses.push(witness)
      Err(error) => return Err(error)
    }
  }
  Ok({ cycles, witnesses, scope: cycle_witness_scope(), })
}
