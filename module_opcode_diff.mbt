///|
/// Signed current-minus-baseline aggregate statistics; never file ranges.
pub struct ModuleOpcodeDelta {
  file_bytes : Int
  code_bytes : Int
  non_code_bytes : Int
  code_header_bytes : Int
  count_encoding_bytes : Int
  body_prefix_bytes : Int
  locals_encoding_bytes : Int
  instruction_bytes : Int
  instruction_count : Int
  imported_function_count : Int
  local_function_count : Int
}

///|
/// status is shared_opcode, baseline_only or current_only. Missing-side counts
/// are zero; neither rows nor function_count deltas establish function identity.
pub struct ModuleOpcodeChange {
  mnemonic : String
  status : String
  baseline_count : Int
  current_count : Int
  count_delta : Int
  baseline_encoded_bytes : Int
  current_encoded_bytes : Int
  encoded_bytes_delta : Int
  baseline_function_count : Int
  current_function_count : Int
  function_count_delta : Int
}

///|
pub struct ModuleOpcodeComparison {
  baseline : ModuleOpcodeReport
  current : ModuleOpcodeReport
  delta : ModuleOpcodeDelta
  opcodes : Array[ModuleOpcodeChange]
  scope : String
}

///|
pub enum ModuleOpcodeComparisonError {
  BaselineModuleOpcodeError(ModuleOpcodeError)
  CurrentModuleOpcodeError(ModuleOpcodeError)
}

///|
pub fn describe_module_opcode_comparison_error(
  error : ModuleOpcodeComparisonError,
) -> String {
  match error {
    BaselineModuleOpcodeError(error) =>
      "baseline: " + describe_module_opcode_error(error)
    CurrentModuleOpcodeError(error) =>
      "current: " + describe_module_opcode_error(error)
  }
}

///|
fn module_opcode_code_bytes(report : ModuleOpcodeReport) -> Int {
  match report.code_section {
    Some(code) => code.total_size
    None => 0
  }
}

///|
fn module_opcode_change(
  mnemonic : String,
  before : ModuleOpcodeGroup?,
  after : ModuleOpcodeGroup?,
) -> ModuleOpcodeChange {
  let (bc, bb, bf) = match before {
    Some(g) => (g.count, g.encoded_bytes, g.function_count)
    None => (0, 0, 0)
  }
  let (cc, cb, cf) = match after {
    Some(g) => (g.count, g.encoded_bytes, g.function_count)
    None => (0, 0, 0)
  }
  {
    mnemonic,
    status: match (before, after) {
      (Some(_), Some(_)) => "shared_opcode"
      (Some(_), None) => "baseline_only"
      _ => "current_only"
    },
    baseline_count: bc,
    current_count: cc,
    count_delta: cc - bc,
    baseline_encoded_bytes: bb,
    current_encoded_bytes: cb,
    encoded_bytes_delta: cb - bb,
    baseline_function_count: bf,
    current_function_count: cf,
    function_count_delta: cf - bf,
  }
}

///|
/// Inspect each side exactly once. No per-function matching or re-decoding.
pub fn compare_module_opcodes(
  baseline_data : Bytes,
  current_data : Bytes,
) -> Result[ModuleOpcodeComparison, ModuleOpcodeComparisonError] {
  let before = match inspect_module_opcodes(baseline_data) {
    Ok(report) => report
    Err(error) => return Err(BaselineModuleOpcodeError(error))
  }
  let after = match inspect_module_opcodes(current_data) {
    Ok(report) => report
    Err(error) => return Err(CurrentModuleOpcodeError(error))
  }
  let previous : Map[String, ModuleOpcodeGroup] = Map([])
  let next : Map[String, ModuleOpcodeGroup] = Map([])
  for g in before.groups {
    previous.set(g.mnemonic, g)
  }
  for g in after.groups {
    next.set(g.mnemonic, g)
  }
  let rows : Array[ModuleOpcodeChange] = []
  for g in before.groups {
    rows.push(module_opcode_change(g.mnemonic, Some(g), next.get(g.mnemonic)))
  }
  for g in after.groups {
    if !previous.contains(g.mnemonic) {
      rows.push(module_opcode_change(g.mnemonic, None, Some(g)))
    }
  }
  // Differences of bounded nonnegative Int statistics cannot be Int::MIN.
  // Compare magnitudes individually, never subtract sorting keys.
  rows.sort_by(fn(a, b) {
    let bytes = b.encoded_bytes_delta.abs().compare(a.encoded_bytes_delta.abs())
    if bytes != 0 {
      bytes
    } else {
      let count = b.count_delta.abs().compare(a.count_delta.abs())
      if count != 0 {
        count
      } else {
        a.mnemonic.lexical_compare(b.mnemonic)
      }
    }
  })
  let bc = module_opcode_code_bytes(before)
  let cc = module_opcode_code_bytes(after)
  Ok({
    baseline: before,
    current: after,
    delta: {
      file_bytes: after.file_size - before.file_size,
      code_bytes: cc - bc,
      non_code_bytes: after.file_size - cc - (before.file_size - bc),
      code_header_bytes: after.code_header_bytes - before.code_header_bytes,
      count_encoding_bytes: after.count_encoding_bytes -
      before.count_encoding_bytes,
      body_prefix_bytes: after.body_prefix_bytes - before.body_prefix_bytes,
      locals_encoding_bytes: after.locals_encoding_bytes -
      before.locals_encoding_bytes,
      instruction_bytes: after.instruction_bytes - before.instruction_bytes,
      instruction_count: after.instruction_count - before.instruction_count,
      imported_function_count: after.imported_function_count -
      before.imported_function_count,
      local_function_count: after.local_function_count -
      before.local_function_count,
    },
    opcodes: rows,
    scope: "All local function instruction encoding aggregates; delta = current - baseline. No function matching or instruction alignment. Non-code bytes include the file header and every non-code encoding, not just metadata. Actual code header, count field, body prefixes, locals and instruction widths are separate. Initializer expressions, runtime frequency, retained and gzip are excluded. function_count counts distinct functions per mnemonic; do not sum these rows or deltas as a function total, or infer which functions were added/removed. Zero aggregate deltas do not prove equal bytes, constants, instruction order or semantics. File offsets remain side-specific; deltas are quantities, not ranges. Encoded changes do not predict safe removal, rebuilding or gzip savings. Top limits text opcode rows only; both original reports and JSON remain complete.",
  })
}
