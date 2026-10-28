# Find decoded opcode locations

This is a source addition after public **0.5.1**, not a new Mooncakes release.

```sh
moonsize app.wasm --find-opcode i32.const --top 20
moonsize app.wasm --find-opcode i32.const \
  --find-opcode-json new-opcode-matches.json --top 1
```

Query is case-sensitive exact equality with the complete `Opcode.name()`.
There is no substring, regular expression, prefix/category, case folding,
Unicode normalization or numeric-opcode interpretation. Whitespace is not trimmed:
` i32.const` is a different query. Empty/all-whitespace queries fail before input
parsing. Unknown or misspelled nonempty names are accepted and may have no matches;
this entry does not duplicate the supported opcode registry. `0x41` is simply a
nonmatching name, not another way to request i32.const.

## Scope and scanning

Every local body in code is decoded once, including bodies that the model might
consider unreachable. The module/import/code/name ranges are read once; there is
no prior statistics report, per-function inspector loop, analyze, graph or retained
pass. Each bounded body checks positive instruction sizes, continuity and the body
endpoint. An unknown, truncated or unsupported instruction in **any** body fails
the whole query, even if an earlier body matched. Errors retain full function
index, original file position/reason and structure/body/evidence distinctions.

Search does not scan raw bytes. Locals declarations, global/element/data initializers,
custom/name/data bytes and immediates are not separate instructions. Extension
subinstructions match their individual full mnemonic. Imports have no body and
receive no synthetic match. Zero decoded instructions remain a structural result,
not evidence of valid termination or complete type/stack/control semantics.

Each matched function keeps its `FunctionStat`, counts/bytes and matching
`FunctionInstructionRecord` sites. Original zero-based ordinal is from the **full**
instruction sequence; filtering does not renumber it. Full function indices include
preceding imports. Function order is index ascending, site order is file order.
Same-named functions are separate. No zero-match function rows or all-instruction
array are retained. The temporary decoded array does not escape the helper; no
promise is made about immediate garbage collection or fixed peak memory.

## Text, JSON and limits

Text uses one global location table. Top limits **position rows**, not function
groups, scans or resource cost. Counts and complete JSON are never truncated.
Query and names are terminal-escaped; JSON preserves raw strings with proper
escaping. Unavailable raw_name is null. No payload context or operand values are
output.

JSON format is `moonsize-opcode-search`, schema version 1. It contains input
size/SHA/query/rule/scope, all summary counts, and all matching functions with
stat/match_count/matched_encoded_bytes/sites. There is no second flattened site
array. Nonmatching functions have no full report entry. The query itself is saved
in the report.

```text
scanned_local_function_count = matched_function_count + unmatched_function_count
match_count = sum(function.match_count) = sum(function.sites.length)
matched_encoded_bytes = sum(function.matched_encoded_bytes)
                      = sum(matching_site.encoded_size)
instruction_bytes = matched_encoded_bytes + other_instruction_bytes
```

Matched bytes include the complete opcode/subopcode/immediate encoding; they are
not pure opcode bytes or predicted savings. Counts are static, not execution
frequency or traces. No source attribution, operand-value interpretation, runtime
memory, full semantic validation or deletion/rebuilt/gzip benefit is inferred.
No-local-functions and local-functions-with-no-match are reported separately.
An empty result makes no claim about other regions of the module. Full-result
memory can grow with the number of matches.

This independent mode accepts only input, query, own JSON and Top. JSON requires
query and a nonempty new `.json` path. Other queries, stats/diff-opcodes, baseline,
strict, budgets, max-size, compression and HTML are rejected before I/O. Existing
unknown-option, value restrictions, `--` and first-argument-only help rules remain.
Exit codes: **0** query completed including no matches; **1** input/body/evidence
or output failure; **2** bad query/arguments/combination. JSON mode only prints a
save confirmation. Existing unified preflight and native exclusive creation are
used; no deletion/retry writer or new transactional guarantee. A failed body never
creates a new report.

## Manual handoff

Run these separately; the query does not automatically run multiple analyses:

```sh
moonsize app.wasm --opcode-stats --top 20
moonsize app.wasm --find-opcode i32.const --top 20
# Substitute an index/file offset actually returned for this input:
moonsize app.wasm --instructions 1
moonsize app.wasm --locate-offset 49 --locate-decode
```

The last coordinates are illustrative generally, and actual for the fixture
below. --instructions selectively decodes one function; --locate-decode refines
the owner of a file byte. These cannot be combined with --find-opcode in one call.
[Module totals](module-opcodes.md), [function instructions](function-instructions.md),
[file ownership](file-offset.md).

## Public API migration

```moonbit
search_opcode(Bytes, String) -> Result[OpcodeSearchReport, OpcodeSearchError]
describe_opcode_search_error(OpcodeSearchError) -> String
render_opcode_search(OpcodeSearchReport, Int) -> String
render_opcode_search_json(OpcodeSearchReport) -> String
```

New types are OpcodeSearchFunction, OpcodeSearchReport and OpcodeSearchError.
InvalidOpcodeSearchQuery is distinct from OpcodeSearchInputError, which wraps the
existing ModuleOpcodeError and retains its input/body/evidence details. No new
WasmError branch. Existing FunctionStat and FunctionInstructionRecord are reused.
Options adds only find_opcode=None and find_opcode_json=None; complete external
struct literals must supply them. Old public signatures and report formats remain
unchanged. Version stays 0.5.1; dependencies and the public registry are untouched.

## Actual focused verification

Input **168 B**, SHA-256
`91adb2a3f8c71128cf78f2798fda633533629ff8c461bb09d6dcccd03e4f7543`.
It has one imported function and two local definitions (full indices 1 and 2).
Both use the same raw name, represented as `same\ni32.const"<&` in escaped text.
Code is [36,85). Function 1 entry [40,75), prefix 2 B, body [42,75), locals [42,45);
function 2 entry [75,85), prefix 1 B, body [76,85), locals [76,77).

| Function | Full ordinal | File offset | Body-relative offset | Complete B | Encoding |
| --- | --- | --- | --- | --- | --- |
| 1 | 2 | 49 | 7 | 2 | 4100 |
| 1 | 4 | 52 | 10 | 3 | 418001 |
| 2 | 0 | 77 | 1 | 2 | 4101 |
| 2 | 2 | 80 | 4 | 3 | 418001 |

Local-function partition: **2 = 2 matched + 0 unmatched**. Each function has
2 sites / 5 B. Total **4 matches = 2 + 2**, **10 B = 5 + 5 = 2 + 3 + 2 + 3**;
all instruction bytes **38 = matched 10 + other 28**, across 20 instructions.
The f32.const immediate contains byte41 at file57, but it is not an extra site.
A global i32.const initializer and literal i32.const text in name/custom/data do
not add matches. The s/u saturating extension mnemonics independently match
file61/69, full ordinal7/10, size2, in unit verification.

Three new combined tests passed for matching facts/ledgers, exact queries/empty
states/whole-query failures, and CLI contract/Top/escaping/null/full JSON. A bad
second local function reports index2 and original position77 for ff; unknown
extensions and truncated immediates fail instead of becoming empty results.

Exactly four real CLI processes returned **0 / 0 / 0 / 1**: i32.const Top1 text,
complete JSON with Top1, absent i64.const text, existing sentinel JSON refusal.
The first has one table row but complete totals; JSON has both functions and all
four sites. The absent query has 2 unmatched functions, no saved report. Buffer
checks independently validate every sequence, ordinal, position, size and SHA.
Input and sentinel bytes stay unchanged; refusal has no success confirmation.
Evidence: `_build/opcode-search-verification/run-GVV8cn/` contains input, four
logs, original argv/status, results.json and new-matches.json.

Necessary interface/fmt/native checks and one release build passed. No local
old/full tests or old CLI scripts, demos/probes, V8 matrix, performance/large-module
or browser/PDF runs. CI retains existing checks and adds only this four-call
script. Confirm the exact final SHA after push; no package publication is claimed.
