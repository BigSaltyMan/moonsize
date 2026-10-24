///|
/// Side-specific wrapper; the original parser error and position are preserved.
pub enum ImportsComparisonError {
  ImportsBaselineError(WasmError)
  ImportsCurrentError(WasmError)
}

///|
/// A multiset key group, not a physical declaration correspondence.
pub struct ImportInventoryGroup {
  module_name : String
  field : String
  kind : String
  status : String
  baseline_ordinals : Array[Int]
  current_ordinals : Array[Int]
  baseline_count : Int
  current_count : Int
  overlap_count : Int
  removed_count : Int
  added_count : Int
  count_delta : Int
  baseline_entry_bytes : Int
  current_entry_bytes : Int
  entry_bytes_delta : Int
}

///|
pub struct ImportInventoryCounts {
  baseline_entry_count : Int
  current_entry_count : Int
  overlap_count : Int
  removed_count : Int
  added_count : Int
  count_delta : Int
} derive(Eq, Debug)

///|
pub struct ImportsComparison {
  baseline : ImportsReport
  current : ImportsReport
  /// Churn descending, absolute byte delta descending, full key ascending.
  groups : Array[ImportInventoryGroup]
  counts : ImportInventoryCounts
  /// Only key multiplicities; never a claim about ABI or descriptor changes.
  inventory_changed : Bool
  /// Signed current-minus-baseline byte totals, never file ranges.
  delta : ImportsLedger
  comparison_scope : String
}

///|
priv enum ImportsInventoryKey {
  ImportInventoryKey(String, String, String)
} derive(Eq, Hash)

///|
priv struct ImportsInventoryBucket {
  module_name : String
  field : String
  kind : String
  baseline_ordinals : Array[Int]
  current_ordinals : Array[Int]
  mut baseline_bytes : Int
  mut current_bytes : Int
}

///|
fn imports_diff_scope() -> String {
  "Exact multiset key: (module_name, field, kind), without normalization. Ordinal, kind_index, offsets and type_index are not cross-build identities. " +
  "Overlap is a quantity intersection, not physical member matching or equality of bytes/types. same_count does not mean unchanged or compatible. " +
  "Type compatibility is not evaluated: equal type_index does not prove equal signatures, different type_index does not prove a signature change; limits, value types and mutability may differ under the same key/count. " +
  "Equal inventories do not establish host compatibility or equal encodings; zero byte delta does not establish byte equality. " +
  "All deltas are current minus baseline; section header and count overhead are separate from groups. " +
  "Declarations do not establish runtime calls, permissions, host implementation/package size, transfer cost or removal savings. " +
  "Top limits text groups only; counts, both complete reports, JSON and scope remain complete."
}

///|
pub fn describe_imports_comparison_error(
  error : ImportsComparisonError,
) -> String {
  match error {
    ImportsBaselineError(e) => "baseline: " + describe_error(e)
    ImportsCurrentError(e) => "current: " + describe_error(e)
  }
}

///|
fn imports_ledger_delta(
  before : ImportsLedger,
  after : ImportsLedger,
) -> ImportsLedger {
  {
    import_section_total_bytes: after.import_section_total_bytes -
    before.import_section_total_bytes,
    section_header_bytes: after.section_header_bytes -
    before.section_header_bytes,
    count_prefix_bytes: after.count_prefix_bytes - before.count_prefix_bytes,
    entry_bytes: after.entry_bytes - before.entry_bytes,
    module_name_encoding_bytes: after.module_name_encoding_bytes -
    before.module_name_encoding_bytes,
    module_length_prefix_bytes: after.module_length_prefix_bytes -
    before.module_length_prefix_bytes,
    module_utf8_bytes: after.module_utf8_bytes - before.module_utf8_bytes,
    field_name_encoding_bytes: after.field_name_encoding_bytes -
    before.field_name_encoding_bytes,
    field_length_prefix_bytes: after.field_length_prefix_bytes -
    before.field_length_prefix_bytes,
    field_utf8_bytes: after.field_utf8_bytes - before.field_utf8_bytes,
    descriptor_bytes: after.descriptor_bytes - before.descriptor_bytes,
  }
}

///|
/// Parse once per side. No analyze, graph, body inventory or type comparison.
pub fn compare_imports(
  baseline : Bytes,
  current : Bytes,
) -> Result[ImportsComparison, ImportsComparisonError] {
  let before = match inspect_imports(baseline) {
    Ok(r) => r
    Err(e) => return Err(ImportsBaselineError(e))
  }
  let after = match inspect_imports(current) {
    Ok(r) => r
    Err(e) => return Err(ImportsCurrentError(e))
  }
  let buckets : Array[ImportsInventoryBucket] = []
  let by_key : Map[ImportsInventoryKey, Int] = Map([])
  for (is_baseline, report) in [(true, before), (false, after)] {
    for entry in report.entries {
      let key = ImportInventoryKey(entry.module_name, entry.field, entry.kind)
      let index = match by_key.get(key) {
        Some(i) => i
        None => {
          let i = buckets.length()
          buckets.push({
            module_name: entry.module_name,
            field: entry.field,
            kind: entry.kind,
            baseline_ordinals: [],
            current_ordinals: [],
            baseline_bytes: 0,
            current_bytes: 0,
          })
          by_key.set(key, i)
          i
        }
      }
      let bucket = buckets[index]
      if is_baseline {
        bucket.baseline_ordinals.push(entry.ordinal)
        bucket.baseline_bytes += entry.encoding.size
      } else {
        bucket.current_ordinals.push(entry.ordinal)
        bucket.current_bytes += entry.encoding.size
      }
    }
  }
  let groups : Array[ImportInventoryGroup] = []
  let mut total_overlap = 0
  let mut total_added = 0
  let mut total_removed = 0
  let mut changed = false
  for bucket in buckets {
    let b = bucket.baseline_ordinals.length()
    let c = bucket.current_ordinals.length()
    let overlap = b.min(c)
    let status = if b == 0 {
      "added"
    } else if c == 0 {
      "removed"
    } else if c > b {
      "count_increased"
    } else if c < b {
      "count_decreased"
    } else {
      "same_count"
    }
    total_overlap += overlap
    total_added += c - overlap
    total_removed += b - overlap
    if b != c {
      changed = true
    }
    groups.push({
      module_name: bucket.module_name,
      field: bucket.field,
      kind: bucket.kind,
      status,
      baseline_ordinals: bucket.baseline_ordinals,
      current_ordinals: bucket.current_ordinals,
      baseline_count: b,
      current_count: c,
      overlap_count: overlap,
      removed_count: b - overlap,
      added_count: c - overlap,
      count_delta: c - b,
      baseline_entry_bytes: bucket.baseline_bytes,
      current_entry_bytes: bucket.current_bytes,
      entry_bytes_delta: bucket.current_bytes - bucket.baseline_bytes,
    })
  }
  groups.sort_by(fn(a, b) {
    let churn = (b.added_count + b.removed_count).compare(
      a.added_count + a.removed_count,
    )
    if churn != 0 {
      return churn
    }
    let bytes = delta_magnitude(b.entry_bytes_delta).compare(
      delta_magnitude(a.entry_bytes_delta),
    )
    if bytes != 0 {
      return bytes
    }
    let names = a.module_name.compare(b.module_name)
    if names != 0 {
      return names
    }
    let fields = a.field.compare(b.field)
    if fields != 0 {
      return fields
    }
    a.kind.compare(b.kind)
  })
  Ok({
    baseline: before,
    current: after,
    groups,
    counts: {
      baseline_entry_count: before.entry_count,
      current_entry_count: after.entry_count,
      overlap_count: total_overlap,
      removed_count: total_removed,
      added_count: total_added,
      count_delta: after.entry_count - before.entry_count,
    },
    inventory_changed: changed,
    delta: imports_ledger_delta(before.ledger, after.ledger),
    comparison_scope: imports_diff_scope(),
  })
}
