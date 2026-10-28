///|
fn run_data_preview(options : @lib.Options, index : Int) -> Unit {
  if options.baseline_data_preview_index is Some(baseline_index) {
    run_data_preview_comparison(options, baseline_index, index)
    return
  }
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

///|
fn run_data_preview_comparison(
  options : @lib.Options,
  baseline_index : Int,
  current_index : Int,
) -> Unit {
  let baseline_path = match options.baseline {
    Some(path) => path
    None => return
  }
  let baseline = read_metadata_input(baseline_path, "baseline")
  let current = read_metadata_input(options.path, "current")
  let report = match
    @lib.compare_data_previews(
      baseline,
      baseline_index,
      options.baseline_data_offset.unwrap_or(0),
      current,
      current_index,
      options.data_offset.unwrap_or(0),
      options.data_limit.unwrap_or(256),
    ) {
    Ok(report) => report
    Err(error) => {
      println("moonsize: " + @lib.describe_data_preview_comparison_error(error))
      @sys.exit(@lib.EXIT_INPUT)
      return
    }
  }
  match options.data_preview_json {
    Some(target) => {
      check_outputs(options)
      write_output(target, @lib.render_data_preview_comparison_json(report))
      println("Data preview comparison written to " + target)
    }
    None => println(@lib.render_data_preview_comparison(report))
  }
}
