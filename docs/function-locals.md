# Local declaration encoding in one function

This is a source addition after public **0.5.1**, not a new Mooncakes release.
Build the current native CLI. The index below is illustrative and includes
preceding function imports:

```sh
moonsize app.wasm --locals 3 --top 20
moonsize app.wasm --locals 3 --locals-json new-locals.json --top 1
```

## Scope and representation

Only local functions with a body are accepted; imported targets return an error.
The report consumes the selected body's locals declarations once, in a Reader
bounded to that body. It does not parse signatures, decode target or other
function instructions, build a graph, or run ordinary analysis. Existing module,
inventory, best-effort name and checked body-range scans still inspect the file;
this is not a promise to read only the selected bytes of the whole input.

Group order, zero-quantity groups, adjacent identical types and actual LEB widths
are preserved. A group remains one record even with quantity **4294967295**.
Records are allocated by the number of groups, never by variable quantity.
Each group keeps quantity/type/whole-group file ranges, raw type hex and a
limited optional type label. Exact single-byte i32/i64/f32/f64/v128/funcref/
externref encodings have labels; other encodings retain hex and `null` labels.
Labels do not infer source types. The existing `Reader.read_valtype` consumer is
reused without changes: this is not full type, heap-type, default-initialization
or constant-expression validation.

Declared ordinals are **half-open intervals excluding parameters**. They are
not complete local indices and do not resolve `local.get`, `local.set` or
`local.tee`. A zero quantity has equal start/end, but its encoding still counts.
No variable array is expanded. Encoded byte sizes do not measure runtime stack
or memory use, execution frequency, deletion, recompilation or gzip savings.
File offsets refer to the original file, not runtime addresses.

The next byte after declaration consumption starts `body_remainder`: an
**undecoded remainder**, not a validated instruction region. Unknown opcodes in
the remainder or another function do not block this query. Truncated quantities,
LEB overflow or a type crossing the selected body fail without borrowing the
next function's bytes or returning a partial report. An empty remainder can be
reported structurally, without asserting valid function instruction semantics.

## Byte and count ledgers

All widths come from the input, including legal non-shortest encodings:

```text
entry.size = prefix.size + body.size
body.size = locals_encoding.size + body_remainder.size
locals_encoding.size = group_count_encoding.size + sum(group.encoding.size)
sum(group.encoding.size) = quantity_encoding_bytes + type_encoding_bytes
declared_count = sum(group.quantity)
```

Zero groups still have an encoded group-count field. This differs from existing
groups whose quantities all equal zero. Neither state says how many parameters
the signature declares.

Group quantities use full u32 values. Accumulation and declared ordinals use
checked u64 arithmetic. JSON uses a u32 **number** for every quantity, and
**decimal strings consistently** for `declared_count_decimal`,
`declared_ordinal_start_decimal` and `declared_ordinal_end_decimal`, including
zero and small values. This prevents a field's type changing with magnitude.

## Reports, errors and API migration

Text prints safely escaped identity, input SHA-256, ranges, ledgers, totals and
the original group rows. Top only limits displayed groups (`showing N of M`),
not totals, parsing cost, the library result or JSON. JSON format is
`moonsize-function-locals`, schema version 1, with complete groups and ranges.
No body contents, expanded variables, parameter counts, guessed local indices
or uncomputed `graph_complete` assurance are exported.

The single-input mode allows input, locals, own JSON and Top; the explicit
comparison below additionally permits a baseline/--baseline-locals pair. JSON
requires
an explicit query and nonempty new `.json` destination. Strict decimal Int index
parsing is independent of Top limits. Other modes, including calls, locate/decode,
preview, unpaired baseline, strict, budgets, compression and HTML, return **2
before input I/O**. Existing separator, unknown-option and first-argument help rules remain.
Completion including zero groups returns **0**; input, invalid/imported target,
declaration or output errors return **1**. JSON mode prints only a save message.
Parsing finishes before shared preflight and native exclusive output creation;
existing files/aliases are not overwritten. No new writer or transaction is added.

```moonbit
inspect_function_locals(Bytes, Int) -> Result[FunctionLocalsReport, FunctionLocalsError]
describe_function_locals_error(FunctionLocalsError) -> String
render_function_locals(FunctionLocalsReport, Int) -> String
render_function_locals_json(FunctionLocalsReport) -> String
```

New types: FunctionLocalGroup, FunctionLocalsReport and FunctionLocalsError.
Errors distinguish wrapped WasmError, invalid target, imported target and range/
count inconsistencies with a real position when available. WasmError is unchanged.
Options adds `locals_index` and `locals_json`, both default None; external complete
struct literals must include them. Existing signatures and JSON formats stay intact.
Use [instructions](function-instructions.md) or [calls](function-calls.md) for a
complete target instruction decode; [locate/decode](file-offset.md) also needs a
successful complete target decode even when its query lands in locals.

## Actual focused verification

The fixed CLI input is **70 B**, SHA-256
`8abadb6bd1361de559518dd99b7812573349d8ac6924372439183f29004c3973`.
One function import precedes target index 1. Entry `[31,46)`, prefix `[31,33)`
(`8d00`), body `[33,46)`, group count `[33,35)` (`8400`), locals `[33,45)`,
undecoded remainder `[45,46)`. The complete group data is:

| Group | Quantity | Declared ordinals, excluding parameters | Quantity hex | Type hex / label | File range | Encoded B |
| --- | --- | --- | --- | --- | --- | --- |
| 0 | 2 | [0,2) | 8200 | 7f / i32 | [35,38) | 3 |
| 1 | 0 | [2,2) | 00 | 7f / i32 | [38,40) | 2 |
| 2 | 1 | [2,3) | 01 | 7f / i32 | [40,42) | 2 |
| 3 | 3 | [3,6) | 03 | 6370 / null | [42,45) | 3 |

**4 groups; 6 = 2 + 0 + 1 + 3 declarations**. Bytes:
**15 = 2 + 13**, **13 = 12 + 1**, **12 = 2 + (3 + 2 + 2 + 3) = 2 + 5 + 5**.
Local function 2 has zero groups, but its count field is one byte at file offset
47. These are encoding facts; no additional V8/type-validation claim is made.

Three new combined tests passed, covering full-u32 quantities and accumulation
to 4294967296 without expansion, multi-byte heap-type consumption, truncation,
body isolation, undecoded unknown opcodes, ordering, JSON/Top, modes and escaping.
Special large-count fixtures are structural tests, not fully validated modules.
Exactly four CLI calls returned **0 / 0 / 0 / 1**: Top 1 text, full JSON with Top 1,
zero groups and an existing JSON sentinel. Node checked fixed source Buffers and
BigInt ordinals independently; input and sentinel remained unchanged.

Evidence: `_build/function-locals-verification/run-WeOB2a/` contains the input,
four logs, argv/status records, `new-locals.json` and `results.json`. Run the new
checks with `moon test --target native function_locals_wbtest.mbt` and
`node scripts/test-function-locals.mjs _build/native/release/build/cmd/main/main.exe`.
No local old suites/scripts, probes, V8 matrix, demos, performance, browser or PDF
checks were run. CI retains old regressions and adds only this four-call script;
confirm the final pushed SHA. Version stays 0.5.1; no dependency or publication change.

## Explicit two-target comparison (source addition after 0.5.1)

```sh
moonsize after.wasm --locals 5 --baseline before.wasm --baseline-locals 3
moonsize after.wasm --locals 5 --baseline before.wasm --baseline-locals 3 --locals-json new-locals-diff.json --top 1
```

The indices here are placeholders, independently selected from each complete
function index space. Names, equal indices or rankings do not establish matching
functions. Both --baseline and --baseline-locals are required with --locals;
a nonempty baseline path is mandatory. Mixing baseline-instructions, instructions,
calls, strict, budgets/max-size, HTML or other modes is still rejected before I/O.
Existing --, help and JSON destination rules are unchanged. Completion including
self-comparison returns 0; side input/target/declaration or output errors return 1;
parameter errors return 2. Comparison JSON mode only prints a save confirmation.
The same locals_json slot, preflight and native exclusive writer protect the
inputs and any existing evidence. Failed inspection returns no partial report.

Each side calls inspect_function_locals once and keeps that complete report.
There is no preliminary single report, ordinary baseline analysis, graph,
signature parse, variable expansion or remainder decode. Raw encoding facts are
aggregated by **full type_hex**, in lexical order. Label equality is not a key;
encodings are not semantically normalized. All groups sharing that exact key
contribute, with their original indices retained. Zero quantities still establish
presence. The three statuses are shared_encoding, baseline_only and current_only;
none claims a matched variable or a stable group identity across builds.

All deltas are **current - baseline**. Byte/group deltas use signed Int.
Declared-count differences compare u64 magnitudes first, subtract smaller from
larger, then attach a minus sign if necessary. No Int/Double/unchecked Int64 cast
or unsigned underflow is used. Zero is always "0". JSON cumulative quantities and
declared-count deltas always have `_decimal` fields and string values; original group
quantities remain u32 numbers. Group counts remain numbers. Type labels can be null.
No statistical row is labeled unchanged, type_changed or variable_added. Zero
totals do not establish equal group order, undecoded bytes, semantics or compatibility.
Selected entry deltas do not explain whole-file changes or predict runtime
memory/removal/gzip.

The encoding ledger is also valid for signed deltas:

```text
delta(entry) = delta(prefix) + delta(body)
delta(body) = delta(locals) + delta(body_remainder)
delta(locals) = delta(group_count_encoding) + delta(quantity_encoding) + delta(type_encoding)
sum(type.baseline.group_bytes) = baseline.locals - baseline.group_count_encoding
sum(type.current.group_bytes) = current.locals - current.group_count_encoding
sum(type.delta.group_bytes) = delta(locals) - delta(group_count_encoding)
```

Type-row declared quantities sum to each side's complete total, and exact signed
row quantity differences sum to the report's quantity difference. The two
original ordered group arrays and ranges are retained, without physical pairing.
Top limits type rows in text only; shown member-index arrays, all totals and the
complete JSON are not shortened. Output size/memory grow with actual groups,
not declared variable count.

### JSON and API additions

Comparison JSON has format moonsize-function-locals-diff, schema_version 1,
with baseline/current objects (complete original reports), delta, type_encodings
and scope. Nested reports are built as Json objects, never stringified/reparsed.
The existing single-input format, fields, signature and rendering stay unchanged.

```moonbit
compare_function_locals(Bytes, Int, Bytes, Int)
  -> Result[FunctionLocalsComparison, FunctionLocalsComparisonError]
describe_function_locals_comparison_error(FunctionLocalsComparisonError) -> String
render_function_locals_comparison(FunctionLocalsComparison, Int) -> String
render_function_locals_comparison_json(FunctionLocalsComparison) -> String
```

New types: FunctionLocalsComparison, FunctionLocalsComparisonError,
FunctionLocalsDelta, FunctionLocalsTypeEncoding, FunctionLocalsTypeTotals and
FunctionLocalsTypeDelta. BaselineLocalsError/CurrentLocalsError retain the target
index and original FunctionLocalsError. WasmError is unchanged. Options adds only
baseline_locals_index, default None; external complete literals must add it.
No existing public signatures or single-file JSON fields change.

### Actual comparison evidence

The four CLI calls used these fixed structural fixtures (not a claim of complete
type/instruction validity, and without new V8 validation):

- Baseline: 47 B, one import, index **1**, SHA-256
  `5d2abe955f9a21dea5b26e667d341560463fd5da35810b018e0ad23a2618b370`.
  Entry [31,44), prefix [31,33) = 8b00, locals [33,43), remainder [43,44).
- Current: 60 B, two imports, index **3**, SHA-256
  `f86329af541446cde8e544970a34f9ce516b11e633a8b2025f29cf68d4376bfa`.
  Entry [41,60), prefix [41,42) = 12, locals [42,58), remainder [58,60).
  Group-count encoding is 8500. Remainders intentionally contain unknown opcodes
  and are left undecoded. The whole-file change is 13 B; selected entry delta is 6 B.

| Type hex | Presence | Before groups | After groups | Declared quantity before/after/delta | Group bytes before/after/delta |
| --- | --- | --- | --- | --- | --- |
| 6370 | shared_encoding | [3] | [3] | 0 / 0 / 0 | 3 / 3 / 0 |
| 638000 | current_only | [] | [4] | 0 / 3 / 3 | 0 / 4 / 4 |
| 7e | baseline_only | [2] | [] | 1 / 0 / -1 | 2 / 0 / -2 |
| 7f | shared_encoding | [0,1] | [0,1,2] | 2 / 3 / 1 | 4 / 7 / 3 |

Group counts **4 -> 5**, declared counts **3 -> 6**, exact difference **"3"**.
Entry **13 -> 19 B**, prefix **2 -> 1**, body **11 -> 18**, locals **10 -> 16**.
Delta ledgers: **6 = -1 + 7**, **7 = 6 + 1**, **6 = 1 + 2 + 3**.
Type-row group bytes **9 -> 14**, delta **5 = 6 - 1**; row quantity differences
**0 + 3 - 1 + 1 = 3**. The zero-quantity shared row remains visible and present.
A focused unit fixture with the same quantity encoded as 02 versus 8200 showed
quantity difference "0" and quantity-encoding growth 1 B in the same type bucket.

Three new combined unit tests passed, including large positive/negative quantities,
full-u64 decimal formatting beyond JS safe integers, side-specific failures,
self-comparison, raw types, Top/full nested JSON, modes and original single format.
Exactly four analyzer calls returned **0 / 0 / 0 / 1**: comparison Top 1 text,
full JSON with Top 1, same-file/index self-comparison to another new JSON, and an
existing sentinel. Node used fixed Buffer ranges/widths/hashes and BigInt counts.
All self deltas were zero and members remained complete; both inputs and the
sentinel were unchanged. Evidence: `_build/function-locals-diff-verification/run-fY4OkX/`
contains both files, four logs, argv/status records, new-diff.json, self-diff.json
and results.json.

Only function_locals_diff_wbtest.mbt's three tests and the new four-call script
ran locally, with necessary info/format/native checks and one release build.
Old suites/scripts/demos, probes, V8 matrices, benchmarks and browser/PDF checks
were not run locally. CI keeps existing regressions and adds the light script;
verify its final pushed SHA. Version remains 0.5.1, without publication.
