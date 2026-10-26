# Bounded data payload byte preview

This is a source addition after public **0.5.1**, not a new Mooncakes release.
Build the current native CLI. The following indices, offsets and paths illustrate
syntax; they are not measurements of your input:

```sh
moonsize app.wasm --data-preview 1
moonsize app.wasm --data-preview 1 --data-offset 8 --data-limit 32
moonsize app.wasm --data-preview 1 --data-offset 8 --data-limit 32 \
  --data-preview-json new-preview.json
```

## Window and output rules

| Option | Meaning | Default |
| --- | --- | --- |
| `--data-preview` | Original zero-based data entry index, not size rank | Required |
| `--data-offset` | Byte offset within the selected payload | 0 |
| `--data-limit` | Maximum returned bytes, 1..4096 | 256 |
| `--data-preview-json` | New `.json` destination | Absent |

Offsets must be in `[0, payload.size]`. At the end, preview succeeds with an
empty window; an empty payload permits offset 0. A limit larger than the
remaining payload is clipped to the end. The preview never crosses entries,
includes prefixes/expressions or pads missing data with zero bytes. Invalid
indices, including inputs with no entries, fail rather than inventing a segment.

The standalone mode accepts only the input and these four options. Explicit
`--top` is rejected, even when equal to the normal default. All three modifiers
require `--data-preview`. Other analysis/report modes, baseline, strict,
max-size, budgets and HTML cannot be combined with preview. Decimal values must
be nonnegative whole integers within Int range; no units, fractions or signs.
Limit additionally must be 1..4096. The existing `--` separator and
first-argument-only help rules remain unchanged.

Text uses at most 16 bytes per row (maximum 256 rows), with decimal payload and
file offsets, lowercase two-digit hex, and ASCII. Only bytes `0x20..0x7e` appear
literally in the ASCII column; all others become dots. Padding aligns columns
without adding data. A window may cut through a multibyte character; it is not
decoded, repaired or asserted to be valid UTF-8. Empty windows have no data rows.

JSON uses `format: "moonsize-data-preview"`, `schema_version: 1`. It contains
the complete selected `DataSegment` metadata and a continuous lowercase `hex`
string of exactly `returned_size * 2` characters. Missing memory index and
offset expression stay `null`. There is no Base64, guessed string or full list
of other entries. “Complete JSON” means the complete **returned finite window**,
not the entire payload. Both reports contain actual window content.

The ledger is:

```text
payload.size = payload_offset + returned_size + remaining_bytes
window.offset = segment.payload.offset + payload_offset
window.size = returned_size = bytes.length()
```

A file offset is not a memory address. Offset expressions remain unevaluated;
preview does not infer source ownership, resource use, liveness, safe merging
or deletion/recompiled/gzip savings. It does not extract a payload file.

## Search, then inspect

These example coordinates are placeholders. Use coordinates returned by your
own search; neither CLI call automatically invokes the other:

```sh
moonsize app.wasm --find-data "assets/logo"
moonsize app.wasm --data-preview 1 --data-offset 8 --data-limit 64
```

See [literal search](data-search.md) and [data encoding ledger](data-segments.md).

## API and errors

```moonbit
preview_data_segment(Bytes, Int, Int, Int) -> Result[DataPreviewReport, DataPreviewError]
describe_data_preview_error(DataPreviewError) -> String
render_data_preview(DataPreviewReport) -> String
render_data_preview_json(DataPreviewReport) -> String
```

The library requires explicit index, offset and limit. It rejects an invalid
limit, calls `inspect_data_segments` once, validates the index and offset, then
computes `available = payload.size - offset` and `returned = min(limit, available)`.
It never uses unchecked `offset + limit`. Only the returned window is copied,
at most 4096 bytes. The inspector still checks **all** data encodings; SHA-256
still covers the entire input. This is not a target-entry-only parser. There
is no `analyze`, graph construction or content search.

New types are `DataPreviewReport` and `DataPreviewError`. The latter distinguishes
limit, index (with actual entry count), offset (with actual payload size) and
wrapped `WasmError`. `Options` adds four optional fields: `data_preview_index`,
`data_offset`, `data_limit`, `data_preview_json`; all default to `None`, and the
CLI fills offset/limit only when running preview. Complete struct literals need
these fields. Existing public signatures, Wasm errors and JSON formats do not
change. Rendering is pure and does not re-read or re-inspect the input.

Exit codes: **0** for valid or end-empty windows; **1** for read/structural/index/
offset/output errors; **2** for argument syntax, limit or mode errors. JSON mode
prints only the save confirmation. Shared preflight and native exclusive-create
protect existing files and aliases; no overwrite/delete path is added. A failed
write may leave a newly created partial file; multi-file writes are not a transaction.

## Actual focused verification

The 92-byte fixture has SHA-256
`596b71eb6db4f48d527a144bddb88fb5f73735b3504f30e75d530bb7ae8f4bfc`.
Entry 1 of 3 is passive with payload file range `[21, 82)` (61 bytes).

The text request offset 1, limit 20 returns `[22, 42)`: **61 = 1 + 20 + 40**.
Its exact hex is `094142434445464748494a4b4c4d4e4f501b7f20`.
Rows start at payload/file offsets **1/22** and **17/38**; ASCII is
`.ABCDEFGHIJKLMNO` and `P.. ` (the final space is an actual printable byte).
The JSON request offset 1, limit 4096 returns `[22, 82)`, 60 bytes with no
remaining bytes: **61 = 1 + 60 + 0**, and 120 hex characters. Node independently
verified hex against the original file; adjacent payloads were not included.

```sh
moon test --target native data_preview_wbtest.mbt
node scripts/test-data-preview.mjs _build/native/release/build/cmd/main/main.exe
```

Three combined new tests passed, covering byte windows/ledgers, errors/rendering
and CLI contracts. Exactly four real analyzer calls returned **0 / 0 / 1 / 1**:
text, complete bounded JSON, offset 62 (new output absent), and an existing
sentinel JSON. Input and sentinel bytes stayed unchanged. Local evidence is
`_build/data-preview-verification/run-tWH3cU/` with input, argv/status records,
four logs, `new-preview.json` and `results.json`. API snapshots are in the sibling
`review-de72d634/` directory.

Local checks did not run old suites/scripts, source demos/probes, V8 matrices,
performance or browser/screenshot/PDF acceptance. CI retains its old checks and
adds only this four-call script; final exact-SHA CI is confirmed after push.
Version stays 0.5.1; no package publication is part of this change.

## Locate an absolute window position

A separate source addition after 0.5.1 provides `--locate-offset`. Use the
preview row's **FILE OFFSET**, not its payload offset; query the actual input
byte, strictly below EOF. For example `moonsize app.wasm --locate-offset 31`
has an illustrative coordinate. A zero-sized end window contains no byte, so
its start may be a later region or EOF rather than that payload's owner.
[File ownership and nine region kinds](file-offset.md). Run separately, with no
Top or strict; this does not evaluate offset expressions or runtime addresses.
