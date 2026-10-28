# Module-wide function opcode encoding statistics

This is a source addition after public **0.5.1**, not a new Mooncakes release.
Build the current native CLI:

```sh
moonsize app.wasm --opcode-stats --top 20
moonsize app.wasm --opcode-stats-json new-opcodes.json --top 1
```

The JSON option implies --opcode-stats. This independent mode accepts only
input, these options and Top. Baseline is allowed only with --diff-opcodes
(see below). Other analysis modes, strict, budgets, max-size, compression and
HTML are rejected before file I/O. JSON destinations
must be nonempty new `.json` files. Existing unknown-option, separator and
first-argument-only help rules remain unchanged.

## What is counted

All local function bodies in code are included without reachability filtering.
Imports have no local body and receive no synthetic zero-byte function row.
Global/element/data initialization expressions are excluded. No graph or retained
analysis is run. Ordinary/default analysis behavior is unchanged.

Each mnemonic has its static occurrence count, **complete encoded instruction
bytes**, and the number of distinct local functions where it appears. Encoded
bytes include opcode, extension subopcode and immediates; they are not pure
opcode bytes. Existing decoder names distinguish extension instructions, such
as i32.trunc_sat_f32_s and i32.trunc_sat_f32_u, rather than one combined 0xFC row.
Each function contributes at most once to a mnemonic's function_count. A function
can contain several mnemonics, so **do not sum function_count to get the number
of functions**. Counts are not execution frequency, timings or runtime hotspots.
Encoded sizes do not predict runtime memory, safe removal, rebuilt or gzip savings.
No transfer-share, graph_complete or strict assurance is computed.

Ranges/names for all local functions are collected first. Each body is then
decoded exactly once and checked for positive instruction sizes, continuity
and the body endpoint. The global map is updated using a temporary per-body
mnemonic Set. After summarizing that body, its decoded array does not escape
the helper; the result retains only global opcode groups and compact local
function summaries. There is no occurrence list or opcode-by-function matrix.
No promise is made about the runtime's immediate memory reclamation or peak
memory; this feature has no performance benchmark or resource limit.

The entry does not loop over inspect_function_instructions and does not reparse
the whole module per function. It reuses parse_module, imported-function counting,
parse_code_section, best-effort names, function_stats and the bounded decoder.
Existing structural scans still occur. Any unknown, truncated or unsupported
body makes the entire report fail, with its **full function index** and the
original WasmError position/reason. No bad function is skipped and no partial
report is saved. Single-function --instructions remains selective, so a successful
query there does not imply every other body can be decoded.

## Code byte ledger and empty results

All section headers, function-count fields and body prefixes use their actual
encoded widths, including valid non-shortest encodings. Entries must be
contiguous inside code payload and consume it exactly:

```text
code.total_size = code_header_bytes + count_encoding_bytes
                  + body_prefix_bytes + locals_encoding_bytes + instruction_bytes
sum(function.stat.total_size) = body_prefix_bytes + locals_encoding_bytes + instruction_bytes
sum(function.instruction_bytes) = sum(group.encoded_bytes) = instruction_bytes
sum(function.instruction_count) = sum(group.count) = instruction_count
0 < group.function_count <= local_function_count
group.function_count <= group.count
```

No code section means code/count ranges are null and all code metrics are zero.
An explicit zero-function code section retains its real header and zero-count
field. An imports-only module has an empty local-function array. The decoder's
zero-instruction structural results are preserved without claiming a valid
function terminator or complete type/stack/control/instantiation semantics.
File offsets are original-file positions, not memory addresses.

## Text, JSON and API migration

Text shows input SHA-256, scope, imported/local counts, the full code ledger and
one opcode table. Sorting is encoded bytes descending, count descending, then
full mnemonic lexical order. There is no second function ranking table. Top
only limits displayed opcode rows (`showing N of M`); it does not truncate
totals, complete JSON or all-body decoding cost. Use --instructions separately
for individual function details.

JSON format is **moonsize-module-opcodes**, schema version 1. It includes all
groups and functions, optional code_section/count_encoding, counts and byte
totals. Each function has stat (FunctionStat facts), locals_encoding and its
instruction count/bytes, without per-function opcode groups or instructions.
Unavailable name/raw_name values are null; display_name preserves FunctionStat's
readable fallback such as `(unnamed)`. Available raw/display names and module
labels are JSON-escaped, including control characters. No original bytes are
embedded. Existing report formats are unchanged.

```moonbit
inspect_module_opcodes(Bytes) -> Result[ModuleOpcodeReport, ModuleOpcodeError]
describe_module_opcode_error(ModuleOpcodeError) -> String
render_module_opcodes(ModuleOpcodeReport, Int) -> String
render_module_opcodes_json(ModuleOpcodeReport) -> String
```

New types: ModuleOpcodeGroup, ModuleOpcodeFunction, ModuleOpcodeReport and
ModuleOpcodeError. Errors distinguish input structure, indexed body errors
wrapping WasmError, and range/aggregate evidence errors with real positions
when available. WasmError and old public signatures are unchanged. Options adds
opcode_stats=false and opcode_stats_json=None; external complete struct literals
must include these fields. Success including empty results returns **0**;
input/body/evidence/output failures **1**; parameter errors **2**. JSON mode only
prints its save confirmation. Query completion precedes shared preflight and
native exclusive creation. Existing targets and aliases stay protected; no
separate writer, deletion/retry path or output transaction is added.

## Actual focused verification

The fixed CLI input is **98 B**, SHA-256
`9d0843495e6d353f6676c4a43e4293e6b66faec6f8fc3f5ff1475ad7749099bb`.
It has **1 import and 2 local bodies** (full indices 1 and 2). Code is `[28,77)`,
total 49 B, payload 47 B. Count `[30,32)` is `8200`. Function 1 has entry
`[32,67)`, prefix `a100`, body `[34,67)`, locals `[34,37)`, 15 instructions / 30 B.
Function 2 has entry `[67,77)`, one-byte prefix `09`, body `[68,77)`, locals
`[68,69)`, 5 instructions / 8 B. Only function 1 has an available raw name.

| Mnemonic | Count | Distinct functions | Complete encoded B |
| --- | --- | --- | --- |
| i32.const | 4 | 2 | 10 |
| f32.const | 2 | 1 | 10 |
| drop | 6 | 2 | 6 |
| end | 4 | 2 | 4 |
| block | 1 | 1 | 2 |
| i32.trunc_sat_f32_s | 1 | 1 | 2 |
| i32.trunc_sat_f32_u | 1 | 1 | 2 |
| loop | 1 | 1 | 2 |

Ledgers: **49 = 2 + 2 + 3 + 4 + 38**; function entries
**35 + 10 = 45 = 3 + 4 + 38**; instructions **15 + 5 = 20**;
instruction bytes **30 + 8 = 38**. Opcode counts sum to 20, bytes to 38,
but function_count sums to **11**, not the local-function count 2.

The bad copy changes only file byte **69** to ff, preserving outer ranges.
Its SHA-256 is `b2efef4a4657c43fc72b0caeb294b77a986ccd93971d114dd1c9957a4e9f65ca`.
The query reports function **2**, position **69**, and leaves the new JSON absent.
Three new combined tests passed, including missing/empty code, imports-only,
zero-instruction structural results, initializer exclusion, exact aggregation,
non-first-body failures, sorting/Top/full JSON, null names, escaping and modes.
One selective --instructions library call is a control inside the new tests;
no old test file or CLI regression was run locally.

Exactly four analyzer processes returned **0 / 0 / 1 / 1**: Top 1 text, full JSON
with Top 1, bad second body with a new destination, and an existing sentinel.
Node checked fixed Buffer encodings/widths, counts, distinct-function counts,
ranges and SHA independently. Both inputs and the sentinel were unchanged.
Evidence: `_build/module-opcodes-verification/run-jAkXR8/` contains inputs,
four logs, raw argv/status, new-opcodes.json and results.json. Necessary
interface/format/native checks and one release build passed. No local full/old
suites/scripts, demos/probes, V8 matrix, performance/large-module benchmark,
browser or PDF acceptance was run. CI retains old regressions and adds only
the four-call script; verify the final pushed SHA. Version stays 0.5.1,
without dependency changes or a Mooncakes publication.

## Compare complete modules (source addition after 0.5.1)

```sh
moonsize after.wasm --baseline before.wasm --diff-opcodes --top 20
moonsize after.wasm --baseline before.wasm --diff-opcodes \
  --opcode-stats-json new-opcode-diff.json --top 1
```

--diff-opcodes implies opcode-stats and requires a nonempty baseline. Explicit
--opcode-stats alongside it is allowed. Without diff, single-input statistics
still reject baseline. Only input, these mode flags, baseline, Top and own JSON
are allowed; strict, budgets, max-size, HTML and all other queries are rejected
before I/O with exit 2. Success including self-comparison is 0; input/body/output
errors are 1. Each side is read once and inspected once, without ordinary
baseline analysis, function matching, instruction alignment or re-decoding.
Any side failure aborts without a new JSON; the error retains baseline/current,
full function index and original error position/reason. Existing protected output
and exclusive creation are reused through the existing opcode_stats_json slot.

This compares **all local bodies** by mnemonic. --instructions plus explicit
--baseline-instructions instead compares a user-selected pair of functions.
Neither establishes cross-build function identity. Counts are static; complete
bytes include subopcodes and immediates. Equal counts with wider immediates can
produce a positive byte delta. Distinct-function counts describe distribution
per mnemonic; their differences neither identify added functions nor sum to a
module function-count difference. Zero statistics do not prove equal bytes,
constants, order or semantics. No runtime, retained, gzip or removal inference.

Union rows use shared_opcode / baseline_only / current_only with zero values on
the absent side. All deltas are signed current minus baseline. Sort by absolute
encoded-byte delta descending, then absolute count delta descending, then full
mnemonic lexical order. Top limits only text opcode rows. Both complete original
reports, including every compact function summary, are retained in JSON:

```json
{
  "format": "moonsize-module-opcodes-diff",
  "schema_version": 1,
  "baseline": {},
  "current": {},
  "delta": {},
  "opcodes": [],
  "scope": "..."
}
```

The abbreviated objects above stand for complete reports, not strings. The
single-input format/fields/signature remain unchanged; both renderers share a
private Json constructor, with no stringify/parse round trip. Missing code/count
remain null in the corresponding original report. An absent code contributes
zero code bytes, whereas explicit empty code retains actual header/count widths.
non_code_bytes = file_size - code_bytes includes the Wasm header and all non-code
encodings, not just metadata. Deltas are quantities, not file ranges.

```text
delta(file_bytes) = delta(code_bytes) + delta(non_code_bytes)
delta(code_bytes) = delta(code_header_bytes) + delta(count_encoding_bytes)
                  + delta(body_prefix_bytes) + delta(locals_encoding_bytes)
                  + delta(instruction_bytes)
sum(opcode.encoded_bytes_delta) = delta(instruction_bytes)
sum(opcode.count_delta) = delta(instruction_count)
```

Public additions: ModuleOpcodeChange, ModuleOpcodeDelta, ModuleOpcodeComparison,
ModuleOpcodeComparisonError (BaselineModuleOpcodeError/CurrentModuleOpcodeError
wrap the existing ModuleOpcodeError). Functions:

```moonbit
compare_module_opcodes(Bytes, Bytes)
  -> Result[ModuleOpcodeComparison, ModuleOpcodeComparisonError]
describe_module_opcode_comparison_error(ModuleOpcodeComparisonError) -> String
render_module_opcode_comparison(ModuleOpcodeComparison, Int) -> String
render_module_opcode_comparison_json(ModuleOpcodeComparison) -> String
```

Options adds only diff_opcodes=false. Complete external struct literals must add
this field. Old public signatures and WasmError are unchanged. No new dependency,
version bump or Mooncakes release.

### Actual comparison evidence

Baseline **44 B**, SHA-256
`edb9f40d44260235c7acc1af1c901880eadb834952dbf8c7cd1687d539bacc36`;
current **57 B**, SHA-256
`e64d91985a9dd2d1d35d627a7bc744bcaedbcca0ec35fb153fc7d7aee75cfaf6`.
Both have one import. Local functions change 2 -> 3. Code ranges are [28,44)
and [29,57), with sizes 16 -> 28. Header widths 2 -> 3, function count encodings
02 -> 8300 (1 -> 2 B), body prefix totals 2 -> 4 B, locals 2 -> 5 B, instructions
9 -> 14 B and counts 7 -> 10. First body prefix 06 -> 8900; first locals
00 -> 01017f; one i32.const immediate changes 00 -> 8001. Other instruction
occurrences also change, so the total const count delta is +1, byte delta +3.

| Mnemonic | Presence | Before/after count | Count delta | Before/after encoded B | Byte delta | Before/after functions | Function delta |
| --- | --- | --- | --- | --- | --- | --- | --- |
| i32.const | shared_opcode | 2 / 3 | +1 | 4 / 7 | +3 | 2 / 3 | +1 |
| drop | shared_opcode | 2 / 3 | +1 | 2 / 3 | +1 | 2 / 3 | +1 |
| end | shared_opcode | 2 / 3 | +1 | 2 / 3 | +1 | 2 / 3 | +1 |
| nop | baseline_only | 1 / 0 | -1 | 1 / 0 | -1 | 1 / 0 | -1 |
| unreachable | current_only | 0 / 1 | +1 | 0 / 1 | +1 | 0 / 1 | +1 |

File: **+13 = code +12 + non-code +1**. Code: **+12 = header +1 + count +1 + body prefixes +2 + locals +3 + instructions +5**. Opcode byte deltas sum +5,
count deltas sum +3. The per-mnemonic function deltas sum +3, while local function
count changes +1: those are different measures.

Three new combined unit tests passed: union/widths/ledgers, absent/empty code,
self/zero-statistics with differing constants/SHA, second-function side-specific
errors, routing/Top/full nested JSON and unchanged single-input format. A separate
unit fixture holds const count constant while widening its immediate, yielding
count delta 0 and byte delta +1.

Exactly four real CLI calls returned **0 / 0 / 0 / 1**: Top1 comparison, full JSON
with Top1, current/current self-comparison, existing sentinel refusal. Buffer
checks independently verify actual widths, instructions, positions and SHA.
All inputs and the sentinel remain unchanged. Self-comparison keeps all members
and every aggregate/row delta is zero. No success save message on refusal.
Evidence: `_build/module-opcode-diff-verification/run-wKD9CX/` contains both
inputs, argv/status, four logs, results.json, new-diff.json and self.json.
Necessary interface/fmt/native checks and one release build passed. No local
old/full suites, old CLI/demos, probes, V8 matrix, performance/large-module or
browser/PDF runs. Existing Linux CI retains its checks and adds only this script;
confirm the exact final SHA after push. These are source additions, not a new
public package release.
