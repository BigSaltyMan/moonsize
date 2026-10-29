///|
fn run_dependency_overlap(
  options : @lib.Options,
  left : Int,
  right : Int,
) -> Unit {
  let report = match
    @lib.compare_function_dependencies(read_input(options.path), left, right) {
    Ok(report) => report
    Err(error) => {
      println("moonsize: " + @lib.describe_dependency_overlap_error(error))
      @sys.exit(@lib.EXIT_INPUT)
      return
    }
  }
  if options.strict && !report.graph_complete {
    println(report.graph_warning)
    println(
      "moonsize: --strict: refusing to report dependency sets with an incomplete call graph",
    )
    @sys.exit(@lib.EXIT_OVER_SIZE)
    return
  }
  match options.compare_dependencies_json {
    Some(target) => {
      check_outputs(options)
      write_output(target, @lib.render_dependency_overlap_json(report))
      println("Dependency comparison written to " + target)
    }
    None => println(@lib.render_dependency_overlap(report, options.top))
  }
}
