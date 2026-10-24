///|
fn run_imports(options : @lib.Options) -> Unit {
  if options.diff_imports {
    run_imports_diff(options)
    return
  }
  let report = match @lib.inspect_imports(read_input(options.path)) {
    Ok(report) => report
    Err(error) => {
      println("moonsize: " + options.path + ": " + @lib.describe_error(error))
      @sys.exit(@lib.EXIT_INPUT)
      return
    }
  }
  match options.imports_json {
    Some(target) => {
      check_outputs(options)
      write_output(target, @lib.render_imports_json(report))
      println("Imports written to " + target)
    }
    None => println(@lib.render_imports(report, options.top))
  }
}

///|
fn read_imports_comparison_input(path : String, side : String) -> Bytes {
  @fs.read_file_to_bytes(path) catch {
    _ => {
      println("moonsize: " + side + ": " + path + ": cannot read input file")
      @sys.exit(@lib.EXIT_INPUT)
      Bytes::new(0)
    }
  }
}

///|
fn run_imports_diff(options : @lib.Options) -> Unit {
  let baseline_path = match options.baseline {
    Some(path) => path
    None => return // parse_options rejects this before input I/O.
  }
  let baseline = read_imports_comparison_input(baseline_path, "baseline")
  let current = read_imports_comparison_input(options.path, "current")
  let report = match @lib.compare_imports(baseline, current) {
    Ok(report) => report
    Err(error) => {
      let path = match error {
        @lib.ImportsBaselineError(_) => baseline_path
        @lib.ImportsCurrentError(_) => options.path
      }
      println(
        "moonsize: " +
        path +
        ": " +
        @lib.describe_imports_comparison_error(error),
      )
      @sys.exit(@lib.EXIT_INPUT)
      return
    }
  }
  match options.imports_json {
    Some(target) => {
      check_outputs(options)
      write_output(target, @lib.render_imports_diff_json(report))
      println("Imports comparison written to " + target)
    }
    None => println(@lib.render_imports_diff(report, options.top))
  }
}
