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
