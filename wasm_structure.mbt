///|
/// Core binary order, independent of numeric section ids (Tag=13, DataCount=12).
/// https://webassembly.github.io/spec/core/binary/modules.html#binary-module
fn section_order(kind : SectionId) -> Int {
  match kind {
    Custom => 0
    Type => 1
    Import => 2
    Function => 3
    Table => 4
    Memory => 5
    Tag => 6
    Global => 7
    Export => 8
    Start => 9
    Element => 10
    DataCount => 11
    Code => 12
    Data => 13
  }
}

///|
fn finish_section(reader : Reader, kind : SectionId) -> Result[Unit, WasmError] {
  if !reader.at_end() {
    Err(WasmError::TrailingSectionBytes(reader.position(), kind))
  } else {
    Ok(())
  }
}

///|
/// Read local declarations' type indices without validating their referents.
fn function_declaration_count(
  data : Bytes,
  section : Section,
) -> Result[Int, WasmError] {
  let reader = match reader_at_payload(data, section) {
    Ok(reader) => reader
    Err(error) => return Err(error)
  }
  let count = match read_u32_as_int(reader) {
    Ok(count) => count
    Err(error) => return Err(error)
  }
  for i = 0; i < count; i = i + 1 {
    match read_u32_as_int(reader) {
      Ok(_) => ()
      Err(error) => return Err(error)
    }
  }
  match finish_section(reader, Function) {
    Ok(_) => Ok(count)
    Err(error) => Err(error)
  }
}

///|
/// Missing function/code sections each contribute zero. Imports do not enter
/// this comparison. Every code body length is checked by the public parser's
/// shared walker, without building an analysis or allocating body records.
fn validate_function_code(
  data : Bytes,
  sections : Array[Section],
) -> Result[Unit, WasmError] {
  let mut declarations = 0
  let mut bodies = 0
  let mut related : Section? = None
  for section in sections {
    match section.kind {
      Function => {
        declarations = match function_declaration_count(data, section) {
          Ok(count) => count
          Err(error) => return Err(error)
        }
        related = Some(section)
      }
      Code => {
        bodies = match walk_code_section(data, section, 0, None) {
          Ok(count) => count
          Err(error) => return Err(error)
        }
        related = Some(section)
      }
      _ => ()
    }
  }
  if declarations != bodies {
    match related {
      Some(section) =>
        return Err(
          WasmError::FunctionCodeCountMismatch(
            section.offset,
            section.kind,
            declarations,
            bodies,
          ),
        )
      None => () // Both missing implies zero == zero.
    }
  }
  Ok(())
}
