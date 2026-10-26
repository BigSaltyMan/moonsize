# Data payload UTF-8 literal search

This is a source addition after published **0.5.1**. Build the current native CLI;
the package version remains 0.5.1 and this change has not been republished.

```sh
moonsize app.wasm --find-data "assets/logo" --top 20
moonsize app.wasm --find-data "assets/logo" --find-data-json new-search.json
moonsize --find-data "assets/logo" -- --app.wasm
```

These paths and queries illustrate the syntax. JSON requires an explicit query
and a new `.json` destination. Existing files and directories are rejected by
the shared preflight and exclusive-create writer; no deletion or overwrite is
attempted. Multiple report writes are not a transaction.

## Matching contract

The query is encoded once as UTF-8 and matched as case-sensitive literal bytes
inside each initialization payload. Only an empty query is invalid; spaces are
meaningful and are not trimmed. There is no Unicode normalization, escape
interpretation, regular expression or UTF-16 guessing. Invalid UTF-8 elsewhere
in the payload does not prevent a byte match. The compiler may use a different
string encoding, so UTF-8 search need not find every source string.

Each entry is searched independently. `aa` in `aaa` produces two occurrences,
at payload offsets 0 and 1. Matches never span entries and never search custom
names, code, data entry prefixes or offset expressions. Results are ordered by
original segment index and then payload byte offset. An occurrence records:

| Field | Meaning |
| --- | --- |
| `segment_index` | Original zero-based data entry index |
| `payload_offset` | Byte offset within that entry's payload |
| `file_offset` | Absolute byte offset in the original input file |
| `size` | Query UTF-8 byte length |

A file offset is not a runtime memory address. A hit shows bytes in an
initialization payload; it does not identify a standalone string, source
constant or resource actually used at runtime. No hit does not prove content
is absent. There is no source attribution, deletion benefit or safe merging
claim. Overlapping occurrence lengths must not be added as occupied bytes.

## Text, JSON and API

Text includes the escaped query, UTF-8 byte length, input size and SHA-256,
the existing data encoding ledger, and the partition
`segment_count = matched_segment_count + unmatched_segment_count`.
No data section, an empty section and entries with no hits have distinct text.
No payload bytes or context snippets are printed. **The query itself is saved
in both text and JSON**, including queries containing sensitive text.

`--top` limits text match rows only; it does not limit search work, totals or
JSON. JSON uses `format: "moonsize-data-search"`, `schema_version: 1`, with all
matches and a nested `data_segments` object in the original single-file format.
Passive memory indices remain `null`. Rendering performs no further parsing or
search. Existing JSON formats and data inspection interfaces are unchanged.

```moonbit
search_data_segments(Bytes, String) -> Result[DataSearchReport, DataSearchError]
describe_data_search_error(DataSearchError) -> String
render_data_search(DataSearchReport, Int) -> String
render_data_search_json(DataSearchReport) -> String
```

New types are `DataSearchMatch`, `DataSearchReport`, and `DataSearchError`
(`EmptyDataSearchQuery` or `DataSearchInputError(WasmError)`). `Options` adds
`find_data` and `find_data_json`, both defaulting to `None`; callers constructing
the complete struct must add these fields. No old function signature changes.

The library checks the query before inspecting the input once. KMP retains a
prefix table and every match, without copying or decoding payloads. Searching
is linear in query bytes, entries visited, payload bytes and occurrences.
Result memory grows with the number of occurrences; Top is not a resource limit.
The original structural inspection and whole-input SHA-256 also have a cost.
This entry does not build a graph or analyze function instructions.

The CLI is an independent mode: input, query, optional own JSON and Top only.
Baseline, strict, budget, max-size, HTML and other report modes are rejected
before input I/O. Exit codes are 0 for a completed query (including zero hits),
1 for input/structural/output failure and 2 for parameter errors. Known option
value restrictions still apply, including rejection of `--`-prefixed query
values. The `--` separator and first-argument-only help dispatch are unchanged.

## Actual focused verification

The four-call fixture is 43 bytes, SHA-256
`31e4561e6e7de6d7c006a71876134e31170ac87bb6313535c297ab7866a18bb3`.
Query `aa` is two UTF-8 bytes:

| Segment | Payload offset | File offset | Size |
| --- | --- | --- | --- |
| 0 | 0 | 18 | 2 |
| 0 | 1 | 19 | 2 |
| 1 | 8 | 31 | 2 |

The data section is **30 = 17 payload + 10 entry metadata + 3 section
overhead bytes**; **5 entries = 2 matched + 3 unmatched**, with 3 occurrences.
Top 1 shows the first row; JSON retains all three. The fixture also contains
`aa` in a custom name, which is excluded. Original bytes were read independently
by the script to verify every match and position.

```sh
moon test --target native data_search_wbtest.mbt
node scripts/test-data-search.mjs _build/native/release/build/cmd/main/main.exe
```

Three combined new tests passed. Exactly four analyzer calls passed with statuses
**0 / 0 / 0 / 1**: text Top 1, complete JSON with Top 1, no match, and an existing
JSON sentinel. Input and sentinel bytes stayed unchanged. Evidence is retained
locally in `_build/data-search-verification/run-j7bKMY/`: input, raw argv and
statuses, four logs, complete JSON and `results.json`.

Local validation did not run legacy suites/scripts, source probes, V8 matrices,
performance, browser, screenshots or PDF checks. Existing Linux CI retains its
regressions and adds only this four-call script. Exact commit CI is checked
after pushing; a local pass alone is not evidence of remote success.

## Follow a hit with a bounded preview

A separate source addition after 0.5.1 offers `--data-preview`. Use the
original `segment_index` and `payload_offset` from your search. Coordinates
below illustrate syntax; they are not measurements of your file:

```sh
moonsize app.wasm --find-data "assets/logo"
moonsize app.wasm --data-preview 1 --data-offset 8 --data-limit 64
```

Preview is a separate call, with no Top: default offset 0, default limit 256,
maximum 4096 bytes, clipped at payload end. An end offset returns an empty
window. Hex and printable ASCII show actual bytes; all other bytes appear as
dots in text. The window may split UTF-8 characters and is not decoded.
`--data-preview-json` writes the complete returned window to a new file.
[Bounded byte preview, API and actual evidence](data-preview.md).

## Locate the file-byte owner

Source addition after 0.5.1: pass a search hit's `file_offset` to the separate
`--locate-offset` mode. For example, `moonsize app.wasm --locate-offset 31`
uses an illustrative coordinate; substitute your actual hit. The query uses an
absolute file byte, not `payload_offset` or a memory address. Data count,
entry metadata and payload have distinct half-open regions; EOF fails.
[Ownership contract, cost and API](file-offset.md). No Top/strict or search
combination; run the two queries separately.
