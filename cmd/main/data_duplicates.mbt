///|
fn run_duplicate_data(options : @lib.Options) -> Unit {
  let report = match @lib.inspect_duplicate_data(read_input(options.path)) {
    Ok(report) => report
    Err(error) => {
      println("moonsize: " + options.path + ": " + @lib.describe_error(error))
      @sys.exit(@lib.EXIT_INPUT)
      return
    }
  }
  match options.data_duplicates_json {
    Some(target) => {
      check_outputs(options)
      write_output(target, @lib.render_duplicate_data_json(report))
      println("Duplicate data payloads written to " + target)
    }
    None => println(@lib.render_duplicate_data(report, options.top))
  }
}
