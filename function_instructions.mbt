///|
/// Half-open original-file range; not a memory address.
pub struct FunctionInstructionRange {
  file_offset : Int
  size : Int
}

///|
pub struct FunctionInstructionRecord {
  ordinal : Int
  mnemonic : String
  file_offset : Int
  body_relative_offset : Int
  encoded_size : Int
}

///|
pub struct FunctionOpcodeGroup {
  mnemonic : String
  count : Int
  encoded_bytes : Int
}

///|
pub struct FunctionInstructionsReport {
  file_size : Int
  sha256 : String
  index : Int
  name : String
  raw_name : String?
  entry : FunctionInstructionRange
  prefix : FunctionInstructionRange
  body : FunctionInstructionRange
  locals_encoding : FunctionInstructionRange
  instruction_bytes : Int
  instruction_count : Int
  groups : Array[FunctionOpcodeGroup]
  instructions : Array[FunctionInstructionRecord]
  scope : String
}

///|
pub enum FunctionInstructionsError {
  InstructionsInputError(WasmError)
  InvalidInstructionsTarget(Int, Int)
  ImportedInstructionsTarget(Int)
  InvalidInstructionsRange(Int, String)
}

///|
pub fn describe_function_instructions_error(
  error : FunctionInstructionsError,
) -> String {
  match error {
    InstructionsInputError(error) => describe_error(error)
    InvalidInstructionsTarget(index, count) =>
      "target function index \{index} is outside the function index space of \{count}"
    ImportedInstructionsTarget(index) =>
      "target function \{index} is imported and has no local body"
    InvalidInstructionsRange(offset, reason) =>
      "invalid function instruction range at file offset \{offset}: \{reason}"
  }
}

///|
/// Decode only the selected local body, once. Other bodies are range-scanned.
pub fn inspect_function_instructions(
  data : Bytes,
  index : Int,
) -> Result[FunctionInstructionsReport, FunctionInstructionsError] {
  let parsed = match parse_module(data) {
    Ok(value) => value
    Err(error) => return Err(InstructionsInputError(error))
  }
  let sections = find_sections(parsed)
  let imported = match sections.imports {
    None => 0
    Some(section) =>
      match count_imported_functions(data, section) {
        Ok(value) => value
        Err(error) => return Err(InstructionsInputError(error))
      }
  }
  let stats = match collect_function_stats(parsed, data) {
    Ok(value) => value
    Err(error) => return Err(InstructionsInputError(error))
  }
  let count = imported + stats.length()
  if index < 0 || index >= count {
    return Err(InvalidInstructionsTarget(index, count))
  }
  if index < imported {
    return Err(ImportedInstructionsTarget(index))
  }
  let stat = stats[index - imported]
  let reader = match Reader::new_range(data, stat.offset, stat.total_size) {
    Ok(value) => value
    Err(error) => return Err(InstructionsInputError(error))
  }
  if stat.body_size < 0 || stat.body_size > stat.total_size {
    return Err(InvalidInstructionsRange(stat.offset, "body exceeds entry"))
  }
  let prefix_size = stat.total_size - stat.body_size
  match reader.read_bytes(prefix_size) {
    Ok(_) => ()
    Err(error) => return Err(InstructionsInputError(error))
  }
  let body_offset = reader.position()
  // The bounded entry validates the entire body before offset arithmetic.
  match reader.read_bytes(stat.body_size) {
    Ok(_) => ()
    Err(error) => return Err(InstructionsInputError(error))
  }
  let decoded = match decode_instructions(data, body_offset, stat.body_size) {
    Ok(value) => value
    Err(error) => return Err(InstructionsInputError(error))
  }
  let body_end = reader.position()
  let first = if decoded.is_empty() { body_end } else { decoded[0].offset }
  if first < body_offset || first > body_end {
    return Err(InvalidInstructionsRange(first, "locals boundary outside body"))
  }
  let records : Array[FunctionInstructionRecord] = []
  let by_name : Map[String, FunctionOpcodeGroup] = Map([])
  let mut cursor = first
  let mut instruction_bytes = 0
  for ordinal, instruction in decoded {
    if instruction.offset != cursor ||
      instruction.size <= 0 ||
      instruction.size > body_end - cursor {
      return Err(
        InvalidInstructionsRange(
          instruction.offset,
          "noncontiguous or out-of-bounds instruction",
        ),
      )
    }
    let mnemonic = instruction.opcode.name()
    records.push({
      ordinal,
      mnemonic,
      file_offset: cursor,
      body_relative_offset: cursor - body_offset,
      encoded_size: instruction.size,
    })
    let group = by_name
      .get(mnemonic)
      .unwrap_or({ mnemonic, count: 0, encoded_bytes: 0, })
    by_name.set(mnemonic, {
      mnemonic,
      count: group.count + 1,
      encoded_bytes: group.encoded_bytes + instruction.size,
    })
    cursor += instruction.size
    instruction_bytes += instruction.size
  }
  let groups : Array[FunctionOpcodeGroup] = []
  let mut group_bytes = 0
  let mut group_count = 0
  for _, group in by_name {
    groups.push(group)
    group_bytes += group.encoded_bytes
    group_count += group.count
  }
  let locals_size = first - body_offset
  if cursor != body_end ||
    locals_size + instruction_bytes != stat.body_size ||
    group_bytes != instruction_bytes ||
    group_count != records.length() {
    return Err(
      InvalidInstructionsRange(cursor, "instruction byte ledger does not close"),
    )
  }
  groups.sort_by(fn(a, b) {
    if a.encoded_bytes != b.encoded_bytes {
      b.encoded_bytes.compare(a.encoded_bytes)
    } else if a.count != b.count {
      b.count.compare(a.count)
    } else {
      a.mnemonic.lexical_compare(b.mnemonic)
    }
  })
  Ok({
    file_size: data.length(),
    sha256: experiment_sha256(data),
    index,
    name: stat.name,
    raw_name: stat.raw_name,
    entry: { file_offset: stat.offset, size: stat.total_size, },
    prefix: { file_offset: stat.offset, size: prefix_size, },
    body: { file_offset: body_offset, size: stat.body_size, },
    locals_encoding: { file_offset: body_offset, size: locals_size, },
    instruction_bytes,
    instruction_count: records.length(),
    groups,
    instructions: records,
    scope: "Static encoding of one local function: locals declarations and instructions, excluding the body-length prefix from instruction bytes. File offsets are not memory addresses. Counts are not execution frequencies or timings; bytes do not predict deletion, recompilation or gzip savings. Existing decoder support only; no complete type, control, stack or instantiation validation. Other bodies are not instruction-decoded. Top limits text only, not analysis cost.",
  })
}
