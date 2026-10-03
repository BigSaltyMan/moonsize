///|
/// The section identifiers defined by the WebAssembly core specification.
pub enum SectionId {
  Custom
  Type
  Import
  Function
  Table
  Memory
  Global
  Export
  Start
  Element
  Code
  Data
  DataCount
  Tag
}

///|
/// Map a raw section id byte to its meaning, or `None` when unassigned.
pub fn SectionId::from_id(id : Int) -> SectionId? {
  match id {
    0 => Some(Custom)
    1 => Some(Type)
    2 => Some(Import)
    3 => Some(Function)
    4 => Some(Table)
    5 => Some(Memory)
    6 => Some(Global)
    7 => Some(Export)
    8 => Some(Start)
    9 => Some(Element)
    10 => Some(Code)
    11 => Some(Data)
    12 => Some(DataCount)
    13 => Some(Tag)
    _ => None
  }
}

///|
/// Custom sections are the only ones that carry a name, and they are worth
/// telling apart from the numbered sections.
pub fn SectionId::is_custom(self : SectionId) -> Bool {
  match self {
    Custom => true
    _ => false
  }
}

///|
/// The lower-case name used by `wasm-objdump` and friends.
pub fn SectionId::name(self : SectionId) -> String {
  match self {
    Custom => "custom"
    Type => "type"
    Import => "import"
    Function => "function"
    Table => "table"
    Memory => "memory"
    Global => "global"
    Export => "export"
    Start => "start"
    Element => "element"
    Code => "code"
    Data => "data"
    DataCount => "datacount"
    Tag => "tag"
  }
}

///|
/// One decoded section header, with the byte budget it accounts for.
pub struct Section {
  /// Raw id byte as it appears in the file.
  id : Int
  kind : SectionId
  /// Offset of the id byte from the start of the file.
  offset : Int
  /// Number of payload bytes, i.e. the value of the section's size field.
  payload_size : Int
  /// Header bytes (id plus encoded size) plus the payload.
  total_size : Int
  /// Name declared inside a custom section, when it is decodable.
  custom_name : String?
}

///|
/// A decoded module preamble plus its section table.
pub struct WasmModule {
  version : Int
  file_size : Int
  sections : Array[Section]
}

///|
/// WebAssembly magic number, `\0asm`.
const MAGIC_0 : Int = 0x00

///|
const MAGIC_1 : Int = 0x61

///|
const MAGIC_2 : Int = 0x73

///|
const MAGIC_3 : Int = 0x6D

///|
/// Decode the module preamble and walk every section header.
///
/// Payloads are measured but not interpreted, which keeps this step a pure
/// structural pass over the file.
pub fn parse_module(data : Bytes) -> Result[WasmModule, WasmError] {
  if data.length() < 8 {
    return Err(WasmError::UnexpectedEnd(0, 8))
  }
  if data[0].to_int() != MAGIC_0 ||
    data[1].to_int() != MAGIC_1 ||
    data[2].to_int() != MAGIC_2 ||
    data[3].to_int() != MAGIC_3 {
    return Err(WasmError::BadMagic)
  }
  let version = data[4].to_int() |
    (data[5].to_int() << 8) |
    (data[6].to_int() << 16) |
    (data[7].to_int() << 24)
  let reader = Reader::new(data)
  reader.seek(8)
  let sections : Array[Section] = []
  while !reader.at_end() {
    let offset = reader.position()
    let id = match reader.read_byte() {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    let kind = match SectionId::from_id(id) {
      Some(kind) => kind
      None => return Err(WasmError::InvalidSectionId(id))
    }
    let payload_size = match reader.read_u32_leb() {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    let header_size = reader.position() - offset
    if reader.remaining() < payload_size {
      return Err(WasmError::UnexpectedEnd(reader.position(), payload_size))
    }
    let payload_start = reader.position()
    let custom_name = if kind.is_custom() {
      read_custom_name(reader)
    } else {
      None
    }
    // The name is read for display only, so rewind to the payload end rather
    // than depending on how far the name happened to advance.
    reader.seek(payload_start + payload_size)
    sections.push({
      id,
      kind,
      offset,
      payload_size,
      total_size: header_size + payload_size,
      custom_name,
    })
  }
  Ok({ version, file_size: data.length(), sections, })
}

///|
/// Custom sections begin with a name, which tells producer metadata, debug info
/// and `name` sections apart. A malformed name never fails the parse: the size
/// of the section is the fact this tool is after.
fn read_custom_name(reader : Reader) -> String? {
  let name_length = match reader.read_u32_leb() {
    Ok(length) => length
    Err(_) => return None
  }
  if reader.remaining() < name_length {
    return None
  }
  match reader.read_bytes(name_length) {
    Ok(name) => Some(@utf8.decode_lossy(name))
    Err(_) => None
  }
}

///|
/// A one-line explanation for a failed parse.
pub fn describe_error(error : WasmError) -> String {
  match error {
    UnexpectedEnd(offset, needed) =>
      "unexpected end of input at offset " +
      offset.to_string() +
      " (needed " +
      needed.to_string() +
      " bytes)"
    BadMagic => "not a WebAssembly binary: missing \\0asm magic number"
    InvalidSectionId(id) => "unknown section id " + id.to_string()
    LebOverflow(offset) =>
      "malformed LEB128 integer at offset " + offset.to_string()
    InvalidImportKind(kind) =>
      "unknown import kind " + kind.to_string() + " (expected 0..4)"
    UnknownOpcode(offset, byte) =>
      "unknown opcode 0x" +
      byte.to_string(radix=16) +
      " at offset " +
      offset.to_string()
    UnknownPrefixedOpcode(offset, prefix, sub) =>
      "unknown opcode 0x" +
      prefix.to_string(radix=16) +
      " 0x" +
      sub.to_string(radix=16) +
      " at offset " +
      offset.to_string()
  }
}

///|
/// One function body decoded out of the code section.
///
/// The spec stores a body as a size-prefixed blob, so an entry costs its own
/// length prefix on top of the body itself. Both numbers are kept: the body is
/// what a compiler can shrink, the total is what the file actually spends.
pub struct FunctionBody {
  /// Index in the function index space, where imported functions come first.
  index : Int
  /// Length declared by the body's size prefix: locals plus instructions.
  body_size : Int
  /// The size prefix plus the body, i.e. the bytes this entry costs.
  total_size : Int
  /// Offset of the size prefix from the start of the file.
  offset : Int
}

///|
/// Subsection id `1` of the `name` custom section: the function name map.
const NAME_SUBSECTION_FUNCTION : Int = 1

///|
/// Byte offset at which a section's payload begins, derived from the header
/// size the section table already recorded.
fn payload_start(section : Section) -> Int {
  section.offset + section.total_size - section.payload_size
}

///|
/// Create a cursor parked on the first payload byte of `section`.
fn reader_at_payload(data : Bytes, section : Section) -> Reader {
  let reader = Reader::new(data)
  reader.seek(payload_start(section))
  reader
}

///|
/// Advance past a WebAssembly name: a LEB128 byte count and that many bytes.
fn skip_name(reader : Reader) -> Result[Unit, WasmError] {
  let length = match reader.read_u32_leb() {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  match reader.read_bytes(length) {
    Ok(_) => Ok(())
    Err(error) => Err(error)
  }
}

///|
/// Advance past a `limits` record: a flag byte, a minimum, and a maximum only
/// when the flag says one is present.
///
/// The shared and 64-bit flags change the value type but not the shape, so
/// skipping only has to read the low bit.
fn skip_limits(reader : Reader) -> Result[Unit, WasmError] {
  let flags = match reader.read_byte() {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  match reader.read_u32_leb() {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  if (flags & 0x01) != 0 {
    match reader.read_u32_leb() {
      Ok(_) => ()
      Err(error) => return Err(error)
    }
  }
  Ok(())
}

///|
/// Read a `limits` record: a flag byte, a minimum, and a maximum when the flag
/// says one is present.
///
/// The shared and 64-bit flags change the value type but not the shape, so only
/// the low bit decides whether a maximum follows.
fn parse_limits(reader : Reader) -> Result[(Int, Int?), WasmError] {
  let flags = match reader.read_byte() {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let minimum = match reader.read_u32_leb() {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  if (flags & 0x01) != 0 {
    let maximum = match reader.read_u32_leb() {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    Ok((minimum, Some(maximum)))
  } else {
    Ok((minimum, None))
  }
}

///|
/// Advance past one import descriptor and report whether it is a function.
///
/// The kind byte picks the shape that follows: a type index for functions, a
/// table type, limits or a global type for everything else.
fn skip_import_desc(reader : Reader) -> Result[Bool, WasmError] {
  let kind = match reader.read_byte() {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  match kind {
    // func: typeidx
    0 =>
      match reader.read_u32_leb() {
        Ok(_) => Ok(true)
        Err(error) => Err(error)
      }
    // table: reftype limits
    1 => {
      match reader.read_byte() {
        Ok(_) => ()
        Err(error) => return Err(error)
      }
      match skip_limits(reader) {
        Ok(_) => Ok(false)
        Err(error) => Err(error)
      }
    }
    // memory: limits
    2 =>
      match skip_limits(reader) {
        Ok(_) => Ok(false)
        Err(error) => Err(error)
      }
    // global: valtype mut
    3 => {
      match reader.read_byte() {
        Ok(_) => ()
        Err(error) => return Err(error)
      }
      match reader.read_byte() {
        Ok(_) => Ok(false)
        Err(error) => Err(error)
      }
    }
    // tag: attribute typeidx
    4 => {
      match reader.read_byte() {
        Ok(_) => ()
        Err(error) => return Err(error)
      }
      match reader.read_u32_leb() {
        Ok(_) => Ok(false)
        Err(error) => Err(error)
      }
    }
    _ => Err(WasmError::InvalidImportKind(kind))
  }
}

///|
/// Count the function imports of a module.
///
/// Imported functions occupy the first slots of the function index space, so
/// this count is what turns a code-section position into the index that the
/// `name` section and every call instruction actually use.
pub fn count_imported_functions(
  data : Bytes,
  section : Section,
) -> Result[Int, WasmError] {
  let reader = reader_at_payload(data, section)
  let end = payload_start(section) + section.payload_size
  let count = match reader.read_u32_leb() {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let mut functions = 0
  for i = 0; i < count; i = i + 1 {
    if reader.position() >= end {
      return Err(WasmError::UnexpectedEnd(reader.position(), 1))
    }
    // Each import is "module name" then "field name" then a descriptor.
    match skip_name(reader) {
      Ok(_) => ()
      Err(error) => return Err(error)
    }
    match skip_name(reader) {
      Ok(_) => ()
      Err(error) => return Err(error)
    }
    match skip_import_desc(reader) {
      Ok(is_function) => if is_function { functions = functions + 1 }
      Err(error) => return Err(error)
    }
  }
  Ok(functions)
}

///|
/// Decode the code section into one record per function body.
///
/// `base_index` is the number of imported functions, so the returned `index`
/// values line up with the function index space. Bodies are measured and
/// skipped, never interpreted, which keeps this a structural pass like
/// `parse_module`.
pub fn parse_code_section(
  data : Bytes,
  section : Section,
  base_index? : Int = 0,
) -> Result[Array[FunctionBody], WasmError] {
  let reader = reader_at_payload(data, section)
  let end = payload_start(section) + section.payload_size
  let count = match reader.read_u32_leb() {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let bodies : Array[FunctionBody] = []
  for i = 0; i < count; i = i + 1 {
    let offset = reader.position()
    let body_size = match reader.read_u32_leb() {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    let prefix_size = reader.position() - offset
    if reader.position() + body_size > end {
      return Err(WasmError::UnexpectedEnd(reader.position(), body_size))
    }
    reader.seek(reader.position() + body_size)
    bodies.push({
      index: base_index + i,
      body_size,
      total_size: prefix_size + body_size,
      offset,
    })
  }
  Ok(bodies)
}

///|
/// Read one function name map (`namemap`) into `names`, stopping early on a
/// malformed entry so a damaged suffix cannot discard the names before it.
fn read_function_names(
  reader : Reader,
  sub_end : Int,
  names : Map[Int, String],
) -> Unit {
  let count = match reader.read_u32_leb() {
    Ok(value) => value
    Err(_) => return
  }
  for i = 0; i < count; i = i + 1 {
    if reader.position() >= sub_end {
      return
    }
    let index = match reader.read_u32_leb() {
      Ok(value) => value
      Err(_) => return
    }
    let length = match reader.read_u32_leb() {
      Ok(value) => value
      Err(_) => return
    }
    let text = match reader.read_bytes(length) {
      Ok(bytes) => @utf8.decode_lossy(bytes)
      Err(_) => return
    }
    names.set(index, text)
  }
}

///|
/// Decode the function names out of a `name` custom section.
///
/// The result is keyed by function index. `None` means the section is not a
/// `name` section at all; `Some` of an empty map is a real answer, because
/// names are optional producer metadata and a stripped binary simply has none.
/// Subsection ids other than `1` (locals, labels, types) are skipped whole,
/// and a malformed subsection ends the walk without discarding earlier names.
pub fn parse_name_section(data : Bytes, section : Section) -> Map[Int, String]? {
  let is_name_section = match section.custom_name {
    Some(name) => name == "name"
    None => false
  }
  if !is_name_section {
    return None
  }
  let names : Map[Int, String] = Map([])
  let reader = reader_at_payload(data, section)
  let end = payload_start(section) + section.payload_size
  // A custom section opens with its own name, which is "name" here.
  match skip_name(reader) {
    Ok(_) => ()
    Err(_) => return Some(names)
  }
  while reader.position() < end {
    let sub_id = match reader.read_byte() {
      Ok(value) => value
      Err(_) => break
    }
    let sub_size = match reader.read_u32_leb() {
      Ok(value) => value
      Err(_) => break
    }
    let sub_end = reader.position() + sub_size
    if sub_end > end {
      break
    }
    if sub_id == NAME_SUBSECTION_FUNCTION {
      read_function_names(reader, sub_end, names)
    }
    reader.seek(sub_end)
  }
  Some(names)
}

///|
/// The sections the analysis passes need, picked out of the section table once.
///
/// A well-formed module holds at most one of each numbered section, so the last
/// one seen wins. Several custom sections are legal, and `name` is the only one
/// this tool reads.
pub struct Sections {
  mut code : Section?
  mut imports : Section?
  mut names : Section?
  mut exports : Section?
  mut elements : Section?
  mut tables : Section?
  mut start : Section?
}

///|
/// Pick the interesting sections out of a parsed section table.
pub fn find_sections(parsed : WasmModule) -> Sections {
  let found : Sections = {
    code: None,
    imports: None,
    names: None,
    exports: None,
    elements: None,
    tables: None,
    start: None,
  }
  for section in parsed.sections {
    match section.kind {
      Code => found.code = Some(section)
      Import => found.imports = Some(section)
      Export => found.exports = Some(section)
      Element => found.elements = Some(section)
      Table => found.tables = Some(section)
      Start => found.start = Some(section)
      Custom =>
        match section.custom_name {
          Some(name) => if name == "name" { found.names = Some(section) }
          None => ()
        }
      _ => ()
    }
  }
  found
}

///|
/// How a call site reaches its target.
pub enum CallKind {
  /// `call x`: the target is named outright.
  Direct(Int)
  /// `call_indirect`: the target is read from table `x` at run time.
  Indirect(Int)
}

///|
/// One call found in a function body.
pub struct CallSite {
  kind : CallKind
  /// The signature `call_indirect` selects on; `None` for a direct call.
  type_index : Int?
  /// Offset of the instruction from the start of the file.
  offset : Int
}

///|
/// Skip a function body's local declaration and decode the expression.
///
/// `body_offset` is the first byte after the body's size prefix, so the locals
/// vector comes first. The declared `body_size` is a hard bound: an instruction
/// that would run past it is reported rather than read out of the next body,
/// which is what keeps a wrong immediate width from quietly becoming a wrong
/// call graph.
pub fn decode_instructions(
  bytes : Bytes,
  body_offset : Int,
  body_size : Int,
) -> Result[Array[Instruction], WasmError] {
  let reader = Reader::new(bytes)
  reader.seek(body_offset)
  let end = body_offset + body_size
  let local_groups = match reader.read_u32_leb() {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let mut group = 0
  while group < local_groups {
    match reader.read_u32_leb() {
      Ok(_) => ()
      Err(error) => return Err(error)
    }
    match reader.read_valtype() {
      Ok(_) => ()
      Err(error) => return Err(error)
    }
    group = group + 1
  }
  if reader.position() > end {
    return Err(WasmError::UnexpectedEnd(body_offset, body_size))
  }
  let instructions : Array[Instruction] = []
  while reader.position() < end {
    let offset = reader.position()
    let instruction = match decode_instruction(bytes, offset) {
      Ok(instruction) => instruction
      Err(error) => return Err(error)
    }
    if offset + instruction.size > end {
      return Err(WasmError::UnexpectedEnd(offset, instruction.size))
    }
    reader.seek(offset + instruction.size)
    instructions.push(instruction)
  }
  Ok(instructions)
}

///|
/// Collect every call a function body makes.
///
/// Only `call` and `call_indirect` count here. `ref.func` is a reference rather
/// than a call, and the call graph picks those up separately.
pub fn scan_calls(
  bytes : Bytes,
  body_offset : Int,
  body_size : Int,
) -> Result[Array[CallSite], WasmError] {
  let instructions = match decode_instructions(bytes, body_offset, body_size) {
    Ok(instructions) => instructions
    Err(error) => return Err(error)
  }
  let sites : Array[CallSite] = []
  for instruction in instructions {
    match instruction.opcode {
      Call =>
        sites.push({
          kind: Direct(instruction.operands[0]),
          type_index: None,
          offset: instruction.offset,
        })
      CallIndirect =>
        sites.push({
          kind: Indirect(instruction.operands[1]),
          type_index: Some(instruction.operands[0]),
          offset: instruction.offset,
        })
      _ => ()
    }
  }
  Ok(sites)
}

///|
/// One entry of the export section.
pub struct Export {
  name : String
  /// 0 function, 1 table, 2 memory, 3 global, 4 tag.
  kind : Int
  /// Index into that kind's own index space.
  index : Int
}

///|
/// Decode the export section.
pub fn parse_export_section(
  data : Bytes,
  section : Section,
) -> Result[Array[Export], WasmError] {
  let reader = reader_at_payload(data, section)
  let end = payload_start(section) + section.payload_size
  let count = match reader.read_u32_leb() {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let exports : Array[Export] = []
  let mut i = 0
  while i < count {
    let length = match reader.read_u32_leb() {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    let name = match reader.read_bytes(length) {
      Ok(bytes) => @utf8.decode_lossy(bytes)
      Err(error) => return Err(error)
    }
    let kind = match reader.read_byte() {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    let index = match reader.read_u32_leb() {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    if reader.position() > end {
      return Err(WasmError::UnexpectedEnd(reader.position(), 1))
    }
    exports.push({ name, kind, index, })
    i = i + 1
  }
  Ok(exports)
}

///|
/// The function the module runs at instantiation, from the start section.
pub fn parse_start_section(
  data : Bytes,
  section : Section,
) -> Result[Int, WasmError] {
  let reader = reader_at_payload(data, section)
  reader.read_u32_leb()
}

///|
/// A table declared by the table section.
pub struct TableType {
  /// Reference type the slots hold: `0x70` is `funcref`.
  element_type : Int
  /// Declared minimum size, in slots.
  minimum : Int
  /// Declared maximum, when the limits carry one.
  maximum : Int?
}

///|
/// Decode the table section.
pub fn parse_table_section(
  data : Bytes,
  section : Section,
) -> Result[Array[TableType], WasmError] {
  let reader = reader_at_payload(data, section)
  let count = match reader.read_u32_leb() {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let tables : Array[TableType] = []
  let mut i = 0
  while i < count {
    // A table with an explicit initialiser leads with `0x40 0x00`; everything
    // else starts straight at the reference type.
    let mut first = match reader.read_byte() {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    if first == 0x40 {
      match reader.read_byte() {
        Ok(_) => ()
        Err(error) => return Err(error)
      }
      first = match reader.read_byte() {
        Ok(value) => value
        Err(error) => return Err(error)
      }
    }
    let element_type = if first == REF_NULL_TYPE || first == REF_TYPE {
      match reader.read_signed_leb(33) {
        Ok(_) => 0
        Err(error) => return Err(error)
      }
    } else {
      first
    }
    let limits = match parse_limits(reader) {
      Ok(limits) => limits
      Err(error) => return Err(error)
    }
    tables.push({ element_type, minimum: limits.0, maximum: limits.1, })
    i = i + 1
  }
  Ok(tables)
}

///|
/// One entry of the element section.
pub struct ElementSegment {
  /// Table the segment initialises, or `-1` when it initialises none.
  table_index : Int
  /// True when the segment is passive or declarative: it fills no table at
  /// instantiation, but the functions it names are still referenced.
  passive : Bool
  /// Function indices the segment places, in slot order. Entries written as
  /// `ref.null` contribute nothing.
  functions : Array[Int]
}

///|
/// Decode the element section.
///
/// The eight encodings differ only in whether a table index, an offset
/// expression, an element kind or a reference type is present, so the shared
/// tail — a vector of function indices or of constant expressions — is read once
/// after the mode byte has been handled.
pub fn parse_element_section(
  data : Bytes,
  section : Section,
) -> Result[Array[ElementSegment], WasmError] {
  let reader = reader_at_payload(data, section)
  let end = payload_start(section) + section.payload_size
  let count = match reader.read_u32_leb() {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let segments : Array[ElementSegment] = []
  let mut i = 0
  while i < count {
    let mode = match reader.read_byte() {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    let mut table_index = -1
    let mut passive = false
    // Modes 2 and 6 name their table; 0 and 4 always mean table 0.
    if mode == 0x02 || mode == 0x06 {
      table_index = match reader.read_u32_leb() {
        Ok(value) => value
        Err(error) => return Err(error)
      }
    } else if mode == 0x00 || mode == 0x04 {
      table_index = 0
    }
    // Active modes carry an offset expression that has to be stepped over.
    if mode == 0x00 || mode == 0x02 || mode == 0x04 || mode == 0x06 {
      match skip_constant_expression(data, reader) {
        Ok(_) => ()
        Err(error) => return Err(error)
      }
    }
    if mode == 0x01 || mode == 0x03 || mode == 0x05 || mode == 0x07 {
      passive = true
    }
    if mode == 0x01 || mode == 0x03 {
      // An element kind byte, which is always `funcref`.
      match reader.read_byte() {
        Ok(_) => ()
        Err(error) => return Err(error)
      }
    }
    if mode == 0x05 || mode == 0x06 || mode == 0x07 {
      match reader.read_reftype() {
        Ok(_) => ()
        Err(error) => return Err(error)
      }
    } else if mode == 0x02 {
      // Mode 2 carries an element kind after its offset.
      match reader.read_byte() {
        Ok(_) => ()
        Err(error) => return Err(error)
      }
    }
    let functions = if mode >= 0x04 {
      match read_element_expressions(data, reader) {
        Ok(functions) => functions
        Err(error) => return Err(error)
      }
    } else {
      let length = match reader.read_u32_leb() {
        Ok(value) => value
        Err(error) => return Err(error)
      }
      let functions : Array[Int] = []
      let mut slot = 0
      while slot < length {
        match reader.read_u32_leb() {
          Ok(value) => functions.push(value)
          Err(error) => return Err(error)
        }
        slot = slot + 1
      }
      functions
    }
    if reader.position() > end {
      return Err(WasmError::UnexpectedEnd(reader.position(), 1))
    }
    segments.push({ table_index, passive, functions, })
    i = i + 1
  }
  Ok(segments)
}

///|
/// How an instruction changes the nesting depth of a constant expression: `1`
/// opens a block, `-1` closes one, and `0` leaves the depth alone.
fn nesting_delta(opcode : Opcode) -> Int {
  match opcode {
    Block | Loop | If => 1
    End => -1
    _ => 0
  }
}

///|
/// True when an instruction ends the expression it sits in.
fn closes_expression(opcode : Opcode, depth : Int) -> Bool {
  match opcode {
    End => depth == 0
    _ => false
  }
}

///|
/// Step over a constant expression, which ends at its matching `end`.
fn skip_constant_expression(
  data : Bytes,
  reader : Reader,
) -> Result[Unit, WasmError] {
  let mut depth = 0
  let mut done = false
  while !done {
    let instruction = match decode_instruction(data, reader.position()) {
      Ok(instruction) => instruction
      Err(error) => return Err(error)
    }
    reader.seek(instruction.offset + instruction.size)
    if closes_expression(instruction.opcode, depth) {
      done = true
    } else {
      depth = depth + nesting_delta(instruction.opcode)
    }
  }
  Ok(())
}

///|
/// Read a vector of element expressions and keep the functions they reference.
fn read_element_expressions(
  data : Bytes,
  reader : Reader,
) -> Result[Array[Int], WasmError] {
  let length = match reader.read_u32_leb() {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let functions : Array[Int] = []
  let mut slot = 0
  while slot < length {
    let mut depth = 0
    let mut done = false
    while !done {
      let instruction = match decode_instruction(data, reader.position()) {
        Ok(instruction) => instruction
        Err(error) => return Err(error)
      }
      reader.seek(instruction.offset + instruction.size)
      match instruction.opcode {
        RefFunc => functions.push(instruction.operands[0])
        _ => ()
      }
      if closes_expression(instruction.opcode, depth) {
        done = true
      } else {
        depth = depth + nesting_delta(instruction.opcode)
      }
    }
    slot = slot + 1
  }
  Ok(functions)
}
