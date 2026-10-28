///|
/// Relative positional evidence, with absent bytes/file offsets kept distinct
/// from actual zero bytes. status has four stable encoding-fact values.
pub struct DataPreviewPosition {
  window_relative_offset : Int
  status : String
  baseline_byte : Int?
  current_byte : Int?
  baseline_file_offset : Int?
  current_file_offset : Int?
} derive(Eq, Debug)

///|
pub struct DataPreviewComparison {
  baseline : DataPreviewReport
  current : DataPreviewReport
  same_count : Int
  different_count : Int
  baseline_only_count : Int
  current_only_count : Int
  compared_positions : Int
  returned_size_delta : Int
  positions : Array[DataPreviewPosition]
  scope : String
}

///|
pub enum DataPreviewComparisonError {
  BaselineDataPreviewError(DataPreviewError)
  CurrentDataPreviewError(DataPreviewError)
}

///|
pub fn describe_data_preview_comparison_error(
  error : DataPreviewComparisonError,
) -> String {
  match error {
    BaselineDataPreviewError(error) =>
      "baseline: " + describe_data_preview_error(error)
    CurrentDataPreviewError(error) =>
      "current: " + describe_data_preview_error(error)
  }
}

///|
/// Preview each explicit side once, then compare at most 4096 relative positions.
/// No resource matching, prior search/diff-data, edit alignment or ordinary analysis.
pub fn compare_data_previews(
  baseline_data : Bytes,
  baseline_index : Int,
  baseline_offset : Int,
  current_data : Bytes,
  current_index : Int,
  current_offset : Int,
  limit : Int,
) -> Result[DataPreviewComparison, DataPreviewComparisonError] {
  let before = match
    preview_data_segment(baseline_data, baseline_index, baseline_offset, limit) {
    Ok(report) => report
    Err(error) => return Err(BaselineDataPreviewError(error))
  }
  let after = match
    preview_data_segment(current_data, current_index, current_offset, limit) {
    Ok(report) => report
    Err(error) => return Err(CurrentDataPreviewError(error))
  }
  let positions : Array[DataPreviewPosition] = []
  let count = before.returned_size.max(after.returned_size)
  let mut same_count = 0
  let mut different_count = 0
  let mut baseline_only_count = 0
  let mut current_only_count = 0
  for i in 0..<count {
    let (baseline_byte, baseline_file_offset) = if i < before.returned_size {
      (Some(before.bytes[i].to_int()), Some(before.window.offset + i))
    } else {
      (None, None)
    }
    let (current_byte, current_file_offset) = if i < after.returned_size {
      (Some(after.bytes[i].to_int()), Some(after.window.offset + i))
    } else {
      (None, None)
    }
    let status = match (baseline_byte, current_byte) {
      (Some(b), Some(c)) =>
        if b == c {
          same_count += 1
          "same_byte"
        } else {
          different_count += 1
          "different_byte"
        }
      (Some(_), None) => {
        baseline_only_count += 1
        "baseline_only"
      }
      _ => {
        current_only_count += 1
        "current_only"
      }
    }
    positions.push({
      window_relative_offset: i,
      status,
      baseline_byte,
      current_byte,
      baseline_file_offset,
      current_file_offset,
    })
  }
  Ok({
    baseline: before,
    current: after,
    same_count,
    different_count,
    baseline_only_count,
    current_only_count,
    compared_positions: count,
    returned_size_delta: after.returned_size - before.returned_size,
    positions,
    scope: "Explicit user-selected bounded payload windows compared at equal window-relative positions, not matched resources. No insertion/deletion alignment, edit distance or minimal edit operations. same_byte/different_byte/baseline_only/current_only describe byte presence and value only, not semantic additions/removals. Missing bytes and offsets stay null, never zero-padded. Equal selected windows do not prove equal whole payloads, files or resource identity. Reports include actual window contents (up to 4096 bytes per side); file offsets are not memory addresses, expressions remain unevaluated, and no encoding/source/runtime or optimization/rebuilt/gzip benefit is inferred. Both offsets independently default to zero in the CLI; one common limit clips each side independently. Full positions are shown with no Top truncation.",
  })
}
