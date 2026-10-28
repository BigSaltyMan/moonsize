///|
/// Only matching instructions, retaining ordinals from the complete sequence.
pub struct OpcodeSearchFunction {
  stat : FunctionStat
  match_count : Int
  matched_encoded_bytes : Int
  sites : Array[FunctionInstructionRecord]
}

///|
pub struct OpcodeSearchReport {
  file_size : Int
  sha256 : String
  query : String
  matching_rule : String
  scope : String
  imported_function_count : Int
  scanned_local_function_count : Int
  matched_function_count : Int
  unmatched_function_count : Int
  instruction_count : Int
  instruction_bytes : Int
  match_count : Int
  matched_encoded_bytes : Int
  other_instruction_bytes : Int
  functions : Array[OpcodeSearchFunction]
}

///|
/// Existing module opcode errors retain structure/body/evidence distinctions.
pub enum OpcodeSearchError {
  InvalidOpcodeSearchQuery
  OpcodeSearchInputError(ModuleOpcodeError)
}

///|
pub fn describe_opcode_search_error(error : OpcodeSearchError) -> String {
  match error {
    InvalidOpcodeSearchQuery =>
      "opcode query must not be empty or all whitespace"
    OpcodeSearchInputError(error) => describe_module_opcode_error(error)
  }
}

///|
/// decoded stays local; only matching records escape. No allocation of records
/// for nonmatching instructions, and no promise of immediate memory reclamation.
fn opcode_search_function(
  data : Bytes,
  stat : FunctionStat,
  query : String,
) -> Result[(OpcodeSearchFunction?, Int, Int), ModuleOpcodeError] {
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
  let sites : Array[FunctionInstructionRecord] = []
  let mut cursor = first
  let mut instruction_bytes = 0
  let mut matched_encoded_bytes = 0
  for ordinal, instruction in decoded {
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
    if mnemonic == query {
      sites.push({
        ordinal,
        mnemonic,
        file_offset: cursor,
        body_relative_offset: cursor - body_offset,
        encoded_size: instruction.size,
      })
      matched_encoded_bytes += instruction.size
    }
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
  let matched = if sites.is_empty() {
    None
  } else {
    Some({ stat, match_count: sites.length(), matched_encoded_bytes, sites, })
  }
  Ok((matched, decoded.length(), instruction_bytes))
}

///|
/// Inspect query first; collect module/function/name ranges once, then decode
/// each local body once. No prior statistics report, graph or per-function inspector.
pub fn search_opcode(
  data : Bytes,
  query : String,
) -> Result[OpcodeSearchReport, OpcodeSearchError] {
  if query.trim().is_empty() {
    return Err(InvalidOpcodeSearchQuery)
  }
  let parsed = match parse_module(data) {
    Ok(parsed) => parsed
    Err(error) =>
      return Err(OpcodeSearchInputError(ModuleOpcodeInputError(error)))
  }
  let sections = find_sections(parsed)
  let imported = match sections.imports {
    Some(section) =>
      match count_imported_functions(data, section) {
        Ok(count) => count
        Err(error) =>
          return Err(OpcodeSearchInputError(ModuleOpcodeInputError(error)))
      }
    None => 0
  }
  let bodies = match sections.code {
    Some(section) =>
      match parse_code_section(data, section, base_index=imported) {
        Ok(bodies) => bodies
        Err(error) =>
          return Err(OpcodeSearchInputError(ModuleOpcodeInputError(error)))
      }
    None => []
  }
  let names = match sections.names {
    Some(section) => parse_name_section(data, section)
    None => None
  }
  let stats = function_stats(bodies, names)
  let functions : Array[OpcodeSearchFunction] = []
  let mut instruction_count = 0
  let mut instruction_bytes = 0
  let mut match_count = 0
  let mut matched_encoded_bytes = 0
  for local_ordinal, stat in stats {
    // The bounded code parser establishes index/file order and complete payload.
    if stat.index != imported + local_ordinal {
      return Err(
        OpcodeSearchInputError(
          InvalidModuleOpcodeEvidence(
            Some(stat.index),
            Some(stat.offset),
            "function index differs from local declaration order",
          ),
        ),
      )
    }
    let (matched, count, bytes) = match
      opcode_search_function(data, stat, query) {
      Ok(result) => result
      Err(error) => return Err(OpcodeSearchInputError(error))
    }
    instruction_count += count
    instruction_bytes += bytes
    if matched is Some(matched) {
      match_count += matched.match_count
      matched_encoded_bytes += matched.matched_encoded_bytes
      functions.push(matched)
    }
  }
  Ok({
    file_size: data.length(),
    sha256: experiment_sha256(data),
    query,
    matching_rule: "Case-sensitive exact equality with the complete decoded Opcode.name(); no trimming, case folding, substring, regex or numeric opcode interpretation. Unknown nonempty names may have no matches.",
    scope: "Static instruction encodings in all local function bodies, including unreachable bodies. Imports have no body. Excludes names/custom/data bytes, locals declarations and global/element/data initializer expressions. File offsets are not memory addresses; ordinal belongs to the complete body instruction sequence. Encoded sizes include opcode, subopcode and immediates. No operand values or source attribution; not execution traces, runtime frequency, full semantic validation or optimization/removal/rebuilt/gzip savings. An empty result says nothing about other regions of the module. Every body is decoded once; any unsupported or malformed body fails the whole report. Only matching records are retained. Top limits text position rows only, not scan cost, full JSON or memory usage; many matches may require substantial memory.",
    imported_function_count: imported,
    scanned_local_function_count: stats.length(),
    matched_function_count: functions.length(),
    unmatched_function_count: stats.length() - functions.length(),
    instruction_count,
    instruction_bytes,
    match_count,
    matched_encoded_bytes,
    other_instruction_bytes: instruction_bytes - matched_encoded_bytes,
    functions,
  })
}
