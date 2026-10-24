///|
/// Half-open range in the original file, never a runtime address.
pub struct ImportByteRange {
  offset : Int
  size : Int
} derive(Eq, Debug)

///|
/// Supported 32-bit limits only. Values retain the full unsigned range.
pub struct ImportLimits {
  flags : Int
  minimum : UInt
  maximum : UInt?
} derive(Eq, Debug)

///|
pub struct ImportDeclaration {
  ordinal : Int
  kind : String
  kind_index : Int
  module_name : String
  field : String
  encoding : ImportByteRange
  module_encoding : ImportByteRange
  field_encoding : ImportByteRange
  /// Includes the kind byte, not just its following type encoding.
  descriptor : ImportByteRange
  module_length_prefix_bytes : Int
  module_utf8_bytes : Int
  field_length_prefix_bytes : Int
  field_utf8_bytes : Int
  /// A declaration, not a validated type referent or a decoded signature.
  type_index : UInt?
  limits : ImportLimits?
  value_type : String?
  mutability : Int?
}

///|
pub struct ImportKindCounts {
  functions : Int
  tables : Int
  memories : Int
  globals : Int
  tags : Int
} derive(Eq, Debug)

///|
pub struct ImportModule {
  module_name : String
  entry_count : Int
  kind_counts : ImportKindCounts
  entry_bytes : Int
  ordinals : Array[Int]
}

///|
/// Parent and child totals are decompositions, not additional costs.
pub struct ImportsLedger {
  import_section_total_bytes : Int
  section_header_bytes : Int
  count_prefix_bytes : Int
  entry_bytes : Int
  module_name_encoding_bytes : Int
  module_length_prefix_bytes : Int
  module_utf8_bytes : Int
  field_name_encoding_bytes : Int
  field_length_prefix_bytes : Int
  field_utf8_bytes : Int
  descriptor_bytes : Int
} derive(Eq, Debug)

///|
pub struct ImportsReport {
  file_size : Int
  sha256 : String
  supported_scope : String
  section : ImportByteRange?
  count_encoding : ImportByteRange?
  entry_count : Int
  kind_counts : ImportKindCounts
  ledger : ImportsLedger
  /// Sorted by declaration bytes descending, full module name ascending.
  modules : Array[ImportModule]
  /// Complete physical declaration order; text sorting does not change this.
  entries : Array[ImportDeclaration]
}

///|
fn imports_name(
  reader : Reader,
  label : String,
) -> Result[(String, ImportByteRange, Int, Int), WasmError] {
  let start = reader.position()
  let size = match read_u32_as_int(reader) {
    Ok(n) => n
    Err(e) => return Err(e)
  }
  let prefix = reader.position() - start
  let name_start = reader.position()
  let bytes = match reader.read_bytes(size) {
    Ok(b) => b
    Err(e) => return Err(e)
  }
  let value = @utf8.decode(bytes) catch {
    _ =>
      return Err(
        InvalidImportEncoding(
          name_start,
          "invalid UTF-8 in import " + label + " name starting here",
        ),
      )
  }
  Ok((value, { offset: start, size: reader.position() - start, }, prefix, size))
}

///|
fn imports_limits(
  reader : Reader,
  table : Bool,
) -> Result[ImportLimits, WasmError] {
  let offset = reader.position()
  let flags = match reader.read_byte() {
    Ok(n) => n
    Err(e) => return Err(e)
  }
  let label = if table { "table" } else { "memory" }
  // Check width and supported forms BEFORE reading either bound. Never reuse
  // the legacy low-bit skipper for memory64/table64 or future flag shapes.
  if (flags & 4) != 0 {
    return Err(
      InvalidImportEncoding(
        offset,
        "unsupported " + label + "64 limits flags " + flags.to_string(),
      ),
    )
  }
  if !table && flags == 2 {
    return Err(
      InvalidImportEncoding(offset, "shared memory limits require a maximum"),
    )
  }
  if flags != 0 && flags != 1 && (table || flags != 3) {
    return Err(
      InvalidImportEncoding(
        offset,
        "unsupported " + label + " limits flags " + flags.to_string(),
      ),
    )
  }
  let minimum = match reader.read_u32_leb() {
    Ok(n) => n
    Err(e) => return Err(e)
  }
  let maximum = if flags == 1 || flags == 3 {
    let value = match reader.read_u32_leb() {
      Ok(n) => n
      Err(e) => return Err(e)
    }
    if minimum > value {
      return Err(
        InvalidImportEncoding(offset, label + " minimum exceeds maximum"),
      )
    }
    Some(value)
  } else {
    None
  }
  Ok({ flags, minimum, maximum, })
}

///|
fn imports_value_type(
  reader : Reader,
  table : Bool,
) -> Result[String, WasmError] {
  let offset = reader.position()
  let byte = match reader.read_byte() {
    Ok(n) => n
    Err(e) => return Err(e)
  }
  match byte {
    0x70 => Ok("funcref")
    0x6f => Ok("externref")
    0x7f if !table => Ok("i32")
    0x7e if !table => Ok("i64")
    0x7d if !table => Ok("f32")
    0x7c if !table => Ok("f64")
    0x7b if !table => Ok("v128")
    _ =>
      Err(
        InvalidImportEncoding(
          offset,
          "unsupported " +
          (if table { "table reference" } else { "global value" }) +
          " type encoding 0x" +
          byte.to_string(radix=16),
        ),
      )
  }
}

///|
fn imports_descriptor(
  reader : Reader,
) -> Result[(Int, UInt?, ImportLimits?, String?, Int?), WasmError] {
  let offset = reader.position()
  let kind = match reader.read_byte() {
    Ok(n) => n
    Err(e) => return Err(e)
  }
  match kind {
    0 => {
      let index = match reader.read_u32_leb() {
        Ok(n) => n
        Err(e) => return Err(e)
      }
      Ok((kind, Some(index), None, None, None))
    }
    1 => {
      let value_type = match imports_value_type(reader, true) {
        Ok(n) => n
        Err(e) => return Err(e)
      }
      let limits = match imports_limits(reader, true) {
        Ok(n) => n
        Err(e) => return Err(e)
      }
      Ok((kind, None, Some(limits), Some(value_type), None))
    }
    2 => {
      let limits = match imports_limits(reader, false) {
        Ok(n) => n
        Err(e) => return Err(e)
      }
      Ok((kind, None, Some(limits), None, None))
    }
    3 => {
      let value_type = match imports_value_type(reader, false) {
        Ok(n) => n
        Err(e) => return Err(e)
      }
      let at = reader.position()
      let mutability = match reader.read_byte() {
        Ok(n) => n
        Err(e) => return Err(e)
      }
      if mutability != 0 && mutability != 1 {
        return Err(
          InvalidImportEncoding(
            at,
            "invalid global mutability " +
            mutability.to_string() +
            " (expected 0 or 1)",
          ),
        )
      }
      Ok((kind, None, None, Some(value_type), Some(mutability)))
    }
    4 => {
      let at = reader.position()
      let attribute = match reader.read_byte() {
        Ok(n) => n
        Err(e) => return Err(e)
      }
      if attribute != 0 {
        return Err(
          InvalidImportEncoding(
            at,
            "unsupported tag attribute " +
            attribute.to_string() +
            " (expected 0)",
          ),
        )
      }
      let index = match reader.read_u32_leb() {
        Ok(n) => n
        Err(e) => return Err(e)
      }
      Ok((kind, Some(index), None, None, None))
    }
    _ =>
      Err(
        InvalidImportEncoding(
          offset,
          "unknown import kind " +
          kind.to_string() +
          " (supported kinds: 0..4); descriptor cannot be skipped",
        ),
      )
  }
}

///|
fn imports_kind_name(kind : Int) -> String {
  ["function", "table", "memory", "global", "tag"][kind]
}

///|
fn imports_counts(counts : Array[Int]) -> ImportKindCounts {
  {
    functions: counts[0],
    tables: counts[1],
    memories: counts[2],
    globals: counts[3],
    tags: counts[4],
  }
}

///|
fn imports_scope() -> String {
  "Import declaration encoding bytes, not host implementation or dependency package sizes. " +
  "Supported: function u32 type index; table funcref/externref with 32-bit limits flags 0/1; memory 32-bit flags 0/1/3 (shared requires maximum); " +
  "global i32/i64/f32/f64/v128/funcref/externref with mutability 0/1; tag attribute 0 and u32 type index. " +
  "Typed references, other GC forms, memory64/table64 and other flags are unsupported. " +
  "Declared type indices are not validated and signatures are not decoded. Names are exact UTF-8 strings, not interpreted package names, paths, URLs, permissions or environment compatibility claims. " +
  "Declarations do not establish runtime calls or permissions used. No removal, recompiled or transfer savings are inferred. " +
  "All ranges are original file offsets, not runtime addresses; parent/child totals are decompositions. Top limits text entries only; summaries and JSON remain complete."
}

///|
/// Inspect core import declarations only after the ordinary module checks.
/// No analyze, graph, function inventory or optional-content partial success.
pub fn inspect_imports(data : Bytes) -> Result[ImportsReport, WasmError] {
  let parsed = match parse_module(data) {
    Ok(m) => m
    Err(e) => return Err(e)
  }
  let entries : Array[ImportDeclaration] = []
  let counts = [0, 0, 0, 0, 0]
  let by_module : Map[String, Array[Int]] = Map([])
  let mut section : ImportByteRange? = None
  let mut count_encoding : ImportByteRange? = None
  let mut section_total = 0
  let mut header_bytes = 0
  for item in parsed.sections {
    if !same_kind(item.kind, Import) {
      continue
    }
    let reader = match reader_at_payload(data, item) {
      Ok(r) => r
      Err(e) => return Err(e)
    }
    section = Some({ offset: item.offset, size: item.total_size, })
    section_total = item.total_size
    header_bytes = item.total_size - item.payload_size
    let count_start = reader.position()
    let mut remaining = match reader.read_u32_leb() {
      Ok(n) => n
      Err(e) => return Err(e)
    }
    count_encoding = Some({
      offset: count_start,
      size: reader.position() - count_start,
    })
    while remaining > 0U {
      let start = reader.position()
      let (module_name, module_encoding, module_prefix, module_utf8) = match
        imports_name(reader, "module") {
        Ok(n) => n
        Err(e) => return Err(e)
      }
      let (field, field_encoding, field_prefix, field_utf8) = match
        imports_name(reader, "field") {
        Ok(n) => n
        Err(e) => return Err(e)
      }
      let descriptor_start = reader.position()
      let (kind, type_index, limits, value_type, mutability) = match
        imports_descriptor(reader) {
        Ok(n) => n
        Err(e) => return Err(e)
      }
      let ordinal = entries.length()
      entries.push({
        ordinal,
        kind: imports_kind_name(kind),
        kind_index: counts[kind],
        module_name,
        field,
        encoding: { offset: start, size: reader.position() - start, },
        module_encoding,
        field_encoding,
        descriptor: {
          offset: descriptor_start,
          size: reader.position() - descriptor_start,
        },
        module_length_prefix_bytes: module_prefix,
        module_utf8_bytes: module_utf8,
        field_length_prefix_bytes: field_prefix,
        field_utf8_bytes: field_utf8,
        type_index,
        limits,
        value_type,
        mutability,
      })
      counts[kind] += 1
      let ordinals = by_module.get(module_name).unwrap_or([])
      ordinals.push(ordinal)
      by_module.set(module_name, ordinals)
      remaining -= 1U
    }
    match finish_section(reader, Import) {
      Ok(_) => ()
      Err(e) => return Err(e)
    }
  }
  let modules : Array[ImportModule] = []
  for name, ordinals in by_module {
    let totals = [0, 0, 0, 0, 0]
    let mut bytes = 0
    for ordinal in ordinals {
      let entry = entries[ordinal]
      bytes += entry.encoding.size
      for kind in 0..<5 {
        if entry.kind == imports_kind_name(kind) {
          totals[kind] += 1
        }
      }
    }
    modules.push({
      module_name: name,
      entry_count: ordinals.length(),
      kind_counts: imports_counts(totals),
      entry_bytes: bytes,
      ordinals,
    })
  }
  modules.sort_by(fn(a, b) {
    let order = b.entry_bytes.compare(a.entry_bytes)
    if order == 0 {
      a.module_name.compare(b.module_name)
    } else {
      order
    }
  })
  let mut entry_bytes = 0
  let mut module_prefix = 0
  let mut module_utf8 = 0
  let mut field_prefix = 0
  let mut field_utf8 = 0
  let mut descriptor_bytes = 0
  for entry in entries {
    entry_bytes += entry.encoding.size
    module_prefix += entry.module_length_prefix_bytes
    module_utf8 += entry.module_utf8_bytes
    field_prefix += entry.field_length_prefix_bytes
    field_utf8 += entry.field_utf8_bytes
    descriptor_bytes += entry.descriptor.size
  }
  Ok({
    file_size: data.length(),
    sha256: experiment_sha256(data),
    supported_scope: imports_scope(),
    section,
    count_encoding,
    entry_count: entries.length(),
    kind_counts: imports_counts(counts),
    modules,
    entries,
    ledger: {
      import_section_total_bytes: section_total,
      section_header_bytes: header_bytes,
      count_prefix_bytes: count_encoding.map(fn(r) { r.size }).unwrap_or(0),
      entry_bytes,
      module_name_encoding_bytes: module_prefix + module_utf8,
      module_length_prefix_bytes: module_prefix,
      module_utf8_bytes: module_utf8,
      field_name_encoding_bytes: field_prefix + field_utf8,
      field_length_prefix_bytes: field_prefix,
      field_utf8_bytes: field_utf8,
      descriptor_bytes,
    },
  })
}
