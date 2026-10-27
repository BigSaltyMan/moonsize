///|
/// One encoded declaration group, never expanded into individual variables.
/// Declared ordinals exclude parameters and use half-open intervals.
pub struct FunctionLocalGroup {
  group_index : Int
  quantity : UInt
  declared_ordinal_start : UInt64
  declared_ordinal_end : UInt64
  encoding : FunctionInstructionRange
  quantity_encoding : FunctionInstructionRange
  type_encoding : FunctionInstructionRange
  type_hex : String
  type_label : String?
}

///|
pub struct FunctionLocalsReport {
  file_size : Int
  sha256 : String
  target : FunctionPathNode
  entry : FunctionInstructionRange
  prefix : FunctionInstructionRange
  body : FunctionInstructionRange
  locals_encoding : FunctionInstructionRange
  group_count_encoding : FunctionInstructionRange
  /// Undecoded remainder, not a validated instruction region.
  body_remainder : FunctionInstructionRange
  group_count : Int
  declared_count : UInt64
  quantity_encoding_bytes : Int
  type_encoding_bytes : Int
  groups : Array[FunctionLocalGroup]
  scope : String
}

///|
pub enum FunctionLocalsError {
  LocalsInputError(WasmError)
  InvalidLocalsTarget(Int, Int)
  ImportedLocalsTarget(Int)
  InvalidLocalsEncoding(Int?, String)
}

///|
pub fn describe_function_locals_error(error : FunctionLocalsError) -> String {
  match error {
    LocalsInputError(error) => describe_error(error)
    InvalidLocalsTarget(index, count) =>
      "target function index \{index} is outside the function index space of \{count}"
    ImportedLocalsTarget(index) =>
      "target function \{index} is imported and has no local body"
    InvalidLocalsEncoding(offset, reason) =>
      "invalid locals encoding" +
      (match offset {
        Some(at) => " at file offset \{at}"
        None => ""
      }) +
      ": " +
      reason
  }
}

///|
/// Labels only for exact, confirmed one-byte encodings. Raw bytes remain the
/// source of truth; the existing read_valtype consumer is not a type validator.
fn function_locals_type_label(hex : String) -> String? {
  match hex {
    "7f" => Some("i32")
    "7e" => Some("i64")
    "7d" => Some("f32")
    "7c" => Some("f64")
    "7b" => Some("v128")
    "70" => Some("funcref")
    "6f" => Some("externref")
    _ => None
  }
}

///|
/// Consume only the selected local body's declarations once; never decode any
/// function's instructions or signature and never allocate by variable count.
pub fn inspect_function_locals(
  data : Bytes,
  index : Int,
) -> Result[FunctionLocalsReport, FunctionLocalsError] {
  let parsed = match parse_module(data) {
    Ok(value) => value
    Err(error) => return Err(LocalsInputError(error))
  }
  let inventory = match path_inventory(data, parsed) {
    Ok(value) => value
    Err(error) => return Err(LocalsInputError(error))
  }
  if index < 0 || index >= inventory.length() {
    return Err(InvalidLocalsTarget(index, inventory.length()))
  }
  let target = inventory[index]
  if target.imported {
    return Err(ImportedLocalsTarget(index))
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
        InvalidLocalsEncoding(None, "local function has no code section"),
      )
  }
  let bodies = match parse_code_section(data, code, base_index=imported) {
    Ok(value) => value
    Err(error) => return Err(LocalsInputError(error))
  }
  if index < imported || bodies.length() != inventory.length() - imported {
    return Err(
      InvalidLocalsEncoding(
        Some(code.offset),
        "inventory and body counts differ",
      ),
    )
  }
  let selected = bodies[index - imported]
  if selected.index != index ||
    target.index != index ||
    target.encoded_size != Some(selected.total_size) ||
    selected.body_size < 0 ||
    selected.body_size >= selected.total_size {
    return Err(
      InvalidLocalsEncoding(
        Some(selected.offset),
        "target identity or range differs",
      ),
    )
  }
  let entry_reader = match
    Reader::new_range(data, selected.offset, selected.total_size) {
    Ok(value) => value
    Err(error) => return Err(LocalsInputError(error))
  }
  let prefix_size = selected.total_size - selected.body_size
  match entry_reader.read_bytes(prefix_size) {
    Ok(_) => ()
    Err(error) => return Err(LocalsInputError(error))
  }
  let body_offset = entry_reader.position()
  let reader = match Reader::new_range(data, body_offset, selected.body_size) {
    Ok(value) => value
    Err(error) => return Err(LocalsInputError(error))
  }
  let group_count = match read_u32_as_int(reader) {
    Ok(value) => value
    Err(error) => return Err(LocalsInputError(error))
  }
  let count_end = reader.position()
  // Each group needs at least one quantity byte and one type byte. Check before
  // iterating/allocating; body boundaries may not borrow the next entry's bytes.
  if group_count > reader.remaining() / 2 {
    return Err(
      InvalidLocalsEncoding(
        Some(count_end),
        "declaration groups exceed remaining body bytes",
      ),
    )
  }
  let groups : Array[FunctionLocalGroup] = []
  let mut declared_count = 0UL
  let mut quantity_encoding_bytes = 0
  let mut type_encoding_bytes = 0
  for group_index in 0..<group_count {
    let start = reader.position()
    let quantity = match reader.read_u32_leb() {
      Ok(value) => value
      Err(error) => return Err(LocalsInputError(error))
    }
    let type_start = reader.position()
    match reader.read_valtype() {
      Ok(_) => ()
      Err(error) => return Err(LocalsInputError(error))
    }
    let end = reader.position()
    let amount = quantity.to_uint64()
    if amount > 18446744073709551615UL - declared_count {
      return Err(
        InvalidLocalsEncoding(Some(start), "declared quantity sum exceeds u64"),
      )
    }
    let ordinal_start = declared_count
    declared_count += amount
    let type_hex = data_preview_hex(data[type_start:end])
    let quantity_size = type_start - start
    let type_size = end - type_start
    groups.push({
      group_index,
      quantity,
      declared_ordinal_start: ordinal_start,
      declared_ordinal_end: declared_count,
      encoding: { file_offset: start, size: end - start, },
      quantity_encoding: { file_offset: start, size: quantity_size, },
      type_encoding: { file_offset: type_start, size: type_size, },
      type_hex,
      type_label: function_locals_type_label(type_hex),
    })
    quantity_encoding_bytes += quantity_size
    type_encoding_bytes += type_size
  }
  let remainder = reader.position()
  let locals_size = remainder - body_offset
  let count_size = count_end - body_offset
  if locals_size - count_size != quantity_encoding_bytes + type_encoding_bytes {
    return Err(
      InvalidLocalsEncoding(
        Some(body_offset),
        "locals byte ledger does not close",
      ),
    )
  }
  Ok({
    file_size: data.length(),
    sha256: experiment_sha256(data),
    target,
    entry: { file_offset: selected.offset, size: selected.total_size, },
    prefix: { file_offset: selected.offset, size: prefix_size, },
    body: { file_offset: body_offset, size: selected.body_size, },
    locals_encoding: { file_offset: body_offset, size: locals_size, },
    group_count_encoding: { file_offset: body_offset, size: count_size, },
    body_remainder: { file_offset: remainder, size: reader.remaining(), },
    group_count,
    declared_count,
    quantity_encoding_bytes,
    type_encoding_bytes,
    groups,
    scope: "Encoded local declaration groups only, in original order, including zero-quantity groups. Declared ordinals are half-open and exclude parameters; they are not full local indices. No signature parsing or local.get/set/tee binding. Quantities are u32; cumulative counts/ordinals use u64 and decimal strings in JSON. No variable expansion or adjacent-group merging. Raw type bytes are authoritative; limited labels and the existing read_valtype consumer do not provide full type, heap-type or default-initialization validation. Body remainder is undecoded, not a validated instruction region; no function opcodes are decoded. Existing module/inventory/name and body-range checks still inspect the module. File offsets are not memory addresses; encoded sizes do not measure runtime stack/memory or predict deletion, recompilation or gzip savings. Top limits text group rows only, not parsing cost or complete JSON.",
  })
}
