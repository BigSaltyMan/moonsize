///|
pub struct GenericInstance {
  index : Int
  raw_name : String
  raw_type_arguments : String
  type_labels : Array[String]
  total_size : Int
}

///|
pub struct GenericFamily {
  /// Exact raw stem, including kind and package identity; artifact-local only.
  family_key : String
  display_name : String
  definition_count : Int
  type_encoding_count : Int
  total_size : Int
  instances : Array[GenericInstance]
}

///|
pub struct GenericCoverage {
  total_functions : Int
  total_size : Int
  grouped_functions : Int
  grouped_size : Int
  named_ungrouped_functions : Int
  named_ungrouped_size : Int
  unnamed_functions : Int
  unnamed_size : Int
}

///|
pub struct GenericInstancesReport {
  file_size : Int
  sha256 : String
  /// missing, unreadable, or available. Unreadable metadata is not trusted.
  name_status : String
  recognition_scope : String
  coverage : GenericCoverage
  families : Array[GenericFamily]
}

///|
priv struct GenericSymbol {
  stem : String
  label : String
  encoding : String
  types : Array[String]
}

///|
/// Forward length parsing, separate from the heuristic display demangler.
/// Try each package-index/first-length boundary; ambiguous paths are rejected.
fn generic_path(bytes : Bytes, stop : Int) -> Array[String]? {
  if stop < 7 || bytes[4] != b'P' {
    return None
  }
  let mut digit_end = 5
  while digit_end < stop && is_ascii_digit(bytes[digit_end]) {
    digit_end += 1
  }
  let mut answer : Array[String]? = None
  for split in 6..<digit_end {
    let parts : Array[String] = []
    let mut pos = split
    let mut valid = true
    while pos < stop && valid {
      let start = pos
      let mut length = 0
      while pos < stop && is_ascii_digit(bytes[pos]) {
        length = length * 10 + (bytes[pos] - b'0').to_int()
        pos += 1
        if length > stop {
          valid = false
          break
        }
      }
      if !valid || pos == start || length == 0 || length > stop - pos {
        valid = false
        break
      }
      let end = pos + length
      if !is_ident_start(bytes[pos]) {
        valid = false
        break
      }
      let name = @utf8.decode_lossy(bytes[pos:end])
      while pos < end && valid {
        if bytes[pos] == b'_' {
          if pos + 1 < end && bytes[pos + 1] == b'_' {
            pos += 2
          } else if pos + 2 < end &&
            hex_value(bytes[pos + 1]) is Some(_) &&
            hex_value(bytes[pos + 2]) is Some(_) {
            pos += 3
          } else {
            valid = false
          }
        } else if is_ascii_letter(bytes[pos]) || is_ascii_digit(bytes[pos]) {
          pos += 1
        } else {
          valid = false
        }
      }
      parts.push(decode_escapes(name))
    }
    let minimum = if bytes[3] == b'M' { 3 } else { 2 }
    if valid && pos == stop && parts.length() >= minimum {
      if answer is Some(_) {
        return None
      }
      answer = Some(parts)
    }
  }
  answer
}

///|
/// Observed on the checked-in toolchain probe: F/M + numeric P path + G[i|d]+E.
/// No inferred named/tuple/closure/trait encodings; the entire symbol must fit.
fn generic_symbol(raw : String) -> GenericSymbol? {
  let bytes = @utf8.encode(raw)
  let end = bytes.length()
  if end > 4096 ||
    end < 9 ||
    !raw.has_prefix("_M0") ||
    (bytes[3] != b'F' && bytes[3] != b'M') ||
    bytes[end - 1] != b'E' {
    return None
  }
  let mut found : GenericSymbol? = None
  for split in 5..<(end - 2) {
    if bytes[split] != b'G' {
      continue
    }
    let types : Array[String] = []
    let mut supported = true
    for i in (split + 1)..<(end - 1) {
      match bytes[i] {
        b'i' => types.push("Int")
        b'd' => types.push("Double")
        _ => {
          supported = false
          break
        }
      }
    }
    if !supported || types.is_empty() {
      continue
    }
    if generic_path(bytes, split) is Some(parts) {
      if found is Some(_) {
        return None
      }
      found = Some({
        stem: @utf8.decode_lossy(bytes[0:split]),
        label: parts.join("::"),
        encoding: @utf8.decode_lossy(bytes[split:end]),
        types,
      })
    }
  }
  found
}

///|
/// Check the selected name section fully instead of trusting the legacy parser's
/// best-effort partial map. Other name subsections remain opaque bounded bytes.
fn generic_names_readable(data : Bytes, section : Section) -> Bool {
  let reader = match reader_at_payload(data, section) {
    Ok(r) => r
    Err(_) => return false
  }
  if skip_name(reader) is Err(_) {
    return false
  }
  let mut seen_functions = false
  while !reader.at_end() {
    let id = match reader.read_byte() {
      Ok(n) => n
      Err(_) => return false
    }
    let size = match read_u32_as_int(reader) {
      Ok(n) => n
      Err(_) => return false
    }
    let sub = match Reader::new_range(data, reader.position(), size) {
      Ok(r) => r
      Err(_) => return false
    }
    if size > reader.remaining() {
      return false
    }
    if id == 1 {
      if seen_functions {
        return false
      }
      seen_functions = true
      let count = match read_u32_as_int(sub) {
        Ok(n) => n
        Err(_) => return false
      }
      let indices : Set[Int] = Set([])
      for _ in 0..<count {
        let index = match read_u32_as_int(sub) {
          Ok(n) => n
          Err(_) => return false
        }
        if indices.contains(index) {
          return false
        }
        indices.add(index)
        let length = match read_u32_as_int(sub) {
          Ok(n) => n
          Err(_) => return false
        }
        let name = match sub.read_bytes(length) {
          Ok(b) => b
          Err(_) => return false
        }
        let _text = @utf8.decode(name) catch { _ => return false }
      }
      if !sub.at_end() {
        return false
      }
    }
    if reader.read_bytes(size) is Err(_) {
      return false
    }
  }
  true
}

///|
fn generic_scope() -> String {
  "Recognizes only fully parsed numeric-package F/M symbols with Int (i) or Double (d) type arguments (G...E), observed in the probe. " +
  "Closures, trait implementations, other types and ambiguous encodings remain ungrouped. Ungrouped named functions are not necessarily non-generic. " +
  "Compiler symbol conventions are not a complete official specification; family keys identify groups only within this artifact, not across toolchains. " +
  "Weights are local function total_size bytes including body length prefixes, excluding the code section header/count. " +
  "Inlined, merged or eliminated source instances are invisible. Encoded totals are not removable redundancy or predictions of recompiled or gzip savings."
}

///|
fn generic_aggregate(
  stats : Array[FunctionStat],
  file_size : Int,
  sha256 : String,
  name_status : String,
) -> GenericInstancesReport {
  let groups : Map[String, Array[GenericInstance]] = Map([])
  let labels : Map[String, String] = Map([])
  let mut total_size = 0
  let mut grouped_functions = 0
  let mut grouped_size = 0
  let mut named_ungrouped_functions = 0
  let mut named_ungrouped_size = 0
  let mut unnamed_functions = 0
  let mut unnamed_size = 0
  for stat in stats {
    total_size += stat.total_size
    let raw = if name_status == "available" { stat.raw_name } else { None }
    match raw {
      Some(raw) =>
        match generic_symbol(raw) {
          Some(symbol) => {
            let instances = groups.get(symbol.stem).unwrap_or([])
            instances.push({
              index: stat.index,
              raw_name: raw,
              raw_type_arguments: symbol.encoding,
              type_labels: symbol.types,
              total_size: stat.total_size,
            })
            groups.set(symbol.stem, instances)
            labels.set(symbol.stem, symbol.label)
            grouped_functions += 1
            grouped_size += stat.total_size
          }
          None => {
            named_ungrouped_functions += 1
            named_ungrouped_size += stat.total_size
          }
        }
      None => {
        unnamed_functions += 1
        unnamed_size += stat.total_size
      }
    }
  }
  let families : Array[GenericFamily] = []
  for key, instances in groups {
    instances.sort_by(fn(a, b) { a.index.compare(b.index) })
    let encodings : Set[String] = Set([])
    let mut size = 0
    for instance in instances {
      encodings.add(instance.raw_type_arguments)
      size += instance.total_size
    }
    families.push({
      family_key: key,
      display_name: labels.get(key).unwrap_or(key),
      definition_count: instances.length(),
      type_encoding_count: encodings.length(),
      total_size: size,
      instances,
    })
  }
  families.sort_by(fn(a, b) {
    let order = b.total_size.compare(a.total_size)
    if order == 0 {
      a.family_key.compare(b.family_key)
    } else {
      order
    }
  })
  {
    file_size,
    sha256,
    name_status,
    recognition_scope: generic_scope(),
    families,
    coverage: {
      total_functions: stats.length(),
      total_size,
      grouped_functions,
      grouped_size,
      named_ungrouped_functions,
      named_ungrouped_size,
      unnamed_functions,
      unnamed_size,
    },
  }
}

///|
/// Size-only inspection: never constructs a graph or invokes analyze/retained.
pub fn inspect_generic_instances(
  data : Bytes,
) -> Result[GenericInstancesReport, WasmError] {
  let parsed = match parse_module(data) {
    Ok(m) => m
    Err(e) => return Err(e)
  }
  let stats = match collect_function_stats(parsed, data) {
    Ok(s) => s
    Err(e) => return Err(e)
  }
  let status = match find_sections(parsed).names {
    None => "missing"
    Some(section) =>
      if generic_names_readable(data, section) {
        "available"
      } else {
        "unreadable"
      }
  }
  Ok(generic_aggregate(stats, data.length(), experiment_sha256(data), status))
}
