///|
pub enum FileOffsetDecodeStatus {
  NotApplicable
  Decoded
} derive(Eq, Debug)

///|
pub enum FileOffsetDecodeDetailKind {
  LocalsEncoding
  Instruction
} derive(Eq, Debug)

///|
pub struct FileOffsetDecodeDetail {
  kind : FileOffsetDecodeDetailKind
  file_offset : Int
  size : Int
  relative_offset : Int
  instruction : FunctionInstructionRecord?
}

///|
pub struct FileOffsetDecodedReport {
  location : FileOffsetReport
  decode_status : FileOffsetDecodeStatus
  detail : FileOffsetDecodeDetail?
  scope : String
}

///|
pub enum FileOffsetDecodeError {
  FileOffsetDecodeLocationError(FileOffsetError)
  FileOffsetDecodeInstructionsError(FunctionInstructionsError)
  InconsistentFileOffsetDecode(Int, String)
}

///|
pub fn describe_file_offset_decode_error(
  error : FileOffsetDecodeError,
) -> String {
  match error {
    FileOffsetDecodeLocationError(error) => describe_file_offset_error(error)
    FileOffsetDecodeInstructionsError(error) =>
      describe_function_instructions_error(error)
    InconsistentFileOffsetDecode(offset, reason) =>
      "inconsistent decoded location for file offset \{offset}: " + reason
  }
}

///|
fn file_offset_decode_range(
  location : FileOffsetReport,
  range : FunctionInstructionRange,
) -> Result[DataByteRange, FileOffsetDecodeError] {
  match
    file_offset_range(
      location.file_size,
      range.file_offset,
      range.size,
      location.offset,
    ) {
    Ok(value) => Ok(value)
    Err(_) =>
      Err(
        InconsistentFileOffsetDecode(
          location.offset,
          "instruction report range exceeds input",
        ),
      )
  }
}

///|
/// Private composition boundary. Both reports must have been produced from
/// the same input in locate_file_offset_decoded, never supplied by a caller.
fn file_offset_decode_detail(
  location : FileOffsetReport,
  decoded : FunctionInstructionsReport,
) -> Result[FileOffsetDecodeDetail, FileOffsetDecodeError] {
  let query = location.offset
  let stat = match location.function {
    Some(value) => value
    None =>
      return Err(
        InconsistentFileOffsetDecode(query, "body has no function owner"),
      )
  }
  if decoded.file_size != location.file_size ||
    decoded.sha256 != location.sha256 ||
    decoded.index != stat.index ||
    decoded.name != stat.name ||
    decoded.raw_name != stat.raw_name {
    return Err(
      InconsistentFileOffsetDecode(
        query, "input identity or function identity differs",
      ),
    )
  }
  let entry = match file_offset_decode_range(location, decoded.entry) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let prefix = match file_offset_decode_range(location, decoded.prefix) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let body = match file_offset_decode_range(location, decoded.body) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let locals = match
    file_offset_decode_range(location, decoded.locals_encoding) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  if location.region.kind != FunctionBodyBytes ||
    entry.offset != stat.offset ||
    entry.size != stat.total_size ||
    prefix.offset != entry.offset ||
    prefix.size < 1 ||
    prefix.size > entry.size ||
    body.offset != prefix.offset + prefix.size ||
    body.size != entry.size - prefix.size ||
    body.size != stat.body_size ||
    body.offset != location.region.file_offset ||
    body.size != location.region.size ||
    !file_offset_contains(body, query) ||
    location.region.relative_offset != query - body.offset ||
    locals.offset != body.offset ||
    !file_offset_within(locals, body) {
    return Err(
      InconsistentFileOffsetDecode(
        query, "entry, prefix, body or locals ranges differ",
      ),
    )
  }
  let first = locals.offset + locals.size // checked against input and body
  let mut cursor = first
  let mut selected : FileOffsetDecodeDetail? = if file_offset_contains(
      locals, query,
    ) {
    Some({
      kind: LocalsEncoding,
      file_offset: locals.offset,
      size: locals.size,
      relative_offset: query - locals.offset,
      instruction: None,
    })
  } else {
    None
  }
  for ordinal, instruction in decoded.instructions {
    let range = match
      file_offset_decode_range(location, {
        file_offset: instruction.file_offset,
        size: instruction.encoded_size,
      }) {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    if range.offset != cursor ||
      range.size <= 0 ||
      !file_offset_within(range, body) ||
      instruction.ordinal != ordinal ||
      instruction.body_relative_offset != range.offset - body.offset {
      return Err(
        InconsistentFileOffsetDecode(
          query, "noncontiguous or inconsistent instruction evidence",
        ),
      )
    }
    if file_offset_contains(range, query) {
      if selected is Some(_) {
        return Err(
          InconsistentFileOffsetDecode(query, "multiple decoded owners"),
        )
      }
      selected = Some({
        kind: Instruction,
        file_offset: range.offset,
        size: range.size,
        relative_offset: query - range.offset,
        instruction: Some(instruction),
      })
    }
    cursor = range.offset + range.size // checked before addition
  }
  if cursor - body.offset != body.size ||
    decoded.instruction_bytes != cursor - first ||
    decoded.instruction_bytes != body.size - locals.size ||
    decoded.instruction_count != decoded.instructions.length() {
    return Err(
      InconsistentFileOffsetDecode(
        query, "decoded body byte ledger does not close",
      ),
    )
  }
  match selected {
    Some(detail) => Ok(detail)
    None => Err(InconsistentFileOffsetDecode(query, "no unique decoded owner"))
  }
}

///|
/// One base location; only a function-body hit invokes the existing complete
/// single-function decoder, exactly once. A target decode error is never hidden.
pub fn locate_file_offset_decoded(
  data : Bytes,
  offset : Int,
) -> Result[FileOffsetDecodedReport, FileOffsetDecodeError] {
  let location = match locate_file_offset(data, offset) {
    Ok(value) => value
    Err(error) => return Err(FileOffsetDecodeLocationError(error))
  }
  let scope = "Optional refinement of one local function body using the existing instruction decoder. Non-body bytes are not_applicable and trigger no instruction decoding. An applicable target must decode completely, even for a locals query; other functions are only range/name checked. Existing entries may repeat structural/name checks and whole-file hashing. Opcode, extended subopcode and immediate bytes belong to their entire instruction; operand fields/values are not identified. No WAT, call-target inference, execution frequency, timing or optimization savings. This does not certify other functions or complete Wasm type, stack or control-flow semantics. All offsets are file bytes, not memory addresses."
  if location.region.kind != FunctionBodyBytes {
    return Ok({ location, decode_status: NotApplicable, detail: None, scope, })
  }
  let index = match location.function {
    Some(stat) => stat.index
    None =>
      return Err(
        InconsistentFileOffsetDecode(offset, "body has no local function index"),
      )
  }
  let decoded = match inspect_function_instructions(data, index) {
    Ok(value) => value
    Err(error) => return Err(FileOffsetDecodeInstructionsError(error))
  }
  let detail = match file_offset_decode_detail(location, decoded) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  Ok({ location, decode_status: Decoded, detail: Some(detail), scope, })
}
