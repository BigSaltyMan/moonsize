# Call instructions in one local function

Source addition after public **0.5.1**, not a new Mooncakes publication. Build
the current native CLI. The index below is illustrative; use your own complete
function index (including preceding function imports):

```sh
moonsize app.wasm --calls 3 --top 20
moonsize app.wasm --calls 3 --calls-json new-calls.json --top 1
```

## What is recorded

Only a function with a local body is accepted. Imported functions are rejected,
not represented by a fabricated empty call list. A local body with zero calls
is a normal success. There is no reachability filter, recursion or call graph.

| Kind | Actual opcodes | Target | Type | Table |
| --- | --- | --- | --- | --- |
| `direct` | `call`, `return_call` | Encoded index and FunctionPathNode | null | null |
| `indirect` | `call_indirect`, `return_call_indirect` | null | Encoded index | Encoded index |
| `reference_call` | `call_ref`, `return_call_ref` | null | Encoded index | null |

Tail calls preserve their actual opcode and `is_tail: true`; tail counts are a
subset of these categories, never extra calls. `ref.func` takes a reference
and is **excluded**, even if the value might later be called. The new kind
`reference_call` does not use graph `EdgeKind.Reference`.

Each call keeps its ordinal in the **full instruction sequence**, actual opcode,
kind, tail flag, absolute file offset, body-relative offset and encoded length.
Repeated calls to the same target stay separate and in file order. Direct
targets must be in the actual function index space, or the query fails with the
call instruction's offset. Their nodes retain display/raw names and import
module/name; imports have `encoded_size: null` because there is no local body.

Dynamic targets remain unknown, without static candidates or target guesses.
Type/table fields are only the encoded indices readable by the existing decoder;
their existence and type compatibility are not checked here. File offsets are
not memory addresses. Counts are static instruction counts, not execution
frequencies, timing or an execution trace. This is not a complete outgoing
dependency graph or full Wasm type/stack/control validation. Encoded bytes do
not predict deletion, recompilation or gzip savings.

## Reports, Top and file protection

Text shows caller identity, input SHA-256, entry/body ranges, counts and byte
ledgers, then call rows. Names and import fields are terminal-escaped. Unknown
targets appear as `unknown`, not a made-up function. Top limits only the number
of displayed call rows; it never truncates counts, the library result or JSON,
and it is not a decoding-cost limit.

JSON uses `format: "moonsize-function-calls"`, `schema_version: 1`, with all
calls and explicit nulls for non-applicable fields. It contains no
`graph_complete`, `unresolved_count` or strict assurance. Ledgers are:

```text
entry.size = prefix.size + body.size
body.size = locals_encoding.size + instruction_bytes
call_count = direct_count + indirect_count + reference_call_count
instruction_bytes = call_encoding_bytes + other_instruction_bytes
```

This standalone CLI mode accepts input, `--calls`, its optional own JSON and Top.
JSON requires an explicit query and a nonempty new `.json` path. Function indices
use strict nonnegative decimal Int parsing, independent of the Top cap. Invalid
numbers and incompatible modes return **2 before business I/O**: baseline,
strict, budgets, HTML, callers, instructions, locate/decode, data search/preview
and other report modes cannot be combined. Existing `--`, unknown-option and
first-argument-only help rules remain unchanged.

Completion, including zero calls, returns **0**; input, target, decoder, evidence
or output errors return **1**. JSON mode prints only its save confirmation. The
entire target must decode successfully, including instructions after the first
call: unknown/truncated code yields no partial report or output. Shared preflight
and native exclusive creation reject existing files and aliases; no overwrite
or deletion path is added. Multi-file output is still not a transaction.

## API and distinction from callers

```moonbit
inspect_function_calls(Bytes, Int) -> Result[FunctionCallsReport, FunctionCallsError]
describe_function_calls_error(FunctionCallsError) -> String
render_function_calls(FunctionCallsReport, Int) -> String
render_function_calls_json(FunctionCallsReport) -> String
```

New types are FunctionCallKind, FunctionCallRecord, FunctionCallsReport and
FunctionCallsError. Error variants cover wrapped WasmError, invalid target,
imported target and invalid evidence (with a real file offset when available).
Options adds only `calls_index` and `calls_json`, both defaulting to `None`;
complete external struct literals must add them. Existing interfaces, graph
types, decoder opcodes and report schemas are unchanged.

The entry reuses `parse_module`, private `path_inventory` and checked code-body
ranges. Existing module/name/range scans can repeat to collect these facts;
only the selected body's `decode_instructions` runs, once. The same decoded
array supplies operands, original ordinals and call records. There is no
per-call instruction re-decode, prior instruction report, analyze, graph or BFS.
Non-target opcodes are not decoded. Rendering reads only the report.

`--callers` queries incoming references in the current graph model, including
reference-taking and indirect candidates. `--calls` lists the actual call
instructions encoded in one target body, with unknown dynamic targets. They
are **not a simple graph reversal**: reference and dynamic-target coverage differ.
Use [callers](function-callers.md), [instruction encodings](function-instructions.md)
or [file-byte ownership](file-offset.md) as separate queries when needed.

## Actual focused verification

The reused small fixture construction produces 96 bytes, SHA-256
`f7e6bd037579921338d03ab9af9b44d3a9c0d6f9d9f09a7c96b9a40f9a9c26d6`.
Caller index 1 has entry `[46,72)`, prefix `[46,48)`, body `[48,72)`, locals
`[48,49)`. One function import precedes it; local function 2 has a 3-byte entry.

| Full ordinal | Opcode | File offset | Size | Target/type/table |
| --- | --- | --- | --- | --- |
| 1 | call | 50 | 2 | target 0, import m.f |
| 4 | call | 55 | 2 | target 0, separate occurrence |
| 5 | call | 57 | 2 | target 2, local |
| 6 | call_indirect | 59 | 3 | target null, type 0/table 0 |
| 7 | return_call_indirect | 62 | 3 | target null, type 0/table 0 |
| 8 | call_ref | 65 | 2 | target null, type 0/table null |
| 9 | return_call_ref | 67 | 2 | target null, type 0/table null |
| 10 | return_call | 69 | 2 | target 0 |

**8 calls = 4 direct + 2 indirect + 2 reference calls**, including **3 tail calls**.
The full sequence contains 12 instructions; `ref.func` at file offset 52 is not
a call. Ledgers: **26 = 2 + 24**, **24 = 1 + 23**, **23 = 18 + 5** bytes. No
payload/execution/host implementation costs are added to these encoding totals.

```sh
moon test --target native function_calls_wbtest.mbt
node scripts/test-function-calls.mjs _build/native/release/build/cmd/main/main.exe
```

Three new combined tests passed. Exactly four CLI calls returned **0 / 0 / 0 / 1**:
Top 1 text, full JSON with Top 1, zero-call local function 2, existing JSON sentinel.
Independent Buffer checks confirmed opcode bytes, indices, positions and sizes;
input and sentinel stayed unchanged. Evidence is retained locally in
`_build/function-calls-verification/run-aUejSo/`: input, argv/status records, four
logs, `new-calls.json`, `results.json`. API snapshots are in `review-96c6f0d6/`.
Target/direct-index/decode failures and mode exclusions were covered in the
three new tests, without extra analyzer processes.

Local checks did not run old suites/scripts, source demos/probes, V8 matrices,
performance or browser/PDF acceptance. CI retains existing regressions and adds
only this four-call script; confirm final exact-SHA success after push. Version
stays 0.5.1, with no dependency change or Mooncakes publication.
