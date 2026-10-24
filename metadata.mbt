///|
/// Half-open original-file range. Offsets are never memory addresses.
pub struct MetadataRange {
  offset : Int
  size : Int
} derive(Eq, Debug)

///|
pub struct MetadataCustom {
  ordinal : Int
  section_ordinal : Int
  encoding : MetadataRange
  section_header_bytes : Int
  name_encoding : MetadataRange
  name_length_prefix_bytes : Int
  name_bytes : MetadataRange
  name : String?
  category : String
  content : MetadataRange
  /// complete/partial for recognized name content; otherwise opaque.
  status : String
  name_subsection_bytes : Int
  unbounded_tail : MetadataRange?
}

///|
pub struct MetadataNameSubsection {
  custom_ordinal : Int
  ordinal : Int
  id : Int
  encoding : MetadataRange
  header_bytes : Int
  payload : MetadataRange
  /// complete/partial for id 1, opaque for all other ids.
  status : String
  declared_count : UInt?
  count_prefix_bytes : Int
  parsed_record_bytes : Int
  unparsed : MetadataRange?
}

///|
pub struct MetadataFunctionName {
  custom_ordinal : Int
  subsection_ordinal : Int
  ordinal : Int
  /// Metadata declaration only, not evidence that the function exists.
  function_index : UInt
  encoding : MetadataRange
  index_prefix_bytes : Int
  name_length_prefix_bytes : Int
  name_bytes : MetadataRange
  name : String?
}

///|
pub struct MetadataDiagnostic {
  offset : Int
  custom_ordinal : Int
  /// Includes a failed framing attempt; there need not be a bounded row.
  subsection_ordinal : Int?
  reason : String
}

///|
pub struct MetadataCategory {
  category : String
  custom_ordinals : Array[Int]
  total_bytes : Int
}

///|
pub struct MetadataNameGroup {
  /// None aggregates unavailable names, without claiming their bytes match.
  name : String?
  custom_ordinals : Array[Int]
  total_bytes : Int
}

///|
pub struct MetadataSummary {
  custom_count : Int
  custom_bytes : Int
  section_header_bytes : Int
  custom_name_encoding_bytes : Int
  content_bytes : Int
  unavailable_custom_count : Int
  unavailable_custom_bytes : Int
  name_custom_count : Int
  name_content_bytes : Int
  name_subsection_bytes : Int
  unbounded_name_tail_bytes : Int
  function_name_payload_bytes : Int
  function_name_count_prefix_bytes : Int
  parsed_function_record_count : Int
  parsed_function_record_bytes : Int
  function_name_unparsed_bytes : Int
  function_index_prefix_bytes : Int
  function_name_length_prefix_bytes : Int
  function_name_utf8_bytes : Int
  unavailable_function_name_count : Int
}

///|
pub struct MetadataReport {
  file_size : Int
  sha256 : String
  byte_ledger_complete : Bool
  custom_name_status : String
  /// absent/complete/partial within the supported name-detail interpretation.
  name_details_status : String
  modeling_scope : String
  summary : MetadataSummary
  categories : Array[MetadataCategory]
  name_groups : Array[MetadataNameGroup]
  customs : Array[MetadataCustom]
  subsections : Array[MetadataNameSubsection]
  function_names : Array[MetadataFunctionName]
  diagnostics : Array[MetadataDiagnostic]
}

///|
priv struct MetadataWork {
  subsections : Array[MetadataNameSubsection]
  records : Array[MetadataFunctionName]
  diagnostics : Array[MetadataDiagnostic]
}

///|
fn metadata_utf8(bytes : BytesView) -> String? {
  let name = @utf8.decode(bytes) catch { _ => return None }
  Some(name)
}

///|
fn metadata_record(
  reader : Reader,
  custom : Int,
  subsection : Int,
  ordinal : Int,
) -> Result[MetadataFunctionName, WasmError] {
  let start = reader.position()
  let function_index = match reader.read_u32_leb() {
    Ok(n) => n
    Err(e) => return Err(e)
  }
  let index_prefix_bytes = reader.position() - start
  let length_start = reader.position()
  let length = match read_u32_as_int(reader) {
    Ok(n) => n
    Err(e) => return Err(e)
  }
  let name_length_prefix_bytes = reader.position() - length_start
  let name_start = reader.position()
  let bytes = match reader.read_bytes(length) {
    Ok(b) => b
    Err(e) => return Err(e)
  }
  Ok({
    custom_ordinal: custom,
    subsection_ordinal: subsection,
    ordinal,
    function_index,
    encoding: { offset: start, size: reader.position() - start, },
    index_prefix_bytes,
    name_length_prefix_bytes,
    name_bytes: { offset: name_start, size: length, },
    name: metadata_utf8(bytes),
  })
}

///|
fn metadata_function_subsection(
  reader : Reader,
  custom : Int,
  ordinal : Int,
  start : Int,
  payload : MetadataRange,
  work : MetadataWork,
) -> MetadataNameSubsection {
  let mut status = "complete"
  let mut prefix = 0
  let mut record_bytes = 0
  let mut unparsed : MetadataRange? = None
  let count = match reader.read_u32_leb() {
    Ok(n) => {
      prefix = reader.position() - payload.offset
      Some(n)
    }
    Err(error) => {
      status = "partial"
      unparsed = Some(payload) // Include all consumed bytes of the failed count.
      work.diagnostics.push({
        offset: payload.offset,
        custom_ordinal: custom,
        subsection_ordinal: Some(ordinal),
        reason: "function-name count: " + describe_error(error),
      })
      None
    }
  }
  if count is Some(n) {
    let mut remaining = n
    let mut record_ordinal = 0
    while remaining > 0U {
      let record_start = reader.position()
      match metadata_record(reader, custom, ordinal, record_ordinal) {
        Err(error) => {
          status = "partial"
          unparsed = Some({
            offset: record_start,
            size: reader.end - record_start,
          })
          work.diagnostics.push({
            offset: record_start,
            custom_ordinal: custom,
            subsection_ordinal: Some(ordinal),
            reason: "function-name record \{record_ordinal}: " +
            describe_error(error),
          })
          break
        }
        Ok(record) => {
          record_bytes += record.encoding.size
          work.records.push(record)
          if record.name is None {
            status = "partial"
            work.diagnostics.push({
              offset: record.name_bytes.offset,
              custom_ordinal: custom,
              subsection_ordinal: Some(ordinal),
              reason: "function-name record \{record_ordinal}: invalid UTF-8 in name starting here; record remains delimited",
            })
          }
        }
      }
      remaining -= 1U
      record_ordinal += 1
    }
    if unparsed is None && !reader.at_end() {
      status = "partial"
      unparsed = Some({ offset: reader.position(), size: reader.remaining(), })
      work.diagnostics.push({
        offset: reader.position(),
        custom_ordinal: custom,
        subsection_ordinal: Some(ordinal),
        reason: "trailing bytes after the declared function-name records",
      })
    }
  }
  // Framing has already been bounded by the outer name reader, even on error.
  {
    custom_ordinal: custom,
    ordinal,
    id: 1,
    encoding: { offset: start, size: reader.end - start, },
    header_bytes: payload.offset - start,
    payload,
    status,
    declared_count: count,
    count_prefix_bytes: prefix,
    parsed_record_bytes: record_bytes,
    unparsed,
  }
}

///|
fn metadata_name_content(
  data : Bytes,
  reader : Reader,
  custom : Int,
  work : MetadataWork,
) -> (String, Int, MetadataRange?) {
  let mut ordinal = 0
  let mut bounded_bytes = 0
  let mut status = "complete"
  while !reader.at_end() {
    let start = reader.position()
    let framing = fn() -> Result[(Int, Int, Int), WasmError] {
      let id = match reader.read_byte() {
        Ok(n) => n
        Err(e) => return Err(e)
      }
      let size = match read_u32_as_int(reader) {
        Ok(n) => n
        Err(e) => return Err(e)
      }
      let payload_start = reader.position()
      match reader.read_bytes(size) {
        Ok(_) => Ok((id, payload_start, size))
        Err(e) => Err(e)
      }
    }
    let (id, payload_start, size) = match framing() {
      Ok(v) => v
      Err(error) => {
        work.diagnostics.push({
          offset: start,
          custom_ordinal: custom,
          subsection_ordinal: Some(ordinal),
          reason: "unbounded name subsection: " + describe_error(error),
        })
        return (
          "partial",
          bounded_bytes,
          Some({ offset: start, size: reader.end - start, }),
        )
      }
    }
    let payload : MetadataRange = { offset: payload_start, size, }
    let subsection = if id == 1 {
      // The entire payload was consumed above before constructing this reader.
      let sub = Reader::{
        data,
        start: payload_start,
        end: reader.position(),
        pos: payload_start,
      }
      metadata_function_subsection(sub, custom, ordinal, start, payload, work)
    } else {
      MetadataNameSubsection::{
        custom_ordinal: custom,
        ordinal,
        id,
        encoding: { offset: start, size: reader.position() - start, },
        header_bytes: payload_start - start,
        payload,
        status: "opaque",
        declared_count: None,
        count_prefix_bytes: 0,
        parsed_record_bytes: 0,
        unparsed: None,
      }
    }
    if subsection.status == "partial" {
      status = "partial"
    }
    bounded_bytes += subsection.encoding.size
    work.subsections.push(subsection)
    ordinal += 1
  }
  (status, bounded_bytes, None)
}

///|
fn metadata_custom(
  data : Bytes,
  section : Section,
  ordinal : Int,
  section_ordinal : Int,
  work : MetadataWork,
) -> Result[MetadataCustom, WasmError] {
  let reader = match reader_at_payload(data, section) {
    Ok(r) => r
    Err(e) => return Err(e)
  }
  let name_start = reader.position()
  let length = match read_u32_as_int(reader) {
    Ok(n) => n
    Err(e) => return Err(e)
  }
  let name_prefix = reader.position() - name_start
  let utf8_start = reader.position()
  let bytes = match reader.read_bytes(length) {
    Ok(b) => b
    Err(e) => return Err(e)
  }
  let content : MetadataRange = {
    offset: reader.position(),
    size: reader.remaining(),
  }
  let name = metadata_utf8(bytes) // Never trust Section.custom_name's lossy label.
  let category = match name {
    None => "unavailable"
    Some("name") => "name"
    Some("producers") => "producers"
    Some(n) => if n.has_prefix(".debug_") { "debug" } else { "other" }
  }
  if name is None {
    work.diagnostics.push({
      offset: utf8_start,
      custom_ordinal: ordinal,
      subsection_ordinal: None,
      reason: "invalid UTF-8 in custom name starting here; name and classification unavailable",
    })
  }
  let (status, bounded, tail) = if category == "name" {
    metadata_name_content(data, reader, ordinal, work)
  } else {
    ("opaque", 0, None)
  }
  Ok({
    ordinal,
    section_ordinal,
    encoding: { offset: section.offset, size: section.total_size, },
    section_header_bytes: section.total_size - section.payload_size,
    name_encoding: { offset: name_start, size: content.offset - name_start, },
    name_length_prefix_bytes: name_prefix,
    name_bytes: { offset: utf8_start, size: length, },
    name,
    category,
    content,
    status,
    name_subsection_bytes: bounded,
    unbounded_tail: tail,
  })
}

///|
fn metadata_scope() -> String {
  "Actual custom section file bytes; parent and child measurements are decompositions, not additive totals. " +
  "Only reliable full UTF-8 names determine classification; .debug_ is a name prefix, not DWARF validation. " +
  "Only name subsection id 1 is interpreted deeply; other subsections, producers and debug contents remain opaque, not failed. " +
  "Physical instances and records are retained; declared function indices do not establish function existence. " +
  "Partial details retain parsed records and all remainder ranges. Exit 0 does not certify that all custom contents were interpreted or semantically validated. " +
  "Metadata may be used by debuggers, loaders or other tools. No safe deletion, recompiled or transfer savings are inferred. " +
  "Top limits text details only; summaries, diagnostics and JSON remain complete."
}

///|
/// Inspect all physical custom/name records, without changing effective-name
/// selection, invoking analyze, building a graph, or copying opaque contents.
pub fn inspect_metadata(data : Bytes) -> Result[MetadataReport, WasmError] {
  let parsed = match parse_module(data) {
    Ok(m) => m
    Err(e) => return Err(e)
  }
  let work : MetadataWork = { subsections: [], records: [], diagnostics: [], }
  let customs : Array[MetadataCustom] = []
  for section_ordinal, section in parsed.sections {
    if section.kind.is_custom() {
      match
        metadata_custom(data, section, customs.length(), section_ordinal, work) {
        Ok(c) => customs.push(c)
        Err(e) => return Err(e)
      }
    }
  }
  let mut custom_bytes = 0
  let mut section_header_bytes = 0
  let mut custom_name_encoding_bytes = 0
  let mut content_bytes = 0
  let mut unavailable_custom_count = 0
  let mut unavailable_custom_bytes = 0
  let mut name_custom_count = 0
  let mut name_content_bytes = 0
  let mut name_subsection_bytes = 0
  let mut unbounded_name_tail_bytes = 0
  let mut name_partial = false
  let by_name : Map[String, Array[Int]] = Map([])
  let unavailable : Array[Int] = []
  for item in customs {
    custom_bytes += item.encoding.size
    section_header_bytes += item.section_header_bytes
    custom_name_encoding_bytes += item.name_encoding.size
    content_bytes += item.content.size
    match item.name {
      None => {
        unavailable.push(item.ordinal)
        unavailable_custom_count += 1
        unavailable_custom_bytes += item.encoding.size
      }
      Some(name) => {
        let ids = by_name.get(name).unwrap_or([])
        ids.push(item.ordinal)
        by_name.set(name, ids)
      }
    }
    if item.category == "name" {
      name_custom_count += 1
      name_content_bytes += item.content.size
      name_subsection_bytes += item.name_subsection_bytes
      unbounded_name_tail_bytes += item.unbounded_tail
        .map(fn(r) { r.size })
        .unwrap_or(0)
      if item.status == "partial" {
        name_partial = true
      }
    }
  }
  let categories : Array[MetadataCategory] = []
  for category in ["name", "producers", "debug", "other", "unavailable"] {
    let ids : Array[Int] = []
    let mut total = 0
    for item in customs {
      if item.category == category {
        ids.push(item.ordinal)
        total += item.encoding.size
      }
    }
    categories.push({ category, custom_ordinals: ids, total_bytes: total, })
  }
  let groups : Array[MetadataNameGroup] = []
  for name, ids in by_name {
    let mut total = 0
    for id in ids {
      total += customs[id].encoding.size
    }
    groups.push({ name: Some(name), custom_ordinals: ids, total_bytes: total, })
  }
  if !unavailable.is_empty() {
    groups.push({
      name: None,
      custom_ordinals: unavailable,
      total_bytes: unavailable_custom_bytes,
    })
  }
  groups.sort_by(fn(a, b) {
    let order = b.total_bytes.compare(a.total_bytes)
    if order != 0 {
      return order
    }
    match (a.name, b.name) {
      (Some(a), Some(b)) => a.compare(b)
      (Some(_), None) => -1
      (None, Some(_)) => 1
      (None, None) => 0
    }
  })
  let mut function_name_payload_bytes = 0
  let mut function_name_count_prefix_bytes = 0
  let mut function_name_unparsed_bytes = 0
  for sub in work.subsections {
    if sub.id == 1 {
      function_name_payload_bytes += sub.payload.size
      function_name_count_prefix_bytes += sub.count_prefix_bytes
      function_name_unparsed_bytes += sub.unparsed
        .map(fn(r) { r.size })
        .unwrap_or(0)
    }
  }
  let mut parsed_function_record_bytes = 0
  let mut function_index_prefix_bytes = 0
  let mut function_name_length_prefix_bytes = 0
  let mut function_name_utf8_bytes = 0
  let mut unavailable_function_name_count = 0
  for record in work.records {
    parsed_function_record_bytes += record.encoding.size
    function_index_prefix_bytes += record.index_prefix_bytes
    function_name_length_prefix_bytes += record.name_length_prefix_bytes
    function_name_utf8_bytes += record.name_bytes.size
    if record.name is None {
      unavailable_function_name_count += 1
    }
  }
  customs.sort_by(fn(a, b) {
    let order = b.encoding.size.compare(a.encoding.size)
    if order == 0 {
      a.encoding.offset.compare(b.encoding.offset)
    } else {
      order
    }
  })
  work.records.sort_by(fn(a, b) {
    let order = b.encoding.size.compare(a.encoding.size)
    if order == 0 {
      a.encoding.offset.compare(b.encoding.offset)
    } else {
      order
    }
  })
  work.diagnostics.sort_by(fn(a, b) {
    let order = a.offset.compare(b.offset)
    if order == 0 {
      a.reason.compare(b.reason)
    } else {
      order
    }
  })
  Ok({
    file_size: data.length(),
    sha256: experiment_sha256(data),
    byte_ledger_complete: true,
    custom_name_status: if unavailable_custom_count == 0 {
      "complete"
    } else {
      "partial"
    },
    name_details_status: if name_custom_count == 0 {
      "absent"
    } else if name_partial {
      "partial"
    } else {
      "complete"
    },
    modeling_scope: metadata_scope(),
    categories,
    name_groups: groups,
    customs,
    subsections: work.subsections,
    function_names: work.records,
    diagnostics: work.diagnostics,
    summary: {
      custom_count: customs.length(),
      custom_bytes,
      section_header_bytes,
      custom_name_encoding_bytes,
      content_bytes,
      unavailable_custom_count,
      unavailable_custom_bytes,
      name_custom_count,
      name_content_bytes,
      name_subsection_bytes,
      unbounded_name_tail_bytes,
      function_name_payload_bytes,
      function_name_count_prefix_bytes,
      parsed_function_record_count: work.records.length(),
      parsed_function_record_bytes,
      function_name_unparsed_bytes,
      function_index_prefix_bytes,
      function_name_length_prefix_bytes,
      function_name_utf8_bytes,
      unavailable_function_name_count,
    },
  })
}
