///|
pub struct FunctionOpcodeDelta {
  mnemonic : String
  baseline_count : Int
  current_count : Int
  count_delta : Int
  baseline_encoded_bytes : Int
  current_encoded_bytes : Int
  encoded_bytes_delta : Int
}

///|
/// Signed current-minus-baseline quantities, never file ranges.
pub struct FunctionInstructionsDelta {
  entry_bytes : Int
  prefix_bytes : Int
  body_bytes : Int
  locals_bytes : Int
  instruction_bytes : Int
  instruction_count : Int
}

///|
pub struct FunctionInstructionsComparison {
  baseline : FunctionInstructionsReport
  current : FunctionInstructionsReport
  delta : FunctionInstructionsDelta
  opcodes : Array[FunctionOpcodeDelta]
  scope : String
}

///|
pub enum FunctionInstructionsComparisonError {
  BaselineInstructionsError(Int, FunctionInstructionsError)
  CurrentInstructionsError(Int, FunctionInstructionsError)
}

///|
pub fn describe_function_instructions_comparison_error(
  error : FunctionInstructionsComparisonError,
) -> String {
  match error {
    BaselineInstructionsError(index, cause) =>
      "baseline function \{index}: " +
      describe_function_instructions_error(cause)
    CurrentInstructionsError(index, cause) =>
      "current function \{index}: " +
      describe_function_instructions_error(cause)
  }
}

///|
fn instruction_composition_row(
  mnemonic : String,
  before_count : Int,
  before_bytes : Int,
  after_count : Int,
  after_bytes : Int,
) -> FunctionOpcodeDelta {
  {
    mnemonic,
    baseline_count: before_count,
    current_count: after_count,
    count_delta: after_count - before_count,
    baseline_encoded_bytes: before_bytes,
    current_encoded_bytes: after_bytes,
    encoded_bytes_delta: after_bytes - before_bytes,
  }
}

///|
/// Each side inspects its explicit target once. No identity matching or alignment.
pub fn compare_function_instructions(
  baseline : Bytes,
  baseline_index : Int,
  current : Bytes,
  current_index : Int,
) -> Result[FunctionInstructionsComparison, FunctionInstructionsComparisonError] {
  let before = match inspect_function_instructions(baseline, baseline_index) {
    Ok(report) => report
    Err(error) => return Err(BaselineInstructionsError(baseline_index, error))
  }
  let after = match inspect_function_instructions(current, current_index) {
    Ok(report) => report
    Err(error) => return Err(CurrentInstructionsError(current_index, error))
  }
  let rows : Map[String, FunctionOpcodeDelta] = Map([])
  for group in before.groups {
    rows.set(
      group.mnemonic,
      instruction_composition_row(
        group.mnemonic,
        group.count,
        group.encoded_bytes,
        0,
        0,
      ),
    )
  }
  for group in after.groups {
    let (count, bytes) = match rows.get(group.mnemonic) {
      Some(row) => (row.baseline_count, row.baseline_encoded_bytes)
      None => (0, 0)
    }
    rows.set(
      group.mnemonic,
      instruction_composition_row(
        group.mnemonic,
        count,
        bytes,
        group.count,
        group.encoded_bytes,
      ),
    )
  }
  let opcodes : Array[FunctionOpcodeDelta] = []
  for _, row in rows {
    opcodes.push(row)
  }
  // Deltas of bounded nonnegative counts/sizes cannot be Int::MIN.
  opcodes.sort_by(fn(a, b) {
    let bytes = b.encoded_bytes_delta.abs().compare(a.encoded_bytes_delta.abs())
    if bytes != 0 {
      bytes
    } else {
      let count = b.count_delta.abs().compare(a.count_delta.abs())
      if count != 0 {
        count
      } else {
        a.mnemonic.lexical_compare(b.mnemonic)
      }
    }
  })
  Ok({
    baseline: before,
    current: after,
    delta: {
      entry_bytes: after.entry.size - before.entry.size,
      prefix_bytes: after.prefix.size - before.prefix.size,
      body_bytes: after.body.size - before.body.size,
      locals_bytes: after.locals_encoding.size - before.locals_encoding.size,
      instruction_bytes: after.instruction_bytes - before.instruction_bytes,
      instruction_count: after.instruction_count - before.instruction_count,
    },
    opcodes,
    scope: "User-selected pair of local functions; full indices belong to their respective inputs. Equal indices or names do not establish cross-build identity; different names are allowed. Only encoding composition statistics are compared; instruction sequences and immediate values are not compared. Zero aggregate deltas do not prove equal sequences, semantics or compatibility. Delta = current - baseline, including actual body-length prefixes and locals vector encodings. Quantities are not file ranges. Excludes section headers/counts, function and name sections and dependency closures. Entry delta is not whole-file delta and predicts neither performance, source removal, rebuilt output nor gzip savings. No automatic matching, instruction alignment, graph or analyze. Top limits text rows only; nested reports and JSON retain complete selected-target evidence.",
  })
}
