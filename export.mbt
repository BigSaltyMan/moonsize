///|
/// Machine-readable exports of the call graph.
///
/// The text reports answer "what is big"; these answer "what points at what", so
/// the graph can be looked at rather than read. Both formats are written by hand
/// because a symbol name comes out of the binary being analysed and has to be
/// escaped for the format it lands in, not for a convenience printer.

///|
/// The hex digit for a value in `0..16`.
fn hex_digit(value : Int) -> String {
  if value < 10 {
    value.to_string()
  } else {
    match value {
      10 => "a"
      11 => "b"
      12 => "c"
      13 => "d"
      14 => "e"
      _ => "f"
    }
  }
}

///|
/// The characters a JSON string has to escape, or `""` for a byte that can be
/// copied through.
fn json_escape(byte : Byte) -> String {
  if byte == b'"' {
    "\\\""
  } else if byte == b'\\' {
    "\\\\"
  } else if byte == b'\n' {
    "\\n"
  } else if byte == b'\r' {
    "\\r"
  } else if byte == b'\t' {
    "\\t"
  } else if byte < 0x20 {
    "\\u00" + hex_digit(byte.to_int() / 16) + hex_digit(byte.to_int() % 16)
  } else {
    ""
  }
}

///|
/// The characters a double-quoted DOT label has to escape.
fn dot_escape(byte : Byte) -> String {
  if byte == b'"' {
    "\\\""
  } else if byte == b'\\' {
    "\\\\"
  } else {
    ""
  }
}

///|
/// Escape and quote `text` for JSON.
///
/// Bytes are copied in runs rather than one at a time, so a name that carries
/// multi-byte UTF-8 survives instead of being shredded into replacement
/// characters.
fn quote(text : String, escape : (Byte) -> String) -> String {
  let bytes = @utf8.encode(text)
  let mut out = "\""
  let mut run = 0
  let mut i = 0
  while i < bytes.length() {
    let replacement = escape(bytes[i])
    if replacement.length() > 0 {
      if run < i {
        out = out + @utf8.decode_lossy(bytes[run:i])
      }
      out = out + replacement
      run = i + 1
    }
    i = i + 1
  }
  if run < bytes.length() {
    out = out + @utf8.decode_lossy(bytes[run:bytes.length()])
  }
  out + "\""
}

///|
/// True when an edge was supplied by a table rather than named outright.
fn is_indirect(kind : EdgeKind) -> Bool {
  match kind {
    Indirect => true
    _ => false
  }
}

///|
/// The name to print for an index, falling back to the bare index.
fn export_name(names : Map[Int, String], index : Int) -> String {
  match names.get(index) {
    Some(name) => name
    None => "fn" + index.to_string()
  }
}

///|
/// Render the call graph as Graphviz DOT.
///
/// Dead functions are drawn dashed, which is what makes the picture useful: the
/// solid part is the program, the dashed part is what could be deleted. Indirect
/// edges are dotted, because they are candidates rather than certainties.
pub fn render_dot(
  stats : Array[FunctionStat],
  graph : CallGraph,
  reachable : Set[Int],
) -> String {
  let names : Map[Int, String] = Map([])
  let sizes : Map[Int, Int] = Map([])
  for stat in stats {
    names.set(stat.index, stat.name)
    sizes.set(stat.index, stat.total_size)
  }
  let mut out = "digraph moonsize {\n  rankdir=LR;\n" +
    "  node [shape=box, fontname=\"monospace\", fontsize=10];\n"
  for stat in stats {
    let label = quote(
      export_name(names, stat.index) +
      "\\n" +
      stat.total_size.to_string() +
      " B",
      dot_escape,
    )
    let dead = if reachable.contains(stat.index) {
      ""
    } else {
      ", style=dashed"
    }
    out = out +
      "  " +
      quote(stat.index.to_string(), dot_escape) +
      " [label=" +
      label +
      dead +
      "];\n"
  }
  for edge in graph.edges {
    let kind = match edge.kind {
      Direct => "call"
      Indirect => "indirect"
      Reference => "ref"
    }
    out = out +
      "  " +
      quote(edge.caller.to_string(), dot_escape) +
      " -> " +
      quote(edge.callee.to_string(), dot_escape) +
      " [label=\"" +
      kind +
      "\"" +
      (if is_indirect(edge.kind) { ", style=dotted" } else { "" }) +
      "];\n"
  }
  out + "}\n"
}

///|
/// Render the call graph, the roots and the retained sizes as JSON.
pub fn render_json(
  path : String,
  stats : Array[FunctionStat],
  graph : CallGraph,
  roots : Set[Int],
  reachable : Set[Int],
  retained : Array[RetainedSize],
) -> String {
  let by_index : Map[Int, RetainedSize] = Map([])
  for entry in retained {
    by_index.set(entry.index, entry)
  }
  let mut out = "{\n  \"module\": " + quote(path, json_escape) + ",\n"
  out = out + "  \"functions\": [\n"
  let mut first = true
  for stat in stats {
    if !first {
      out = out + ",\n"
    }
    first = false
    let retention = match by_index.get(stat.index) {
      Some(entry) =>
        ",\"retained\":" +
        entry.retained.to_string() +
        ",\"retained_functions\":" +
        entry.retained_functions.to_string()
      None => ""
    }
    out = out +
      "    {\"index\":" +
      stat.index.to_string() +
      ",\"name\":" +
      quote(stat.name, json_escape) +
      ",\"module\":" +
      quote(stat.module_name, json_escape) +
      ",\"body_size\":" +
      stat.body_size.to_string() +
      ",\"size\":" +
      stat.total_size.to_string() +
      ",\"reachable\":" +
      (if reachable.contains(stat.index) { "true" } else { "false" }) +
      retention +
      "}"
  }
  out = out + "\n  ],\n  \"roots\": ["
  out = out + join_indices(roots)
  out = out + "],\n  \"edges\": [\n"
  first = true
  for edge in graph.edges {
    if !first {
      out = out + ",\n"
    }
    first = false
    let kind = match edge.kind {
      Direct => "direct"
      Indirect => "indirect"
      Reference => "reference"
    }
    out = out +
      "    {\"caller\":" +
      edge.caller.to_string() +
      ",\"callee\":" +
      edge.callee.to_string() +
      ",\"kind\":\"" +
      kind +
      "\",\"offset\":" +
      edge.offset.to_string() +
      "}"
  }
  out = out + "\n  ],\n  \"indirect_sites\": [\n"
  first = true
  for site in graph.indirect_sites {
    if !first {
      out = out + ",\n"
    }
    first = false
    let candidates : Set[Int] = Set([])
    for candidate in site.candidates {
      candidates.add(candidate)
    }
    out = out +
      "    {\"caller\":" +
      site.caller.to_string() +
      ",\"table\":" +
      site.table_index.to_string() +
      ",\"type\":" +
      site.type_index.to_string() +
      ",\"offset\":" +
      site.offset.to_string() +
      ",\"candidates\":" +
      array_of_indices(candidates) +
      "}"
  }
  out = out + "\n  ]\n}\n"
  out
}

///|
/// A JSON array of the indices in a set, sorted so two runs agree.
fn array_of_indices(values : Set[Int]) -> String {
  let sorted = values.to_array()
  sorted.sort()
  let mut out = "["
  let mut i = 0
  while i < sorted.length() {
    if i > 0 {
      out = out + ","
    }
    out = out + sorted[i].to_string()
    i = i + 1
  }
  out + "]"
}

///|
/// A comma-separated list of the indices in a set, sorted.
fn join_indices(values : Set[Int]) -> String {
  let sorted = values.to_array()
  sorted.sort()
  let mut out = ""
  let mut i = 0
  while i < sorted.length() {
    if i > 0 {
      out = out + ","
    }
    out = out + sorted[i].to_string()
    i = i + 1
  }
  out
}

///|
/// Render a graph export, choosing the format from the target file's extension.
///
/// The extension is the only signal available and the one a user already thinks
/// in: `.json` means JSON, anything else means DOT, which is what Graphviz
/// tooling expects from a file called `graph.dot`.
pub fn render_graph(
  path : String,
  analysis : Analysis,
  target : String,
) -> String {
  if has_json_extension(target) {
    render_json(
      path,
      analysis.stats,
      analysis.graph,
      analysis.roots,
      analysis.reachable,
      analysis.retained,
    )
  } else {
    render_dot(analysis.stats, analysis.graph, analysis.reachable)
  }
}

///|
/// True when a path ends in `.json`, ignoring case.
fn has_json_extension(path : String) -> Bool {
  let bytes = @utf8.encode(path)
  if bytes.length() < 5 {
    return false
  }
  let extension = bytes[bytes.length() - 5:bytes.length()]
  let wanted = @utf8.encode(".json")
  let mut i = 0
  while i < 5 {
    if lower_ascii(extension[i]) != wanted[i] {
      return false
    }
    i = i + 1
  }
  true
}

///|
/// Fold an ASCII byte to lower case, leaving everything else alone.
fn lower_ascii(byte : Byte) -> Byte {
  if byte >= b'A' && byte <= b'Z' {
    byte + 32
  } else {
    byte
  }
}
