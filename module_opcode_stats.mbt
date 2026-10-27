///|
/// Complete instruction encoding bytes include opcode, subopcode and immediates.
pub struct ModuleOpcodeGroup {
  mnemonic : String
  count : Int
  encoded_bytes : Int
  function_count : Int
}

///|
/// Compact local-function facts, without instructions or an opcode matrix.
pub struct ModuleOpcodeFunction {
  stat : FunctionStat
  locals_encoding : FunctionInstructionRange
  instruction_count : Int
  instruction_bytes : Int
}

///|
pub struct ModuleOpcodeReport {
  file_size : Int
  sha256 : String
  code_section : Section?
  count_encoding : FunctionInstructionRange?
  imported_function_count : Int
  local_function_count : Int
  code_header_bytes : Int
  count_encoding_bytes : Int
  body_prefix_bytes : Int
  locals_encoding_bytes : Int
  instruction_bytes : Int
  instruction_count : Int
  groups : Array[ModuleOpcodeGroup]
  functions : Array[ModuleOpcodeFunction]
  scope : String
}

///|
pub enum ModuleOpcodeError {
  ModuleOpcodeInputError(WasmError)
  ModuleOpcodeBodyError(Int, WasmError)
  InvalidModuleOpcodeEvidence(Int?, Int?, String)
}

///|
pub fn describe_module_opcode_error(error : ModuleOpcodeError) -> String {
  match error {
    ModuleOpcodeInputError(error) => describe_error(error)
    ModuleOpcodeBodyError(index, error) =>
      "function \{index}: " + describe_error(error)
    InvalidModuleOpcodeEvidence(index, offset, reason) =>
      "invalid module opcode evidence" +
      (match index {
        Some(index) => " for function \{index}"
        None => ""
      }) +
      (match offset {
        Some(offset) => " at file offset \{offset}"
        None => ""
      }) +
      ": " +
      reason
  }
}

///|
/// The decoded array and per-function set do not escape this helper. This makes
/// no promise about the runtime's exact garbage-collection/release timing.
fn module_opcode_function(
  data : Bytes,
  stat : FunctionStat,
  totals : Map[String, ModuleOpcodeGroup],
) -> Result[ModuleOpcodeFunction, ModuleOpcodeError] {
  if stat.body_size < 0 || stat.body_size >= stat.total_size {
    return Err(
      InvalidModuleOpcodeEvidence(
        Some(stat.index),
        Some(stat.offset),
        "body/prefix range differs",
      ),
    )
  }
  let reader = match Reader::new_range(data, stat.offset, stat.total_size) {
    Ok(reader) => reader
    Err(error) => return Err(ModuleOpcodeBodyError(stat.index, error))
  }
  match reader.read_bytes(stat.total_size - stat.body_size) {
    Ok(_) => ()
    Err(error) => return Err(ModuleOpcodeBodyError(stat.index, error))
  }
  let body_offset = reader.position()
  match reader.read_bytes(stat.body_size) {
    Ok(_) => ()
    Err(error) => return Err(ModuleOpcodeBodyError(stat.index, error))
  }
  let body_end = reader.position()
  let decoded = match decode_instructions(data, body_offset, stat.body_size) {
    Ok(decoded) => decoded
    Err(error) => return Err(ModuleOpcodeBodyError(stat.index, error))
  }
  let first = if decoded.is_empty() { body_end } else { decoded[0].offset }
  if first < body_offset || first > body_end {
    return Err(
      InvalidModuleOpcodeEvidence(
        Some(stat.index),
        Some(body_offset),
        "locals boundary outside body",
      ),
    )
  }
  let seen : Set[String] = Set([])
  let mut cursor = first
  let mut instruction_bytes = 0
  for instruction in decoded {
    if instruction.offset != cursor ||
      instruction.size <= 0 ||
      instruction.size > body_end - cursor {
      return Err(
        InvalidModuleOpcodeEvidence(
          Some(stat.index),
          Some(instruction.offset),
          "noncontiguous or out-of-bounds instruction",
        ),
      )
    }
    let mnemonic = instruction.opcode.name()
    let first_in_function = !seen.contains(mnemonic)
    seen.add(mnemonic)
    let previous = totals
      .get(mnemonic)
      .unwrap_or({ mnemonic, count: 0, encoded_bytes: 0, function_count: 0, })
    totals.set(mnemonic, {
      mnemonic,
      count: previous.count + 1,
      encoded_bytes: previous.encoded_bytes + instruction.size,
      function_count: previous.function_count +
      (if first_in_function { 1 } else { 0 }),
    })
    cursor += instruction.size
    instruction_bytes += instruction.size
  }
  if cursor != body_end ||
    instruction_bytes != stat.body_size - (first - body_offset) {
    return Err(
      InvalidModuleOpcodeEvidence(
        Some(stat.index),
        Some(cursor),
        "instruction ledger does not close",
      ),
    )
  }
  Ok({
    stat,
    locals_encoding: { file_offset: body_offset, size: first - body_offset, },
    instruction_count: decoded.length(),
    instruction_bytes,
  })
}

///|
/// Collect ranges first, then decode each local body once. No repeated module
/// inspection per function, graph, retained or initializer-expression decoding.
pub fn inspect_module_opcodes(
  data : Bytes,
) -> Result[ModuleOpcodeReport, ModuleOpcodeError] {
  let parsed = match parse_module(data) {
    Ok(parsed) => parsed
    Err(error) => return Err(ModuleOpcodeInputError(error))
  }
  let sections = find_sections(parsed)
  let imported = match sections.imports {
    Some(section) =>
      match count_imported_functions(data, section) {
        Ok(count) => count
        Err(error) => return Err(ModuleOpcodeInputError(error))
      }
    None => 0
  }
  let bodies = match sections.code {
    Some(section) =>
      match parse_code_section(data, section, base_index=imported) {
        Ok(bodies) => bodies
        Err(error) => return Err(ModuleOpcodeInputError(error))
      }
    None => []
  }
  let names = match sections.names {
    Some(section) => parse_name_section(data, section)
    None => None
  }
  let stats = function_stats(bodies, names)
  let totals : Map[String, ModuleOpcodeGroup] = Map([])
  let functions : Array[ModuleOpcodeFunction] = []
  let mut count_encoding : FunctionInstructionRange? = None
  let mut code_header_bytes = 0
  let mut count_encoding_bytes = 0
  let mut body_prefix_bytes = 0
  let mut locals_encoding_bytes = 0
  let mut instruction_bytes = 0
  let mut instruction_count = 0
  let mut entry_bytes = 0
  if sections.code is Some(code) {
    let reader = match reader_at_payload(data, code) {
      Ok(reader) => reader
      Err(error) => return Err(ModuleOpcodeInputError(error))
    }
    let count_offset = reader.position()
    let count = match read_u32_as_int(reader) {
      Ok(count) => count
      Err(error) => return Err(ModuleOpcodeInputError(error))
    }
    code_header_bytes = code.total_size - code.payload_size
    count_encoding_bytes = reader.position() - count_offset
    count_encoding = Some({
      file_offset: count_offset,
      size: count_encoding_bytes,
    })
    if count != stats.length() {
      return Err(
        InvalidModuleOpcodeEvidence(
          None,
          Some(count_offset),
          "function count differs from collected ranges",
        ),
      )
    }
    for ordinal, stat in stats {
      // parse_code_section already checked full-index addition and entry ranges.
      if stat.index != imported + ordinal || stat.offset != reader.position() {
        return Err(
          InvalidModuleOpcodeEvidence(
            Some(stat.index),
            Some(stat.offset),
            "function entries are not contiguous in index/file order",
          ),
        )
      }
      match reader.read_bytes(stat.total_size) {
        Ok(_) => ()
        Err(error) => return Err(ModuleOpcodeBodyError(stat.index, error))
      }
      let summary = match module_opcode_function(data, stat, totals) {
        Ok(summary) => summary
        Err(error) => return Err(error)
      }
      functions.push(summary)
      entry_bytes += stat.total_size
      body_prefix_bytes += stat.total_size - stat.body_size
      locals_encoding_bytes += summary.locals_encoding.size
      instruction_bytes += summary.instruction_bytes
      instruction_count += summary.instruction_count
    }
    if !reader.at_end() ||
      entry_bytes !=
      body_prefix_bytes + locals_encoding_bytes + instruction_bytes ||
      code.total_size != code_header_bytes + count_encoding_bytes + entry_bytes {
      return Err(
        InvalidModuleOpcodeEvidence(
          None,
          Some(reader.position()),
          "code section byte ledger does not close",
        ),
      )
    }
  }
  let groups : Array[ModuleOpcodeGroup] = []
  let mut grouped_bytes = 0
  let mut grouped_count = 0
  for _, group in totals {
    if group.function_count <= 0 ||
      group.function_count > stats.length() ||
      group.function_count > group.count {
      return Err(
        InvalidModuleOpcodeEvidence(
          None,
          None,
          "opcode function count is inconsistent",
        ),
      )
    }
    grouped_bytes += group.encoded_bytes
    grouped_count += group.count
    groups.push(group)
  }
  if grouped_bytes != instruction_bytes || grouped_count != instruction_count {
    return Err(
      InvalidModuleOpcodeEvidence(
        None,
        None,
        "opcode/function aggregates do not close",
      ),
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
    code_section: sections.code,
    count_encoding,
    imported_function_count: imported,
    local_function_count: stats.length(),
    code_header_bytes,
    count_encoding_bytes,
    body_prefix_bytes,
    locals_encoding_bytes,
    instruction_bytes,
    instruction_count,
    groups,
    functions,
    scope: "Static encodings in all local function bodies, without reachability filtering. Imports have no local body or synthetic zero-byte row. Global, element and data initializer expressions are excluded. Each local body is decoded once after collecting checked ranges/names; no per-function reparse of the module, analyze, graph, retained, calls or local-accesses report. Any unsupported/unknown/truncated body fails the entire report with its full function index and original decoder error; no partial success. Complete encoding bytes include opcode, extension subopcode and immediates; counts are not execution frequency or runtime hotspots. Distinct function counts are deduplicated per mnemonic per body; summing them does not give the local-function total. Only opcode aggregates and compact function summaries are retained, not instructions, occurrence lists or an opcode-by-function matrix. Runtime memory release timing is not guaranteed. Missing code differs from an explicit zero-function section; zero-instruction structural results do not validate function termination or full type/stack/control semantics. File offsets are not memory addresses; encoded bytes do not predict runtime memory, deletion/recompilation or gzip/transfer shares. Top limits text opcode rows only, not totals, complete JSON, all-body decoding cost or resource usage.",
  })
}
