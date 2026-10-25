///|
/// Exact host-visible name match, not a cross-build target or source identity.
pub struct ExportComparisonRow {
  name : String
  /// added / removed / kind_changed / same_kind, never a compatibility verdict.
  status : String
  baseline : ExportDeclaration?
  current : ExportDeclaration?
  declaration_bytes_delta : Int
  /// Only defined when both declarations have the same kind. Numeric change only.
  target_index_changed : Bool?
}

///|
pub struct ExportsComparisonCounts {
  added_count : Int
  removed_count : Int
  kind_changed_count : Int
  same_kind_count : Int
  row_count : Int
} derive(Eq, Debug)

///|
pub struct ExportsComparison {
  baseline : ExportsReport
  current : ExportsReport
  counts : ExportsComparisonCounts
  /// All fields are signed current - baseline, using original encoded widths.
  delta : ExportsLedger
  baseline_non_export_bytes : Int
  current_non_export_bytes : Int
  delta_non_export_bytes : Int
  delta_file_bytes : Int
  /// Display order: removed, kind_changed, added, same_kind; then |bytes| and name.
  rows : Array[ExportComparisonRow]
  comparison_scope : String
}

///|
fn exports_diff_ledger(
  before : ExportsLedger,
  after : ExportsLedger,
) -> ExportsLedger {
  {
    export_section_bytes: after.export_section_bytes -
    before.export_section_bytes,
    section_header_bytes: after.section_header_bytes -
    before.section_header_bytes,
    count_prefix_bytes: after.count_prefix_bytes - before.count_prefix_bytes,
    declaration_bytes: after.declaration_bytes - before.declaration_bytes,
    name_encoding_bytes: after.name_encoding_bytes - before.name_encoding_bytes,
    name_length_prefix_bytes: after.name_length_prefix_bytes -
    before.name_length_prefix_bytes,
    name_utf8_bytes: after.name_utf8_bytes - before.name_utf8_bytes,
    descriptor_bytes: after.descriptor_bytes - before.descriptor_bytes,
    kind_bytes: after.kind_bytes - before.kind_bytes,
    target_index_prefix_bytes: after.target_index_prefix_bytes -
    before.target_index_prefix_bytes,
  }
}

///|
fn exports_diff_status_order(status : String) -> Int {
  match status {
    "removed" => 0
    "kind_changed" => 1
    "added" => 2
    "same_kind" => 3
    _ => 4 // Reports only contain the four statuses above.
  }
}

///|
fn exports_diff_row(
  name : String,
  before : ExportDeclaration?,
  after : ExportDeclaration?,
) -> ExportComparisonRow {
  let (status, target_index_changed) = match (before, after) {
    (Some(a), Some(b)) if a.kind_code == b.kind_code =>
      ("same_kind", Some(a.target_index != b.target_index))
    (Some(_), Some(_)) => ("kind_changed", None)
    (Some(_), None) => ("removed", None)
    (None, _) => ("added", None) // Called only for a name present on at least one side.
  }
  {
    name,
    status,
    baseline: before,
    current: after,
    target_index_changed,
    declaration_bytes_delta: after.map(fn(e) { e.encoding.size }).unwrap_or(0) -
    before.map(fn(e) { e.encoding.size }).unwrap_or(0),
  }
}

///|
/// Each strict inventory is obtained once. No rehashing, target matching, graph
/// or type analysis; any side error aborts the whole comparison.
pub fn compare_exports(
  baseline : Bytes,
  current : Bytes,
) -> Result[ExportsComparison, ComparisonError] {
  let before = match inspect_exports(baseline) {
    Ok(report) => report
    Err(error) => return Err(Baseline(error))
  }
  let after = match inspect_exports(current) {
    Ok(report) => report
    Err(error) => return Err(Current(error))
  }
  let by_before : Map[String, ExportDeclaration] = Map([])
  let by_after : Map[String, ExportDeclaration] = Map([])
  for entry in before.entries {
    by_before.set(entry.name, entry)
  }
  for entry in after.entries {
    by_after.set(entry.name, entry)
  }
  let rows = []
  for entry in before.entries {
    rows.push(
      exports_diff_row(entry.name, Some(entry), by_after.get(entry.name)),
    )
  }
  for entry in after.entries {
    if by_before.get(entry.name) is None {
      rows.push(exports_diff_row(entry.name, None, Some(entry)))
    }
  }
  rows.sort_by(fn(a, b) {
    let status_order = exports_diff_status_order(a.status).compare(
      exports_diff_status_order(b.status),
    )
    if status_order != 0 {
      return status_order
    }
    let size_order = b.declaration_bytes_delta
      .abs()
      .compare(a.declaration_bytes_delta.abs())
    if size_order != 0 {
      size_order
    } else {
      a.name.lexical_compare(b.name)
    }
  })
  let counts = [0, 0, 0, 0]
  for row in rows {
    counts[exports_diff_status_order(row.status)] += 1
  }
  let baseline_non_export_bytes = before.file_size -
    before.ledger.export_section_bytes
  let current_non_export_bytes = after.file_size -
    after.ledger.export_section_bytes
  Ok({
    baseline: before,
    current: after,
    counts: {
      added_count: counts[2],
      removed_count: counts[0],
      kind_changed_count: counts[1],
      same_kind_count: counts[3],
      row_count: rows.length(),
    },
    delta: exports_diff_ledger(before.ledger, after.ledger),
    baseline_non_export_bytes,
    current_non_export_bytes,
    delta_non_export_bytes: current_non_export_bytes - baseline_non_export_bytes,
    delta_file_bytes: after.file_size - before.file_size,
    rows,
    comparison_scope: "Only export name and kind declarations are compared; full ABI, target existence, signatures, reachability and runtime behavior are not evaluated. Exact names are matched without normalization or demangling. same_kind is a declaration category only. target_index_changed compares unsigned numbers within the same kind, not target identity. Indices, ordinals and file offsets locate declarations within their own input, not source identities across builds. Renames appear as removed and added. Alias groups remain in each inventory but are not matched across builds. Signed byte deltas are current minus baseline; non-export bytes include the file header, code, custom and all other sections. Declaration bytes do not measure function bodies, source edits or recompiled/gzip savings. Display order is not a risk ranking; Top limits text rows only.",
  })
}
