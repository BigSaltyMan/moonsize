///|
fn diff_code_json(code : CodeSizeSummary) -> Json {
  let row : Map[String, Json] = Map([])
  row.set("code_size", int_json(code.code_size))
  row.set("function_count", int_json(code.function_count))
  row.set("function_bytes", int_json(code.function_bytes))
  row.set("overhead", int_json(code.overhead))
  Json::object(row)
}

///|
fn diff_stat_json(stat : FunctionStat?) -> Json {
  match stat {
    None => Json::null()
    Some(stat) => {
      let row : Map[String, Json] = Map([])
      row.set("index", int_json(stat.index))
      row.set("name", Json::string(stat.name))
      row.set("raw_name", path_optional_string(stat.raw_name))
      row.set("module_name", Json::string(stat.module_name))
      row.set("offset", int_json(stat.offset))
      row.set("body_size", int_json(stat.body_size))
      row.set("prefix_size", int_json(stat.total_size - stat.body_size))
      row.set("total_size", int_json(stat.total_size))
      Json::object(row)
    }
  }
}

///|
fn diff_coverage_json(coverage : FunctionCoverage) -> Json {
  let row : Map[String, Json] = Map([])
  row.set("count", int_json(coverage.count))
  row.set("bytes", int_json(coverage.bytes))
  Json::object(row)
}

///|
/// Serialize the existing comparison only, with no parsing, matching or graph.
/// Callers must supply SHA-256 strings from exactly the inputs used for diff.
/// Every original row is retained, in the comparison's existing ranked order.
pub fn render_function_diff_json(
  diff : ModuleSizeDiff,
  baseline_sha256 : String,
  current_sha256 : String,
) -> String {
  let root : Map[String, Json] = Map([])
  root.set("format", Json::string("moonsize-function-diff"))
  root.set("schema_version", int_json(1))
  for
    (key, sha, size, code) in [
      ("baseline", baseline_sha256, diff.baseline_size, diff.baseline_code),
      ("current", current_sha256, diff.current_size, diff.current_code),
    ] {
    let side : Map[String, Json] = Map([])
    side.set("sha256", Json::string(sha))
    side.set("file_size", int_json(size))
    side.set("code", diff_code_json(code))
    root.set(key, Json::object(side))
  }
  let delta : Map[String, Json] = Map([])
  delta.set("file_bytes", int_json(diff.delta))
  delta.set(
    "code_bytes",
    int_json(diff.current_code.code_size - diff.baseline_code.code_size),
  )
  delta.set(
    "function_bytes",
    int_json(
      diff.current_code.function_bytes - diff.baseline_code.function_bytes,
    ),
  )
  delta.set(
    "code_overhead_bytes",
    int_json(diff.current_code.overhead - diff.baseline_code.overhead),
  )
  delta.set(
    "non_code_bytes",
    int_json(
      diff.current_size -
      diff.current_code.code_size -
      (diff.baseline_size - diff.baseline_code.code_size),
    ),
  )
  root.set("delta", Json::object(delta))
  let summary = diff.matching
  let matching : Map[String, Json] = Map([])
  for
    (name, coverage) in [
      ("matched_baseline", summary.matched_baseline),
      ("matched_current", summary.matched_current),
      ("added_symbols", summary.added_symbols),
      ("removed_symbols", summary.removed_symbols),
      ("ambiguous_baseline", summary.ambiguous_baseline),
      ("ambiguous_current", summary.ambiguous_current),
      ("missing_baseline", summary.missing_baseline),
      ("missing_current", summary.missing_current),
    ] {
    matching.set(name, diff_coverage_json(coverage))
  }
  matching.set("matched_delta", int_json(summary.matched_delta))
  root.set("matching", Json::object(matching))
  root.set(
    "functions",
    Json::array(
      diff.functions.map(fn(change) {
        let row : Map[String, Json] = Map([])
        row.set("status", Json::string(change_status_text(change.status)))
        row.set("raw_name", path_optional_string(change.raw_name))
        row.set("baseline", diff_stat_json(change.baseline))
        row.set("current", diff_stat_json(change.current))
        row.set("delta", int_json(change.delta))
        Json::object(row)
      }),
    ),
  )
  root.set(
    "packages",
    Json::array(
      diff.packages.map(fn(pkg_row) {
        let row : Map[String, Json] = Map([])
        row.set("name", Json::string(pkg_row.name))
        row.set("baseline_functions", int_json(pkg_row.baseline_functions))
        row.set("current_functions", int_json(pkg_row.current_functions))
        row.set("baseline_size", int_json(pkg_row.baseline_size))
        row.set("current_size", int_json(pkg_row.current_size))
        row.set("delta", int_json(pkg_row.delta))
        Json::object(row)
      }),
    ),
  )
  root.set(
    "scope",
    Json::string(
      "Existing binary-symbol matching rules: only raw symbols unique on both sides are matched; this is not cross-build semantic identity. Single-side symbols do not prove source additions or deletions. Ambiguous and missing names remain unresolved, with one record per function per side; no index, display-name or size fallback. Equal input hashes do not override these states. Indices and offsets locate records only within their respective input; offset starts the body-length prefix. Package attribution is inferred from existing symbol labels, not verified source or third-party dependency ownership. All quantities are raw encoded bytes, delta = current - baseline. Function bytes include locals, instructions and actual length prefixes; code overhead is section-level encoding. Non-code bytes include the file header and all other sections, not error or optimization space. Matched delta explains only the successfully matched subset. No retained, graph completeness, execution frequency, gzip or transfer measurements are computed here. Raw file differences do not predict future source-edit, rebuilt-output or gzip savings. Top limits text only; JSON retains all rows and coverage. Digest arguments must correspond to exactly the inputs used to create this comparison. CLI strict checks the current input graph only, not both graphs; existing max-size with baseline gates file growth, independently of symbol statuses.",
    ),
  )
  Json::object(root).stringify(indent=2) + "\n"
}
