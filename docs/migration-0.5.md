# Migrating from public 0.4.0 to 0.5.0

This guide compares the public 0.4.0 package with the 0.5.0 source. Actual
publication, source SHA, exact-SHA Linux CI, ZIP hashes and external consumer
results are recorded when completed in the
[v0.5.0 release](https://github.com/BigSaltyMan/moonsize/releases/tag/v0.5.0).
It is not a claim that those later steps have already succeeded.

## CLI behavior changes

All report files now require a **new** target, including the older `--html` and
`--call-graph` modes that could overwrite files in 0.4.0. Existing files,
directories and link aliases are refused with exit 1. All requested targets are
preflighted before the first write; each native write uses exclusive creation.
Generate to a new staging path, inspect it, then explicitly replace the desired
example outside the CLI. There is no force flag. This is not a multi-file
transaction or protection against hostile parent-directory replacement; see
[the actual guarantees](output-protection.md).

New options: `--data-segments`, `--data-json <new.json>` and `--diff-data`
(requires `--baseline`). Default analysis and report content are unchanged when
these are absent. HTML accepts single-input data details explicitly; HTML with
`--diff-data` is rejected with exit 2. Text `--top` does not truncate JSON or
totals, nor control HTML's 20-row batches. Existing strict and budget exit 3
semantics remain. Input/parsing/writing errors return 1; mode conflicts return 2.

## Library additions and migration points

Existing `parse_module`, `analyze`, `build` and `render_html` signatures remain.
`Analysis`, `WasmModule` and `Sections` do not gain mandatory fields. Dependencies
and native target requirements are unchanged.

New public types for inspection:

- `DataByteRange` (`offset`, `size`), `DataSegmentMode` (`Active`, `Passive`).
- `DataSegment`: index/mode/memory index, encoding and payload ranges, optional
  offset-expression range, and actual encoded field lengths.
- `DataSegmentsReport`: file size, optional data section/datacount, section/header/
  count sizes, payload and entry metadata totals, and all entries.

New public types for content-group comparison:

- `DataPayloadGroupKind`: `SharedPayload`, `BaselineOnly`, `CurrentOnly`.
- `DataGroupTotals`: count, payload, encoded and metadata sizes.
- `DataPayloadGroup`: report id, full SHA-256, payload length, kind,
  both entry-index lists, both totals and their signed delta.
- `DataSegmentsDelta`: section, payload, entry metadata and section overhead deltas.
- `DataSegmentsComparison`: both file hashes, both complete inspection reports,
  all content groups and the aggregate delta.

New entry points (argument names omitted except the optional ECharts source):

```moonbit
inspect_data_segments(Bytes) -> Result[DataSegmentsReport, WasmError]
compare_data_segments(Bytes, Bytes) -> Result[DataSegmentsComparison, ComparisonError]
render_data_segments(DataSegmentsReport, Int) -> String
render_data_segments_json(DataSegmentsReport) -> String
render_data_segments_diff(DataSegmentsComparison, String, String, Int) -> String
render_data_segments_diff_json(DataSegmentsComparison, String, String) -> String
render_html_with_data_segments(Analysis, String, DataSegmentsReport, echarts? : String) -> String
```

Pass an inspection report for the **same input** to the new HTML entry point;
it reuses the template and compression measurements without reparsing the input.
The old `render_html` remains available. Native CLI reports inline pinned ECharts;
library callers still choose the optional resource source (empty retains CDN).

`Options` adds `data_segments : Bool`, `data_json : String?`, `diff_data : Bool`.
`Options::default` and `parse_options` populate false/None/false. Code maintaining
record constructors must account for these additions.

`WasmError` adds `InvalidDataEncoding(Int, String)` (file offset and reason).
**External exhaustive matches must add a case** or a suitable fallback;
`describe_error` already renders it. Comparison errors preserve baseline/current
attribution through the existing `ComparisonError`.

## JSON compatibility and interpretation

Existing graph, experiment, function-path and budget JSON formats are unchanged.
HTML's existing schema and fields retain their meaning; opted-in reports add
optional `dataSegments` metadata, never payload bytes.

The new independent single-input format is `moonsize-data-segments`, schema 1.
With `--diff-data`, `--data-json` instead emits `moonsize-data-segments-diff`,
schema 1. Consumers must dispatch on `format`, not assume these two are the same
shape. The original single-input renderer and format remain unchanged.

Data sizes form a file-byte ledger, not runtime memory usage. Expressions are
recorded through their terminating instruction and explicitly not evaluated.
No memory-index/constant-expression/type/instantiation validation is promised.
Payload groups compare actual bytes after hash bucketing and count duplicates;
they do not establish cross-build identity, initialization equivalence, safe
deduplication, rebuilt savings or gzip gains. Datacount stays separate.

The performance baseline has not measured 50k functions, peak memory or real
large projects. Historical browser/PDF evidence is reused with its original
environment and review scope; other engines and physical printers remain untested.

## 0.5.1 documentation compatibility patch

Public 0.4.0/0.5.0 depend on bikallem/compress@0.3.4, whose old
moon.mod.json is rejected by the current Mooncakes documentation builder.
0.5.1 removes that registry chain and ships the pinned synchronous runtime under
internal/compression, with original/adapted hashes and Apache-2.0 attribution.
No root library signature or report schema changes; gzip defaults are retained.
See [toolchain checks and publication status](toolchain-compatibility.md).

## Source addition after public 0.5.1: incoming references

This unreleased source increment keeps the module version unchanged. New public
entry points are function_callers(Bytes, Int), render_function_callers(report, top),
render_function_callers_json(report) and describe_function_callers_error(error).
New types: FunctionCallersReport, FunctionCallerGroup, FunctionCallersError
(CallersInputError / InvalidCallersTarget / InvalidCallersEvidence). Nodes and
sources reuse FunctionPathNode and FunctionPathStep. Options adds callers_index
and callers_json (both None by default); manual record constructors must include
them. Existing path APIs, graph algorithms and report formats are unchanged.
The new independent JSON format is moonsize-function-callers/schema_version 1.
See [the callers contract](function-callers.md) for complete counts, model scope,
mode constraints, strict behavior and the actual sample. No Mooncakes publication
is claimed by this source commit.
