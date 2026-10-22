///|
pub struct FunctionCallerGroup {
  caller : FunctionPathNode
  sources : Array[FunctionPathStep]
}

///|
/// Complete recorded one-hop instruction sources, without reachability filtering.
pub struct FunctionCallersReport {
  target : FunctionPathNode
  file_size : Int
  sha256 : String
  callers : Array[FunctionCallerGroup]
  caller_count : Int
  source_count : Int
  graph_complete : Bool
  diagnostics : Array[GraphDiagnostic]
  graph_warning : String
  modeling_scope : String
}

///|
pub enum FunctionCallersError {
  CallersInputError(WasmError)
  InvalidCallersTarget(Int, Int)
  InvalidCallersEvidence(Int, String)
}

///|
pub fn describe_function_callers_error(error : FunctionCallersError) -> String {
  match error {
    CallersInputError(error) => describe_error(error)
    InvalidCallersTarget(index, count) =>
      "target function index " +
      index.to_string() +
      " is outside the function index space of " +
      count.to_string()
    InvalidCallersEvidence(offset, reason) =>
      "invalid incoming instruction evidence at file offset " +
      offset.to_string() +
      ": " +
      reason
  }
}

///|
fn function_callers_scope() -> String {
  "All one-hop instruction references recorded in the current model, including sources in unreachable functions. " +
  "Direct calls, references taken and indirect candidates are distinct; these are not execution traces or predictions of recompiled or gzip savings. " +
  "Exports, start and element roots are not incoming body instructions; use --why-index to explain model roots. " +
  "Diagnostics describe the whole module and need not concern this target. graph_complete does not prove full semantics or removability. " +
  "Top only limits displayed caller groups, not parsing or graph-building costs. " +
  graph_modeling_scope()
}

///|
/// Only matching offsets need evidence decoding; shared offsets are cached.
fn callers_sources(
  data : Bytes,
  graph : CallGraph,
  inventory : Array[FunctionPathNode],
  target : Int,
) -> Result[Array[FunctionPathStep], FunctionCallersError] {
  let sources : Array[FunctionPathStep] = []
  let decoded : Map[Int, Instruction] = Map([])
  for edge in graph.edges {
    if edge.callee != target {
      continue
    }
    if edge.caller < 0 ||
      edge.caller >= inventory.length() ||
      inventory[edge.caller].imported {
      return Err(
        InvalidCallersEvidence(edge.offset, "invalid body caller index"),
      )
    }
    let instruction = match decoded.get(edge.offset) {
      Some(instruction) => instruction
      None => {
        let instruction = match decode_instruction(data, edge.offset) {
          Ok(instruction) => instruction
          Err(error) =>
            return Err(
              InvalidCallersEvidence(edge.offset, describe_error(error)),
            )
        }
        decoded.set(edge.offset, instruction)
        instruction
      }
    }
    let (type_index, table_index) = match (edge.kind, instruction.opcode) {
      (Direct, Call | ReturnCall) | (Reference, RefFunc) => {
        if instruction.operands.length() != 1 ||
          instruction.operands[0] != target {
          return Err(
            InvalidCallersEvidence(
              edge.offset,
              "target operand does not match edge",
            ),
          )
        }
        (None, None)
      }
      (Indirect, CallIndirect | ReturnCallIndirect) => {
        if instruction.operands.length() != 2 {
          return Err(
            InvalidCallersEvidence(edge.offset, "missing type or table index"),
          )
        }
        (Some(instruction.operands[0]), Some(instruction.operands[1]))
      }
      _ =>
        return Err(
          InvalidCallersEvidence(edge.offset, "opcode does not match edge kind"),
        )
    }
    sources.push({
      caller: edge.caller,
      callee: edge.callee,
      kind: edge.kind,
      opcode: instruction.opcode,
      offset: edge.offset,
      type_index,
      table_index,
    })
  }
  sources.sort_by(fn(a, b) {
    let caller = a.caller - b.caller
    if caller != 0 {
      return caller
    }
    let offset = a.offset - b.offset
    if offset != 0 {
      offset
    } else {
      path_edge_rank(a.kind) - path_edge_rank(b.kind)
    }
  })
  let unique : Array[FunctionPathStep] = []
  for source in sources {
    if !unique.is_empty() {
      let previous = unique[unique.length() - 1]
      // Target is fixed; cached instruction determines opcode/type/table.
      if previous.caller == source.caller &&
        previous.offset == source.offset &&
        path_edge_rank(previous.kind) == path_edge_rank(source.kind) {
        continue
      }
    }
    unique.push(source)
  }
  Ok(unique)
}

///|
/// Parse, inventory and build directly. No analyze, dominators, BFS or truncation.
pub fn function_callers(
  data : Bytes,
  target_index : Int,
) -> Result[FunctionCallersReport, FunctionCallersError] {
  let parsed = match parse_module(data) {
    Ok(parsed) => parsed
    Err(error) => return Err(CallersInputError(error))
  }
  let inventory = match path_inventory(data, parsed) {
    Ok(inventory) => inventory
    Err(error) => return Err(CallersInputError(error))
  }
  if target_index < 0 || target_index >= inventory.length() {
    return Err(InvalidCallersTarget(target_index, inventory.length()))
  }
  let graph = match build(data) {
    Ok(graph) => graph
    Err(error) => return Err(CallersInputError(error))
  }
  let sources = match callers_sources(data, graph, inventory, target_index) {
    Ok(sources) => sources
    Err(error) => return Err(error)
  }
  let groups : Array[FunctionCallerGroup] = []
  for source in sources {
    if !groups.is_empty() &&
      groups[groups.length() - 1].caller.index == source.caller {
      groups[groups.length() - 1].sources.push(source)
    } else {
      groups.push({ caller: inventory[source.caller], sources: [source], })
    }
  }
  Ok({
    target: inventory[target_index],
    file_size: data.length(),
    sha256: experiment_sha256(data),
    callers: groups,
    caller_count: groups.length(),
    source_count: sources.length(),
    graph_complete: is_graph_complete(graph),
    diagnostics: sorted_diagnostics(graph),
    graph_warning: render_graph_warning(graph),
    modeling_scope: function_callers_scope(),
  })
}
