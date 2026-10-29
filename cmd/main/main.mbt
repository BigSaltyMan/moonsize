///|
/// Read the whole input file, reporting failure and exiting when it is missing.
///
/// The library deliberately does no I/O, so the process boundary owns both the
/// filesystem and the exit code.
fn read_input(path : String) -> Bytes {
  @fs.read_file_to_bytes(path) catch {
    _ => {
      println("moonsize: cannot read \{path}")
      @sys.exit(1)
      Bytes::new(0)
    }
  }
}

///|
/// Hash bytes already read for the comparison, using the existing crypto dependency.
fn diff_input_sha256(data : Bytes) -> String {
  let out = StringBuilder()
  for byte in @crypto.sha256(data) {
    out.write_string(byte.to_hex())
  }
  out.to_string()
}

///|
/// The module to compare against, or `None` when the invocation named none.
fn read_baseline(options : @lib.Options) -> (Bytes, @lib.WasmModule)? {
  match options.baseline {
    None => None
    Some(target) => {
      let bytes = read_input(target)
      match @lib.parse_module(bytes) {
        Ok(parsed) => Some((bytes, parsed))
        Err(error) => {
          let role = if options.diff_functions_json is Some(_) {
            "baseline: "
          } else {
            ""
          }
          println("moonsize: \{role}\{target}: \{@lib.describe_error(error)}")
          @sys.exit(1)
          None
        }
      }
    }
  }
}

///|
/// The text report: the section table, the function ranking, the module summary,
/// and whichever optional sections were asked for.
fn print_report(
  bytes : Bytes,
  parsed : @lib.WasmModule,
  analysis : @lib.Analysis,
  options : @lib.Options,
  whole_gzip? : Result[Int, String],
) -> Unit {
  let warning = @lib.render_graph_warning(analysis.graph)
  if warning.length() > 0 {
    println(warning)
    println("")
  }
  println(@lib.format_report(parsed, options.path))
  if options.compress {
    println("")
    println(
      @lib.render_compression(
        parsed.file_size,
        whole_gzip.unwrap_or_else(fn() { @lib.compressed_size(bytes) }),
        @lib.compress_sections(bytes, parsed),
      ),
    )
  }
  println("")
  println(
    @lib.render_top_functions(analysis.stats, parsed.file_size, options.top),
  )
  println("")
  println(@lib.render_module_summary(analysis.stats, parsed.file_size))
  if options.retained {
    println("")
    println(@lib.render_retained(analysis, options.top))
  }
  if options.dead_code {
    println("")
    println(@lib.render_dead_code(analysis, options.top))
  }
}

///|
/// A separate output mode: validate all evidence before writing a new report.
/// Existing paths are refused, including input aliases and existing reports.
fn run_experiment(options : @lib.Options, target : String) -> Unit {
  let context = match options.experiment_context {
    None => Json::null()
    Some(path) => {
      let text = @fs.read_file_to_string(path) catch {
        _ => {
          println("moonsize: cannot read experiment context " + path)
          @sys.exit(@lib.EXIT_INPUT)
          return
        }
      }
      @json.parse(text) catch {
        error => {
          println(
            "moonsize: invalid experiment context " +
            path +
            ": " +
            error.to_string(),
          )
          @sys.exit(@lib.EXIT_INPUT)
          return
        }
      }
    }
  }
  match @lib.check_experiment_context(context) {
    Err(error) => {
      println("moonsize: " + error)
      @sys.exit(@lib.EXIT_INPUT)
      return
    }
    Ok(_) => ()
  }
  let baseline_path = match options.baseline {
    Some(path) => path
    None => return // parse_options rejects this before I/O.
  }
  let baseline = read_input(baseline_path)
  let current = read_input(options.path)
  let report = match
    @lib.experiment_report(
      baseline,
      current,
      baseline_path,
      options.path,
      context,
      top=options.top,
    ) {
    Ok(report) => report
    Err(error) => {
      println("moonsize: " + error)
      @sys.exit(@lib.EXIT_INPUT)
      return
    }
  }
  if options.strict && report is Object(fields) {
    for side in ["baseline", "current"] {
      match fields.get(side) {
        Some(Object(artifact)) if artifact.get("graph_complete") ==
          Some(Json::boolean(false)) => {
          println(
            "moonsize: --strict: refusing experiment with an incomplete " +
            side +
            " call graph",
          )
          match artifact.get("diagnostics") {
            Some(diagnostics) => println(diagnostics.stringify(indent=2))
            None => ()
          }
          @sys.exit(@lib.EXIT_OVER_SIZE)
          return
        }
        _ => ()
      }
    }
  }
  let code = @lib.size_exit_code(
    options,
    current.length(),
    Some(baseline.length()),
  )
  if report is Object(fields) {
    fields.set(
      "raw_growth_budget_bytes",
      match options.max_size {
        Some(size) => Json::number(size.to_double(), repr=size.to_string())
        None => Json::null()
      },
    )
    fields.set("raw_growth_budget_passed", Json::boolean(code == @lib.EXIT_OK))
  }
  let contents = if target.has_suffix(".html") {
    @lib.render_experiment_html(report)
  } else {
    report.stringify(indent=2) + "\n"
  }
  check_outputs(options)
  write_output(target, contents)
  println("Optimization experiment written to " + target)
  if code != @lib.EXIT_OK {
    println(
      @lib.describe_size_failure(
        options,
        current.length(),
        Some(baseline.length()),
      ),
    )
    @sys.exit(code)
  }
}

///|
/// Query the canonical graph without running whole-module retained analysis.
fn run_function_path(options : @lib.Options, target_index : Int) -> Unit {
  let data = read_input(options.path)
  let report = match
    @lib.explain_function(data, target_index, root?=options.why_root) {
    Ok(report) => report
    Err(error) => {
      println("moonsize: " + @lib.describe_function_path_error(error))
      @sys.exit(@lib.EXIT_INPUT)
      return
    }
  }
  if options.strict && !report.graph_complete {
    println(report.graph_warning)
    println(
      "moonsize: --strict: refusing to report a function path with an incomplete call graph",
    )
    @sys.exit(@lib.EXIT_OVER_SIZE)
    return
  }
  match options.why_json {
    Some(target) => {
      check_outputs(options)
      write_output(target, @lib.render_function_path_json(report))
      println("Function path written to " + target)
    }
    None => println(@lib.render_function_path(report))
  }
  if report.status is PathSearchLimited {
    @sys.exit(@lib.EXIT_OVER_SIZE)
  }
}

///|
/// Validate configuration and baseline requirements before business input I/O.
fn read_budget(options : @lib.Options) -> @lib.CompiledBudget? {
  let config_path = match options.budget {
    Some(path) => path
    None => return None
  }
  let config_text = @fs.read_file_to_string(config_path) catch {
    _ => {
      println("moonsize: cannot read budget configuration " + config_path)
      @sys.exit(1)
      return None
    }
  }
  let compiled = match @lib.compile_budget_text(config_text) {
    Ok(compiled) => compiled
    Err(problems) => {
      for problem in problems {
        let location = match problem.rule_index {
          Some(index) => "rules[" + index.to_string() + "]."
          None => ""
        }
        println(
          "moonsize: budget " + location + problem.field + ": " + problem.reason,
        )
      }
      @sys.exit(2)
      return None
    }
  }
  if @lib.budget_requires_baseline(compiled) && options.baseline is None {
    println("moonsize: growth budget rules require --baseline")
    @sys.exit(2)
    return None
  }
  Some(compiled)
}

///|
/// Supply command-line arguments and filesystem access to the library.
fn main {
  let args = @env.args()
  match @lib.help_request(args) {
    Ok(Some(text)) => {
      println(text)
      return
    }
    Ok(None) => ()
    Err(message) => {
      println(message)
      @sys.exit(@lib.EXIT_USAGE)
      return
    }
  }
  let options = match @lib.parse_options(args) {
    Ok(options) => options
    Err(message) => {
      println(message)
      @sys.exit(@lib.EXIT_USAGE)
      return
    }
  }
  if options.find_opcode is Some(_) {
    run_opcode_search(options)
    return
  }
  if options.opcode_stats {
    run_module_opcode_stats(options)
    return
  }
  if options.local_accesses_index is Some(index) {
    run_function_local_accesses(options, index)
    return
  }
  if options.locals_index is Some(index) {
    run_function_locals(options, index)
    return
  }
  if options.calls_index is Some(index) {
    run_function_calls(options, index)
    return
  }
  if options.path_between is Some((source, target)) {
    run_function_path_between(options, source, target)
    return
  }
  if options.dependents is Some(index) {
    run_function_dependents(options, index)
    return
  }
  if options.dependencies is Some(index) {
    run_function_dependencies(options, index)
    return
  }
  if options.cycles {
    run_function_cycles(options)
    return
  }
  if options.locate_range_offset is Some(offset) {
    run_file_range(options, offset, options.locate_range_length.unwrap())
    return
  }
  if options.locate_offset is Some(offset) {
    run_file_offset(options, offset)
    return
  }
  if options.data_preview_index is Some(index) {
    run_data_preview(options, index)
    return
  }
  if options.find_data_hex is Some(query) {
    run_data_hex_search(options, query)
    return
  }
  if options.find_data is Some(query) {
    run_data_search(options, query)
    return
  }
  if options.find_functions is Some(query) {
    run_function_search(options, query)
    return
  }
  if options.instructions_index is Some(index) {
    run_function_instructions(options, index)
    return
  }
  if options.data_duplicates {
    run_duplicate_data(options)
    return
  }
  if options.imports {
    run_imports(options)
    return
  }
  if options.exports {
    run_exports(options)
    return
  }
  if options.metadata {
    run_metadata(options)
    return
  }
  if options.duplicates {
    run_duplicate_functions(options)
    return
  }
  if options.entrypoints {
    run_entrypoints(options)
    return
  }
  if options.generics {
    run_generic_instances(options)
    return
  }
  let budget = read_budget(options)
  if options.callers_index is Some(target) {
    run_function_callers(options, target)
    return
  }
  if options.why_index is Some(target) {
    run_function_path(options, target)
    return
  }
  if options.experiment is Some(target) {
    run_experiment(options, target)
    return
  }
  let bytes = read_input(options.path)
  let parsed = match @lib.parse_module(bytes) {
    Ok(parsed) => parsed
    Err(error) => {
      println("moonsize: \{options.path}: \{@lib.describe_error(error)}")
      @sys.exit(@lib.EXIT_INPUT)
      return
    }
  }
  // The baseline is read before any report is printed, so a bad path fails the
  // run without half a comparison already in the log.
  let baseline = read_baseline(options)
  let baseline_size = match baseline {
    Some((_, baseline_module)) => Some(baseline_module.file_size)
    None => None
  }
  // Opt-in structural inspection must fail before any normal report is printed.
  let data_diff = if options.diff_data {
    match baseline {
      Some((baseline_bytes, _)) =>
        match @lib.compare_data_segments(baseline_bytes, bytes) {
          Ok(report) => Some(report)
          Err(error) => {
            match error {
              Baseline(error) =>
                println("moonsize: baseline: " + @lib.describe_error(error))
              Current(error) =>
                println("moonsize: current: " + @lib.describe_error(error))
            }
            @sys.exit(@lib.EXIT_INPUT)
            return
          }
        }
      None => None // parse_options rejects this combination before I/O.
    }
  } else {
    None
  }
  let data_details = if data_diff is Some(report) {
    Some(report.current) // Reuse the comparison's inspection, not a third scan.
  } else if options.data_segments {
    match @lib.inspect_data_segments(bytes) {
      Ok(report) => Some(report)
      Err(error) => {
        println("moonsize: " + options.path + ": " + @lib.describe_error(error))
        @sys.exit(@lib.EXIT_INPUT)
        return
      }
    }
  } else {
    None
  }
  let budget_report = match budget {
    None => None
    Some(compiled) => {
      let baseline_data = baseline.map(fn(pair) { pair.0 })
      match @lib.evaluate_budget(compiled, bytes, baseline_data?) {
        Ok(report) => Some(report)
        Err(error) => {
          println("moonsize: " + @lib.describe_budget_error(error))
          @sys.exit(1)
          return
        }
      }
    }
  }
  // Prepare every fallible comparison before printing any normal report. The
  // baseline bytes were read once; size comparison never constructs its graph.
  let function_diff = if options.diff_functions {
    match baseline {
      Some((baseline_bytes, _)) =>
        match @lib.compare_modules(baseline_bytes, bytes) {
          Ok(diff) => Some(diff)
          Err(error) => {
            match error {
              Baseline(error) =>
                println("moonsize: baseline: \{@lib.describe_error(error)}")
              Current(error) =>
                println("moonsize: current: \{@lib.describe_error(error)}")
            }
            @sys.exit(@lib.EXIT_INPUT)
            return
          }
        }
      None => None // parse_options rejects this combination before I/O.
    }
  } else {
    None
  }
  let analysis = match @lib.analyze(bytes, parsed) {
    Ok(analysis) => analysis
    Err(error) => {
      println("moonsize: \{options.path}: \{@lib.describe_error(error)}")
      @sys.exit(@lib.EXIT_INPUT)
      return
    }
  }
  // `--strict` refuses before any output: a report is what a caller acts on, and
  // half a report with a warning on it is exactly the failure mode this flag
  // exists to rule out for a job that cannot judge the warning itself.
  if @lib.strict_exit_code(options, analysis.graph_complete) != @lib.EXIT_OK {
    println(@lib.render_graph_warning(analysis.graph))
    println("")
    println(
      "moonsize: --strict: refusing to report an incomplete call graph for " +
      options.path,
    )
    @sys.exit(@lib.EXIT_OVER_SIZE)
    return
  }
  check_outputs(options)
  if options.diff_functions_json is Some(target) &&
    function_diff is Some(diff) &&
    baseline is Some((before_bytes, _)) {
    write_output(
      target,
      @lib.render_function_diff_json(
        diff,
        diff_input_sha256(before_bytes),
        diff_input_sha256(bytes),
      ),
    )
    println("Function and package comparison written to " + target)
  }
  if options.summary_json is Some(target) {
    write_output(target, @lib.render_summary_json(analysis))
    println("Analysis summary written to " + target)
  }
  if data_details is Some(report) && options.data_json is Some(target) {
    let contents = match data_diff {
      Some(diff) =>
        @lib.render_data_segments_diff_json(
          diff,
          options.baseline.unwrap_or(""),
          options.path,
        )
      None => @lib.render_data_segments_json(report)
    }
    write_output(target, contents)
    println("Data segment details written to " + target)
  }
  if budget_report is Some(report) {
    if options.budget_json is Some(target) {
      write_output(
        target,
        @lib.render_budget_json(
          report,
          options.path,
          baseline_path?=options.baseline,
        ),
      )
    }
    if options.budget_md is Some(target) {
      write_output(
        target,
        @lib.render_budget_markdown(
          report,
          options.path,
          baseline_path?=options.baseline,
        ),
      )
    }
  }
  match options.call_graph {
    Some(target) =>
      write_output(target, @lib.render_graph(options.path, analysis, target))
    None =>
      match options.html {
        Some(target) => {
          let contents = match data_details {
            Some(report) =>
              @lib.render_html_with_data_segments(
                analysis,
                options.path,
                report,
                echarts=vendored_echarts(),
              )
            None =>
              @lib.render_html(
                analysis,
                options.path,
                echarts=vendored_echarts(),
              )
          }
          write_output(target, contents)
          println("HTML report written to " + target)
        }
        None => {
          let whole_gzip = match budget_report {
            Some(report) => report.current.gzip
            None => None
          }
          print_report(bytes, parsed, analysis, options, whole_gzip?)
        }
      }
  }
  match baseline {
    Some((_, baseline_module)) => {
      println("")
      println(@lib.render_size_comparison(baseline_module, parsed))
    }
    None => ()
  }
  if function_diff is Some(diff) {
    println("")
    println(@lib.render_function_diff(diff, options.top))
  }
  if data_details is Some(report) && options.html is None {
    println("")
    println(@lib.render_data_segments(report, options.top))
  }
  if data_diff is Some(report) {
    println("")
    println(
      @lib.render_data_segments_diff(
        report,
        options.baseline.unwrap_or(""),
        options.path,
        options.top,
      ),
    )
  }
  if budget_report is Some(report) {
    println("")
    println(@lib.render_budget(report))
    if report.exit_code != 0 {
      @sys.exit(report.exit_code)
    }
    return
  }
  // The gate is last so the report a CI log shows is the one that explains the
  // failure, and it runs whatever the output mode was: a budget is a budget.
  let code = @lib.size_exit_code(options, parsed.file_size, baseline_size)
  if code != @lib.EXIT_OK {
    println("")
    println(
      @lib.describe_size_failure(options, parsed.file_size, baseline_size),
    )
    @sys.exit(code)
  }
}
