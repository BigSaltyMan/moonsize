///|
/// Optimization experiments compare supplied artifacts. Build and validation
/// declarations are evidence supplied by the caller, never commands to execute.
fn experiment_get(value : Json, key : String) -> Json {
  match value {
    Object(fields) => fields.get(key).unwrap_or(Json::null())
    _ => Json::null()
  }
}

///|
fn experiment_keys(
  value : Json,
  keys : Array[String],
  path : String,
) -> Result[Unit, String] {
  guard value is Object(fields) else {
    return Err(path + ": expected an object")
  }
  for key, _ in fields {
    if !keys.contains(key) {
      return Err(path + "." + key + ": unknown field")
    }
  }
  Ok(())
}

///|
fn experiment_string(
  value : Json,
  key : String,
  path : String,
) -> Result[Unit, String] {
  match experiment_get(value, key) {
    String(text) if text.length() > 0 => Ok(())
    _ => Err(path + "." + key + ": expected a non-empty string")
  }
}

///|
/// Validate optional context before reading Wasm inputs or creating output.
/// Null means no context was recorded. Unknown fields fail rather than silently
/// accepting a typo in a build setting or validation declaration.
pub fn check_experiment_context(context : Json) -> Result[Unit, String] {
  if context is Null {
    return Ok(())
  }
  match
    experiment_keys(
      context,
      ["title", "hypothesis", "baseline", "current", "validation"],
      "context",
    ) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  for key in ["title", "hypothesis"] {
    match experiment_string(context, key, "context") {
      Err(error) => return Err(error)
      Ok(_) => ()
    }
  }
  for side in ["baseline", "current"] {
    let build = experiment_get(context, side)
    let path = "context." + side
    match
      experiment_keys(
        build,
        [
          "revision", "command", "toolchain", "target", "mode", "strip", "features",
        ],
        path,
      ) {
      Err(error) => return Err(error)
      Ok(_) => ()
    }
    for key in ["revision", "command", "toolchain", "target", "mode"] {
      match experiment_string(build, key, path) {
        Err(error) => return Err(error)
        Ok(_) => ()
      }
    }
    match experiment_get(build, "strip") {
      True | False => ()
      _ => return Err(path + ".strip: expected a boolean")
    }
    match experiment_get(build, "features") {
      Array(features) =>
        for feature in features {
          match feature {
            String(text) if text.length() > 0 => ()
            _ => return Err(path + ".features: expected non-empty strings")
          }
        }
      _ => return Err(path + ".features: expected an array")
    }
  }
  let validation = experiment_get(context, "validation")
  match
    experiment_keys(
      validation,
      ["status", "command", "notes"],
      "context.validation",
    ) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  match experiment_get(validation, "status") {
    String("passed" | "failed" | "not-run") => ()
    _ =>
      return Err(
        "context.validation.status: expected passed, failed or not-run",
      )
  }
  for key in ["command", "notes"] {
    match experiment_get(validation, key) {
      String(_) => ()
      _ => return Err("context.validation." + key + ": expected a string")
    }
  }
  if experiment_get(validation, "status") != Json::string("not-run") {
    match experiment_string(validation, "command", "context.validation") {
      Err(error) => return Err(error)
      Ok(_) => ()
    }
  }
  Ok(())
}

///|
fn experiment_sha256(data : Bytes) -> String {
  let digits = b"0123456789abcdef"
  let out = StringBuilder()
  for byte in @crypto.sha256(data) {
    let n = byte.to_int()
    out.write_string(
      @utf8.decode_lossy(Bytes::from_array([digits[n / 16], digits[n % 16]])),
    )
  }
  out.to_string()
}

///|
fn experiment_artifact(analysis : Analysis, path : String) -> Json {
  let gzip = compressed_size(analysis.data)
  Json::object({
    "path": Json::string(path),
    "sha256": Json::string(experiment_sha256(analysis.data)),
    "raw_bytes": int_json(analysis.data.length()),
    "whole_gzip_bytes": gzip_json(gzip),
    "gzip_error": gzip_error_json(gzip),
    "graph_complete": Json::boolean(analysis.graph_complete),
    "diagnostics": diagnostics_json(analysis.graph),
  })
}

///|
fn experiment_code(summary : CodeSizeSummary) -> Json {
  Json::object({
    "section_bytes": int_json(summary.code_size),
    "function_count": int_json(summary.function_count),
    "function_bytes": int_json(summary.function_bytes),
    "overhead_bytes": int_json(summary.overhead),
  })
}

///|
fn experiment_coverage(coverage : FunctionCoverage) -> Json {
  Json::object({
    "count": int_json(coverage.count),
    "bytes": int_json(coverage.bytes),
  })
}

///|
fn experiment_stat(stat : FunctionStat?) -> Json {
  match stat {
    None => Json::null()
    Some(stat) =>
      Json::object({
        "index": int_json(stat.index),
        "encoded_bytes": int_json(stat.total_size),
      })
  }
}

///|
/// Compare two artifacts, retaining both graph diagnostics and measured deltas.
/// Deltas are current minus baseline. Function identity is raw-symbol based;
/// missing/duplicate names remain unmatched. Context is explicitly self-reported.
/// This neither rebuilds code nor establishes behavioral equivalence.
pub fn experiment_report(
  baseline_data : Bytes,
  current_data : Bytes,
  baseline_path : String,
  current_path : String,
  context : Json,
  top? : Int = DEFAULT_TOP,
) -> Result[Json, String] {
  if top < 0 {
    return Err("experiment: top must be non-negative")
  }
  match check_experiment_context(context) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  let diff = match compare_modules(baseline_data, current_data) {
    Ok(diff) => diff
    Err(Baseline(error)) => return Err("baseline: " + describe_error(error))
    Err(Current(error)) => return Err("current: " + describe_error(error))
  }
  let before = match parse_module(baseline_data) {
    Ok(parsed) =>
      match analyze(baseline_data, parsed) {
        Ok(analysis) => analysis
        Err(error) => return Err("baseline: " + describe_error(error))
      }
    Err(error) => return Err("baseline: " + describe_error(error))
  }
  let after = match parse_module(current_data) {
    Ok(parsed) =>
      match analyze(current_data, parsed) {
        Ok(analysis) => analysis
        Err(error) => return Err("current: " + describe_error(error))
      }
    Err(error) => return Err("current: " + describe_error(error))
  }
  let baseline = experiment_artifact(before, baseline_path)
  let current = experiment_artifact(after, current_path)
  let gzip_delta = match
    (
      experiment_get(baseline, "whole_gzip_bytes"),
      experiment_get(current, "whole_gzip_bytes"),
    ) {
    (Number(b, ..), Number(a, ..)) => int_json((a - b).to_int())
    _ => Json::null()
  }
  let mismatches : Array[Json] = []
  if !(context is Null) {
    let b = experiment_get(context, "baseline")
    let a = experiment_get(context, "current")
    for key in ["command", "toolchain", "target", "mode", "strip", "features"] {
      if experiment_get(b, key) != experiment_get(a, key) {
        mismatches.push(Json::string(key))
      }
    }
  }
  let functions : Array[Json] = []
  for i = 0; i < diff.functions.length() && i < top; i = i + 1 {
    let row = diff.functions[i]
    functions.push(
      Json::object({
        "status": Json::string(change_status_text(row.status)),
        "raw_name": match row.raw_name {
          Some(name) => Json::string(name)
          None => Json::null()
        },
        "baseline": experiment_stat(row.baseline),
        "current": experiment_stat(row.current),
        "delta": int_json(row.delta),
      }),
    )
  }
  let packages : Array[Json] = []
  for i = 0; i < diff.packages.length() && i < top; i = i + 1 {
    let row = diff.packages[i]
    packages.push(
      Json::object({
        "name": Json::string(row.name),
        "baseline_bytes": int_json(row.baseline_size),
        "current_bytes": int_json(row.current_size),
        "baseline_functions": int_json(row.baseline_functions),
        "current_functions": int_json(row.current_functions),
        "delta": int_json(row.delta),
      }),
    )
  }
  let sections : Array[Json] = []
  for row in size_rows(before.parsed, after.parsed) {
    sections.push(
      Json::object({
        "label": Json::string(row.label),
        "baseline_bytes": int_json(row.baseline),
        "current_bytes": int_json(row.current),
        "delta": int_json(row.current - row.baseline),
      }),
    )
  }
  let summary = diff.matching
  Ok(
    Json::object({
      "schema_version": int_json(1),
      "kind": Json::string("moonsize-optimization-experiment"),
      "producer": Json::string("BigSaltyMan/moonsize"),
      "gzip_configuration": Json::string(
        "bikallem/compress gzip.compress defaults; one complete artifact per stream",
      ),
      "delta_convention": Json::string(
        "current minus baseline; negative means fewer bytes",
      ),
      "baseline": baseline,
      "current": current,
      "raw_delta": int_json(diff.delta),
      "whole_gzip_delta": gzip_delta,
      "baseline_code": experiment_code(diff.baseline_code),
      "current_code": experiment_code(diff.current_code),
      "context": context,
      "context_provenance": Json::string(
        "Self-reported; moonsize did not execute builds or business validation.",
      ),
      "build_comparability": Json::string(
        if context is Null {
          "not-recorded"
        } else if mismatches.is_empty() {
          "same-declared-settings"
        } else {
          "different-declared-settings"
        },
      ),
      "different_build_fields": Json::array(mismatches),
      "validation_status": if context is Null {
        Json::string("not-recorded")
      } else {
        experiment_get(experiment_get(context, "validation"), "status")
      },
      "sections": Json::array(sections),
      "functions": Json::array(functions),
      "packages": Json::array(packages),
      "function_record_count": int_json(diff.functions.length()),
      "package_record_count": int_json(diff.packages.length()),
      "top": int_json(top),
      "matching": Json::object({
        "matched_baseline": experiment_coverage(summary.matched_baseline),
        "matched_current": experiment_coverage(summary.matched_current),
        "added_symbols": experiment_coverage(summary.added_symbols),
        "removed_symbols": experiment_coverage(summary.removed_symbols),
        "ambiguous_baseline": experiment_coverage(summary.ambiguous_baseline),
        "ambiguous_current": experiment_coverage(summary.ambiguous_current),
        "missing_baseline": experiment_coverage(summary.missing_baseline),
        "missing_current": experiment_coverage(summary.missing_current),
      }),
      "section_comparison_text": Json::string(
        render_size_comparison(before.parsed, after.parsed),
      ),
      "function_comparison_text": Json::string(render_function_diff(diff, top)),
      "modeling_scope": Json::string(graph_modeling_scope()),
      "measurement_scope": Json::string(
        "Raw and whole-file gzip deltas measure only these supplied artifacts. Gzip uses bikallem/compress defaults, not a measured network transfer. Function/package differences use encoded bytes and best-effort symbol identity. Build declarations do not prove controlled conditions or behavioral equivalence.",
      ),
    }),
  )
}

///|
fn experiment_display(value : Json) -> String {
  match value {
    String(text) => text
    Null => "not recorded / unavailable"
    _ => value.stringify()
  }
}

///|
fn experiment_cell(value : Json) -> String {
  "<td>" + html_escape(experiment_display(value)) + "</td>"
}

///|
fn experiment_gzip_error(value : Json) -> String {
  if value is Null {
    "none"
  } else {
    experiment_display(value)
  }
}

///|
/// Standalone HTML with no scripts or external resources. All supplied strings,
/// including paths, raw symbols and context, are escaped before entering HTML.
pub fn render_experiment_html(report : Json) -> String {
  let context = experiment_get(report, "context")
  let title = match experiment_get(context, "title") {
    String(title) => title
    _ => "Optimization experiment"
  }
  let b = experiment_get(report, "baseline")
  let a = experiment_get(report, "current")
  let out = StringBuilder()
  out.write_string(
    "<!doctype html><html lang=\"en\"><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width, initial-scale=1\"><title>" +
    html_escape(title) +
    "</title><style>body{font:16px/1.6 system-ui,sans-serif;background:#f4f6fa;color:#172338;max-width:1120px;margin:32px auto;padding:0 20px}section{background:white;border:1px solid #dce3ee;border-radius:12px;padding:20px;margin:18px 0}h1,h2{line-height:1.25}table{border-collapse:collapse;width:100%}th,td{text-align:left;vertical-align:top;padding:10px;border-bottom:1px solid #dce3ee;overflow-wrap:anywhere}pre{white-space:pre-wrap;overflow-wrap:anywhere;font:13px/1.6 ui-monospace,monospace}.notice{border-left:5px solid #b7791f}.scroll{overflow:auto}code{overflow-wrap:anywhere}</style><h1>" +
    html_escape(title) +
    "</h1><p>Measured artifact comparison · moonsize</p>",
  )
  out.write_string(
    "<section class=\"notice\"><h2>Interpretation</h2><p>Delta = current minus baseline. Negative means fewer bytes.</p><p>Declared build comparability: <strong>" +
    html_escape(
      experiment_display(experiment_get(report, "build_comparability")),
    ) +
    "</strong>. Different fields: " +
    html_escape(
      experiment_display(experiment_get(report, "different_build_fields")),
    ) +
    ".</p><p>Business validation (self-reported): <strong>" +
    html_escape(experiment_display(experiment_get(report, "validation_status"))) +
    "</strong>. A smaller artifact alone does not establish a successful optimization.</p><p>" +
    html_escape(
      experiment_display(experiment_get(report, "context_provenance")),
    ) +
    "</p></section>",
  )
  out.write_string(
    "<section><h2>Measured sizes</h2><table><tr><th>Bytes</th><th>Baseline</th><th>Current</th><th>Delta</th></tr>",
  )
  out.write_string(
    "<tr><th>Whole file</th>" +
    experiment_cell(experiment_get(b, "raw_bytes")) +
    experiment_cell(experiment_get(a, "raw_bytes")) +
    experiment_cell(experiment_get(report, "raw_delta")) +
    "</tr>",
  )
  out.write_string(
    "<tr><th>Whole-file gzip</th>" +
    experiment_cell(experiment_get(b, "whole_gzip_bytes")) +
    experiment_cell(experiment_get(a, "whole_gzip_bytes")) +
    experiment_cell(experiment_get(report, "whole_gzip_delta")) +
    "</tr></table><p>Gzip errors: baseline " +
    html_escape(experiment_gzip_error(experiment_get(b, "gzip_error"))) +
    "; current " +
    html_escape(experiment_gzip_error(experiment_get(a, "gzip_error"))) +
    ".</p></section>",
  )
  if !(experiment_get(report, "raw_growth_budget_bytes") is Null) {
    out.write_string(
      "<section><h2>Raw growth budget</h2><p>Allowed growth in bytes: " +
      html_escape(
        experiment_display(experiment_get(report, "raw_growth_budget_bytes")),
      ) +
      ". Passed: " +
      html_escape(
        experiment_display(experiment_get(report, "raw_growth_budget_passed")),
      ) +
      ". A budget refusal still preserves this measured report.</p></section>",
    )
  }
  out.write_string(
    "<section><details><summary>Artifacts and graph diagnostics</summary><p>Graph completeness concerns the current model; it does not certify deletion safety.</p>",
  )
  for side in ["baseline", "current"] {
    out.write_string(
      "<h3>" +
      side +
      "</h3><pre>" +
      html_escape(experiment_get(report, side).stringify(indent=2)) +
      "</pre>",
    )
  }
  out.write_string(
    "</details></section><section><details><summary>Build and business validation record (self-reported)</summary><pre>" +
    html_escape(context.stringify(indent=2)) +
    "</pre></details></section>",
  )
  for
    (key, heading) in [
      ("section_comparison_text", "Section changes"),
      ("function_comparison_text", "Functions, packages and matching coverage"),
    ] {
    out.write_string(
      "<section><h2>" +
      heading +
      "</h2><div class=\"scroll\"><pre>" +
      html_escape(experiment_display(experiment_get(report, key))) +
      "</pre></div></section>",
    )
  }
  out.write_string(
    "<section><h2>Measurement boundaries</h2><p>" +
    html_escape(experiment_display(experiment_get(report, "measurement_scope"))) +
    "</p><p>" +
    html_escape(experiment_display(experiment_get(report, "modeling_scope"))) +
    "</p></section></html>",
  )
  out.to_string()
}
