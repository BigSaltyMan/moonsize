# Migrating from public 0.5.1 to the 0.6.0 source candidate

**0.6.0 is a source release candidate, not a published Mooncakes version.**
Do not treat `moon add BigSaltyMan/moonsize@0.6.0` as an available installation
command. No tag or GitHub Release is created by this preparation. The existing
[v0.5.1 release](https://github.com/BigSaltyMan/moonsize/releases/tag/v0.5.1)
remains the identity of the old public library. `moon add` adds a library
dependency; it does not install an independent CLI. Build current native CLI
features from an explicit full source commit as described in
[source delivery](source-delivery.md).

## Comparison baseline and scope

The readable public0.5.1 source baseline used here is commit
`2b0db5acaf6cb080cb1cc0fd1a4d2f1c479fa6a7`. Its original release/export and
registry-verification records associate it with that public version; the recorded
registry ZIP SHA-256 is
`e18e242d89e80d0989d79f5f94e336e0e7e9845b36171e4be614a288a643620e`.
The local Git object and prior generated public interface record are readable.
The local checkout has no v0.5.1 tag, so the explicit commit and release records
were used rather than assuming the tag resolves locally.

The current interface was checked against the generated interface saved after
the last product implementation, `bd86359`, whose product declarations remain
unchanged through the package-audit commit `4b93245`. The comparison reads those
existing interfaces and source files; no historical version was built, no ACL
was changed, and no new `moon info` was run for this candidate preparation.
This is a source/API and schema-construction review, not a claim of a freshly
executed historical-output or binary-ABI compatibility matrix.

Features previously documented as “source additions after public0.5.1” are now
included in the0.6.0 candidate. Their development sections and measured evidence
retain their original versions, commits and dates. This candidate commit only
collects that work through version, documentation and strict package-identity
checks; it does not implement those features again.

## Capabilities accumulated since the public package

| Task | Candidate additions and detailed guides |
| --- | --- |
| Find and investigate functions | [Name search](function-search.md), [instruction encoding and explicit two-function comparison](function-instructions.md), [locals and comparison](function-locals.md), [local access encoding](function-local-accesses.md), [call sites](function-calls.md), [identical bodies](duplicate-functions.md), [generic families](generic-instances.md) |
| Inspect instruction composition | [Module opcode statistics and comparison](module-opcodes.md), [opcode location search](opcode-search.md) |
| Locate data and file bytes | [UTF-8/hex payload search](data-search.md), [bounded previews and two-window comparison](data-preview.md), [payload duplicate groups](data-segments.md), [offset ownership/decode](file-offset.md), [range decomposition](file-range.md) |
| Inspect host interfaces and metadata | [Imports and comparison](imports.md), [exports/aliases and comparison](exports.md), [custom/name byte ledgers and outer comparison](metadata.md) |
| Export machine-readable reports | [Ordinary summary JSON](summary-json.md), [function/module comparison JSON](function-diff-json.md), and complete JSON alongside each independent query |
| Explain reference relationships | [Callers](function-callers.md), [pair paths](function-path-between.md), [outgoing closure/DOT](function-dependencies.md), [incoming closure/DOT](function-dependents.md), [set overlap](dependency-overlap.md), [cycles and closed evidence](function-cycles.md), [entrypoint attribution](entrypoints.md) |
| Discover valid commands | [Seven help topics, unknown options and the `--` separator](cli-help.md) |

The table is a navigation guide, not a replacement parameter manual. Independent
modes have distinct combination rules; use their guides or `--help-topic` before
combining flags. Top limits presentation, not search/build cost or complete JSON
and DOT output.

## Source compatibility requiring caller changes

Prefer the existing constructor:

```moonbit
let options = @moonsize.Options::default("app.wasm")
```

The public0.5.1 Options record had22 fields; the candidate has88. All original
field names and types remain, with66 fields added over the intervening feature
commits. A caller manually constructing the complete Options record must supply
the new fields. They include summary/comparison JSON, function queries, incoming
and outgoing closures/DOT, cycles, interface/metadata queries, data search and
windows, and file-location queries. `Options::default` supplies absent values;
`parse_options` applies the actual independent-mode constraints. This is **not**
a blanket claim of source compatibility for record literals.

The existing `WasmError` enum adds exactly these variants relative to public0.5.1:

```moonbit
InvalidImportEncoding(Int, String)
InvalidExportEncoding(Int, String)
```

Their arguments carry a file offset and reason. External exhaustive matches
must handle them or use an appropriate fallback. All original variants remain.
New independent queries also introduce their own error/status enums (for example
FunctionDependenciesError, FunctionDependentsError and FunctionPathBetweenStatus);
handle the types returned by each new entry point rather than assuming every
query returns WasmError. This preparation adds no new error variant itself.

Static interface comparison found no removed public declarations and no changed
pre-existing function signature. Apart from Options and WasmError, the existing
public type declarations were unchanged in that comparison. These findings do
not imply that every malformed input is accepted or rejected as before, nor
do they establish full Wasm semantic validation.

Representative actual new entry points include:

```moonbit
function_dependencies(Bytes, Int) -> Result[FunctionDependenciesReport, FunctionDependenciesError]
function_dependents(Bytes, Int) -> Result[FunctionDependentsReport, FunctionDependentsError]
function_path_between(Bytes, Int, Int) -> Result[FunctionPathBetweenReport, FunctionPathBetweenError]
compare_function_dependencies(Bytes, Int, Int) -> Result[DependencyOverlapReport, DependencyOverlapError]
render_function_dependencies_dot(FunctionDependenciesReport) -> String
render_function_dependents_dot(FunctionDependentsReport) -> String
```

These summarize already implemented APIs; they are not declarations added by
the version-preparation commit. Use native as before; module name, dependencies
and supported target are unchanged.

## JSON and CLI migration boundaries

The existing JSON/schema construction for budget reports, data details/data
comparison, model-root paths, whole-graph export and experiments was checked
against the baseline source. Their renderer implementation files and pre-existing
report type declarations are unchanged. The old HTML renderer entry signatures
also remain. New summary, function and independent-query exports use their own
format/schema identities; they do not replace the old report formats. No new
JSON format is introduced by this candidate-preparation commit. This statement
concerns the checked schema construction, not byte-identical output for every
possible input, compiler or environment.

Unknown option-like tokens now fail as parameter errors. Put dash-prefixed input
filenames after `--`, for example `moonsize -- --help`; a single `-` is still a
filename, not stdin. Help is recognized only at the first user argument and
does not read a module. See [argument routing](cli-help.md).

Report output continues to use exclusive creation. Generate a new target rather
than overwriting an input, baseline or existing report; JSON/DOT pairs that are
documented as mutually exclusive cannot be combined. Graph-query strict rejects
detected module-level gaps with3 before output creation, including gaps outside
the selected subgraph. Strict is not available for every independent mode, and3
does not always mean a size budget failure.

## Candidate package evidence and remaining steps

The existing package audit reads identity from the clean source manifest and
strictly compares the actual ZIP manifest. Candidate CI separately requires
source version0.6.0. It preserves the safety/source/resource/license checks,
one package-contained API probe, one extracted native CLI build and three
smoke processes0/0/1. Final SHA, package hash/size/member counts, toolchain and
success/failure are produced by that final CI artifact and completion report,
not prefilled here. No public registry0.6.0 dependency is required or consumed.

Package-contained success is not registry exact-version consumption. Publication,
tag, Release, registry download/consumer checks and any application submission
remain separate, unperformed steps. This task does not automatically continue
into them.

To reproduce results from historical source that also declared0.5.1, record the
full source SHA; that version string alone is ambiguous. Retained, path and
closure facts remain model-relative and do not predict deletion, recompilation
or gzip savings. Independent gzip measurements are not additive. Identical
payload/body bytes do not prove safe merging. Prior Graphviz, PDF and measured
rebuild evidence keeps its historical identity; none is re-performed merely by
changing the candidate version. [Validation and delivery limits](source-delivery.md)
remain applicable.
