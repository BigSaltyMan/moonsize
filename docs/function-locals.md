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

This independent mode allows only input, locals, own JSON and Top. JSON requires
an explicit query and nonempty new `.json` destination. Strict decimal Int index
parsing is independent of Top limits. Other modes, including calls, locate/decode,
preview, baseline, strict, budgets, compression and HTML, return **2 before input
I/O**. Existing separator, unknown-option and first-argument help rules remain.
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
