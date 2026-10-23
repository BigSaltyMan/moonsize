///|
fn run_entrypoints(options : @lib.Options) -> Unit {
  let report = match @lib.inspect_entrypoints(read_input(options.path)) {
    Ok(report) => report
    Err(error) => {
      println("moonsize: " + @lib.describe_entrypoints_error(error))
      @sys.exit(@lib.EXIT_INPUT)
      return
    }
  }
  if options.strict && !report.graph_complete {
    println(report.graph_warning)
    println(
      "moonsize: --strict: refusing to report entrypoints with an incomplete call graph",
    )
    @sys.exit(@lib.EXIT_OVER_SIZE)
    return
  }
  match options.entrypoints_json {
    Some(target) => {
      check_outputs(options)
      write_output(target, @lib.render_entrypoints_json(report))
      println("Entrypoints written to " + target)
    }
    None => println(@lib.render_entrypoints(report, options.top))
  }
}
