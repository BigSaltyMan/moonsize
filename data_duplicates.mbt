///|
/// A content group in this input only; id is its smallest original entry index.
pub struct DuplicateDataGroup {
  id : Int
  sha256 : String
  payload_size : Int
  member_count : Int
  member_indices : Array[Int]
  member_payload_bytes : Int
  member_metadata_bytes : Int
  member_encoded_bytes : Int
}

///|
/// Duplicate-member bytes count ALL members, never estimated removable bytes.
pub struct DuplicateDataSummary {
  segment_count : Int
  duplicate_group_count : Int
  duplicate_member_count : Int
  singleton_count : Int
  total_payload_bytes : Int
  duplicate_member_payload_bytes : Int
  singleton_payload_bytes : Int
  total_entry_encoded_bytes : Int
  total_entry_metadata_bytes : Int
  duplicate_member_metadata_bytes : Int
  duplicate_member_encoded_bytes : Int
  singleton_metadata_bytes : Int
  singleton_encoded_bytes : Int
  data_section_bytes : Int
  section_header_bytes : Int
  count_prefix_bytes : Int
} derive(Eq, Debug)

///|
pub struct DuplicateDataReport {
  file_size : Int
  sha256 : String
  comparison_scope : String
  data_segments : DataSegmentsReport
  groups : Array[DuplicateDataGroup]
  summary : DuplicateDataSummary
}

///|
priv enum DuplicateDataKey {
  DuplicateDataKey(String, Int)
} derive(Eq, Hash)

///|
/// Temporary input views; neither views nor payload copies enter the report.
priv struct DuplicateDataBucket {
  sha256 : String
  bytes : BytesView
  indices : Array[Int]
  mut payload_bytes : Int
  mut metadata_bytes : Int
  mut encoded_bytes : Int
}

///|
/// Inputs are nonnegative sizes/counts from bounded data entries. Their unsigned
/// sum fits u32 (two nonnegative Int values); check BEFORE narrowing to Int.
fn duplicate_data_add(a : Int, b : Int, offset : Int) -> Result[Int, WasmError] {
  let sum = a.reinterpret_as_uint() + b.reinterpret_as_uint()
  if sum > 2147483647U {
    Err(ValueOutOfRange(offset, sum))
  } else {
    Ok(sum.reinterpret_as_int())
  }
}

///|
/// Hash/length only select candidates. Separate from hashing to test collisions
/// privately, without a public hash override or changes to the older grouper.
fn duplicate_data_insert(
  buckets : Array[DuplicateDataBucket],
  by_digest : Map[DuplicateDataKey, Array[Int]],
  digest : String,
  bytes : BytesView,
  entry : DataSegment,
) -> Result[Unit, WasmError] {
  let key = DuplicateDataKey(digest, bytes.length())
  let candidates = by_digest.get(key).unwrap_or([])
  for index in candidates {
    let bucket = buckets[index]
    if data_payload_equal(bucket.bytes, bytes) {
      let payload = match
        duplicate_data_add(
          bucket.payload_bytes,
          entry.payload.size,
          entry.payload.offset,
        ) {
        Ok(n) => n
        Err(e) => return Err(e)
      }
      let metadata = match
        duplicate_data_add(
          bucket.metadata_bytes,
          entry.encoding.size - entry.payload.size,
          entry.encoding.offset,
        ) {
        Ok(n) => n
        Err(e) => return Err(e)
      }
      let encoded = match
        duplicate_data_add(
          bucket.encoded_bytes,
          entry.encoding.size,
          entry.encoding.offset,
        ) {
        Ok(n) => n
        Err(e) => return Err(e)
      }
      bucket.indices.push(entry.index)
      bucket.payload_bytes = payload
      bucket.metadata_bytes = metadata
      bucket.encoded_bytes = encoded
      return Ok(())
    }
  }
  candidates.push(buckets.length())
  by_digest.set(key, candidates)
  buckets.push({
    sha256: digest,
    bytes,
    indices: [entry.index],
    payload_bytes: entry.payload.size,
    metadata_bytes: entry.encoding.size - entry.payload.size,
    encoded_bytes: entry.encoding.size,
  })
  Ok(())
}

///|
fn duplicate_data_groups(
  buckets : Array[DuplicateDataBucket],
) -> Array[DuplicateDataGroup] {
  let groups : Array[DuplicateDataGroup] = []
  for bucket in buckets {
    if bucket.indices.length() < 2 {
      continue
    }
    bucket.indices.sort_by(fn(a, b) { a.compare(b) })
    groups.push({
      id: bucket.indices[0],
      sha256: bucket.sha256,
      payload_size: bucket.bytes.length(),
      member_count: bucket.indices.length(),
      member_indices: bucket.indices,
      member_payload_bytes: bucket.payload_bytes,
      member_metadata_bytes: bucket.metadata_bytes,
      member_encoded_bytes: bucket.encoded_bytes,
    })
  }
  groups.sort_by(fn(a, b) {
    let total = b.member_payload_bytes.compare(a.member_payload_bytes)
    if total != 0 {
      return total
    }
    let size = b.payload_size.compare(a.payload_size)
    if size != 0 {
      return size
    }
    a.id.compare(b.id)
  })
  groups
}

///|
fn duplicate_data_scope() -> String {
  "Exact DataSegment.payload bytes only; mode, memory index, offset expression and payload length prefix do not determine grouping. " +
  "SHA-256 and length select candidates; all bytes are checked, including digest collisions. Empty payloads participate and zero-byte groups remain visible. " +
  "duplicate_member_payload_bytes counts ALL members in duplicate groups, not a one-copy remainder or savings estimate. " +
  "Equal content does not prove equivalent initialization targets, timing or uses, safe merging, removal or recompiled/whole-file gzip reduction. " +
  "Group ids are minimum original indices, valid only within this report, not cross-build identities. " +
  "Top limits text groups and each group previews at most 20 members; JSON and summaries are complete. " +
  data_scope()
}

///|
/// Single inspection and one digest per entry. No self-comparison, analyze,
/// graph, expression evaluation, similarity search or retained payload copies.
pub fn inspect_duplicate_data(
  data : Bytes,
) -> Result[DuplicateDataReport, WasmError] {
  let source = match inspect_data_segments(data) {
    Ok(r) => r
    Err(e) => return Err(e)
  }
  let buckets : Array[DuplicateDataBucket] = []
  let by_digest : Map[DuplicateDataKey, Array[Int]] = Map([])
  for entry in source.entries {
    let reader = match
      Reader::new_range(data, entry.payload.offset, entry.payload.size) {
      Ok(r) => r
      Err(e) => return Err(e)
    }
    let bytes = match reader.read_bytes(entry.payload.size) {
      Ok(b) => b
      Err(e) => return Err(e)
    }
    // The current SHA API requires Bytes. The temporary copy is not retained.
    let digest = experiment_sha256(bytes.to_owned())
    match duplicate_data_insert(buckets, by_digest, digest, bytes, entry) {
      Ok(_) => ()
      Err(e) => return Err(e)
    }
  }
  let groups = duplicate_data_groups(buckets)
  let mut members = 0
  let mut payload = 0
  let mut metadata = 0
  let mut encoded = 0
  for group in groups {
    let offset = source.entries[group.id].encoding.offset
    members = match duplicate_data_add(members, group.member_count, offset) {
      Ok(n) => n
      Err(e) => return Err(e)
    }
    payload = match
      duplicate_data_add(payload, group.member_payload_bytes, offset) {
      Ok(n) => n
      Err(e) => return Err(e)
    }
    metadata = match
      duplicate_data_add(metadata, group.member_metadata_bytes, offset) {
      Ok(n) => n
      Err(e) => return Err(e)
    }
    encoded = match
      duplicate_data_add(encoded, group.member_encoded_bytes, offset) {
      Ok(n) => n
      Err(e) => return Err(e)
    }
  }
  let total_encoded = match
    duplicate_data_add(
      source.payload_size,
      source.entry_metadata_size,
      source.section.map(fn(s) { s.offset }).unwrap_or(0),
    ) {
    Ok(n) => n
    Err(e) => return Err(e)
  }
  // Each inspected entry was inserted exactly once into one bucket. Duplicate
  // totals are subsets of the bounded source ledger; these subtractions cannot
  // be negative or overflow. Products are avoided in favor of checked sums.
  Ok({
    file_size: data.length(),
    sha256: experiment_sha256(data),
    comparison_scope: duplicate_data_scope(),
    data_segments: source,
    groups,
    summary: {
      segment_count: source.entries.length(),
      duplicate_group_count: groups.length(),
      duplicate_member_count: members,
      singleton_count: source.entries.length() - members,
      total_payload_bytes: source.payload_size,
      duplicate_member_payload_bytes: payload,
      singleton_payload_bytes: source.payload_size - payload,
      total_entry_encoded_bytes: total_encoded,
      total_entry_metadata_bytes: source.entry_metadata_size,
      duplicate_member_metadata_bytes: metadata,
      duplicate_member_encoded_bytes: encoded,
      singleton_metadata_bytes: source.entry_metadata_size - metadata,
      singleton_encoded_bytes: total_encoded - encoded,
      data_section_bytes: source.section_size,
      section_header_bytes: source.header_size,
      count_prefix_bytes: source.count_size,
    },
  })
}
