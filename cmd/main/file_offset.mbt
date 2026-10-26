///|
fn run_file_offset(options : @lib.Options, offset : Int) -> Unit {
  let report = match @lib.locate_file_offset(read_input(options.path), offset) {
    Ok(value) => value
    Err(error) => {
      println(
        "moonsize: " +
        options.path +
        ": " +
        @lib.describe_file_offset_error(error),
      )
      @sys.exit(@lib.EXIT_INPUT)
      return
    }
  }
  match options.locate_offset_json {
    Some(target) => {
      check_outputs(options)
      write_output(target, @lib.render_file_offset_json(report))
      println("File offset location written to " + target)
    }
    None => println(@lib.render_file_offset(report))
  }
}
