///|
fn run_function_local_accesses(options : @lib.Options, index : Int) -> Unit {
  let report = match
    @lib.inspect_function_local_accesses(read_input(options.path), index) {
    Ok(value) => value
    Err(error) => {
      println(
        "moonsize: " +
        options.path +
        ": " +
        @lib.describe_function_local_accesses_error(error),
      )
      @sys.exit(@lib.EXIT_INPUT)
      return
    }
  }
  match options.local_accesses_json {
    Some(target) => {
      check_outputs(options)
      write_output(target, @lib.render_function_local_accesses_json(report))
      println("Function local accesses written to " + target)
    }
    None => println(@lib.render_function_local_accesses(report, options.top))
  }
}
