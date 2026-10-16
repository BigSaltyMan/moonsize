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
/// Write an export to disk, reporting failure and exiting when it cannot.
fn write_output(path : String, contents : String) -> Unit {
  @fs.write_string_to_file(path, contents) catch {
    _ => {
      println("moonsize: cannot write \{path}")
      @sys.exit(1)
    }
  }
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
          println("moonsize: \{target}: \{@lib.describe_error(error)}")
          @sys.exit(1)
          None
        }
      }
    }
  }
}

///|
/// The vendored chart library, or an empty string when it is not there.
///
/// The report is generated with the library inlined, so it opens offline from
/// anywhere. When the checkout's `assets/` directory is not next to the working
/// directory the report falls back to a CDN script tag, which still renders but
/// needs a network connection; saying so once is better than producing a page
/// that silently shows empty boxes.
fn read_echarts() -> String {
  let candidates = [
    "assets/echarts.min.js", "../assets/echarts.min.js", "../../assets/echarts.min.js",
  ]
  let mut found = ""
  let mut i = 0
  while i < candidates.length() && found.length() == 0 {
    try {
      found = @fs.read_file_to_string(candidates[i])
    } catch {
      _ => ()
    }
    i = i + 1
  }
  if found.length() == 0 {
    println(
      "moonsize: assets/echarts.min.js not found; the report will load ECharts from a CDN",
    )
  }
  found
}

///|
/// The text report: the section table, the function ranking, the module summary,
/// and whichever optional sections were asked for.
fn print_report(
  bytes : Bytes,
  parsed : @lib.WasmModule,
  analysis : @lib.Analysis,
  options : @lib.Options,
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
        @lib.compressed_size(bytes),
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
  if @fs.path_exists(target) {
    println("moonsize: experiment output already exists: " + target)
    @sys.exit(@lib.EXIT_INPUT)
    return
  }
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
      if @fs.path_exists(target) {
        println("moonsize: path query output already exists: " + target)
        @sys.exit(@lib.EXIT_INPUT)
        return
      }
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
/// Supply command-line arguments and filesystem access to the library.
fn main {
  let options = match @lib.parse_options(@env.args()) {
    Ok(options) => options
    Err(message) => {
      println(message)
      @sys.exit(@lib.EXIT_USAGE)
      return
    }
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
  match options.call_graph {
    Some(target) =>
      write_output(target, @lib.render_graph(options.path, analysis, target))
    None =>
      match options.html {
        Some(target) => {
          let contents = @lib.render_html(
            analysis,
            options.path,
            echarts=read_echarts(),
          )
          write_output(target, contents)
          println("HTML report written to " + target)
        }
        None => print_report(bytes, parsed, analysis, options)
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
