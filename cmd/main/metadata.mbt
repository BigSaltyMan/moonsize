///|
fn read_metadata_input(path : String, side : String) -> Bytes {
  @fs.read_file_to_bytes(path) catch {
    _ => {
      println("moonsize: \{side}: \{path}: cannot read input file")
      @sys.exit(@lib.EXIT_INPUT)
      Bytes::new(0)
    }
  }
}

///|
fn run_metadata_diff(options : @lib.Options) -> Unit {
  let baseline_path = match options.baseline {
    Some(path) => path
    None => return // Rejected before input I/O by parse_options.
  }
  let baseline = read_metadata_input(baseline_path, "baseline")
  let current = read_metadata_input(options.path, "current")
  let report = match @lib.compare_metadata(baseline, current) {
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
  match options.metadata_json {
    Some(target) => {
      check_outputs(options)
      write_output(target, @lib.render_metadata_diff_json(report))
      println("Metadata comparison written to " + target)
    }
    None => println(@lib.render_metadata_diff(report, options.top))
  }
}

///|
fn run_metadata(options : @lib.Options) -> Unit {
  if options.diff_metadata {
    run_metadata_diff(options)
    return
  }
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
