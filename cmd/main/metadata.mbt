///|
fn run_metadata(options : @lib.Options) -> Unit {
  let report = match @lib.inspect_metadata(read_input(options.path)) {
    Ok(report) => report
    Err(error) => {
      println("moonsize: " + options.path + ": " + @lib.describe_error(error))
      @sys.exit(@lib.EXIT_INPUT)
      return
    }
  }
  match options.metadata_json {
    Some(target) => {
      check_outputs(options)
      write_output(target, @lib.render_metadata_json(report))
      println("Metadata written to " + target)
    }
    None => println(@lib.render_metadata(report, options.top))
  }
}
