///|
/// Full table index space: imported tables first, then local declarations.
/// Other import kinds never advance this index. Export aliases collapse to the
/// first export position; explicit initializers remain unmodelled even if simple.
priv struct TableInfo {
  index : Int
  imported : Bool
  offset : Int
  mut export_offset : Int?
  initializer_offset : Int?
}

///|
fn table_context(
  data : Bytes,
  sections : Sections,
) -> Result[Array[TableInfo], WasmError] {
  let tables : Array[TableInfo] = []
  match sections.imports {
    Some(section) => {
      let reader = match reader_at_payload(data, section) {
        Ok(value) => value
        Err(error) => return Err(error)
      }
      let count = match read_u32_as_int(reader) {
        Ok(value) => value
        Err(error) => return Err(error)
      }
      for i = 0; i < count; i = i + 1 {
        for j = 0; j < 2; j = j + 1 {
          match skip_name(reader) {
            Ok(_) => ()
            Err(error) => return Err(error)
          }
        }
        let offset = reader.position()
        let kind = match reader.read_byte() {
          Ok(value) => value
          Err(error) => return Err(error)
        }
        if kind == 1 {
          match read_table_type(reader) {
            Ok(_) => ()
            Err(error) => return Err(error)
          }
          tables.push({
            index: tables.length(),
            imported: true,
            offset,
            export_offset: None,
            initializer_offset: None,
          })
        } else {
          match reader.seek(offset) {
            Ok(_) => ()
            Err(error) => return Err(error)
          }
          match skip_import_desc(reader) {
            Ok(_) => ()
            Err(error) => return Err(error)
          }
        }
      }
      match finish_section(reader, Import) {
        Ok(_) => ()
        Err(error) => return Err(error)
      }
    }
    None => ()
  }
  match sections.tables {
    Some(section) => {
      let definitions = match decode_tables(data, section) {
        Ok(value) => value
        Err(error) => return Err(error)
      }
      for table in definitions {
        tables.push({
          index: tables.length(),
          imported: false,
          offset: table.offset,
          export_offset: None,
          initializer_offset: table.initializer_offset,
        })
      }
    }
    None => ()
  }
  match sections.exports {
    Some(section) => {
      let reader = match reader_at_payload(data, section) {
        Ok(value) => value
        Err(error) => return Err(error)
      }
      let count = match read_u32_as_int(reader) {
        Ok(value) => value
        Err(error) => return Err(error)
      }
      for i = 0; i < count; i = i + 1 {
        match skip_name(reader) {
          Ok(_) => ()
          Err(error) => return Err(error)
        }
        let offset = reader.position()
        let kind = match reader.read_byte() {
          Ok(value) => value
          Err(error) => return Err(error)
        }
        let index = match read_u32_as_int(reader) {
          Ok(value) => value
          Err(error) => return Err(error)
        }
        if kind == 1 &&
          index < tables.length() &&
          tables[index].export_offset is None {
          tables[index].export_offset = Some(offset)
        }
      }
      match finish_section(reader, Export) {
        Ok(_) => ()
        Err(error) => return Err(error)
      }
    }
    None => ()
  }
  Ok(tables)
}

///|
/// Operand order is significant: table.init = [element, table],
/// table.copy = [destination, source]. Reads (get/size) are not writes.
fn written_table(instruction : Instruction) -> Int? {
  match instruction.opcode {
    TableInit => Some(instruction.operands[1])
    TableSet | TableCopy | TableGrow | TableFill =>
      Some(instruction.operands[0])
    _ => None
  }
}

///|
fn table_gap(
  site : IndirectSite,
  opcode : Opcode,
  kind : GraphDiagnosticKind,
  source : GraphDiagnosticSource?,
) -> GraphDiagnostic {
  {
    kind,
    caller: site.caller,
    offset: site.offset,
    opcode,
    type_index: Some(site.type_index),
    table_index: Some(site.table_index),
    source,
  }
}

///|
/// One reason per import/export/initializer and one per distinct writer offset.
/// These sources are independent: known candidates never suppress these gaps.
fn table_diagnostics(
  site : IndirectSite,
  opcode : Opcode,
  tables : Array[TableInfo],
  writes : Map[Int, Array[GraphDiagnosticSource]],
  diagnostics : Array[GraphDiagnostic],
) -> Unit {
  if site.table_index >= tables.length() {
    diagnostics.push(table_gap(site, opcode, UnknownTableContents, None))
  } else {
    let table = tables[site.table_index]
    // Assert the context's complete index space by construction, not local ids.
    if table.index == site.table_index {
      if table.imported {
        diagnostics.push(
          table_gap(
            site,
            opcode,
            ImportedTableContents,
            Some({ caller: None, offset: table.offset, opcode: None, }),
          ),
        )
      }
      match table.export_offset {
        Some(offset) =>
          diagnostics.push(
            table_gap(
              site,
              opcode,
              ExportedTableContents,
              Some({ caller: None, offset, opcode: None, }),
            ),
          )
        None => ()
      }
      match table.initializer_offset {
        Some(offset) =>
          diagnostics.push(
            table_gap(
              site,
              opcode,
              UnmodeledTableInitializer,
              Some({ caller: None, offset, opcode: None, }),
            ),
          )
        None => ()
      }
    } else {
      diagnostics.push(table_gap(site, opcode, UnknownTableContents, None))
    }
  }
  match writes.get(site.table_index) {
    Some(sources) =>
      for source in sources {
        diagnostics.push(
          table_gap(site, opcode, RuntimeTableMutation, Some(source)),
        )
      }
    None => ()
  }
}
