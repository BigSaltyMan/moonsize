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
fn read_baseline(options : @lib.Options) -> @lib.WasmModule? {
  match options.baseline {
    None => None
    Some(target) =>
      match @lib.parse_module(read_input(target)) {
        Ok(parsed) => Some(parsed)
        Err(error) => {
          println("moonsize: \{target}: \{@lib.describe_error(error)}")
          @sys.exit(1)
          None
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
  parsed : @lib.WasmModule,
  analysis : @lib.Analysis,
  options : @lib.Options,
) -> Unit {
  println(@lib.format_report(parsed, options.path))
  println("")
  println(
    @lib.render_top_functions(analysis.stats, parsed.file_size, options.top),
  )
  println("")
  println(@lib.render_module_summary(analysis.stats, parsed.file_size))
  if options.retained {
    println("")
    println(
      @lib.render_retained(
        analysis.stats,
        analysis.retained,
        analysis.indirect,
        parsed.file_size,
        options.top,
      ),
    )
  }
  if options.dead_code {
    println("")
    println(
      @lib.render_dead_code(
        analysis.stats,
        analysis.reachable,
        parsed.file_size,
        options.top,
      ),
    )
  }
}

///|
/// Everything the tool does lives in the library, so it can be tested without a
/// process around it. This entry point only supplies the real environment: the
/// command line and the filesystem.
fn main {
  let options = match @lib.parse_options(@env.args()) {
    Ok(options) => options
    Err(message) => {
      println(message)
      @sys.exit(@lib.EXIT_USAGE)
      return
    }
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
    Some(baseline_module) => Some(baseline_module.file_size)
    None => None
  }
  let analysis = match @lib.analyze(bytes, parsed) {
    Ok(analysis) => analysis
    Err(error) => {
      println("moonsize: \{options.path}: \{@lib.describe_error(error)}")
      @sys.exit(@lib.EXIT_INPUT)
      return
    }
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
        None => print_report(parsed, analysis, options)
      }
  }
  match baseline {
    Some(baseline_module) => {
      println("")
      println(@lib.render_size_comparison(baseline_module, parsed))
    }
    None => ()
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
