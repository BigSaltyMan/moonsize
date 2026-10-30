///|
fn run_function_dependencies(options : @lib.Options, index : Int) -> Unit {
  let report = match
    @lib.function_dependencies(read_input(options.path), index) {
    Ok(report) => report
    Err(error) => {
      println("moonsize: " + @lib.describe_function_dependencies_error(error))
      @sys.exit(@lib.EXIT_INPUT)
      return
    }
  }
  if options.strict && !report.graph_complete {
    println(report.graph_warning)
    println(
      "moonsize: --strict: refusing to report function dependencies with an incomplete call graph",
    )
    @sys.exit(@lib.EXIT_OVER_SIZE)
    return
  }
  if options.dependencies_dot is Some(target) {
    check_outputs(options)
    write_output(target, @lib.render_function_dependencies_dot(report))
    println("Function dependencies DOT written to " + target)
    return
  }
  match options.dependencies_json {
    Some(target) => {
      check_outputs(options)
      write_output(target, @lib.render_function_dependencies_json(report))
      println("Function dependencies written to " + target)
    }
    None => println(@lib.render_function_dependencies(report, options.top))
  }
}
