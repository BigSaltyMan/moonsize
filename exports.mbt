///|
/// Half-open original file range; never a runtime address.
pub struct ExportByteRange {
  offset : Int
  size : Int
} derive(Eq, Debug)

///|
pub struct ExportDeclaration {
  ordinal : Int
  name : String
  kind : String
  kind_code : Int
  target_index : UInt
  encoding : ExportByteRange
  name_encoding : ExportByteRange
  name_length_prefix_bytes : Int
  name_utf8_bytes : Int
  /// The kind byte plus the target index encoding.
  descriptor : ExportByteRange
  target_index_prefix_bytes : Int
}

///|
pub struct ExportTarget {
  kind : String
  kind_code : Int
  target_index : UInt
  entry_ordinals : Array[Int]
  member_count : Int
  declaration_bytes : Int
  is_alias : Bool
}

///|
pub struct ExportKindCounts {
  functions : Int
  tables : Int
  memories : Int
  globals : Int
  tags : Int
} derive(Eq, Debug)

///|
pub struct ExportsSummary {
  export_count : Int
  kind_counts : ExportKindCounts
  distinct_target_count : Int
  alias_group_count : Int
  alias_member_count : Int
  singleton_target_count : Int
} derive(Eq, Debug)

///|
/// Parent and child byte counts are decompositions, not additional costs.
pub struct ExportsLedger {
  export_section_bytes : Int
  section_header_bytes : Int
  count_prefix_bytes : Int
  declaration_bytes : Int
  name_encoding_bytes : Int
  name_length_prefix_bytes : Int
  name_utf8_bytes : Int
  descriptor_bytes : Int
  kind_bytes : Int
  target_index_prefix_bytes : Int
} derive(Eq, Debug)

///|
pub struct ExportsReport {
  file_size : Int
  sha256 : String
  section : ExportByteRange?
  count_encoding : ExportByteRange?
  summary : ExportsSummary
  ledger : ExportsLedger
  /// Complete physical declaration order, unaffected by text sorting or Top.
  entries : Array[ExportDeclaration]
  /// Kind code then full unsigned index ascending, including singleton targets.
  targets : Array[ExportTarget]
  supported_scope : String
}

///|
priv struct ExportTargetKey {
  kind : Int
  index : UInt
} derive(Eq, Hash)

///|
fn exports_kind_name(code : Int) -> String {
  match code {
    0 => "function"
    1 => "table"
    2 => "memory"
    3 => "global"
    4 => "tag"
    _ => "unknown" // Only 0..4 reach a successful report.
  }
}

///|
/// Inspect only export declarations after ordinary module framing checks.
/// No graph, body decoding, target/type validation or optional partial results.
pub fn inspect_exports(data : Bytes) -> Result[ExportsReport, WasmError] {
  let parsed = match parse_module(data) {
    Ok(parsed) => parsed
    Err(error) => return Err(error)
  }
  let entries : Array[ExportDeclaration] = []
  let seen_names : Map[String, Int] = Map([])
  let buckets : Map[ExportTargetKey, Array[Int]] = Map([])
  let counts = [0, 0, 0, 0, 0]
  let mut section : ExportByteRange? = None
  let mut count_encoding : ExportByteRange? = None
  let mut section_header_bytes = 0
  for item in parsed.sections {
    if !same_kind(item.kind, Export) {
      continue
    }
    let reader = match reader_at_payload(data, item) {
      Ok(reader) => reader
      Err(error) => return Err(error)
    }
    section = Some({ offset: item.offset, size: item.total_size, })
    section_header_bytes = item.total_size - item.payload_size
    let count_start = reader.position()
    let mut remaining = match reader.read_u32_leb() {
      Ok(count) => count
      Err(error) => return Err(error)
    }
    count_encoding = Some({
      offset: count_start,
      size: reader.position() - count_start,
    })
    while remaining > 0U {
      let start = reader.position()
      let length = match read_u32_as_int(reader) {
        Ok(length) => length
        Err(error) => return Err(error)
      }
      let name_length_prefix_bytes = reader.position() - start
      let name_start = reader.position()
      let raw_name = match reader.read_bytes(length) {
        Ok(bytes) => bytes
        Err(error) => return Err(error)
      }
      let name = @utf8.decode(raw_name) catch {
        _ =>
          return Err(
            InvalidExportEncoding(
              name_start, "invalid UTF-8 in export name starting here",
            ),
          )
      }
      if seen_names.get(name) is Some(first) {
        return Err(
          InvalidExportEncoding(
            start,
            "duplicate export name " +
            Json::string(name).stringify() +
            "; first declaration at file offset \{first}",
          ),
        )
      }
      seen_names.set(name, start)
      let descriptor_start = reader.position()
      let kind = match reader.read_byte() {
        Ok(kind) => kind
        Err(error) => return Err(error)
      }
      if kind < 0 || kind > 4 {
        return Err(
          InvalidExportEncoding(descriptor_start, "unknown export kind \{kind}"),
        )
      }
      let index_start = reader.position()
      let target_index = match reader.read_u32_leb() {
        Ok(index) => index
        Err(error) => return Err(error)
      }
      let ordinal = entries.length()
      entries.push({
        ordinal,
        name,
        kind: exports_kind_name(kind),
        kind_code: kind,
        target_index,
        encoding: { offset: start, size: reader.position() - start, },
        name_encoding: { offset: start, size: descriptor_start - start, },
        name_length_prefix_bytes,
        name_utf8_bytes: length,
        descriptor: {
          offset: descriptor_start,
          size: reader.position() - descriptor_start,
        },
        target_index_prefix_bytes: reader.position() - index_start,
      })
      counts[kind] += 1
      let key = ExportTargetKey::{ kind, index: target_index, }
      let ordinals = buckets.get_or_default(key, [])
      ordinals.push(ordinal)
      buckets.set(key, ordinals)
      remaining -= 1U
    }
    match finish_section(reader, Export) {
      Ok(_) => ()
      Err(error) => return Err(error)
    }
  }
  let targets : Array[ExportTarget] = []
  let mut alias_group_count = 0
  let mut alias_member_count = 0
  for key, ordinals in buckets {
    let mut declaration_bytes = 0
    for ordinal in ordinals {
      declaration_bytes += entries[ordinal].encoding.size
    }
    let is_alias = ordinals.length() >= 2
    if is_alias {
      alias_group_count += 1
      alias_member_count += ordinals.length()
    }
    targets.push({
      kind: exports_kind_name(key.kind),
      kind_code: key.kind,
      target_index: key.index,
      entry_ordinals: ordinals,
      member_count: ordinals.length(),
      declaration_bytes,
      is_alias,
    })
  }
  targets.sort_by(fn(a, b) {
    let order = a.kind_code.compare(b.kind_code)
    if order != 0 {
      order
    } else {
      a.target_index.compare(b.target_index)
    }
  })
  let mut declaration_bytes = 0
  let mut name_encoding_bytes = 0
  let mut name_length_prefix_bytes = 0
  let mut name_utf8_bytes = 0
  let mut descriptor_bytes = 0
  let mut target_index_prefix_bytes = 0
  for entry in entries {
    declaration_bytes += entry.encoding.size
    name_encoding_bytes += entry.name_encoding.size
    name_length_prefix_bytes += entry.name_length_prefix_bytes
    name_utf8_bytes += entry.name_utf8_bytes
    descriptor_bytes += entry.descriptor.size
    target_index_prefix_bytes += entry.target_index_prefix_bytes
  }
  Ok({
    file_size: data.length(),
    sha256: experiment_sha256(data),
    section,
    count_encoding,
    entries,
    targets,
    summary: {
      export_count: entries.length(),
      kind_counts: {
        functions: counts[0],
        tables: counts[1],
        memories: counts[2],
        globals: counts[3],
        tags: counts[4],
      },
      distinct_target_count: targets.length(),
      alias_group_count,
      alias_member_count,
      singleton_target_count: targets.length() - alias_group_count,
    },
    ledger: {
      export_section_bytes: section.map(fn(range) { range.size }).unwrap_or(0),
      section_header_bytes,
      count_prefix_bytes: count_encoding
      .map(fn(range) { range.size })
      .unwrap_or(0),
      declaration_bytes,
      name_encoding_bytes,
      name_length_prefix_bytes,
      name_utf8_bytes,
      descriptor_bytes,
      kind_bytes: entries.length(),
      target_index_prefix_bytes,
    },
    supported_scope: "Export declarations and exact UTF-8 host-visible names, not internal symbols or source names. Targets are grouped only by declared (kind, unsigned index); ordinals locate declarations within this file. Target existence, signatures, types, imported/local origin, reachability and runtime semantics are not validated. Function targets may be imports with no local body; host cost is not measured. Bytes cover declaration encodings only, not function bodies, dependency closures, memory capacities or host implementations. Alias groups do not establish safe removal or recompiled/gzip savings. Ranges are half-open file offsets, never memory addresses. Top limits text declarations and alias groups only; summaries and JSON remain complete.",
  })
}
