///|
fn run_module_opcode_stats(options : @lib.Options) -> Unit {
  if options.diff_opcodes {
    run_module_opcode_comparison(options)
    return
  }
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

///|
fn run_module_opcode_comparison(options : @lib.Options) -> Unit {
  let baseline_path = match options.baseline {
    Some(path) => path
    None => return // Rejected by argument validation before I/O.
  }
  let baseline = read_metadata_input(baseline_path, "baseline")
  let current = read_metadata_input(options.path, "current")
  let report = match @lib.compare_module_opcodes(baseline, current) {
    Ok(report) => report
    Err(error) => {
      println(
        "moonsize: " + @lib.describe_module_opcode_comparison_error(error),
      )
      @sys.exit(@lib.EXIT_INPUT)
      return
    }
  }
  match options.opcode_stats_json {
    Some(target) => {
      check_outputs(options)
      write_output(target, @lib.render_module_opcode_comparison_json(report))
      println("Module opcode comparison written to " + target)
    }
    None => println(@lib.render_module_opcode_comparison(report, options.top))
  }
}
