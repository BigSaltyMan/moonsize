///|
/// A named local definition, preserving its full function index and file range.
pub struct FunctionSearchMatch {
  index : Int
  name : String
  raw_name : String
  module_name : String
  /// Start of the body-length prefix, not the first instruction.
  offset : Int
  body_size : Int
  total_size : Int
  matched_raw_name : Bool
  matched_display_name : Bool
}

///|
pub struct FunctionSearchReport {
  file_size : Int
  sha256 : String
  query : String
  matching_rule : String
  scope : String
  local_function_count : Int
  named_count : Int
  unnamed_count : Int
  match_count : Int
  unmatched_named_count : Int
  matched_body_bytes : Int
  matched_prefix_bytes : Int
  matched_encoded_bytes : Int
  matches : Array[FunctionSearchMatch]
}

///|
pub enum FunctionSearchError {
  InvalidFunctionSearchQuery
  FunctionSearchInputError(WasmError)
}

///|
pub fn describe_function_search_error(error : FunctionSearchError) -> String {
  match error {
    InvalidFunctionSearchQuery =>
      "function search query must not be empty or whitespace-only"
    FunctionSearchInputError(error) => describe_error(error)
  }
}

///|
/// Inspect available local names once, without decoding instructions or a graph.
pub fn search_local_functions(
  data : Bytes,
  query : String,
) -> Result[FunctionSearchReport, FunctionSearchError] {
  if query.trim().is_empty() {
    return Err(InvalidFunctionSearchQuery)
  }
  let parsed = match parse_module(data) {
    Ok(value) => value
    Err(error) => return Err(FunctionSearchInputError(error))
  }
  let stats = match collect_function_stats(parsed, data) {
    Ok(value) => value
    Err(error) => return Err(FunctionSearchInputError(error))
  }
  let matches : Array[FunctionSearchMatch] = []
  let mut named_count = 0
  let mut body_bytes = 0
  let mut prefix_bytes = 0
  let mut encoded_bytes = 0
  for stat in stats {
    let raw = match stat.raw_name {
      None => continue
      Some(value) => value
    }
    named_count += 1
    let matched_raw_name = raw.contains(query)
    let matched_display_name = stat.name.contains(query)
    if !matched_raw_name && !matched_display_name {
      continue
    }
    matches.push({
      index: stat.index,
      name: stat.name,
      raw_name: raw,
      module_name: stat.module_name,
      offset: stat.offset,
      body_size: stat.body_size,
      total_size: stat.total_size,
      matched_raw_name,
      matched_display_name,
    })
    body_bytes += stat.body_size
    prefix_bytes += stat.total_size - stat.body_size
    encoded_bytes += stat.total_size
  }
  matches.sort_by(fn(a, b) {
    if a.total_size != b.total_size {
      b.total_size.compare(a.total_size)
    } else {
      a.index.compare(b.index)
    }
  })
  Ok({
    file_size: data.length(),
    sha256: experiment_sha256(data),
    query,
    matching_rule: "Case-sensitive literal substring in the available raw name or display name; no regex, wildcards, Unicode normalization or path splitting. The query is not trimmed for matching.",
    scope: "Local function definitions only, using existing best-effort name selection and display rules. Imported declarations and export aliases are not searched. Generated unnamed placeholders are excluded; real names equal to (unnamed) are searchable. Names are not unique identities and available names need not cover all definitions. No match does not prove a function is absent. Indices include preceding function imports. Offset points to the body-length prefix. Matched bytes include locals, instructions and actual body-length prefixes, excluding section headers, names and dependency closures; they do not predict removal, recompilation or gzip savings. No graph or instruction decoding. Top limits text only, not search cost. Run subsequent index queries explicitly.",
    local_function_count: stats.length(),
    named_count,
    unnamed_count: stats.length() - named_count,
    match_count: matches.length(),
    unmatched_named_count: named_count - matches.length(),
    matched_body_bytes: body_bytes,
    matched_prefix_bytes: prefix_bytes,
    matched_encoded_bytes: encoded_bytes,
    matches,
  })
}
