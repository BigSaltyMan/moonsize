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
still has an owner. Offset expressions are not evaluated. By default, function
bodies are not split into locals or instructions; custom/name and import/export
declaration interiors are not expanded.

## Reports and CLI behavior

Text shows input identity and SHA-256, query offset, physical section ordinal,
kind and range, the most specific region, its relative offset and applicable
function/data identity. Names are terminal-escaped. Default reports emit no raw
bytes or instruction records. Default JSON has `format: "moonsize-file-offset"`,
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

This independent CLI mode accepts input, `--locate-offset`, its own optional
JSON and optional `--locate-decode`. Explicit Top, baseline, strict, max-size, budget, HTML, search,
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
The whole-input SHA-256 is computed once for a successful base report. Rendering
is pure: it neither re-reads nor re-locates. The default path has no instruction inspection,
graph construction, retained calculation or ordinary `analyze`.

Success confirms this path's structural/range checks, not complete Wasm type
or instruction semantics. A file position is not a runtime memory address,
source location, execution trace or prediction of deletion/gzip savings.

## Base location evidence (commit 4fa22cc)

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

## Optional target-function decoding (source increment after 0.5.1)

Only explicit `--locate-decode` enables this behavior; it requires
`--locate-offset`. These example numbers are placeholders:

```sh
moonsize app.wasm --locate-offset 45 --locate-decode
moonsize app.wasm --locate-offset 34 --locate-decode --locate-offset-json new-detail.json
```

If the base region is `function_body`, the entire selected local function
must decode successfully using existing instruction support. The detail is
`locals_encoding` or one whole `instruction`, with a half-open file range
and `relative_offset = query - detail.file_offset`. Opcode, extended subopcode
and immediate bytes belong to that same instruction. No operand fields/values,
`byte_role`, WAT or call-target guesses are emitted. The base
`location.region.kind` remains `function_body`.

For a size prefix, section/module header, count, data or another non-body byte,
status is `not_applicable` and detail is `null`; no instruction decoding
runs. Applicable queries return `decoded`. A bad target returns an error even
when the query is in valid locals before the bad instruction; there is no partial
success or fallback. Unknown opcodes in other function bodies do not block a
valid target. EOF and the existing argument rules still apply. Non-body and
successful decoded queries return 0; location/decode/write failure 1; argument
errors 2. Decode failure happens before output checks/creation or success text.

JSON without the modifier keeps `moonsize-file-offset`/schema 1 unchanged.
With the modifier it uses `moonsize-file-offset-decoded`/schema 1, containing
`location` as the original **object**, plus `decode_status`, `detail`
and `scope`. Locals detail has `instruction: null`. Instruction detail
reuses `FunctionInstructionRecord` (ordinal, mnemonic, file offset,
body-relative offset and encoded size). Only the matching record is exported,
not the entire list. Both formats use the same existing JSON target slot and native
exclusive writer; Top is still rejected.

```moonbit
locate_file_offset_decoded(Bytes, Int) -> Result[FileOffsetDecodedReport, FileOffsetDecodeError]
describe_file_offset_decode_error(FileOffsetDecodeError) -> String
render_file_offset_decoded(FileOffsetDecodedReport) -> String
render_file_offset_decoded_json(FileOffsetDecodedReport) -> String
```

New types are FileOffsetDecodedReport, FileOffsetDecodeStatus,
FileOffsetDecodeDetail, FileOffsetDecodeDetailKind and FileOffsetDecodeError.
Errors wrap base-location and instruction-inspection failures or explain a
consistency failure. Options adds only `locate_decode: Bool`, default false;
full struct literals must add it. FileOffsetKind, FileOffsetReport, WasmError
and their old public signatures remain unchanged.

The entry locates exactly once, then calls `inspect_function_instructions`
exactly once for a body hit. Existing structural/name checks and whole-file
hashing can repeat across these two composed APIs; only target instruction
decoding runs once. File size/SHA, function identity and entry/prefix/body ranges
must agree, and locals plus all contiguous instruction ranges must cover the
body exactly. It accepts no separately supplied reports. Rendering does not
parse or decode. Other functions and complete Wasm type, stack or control-flow
semantics are not certified. Counts/bytes do not imply execution frequency,
time, removal or optimization savings. No new opcodes are added.

### Actual decoded-location verification

Reused fixed function-instructions fixture: 90 bytes, SHA-256
`768c361dbef43f068141ad27b866b8540ff221433d84b95ff22e684b4179283e`.
It has one function import and target function index 1, encoding [31,66),
prefix [31,33), body [33,66). Body ledger: **33 = locals 3 + instructions 30**.

| Query | Detail | Range | Relative offset | Evidence |
| --- | --- | --- | --- | --- |
| 45 | ordinal 4, i32.const | [43,46) | 45 - 43 = 2 | fixture bytes 41 80 01; body-relative start 10 |
| 34 | locals_encoding | [33,36) | 34 - 33 = 1 | fixture bytes 01 02 7f; instruction=null |

The known instruction is [43,46), so its last immediate byte is not classified
as another opcode. Unit checks also include 0xFC/subopcode ownership and the
final end. A deliberately invalid copy changes only byte 47 to 0xff, preserving
outer lengths; its locals query 34 fails with unknown opcode at 47 and no file.
The bad copy SHA-256 is
`8d6473a3c71940764dd0102af00f114449bcfa386eda32ee63ede67a45c591fd`.

```sh
moon test --target native file_offset_decode_wbtest.mbt
node scripts/test-file-offset-decode.mjs _build/native/release/build/cmd/main/main.exe
```

Three new combined tests passed; exactly four analyzer calls returned
**0 / 0 / 1 / 1**: immediate text, locals JSON, bad target (new output absent),
and existing sentinel. Input and sentinel bytes stayed unchanged. Evidence:
`_build/file-offset-decode-verification/run-SzeQzE/`, including both inputs,
raw argv/status, four logs, new-detail.json and results.json. API snapshots:
`review-fa7ea65e/`. No local old suites/scripts, demos, probes, V8 matrix,
performance or browser/PDF acceptance. Existing CI remains and only adds the
four-call script. Confirm the final exact SHA after push. Version stays 0.5.1;
this increment is not a Mooncakes publication.

## Inspect declarations without a complete body decode

`--locals <index>` is a separate source addition after public 0.5.1. It reads only
the selected body's locals declarations and labels the remainder undecoded.
Unlike `--locate-decode`, it can succeed with an unknown opcode after valid
locals; it does not validate that remainder or resolve local indices including
parameters. These standalone queries cannot be combined. See the
[group ranges, precision and API](function-locals.md).


## Locate a returned opcode site

The source-only --find-opcode query returns decoded mnemonic sites with original
file offsets, full function indices and full-sequence ordinals. Copy a returned
offset into a separate --locate-offset / --locate-decode command; do not combine
the independent modes. No raw-byte opcode inference or runtime address lookup
is performed. On the documented 168 B fixture, query i32.const returns file
49/52/77/80; 49 is the complete instruction at function1 ordinal2, not its
following immediate. [Query contract and original bytes](opcode-search.md).


## Locate a hexadecimal data-search hit

--find-data-hex returns the same DataSearchMatch coordinates as UTF-8 search.
Use file_offset in a separate --locate-offset call, not payload_offset. On the
documented 49 B fixture, pattern00ff00 hits file23/25 in entry0 and file31 in
entry1; the custom copy at file15 is excluded. No memory-address or automatic
encoding interpretation is involved. The two independent modes cannot combine.
[Hex rules and original-byte checks](data-search.md#compact-hexadecimal-byte-search-source-addition-after-051).
