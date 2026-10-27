# Module-wide function opcode encoding statistics

This is a source addition after public **0.5.1**, not a new Mooncakes release.
Build the current native CLI:

```sh
moonsize app.wasm --opcode-stats --top 20
moonsize app.wasm --opcode-stats-json new-opcodes.json --top 1
```

The JSON option implies --opcode-stats. This independent mode accepts only
input, these options and Top. Other analysis modes, baseline, strict, budgets,
max-size, compression and HTML are rejected before file I/O. JSON destinations
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
