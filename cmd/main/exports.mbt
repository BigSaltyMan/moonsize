///|
fn run_exports(options : @lib.Options) -> Unit {
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
