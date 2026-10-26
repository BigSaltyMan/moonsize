///|
fn run_data_search(options : @lib.Options, query : String) -> Unit {
  let report = match
    @lib.search_data_segments(read_input(options.path), query) {
    Ok(value) => value
    Err(error) => {
      println(
        "moonsize: " +
        options.path +
        ": " +
        @lib.describe_data_search_error(error),
      )
      @sys.exit(@lib.EXIT_INPUT)
      return
    }
  }
  match options.find_data_json {
    Some(target) => {
      check_outputs(options)
      write_output(target, @lib.render_data_search_json(report))
      println("Data search written to " + target)
    }
    None => println(@lib.render_data_search(report, options.top))
  }
}
