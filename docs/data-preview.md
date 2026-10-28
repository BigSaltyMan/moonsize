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
require `--data-preview`. Baseline requires an explicit baseline preview pair
(see below); other analysis/report modes, strict, max-size, budgets and HTML
cannot be combined with preview. Decimal values must
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


## Find known binary bytes before previewing

Use --find-data-hex 00ff00 for compact known hex bytes such as NUL/ff that a UTF-8
query cannot express directly. It is mutually exclusive with --find-data and
shares --find-data-json, with a separate moonsize-data-hex-search format. Copy
the result's entry index and payload_offset to a separate --data-preview call;
file_offset is absolute and must not be supplied as a payload-relative offset.
No encoding detection/conversion, cross-entry match or payload context is added
to search. [Syntax, overlap example and API](data-search.md#compact-hexadecimal-byte-search-source-addition-after-051).

## Explicit two-window comparison (source addition after 0.5.1)

```sh
moonsize after.wasm --data-preview 2 --data-offset 8 --data-limit 32 \
  --baseline before.wasm --baseline-data-preview 1 --baseline-data-offset 4
moonsize after.wasm --data-preview 2 --data-offset 8 --data-limit 32 \
  --baseline before.wasm --baseline-data-preview 1 --baseline-data-offset 4 \
  --data-preview-json new-window-diff.json
```

Both entry indices must be explicit. --baseline-data-preview needs --baseline
and --data-preview; current preview with baseline also requires this explicit
baseline index. --baseline-data-offset requires the complete comparison pair.
Each payload offset independently defaults to **0**; a supplied current offset
is never copied to baseline. One --data-limit applies to both: default 256,
range 1..4096, each returns min(limit, remaining). An offset at payload end
succeeds with an empty window. No entry crossing or zero padding.

Indices/offsets use strict nonnegative decimal Int syntax. Missing pairs,
malformed numbers, invalid limits and combinations fail with **2** before
business I/O. Explicit Top remains rejected, including `--top 10`. Only the preview
options and this baseline pair may combine; no strict, search, diff-data, HTML,
budgets or other analyses. Unknown options, -- and help routing are unchanged.
Success including empty windows returns **0**; input/index/range/output errors
return **1**, preserving baseline/current and the original DataPreviewError.

Each side is read once by CLI and previewed once by the library. Both succeed
before positional comparison; an invalid side yields no partial report and
creates no new JSON. The existing data-preview-json slot, unified preflight,
path/alias protections and native exclusive creation are reused. No new writer
or transactional guarantee. The single-input mode and schema remain unchanged.

### Position facts and output

Positions cover 0 <= i < max(baseline.returned_size, current.returned_size).
Each has window_relative_offset, status, baseline_byte/current_byte (0..255 or
null), and the corresponding original file offsets (null exactly when absent).
Statuses are same_byte, different_byte, baseline_only, current_only. Both-absent
positions do not exist. Zero-valued bytes remain 0, not null. The result keeps
complete original preview reports plus all positions/counts, at most 4096 records.
No complete payload is copied beyond the existing bounded previews. Input files
are still read and data encodings inspected; this is not a whole-process memory
or time limit.

Text DATA PAYLOAD WINDOW COMPARISON shows both SHA/indices/payload offsets/file
ranges/returned sizes/limits/remaining bytes, their original byte ledgers and counts.
Each row contains at most 16 relative positions, before/after hex and markers:
`.` same, `^` different, `B` baseline-only, `C` current-only. Absent bytes are
`--`, actual zeros `00`. Offset labels are decimal. All rows are printed, at
most 256, without Top truncation. Markers are not minimal edit operations.

JSON **moonsize-data-preview-diff**, schema_version 1, embeds complete baseline
and current **objects**, all positions, counts, returned_size_delta and scope.
A private Json constructor is reused; no old-string parse round trip. Each
nested original preview keeps moonsize-data-preview/schema1 and selected entry
metadata, full returned hex and nullable fields. The old single-input renderer
and format/fields remain unchanged.

```text
compared_positions = max(baseline.returned_size, current.returned_size)
                   = same_count + different_count + baseline_only_count + current_only_count
baseline.returned_size = same_count + different_count + baseline_only_count
current.returned_size = same_count + different_count + current_only_count
returned_size_delta = current.returned_size - baseline.returned_size
                    = current_only_count - baseline_only_count
```

Both-empty windows succeed with zero counts/positions. A one-sided empty window
makes all other bytes only. Comparing ABC with XABC yields 3 different positions
and 1 current_only, without aligning the insertion. Equal selected windows prove
nothing about whole payloads, files, resource identity, runtime addresses or
optimization/rebuilt/gzip benefits. only means byte presence, not semantic
addition/removal. Reports contain actual selected contents.

--diff-data groups **complete payload bytes** by content and counts occurrences;
this feature compares **explicit finite windows** at equal relative positions.
It does not search for or match resources, compute edit distance or extract files.

### Public API migration

```moonbit
compare_data_previews(Bytes, Int, Int, Bytes, Int, Int, Int)
  -> Result[DataPreviewComparison, DataPreviewComparisonError]
describe_data_preview_comparison_error(DataPreviewComparisonError) -> String
render_data_preview_comparison(DataPreviewComparison) -> String
render_data_preview_comparison_json(DataPreviewComparison) -> String
```

Parameters are baseline data/index/offset, current data/index/offset, common
limit, in that order. Three new types: DataPreviewPosition, DataPreviewComparison,
DataPreviewComparisonError. Errors wrap the original DataPreviewError separately
as BaselineDataPreviewError or CurrentDataPreviewError; the old error enum is
unchanged. Options adds baseline_data_preview_index=None and
baseline_data_offset=None; external complete struct literals must add these
fields. Old public signatures, package version 0.5.1 and dependencies remain;
this source increment has not been published to Mooncakes.

### Actual focused verification

Baseline **32 B**, SHA-256
`48d940e4f66d58046d735cadd3b97b2d0f516419a972d6a53f8d4a91f9eb7123`;
current **41 B**, SHA-256
`f3f59c92d50e97788b806f8ee3edd95fd4a3ea3152783676602b2afdf558976b`.

| Side | Entry | Payload file range | Selected payload offset | File window | Returned | Limit | Remaining |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Baseline | 1 | [21,27) | 1 | [22,27) | 5 | 32 | 0 |
| Current | 2 | [20,41) | 3 | [23,41) | 18 | 32 | 0 |

Baseline selected bytes `00ff414200`; current `007f414200101112131415161718191a1b1c`.
Position 0 is actual zero on both sides, position 1 ff/7f differs, positions 2..4
are equal 41/42/00, and positions 5..17 have baseline null/current 10..1c. File
offsets are 22+i when baseline exists and 23+i for current. Count ledger:
**18 = same4 + different1 + baseline-only0 + current-only13**;
**5 = 4 + 1 + 0**, **18 = 4 + 1 + 13**; returned delta **+13 = 13 - 0**.
Original payload ledgers **6 = 1 + 5 + 0**, **21 = 3 + 18 + 0**.
Swapping sides gives baseline_only13 and returned delta-13 in unit checks.
Window-size delta is not the file-size delta (here file41-32=9), nor a savings claim.

Three new combined tests passed on the first run: explicit ranges/bytes/null/
ledgers/reversal, both/one-sided empty windows, self, common clipping, max 4096,
indexed/range/limit/input side errors, two-line/last-line/null/old-schema output,
nonalignment example, and CLI dependencies/defaults/numbers/Top/combination/help/--.
No old test file was executed.

Exactly four real CLI calls returned **0 / 0 / 0 / 1**: text comparison, complete
JSON, current/current self JSON, existing sentinel refusal. Text has 16+2 positions
in two rows; Buffer-derived expected hex/markers match exactly. JSON retains all
18 positions and complete nested reports. Self has same 18/different 0/only 0 and
zero delta. Both inputs and sentinel stay byte-identical; refusal has no successful
save message. Evidence `_build/data-preview-diff-verification/run-zhNxIt/` contains
both inputs, four logs, original argv/status, results.json, new-window-diff.json
and self.json.

Necessary interface/fmt/native checks and one release build passed. No local
old/full tests, old CLI/demos, probes, V8 matrix, performance/large-module or
browser/PDF runs. CI keeps previous checks and adds only the four-call script;
verify final exact-SHA success after push. Version remains 0.5.1, no publication.
Pictures, AGENTS/plans and build evidence are excluded from the feature commit.

## Explain a file range instead of previewing bytes

`--locate-range OFFSET LENGTH` uses original-file coordinates, not payload
coordinates, and reports structural intersections rather than byte contents.
It can cross sections/functions/entries, never clips at EOF, and accepts an EOF
empty range. Top affects text rows only. Preview retains its bounded/clipped
payload semantics. Run these independent modes separately; neither locates a
runtime memory address. [Range ownership and API](file-range.md).
