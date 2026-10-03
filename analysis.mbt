///|
/// The pipeline: one pass over a parsed module that produces everything the
/// reports need.
///
/// The section table, the function sizes and the call graph all read the same
/// bytes, and the graph has to decode the bodies anyway, so they are gathered
/// together rather than re-parsed per report.

///|
/// A parsed module with its sizes, call graph and reachability resolved.
pub struct Analysis {
  /// The bytes the module was parsed from. Reports that measure a piece of the
  /// file on its own — the compression view — need the actual bytes, not just
  /// where they are.
  data : Bytes
  parsed : WasmModule
  stats : Array[FunctionStat]
  graph : CallGraph
  /// Where reachability starts: exports, the start function, table contents.
  roots : Set[Int]
  /// Everything the roots can reach.
  reachable : Set[Int]
  /// What deleting each reachable function would free.
  retained : Array[RetainedSize]
  /// Functions a `call_indirect` could reach.
  indirect : Set[Int]
}

///|
/// Analyse a module: names and sizes, then the call graph and what it implies.
pub fn analyze(
  data : Bytes,
  parsed : WasmModule,
) -> Result[Analysis, WasmError] {
  let sections = find_sections(parsed)
  let imported = match sections.imports {
    Some(section) =>
      match count_imported_functions(data, section) {
        Ok(count) => count
        Err(error) => return Err(error)
      }
    None => 0
  }
  let bodies = match sections.code {
    Some(section) =>
      match parse_code_section(data, section, base_index=imported) {
        Ok(bodies) => bodies
        Err(error) => return Err(error)
      }
    None => []
  }
  let names = match sections.names {
    Some(section) => parse_name_section(data, section)
    None => None
  }
  let stats = function_stats(bodies, names)
  let elements = match sections.elements {
    Some(section) =>
      match parse_element_section(data, section) {
        Ok(segments) => segments
        Err(error) => return Err(error)
      }
    None => []
  }
  let exports = match sections.exports {
    Some(section) =>
      match parse_export_section(data, section) {
        Ok(exports) => exports
        Err(error) => return Err(error)
      }
    None => []
  }
  let start = match sections.start {
    Some(section) =>
      match parse_start_section(data, section) {
        Ok(index) => Some(index)
        Err(error) => return Err(error)
      }
    None => None
  }
  let graph = match build(data, bodies, elements) {
    Ok(graph) => graph
    Err(error) => return Err(error)
  }
  let roots = roots_of(exports, elements, start)
  let reachable = reachable_from_roots(graph, roots)
  let sizes : Map[Int, Int] = Map([])
  for stat in stats {
    sizes.set(stat.index, stat.total_size)
  }
  Ok({
    data,
    parsed,
    stats,
    graph,
    roots,
    reachable,
    retained: retained_sizes(graph, sizes, roots),
    indirect: indirect_targets(graph),
  })
}
