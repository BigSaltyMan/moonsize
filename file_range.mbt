///|
pub struct FileRangePart {
  kind : FileOffsetKind
  owner_range : DataByteRange
  overlap_range : DataByteRange
  query_relative_offset : Int
  owner_relative_offset : Int
  section_index : Int?
  section : Section?
  function : FunctionStat?
  data_segment : DataSegment?
}

///|
pub struct FileRangeReport {
  file_size : Int
  sha256 : String
  query : DataByteRange
  covered_size : Int
  parts : Array[FileRangePart]
  scope : String
}

///|
pub enum FileRangeError {
  FileRangeOutOfRange(Int, Int, Int)
  FileRangeOwnershipError(Int, Int, Int, FileOffsetError)
  InconsistentFileRange(Int, Int, Int, String)
}

///|
pub fn describe_file_range_error(error : FileRangeError) -> String {
  match error {
    FileRangeOutOfRange(offset, length, size) =>
      "file range offset \{offset}, length \{length} is outside input size \{size} (no clipping)"
    FileRangeOwnershipError(offset, length, size, reason) =>
      "file range offset \{offset}, length \{length}, file size \{size}: " +
      describe_file_offset_error(reason)
    InconsistentFileRange(offset, length, size, reason) =>
      "inconsistent file range offset \{offset}, length \{length}, file size \{size}: " +
      reason
  }
}

///|
/// Intersect checked nonnegative file ranges without copying file bytes.
fn file_range_overlap(a : DataByteRange, b : DataByteRange) -> Bool {
  a.size > 0 &&
  b.size > 0 &&
  a.offset < b.offset + b.size &&
  b.offset < a.offset + a.size
}

///|
fn file_range_append(
  parts : Array[FileRangePart],
  part : FileOffsetPart,
  query : DataByteRange,
  section_index : Int?,
  section : Section?,
) -> Unit {
  if !file_range_overlap(part.range, query) {
    return
  }
  let start = if part.range.offset > query.offset {
    part.range.offset
  } else {
    query.offset
  }
  let owner_end = part.range.offset + part.range.size
  let query_end = query.offset + query.size
  let end = if owner_end < query_end { owner_end } else { query_end }
  parts.push({
    kind: part.kind,
    owner_range: part.range,
    overlap_range: { offset: start, size: end - start, },
    query_relative_offset: start - query.offset,
    owner_relative_offset: start - part.range.offset,
    section_index,
    section,
    function: part.function,
    data_segment: part.data_segment,
  })
}

///|
/// Basic module validation still scans section/code structure. Refine only
/// intersected code/data payloads, once each; never decode instructions.
pub fn locate_file_range(
  data : Bytes,
  offset : Int,
  length : Int,
) -> Result[FileRangeReport, FileRangeError] {
  let size = data.length()
  let parsed = match parse_module(data) {
    Ok(value) => value
    Err(error) =>
      return Err(
        FileRangeOwnershipError(
          offset,
          length,
          size,
          FileOffsetInputError(error),
        ),
      )
  }
  if offset < 0 || length < 0 || offset > size || length > size - offset {
    return Err(FileRangeOutOfRange(offset, length, size))
  }
  let query : DataByteRange = { offset, size: length, }
  let parts : Array[FileRangePart] = []
  file_range_append(
    parts,
    {
      kind: ModuleHeader,
      range: { offset: 0, size: 8, },
      function: None,
      data_segment: None,
    },
    query,
    None,
    None,
  )
  let mut cursor = 8
  for ordinal, section in parsed.sections {
    let range = match
      file_offset_range(size, section.offset, section.total_size, offset) {
      Ok(value) => value
      Err(error) =>
        return Err(FileRangeOwnershipError(offset, length, size, error))
    }
    if range.offset != cursor ||
      section.payload_size < 0 ||
      section.payload_size > range.size ||
      range.size - section.payload_size < 2 {
      return Err(
        InconsistentFileRange(
          offset, length, size, "invalid physical section partition",
        ),
      )
    }
    cursor = range.offset + range.size
    let header_size = range.size - section.payload_size
    let header : DataByteRange = { offset: range.offset, size: header_size, }
    let payload : DataByteRange = {
      offset: range.offset + header_size,
      size: section.payload_size,
    }
    file_range_append(
      parts,
      {
        kind: SectionHeader,
        range: header,
        function: None,
        data_segment: None,
      },
      query,
      Some(ordinal),
      Some(section),
    )
    if !file_range_overlap(payload, query) {
      continue
    }
    let detailed = match section.kind {
      Code => file_offset_code_parts(data, parsed, section, payload, offset)
      Data => file_offset_data_parts(data, section, payload, offset)
      _ =>
        Ok([
          {
            kind: SectionPayload,
            range: payload,
            function: None,
            data_segment: None,
          },
        ])
    }
    let detailed = match detailed {
      Ok(value) => value
      Err(error) =>
        return Err(FileRangeOwnershipError(offset, length, size, error))
    }
    for part in detailed {
      file_range_append(parts, part, query, Some(ordinal), Some(section))
    }
  }
  if cursor != size {
    return Err(
      InconsistentFileRange(offset, length, size, "sections do not cover file"),
    )
  }
  let mut covered = 0
  let mut cursor = offset
  for part in parts {
    let overlap = part.overlap_range
    if overlap.size <= 0 ||
      overlap.offset != cursor ||
      !file_offset_within(overlap, query) ||
      !file_offset_within(overlap, part.owner_range) ||
      part.query_relative_offset != overlap.offset - offset ||
      part.owner_relative_offset != overlap.offset - part.owner_range.offset {
      return Err(
        InconsistentFileRange(
          offset, length, size, "invalid or non-contiguous intersection",
        ),
      )
    }
    covered += overlap.size
    cursor = overlap.offset + overlap.size
  }
  if covered != length || cursor != offset + length {
    return Err(
      InconsistentFileRange(
        offset, length, size, "intersections do not cover query",
      ),
    )
  }
  Ok({
    file_size: size,
    sha256: experiment_sha256(data),
    query,
    covered_size: covered,
    parts,
    scope: "Original-file half-open offset + length ownership; owner_range is the full structural region, overlap_range is only the query intersection. Empty ranges are valid, including EOF; out-of-bounds requests are never clipped. Physical section ordinals include custom sections, function indices include imports, data indices retain original order. Only intersected code/data payloads are refined once using shared base ownership partitions. Basic module validation scans section/code structure; selected data reuses its inspector and module checks. Function bodies include locals and instructions, without opcode decoding. Custom/name interiors are undivided. No runtime addresses, expression evaluation, full semantic validation, source identity or deletion benefit. Top limits text rows only, not analysis cost or complete JSON; result memory grows with structural regions.",
  })
}
