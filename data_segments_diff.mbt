///|
pub enum DataPayloadGroupKind {
  SharedPayload
  BaselineOnly
  CurrentOnly
} derive(Eq, Debug)

///|
/// Totals on either side, or signed current-minus-baseline deltas.
pub struct DataGroupTotals {
  count : Int
  payload_size : Int
  encoded_size : Int
  metadata_size : Int
} derive(Eq, Debug)

///|
/// A content group, never an assertion of cross-build entry identity. The local
/// id distinguishes even different byte groups with an identical full digest.
pub struct DataPayloadGroup {
  id : Int
  sha256 : String
  payload_length : Int
  kind : DataPayloadGroupKind
  baseline_indices : Array[Int]
  current_indices : Array[Int]
  baseline : DataGroupTotals
  current : DataGroupTotals
  delta : DataGroupTotals
}

///|
pub struct DataSegmentsDelta {
  section_size : Int
  payload_size : Int
  entry_metadata_size : Int
  section_overhead_size : Int
} derive(Eq, Debug)

///|
pub struct DataSegmentsComparison {
  baseline_sha256 : String
  current_sha256 : String
  baseline : DataSegmentsReport
  current : DataSegmentsReport
  groups : Array[DataPayloadGroup]
  delta : DataSegmentsDelta
}

///|
/// Views live only during grouping; the public report retains metadata only.
priv struct DataPayloadBucket {
  sha256 : String
  bytes : BytesView
  baseline_indices : Array[Int]
  current_indices : Array[Int]
  mut baseline_encoded : Int
  mut current_encoded : Int
  mut baseline_payload : Int
  mut current_payload : Int
}

///|
fn data_payload_equal(a : BytesView, b : BytesView) -> Bool {
  if a.length() != b.length() {
    return false
  }
  for i = 0; i < a.length(); i = i + 1 {
    if a[i] != b[i] {
      return false
    }
  }
  true
}

///|
/// Digest hits only select candidates. Length and bytes decide membership.
fn collect_data_payloads(
  data : Bytes,
  report : DataSegmentsReport,
  is_baseline : Bool,
  buckets : Array[DataPayloadBucket],
  by_hash : Map[String, Array[Int]],
) -> Unit {
  for entry in report.entries {
    let range = entry.payload
    let bytes = data[range.offset:range.offset + range.size]
    // The current crypto API takes Bytes. This temporary copy is not retained.
    let hash = experiment_sha256(bytes.to_owned())
    let candidates = match by_hash.get(hash) {
      Some(indices) => indices
      None => {
        let indices = []
        by_hash.set(hash, indices)
        indices
      }
    }
    let mut found : Int? = None
    for index in candidates {
      if data_payload_equal(buckets[index].bytes, bytes) {
        found = Some(index)
        break
      }
    }
    let index = match found {
      Some(index) => index
      None => {
        let index = buckets.length()
        buckets.push({
          sha256: hash,
          bytes,
          baseline_indices: [],
          current_indices: [],
          baseline_encoded: 0,
          current_encoded: 0,
          baseline_payload: 0,
          current_payload: 0,
        })
        candidates.push(index)
        index
      }
    }
    let bucket = buckets[index]
    if is_baseline {
      bucket.baseline_indices.push(entry.index)
      bucket.baseline_encoded += entry.encoding.size
      bucket.baseline_payload += range.size
    } else {
      bucket.current_indices.push(entry.index)
      bucket.current_encoded += entry.encoding.size
      bucket.current_payload += range.size
    }
  }
}

///|
/// Exact payload groups after safe inspection of both inputs. No offset
/// evaluation, stable entry identity, semantic-equivalence or savings inference.
pub fn compare_data_segments(
  baseline : Bytes,
  current : Bytes,
) -> Result[DataSegmentsComparison, ComparisonError] {
  let before = match inspect_data_segments(baseline) {
    Ok(report) => report
    Err(error) => return Err(Baseline(error))
  }
  let after = match inspect_data_segments(current) {
    Ok(report) => report
    Err(error) => return Err(Current(error))
  }
  let buckets : Array[DataPayloadBucket] = []
  let by_hash : Map[String, Array[Int]] = Map([])
  collect_data_payloads(baseline, before, true, buckets, by_hash)
  collect_data_payloads(current, after, false, buckets, by_hash)
  // Stable file discovery order: baseline first, then current-only contents.
  let groups = buckets.mapi(fn(id, bucket) {
    let baseline : DataGroupTotals = {
      count: bucket.baseline_indices.length(),
      payload_size: bucket.baseline_payload,
      encoded_size: bucket.baseline_encoded,
      metadata_size: bucket.baseline_encoded - bucket.baseline_payload,
    }
    let current : DataGroupTotals = {
      count: bucket.current_indices.length(),
      payload_size: bucket.current_payload,
      encoded_size: bucket.current_encoded,
      metadata_size: bucket.current_encoded - bucket.current_payload,
    }
    DataPayloadGroup::{
      id,
      sha256: bucket.sha256,
      payload_length: bucket.bytes.length(),
      kind: if baseline.count == 0 {
        CurrentOnly
      } else if current.count == 0 {
        BaselineOnly
      } else {
        SharedPayload
      },
      baseline_indices: bucket.baseline_indices,
      current_indices: bucket.current_indices,
      baseline,
      current,
      delta: {
        count: current.count - baseline.count,
        payload_size: current.payload_size - baseline.payload_size,
        encoded_size: current.encoded_size - baseline.encoded_size,
        metadata_size: current.metadata_size - baseline.metadata_size,
      },
    }
  })
  Ok({
    baseline_sha256: experiment_sha256(baseline),
    current_sha256: experiment_sha256(current),
    baseline: before,
    current: after,
    groups,
    delta: {
      section_size: after.section_size - before.section_size,
      payload_size: after.payload_size - before.payload_size,
      entry_metadata_size: after.entry_metadata_size -
      before.entry_metadata_size,
      section_overhead_size: after.header_size +
      after.count_size -
      (before.header_size + before.count_size),
    },
  })
}
