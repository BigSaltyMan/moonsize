///|
fn run_opcode_search(options : @lib.Options) -> Unit {
  let query = match options.find_opcode {
    Some(query) => query
    None => return // Rejected before I/O by the parser.
  }
  let report = match @lib.search_opcode(read_input(options.path), query) {
    Ok(report) => report
    Err(error) => {
      println(
        "moonsize: " +
        options.path +
        ": " +
        @lib.describe_opcode_search_error(error),
      )
      @sys.exit(@lib.EXIT_INPUT)
      return
    }
  }
  match options.find_opcode_json {
    Some(target) => {
      check_outputs(options)
      write_output(target, @lib.render_opcode_search_json(report))
      println("Opcode search written to " + target)
    }
    None => println(@lib.render_opcode_search(report, options.top))
  }
}
