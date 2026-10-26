# Wasm file byte ownership

Source addition after public **0.5.1**; this change does not publish a new package.
Build the current native CLI. These coordinates illustrate syntax; use a file
offset from your own instruction, data search or byte preview report:

```sh
moonsize app.wasm --locate-offset 31
moonsize app.wasm --locate-offset 31 --locate-offset-json new-location.json
```

## Query and classification

Offsets are nonnegative **decimal file byte offsets**, strictly less than file
size. `offset == file_size` fails: EOF is a boundary, not an existing byte.
Every range is half-open `[start, start + size)`. Physical section indices start
at zero and include every custom section, including repeated names. Function
indices include preceding imports. Data indices preserve original entry order.

| JSON region kind | Range covered |
| --- | --- |
| `module_header` | `[0, 8)` |
| `section_header` | Section ID and actual encoded length prefix |
| `section_payload` | An otherwise undivided payload |
| `code_count` | Actual local-function count encoding in code |
| `function_size_prefix` | Actual body-length encoding |
| `function_body` | Locals and instruction bytes, without further subdivision |
| `data_count` | Actual entry-count encoding inside data |
| `data_entry_metadata` | Entry start through the byte before payload |
| `data_payload` | Initialization payload bytes |

The separate **datacount section** is classified as `section_payload`; it is
not `data_count`. An empty data payload owns no byte, but its entry metadata
still has an owner. Offset expressions are not evaluated. Function bodies are
not split into locals, opcodes or immediates; custom/name and import/export
declaration interiors are not expanded.

## Reports and CLI behavior

Text shows input identity and SHA-256, query offset, physical section ordinal,
kind and range, the most specific region, its relative offset and applicable
function/data identity. Names are terminal-escaped. No raw bytes or opcode
records are emitted. JSON has `format: "moonsize-file-offset"`,
`schema_version: 1` and nested section/function/data range objects.

`region` contains `kind`, `file_offset`, `size`, `relative_offset`:

```text
region.file_offset <= query < region.file_offset + region.size
relative_offset = query - region.file_offset
```

Regions lie inside their section and, when applicable, the owning function or
data entry. Module-header queries have `section_index`, `section`, `function`
and `data_segment` all `null`. Section-only and count regions have no function
or data owner. Function regions have only `function`, data entry regions only
`data_segment`. Unavailable raw names, passive memory index and absent offset
expression are `null`, never a zero or empty object standing in for absence.

This independent CLI mode accepts only input, `--locate-offset` and its own
optional JSON. Explicit Top, baseline, strict, max-size, budget, HTML, search,
preview and other business options are rejected before input I/O. The number
must be a decimal whole integer within Int range; hex, negative numbers, units,
fractions and overflow are rejected. JSON requires the query and a nonempty new
`.json` path. Existing option values, unknown-option rejection, `--` and
first-argument-only help rules remain unchanged.

Exit codes: **0** for a successful location, **1** for input, query-range,
internal-range or output errors, **2** for argument/combination errors. JSON mode
prints only the save confirmation. The shared preflight and native exclusive
writer reject existing targets and aliases. EOF does not create output. No
overwrite/delete writer or multi-output transaction is added.

## Implementation cost and API migration

```moonbit
locate_file_offset(Bytes, Int) -> Result[FileOffsetReport, FileOffsetError]
describe_file_offset_error(FileOffsetError) -> String
render_file_offset(FileOffsetReport) -> String
render_file_offset_json(FileOffsetReport) -> String
```

New types are `FileOffsetKind`, `FileOffsetRegion`, `FileOffsetReport` and
`FileOffsetError`. Errors distinguish query bounds, wrapped `WasmError` and
inconsistent ownership. `Options` adds `locate_offset` and `locate_offset_json`,
both `None` by default; full external struct literals must add them. No old
public signatures, Wasm errors or JSON formats change.

The CLI reads the file once and locates once. `parse_module` checks the header,
section table and existing function/code structure first. This is not a
constant-time seek: those base checks scan code lengths even for a header query.
Only a selected **code payload** triggers `collect_function_stats`, including
import count and best-effort names, plus actual count-prefix reading. Only a
selected **data payload** invokes `inspect_data_segments` once, checking every
data entry and repeating its existing module checks. A data parse failure is
returned, not hidden by a generic region. A header or another section does not
claim that the data inspector ran.

File ranges use checked subtraction before addition. Code/data subranges must
partition the payload contiguously, with no gaps or overlaps; a missing owner
is an internal-range error. Zero-length bodies/payloads own no query byte.
The whole-input SHA-256 is computed once for a successful report. Rendering is
pure: it neither re-reads nor re-locates. There is no instruction inspection,
graph construction, retained calculation or ordinary `analyze`.

Success confirms this path's structural/range checks, not complete Wasm type
or instruction semantics. A file position is not a runtime memory address,
source location, execution trace or prediction of deletion/gzip savings.

## Actual focused evidence

The 78-byte mixed fixture SHA-256 is
`ac242670646f17a6eaa1ff9660f4ae7185cf276a64890847e387f890a29cee63`.
It has one imported function, two local definitions, three custom sections named
`x`, and non-shortest code/data section lengths, count and entry prefixes.

| Query | Physical section | Specific owner | Region | Relative offset |
| --- | --- | --- | --- | --- |
| 52 | 7, code `[44, 56)` | Function 1, encoding `[49, 53)` | body `[51, 53)` | `52 - 51 = 1` |
| 66 | 8, data `[56, 74)` | Entry 0, encoding `[61, 68)` | payload `[65, 68)` | `66 - 65 = 1` |

The first function prefix is `[49, 51)`. Code count is `[47, 49)` and data entry
count is `[59, 61)`, each two encoded bytes. Entry 0 metadata is `[61, 65)`;
entry 1 has metadata `[68, 74)` and an empty payload at 74. That boundary is
the next custom section header, not a data payload byte. Separate datacount
payload `[43, 44)` remains an ordinary section payload.

```sh
moon test --target native file_offset_wbtest.mbt
node scripts/test-file-offset.mjs _build/native/release/build/cmd/main/main.exe
```

Three combined new tests passed. Exactly four analyzer calls returned
**0 / 0 / 1 / 1**: function text, data JSON, EOF 78 (new target absent), existing
JSON sentinel. Independent fixture/Buffer checks confirmed byte ranges, identity,
SHA and unchanged input/sentinel. Evidence is retained locally in
`_build/file-offset-verification/run-0Qhnor/`: input, all argv/status records,
four logs, `new-location.json`, `results.json`. API review is in the sibling
`review-09ea3c9e/` directory.

Local validation ran only these new tests/calls, necessary interface/format/
native checks and one release build. No old suites/scripts, demos/probes,
V8 matrix, performance, browser, screenshots or PDFs. CI keeps the existing
regressions and adds only this four-call script; exact-SHA success is confirmed
after push. Version remains 0.5.1; Mooncakes publication is outside this change.
