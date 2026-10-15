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
/// The run produced something the caller should not accept: the module is over
/// the size budget the invocation set, or `--strict` found the call graph
/// incomplete. Both mean "this run's answer is refused", which is why they share
/// a code — a job branches on it either way.
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
/// The exit code `--strict` earns, or `EXIT_OK` when the graph is complete or
/// the flag is absent.
/// Completeness includes every unified graph diagnostic, including reference calls.
///
/// It lives here rather than in the entry point so the rule can be tested
/// without a process: a job that passes `--strict` is saying it cannot judge a
/// warning itself, and the run has to fail rather than print one.
pub fn strict_exit_code(options : Options, graph_complete : Bool) -> Int {
  if options.strict && !graph_complete {
    EXIT_OVER_SIZE
  } else {
    EXIT_OK
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
/// Identity is separate from display: full, case-sensitive custom names cannot
/// collide with standard sections. Empty names are valid custom identities.
priv enum SectionKey {
  StandardSection(Int)
  CustomSection(String)
} derive(Eq, Hash)

///|
/// One row compares all encoded bytes for a section identity on either side.
priv struct SizeRow {
  key : SectionKey
  label : String
  baseline : Int
  current : Int
}

///|
/// Sum actual encoded sizes, including each repeated custom section's header.
fn summarize_sections(parsed : WasmModule) -> Map[SectionKey, Int] {
  let sizes : Map[SectionKey, Int] = Map([])
  for section in parsed.sections {
    let key = if section.kind.is_custom() {
      CustomSection(
        match section.custom_name {
          Some(name) => name
          None => ""
        },
      )
    } else {
      StandardSection(section.id)
    }
    sizes.set(key, sizes.get(key).unwrap_or(0) + section.total_size)
  }
  sizes
}

///|
fn section_key_label(key : SectionKey) -> String {
  match key {
    StandardSection(id) =>
      match SectionId::from_id(id) {
        Some(kind) => kind.name()
        None => "section " + id.to_string()
      }
    CustomSection(name) => "custom (" + name + ")"
  }
}

///|
fn standard_section_rank(id : Int) -> Int {
  match SectionId::from_id(id) {
    Some(kind) => section_order(kind)
    None => id
  }
}

///|
/// Final tie-break: standard sections in binary order, then custom names in
/// String::compare order. Neither map iteration nor physical section order is
/// used, so rearranging same-size or repeated custom sections changes no rows.
fn compare_section_keys(a : SectionKey, b : SectionKey) -> Int {
  match (a, b) {
    (StandardSection(left), StandardSection(right)) =>
      standard_section_rank(left) - standard_section_rank(right)
    (StandardSection(_), CustomSection(_)) => -1
    (CustomSection(_), StandardSection(_)) => 1
    (CustomSection(left), CustomSection(right)) => String::compare(left, right)
  }
}

///|
/// Independently sum both modules, union identities, then order by current size
/// descending, baseline size descending, and deterministic section identity.
fn size_rows(baseline : WasmModule, current : WasmModule) -> Array[SizeRow] {
  let before = summarize_sections(baseline)
  let after = summarize_sections(current)
  let keys : Set[SectionKey] = Set([])
  for key, _ in before {
    keys.add(key)
  }
  for key, _ in after {
    keys.add(key)
  }
  let rows : Array[SizeRow] = []
  for key in keys {
    rows.push({
      key,
      label: section_key_label(key),
      baseline: before.get(key).unwrap_or(0),
      current: after.get(key).unwrap_or(0),
    })
  }
  rows.sort_by(fn(a, b) {
    if a.current != b.current {
      b.current - a.current
    } else if a.baseline != b.baseline {
      b.baseline - a.baseline
    } else {
      compare_section_keys(a.key, b.key)
    }
  })
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
/// The size comparison table: the whole file and every section group, against the
/// module it is being compared with.
///
/// Standard sections match by kind; custom sections group by full name. Sizes
/// include actual headers. Current size, baseline size, then identity determine
/// row order. The whole-file total comes first and remains the budget's input.
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
