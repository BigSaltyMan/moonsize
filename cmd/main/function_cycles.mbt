///|
fn run_function_cycles(options : @lib.Options) -> Unit {
  let data = read_input(options.path)
  let witnesses = if options.cycle_witness {
    match @lib.function_cycle_witnesses(data) {
      Ok(report) => Some(report)
      Err(error) => {
        println(
          "moonsize: " + @lib.describe_function_cycle_witness_error(error),
        )
        @sys.exit(@lib.EXIT_INPUT)
        return
      }
    }
  } else {
    None
  }
  let cycles = match witnesses {
    Some(report) => report.cycles
    None =>
      match @lib.function_cycles(data) {
        Ok(report) => report
        Err(error) => {
          println("moonsize: " + @lib.describe_function_cycles_error(error))
          @sys.exit(@lib.EXIT_INPUT)
          return
        }
      }
  }
  if options.strict && !cycles.graph_complete {
    println(cycles.graph_warning)
    println(
      "moonsize: --strict: refusing to report function cycles with an incomplete call graph",
    )
    @sys.exit(@lib.EXIT_OVER_SIZE)
    return
  }
  let rendered = match (witnesses, options.cycles_json) {
    (Some(report), Some(_)) => @lib.render_function_cycle_witnesses_json(report)
    (Some(report), None) =>
      @lib.render_function_cycle_witnesses(report, options.top)
    (None, Some(_)) => @lib.render_function_cycles_json(cycles)
    (None, None) => @lib.render_function_cycles(cycles, options.top)
  }
  match options.cycles_json {
    Some(target) => {
      check_outputs(options)
      write_output(target, rendered)
      println(
        (if options.cycle_witness {
          "Function cycle witnesses written to "
        } else {
          "Function cycles written to "
        }) +
        target,
      )
    }
    None => println(rendered)
  }
}
