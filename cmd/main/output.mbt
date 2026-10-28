///|
/// Native x/fs exposes truncating writes only. Keep the exclusive operation
/// private to the CLI; path bytes are NUL-terminated and explicitly length checked.
#borrow(path)
extern "C" fn output_probe(path : Bytes, length : Int) -> Int = "moonsize_output_probe"

///|
#borrow(path, contents)
extern "C" fn output_create(
  path : Bytes,
  length : Int,
  contents : Bytes,
  size : Int,
) -> Int = "moonsize_output_create"

///|
fn output_failure(path : String, status : Int) -> Unit {
  if status == 1 {
    println("moonsize: output already exists: " + path)
  } else {
    println("moonsize: cannot safely write output: " + path)
  }
  @sys.exit(@lib.EXIT_INPUT)
}

///|
/// Check every destination after parsing/analysis/strict refusal and before the
/// first write. This check is advisory; each actual create is exclusive as well.
fn check_outputs(options : @lib.Options) -> Unit {
  for
    target in [
      options.html,
      options.summary_json,
      options.diff_functions_json,
      options.call_graph,
      options.experiment,
      options.why_json,
      options.callers_json,
      options.calls_json,
      options.locals_json,
      options.local_accesses_json,
      options.opcode_stats_json,
      options.find_opcode_json,
      options.generics_json,
      options.entrypoints_json,
      options.duplicates_json,
      options.exports_json,
      options.metadata_json,
      options.imports_json,
      options.data_duplicates_json,
      options.instructions_json,
      options.find_functions_json,
      options.find_data_json,
      options.data_preview_json,
      options.locate_offset_json,
      options.budget_json,
      options.budget_md,
      options.data_json,
    ] {
    if target is Some(path) {
      let bytes = @utf8.encode(path)
      let status = output_probe(bytes + Bytes::make(1, 0), bytes.length())
      if status != 0 {
        output_failure(path, status)
      }
    }
  }
}

///|
/// Never truncates or removes a destination, even if it appeared after the
/// preflight. A failed write may leave our own new partial file; no rollback or
/// multi-output transaction is claimed. Hostile parent-directory changes remain
/// outside this pathname-based guarantee.
fn write_output(path : String, contents : String) -> Unit {
  let path_bytes = @utf8.encode(path)
  let contents = @utf8.encode(contents)
  let status = output_create(
    path_bytes + Bytes::make(1, 0),
    path_bytes.length(),
    contents,
    contents.length(),
  )
  if status != 0 {
    output_failure(path, status)
  }
}
