///|
pub enum FileOffsetKind {
  ModuleHeader
  SectionHeader
  SectionPayload
  CodeCount
  FunctionSizePrefix
  FunctionBodyBytes
  DataEntryCount
  DataEntryMetadata
  DataPayload
} derive(Eq, Debug)

///|
/// A half-open file range and the query's byte position within that range.
pub struct FileOffsetRegion {
  kind : FileOffsetKind
  file_offset : Int
  size : Int
  relative_offset : Int
} derive(Eq, Debug)

///|
pub struct FileOffsetReport {
  file_size : Int
  sha256 : String
  offset : Int
  section_index : Int?
  section : Section?
  function : FunctionStat?
  data_segment : DataSegment?
  region : FileOffsetRegion
  scope : String
}

///|
pub enum FileOffsetError {
  FileOffsetOutOfRange(Int, Int)
  FileOffsetInputError(WasmError)
  InconsistentFileOffsetRange(Int, String)
}

///|
pub fn describe_file_offset_error(error : FileOffsetError) -> String {
  match error {
    FileOffsetOutOfRange(offset, size) =>
      "file offset \{offset} is outside [0, \{size}); EOF has no byte"
    FileOffsetInputError(error) => describe_error(error)
    InconsistentFileOffsetRange(offset, reason) =>
      "inconsistent file range ownership for offset \{offset}: " + reason
  }
}

///|
priv struct FileOffsetPart {
  kind : FileOffsetKind
  range : DataByteRange
  function : FunctionStat?
  data_segment : DataSegment?
}

///|
fn file_offset_range(
  file_size : Int,
  start : Int,
  size : Int,
  query : Int,
) -> Result[DataByteRange, FileOffsetError] {
  if start < 0 || size < 0 || start > file_size || size > file_size - start {
    return Err(InconsistentFileOffsetRange(query, "range exceeds input"))
  }
  Ok({ offset: start, size, })
}

///|
fn file_offset_contains(range : DataByteRange, query : Int) -> Bool {
  query >= range.offset && query - range.offset < range.size
}

///|
/// Both ranges have already been checked against the input.
fn file_offset_within(inner : DataByteRange, outer : DataByteRange) -> Bool {
  inner.offset >= outer.offset &&
  inner.offset - outer.offset <= outer.size &&
  inner.size <= outer.size - (inner.offset - outer.offset)
}

///|
/// Require a contiguous partition, including zero-sized bodies/payloads. Never
/// fall back to section_payload on a gap, overlap or missing detailed owner.
fn file_offset_partition(
  parts : Array[FileOffsetPart],
  parent : DataByteRange,
  file_size : Int,
  query : Int,
) -> Result[FileOffsetPart, FileOffsetError] {
  let mut cursor = parent.offset
  let mut selected : FileOffsetPart? = None
  for part in parts {
    let range = match
      file_offset_range(file_size, part.range.offset, part.range.size, query) {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    if range.offset != cursor || !file_offset_within(range, parent) {
      return Err(
        InconsistentFileOffsetRange(query, "non-contiguous detailed ranges"),
      )
    }
    if file_offset_contains(range, query) {
      if selected is Some(_) {
        return Err(
          InconsistentFileOffsetRange(query, "multiple detailed owners"),
        )
      }
      selected = Some(part)
    }
    cursor = range.offset + range.size // checked above, at most file_size
  }
  if cursor - parent.offset != parent.size {
    return Err(
      InconsistentFileOffsetRange(query, "detailed ranges do not cover payload"),
    )
  }
  match selected {
    Some(value) => Ok(value)
    None => Err(InconsistentFileOffsetRange(query, "no detailed owner"))
  }
}

///|
fn file_offset_code(
  data : Bytes,
  parsed : WasmModule,
  section : Section,
  payload : DataByteRange,
  query : Int,
) -> Result[FileOffsetPart, FileOffsetError] {
  let stats = match collect_function_stats(parsed, data) {
    Ok(value) => value
    Err(error) => return Err(FileOffsetInputError(error))
  }
  let reader = match reader_at_payload(data, section) {
    Ok(value) => value
    Err(error) => return Err(FileOffsetInputError(error))
  }
  let count = match read_u32_as_int(reader) {
    Ok(value) => value
    Err(error) => return Err(FileOffsetInputError(error))
  }
  if count != stats.length() {
    return Err(
      InconsistentFileOffsetRange(
        query, "code count differs from local definitions",
      ),
    )
  }
  let parts : Array[FileOffsetPart] = [
    {
      kind: CodeCount,
      range: {
        offset: payload.offset,
        size: reader.position() - payload.offset,
      },
      function: None,
      data_segment: None,
    },
  ]
  for stat in stats {
    let encoded = match
      file_offset_range(data.length(), stat.offset, stat.total_size, query) {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    if !file_offset_within(encoded, payload) ||
      stat.body_size < 0 ||
      stat.body_size >= stat.total_size {
      return Err(
        InconsistentFileOffsetRange(query, "invalid local function range"),
      )
    }
    let prefix = stat.total_size - stat.body_size
    parts.push({
      kind: FunctionSizePrefix,
      range: { offset: stat.offset, size: prefix, },
      function: Some(stat),
      data_segment: None,
    })
    parts.push({
      kind: FunctionBodyBytes,
      range: { offset: stat.offset + prefix, size: stat.body_size, },
      function: Some(stat),
      data_segment: None,
    })
  }
  file_offset_partition(parts, payload, data.length(), query)
}

///|
fn file_offset_data(
  data : Bytes,
  section : Section,
  payload : DataByteRange,
  query : Int,
) -> Result[FileOffsetPart, FileOffsetError] {
  let details = match inspect_data_segments(data) {
    Ok(value) => value
    Err(error) => return Err(FileOffsetInputError(error))
  }
  match details.section {
    Some(found) if found.offset == section.offset &&
      found.total_size == section.total_size => ()
    _ =>
      return Err(
        InconsistentFileOffsetRange(
          query, "data inspector selected another section",
        ),
      )
  }
  let parts : Array[FileOffsetPart] = [
    {
      kind: DataEntryCount,
      range: { offset: payload.offset, size: details.count_size, },
      function: None,
      data_segment: None,
    },
  ]
  for entry in details.entries {
    let encoded = match
      file_offset_range(
        data.length(),
        entry.encoding.offset,
        entry.encoding.size,
        query,
      ) {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    let content = match
      file_offset_range(
        data.length(),
        entry.payload.offset,
        entry.payload.size,
        query,
      ) {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    if !file_offset_within(encoded, payload) ||
      !file_offset_within(content, encoded) {
      return Err(
        InconsistentFileOffsetRange(query, "data entry escapes its owner"),
      )
    }
    let metadata_size = content.offset - encoded.offset
    if content.size != encoded.size - metadata_size || metadata_size < 2 {
      return Err(
        InconsistentFileOffsetRange(
          query, "data payload does not end at entry end",
        ),
      )
    }
    parts.push({
      kind: DataEntryMetadata,
      range: { offset: encoded.offset, size: metadata_size, },
      function: None,
      data_segment: Some(entry),
    })
    parts.push({
      kind: DataPayload,
      range: content,
      function: None,
      data_segment: Some(entry),
    })
  }
  file_offset_partition(parts, payload, data.length(), query)
}

///|
/// Parse structural ranges, then refine only the selected code/data payload.
/// No function instruction decoding, graph construction or ordinary analysis.
pub fn locate_file_offset(
  data : Bytes,
  offset : Int,
) -> Result[FileOffsetReport, FileOffsetError] {
  let parsed = match parse_module(data) {
    Ok(value) => value
    Err(error) => return Err(FileOffsetInputError(error))
  }
  if offset < 0 || offset >= data.length() {
    return Err(FileOffsetOutOfRange(offset, data.length()))
  }
  let mut selected_section : (Int, Section)? = None
  let mut cursor = 8
  for ordinal, section in parsed.sections {
    let range = match
      file_offset_range(
        data.length(),
        section.offset,
        section.total_size,
        offset,
      ) {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    if range.offset != cursor ||
      section.payload_size < 0 ||
      section.payload_size > range.size ||
      range.size - section.payload_size < 2 {
      return Err(
        InconsistentFileOffsetRange(
          offset, "invalid physical section partition",
        ),
      )
    }
    if file_offset_contains(range, offset) {
      if selected_section is Some(_) {
        return Err(
          InconsistentFileOffsetRange(offset, "multiple physical sections"),
        )
      }
      selected_section = Some((ordinal, section))
    }
    cursor = range.offset + range.size
  }
  if cursor != data.length() {
    return Err(
      InconsistentFileOffsetRange(offset, "sections do not cover file"),
    )
  }
  let (section_index, section, part) = match selected_section {
    None if offset < 8 =>
      (
        None,
        None,
        FileOffsetPart::{
          kind: ModuleHeader,
          range: { offset: 0, size: 8, },
          function: None,
          data_segment: None,
        },
      )
    None =>
      return Err(InconsistentFileOffsetRange(offset, "no physical section"))
    Some((ordinal, section)) => {
      let header_size = section.total_size - section.payload_size
      let header = DataByteRange::{ offset: section.offset, size: header_size, }
      let payload = DataByteRange::{
        offset: section.offset + header_size,
        size: section.payload_size,
      }
      let part = if file_offset_contains(header, offset) {
        FileOffsetPart::{
          kind: SectionHeader,
          range: header,
          function: None,
          data_segment: None,
        }
      } else {
        match section.kind {
          Code =>
            match file_offset_code(data, parsed, section, payload, offset) {
              Ok(value) => value
              Err(error) => return Err(error)
            }
          Data =>
            match file_offset_data(data, section, payload, offset) {
              Ok(value) => value
              Err(error) => return Err(error)
            }
          _ =>
            FileOffsetPart::{
              kind: SectionPayload,
              range: payload,
              function: None,
              data_segment: None,
            }
        }
      }
      (Some(ordinal), Some(section), part)
    }
  }
  if !file_offset_contains(part.range, offset) {
    return Err(
      InconsistentFileOffsetRange(offset, "query outside selected region"),
    )
  }
  Ok({
    file_size: data.length(),
    sha256: experiment_sha256(data),
    offset,
    section_index,
    section,
    function: part.function,
    data_segment: part.data_segment,
    region: {
      kind: part.kind,
      file_offset: part.range.offset,
      size: part.range.size,
      relative_offset: offset - part.range.offset,
    },
    scope: "Original-file byte ownership with half-open ranges; physical section ordinals include custom sections, function indices include imports, data indices retain original order. Only selected code/data payloads are refined. Function bodies include locals and instructions without opcode decoding; other payload interiors remain undivided. data_count is the data entry count field, not the separate datacount section. Offset expressions are not evaluated. Base module checks scan all section/code ranges; selected code adds local stats and best-effort names, selected data reuses a full data inspection and its module checks. SHA-256 covers the whole input. This is not full Wasm semantic validation, a runtime address, source attribution or deletion benefit.",
  })
}
