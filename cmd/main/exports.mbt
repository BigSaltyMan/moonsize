///|
fn read_exports_input(path : String, side : String) -> Bytes {
  @fs.read_file_to_bytes(path) catch {
    _ => {
      println("moonsize: \{side}: \{path}: cannot read input file")
      @sys.exit(@lib.EXIT_INPUT)
      Bytes::new(0)
    }
  }
}

///|
fn run_exports_diff(options : @lib.Options) -> Unit {
  let baseline_path = match options.baseline {
    Some(path) => path
    None => return // parse_options rejects missing baseline before input I/O.
  }
  let baseline = read_exports_input(baseline_path, "baseline")
  let current = read_exports_input(options.path, "current")
  let report = match @lib.compare_exports(baseline, current) {
    Ok(report) => report
    Err(error) => {
      let (side, path, cause) = match error {
        @lib.Baseline(cause) => ("baseline", baseline_path, cause)
        @lib.Current(cause) => ("current", options.path, cause)
      }
      println("moonsize: \{side}: \{path}: " + @lib.describe_error(cause))
      @sys.exit(@lib.EXIT_INPUT)
      return
    }
  }
  match options.exports_json {
    Some(target) => {
      check_outputs(options)
      write_output(target, @lib.render_exports_diff_json(report))
      println("Exports comparison written to " + target)
    }
    None => println(@lib.render_exports_diff(report, options.top))
  }
}

///|
fn run_exports(options : @lib.Options) -> Unit {
  if options.diff_exports {
    run_exports_diff(options)
    return
  }
  let report = match @lib.inspect_exports(read_input(options.path)) {
    Ok(report) => report
    Err(error) => {
      println("moonsize: " + options.path + ": " + @lib.describe_error(error))
      @sys.exit(@lib.EXIT_INPUT)
      return
    }
  }
  match options.exports_json {
    Some(target) => {
      check_outputs(options)
      write_output(target, @lib.render_exports_json(report))
      println("Exports written to " + target)
    }
    None => println(@lib.render_exports(report, options.top))
  }
}
