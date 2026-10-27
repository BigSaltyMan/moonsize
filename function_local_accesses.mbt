///|
/// One encoded access; ordinal belongs to the full instruction sequence.
pub struct FunctionLocalAccess {
  instruction_ordinal : Int
  opcode : Opcode
  local_index : Int
  file_offset : Int
  body_relative_offset : Int
  encoded_size : Int
  index_encoding : FunctionInstructionRange
}

///|
/// Sparse numeric index group; members retain all original instruction ordinals.
pub struct FunctionLocalAccessGroup {
  local_index : Int
  access_count : Int
  get_count : Int
  set_count : Int
  tee_count : Int
  encoded_bytes : Int
  index_encoding_bytes : Int
  instruction_ordinals : Array[Int]
}

///|
pub struct FunctionLocalAccessesReport {
  file_size : Int
  sha256 : String
  target : FunctionPathNode
  entry : FunctionInstructionRange
  prefix : FunctionInstructionRange
  body : FunctionInstructionRange
  locals_encoding : FunctionInstructionRange
  instruction_count : Int
  instruction_bytes : Int
  access_count : Int
  get_count : Int
  set_count : Int
  tee_count : Int
  distinct_local_index_count : Int
  access_encoding_bytes : Int
  index_encoding_bytes : Int
  other_instruction_bytes : Int
  accesses : Array[FunctionLocalAccess]
  groups : Array[FunctionLocalAccessGroup]
  scope : String
}

///|
pub enum FunctionLocalAccessesError {
  LocalAccessesInputError(WasmError)
  InvalidLocalAccessesTarget(Int, Int)
  ImportedLocalAccessesTarget(Int)
  InvalidLocalAccessesEvidence(Int?, String)
}

///|
pub fn describe_function_local_accesses_error(
  error : FunctionLocalAccessesError,
) -> String {
  match error {
    LocalAccessesInputError(error) => describe_error(error)
    InvalidLocalAccessesTarget(index, count) =>
      "target function index \{index} is outside the function index space of \{count}"
    ImportedLocalAccessesTarget(index) =>
      "target function \{index} is imported and has no local body"
    InvalidLocalAccessesEvidence(offset, reason) =>
      "invalid local-access evidence" +
      (match offset {
        Some(at) => " at file offset \{at}"
        None => ""
      }) +
      ": " +
      reason
  }
}

///|
/// Decode the selected body once. No graph, locals inspection, prior instruction
/// report, signature parsing or secondary operand decoding.
pub fn inspect_function_local_accesses(
  data : Bytes,
  index : Int,
) -> Result[FunctionLocalAccessesReport, FunctionLocalAccessesError] {
  let parsed = match parse_module(data) {
    Ok(value) => value
    Err(error) => return Err(LocalAccessesInputError(error))
  }
  let inventory = match path_inventory(data, parsed) {
    Ok(value) => value
    Err(error) => return Err(LocalAccessesInputError(error))
  }
  if index < 0 || index >= inventory.length() {
    return Err(InvalidLocalAccessesTarget(index, inventory.length()))
  }
  let target = inventory[index]
  if target.imported {
    return Err(ImportedLocalAccessesTarget(index))
  }
  let mut imported = 0
  for node in inventory {
    if !node.imported {
      break
    }
    imported += 1
  }
  let code = match find_sections(parsed).code {
    Some(value) => value
    None =>
      return Err(
        InvalidLocalAccessesEvidence(None, "local function has no code section"),
      )
  }
  let bodies = match parse_code_section(data, code, base_index=imported) {
    Ok(value) => value
    Err(error) => return Err(LocalAccessesInputError(error))
  }
  if index < imported || bodies.length() != inventory.length() - imported {
    return Err(
      InvalidLocalAccessesEvidence(
        Some(code.offset),
        "inventory and local body counts differ",
      ),
    )
  }
  let target_body = bodies[index - imported]
  if target.index != index ||
    target_body.index != index ||
    target.encoded_size != Some(target_body.total_size) ||
    target_body.body_size < 0 ||
    target_body.body_size >= target_body.total_size {
    return Err(
      InvalidLocalAccessesEvidence(
        Some(target_body.offset),
        "target identity or body range differs",
      ),
    )
  }
  let reader = match
    Reader::new_range(data, target_body.offset, target_body.total_size) {
    Ok(value) => value
    Err(error) => return Err(LocalAccessesInputError(error))
  }
  let prefix_size = target_body.total_size - target_body.body_size
  match reader.read_bytes(prefix_size) {
    Ok(_) => ()
    Err(error) => return Err(LocalAccessesInputError(error))
  }
  let body_offset = reader.position()
  match reader.read_bytes(target_body.body_size) {
    Ok(_) => ()
    Err(error) => return Err(LocalAccessesInputError(error))
  }
  let body_end = reader.position()
  let decoded = match
    decode_instructions(data, body_offset, target_body.body_size) {
    Ok(value) => value
    Err(error) => return Err(LocalAccessesInputError(error))
  }
  let first = if decoded.is_empty() { body_end } else { decoded[0].offset }
  if first < body_offset || first > body_end {
    return Err(
      InvalidLocalAccessesEvidence(
        Some(body_offset),
        "locals range exceeds body",
      ),
    )
  }
  let accesses : Array[FunctionLocalAccess] = []
  let buckets : Map[Int, Array[FunctionLocalAccess]] = Map([])
  let mut cursor = first
  let mut instruction_bytes = 0
  let mut access_encoding_bytes = 0
  let mut index_encoding_bytes = 0
  let mut get_count = 0
  let mut set_count = 0
  let mut tee_count = 0
  for ordinal, instruction in decoded {
    if instruction.offset != cursor ||
      instruction.size <= 0 ||
      instruction.size > body_end - cursor {
      return Err(
        InvalidLocalAccessesEvidence(
          Some(instruction.offset),
          "instruction range is not contiguous within body",
        ),
      )
    }
    cursor += instruction.size
    instruction_bytes += instruction.size
    match instruction.opcode {
      LocalGet | LocalSet | LocalTee => ()
      _ => continue
    }
    if instruction.operands.length() != 1 ||
      instruction.operands[0] < 0 ||
      instruction.size < 2 {
      return Err(
        InvalidLocalAccessesEvidence(
          Some(instruction.offset),
          "local access needs exactly one nonnegative index and its encoded bytes",
        ),
      )
    }
    // Single-byte opcode; validated size >= 2 within body before this addition.
    let index_encoding : FunctionInstructionRange = {
      file_offset: instruction.offset + 1,
      size: instruction.size - 1,
    }
    let access : FunctionLocalAccess = {
      instruction_ordinal: ordinal,
      opcode: instruction.opcode,
      local_index: instruction.operands[0],
      file_offset: instruction.offset,
      body_relative_offset: instruction.offset - body_offset,
      encoded_size: instruction.size,
      index_encoding,
    }
    accesses.push(access)
    match buckets.get(access.local_index) {
      Some(records) => records.push(access)
      None => buckets.set(access.local_index, [access])
    }
    match instruction.opcode {
      LocalGet => get_count += 1
      LocalSet => set_count += 1
      LocalTee => tee_count += 1
      _ => ()
    }
    access_encoding_bytes += instruction.size
    index_encoding_bytes += index_encoding.size
  }
  let groups : Array[FunctionLocalAccessGroup] = []
  let mut grouped_count = 0
  let mut grouped_bytes = 0
  for local_index, records in buckets {
    let ordinals : Array[Int] = []
    let mut gets = 0
    let mut sets = 0
    let mut tees = 0
    let mut bytes = 0
    let mut index_bytes = 0
    for record in records {
      ordinals.push(record.instruction_ordinal)
      match record.opcode {
        LocalGet => gets += 1
        LocalSet => sets += 1
        LocalTee => tees += 1
        _ => ()
      }
      bytes += record.encoded_size
      index_bytes += record.index_encoding.size
    }
    grouped_count += records.length()
    grouped_bytes += bytes
    groups.push({
      local_index,
      access_count: records.length(),
      get_count: gets,
      set_count: sets,
      tee_count: tees,
      encoded_bytes: bytes,
      index_encoding_bytes: index_bytes,
      instruction_ordinals: ordinals,
    })
  }
  groups.sort_by(fn(a, b) { a.local_index.compare(b.local_index) })
  let locals_size = first - body_offset
  if cursor != body_end ||
    instruction_bytes != target_body.body_size - locals_size ||
    accesses.length() != get_count + set_count + tee_count ||
    access_encoding_bytes > instruction_bytes ||
    access_encoding_bytes - accesses.length() != index_encoding_bytes ||
    grouped_count != accesses.length() ||
    grouped_bytes != access_encoding_bytes {
    return Err(
      InvalidLocalAccessesEvidence(
        Some(body_offset),
        "local-access byte/count ledger does not close",
      ),
    )
  }
  Ok({
    file_size: data.length(),
    sha256: experiment_sha256(data),
    target,
    entry: { file_offset: target_body.offset, size: target_body.total_size, },
    prefix: { file_offset: target_body.offset, size: prefix_size, },
    body: { file_offset: body_offset, size: target_body.body_size, },
    locals_encoding: { file_offset: body_offset, size: locals_size, },
    instruction_count: decoded.length(),
    instruction_bytes,
    access_count: accesses.length(),
    get_count,
    set_count,
    tee_count,
    distinct_local_index_count: groups.length(),
    access_encoding_bytes,
    index_encoding_bytes,
    other_instruction_bytes: instruction_bytes - access_encoding_bytes,
    accesses,
    groups,
    scope: "Static local.get/local.set/local.tee encodings in one completely decoded local body. Local indices are encoded values in the index space including parameters, unlike --locals declaration ordinals that exclude parameters. No signature/parameter count, parameter-versus-declared-local classification, declaration-group binding, variable names/types or actual index-range validation. Existing decoder limits indices to nonnegative Int; values beyond that range fail, not full-u32 support. Original instruction ordinals and repeated sites are retained without reachability/control-flow filtering; tee counts only as tee. Sparse groups are allocated by observed distinct indices, not maximum index. Existing module/inventory/name and body-range checks still inspect the file, but no other function opcodes are decoded. No analyze, graph or separate locals query; target is decoded once. Not complete Wasm type/stack/control validation. Static counts are not execution frequency or runtime heat; file offsets are not memory addresses; encoded sizes are not runtime memory or deletion/recompilation/gzip savings. No accesses does not imply no variables. Top limits each text table independently, not totals, complete members/JSON or decode cost.",
  })
}
