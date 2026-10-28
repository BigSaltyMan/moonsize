///|
pub struct FunctionCycleComponent {
  component_id : Int
  members : Array[FunctionPathNode]
  internal_edges : Array[CallEdge]
  node_count : Int
  internal_edge_count : Int
  direct_edges : Int
  reference_edges : Int
  indirect_edges : Int
  local_encoded_bytes : Int
}

///|
pub struct FunctionCyclesReport {
  file_size : Int
  sha256 : String
  function_count : Int
  imported_function_count : Int
  local_function_count : Int
  cyclic_function_count : Int
  non_cyclic_function_count : Int
  component_count : Int
  components : Array[FunctionCycleComponent]
  local_encoded_bytes : Int
  cyclic_local_encoded_bytes : Int
  other_local_encoded_bytes : Int
  graph_complete : Bool
  unresolved_count : Int
  diagnostics : Array[GraphDiagnostic]
  graph_warning : String
  modeling_scope : String
}

///|
pub enum FunctionCyclesError {
  CyclesInputError(WasmError)
  InvalidCyclesEvidence(Int, Int, String)
}

///|
pub fn describe_function_cycles_error(error : FunctionCyclesError) -> String {
  match error {
    CyclesInputError(error) => describe_error(error)
    InvalidCyclesEvidence(index, offset, reason) =>
      "invalid cycle graph evidence for function \{index} at file offset \{offset}: " +
      reason
  }
}

///|
fn function_cycles_scope() -> String {
  "Strongly connected components in the current reference model, including unreachable functions; only multi-node components or singletons with self-edges are shown. " +
  "Direct call/return_call, ref.func references taken and indirect static candidates all participate; even direct-only cycles do not prove runtime recursion. " +
  "Roots do not create body edges. Unmodeled reference calls have diagnostics, not guessed targets. Diagnostics cover the entire module and may be outside every component. " +
  "Counts are model edges, not execution counts or indirect call-site counts. An empty result or graph_complete does not prove absence of recursion, host callbacks or full semantics. " +
  "Local encoded bytes include body length prefixes and bodies, excluding code header/count and other sections; imports have no local encoded size. Disjoint component weights may be added, but are not retained size or deletion/recompile/gzip benefit. " +
  "Component IDs are minimum node indices within this input only. Top limits displayed components, not members, complete JSON or graph/SCC costs. " +
  graph_modeling_scope()
}

///|
/// Nonrecursive Kosaraju. Only topology is deduplicated; every evidence edge is
/// bucketed once after SCC assignment, including parallel positions and kinds.
fn cycles_components(
  inventory : Array[FunctionPathNode],
  edges : Array[CallEdge],
  file_size : Int,
) -> Result[Array[FunctionCycleComponent], FunctionCyclesError] {
  let count = inventory.length()
  let forward_sets : Array[Set[Int]] = Array::makei(count, fn(_) { Set([]) })
  let reverse_sets : Array[Set[Int]] = Array::makei(count, fn(_) { Set([]) })
  for edge in edges {
    for index in [edge.caller, edge.callee] {
      if index < 0 || index >= count {
        return Err(
          InvalidCyclesEvidence(
            index,
            edge.offset,
            "index outside function inventory",
          ),
        )
      }
    }
    if inventory[edge.caller].imported {
      return Err(
        InvalidCyclesEvidence(
          edge.caller,
          edge.offset,
          "imported caller has no local body",
        ),
      )
    }
    if edge.offset < 0 || edge.offset >= file_size {
      return Err(
        InvalidCyclesEvidence(
          edge.caller,
          edge.offset,
          "instruction offset outside input",
        ),
      )
    }
    forward_sets[edge.caller].add(edge.callee)
    reverse_sets[edge.callee].add(edge.caller)
  }
  let forward = forward_sets.map(fn(set) {
    let nodes = set.to_array()
    nodes.sort()
    nodes
  })
  let reverse = reverse_sets.map(fn(set) {
    let nodes = set.to_array()
    nodes.sort()
    nodes
  })
  let visited : Array[Bool] = Array::make(count, false)
  let next_edge : Array[Int] = Array::make(count, 0)
  let finished : Array[Int] = []
  for start in 0..<count {
    if visited[start] {
      continue
    }
    let stack = [start]
    visited[start] = true
    while !stack.is_empty() {
      let node = stack[stack.length() - 1]
      if next_edge[node] < forward[node].length() {
        let target = forward[node][next_edge[node]]
        next_edge[node] += 1
        if !visited[target] {
          visited[target] = true
          stack.push(target)
        }
      } else {
        let _ = stack.pop()
        finished.push(node)
      }
    }
  }
  let component_of : Array[Int] = Array::make(count, -1)
  let groups : Array[Array[Int]] = []
  let mut remaining = finished.length()
  while remaining > 0 {
    remaining -= 1
    let start = finished[remaining]
    if component_of[start] >= 0 {
      continue
    }
    let id = groups.length()
    let members : Array[Int] = []
    let stack = [start]
    component_of[start] = id
    while !stack.is_empty() {
      let node = stack.pop().unwrap()
      members.push(node)
      for predecessor in reverse[node] {
        if component_of[predecessor] < 0 {
          component_of[predecessor] = id
          stack.push(predecessor)
        }
      }
    }
    members.sort()
    groups.push(members)
  }
  let internal : Array[Array[CallEdge]] = Array::makei(groups.length(), fn(_) {
    []
  })
  for edge in edges {
    if component_of[edge.caller] == component_of[edge.callee] {
      internal[component_of[edge.caller]].push(edge)
    }
  }
  let components : Array[FunctionCycleComponent] = []
  for group_index, indices in groups {
    let evidence = internal[group_index]
    if indices.length() == 1 && evidence.is_empty() {
      continue
    }
    evidence.sort_by(fn(a, b) {
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
    let mut direct = 0
    let mut reference = 0
    let mut indirect = 0
    for edge in evidence {
      match edge.kind {
        Direct => direct += 1
        Reference => reference += 1
        Indirect => indirect += 1
      }
    }
    let members = indices.map(fn(index) { inventory[index] })
    let mut size = 0
    for node in members {
      size += node.encoded_size.unwrap_or(0)
    }
    components.push({
      component_id: indices[0],
      members,
      internal_edges: evidence,
      node_count: indices.length(),
      internal_edge_count: evidence.length(),
      direct_edges: direct,
      reference_edges: reference,
      indirect_edges: indirect,
      local_encoded_bytes: size,
    })
  }
  components.sort_by(fn(a, b) {
    if a.local_encoded_bytes != b.local_encoded_bytes {
      b.local_encoded_bytes - a.local_encoded_bytes
    } else {
      a.component_id - b.component_id
    }
  })
  Ok(components)
}

///|
/// One inventory and one graph build; no analyze, retained, BFS or opcode
/// evidence recovery. build owns decoding; SCC consumes its original edges.
pub fn function_cycles(
  data : Bytes,
) -> Result[FunctionCyclesReport, FunctionCyclesError] {
  let parsed = match parse_module(data) {
    Ok(value) => value
    Err(error) => return Err(CyclesInputError(error))
  }
  let inventory = match path_inventory(data, parsed) {
    Ok(value) => value
    Err(error) => return Err(CyclesInputError(error))
  }
  let graph = match build(data) {
    Ok(value) => value
    Err(error) => return Err(CyclesInputError(error))
  }
  let components = match
    cycles_components(inventory, graph.edges, data.length()) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let mut imported = 0
  let mut local_bytes = 0
  for node in inventory {
    if node.imported {
      imported += 1
    } else {
      local_bytes += node.encoded_size.unwrap_or(0)
    }
  }
  let mut cyclic_nodes = 0
  let mut cyclic_bytes = 0
  for component in components {
    cyclic_nodes += component.node_count
    cyclic_bytes += component.local_encoded_bytes
  }
  Ok({
    file_size: data.length(),
    sha256: experiment_sha256(data),
    function_count: inventory.length(),
    imported_function_count: imported,
    local_function_count: inventory.length() - imported,
    cyclic_function_count: cyclic_nodes,
    non_cyclic_function_count: inventory.length() - cyclic_nodes,
    component_count: components.length(),
    components,
    local_encoded_bytes: local_bytes,
    cyclic_local_encoded_bytes: cyclic_bytes,
    other_local_encoded_bytes: local_bytes - cyclic_bytes,
    graph_complete: is_graph_complete(graph),
    unresolved_count: graph.unresolved_indirect.length(),
    diagnostics: sorted_diagnostics(graph),
    graph_warning: render_graph_warning(graph),
    modeling_scope: function_cycles_scope(),
  })
}
