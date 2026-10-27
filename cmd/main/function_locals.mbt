///|
fn run_function_locals(options : @lib.Options, index : Int) -> Unit {
  let report = match
    @lib.inspect_function_locals(read_input(options.path), index) {
    Ok(value) => value
    Err(error) => {
      println(
        "moonsize: " +
        options.path +
        ": " +
        @lib.describe_function_locals_error(error),
      )
      @sys.exit(@lib.EXIT_INPUT)
      return
    }
  }
  match options.locals_json {
    Some(target) => {
      check_outputs(options)
      write_output(target, @lib.render_function_locals_json(report))
      println("Function locals written to " + target)
    }
    None => println(@lib.render_function_locals(report, options.top))
  }
}
