///|
/// Independent query: no whole-module analyze or retained computation.
fn run_function_callers(options : @lib.Options, target_index : Int) -> Unit {
  let report = match
    @lib.function_callers(read_input(options.path), target_index) {
    Ok(report) => report
    Err(error) => {
      println("moonsize: " + @lib.describe_function_callers_error(error))
      @sys.exit(@lib.EXIT_INPUT)
      return
    }
  }
  if options.strict && !report.graph_complete {
    println(report.graph_warning)
    println(
      "moonsize: --strict: refusing to report function callers with an incomplete call graph",
    )
    @sys.exit(@lib.EXIT_OVER_SIZE)
    return
  }
  match options.callers_json {
    Some(target) => {
      check_outputs(options)
      write_output(target, @lib.render_function_callers_json(report))
      println("Function callers written to " + target)
    }
    None => println(@lib.render_function_callers(report, options.top))
  }
}
