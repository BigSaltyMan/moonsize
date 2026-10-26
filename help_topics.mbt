///|
/// One registry owns topic IDs, copy and example argv; no shell-text parsing.
priv struct HelpTopic {
  id : String
  title : String
  summary : String
  options : Array[String]
  examples : Array[Array[String]]
  limits : Array[String]
  related : Array[String]
}

///|
fn help_topics() -> Array[HelpTopic] {
  [
    {
      id: "overview",
      title: "Ordinary analysis and reports",
      summary: "Inspect sections and function/module sizes, then save a report.",
      options: [
        "--top <n>; --compress", "--html <new.html>; --summary-json <new.json>",
      ],
      examples: [
        ["moonsize", "app.wasm", "--top", "20", "--compress"],
        ["moonsize", "app.wasm", "--html", "new-report.html"],
        ["moonsize", "app.wasm", "--summary-json", "new-summary.json"],
      ],
      limits: [
        "-- ends option parsing; place a dash-prefixed input path after it (for example, moonsize -- --help). A single - is a filename, not stdin. Option value constraints are unchanged; use ./--name when needed.",
        "--summary-json does not support --baseline, --html or --compress; it exports ordinary analysis.",
        "Whole-file gzip measures one complete stream. Independent section/function gzip sizes are not additive and are not transfer shares.",
        "Top limits text display; complete JSON is not truncated. Report destinations must be new paths.",
      ],
      related: ["functions", "data", "ci"],
    },
    {
      id: "functions",
      title: "Find and explain functions",
      summary: "Locate a local index, inspect its encoding, or query model references.",
      options: [
        "--find-functions <literal>; --find-functions-json <new.json>", "--instructions <index>; --instructions-json <new.json>; --baseline-instructions <index>",
        "--callers <index>; --callers-json <new.json> (all recorded one-hop sources)",
        "--why-index <index>; --why-root <root>; --why-json <new.json> (one root-to-target path)",
        "--retained; --dead-code (ordinary analysis)", "--duplicates / --duplicates-json <new.json>; --generics / --generics-json <new.json>",
        "--entrypoints / --entrypoints-json <new.json>; --top <n> where supported",
      ],
      examples: [
        ["moonsize", "app.wasm", "--find-functions", "decode", "--top", "20"],
        [
          "moonsize", "app.wasm", "--instructions", "42", "--instructions-json",
          "new-instructions.json",
        ],
        [
          "moonsize", "app.wasm", "--why-index", "42", "--why-root", "0", "--why-json",
          "new-path.json", "--strict",
        ],
      ],
      limits: [
        "Run independent queries separately. --instructions-json requires --instructions; instruction inspection requires a local body. Imports may have no local body.",
        "--why-root must be an actual model root; element functions are conservative roots. --why-index does not accept --top.",
        "Retained, unreachable functions and reference paths belong to the current model, not execution traces or predictions of recompiled savings.",
        "--callers, --why-index and --entrypoints allow --strict. Name search, instructions, duplicates and generics do not. Retained/dead-code flags belong to ordinary analysis.",
        "Identical bodies and generic-instance totals do not prove safe merging or savings. Top limits display, not analysis cost; JSON remains complete.",
      ],
      related: ["overview", "baseline", "ci"],
    },
    {
      id: "data",
      title: "Data payloads and encoding overhead",
      summary: "Inspect data entries, group identical payloads, or compare content groups.",
      options: [
        "--find-data <UTF-8 literal>; --find-data-json <new.json>", "--data-segments; --data-json <new.json>; --top <n>",
        "--data-duplicates; --data-duplicates-json <new.json>", "--diff-data with --baseline; --html with current-input details",
      ],
      examples: [
        ["moonsize", "app.wasm", "--find-data", "assets/logo", "--top", "20"],
        [
          "moonsize", "app.wasm", "--data-duplicates-json", "new-data-duplicates.json",
        ],
        [
          "moonsize", "after.wasm", "--baseline", "before.wasm", "--diff-data", "--data-json",
          "new-data-diff.json",
        ],
      ],
      limits: [
        "File offsets are not memory addresses; payload bytes differ from full entry encodings. Offset expressions are recorded, not evaluated.",
        "--find-data is independent: only Top and its own JSON. Spaces and overlaps matter; no cross-entry matches. Query text is saved in reports. A hit is not proof of a string or used resource; compiler encodings may differ. Complete hits use memory proportional to occurrence count.",
        "Repeated payloads do not prove they can be safely merged. Content groups do not establish cross-build entry identity or deletion savings.",
        "--html accepts --data-segments or --data-json for current input only; --html --diff-data is rejected. --data-duplicates is a separate mode with Top and its own JSON only.",
        "Text Top does not truncate ledgers or complete JSON. All report targets must be new paths.",
      ],
      related: ["overview", "baseline"],
    },
    {
      id: "interfaces",
      title: "Host imports and exports",
      summary: "Inventory host declarations or compare their exact names and counts/kinds.",
      options: [
        "--imports; --imports-json <new.json>; --diff-imports with --baseline", "--exports; --exports-json <new.json>; --diff-exports with --baseline",
        "--top <n>",
      ],
      examples: [
        ["moonsize", "app.wasm", "--imports-json", "new-imports.json"],
        ["moonsize", "app.wasm", "--exports", "--top", "20"],
        [
          "moonsize", "after.wasm", "--baseline", "before.wasm", "--diff-exports",
          "--exports-json", "new-exports-diff.json",
        ],
      ],
      limits: [
        "Imports and exports are separate modes. Baseline is accepted only with the matching diff flag; --strict is rejected. Top does not truncate JSON.",
        "These are declaration bytes, not host costs or function body sizes. Full ABI, signatures, target existence and runtime use are not evaluated.",
        "Export matches use exact full names. same_kind does not mean compatible; an index change is a numeric change, not proof of target identity. Alias groups remain input-local.",
      ],
      related: ["functions", "baseline", "ci"],
    },
    {
      id: "metadata",
      title: "Custom sections and name overhead",
      summary: "Account for custom/name file bytes and compare outer encodings.",
      options: [
        "--metadata; --metadata-json <new.json>; --top <n>", "--diff-metadata with --baseline",
      ],
      examples: [
        ["moonsize", "app.wasm", "--metadata", "--top", "20"],
        ["moonsize", "app.wasm", "--metadata-json", "new-metadata.json"],
        [
          "moonsize", "after.wasm", "--baseline", "before.wasm", "--diff-metadata",
          "--metadata-json", "new-metadata-diff.json",
        ],
      ],
      limits: [
        "An outer byte ledger can be complete while internal name details are partial. Optional name-content diagnostics may still return 0; opaque content is not a parsing failure.",
        "Comparison groups outer encodings by category and exact full name, not contents or name internals. Unavailable names share an accounting bucket only; debug labels do not validate DWARF.",
        "Baseline requires --diff-metadata. Only Top and own JSON may accompany this mode (plus baseline for comparison); --strict is rejected. Top never truncates JSON or diagnostics.",
        "Same names or zero byte deltas do not prove equal contents, safe stripping or recompiled/gzip savings.",
      ],
      related: ["overview", "baseline"],
    },
    {
      id: "baseline",
      title: "Compare two builds",
      summary: "Compare files, function/package encodings, or explicitly selected functions.",
      options: [
        "--baseline <before.wasm>; --diff-functions; --diff-functions-json <new.json>",
        "--instructions <current-index>; --baseline-instructions <baseline-index>; --instructions-json <new.json>",
        "--experiment <new.json|new.html>; --experiment-context <context.json>",
        "Separate inspectors: --diff-data, --diff-imports, --diff-exports, --diff-metadata with their own JSON options",
      ],
      examples: [
        [
          "moonsize", "after.wasm", "--baseline", "before.wasm", "--diff-functions-json",
          "new-function-diff.json",
        ],
        [
          "moonsize", "after.wasm", "--instructions", "42", "--baseline", "before.wasm",
          "--baseline-instructions", "17", "--instructions-json", "new-instructions-diff.json",
        ],
        [
          "moonsize", "after.wasm", "--baseline", "before.wasm", "--experiment",
          "new-experiment.json", "--experiment-context", "context.json",
        ],
      ],
      limits: [
        "--baseline alone compares file/section totals. Diff modes require baseline; run independent comparison modes separately. --summary-json does not support baseline.",
        "Instruction comparison requires both explicit indices and baseline; it does not automatically match functions. Symbol matches may be ambiguous or missing.",
        "Experiment context is user-declared evidence, not automatically verified business behavior. Encoded differences are not source identity, ABI checks or predicted gzip savings.",
        "Top limits text only; JSON remains complete. Output paths must be new; existing destinations are refused.",
      ],
      related: ["functions", "data", "interfaces", "metadata", "ci"],
    },
    {
      id: "ci",
      title: "Budgets and automation",
      summary: "Choose a size gate, save complete evidence, and interpret exit codes.",
      options: [
        "--max-size <bytes|KB|MB|GB>; --baseline <before.wasm>", "--budget <config.json>; --budget-json <new.json>; --budget-md <new.md>",
        "--strict in supported graph-based modes; --summary-json / --diff-functions-json in their supported modes",
      ],
      examples: [
        ["moonsize", "app.wasm", "--max-size", "100KB", "--strict"],
        [
          "moonsize", "after.wasm", "--baseline", "before.wasm", "--max-size", "0B",
          "--diff-functions-json", "new-gate.json",
        ],
        [
          "moonsize", "app.wasm", "--budget", "budget.json", "--budget-json", "new-budget.json",
          "--budget-md", "new-budget.md", "--strict",
        ],
      ],
      limits: [
        "--max-size limits the whole file without baseline, and growth with baseline. --budget is separate from --max-size; growth rules need baseline. JSON/Markdown budget outputs require --budget.",
        "--strict is supported by ordinary analysis (including budgets, HTML and call-graph output), why, callers and entrypoints; it is not universal. Standalone instructions, find-functions, duplicates, generics, data-duplicates, imports, exports and metadata reject it.",
        "Exit codes: 0 completed (some inspectors may report partial/unknown information); 1 input/query/output or unavailable measurement; 2 bad arguments/configuration; 3 budget exceeded, incomplete strict graph, or path search limited.",
        "Strict refusal precedes output creation; strict success does not prove complete Wasm semantics. Top does not truncate JSON evidence. Existing files/directories/link aliases are refused; multi-output writes are not a transaction.",
      ],
      related: ["overview", "baseline", "functions"],
    },
  ]
}

///|
/// Appended to the existing usage; this is navigation, not another option table.
fn help_navigation() -> String {
  let out = StringBuilder()
  out.write_string(
    "Help (no input file):\n  moonsize --help\n  moonsize -h\n  moonsize --help-topic <topic>\n\nAvailable topics (exact lowercase IDs):\n",
  )
  for topic in help_topics() {
    out.write_string("  \{topic.id}  \{topic.title}\n")
  }
  out.to_string()
}

///|
fn help_render_topic(topic : HelpTopic) -> String {
  let out = StringBuilder()
  out.write_string(
    "\{topic.id}: \{topic.title}\n\n\{topic.summary}\n\nOptions\n",
  )
  for option in topic.options {
    out.write_string("  " + option + "\n")
  }
  out.write_string(
    "\nExamples (paths, queries, indices and budgets are placeholders, not measured results; use new output paths)\n",
  )
  for example in topic.examples {
    out.write_string("  ")
    for i in 0..<example.length() {
      if i > 0 {
        out.write_string(" ")
      }
      out.write_string(example[i])
    }
    out.write_string("\n")
  }
  out.write_string("\nLimits\n")
  for limit in topic.limits {
    out.write_string("  " + limit + "\n")
  }
  out.write_string("\nRelated topics\n")
  for id in topic.related {
    out.write_string("  moonsize --help-topic " + id + "\n")
  }
  out.write_string("\nFull option table: moonsize --help\n")
  out.to_string()
}

///|
fn help_error(reason : String) -> String {
  "moonsize: " + reason + "\n\n" + help_navigation()
}

///|
/// Args include the program name. Inspect only the first user argument;
/// business option values later in argv never trigger this entry point.
pub fn help_request(args : Array[String]) -> Result[String?, String] {
  if args.length() < 2 {
    return Ok(None)
  }
  let flag = args[1]
  if flag == "--help" || flag == "-h" {
    if args.length() != 2 {
      return Err(
        help_error(
          "--help and -h accept no extra arguments; use --help-topic <topic>",
        ),
      )
    }
    return Ok(Some(usage()))
  }
  if flag != "--help-topic" {
    return Ok(None)
  }
  if args.length() != 3 {
    return Err(
      help_error(
        "--help-topic requires exactly one topic; no extra arguments are accepted",
      ),
    )
  }
  if args[2].trim().is_empty() {
    return Err(help_error("--help-topic requires a non-empty topic"))
  }
  for topic in help_topics() {
    if topic.id == args[2] {
      return Ok(Some(help_render_topic(topic)))
    }
  }
  Err(help_error("unknown help topic " + Json::string(args[2]).stringify()))
}
