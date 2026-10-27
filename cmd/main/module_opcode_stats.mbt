///|
fn run_module_opcode_stats(options : @lib.Options) -> Unit {
  let report = match @lib.inspect_module_opcodes(read_input(options.path)) {
    Ok(report) => report
    Err(error) => {
      println(
        "moonsize: " +
        options.path +
        ": " +
        @lib.describe_module_opcode_error(error),
      )
      @sys.exit(@lib.EXIT_INPUT)
      return
    }
  }
  match options.opcode_stats_json {
    Some(target) => {
      check_outputs(options)
      write_output(target, @lib.render_module_opcodes_json(report))
      println("Module opcode statistics written to " + target)
    }
    None => println(@lib.render_module_opcodes(report, options.top))
  }
}
