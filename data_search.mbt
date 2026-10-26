///|
pub struct DataSearchMatch {
  segment_index : Int
  payload_offset : Int
  file_offset : Int
  size : Int
} derive(Eq, Debug)

///|
/// Full results, ordered by original segment index and payload byte offset.
pub struct DataSearchReport {
  file_size : Int
  sha256 : String
  query : String
  query_size : Int
  matching_rule : String
  scope : String
  data_segments : DataSegmentsReport
  segment_count : Int
  matched_segment_count : Int
  unmatched_segment_count : Int
  occurrence_count : Int
  matches : Array[DataSearchMatch]
}

///|
pub enum DataSearchError {
  EmptyDataSearchQuery
  DataSearchInputError(WasmError)
}

///|
pub fn describe_data_search_error(error : DataSearchError) -> String {
  match error {
    EmptyDataSearchQuery => "data search query must not be empty"
    DataSearchInputError(error) => describe_error(error)
  }
}

///|
/// KMP prefix table; each mismatch follows a previously computed proper suffix.
fn data_search_prefix(query : Bytes) -> Array[Int] {
  let prefix = Array::make(query.length(), 0)
  let mut matched = 0
  for i = 1; i < query.length(); i = i + 1 {
    while matched > 0 && query[i] != query[matched] {
      matched = prefix[matched - 1]
    }
    if query[i] == query[matched] {
      matched += 1
    }
    prefix[i] = matched
  }
  prefix
}

///|
/// One structural inspection and query encoding. Linear in query bytes,
/// payload bytes and occurrences; retains every hit, including overlaps.
/// Payload bytes are neither copied nor decoded as text. No function decoding
/// or graph analysis is performed beyond the inspector's module checks.
pub fn search_data_segments(
  data : Bytes,
  query : String,
) -> Result[DataSearchReport, DataSearchError] {
  if query.is_empty() {
    return Err(EmptyDataSearchQuery)
  }
  let needle = @utf8.encode(query)
  let report = match inspect_data_segments(data) {
    Ok(value) => value
    Err(error) => return Err(DataSearchInputError(error))
  }
  let prefix = data_search_prefix(needle)
  let matches : Array[DataSearchMatch] = []
  let mut matched_segment_count = 0
  for entry in report.entries {
    let mut matched = 0
    let mut found = false
    // Ranges were checked by inspect_data_segments against this same input.
    for i = 0; i < entry.payload.size; i = i + 1 {
      let byte = data[entry.payload.offset + i]
      while matched > 0 && byte != needle[matched] {
        matched = prefix[matched - 1]
      }
      if byte == needle[matched] {
        matched += 1
      }
      if matched == needle.length() {
        let payload_offset = i + 1 - needle.length()
        matches.push({
          segment_index: entry.index,
          payload_offset,
          file_offset: entry.payload.offset + payload_offset,
          size: needle.length(),
        })
        found = true
        matched = prefix[matched - 1]
      }
    }
    if found {
      matched_segment_count += 1
    }
  }
  Ok({
    file_size: data.length(),
    sha256: experiment_sha256(data),
    query,
    query_size: needle.length(),
    matching_rule: "Case-sensitive literal UTF-8 byte matching within each data payload; overlapping occurrences retained. No trimming, Unicode normalization, escape interpretation, regex or UTF-16 guessing. Invalid UTF-8 elsewhere in a payload is allowed. Never matches across entries or searches encoding metadata.",
    scope: "A hit only records query bytes in an initialization payload, not an independent string, source constant or used resource. No match does not prove content is absent: compiler string encodings may differ. File offsets are not memory addresses. No deletion savings or safe deduplication are inferred. Overlapping occurrence lengths must not be added as occupied bytes. Offset expressions remain unevaluated. Top limits text rows only, not search cost or complete JSON; result memory grows with occurrences. The query itself is included in reports.",
    data_segments: report,
    segment_count: report.entries.length(),
    matched_segment_count,
    unmatched_segment_count: report.entries.length() - matched_segment_count,
    occurrence_count: matches.length(),
    matches,
  })
}
