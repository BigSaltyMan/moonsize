///|
/// Command-line decoding.
///
/// The library owns this rather than the entry point, so the argument grammar
/// can be tested without a process around it. `main` supplies the real
/// environment and nothing else.

///|
/// What to analyze, how much of it to show, and which reports to produce.
pub struct Options {
  path : String
  top : Int
  /// Print the retained-size section.
  retained : Bool
  /// Print the dead-code section.
  dead_code : Bool
  /// Write the call graph to this path instead of printing the text report.
  call_graph : String?
  /// Write the HTML report to this path instead of printing the text report.
  html : String?
  /// The size budget: a ceiling on the file, or — when `baseline` is set — the
  /// growth the file may show over the baseline.
  max_size : Int?
  /// Compare against this module instead of checking an absolute ceiling.
  baseline : String?
  /// Append symbol-based function and package differences (requires baseline).
  diff_functions : Bool
  /// Write an optimization experiment as .html or .json (requires baseline).
  experiment : String?
  /// Optional self-reported build settings and business validation record.
  experiment_context : String?
  /// Independent function-reference path query (full function index space).
  why_index : Int?
  why_root : Int?
  why_json : String?
  /// Independent one-hop incoming instruction-reference query.
  callers_index : Int?
  callers_json : String?
  /// Independent raw-symbol generic-instance size inspection.
  generics : Bool
  generics_json : String?
  /// Independent function-export reachability and shared-byte analysis.
  entrypoints : Bool
  entrypoints_json : String?
  /// Independent exact local function-body byte comparison.
  duplicates : Bool
  duplicates_json : String?
  /// Independent custom/name physical byte accounting.
  metadata : Bool
  metadata_json : String?
  /// Independent host-import declaration byte accounting.
  imports : Bool
  imports_json : String?
  /// Compare exact host-import key multiplicities against baseline.
  diff_imports : Bool
  /// Independent exact data payload groups within the current input.
  data_duplicates : Bool
  data_duplicates_json : String?
  /// Independent selected local-function instruction encoding.
  instructions_index : Int?
  instructions_json : String?
  /// Independent literal search of available local raw/display names.
  find_functions : String?
  find_functions_json : String?
  /// Validated multi-metric budgets, with optional evidence outputs.
  budget : String?
  budget_json : String?
  budget_md : String?
  /// Print whole-file gzip and independent section gzip measurements.
  compress : Bool
  /// Append encoded data-entry details; JSON implies this flag.
  data_segments : Bool
  data_json : String?
  /// Compare exact payload groups against baseline; implies data_segments.
  diff_data : Bool
  /// Refuse to report at all when the call graph is incomplete, rather than
  /// printing the numbers with a warning above them.
  strict : Bool
}

///|
/// How many functions `--top` ranks when the flag is absent.
pub const DEFAULT_TOP : Int = 10

///|
/// The defaults `parse_options` starts from, with one flat report for the module
/// at `path`. For callers that link this module as a library instead of running
/// the CLI: every flag the command line can set is left at its absent value.
pub fn Options::default(path : String) -> Options {
  {
    path,
    top: DEFAULT_TOP,
    retained: false,
    dead_code: false,
    call_graph: None,
    html: None,
    max_size: None,
    baseline: None,
    diff_functions: false,
    experiment: None,
    experiment_context: None,
    why_index: None,
    why_root: None,
    why_json: None,
    callers_index: None,
    callers_json: None,
    generics: false,
    generics_json: None,
    entrypoints: false,
    entrypoints_json: None,
    duplicates: false,
    duplicates_json: None,
    metadata: false,
    metadata_json: None,
    imports: false,
    imports_json: None,
    diff_imports: false,
    data_duplicates: false,
    data_duplicates_json: None,
    instructions_index: None,
    instructions_json: None,
    find_functions: None,
    find_functions_json: None,
    budget: None,
    budget_json: None,
    budget_md: None,
    compress: false,
    data_segments: false,
    data_json: None,
    diff_data: false,
    strict: false,
  }
}

///|
/// A guard that keeps the decimal scan from overflowing on long input; no real
/// module has a million functions, let alone this many.
const MAX_TOP : Int = 1000000

///|
/// Function indices are not --top counts: accept the entire nonnegative Int
/// range and defer real function-space membership to the query's safe entry.
fn parse_path_index(text : String) -> Int? {
  let bytes = @utf8.encode(text)
  if bytes.is_empty() {
    return None
  }
  let mut value = 0
  for byte in bytes {
    if !is_ascii_digit(byte) {
      return None
    }
    let digit = (byte - b'0').to_int()
    if value > 214748364 || (value == 214748364 && digit > 7) {
      return None
    }
    value = value * 10 + digit
  }
  Some(value)
}

///|
/// Parse a non-negative decimal integer, or `None` for anything else.
///
/// This toolchain's core library ships no string-to-`Int` parser, and the only
/// number the CLI accepts is `--top`, so the grammar stays deliberately narrow:
/// one or more ASCII digits, saturating into a rejection rather than an
/// overflow.
pub fn parse_count(text : String) -> Int? {
  if text.length() == 0 {
    return None
  }
  let bytes = @utf8.encode(text)
  let mut value = 0
  let mut i = 0
  while i < bytes.length() {
    let digit = bytes[i]
    if !is_ascii_digit(digit) {
      return None
    }
    if value > MAX_TOP {
      return None
    }
    value = value * 10 + (digit - b'0').to_int()
    i = i + 1
  }
  Some(value)
}

///|
/// The byte for an ASCII letter's lowercase form, and anything else unchanged.
fn lower_byte(value : Byte) -> Byte {
  if value >= b'A' && value <= b'Z' {
    value + 32
  } else {
    value
  }
}

///|
/// True when `bytes` spells `text`, ignoring ASCII case.
fn suffix_is(bytes : BytesView, text : String) -> Bool {
  let candidate = @utf8.encode(text)
  if bytes.length() != candidate.length() {
    return false
  }
  let mut i = 0
  while i < bytes.length() {
    if lower_byte(bytes[i]) != lower_byte(candidate[i]) {
      return false
    }
    i = i + 1
  }
  true
}

///|
/// The multiplier a size suffix stands for.
fn size_scale(suffix : BytesView) -> Int? {
  if suffix.length() == 0 || suffix_is(suffix, "b") {
    Some(1)
  } else if suffix_is(suffix, "kb") {
    Some(1024)
  } else if suffix_is(suffix, "mb") {
    Some(1024 * 1024)
  } else if suffix_is(suffix, "gb") {
    Some(1024 * 1024 * 1024)
  } else {
    None
  }
}

///|
/// The largest size the parser will accept. `Int` is 32 bits wide here, so the
/// ceiling is what keeps a long digit run from wrapping instead of being
/// rejected; two gigabytes is far past any WebAssembly module.
const MAX_SIZE : Int = 2000000000

///|
/// Parse a byte size: a decimal count with an optional `KB`, `MB` or `GB`
/// suffix, so `--max-size 10KB` and `--max-size 1.5MB` both work.
///
/// The suffixes are binary — a KB is 1024 bytes — which is what a size report
/// means by the word. A fraction has to be followed by a suffix: `--max-size
/// 1.5` is rejected, because half a byte is not a size.
pub fn parse_size(text : String) -> Int? {
  let bytes = @utf8.encode(text)
  let end = bytes.length()
  if end == 0 {
    return None
  }
  // The suffix, when there is one, is the trailing run of letters.
  let mut count_end = end
  while count_end > 0 && is_ascii_letter(bytes[count_end - 1]) {
    count_end = count_end - 1
  }
  let scale = match size_scale(bytes[count_end:end]) {
    Some(scale) => scale
    None => return None
  }
  // The ceiling is checked before each multiply, not after: once `whole * 10`
  // has wrapped there is nothing left to compare against.
  let whole_limit = MAX_SIZE / 10
  let last_digit = MAX_SIZE % 10
  let mut whole = 0
  let mut i = 0
  while i < count_end && is_ascii_digit(bytes[i]) {
    let digit = (bytes[i] - b'0').to_int()
    if whole > whole_limit || (whole == whole_limit && digit > last_digit) {
      return None
    }
    whole = whole * 10 + digit
    i = i + 1
  }
  if i == 0 {
    return None
  }
  let mut value = whole.to_double()
  if i < count_end && bytes[i] == b'.' {
    if scale == 1 {
      return None
    }
    i = i + 1
    let mut place = 0.1
    let mut digits = 0
    while i < count_end && is_ascii_digit(bytes[i]) {
      value = value + (bytes[i] - b'0').to_int().to_double() * place
      place = place / 10.0
      digits = digits + 1
      i = i + 1
    }
    if digits == 0 {
      return None
    }
  }
  if i != count_end {
    return None
  }
  // The ceiling is checked before the conversion, because rounding a value the
  // `Int` cannot hold is what would wrap it.
  let scaled = value * scale.to_double()
  if scaled > MAX_SIZE.to_double() {
    return None
  }
  Some(scaled.to_int())
}

///|
/// Parse a full `argv`, including the program name in slot zero.
///
/// The grammar is `moonsize <file.wasm> [--top <n>] [--retained] [--dead-code]
/// [--call-graph <path>] [--html <path>] [--max-size <size>] [--baseline
/// <path.wasm>] [--diff-functions] [--compress] [--strict]`: exactly one positional path, and a repeat of a flag keeps the
/// last value. Anything else is reported as an error so a typo never silently
/// analyses the wrong thing.
///
/// `--call-graph` and `--html` each write a file rather than a report, so
/// combining either with another output mode is rejected instead of quietly
/// ignoring one of them.
pub fn parse_options(args : Array[String]) -> Result[Options, String] {
  let mut path : String? = None
  let mut top = DEFAULT_TOP
  let mut top_seen = false
  let mut retained = false
  let mut dead_code = false
  let mut call_graph : String? = None
  let mut html : String? = None
  let mut max_size : Int? = None
  let mut baseline : String? = None
  let mut diff_functions = false
  let mut experiment : String? = None
  let mut experiment_context : String? = None
  let mut why_index : Int? = None
  let mut why_root : Int? = None
  let mut why_json : String? = None
  let mut callers_index : Int? = None
  let mut callers_json : String? = None
  let mut generics = false
  let mut generics_json : String? = None
  let mut entrypoints = false
  let mut entrypoints_json : String? = None
  let mut duplicates = false
  let mut duplicates_json : String? = None
  let mut metadata = false
  let mut metadata_json : String? = None
  let mut imports = false
  let mut imports_json : String? = None
  let mut diff_imports = false
  let mut data_duplicates = false
  let mut data_duplicates_json : String? = None
  let mut instructions_index : Int? = None
  let mut instructions_json : String? = None
  let mut find_functions : String? = None
  let mut find_functions_json : String? = None
  let mut budget : String? = None
  let mut budget_json : String? = None
  let mut budget_md : String? = None
  let mut compress = false
  let mut data_segments = false
  let mut data_json : String? = None
  let mut diff_data = false
  let mut strict = false
  let mut i = 1
  while i < args.length() {
    let arg = args[i]
    if arg == "--top" {
      top_seen = true
      if i + 1 >= args.length() {
        return Err("moonsize: --top needs a number\n\n" + usage())
      }
      match parse_count(args[i + 1]) {
        Some(count) => top = count
        None =>
          return Err(
            "moonsize: --top wants a whole number, got " +
            args[i + 1] +
            "\n\n" +
            usage(),
          )
      }
      i = i + 2
    } else if arg == "--budget" ||
      arg == "--budget-json" ||
      arg == "--budget-md" {
      if i + 1 >= args.length() ||
        args[i + 1].trim().is_empty() ||
        args[i + 1].has_prefix("--") {
        return Err("moonsize: " + arg + " needs a non-empty path\n\n" + usage())
      }
      if arg == "--budget" {
        budget = Some(args[i + 1])
      } else if arg == "--budget-json" {
        budget_json = Some(args[i + 1])
      } else {
        budget_md = Some(args[i + 1])
      }
      i += 2
    } else if arg == "--find-functions" {
      if i + 1 >= args.length() ||
        args[i + 1].trim().is_empty() ||
        args[i + 1].has_prefix("--") {
        return Err(
          "moonsize: --find-functions needs a non-empty, non-whitespace query\n\n" +
          usage(),
        )
      }
      find_functions = Some(args[i + 1])
      i += 2
    } else if arg == "--find-functions-json" {
      if i + 1 >= args.length() ||
        args[i + 1].trim().is_empty() ||
        args[i + 1].has_prefix("--") {
        return Err(
          "moonsize: --find-functions-json needs a new .json path\n\n" + usage(),
        )
      }
      find_functions_json = Some(args[i + 1])
      i += 2
    } else if arg == "--instructions" {
      if i + 1 >= args.length() {
        return Err(
          "moonsize: --instructions needs a function index\n\n" + usage(),
        )
      }
      instructions_index = match parse_path_index(args[i + 1]) {
        Some(index) => Some(index)
        None =>
          return Err(
            "moonsize: --instructions wants a nonnegative function index\n\n" +
            usage(),
          )
      }
      i += 2
    } else if arg == "--instructions-json" {
      if i + 1 >= args.length() ||
        args[i + 1].trim().is_empty() ||
        args[i + 1].has_prefix("--") {
        return Err(
          "moonsize: --instructions-json needs a new .json path\n\n" + usage(),
        )
      }
      instructions_json = Some(args[i + 1])
      i += 2
    } else if arg == "--data-duplicates" {
      data_duplicates = true
      i += 1
    } else if arg == "--data-duplicates-json" {
      if i + 1 >= args.length() ||
        args[i + 1].trim().is_empty() ||
        args[i + 1].has_prefix("--") {
        return Err(
          "moonsize: --data-duplicates-json needs a new .json path\n\n" +
          usage(),
        )
      }
      data_duplicates = true
      data_duplicates_json = Some(args[i + 1])
      i += 2
    } else if arg == "--diff-imports" {
      diff_imports = true
      imports = true
      i += 1
    } else if arg == "--imports" {
      imports = true
      i += 1
    } else if arg == "--imports-json" {
      if i + 1 >= args.length() ||
        args[i + 1].trim().is_empty() ||
        args[i + 1].has_prefix("--") {
        return Err(
          "moonsize: --imports-json needs a new .json path\n\n" + usage(),
        )
      }
      imports = true
      imports_json = Some(args[i + 1])
      i += 2
    } else if arg == "--metadata" {
      metadata = true
      i += 1
    } else if arg == "--metadata-json" {
      if i + 1 >= args.length() ||
        args[i + 1].trim().is_empty() ||
        args[i + 1].has_prefix("--") {
        return Err(
          "moonsize: --metadata-json needs a new .json path\n\n" + usage(),
        )
      }
      metadata = true
      metadata_json = Some(args[i + 1])
      i += 2
    } else if arg == "--duplicates" {
      duplicates = true
      i += 1
    } else if arg == "--duplicates-json" {
      if i + 1 >= args.length() ||
        args[i + 1].trim().is_empty() ||
        args[i + 1].has_prefix("--") {
        return Err(
          "moonsize: --duplicates-json needs a new .json path\n\n" + usage(),
        )
      }
      duplicates = true
      duplicates_json = Some(args[i + 1])
      i += 2
    } else if arg == "--entrypoints" {
      entrypoints = true
      i += 1
    } else if arg == "--entrypoints-json" {
      if i + 1 >= args.length() ||
        args[i + 1].trim().is_empty() ||
        args[i + 1].has_prefix("--") {
        return Err(
          "moonsize: --entrypoints-json needs a new .json path\n\n" + usage(),
        )
      }
      entrypoints = true
      entrypoints_json = Some(args[i + 1])
      i += 2
    } else if arg == "--generics" {
      generics = true
      i += 1
    } else if arg == "--generics-json" {
      if i + 1 >= args.length() ||
        args[i + 1].trim().is_empty() ||
        args[i + 1].has_prefix("--") {
        return Err(
          "moonsize: --generics-json needs a new .json path\n\n" + usage(),
        )
      }
      generics = true
      generics_json = Some(args[i + 1])
      i += 2
    } else if arg == "--callers" {
      if i + 1 >= args.length() {
        return Err("moonsize: --callers needs an index\n\n" + usage())
      }
      match parse_path_index(args[i + 1]) {
        Some(index) => callers_index = Some(index)
        None =>
          return Err(
            "moonsize: --callers wants a nonnegative function index\n\n" +
            usage(),
          )
      }
      i += 2
    } else if arg == "--callers-json" {
      if i + 1 >= args.length() ||
        args[i + 1].trim().is_empty() ||
        args[i + 1].has_prefix("--") {
        return Err(
          "moonsize: --callers-json needs a new .json path\n\n" + usage(),
        )
      }
      callers_json = Some(args[i + 1])
      i += 2
    } else if arg == "--why-index" || arg == "--why-root" {
      if i + 1 >= args.length() {
        return Err("moonsize: " + arg + " needs an index\n\n" + usage())
      }
      let index = match parse_path_index(args[i + 1]) {
        Some(index) => index
        None =>
          return Err(
            "moonsize: " +
            arg +
            " wants a nonnegative function index\n\n" +
            usage(),
          )
      }
      if arg == "--why-index" {
        why_index = Some(index)
      } else {
        why_root = Some(index)
      }
      i += 2
    } else if arg == "--why-json" {
      if i + 1 >= args.length() {
        return Err("moonsize: --why-json needs a .json path\n\n" + usage())
      }
      why_json = Some(args[i + 1])
      i += 2
    } else if arg == "--diff-data" {
      diff_data = true
      data_segments = true
      i += 1
    } else if arg == "--data-segments" {
      data_segments = true
      i += 1
    } else if arg == "--data-json" {
      if i + 1 >= args.length() ||
        args[i + 1].trim().is_empty() ||
        args[i + 1].has_prefix("--") {
        return Err("moonsize: --data-json needs a new .json path\n\n" + usage())
      }
      data_json = Some(args[i + 1])
      data_segments = true
      i += 2
    } else if arg == "--retained" {
      retained = true
      i = i + 1
    } else if arg == "--dead-code" {
      dead_code = true
      i = i + 1
    } else if arg == "--call-graph" {
      if i + 1 >= args.length() {
        return Err("moonsize: --call-graph needs a path\n\n" + usage())
      }
      call_graph = Some(args[i + 1])
      i = i + 2
    } else if arg == "--html" {
      if i + 1 >= args.length() {
        return Err("moonsize: --html needs a path\n\n" + usage())
      }
      html = Some(args[i + 1])
      i = i + 2
    } else if arg == "--max-size" {
      if i + 1 >= args.length() {
        return Err("moonsize: --max-size needs a size\n\n" + usage())
      }
      match parse_size(args[i + 1]) {
        Some(size) => max_size = Some(size)
        None =>
          return Err(
            "moonsize: --max-size wants a byte count, optionally with a KB, MB or GB suffix, got " +
            args[i + 1] +
            "\n\n" +
            usage(),
          )
      }
      i = i + 2
    } else if arg == "--experiment" || arg == "--experiment-context" {
      if i + 1 >= args.length() {
        return Err("moonsize: " + arg + " needs a path\n\n" + usage())
      }
      if arg == "--experiment" {
        experiment = Some(args[i + 1])
      } else {
        experiment_context = Some(args[i + 1])
      }
      i = i + 2
    } else if arg == "--diff-functions" {
      diff_functions = true
      i = i + 1
    } else if arg == "--compress" {
      compress = true
      i = i + 1
    } else if arg == "--strict" {
      strict = true
      i = i + 1
    } else if arg == "--baseline" {
      if i + 1 >= args.length() {
        return Err("moonsize: --baseline needs a path\n\n" + usage())
      }
      baseline = Some(args[i + 1])
      i = i + 2
    } else if path is None {
      path = Some(arg)
      i = i + 1
    } else {
      return Err("moonsize: unexpected argument " + arg + "\n\n" + usage())
    }
  }
  let path = match path {
    Some(path) => path
    None => return Err(usage())
  }
  if find_functions_json is Some(_) && find_functions is None {
    return Err(
      "moonsize: --find-functions-json requires --find-functions\n\n" + usage(),
    )
  }
  if find_functions is Some(_) {
    if retained ||
      dead_code ||
      compress ||
      strict ||
      data_segments ||
      diff_data ||
      diff_functions ||
      generics ||
      entrypoints ||
      duplicates ||
      metadata ||
      imports ||
      diff_imports ||
      data_duplicates ||
      data_json is Some(_) ||
      html is Some(_) ||
      call_graph is Some(_) ||
      baseline is Some(_) ||
      max_size is Some(_) ||
      experiment is Some(_) ||
      experiment_context is Some(_) ||
      why_index is Some(_) ||
      why_root is Some(_) ||
      why_json is Some(_) ||
      callers_index is Some(_) ||
      callers_json is Some(_) ||
      instructions_index is Some(_) ||
      instructions_json is Some(_) ||
      budget is Some(_) ||
      budget_json is Some(_) ||
      budget_md is Some(_) {
      return Err(
        "moonsize: --find-functions is an independent mode; only --top and --find-functions-json may be combined with it\n\n" +
        usage(),
      )
    }
    if find_functions_json is Some(target) && !target.has_suffix(".json") {
      return Err(
        "moonsize: --find-functions-json wants a .json path\n\n" + usage(),
      )
    }
  }
  if instructions_json is Some(_) && instructions_index is None {
    return Err(
      "moonsize: --instructions-json requires --instructions\n\n" + usage(),
    )
  }
  if instructions_index is Some(_) {
    if retained ||
      dead_code ||
      compress ||
      strict ||
      data_segments ||
      diff_data ||
      diff_functions ||
      generics ||
      entrypoints ||
      duplicates ||
      metadata ||
      imports ||
      diff_imports ||
      data_duplicates ||
      data_json is Some(_) ||
      html is Some(_) ||
      call_graph is Some(_) ||
      baseline is Some(_) ||
      max_size is Some(_) ||
      experiment is Some(_) ||
      experiment_context is Some(_) ||
      why_index is Some(_) ||
      why_root is Some(_) ||
      why_json is Some(_) ||
      callers_index is Some(_) ||
      callers_json is Some(_) ||
      budget is Some(_) ||
      budget_json is Some(_) ||
      budget_md is Some(_) {
      return Err(
        "moonsize: --instructions is an independent mode; only --top and --instructions-json may be combined with it\n\n" +
        usage(),
      )
    }
    if instructions_json is Some(target) && !target.has_suffix(".json") {
      return Err(
        "moonsize: --instructions-json wants a .json path\n\n" + usage(),
      )
    }
  }
  if data_duplicates {
    if retained ||
      dead_code ||
      compress ||
      strict ||
      data_segments ||
      diff_data ||
      diff_functions ||
      generics ||
      entrypoints ||
      duplicates ||
      metadata ||
      imports ||
      diff_imports ||
      data_json is Some(_) ||
      html is Some(_) ||
      call_graph is Some(_) ||
      baseline is Some(_) ||
      max_size is Some(_) ||
      experiment is Some(_) ||
      experiment_context is Some(_) ||
      why_index is Some(_) ||
      why_root is Some(_) ||
      why_json is Some(_) ||
      callers_index is Some(_) ||
      callers_json is Some(_) ||
      budget is Some(_) ||
      budget_json is Some(_) ||
      budget_md is Some(_) {
      return Err(
        "moonsize: --data-duplicates is an independent mode; only --top and --data-duplicates-json may be combined with it\n\n" +
        usage(),
      )
    }
    if data_duplicates_json is Some(target) && !target.has_suffix(".json") {
      return Err(
        "moonsize: --data-duplicates-json wants a .json path\n\n" + usage(),
      )
    }
  }
  if diff_imports {
    match baseline {
      Some(target) if !target.trim().is_empty() && !target.has_prefix("--") =>
        ()
      _ =>
        return Err(
          "moonsize: --diff-imports requires --baseline with a non-empty path\n\n" +
          usage(),
        )
    }
  }
  if imports {
    if retained ||
      dead_code ||
      compress ||
      strict ||
      data_segments ||
      diff_data ||
      diff_functions ||
      generics ||
      entrypoints ||
      duplicates ||
      metadata ||
      html is Some(_) ||
      call_graph is Some(_) ||
      (baseline is Some(_) && !diff_imports) ||
      max_size is Some(_) ||
      experiment is Some(_) ||
      experiment_context is Some(_) ||
      why_index is Some(_) ||
      why_root is Some(_) ||
      why_json is Some(_) ||
      callers_index is Some(_) ||
      callers_json is Some(_) ||
      budget is Some(_) ||
      budget_json is Some(_) ||
      budget_md is Some(_) {
      return Err(
        "moonsize: --imports is an independent mode; only --top, --imports-json and --baseline with --diff-imports may be combined with it\n\n" +
        usage(),
      )
    }
    if imports_json is Some(target) && !target.has_suffix(".json") {
      return Err("moonsize: --imports-json wants a .json path\n\n" + usage())
    }
  }
  if metadata {
    if retained ||
      dead_code ||
      compress ||
      strict ||
      data_segments ||
      diff_data ||
      diff_functions ||
      generics ||
      entrypoints ||
      duplicates ||
      html is Some(_) ||
      call_graph is Some(_) ||
      baseline is Some(_) ||
      max_size is Some(_) ||
      experiment is Some(_) ||
      experiment_context is Some(_) ||
      why_index is Some(_) ||
      why_root is Some(_) ||
      why_json is Some(_) ||
      callers_index is Some(_) ||
      callers_json is Some(_) ||
      budget is Some(_) ||
      budget_json is Some(_) ||
      budget_md is Some(_) {
      return Err(
        "moonsize: --metadata is an independent mode; only --top and --metadata-json may be combined with it\n\n" +
        usage(),
      )
    }
    if metadata_json is Some(target) && !target.has_suffix(".json") {
      return Err("moonsize: --metadata-json wants a .json path\n\n" + usage())
    }
  }
  if duplicates {
    if retained ||
      dead_code ||
      compress ||
      strict ||
      data_segments ||
      diff_data ||
      diff_functions ||
      generics ||
      entrypoints ||
      html is Some(_) ||
      call_graph is Some(_) ||
      baseline is Some(_) ||
      max_size is Some(_) ||
      experiment is Some(_) ||
      experiment_context is Some(_) ||
      why_index is Some(_) ||
      why_root is Some(_) ||
      why_json is Some(_) ||
      callers_index is Some(_) ||
      callers_json is Some(_) ||
      budget is Some(_) ||
      budget_json is Some(_) ||
      budget_md is Some(_) {
      return Err(
        "moonsize: --duplicates is an independent mode; only --top and --duplicates-json may be combined with it\n\n" +
        usage(),
      )
    }
    if duplicates_json is Some(target) && !target.has_suffix(".json") {
      return Err("moonsize: --duplicates-json wants a .json path\n\n" + usage())
    }
  }
  if entrypoints {
    if retained ||
      dead_code ||
      compress ||
      data_segments ||
      diff_data ||
      diff_functions ||
      generics ||
      html is Some(_) ||
      call_graph is Some(_) ||
      baseline is Some(_) ||
      max_size is Some(_) ||
      experiment is Some(_) ||
      experiment_context is Some(_) ||
      why_index is Some(_) ||
      why_root is Some(_) ||
      why_json is Some(_) ||
      callers_index is Some(_) ||
      callers_json is Some(_) ||
      budget is Some(_) ||
      budget_json is Some(_) ||
      budget_md is Some(_) {
      return Err(
        "moonsize: --entrypoints is an independent mode; only --top, --entrypoints-json and --strict may be combined with it\n\n" +
        usage(),
      )
    }
    if entrypoints_json is Some(target) && !target.has_suffix(".json") {
      return Err(
        "moonsize: --entrypoints-json wants a .json path\n\n" + usage(),
      )
    }
  }
  if generics {
    if retained ||
      dead_code ||
      compress ||
      strict ||
      data_segments ||
      diff_data ||
      diff_functions ||
      html is Some(_) ||
      call_graph is Some(_) ||
      baseline is Some(_) ||
      max_size is Some(_) ||
      experiment is Some(_) ||
      experiment_context is Some(_) ||
      why_index is Some(_) ||
      why_root is Some(_) ||
      why_json is Some(_) ||
      callers_index is Some(_) ||
      callers_json is Some(_) ||
      budget is Some(_) ||
      budget_json is Some(_) ||
      budget_md is Some(_) {
      return Err(
        "moonsize: --generics is an independent mode; only --top and --generics-json may be combined with it\n\n" +
        usage(),
      )
    }
    if generics_json is Some(target) && !target.has_suffix(".json") {
      return Err("moonsize: --generics-json wants a .json path\n\n" + usage())
    }
  }
  if callers_json is Some(_) && callers_index is None {
    return Err("moonsize: --callers-json requires --callers\n\n" + usage())
  }
  if callers_index is Some(_) {
    if retained ||
      dead_code ||
      compress ||
      data_segments ||
      diff_data ||
      diff_functions ||
      html is Some(_) ||
      call_graph is Some(_) ||
      baseline is Some(_) ||
      max_size is Some(_) ||
      experiment is Some(_) ||
      experiment_context is Some(_) ||
      why_index is Some(_) ||
      why_root is Some(_) ||
      why_json is Some(_) ||
      budget is Some(_) ||
      budget_json is Some(_) ||
      budget_md is Some(_) {
      return Err(
        "moonsize: --callers is an independent query mode; only --top, --callers-json and --strict may be combined with it\n\n" +
        usage(),
      )
    }
    if callers_json is Some(target) && !target.has_suffix(".json") {
      return Err("moonsize: --callers-json wants a .json path\n\n" + usage())
    }
  }
  if diff_data {
    match baseline {
      Some(target) if !target.trim().is_empty() && !target.has_prefix("--") =>
        ()
      _ =>
        return Err(
          "moonsize: --diff-data requires --baseline with a non-empty path\n\n" +
          usage(),
        )
    }
  }
  if data_segments {
    if (html is Some(_) && diff_data) ||
      call_graph is Some(_) ||
      experiment is Some(_) ||
      experiment_context is Some(_) ||
      why_index is Some(_) ||
      why_root is Some(_) ||
      why_json is Some(_) ||
      budget is Some(_) ||
      budget_json is Some(_) ||
      budget_md is Some(_) ||
      diff_functions {
      return Err(
        "moonsize: data segment details cannot be combined with --call-graph, --experiment, function-path queries, --budget or --diff-functions; --html only accepts current-input details, not --diff-data\n\n" +
        usage(),
      )
    }
    if data_json is Some(target) && !target.has_suffix(".json") {
      return Err("moonsize: --data-json wants a .json path\n\n" + usage())
    }
  }
  if budget is None && (budget_json is Some(_) || budget_md is Some(_)) {
    return Err(
      "moonsize: --budget-json and --budget-md require --budget\n\n" + usage(),
    )
  }
  if budget is Some(_) {
    if max_size is Some(_) ||
      why_index is Some(_) ||
      why_root is Some(_) ||
      why_json is Some(_) ||
      experiment is Some(_) ||
      experiment_context is Some(_) ||
      html is Some(_) ||
      call_graph is Some(_) {
      return Err(
        "moonsize: --budget cannot be combined with --max-size, function-path queries, --experiment, --html or --call-graph\n\n" +
        usage(),
      )
    }
    if budget_json is Some(target) && !target.has_suffix(".json") {
      return Err("moonsize: --budget-json wants a .json path\n\n" + usage())
    }
    if budget_md is Some(target) && !target.has_suffix(".md") {
      return Err("moonsize: --budget-md wants a .md path\n\n" + usage())
    }
    if baseline is Some(target) &&
      (target.trim().is_empty() || target.has_prefix("--")) {
      return Err("moonsize: --baseline needs a non-empty path\n\n" + usage())
    }
    if path.trim().is_empty() {
      return Err("moonsize: input path must not be empty\n\n" + usage())
    }
  }
  if why_index is None && (why_root is Some(_) || why_json is Some(_)) {
    return Err(
      "moonsize: --why-root and --why-json require --why-index\n\n" + usage(),
    )
  }
  if why_index is Some(_) {
    if top_seen ||
      html is Some(_) ||
      call_graph is Some(_) ||
      experiment is Some(_) ||
      experiment_context is Some(_) ||
      retained ||
      dead_code ||
      compress ||
      diff_functions ||
      baseline is Some(_) ||
      max_size is Some(_) {
      return Err(
        "moonsize: --why-index is an independent query mode; only --why-root, --why-json and --strict may be combined with it\n\n" +
        usage(),
      )
    }
    if why_json is Some(target) && !target.has_suffix(".json") {
      return Err("moonsize: --why-json wants a .json path\n\n" + usage())
    }
  }
  if experiment_context is Some(_) && experiment is None {
    return Err(
      "moonsize: --experiment-context requires --experiment\n\n" + usage(),
    )
  }
  if experiment is Some(target) {
    if baseline is None {
      return Err("moonsize: --experiment requires --baseline\n\n" + usage())
    }
    if !(target.has_suffix(".json") || target.has_suffix(".html")) {
      return Err(
        "moonsize: --experiment wants a .json or .html path\n\n" + usage(),
      )
    }
    if html is Some(_) ||
      call_graph is Some(_) ||
      retained ||
      dead_code ||
      compress ||
      diff_functions {
      return Err(
        "moonsize: --experiment includes its own measurements; cannot combine with --html, --call-graph, --retained, --dead-code, --compress or --diff-functions\n\n" +
        usage(),
      )
    }
  }
  if diff_functions && baseline is None {
    return Err("moonsize: --diff-functions requires --baseline\n\n" + usage())
  }
  if diff_functions && (html is Some(_) || call_graph is Some(_)) {
    return Err(
      "moonsize: --diff-functions cannot be combined with --html or --call-graph\n\n" +
      usage(),
    )
  }
  match call_graph {
    Some(target) =>
      if retained || dead_code || html is Some(_) {
        return Err(
          "moonsize: --call-graph writes the graph to " +
          target +
          ", so it cannot be combined with --retained, --dead-code or --html\n\n" +
          usage(),
        )
      }
    None => ()
  }
  match html {
    Some(target) =>
      if retained || dead_code {
        return Err(
          "moonsize: --html writes the report to " +
          target +
          ", so it cannot be combined with --retained or --dead-code\n\n" +
          usage(),
        )
      }
    None => ()
  }
  Ok({
    path,
    top,
    retained,
    dead_code,
    call_graph,
    html,
    max_size,
    baseline,
    diff_functions,
    experiment,
    experiment_context,
    why_index,
    why_root,
    why_json,
    callers_index,
    callers_json,
    generics,
    generics_json,
    entrypoints,
    entrypoints_json,
    duplicates,
    duplicates_json,
    metadata,
    metadata_json,
    imports,
    imports_json,
    diff_imports,
    data_duplicates,
    data_duplicates_json,
    instructions_index,
    instructions_json,
    find_functions,
    find_functions_json,
    budget,
    budget_json,
    budget_md,
    compress,
    data_segments,
    data_json,
    diff_data,
    strict,
  })
}
