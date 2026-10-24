///|
fn run_function_search(options : @lib.Options, query : String) -> Unit {
  let report = match
    @lib.search_local_functions(read_input(options.path), query) {
    Ok(value) => value
    Err(error) => {
      println(
        "moonsize: " +
        options.path +
        ": " +
        @lib.describe_function_search_error(error),
      )
      @sys.exit(@lib.EXIT_INPUT)
      return
    }
  }
  match options.find_functions_json {
    Some(target) => {
      check_outputs(options)
      write_output(target, @lib.render_function_search_json(report))
      println("Function search written to " + target)
    }
    None => println(@lib.render_function_search(report, options.top))
  }
}
