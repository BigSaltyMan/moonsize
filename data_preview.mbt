///|
/// One bounded payload window. File offsets never represent memory addresses.
pub struct DataPreviewReport {
  file_size : Int
  sha256 : String
  segment_count : Int
  segment : DataSegment
  payload_offset : Int
  requested_limit : Int
  window : DataByteRange
  returned_size : Int
  remaining_bytes : Int
  bytes : Bytes
  scope : String
}

///|
pub enum DataPreviewError {
  InvalidDataPreviewLimit(Int)
  InvalidDataPreviewIndex(Int, Int)
  InvalidDataPreviewOffset(Int, Int)
  DataPreviewInputError(WasmError)
}

///|
pub fn describe_data_preview_error(error : DataPreviewError) -> String {
  match error {
    InvalidDataPreviewLimit(limit) =>
      "data preview limit must be in 1..4096, got \{limit}"
    InvalidDataPreviewIndex(index, count) =>
      "data preview segment index \{index} is outside \{count} entries"
    InvalidDataPreviewOffset(offset, size) =>
      "data preview payload offset \{offset} is outside 0..\{size} bytes"
    DataPreviewInputError(error) => describe_error(error)
  }
}

///|
/// Inspect all data encodings once, then copy at most 4096 bytes from one
/// payload. Does not analyze functions, build a graph or run content search.
pub fn preview_data_segment(
  data : Bytes,
  index : Int,
  offset : Int,
  limit : Int,
) -> Result[DataPreviewReport, DataPreviewError] {
  if limit < 1 || limit > 4096 {
    return Err(InvalidDataPreviewLimit(limit))
  }
  let report = match inspect_data_segments(data) {
    Ok(value) => value
    Err(error) => return Err(DataPreviewInputError(error))
  }
  if index < 0 || index >= report.entries.length() {
    return Err(InvalidDataPreviewIndex(index, report.entries.length()))
  }
  let segment = report.entries[index]
  if offset < 0 || offset > segment.payload.size {
    return Err(InvalidDataPreviewOffset(offset, segment.payload.size))
  }
  let available = segment.payload.size - offset
  let returned_size = limit.min(available)
  // The inspector bounded this payload against the same input. These sums
  // cannot exceed its checked end (or the input length); offset+limit is never used.
  let start = segment.payload.offset + offset
  let end = start + returned_size
  Ok({
    file_size: data.length(),
    sha256: experiment_sha256(data),
    segment_count: report.entries.length(),
    segment,
    payload_offset: offset,
    requested_limit: limit,
    window: { offset: start, size: returned_size, },
    returned_size,
    remaining_bytes: available - returned_size,
    bytes: data[start:end].to_owned(),
    scope: "This report contains actual bytes from a bounded initialization payload window, not a full payload export. Offsets are decimal file/payload byte offsets, not runtime memory addresses. Offset expressions are not evaluated. A window may split multibyte characters; no text encoding is inferred. Printable ASCII alone is shown literally; other bytes become dots. No source attribution, liveness, safe merging or deletion savings are inferred. The inspector checks all data encodings, not just the selected entry. No Top truncation: the entire returned window is shown.",
  })
}
