///|
fn signed_bytes(delta : Int) -> String {
  (if delta > 0 { "+" } else { "" }) + delta.to_string()
}

///|
fn diff_numbers(baseline : Int, current : Int) -> String {
  pad_left(baseline.to_string(), 12) +
  "  " +
  pad_left(current.to_string(), 12) +
  "  " +
  pad_left(signed_bytes(current - baseline), 12)
}

///|
fn diff_index(stat : FunctionStat?) -> String {
  match stat {
    Some(stat) => stat.index.to_string()
    None => "-"
  }
}

///|
fn coverage_line(
  name : String,
  before : FunctionCoverage,
  after : FunctionCoverage,
) -> String {
  "  " +
  pad_right(name, 16) +
  "  " +
  pad_left(before.count.to_string(), 10) +
  "  " +
  pad_left(after.count.to_string(), 10) +
  "  " +
  pad_left(before.bytes.to_string(), 12) +
  "  " +
  pad_left(after.bytes.to_string(), 12) +
  "\n"
}

///|
/// Text-only first release. Ranking uses absolute delta then exact symbol/package
/// identity; indices locate records within a build and never establish a match.
/// top=0 hides both detail rankings while retaining all totals and coverage.
pub fn render_function_diff(diff : ModuleSizeDiff, top : Int) -> String {
  let out = StringBuilder()
  out.write_string("FUNCTION SIZE CHANGES\n\n")
  out.write_string(
    "  Encoded bytes = body length prefix + locals + instructions.\n",
  )
  out.write_string(
    "  " +
    pad_right("TOTAL", 16) +
    "  " +
    pad_left("BASELINE", 12) +
    "  " +
    pad_left("CURRENT", 12) +
    "  " +
    pad_left("DELTA", 12) +
    "\n",
  )
  out.write_string(
    "  " +
    pad_right("file", 16) +
    "  " +
    diff_numbers(diff.baseline_size, diff.current_size) +
    "\n",
  )
  out.write_string(
    "  " +
    pad_right("function encoding", 16) +
    "  " +
    diff_numbers(
      diff.baseline_code.function_bytes,
      diff.current_code.function_bytes,
    ) +
    "\n",
  )
  if top > 0 {
    out.write_string(
      "\n  " +
      pad_right("STATUS", 14) +
      "  " +
      pad_left("BASE_INDEX", 10) +
      "  " +
      pad_left("CURRENT_INDEX", 13) +
      "  " +
      pad_left("BASE_ENCODED", 12) +
      "  " +
      pad_left("CUR_ENCODED", 12) +
      "  " +
      pad_left("DELTA", 12) +
      "  RAW_SYMBOL\n",
    )
    for i, row in diff.functions {
      if i >= top {
        break
      }
      let symbol = match row.raw_name {
        Some(raw) => Json::string(raw).stringify()
        None => "<missing symbol>"
      }
      out.write_string(
        "  " +
        pad_right(change_status_text(row.status), 14) +
        "  " +
        pad_left(diff_index(row.baseline), 10) +
        "  " +
        pad_left(diff_index(row.current), 13) +
        "  " +
        diff_numbers(stat_size(row.baseline), stat_size(row.current)) +
        "  " +
        symbol +
        "\n",
      )
    }
    if diff.functions.is_empty() {
      out.write_string("  no local functions\n")
    }
  } else {
    out.write_string("\n  detail rankings hidden (--top 0)\n")
  }
  out.write_string(
    "\nPACKAGE SIZE CHANGES\n\n  Best-effort symbol package attribution; includes unmatched functions.\n",
  )
  out.write_string(
    "  package totals: " +
    diff_numbers(
      diff.baseline_code.function_bytes,
      diff.current_code.function_bytes,
    ) +
    "\n",
  )
  if top > 0 {
    out.write_string(
      "\n  " +
      pad_left("BASE_FUNCS", 10) +
      "  " +
      pad_left("CURRENT_FUNCS", 13) +
      "  " +
      pad_left("BASE_ENCODED", 12) +
      "  " +
      pad_left("CUR_ENCODED", 12) +
      "  " +
      pad_left("DELTA", 12) +
      "  PACKAGE\n",
    )
    for i, row in diff.packages {
      if i >= top {
        break
      }
      out.write_string(
        "  " +
        pad_left(row.baseline_functions.to_string(), 10) +
        "  " +
        pad_left(row.current_functions.to_string(), 13) +
        "  " +
        diff_numbers(row.baseline_size, row.current_size) +
        "  " +
        Json::string(row.name).stringify() +
        "\n",
      )
    }
    if diff.packages.is_empty() {
      out.write_string("  no packages with local functions\n")
    }
  }
  let summary = diff.matching
  let zero : FunctionCoverage = { count: 0, bytes: 0, }
  out.write_string(
    "\nMATCHING SUMMARY\n\n  " +
    pad_right("CATEGORY", 16) +
    "  " +
    pad_left("BASE_COUNT", 10) +
    "  " +
    pad_left("CUR_COUNT", 10) +
    "  " +
    pad_left("BASE_BYTES", 12) +
    "  " +
    pad_left("CUR_BYTES", 12) +
    "\n",
  )
  out.write_string(
    coverage_line("matched", summary.matched_baseline, summary.matched_current),
  )
  out.write_string(coverage_line("added-symbol", zero, summary.added_symbols))
  out.write_string(
    coverage_line("removed-symbol", summary.removed_symbols, zero),
  )
  out.write_string(
    coverage_line(
      "ambiguous",
      summary.ambiguous_baseline,
      summary.ambiguous_current,
    ),
  )
  out.write_string(
    coverage_line(
      "missing-symbol",
      summary.missing_baseline,
      summary.missing_current,
    ),
  )
  out.write_string(
    "\n  Matched coverage: baseline " +
    share_text(
      summary.matched_baseline.count,
      diff.baseline_code.function_count,
    ) +
    " of functions / " +
    share_text(
      summary.matched_baseline.bytes,
      diff.baseline_code.function_bytes,
    ) +
    " of encoded bytes; current " +
    share_text(summary.matched_current.count, diff.current_code.function_count) +
    " of functions / " +
    share_text(summary.matched_current.bytes, diff.current_code.function_bytes) +
    " of encoded bytes.\n",
  )
  let unmatched_before = summary.ambiguous_baseline.bytes +
    summary.missing_baseline.bytes
  let unmatched_after = summary.ambiguous_current.bytes +
    summary.missing_current.bytes
  if summary.ambiguous_baseline.count +
    summary.ambiguous_current.count +
    summary.missing_baseline.count +
    summary.missing_current.count >
    0 {
    out.write_string(
      "  WARNING: ambiguous or missing symbols prevent function identity matching; unmatched bytes remain in package totals.\n",
    )
  }
  out.write_string(
    "  Only symbols unique on both sides are matched. Added/removed symbols may reflect renames or toolchain changes, not source additions/deletions.\n",
  )
  out.write_string(
    "  Function delta = matched " +
    signed_bytes(summary.matched_delta) +
    " + added " +
    summary.added_symbols.bytes.to_string() +
    " - removed " +
    summary.removed_symbols.bytes.to_string() +
    " + unmatched current " +
    unmatched_after.to_string() +
    " - unmatched baseline " +
    unmatched_before.to_string() +
    " = " +
    signed_bytes(
      diff.current_code.function_bytes - diff.baseline_code.function_bytes,
    ) +
    " B.\n",
  )
  out.write_string(
    "\nCODE OVERHEAD\n\n  " +
    pad_right("RAW BYTES", 16) +
    "  " +
    pad_left("BASELINE", 12) +
    "  " +
    pad_left("CURRENT", 12) +
    "  " +
    pad_left("DELTA", 12) +
    "\n",
  )
  for
    (label, before, after) in [
      (
        "code section",
        diff.baseline_code.code_size,
        diff.current_code.code_size,
      ),
      (
        "function encoding",
        diff.baseline_code.function_bytes,
        diff.current_code.function_bytes,
      ),
      ("code overhead", diff.baseline_code.overhead, diff.current_code.overhead),
    ] {
    out.write_string(
      "  " + pad_right(label, 16) + "  " + diff_numbers(before, after) + "\n",
    )
  }
  out.write_string(
    "\n  Code overhead includes the section header and function-count encoding.\n",
  )
  out.write_string(
    "  Function changes do not sum to file changes; see the existing section comparison for name, data and other sections.\n",
  )
  out.to_string()
}
