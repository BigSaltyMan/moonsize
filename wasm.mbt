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
/// True when two section ids are the same variant.
///
/// Section ids carry no payload and this toolchain derives no `Eq` for them, so
/// the comparison is written out once here rather than spelled at each call site
/// that has to pick a section out of the table.
pub fn same_kind(a : SectionId, b : SectionId) -> Bool {
  match (a, b) {
    (Custom, Custom)
    | (Type, Type)
    | (Import, Import)
    | (Function, Function)
    | (Table, Table)
    | (Memory, Memory)
    | (Global, Global)
    | (Export, Export)
    | (Start, Start)
    | (Element, Element)
    | (Code, Code)
    | (Data, Data)
    | (DataCount, DataCount)
    | (Tag, Tag) => true
    _ => false
  }
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
/// Check version, standard-section uniqueness/order and function/code structure.
/// Other payloads remain outside full type and instruction-semantic validation.
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
  let version = data[4].to_int().reinterpret_as_uint() |
    (data[5].to_int().reinterpret_as_uint() << 8) |
    (data[6].to_int().reinterpret_as_uint() << 16) |
    (data[7].to_int().reinterpret_as_uint() << 24)
  if version != 1U {
    return Err(WasmError::UnsupportedVersion(4, version))
  }
  let reader = Reader::new(data)
  match reader.seek(8) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  let sections : Array[Section] = []
  let seen : Set[Int] = Set([])
  let mut previous = Custom
  let mut order = 0
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
    if !kind.is_custom() {
      if seen.contains(id) {
        return Err(WasmError::DuplicateSection(offset, kind))
      }
      let current = section_order(kind)
      if current < order {
        return Err(WasmError::InvalidSectionOrder(offset, kind, previous))
      }
      seen.add(id)
      previous = kind
      order = current
    }
    let payload_size = match read_u32_as_int(reader) {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    let header_size = reader.position() - offset
    if reader.remaining() < payload_size {
      return Err(WasmError::UnexpectedEnd(reader.position(), payload_size))
    }
    let payload_start = reader.position()
    let custom_name = if kind.is_custom() {
      let payload = match Reader::new_range(data, payload_start, payload_size) {
        Ok(reader) => reader
        Err(error) => return Err(error)
      }
      match read_custom_name(payload) {
        Ok(name) => Some(name)
        Err(error) => return Err(error)
      }
    } else {
      None
    }
    // The bounded name reader does not advance the section-table reader.
    match reader.read_bytes(payload_size) {
      Ok(_) => ()
      Err(error) => return Err(error)
    }
    sections.push({
      id,
      kind,
      offset,
      payload_size,
      total_size: header_size + payload_size,
      custom_name,
    })
  }
  match validate_function_code(data, sections) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  Ok({ version: 1, file_size: data.length(), sections, })
}

///|
/// Custom sections begin with a name, which tells producer metadata, debug info
/// and `name` sections apart. This outer name is structural, so a malformed
/// length fails the parse even though optional name subsections remain tolerant.
fn read_custom_name(reader : Reader) -> Result[String, WasmError] {
  let name_length = match read_u32_as_int(reader) {
    Ok(length) => length
    Err(error) => return Err(error)
  }
  match reader.read_bytes(name_length) {
    Ok(name) => Ok(@utf8.decode_lossy(name))
    Err(error) => Err(error)
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
    InvalidReadRange(offset, length, start, end) =>
      "invalid read range at offset " +
      offset.to_string() +
      " (length " +
      length.to_string() +
      ", allowed [" +
      start.to_string() +
      ", " +
      end.to_string() +
      "))"
    ValueOutOfRange(offset, value) =>
      "unsigned value at offset " +
      offset.to_string() +
      " exceeds the supported integer range (value " +
      value.to_string() +
      ")"
    UnsupportedVersion(offset, version) =>
      "unsupported WebAssembly version " +
      version.to_string() +
      " at offset " +
      offset.to_string()
    DuplicateSection(offset, kind) =>
      "duplicate " + kind.name() + " section at offset " + offset.to_string()
    InvalidSectionOrder(offset, kind, previous) =>
      kind.name() +
      " section appears after " +
      previous.name() +
      " section at offset " +
      offset.to_string()
    FunctionCodeCountMismatch(offset, kind, declarations, bodies) =>
      "function/code count mismatch: " +
      plural(declarations, "declaration") +
      ", " +
      bodies.to_string() +
      (if bodies == 1 { " body" } else { " bodies" }) +
      " (" +
      kind.name() +
      " section at offset " +
      offset.to_string() +
      ")"
    TrailingSectionBytes(offset, kind) =>
      "unexpected trailing bytes in " +
      kind.name() +
      " section at offset " +
      offset.to_string()
    InvalidTableEncoding(offset, reason) =>
      "invalid or unsupported table encoding at offset " +
      offset.to_string() +
      ": " +
      reason
    InvalidDataEncoding(offset, reason) =>
      "invalid data encoding at offset " + offset.to_string() + ": " + reason
    InvalidImportEncoding(offset, reason) =>
      "import encoding at offset " + offset.to_string() + ": " + reason
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
/// Create a reader restricted to the section payload. Validate header arithmetic
/// before adding offsets, including when a section is reused with another buffer.
fn reader_at_payload(
  data : Bytes,
  section : Section,
) -> Result[Reader, WasmError] {
  if section.offset < 0 ||
    section.offset > data.length() ||
    section.payload_size < 0 ||
    section.total_size < section.payload_size {
    return Err(
      WasmError::InvalidReadRange(
        section.offset,
        section.total_size,
        0,
        data.length(),
      ),
    )
  }
  let header = section.total_size - section.payload_size
  if header > data.length() - section.offset {
    return Err(
      WasmError::InvalidReadRange(
        section.offset,
        section.total_size,
        0,
        data.length(),
      ),
    )
  }
  Reader::new_range(data, section.offset + header, section.payload_size)
}

///|
/// Advance past a WebAssembly name: a LEB128 byte count and that many bytes.
fn skip_name(reader : Reader) -> Result[Unit, WasmError] {
  let length = match read_u32_as_int(reader) {
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
  match read_u32_as_int(reader) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  if (flags & 0x01) != 0 {
    match read_u32_as_int(reader) {
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
  let minimum = match read_u32_as_int(reader) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  if (flags & 0x01) != 0 {
    let maximum = match read_u32_as_int(reader) {
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
      match read_u32_as_int(reader) {
        Ok(_) => Ok(true)
        Err(error) => Err(error)
      }
    // table: reftype limits
    1 =>
      match read_table_type(reader) {
        Ok(_) => Ok(false)
        Err(error) => Err(error)
      }
    // memory: limits
    2 =>
      match skip_limits(reader) {
        Ok(_) => Ok(false)
        Err(error) => Err(error)
      }
    // global: valtype mut
    3 => {
      match reader.read_valtype() {
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
      match read_u32_as_int(reader) {
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
  let reader = match reader_at_payload(data, section) {
    Ok(reader) => reader
    Err(error) => return Err(error)
  }
  let count = match read_u32_as_int(reader) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let mut functions = 0
  for i = 0; i < count; i = i + 1 {
    if reader.at_end() {
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
  let bodies : Array[FunctionBody] = []
  match walk_code_section(data, section, base_index, Some(bodies)) {
    Ok(_) => Ok(bodies)
    Err(error) => Err(error)
  }
}

///|
/// One bounded length walker for structure validation and body collection.
/// Validation passes None and allocates no FunctionBody array.
fn walk_code_section(
  data : Bytes,
  section : Section,
  base_index : Int,
  bodies : Array[FunctionBody]?,
) -> Result[Int, WasmError] {
  if base_index < 0 {
    return Err(
      WasmError::InvalidReadRange(section.offset, base_index, 0, 2147483647),
    )
  }
  let reader = match reader_at_payload(data, section) {
    Ok(reader) => reader
    Err(error) => return Err(error)
  }
  let count = match read_u32_as_int(reader) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  for i = 0; i < count; i = i + 1 {
    let offset = reader.position()
    let body_size = match read_u32_as_int(reader) {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    let prefix_size = reader.position() - offset
    if body_size > reader.remaining() {
      return Err(WasmError::UnexpectedEnd(reader.position(), body_size))
    }
    if i > 2147483647 - base_index {
      return Err(
        WasmError::ValueOutOfRange(
          offset,
          base_index.reinterpret_as_uint() + i.reinterpret_as_uint(),
        ),
      )
    }
    match reader.read_bytes(body_size) {
      Ok(_) => ()
      Err(error) => return Err(error)
    }
    match bodies {
      Some(bodies) =>
        bodies.push({
          index: base_index + i,
          body_size,
          total_size: prefix_size + body_size,
          offset,
        })
      None => ()
    }
  }
  match finish_section(reader, Code) {
    Ok(_) => Ok(count)
    Err(error) => Err(error)
  }
}

///|
/// Read one function name map (`namemap`) into `names`, stopping early on a
/// malformed entry so a damaged suffix cannot discard the names before it.
fn read_function_names(reader : Reader, names : Map[Int, String]) -> Unit {
  let count = match read_u32_as_int(reader) {
    Ok(value) => value
    Err(_) => return
  }
  for i = 0; i < count; i = i + 1 {
    if reader.at_end() {
      return
    }
    let index = match read_u32_as_int(reader) {
      Ok(value) => value
      Err(_) => return
    }
    let length = match read_u32_as_int(reader) {
      Ok(value) => value
      Err(_) => return
    }
    let bytes = match reader.read_bytes(length) {
      Ok(bytes) => bytes
      Err(_) => return
    }
    // Debug names are optional, but a replacement character manufactured by
    // lossy decoding is not a reliable cross-build symbol identity. Keep earlier
    // names and leave this damaged suffix unnamed. A literal U+FFFD remains valid.
    let text = @utf8.decode(bytes) catch { _ => return }
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
  let reader = match reader_at_payload(data, section) {
    Ok(reader) => reader
    Err(_) => return Some(names)
  }
  // A custom section opens with its own name, which is "name" here.
  match skip_name(reader) {
    Ok(_) => ()
    Err(_) => return Some(names)
  }
  while !reader.at_end() {
    let sub_id = match reader.read_byte() {
      Ok(value) => value
      Err(_) => break
    }
    let sub_size = match read_u32_as_int(reader) {
      Ok(value) => value
      Err(_) => break
    }
    if sub_size > reader.remaining() {
      break
    }
    let subsection = match
      Reader::new_range(data, reader.position(), sub_size) {
      Ok(reader) => reader
      Err(_) => break
    }
    if sub_id == NAME_SUBSECTION_FUNCTION {
      read_function_names(subsection, names)
    }
    match reader.read_bytes(sub_size) {
      Ok(_) => ()
      Err(_) => break
    }
  }
  Some(names)
}

///|
/// The sections the analysis passes need, picked out of the section table once.
///
/// parse_module validates standard-section uniqueness before returning a module.
/// Several custom sections are legal; the last name custom section is selected.
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
  /// `call x` or `return_call x`: the target is named outright.
  Direct(Int)
  /// `call_indirect` or `return_call_indirect`: table `x` supplies the target.
  Indirect(Int)
  /// `call_ref` or `return_call_ref`: target comes from a function reference.
  Reference
}

///|
/// One call found in a function body.
pub struct CallSite {
  kind : CallKind
  /// Signature of a table or reference call; `None` for a direct call.
  type_index : Int?
  /// Offset of the instruction from the start of the file.
  offset : Int
}

///|
/// Skip a function body's local declaration and decode the expression.
///
/// `body_offset` is the first byte after the body's size prefix, so the locals
/// vector comes first. Locals and instructions share a bounded reader, so no
/// immediate can consume bytes from the next body before reporting an error,
/// which is what keeps a wrong immediate width from quietly becoming a wrong
/// call graph.
pub fn decode_instructions(
  bytes : Bytes,
  body_offset : Int,
  body_size : Int,
) -> Result[Array[Instruction], WasmError] {
  let reader = match Reader::new_range(bytes, body_offset, body_size) {
    Ok(reader) => reader
    Err(error) => return Err(error)
  }
  let local_groups = match read_u32_as_int(reader) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let mut group = 0
  while group < local_groups {
    match read_u32_as_int(reader) {
      Ok(_) => ()
      Err(error) => return Err(error)
    }
    match reader.read_valtype() {
      Ok(_) => ()
      Err(error) => return Err(error)
    }
    group = group + 1
  }
  let instructions : Array[Instruction] = []
  while !reader.at_end() {
    let instruction = match decode_instruction_from_reader(reader) {
      Ok(instruction) => instruction
      Err(error) => return Err(error)
    }
    instructions.push(instruction)
  }
  Ok(instructions)
}

///|
/// Collect direct, table and reference calls, including tail calls, from a body.
///
/// Collect `call`, `return_call`, `call_indirect` and `return_call_indirect`.
/// Also collect `call_ref` and `return_call_ref`, without resolving their targets.
/// `ref.func` is a reference rather than a call; the graph handles it separately.
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
      Call | ReturnCall =>
        sites.push({
          kind: Direct(instruction.operands[0]),
          type_index: None,
          offset: instruction.offset,
        })
      CallIndirect | ReturnCallIndirect =>
        sites.push({
          kind: Indirect(instruction.operands[1]),
          type_index: Some(instruction.operands[0]),
          offset: instruction.offset,
        })
      CallRef | ReturnCallRef =>
        sites.push({
          kind: Reference,
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
  let reader = match reader_at_payload(data, section) {
    Ok(reader) => reader
    Err(error) => return Err(error)
  }
  let count = match read_u32_as_int(reader) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let exports : Array[Export] = []
  let mut i = 0
  while i < count {
    let length = match read_u32_as_int(reader) {
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
    let index = match read_u32_as_int(reader) {
      Ok(value) => value
      Err(error) => return Err(error)
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
  let reader = match reader_at_payload(data, section) {
    Ok(reader) => reader
    Err(error) => return Err(error)
  }
  read_u32_as_int(reader)
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
  match decode_tables(data, section) {
    Ok(tables) => Ok(tables.map(table => table.table_type))
    Err(error) => Err(error)
  }
}

///|
priv struct DecodedTable {
  table_type : TableType
  offset : Int
  initializer_offset : Int?
}

///|
/// Share reference-type and limits decoding with imported-table handling.
fn read_table_type(reader : Reader) -> Result[TableType, WasmError] {
  let at = reader.position()
  let first = match reader.read_byte() {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  if first != REF_NULL_TYPE &&
    first != REF_TYPE &&
    (first < 0x68 || first > 0x75) {
    return Err(InvalidTableEncoding(at, "expected a supported reference type"))
  }
  match reader.seek(at) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  let element_type = match reader.read_reftype() {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let limits_at = reader.position()
  let flags = match reader.read_byte() {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  // Table64/shared limits need a different numeric/model design. Reject their
  // flags explicitly rather than misreading their widths as i32 table limits.
  if flags != 0 && flags != 1 {
    return Err(
      InvalidTableEncoding(
        limits_at, "only i32 table limits flags 0 and 1 are supported",
      ),
    )
  }
  match reader.seek(limits_at) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  let limits = match parse_limits(reader) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  Ok({ element_type, minimum: limits.0, maximum: limits.1, })
}

///|
/// Decode and bound complete explicit initializer expressions, without guessing
/// their values. Metadata and the public table parser share this exact walker.
fn decode_tables(
  data : Bytes,
  section : Section,
) -> Result[Array[DecodedTable], WasmError] {
  let reader = match reader_at_payload(data, section) {
    Ok(reader) => reader
    Err(error) => return Err(error)
  }
  let count = match read_u32_as_int(reader) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let tables : Array[DecodedTable] = []
  let mut i = 0
  while i < count {
    // A table with an explicit initialiser leads with `0x40 0x00`; everything
    // else starts straight at the reference type.
    let offset = reader.position()
    let first = match reader.read_byte() {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    let explicit = first == 0x40
    if explicit {
      let reserved_at = reader.position()
      match reader.read_byte() {
        Ok(0) => ()
        Ok(_) =>
          return Err(
            InvalidTableEncoding(
              reserved_at, "explicit initializer reserved byte must be zero",
            ),
          )
        Err(error) => return Err(error)
      }
    } else {
      match reader.seek(offset) {
        Ok(_) => ()
        Err(error) => return Err(error)
      }
    }
    let table_type = match read_table_type(reader) {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    let initializer_offset = if explicit {
      let at = reader.position()
      match skip_constant_expression(reader) {
        Ok(_) => ()
        Err(error) => return Err(error)
      }
      Some(at)
    } else {
      None
    }
    tables.push({ table_type, offset, initializer_offset, })
    i = i + 1
  }
  match finish_section(reader, Table) {
    Ok(_) => Ok(tables)
    Err(error) => Err(error)
  }
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
  let reader = match reader_at_payload(data, section) {
    Ok(reader) => reader
    Err(error) => return Err(error)
  }
  let count = match read_u32_as_int(reader) {
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
      table_index = match read_u32_as_int(reader) {
        Ok(value) => value
        Err(error) => return Err(error)
      }
    } else if mode == 0x00 || mode == 0x04 {
      table_index = 0
    }
    // Active modes carry an offset expression that has to be stepped over.
    if mode == 0x00 || mode == 0x02 || mode == 0x04 || mode == 0x06 {
      match skip_constant_expression(reader) {
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
      match read_element_expressions(reader) {
        Ok(functions) => functions
        Err(error) => return Err(error)
      }
    } else {
      let length = match read_u32_as_int(reader) {
        Ok(value) => value
        Err(error) => return Err(error)
      }
      let functions : Array[Int] = []
      let mut slot = 0
      while slot < length {
        match read_u32_as_int(reader) {
          Ok(value) => functions.push(value)
          Err(error) => return Err(error)
        }
        slot = slot + 1
      }
      functions
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
fn skip_constant_expression(reader : Reader) -> Result[Unit, WasmError] {
  let mut depth = 0
  let mut done = false
  while !done {
    let instruction = match decode_instruction_from_reader(reader) {
      Ok(instruction) => instruction
      Err(error) => return Err(error)
    }
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
fn read_element_expressions(reader : Reader) -> Result[Array[Int], WasmError] {
  let length = match read_u32_as_int(reader) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let functions : Array[Int] = []
  let mut slot = 0
  while slot < length {
    let mut depth = 0
    let mut done = false
    while !done {
      let instruction = match decode_instruction_from_reader(reader) {
        Ok(instruction) => instruction
        Err(error) => return Err(error)
      }
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
