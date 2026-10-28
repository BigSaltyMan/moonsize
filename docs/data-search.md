# Data payload literal search: UTF-8 and hex

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

## Compact hexadecimal byte search (source addition after 0.5.1)

```sh
moonsize app.wasm --find-data-hex 00ff00 --top 20
moonsize app.wasm --find-data-hex 00FF00 \
  --find-data-json new-hex-search.json --top 1
```

Hex must be nonempty and have an even number of **ASCII** 0-9/a-f/A-F digits.
Letter case is equivalent; reports normalize to lowercase. No trimming, spaces,
colons, 0x prefix, escapes, question marks or wildcards. For example 00ff00 is
three bytes, not UTF-8 text. NUL/ff and any other known encoded bytes are allowed.
Known other encodings can be supplied by the user as bytes; no encoding is
automatically recognized or converted, including UTF-16.

--find-data and --find-data-hex are mutually exclusive. Shared --find-data-json
requires exactly one query and a nonempty new .json destination. Hex otherwise
uses the same independent-mode restriction: only input, query, Top and own JSON;
no baseline, strict, HTML, budget or other analysis modes. Invalid syntax/query
combinations fail **2** before reading input. Input/output failure is **1**;
completed search including no matches is **0**. Existing --, unknown-option and
first-argument help behavior is unchanged. The same output slot, preflight and
native exclusive create are reused, without a new writer or deletion/retry.

The private ASCII syntax validator is shared by CLI and library. The library
validates before inspecting data, decodes pairs directly once into a nonempty
byte pattern, then calls inspect_data_segments once. The existing KMP loop is
minimally extracted to a private byte-match helper. UTF-8 still encodes its text
once; hex never round-trips through UTF-8 or the old text query. Each builds one
prefix table per search, resets state at each payload, retains overlapping suffixes,
and never copies complete payloads or per-candidate slices. No graph or function
instruction decoding is added. Time stays linear in pattern bytes, payload bytes
and matches; complete results may consume memory proportional to occurrences.

Only data payloads are searched, not section headers, names/custom content,
length fields, code or offset expressions. 00ff00 in 00ff00ff00 has occurrences
at offsets 0 and 2. It cannot continue from one entry into the next. Full matches
stay in original entry/offset order. Top limits text **location rows**, not scan
cost, summaries or full JSON. No-data, empty-data and entries-with-no-match stay
separate. Reports save the normalized pattern itself, without payload context.
File offsets are not memory addresses; hits do not identify encoding, source,
independent strings, used resources, safe deduplication or deletion/rebuilt/gzip
benefits. Overlapping hit lengths cannot be added as exclusively occupied bytes.

Hex text is titled DATA PAYLOAD HEX SEARCH. Its separate JSON format is
**moonsize-data-hex-search**, schema_version 1, with query_hex/query_size, file
size/SHA/rule/scope, segment partition, occurrence_count, all matches and the
complete nested original data_segments object. The existing UTF-8 JSON remains
**moonsize-data-search** with query, not query_hex; old public types, signatures,
whitespace behavior and format fields are unchanged. Passive memory indices are
still null.

```text
query_hex.length = query_size * 2
segment_count = matched_segment_count + unmatched_segment_count
occurrence_count = matches.length
hit.file_offset = entry.payload.offset + hit.payload_offset
hit.size = query_size
```

### API additions

```moonbit
search_data_segments_hex(Bytes, String)
  -> Result[DataHexSearchReport, DataHexSearchError]
describe_data_hex_search_error(DataHexSearchError) -> String
render_data_hex_search(DataHexSearchReport, Int) -> String
render_data_hex_search_json(DataHexSearchReport) -> String
```

New report/error types only; DataHexSearchError distinguishes InvalidDataHexQuery
from DataHexSearchInputError wrapping WasmError. Existing DataSearchMatch is reused;
DataSearchError and WasmError are not extended. Options adds only find_data_hex=None;
complete external struct literals must supply it. No public generic matcher or new
dependency. Version remains 0.5.1; this increment is not a Mooncakes publication.

### Actual binary verification

Input **49 B**, SHA-256
`aad74aba2dc0b955b32e162e95b3cd6f47e539fe69435770655902676bc73caa`.
The data section [18,49) is 31 B: **31 = payload 16 + entry metadata 12 + section
overhead 3**, with header2/count1. Six passive payloads, in order:
00ff00ff00 / 6100ff0062 / 00ff / 00 / empty / 616161.
Payload ranges are [23,28), [30,35), [37,39), [41,42), [44,44), [46,49).
The custom content at file15 also contains 00ff00 and must not count.

| Pattern | Entry | Payload offset | File offset | Length B |
| --- | --- | --- | --- | --- |
| 00ff00 | 0 | 0 | 23 | 3 |
| 00ff00 | 0 | 2 | 25 | 3 |
| 00ff00 | 1 | 1 | 31 | 3 |

Partition **6 = matched 2 + unmatched 4**, occurrences3. The partial entries
00ff / 00 never combine into a fourth hit. Same shared-helper check: hex6161
and UTF-8 aa both yield file46/47 with overlapping payload offsets0/1.
The one-byte pattern00 yields **7** payload occurrences, excluding metadata.

Three new combined tests passed. Initially one fixture assertion undercounted
those zeros as6; fixed to7 after checking the raw payloads, then reran only test
index0 (passed1/1). The other two passed on the first run. Tests cover invalid
ASCII syntax before bad input, empty states, longer-than-payload pattern, truncated
input, lowercase normalization, exact offsets/ledger, Top/full nested JSON/null,
UTF-8 compatibility and routing. No old test file was run.

Exactly four real analyzer processes returned **0 / 0 / 0 / 1**: uppercase hex
Top1 text, lowercase/full JSON with Top1, absent deadbeef text, existing sentinel
JSON refusal. The text has one row while JSON keeps all three hits and six entries.
Buffer checks independently verify bytes/positions/lengths/SHA/ledger. Input and
sentinel stay byte-identical; absent text saves no report and refusal has no save
success message. Evidence: `_build/data-hex-search-verification/run-tz9ztu/` contains
input, four logs, argv/status, results.json and new-hex-search.json.

Necessary interface/fmt/native checks and one release build passed. No local full
or old tests/scripts, demos/probes, V8 matrix, performance/large-module benchmark
or browser/PDF runs. CI retains prior checks and adds only this four-call script;
confirm the final exact SHA after push. Pictures, AGENTS/plans and _build evidence
are not included in the feature commit.


## Compare two explicitly located windows

After locating each side separately with UTF-8/hex search, choose each entry and
payload_offset explicitly using --data-preview plus --baseline-data-preview and
--baseline. --data-offset and --baseline-data-offset independently default to0;
one --data-limit clips both sides. The reused --data-preview-json has a separate
moonsize-data-preview-diff format when paired. No Top, resource identity matching
or automatic insert/delete alignment. Missing bytes are null, not zero-filled;
reports contain actual selected window content. Unlike --diff-data complete
content groups, this is equal-relative-position comparison of finite windows.
[Parameters, count equations and actual ranges](data-preview.md#explicit-two-window-comparison-source-addition-after-051).
