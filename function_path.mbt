///|
/// Limits apply separately to roots/visited nodes, root-source records, indexed
/// edges and BFS edge examinations. Parsing/building the existing graph is not
/// bounded by these query limits; deterministic sorting has its own cost.
pub struct PathLimits {
  max_nodes : Int
  max_edges : Int
  max_depth : Int
}

///|
pub fn PathLimits::new(
  max_nodes? : Int = 100000,
  max_edges? : Int = 1000000,
  max_depth? : Int = 256,
) -> PathLimits {
  { max_nodes, max_edges, max_depth, }
}

///|
pub enum FunctionPathStatus {
  PathFound
  PathNotFound
  PathSearchLimited
} derive(Eq)

///|
pub enum FunctionRootKind {
  ExportRoot
  StartRoot
  ElementRoot
} derive(Eq)

///|
/// Positions are section starts, with export/segment ordinals when available;
/// never presented as member positions or instruction offsets.
pub struct FunctionRootReason {
  function_index : Int
  kind : FunctionRootKind
  name : String?
  section_offset : Int
  ordinal : Int?
  table_index : Int?
  element_mode : String?
}

///|
pub struct FunctionRoot {
  index : Int
  reasons : Array[FunctionRootReason]
}

///|
pub struct FunctionPathNode {
  index : Int
  name : String
  raw_name : String?
  imported : Bool
  /// None for imports, whose function body is not in this file.
  encoded_size : Int?
  import_module : String?
  import_name : String?
}

///|
pub struct FunctionPathStep {
  caller : Int
  callee : Int
  kind : EdgeKind
  opcode : Opcode
  offset : Int
  type_index : Int?
  table_index : Int?
}

///|
pub struct PathSearchStats {
  root_sources : Int
  prepared_roots : Int
  indexed_edges : Int
  visited_nodes : Int
  checked_edges : Int
  max_depth : Int
  phase : String
  limit_reason : String?
}

///|
pub struct FunctionPathReport {
  target : FunctionPathNode
  requested_root : Int?
  /// Canonical model roots, or the bounded prefix if preparation was limited.
  roots : Array[FunctionRoot]
  selected_roots : Array[Int]
  status : FunctionPathStatus
  path_root : Int?
  nodes : Array[FunctionPathNode]
  steps : Array[FunctionPathStep]
  graph_complete : Bool
  diagnostics : Array[GraphDiagnostic]
  graph_warning : String
  limits : PathLimits
  search_stats : PathSearchStats
}

///|
pub enum FunctionPathError {
  PathInputError(WasmError)
  InvalidPathTarget(Int, Int)
  InvalidPathRoot(Int)
  InvalidPathLimits(String)
  InvalidPathRootReference(Int, Int)
  InvalidPathEdgeIndex(Int, Int)
  InvalidPathEdgeEvidence(Int)
}

///|
pub fn describe_function_path_error(error : FunctionPathError) -> String {
  match error {
    PathInputError(error) => describe_error(error)
    InvalidPathTarget(index, count) =>
      "target function index " +
      index.to_string() +
      " is outside the function index space of " +
      count.to_string()
    InvalidPathRoot(index) =>
      "function " + index.to_string() + " is not a valid model root"
    InvalidPathLimits(message) => "invalid path limits: " + message
    InvalidPathRootReference(index, offset) =>
      "invalid root function index " +
      index.to_string() +
      " in section at offset " +
      offset.to_string()
    InvalidPathEdgeIndex(index, offset) =>
      "invalid graph function index " +
      index.to_string() +
      " at instruction offset " +
      offset.to_string()
    InvalidPathEdgeEvidence(offset) =>
      "invalid graph instruction evidence at offset " + offset.to_string()
  }
}

///|
priv struct PathWork {
  limits : PathLimits
  mut root_sources : Int
  mut indexed_edges : Int
  mut visited_nodes : Int
  mut checked_edges : Int
  mut max_depth : Int
  mut phase : String
  mut limit_reason : String?
}

///|
fn path_read_name(reader : Reader) -> Result[String, WasmError] {
  let length = match read_u32_as_int(reader) {
    Ok(n) => n
    Err(e) => return Err(e)
  }
  match reader.read_bytes(length) {
    Ok(bytes) => Ok(@utf8.decode_lossy(bytes))
    Err(e) => Err(e)
  }
}

///|
fn path_inventory(
  data : Bytes,
  parsed : WasmModule,
) -> Result[Array[FunctionPathNode], WasmError] {
  let nodes : Array[FunctionPathNode] = []
  let sections = find_sections(parsed)
  let names = match sections.names {
    Some(section) => parse_name_section(data, section)
    None => None
  }
  if sections.imports is Some(section) {
    let reader = match reader_at_payload(data, section) {
      Ok(r) => r
      Err(e) => return Err(e)
    }
    let count = match read_u32_as_int(reader) {
      Ok(n) => n
      Err(e) => return Err(e)
    }
    for _ in 0..<count {
      let module_name = match path_read_name(reader) {
        Ok(n) => n
        Err(e) => return Err(e)
      }
      let field = match path_read_name(reader) {
        Ok(n) => n
        Err(e) => return Err(e)
      }
      let is_function = match skip_import_desc(reader) {
        Ok(f) => f
        Err(e) => return Err(e)
      }
      if is_function {
        let index = nodes.length()
        let raw_name = match names {
          Some(names) =>
            match names.get(index) {
              Some(name) if !name.is_empty() => Some(name)
              _ => None
            }
          None => None
        }
        nodes.push({
          index,
          raw_name,
          name: match raw_name {
            Some(raw) => display_name(raw)
            None => module_name + "." + field
          },
          imported: true,
          encoded_size: None,
          import_module: Some(module_name),
          import_name: Some(field),
        })
      }
    }
    match finish_section(reader, Import) {
      Ok(_) => ()
      Err(e) => return Err(e)
    }
  }
  let stats = match collect_function_stats(parsed, data) {
    Ok(stats) => stats
    Err(e) => return Err(e)
  }
  for stat in stats {
    nodes.push({
      index: stat.index,
      name: stat.name,
      raw_name: stat.raw_name,
      imported: false,
      encoded_size: Some(stat.total_size),
      import_module: None,
      import_name: None,
    })
  }
  Ok(nodes)
}

///|
fn add_path_root(
  roots : Map[Int, Array[FunctionRootReason]],
  reason : FunctionRootReason,
  count : Int,
  work : PathWork,
) -> Result[Bool, FunctionPathError] {
  if reason.function_index < 0 || reason.function_index >= count {
    return Err(
      InvalidPathRootReference(reason.function_index, reason.section_offset),
    )
  }
  if work.root_sources >= work.limits.max_edges {
    work.limit_reason = Some("root-source-limit")
    return Ok(false)
  }
  work.root_sources += 1
  match roots.get(reason.function_index) {
    Some(reasons) => {
      // Repeated references to one function in the same element segment carry
      // identical evidence; exports with different ordinals remain distinct.
      let previous = reasons[reasons.length() - 1]
      if !(reason.kind == ElementRoot &&
        previous.kind == ElementRoot &&
        previous.section_offset == reason.section_offset &&
        previous.ordinal == reason.ordinal) {
        reasons.push(reason)
      }
    }
    None => {
      if roots.length() >= work.limits.max_nodes {
        work.limit_reason = Some("root-limit")
        return Ok(false)
      }
      roots.set(reason.function_index, [reason])
    }
  }
  Ok(true)
}

///|
fn path_roots(
  data : Bytes,
  parsed : WasmModule,
  count : Int,
  work : PathWork,
) -> Result[Map[Int, Array[FunctionRootReason]], FunctionPathError] {
  let roots : Map[Int, Array[FunctionRootReason]] = Map([])
  let sections = find_sections(parsed)
  if sections.exports is Some(section) {
    let exports = match parse_export_section(data, section) {
      Ok(v) => v
      Err(e) => return Err(PathInputError(e))
    }
    for ordinal, item in exports {
      if item.kind == 0 {
        let more = match
          add_path_root(
            roots,
            {
              function_index: item.index,
              kind: ExportRoot,
              name: Some(item.name),
              section_offset: section.offset,
              ordinal: Some(ordinal),
              table_index: None,
              element_mode: None,
            },
            count,
            work,
          ) {
          Ok(more) => more
          Err(e) => return Err(e)
        }
        if !more {
          return Ok(roots)
        }
      }
    }
  }
  if sections.start is Some(section) {
    let index = match parse_start_section(data, section) {
      Ok(v) => v
      Err(e) => return Err(PathInputError(e))
    }
    let more = match
      add_path_root(
        roots,
        {
          function_index: index,
          kind: StartRoot,
          name: None,
          section_offset: section.offset,
          ordinal: None,
          table_index: None,
          element_mode: None,
        },
        count,
        work,
      ) {
      Ok(v) => v
      Err(e) => return Err(e)
    }
    if !more {
      return Ok(roots)
    }
  }
  if sections.elements is Some(section) {
    let elements = match parse_element_section(data, section) {
      Ok(v) => v
      Err(e) => return Err(PathInputError(e))
    }
    for ordinal, segment in elements {
      for index in segment.functions {
        let more = match
          add_path_root(
            roots,
            {
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
            },
            count,
            work,
          ) {
          Ok(v) => v
          Err(e) => return Err(e)
        }
        if !more {
          return Ok(roots)
        }
      }
    }
  }
  Ok(roots)
}

///|
fn path_edge_rank(kind : EdgeKind) -> Int {
  match kind {
    Direct => 0
    Reference => 1
    Indirect => 2
  }
}

///|
fn path_adjacency(
  data : Bytes,
  graph : CallGraph,
  count : Int,
  work : PathWork,
) -> Result[Map[Int, Array[FunctionPathStep]], FunctionPathError] {
  let adjacency : Map[Int, Array[FunctionPathStep]] = Map([])
  let decoded : Map[Int, Instruction] = Map([])
  for edge in graph.edges {
    if work.indexed_edges >= work.limits.max_edges {
      work.limit_reason = Some("edge-index-limit")
      return Ok(adjacency)
    }
    work.indexed_edges += 1
    for index in [edge.caller, edge.callee] {
      if index < 0 || index >= count {
        return Err(InvalidPathEdgeIndex(index, edge.offset))
      }
    }
    let instruction = match decoded.get(edge.offset) {
      Some(i) => i
      None => {
        let i = match decode_instruction(data, edge.offset) {
          Ok(i) => i
          Err(e) => return Err(PathInputError(e))
        }
        decoded.set(edge.offset, i)
        i
      }
    }
    let (type_index, table_index) = match (edge.kind, instruction.opcode) {
      (Direct, Call | ReturnCall) | (Reference, RefFunc) => (None, None)
      (Indirect, CallIndirect | ReturnCallIndirect) =>
        (Some(instruction.operands[0]), Some(instruction.operands[1]))
      _ => return Err(InvalidPathEdgeEvidence(edge.offset))
    }
    let step : FunctionPathStep = {
      caller: edge.caller,
      callee: edge.callee,
      kind: edge.kind,
      opcode: instruction.opcode,
      offset: edge.offset,
      type_index,
      table_index,
    }
    match adjacency.get(edge.caller) {
      Some(edges) => edges.push(step)
      None => adjacency.set(edge.caller, [step])
    }
  }
  for _, edges in adjacency {
    edges.sort_by(fn(a, b) {
      let target = a.callee - b.callee
      if target != 0 {
        return target
      }
      let kind = path_edge_rank(a.kind) - path_edge_rank(b.kind)
      if kind != 0 {
        kind
      } else {
        a.offset - b.offset
      }
    })
  }
  Ok(adjacency)
}

///|
fn path_report(
  inventory : Array[FunctionPathNode],
  target : Int,
  requested_root : Int?,
  roots : Map[Int, Array[FunctionRootReason]],
  selected : Array[Int],
  graph : CallGraph,
  work : PathWork,
  status : FunctionPathStatus,
  nodes : Array[FunctionPathNode],
  steps : Array[FunctionPathStep],
) -> FunctionPathReport {
  let ledger : Array[FunctionRoot] = []
  for index, reasons in roots {
    ledger.push({ index, reasons, })
  }
  ledger.sort_by(fn(a, b) { a.index - b.index })
  {
    target: inventory[target],
    requested_root,
    roots: ledger,
    selected_roots: selected,
    status,
    path_root: if nodes.is_empty() {
      None
    } else {
      Some(nodes[0].index)
    },
    nodes,
    steps,
    graph_complete: is_graph_complete(graph),
    diagnostics: sorted_diagnostics(graph),
    graph_warning: render_graph_warning(graph),
    limits: work.limits,
    search_stats: {
      root_sources: work.root_sources,
      prepared_roots: roots.length(),
      indexed_edges: work.indexed_edges,
      visited_nodes: work.visited_nodes,
      checked_edges: work.checked_edges,
      max_depth: work.max_depth,
      phase: work.phase,
      limit_reason: work.limit_reason,
    },
  }
}

///|
/// A deterministic shortest reference-model path. Builds a canonical graph from
/// bytes without computing dominators. Never changes global roots or graph gaps.
pub fn explain_function(
  data : Bytes,
  target_index : Int,
  root? : Int,
  limits? : PathLimits,
) -> Result[FunctionPathReport, FunctionPathError] {
  let limits = limits.unwrap_or(PathLimits::new())
  if limits.max_nodes <= 0 || limits.max_edges < 0 || limits.max_depth < 0 {
    return Err(
      InvalidPathLimits(
        "nodes must be positive; edges and depth must be nonnegative",
      ),
    )
  }
  let parsed = match parse_module(data) {
    Ok(v) => v
    Err(e) => return Err(PathInputError(e))
  }
  let inventory = match path_inventory(data, parsed) {
    Ok(v) => v
    Err(e) => return Err(PathInputError(e))
  }
  if target_index < 0 || target_index >= inventory.length() {
    return Err(InvalidPathTarget(target_index, inventory.length()))
  }
  if root is Some(index) && (index < 0 || index >= inventory.length()) {
    return Err(InvalidPathRoot(index))
  }
  let graph = match build(data) {
    Ok(v) => v
    Err(e) => return Err(PathInputError(e))
  }
  let work : PathWork = {
    limits,
    root_sources: 0,
    indexed_edges: 0,
    visited_nodes: 0,
    checked_edges: 0,
    max_depth: 0,
    phase: "root-preparation",
    limit_reason: None,
  }
  let roots = match path_roots(data, parsed, inventory.length(), work) {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  let selected = match root {
    Some(index) => [index]
    None => roots.keys().to_array()
  }
  selected.sort_by(fn(a, b) { a - b })
  if work.limit_reason is Some(_) {
    return Ok(
      path_report(
        inventory,
        target_index,
        root,
        roots,
        [],
        graph,
        work,
        PathSearchLimited,
        [],
        [],
      ),
    )
  }
  if root is Some(index) && !roots.contains(index) {
    return Err(InvalidPathRoot(index))
  }
  work.phase = "edge-index"
  let adjacency = match path_adjacency(data, graph, inventory.length(), work) {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  if work.limit_reason is Some(_) {
    return Ok(
      path_report(
        inventory,
        target_index,
        root,
        roots,
        selected,
        graph,
        work,
        PathSearchLimited,
        [],
        [],
      ),
    )
  }
  work.phase = "search"
  let visited : Set[Int] = Set([])
  let parent : Map[Int, FunctionPathStep] = Map([])
  let queue : Array[(Int, Int)] = []
  for index in selected {
    visited.add(index)
    queue.push((index, 0))
  }
  work.visited_nodes = visited.length()
  let mut found = visited.contains(target_index)
  let mut depth_cut = false
  let mut at = 0
  while !found && at < queue.length() {
    let (caller, depth) = queue[at]
    at += 1
    let edges = adjacency.get(caller).unwrap_or([])
    for edge in edges {
      if work.checked_edges >= limits.max_edges {
        work.limit_reason = Some("edge-limit")
        break
      }
      work.checked_edges += 1
      if visited.contains(edge.callee) {
        continue
      }
      if depth >= limits.max_depth {
        depth_cut = true
        continue
      }
      if work.visited_nodes >= limits.max_nodes {
        work.limit_reason = Some("node-limit")
        break
      }
      visited.add(edge.callee)
      work.visited_nodes += 1
      work.max_depth = depth + 1
      parent.set(edge.callee, edge)
      queue.push((edge.callee, depth + 1))
      if edge.callee == target_index {
        found = true
        break
      }
    }
    if work.limit_reason is Some(_) {
      break
    }
  }
  if found {
    let nodes : Array[FunctionPathNode] = [inventory[target_index]]
    let steps : Array[FunctionPathStep] = []
    let mut cursor = target_index
    while parent.get(cursor) is Some(step) {
      steps.push(step)
      cursor = step.caller
      nodes.push(inventory[cursor])
    }
    for i in 0..<(nodes.length() / 2) {
      let other = nodes.length() - 1 - i
      let saved = nodes[i]
      nodes[i] = nodes[other]
      nodes[other] = saved
    }
    for i in 0..<(steps.length() / 2) {
      let other = steps.length() - 1 - i
      let saved = steps[i]
      steps[i] = steps[other]
      steps[other] = saved
    }
    work.phase = "complete"
    return Ok(
      path_report(
        inventory,
        target_index,
        root,
        roots,
        selected,
        graph,
        work,
        PathFound,
        nodes,
        steps,
      ),
    )
  }
  if depth_cut && work.limit_reason is None {
    work.limit_reason = Some("depth-limit")
  }
  let status = if work.limit_reason is Some(_) {
    PathSearchLimited
  } else {
    work.phase = "complete"
    PathNotFound
  }
  Ok(
    path_report(
      inventory,
      target_index,
      root,
      roots,
      selected,
      graph,
      work,
      status,
      [],
      [],
    ),
  )
}
