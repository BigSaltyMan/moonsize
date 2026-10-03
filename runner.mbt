///|
/// The process contract: what the exit code means, and the size gate that
/// decides it.
///
/// The library owns this so the decisions can be tested without a process
/// around them, and so a CI job reading an exit code is reading something that
/// was specified rather than inferred.

///|
/// The analysis ran and nothing was over budget.
pub const EXIT_OK : Int = 0

///|
/// The input could not be read, or is not a WebAssembly module.
pub const EXIT_INPUT : Int = 1

///|
/// The command line did not make sense.
pub const EXIT_USAGE : Int = 2

///|
/// The module is over the size budget the invocation set.
pub const EXIT_OVER_SIZE : Int = 3

///|
/// The exit code a module of `current_size` bytes earns, measured against
/// `baseline_size` when the invocation named a baseline.
///
/// Without one, `--max-size` is a ceiling on the file. With one it is the growth
/// the file may show over the baseline, because that is the question a CI job is
/// asking when it compares a branch against the branch it merges into — an
/// absolute ceiling there would be answering something nobody asked.
pub fn size_exit_code(
  options : Options,
  current_size : Int,
  baseline_size : Int?,
) -> Int {
  match options.max_size {
    None => EXIT_OK
    Some(budget) =>
      match baseline_size {
        Some(baseline) =>
          if current_size - baseline > budget {
            EXIT_OVER_SIZE
          } else {
            EXIT_OK
          }
        None => if current_size > budget { EXIT_OVER_SIZE } else { EXIT_OK }
      }
  }
}

///|
/// Why the size gate failed, in one line, and an empty string when it passed.
///
/// It asks the gate rather than re-deriving the answer, so the message and the
/// exit code can never disagree about whether the run was over budget.
pub fn describe_size_failure(
  options : Options,
  current_size : Int,
  baseline_size : Int?,
) -> String {
  if size_exit_code(options, current_size, baseline_size) == EXIT_OK {
    return ""
  }
  match options.max_size {
    None => ""
    Some(budget) =>
      match baseline_size {
        Some(baseline) =>
          "moonsize: grew by " +
          plural(current_size - baseline, "byte") +
          " over the baseline, budget " +
          plural(budget, "byte")
        None =>
          "moonsize: " +
          plural(current_size, "byte") +
          " is over the budget of " +
          plural(budget, "byte")
      }
  }
}

///|
/// One row of the size comparison: a section as each module has it.
priv struct SizeRow {
  label : String
  baseline : Int
  current : Int
}

///|
/// The size of the section carrying this label, or `None` when the module has no
/// such section.
fn labelled_section_size(parsed : WasmModule, label : String) -> Int? {
  for section in parsed.sections {
    if section_label(section) == label {
      return Some(section.total_size)
    }
  }
  None
}

///|
/// Both modules' sections, matched by label and ordered by their current size.
///
/// A section only one of the two has is still listed, against a zero: arriving
/// or disappearing is exactly the kind of change a comparison is for.
fn size_rows(baseline : WasmModule, current : WasmModule) -> Array[SizeRow] {
  let rows : Array[SizeRow] = []
  for section in ordered_sections(current) {
    let label = section_label(section)
    rows.push({
      label,
      baseline: match labelled_section_size(baseline, label) {
        Some(size) => size
        None => 0
      },
      current: section.total_size,
    })
  }
  for section in ordered_sections(baseline) {
    let label = section_label(section)
    if labelled_section_size(current, label) is None {
      rows.push({ label, baseline: section.total_size, current: 0, })
    }
  }
  rows
}

///|
/// A signed byte delta and the same change as a share of the baseline.
///
/// A section the baseline never had has no share to give — the change is
/// everything it is — so it says `new` rather than dividing by zero.
fn delta_text(delta : Int, baseline : Int) -> String {
  let magnitude = if delta < 0 { -delta } else { delta }
  let sign = if delta > 0 { "+" } else if delta < 0 { "-" } else { "" }
  if baseline <= 0 {
    if delta == 0 {
      return "0"
    }
    return sign + magnitude.to_string() + "  (new)"
  }
  sign +
  magnitude.to_string() +
  "  (" +
  sign +
  share_text(magnitude, baseline) +
  ")"
}

///|
/// One comparison row, with the numbers right-aligned under their headings.
fn size_row_text(
  label : String,
  baseline : Int,
  current : Int,
  label_width : Int,
  baseline_width : Int,
  current_width : Int,
) -> String {
  "  " +
  pad_right(label, label_width) +
  "  " +
  pad_left(baseline.to_string(), baseline_width) +
  "  " +
  pad_left(current.to_string(), current_width) +
  "  " +
  delta_text(current - baseline, baseline) +
  "\n"
}

///|
/// The size comparison table: the whole file and every section, against the
/// module it is being compared with.
///
/// Sections are ordered by their current size, so the table reads like the
/// section report above it, and the totals come first because that is the number
/// a budget is spent against.
pub fn render_size_comparison(
  baseline : WasmModule,
  current : WasmModule,
) -> String {
  let rows = size_rows(baseline, current)
  let mut label_width = "total".length()
  let mut baseline_width = number_width(baseline.file_size, 8)
  let mut current_width = number_width(current.file_size, 7)
  for row in rows {
    if row.label.length() > label_width {
      label_width = row.label.length()
    }
    baseline_width = number_width(row.baseline, baseline_width)
    current_width = number_width(row.current, current_width)
  }
  let mut out = "SIZE COMPARISON\n\n  " +
    pad_right("", label_width) +
    "  " +
    pad_left("baseline", baseline_width) +
    "  " +
    pad_left("current", current_width) +
    "  delta\n" +
    size_row_text(
      "total",
      baseline.file_size,
      current.file_size,
      label_width,
      baseline_width,
      current_width,
    )
  for row in rows {
    out = out +
      size_row_text(
        row.label,
        row.baseline,
        row.current,
        label_width,
        baseline_width,
        current_width,
      )
  }
  out
}
