# Wasm file range ownership

This is a source addition after public **0.5.1**. The package version remains
0.5.1; this feature has not been republished to Mooncakes.

```sh
moonsize app.wasm --locate-range 40 32 --top 20
moonsize app.wasm --locate-range 40 32 --top 1 \
  --locate-range-json new-range.json
```

These coordinates illustrate syntax. They are **file offset and length**, not
two endpoints or a data payload offset. The query is `[offset, offset + length)`.
Both CLI values are strict nonnegative decimal Int values. Before adding them,
the library requires `offset <= file_size` and `length <= file_size - offset`.
It never clips a request. Length zero is valid anywhere through EOF, produces
no parts and covers zero bytes, and still performs basic module validation.

## Ownership and coverage

The nine region kinds are unchanged from [single-byte ownership](file-offset.md):
module header, section header, ordinary section payload, code count, function
size prefix, function body, data entry count, entry metadata and data payload.
`data_count` means the count field inside the data section, not the separate
datacount section. A body includes locals and instructions; this query does not
decode either. Custom/name payload interiors remain undivided.

Each part preserves:

- `owner_range`: the **whole original structural region**.
- `overlap_range`: only the positive-sized intersection with the request.
- `query_relative_offset` and `owner_relative_offset`: the intersection's start
  relative to the query and owner respectively.
- Physical section ordinal and full section context, full function index and
  function context when applicable, or original data entry index and context.
  Missing contexts stay null.

Physical ordinals include repeated custom sections. Function indices include
imports. Separate functions, entries and custom instances are never merged.
Zero-sized bodies/payloads do not produce rows; their prefixes/metadata remain.

All parts are ordered, disjoint and continuous from query start to end:

```text
sum(part.overlap_range.size) = covered_size = query.size
query_relative_offset = overlap.offset - query.offset
owner_relative_offset = overlap.offset - owner.offset
```

The implementation intersects shared structural partitions, rather than
querying every byte. It constructs each intersected code/data list at most once.
Basic `parse_module` checks still scan section/code structure; code refinement
adds function statistics and best-effort names, and data refinement reuses the
data inspector and its module checks. It does not claim to read only requested
bytes. A failed relevant inspector or inconsistent partition fails the whole
query; it never hides the error inside a generic payload or unknown row. An
unknown body opcode can still be located without decoding it.

## Text, JSON and CLI contract

Text shows identity, query, full coverage and part count, then overlap/owner
coordinates and relevant indices. Names are terminal-escaped. Top limits only
displayed parts (`showing N of M`); the ledger always uses **all** parts. Results
grow with structural regions. Top is not a resource limit.

JSON uses `format: "moonsize-file-range"`, `schema_version: 1`. It contains the
complete query and parts, whole-input SHA-256, null contexts and scope. It
contains no raw bytes or opcode records. JSON is never truncated by Top.

Only input, this query, own JSON and Top may combine. Baseline, strict, budgets,
HTML, ordinary analysis, preview, single-byte/decode and other modes are rejected
before business I/O. Unknown-option, `--` and first-argument help rules remain.
Destinations must be new `.json` paths; unified preflight and native exclusive
creation protect existing files. No rollback or multi-file transaction is added.

| Result | Exit |
| --- | ---: |
| Complete coverage, including empty query | 0 |
| Input, bounds, structure, ownership or output error | 1 |
| Parameter or combination error | 2 |

Use `--locate-offset` for one actual byte (EOF fails), `--data-preview` for a
bounded payload byte window (it may clip to payload end), and `--locate-range`
for structural ownership across a file range (no clipping). These are separate
commands. File coordinates are not runtime addresses. Ownership does not prove
full Wasm semantics, source attribution or deletion/recompile/gzip benefit.

## API and migration

```moonbit
locate_file_range(Bytes, Int, Int) -> Result[FileRangeReport, FileRangeError]
describe_file_range_error(FileRangeError) -> String
render_file_range(FileRangeReport, Int) -> String
render_file_range_json(FileRangeReport) -> String
```

New public types are `FileRangePart`, `FileRangeReport` and `FileRangeError`.
The error variants retain offset, length, file size and original ownership/input
reason, or an internal consistency explanation. Options gains only
`locate_range_offset`, `locate_range_length` and `locate_range_json`, all None by
default. External exhaustive Options construction needs those fields; callers
using defaults can leave them absent. Existing single-byte types, errors,
signatures, classification and JSON stay unchanged. Shared partition helpers
are private; no parser or WasmError changes are required.

## Actual local evidence

The fixed 78 B fixture reused from file-offset validation has SHA-256
`ac242670646f17a6eaa1ff9660f4ae7185cf276a64890847e387f890a29cee63`.
It includes one function import, two local definitions, repeated custom `x`
sections, nonshortest section/count/body prefixes, passive `abc` and an active
empty payload. Query **offset 45, length 32** covers **[45,77)**:

| Kind | Section | Owner range | Overlap range | Function / entry |
| --- | ---: | --- | --- | --- |
| section_header | 7 | [44,47) | [45,47) | — |
| code_count | 7 | [47,49) | [47,49) | — |
| function_size_prefix | 7 | [49,51) | [49,51) | function 1 |
| function_body | 7 | [51,53) | [51,53) | function 1 |
| function_size_prefix | 7 | [53,54) | [53,54) | function 2 |
| function_body | 7 | [54,56) | [54,56) | function 2 |
| section_header | 8 | [56,59) | [56,59) | — |
| data_count | 8 | [59,61) | [59,61) | — |
| data_entry_metadata | 8 | [61,65) | [61,65) | entry 0 |
| data_payload | 8 | [65,68) | [65,68) | entry 0 |
| data_entry_metadata | 8 | [68,74) | [68,74) | entry 1 |
| section_header | 9 | [74,76) | [74,76) | — |
| section_payload | 9 | [76,78) | [76,77) | — |

```text
32 = 2 + 2 + 2 + 2 + 1 + 2 + 3 + 2 + 4 + 3 + 6 + 2 + 1
```

The first overlap has owner-relative offset 1 and query-relative offset 0.
The last has query-relative offset 31 and covers 1 of the owner's 2 bytes.
The empty payload at file 74 emits no row. EOF `[78,78)` has zero parts.

Three filtered new combined unit tests passed first run (3/3). Exactly four
real CLI invocations returned **0 / 0 / 0 / 1**: Top 1 text, full JSON with Top
1, EOF empty JSON, and existing-output refusal. The Node Buffer oracle checks
fixed owners, intersections, identities, bytes, SHA, continuity and ledger;
input and sentinel remained unchanged. No V8 or probe build was needed.

Local records: `_build/file-range-verification/run-sHvIy3/` contains the input,
four logs, `processes.json`, `results.json`, `new-range.json`, `empty.json` and
the preserved sentinel. API before/after snapshots and diff are in
`_build/file-range-verification/review-d8q3wkv1/`.

Only new-feature tests, necessary interface/format/native checks and one release
build ran locally. Old/full suites, old CLI scripts/demos, performance, browser
and PDF checks were not rerun. Existing CI retains its full regression workflow
and adds only this four-call script; final-SHA status is reported separately.
