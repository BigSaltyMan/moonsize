///|
/// Signed current-minus-baseline encoding deltas, never file ranges.
pub struct FunctionLocalsDelta {
  entry_bytes : Int
  prefix_bytes : Int
  body_bytes : Int
  locals_bytes : Int
  group_count_encoding_bytes : Int
  quantity_encoding_bytes : Int
  type_encoding_bytes : Int
  body_remainder_bytes : Int
  group_count : Int
  declared_count_delta_decimal : String
}

///|
pub struct FunctionLocalsTypeTotals {
  group_indices : Array[Int]
  group_count : Int
  declared_count : UInt64
  quantity_encoding_bytes : Int
  type_encoding_bytes : Int
  group_bytes : Int
}

///|
pub struct FunctionLocalsTypeDelta {
  group_count : Int
  declared_count_delta_decimal : String
  quantity_encoding_bytes : Int
  type_encoding_bytes : Int
  group_bytes : Int
}

///|
/// Full raw type encoding is the key; presence depends on groups, not quantity.
pub struct FunctionLocalsTypeEncoding {
  type_hex : String
  type_label : String?
  presence : String
  baseline : FunctionLocalsTypeTotals
  current : FunctionLocalsTypeTotals
  delta : FunctionLocalsTypeDelta
}

///|
pub struct FunctionLocalsComparison {
  baseline : FunctionLocalsReport
  current : FunctionLocalsReport
  delta : FunctionLocalsDelta
  type_encodings : Array[FunctionLocalsTypeEncoding]
  scope : String
}

///|
pub enum FunctionLocalsComparisonError {
  BaselineLocalsError(Int, FunctionLocalsError)
  CurrentLocalsError(Int, FunctionLocalsError)
}

///|
pub fn describe_function_locals_comparison_error(
  error : FunctionLocalsComparisonError,
) -> String {
  match error {
    BaselineLocalsError(index, cause) =>
      "baseline function \{index}: " + describe_function_locals_error(cause)
    CurrentLocalsError(index, cause) =>
      "current function \{index}: " + describe_function_locals_error(cause)
  }
}

///|
/// Compare before subtracting; no signed casts, floating point or u64 underflow.
fn locals_count_delta(before : UInt64, after : UInt64) -> String {
  if after >= before {
    (after - before).to_string()
  } else {
    "-" + (before - after).to_string()
  }
}

///|
fn locals_type_buckets(
  report : FunctionLocalsReport,
) -> Map[String, Array[FunctionLocalGroup]] {
  let buckets : Map[String, Array[FunctionLocalGroup]] = Map([])
  for group in report.groups {
    match buckets.get(group.type_hex) {
      Some(groups) => groups.push(group)
      None => buckets.set(group.type_hex, [group])
    }
  }
  buckets
}

///|
fn locals_type_totals(
  groups : Array[FunctionLocalGroup],
) -> FunctionLocalsTypeTotals {
  let indices : Array[Int] = []
  let mut declared_count = 0UL
  let mut quantity_bytes = 0
  let mut type_bytes = 0
  let mut group_bytes = 0
  for group in groups {
    indices.push(group.group_index)
    // These are disjoint subsets of one successful inspector report: positive
    // partial sums cannot exceed its checked u64 total or bounded locals bytes.
    declared_count += group.quantity.to_uint64()
    quantity_bytes += group.quantity_encoding.size
    type_bytes += group.type_encoding.size
    group_bytes += group.encoding.size
  }
  {
    group_indices: indices,
    group_count: groups.length(),
    declared_count,
    quantity_encoding_bytes: quantity_bytes,
    type_encoding_bytes: type_bytes,
    group_bytes,
  }
}

///|
/// Inspect each explicitly selected target once; no identity or group alignment.
pub fn compare_function_locals(
  baseline_data : Bytes,
  baseline_index : Int,
  current_data : Bytes,
  current_index : Int,
) -> Result[FunctionLocalsComparison, FunctionLocalsComparisonError] {
  let before = match inspect_function_locals(baseline_data, baseline_index) {
    Ok(report) => report
    Err(error) => return Err(BaselineLocalsError(baseline_index, error))
  }
  let after = match inspect_function_locals(current_data, current_index) {
    Ok(report) => report
    Err(error) => return Err(CurrentLocalsError(current_index, error))
  }
  let before_types = locals_type_buckets(before)
  let after_types = locals_type_buckets(after)
  let keys : Set[String] = Set([])
  for key, _ in before_types {
    keys.add(key)
  }
  for key, _ in after_types {
    keys.add(key)
  }
  let type_encodings : Array[FunctionLocalsTypeEncoding] = []
  for key in keys {
    let baseline_groups = match before_types.get(key) {
      Some(groups) => groups
      None => []
    }
    let current_groups = match after_types.get(key) {
      Some(groups) => groups
      None => []
    }
    let b = locals_type_totals(baseline_groups)
    let c = locals_type_totals(current_groups)
    type_encodings.push({
      type_hex: key,
      type_label: function_locals_type_label(key),
      presence: if b.group_count == 0 {
        "current_only"
      } else if c.group_count == 0 {
        "baseline_only"
      } else {
        "shared_encoding"
      },
      baseline: b,
      current: c,
      delta: {
        group_count: c.group_count - b.group_count,
        declared_count_delta_decimal: locals_count_delta(
          b.declared_count,
          c.declared_count,
        ),
        quantity_encoding_bytes: c.quantity_encoding_bytes -
        b.quantity_encoding_bytes,
        type_encoding_bytes: c.type_encoding_bytes - b.type_encoding_bytes,
        group_bytes: c.group_bytes - b.group_bytes,
      },
    })
  }
  type_encodings.sort_by(fn(a, b) { a.type_hex.lexical_compare(b.type_hex) })
  Ok({
    baseline: before,
    current: after,
    delta: {
      entry_bytes: after.entry.size - before.entry.size,
      prefix_bytes: after.prefix.size - before.prefix.size,
      body_bytes: after.body.size - before.body.size,
      locals_bytes: after.locals_encoding.size - before.locals_encoding.size,
      group_count_encoding_bytes: after.group_count_encoding.size -
      before.group_count_encoding.size,
      quantity_encoding_bytes: after.quantity_encoding_bytes -
      before.quantity_encoding_bytes,
      type_encoding_bytes: after.type_encoding_bytes -
      before.type_encoding_bytes,
      body_remainder_bytes: after.body_remainder.size -
      before.body_remainder.size,
      group_count: after.group_count - before.group_count,
      declared_count_delta_decimal: locals_count_delta(
        before.declared_count,
        after.declared_count,
      ),
    },
    type_encodings,
    scope: "Explicit user-selected pair; respective function indices include imports. No automatic function, group or variable identity matching. Full raw type_hex is the grouping key, without semantic normalization; equal labels are not keys. Presence depends on groups, including zero-quantity groups. Original groups, order, ranges and actual encoding widths remain in both reports. All deltas are current - baseline; cumulative quantities and their signed differences use exact decimal strings in JSON. No variable expansion, signature parsing, parameter binding, body remainder decoding, graph or ordinary baseline analysis. Neither equal encodings nor zero aggregate deltas prove identical group sequences, remainder bytes, type compatibility or semantics. File offsets are not memory addresses; deltas are not ranges. Selected entry deltas do not explain the whole file or measure runtime stack/memory, safe removal, recompilation or gzip savings. Top limits text type rows only, not totals, member arrays, complete JSON or inspection cost.",
  })
}
