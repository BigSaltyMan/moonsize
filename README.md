# moonsize

```sh
moon add BigSaltyMan/moonsize@0.5.1
```

A size analyzer for WebAssembly, built for MoonBit's output. It reads a `.wasm`
file, measures every section, attributes the code section to named functions,
follows a reference graph, and highlights candidates for investigation. It does
not predict the exact bytes a source deletion will save after rebuilding.

The analysis model follows [Twiggy](https://github.com/rustwasm/twiggy): sizes
are attributed to individual functions, functions are grouped by package, and
reachability is calculated from the current model's roots. Read the
[retained-size boundaries and measured rebuild cases](docs/retained-size-boundaries.md)
before interpreting a removal candidate.

Chinese version: [README.zh.md](README.zh.md).

Version **0.5.0** adds data-entry inspection, exact-payload group comparison and
opt-in HTML details. It also changes report writes to exclusive creation; read
the [0.5 migration guide](docs/migration-0.5.md) for behavior and API changes.
The [0.4 migration guide](docs/migration-0.4.md) remains historical. The moon add command adds a library
dependency; it does not install a standalone CLI. For the CLI, clone this source
repository and run the build below.

The [review evidence index](https://github.com/BigSaltyMan/moonsize/blob/main/docs/review-evidence.md)
links measured rebuild cases, real PDFs and explicit model boundaries. The
[0.4.0 release record](https://github.com/BigSaltyMan/moonsize/releases/tag/v0.4.0)
records the exact source SHA, target Linux CI, registry checksum and clean consumer
verification; historic devlog counts are snapshots.

The source here prepares **0.5.1**. Publication, exact-version consumption and
the target CI result are recorded separately in the
[0.5.1 release record](https://github.com/BigSaltyMan/moonsize/releases/tag/v0.5.1)
when completed; this document is not a publication receipt. The published 0.4.0
HTML/graph writer retains its old behavior.

Patch 0.5.1 removes the obsolete JSON-manifest dependency chain that blocked
Mooncakes documentation for 0.4.0/0.5.0. It ships the pinned synchronous gzip
implementation with [source hashes and Apache-2.0 attribution](internal/compression/README.md),
keeping its algorithm and defaults. See [toolchain compatibility](docs/toolchain-compatibility.md).

## Building

[Reproducible CLI performance baseline](docs/performance.md): run the built native
CLI against four bounded representative inputs, or use the two-input `--smoke`
check. Raw times, hashes, failures and environment are retained. CI runs smoke
only, without a millisecond gate; 50k functions and peak memory are not claimed
as measured by this local baseline.

```sh
moon build --target native --release
./_build/native/release/build/cmd/main/main.exe app.wasm
```

The module declares `supported_targets = "+native"`, so a project that depends on
it builds with `--target native` as well.

## Data segment encodings

```sh
moonsize app.wasm --data-segments --top 20
moonsize app.wasm --data-json new-data.json
moonsize app.wasm --html new-report.html --data-json new-data.json
```

The 0.5.0 data-segment feature accounts for
data-entry payload, encoding metadata and section overhead in file bytes.
Active offset expressions are recorded without evaluation; no source attribution
or deletion savings are inferred. Text Top does not truncate the JSON or totals.
It supports ordinary text, strict, max-size and baseline (single-file details
unless `--diff-data` is enabled),
and rejects graph, experiment, path, budget and function-diff combinations.
HTML accepts current-input details explicitly: a static first 20 rows remain
readable without JavaScript, and the button appends 20 at a time. HTML and JSON
share the same ledger. Printing includes the displayed subset; `--top` remains
a text-only limit. HTML does not accept `--diff-data`.
See [encoding ledger, real sample and API migration](docs/data-segments.md).

With `--baseline before.wasm --diff-data`, the text report also compares exact
payload content groups, including duplicate counts and encoding overhead. Add
`--data-json new-diff.json` for the independent `moonsize-data-segments-diff`
format; without `--diff-data`, JSON keeps the original single-file format.
Groups do not establish source identity, equivalent initialization or safe
deduplication, and raw differences do not predict rebuild or gzip savings.

## Data payload literal search

This source addition follows public 0.5.1; it has not been republished.

```sh
moonsize app.wasm --find-data "assets/logo" --top 20
moonsize app.wasm --find-data "assets/logo" --find-data-json new-search.json
moonsize app.wasm --find-data-hex 00FF00 --find-data-json new-hex-search.json --top 1
```

Search exact UTF-8 bytes inside each data payload, retaining overlapping hits.
Spaces matter; no normalization or cross-entry matching is performed. Results
record original segment indices and payload/file byte offsets, not memory
addresses. Query text is included in reports. Top limits text only; JSON and
counts remain complete, and memory grows with occurrences. Hits do not prove
standalone strings, resource use or deletion savings; compiler encodings can
differ. This independent mode accepts only Top and its own new JSON target.
Alternatively, --find-data-hex accepts compact, nonempty, even-length ASCII hex
pairs; case is equivalent and reports use lowercase. It matches actual bytes,
including NUL and invalid UTF-8, without text conversion or encoding detection.
The two queries are mutually exclusive. Shared --find-data-json exports
moonsize-data-search for text and moonsize-data-hex-search for hex. No spaces,
0x prefixes, separators or wildcards.
See [matching rules, API and verified positions](docs/data-search.md).

## Bounded data payload preview

This source addition follows public 0.5.1 and has not been republished.
Coordinates below are illustrative; use your own search result:

```sh
moonsize app.wasm --find-data "assets/logo"
moonsize app.wasm --data-preview 1 --data-offset 8 --data-limit 64
moonsize app.wasm --data-preview 1 --data-preview-json new-preview.json
moonsize after.wasm --data-preview 2 --data-offset 8 --data-limit 32 \
  --baseline before.wasm --baseline-data-preview 1 --baseline-data-offset 4 \
  --data-preview-json new-window-diff.json
```

Preview uses the original entry index and payload byte offsets. Default offset
is 0 and limit is 256; valid limits are 1..4096. It clips at payload end and
permits an empty end window, without crossing entries or padding data. Text
shows hex plus printable ASCII (other bytes become dots); JSON contains the
complete returned window, not a full payload export. Both expose actual content.
No encoding or memory address is inferred. This independent mode rejects Top
and other analysis/report modes. An explicit baseline preview pair compares
equal window-relative positions: both indices are required; offsets independently
default to zero and a common limit clips each side. Missing bytes are null (--),
not 00. No resource matching or insertion/deletion alignment. --diff-data instead
groups complete payload content. See [byte contract, API and actual ranges](docs/data-preview.md).

## Compare two function dependency sets

Source addition after public0.5.1: compare two arbitrary full function indices
in one input, including imports and each start itself.

```sh
moonsize app.wasm --compare-dependencies 12 47 --top 20
moonsize app.wasm --compare-dependencies 12 47 --compare-dependencies-json new-overlap.json --top 1
```

Indices are placeholders. shared/left_only/right_only/neither partition the
full index space with count and local-byte ledgers. Single-side is relative to
these starts, not global exclusive attribution; neither is not dead code or
removal savings. Only Top, own JSON and strict combine; no baseline. Top applies
to each of three text tables; JSON retains all groups and both complete edges.
One build, at most two old closure BFS calls (one for equal starts).
[Actual sets, byte ledgers, entrypoint distinction and API](docs/dependency-overlap.md).

## A model path between any two functions

Source addition after public0.5.1: explicitly choose FROM and TO in the full
function index space, including imports. The source need not be a model root.

```sh
moonsize app.wasm --path-between 12 47
moonsize app.wasm --path-between 12 47 --path-between-json new-path.json --strict
```

Indices12/47 are placeholders. Only own JSON and strict combine; explicit Top
is rejected. Found, zero-step and within-model not-found all return0; strict
checks full-module diagnostics before writing. The complete dependencies closure
is prepared once, then predecessors are reconstructed without another search.
This is a model path, not execution, stack depth or removal benefit.
[Exact path, preparation cost, null states and API](docs/function-path-between.md).

## Transitive function model referrers

Source addition after public 0.5.1: `--dependents INDEX` lists every modeled
source that can reach any valid function, including imported targets. Edges
retain caller-to-callee direction; each node keeps one next edge toward the
target and a minimum model depth. Complete internal edges remain separate.

```sh
moonsize app.wasm --dependents 12 --top 20
moonsize app.wasm --dependents 12 --dependents-json new-dependents.json --top 1
```

Index12 is a placeholder. Only Top, own JSON and strict combine; strict checks
full-module diagnostics. Top limits text rows, not traversal or JSON. This is
not source-change impact or removal savings. Contrast callers (one-hop incoming),
dependencies (outgoing closure), and why-index (one root path).
[Direction, actual accounting, API and limits](docs/function-dependents.md).

## Transitive function model dependencies

Source addition after public 0.5.1: start at any full function index, including
imports, and list its transitive reference-model closure. The target is included
once; other nodes keep minimum model depth and one first-discovery edge. Full
closure evidence retains parallel/direct/reference/candidate edges separately
from the predecessor tree. Local bytes are unique per index, not retained or
removal savings; imported encoded sizes remain null.

```sh
moonsize app.wasm --dependencies 12 --top 20
moonsize app.wasm --dependencies 12 --dependencies-json new-dependencies.json --top 1
moonsize app.wasm --dependencies 12 --dependencies-dot new-dependencies.dot --top 1
```

Index12 is a placeholder. Only Top, strict and own JSON or DOT combine; JSON
and DOT are mutually exclusive. Strict uses whole-module diagnostics, including
outside the target closure. Top limits text, never the complete JSON or DOT.
DOT generation needs no Graphviz; parallel edges, candidates and diagnostics
remain. This local graph does not determine global dead code. Graphviz parsing
and actual rendering were not verified for this delivery. [Actual depths, byte ledgers, related queries
and migration](docs/function-dependencies.md).

## Reference cycle components

Add `--cycle-witness` to cycles or cycles-json for one deterministic closed
model path per component, starting at its minimum index. It may show only some
members and does not promise a globally shortest cycle or actual recursion.
Original edges and diagnostics remain complete; Top never truncates shown
steps or JSON. Without the modifier the old query/format is unchanged.

```sh
moonsize app.wasm --cycles --cycle-witness --top 10
moonsize app.wasm --cycles-json new-witnesses.json --cycle-witness --top 1
```

[Selection, actual paths and migration](docs/function-cycles.md#optional-closed-evidence-paths-source-addition-after-public-051).


Source addition after public 0.5.1: query strongly connected components in the
current reference graph, including unreachable functions and self-loops.
Direct calls, references taken and indirect candidates remain distinct.
Model cycles do not prove runtime recursion; component encoded bytes are not
retained or deletion savings. Only Top, own JSON and strict may combine.

```sh
moonsize app.wasm --cycles --top 10
moonsize app.wasm --cycles-json new-cycles.json --top 1
```

Top limits components in text, not their members or complete JSON. Strict
refuses incomplete graphs before output creation. [Actual components, edge
positions, ledgers and API migration](docs/function-cycles.md).

## File range ownership

Source addition after public 0.5.1: `--locate-range OFFSET LENGTH` explains a
half-open file range, without opcode decoding. Empty ranges through EOF are
valid; out-of-bounds requests fail rather than clip. Each row separates full
`owner_range` from actual `overlap_range`; all intersections continuously cover
the query. Only Top and own JSON combine; Top never truncates JSON or coverage.

```sh
moonsize app.wasm --locate-range 40 32 --top 20
moonsize app.wasm --locate-range 40 32 --locate-range-json new-range.json --top 1
```

Coordinates above are placeholders, not measurements. No runtime addresses or
optimization benefit is inferred. [Actual 13-part ledger, API and errors](docs/file-range.md).

## File offset ownership

A source addition after public 0.5.1; not republished. Example 31 is a placeholder:

```sh
moonsize app.wasm --locate-offset 31
moonsize app.wasm --locate-offset 31 --locate-offset-json new-location.json
```

Locate one decimal file byte in its physical section and, for a selected code
or data payload, its count field, function prefix/body or data metadata/payload.
Ranges are half-open; EOF has no byte and fails. Custom sections count toward
physical ordinals, imported functions toward function indices. Other payload
interiors stay undivided. This independent mode has no Top or strict and accepts
its own optional new JSON and --locate-decode. Default locating does not decode
instructions; the modifier refines only a hit local body to locals or one whole
instruction. Non-body bytes are not_applicable; a bad target fails even for a
locals query. Decoded JSON uses moonsize-file-offset-decoded with the base
location nested; default JSON is unchanged. No runtime-address lookup or full
semantic validation is claimed. Base structure checks and whole-file SHA
still scan the input. See [nine regions, API and actual ranges](docs/file-offset.md).

## Find opcode locations

Source addition after public 0.5.1; not republished:

```sh
moonsize app.wasm --find-opcode i32.const --top 20
moonsize app.wasm --find-opcode i32.const --find-opcode-json new-matches.json --top 1
```

Match a complete decoded mnemonic, case-sensitively, in all local functions.
Results retain full function indices, original instruction ordinals and file/body
positions. Immediates, initializer expressions, names and payload text do not
become opcode sites. Every body is decoded once; any bad body fails the query.
Top limits global location rows, not scan cost or complete JSON. Only query,
Top and own new JSON may be combined; no strict or baseline. Empty results do
not describe other module regions. [Rules, actual positions and API](docs/opcode-search.md).
Use separate commands to go from opcode statistics to this query, then to
--instructions or --locate-offset --locate-decode. No automatic multi-pass mode.

## Module-wide function opcode statistics

Source addition after public 0.5.1; not republished:

```sh
moonsize app.wasm --opcode-stats --top 20
moonsize app.wasm --opcode-stats-json new-opcodes.json --top 1
moonsize after.wasm --baseline before.wasm --diff-opcodes --top 20
```

Decode every local body once and aggregate mnemonic counts, complete instruction
encoding bytes and distinct-function counts. Bytes include subopcodes/immediates;
function_count is deduplicated within each function and cannot be summed to a
function total. Imports have no synthetic body; initializer expressions are
excluded. One bad body fails the whole query, naming its full index. The result
keeps only opcode groups and compact function summaries, without instruction
lists or a matrix. Top limits text only, not all-body decoding cost or JSON.
Single-input statistics accept Top and own new JSON. For two complete modules,
`--diff-opcodes` requires baseline and reuses `--opcode-stats-json` for a complete
comparison. It separates instruction deltas from code header/count/prefix/locals
overhead, without matching functions. Zero statistical deltas do not prove equal
bytes or semantics. Neither mode accepts strict, HTML or budgets. Static
statistics are not runtime hotspots or savings.
[Code byte ledger, API and real output](docs/module-opcodes.md).

## Local access instruction encodings

Source addition after public 0.5.1; not republished. Index 3 is illustrative:

```sh
moonsize app.wasm --local-accesses 3 --top 20
moonsize app.wasm --local-accesses 3 --local-accesses-json new-accesses.json --top 1
```

List actual local.get/set/tee positions and index encoding widths in one fully
decoded local body, with sparse numeric-index groups. Repeated sites remain;
tee counts once. The encoded local index includes the parameter index space,
unlike parameter-excluding --locals ordinals. No signature, parameter/declaration
binding, variable names/types or actual index-range validation is provided.
The decoder currently limits operands to nonnegative Int, not full u32. Static
counts are not execution frequency; encoded bytes do not measure runtime memory
or savings. Top independently limits each text table, keeping totals, members
and JSON complete. This standalone mode accepts only Top and own new JSON,
without strict. [Scope, API and measured access ledger](docs/function-local-accesses.md).

## Local declaration groups in one function

Source addition after public 0.5.1; not republished. Index 3 is illustrative:

```sh
moonsize app.wasm --locals 3 --top 20
moonsize app.wasm --locals 3 --locals-json new-locals.json --top 1
```

Inspect original locals groups, quantities and exact type bytes without decoding
instructions or expanding variables. Zero groups and zero-quantity groups differ;
ordinals exclude parameters and are not complete local indices. Quantities use
u32; cumulative counts/ordinals use decimal strings in JSON. Limited type labels
do not validate types, and the body remainder stays undecoded. Top limits text
rows only; JSON is complete. The single-input query accepts Top and its own
new JSON, without strict. An explicit comparison additionally requires both
--baseline and --baseline-locals; targets are never matched automatically.
[Scope, API and measured ledger](docs/function-locals.md).

### Explicit locals comparison

```sh
moonsize after.wasm --locals 5 --baseline before.wasm --baseline-locals 3 --top 20
moonsize after.wasm --locals 5 --baseline before.wasm --baseline-locals 3 --locals-json new-locals-diff.json --top 1
```

Indices are placeholders in each file's complete function index space. Both
targets are explicit; full raw type_hex buckets describe encoding statistics,
not variable identity or semantic type equivalence. Zero-quantity groups count
as present. Cumulative quantities and signed quantity deltas use exact decimal
strings; actual encoding widths are measured separately. Remainders stay undecoded. Top limits
only displayed type rows, keeping all member indices and nested JSON complete.
The existing single-input JSON stays moonsize-function-locals; the comparison
uses moonsize-function-locals-diff/schema 1. Zero statistical differences do not
prove equal group sequences, remainder contents or semantics. This is an
unpublished source increment after 0.5.1, without deletion/runtime/gzip estimates.

## Calls inside one function

Source addition after public 0.5.1; not republished. Index 3 is illustrative:

```sh
moonsize app.wasm --calls 3 --top 20
moonsize app.wasm --calls 3 --calls-json new-calls.json --top 1
```

List call/return_call, table calls and reference calls at their original positions
in one local body. Direct targets retain full indices and identities; dynamic
targets remain null. ref.func is excluded. A local function with no calls succeeds;
imports have no local body and are rejected. Top limits text rows, not the full
JSON or decode cost. This independent mode has no strict and only accepts Top
and its own new JSON. Calls are static instruction facts, not execution counts
or savings. Callers queries incoming model references; calls inspects body call
instructions, so these are not a simple graph reversal.
[Scope, API and actual call-site ledger](docs/function-calls.md).

## Function and package comparison JSON

This source addition follows public 0.5.1; build the native CLI from source.

```sh
moonsize after.wasm --baseline before.wasm --diff-functions-json new-function-diff.json --top 20
moonsize after.wasm --baseline before.wasm --diff-functions --diff-functions-json new-growth.json --max-size 5KB
```

The JSON flag implies --diff-functions and exports that same existing comparison.
Top never truncates the complete functions, packages or matching coverage. The
independent moonsize-function-diff/schema_version 1 format records both input
hashes, code/function/overhead totals, signed current-minus-baseline deltas and
all five symbol states. Absent sides remain null; ambiguous and missing names
retain one row per function per side. Even self comparison can have nonzero
one-sided uncertain rows whose deltas cancel. A unique raw-symbol match is not
semantic identity, and added/removed symbols do not prove source changes.

This JSON option allows baseline, Top, retained, dead-code, strict, max-size and
the explicit text flag. Other reports, compression, independent queries, budget
configuration and data details are rejected before I/O. Old text-only combinations
stay unchanged. Strict checks the current input graph only and refuses before
writing. With baseline, max-size gates file growth; a failure can still save the
comparison before exit 3. Existing targets are refused with exit 1. No retained,
graph completeness, gzip or future source-edit savings are inferred. See
[fields, coverage ledgers and JSON.parse example](docs/function-diff-json.md).

## Complete analysis JSON

This source addition follows public 0.5.1; build the native CLI from source.

```sh
moonsize app.wasm --summary-json new-summary.json --top 1 --retained --dead-code
moonsize app.wasm --summary-json new-strict-summary.json --strict --max-size 100KB
```

An additional export of the same ordinary Analysis, with every physical section,
local function, symbol module group, model root and diagnostic. Top affects text
only. The versioned moonsize-summary/schema_version 1 format keeps numeric byte
ledgers, nullable raw names/retained results, booleans and complete provenance.
Module names are existing symbol attribution labels, not verified source ownership.
Retained dominated bytes include the function itself; other dominated function
counts exclude it. Missing results stay null. Model-unreachable is not safe removal;
retained sets can overlap and must not be summed. Function/module bytes are already
contained in section bytes, so those views must not be added together.

Only Top, retained, dead-code, strict and max-size may accompany this export.
Strict refusal returns 3 before creating a file. Non-strict incomplete models keep
all diagnostics. A max-size violation still saves the report before returning 3;
JSON contains analysis, not a budget conclusion. Existing destinations are refused
with exit 1. No compression, baseline, independent queries, budget configuration,
data details, HTML or complete call edges; use --call-graph for edges. See
[field definitions, real evidence and JSON.parse example](docs/summary-json.md).

## Local function name search

This source addition follows public 0.5.1; build the native CLI from source.

```sh
moonsize app.wasm --find-functions 'demo::sample' --top 20
moonsize app.wasm --find-functions 'classify' --find-functions-json new-search.json
```

Searches available raw symbols and display names of local definitions using a
case-sensitive literal substring, preserving the original query, including spaces.
No regex, wildcards or Unicode normalization. Generated unnamed placeholders are
excluded; a real raw name equal to (unnamed) remains searchable. Duplicate names
keep their distinct full function indices, including preceding function imports.
Imports and export aliases are outside this search; use --imports for declarations.

Top limits text only; counts, byte totals and JSON remain complete. No match,
no available names or no local functions all return 0, with distinct explanations.
This independent mode accepts only Top and its own JSON, rejects strict and other
modes before I/O, and uses exclusive output creation. Choose an index from the
results and explicitly run --instructions, --callers or --why-index next. A name
is not a unique identity; no match does not prove absence. Matched encoding bytes
exclude section headers, names and dependency closures, and are not savings.
See [measured results, examples, coverage and API](docs/function-search.md).

## Single-function instruction encoding

This source addition follows public 0.5.1; build the native CLI from source.

```sh
moonsize app.wasm --instructions 3 --top 20
moonsize app.wasm --instructions 3 --instructions-json new-instructions.json
```

Uses the full function index space, with imports first; an imported target has
no local body and returns an input error. Only the selected body is decoded.
The report separates its length prefix, locals encoding and instructions, and
lists opcode counts, encoded bytes and original-file instruction ranges.
Top limits both text tables; JSON contains every group and instruction.
This independent mode accepts Top, its own JSON and an optional explicit
baseline/index pair, rejects strict and other modes before I/O, and refuses
to overwrite existing output. Counts and
bytes describe static encoding, not execution frequency, timing or savings.
To compare two explicitly selected local functions:

```sh
moonsize after.wasm --instructions 7 --baseline before.wasm --baseline-instructions 5 --top 20
moonsize after.wasm --instructions 7 --baseline before.wasm --baseline-instructions 5 --instructions-json new-instructions-diff.json
```

Both indices are required, even when numerically equal. Each target is inspected
once. Exact opcode mnemonics compare counts and encoded bytes; full prefix,
locals and instruction ledgers use current minus baseline. Different names are
allowed; names and indices do not establish cross-build identity. Zero aggregate
deltas do not prove equal sequences, immediate values, semantics or compatibility.
Top limits text rows only. The independent moonsize-function-instructions-diff
JSON nests both complete reports as objects; single-file JSON remains unchanged.
Baseline/current errors retain their target and original cause. No automatic
matching, instruction alignment, performance or complete-build savings prediction.
See [scope, measured ledgers and API](docs/function-instructions.md).

## Duplicate data payloads

This source addition follows public 0.5.1; build the native CLI from source.

```sh
moonsize app.wasm --data-duplicates --top 20
moonsize app.wasm --data-duplicates-json new-data-duplicates.json
```

Groups exact payload bytes within one input, excluding modes, memory indices,
offset expressions and length prefixes. SHA-256 and length select candidate
buckets; every match is confirmed against the bytes. Member indices refer to the
complete original data report, retaining each encoding and unevaluated expression.
Empty payloads participate, including zero-byte groups. This differs from function
--duplicates and cross-build --diff-data; it does not infer safe deduplication.

Top limits text groups and each group previews at most 20 members, with displayed
and total counts. JSON retains all groups and entries. The measured 74 B fixture
has 3 duplicate groups, 7 members and 1 singleton: payload 16 = all duplicate-group
members 13 + singletons 3 B; data section 56 = header 3 + count 2 + entries 51 B.
These are file-byte facts, not estimated savings or runtime memory usage. The
independent mode accepts only Top and its own JSON, rejects strict/other modes
before input I/O, and inherits exclusive output creation. See
[full ledgers, collision checks, scope and API](docs/data-segments.md).

## Visual report development

Start the local HTTP server before visual acceptance, screenshots, printing, or
browser tests:

```sh
npm run dev
```

Then open [http://localhost:5173/](http://localhost:5173/). The root serves
`examples/report.html`; use this HTTP URL for all browser-based checks rather
than opening the report with `file://`.

## Usage

### Help by task

No Wasm input is needed. This is a source addition after public 0.5.1; build the
current native CLI. Help examples use placeholder paths/indices, not measurements.

```sh
moonsize --help
moonsize -h
moonsize --help-topic functions
```

| Topic ID | Task | Existing guides |
| --- | --- | --- |
| overview | Ordinary report, Top, HTML and summary JSON | [HTML delivery](docs/html-delivery.md), [summary JSON](docs/summary-json.md) |
| functions | Find an index, inspect instructions and model references | [Search](docs/function-search.md), [instructions](docs/function-instructions.md), [callers](docs/function-callers.md) |
| data | Data entries, duplicate payloads and comparisons | [Data encodings and comparisons](docs/data-segments.md) |
| interfaces | Imports/exports and their baseline comparisons | [Imports](docs/imports.md), [exports](docs/exports.md) |
| metadata | Custom/name overhead, outer comparison and partial details | [Metadata](docs/metadata.md) |
| baseline | File, function/package and selected-function comparisons | [Function/package JSON](docs/function-diff-json.md), [experiments](docs/optimization-experiments.md) |
| ci | Size gates, budget evidence and supported strict modes | [Budgets](docs/budgets.md) |

Only the first user argument triggers help; flags inside business arguments are
left to the existing parser. Help returns 0; malformed help requests return 2
with available topics. No input is read and no report is created. See [help syntax
and dispatch rules](docs/cli-help.md). The full option table remains below.

Unknown ASCII dash-prefixed options now return 2 before file/config I/O. End option
parsing with `--` to read a dash-prefixed filename, including a file named `--help`:

```sh
moonsize -- --help
moonsize --top 1 --summary-json new-summary.json -- --app.wasm
```

After the separator, tokens are positional paths only; at most one input is
accepted overall. Place all options before it. Known option-value constraints
are unchanged; use an explicit path such as `./--name` where needed. A single `-`
is a filename, not stdin. This source behavior follows public 0.5.1; earlier
implicit dash-prefixed input calls must use `--` or an explicit relative path.

```
usage: moonsize <file.wasm> [--top <n>] [--retained] [--dead-code]
                 [--compress] [--strict] [--call-graph <path>] [--html <path>]
                 [--max-size <size>] [--baseline <path.wasm>] [--diff-functions]
                 [--diff-functions-json <new-path.json>]
                 [--summary-json <new-path.json>]
                 [--data-segments] [--diff-data] [--data-json <new-path.json>]
                 [--budget <config.json>] [--budget-json <path.json>] [--budget-md <path.md>]
                 [--experiment <report.html|report.json>] [--experiment-context <context.json>]
       moonsize <file.wasm> --find-functions <query> [--top <n>] [--find-functions-json <new.json>]
       moonsize <file.wasm> --instructions <n> [--top <n>] [--instructions-json <new.json>]
       moonsize <after.wasm> --instructions <n> --baseline <before.wasm> --baseline-instructions <n> [--top <n>] [--instructions-json <new.json>]
       moonsize <file.wasm> --data-duplicates [--top <n>] [--data-duplicates-json <new.json>]
       moonsize <file.wasm> --imports [--top <n>] [--imports-json <new.json>]
       moonsize <file.wasm> --baseline <before.wasm> --diff-imports [--top <n>] [--imports-json <new.json>]
       moonsize <file.wasm> --metadata [--top <n>] [--metadata-json <new.json>]
       moonsize <file.wasm> --duplicates [--top <n>] [--duplicates-json <new.json>]
       moonsize <file.wasm> --entrypoints [--top <n>] [--entrypoints-json <new.json>] [--strict]
       moonsize <file.wasm> --generics [--top <n>] [--generics-json <new.json>]
       moonsize <file.wasm> --callers <n> [--top <n>] [--callers-json <new.json>] [--strict]
       moonsize <file.wasm> --why-index <n> [--why-root <n>] [--why-json <path.json>] [--strict]

Report the section table of a WebAssembly binary, rank its heaviest
functions, roll the bytes up by module, and follow the call graph to
identify candidates for investigation.

  --top <n>            how many functions to rank (default 10)
  --retained           dominated function bytes in the current graph model
  --dead-code          functions no root can reach
  --compress           whole-file gzip and independent section gzip sizes
  --data-segments      append data-entry file bytes (payload-ranked by --top)
  --data-json <path>   enable details and write all entries to a new .json file
                       offset expressions are recorded, not evaluated
  --diff-data          compare exact payload content groups; requires --baseline
                       --data-json then writes the data comparison format
  --strict             refuse to report when the call graph is incomplete,
                       instead of reporting it with a warning
  --call-graph <path>  write a new .dot or .json call graph; refuses existing paths
  --html <path>        write a new self-contained HTML report; refuses existing paths
                       --data-segments or --data-json adds current-input data details
  --max-size <size>    fail with exit code 3 above this size, where size is
                       bytes or a KB/MB/GB count such as 10KB or 1.5MB
  --budget <path>      validated multi-metric byte budgets; growth needs --baseline
  --budget-json <path> write budget JSON; requires --budget, refuses existing paths
  --budget-md <path>   write CI Markdown summary; requires --budget, refuses existing paths
  --baseline <path>    compare against another module and print the change;
                       --max-size then bounds the growth, not the file
  --diff-functions     append function and package changes; requires --baseline
  --experiment <path>  write measured before/after results; requires --baseline
                       refuses to overwrite an existing path
  --experiment-context <path>  attach declared build settings and validation
  --locate-range <offset> <length> decompose file ownership; EOF empty allowed
  --locate-range-json <path> complete ownership JSON to a new target
  --locate-offset <n> locate one decimal file byte; EOF fails; no Top
  --locate-decode opt-in whole target-body decoding to locals/instruction; requires query
  --locate-offset-json <path> location to a new .json; requires query
  --data-preview <index> bounded payload bytes (no Top); original entry index
  --data-offset <n> payload byte offset, default 0; requires --data-preview
  --data-limit <n> 1..4096 bytes, default 256; requires --data-preview
  --baseline-data-preview <index> explicit baseline entry, requires baseline/current preview
  --baseline-data-offset <n> independent baseline payload offset, default 0; comparison only
  --data-preview-json <path> returned window or explicit comparison to a new .json
  --find-data <query> exact UTF-8 byte search within data payloads, including overlaps
  --find-data-hex <hex> exact payload bytes from compact hex pairs; excludes --find-data
  --find-data-json <path> save every hit to a new .json; requires either query
  --find-functions <query> case-sensitive literal search of local raw/display names
  --find-functions-json <path> save all matches to a new .json; requires a query
  --diff-functions-json <path> save full function/package comparison; implies diff-functions and requires baseline
  --summary-json <path> save full ordinary analysis to a new .json; Top never truncates it
  --instructions <n> inspect a local function in the full function index space
  --instructions-json <path> save complete groups/instructions or explicit comparison to a new .json
  --baseline-instructions <n> explicit baseline function index; requires instructions/baseline
  --data-duplicates   group exact data payloads within the current input
  --data-duplicates-json <path> write full groups and source entries to a new .json
                       only Top and own JSON; text previews 20 members per group
  --imports           list host import declarations and their encoding bytes
  --imports-json <path> write all declarations to a new .json file; implies --imports
                       unsupported descriptors fail; baseline requires --diff-imports
  --diff-imports      compare import names/kinds/counts; requires --baseline
                       type compatibility not evaluated; differences still return 0
  --exports           list exact host-visible declarations and declared-target aliases
  --diff-exports      compare exact export names/kinds; requires --baseline
  --exports-json <path> write complete exports to a new .json file; implies --exports
  --metadata          account for custom/name physical file bytes
  --diff-metadata     compare outer custom encodings; requires --baseline
  --metadata-json <path> write full metadata to a new .json file; implies --metadata
                       partial optional name details still return 0 with diagnostics
  --duplicates        group exact local body bytes, excluding length prefixes
  --duplicates-json <path> write complete groups to a new .json file
  --entrypoints       show model-reachable, exclusive and shared function bytes
  --entrypoints-json <path> write complete results to a new .json file
  --generics          group supported raw symbols by encoded function bytes
  --generics-json <path> write full groups to a new .json file; implies --generics
  --find-opcode <mnemonic> exact decoded locations in all local bodies
  --find-opcode-json <path> all matching sites to a new .json; requires query
  --opcode-stats aggregate all local function instruction encodings; Top/own JSON
  --diff-opcodes compare both module aggregates; requires --baseline
  --opcode-stats-json <path> full opcode/function summaries to a new .json; implies mode
  --local-accesses <n> inspect local.get/set/tee encodings; Top/own JSON only
  --local-accesses-json <path> save full accesses/groups to a new .json; requires query
  --locals <n> inspect local declaration groups; Top/own JSON or explicit baseline pair
  --locals-json <path> save all groups or explicit comparison to a new .json
  --baseline-locals <n> baseline target; requires locals and baseline
  --calls <n> list call instructions in one local body; Top/own JSON only
  --calls-json <path> save all call sites to a new .json; requires calls
  --compare-dependencies <left> <right> two outgoing closures in one input; Top/strict
  --compare-dependencies-json <path> full sets to a new .json; requires pair
  --path-between <from> <to> one shortest model path; strict/own JSON only, no Top
  --path-between-json <path> full path to a new .json; requires explicit pair
  --dependents <n>     transitive model referrers to any function; Top/strict
  --dependents-json <path> full reverse closure to a new .json; requires dependents
  --dependencies <n>   transitive model closure from any function; Top/strict allowed
  --dependencies-json <path> full closure to a new .json; requires dependencies
  --dependencies-dot <path> full subgraph to a new .dot; exclusive with JSON; Top only limits text
  --cycles             query reference-model cyclic components; Top/strict allowed
  --cycle-witness      add one closed model path per component; requires cycles
  --cycles-json <path> complete cycles JSON to a new .json; implies cycles
  --callers <n>        list recorded one-hop incoming instruction sources
  --callers-json <path> write full callers JSON to a new .json file; requires --callers
  --why-index <n>      explain a shortest model reference path to function n
  --why-root <n>       search from one actual model root (requires --why-index)
  --why-json <path>    write path JSON; refuses existing paths
                       query mode allows only these flags and --strict
                       element functions are conservative roots; paths are
                       not execution traces or predictions of savings

All report outputs refuse existing files, directories and link aliases.
Targets are checked together; each file is created exclusively. Output errors use exit 1.
Multiple files are not a transaction; a later failure may leave earlier new outputs.

Exit codes: 0 completed, 1 input/query/output/unavailable measurement, 2 bad arguments/config,
            3 over budget, incomplete strict graph, or path search limited.
```

Without flags it prints the section table, the heaviest functions and the
per-package roll-up. `--retained` and `--dead-code` add their sections and can
be combined. `--call-graph` and `--html` each write a file instead of printing
a report, so they are used on their own:

```sh
moonsize app.wasm --retained --dead-code        # the full text report
moonsize app.wasm --html report.html            # charts, opens in a browser
moonsize app.wasm --call-graph graph.dot        # for Graphviz
```

All report destinations, including HTML and DOT/JSON graphs, refuse existing
files, directories and link aliases. Output protection failures return 1. Targets
are checked together after parsing and strict refusal; each write uses native
exclusive creation. This prevents truncation if a target appears after preflight,
but is not a multi-file transaction or crash-atomic write. Later failure can leave
earlier new files or a partial new file; hostile parent-directory changes remain
outside this guarantee. See [protection and concurrency boundaries](docs/output-protection.md).
Generate an update at a fresh staging path, verify it, then explicitly replace the
published copy yourself. No production Node dependency or overwrite flag is added.

## Optimization experiments

```sh
moonsize after.wasm --baseline before.wasm --experiment experiment.html \
  --experiment-context context.json --top 20
```

The offline HTML report (or `.json` for CI) combines artifact SHA-256, measured
file and whole-file gzip changes, section/function/package differences, graph
diagnostics, and declared build/validation records. Different build settings,
failed checks, and missing records remain visible; smaller output does not prove
equivalent behavior. Context commands are recorded, never executed. Existing
output paths are refused. See the [format and reproducible workflow](docs/optimization-experiments.md)
and [sample report](examples/optimization-experiment.html).

## Multi-metric budgets and CI summaries

Use a versioned JSON configuration to check several measured byte limits:

```sh
moonsize after.wasm --baseline before.wasm --budget moonsize-budget.json \
  --budget-json budget-result.json --budget-md budget-summary.md
```

Version 1 has a nonempty `rules` array. Every rule needs a unique nonempty `id`,
`metric`, `mode` and integer `max_bytes` (0 through 2147483647). Supported metrics
are `file.raw`, whole-file `file.gzip`, complete `code.raw`, and `package.raw`;
the last also requires an exact `package` label from the report. Unknown fields,
fractional/exponent tokens and invalid values are rejected before reading Wasm.
`absolute` checks current bytes; `growth` checks current minus baseline and
requires `--baseline`. Equality passes and shrinkage retains its negative delta.

Package bytes sum local function `total_size` under existing symbol attribution,
including body size prefixes. Missing names or unresolved ownership make package
rules unavailable. A fully attributed growth comparison can record a newly
observed/disappeared label as zero on the missing side; a label absent on both
sides is unavailable. Successful file/code/gzip measurements are retained.
Package totals are not total source-package costs or deletion savings; gzip is
one whole-file measurement with the current compressor defaults, not predicted
network cost. Independent gzip streams are never added.

Each rule reports `passed`, `exceeded` or `unavailable`, its measurements and
reason. Exits are 0 for all passed, 3 for evaluable rules with an exceeded limit,
1 for input/measurement/attribution/output errors (taking precedence over exceeded),
and 2 for arguments/configuration. Strict retains its existing refusal code 3
before normal reports are written. JSON/Markdown refuse existing destinations;
they include artifact hashes, coverage and metric scope. Both outputs can be
requested together. `--budget` conflicts with `--max-size`, path queries,
experiments, HTML and graph export; ordinary text options remain available.

[Configuration, APIs, migration and exact semantics](docs/budgets.md) include a
reproducible source demo and the actual
[demo configuration](examples/budget.json). Run it before this example, whose
package label belongs to that demo:

```sh
node scripts/demo-budget.mjs _build/native/release/build/cmd/main/main.exe
_build/native/release/build/cmd/main/main.exe _build/budget-demo/after.wasm \
  --baseline _build/budget-demo/before.wasm --budget examples/budget.json
```

CI runs the budget regression and source/rollback demo, saves JSON/Markdown, and
applies [file/gzip/code budgets](examples/ci-budget.json) to the freshly built
example. Its generated Markdown is also appended to the CI step summary.

## Incoming function references

This is a source-checkout addition after public 0.5.1; rebuild the native CLI.
No new Mooncakes version is published by this change.

```sh
moonsize app.wasm --callers 42 --top 20
moonsize app.wasm --callers 42 --callers-json new-callers.json
```

`--why-index` finds one root-to-target model path; `--callers` lists all
recorded one-hop body sources, including unreachable callers. Distinct positions
are retained; direct calls, references taken and indirect candidates are labeled
separately. Top limits text caller groups; JSON and counts remain complete.
Only Top, callers JSON and strict may accompany this independent query. Empty
results do not prove removability. Strict gaps return 3 before output checks;
JSON uses exclusive creation. See [actual sample, API and scope](docs/function-callers.md).

## Host import declarations

This source addition follows public 0.5.1; build the native CLI from source.

```sh
moonsize app.wasm --imports --top 20
moonsize app.wasm --imports-json new-imports.json
```

Lists physical function, table, memory, global and tag import declarations, with
exact module/field names, per-kind indices and original file ranges. Repeated
names remain separate. The measured fixture's import section is 138 B = 3 B
header + 2 B count prefix + 133 B declarations; declaration bytes decompose into
64 B module names + 39 B field names + 30 B descriptors. Module summaries exclude
section overhead. These are declaration encoding bytes, not host/package sizes.

The supported subset covers short funcref/externref table types, 32-bit limits
(including shared memory with a maximum), the listed global scalar/vector/reference
types, and tag attribute 0. Typed references, other GC forms, memory64/table64 and
unsupported flags fail explicitly. Core import errors never become partial success.
Top limits text entries only; summaries and declaration-order JSON remain complete.
Single-file mode allows Top and its own JSON; baseline requires --diff-imports.
Strict and other report modes are rejected before input I/O. Output inherits
exclusive creation. To compare two builds:

```sh
moonsize after.wasm --baseline before.wasm --diff-imports --top 20
moonsize after.wasm --baseline before.wasm --diff-imports --imports-json new-imports-diff.json
```

Exact (module_name, field, kind) groups compare multiplicities, retaining both
complete inventories. Overlap is a quantity intersection, not physical member
matching. same_count does not mean unchanged or type-compatible; type indices,
limits and mutability can differ. Top limits text groups only; comparison JSON is
moonsize-imports-diff/schema_version 1, while single-file JSON remains unchanged.
The measured pair has 9 declarations on each side: overlap 6, removed 3, added 3.
Its import section delta is 11 B = 1 header + 1 count prefix + 9 declaration bytes,
all current minus baseline. Reordering creates no quantity change. Differences
still return 0; parse errors retain side, path and reason. Declarations do not
prove runtime use, permissions, host compatibility or removal savings. See
[the support matrix, comparison contract and actual ledgers](docs/imports.md).

## Export declarations and aliases

This is a source addition after public 0.5.1; build the native CLI from source.

```sh
moonsize app.wasm --exports --top 20
moonsize app.wasm --exports-json new-exports.json
```

Lists function, table, memory, global and tag declarations with exact UTF-8 host
names, full u32 target indices and original file ranges. Names are not demangled
internal symbols. Duplicate names across any kinds are rejected. Targets group
by both kind and index: function #0 and table #0 are separate. Singleton targets
are retained too. This does not validate target existence, signatures, origin or
reachability; re-exported functions can be imports without a local body.

The measured five-kind fixture has 8 declarations, 5 declared targets, 2 alias
groups and 5 alias members. Export bytes: 57 = headers 3 + count 2 + declarations
52; declaration bytes: 52 = name encodings 35 + descriptors 17. These are declaration
costs, not body sizes or removal savings. Top limits each text table, while JSON
retains all entries/targets using moonsize-exports/schema_version 1. Only Top and
own JSON may be combined; invalid combinations return 2 before input I/O, input/
output failures return 1 and successful empty results return 0. New JSON paths
use the existing exclusive-create protection. Use --entrypoints separately for
model reachability. See [scope, actual ledgers and API migration](docs/exports.md).

Compare two export inventories by exact full name:

```sh
moonsize after.wasm --baseline before.wasm --diff-exports --top 20
moonsize after.wasm --baseline before.wasm --diff-exports --exports-json new-exports-diff.json
```

The four states are added, removed, kind_changed and same_kind. Same-kind targets
expose a boolean target_index_changed; other rows use null. This compares index
numbers, not cross-build identities or ABI compatibility. Renumbering stays
same_kind; alias groups remain complete on each side and are not matched across
builds. Top limits text rows only; moonsize-exports-diff/schema_version 1 retains
complete nested inventories, all rows and signed ledgers. The measured pair has
removed 1, kind_changed 1, added 1, same_kind 5; file +23 B = export +8 B +
non-export +15 B. Only baseline, Top, exports and own JSON are allowed. Changes
still return 0; input/output failures return 1, invalid combinations return 2.
This is a source increment after public 0.5.1, not a new Mooncakes release.

## Custom sections and symbol-name overhead

This source addition follows public 0.5.1; build the native CLI from source.

```sh
moonsize app.wasm --metadata --top 20
moonsize app.wasm --metadata-json new-metadata.json
```

The report accounts for every physical custom section, including repeated names,
actual length prefixes, name bytes and opaque content. Classification uses only
reliably decoded full UTF-8 names: name, producers, the .debug_ prefix, or other;
unavailable names retain their ranges and a separate accounting bucket. All
recognized name sections retain physical subsections and function-name records.
Indices are metadata declarations, not proof that those functions exist.

Optional name-content errors produce partial details, diagnostics and remainder
ranges while preserving the byte ledger; successful exit 0 does not certify
complete interpretation. Outer parse errors still return 1. Top limits details
only; summaries and JSON remain complete. This independent mode allows only Top
and its own JSON, rejects strict, and inherits exclusive output creation.
The measured fixture accounts for 115 custom bytes as 15 header + 48 custom-name
encoding + 52 content bytes; these are decompositions, not additive parent/child
totals. Metadata is not necessarily removable, and file bytes do not predict
recompiled or transfer savings. See [the scope, actual ledgers and API](docs/metadata.md).

Compare outer custom encodings by category and exact full name:

```sh
moonsize after.wasm --baseline before.wasm --diff-metadata --top 20
moonsize after.wasm --baseline before.wasm --diff-metadata --metadata-json new-metadata-diff.json
```

Repeated names retain all instances; unavailable names use a separate accounting
bucket. Both coverage states and partial name details remain visible. Top limits
only text name groups; JSON retains both complete reports and all groups using
`moonsize-metadata-diff/schema_version: 1`. This compares counts and outer bytes,
not contents, name internals, DWARF or semantics. Equal names or zero deltas do
not establish equal contents or safe removal. The measured fixture changes file
bytes by +2 = custom -3 + non-custom +5. Comparison accepts only baseline, Top,
metadata and its JSON; exits 0/1/2 mean success (including partial), input/output
failure and argument error. This is a source addition after public 0.5.1.

## Identical function bodies

This source addition follows public 0.5.1; build the native CLI from source.

```sh
moonsize app.wasm --duplicates --top 20
moonsize app.wasm --duplicates-json new-duplicates.json
```

Only exact local body bytes (locals declarations plus instructions) determine
membership. Length prefixes, names and declared type indices do not. SHA-256 and
length select candidates; every match is confirmed against the actual bytes.
The actual fixture groups functions #8/#9 despite different type indices and
1/2-byte prefixes, retaining their measured 5/6-byte encodings separately.
No names are required. Top limits text groups only; JSON keeps all members and
refuses existing targets. This independent mode rejects strict and other modes.
Identical bytes do not establish semantic equivalence, safe merging or savings;
absence of identical bodies does not establish absence of semantic duplication.
See [the byte ledger, actual sample and API](docs/duplicate-functions.md).

## Exported entrypoint dependencies

This source addition follows public 0.5.1; build the native CLI from source.

```sh
moonsize app.wasm --entrypoints --top 20
moonsize app.wasm --entrypoints-json new-entrypoints.json
moonsize app.wasm --entrypoints --strict
```

Aliases of the same function form one entry group. The report separates each
entry's model-reachable local function bytes into exclusive and shared portions,
including sharing with start/all conservative element roots. Imports retain null
body sizes. One graph is built; each unique entry requires one reachability walk,
and Top limits display, not analysis costs. JSON keeps complete membership and
aliases and refuses existing targets. Strict gaps return 3 before file checks.
The actual shared example has 34 local encoded bytes: 31 in the export union,
3 outside it; the union is 18 exclusive + 13 shared bytes counted once. These
are overlapping model sets, not deletion or gzip savings. See [the actual sample,
ledger, API and limits](docs/entrypoints.md).

## MoonBit generic-instance sizes

This source addition is not part of the published 0.5.1 package. Build the native
CLI from source to use it:

```sh
moonsize app.wasm --generics --top 20
moonsize app.wasm --generics-json new-generics.json
```

The independent mode accepts only Top and generics JSON; even strict is rejected
because no call graph is built. Families use fully parsed **raw symbols**, never
matching display names. The first supported shape is numeric-package free
functions/methods with Int or Double type arguments. The real probe identifies
four definitions in two families, totaling 26 encoded bytes. Counts distinguish
function definitions from distinct raw type-argument encodings. Top limits text
only; JSON preserves every family and instance and refuses existing targets.
Missing/unreadable names and unsupported symbols are reported, not guessed.
Family keys apply within one artifact; totals do not predict removable bytes.
See [the observed encoding, size ledger and limits](docs/generic-instances.md).

## Explaining a function's reference path

For an arbitrary non-root FROM -> TO query use [path-between](docs/function-path-between.md);
why-index and why-root retain their model-root rules.

`--cycles --cycle-witness` instead closes a representative path inside each
component, without selecting roots or claiming all members are visited. It is
a separate query; inspect real opcodes manually with the returned offsets.
[Closed witness rules](docs/function-cycles.md#optional-closed-evidence-paths-source-addition-after-public-051).


For whole-module mutually reachable groups instead of one root path, run
`--cycles` separately. It includes unreachable functions and model self-loops;
reference/candidate cycles do not prove runtime recursion. Component weights
are local encoded bytes, not retained size. [Cycle query](docs/function-cycles.md).


After locating a large function's index in the report, ask which modeled entry
can introduce it:

```sh
moonsize app.wasm --why-index 47
moonsize app.wasm --why-index 47 --why-root 0
moonsize app.wasm --why-index 47 --why-json function-path.json --strict
```

Indices above are illustrative. The query returns one deterministic path with
the fewest edges. Roots are ordered by function index; outgoing edges by target
index, then direct/reference/indirect kind, then original instruction offset.
Every step retains its actual opcode (`call`, `return_call`, `ref.func`,
`call_indirect`, or `return_call_indirect`) and file offset. Indirect edges are
known candidates; `ref.func` takes a reference rather than proving a call.
Unmodeled `call_ref` targets are not guessed, and graph diagnostics remain visible
even when a path is found.

The default searches all existing model roots: function exports (including all
aliases), the start function, and conservative element references. If the target
is itself an element root, a zero-edge path is expected and its source is shown.
`--why-root` selects one **actual** model root without changing global reachability
or retained sizes. Failure from that entry does not imply global unreachability.
Root evidence records the section start and export/element ordinal; these are
explicitly section positions, separate from instruction offsets.

Results distinguish `found`, `not-found-within-model`, and `search-limited`.
An incomplete graph may still yield either of the first two; an absent path is
then particularly inconclusive. Imports have `encoded_size: null` because their
bodies are outside this module. Path JSON has its own format
`moonsize-function-path` and `schema_version: 1`, structured root reasons,
ordered nodes/steps, diagnostics, limits and search counters. Existing JSON paths
are refused. Strict graph refusal occurs before creating a report.

Query mode accepts only `--why-index`, `--why-root`, `--why-json` and `--strict`;
other report, comparison, experiment and budget flags conflict before input is
read (including an explicit `--top`). Exit codes are 0 for a completed query
(found or absent), 1 for input/index/root/output errors, 2 for invalid arguments,
and 3 for a limited search or strict refusal of an incomplete graph.

The library entry is `explain_function(data, target_index, root?, limits?)`;
render with `render_function_path` or `render_function_path_json`, and describe
errors with `describe_function_path_error`. It builds the canonical graph from
bytes without computing dominators. `PathLimits::new()` defaults to 100,000 nodes,
1,000,000 edges and depth 256. The node limit separately bounds prepared roots
and visited nodes; the edge limit separately bounds root-source records, indexed
edges and examined edges. Preparation limits return `search-limited` too. These
limits do not bound binary parsing or construction of the existing call graph;
sorting also has its own cost. Existing parsing/analysis signatures are unchanged;
`Options` gains the three optional query fields. Clients inspecting options or
matching the new status/error enums should handle the added fields/variants.

This is a path in the current reference model, not an execution trace or a
prediction of recompiled or gzip savings. Measure actual changes by rebuilding
both complete artifacts.

```sh
node scripts/test-function-path.mjs _build/native/release/build/cmd/main/main.exe
node scripts/demo-function-path.mjs _build/native/release/build/cmd/main/main.exe
```

The source demo discovers emitted indices instead of hardcoding them, queries
an exported entry through `path_upstream` to `path_target`, removes the upstream
call, rebuilds, writes an optimization experiment, then restores the source and
checks exact bytes and path evidence. Base output is preserved; optional output
is intentionally removed, so this is not a claim of full behavioral equivalence.
Sources, paths, hashes, outputs and before/after experiment reports stay under
`_build/function-path-demo/`; CI uploads this evidence. Path bytes are never
summed as a deletion benefit.

## Using the library

The parsing, the analysis and every report are ordinary packages in this module,
so a program can take the numbers instead of the text. `moon add
BigSaltyMan/moonsize` and import it; `Options::default` is the way in, because
`Options` is read-only and no other package may write one.

```moonbit
fn main {
  let bytes : Bytes = read("app.wasm")
  match @moonsize.parse_module(bytes) {
    Ok(parsed) =>
      match @moonsize.analyze(bytes, parsed) {
        Ok(analysis) => {
          let options = @moonsize.Options::default("app.wasm")
          // What the five heaviest functions cost, as text or as numbers:
          // `analysis.stats` and `analysis.retained` are there to be read.
          println(@moonsize.render_top_functions(analysis.stats, analysis.data.length(), 5))
          println(@moonsize.render_graph_warning(analysis.graph))
          println(@moonsize.render_dead_code(analysis, 5))
          println(@moonsize.render_retained(analysis, 5))
          println(@moonsize.render_html(analysis, options.path))
        }
        Err(error) => println(@moonsize.describe_error(error))
      }
    Err(error) => println(@moonsize.describe_error(error))
  }
}
```

The library does no I/O, so reading the file and choosing an exit code stay with
the caller. `supported_targets = "+native"` applies to a program that depends on
this module too: build it with `--target native`.

## Analysis

Everything below is built on one idea: a function's bytes only matter if
something can call it.

### Symbol names

Attribution starts with the names in the binary's name section, and MoonBit does
not publish how it mangles them, so the rules here were read back from the name
section of real builds (`moonc` 0.1.20260920, the `wasm` backend):

- a symbol is `_M0<kind>` and then a path: `F` a function, `M` a method, `I` a
  trait implementation;
- the package is `B` for the builtin package, `C` for `moonbitlang/core`, or `P`
  and an index — which runs into the first component's own length, so `P55probe`
  is index `5` followed by `5probe`;
- a component is its length and then its name, and the length counts the *mangled*
  name;
- anything that cannot appear in an identifier is escaped as `_` and the byte in
  hex, and a literal underscore is doubled: `to__string_2einner` is
  `to_string.inner`, `_24default__impl` is `$default_impl`, and a non-ASCII
  character is escaped one byte at a time, so `中` is `_e4_b8_ad`;
- a generic instantiation carries `G...E` with one code per argument, where a
  builtin is a single letter, a tuple is `U...E`, and a named type is `R` and a
  path;
- a closure is either an environment named `__moonbit_<fn>` or a body carrying
  `C<id>l<line>`, the id of the closure and the line it was written on;
- a trait implementation names two packages, its type's and its trait's.

The reports print the path through `display_name`. `demangle_full` is the fuller
decoder, for callers that want escapes resolved, arguments spelled out and
closures marked. Both are display aids rather than a codec: when one cannot
decode a symbol exactly it returns it untouched, because a report that invents a
name is worse than one that shows a raw symbol. The known limits are where that
happens — a generic argument whose type code is not one of the letters a build
produced (`Int`, `Double`, `String`, `Bool`, `Char`, `Byte`, `Float`, `Int64`,
`UInt64`, `Unit`) is left undecoded rather than guessed, a named argument is only
decoded as the last one in its list because its path has no terminator to
separate it from what follows, and a symbol over 4096 bytes is refused outright
so a forged name cannot drive the walk into a deep recursion.

### The call graph

The decoder walks every function body instruction by instruction — the full MVP
instruction set, the `0xFC` saturating and bulk-memory opcodes, the exception
handling and tail-call opcodes MoonBit emits, and the `0xFB` garbage-collection
opcodes its `wasm-gc` backend uses. Each body contributes:

- `call x` and `return_call x` — precise edges to `x`;
- `ref.func x` — a reference, which counts as reachable because the function may
  run later as a closure;
- `call_indirect` and `return_call_indirect` — *conservative* edges to static
  element candidates in the selected table;
- `call_ref` and `return_call_ref` — recognised call sites with an
  `UnmodeledReferenceCall` diagnostic. Target analysis is not implemented,
  including when `ref.func` immediately precedes the call. No target is guessed.

Static element segments supply **known candidates**, not proof of a complete
target set. Imports, exports, runtime writes or unmodelled explicit initializers
can make that set incomplete. This version conservatively diagnoses each such
risk for ordinary and tail indirect calls, even when candidates are nonempty;
known candidate edges remain in the graph. Calls with no static candidates also
retain their separate diagnostic. Dead-code and retained-size results may be
inaccurate. The report says so above everything else:

```
WARNING: the call graph has 1 analysis gap.
  function 0, offset 42: call_ref: reference-call target analysis is not implemented.

Dead-code and retained-size results may be inaccurate; do not use them as proof that a function can be removed.
```

`--dead-code` and `--retained` repeat it under their titles, and `--strict` turns
these recognised incomplete cases into a refusal — no report, exit code 3.

Writes are collected from all functions before checking any table call:
`table.set`, `table.init`, `table.copy` (destination only), `table.grow` and
`table.fill`. Reads via `table.get` and `table.size` are not writes. A writer
that appears after the call, or in an unreachable function, still causes a
conservative refusal: this version does not prove whether that write executes.
Imported tables precede local tables in their own index space, independently of
function imports. Explicit initializer expressions are consumed completely and
reported as unmodelled; their targets are not guessed.

`call_ref` and `return_call_ref` make the graph incomplete even if every table
call has candidates. `analyze` still returns `Ok(Analysis)`: a modelling gap is
distinct from malformed input. Diagnostics retain their category, full caller
index, file offset, actual opcode, type index and optional table index.

`graph_complete` means no gaps were detected within the current scope:
`analysis.graph.diagnostics` is empty. Dynamic table writes, host-provided
contents and explicit initializers are diagnosed but not solved. Other Wasm
modelling limitations remain. A successful `--strict` run is not a completeness
certificate.

A function is a **root** if the outside world can reach it: it is exported, it is
the start function, or it is referenced by an element segment. Reachability and
retained sizes describe paths in the current graph model.

### Parser bounds and Reader API

`Reader::read_u32_leb()` returns `Result[UInt, WasmError]` across the full
`0..4294967295` range. Non-shortest encodings remain accepted within five bytes;
illegal fifth-byte high bits or continuation produce `LebOverflow(offset)`.
Lengths, counts, indices and integer instruction operands pass through one
checked internal conversion and currently support `0..2147483647`. Larger
valid u32 encodings produce `ValueOutOfRange(offset, value)`, an implementation
limit rather than a claim that the unsigned encoding is invalid Wasm.

`Reader::new(data)` still covers the whole buffer. The new
`Reader::new_range(data, start, length)` returns `Result[Reader, WasmError]`
and restricts reads to `[start, start + length)`. Negative or out-of-buffer
requests return `InvalidReadRange(offset, length, start, end)`.
`seek(offset)` now returns `Result[Unit, WasmError]`; handle that result when
migrating callers. Seeking to the end is allowed; reading there returns
`UnexpectedEnd`. Failed seek and `read_bytes` operations leave the cursor
unchanged. Every reported offset is absolute within the file.

Section payloads, function bodies, locals, instruction immediates and optional
name subsections use bounded readers. The outer custom-section name is
structural and must fit its payload. Optional name metadata remains tolerant of
damaged entries, preserving earlier names without borrowing following bytes.
Parsing and range failures return CLI exit code `1`, including with `--strict`,
and never create or overwrite JSON, DOT or HTML reports. They are distinct from
call-graph gaps refused with code `3`.

`parse_module` accepts Core Wasm binary version `1` only and checks standard
section uniqueness and order. Custom sections may repeat, including with the
same name, anywhere between standard sections. The explicit order is Type,
Import, Function, Table, Memory, Tag, Global, Export, Start, Element, DataCount,
Code, Data; numeric section ids alone do not give this order.

Local function declarations and code bodies must have equal counts; imports
are excluded. Both payloads must be consumed completely, and every code body
must fit its declared range. Missing sections count as zero. Current inputs
and `--baseline` use the same checks before reports are printed or written.
`analyze(data, parsed)` also revalidates the bytes and derives its section table
from them, so stale or modified metadata cannot bypass these checks.

These are the basic structure checks needed for size analysis. The tool does
not yet provide full WebAssembly type and instruction-semantic validation.
Type/call index validity, signed LEB numeric semantics and full 64-bit constant
storage remain limited; dynamic table analysis also retains its documented
limitations.

Parsing function signatures are unchanged. External exhaustive matches on
`WasmError` must handle five new variants:

| Variant | Fields |
|---|---|
| `UnsupportedVersion` | version-field offset, raw unsigned `UInt` value |
| `DuplicateSection` | second section's id-byte offset, kind |
| `InvalidSectionOrder` | current id-byte offset, kind, preceding standard kind |
| `FunctionCodeCountMismatch` | related section's id-byte offset, kind, local declaration count, body count |
| `TrailingSectionBytes` | first unconsumed payload byte offset, kind |

Version errors point to offset `4`; mismatch errors use the code section when
present, otherwise the function section. These failures return input error
`1`, including under `--strict`, rather than graph-incompleteness code `3`.

### Diagnostic API and export migration

`build(data, bodies, elements)` is replaced by `build(data)`. Pass complete
module bytes: the public entry parses canonical bodies, elements and table
context, so callers cannot omit writers or imply completeness with an empty
context. `analyze(data, parsed)` keeps its signature and uses the same internal
rules. `count_imported_functions` still counts function imports only.

`CallGraph.diagnostics` counts **reason entries**, not call sites. One call can
have multiple reasons or distinct writer sources. Export aliases collapse to
one host-exposure reason per table; runtime writers deduplicate by file offset.
`Analysis.unresolved_count` is unchanged: only table calls with no static
candidates, even when other reasons make the graph incomplete.

External exhaustive matches on `GraphDiagnosticKind` need the new variants:

| Variant | Stable JSON code |
|---|---|
| `NoStaticTableTargets` | `no_static_table_targets` |
| `UnmodeledReferenceCall` | `unmodeled_reference_call` |
| `ImportedTableContents` | `imported_table_contents` |
| `ExportedTableContents` | `exported_table_contents` |
| `RuntimeTableMutation` | `runtime_table_mutation` |
| `UnmodeledTableInitializer` | `unmodeled_table_initializer` |
| `UnknownTableContents` | `unknown_table_contents` |

The last reason covers a target absent from the parsed context, without claiming
full index/type validation. `GraphDiagnostic.source : GraphDiagnosticSource?`
records provenance separately from the call's own `caller`, `offset`, `opcode`.
Writer sources have their full function index, opcode and absolute file offset.
Import/export sources point to their descriptor kind byte; initializer sources
point to the expression start, with no function/opcode. Unsupported or malformed
table encodings return `InvalidTableEncoding(offset, reason)` (CLI `1`), while
analysis gaps return `Ok(Analysis)` and strict refusal `3`. Table metadata handles
multi-byte reference types and i32 limits; table64/shared limits are explicitly
unsupported rather than silently misread. Exhaustive `WasmError` matches must
add `InvalidTableEncoding`.

`scan_calls` now returns `CallKind::Reference` for `call_ref` and
`return_call_ref`, with `type_index = Some(type)` and the original offset.
External exhaustive matches on `CallKind` must add this branch. `ref.func`
continues to create a reference edge, not a call site.

Use `render_graph_warning(analysis.graph)`, `render_dead_code(analysis, top)`
and `render_retained(analysis, top)`. The last two read diagnostics internally;
the old separate arrays, file-size argument and optional `unresolved` count
are removed. The library example above and `_probe/` use these signatures.

JSON exports retain `module`, `functions`, `roots`, `edges` and `indirect_sites`,
and add `schema_version: 1`, `graph_complete`, `modeling_scope` and `diagnostics`.
Each diagnostic has `code`, `caller`, `offset`, `opcode`, `type_index` and
`table_index` (null for reference calls). Provenance-bearing reasons add
`source: {caller, offset, opcode}`; metadata sources have null caller/opcode.
Existing no-target/reference diagnostics retain their original shape. Complete
graphs carry an empty array. Diagnostics sort by caller, call offset, stable
reason code, then source offset. JSON and HTML keep schema version `1` with
these additive reason/source fields.

Non-strict JSON, DOT and HTML exports carry their own limitations: JSON contains
structured diagnostics and scope, DOT has a graph-level warning label, and HTML
shows diagnostics at the top and limits alongside dead-code results. Sharing an
export preserves this information. Strict refusal occurs before writing a new
file or changing an existing one, for all three formats.

### Retained size

`SIZE` is a defined function's encoded size, including its body-length prefix.
`RETAINED` sums those encoded sizes for the reachable defined functions dominated
by the selected function in the current graph/root model, including itself.
`DIES` counts the other functions in that model set.

The dominator computation answers a question about a fixed graph: every path
from a root to a dominated function passes through the selected function. Its
graph result does not model editing callers, recompiling, changing indices or
removing data and metadata. Element functions are conservatively rooted even
for private/passive/declarative segments. A clean diagnostic list or successful
`--strict` therefore does not turn this result into exact deletion savings.

Reading the table:

- `RETAINED == SIZE` — the model attributes no other function's encoded bytes to
  this dominator; an actual source change may affect other sections and callers.
- `RETAINED ≫ SIZE` with a high `DIES` — investigate the corresponding dependency
  branch, then rebuild to measure the actual effect.
- `IND` — the function can be reached through a `call_indirect`, so removing it
  requires checking every dependent table entry and indirect call before removal.

Actual raw-file reduction is `before.wasm` size minus rebuilt `after.wasm` size.
Whole-file gzip reduction is measured separately on the two complete files with
the same compressor settings. Neither is predicted by retained size or by
summing independently compressed functions. Reproducible cases and the exact
definitions are in [the boundary report](docs/retained-size-boundaries.md).

### Dead code

The list contains functions unreachable from roots within the current model.
Inspect diagnostics and modelling limits before considering removal; an
incomplete graph does not prove a function can be removed.

MoonBit's compiler does dead-code elimination well, so a small program usually
reports none — that is a finding too.

### Compressed size

`--compress` measures the complete Wasm file as one gzip stream using the current
compressor defaults. Actual servers may use gzip with other settings, another
content encoding, or no compression. Section measurements are independent gzip
streams for observing local compressibility.

Measured from `examples/fib.wasm` with `--compress`:

```
COMPRESSED SIZE
  raw   10675 B
  gzip   5207 B  (48.7% of raw, ratio 2.05x)

  BY SECTION — INDEPENDENT GZIP STREAMS

  SECTION              RAW  GZIP  RATIO
  code                5166  2712  1.90x
  custom (name)       4975  1983  2.50x
  data                 252   174  1.44x
  custom (producers)    71    95  0.74x
  type                  59    66  0.89x
  function              50    63  0.79x
  import                37    61  0.60x
  export                21    45  0.46x
  global                13    34  0.38x
  element                8    32  0.25x
  table                  7    31  0.22x
  memory                 5    29  0.17x
  datacount              3    27  0.11x

  Section gzip sizes are measured independently and are not additive.
  They do not represent shares of the whole-file gzip size.
```

Each section range includes its id, length prefix and payload, including a
custom section's name. HTML function gzip covers the encoded function range
including its length prefix (`total_size` / HTML `size`); its ratio uses that
same raw range, not `bodySize`. `RATIO` is raw bytes divided by gzip bytes. Small
streams may grow because each has its own header and trailer; their actual size
and ratio below `1` remain visible.

Independent streams are not additive and do not represent whole-file transfer
shares or the bytes saved by removing a function. Gzip can exploit redundancy
across ranges when compressing the whole file. To measure an optimization's
benefit, compare the complete build artifacts before and after the change.

A failed measurement stays a failure: text shows `failed` and a reason for the
specific section; a failed whole-file card shows `N/A` with its own reason.
Other successful measurements remain available. HTML sections, functions and
treemap leaves pair `gzip` with `gzipError`: success is a number and `null`;
failure is `null` and the local reason. This additive HTML data extension and
its `compression_scope` explanation are separate from call-graph JSON exports.
Public parsing and compression signatures are unchanged; `compress_sections`
now returns `Err` for invalid metadata ranges instead of measuring empty bytes.

### Judging what can be deleted

1. Check graph diagnostics, root assumptions and the runtime integration contract.
   `--dead-code` lists functions unreachable in this model; it is not a safe-deletion list.
2. Then look at `--retained` for large `RETAINED` values with `DIES` above zero.
   These identify modelled dependency branches to investigate, not promised savings.
3. Treat `IND` rows with care: an indirect candidate can only be removed when the
   table entry and the call sites go with it.

## Example output

A 10,675-byte MoonBit program (`--target wasm`, debug), reduced to the analysis
sections:

```
Retained size

    #  INDEX  SIZE  RETAINED  DIES    SHARE  IND  FUNCTION
    1     47   158      5162    46    48.3%       ____moonbit__main
    2     39   301      1773    10    16.6%       int::Int::to__string_2einner
    3     37    24       887     8     8.3%       println
    4     34     9       819     5     7.6%       moonbit.println
    5     33   206       810     4     7.5%       moonbit.fprintln
    6     28    49       717     7     6.7%       moonbit.decref
    7     29   409       668     6     6.2%       moonbit.gc.free
    8     43   633       633     0     5.9%       int__to__string__dec

  DIES counts the other functions that become unreachable with this one.
  IND marks a function an indirect call could reach.

Dead code

  0 of 47 functions are unreachable from the roots
  0 bytes (0.0% of file)

  every function is reachable
```

`____moonbit__main` retains 5,162 bytes — 48.3% of the file, 46 functions — which
is what a program with a single entry point looks like: everything hangs off it.
`int__to__string__dec` is the largest single function at 633 bytes but retains
only itself, so shrinking it is a compiler problem rather than a deletion.

`--call-graph graph.dot` writes the same graph for Graphviz, with dead functions
dashed and indirect edges dotted; `--call-graph graph.json` writes it with the
roots, every edge and every indirect site's candidate set.

## HTML report

```sh
moonsize examples/fib.wasm --html new-report.html
```

The original analysis page starts with the full input path, section navigation
and four exact byte counts: **File size**, **Code section**, **Whole-file gzip**
and **Unreachable in model**. The analysis status follows the cards. Detected
graph gaps and their actual diagnostic positions remain visible; “No detected
graph gaps” means only that no gaps were detected within this model. Model
results identify investigation candidates, not guaranteed deletion savings.

Then read the sections and module composition, Top 20 functions, module map,
and expandable methods. Section and function bars have independent row heights.
The section legend and keyboard-accessible comparison button share one byte
axis for raw and independent gzip, including small streams that grow.
Independent gzip sizes are not additive and are not whole-file transfer shares.
Each failed measurement retains its own reason.

**Full function names without hovering.** Expand or collapse the function table
below the ranking. Its same Top 20 local functions expose index, full name/module,
body bytes, encoded bytes, independent gzip and model reachability. Long names
wrap and can be selected/copied; the table scrolls locally on narrow screens.
Ranking uses body bytes, while independent gzip ratios use the full encoded
range, including its size prefix. Function indices include preceding imports;
the displayed function count explicitly counts local functions.

**Module shares and colors.** The ring divides attributed function encodings,
excluding code-section overhead. Its tooltip separately computes a share of
the complete code section. The ring and module→function treemap use the same
identity-based module colors, independent of rank. Treemap area remains raw
function encoding; unreachable functions also have text and outlined cells,
which do not imply removal savings.

The native CLI always embeds pinned ECharts 5.6.0 from its executable, regardless
of the working directory. It never reads a nearby assets/ file or downloads a
chart library. The report contains its library, styles, scripts and data without
remote fonts or sibling files. Copying that one HTML file is sufficient.
The library API remains compatible: render_html without an echarts source still
selects CDN mode; pass a source explicitly for an offline library-generated page.
Missing/broken chart code still leaves a clear fallback and readable cards,
function table and methods.

A4 printing redraws charts at paper width, hides hover controls, opens required
disclosures, repeats table headers and includes a complete module legend. It
restores the screen layout and disclosure states afterwards. Actual relocated
offline rendering and two browser-generated PDFs have been checked; see
[delivery evidence and reproduction](docs/html-delivery.md). Node and browser
test tools are not required to generate reports with the native CLI.

The current [generated example](examples/report.html) uses the unchanged
[stored input](examples/fib.wasm), SHA-256
`0e6f10e56434b67adb162cdb56a46553ef38b8de1abd0d0deb1fe56d7173d10c`.
It measures 10,675 B file, 5,166 B code, 5,207 B whole-file gzip and 0 B
unreachable local function encodings. [Page usage and verification limits](docs/html-report.md)
record the real HTTP-browser checks, screenshots and tested offline/print scope.

![Current report at 1440 px](examples/report-desktop.jpg)

![Current report at 390 px](examples/report-mobile.jpg)

Both screenshots were captured from the generated report in a real browser at
`http://localhost:5173/`.

## CI integration

`--max-size` turns the report into a gate, and `--baseline` turns it into a
comparison, so a build can fail on growth instead of on a number somebody has to
keep updating by hand.

```sh
moonsize app.wasm --max-size 100KB                     # a ceiling on the file
moonsize app.wasm --baseline main.wasm --max-size 5KB  # at most 5 KB of growth
```

With a baseline, `--max-size` bounds the *change*, not the file: the question a
pull request asks is what it costs, not how big the program already was. A run
with a baseline prints the comparison after the report, largest current group first,
with the change as bytes and as a share of what it was:

```
SIZE COMPARISON

                      baseline  current  delta
  total                  10675    11039  +364  (+3.4%)
  code                    5166     5299  +133  (+2.5%)
  custom (name)           4975     5205  +230  (+4.6%)
  data                     252      252  0  (0.0%)
  custom (producers)        71       71  0  (0.0%)
  ...
```

Standard sections compare by kind. Custom sections group by their complete,
case-sensitive names: repeated names produce one row containing their summed
encoded sizes. Empty names are valid, and a custom section named `code` remains
separate from the standard code section. Sizes include each section's actual
id, length encoding and full payload, including the custom name encoding;
legal non-shortest length encodings therefore count their extra bytes.

For example, two `x` sections of 4 and 6 bytes compared with two of 5 and 8 bytes
produce one row:

```text
              baseline  current  delta
  custom (x)        10       13  +3  (+30.0%)
```

This compares a name's total encoded size without attempting to pair individual
same-name custom sections across builds. Reordering sections does not change
the result. Ties use descending baseline size, then standard binary section
order followed by custom name order (`String::compare`). Deleted groups remain
visible against zero.

`total` is the entire file, including its eight-byte header. Group increases
and decreases may cancel, and equal group sizes do not imply equal content.
With a baseline, `--max-size` still limits only the whole-file growth, including
when some groups grow while the total is unchanged.

### Function and package changes

```sh
moonsize current.wasm --baseline previous.wasm --diff-functions --top 20
```

This appends `FUNCTION SIZE CHANGES`, `PACKAGE SIZE CHANGES`, `MATCHING SUMMARY`
and `CODE OVERHEAD`. Without `--diff-functions`, baseline output stays at the
existing file/section comparison. The option requires `--baseline` and rejects
`--html` or `--call-graph` with exit `2` before reading inputs. Other text options
combine normally. `--top 0` keeps totals and matching coverage but hides both
detail rankings; positive limits apply independently to functions and packages.

Matching uses the exact, nonempty original symbol only when it appears once
among local functions on **each** side. Function indices and offsets only locate
records within a build. Display names, sizes and order never establish identity.
Unique one-sided symbols are `added-symbol` or `removed-symbol`; a duplicate on
either side makes all related records `ambiguous`, even if absent on the other
side. Missing or empty names are `missing-symbol`. Both unmatched categories
retain separate per-side records and byte counts; neither is also called an
addition/removal. The actual symbol `(unnamed)` remains distinct from no symbol.
Added/removed symbols may reflect renames or compiler changes rather than source
functions being added/deleted. Stripped binaries still have accurate totals and
package summaries, with an explicit lack of function identity coverage.

Function sizes include the body length prefix, locals and instruction bytes
(`total_size`); package summaries independently aggregate **all** functions by
the existing best-effort `module_name`, including `(unnamed)` and `(top-level)`.
Ranking uses absolute byte delta, then case-sensitive UTF-16 lexical symbol or
package order; duplicate identity ties use status and per-build indices. It does
not depend on Map traversal. Raw symbols are quoted and escaped in text.

The structured results reconcile:

```text
package encoded-byte sums = local function total_size sums
code section = function encoding + code overhead (header/count encoding)
function delta = matched delta + added bytes - removed bytes
               + unmatched current bytes - unmatched baseline bytes
```

Name/data and other section changes belong to the existing section comparison;
function deltas do not sum to the whole-file delta. `--max-size` still budgets
only whole-file growth, including growth outside code. Current-input strict
behavior is unchanged; comparison itself does not build a baseline call graph.
Both files are read once, and fallible comparison preparation finishes before
any normal report is printed.

Library callers use `compare_modules(baseline_data, current_data)` returning
`Result[ModuleSizeDiff, ComparisonError]` (`Baseline(WasmError)` / `Current(WasmError)`).
The result exposes file totals, `baseline_code` / `current_code`
(`CodeSizeSummary`: section, function count/bytes, overhead), `functions`
(`FunctionSizeChange` with status, raw symbol, optional per-side `FunctionStat`,
delta), `packages` (`PackageSizeChange`) and `matching` (`MatchingSummary`,
per-category count/byte coverage and matched delta). `render_function_diff(diff,
top)` renders the same text. Validation covers basic module structure and bounded
function/import parsing, without full Wasm type/instruction validation.

API migration: `FunctionStat.raw_name : String?` preserves a nonempty symbol
before `display_name`, alongside unchanged display, package and size fields.
Internal record constructors must supply it; never reconstruct it from `name`.
Malformed UTF-8 in optional function-name metadata stops name collection at that
entry, retaining earlier names and leaving the damaged suffix unmatched; it is
not lossily converted into a fabricated shared identity. Valid Unicode names,
including a literal replacement character or BOM, retain their exact identity.
`Options` adds `diff_functions`, defaulting to false. Existing parse, analyze,
compression and budget signatures remain unchanged.

For a source-built demonstration, run:

```sh
moon build --target native --release
bash scripts/demo-function-diff.sh _build/native/release/build/cmd/main/main.exe
```

The script copies [before.mbt](examples/function-diff/before.mbt) and
[after.mbt](examples/function-diff/after.mbt) into the **same** temporary project,
builds both with `--target wasm --debug --no-strip`, verifies real name sections
with V8, runs comparison, then restores the source and checks the complete
artifact and symbol differences return to zero. Artifacts and measured reports
remain under `_build/function-diff-demo.*`. With MoonBit `0.10.13+cbb11c36f`, the
measured example is 4,977 → 10,785 file bytes; `classify` is 29 → 55 encoded bytes,
the new `weighted_score` symbol is 103 bytes, and `demo::functiondiff` is
29 → 158 bytes. All function encoding grows by 2,125 bytes, including runtime
helpers; this differs from the 5,808-byte whole-file growth. These are measured
demo results for that toolchain, not fixed cross-version expectations.

The exit codes are `0` ok, `1` unreadable input, `2` bad command line and `3`
over budget or refused by `--strict`, so a job can tell a broken input apart
from a broken build.

This repository gates itself in [`.github/workflows/ci.yml`](.github/workflows/ci.yml):
formatting, `moon check --target native --deny-warn`, `moon test`, and the
freshly built debug Wasm example held to a budget. The local setup action pins
MoonBit `0.10.13+cbb11c36f` to match local formatting and tests, and runs
`moon update` before dependency resolution. A toolchain upgrade should update
local checks and CI together.

```yaml
- uses: ./.github/actions/setup-moonbit
- name: Build the example and CLI
  run: |
    moon build --target wasm
    moon build --target native --release
- name: The example stays inside its budget
  env:
    EXAMPLE: _build/wasm/debug/build/examples/examples.wasm
    CLI: _build/native/release/build/cmd/main/main.exe
  run: |
    test -s "$EXAMPLE"
    printf 'budget input: %s\nbytes: %s\n' "$EXAMPLE" "$(wc -c < "$EXAMPLE")"
    sha256sum "$EXAMPLE"
    "$CLI" "$EXAMPLE" --max-size 100KB
```

The budget job reads that build artifact directly; `examples/fib.wasm` remains
the published example copy. Its reverse check uses `0B`, explicitly captures
the native CLI's status, and requires exactly `3` plus the budget-failure reason.
Missing files, launch errors and command-line errors fail the job. Debug and
release artifact paths must track the build mode if it changes.

For another project that produces a `.wasm`, install the compatible toolchain
with the official installer before applying its size budget:

```yaml
- name: Setup MoonBit
  run: |
    curl -fsSL https://cli.moonbitlang.com/install/unix.sh | bash -s '0.10.13+cbb11c36f'
    echo "$HOME/.moon/bin" >> "$GITHUB_PATH"
- run: moon update
- run: moon build --target wasm --release
- name: Size budget
  run: moonsize _build/wasm/release/build/app/app.wasm --max-size 250KB
```

To catch growth rather than an absolute size, build the base branch too and pass
it as the baseline; `--max-size` then reads as the allowance:

```yaml
- name: Build the base branch
  run: |
    git worktree add "$RUNNER_TEMP/base" "origin/${{ github.base_ref }}"
    (cd "$RUNNER_TEMP/base" && moon build --target wasm --release)
- name: Size budget
  run: |
    moonsize _build/wasm/release/build/app/app.wasm \
      --baseline "$RUNNER_TEMP/base/_build/wasm/release/build/app/app.wasm" \
      --max-size 5KB
```

[`.github/workflows/size-check.yml`](.github/workflows/size-check.yml) does that
on every pull request. Both sides use the same installed toolchain and default
debug Wasm mode. Each build artifact must exist and be nonempty before copying;
the workflow logs source paths, comparison paths, byte counts and SHA-256 hashes.
The native CLI compares `$RUNNER_TEMP/current.wasm` against
`$RUNNER_TEMP/baseline.wasm`. If a historical baseline has no
`examples/moon.pkg`, the log explicitly says it uses the repository's historical
example without rebuilding that branch's source. A baseline with that package
must build successfully; build failures do not fall back to the stored binary.

## Development

The key decisions, the known limits of the symbol rules, the role AI tools
played, and the provenance of everything vendored are written down in
[`docs/devlog.md`](docs/devlog.md).

```sh
moon check --target native --deny-warn
moon test
moon build --target native --release
bash scripts/test-tail-calls.sh _build/native/release/build/cmd/main/main.exe
bash scripts/test-graph-diagnostics.sh _build/native/release/build/cmd/main/main.exe
bash scripts/test-parser-boundaries.sh _build/native/release/build/cmd/main/main.exe
```

The diagnostic CLI script requires Node.js to validate its Wasm fixtures with
V8 and assert fields in parsed JSON. The parser script also uses Node.js for a
five-second timeout per CLI process, distinguishing timeouts, crashes and
expected input errors. All three scripts run in Git Bash or Linux after building
the native executable. Complete-module fixtures are cross-checked with V8;
Reader-only and optional metadata tests are kept separate.

The test suite covers the instruction table one opcode at a time — every entry
carries a canonical encoding and the length the specification gives it — and pins
three real MoonBit function bodies, including one whose locals use two-byte
garbage-collection reference types, so a wrong immediate width fails a test
instead of quietly producing a wrong call graph.

### Regenerating the example

The numbers quoted in [`examples/report.html`](examples/report.html) and in this
README — the file size, the section shares, the retained sizes — are read out of a
real build rather than written by hand. Changing
[`examples/fib.mbt`](examples/fib.mbt) or moving to a new toolchain makes them
stale. Build, copy the artifact, then generate the report:

```sh
moon build --target wasm

stage=$(mktemp -d examples/report-update.XXXXXX)
cp _build/wasm/debug/build/examples/examples.wasm "$stage/fib.wasm"

moon run cmd/main -- \
  --html "$stage/report.html" \
  "$stage/fib.wasm"

sha256sum _build/wasm/debug/build/examples/examples.wasm "$stage/fib.wasm"
```

The build and staged input hashes must match. Check the measurements against
that input before replacing either checked-in artifact. Start npm run dev, open
http://127.0.0.1:5173/, then inspect the staged page at
http://127.0.0.1:5173/report-update.XXXXXX/report.html (use the actual directory).
The report records the actual staged input path. After accepting the new report,
run these **explicit replacement steps**; the CLI never removes the old report:

```sh
cp "$stage/fib.wasm" examples/fib.wasm
cp "$stage/report.html" examples/report.html
```

Update report-desktop.jpg (1440 × 1000) and report-mobile.jpg (390 × 844) only
after reviewing the accepted page. Do not overwrite an unrelated report.png.
Keep or explicitly clean up only your own staging directory after review.

`.moonignore` keeps the rendered page out of the published package — it is
1.2 MB of what would otherwise be a 2.4 MB module, and nobody `moon add`s this
for a screenshot — while the source, the example binary and the chart library
all ship.
