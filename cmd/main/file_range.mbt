///|
fn run_file_range(options : @lib.Options, offset : Int, length : Int) -> Unit {
  let data = read_input(options.path)
  let report = match @lib.locate_file_range(data, offset, length) {
    Ok(value) => value
    Err(error) => {
      println(
        "moonsize: " +
        options.path +
        ": " +
        @lib.describe_file_range_error(error),
      )
      @sys.exit(@lib.EXIT_INPUT)
      return
    }
  }
  match options.locate_range_json {
    Some(target) => {
      check_outputs(options)
      write_output(target, @lib.render_file_range_json(report))
      println("File range ownership written to " + target)
    }
    None => println(@lib.render_file_range(report, options.top))
  }
}
