///|
fn run_function_calls(options : @lib.Options, index : Int) -> Unit {
  let report = match
    @lib.inspect_function_calls(read_input(options.path), index) {
    Ok(value) => value
    Err(error) => {
      println(
        "moonsize: " +
        options.path +
        ": " +
        @lib.describe_function_calls_error(error),
      )
      @sys.exit(@lib.EXIT_INPUT)
      return
    }
  }
  match options.calls_json {
    Some(target) => {
      check_outputs(options)
      write_output(target, @lib.render_function_calls_json(report))
      println("Function calls written to " + target)
    }
    None => println(@lib.render_function_calls(report, options.top))
  }
}
