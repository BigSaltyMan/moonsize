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

## Source addition after public 0.5.1: generic-instance sizes

New entry points: inspect_generic_instances(Bytes) returning
Result[GenericInstancesReport, WasmError], render_generic_instances(report, top),
and render_generic_instances_json(report). New read-only types are
GenericInstance, GenericFamily, GenericCoverage and GenericInstancesReport.
Options adds generics (false) and generics_json (None); callers constructing the
record inside the package must account for these fields. Options::default remains
the external default constructor. No old symbol, analysis or report signatures
change. JSON uses the separate moonsize-generic-instances/schema_version 1 format.
The independent CLI mode accepts only Top/JSON, rejects strict before input I/O,
and inherits exclusive output creation. See [scope and real probe](generic-instances.md).
Version stays 0.5.1; this source increment has not been published to Mooncakes.

## Source addition after public 0.5.1: exported entrypoints

New APIs: inspect_entrypoints(Bytes) -> Result[EntrypointsReport, EntrypointsError],
render_entrypoints(report, top), render_entrypoints_json(report), and
describe_entrypoints_error(error). New types: EntrypointGroup,
EntrypointFunction, EntrypointsLedger, EntrypointsReport and EntrypointsError.
The error distinguishes wrapped input errors, invalid function exports, roots,
edges and unassigned export kinds. Options adds entrypoints=false and
entrypoints_json=None; use Options::default externally. No existing signature,
WasmError branch or report schema changes. The independent JSON format is
moonsize-entrypoints/schema_version 1; references to groups/functions use full
function indices. Strict refusals precede output checks; files use the existing
exclusive creator. See [the entrypoint contract](entrypoints.md). The module
version stays 0.5.1 and this increment is not published to Mooncakes.

## Source addition after public 0.5.1: identical function bodies

New APIs: inspect_duplicate_functions(Bytes) -> Result[DuplicateFunctionsReport,
WasmError], render_duplicate_functions(report, top), and
render_duplicate_functions_json(report). New read-only types:
DuplicateFunctionMember, DuplicateFunctionGroup, DuplicateFunctionsSummary and
DuplicateFunctionsReport. Options adds duplicates=false and duplicates_json=None;
Options::default supplies these defaults. Old signatures, Sections, WasmError and
existing report schemas remain unchanged. The independent format is
moonsize-duplicate-function-bodies/schema_version 1. It stores exact ranges and
metadata, not body content or estimated savings. Strict/other-mode combinations
are rejected before I/O; new JSON paths use the existing exclusive creator.
See [comparison scope and real byte ledger](duplicate-functions.md).
Version remains 0.5.1; this source increment has not been published to Mooncakes.

## Source addition after public 0.5.1: metadata file bytes

New APIs: inspect_metadata(Bytes) -> Result[MetadataReport, WasmError],
render_metadata(report, top), and render_metadata_json(report). New read-only
structures: MetadataRange, MetadataCustom, MetadataNameSubsection,
MetadataFunctionName, MetadataDiagnostic, MetadataCategory, MetadataNameGroup,
MetadataSummary and MetadataReport. Options adds metadata=false and
metadata_json=None; Options::default supplies the defaults. No old signature,
Sections, WasmError branch, effective-name selection or existing schema changes.
Function-name declaration indices and subsection counts retain full UInt/u32
values; they do not validate actual function existence. Ranges refer to original
file bytes. New JSON uses moonsize-metadata/schema_version 1 and retains complete
summaries, instances, physical records, remainders and diagnostics, without raw
payloads. Optional name-content failures return partial reports rather than
invalidating the outer module; outer parser errors remain errors. Strict and
other modes are rejected before input I/O; output uses exclusive creation.
See [the byte ledgers and coverage contract](metadata.md). Version remains 0.5.1;
this source increment has not been published to Mooncakes.

## Source addition after public 0.5.1: host import declarations

New APIs: inspect_imports(Bytes) -> Result[ImportsReport, WasmError],
render_imports(report, top), and render_imports_json(report). New read-only types:
ImportByteRange, ImportLimits, ImportDeclaration, ImportKindCounts, ImportModule,
ImportsLedger and ImportsReport. Options adds imports=false and imports_json=None;
Options::default supplies both. WasmError adds InvalidImportEncoding(Int, String),
carrying a file offset and malformed/unsupported reason: external exhaustive
matches must handle this branch. Existing truncation, LEB and trailing-byte
errors are reused. No old signature, default analysis, imported-function counting
behavior or existing report schema changes. The library uses module_name to avoid
the toolchain's reserved word; the independent moonsize-imports/schema_version 1
JSON uses module and keeps every declaration in physical order. UInt type indices
and limits retain their unsigned range; they are not complete semantic validation.
The CLI allows only Top and its own JSON; unsupported descriptors fail with exit 1,
not partial success, and new files use the existing exclusive creator. See
[the import support and byte-ledger contract](imports.md). Version remains 0.5.1;
this source increment has not been published to Mooncakes.

## Source addition after public 0.5.1: import inventory comparison

New APIs: compare_imports(Bytes, Bytes) -> Result[ImportsComparison,
ImportsComparisonError], render_imports_diff(report, top),
render_imports_diff_json(report), and describe_imports_comparison_error(error).
New types: ImportInventoryGroup, ImportInventoryCounts, ImportsComparison and
ImportsComparisonError (ImportsBaselineError / ImportsCurrentError wrapping the
original WasmError). No old signatures, WasmError branches or parser support
changes. Options adds diff_imports=false; Options::default supplies it. Each side
is inspected once, retaining the full ImportsReport; delta reuses ImportsLedger
for signed current-minus-baseline byte quantities, never ranges. JSON has the
independent moonsize-imports-diff/schema_version 1 format. Single-file imports
JSON retains its fields and meanings; private JSON constructors are shared.
Plain --imports still rejects baseline; --diff-imports requires a nonempty
baseline and allows Top, own JSON and an explicit --imports flag. It rejects
strict/other modes before I/O, reports side-specific errors and uses the existing
output slot and exclusive creator. Successful inventory differences return 0;
same_count is not a compatibility claim. See [scope and actual ledgers](imports.md).
Version remains 0.5.1; this increment is not published to Mooncakes.

## Source addition after public 0.5.1: duplicate data payloads

New APIs: inspect_duplicate_data(Bytes) -> Result[DuplicateDataReport, WasmError],
render_duplicate_data(report, top), and render_duplicate_data_json(report). New
read-only types: DuplicateDataGroup, DuplicateDataSummary and DuplicateDataReport.
Options adds data_duplicates=false and data_duplicates_json=None; Options::default
supplies both. Old signatures, WasmError and existing JSON contracts are unchanged.
The inspector calls inspect_data_segments once, retains the original report, and
hashes each payload once; no graph, analyze or self-comparison. Digest/length
buckets confirm actual bytes, including collisions. Group ids are minimum input
indices, not cross-build identities. Byte totals count all duplicate-group members,
not inferred savings. The independent moonsize-data-duplicates/schema_version 1
JSON retains all groups and original entries; text previews at most 20 members
per displayed group. Only Top/own JSON are allowed; other modes (including strict,
baseline, data details/diff and function duplicates) fail before I/O. The existing
output preflight and exclusive creator are reused. See [scope and actual ledgers](data-segments.md).
Version remains 0.5.1; this source increment has not been published to Mooncakes.

## Source addition after public 0.5.1: selected-function instruction encoding

New APIs: inspect_function_instructions(Bytes, Int),
describe_function_instructions_error(error), render_function_instructions(report,
top), and render_function_instructions_json(report). New types:
FunctionInstructionRange, FunctionInstructionRecord, FunctionOpcodeGroup,
FunctionInstructionsReport and FunctionInstructionsError. Errors wrap the original
WasmError or distinguish invalid targets, imported targets and range consistency.
Options adds instructions_index=None and instructions_json=None; default supplies
both, and external struct literals must include the new fields. Old signatures,
WasmError branches and report schemas are unchanged. The independent
moonsize-function-instructions/schema_version 1 JSON retains complete groups and
file-order instructions; Top limits both text tables only. Full function indices
include imports; imported targets fail because no local body exists. Only the
selected local body is instruction-decoded once, using the existing bounded
decoder and mnemonic table. No analyze/graph/retained, operands, WAT, execution
frequency, timing or savings. Strict and other modes are rejected before I/O;
JSON requires an explicit target and uses the existing preflight/exclusive writer.
See [ranges, measured ledger and scope](function-instructions.md). Version remains
0.5.1; this source increment has not been published to Mooncakes.

## Source addition after public 0.5.1: local function name search

New APIs: search_local_functions(Bytes, String), describe_function_search_error,
render_function_search(report, top), and render_function_search_json(report).
New types: FunctionSearchMatch, FunctionSearchReport and FunctionSearchError.
The error is InvalidFunctionSearchQuery or FunctionSearchInputError(WasmError).
Options adds find_functions=None and find_functions_json=None; default supplies
both, and external struct literals need these fields. Old signatures, WasmError
branches and report schemas are unchanged. Only available local raw/display
names are searched once, using case-sensitive literal substrings and the original
query. Imports and generated unnamed labels are excluded; real (unnamed) names
and different indices with the same name remain searchable. There is no graph,
analyze or instruction decoding. Top limits text only; the independent
moonsize-function-search/schema_version 1 JSON retains all matches, original
strings, coverage counts and byte totals. Empty results return 0, not absence or
removability proof. Other modes, including strict, are rejected before I/O. JSON
requires a query and uses the existing preflight/exclusive writer. See
[measured results and scope](function-search.md). Version remains 0.5.1; this
source increment has not been published to Mooncakes.

## Source addition after public 0.5.1: explicit instruction composition comparison

New APIs: compare_function_instructions(Bytes, Int, Bytes, Int),
describe_function_instructions_comparison_error,
render_function_instructions_diff(report, top), and
render_function_instructions_diff_json(report). New types: FunctionOpcodeDelta,
FunctionInstructionsDelta, FunctionInstructionsComparison and
FunctionInstructionsComparisonError. BaselineInstructionsError(index, cause) and
CurrentInstructionsError(index, cause) wrap the original FunctionInstructionsError,
retaining the selected target and original offset/reason. Options adds
baseline_instructions_index=None; default supplies it, and external struct literals
need the new field. Old signatures, WasmError and single-file JSON fields/types/
values remain unchanged. A private JSON object constructor is shared so the new
moonsize-function-instructions-diff/schema_version 1 format nests complete report
objects, not serialized strings. The instructions_json output slot and exclusive
writer are reused. Comparison requires both explicit indices plus a nonempty
baseline; no same-index default or name matching. Each selected body is inspected
once. Delta=current-baseline, preserving actual prefix/locals widths. Exact
mnemonic rows retain zero deltas; Top limits text only. Aggregates do not compare
sequences or immediate values and do not establish identity, equivalence,
compatibility or savings. See [actual ledgers and errors](function-instructions.md).
Version remains 0.5.1; this source increment has not been published to Mooncakes.

## Source addition after public 0.5.1: complete ordinary-analysis JSON

New API: render_summary_json(Analysis) -> String. Options adds summary_json=None;
default supplies it, and external struct literals need the field. No new public
analysis types, changed old signatures, WasmError branches, dependencies or old
JSON schemas. The CLI exports the same already-computed ordinary Analysis after
strict refusal and unified output preflight, using the existing exclusive writer.
Only Top, retained, dead-code, strict and max-size may accompany this option.
Max-size failure can still save the explanation before exit 3; strict refusal
writes nothing. The moonsize-summary/schema_version 1 object retains every
physical section, local definition, symbol module group, sorted model root and
existing diagnostic/source fields, adding readable reasons in this new format.
Top never truncates machine data. Retained dominated bytes include self, other
function counts exclude self, and missing results stay null without recalculation.
Imported indices may be roots but are not zero-byte local definitions. Module
labels are existing symbol attribution, not verified ownership. No raw bytes,
compression, baselines, budget results, full call edges, graph internals or
analysis reruns are included; hash and serialization have their own cost. See
[field types, ledgers and observed exits](summary-json.md). Version remains
0.5.1; this source increment has not been published to Mooncakes.
