///|
/// The reference graph between functions, and what deleting one of them frees.
///
/// The model follows Twiggy: a module is a graph of functions rooted at whatever
/// the outside world can reach — exported functions, the start function and
/// everything the element sections hand to the host or to `call_indirect`. What
/// is not reachable from those roots can never run, and what is only reachable
/// through one function dies with it.

///|
/// How one function refers to another.
pub enum EdgeKind {
  /// `call x`: the target is named outright.
  Direct
  /// `call_indirect`: the target comes out of a table at run time.
  Indirect
  /// `ref.func x`: a reference taken without calling, as when building a
  /// closure. The function may well run later, so it counts as reachable.
  Reference
}

///|
/// One edge of the call graph.
pub struct CallEdge {
  caller : Int
  callee : Int
  kind : EdgeKind
  /// Offset of the instruction that makes the reference.
  offset : Int
}

///|
/// A `call_indirect`, with the targets its table could supply.
pub struct IndirectSite {
  caller : Int
  /// Table the call reads.
  table_index : Int
  /// Signature the call selects on.
  type_index : Int
  /// Offset of the `call_indirect` instruction.
  offset : Int
  /// Every function any element segment places in that table. Conservative by
  /// construction: the table's contents are not known statically, so a missing
  /// candidate would mean a missing edge, and a missing edge would mean a
  /// function wrongly called dead.
  candidates : Array[Int]
}

///|
/// The reference graph between functions.
pub struct CallGraph {
  /// Outgoing references by function index.
  calls : Map[Int, Set[Int]]
  /// Incoming references by function index.
  called_by : Map[Int, Set[Int]]
  /// Every `call_indirect`, with the candidates its table allows.
  indirect_sites : Array[IndirectSite]
  /// Every edge with its kind and site, for export.
  edges : Array[CallEdge]
}

///|
/// The functions an element segment puts in a table, merged over every segment
/// that targets it.
fn table_functions(elements : Array[ElementSegment], table : Int) -> Array[Int] {
  let seen : Set[Int] = Set([])
  for segment in elements {
    if segment.table_index == table {
      for function in segment.functions {
        seen.add(function)
      }
    }
  }
  seen.to_array()
}

///|
/// Build the call graph of a module.
///
/// Every body is decoded once: `call` gives a precise edge, `ref.func` gives a
/// reference edge, and `call_indirect` gives one conservative edge per function
/// its table can hold plus a record of the site itself.
pub fn build(
  data : Bytes,
  bodies : Array[FunctionBody],
  elements : Array[ElementSegment],
) -> Result[CallGraph, WasmError] {
  let calls : Map[Int, Set[Int]] = Map([])
  let called_by : Map[Int, Set[Int]] = Map([])
  let edges : Array[CallEdge] = []
  let sites : Array[IndirectSite] = []
  for body in bodies {
    let start = body.offset + body.total_size - body.body_size
    let instructions = match decode_instructions(data, start, body.body_size) {
      Ok(instructions) => instructions
      Err(error) => return Err(error)
    }
    for instruction in instructions {
      match instruction.opcode {
        Call =>
          add_edge(
            calls,
            called_by,
            edges,
            body.index,
            instruction.operands[0],
            Direct,
            instruction.offset,
          )
        RefFunc =>
          add_edge(
            calls,
            called_by,
            edges,
            body.index,
            instruction.operands[0],
            Reference,
            instruction.offset,
          )
        CallIndirect => {
          let type_index = instruction.operands[0]
          let table_index = instruction.operands[1]
          let candidates = table_functions(elements, table_index)
          sites.push({
            caller: body.index,
            table_index,
            type_index,
            offset: instruction.offset,
            candidates,
          })
          for candidate in candidates {
            add_edge(
              calls,
              called_by,
              edges,
              body.index,
              candidate,
              Indirect,
              instruction.offset,
            )
          }
        }
        _ => ()
      }
    }
  }
  Ok({ calls, called_by, indirect_sites: sites, edges, })
}

///|
/// Record one edge in both directions.
fn add_edge(
  calls : Map[Int, Set[Int]],
  called_by : Map[Int, Set[Int]],
  edges : Array[CallEdge],
  caller : Int,
  callee : Int,
  kind : EdgeKind,
  offset : Int,
) -> Unit {
  outgoing(calls, caller).add(callee)
  outgoing(called_by, callee).add(caller)
  edges.push({ caller, callee, kind, offset, })
}

///|
/// The adjacency set for a node, created on first use.
fn outgoing(map : Map[Int, Set[Int]], node : Int) -> Set[Int] {
  match map.get(node) {
    Some(set) => set
    None => {
      let set : Set[Int] = Set([])
      map.set(node, set)
      set
    }
  }
}

///|
/// Everything reachable from `roots`, the roots included.
///
/// An explicit stack rather than recursion: real modules nest thousands of calls
/// deep, and the depth of the graph should not be the depth of the C stack.
pub fn reachable_from_roots(graph : CallGraph, roots : Set[Int]) -> Set[Int] {
  let seen : Set[Int] = Set([])
  let stack : Array[Int] = []
  for root in roots {
    if !seen.contains(root) {
      seen.add(root)
      stack.push(root)
    }
  }
  while stack.length() > 0 {
    let node = stack[stack.length() - 1]
    let _ = stack.pop()
    match graph.calls.get(node) {
      Some(targets) =>
        for target in targets {
          if !seen.contains(target) {
            seen.add(target)
            stack.push(target)
          }
        }
      None => ()
    }
  }
  seen
}

///|
/// The roots of a module: what the outside world can reach without going through
/// code the module already has.
///
/// Exported functions are the module's public surface, the start function runs
/// at instantiation, and anything an element section puts in a table can be
/// called from outside or through `call_indirect`.
pub fn roots_of(
  exports : Array[Export],
  elements : Array[ElementSegment],
  start : Int?,
) -> Set[Int] {
  let roots : Set[Int] = Set([])
  for item in exports {
    if item.kind == 0 {
      roots.add(item.index)
    }
  }
  for segment in elements {
    for function in segment.functions {
      roots.add(function)
    }
  }
  match start {
    Some(index) => roots.add(index)
    None => ()
  }
  roots
}

///|
/// The functions any `call_indirect` could reach, for labelling report rows.
pub fn indirect_targets(graph : CallGraph) -> Set[Int] {
  let targets : Set[Int] = Set([])
  for site in graph.indirect_sites {
    for candidate in site.candidates {
      targets.add(candidate)
    }
  }
  targets
}

///|
/// What deleting one function would free.
pub struct RetainedSize {
  index : Int
  /// The function's own encoded bytes, its size prefix included.
  own_size : Int
  /// Bytes freed by deleting it: its own bytes plus every function that becomes
  /// unreachable with it.
  retained : Int
  /// How many other functions die with it.
  retained_functions : Int
}

///|
/// Walk to the common dominator of two nodes, using reverse-postorder numbers as
/// the fingers of the classic algorithm.
fn intersect(a : Int, b : Int, idom : Array[Int], order : Array[Int]) -> Int {
  let mut x = a
  let mut y = b
  while x != y {
    while order[x] > order[y] {
      x = idom[x]
    }
    while order[y] > order[x] {
      y = idom[y]
    }
  }
  x
}

///|
/// The retained size of every reachable function.
///
/// Deleting a function makes exactly the functions it *dominates* unreachable:
/// those every path from a root has to pass through. Computing that with an
/// explicit "remove it and see what dies" walk would be correct but quadratic,
/// and it would still need cycle handling; the dominator tree answers the same
/// question for every function at once, and cycles fall out of the fixpoint
/// without a special case.
pub fn retained_sizes(
  graph : CallGraph,
  sizes : Map[Int, Int],
  roots : Set[Int],
) -> Array[RetainedSize] {
  let reachable = reachable_from_roots(graph, roots)
  // Only functions with a body have a size, and only those can be dominators.
  let nodes : Array[Int] = []
  for node in reachable {
    if sizes.get(node) is Some(_) {
      nodes.push(node)
    }
  }
  let count = nodes.length()
  let id_of : Map[Int, Int] = Map([])
  let mut i = 0
  while i < count {
    id_of.set(nodes[i], i)
    i = i + 1
  }
  // A virtual root above the real ones, so a graph with several entry points
  // still has a single dominator tree.
  let root_id = count
  let total = count + 1
  let successors : Array[Array[Int]] = []
  let predecessors : Array[Array[Int]] = []
  let mut i = 0
  while i < total {
    successors.push([])
    predecessors.push([])
    i = i + 1
  }
  for node in nodes {
    let from = match id_of.get(node) {
      Some(id) => id
      None => continue
    }
    match graph.calls.get(node) {
      Some(targets) =>
        for target in targets {
          match id_of.get(target) {
            Some(to) => {
              successors[from].push(to)
              predecessors[to].push(from)
            }
            None => ()
          }
        }
      None => ()
    }
  }
  for node in nodes {
    match id_of.get(node) {
      Some(id) =>
        if roots.contains(node) {
          successors[root_id].push(id)
          predecessors[id].push(root_id)
        }
      None => ()
    }
  }
  // Reverse postorder from the virtual root, iteratively.
  let visited : Array[Bool] = Array::make(total, false)
  let next_edge : Array[Int] = Array::make(total, 0)
  let stack : Array[Int] = [root_id]
  visited[root_id] = true
  let postorder : Array[Int] = []
  while stack.length() > 0 {
    let node = stack[stack.length() - 1]
    if next_edge[node] < successors[node].length() {
      let target = successors[node][next_edge[node]]
      next_edge[node] = next_edge[node] + 1
      if !visited[target] {
        visited[target] = true
        stack.push(target)
      }
    } else {
      postorder.push(node)
      let _ = stack.pop()
    }
  }
  let order : Array[Int] = Array::make(total, 0)
  let reverse : Array[Int] = []
  let mut i = postorder.length() - 1
  while i >= 0 {
    order[postorder[i]] = reverse.length()
    reverse.push(postorder[i])
    i = i - 1
  }
  let idom : Array[Int] = Array::make(total, -1)
  idom[root_id] = root_id
  let mut changed = true
  while changed {
    changed = false
    let mut i = 1
    while i < reverse.length() {
      let node = reverse[i]
      let mut candidate = -1
      for predecessor in predecessors[node] {
        if idom[predecessor] != -1 {
          candidate = if candidate == -1 {
            predecessor
          } else {
            intersect(predecessor, candidate, idom, order)
          }
        }
      }
      if candidate != -1 && idom[node] != candidate {
        idom[node] = candidate
        changed = true
      }
      i = i + 1
    }
  }
  let retained : Array[Int] = Array::make(total, 0)
  let dominated : Array[Int] = Array::make(total, 0)
  for node in nodes {
    match id_of.get(node) {
      Some(id) => {
        retained[id] = match sizes.get(node) {
          Some(size) => size
          None => 0
        }
        dominated[id] = 1
      }
      None => ()
    }
  }
  // Walk the reverse postorder backwards: every node is settled before the
  // dominator it hands its total to.
  let mut i = reverse.length() - 1
  while i > 0 {
    let node = reverse[i]
    retained[idom[node]] = retained[idom[node]] + retained[node]
    dominated[idom[node]] = dominated[idom[node]] + dominated[node]
    i = i - 1
  }
  let out : Array[RetainedSize] = []
  for node in nodes {
    match id_of.get(node) {
      Some(id) =>
        out.push({
          index: node,
          own_size: match sizes.get(node) {
            Some(size) => size
            None => 0
          },
          retained: retained[id],
          retained_functions: dominated[id] - 1,
        })
      None => ()
    }
  }
  out
}
