# Multi-metric byte budgets

```sh
moonsize after.wasm --baseline before.wasm --budget moonsize-budget.json \
  --budget-json budget-result.json --budget-md budget-summary.md
```

Configuration version 1 accepts only `version` and a nonempty `rules` array.
Each rule has a nonempty unique `id`, `metric`, `mode`, `max_bytes`, and (only for
`package.raw`) a nonempty `package`. Unknown fields, types and unsupported values
are errors. Numeric JSON tokens must be nonnegative decimal integers from 0 to
2147483647: zero is valid; fractions, exponents, negatives and overflow are rejected.
Source preflight checks the token as well as the JSON value, so a tiny fractional
part rounded away by a floating-point JSON parser cannot pass as an integer.

[`examples/budget.json`](../examples/budget.json) is executable against the real
source demo. Its package label is `demo::budgetdemo`; replace it with an actual
module label from your own report, not a source directory guess.
[`examples/ci-budget.json`](../examples/ci-budget.json) contains only file/code
absolute rules and is used for this repository's freshly built example.

| Metric | Bytes measured |
| --- | --- |
| `file.raw` | Complete input artifact |
| `file.gzip` | Complete file compressed as one gzip stream, using the current `bikallem/compress` defaults |
| `code.raw` | Complete code section: id, size prefix, function count and function encodings |
| `package.raw` | Local function `total_size` summed under an exact existing module label, including body size prefixes |

Absolute rules pass when `current <= max_bytes`; growth rules pass when
`current - baseline <= max_bytes`. Equality passes, shrinkage keeps a negative
delta, and an empty module has a true zero code size. There is no division or
percentage budget. Growth requires `--baseline`, checked after configuration
preflight but before reading Wasm. Configuration failures also precede business
input I/O. `--max-size` keeps its prior units and behavior and conflicts with
`--budget`.

Each required side/metric is measured once per budget evaluation, shared by all
rules. Only growth rules request baseline measurements; an absolute package rule
does not request baseline attribution just because another rule measures file
growth. Whole-file gzip is reused by the CLI compression view when already
measured. Independent section/function streams are never added. The budget
evaluator does no graph or dominator computation; ordinary CLI reports and strict
checking still use the existing analysis pipeline, once rather than per rule.

## Package coverage and missing values

Labels use the existing best-effort binary symbol attribution. This measures
attributed function encodings, not complete source-package cost or savings from
deleting a package. Missing/empty/damaged function names and unrecognized MoonBit
mangled symbols leave possible ownership unresolved. If any local function is
unassigned, a selected package's complete size cannot be confirmed, so that rule
is `unavailable`, even if some named functions match the label. Function counts
and unassigned encoded bytes are recorded per required side. Plain named symbols
continue to use the existing labels, including `(top-level)`.

With sufficient coverage, an absolute package rule requires the label to exist
in current. For growth, if the label exists on either side, absence on the other
side contributes zero and is explicitly described as newly observed/disappeared.
If it appears on neither side, the rule is unavailable; a typo cannot silently
pass with two zeros. Presence flags mean **observed** presence, interpreted with
coverage. Disappearance does not prove source removal. No similar-name matching
is performed.

Every rule retains current, baseline, delta, limit, status and reason. Failed or
unrequested values are null, never substitute zero/raw values. Successful file,
code and gzip measurements survive a package coverage failure. A compressor
failure stays unavailable and includes its actual error.

## Reports and exits

The CLI appends an English budget table to ordinary text output. It accepts
`--top`, `--compress`, `--retained`, `--dead-code`, `--diff-functions` and strict
where applicable; path queries, experiments, HTML and call-graph exports are
conflicting modes, rejected before input I/O. `--budget-json` and `--budget-md`
require `--budget` and `.json`/`.md` destinations. Both may be requested together.

| Outcome | Exit |
| --- | ---: |
| Every rule is evaluable and passed | 0 |
| Input/parsing/measurement/attribution/output error | 1 |
| Configuration or argument error | 2 |
| All rules evaluable, at least one exceeded; or existing strict refusal | 3 |

Unavailable has precedence over exceeded: both rule results/reasons remain, but
the process returns 1. Completed budget failures may save explanatory reports.
Strict refusal occurs before normal text or report writes, even with existing
destinations. All destinations are checked before either write; existing files,
directories, configuration/input aliases and evidence paths are refused. Files
written successfully before a later I/O error can remain; exit 1 and the failed
path are reported, with no claim of complete success.

JSON has its own `format: "moonsize-budget"`, `schema_version: 1` and
`config_version: 1`. It includes actual SHA-256 identities, paths, whole-file
measurements/errors, attribution coverage, observed label presence, every rule,
overall status, exit code and metric/compressor scope. Markdown contains a rule
table, reasons, identities, coverage and scope. User text is escaped for pipes,
line breaks, backticks and HTML/Markdown syntax. Nothing posts PR comments or
sends external messages.

## Library and migration

`compile_budget(Json)` returns either opaque `CompiledBudget` or all
`BudgetProblem` records (rule index, field, reason). The compiled rules are not
externally accessible or mutable. Use `compile_budget_text(String)` for source
JSON preflight with exact integer-token checking. `budget_requires_baseline`
supports I/O preflight. `evaluate_budget(compiled, current_data, baseline_data?)`
returns `Result[BudgetReport, BudgetError]`; parse errors identify current or
baseline, whereas per-rule unavailability stays in a report with exit 1.
`describe_budget_error`, `render_budget`, `render_budget_json` and
`render_budget_markdown` support consumers. The two structured renderers accept
current path and optional baseline path; paths label bytes, not inferred inputs.
The library ignores an unneeded baseline for absolute-only rules. A CLI baseline
still participates in its ordinary comparison and must be valid.

`Options` adds optional `budget`, `budget_json`, `budget_md` fields, all None by
default. Existing parsing/analysis/graph/compression/comparison signatures remain
unchanged. Match the new budget status/error enums explicitly when consuming them.

## Real source demonstration and CI

```sh
moon build --target native --release
node scripts/test-budget.mjs _build/native/release/build/cmd/main/main.exe
node scripts/demo-budget.mjs _build/native/release/build/cmd/main/main.exe

_build/native/release/build/cmd/main/main.exe _build/budget-demo/after.wasm \
  --baseline _build/budget-demo/before.wasm --budget examples/budget.json
```

The demo builds one isolated MoonBit project with wasm/debug/no-strip, adds
optional output, rebuilds, measures all four metrics, checks exact pass/refusal
codes 0/3, then rolls back and verifies identical Wasm bytes, outputs and budget
rules. Base output is preserved; optional output is deliberately added, so this
is not full behavioral equivalence. Thresholds are derived from actual artifacts,
not invented platform-independent gzip sizes. It separately confirms an input
error returns 1. Sources, commands, toolchain, hashes, Wasm, JSON and Markdown
stay in `_build/budget-demo/`, uploaded by CI.

The size-budget job still checks the newly built `$EXAMPLE` and retains legacy
100KB/0B checks. It additionally applies `examples/ci-budget.json`, uploads its
JSON/Markdown evidence and appends the generated Markdown to `GITHUB_STEP_SUMMARY`.
No old repository binary is substituted for the build artifact.
