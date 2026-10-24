///|
fn run_function_instructions(options : @lib.Options, index : Int) -> Unit {
  let report = match
    @lib.inspect_function_instructions(read_input(options.path), index) {
    Ok(value) => value
    Err(error) => {
      println(
        "moonsize: " +
        options.path +
        ": " +
        @lib.describe_function_instructions_error(error),
      )
      @sys.exit(@lib.EXIT_INPUT)
      return
    }
  }
  match options.instructions_json {
    Some(target) => {
      check_outputs(options)
      write_output(target, @lib.render_function_instructions_json(report))
      println("Function instructions written to " + target)
    }
    None => println(@lib.render_function_instructions(report, options.top))
  }
}
