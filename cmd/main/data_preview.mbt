///|
fn run_data_preview(options : @lib.Options, index : Int) -> Unit {
  let report = match
    @lib.preview_data_segment(
      read_input(options.path),
      index,
      options.data_offset.unwrap_or(0),
      options.data_limit.unwrap_or(256),
    ) {
    Ok(value) => value
    Err(error) => {
      println(
        "moonsize: " +
        options.path +
        ": " +
        @lib.describe_data_preview_error(error),
      )
      @sys.exit(@lib.EXIT_INPUT)
      return
    }
  }
  match options.data_preview_json {
    Some(target) => {
      check_outputs(options)
      write_output(target, @lib.render_data_preview_json(report))
      println("Data preview written to " + target)
    }
    None => println(@lib.render_data_preview(report))
  }
}
