///|
fn run_function_dependents(options : @lib.Options, index : Int) -> Unit {
  let report = match @lib.function_dependents(read_input(options.path), index) {
    Ok(report) => report
    Err(error) => {
      println("moonsize: " + @lib.describe_function_dependents_error(error))
      @sys.exit(@lib.EXIT_INPUT)
      return
    }
  }
  if options.strict && !report.graph_complete {
    println(report.graph_warning)
    println(
      "moonsize: --strict: refusing to report function dependents with an incomplete call graph",
    )
    @sys.exit(@lib.EXIT_OVER_SIZE)
    return
  }
  if options.dependents_dot is Some(target) {
    check_outputs(options)
    write_output(target, @lib.render_function_dependents_dot(report))
    println("Function dependents DOT written to " + target)
    return
  }
  match options.dependents_json {
    Some(target) => {
      check_outputs(options)
      write_output(target, @lib.render_function_dependents_json(report))
      println("Function dependents written to " + target)
    }
    None => println(@lib.render_function_dependents(report, options.top))
  }
}
