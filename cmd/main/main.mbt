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
        Ok(parsed) => {
          println(@lib.format_report(parsed, options.path))
          match @lib.collect_function_stats(parsed, bytes) {
            Err(error) => {
              println(
                "moonsize: \{options.path}: \{@lib.describe_error(error)}",
              )
              @sys.exit(1)
            }
            Ok(stats) => {
              println("")
              println(
                @lib.render_top_functions(stats, parsed.file_size, options.top),
              )
              println("")
              println(@lib.render_module_summary(stats, parsed.file_size))
            }
          }
        }
      }
    }
  }
}
