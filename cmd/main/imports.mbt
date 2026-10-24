///|
fn run_imports(options : @lib.Options) -> Unit {
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
