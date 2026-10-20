///|
/// Half-open encoded range in the original file, never a memory address.
pub struct DataByteRange {
  offset : Int
  size : Int
} derive(Eq, Debug)

///|
pub enum DataSegmentMode {
  Active
  Passive
} derive(Eq, Debug)

///|
/// Metadata only: no payload copy and no evaluation of the offset expression.
pub struct DataSegment {
  index : Int
  mode : DataSegmentMode
  memory_index : Int?
  encoding : DataByteRange
  payload : DataByteRange
  offset_expression : DataByteRange?
  mode_size : Int
  memory_index_size : Int
  payload_length_size : Int
} derive(Eq, Debug)

///|
/// DataCount is separate and excluded from the data-section byte ledger.
/// Absent data has section=None and all ledger sizes zero; an empty section
/// still has a header and an encoded zero count. Entries remain in file order.
pub struct DataSegmentsReport {
  file_size : Int
  section : Section?
  datacount : Int?
  section_size : Int
  header_size : Int
  count_size : Int
  payload_size : Int
  entry_metadata_size : Int
  entries : Array[DataSegment]
}

///|
/// Inspect data encodings after the ordinary module structure checks. This is
/// not type/constant-expression validation, memory-index validation or an
/// instantiation check. Expression ranges include their final end instruction.
pub fn inspect_data_segments(
  data : Bytes,
) -> Result[DataSegmentsReport, WasmError] {
  let parsed = match parse_module(data) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let mut section : Section? = None
  let mut datacount : Int? = None
  let mut datacount_offset = 0
  for item in parsed.sections {
    match item.kind {
      Data => section = Some(item)
      DataCount => {
        let reader = match reader_at_payload(data, item) {
          Ok(value) => value
          Err(error) => return Err(error)
        }
        datacount_offset = reader.position()
        datacount = match read_u32_as_int(reader) {
          Ok(value) => Some(value)
          Err(error) => return Err(error)
        }
        match finish_section(reader, DataCount) {
          Ok(_) => ()
          Err(error) => return Err(error)
        }
      }
      _ => ()
    }
  }
  let entries : Array[DataSegment] = []
  let mut count_size = 0
  let mut payload_size = 0
  let mut entry_metadata_size = 0
  let mut section_size = 0
  let mut header_size = 0
  if section is Some(item) {
    section_size = item.total_size
    header_size = item.total_size - item.payload_size
    let reader = match reader_at_payload(data, item) {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    let count_start = reader.position()
    let count = match read_u32_as_int(reader) {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    count_size = reader.position() - count_start
    for index = 0; index < count; index = index + 1 {
      let start = reader.position()
      let flags = match read_u32_as_int(reader) {
        Ok(value) => value
        Err(error) => return Err(error)
      }
      let mode_size = reader.position() - start
      let mut memory_index : Int? = None
      let mut memory_index_size = 0
      let mode = match flags {
        0 => {
          memory_index = Some(0)
          Active
        }
        1 => Passive
        2 => {
          let memory_start = reader.position()
          memory_index = match read_u32_as_int(reader) {
            Ok(value) => Some(value)
            Err(error) => return Err(error)
          }
          memory_index_size = reader.position() - memory_start
          Active
        }
        _ =>
          return Err(
            WasmError::InvalidDataEncoding(
              start,
              "unsupported data segment mode " + flags.to_string(),
            ),
          )
      }
      let offset_expression = if mode == Active {
        let offset = reader.position()
        match skip_constant_expression(reader) {
          Ok(_) => ()
          Err(error) => return Err(error)
        }
        Some(DataByteRange::{ offset, size: reader.position() - offset, })
      } else {
        None
      }
      let length_start = reader.position()
      let length = match read_u32_as_int(reader) {
        Ok(value) => value
        Err(error) => return Err(error)
      }
      let payload_length_size = reader.position() - length_start
      let payload_offset = reader.position()
      // A checked view only, not a copy of the initializer bytes.
      match reader.read_bytes(length) {
        Ok(_) => ()
        Err(error) => return Err(error)
      }
      let size = reader.position() - start
      payload_size += length
      entry_metadata_size += size - length
      entries.push({
        index,
        mode,
        memory_index,
        encoding: { offset: start, size, },
        payload: { offset: payload_offset, size: length, },
        offset_expression,
        mode_size,
        memory_index_size,
        payload_length_size,
      })
    }
    match finish_section(reader, Data) {
      Ok(_) => ()
      Err(error) => return Err(error)
    }
  }
  if datacount is Some(declared) && declared != entries.length() {
    return Err(
      WasmError::InvalidDataEncoding(
        datacount_offset,
        "datacount mismatch: " +
        declared.to_string() +
        " declared, " +
        entries.length().to_string() +
        " data entries",
      ),
    )
  }
  Ok({
    file_size: parsed.file_size,
    section,
    datacount,
    section_size,
    header_size,
    count_size,
    payload_size,
    entry_metadata_size,
    entries,
  })
}
