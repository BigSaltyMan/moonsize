///|
/// Which input failed structural parsing or function-size collection.
pub enum ComparisonError {
  Baseline(WasmError)
  Current(WasmError)
}

///|
/// Symbol changes describe binary identities, not source additions/deletions.
/// Ambiguous and missing symbols have one record per function per side.
pub enum FunctionMatchStatus {
  Matched
  AddedSymbol
  RemovedSymbol
  AmbiguousSymbol
  MissingSymbol
} derive(Eq)

///|
pub struct FunctionSizeChange {
  status : FunctionMatchStatus
  raw_name : String?
  baseline : FunctionStat?
  current : FunctionStat?
  /// Current total_size minus baseline total_size; absent sides contribute zero.
  delta : Int
}

///|
/// Best-effort package attribution includes every local function, even unmatched.
pub struct PackageSizeChange {
  name : String
  baseline_functions : Int
  current_functions : Int
  baseline_size : Int
  current_size : Int
  delta : Int
}

///|
pub struct FunctionCoverage {
  count : Int
  bytes : Int
}

///|
/// Disjoint per-side categories. Missing/ambiguous are the unmatched reasons;
/// neither category is also counted as an added or removed symbol.
pub struct MatchingSummary {
  matched_baseline : FunctionCoverage
  matched_current : FunctionCoverage
  added_symbols : FunctionCoverage
  removed_symbols : FunctionCoverage
  ambiguous_baseline : FunctionCoverage
  ambiguous_current : FunctionCoverage
  missing_baseline : FunctionCoverage
  missing_current : FunctionCoverage
  matched_delta : Int
}

///|
pub struct CodeSizeSummary {
  code_size : Int
  function_count : Int
  function_bytes : Int
  /// Section header and function-count encoding; not attributed to a function.
  overhead : Int
}

///|
/// All sizes are raw encoded bytes. Function/package sums explain local function
/// encoding, not file deltas (name/data/etc. remain in the section comparison).
/// Records are ranked by absolute delta, then raw symbol/package identity.
pub struct ModuleSizeDiff {
  baseline_size : Int
  current_size : Int
  delta : Int
  baseline_code : CodeSizeSummary
  current_code : CodeSizeSummary
  functions : Array[FunctionSizeChange]
  packages : Array[PackageSizeChange]
  matching : MatchingSummary
}

///|
fn symbols_by_name(
  stats : Array[FunctionStat],
) -> Map[String, Array[FunctionStat]] {
  let symbols : Map[String, Array[FunctionStat]] = Map([])
  for stat in stats {
    if stat.raw_name is Some(name) {
      match symbols.get(name) {
        Some(items) => items.push(stat)
        None => symbols.set(name, [stat])
      }
    }
  }
  symbols
}

///|
fn symbol_count(
  symbols : Map[String, Array[FunctionStat]],
  name : String,
) -> Int {
  match symbols.get(name) {
    Some(items) => items.length()
    None => 0
  }
}

///|
fn stat_size(stat : FunctionStat?) -> Int {
  match stat {
    Some(stat) => stat.total_size
    None => 0
  }
}

///|
fn size_change(
  status : FunctionMatchStatus,
  baseline : FunctionStat?,
  current : FunctionStat?,
) -> FunctionSizeChange {
  {
    status,
    raw_name: match baseline {
      Some(stat) => stat.raw_name
      None =>
        match current {
          Some(stat) => stat.raw_name
          None => None
        }
    },
    baseline,
    current,
    delta: stat_size(current) - stat_size(baseline),
  }
}

///|
fn change_status_text(status : FunctionMatchStatus) -> String {
  match status {
    Matched => "matched"
    AddedSymbol => "added-symbol"
    RemovedSymbol => "removed-symbol"
    AmbiguousSymbol => "ambiguous"
    MissingSymbol => "missing-symbol"
  }
}

///|
fn delta_magnitude(delta : Int) -> Int {
  if delta < 0 {
    -delta
  } else {
    delta
  }
}

///|
fn raw_identity_compare(a : String?, b : String?) -> Int {
  match (a, b) {
    (Some(a), Some(b)) => diff_identity_compare(a, b)
    (None, None) => 0
    (None, _) => -1
    (_, None) => 1
  }
}

///|
/// Case-sensitive UTF-16 lexical ordering, independent of locale and Map order.
/// The toolchain's String::compare orders by length first, so spell this out.
fn diff_identity_compare(a : String, b : String) -> Int {
  let mut i = 0
  while i < a.length() && i < b.length() {
    if a[i] < b[i] {
      return -1
    }
    if a[i] > b[i] {
      return 1
    }
    i += 1
  }
  a.length() - b.length()
}

///|
fn change_index(stat : FunctionStat?) -> Int {
  match stat {
    Some(stat) => stat.index
    None => -1
  }
}

///|
fn compare_function_changes(
  a : FunctionSizeChange,
  b : FunctionSizeChange,
) -> Int {
  let size = delta_magnitude(b.delta) - delta_magnitude(a.delta)
  if size != 0 {
    return size
  }
  let identity = raw_identity_compare(a.raw_name, b.raw_name)
  if identity != 0 {
    return identity
  }
  let status = String::compare(
    change_status_text(a.status),
    change_status_text(b.status),
  )
  if status != 0 {
    return status
  }
  // Index is only a final ordering key within an identity/status, never a match.
  let baseline = change_index(a.baseline) - change_index(b.baseline)
  if baseline != 0 {
    baseline
  } else {
    change_index(a.current) - change_index(b.current)
  }
}

///|
fn category_coverage(
  changes : Array[FunctionSizeChange],
  status : FunctionMatchStatus,
  baseline : Bool,
) -> FunctionCoverage {
  let mut count = 0
  let mut bytes = 0
  for row in changes {
    if row.status == status {
      let stat = if baseline { row.baseline } else { row.current }
      if stat is Some(stat) {
        count += 1
        bytes += stat.total_size
      }
    }
  }
  { count, bytes, }
}

///|
fn code_size_summary(
  parsed : WasmModule,
  stats : Array[FunctionStat],
) -> CodeSizeSummary {
  let code_size = match find_sections(parsed).code {
    Some(section) => section.total_size
    None => 0
  }
  let mut function_bytes = 0
  for stat in stats {
    function_bytes += stat.total_size
  }
  {
    code_size,
    function_count: stats.length(),
    function_bytes,
    overhead: code_size - function_bytes,
  }
}

///|
fn compare_packages(
  baseline : Array[FunctionStat],
  current : Array[FunctionStat],
) -> Array[PackageSizeChange] {
  let before : Map[String, ModuleStat] = Map([])
  let after : Map[String, ModuleStat] = Map([])
  let names : Set[String] = Set([])
  for row in aggregate_by_module(baseline) {
    before.set(row.name, row)
    names.add(row.name)
  }
  for row in aggregate_by_module(current) {
    after.set(row.name, row)
    names.add(row.name)
  }
  let rows : Array[PackageSizeChange] = []
  for name in names {
    let (baseline_functions, baseline_size) = match before.get(name) {
      Some(row) => (row.functions, row.total_size)
      None => (0, 0)
    }
    let (current_functions, current_size) = match after.get(name) {
      Some(row) => (row.functions, row.total_size)
      None => (0, 0)
    }
    rows.push({
      name,
      baseline_functions,
      current_functions,
      baseline_size,
      current_size,
      delta: current_size - baseline_size,
    })
  }
  rows.sort_by(fn(a, b) {
    let delta = delta_magnitude(b.delta) - delta_magnitude(a.delta)
    if delta != 0 {
      delta
    } else {
      diff_identity_compare(a.name, b.name)
    }
  })
  rows
}

///|
/// Validate both inputs and collect raw symbols and encoded function sizes.
/// This does not build either call graph or require graph completeness. It is
/// basic structure checking, not full Wasm type/instruction validation.
pub fn compare_modules(
  baseline_data : Bytes,
  current_data : Bytes,
) -> Result[ModuleSizeDiff, ComparisonError] {
  let baseline = match parse_module(baseline_data) {
    Ok(parsed) => parsed
    Err(error) => return Err(Baseline(error))
  }
  let current = match parse_module(current_data) {
    Ok(parsed) => parsed
    Err(error) => return Err(Current(error))
  }
  let before = match collect_function_stats(baseline, baseline_data) {
    Ok(stats) => stats
    Err(error) => return Err(Baseline(error))
  }
  let after = match collect_function_stats(current, current_data) {
    Ok(stats) => stats
    Err(error) => return Err(Current(error))
  }
  let before_names = symbols_by_name(before)
  let after_names = symbols_by_name(after)
  let changes : Array[FunctionSizeChange] = []
  for stat in before {
    match stat.raw_name {
      None => changes.push(size_change(MissingSymbol, Some(stat), None))
      Some(name) =>
        if symbol_count(before_names, name) > 1 ||
          symbol_count(after_names, name) > 1 {
          changes.push(size_change(AmbiguousSymbol, Some(stat), None))
        } else if symbol_count(after_names, name) == 0 {
          changes.push(size_change(RemovedSymbol, Some(stat), None))
        } else {
          changes.push(
            size_change(Matched, Some(stat), Some(after_names[name][0])),
          )
        }
    }
  }
  for stat in after {
    match stat.raw_name {
      None => changes.push(size_change(MissingSymbol, None, Some(stat)))
      Some(name) =>
        if symbol_count(before_names, name) > 1 ||
          symbol_count(after_names, name) > 1 {
          changes.push(size_change(AmbiguousSymbol, None, Some(stat)))
        } else if symbol_count(before_names, name) == 0 {
          changes.push(size_change(AddedSymbol, None, Some(stat)))
        }
    }
  }
  changes.sort_by(compare_function_changes)
  let matched_baseline = category_coverage(changes, Matched, true)
  let matched_current = category_coverage(changes, Matched, false)
  Ok({
    baseline_size: baseline.file_size,
    current_size: current.file_size,
    delta: current.file_size - baseline.file_size,
    baseline_code: code_size_summary(baseline, before),
    current_code: code_size_summary(current, after),
    functions: changes,
    packages: compare_packages(before, after),
    matching: {
      matched_baseline,
      matched_current,
      added_symbols: category_coverage(changes, AddedSymbol, false),
      removed_symbols: category_coverage(changes, RemovedSymbol, true),
      ambiguous_baseline: category_coverage(changes, AmbiguousSymbol, true),
      ambiguous_current: category_coverage(changes, AmbiguousSymbol, false),
      missing_baseline: category_coverage(changes, MissingSymbol, true),
      missing_current: category_coverage(changes, MissingSymbol, false),
      matched_delta: matched_current.bytes - matched_baseline.bytes,
    },
  })
}
