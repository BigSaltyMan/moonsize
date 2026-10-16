///|
fn budget_status_text(status : BudgetStatus) -> String {
  match status {
    BudgetPassed => "passed"
    BudgetExceeded => "exceeded"
    BudgetUnavailable => "unavailable"
  }
}

///|
fn budget_scope() -> String {
  "All sizes are bytes. Equality passes; growth compares current - baseline. " +
  "file.gzip measures the entire file as one gzip stream with the current bikallem/compress defaults, not server transfer cost. " +
  "code.raw includes its section header and count encoding. package.raw sums local function total_size under the existing symbol attribution; " +
  "it is not total source-package cost or predicted deletion savings. Unknown attribution makes a package rule unavailable."
}

///|
fn budget_number(value : Int?) -> String {
  match value {
    Some(n) => n.to_string()
    None => "-"
  }
}

///|
fn budget_artifact_json(artifact : BudgetArtifact, path : String?) -> Json {
  Json::object({
    "path": path_optional_string(path),
    "sha256": Json::string(artifact.sha256),
    "raw_bytes": int_json(artifact.raw_bytes),
    "code_bytes": int_json(artifact.code_bytes),
    "whole_gzip_bytes": match artifact.gzip {
      Some(result) => gzip_json(result)
      None => Json::null()
    },
    "gzip_error": match artifact.gzip {
      Some(result) => gzip_error_json(result)
      None => Json::null()
    },
    "attribution": match artifact.coverage {
      None => Json::null()
      Some(c) =>
        Json::object({
          "functions": int_json(c.functions),
          "function_bytes": int_json(c.function_bytes),
          "unattributed_functions": int_json(c.unattributed_functions),
          "unattributed_bytes": int_json(c.unattributed_bytes),
          "complete_within_symbol_model": Json::boolean(
            c.unattributed_functions == 0,
          ),
        })
    },
  })
}

///|
fn budget_bool(value : Bool?) -> Json {
  match value {
    Some(value) => Json::boolean(value)
    None => Json::null()
  }
}

///|
pub fn render_budget_json(
  report : BudgetReport,
  current_path : String,
  baseline_path? : String,
) -> String {
  Json::object({
    "format": Json::string("moonsize-budget"),
    "schema_version": int_json(1),
    "config_version": int_json(report.config_version),
    "status": Json::string(budget_status_text(report.status)),
    "exit_code": int_json(report.exit_code),
    "current": budget_artifact_json(report.current, Some(current_path)),
    "baseline": match report.baseline {
      Some(side) => budget_artifact_json(side, baseline_path)
      None => Json::null()
    },
    "compression": Json::string(
      "whole file, one gzip stream; bikallem/compress current defaults; independent streams are never added",
    ),
    "scope": Json::string(budget_scope()),
    "rules": Json::array(
      report.rules.map(fn(rule) {
        Json::object({
          "id": Json::string(rule.id),
          "metric": Json::string(rule.metric),
          "package": path_optional_string(rule.package_name),
          "mode": Json::string(rule.mode),
          "current": optional_index_json(rule.current),
          "baseline": optional_index_json(rule.baseline),
          "delta": optional_index_json(rule.delta),
          "max_bytes": int_json(rule.max_bytes),
          "status": Json::string(budget_status_text(rule.status)),
          "reason": Json::string(rule.reason),
          "current_package_present": budget_bool(rule.current_package_present),
          "baseline_package_present": budget_bool(rule.baseline_package_present),
        })
      }),
    ),
  }).stringify(indent=2) +
  "\n"
}

///|
/// Escape untrusted table content without allowing HTML, Markdown or line injection.
fn budget_md(text : String) -> String {
  html_escape(text)
  .replace(old="|", new="&#124;")
  .replace(old="`", new="&#96;")
  .replace(old="\\", new="&#92;")
  .replace(old="\r", new="&#13;")
  .replace(old="\n", new="&#10;")
  .replace(old="*", new="&#42;")
  .replace(old="_", new="&#95;")
  .replace(old="[", new="&#91;")
  .replace(old="]", new="&#93;")
}

///|
pub fn render_budget_markdown(
  report : BudgetReport,
  current_path : String,
  baseline_path? : String,
) -> String {
  let out = StringBuilder()
  out.write_string(
    "## Size budget: " + budget_status_text(report.status) + "\n\n",
  )
  out.write_string(
    "| Rule | Metric / package | Mode | Current B | Baseline B | Delta B | Limit B | Status | Reason |\n",
  )
  out.write_string(
    "| --- | --- | --- | ---: | ---: | ---: | ---: | --- | --- |\n",
  )
  for r in report.rules {
    let label = r.metric +
      (match r.package_name {
        Some(name) => " / " + name
        None => ""
      })
    out.write_string(
      "| " +
      budget_md(r.id) +
      " | " +
      budget_md(label) +
      " | " +
      r.mode +
      " | " +
      budget_number(r.current) +
      " | " +
      budget_number(r.baseline) +
      " | " +
      budget_number(r.delta) +
      " | " +
      r.max_bytes.to_string() +
      " | " +
      budget_status_text(r.status) +
      " | " +
      budget_md(r.reason) +
      " |\n",
    )
  }
  out.write_string(
    "\nCurrent: " +
    budget_md(current_path) +
    "; SHA-256: " +
    report.current.sha256 +
    "\n",
  )
  if report.baseline is Some(side) {
    out.write_string(
      "\nBaseline: " +
      budget_md(baseline_path.unwrap_or("(path not supplied)")) +
      "; SHA-256: " +
      side.sha256 +
      "\n",
    )
  }
  for
    (label, side) in [
      ("Current", Some(report.current)),
      ("Baseline", report.baseline),
    ] {
    if side is Some(artifact) && artifact.coverage is Some(c) {
      out.write_string(
        "\n" +
        label +
        " attribution: " +
        c.unattributed_functions.to_string() +
        " / " +
        c.functions.to_string() +
        " local functions unassigned (" +
        c.unattributed_bytes.to_string() +
        " B). Package presence is observed, not proof of complete coverage.\n",
      )
    }
  }
  out.write_string(
    "\nExit code: " +
    report.exit_code.to_string() +
    ".\n\n" +
    budget_scope() +
    "\n",
  )
  out.to_string()
}

///|
pub fn render_budget(report : BudgetReport) -> String {
  let out = StringBuilder()
  out.write_string(
    "SIZE BUDGET\n\n  Values in bytes; delta = current - baseline.\n",
  )
  out.write_string(
    "  RULE / METRIC / MODE / CURRENT / BASELINE / DELTA / LIMIT / STATUS\n",
  )
  for r in report.rules {
    out.write_string(
      "  " +
      Json::string(r.id).stringify() +
      " / " +
      r.metric +
      " / " +
      r.mode +
      " / " +
      budget_number(r.current) +
      " / " +
      budget_number(r.baseline) +
      " / " +
      budget_number(r.delta) +
      " / " +
      r.max_bytes.to_string() +
      " / " +
      budget_status_text(r.status) +
      "\n",
    )
    if r.package_name is Some(name) {
      out.write_string("    package: " + Json::string(name).stringify() + "\n")
    }
    out.write_string("    " + Json::string(r.reason).stringify() + "\n")
  }
  out.write_string(
    "\nOverall: " +
    budget_status_text(report.status) +
    "; exit code " +
    report.exit_code.to_string() +
    "\n" +
    budget_scope() +
    "\n",
  )
  out.to_string()
}
