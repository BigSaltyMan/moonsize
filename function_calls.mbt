///|
/// Call instruction categories, independent of call-graph EdgeKind.
pub enum FunctionCallKind {
  DirectCall
  IndirectCall
  ReferenceCall
} derive(Eq, Debug)

///|
pub struct FunctionCallRecord {
  instruction_ordinal : Int
  opcode : Opcode
  kind : FunctionCallKind
  is_tail : Bool
  file_offset : Int
  body_relative_offset : Int
  encoded_size : Int
  target_index : Int?
  type_index : Int?
  table_index : Int?
  target : FunctionPathNode?
}

///|
pub struct FunctionCallsReport {
  file_size : Int
  sha256 : String
  caller : FunctionPathNode
  entry : FunctionInstructionRange
  prefix : FunctionInstructionRange
  body : FunctionInstructionRange
  locals_encoding : FunctionInstructionRange
  instruction_count : Int
  instruction_bytes : Int
  call_count : Int
  direct_count : Int
  indirect_count : Int
  reference_call_count : Int
  tail_count : Int
  call_encoding_bytes : Int
  other_instruction_bytes : Int
  calls : Array[FunctionCallRecord]
  scope : String
}

///|
pub enum FunctionCallsError {
  CallsInputError(WasmError)
  InvalidCallsTarget(Int, Int)
  ImportedCallsTarget(Int)
  InvalidCallsEvidence(Int?, String)
}

///|
pub fn describe_function_calls_error(error : FunctionCallsError) -> String {
  match error {
    CallsInputError(error) => describe_error(error)
    InvalidCallsTarget(index, count) =>
      "target function index \{index} is outside the function index space of \{count}"
    ImportedCallsTarget(index) =>
      "target function \{index} is imported and has no local body"
    InvalidCallsEvidence(offset, reason) =>
      "invalid call evidence" +
      (match offset {
        Some(at) => " at file offset \{at}"
        None => ""
      }) +
      ": " +
      reason
  }
}

///|
/// Full instruction decode of one local body only. No graph, analyze, BFS or
/// second decode for operands; ref.func is not a call instruction.
pub fn inspect_function_calls(
  data : Bytes,
  index : Int,
) -> Result[FunctionCallsReport, FunctionCallsError] {
  let parsed = match parse_module(data) {
    Ok(value) => value
    Err(error) => return Err(CallsInputError(error))
  }
  let inventory = match path_inventory(data, parsed) {
    Ok(value) => value
    Err(error) => return Err(CallsInputError(error))
  }
  if index < 0 || index >= inventory.length() {
    return Err(InvalidCallsTarget(index, inventory.length()))
  }
  let caller = inventory[index]
  if caller.imported {
    return Err(ImportedCallsTarget(index))
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
        InvalidCallsEvidence(None, "local function has no code section"),
      )
  }
  let bodies = match parse_code_section(data, code, base_index=imported) {
    Ok(value) => value
    Err(error) => return Err(CallsInputError(error))
  }
  if index < imported || bodies.length() != inventory.length() - imported {
    return Err(
      InvalidCallsEvidence(
        Some(code.offset),
        "inventory and local body counts differ",
      ),
    )
  }
  let target_body = bodies[index - imported]
  if caller.index != index ||
    target_body.index != index ||
    caller.encoded_size != Some(target_body.total_size) ||
    target_body.body_size < 0 ||
    target_body.body_size >= target_body.total_size {
    return Err(
      InvalidCallsEvidence(
        Some(target_body.offset),
        "caller identity or body range differs",
      ),
    )
  }
  let reader = match
    Reader::new_range(data, target_body.offset, target_body.total_size) {
    Ok(value) => value
    Err(error) => return Err(CallsInputError(error))
  }
  let prefix_size = target_body.total_size - target_body.body_size
  match reader.read_bytes(prefix_size) {
    Ok(_) => ()
    Err(error) => return Err(CallsInputError(error))
  }
  let body_offset = reader.position()
  match reader.read_bytes(target_body.body_size) {
    Ok(_) => ()
    Err(error) => return Err(CallsInputError(error))
  }
  let body_end = reader.position()
  let decoded = match
    decode_instructions(data, body_offset, target_body.body_size) {
    Ok(value) => value
    Err(error) => return Err(CallsInputError(error))
  }
  let first = if decoded.is_empty() { body_end } else { decoded[0].offset }
  if first < body_offset || first > body_end {
    return Err(
      InvalidCallsEvidence(Some(body_offset), "locals range exceeds body"),
    )
  }
  let calls : Array[FunctionCallRecord] = []
  let mut cursor = first
  let mut instruction_bytes = 0
  let mut call_encoding_bytes = 0
  let mut direct_count = 0
  let mut indirect_count = 0
  let mut reference_call_count = 0
  let mut tail_count = 0
  for ordinal, instruction in decoded {
    if instruction.offset != cursor ||
      instruction.size <= 0 ||
      instruction.size > body_end - cursor {
      return Err(
        InvalidCallsEvidence(
          Some(instruction.offset),
          "instruction range is not contiguous within body",
        ),
      )
    }
    cursor += instruction.size // size checked against remaining body before addition
    instruction_bytes += instruction.size
    let (kind, is_tail, operands) = match instruction.opcode {
      Call => (DirectCall, false, 1)
      ReturnCall => (DirectCall, true, 1)
      CallIndirect => (IndirectCall, false, 2)
      ReturnCallIndirect => (IndirectCall, true, 2)
      CallRef => (ReferenceCall, false, 1)
      ReturnCallRef => (ReferenceCall, true, 1)
      _ => continue
    }
    if instruction.operands.length() != operands {
      return Err(
        InvalidCallsEvidence(
          Some(instruction.offset),
          "call operand shape differs from opcode",
        ),
      )
    }
    let mut target_index : Int? = None
    let mut target : FunctionPathNode? = None
    let mut type_index : Int? = None
    let mut table_index : Int? = None
    match kind {
      DirectCall => {
        let callee = instruction.operands[0]
        if callee < 0 || callee >= inventory.length() {
          return Err(
            InvalidCallsEvidence(
              Some(instruction.offset),
              "direct target function index \{callee} is outside the function index space of \{inventory.length()}",
            ),
          )
        }
        target_index = Some(callee)
        target = Some(inventory[callee])
        direct_count += 1
      }
      IndirectCall => {
        type_index = Some(instruction.operands[0])
        table_index = Some(instruction.operands[1])
        indirect_count += 1
      }
      ReferenceCall => {
        type_index = Some(instruction.operands[0])
        reference_call_count += 1
      }
    }
    calls.push({
      instruction_ordinal: ordinal,
      opcode: instruction.opcode,
      kind,
      is_tail,
      file_offset: instruction.offset,
      body_relative_offset: instruction.offset - body_offset,
      encoded_size: instruction.size,
      target_index,
      type_index,
      table_index,
      target,
    })
    call_encoding_bytes += instruction.size
    if is_tail {
      tail_count += 1
    }
  }
  let locals_size = first - body_offset
  if cursor != body_end ||
    instruction_bytes != target_body.body_size - locals_size ||
    calls.length() != direct_count + indirect_count + reference_call_count ||
    call_encoding_bytes > instruction_bytes {
    return Err(
      InvalidCallsEvidence(
        Some(body_offset),
        "call/instruction byte ledger does not close",
      ),
    )
  }
  Ok({
    file_size: data.length(),
    sha256: experiment_sha256(data),
    caller,
    entry: { file_offset: target_body.offset, size: target_body.total_size, },
    prefix: { file_offset: target_body.offset, size: prefix_size, },
    body: { file_offset: body_offset, size: target_body.body_size, },
    locals_encoding: { file_offset: body_offset, size: locals_size, },
    instruction_count: decoded.length(),
    instruction_bytes,
    call_count: calls.length(),
    direct_count,
    indirect_count,
    reference_call_count,
    tail_count,
    call_encoding_bytes,
    other_instruction_bytes: instruction_bytes - call_encoding_bytes,
    calls,
    scope: "Static call instructions in one completely decoded local body, not an execution trace or a complete outgoing dependency graph. Direct targets are exact encoded function indices; indirect/reference-call targets are unresolved and remain null, with no candidate inference. Type/table indices record encoding only, without existence or compatibility checks. ref.func takes a reference and is excluded. Tail calls are a subset, not extra calls. Different positions remain separate; no reachability filtering. Existing parser/inventory range and best-effort name checks still inspect the module, but other function opcodes are not decoded. No graph, recursive search or strict guarantee. No complete Wasm type/stack/control validation. File offsets are not memory addresses; counts are not execution frequencies; encoded bytes do not predict deletion, recompilation or gzip savings. Top limits text call rows only, not decode cost or complete JSON.",
  })
}
