///|
/// The instruction table, checked one opcode at a time.
///
/// Every entry carries the bytes of a canonical encoding and the length the
/// specification gives it. The lengths here are written from the encoding rules
/// rather than read back from the decoder, so a wrong immediate width fails
/// here instead of quietly desynchronising a real function body.

///|
/// One row of the length table: bytes, mnemonic, encoded length.
fn opcode_table() -> Array[(Bytes, String, Int)] {
  [
    (b"\x00", "unreachable", 1),
    (b"\x01", "nop", 1),
    (b"\x02\x40", "block", 2),
    (b"\x03\x40", "loop", 2),
    (b"\x04\x40", "if", 2),
    (b"\x05", "else", 1),
    (b"\x06\x40", "try", 2),
    (b"\x07\x00", "catch", 2),
    (b"\x08\x00", "throw", 2),
    (b"\x09\x00", "rethrow", 2),
    (b"\x0a", "throw_ref", 1),
    (b"\x0b", "end", 1),
    (b"\x0c\x00", "br", 2),
    (b"\x0d\x00", "br_if", 2),
    (b"\x0e\x01\x00\x00", "br_table", 4),
    (b"\x0f", "return", 1),
    (b"\x10\x00", "call", 2),
    (b"\x11\x00\x00", "call_indirect", 3),
    (b"\x12\x00", "return_call", 2),
    (b"\x13\x00\x00", "return_call_indirect", 3),
    (b"\x14\x00", "call_ref", 2),
    (b"\x15\x00", "return_call_ref", 2),
    (b"\x1a", "drop", 1),
    (b"\x1b", "select", 1),
    (b"\x18\x00", "delegate", 2),
    (b"\x19", "catch_all", 1),
    (b"\x1c\x01\x7f", "select_t", 3),
    (b"\x20\x00", "local.get", 2),
    (b"\x21\x00", "local.set", 2),
    (b"\x22\x00", "local.tee", 2),
    (b"\x23\x00", "global.get", 2),
    (b"\x24\x00", "global.set", 2),
    (b"\x25\x00", "table.get", 2),
    (b"\x26\x00", "table.set", 2),
    (b"\x28\x00\x00", "i32.load", 3),
    (b"\x29\x00\x00", "i64.load", 3),
    (b"\x2a\x00\x00", "f32.load", 3),
    (b"\x2b\x00\x00", "f64.load", 3),
    (b"\x2c\x00\x00", "i32.load8_s", 3),
    (b"\x2d\x00\x00", "i32.load8_u", 3),
    (b"\x2e\x00\x00", "i32.load16_s", 3),
    (b"\x2f\x00\x00", "i32.load16_u", 3),
    (b"\x30\x00\x00", "i64.load8_s", 3),
    (b"\x31\x00\x00", "i64.load8_u", 3),
    (b"\x32\x00\x00", "i64.load16_s", 3),
    (b"\x33\x00\x00", "i64.load16_u", 3),
    (b"\x34\x00\x00", "i64.load32_s", 3),
    (b"\x35\x00\x00", "i64.load32_u", 3),
    (b"\x36\x00\x00", "i32.store", 3),
    (b"\x37\x00\x00", "i64.store", 3),
    (b"\x38\x00\x00", "f32.store", 3),
    (b"\x39\x00\x00", "f64.store", 3),
    (b"\x3a\x00\x00", "i32.store8", 3),
    (b"\x3b\x00\x00", "i32.store16", 3),
    (b"\x3c\x00\x00", "i64.store8", 3),
    (b"\x3d\x00\x00", "i64.store16", 3),
    (b"\x3e\x00\x00", "i64.store32", 3),
    (b"\x3f\x00", "memory.size", 2),
    (b"\x40\x00", "memory.grow", 2),
    (b"\x41\x00", "i32.const", 2),
    (b"\x42\x00", "i64.const", 2),
    (b"\x43\x00\x00\x00\x00", "f32.const", 5),
    (b"\x44\x00\x00\x00\x00\x00\x00\x00\x00", "f64.const", 9),
    (b"\x45", "i32.eqz", 1),
    (b"\x46", "i32.eq", 1),
    (b"\x47", "i32.ne", 1),
    (b"\x48", "i32.lt_s", 1),
    (b"\x49", "i32.lt_u", 1),
    (b"\x4a", "i32.gt_s", 1),
    (b"\x4b", "i32.gt_u", 1),
    (b"\x4c", "i32.le_s", 1),
    (b"\x4d", "i32.le_u", 1),
    (b"\x4e", "i32.ge_s", 1),
    (b"\x4f", "i32.ge_u", 1),
    (b"\x50", "i64.eqz", 1),
    (b"\x51", "i64.eq", 1),
    (b"\x52", "i64.ne", 1),
    (b"\x53", "i64.lt_s", 1),
    (b"\x54", "i64.lt_u", 1),
    (b"\x55", "i64.gt_s", 1),
    (b"\x56", "i64.gt_u", 1),
    (b"\x57", "i64.le_s", 1),
    (b"\x58", "i64.le_u", 1),
    (b"\x59", "i64.ge_s", 1),
    (b"\x5a", "i64.ge_u", 1),
    (b"\x5b", "f32.eq", 1),
    (b"\x5c", "f32.ne", 1),
    (b"\x5d", "f32.lt", 1),
    (b"\x5e", "f32.gt", 1),
    (b"\x5f", "f32.le", 1),
    (b"\x60", "f32.ge", 1),
    (b"\x61", "f64.eq", 1),
    (b"\x62", "f64.ne", 1),
    (b"\x63", "f64.lt", 1),
    (b"\x64", "f64.gt", 1),
    (b"\x65", "f64.le", 1),
    (b"\x66", "f64.ge", 1),
    (b"\x67", "i32.clz", 1),
    (b"\x68", "i32.ctz", 1),
    (b"\x69", "i32.popcnt", 1),
    (b"\x6a", "i32.add", 1),
    (b"\x6b", "i32.sub", 1),
    (b"\x6c", "i32.mul", 1),
    (b"\x6d", "i32.div_s", 1),
    (b"\x6e", "i32.div_u", 1),
    (b"\x6f", "i32.rem_s", 1),
    (b"\x70", "i32.rem_u", 1),
    (b"\x71", "i32.and", 1),
    (b"\x72", "i32.or", 1),
    (b"\x73", "i32.xor", 1),
    (b"\x74", "i32.shl", 1),
    (b"\x75", "i32.shr_s", 1),
    (b"\x76", "i32.shr_u", 1),
    (b"\x77", "i32.rotl", 1),
    (b"\x78", "i32.rotr", 1),
    (b"\x79", "i64.clz", 1),
    (b"\x7a", "i64.ctz", 1),
    (b"\x7b", "i64.popcnt", 1),
    (b"\x7c", "i64.add", 1),
    (b"\x7d", "i64.sub", 1),
    (b"\x7e", "i64.mul", 1),
    (b"\x7f", "i64.div_s", 1),
    (b"\x80", "i64.div_u", 1),
    (b"\x81", "i64.rem_s", 1),
    (b"\x82", "i64.rem_u", 1),
    (b"\x83", "i64.and", 1),
    (b"\x84", "i64.or", 1),
    (b"\x85", "i64.xor", 1),
    (b"\x86", "i64.shl", 1),
    (b"\x87", "i64.shr_s", 1),
    (b"\x88", "i64.shr_u", 1),
    (b"\x89", "i64.rotl", 1),
    (b"\x8a", "i64.rotr", 1),
    (b"\x8b", "f32.abs", 1),
    (b"\x8c", "f32.neg", 1),
    (b"\x8d", "f32.ceil", 1),
    (b"\x8e", "f32.floor", 1),
    (b"\x8f", "f32.trunc", 1),
    (b"\x90", "f32.nearest", 1),
    (b"\x91", "f32.sqrt", 1),
    (b"\x92", "f32.add", 1),
    (b"\x93", "f32.sub", 1),
    (b"\x94", "f32.mul", 1),
    (b"\x95", "f32.div", 1),
    (b"\x96", "f32.min", 1),
    (b"\x97", "f32.max", 1),
    (b"\x98", "f32.copysign", 1),
    (b"\x99", "f64.abs", 1),
    (b"\x9a", "f64.neg", 1),
    (b"\x9b", "f64.ceil", 1),
    (b"\x9c", "f64.floor", 1),
    (b"\x9d", "f64.trunc", 1),
    (b"\x9e", "f64.nearest", 1),
    (b"\x9f", "f64.sqrt", 1),
    (b"\xa0", "f64.add", 1),
    (b"\xa1", "f64.sub", 1),
    (b"\xa2", "f64.mul", 1),
    (b"\xa3", "f64.div", 1),
    (b"\xa4", "f64.min", 1),
    (b"\xa5", "f64.max", 1),
    (b"\xa6", "f64.copysign", 1),
    (b"\xa7", "i32.wrap_i64", 1),
    (b"\xa8", "i32.trunc_f32_s", 1),
    (b"\xa9", "i32.trunc_f32_u", 1),
    (b"\xaa", "i32.trunc_f64_s", 1),
    (b"\xab", "i32.trunc_f64_u", 1),
    (b"\xac", "i64.extend_i32_s", 1),
    (b"\xad", "i64.extend_i32_u", 1),
    (b"\xae", "i64.trunc_f32_s", 1),
    (b"\xaf", "i64.trunc_f32_u", 1),
    (b"\xb0", "i64.trunc_f64_s", 1),
    (b"\xb1", "i64.trunc_f64_u", 1),
    (b"\xb2", "f32.convert_i32_s", 1),
    (b"\xb3", "f32.convert_i32_u", 1),
    (b"\xb4", "f32.convert_i64_s", 1),
    (b"\xb5", "f32.convert_i64_u", 1),
    (b"\xb6", "f32.demote_f64", 1),
    (b"\xb7", "f64.convert_i32_s", 1),
    (b"\xb8", "f64.convert_i32_u", 1),
    (b"\xb9", "f64.convert_i64_s", 1),
    (b"\xba", "f64.convert_i64_u", 1),
    (b"\xbb", "f64.promote_f32", 1),
    (b"\xbc", "i32.reinterpret_f32", 1),
    (b"\xbd", "i64.reinterpret_f64", 1),
    (b"\xbe", "f32.reinterpret_i32", 1),
    (b"\xbf", "f64.reinterpret_i64", 1),
    (b"\xc0", "i32.extend8_s", 1),
    (b"\xc1", "i32.extend16_s", 1),
    (b"\xc2", "i64.extend8_s", 1),
    (b"\xc3", "i64.extend16_s", 1),
    (b"\xc4", "i64.extend32_s", 1),
    (b"\xd0\x70", "ref.null", 2),
    (b"\xd1", "ref.is_null", 1),
    (b"\xd2\x00", "ref.func", 2),
    (b"\xd3", "ref.eq", 1),
    (b"\xd4", "ref.as_non_null", 1),
    (b"\xd5\x00", "br_on_null", 2),
    (b"\xd6\x00", "br_on_non_null", 2),
    (b"\xfc\x00", "i32.trunc_sat_f32_s", 2),
    (b"\xfc\x01", "i32.trunc_sat_f32_u", 2),
    (b"\xfc\x02", "i32.trunc_sat_f64_s", 2),
    (b"\xfc\x03", "i32.trunc_sat_f64_u", 2),
    (b"\xfc\x04", "i64.trunc_sat_f32_s", 2),
    (b"\xfc\x05", "i64.trunc_sat_f32_u", 2),
    (b"\xfc\x06", "i64.trunc_sat_f64_s", 2),
    (b"\xfc\x07", "i64.trunc_sat_f64_u", 2),
    (b"\xfc\x08\x00\x00", "memory.init", 4),
    (b"\xfc\x09\x00", "data.drop", 3),
    (b"\xfc\x0a\x00\x00", "memory.copy", 4),
    (b"\xfc\x0b\x00", "memory.fill", 3),
    (b"\xfc\x0c\x00\x00", "table.init", 4),
    (b"\xfc\x0d\x00", "elem.drop", 3),
    (b"\xfc\x0e\x00\x00", "table.copy", 4),
    (b"\xfc\x0f\x00", "table.grow", 3),
    (b"\xfc\x10\x00", "table.size", 3),
    (b"\xfc\x11\x00", "table.fill", 3),
    (b"\xfb\x00\x00", "struct.new", 3),
    (b"\xfb\x01\x00", "struct.new_default", 3),
    (b"\xfb\x02\x00\x00", "struct.get", 4),
    (b"\xfb\x03\x00\x00", "struct.get_s", 4),
    (b"\xfb\x04\x00\x00", "struct.get_u", 4),
    (b"\xfb\x05\x00\x00", "struct.set", 4),
    (b"\xfb\x06\x00", "array.new", 3),
    (b"\xfb\x07\x00", "array.new_default", 3),
    (b"\xfb\x08\x00\x00", "array.new_fixed", 4),
    (b"\xfb\x09\x00\x00", "array.new_data", 4),
    (b"\xfb\x0a\x00\x00", "array.new_elem", 4),
    (b"\xfb\x0b\x00", "array.get", 3),
    (b"\xfb\x0c\x00", "array.get_s", 3),
    (b"\xfb\x0d\x00", "array.get_u", 3),
    (b"\xfb\x0e\x00", "array.set", 3),
    (b"\xfb\x0f", "array.len", 2),
    (b"\xfb\x10\x00", "array.fill", 3),
    (b"\xfb\x11\x00\x00", "array.copy", 4),
    (b"\xfb\x12\x00\x00", "array.init_data", 4),
    (b"\xfb\x13\x00\x00", "array.init_elem", 4),
    (b"\xfb\x14\x70", "ref.test", 3),
    (b"\xfb\x15\x70", "ref.test_null", 3),
    (b"\xfb\x16\x70", "ref.cast", 3),
    (b"\xfb\x17\x70", "ref.cast_null", 3),
    (b"\xfb\x18\x00\x70\x70", "br_on_cast", 5),
    (b"\xfb\x19\x00\x70\x70", "br_on_cast_fail", 5),
    (b"\xfb\x1a", "any.convert_extern", 2),
    (b"\xfb\x1b", "extern.convert_any", 2),
    (b"\xfb\x1c", "ref.i31", 2),
    (b"\xfb\x1d", "i31.get_s", 2),
    (b"\xfb\x1e", "i31.get_u", 2),
  ]
}

///|
test "every opcode decodes to its length and mnemonic" {
  let entries = opcode_table()
  inspect(
    entries.length(),
    content=(
      #|247
    ),
  )
  for entry in entries {
    let bytes = entry.0
    let name = entry.1
    let length = entry.2
    match decode_instruction(bytes, 0) {
      Ok(instruction) => {
        if instruction.opcode.name() != name {
          fail(name + ": decoded as " + instruction.opcode.name())
        }
        if instruction.size != length {
          fail(
            name +
            ": expected " +
            length.to_string() +
            " bytes, got " +
            instruction.size.to_string(),
          )
        }
      }
      Err(error) => fail(name + ": " + describe_error(error))
    }
  }
}

///|
test "an unassigned opcode is an error with its offset" {
  match decode_instruction(b"\xc5", 0) {
    Err(WasmError::UnknownOpcode(offset, byte)) => {
      inspect(
        offset,
        content=(
          #|0
        ),
      )
      inspect(
        byte,
        content=(
          #|197
        ),
      )
    }
    Ok(_) => fail("expected UnknownOpcode")
    Err(_) => fail("expected UnknownOpcode")
  }
}

///|
test "an unassigned prefixed opcode names both bytes" {
  match decode_instruction(b"\xfb\x7f", 0) {
    Err(WasmError::UnknownPrefixedOpcode(offset, prefix, sub)) => {
      inspect(
        offset,
        content=(
          #|0
        ),
      )
      inspect(
        prefix,
        content=(
          #|251
        ),
      )
      inspect(
        sub,
        content=(
          #|127
        ),
      )
    }
    Ok(_) => fail("expected UnknownPrefixedOpcode")
    Err(_) => fail("expected UnknownPrefixedOpcode")
  }
}

///|
test "immediates are recorded in encoding order" {
  // br_table with two targets and a default.
  match decode_instruction(b"\x0e\x02\x01\x00\x03", 0) {
    Ok(instruction) => {
      inspect(
        instruction.opcode.name(),
        content=(
          #|br_table
        ),
      )
      inspect(
        instruction.size,
        content=(
          #|5
        ),
      )
      assert_eq(instruction.operands, [2, 1, 0, 3])
    }
    Err(error) => fail(describe_error(error))
  }
  // local.get 200 needs two LEB128 groups.
  match decode_instruction(b"\x20\xc8\x01", 0) {
    Ok(instruction) => {
      inspect(
        instruction.size,
        content=(
          #|3
        ),
      )
      assert_eq(instruction.operands, [200])
    }
    Err(error) => fail(describe_error(error))
  }
  // memory.copy names both memories.
  match decode_instruction(b"\xfc\x0a\x00\x00", 0) {
    Ok(instruction) => {
      inspect(
        instruction.opcode.name(),
        content=(
          #|memory.copy
        ),
      )
      inspect(
        instruction.size,
        content=(
          #|4
        ),
      )
    }
    Err(error) => fail(describe_error(error))
  }
  // struct.get carries a type index and a field index.
  match decode_instruction(b"\xfb\x02\x17\x05", 0) {
    Ok(instruction) => {
      inspect(
        instruction.opcode.name(),
        content=(
          #|struct.get
        ),
      )
      assert_eq(instruction.operands, [23, 5])
    }
    Err(error) => fail(describe_error(error))
  }
}

///|
test "signed constants keep their sign" {
  // i32.const -1 is a single 0x7f group.
  match decode_instruction(b"\x41\x7f", 0) {
    Ok(instruction) => assert_eq(instruction.operands, [-1])
    Err(error) => fail(describe_error(error))
  }
  // i32.const 64 needs a second group because bit 6 would read as a sign.
  match decode_instruction(b"\x41\xc0\x00", 0) {
    Ok(instruction) => {
      inspect(
        instruction.size,
        content=(
          #|3
        ),
      )
      assert_eq(instruction.operands, [64])
    }
    Err(error) => fail(describe_error(error))
  }
  // i64.const -1 is ten groups wide, so nine continuation bits.
  match decode_instruction(b"\x42\xff\xff\xff\xff\xff\xff\xff\xff\xff\x7f", 0) {
    Ok(instruction) =>
      inspect(
        instruction.size,
        content=(
          #|11
        ),
      )
    Err(error) => fail(describe_error(error))
  }
}

///|
test "a block type may be a value type, an index or a reference type" {
  // Empty block type.
  match decode_instruction(b"\x02\x40", 0) {
    Ok(instruction) => assert_eq(instruction.operands, [-64])
    Err(error) => fail(describe_error(error))
  }
  // A type index large enough to need two groups.
  match decode_instruction(b"\x02\xc0\x00", 0) {
    Ok(instruction) => {
      inspect(
        instruction.size,
        content=(
          #|3
        ),
      )
      assert_eq(instruction.operands, [64])
    }
    Err(error) => fail(describe_error(error))
  }
  // The GC form: 0x63/0x64 followed by a heap type, which is two bytes wide.
  match decode_instruction(b"\x02\x63\x17", 0) {
    Ok(instruction) => {
      inspect(
        instruction.size,
        content=(
          #|3
        ),
      )
      assert_eq(instruction.operands, [99, 23])
    }
    Err(error) => fail(describe_error(error))
  }
}

///|
test "a function body skips a locals declaration with GC types in it" {
  // Two local groups, the second a two-byte reference type.
  let body = b"\x02\x01\x7f\x01\x63\x17\x0b"
  match decode_instructions(body, 0, body.length()) {
    Ok(instructions) => {
      inspect(
        instructions.length(),
        content=(
          #|1
        ),
      )
      inspect(
        instructions[0].opcode.name(),
        content=(
          #|end
        ),
      )
      inspect(
        instructions[0].offset,
        content=(
          #|6
        ),
      )
    }
    Err(error) => fail(describe_error(error))
  }
}

///|
test "decoding stops at the declared body size" {
  // A body whose declared size cuts an instruction in half.
  let body = b"\x00\x41\x80"
  match decode_instructions(body, 0, body.length()) {
    Err(WasmError::UnexpectedEnd(_, _)) => ()
    Ok(_) => fail("expected UnexpectedEnd")
    Err(_) => fail("expected UnexpectedEnd")
  }
}

///|
/// A real body from a MoonBit `wasm-gc` build: ten local groups, four of them
/// two-byte reference types, then struct reads and a loop. Skipping locals one
/// byte at a time desynchronises on this body, which is why it is here.
fn gc_body() -> Bytes {
  b"\x0a\x01\x7f\x02\x7e\x01\x7f\x01\x7e\x01\x7f\x01\x63\x17\x01\x64\x17\x01\x63" +
  b"\x17\x02\x64\x17\x02\x7e\x20\x00\x44\x00\x00\x00\x00\x00\x00\x00\x00\x61\x04" +
  b"\x40\x41\x01\x41\x02\x41\x01\x10\x03\x0f\x0b\x20\x00\x44\x00\x00\x00\x00\x00" +
  b"\x00\x40\xc3\x66\x04\x7f\x20\x00\x44\x00\x00\x00\x00\x00\x00\x40\x43\x65\x05" +
  b"\x41\x00\x0b\x04\x40\x20\x00\x44\x00\x00\x00\x00\x00\x00\xe0\xc1\x66\x04\x7f" +
  b"\x20\x00\x44\x00\x00\xc0\xff\xff\xff\xdf\x41\x65\x05\x41\x00\x0b\x04\x40\x20" +
  b"\x00\xfc\x02\x22\x01\xb7\x20\x00\x61\x04\x40\x20\x01\x41\x0a\x10\x20\x0f\x0b" +
  b"\x05\x20\x00\xfc\x06\x22\x02\xb9\x20\x00\x61\x04\x40\x20\x02\x41\x0a\x10\x19" +
  b"\x0f\x0b\x0b\x0b\x20\x00\xbd\x22\x03\x41\x3f\xac\x88\x42\x01\x83\x42\x00\x52" +
  b"\x21\x04\x20\x03\x42\xff\xff\xff\xff\xff\xff\xff\x07\x83\x21\x05\x20\x03\x41" +
  b"\x34\xac\x88\x42\xff\x0f\x83\xa7\x22\x06\x41\xff\x0f\x46\x04\x7f\x41\x01\x05" +
  b"\x20\x06\x41\x00\x46\x04\x7f\x20\x05\x42\x00\x51\x05\x41\x00\x0b\x0b\x04\x40" +
  b"\x20\x04\x20\x06\x41\x00\x47\x20\x05\x42\x00\x52\x10\x14\x0f\x0b\x20\x05\x20" +
  b"\x06\x10\x09\x22\x07\xd1\x04\x64\x17\x20\x05\x20\x06\x10\x0b\x05\x20\x07\x22" +
  b"\x09\xd4\x21\x0a\x02\x64\x17\x20\x0a\x03\x26\x22\x0b\xfb\x02\x17\x00\x42\x0a" +
  b"\x80\x21\x0c\x20\x0b\xfb\x02\x17\x00\x42\x0a\x20\x0c\x7e\x7d\x22\x0d\x42\x00" +
  b"\x52\x04\x40\x20\x0b\x0c\x02\x0b\x20\x0c\x20\x0b\xfb\x02\x17\x01\x41\x01\x6a" +
  b"\xfb\x00\x17\x0c\x00\x0b\x0b\x0b\x22\x08\x20\x04\x10\x0a\x0b"
}

///|
/// A real body from the same build: struct.get and struct.set through the GC
/// encoding, whose immediates are a type index *and* a field index.
fn struct_body() -> Bytes {
  b"\x00\x20\x00\xfb\x02\x19\x01\x41\x00\x41\x00\x41\x01\x10\x03\x10\x02\x20\x00" +
  b"\xfb\x02\x19\x00\xfb\x02\x18\x01\x41\x0a\x10\x20\x10\x02\x0b"
}

///|
/// A real body from a MoonBit linear-memory build: saturating conversions via
/// the 0xFC prefix and a br_table.
fn linear_body() -> Bytes {
  b"\x01\x04\x7f\x20\x01\x28\x00\x00\x41\x7c\x71\x22\x02\x41\x80\x02\x49\x04\x7f" +
  b"\x20\x02\x41\x04\x76\x21\x03\x41\x00\x05\x41\x1f\x41\xfc\xff\xff\xff\x03\x20" +
  b"\x02\x20\x02\x41\xfc\xff\xff\xff\x03\x4f\x1b\x22\x03\x67\x6b\x21\x02\x20\x03" +
  b"\x20\x02\x41\x04\x6b\x76\x41\x10\x73\x21\x03\x20\x02\x41\x07\x6b\x0b\x21\x05" +
  b"\x20\x01\x28\x00\x08\x21\x02\x20\x01\x28\x00\x04\x22\x04\x04\x40\x20\x04\x20" +
  b"\x02\x36\x00\x08\x0b\x20\x02\x04\x40\x20\x02\x20\x04\x36\x00\x04\x0b\x20\x01" +
  b"\x20\x00\x20\x05\x41\x04\x74\x20\x03\x6a\x41\x02\x74\x6a\x22\x04\x28\x00\x60" +
  b"\x46\x04\x40\x20\x04\x20\x02\x36\x00\x60\x20\x02\x45\x04\x40\x20\x00\x20\x05" +
  b"\x41\x02\x74\x6a\x22\x01\x20\x01\x28\x00\x04\x41\x7e\x20\x03\x77\x71\x22\x01" +
  b"\x36\x00\x04\x20\x01\x45\x04\x40\x20\x00\x20\x00\x28\x00\x00\x41\x7e\x20\x05" +
  b"\x77\x71\x36\x00\x00\x0b\x0b\x0b\x0b"
}

///|
/// Decode one embedded body and check where it lands.
fn check_body(body : Bytes, instructions : Int, label : String) -> Unit raise {
  match decode_instructions(body, 0, body.length()) {
    Ok(decoded) => {
      if decoded.length() != instructions {
        fail(
          label +
          ": expected " +
          instructions.to_string() +
          " instructions, got " +
          decoded.length().to_string(),
        )
      }
      let last = decoded[decoded.length() - 1]
      if last.offset + last.size != body.length() {
        fail(
          label +
          ": decode ended at " +
          (last.offset + last.size).to_string() +
          " of " +
          body.length().to_string(),
        )
      }
      if last.opcode.name() != "end" {
        fail(label + ": expected a final end, got " + last.opcode.name())
      }
    }
    Err(error) => fail(label + ": " + describe_error(error))
  }
}

///|
test "real moonbit bodies decode to their exact length" {
  check_body(gc_body(), 158, "wasm-gc body")
  check_body(struct_body(), 14, "struct body")
  check_body(linear_body(), 104, "linear-memory body")
}

///|
test "scan_calls reports direct and indirect sites with their offsets" {
  // call 3; call_indirect (type 1, table 0)
  let body = b"\x00\x10\x03\x11\x01\x00\x0b"
  match scan_calls(body, 0, body.length()) {
    Ok(sites) => {
      inspect(
        sites.length(),
        content=(
          #|2
        ),
      )
      match sites[0].kind {
        Direct(target) =>
          inspect(
            target,
            content=(
              #|3
            ),
          )
        Indirect(_) => fail("expected a direct call")
      }
      inspect(
        sites[0].offset,
        content=(
          #|1
        ),
      )
      match sites[1].kind {
        Indirect(table) =>
          inspect(
            table,
            content=(
              #|0
            ),
          )
        Direct(_) => fail("expected an indirect call")
      }
      assert_eq(sites[1].type_index, Some(1))
    }
    Err(error) => fail(describe_error(error))
  }
}
