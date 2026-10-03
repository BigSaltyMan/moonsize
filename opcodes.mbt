///|
/// The instruction set, table-driven.
///
/// Every opcode the decoder accepts is listed exactly once with the shape of the
/// immediates that follow it, so adding an instruction is a one-line edit and the
/// decoder itself never grows. Three encodings are folded in here: single-byte
/// opcodes, the `0xFC` saturating/bulk-memory prefix and the `0xFB`
/// garbage-collection prefix.
///
/// The `0xFB` layout is the one MoonBit's `wasm-gc` backend emits: a
/// `struct.get` carries a type index *and* a field index, `array.new_fixed` a
/// length, and `array.copy` two type indices. Misreading any of those widths
/// desynchronises the whole body, which is why every width here is checked
/// against real output in `opcodes_wbtest.mbt`.

///|
/// Every instruction the decoder recognises, one variant per mnemonic.
///
/// The set covers the MVP, the sign-extension, saturating-truncation, bulk-memory
/// and reference-type extensions MoonBit's linear-memory backend emits, and the
/// garbage-collection instructions its `wasm-gc` backend emits.
pub enum Opcode {
  Unreachable
  Nop
  Block
  Loop
  If
  Else
  Try
  Catch
  Throw
  Rethrow
  ThrowRef
  End
  Br
  BrIf
  BrTable
  Return
  Call
  CallIndirect
  ReturnCall
  ReturnCallIndirect
  CallRef
  ReturnCallRef
  Drop
  Select
  Delegate
  CatchAll
  SelectT
  LocalGet
  LocalSet
  LocalTee
  GlobalGet
  GlobalSet
  TableGet
  TableSet
  I32Load
  I64Load
  F32Load
  F64Load
  I32Load8S
  I32Load8U
  I32Load16S
  I32Load16U
  I64Load8S
  I64Load8U
  I64Load16S
  I64Load16U
  I64Load32S
  I64Load32U
  I32Store
  I64Store
  F32Store
  F64Store
  I32Store8
  I32Store16
  I64Store8
  I64Store16
  I64Store32
  MemorySize
  MemoryGrow
  I32Const
  I64Const
  F32Const
  F64Const
  I32Eqz
  I32Eq
  I32Ne
  I32LtS
  I32LtU
  I32GtS
  I32GtU
  I32LeS
  I32LeU
  I32GeS
  I32GeU
  I64Eqz
  I64Eq
  I64Ne
  I64LtS
  I64LtU
  I64GtS
  I64GtU
  I64LeS
  I64LeU
  I64GeS
  I64GeU
  F32Eq
  F32Ne
  F32Lt
  F32Gt
  F32Le
  F32Ge
  F64Eq
  F64Ne
  F64Lt
  F64Gt
  F64Le
  F64Ge
  I32Clz
  I32Ctz
  I32Popcnt
  I32Add
  I32Sub
  I32Mul
  I32DivS
  I32DivU
  I32RemS
  I32RemU
  I32And
  I32Or
  I32Xor
  I32Shl
  I32ShrS
  I32ShrU
  I32Rotl
  I32Rotr
  I64Clz
  I64Ctz
  I64Popcnt
  I64Add
  I64Sub
  I64Mul
  I64DivS
  I64DivU
  I64RemS
  I64RemU
  I64And
  I64Or
  I64Xor
  I64Shl
  I64ShrS
  I64ShrU
  I64Rotl
  I64Rotr
  F32Abs
  F32Neg
  F32Ceil
  F32Floor
  F32Trunc
  F32Nearest
  F32Sqrt
  F32Add
  F32Sub
  F32Mul
  F32Div
  F32Min
  F32Max
  F32Copysign
  F64Abs
  F64Neg
  F64Ceil
  F64Floor
  F64Trunc
  F64Nearest
  F64Sqrt
  F64Add
  F64Sub
  F64Mul
  F64Div
  F64Min
  F64Max
  F64Copysign
  I32WrapI64
  I32TruncF32S
  I32TruncF32U
  I32TruncF64S
  I32TruncF64U
  I64ExtendI32S
  I64ExtendI32U
  I64TruncF32S
  I64TruncF32U
  I64TruncF64S
  I64TruncF64U
  F32ConvertI32S
  F32ConvertI32U
  F32ConvertI64S
  F32ConvertI64U
  F32DemoteF64
  F64ConvertI32S
  F64ConvertI32U
  F64ConvertI64S
  F64ConvertI64U
  F64PromoteF32
  I32ReinterpretF32
  I64ReinterpretF64
  F32ReinterpretI32
  F64ReinterpretI64
  I32Extend8S
  I32Extend16S
  I64Extend8S
  I64Extend16S
  I64Extend32S
  RefNull
  RefIsNull
  RefFunc
  RefEq
  RefAsNonNull
  BrOnNull
  BrOnNonNull
  I32TruncSatF32S
  I32TruncSatF32U
  I32TruncSatF64S
  I32TruncSatF64U
  I64TruncSatF32S
  I64TruncSatF32U
  I64TruncSatF64S
  I64TruncSatF64U
  MemoryInit
  DataDrop
  MemoryCopy
  MemoryFill
  TableInit
  ElemDrop
  TableCopy
  TableGrow
  TableSize
  TableFill
  StructNew
  StructNewDefault
  StructGet
  StructGetS
  StructGetU
  StructSet
  ArrayNew
  ArrayNewDefault
  ArrayNewFixed
  ArrayNewData
  ArrayNewElem
  ArrayGet
  ArrayGetS
  ArrayGetU
  ArraySet
  ArrayLen
  ArrayFill
  ArrayCopy
  ArrayInitData
  ArrayInitElem
  RefTest
  RefTestNull
  RefCast
  RefCastNull
  BrOnCast
  BrOnCastFail
  AnyConvertExtern
  ExternConvertAny
  RefI31
  I31GetS
  I31GetU
}

///|
/// The immediate operands each opcode carries.
pub fn Opcode::operands(self : Opcode) -> Operands {
  match self {
    Unreachable => None_
    Nop => None_
    Block => BlockType
    Loop => BlockType
    If => BlockType
    Else => None_
    Try => BlockType
    Catch => TagIndex
    Throw => TagIndex
    Rethrow => Label
    ThrowRef => None_
    End => None_
    Br => Label
    BrIf => Label
    BrTable => LabelTable
    Return => None_
    Call => FunctionIndex
    CallIndirect => CallIndirect
    ReturnCall => FunctionIndex
    ReturnCallIndirect => CallIndirect
    CallRef => TypeIndex
    ReturnCallRef => TypeIndex
    Drop => None_
    Select => None_
    Delegate => Label
    CatchAll => None_
    SelectT => TypeVector
    LocalGet => LocalIndex
    LocalSet => LocalIndex
    LocalTee => LocalIndex
    GlobalGet => GlobalIndex
    GlobalSet => GlobalIndex
    TableGet => TableIndex
    TableSet => TableIndex
    I32Load => MemoryArg
    I64Load => MemoryArg
    F32Load => MemoryArg
    F64Load => MemoryArg
    I32Load8S => MemoryArg
    I32Load8U => MemoryArg
    I32Load16S => MemoryArg
    I32Load16U => MemoryArg
    I64Load8S => MemoryArg
    I64Load8U => MemoryArg
    I64Load16S => MemoryArg
    I64Load16U => MemoryArg
    I64Load32S => MemoryArg
    I64Load32U => MemoryArg
    I32Store => MemoryArg
    I64Store => MemoryArg
    F32Store => MemoryArg
    F64Store => MemoryArg
    I32Store8 => MemoryArg
    I32Store16 => MemoryArg
    I64Store8 => MemoryArg
    I64Store16 => MemoryArg
    I64Store32 => MemoryArg
    MemorySize => MemoryIndex
    MemoryGrow => MemoryIndex
    I32Const => I32Const
    I64Const => I64Const
    F32Const => F32Const
    F64Const => F64Const
    I32Eqz => None_
    I32Eq => None_
    I32Ne => None_
    I32LtS => None_
    I32LtU => None_
    I32GtS => None_
    I32GtU => None_
    I32LeS => None_
    I32LeU => None_
    I32GeS => None_
    I32GeU => None_
    I64Eqz => None_
    I64Eq => None_
    I64Ne => None_
    I64LtS => None_
    I64LtU => None_
    I64GtS => None_
    I64GtU => None_
    I64LeS => None_
    I64LeU => None_
    I64GeS => None_
    I64GeU => None_
    F32Eq => None_
    F32Ne => None_
    F32Lt => None_
    F32Gt => None_
    F32Le => None_
    F32Ge => None_
    F64Eq => None_
    F64Ne => None_
    F64Lt => None_
    F64Gt => None_
    F64Le => None_
    F64Ge => None_
    I32Clz => None_
    I32Ctz => None_
    I32Popcnt => None_
    I32Add => None_
    I32Sub => None_
    I32Mul => None_
    I32DivS => None_
    I32DivU => None_
    I32RemS => None_
    I32RemU => None_
    I32And => None_
    I32Or => None_
    I32Xor => None_
    I32Shl => None_
    I32ShrS => None_
    I32ShrU => None_
    I32Rotl => None_
    I32Rotr => None_
    I64Clz => None_
    I64Ctz => None_
    I64Popcnt => None_
    I64Add => None_
    I64Sub => None_
    I64Mul => None_
    I64DivS => None_
    I64DivU => None_
    I64RemS => None_
    I64RemU => None_
    I64And => None_
    I64Or => None_
    I64Xor => None_
    I64Shl => None_
    I64ShrS => None_
    I64ShrU => None_
    I64Rotl => None_
    I64Rotr => None_
    F32Abs => None_
    F32Neg => None_
    F32Ceil => None_
    F32Floor => None_
    F32Trunc => None_
    F32Nearest => None_
    F32Sqrt => None_
    F32Add => None_
    F32Sub => None_
    F32Mul => None_
    F32Div => None_
    F32Min => None_
    F32Max => None_
    F32Copysign => None_
    F64Abs => None_
    F64Neg => None_
    F64Ceil => None_
    F64Floor => None_
    F64Trunc => None_
    F64Nearest => None_
    F64Sqrt => None_
    F64Add => None_
    F64Sub => None_
    F64Mul => None_
    F64Div => None_
    F64Min => None_
    F64Max => None_
    F64Copysign => None_
    I32WrapI64 => None_
    I32TruncF32S => None_
    I32TruncF32U => None_
    I32TruncF64S => None_
    I32TruncF64U => None_
    I64ExtendI32S => None_
    I64ExtendI32U => None_
    I64TruncF32S => None_
    I64TruncF32U => None_
    I64TruncF64S => None_
    I64TruncF64U => None_
    F32ConvertI32S => None_
    F32ConvertI32U => None_
    F32ConvertI64S => None_
    F32ConvertI64U => None_
    F32DemoteF64 => None_
    F64ConvertI32S => None_
    F64ConvertI32U => None_
    F64ConvertI64S => None_
    F64ConvertI64U => None_
    F64PromoteF32 => None_
    I32ReinterpretF32 => None_
    I64ReinterpretF64 => None_
    F32ReinterpretI32 => None_
    F64ReinterpretI64 => None_
    I32Extend8S => None_
    I32Extend16S => None_
    I64Extend8S => None_
    I64Extend16S => None_
    I64Extend32S => None_
    RefNull => HeapType
    RefIsNull => None_
    RefFunc => FunctionIndex
    RefEq => None_
    RefAsNonNull => None_
    BrOnNull => Label
    BrOnNonNull => Label
    I32TruncSatF32S => None_
    I32TruncSatF32U => None_
    I32TruncSatF64S => None_
    I32TruncSatF64U => None_
    I64TruncSatF32S => None_
    I64TruncSatF32U => None_
    I64TruncSatF64S => None_
    I64TruncSatF64U => None_
    MemoryInit => DataMemoryPair
    DataDrop => DataIndex
    MemoryCopy => MemoryPair
    MemoryFill => MemoryIndex
    TableInit => ElemTablePair
    ElemDrop => ElemIndex
    TableCopy => TablePair
    TableGrow => TableIndex
    TableSize => TableIndex
    TableFill => TableIndex
    StructNew => TypeIndex
    StructNewDefault => TypeIndex
    StructGet => TypeFieldPair
    StructGetS => TypeFieldPair
    StructGetU => TypeFieldPair
    StructSet => TypeFieldPair
    ArrayNew => TypeIndex
    ArrayNewDefault => TypeIndex
    ArrayNewFixed => TypeCountPair
    ArrayNewData => TypeDataPair
    ArrayNewElem => TypeElemPair
    ArrayGet => TypeIndex
    ArrayGetS => TypeIndex
    ArrayGetU => TypeIndex
    ArraySet => TypeIndex
    ArrayLen => None_
    ArrayFill => TypeIndex
    ArrayCopy => TypePair
    ArrayInitData => TypeDataPair
    ArrayInitElem => TypeElemPair
    RefTest => RefType
    RefTestNull => RefType
    RefCast => RefType
    RefCastNull => RefType
    BrOnCast => CastPair
    BrOnCastFail => CastPair
    AnyConvertExtern => None_
    ExternConvertAny => None_
    RefI31 => None_
    I31GetS => None_
    I31GetU => None_
  }
}

///|
/// The spec mnemonic for an opcode, spelled as the text format writes it.
pub fn Opcode::name(self : Opcode) -> String {
  match self {
    Unreachable => "unreachable"
    Nop => "nop"
    Block => "block"
    Loop => "loop"
    If => "if"
    Else => "else"
    Try => "try"
    Catch => "catch"
    Throw => "throw"
    Rethrow => "rethrow"
    ThrowRef => "throw_ref"
    End => "end"
    Br => "br"
    BrIf => "br_if"
    BrTable => "br_table"
    Return => "return"
    Call => "call"
    CallIndirect => "call_indirect"
    ReturnCall => "return_call"
    ReturnCallIndirect => "return_call_indirect"
    CallRef => "call_ref"
    ReturnCallRef => "return_call_ref"
    Drop => "drop"
    Select => "select"
    Delegate => "delegate"
    CatchAll => "catch_all"
    SelectT => "select_t"
    LocalGet => "local.get"
    LocalSet => "local.set"
    LocalTee => "local.tee"
    GlobalGet => "global.get"
    GlobalSet => "global.set"
    TableGet => "table.get"
    TableSet => "table.set"
    I32Load => "i32.load"
    I64Load => "i64.load"
    F32Load => "f32.load"
    F64Load => "f64.load"
    I32Load8S => "i32.load8_s"
    I32Load8U => "i32.load8_u"
    I32Load16S => "i32.load16_s"
    I32Load16U => "i32.load16_u"
    I64Load8S => "i64.load8_s"
    I64Load8U => "i64.load8_u"
    I64Load16S => "i64.load16_s"
    I64Load16U => "i64.load16_u"
    I64Load32S => "i64.load32_s"
    I64Load32U => "i64.load32_u"
    I32Store => "i32.store"
    I64Store => "i64.store"
    F32Store => "f32.store"
    F64Store => "f64.store"
    I32Store8 => "i32.store8"
    I32Store16 => "i32.store16"
    I64Store8 => "i64.store8"
    I64Store16 => "i64.store16"
    I64Store32 => "i64.store32"
    MemorySize => "memory.size"
    MemoryGrow => "memory.grow"
    I32Const => "i32.const"
    I64Const => "i64.const"
    F32Const => "f32.const"
    F64Const => "f64.const"
    I32Eqz => "i32.eqz"
    I32Eq => "i32.eq"
    I32Ne => "i32.ne"
    I32LtS => "i32.lt_s"
    I32LtU => "i32.lt_u"
    I32GtS => "i32.gt_s"
    I32GtU => "i32.gt_u"
    I32LeS => "i32.le_s"
    I32LeU => "i32.le_u"
    I32GeS => "i32.ge_s"
    I32GeU => "i32.ge_u"
    I64Eqz => "i64.eqz"
    I64Eq => "i64.eq"
    I64Ne => "i64.ne"
    I64LtS => "i64.lt_s"
    I64LtU => "i64.lt_u"
    I64GtS => "i64.gt_s"
    I64GtU => "i64.gt_u"
    I64LeS => "i64.le_s"
    I64LeU => "i64.le_u"
    I64GeS => "i64.ge_s"
    I64GeU => "i64.ge_u"
    F32Eq => "f32.eq"
    F32Ne => "f32.ne"
    F32Lt => "f32.lt"
    F32Gt => "f32.gt"
    F32Le => "f32.le"
    F32Ge => "f32.ge"
    F64Eq => "f64.eq"
    F64Ne => "f64.ne"
    F64Lt => "f64.lt"
    F64Gt => "f64.gt"
    F64Le => "f64.le"
    F64Ge => "f64.ge"
    I32Clz => "i32.clz"
    I32Ctz => "i32.ctz"
    I32Popcnt => "i32.popcnt"
    I32Add => "i32.add"
    I32Sub => "i32.sub"
    I32Mul => "i32.mul"
    I32DivS => "i32.div_s"
    I32DivU => "i32.div_u"
    I32RemS => "i32.rem_s"
    I32RemU => "i32.rem_u"
    I32And => "i32.and"
    I32Or => "i32.or"
    I32Xor => "i32.xor"
    I32Shl => "i32.shl"
    I32ShrS => "i32.shr_s"
    I32ShrU => "i32.shr_u"
    I32Rotl => "i32.rotl"
    I32Rotr => "i32.rotr"
    I64Clz => "i64.clz"
    I64Ctz => "i64.ctz"
    I64Popcnt => "i64.popcnt"
    I64Add => "i64.add"
    I64Sub => "i64.sub"
    I64Mul => "i64.mul"
    I64DivS => "i64.div_s"
    I64DivU => "i64.div_u"
    I64RemS => "i64.rem_s"
    I64RemU => "i64.rem_u"
    I64And => "i64.and"
    I64Or => "i64.or"
    I64Xor => "i64.xor"
    I64Shl => "i64.shl"
    I64ShrS => "i64.shr_s"
    I64ShrU => "i64.shr_u"
    I64Rotl => "i64.rotl"
    I64Rotr => "i64.rotr"
    F32Abs => "f32.abs"
    F32Neg => "f32.neg"
    F32Ceil => "f32.ceil"
    F32Floor => "f32.floor"
    F32Trunc => "f32.trunc"
    F32Nearest => "f32.nearest"
    F32Sqrt => "f32.sqrt"
    F32Add => "f32.add"
    F32Sub => "f32.sub"
    F32Mul => "f32.mul"
    F32Div => "f32.div"
    F32Min => "f32.min"
    F32Max => "f32.max"
    F32Copysign => "f32.copysign"
    F64Abs => "f64.abs"
    F64Neg => "f64.neg"
    F64Ceil => "f64.ceil"
    F64Floor => "f64.floor"
    F64Trunc => "f64.trunc"
    F64Nearest => "f64.nearest"
    F64Sqrt => "f64.sqrt"
    F64Add => "f64.add"
    F64Sub => "f64.sub"
    F64Mul => "f64.mul"
    F64Div => "f64.div"
    F64Min => "f64.min"
    F64Max => "f64.max"
    F64Copysign => "f64.copysign"
    I32WrapI64 => "i32.wrap_i64"
    I32TruncF32S => "i32.trunc_f32_s"
    I32TruncF32U => "i32.trunc_f32_u"
    I32TruncF64S => "i32.trunc_f64_s"
    I32TruncF64U => "i32.trunc_f64_u"
    I64ExtendI32S => "i64.extend_i32_s"
    I64ExtendI32U => "i64.extend_i32_u"
    I64TruncF32S => "i64.trunc_f32_s"
    I64TruncF32U => "i64.trunc_f32_u"
    I64TruncF64S => "i64.trunc_f64_s"
    I64TruncF64U => "i64.trunc_f64_u"
    F32ConvertI32S => "f32.convert_i32_s"
    F32ConvertI32U => "f32.convert_i32_u"
    F32ConvertI64S => "f32.convert_i64_s"
    F32ConvertI64U => "f32.convert_i64_u"
    F32DemoteF64 => "f32.demote_f64"
    F64ConvertI32S => "f64.convert_i32_s"
    F64ConvertI32U => "f64.convert_i32_u"
    F64ConvertI64S => "f64.convert_i64_s"
    F64ConvertI64U => "f64.convert_i64_u"
    F64PromoteF32 => "f64.promote_f32"
    I32ReinterpretF32 => "i32.reinterpret_f32"
    I64ReinterpretF64 => "i64.reinterpret_f64"
    F32ReinterpretI32 => "f32.reinterpret_i32"
    F64ReinterpretI64 => "f64.reinterpret_i64"
    I32Extend8S => "i32.extend8_s"
    I32Extend16S => "i32.extend16_s"
    I64Extend8S => "i64.extend8_s"
    I64Extend16S => "i64.extend16_s"
    I64Extend32S => "i64.extend32_s"
    RefNull => "ref.null"
    RefIsNull => "ref.is_null"
    RefFunc => "ref.func"
    RefEq => "ref.eq"
    RefAsNonNull => "ref.as_non_null"
    BrOnNull => "br_on_null"
    BrOnNonNull => "br_on_non_null"
    I32TruncSatF32S => "i32.trunc_sat_f32_s"
    I32TruncSatF32U => "i32.trunc_sat_f32_u"
    I32TruncSatF64S => "i32.trunc_sat_f64_s"
    I32TruncSatF64U => "i32.trunc_sat_f64_u"
    I64TruncSatF32S => "i64.trunc_sat_f32_s"
    I64TruncSatF32U => "i64.trunc_sat_f32_u"
    I64TruncSatF64S => "i64.trunc_sat_f64_s"
    I64TruncSatF64U => "i64.trunc_sat_f64_u"
    MemoryInit => "memory.init"
    DataDrop => "data.drop"
    MemoryCopy => "memory.copy"
    MemoryFill => "memory.fill"
    TableInit => "table.init"
    ElemDrop => "elem.drop"
    TableCopy => "table.copy"
    TableGrow => "table.grow"
    TableSize => "table.size"
    TableFill => "table.fill"
    StructNew => "struct.new"
    StructNewDefault => "struct.new_default"
    StructGet => "struct.get"
    StructGetS => "struct.get_s"
    StructGetU => "struct.get_u"
    StructSet => "struct.set"
    ArrayNew => "array.new"
    ArrayNewDefault => "array.new_default"
    ArrayNewFixed => "array.new_fixed"
    ArrayNewData => "array.new_data"
    ArrayNewElem => "array.new_elem"
    ArrayGet => "array.get"
    ArrayGetS => "array.get_s"
    ArrayGetU => "array.get_u"
    ArraySet => "array.set"
    ArrayLen => "array.len"
    ArrayFill => "array.fill"
    ArrayCopy => "array.copy"
    ArrayInitData => "array.init_data"
    ArrayInitElem => "array.init_elem"
    RefTest => "ref.test"
    RefTestNull => "ref.test_null"
    RefCast => "ref.cast"
    RefCastNull => "ref.cast_null"
    BrOnCast => "br_on_cast"
    BrOnCastFail => "br_on_cast_fail"
    AnyConvertExtern => "any.convert_extern"
    ExternConvertAny => "extern.convert_any"
    RefI31 => "ref.i31"
    I31GetS => "i31.get_s"
    I31GetU => "i31.get_u"
  }
}

///|
/// The opcode a single leading byte stands for, or `None` for a reserved byte.
fn simple_opcode(byte : Int) -> Opcode? {
  match byte {
    0x00 => Some(Unreachable)
    0x01 => Some(Nop)
    0x02 => Some(Block)
    0x03 => Some(Loop)
    0x04 => Some(If)
    0x05 => Some(Else)
    0x06 => Some(Try)
    0x07 => Some(Catch)
    0x08 => Some(Throw)
    0x09 => Some(Rethrow)
    0x0A => Some(ThrowRef)
    0x0B => Some(End)
    0x0C => Some(Br)
    0x0D => Some(BrIf)
    0x0E => Some(BrTable)
    0x0F => Some(Return)
    0x10 => Some(Call)
    0x11 => Some(CallIndirect)
    0x12 => Some(ReturnCall)
    0x13 => Some(ReturnCallIndirect)
    0x14 => Some(CallRef)
    0x15 => Some(ReturnCallRef)
    0x1A => Some(Drop)
    0x1B => Some(Select)
    0x18 => Some(Delegate)
    0x19 => Some(CatchAll)
    0x1C => Some(SelectT)
    0x20 => Some(LocalGet)
    0x21 => Some(LocalSet)
    0x22 => Some(LocalTee)
    0x23 => Some(GlobalGet)
    0x24 => Some(GlobalSet)
    0x25 => Some(TableGet)
    0x26 => Some(TableSet)
    0x28 => Some(I32Load)
    0x29 => Some(I64Load)
    0x2A => Some(F32Load)
    0x2B => Some(F64Load)
    0x2C => Some(I32Load8S)
    0x2D => Some(I32Load8U)
    0x2E => Some(I32Load16S)
    0x2F => Some(I32Load16U)
    0x30 => Some(I64Load8S)
    0x31 => Some(I64Load8U)
    0x32 => Some(I64Load16S)
    0x33 => Some(I64Load16U)
    0x34 => Some(I64Load32S)
    0x35 => Some(I64Load32U)
    0x36 => Some(I32Store)
    0x37 => Some(I64Store)
    0x38 => Some(F32Store)
    0x39 => Some(F64Store)
    0x3A => Some(I32Store8)
    0x3B => Some(I32Store16)
    0x3C => Some(I64Store8)
    0x3D => Some(I64Store16)
    0x3E => Some(I64Store32)
    0x3F => Some(MemorySize)
    0x40 => Some(MemoryGrow)
    0x41 => Some(I32Const)
    0x42 => Some(I64Const)
    0x43 => Some(F32Const)
    0x44 => Some(F64Const)
    0x45 => Some(I32Eqz)
    0x46 => Some(I32Eq)
    0x47 => Some(I32Ne)
    0x48 => Some(I32LtS)
    0x49 => Some(I32LtU)
    0x4A => Some(I32GtS)
    0x4B => Some(I32GtU)
    0x4C => Some(I32LeS)
    0x4D => Some(I32LeU)
    0x4E => Some(I32GeS)
    0x4F => Some(I32GeU)
    0x50 => Some(I64Eqz)
    0x51 => Some(I64Eq)
    0x52 => Some(I64Ne)
    0x53 => Some(I64LtS)
    0x54 => Some(I64LtU)
    0x55 => Some(I64GtS)
    0x56 => Some(I64GtU)
    0x57 => Some(I64LeS)
    0x58 => Some(I64LeU)
    0x59 => Some(I64GeS)
    0x5A => Some(I64GeU)
    0x5B => Some(F32Eq)
    0x5C => Some(F32Ne)
    0x5D => Some(F32Lt)
    0x5E => Some(F32Gt)
    0x5F => Some(F32Le)
    0x60 => Some(F32Ge)
    0x61 => Some(F64Eq)
    0x62 => Some(F64Ne)
    0x63 => Some(F64Lt)
    0x64 => Some(F64Gt)
    0x65 => Some(F64Le)
    0x66 => Some(F64Ge)
    0x67 => Some(I32Clz)
    0x68 => Some(I32Ctz)
    0x69 => Some(I32Popcnt)
    0x6A => Some(I32Add)
    0x6B => Some(I32Sub)
    0x6C => Some(I32Mul)
    0x6D => Some(I32DivS)
    0x6E => Some(I32DivU)
    0x6F => Some(I32RemS)
    0x70 => Some(I32RemU)
    0x71 => Some(I32And)
    0x72 => Some(I32Or)
    0x73 => Some(I32Xor)
    0x74 => Some(I32Shl)
    0x75 => Some(I32ShrS)
    0x76 => Some(I32ShrU)
    0x77 => Some(I32Rotl)
    0x78 => Some(I32Rotr)
    0x79 => Some(I64Clz)
    0x7A => Some(I64Ctz)
    0x7B => Some(I64Popcnt)
    0x7C => Some(I64Add)
    0x7D => Some(I64Sub)
    0x7E => Some(I64Mul)
    0x7F => Some(I64DivS)
    0x80 => Some(I64DivU)
    0x81 => Some(I64RemS)
    0x82 => Some(I64RemU)
    0x83 => Some(I64And)
    0x84 => Some(I64Or)
    0x85 => Some(I64Xor)
    0x86 => Some(I64Shl)
    0x87 => Some(I64ShrS)
    0x88 => Some(I64ShrU)
    0x89 => Some(I64Rotl)
    0x8A => Some(I64Rotr)
    0x8B => Some(F32Abs)
    0x8C => Some(F32Neg)
    0x8D => Some(F32Ceil)
    0x8E => Some(F32Floor)
    0x8F => Some(F32Trunc)
    0x90 => Some(F32Nearest)
    0x91 => Some(F32Sqrt)
    0x92 => Some(F32Add)
    0x93 => Some(F32Sub)
    0x94 => Some(F32Mul)
    0x95 => Some(F32Div)
    0x96 => Some(F32Min)
    0x97 => Some(F32Max)
    0x98 => Some(F32Copysign)
    0x99 => Some(F64Abs)
    0x9A => Some(F64Neg)
    0x9B => Some(F64Ceil)
    0x9C => Some(F64Floor)
    0x9D => Some(F64Trunc)
    0x9E => Some(F64Nearest)
    0x9F => Some(F64Sqrt)
    0xA0 => Some(F64Add)
    0xA1 => Some(F64Sub)
    0xA2 => Some(F64Mul)
    0xA3 => Some(F64Div)
    0xA4 => Some(F64Min)
    0xA5 => Some(F64Max)
    0xA6 => Some(F64Copysign)
    0xA7 => Some(I32WrapI64)
    0xA8 => Some(I32TruncF32S)
    0xA9 => Some(I32TruncF32U)
    0xAA => Some(I32TruncF64S)
    0xAB => Some(I32TruncF64U)
    0xAC => Some(I64ExtendI32S)
    0xAD => Some(I64ExtendI32U)
    0xAE => Some(I64TruncF32S)
    0xAF => Some(I64TruncF32U)
    0xB0 => Some(I64TruncF64S)
    0xB1 => Some(I64TruncF64U)
    0xB2 => Some(F32ConvertI32S)
    0xB3 => Some(F32ConvertI32U)
    0xB4 => Some(F32ConvertI64S)
    0xB5 => Some(F32ConvertI64U)
    0xB6 => Some(F32DemoteF64)
    0xB7 => Some(F64ConvertI32S)
    0xB8 => Some(F64ConvertI32U)
    0xB9 => Some(F64ConvertI64S)
    0xBA => Some(F64ConvertI64U)
    0xBB => Some(F64PromoteF32)
    0xBC => Some(I32ReinterpretF32)
    0xBD => Some(I64ReinterpretF64)
    0xBE => Some(F32ReinterpretI32)
    0xBF => Some(F64ReinterpretI64)
    0xC0 => Some(I32Extend8S)
    0xC1 => Some(I32Extend16S)
    0xC2 => Some(I64Extend8S)
    0xC3 => Some(I64Extend16S)
    0xC4 => Some(I64Extend32S)
    0xD0 => Some(RefNull)
    0xD1 => Some(RefIsNull)
    0xD2 => Some(RefFunc)
    0xD3 => Some(RefEq)
    0xD4 => Some(RefAsNonNull)
    0xD5 => Some(BrOnNull)
    0xD6 => Some(BrOnNonNull)
    _ => None
  }
}

///|
/// The `0xFC`-prefixed opcode a sub-opcode stands for, or `None` when unassigned.
fn misc_opcode(sub : Int) -> Opcode? {
  match sub {
    0x00 => Some(I32TruncSatF32S)
    0x01 => Some(I32TruncSatF32U)
    0x02 => Some(I32TruncSatF64S)
    0x03 => Some(I32TruncSatF64U)
    0x04 => Some(I64TruncSatF32S)
    0x05 => Some(I64TruncSatF32U)
    0x06 => Some(I64TruncSatF64S)
    0x07 => Some(I64TruncSatF64U)
    0x08 => Some(MemoryInit)
    0x09 => Some(DataDrop)
    0x0A => Some(MemoryCopy)
    0x0B => Some(MemoryFill)
    0x0C => Some(TableInit)
    0x0D => Some(ElemDrop)
    0x0E => Some(TableCopy)
    0x0F => Some(TableGrow)
    0x10 => Some(TableSize)
    0x11 => Some(TableFill)
    _ => None
  }
}

///|
/// The `0xFB`-prefixed opcode a sub-opcode stands for, or `None` when unassigned.
fn gc_opcode(sub : Int) -> Opcode? {
  match sub {
    0x00 => Some(StructNew)
    0x01 => Some(StructNewDefault)
    0x02 => Some(StructGet)
    0x03 => Some(StructGetS)
    0x04 => Some(StructGetU)
    0x05 => Some(StructSet)
    0x06 => Some(ArrayNew)
    0x07 => Some(ArrayNewDefault)
    0x08 => Some(ArrayNewFixed)
    0x09 => Some(ArrayNewData)
    0x0A => Some(ArrayNewElem)
    0x0B => Some(ArrayGet)
    0x0C => Some(ArrayGetS)
    0x0D => Some(ArrayGetU)
    0x0E => Some(ArraySet)
    0x0F => Some(ArrayLen)
    0x10 => Some(ArrayFill)
    0x11 => Some(ArrayCopy)
    0x12 => Some(ArrayInitData)
    0x13 => Some(ArrayInitElem)
    0x14 => Some(RefTest)
    0x15 => Some(RefTestNull)
    0x16 => Some(RefCast)
    0x17 => Some(RefCastNull)
    0x18 => Some(BrOnCast)
    0x19 => Some(BrOnCastFail)
    0x1A => Some(AnyConvertExtern)
    0x1B => Some(ExternConvertAny)
    0x1C => Some(RefI31)
    0x1D => Some(I31GetS)
    0x1E => Some(I31GetU)
    _ => None
  }
}

///|
/// How the bytes after an opcode are laid out.
///
/// The shapes named `<a><b>Pair` read `a` then `b`, in encoding order. Naming
/// them here rather than inlining the reads keeps every immediate width in one
/// table that can be reviewed — and tested — against the specification.
pub enum Operands {
  /// The instruction is exactly one byte.
  None_
  /// A block type: one byte for a value type or `0x40`, otherwise an s33 index.
  BlockType
  /// A single label index.
  Label
  /// `vec(labelidx)` and then the default label index.
  LabelTable
  /// A function index: `call`, `ref.func`.
  FunctionIndex
  /// `call_indirect`: a type index and a table index.
  CallIndirect
  /// A local index.
  LocalIndex
  /// A global index.
  GlobalIndex
  /// A table index.
  TableIndex
  /// An exception tag index: `try`, `catch`, `throw`.
  TagIndex
  /// `memory.size`, `memory.grow` and the bulk-memory fills: a single byte.
  MemoryIndex
  /// An alignment hint and an offset, plus a memory index when bit 6 is set.
  MemoryArg
  /// A 32-bit signed constant.
  I32Const
  /// A 64-bit signed constant, kept as its bit pattern.
  I64Const
  /// Four raw bytes.
  F32Const
  /// Eight raw bytes.
  F64Const
  /// A heap type: one byte, or an s33 type index.
  HeapType
  /// A reference type: a shorthand byte, or `0x63`/`0x64` and a heap type.
  RefType
  /// A type index.
  TypeIndex
  /// `struct.get` and friends: a type index and a field index.
  TypeFieldPair
  /// `array.copy`: two type indices.
  TypePair
  /// `array.new_fixed`: a type index and an element count.
  TypeCountPair
  /// `array.new_data` and `array.init_data`: a type index and a data index.
  TypeDataPair
  /// `array.new_elem` and `array.init_elem`: a type index and an element index.
  TypeElemPair
  /// A data index.
  DataIndex
  /// An element index.
  ElemIndex
  /// `memory.init`: a data index and a memory index.
  DataMemoryPair
  /// `memory.copy`: two memory indices.
  MemoryPair
  /// `table.init`: an element index and a table index.
  ElemTablePair
  /// `table.copy`: two table indices.
  TablePair
  /// `br_on_cast`: a label index and two reference types.
  CastPair
  /// `select` with an explicit type: `vec(valtype)`.
  TypeVector
}

///|
/// A decoded instruction: what it is, where it starts and what it carries.
pub struct Instruction {
  opcode : Opcode
  /// Offset of the opcode byte from the start of the file.
  offset : Int
  /// Total encoded length, opcode byte and immediates included.
  size : Int
  /// Immediates in encoding order. Indices are exact; 64-bit and floating point
  /// constants are kept as their bit pattern; `br_table` contributes its element
  /// count first, so the target list can be split back off.
  operands : Array[Int]
}

///|
/// The byte that introduces a garbage-collection instruction.
const PREFIX_GC : Int = 0xFB

///|
/// The byte that introduces a saturating-truncation or bulk-memory instruction.
const PREFIX_MISC : Int = 0xFC

///|
/// The two reference-type constructors that are followed by a heap type.
const REF_NULL_TYPE : Int = 0x63

///|
const REF_TYPE : Int = 0x64

///|
/// Multi-memory marks a memory index inside a memory argument with this bit of
/// the alignment field. Natural alignments never reach it, so a module without
/// multi-memory decodes identically either way.
const MEMARG_HAS_MEMORY : Int = 0x40

///|
/// Read an unsigned index immediate and record it.
fn take_index(reader : Reader, out : Array[Int]) -> Result[Unit, WasmError] {
  match reader.read_u32_leb() {
    Ok(value) => {
      out.push(value)
      Ok(())
    }
    Err(error) => Err(error)
  }
}

///|
/// Read the bytes of a constant immediate and record them as one bit pattern.
fn take_bits(
  reader : Reader,
  out : Array[Int],
  count : Int,
) -> Result[Unit, WasmError] {
  match reader.read_bits(count) {
    Ok(value) => {
      out.push(value)
      Ok(())
    }
    Err(error) => Err(error)
  }
}

///|
/// Read a reference type into `out`.
fn take_reftype(reader : Reader, out : Array[Int]) -> Result[Unit, WasmError] {
  let first = match reader.read_byte() {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  out.push(first)
  if first == REF_NULL_TYPE || first == REF_TYPE {
    match reader.read_signed_leb(33) {
      Ok(value) => out.push(value)
      Err(error) => return Err(error)
    }
  }
  Ok(())
}

///|
/// Read the immediates an opcode carries, in encoding order.
fn read_operands(
  reader : Reader,
  shape : Operands,
  out : Array[Int],
) -> Result[Unit, WasmError] {
  match shape {
    None_ => ()
    BlockType => {
      // A block type is a value type, or an s33 type index. Value types are
      // usually one byte, but a GC reference type is two, so the first byte has
      // to be looked at before the s33 reading is committed to.
      let at = reader.position()
      let first = match reader.read_byte() {
        Ok(value) => value
        Err(error) => return Err(error)
      }
      if first == REF_NULL_TYPE || first == REF_TYPE {
        out.push(first)
        match reader.read_signed_leb(33) {
          Ok(value) => out.push(value)
          Err(error) => return Err(error)
        }
      } else {
        reader.seek(at)
        match reader.read_signed_leb(33) {
          Ok(value) => out.push(value)
          Err(error) => return Err(error)
        }
      }
    }
    Label => return take_index(reader, out)
    LabelTable => {
      let count = match reader.read_u32_leb() {
        Ok(value) => value
        Err(error) => return Err(error)
      }
      out.push(count)
      let mut i = 0
      while i <= count {
        match take_index(reader, out) {
          Ok(_) => ()
          Err(error) => return Err(error)
        }
        i = i + 1
      }
    }
    FunctionIndex
    | LocalIndex
    | GlobalIndex
    | TableIndex
    | TagIndex
    | TypeIndex
    | DataIndex
    | ElemIndex => return take_index(reader, out)
    CallIndirect => {
      match take_index(reader, out) {
        Ok(_) => ()
        Err(error) => return Err(error)
      }
      return take_index(reader, out)
    }
    MemoryIndex =>
      // The spec writes these as a literal zero byte, not a LEB128 field.
      match reader.read_byte() {
        Ok(value) => out.push(value)
        Err(error) => return Err(error)
      }
    MemoryArg => {
      let align = match reader.read_u32_leb() {
        Ok(value) => value
        Err(error) => return Err(error)
      }
      out.push(align)
      match take_index(reader, out) {
        Ok(_) => ()
        Err(error) => return Err(error)
      }
      if (align & MEMARG_HAS_MEMORY) != 0 {
        match reader.read_byte() {
          Ok(value) => out.push(value)
          Err(error) => return Err(error)
        }
      }
    }
    I32Const =>
      match reader.read_signed_leb(32) {
        Ok(value) => out.push(value)
        Err(error) => return Err(error)
      }
    I64Const =>
      match reader.read_signed_leb(64) {
        Ok(value) => out.push(value)
        Err(error) => return Err(error)
      }
    F32Const => return take_bits(reader, out, 4)
    F64Const => return take_bits(reader, out, 8)
    HeapType =>
      match reader.read_signed_leb(33) {
        Ok(value) => out.push(value)
        Err(error) => return Err(error)
      }
    RefType => return take_reftype(reader, out)
    TypeFieldPair
    | TypePair
    | TypeCountPair
    | TypeDataPair
    | TypeElemPair
    | DataMemoryPair
    | MemoryPair
    | ElemTablePair
    | TablePair => {
      // Two immediates of the shapes their names spell out.
      match take_index(reader, out) {
        Ok(_) => ()
        Err(error) => return Err(error)
      }
      return take_index(reader, out)
    }
    CastPair => {
      match take_index(reader, out) {
        Ok(_) => ()
        Err(error) => return Err(error)
      }
      let mut i = 0
      while i < 2 {
        match take_reftype(reader, out) {
          Ok(_) => ()
          Err(error) => return Err(error)
        }
        i = i + 1
      }
    }
    TypeVector => {
      // Each element is a value type, and a GC reference type among them is
      // two bytes wide, not one.
      let count = match reader.read_u32_leb() {
        Ok(value) => value
        Err(error) => return Err(error)
      }
      out.push(count)
      let mut i = 0
      while i < count {
        match reader.read_valtype() {
          Ok(_) => out.push(0)
          Err(error) => return Err(error)
        }
        i = i + 1
      }
    }
  }
  Ok(())
}

///|
/// Decode the instruction that starts at `offset`.
///
/// An unassigned opcode is an error rather than a skip: silently stepping over
/// one byte would turn a decoding bug into a wrong call graph, and every number
/// downstream of this function is a size.
pub fn decode_instruction(
  bytes : Bytes,
  offset : Int,
) -> Result[Instruction, WasmError] {
  let reader = Reader::new(bytes)
  reader.seek(offset)
  let first = match reader.read_byte() {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let opcode = match first {
    PREFIX_GC => {
      let sub = match reader.read_u32_leb() {
        Ok(value) => value
        Err(error) => return Err(error)
      }
      match gc_opcode(sub) {
        Some(opcode) => opcode
        None =>
          return Err(WasmError::UnknownPrefixedOpcode(offset, PREFIX_GC, sub))
      }
    }
    PREFIX_MISC => {
      let sub = match reader.read_u32_leb() {
        Ok(value) => value
        Err(error) => return Err(error)
      }
      match misc_opcode(sub) {
        Some(opcode) => opcode
        None =>
          return Err(WasmError::UnknownPrefixedOpcode(offset, PREFIX_MISC, sub))
      }
    }
    _ =>
      match simple_opcode(first) {
        Some(opcode) => opcode
        None => return Err(WasmError::UnknownOpcode(offset, first))
      }
  }
  let operands : Array[Int] = []
  match read_operands(reader, opcode.operands(), operands) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  Ok({ opcode, offset, size: reader.position() - offset, operands, })
}

///|
/// Consume a reference type.
///
/// A reference type is either a one-byte shorthand such as `funcref` (`0x70`),
/// or one of the two constructors `0x63`/`0x64` followed by a heap type. The
/// shorthand byte is returned, or `0` when the two-byte form was used.
pub fn Reader::read_reftype(self : Reader) -> Result[Int, WasmError] {
  let first = match self.read_byte() {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  if first == REF_NULL_TYPE || first == REF_TYPE {
    match self.read_signed_leb(33) {
      Ok(_) => ()
      Err(error) => return Err(error)
    }
    Ok(0)
  } else {
    Ok(first)
  }
}

///|
/// Consume a value type, whose width is not always one byte.
///
/// Numeric and vector types are a single byte, but a garbage-collection
/// reference type is the two-byte `0x63`/`0x64` form followed by a heap type.
/// Reading one byte per type desynchronises the stream on the first struct-typed
/// local, so every value type goes through here.
pub fn Reader::read_valtype(self : Reader) -> Result[Unit, WasmError] {
  let at = self.position()
  let first = match self.read_byte() {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  if first == REF_NULL_TYPE || first == REF_TYPE {
    match self.read_signed_leb(33) {
      Ok(_) => Ok(())
      Err(error) => Err(error)
    }
  } else {
    self.seek(at)
    match self.read_signed_leb(33) {
      Ok(_) => Ok(())
      Err(error) => Err(error)
    }
  }
}
