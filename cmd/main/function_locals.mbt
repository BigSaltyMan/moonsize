///|
fn run_function_locals(options : @lib.Options, index : Int) -> Unit {
  if options.baseline_locals_index is Some(before_index) &&
    options.baseline is Some(before_path) {
    let report = match
      @lib.compare_function_locals(
        read_input(before_path),
        before_index,
        read_input(options.path),
        index,
      ) {
      Ok(value) => value
      Err(error) => {
        println(
          "moonsize: " + @lib.describe_function_locals_comparison_error(error),
        )
        @sys.exit(@lib.EXIT_INPUT)
        return
      }
    }
    match options.locals_json {
      Some(target) => {
        check_outputs(options)
        write_output(
          target,
          @lib.render_function_locals_comparison_json(report),
        )
        println("Function locals comparison written to " + target)
      }
      None =>
        println(@lib.render_function_locals_comparison(report, options.top))
    }
    return
  }
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
