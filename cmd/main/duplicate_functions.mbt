///|
fn run_duplicate_functions(options : @lib.Options) -> Unit {
  let report = match
    @lib.inspect_duplicate_functions(read_input(options.path)) {
    Ok(report) => report
    Err(error) => {
      println("moonsize: " + options.path + ": " + @lib.describe_error(error))
      @sys.exit(@lib.EXIT_INPUT)
      return
    }
  }
  match options.duplicates_json {
    Some(target) => {
      check_outputs(options)
      write_output(target, @lib.render_duplicate_functions_json(report))
      println("Duplicate function bodies written to " + target)
    }
    None => println(@lib.render_duplicate_functions(report, options.top))
  }
}
