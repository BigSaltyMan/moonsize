///|
pub struct DataHexSearchReport {
  file_size : Int
  sha256 : String
  query_hex : String
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
pub enum DataHexSearchError {
  InvalidDataHexQuery
  DataHexSearchInputError(WasmError)
}

///|
pub fn describe_data_hex_search_error(error : DataHexSearchError) -> String {
  match error {
    InvalidDataHexQuery =>
      "hex query must contain a nonempty even number of ASCII hexadecimal digits, without spaces, prefixes or separators"
    DataHexSearchInputError(error) => describe_error(error)
  }
}

///|
fn data_hex_nibble(code : Int) -> Int {
  if code >= 0x30 && code <= 0x39 {
    code - 0x30
  } else if code >= 0x61 && code <= 0x66 {
    code - 0x61 + 10
  } else if code >= 0x41 && code <= 0x46 {
    code - 0x41 + 10
  } else {
    -1
  }
}

///|
/// Shared syntax check for library and CLI; no byte pattern allocation or trim.
fn data_hex_search_valid(query : String) -> Bool {
  if query.is_empty() || query.length() % 2 != 0 {
    return false
  }
  for ch in query.iter() {
    if data_hex_nibble(ch.to_int()) < 0 {
      return false
    }
  }
  true
}

///|
/// Decode ASCII pairs directly into bytes; never use UTF-8 as an intermediate.
pub fn search_data_segments_hex(
  data : Bytes,
  query_hex : String,
) -> Result[DataHexSearchReport, DataHexSearchError] {
  if !data_hex_search_valid(query_hex) {
    return Err(InvalidDataHexQuery)
  }
  let bytes : Array[Byte] = []
  let mut high = -1
  for ch in query_hex.iter() {
    let value = data_hex_nibble(ch.to_int())
    if high < 0 {
      high = value
    } else {
      bytes.push(((high << 4) | value).to_byte())
      high = -1
    }
  }
  let needle = Bytes::from_array(bytes)
  let canonical = StringBuilder()
  for byte in needle {
    canonical.write_string(byte.to_hex())
  }
  let report = match inspect_data_segments(data) {
    Ok(report) => report
    Err(error) => return Err(DataHexSearchInputError(error))
  }
  let (matches, matched_segment_count) = data_search_matches(
    data, report, needle,
  )
  Ok({
    file_size: data.length(),
    sha256: experiment_sha256(data),
    query_hex: canonical.to_string(),
    query_size: needle.length(),
    matching_rule: "Exact bytes decoded from compact ASCII hex pairs; letter case is equivalent and reports use lowercase. Overlapping occurrences retained within each payload, never across entries or in encoding metadata. No trimming, spaces, separators, prefixes, escapes or wildcards. No UTF-8 conversion or automatic encoding detection.",
    scope: "Hits record exact query bytes in initialization payloads, not independent strings, source constants or used resources. No match does not prove content is absent. File offsets are not memory addresses. No encoding/source attribution, safe merging or deletion/rebuilt/gzip savings are inferred. Overlapping occurrence lengths cannot be added as occupied content bytes. Offset expressions remain unevaluated. Top limits text position rows only, not search cost or full JSON; memory grows with occurrences. The normalized pattern itself is saved in reports; no payload context is output.",
    data_segments: report,
    segment_count: report.entries.length(),
    matched_segment_count,
    unmatched_segment_count: report.entries.length() - matched_segment_count,
    occurrence_count: matches.length(),
    matches,
  })
}
