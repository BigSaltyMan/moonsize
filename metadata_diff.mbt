///|
/// Outer custom encoding accounting only; counts/deltas are not file ranges.
pub struct MetadataEncodingTotals {
  custom_count : Int
  custom_encoded_bytes : Int
  section_header_bytes : Int
  name_encoding_bytes : Int
  content_bytes : Int
} derive(Eq, Debug)

///|
/// Ordinals identify physical instances within each input, never matched pairs.
pub struct MetadataComparisonGroup {
  /// category, named, or unavailable_names. The latter is accounting only.
  kind : String
  name : String?
  baseline_ordinals : Array[Int]
  current_ordinals : Array[Int]
  baseline : MetadataEncodingTotals
  current : MetadataEncodingTotals
  delta : MetadataEncodingTotals
}

///|
pub struct MetadataComparison {
  baseline : MetadataReport
  current : MetadataReport
  delta : MetadataEncodingTotals
  baseline_non_custom_bytes : Int
  current_non_custom_bytes : Int
  delta_non_custom_bytes : Int
  delta_file_bytes : Int
  categories : Array[MetadataComparisonGroup]
  name_groups : Array[MetadataComparisonGroup]
  comparison_scope : String
}

///|
priv enum MetadataDiffKey {
  Named(String)
  Unavailable
} derive(Eq, Hash)

///|
fn metadata_diff_totals(rows : Array[MetadataCustom]) -> MetadataEncodingTotals {
  let mut encoded = 0
  let mut headers = 0
  let mut names = 0
  let mut contents = 0
  for row in rows {
    encoded += row.encoding.size
    headers += row.section_header_bytes
    names += row.name_encoding.size
    contents += row.content.size
  }
  {
    custom_count: rows.length(),
    custom_encoded_bytes: encoded,
    section_header_bytes: headers,
    name_encoding_bytes: names,
    content_bytes: contents,
  }
}

///|
fn metadata_diff_delta(
  before : MetadataEncodingTotals,
  after : MetadataEncodingTotals,
) -> MetadataEncodingTotals {
  {
    custom_count: after.custom_count - before.custom_count,
    custom_encoded_bytes: after.custom_encoded_bytes -
    before.custom_encoded_bytes,
    section_header_bytes: after.section_header_bytes -
    before.section_header_bytes,
    name_encoding_bytes: after.name_encoding_bytes - before.name_encoding_bytes,
    content_bytes: after.content_bytes - before.content_bytes,
  }
}

///|
fn metadata_diff_group(
  kind : String,
  name : String?,
  before : Array[MetadataCustom],
  after : Array[MetadataCustom],
) -> MetadataComparisonGroup {
  let baseline_ordinals = before.map(fn(row) { row.ordinal })
  let current_ordinals = after.map(fn(row) { row.ordinal })
  baseline_ordinals.sort()
  current_ordinals.sort()
  let baseline = metadata_diff_totals(before)
  let current = metadata_diff_totals(after)
  {
    kind,
    name,
    baseline_ordinals,
    current_ordinals,
    baseline,
    current,
    delta: metadata_diff_delta(baseline, current),
  }
}

///|
/// Each side is inspected exactly once. Optional name-detail partial results
/// remain successful; neither contents nor internal name records are compared.
pub fn compare_metadata(
  baseline : Bytes,
  current : Bytes,
) -> Result[MetadataComparison, ComparisonError] {
  let before = match inspect_metadata(baseline) {
    Ok(report) => report
    Err(error) => return Err(Baseline(error))
  }
  let after = match inspect_metadata(current) {
    Ok(report) => report
    Err(error) => return Err(Current(error))
  }
  let categories = ["name", "producers", "debug", "other", "unavailable"].map(fn(
    category,
  ) {
    metadata_diff_group(
      "category",
      Some(category),
      before.customs.filter(fn(row) { row.category == category }),
      after.customs.filter(fn(row) { row.category == category }),
    )
  })
  let buckets : Map[
    MetadataDiffKey,
    (Array[MetadataCustom], Array[MetadataCustom]),
  ] = Map([])
  for (rows, is_current) in [(before.customs, false), (after.customs, true)] {
    for row in rows {
      let key = match row.name {
        Some(name) => Named(name)
        None => Unavailable
      }
      let pair = buckets.get_or_default(key, ([], []))
      if is_current {
        pair.1.push(row)
      } else {
        pair.0.push(row)
      }
      buckets.set(key, pair)
    }
  }
  let name_groups = []
  for key, pair in buckets {
    let (kind, name) = match key {
      Named(name) => ("named", Some(name))
      Unavailable => ("unavailable_names", None)
    }
    name_groups.push(metadata_diff_group(kind, name, pair.0, pair.1))
  }
  name_groups.sort_by(fn(a, b) {
    let size_order = b.delta.custom_encoded_bytes
      .abs()
      .compare(a.delta.custom_encoded_bytes.abs())
    if size_order != 0 {
      return size_order
    }
    let count_order = b.delta.custom_count
      .abs()
      .compare(a.delta.custom_count.abs())
    if count_order != 0 {
      return count_order
    }
    match (a.name, b.name) {
      (Some(x), Some(y)) => x.lexical_compare(y)
      (Some(_), None) => -1
      (None, Some(_)) => 1
      (None, None) => 0
    }
  })
  let before_totals = metadata_diff_totals(before.customs)
  let after_totals = metadata_diff_totals(after.customs)
  let baseline_non_custom_bytes = before.file_size -
    before_totals.custom_encoded_bytes
  let current_non_custom_bytes = after.file_size -
    after_totals.custom_encoded_bytes
  Ok({
    baseline: before,
    current: after,
    delta: metadata_diff_delta(before_totals, after_totals),
    baseline_non_custom_bytes,
    current_non_custom_bytes,
    delta_non_custom_bytes: current_non_custom_bytes - baseline_non_custom_bytes,
    delta_file_bytes: after.file_size - before.file_size,
    categories,
    name_groups,
    comparison_scope: "Outer custom encodings only. Category and full-name groups are alternative views of the same instances. Names and zero byte deltas do not prove equal contents. Ordinals are input-local, not cross-build identities. Unavailable names share an accounting bucket only. Optional name details and opaque contents are retained, not compared. Debug classification uses a name prefix, not DWARF validation. Non-custom bytes include the Wasm header and all standard sections. No semantic equivalence, safe removal, recompiled or gzip savings are inferred.",
  })
}
