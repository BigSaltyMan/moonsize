///|
fn run_function_cycles(options : @lib.Options) -> Unit {
  let report = match @lib.function_cycles(read_input(options.path)) {
    Ok(report) => report
    Err(error) => {
      println("moonsize: " + @lib.describe_function_cycles_error(error))
      @sys.exit(@lib.EXIT_INPUT)
      return
    }
  }
  if options.strict && !report.graph_complete {
    println(report.graph_warning)
    println(
      "moonsize: --strict: refusing to report function cycles with an incomplete call graph",
    )
    @sys.exit(@lib.EXIT_OVER_SIZE)
    return
  }
  match options.cycles_json {
    Some(target) => {
      check_outputs(options)
      write_output(target, @lib.render_function_cycles_json(report))
      println("Function cycles written to " + target)
    }
    None => println(@lib.render_function_cycles(report, options.top))
  }
}
