///|
fn run_function_path_between(
  options : @lib.Options,
  source : Int,
  target : Int,
) -> Unit {
  let report = match
    @lib.function_path_between(read_input(options.path), source, target) {
    Ok(report) => report
    Err(error) => {
      println("moonsize: " + @lib.describe_function_path_between_error(error))
      @sys.exit(@lib.EXIT_INPUT)
      return
    }
  }
  if options.strict && !report.graph_complete {
    println(report.graph_warning)
    println(
      "moonsize: --strict: refusing to report function-to-function path with an incomplete call graph",
    )
    @sys.exit(@lib.EXIT_OVER_SIZE)
    return
  }
  match options.path_between_json {
    Some(target) => {
      check_outputs(options)
      write_output(target, @lib.render_function_path_between_json(report))
      println("Function path written to " + target)
    }
    None => println(@lib.render_function_path_between(report))
  }
}
