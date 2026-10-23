///|
pub struct DuplicateFunctionMember {
  index : Int
  name : String
  raw_name : String?
  type_index : Int
  /// File offset of the actual body-length prefix.
  offset : Int
  body_offset : Int
  body_size : Int
  prefix_size : Int
  total_size : Int
}

///|
pub struct DuplicateFunctionGroup {
  sha256 : String
  body_size : Int
  member_count : Int
  member_body_bytes : Int
  member_prefix_bytes : Int
  member_total_bytes : Int
  members : Array[DuplicateFunctionMember]
}

///|
pub struct DuplicateFunctionsSummary {
  local_function_count : Int
  duplicate_group_count : Int
  duplicate_member_count : Int
  singleton_function_count : Int
  total_body_bytes : Int
  duplicate_body_bytes : Int
  singleton_body_bytes : Int
  total_prefix_bytes : Int
  total_encoded_bytes : Int
}

///|
pub struct DuplicateFunctionsReport {
  file_size : Int
  sha256 : String
  comparison_scope : String
  summary : DuplicateFunctionsSummary
  groups : Array[DuplicateFunctionGroup]
}

///|
/// Temporary original-file views only; public results retain ranges, not bodies.
priv struct DuplicateBodyBucket {
  sha256 : String
  bytes : BytesView
  members : Array[DuplicateFunctionMember]
}

///|
/// Read type references without interpreting the type or GC sections.
fn duplicate_type_indices(
  data : Bytes,
  parsed : WasmModule,
) -> Result[Array[Int], WasmError] {
  for section in parsed.sections {
    if same_kind(section.kind, Function) {
      let reader = match reader_at_payload(data, section) {
        Ok(r) => r
        Err(e) => return Err(e)
      }
      let count = match read_u32_as_int(reader) {
        Ok(n) => n
        Err(e) => return Err(e)
      }
      let indices : Array[Int] = []
      for _ in 0..<count {
        match read_u32_as_int(reader) {
          Ok(n) => indices.push(n)
          Err(e) => return Err(e)
        }
      }
      match finish_section(reader, Function) {
        Ok(_) => return Ok(indices)
        Err(e) => return Err(e)
      }
    }
  }
  Ok([])
}

///|
/// The bounded reader validates offset/total before addition or slicing. Check
/// subtraction before obtaining the prefix, then advance through that prefix.
fn duplicate_body_view(
  data : Bytes,
  body : FunctionBody,
) -> Result[(Int, Int, BytesView), WasmError] {
  let reader = match Reader::new_range(data, body.offset, body.total_size) {
    Ok(r) => r
    Err(e) => return Err(e)
  }
  if body.body_size < 0 || body.body_size > body.total_size {
    return Err(
      InvalidReadRange(body.offset, body.body_size, reader.start, reader.end),
    )
  }
  let prefix_size = body.total_size - body.body_size
  match reader.read_bytes(prefix_size) {
    Ok(_) => ()
    Err(e) => return Err(e)
  }
  let body_offset = reader.position()
  match reader.read_bytes(body.body_size) {
    Ok(bytes) => Ok((body_offset, prefix_size, bytes))
    Err(e) => Err(e)
  }
}

///|
/// Digest plus length selects a bucket; actual bytes decide membership. Kept
/// separate from hashing so collision handling is testable without a public knob.
fn duplicate_insert(
  buckets : Array[DuplicateBodyBucket],
  by_digest : Map[String, Array[Int]],
  digest : String,
  bytes : BytesView,
  definition : DuplicateFunctionMember,
) -> Unit {
  let key = digest + ":" + bytes.length().to_string()
  let candidates = by_digest.get(key).unwrap_or([])
  for index in candidates {
    if data_payload_equal(buckets[index].bytes, bytes) {
      buckets[index].members.push(definition)
      return
    }
  }
  candidates.push(buckets.length())
  by_digest.set(key, candidates)
  buckets.push({ sha256: digest, bytes, members: [definition], })
}

///|
fn duplicate_groups(
  buckets : Array[DuplicateBodyBucket],
) -> Array[DuplicateFunctionGroup] {
  let groups : Array[DuplicateFunctionGroup] = []
  for bucket in buckets {
    if bucket.members.length() < 2 {
      continue
    }
    bucket.members.sort_by(fn(a, b) { a.index.compare(b.index) })
    let mut body_bytes = 0
    let mut prefix_bytes = 0
    let mut encoded_bytes = 0
    for definition in bucket.members {
      body_bytes += definition.body_size
      prefix_bytes += definition.prefix_size
      encoded_bytes += definition.total_size
    }
    groups.push({
      sha256: bucket.sha256,
      body_size: bucket.bytes.length(),
      member_count: bucket.members.length(),
      member_body_bytes: body_bytes,
      member_prefix_bytes: prefix_bytes,
      member_total_bytes: encoded_bytes,
      members: bucket.members,
    })
  }
  groups.sort_by(fn(a, b) {
    let total = b.member_body_bytes.compare(a.member_body_bytes)
    if total != 0 {
      return total
    }
    let length = b.body_size.compare(a.body_size)
    if length != 0 {
      return length
    }
    let hash = a.sha256.compare(b.sha256)
    if hash != 0 {
      return hash
    }
    a.members[0].index.compare(b.members[0].index)
  })
  groups
}

///|
fn duplicate_scope() -> String {
  "Compare exact local function body bytes: locals declarations plus instructions, excluding the body-length prefix. " +
  "SHA-256 and length select candidates; actual bytes confirm every match. No normalization; names and type indices do not determine membership. " +
  "Identical bytes do not prove semantic/type/function-identity equivalence or safe merging; no identical bodies does not prove no semantic duplication. " +
  "Imported functions are excluded. Encoded totals include actual body-length prefixes but exclude code section header/count and all other sections. " +
  "No deletion, recompiled or gzip savings are estimated. No call graph, retained computation or full type/instruction validation is performed. " +
  "Top limits displayed groups only, not analysis cost; summaries and JSON remain complete."
}

///|
/// Structural size-only inspection; no analyze, graph or path query.
pub fn inspect_duplicate_functions(
  data : Bytes,
) -> Result[DuplicateFunctionsReport, WasmError] {
  let parsed = match parse_module(data) {
    Ok(m) => m
    Err(e) => return Err(e)
  }
  let sections = find_sections(parsed)
  let types = match duplicate_type_indices(data, parsed) {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  let imported = match sections.imports {
    None => 0
    Some(section) =>
      match count_imported_functions(data, section) {
        Ok(n) => n
        Err(e) => return Err(e)
      }
  }
  let bodies = match sections.code {
    None => []
    Some(section) =>
      match parse_code_section(data, section, base_index=imported) {
        Ok(v) => v
        Err(e) => return Err(e)
      }
  }
  // parse_module has already checked this; keep index correspondence explicit.
  if types.length() != bodies.length() {
    for section in parsed.sections {
      if same_kind(section.kind, Function) || same_kind(section.kind, Code) {
        return Err(
          FunctionCodeCountMismatch(
            section.offset,
            section.kind,
            types.length(),
            bodies.length(),
          ),
        )
      }
    }
  }
  let names = match sections.names {
    None => None
    Some(section) => parse_name_section(data, section)
  }
  let stats = function_stats(bodies, names)
  let buckets : Array[DuplicateBodyBucket] = []
  let by_digest : Map[String, Array[Int]] = Map([])
  let mut total_body_bytes = 0
  let mut total_prefix_bytes = 0
  let mut total_encoded_bytes = 0
  for ordinal, body in bodies {
    let (body_offset, prefix_size, bytes) = match
      duplicate_body_view(data, body) {
      Ok(v) => v
      Err(e) => return Err(e)
    }
    // crypto accepts Bytes, so this one hash uses a temporary owned copy.
    // Only the original-file view is retained while grouping.
    let digest = experiment_sha256(bytes.to_owned())
    duplicate_insert(buckets, by_digest, digest, bytes, {
      index: body.index,
      name: stats[ordinal].name,
      raw_name: stats[ordinal].raw_name,
      type_index: types[ordinal],
      offset: body.offset,
      body_offset,
      body_size: body.body_size,
      prefix_size,
      total_size: body.total_size,
    })
    total_body_bytes += body.body_size
    total_prefix_bytes += prefix_size
    total_encoded_bytes += body.total_size
  }
  let groups = duplicate_groups(buckets)
  let mut duplicate_member_count = 0
  let mut duplicate_body_bytes = 0
  for group in groups {
    duplicate_member_count += group.member_count
    duplicate_body_bytes += group.member_body_bytes
  }
  Ok({
    file_size: data.length(),
    sha256: experiment_sha256(data),
    comparison_scope: duplicate_scope(),
    groups,
    summary: {
      local_function_count: bodies.length(),
      duplicate_group_count: groups.length(),
      duplicate_member_count,
      singleton_function_count: bodies.length() - duplicate_member_count,
      total_body_bytes,
      duplicate_body_bytes,
      singleton_body_bytes: total_body_bytes - duplicate_body_bytes,
      total_prefix_bytes,
      total_encoded_bytes,
    },
  })
}
