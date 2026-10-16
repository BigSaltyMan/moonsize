///|
/// Opaque validated rules. No rule array is exposed outside this package.
struct CompiledBudget {
  rules : Array[BudgetRule]
}

///|
priv struct BudgetRule {
  id : String
  metric : String
  package_name : String?
  mode : String
  max_bytes : Int
}

///|
pub struct BudgetProblem {
  rule_index : Int?
  field : String
  reason : String
}

///|
pub enum BudgetStatus {
  BudgetPassed
  BudgetExceeded
  BudgetUnavailable
} derive(Eq)

///|
pub enum BudgetError {
  BudgetCurrentInput(WasmError)
  BudgetBaselineInput(WasmError)
  BudgetBaselineRequired
}

///|
pub struct BudgetCoverage {
  functions : Int
  function_bytes : Int
  unattributed_functions : Int
  unattributed_bytes : Int
}

///|
pub struct BudgetArtifact {
  sha256 : String
  raw_bytes : Int
  code_bytes : Int
  /// Only measured when requested; errors remain errors.
  gzip : Result[Int, String]?
  coverage : BudgetCoverage?
}

///|
pub struct BudgetRuleResult {
  id : String
  metric : String
  package_name : String?
  mode : String
  current : Int?
  baseline : Int?
  delta : Int?
  max_bytes : Int
  status : BudgetStatus
  reason : String
  /// Observed label presence, to be interpreted together with coverage.
  current_package_present : Bool?
  baseline_package_present : Bool?
}

///|
pub struct BudgetReport {
  config_version : Int
  current : BudgetArtifact
  baseline : BudgetArtifact?
  rules : Array[BudgetRuleResult]
  status : BudgetStatus
  exit_code : Int
}

///|
fn budget_problem(
  problems : Array[BudgetProblem],
  rule : Int?,
  field : String,
  reason : String,
) -> Unit {
  problems.push({ rule_index: rule, field, reason, })
}

///|
fn budget_nonempty(value : Json) -> String? {
  match value {
    String(s) if !s.trim().is_empty() => Some(s)
    _ => None
  }
}

///|
fn budget_integer(value : Json) -> Int? {
  match value {
    Number(n, repr~) if n >= 0.0 && n <= 2147483647.0 => {
      let integer = n.to_int()
      if repr is Some(raw) && parse_path_index(raw) != Some(integer) {
        return None
      }
      if integer.to_double() == n {
        Some(integer)
      } else {
        None
      }
    }
    _ => None
  }
}

///|
fn budget_check_keys(
  value : Json,
  allowed : Array[String],
  index : Int?,
  problems : Array[BudgetProblem],
) -> Unit {
  match value {
    Object(fields) =>
      for key, _ in fields {
        if !allowed.contains(key) {
          budget_problem(problems, index, key, "unknown field")
        }
      }
    _ => budget_problem(problems, index, "object", "expected an object")
  }
}

///|
/// JSON byte thresholds use decimal integer tokens. Check the source too: the
/// generic JSON parser rounds tiny fractional parts when converting to Double.
pub fn compile_budget_text(
  text : String,
) -> Result[CompiledBudget, Array[BudgetProblem]] {
  let config = @json.parse(text) catch {
    error =>
      return Err([
        { rule_index: None, field: "json", reason: error.to_string(), },
      ])
  }
  let compiled = match compile_budget(config) {
    Ok(c) => c
    Err(e) => return Err(e)
  }
  let bytes = @utf8.encode(text)
  let mut at = 0
  let mut key = "number"
  let mut rule_index = 0
  let problems : Array[BudgetProblem] = []
  while at < bytes.length() {
    let byte = bytes[at]
    if byte == b'"' {
      let start = at
      at += 1
      while at < bytes.length() {
        if bytes[at] == b'\\' {
          at += 2
          continue
        }
        if bytes[at] == b'"' {
          at += 1
          break
        }
        at += 1
      }
      let value = @json.parse(@utf8.decode_lossy(bytes[start:at])) catch {
        _ => Json::null()
      }
      if value is String(name) {
        key = name
      }
    } else if is_ascii_digit(byte) || byte == b'-' {
      let start = at
      at += 1
      while at < bytes.length() &&
            (
              is_ascii_digit(bytes[at]) ||
              [b'.', b'e', b'E', b'+', b'-'].contains(bytes[at])
            ) {
        at += 1
      }
      let raw = @utf8.decode_lossy(bytes[start:at])
      if parse_path_index(raw) is None {
        budget_problem(
          problems,
          if key == "max_bytes" {
            Some(rule_index)
          } else {
            None
          },
          key,
          "expected a nonnegative decimal integer token at byte offset " +
          start.to_string(),
        )
      }
      if key == "max_bytes" {
        rule_index += 1
      }
    } else {
      at += 1
    }
  }
  if problems.is_empty() {
    Ok(compiled)
  } else {
    Err(problems)
  }
}

///|
/// Preflight all fields, reporting every configuration problem before I/O.
pub fn compile_budget(
  config : Json,
) -> Result[CompiledBudget, Array[BudgetProblem]] {
  let problems : Array[BudgetProblem] = []
  budget_check_keys(config, ["version", "rules"], None, problems)
  if budget_integer(experiment_get(config, "version")) != Some(1) {
    budget_problem(
      problems,
      None,
      "version",
      "only budget version 1 is supported",
    )
  }
  let rules : Array[BudgetRule] = []
  let ids : Set[String] = Set([])
  match experiment_get(config, "rules") {
    Array(items) if !items.is_empty() =>
      for index, item in items {
        budget_check_keys(
          item,
          ["id", "metric", "mode", "max_bytes", "package"],
          Some(index),
          problems,
        )
        let id = budget_nonempty(experiment_get(item, "id"))
        match id {
          None =>
            budget_problem(
              problems,
              Some(index),
              "id",
              "expected a non-empty unique id",
            )
          Some(id) => {
            if ids.contains(id) {
              budget_problem(
                problems,
                Some(index),
                "id",
                "duplicate rule id: " + id,
              )
            }
            ids.add(id)
          }
        }
        let metric = budget_nonempty(experiment_get(item, "metric"))
        if ![
            Some("file.raw"),
            Some("file.gzip"),
            Some("code.raw"),
            Some("package.raw"),
          ].contains(metric) {
          budget_problem(
            problems,
            Some(index),
            "metric",
            "expected file.raw, file.gzip, code.raw or package.raw",
          )
        }
        let mode = budget_nonempty(experiment_get(item, "mode"))
        if mode != Some("absolute") && mode != Some("growth") {
          budget_problem(
            problems,
            Some(index),
            "mode",
            "expected absolute or growth",
          )
        }
        let maximum = budget_integer(experiment_get(item, "max_bytes"))
        if maximum is None {
          budget_problem(
            problems,
            Some(index),
            "max_bytes",
            "expected an integer from 0 through 2147483647",
          )
        }
        let package_name = budget_nonempty(experiment_get(item, "package"))
        let has_package = match item {
          Object(fields) => fields.contains("package")
          _ => false
        }
        if metric == Some("package.raw") {
          if package_name is None {
            budget_problem(
              problems,
              Some(index),
              "package",
              "package.raw requires a non-empty package label",
            )
          }
        } else if has_package {
          budget_problem(
            problems,
            Some(index),
            "package",
            "package is only allowed for package.raw",
          )
        }
        // This array remains private and is returned only if the entire config is valid.
        rules.push({
          id: id.unwrap_or(""),
          metric: metric.unwrap_or(""),
          package_name,
          mode: mode.unwrap_or(""),
          max_bytes: maximum.unwrap_or(0),
        })
      }
    _ => budget_problem(problems, None, "rules", "expected a non-empty array")
  }
  if problems.is_empty() {
    Ok({ rules, })
  } else {
    Err(problems)
  }
}

///|
pub fn budget_requires_baseline(budget : CompiledBudget) -> Bool {
  budget.rules.any(fn(rule) { rule.mode == "growth" })
}

///|
pub fn describe_budget_error(error : BudgetError) -> String {
  match error {
    BudgetCurrentInput(error) => "current: " + describe_error(error)
    BudgetBaselineInput(error) => "baseline: " + describe_error(error)
    BudgetBaselineRequired => "growth budget rules require --baseline"
  }
}

///|
priv struct BudgetSide {
  artifact : BudgetArtifact
  packages : Map[String, Int]
}

///|
fn budget_unknown_symbol(raw : String) -> Bool {
  let bytes = @utf8.encode(raw)
  let mut at = 0
  while at < bytes.length() && bytes[at] == b'_' {
    at += 1
  }
  at + 1 < bytes.length() &&
  bytes[at] == b'M' &&
  bytes[at + 1] == b'0' &&
  mangled_segments(raw) is None
}

///|
fn budget_side(
  data : Bytes,
  gzip : Bool,
  packages : Bool,
) -> Result[BudgetSide, WasmError] {
  let parsed = match parse_module(data) {
    Ok(p) => p
    Err(e) => return Err(e)
  }
  let totals : Map[String, Int] = Map([])
  let coverage = if packages {
    let stats = match collect_function_stats(parsed, data) {
      Ok(s) => s
      Err(e) => return Err(e)
    }
    let mut bytes = 0
    let mut unknown = 0
    let mut unknown_bytes = 0
    for stat in stats {
      bytes += stat.total_size
      let unassigned = match stat.raw_name {
        None => true
        Some(raw) => budget_unknown_symbol(raw)
      }
      if unassigned {
        unknown += 1
        unknown_bytes += stat.total_size
      }
    }
    for row in aggregate_by_module(stats) {
      totals.set(row.name, row.total_size)
    }
    Some({
      functions: stats.length(),
      function_bytes: bytes,
      unattributed_functions: unknown,
      unattributed_bytes: unknown_bytes,
    })
  } else {
    None
  }
  Ok({
    packages: totals,
    artifact: {
      sha256: experiment_sha256(data),
      raw_bytes: data.length(),
      code_bytes: match find_sections(parsed).code {
        Some(s) => s.total_size
        None => 0
      },
      gzip: if gzip {
        Some(compressed_size(data))
      } else {
        None
      },
      coverage,
    },
  })
}

///|
fn budget_value(
  side : BudgetSide,
  rule : BudgetRule,
  allow_absent : Bool,
) -> Result[Int, String] {
  match rule.metric {
    "file.raw" => Ok(side.artifact.raw_bytes)
    "code.raw" => Ok(side.artifact.code_bytes)
    "file.gzip" =>
      side.artifact.gzip.unwrap_or(Err("whole-file gzip was not measured"))
    "package.raw" => {
      let coverage = side.artifact.coverage.unwrap()
      if coverage.unattributed_functions > 0 {
        return Err(
          "package attribution coverage insufficient: " +
          coverage.unattributed_functions.to_string() +
          " local functions (" +
          coverage.unattributed_bytes.to_string() +
          " B) may belong to the selected package",
        )
      }
      match side.packages.get(rule.package_name.unwrap()) {
        Some(size) => Ok(size)
        None if allow_absent => Ok(0)
        None => Err("package label not found in the required artifact(s)")
      }
    }
    _ => Err("unsupported compiled metric")
  }
}

///|
/// One evaluation per side/metric. No graph, dominators or independent gzip streams.
pub fn evaluate_budget(
  budget : CompiledBudget,
  current_data : Bytes,
  baseline_data? : Bytes,
) -> Result[BudgetReport, BudgetError] {
  let growth = budget_requires_baseline(budget)
  if growth && baseline_data is None {
    return Err(BudgetBaselineRequired)
  }
  let need_gzip = budget.rules.any(fn(r) { r.metric == "file.gzip" })
  let need_package = budget.rules.any(fn(r) { r.metric == "package.raw" })
  let current = match budget_side(current_data, need_gzip, need_package) {
    Ok(side) => side
    Err(e) => return Err(BudgetCurrentInput(e))
  }
  let baseline = if growth {
    match
      budget_side(
        baseline_data.unwrap(),
        budget.rules.any(fn(r) { r.mode == "growth" && r.metric == "file.gzip" }),
        budget.rules.any(fn(r) {
          r.mode == "growth" && r.metric == "package.raw"
        }),
      ) {
      Ok(side) => Some(side)
      Err(e) => return Err(BudgetBaselineInput(e))
    }
  } else {
    None
  }
  Ok(evaluate_budget_sides(budget, current, baseline))
}

///|
/// Kept separate so tests can inject a compressor failure without a production switch.
fn evaluate_budget_sides(
  budget : CompiledBudget,
  current : BudgetSide,
  baseline : BudgetSide?,
) -> BudgetReport {
  let results : Array[BudgetRuleResult] = []
  let mut overall = BudgetPassed
  for rule in budget.rules {
    let before = if rule.mode == "growth" { baseline } else { None }
    let current_present = if rule.metric == "package.raw" {
      Some(current.packages.contains(rule.package_name.unwrap()))
    } else {
      None
    }
    let baseline_present = if rule.metric == "package.raw" &&
      before is Some(side) {
      Some(side.packages.contains(rule.package_name.unwrap()))
    } else {
      None
    }
    let allow_absent = before is Some(_) &&
      (current_present == Some(true) || baseline_present == Some(true))
    let now = budget_value(current, rule, allow_absent)
    let old = match before {
      Some(side) => Some(budget_value(side, rule, allow_absent))
      None => None
    }
    let current_bytes = match now {
      Ok(n) => Some(n)
      Err(_) => None
    }
    let baseline_bytes = match old {
      Some(Ok(n)) => Some(n)
      _ => None
    }
    let delta = match (current_bytes, baseline_bytes) {
      (Some(a), Some(b)) => Some(a - b)
      _ => None
    }
    let reasons : Array[String] = []
    if now is Err(error) {
      reasons.push("current: " + error)
    }
    if old is Some(Err(error)) {
      reasons.push("baseline: " + error)
    }
    let status = if !reasons.is_empty() {
      BudgetUnavailable
    } else {
      let compared = if rule.mode == "growth" {
        delta.unwrap()
      } else {
        current_bytes.unwrap()
      }
      if compared > rule.max_bytes {
        BudgetExceeded
      } else {
        BudgetPassed
      }
    }
    if status == BudgetUnavailable {
      overall = BudgetUnavailable
    } else if status == BudgetExceeded && overall == BudgetPassed {
      overall = BudgetExceeded
    }
    if reasons.is_empty() {
      reasons.push(
        (if rule.mode == "growth" { "current - baseline" } else { "current" }) +
        (if status == BudgetExceeded {
          " exceeds max_bytes"
        } else {
          " is within max_bytes (equality passes)"
        }),
      )
      if current_present == Some(false) && baseline_present == Some(true) {
        reasons.push(
          "label disappeared from the current artifact; this does not prove source-package removal",
        )
      } else if current_present == Some(true) && baseline_present == Some(false) {
        reasons.push("label newly observed in the current artifact")
      }
    }
    results.push({
      id: rule.id,
      metric: rule.metric,
      package_name: rule.package_name,
      mode: rule.mode,
      current: current_bytes,
      baseline: baseline_bytes,
      delta,
      max_bytes: rule.max_bytes,
      status,
      reason: reasons.join("; "),
      current_package_present: current_present,
      baseline_package_present: baseline_present,
    })
  }
  {
    config_version: 1,
    current: current.artifact,
    baseline: baseline.map(fn(side) { side.artifact }),
    rules: results,
    status: overall,
    exit_code: match overall {
      BudgetPassed => 0
      BudgetExceeded => 3
      BudgetUnavailable => 1
    },
  }
}
