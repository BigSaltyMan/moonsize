# Migrating from public 0.3.0 to 0.4.0

Compared the **downloaded Mooncakes 0.3.0 ZIP**, SHA-256
`60339bdfebc95cfe30948ea1ba5b5dda75e032c0b61c1956e2512d3a4719246c`,
using `moon info` on both versions with moon 0.1.20260915 / moonc
v0.10.13+cbb11c36f. This pre-1.0 minor release includes breaking library changes.

## Changed signatures

| 0.3.0 | 0.4.0 / migration |
| --- | --- |
| `build(data, bodies, elements)` | `build(data)` validates complete module bytes and obtains table imports/exports/initializers internally. Do not replace context with an empty value. |
| `compressed_size(data) -> Int` | `-> Result[Int, String]`; handle errors explicitly. |
| `render_compression(raw, gzip : Int, sections)` | `gzip : Result[Int, String]`; pass the actual measurement result. |
| `render_dead_code(stats, reachable, total, top)` | `render_dead_code(analysis, top)` preserves diagnostics. |
| `render_retained(stats, retained, reachable, total, top)` | `render_retained(analysis, top)` preserves diagnostics. |
| `Reader::read_u32_leb() -> Result[Int, WasmError]` | `Result[UInt, WasmError]`; check supported range before converting to Int. |
| `Reader::seek(offset) -> Unit` | `Result[Unit, WasmError]`; failed bounded seeks leave the cursor unchanged. |

`parse_module(data)` and `analyze(data, parsed)` keep their signatures. Analysis
revalidates bytes; stale metadata cannot bypass version, section order/uniqueness
or function/code checks. Previously accepted malformed modules can now fail.
This is basic structure checking, not full Wasm type/instruction validation.

## Additions and exhaustive matches

- `WasmError` adds bounded-read/range, unsigned conversion, version, duplicate/
  out-of-order section, function/code mismatch, trailing payload and table
  encoding errors. Update exhaustive matches; use `describe_error` for display.
  Reader adds bounded construction.
- `CallKind` adds `Reference` for unknown `call_ref`/`return_call_ref` targets.
  `scan_calls` recognizes direct/indirect tail calls with original offsets;
  `ref.func` remains a graph reference rather than a call site.
- `CallGraph` adds `diagnostics` and `unresolved_indirect`; Analysis adds
  `graph_complete` and `unresolved_count`. The latter counts **no-static-candidate
  table call sites**, not diagnostic entries. One site can have several reasons.
  Diagnostic types/source records explain reference calls, empty candidates,
  imported/exported/mutated/unknown tables and unmodeled initializers. Known
  candidate edges remain even when the graph is incomplete.
- Table imports, exports and explicit initialization are collected internally
  by safe `build(data)`; callers need no new public context object. The existing
  public `TableType` still describes reference type and limits.
- `compare_modules` / `ModuleSizeDiff` / `render_function_diff`: unique raw-symbol
  matching, function/package differences, ambiguous/unmatched identities,
  attribution coverage and code overhead.
- `check_experiment_context`, `experiment_report`, `render_experiment_html`:
  measured artifacts plus **declared** build/validation context; no execution of
  declared commands.
- `explain_function(data, target_index, root?, limits?)`: root reasons,
  opcode/offset evidence, diagnostics and deterministic bounded BFS.
  `PathFound`, `PathNotFound`, `PathSearchLimited` differ; import size is None.
  Use path renderers and `describe_function_path_error`.
- `compile_budget_text` / `compile_budget`: opaque validated `CompiledBudget`;
  `evaluate_budget` takes current bytes and optional `baseline_data`.
  `BudgetReport` distinguishes passed/exceeded/unavailable and exit 0/3/1;
  text/JSON/Markdown retain each rule's reason.

Prefer `Options::default(path)` or `parse_options(args)`. New readable fields:
`strict`, `diff_functions`, `experiment`, `experiment_context`, `why_index`,
`why_root`, `why_json`, `budget`, `budget_json`, `budget_md`.

## CLI and formats

Simple analysis/top/retained/dead-code/compress/baseline/max-size remain.
Max-size checks raw file size, or raw growth with baseline; equality passes.
Compression reports errors and independent ratios, without `SHARE(GZIP)`.
Malformed input rejection and removal of exact-savings claims are intentional.

Modes validate conflicts before reading input. Path permits only why-index,
why-root, why-json and strict. Experiments require baseline. Budget cannot
combine with max-size, path, experiment, HTML or graph export. See `usage()` and
[budgets](budgets.md). Exit 1 covers input/query/output/unavailable measurement,
2 arguments/config, 3 budget/strict/limited search. Strict refuses before report
creation. New evidence modes refuse existing paths.

These are **separate** version namespaces, currently 1:

| Format | Version field |
| --- | --- |
| Graph JSON | `schema_version` |
| HTML embedded data | `schema_version` |
| Experiment JSON | `schema_version` |
| Function-path JSON (`moonsize-function-path`) | `schema_version` |
| Budget configuration | `version` |
| Budget result JSON | `schema_version`, plus `config_version` |

Parse by format, not one global version. Diagnostics, null/error pairs and new
fields are intentional. Native CLI embeds fixed ECharts; compatible library
`render_html(analysis, path, echarts?)` still selects CDN for an empty source.
Pass source explicitly for offline library-generated reports.

## Exact-version consumer

```sh
moon add BigSaltyMan/moonsize@0.4.0
# moon.pkg: import { "BigSaltyMan/moonsize" }
moon check --target native
node scripts/verify-release-consumer.mjs 0.4.0 consumer-result.json
```

`moon add` adds a **library dependency**, not a standalone CLI. Build the CLI
from its source checkout. The fresh external consumer installs from the public
registry and executes parsing/statistics, safe build, tail-call path, diff,
experiment, Options and budgets 0/3. Exact SHA, registry checksum, consumer result
and target Linux CI are recorded in the
[0.4.0 release](https://github.com/BigSaltyMan/moonsize/releases/tag/v0.4.0).
