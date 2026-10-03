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
/// Everything the tool does lives in the library, so it can be tested without a
/// process around it. This entry point only supplies the real environment: the
/// command line and the filesystem.
fn main {
  match @lib.parse_options(@env.args()) {
    Err(message) => {
      println(message)
      @sys.exit(2)
    }
    Ok(options) => {
      let bytes = read_input(options.path)
      match @lib.parse_module(bytes) {
        Err(error) => {
          println("moonsize: \{options.path}: \{@lib.describe_error(error)}")
          @sys.exit(1)
        }
        Ok(parsed) =>
          match @lib.analyze(bytes, parsed) {
            Err(error) => {
              println(
                "moonsize: \{options.path}: \{@lib.describe_error(error)}",
              )
              @sys.exit(1)
            }
            Ok(analysis) =>
              match options.call_graph {
                Some(target) =>
                  write_output(
                    target,
                    @lib.render_graph(options.path, analysis, target),
                  )
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
                    None => {
                      println(@lib.format_report(parsed, options.path))
                      println("")
                      println(
                        @lib.render_top_functions(
                          analysis.stats,
                          parsed.file_size,
                          options.top,
                        ),
                      )
                      println("")
                      println(
                        @lib.render_module_summary(
                          analysis.stats,
                          parsed.file_size,
                        ),
                      )
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
                  }
              }
          }
      }
    }
  }
}
