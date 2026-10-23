///|
/// Independent size-only path: no analyze, graph or retained computation.
fn run_generic_instances(options : @lib.Options) -> Unit {
  let report = match @lib.inspect_generic_instances(read_input(options.path)) {
    Ok(report) => report
    Err(error) => {
      println("moonsize: " + options.path + ": " + @lib.describe_error(error))
      @sys.exit(@lib.EXIT_INPUT)
      return
    }
  }
  match options.generics_json {
    Some(target) => {
      check_outputs(options)
      write_output(target, @lib.render_generic_instances_json(report))
      println("Generic instances written to " + target)
    }
    None => println(@lib.render_generic_instances(report, options.top))
  }
}
