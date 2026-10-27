# Local access instruction encodings

Source addition after public **0.5.1**, not a new Mooncakes publication. Build
the current native CLI. The function index below is a placeholder in the full
index space, including preceding function imports:

```sh
moonsize app.wasm --local-accesses 3 --top 20
moonsize app.wasm --local-accesses 3 --local-accesses-json new-accesses.json --top 1
```

## What an index means here

The query records actual `local.get`, `local.set` and `local.tee` instructions
in one local function. It retains every occurrence without reachability or
control-flow filtering. A tee counts once as tee, not again as get or set.
Imported function targets are rejected because they have no local body.
No accesses is a successful empty result; it does not imply no variables.

The operand is the **encoded local index including the parameter index space**.
It is different from the parameter-excluding declaration ordinal in
[locals reports](function-locals.md). This query does not parse signatures,
determine parameter counts, classify indices as parameters versus declared
locals, bind declaration groups, guess names/types or validate actual local
index ranges. The existing instruction decoder accepts nonnegative Int indices
through **2147483647**; greater u32 values fail explicitly. This is not full-u32
operand support or complete type/stack/control validation.

Static counts are not execution frequencies or runtime heat. File offsets are
original-file positions, not memory addresses. Encoded sizes do not measure
runtime memory or predict safe deletion, recompilation or gzip savings.

## Evidence and byte accounting

Only the selected body is fully decoded, once. The existing module, inventory,
best-effort names and checked body ranges are reused; these still scan the file.
There is no analyze, graph, locals query, preliminary instruction report or
operand re-decode. Other function opcodes are not decoded. An unknown/truncated
instruction anywhere in the selected body fails before any partial report or
file is returned, even after earlier successful accesses.

Each record preserves its ordinal in the **complete instruction sequence**,
actual opcode, encoded index, absolute file offset, body-relative offset and
instruction size. After verifying the full instruction range and a size of at
least two bytes, its index encoding is `[file_offset + 1, file_offset + size)`.
The single-byte opcode contributes one byte; actual LEB widths, including legal
non-shortest encodings, are preserved.

Groups use a sparse Map keyed by observed indices. They never allocate by the
maximum index or index+1 and never expand declared variables. Numeric index
sorting is explicit; each group keeps get/set/tee counts, total count, encoded
and index bytes, and all member instruction ordinals in file order.

```text
entry.size = prefix.size + body.size
body.size = locals_encoding.size + instruction_bytes
access_count = get_count + set_count + tee_count
instruction_bytes = access_encoding_bytes + other_instruction_bytes
access_encoding_bytes = access_count + index_encoding_bytes
sum(groups.access_count) = access_count
sum(groups.encoded_bytes) = access_encoding_bytes
```

## Reports, CLI and API migration

Text prints escaped target identity, SHA-256, ranges, counts and ledgers, then
two tables: GROUPS in numeric index order and ACCESS SITES in file order. Top
independently limits each table's rows, with separate `showing N of M` counts.
It never truncates totals, member-ordinal arrays of shown groups, the library
result or JSON, and does not limit decoding cost.

JSON format is `moonsize-function-local-accesses`, schema version 1. All sites,
groups, members and ranges are included. No guessed declaration/parameter
bindings, variable names/types or uncomputed graph_complete flag are added.

This standalone CLI accepts only input, query, Top and its own new `.json`.
JSON requires --local-accesses. Strict decimal nonnegative function indices are
independent of Top's cap. All other modes, including locals/baseline-locals,
calls, locate/decode, preview, baseline, strict, budgets/max-size and HTML, are
rejected before input I/O. Separator, unknown-option and first-argument-only
help rules are unchanged. Success including no accesses returns **0**;
input/target/decode/evidence/output errors return **1**; argument errors return
**2**. JSON mode prints only its save confirmation.

Parsing completes before shared output preflight and native exclusive creation.
Existing targets and aliases are not overwritten or removed. No separate writer
or transaction guarantee is added.

```moonbit
inspect_function_local_accesses(Bytes, Int)
  -> Result[FunctionLocalAccessesReport, FunctionLocalAccessesError]
describe_function_local_accesses_error(FunctionLocalAccessesError) -> String
render_function_local_accesses(FunctionLocalAccessesReport, Int) -> String
render_function_local_accesses_json(FunctionLocalAccessesReport) -> String
```

New types: FunctionLocalAccess, FunctionLocalAccessGroup,
FunctionLocalAccessesReport and FunctionLocalAccessesError. Error variants cover
wrapped WasmError (structure/decode), invalid target, imported target and invalid
range/operand evidence, with a real position where available. WasmError and old
public signatures/formats are unchanged. Options adds local_accesses_index and
local_accesses_json, both None by default; complete external literals must add
these fields. See also [full instruction encodings](function-instructions.md).

## Actual focused verification

The fixed input is **85 B**, SHA-256
`5f3650d33a8b691228de226fbd060ce4e8b32c6bc3ab4a293ab3a53a3980a2cb`.
One function import precedes target **index 1**. Entry `[31,59)`, prefix
`[31,33)`, body `[33,59)`, locals `[33,37)` (hex `01 82 01 7f`: one group,
130 i32 declarations). No parameter-binding inference is made by the inspector.

| Original ordinal | Opcode | Encoded index | File offset | Body offset | Size | Index file range / hex |
| --- | --- | --- | --- | --- | --- | --- |
| 0 | local.get | 127 | 37 | 4 | 2 | [38,39) / 7f |
| 3 | local.set | 128 | 42 | 9 | 3 | [43,45) / 8001 |
| 5 | local.tee | 127 | 47 | 14 | 3 | [48,50) / ff00 |
| 7 | local.get | 128 | 51 | 18 | 3 | [52,54) / 8001 |
| 9 | local.get | 127 | 55 | 22 | 2 | [56,57) / 7f |

The complete sequence has 12 instructions. **5 accesses = 3 get + 1 set + 1 tee**.
Group **127**: ordinals `[0,5,9]`, get/set/tee **2/0/1**, **7 B** including
**4 index B**. Group **128**: ordinals `[3,7]`, counts **1/1/0**, **6 B** including
**4 index B**. Ledgers: **28 = 2 + 26**, **26 = 4 + 22**, **22 = 13 + 9**,
**13 = 5 + 8 = 7 + 6**. Local function 2 has one declared i32 and zero access
instructions, illustrating why no accesses does not mean no variables.

Three new combined tests passed: exact positions/ordinals/widths/ledgers,
selected-body failures and other-body isolation, sparse index 2147483647,
explicit rejection above Int, numeric index sorting, modes, escaping and Top/full
JSON. Large-index fixtures test encoding inspection, not semantic validity.
Exactly four CLI calls returned **0 / 0 / 0 / 1**: text Top 1, complete JSON with
Top 1, no-access local target, and an existing JSON sentinel. Node independently
checked fixed Buffer opcode/index bytes, offsets, lengths and SHA-256. Input and
sentinel remained unchanged. Evidence is retained locally at
`_build/function-local-accesses-verification/run-ynX9BB/`: input, four logs,
argv/status records, new-accesses.json and results.json.

Only the three new tests and four new CLI cases ran locally, with necessary
interface/format/native checks and one release build. No old suites/scripts,
source demos/probes, V8 matrix, performance or browser/PDF acceptance were run.
CI keeps existing regressions and adds the four-call script; verify final-SHA
success after push. Version remains 0.5.1; no dependency or publication change.
