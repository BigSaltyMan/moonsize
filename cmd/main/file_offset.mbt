///|
fn run_file_offset(options : @lib.Options, offset : Int) -> Unit {
  let data = read_input(options.path)
  let rendered = if options.locate_decode {
    let report = match @lib.locate_file_offset_decoded(data, offset) {
      Ok(value) => value
      Err(error) => {
        println(
          "moonsize: " +
          options.path +
          ": " +
          @lib.describe_file_offset_decode_error(error),
        )
        @sys.exit(@lib.EXIT_INPUT)
        return
      }
    }
    match options.locate_offset_json {
      Some(_) => @lib.render_file_offset_decoded_json(report)
      None => @lib.render_file_offset_decoded(report)
    }
  } else {
    let report = match @lib.locate_file_offset(data, offset) {
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
      Some(_) => @lib.render_file_offset_json(report)
      None => @lib.render_file_offset(report)
    }
  }
  match options.locate_offset_json {
    Some(target) => {
      check_outputs(options)
      write_output(target, rendered)
      println("File offset location written to " + target)
    }
    None => println(rendered)
  }
}
