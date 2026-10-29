# Explicit function-to-function model paths

Source addition after public **0.5.1**, not a new Mooncakes release. Indices12/47
in these commands are syntax placeholders:

```sh
moonsize app.wasm --path-between 12 47
moonsize app.wasm --path-between 12 47 --path-between-json new-path.json
moonsize app.wasm --path-between 12 47 --strict
```

FROM and TO use the full function index space, including preceding imports.
Both can be local or imported. The source need not be an export/start/element
root, root-reachable or cyclic. Direction is always FROM -> TO, never swapped.
Only strict and this mode's own JSON combine. Explicit Top, baseline, why,
dependencies, dependents, cycles, budgets, HTML and other modes are rejected
before business I/O. Even explicit `--top 20` is rejected; there is no truncation
or Top field added to this query.

JSON requires explicit FROM/TO and a new nonempty `.json` path. Existing decimal
Int/value rules, first-argument help, unknown options and `--` are unchanged.
A valid integer outside the actual function space is error1, whereas invalid
syntax is parameter error2. FROM errors come from the wrapped dependencies
query; TO bounds use its returned function_count.

| Result | Exit |
| --- | ---: |
| Found, zero steps, or no path recorded within the model | 0 |
| Input, index, evidence/reconstruction or output failure | 1 |
| Missing/invalid arguments or conflicting modes | 2 |
| Strict refusal of an incomplete whole-module graph | 3 |

Strict uses graph_complete for **found, not-found and zero-step results alike**,
before output preflight and creation. JSON uses existing unified check_outputs,
write_output and native exclusive creation, including existing alias protection.
It never removes or truncates a target. No new writer, rollback or multi-file
transaction is introduced.

## Reuse, path selection and failure checks

The public entry calls **function_dependencies(data, FROM) once**. It does not
call build/analyze/retained/SCC/dependents/explain_function, run another BFS, or
decode opcodes. The complete dependencies closure has already been prepared;
this is not a destination-early-stop query or fixed-cost operation. Its work and
memory depend on the graph/closure, and old why limits do not apply.

A private reconstruction helper builds an index-to-prepared-node map. If TO is
absent from that closure, it returns not-found with empty nodes/edges and null
hop_count. The report keeps source identity and target_index; destination name,
import identity and size are not re-read, guessed or fabricated.

For a present TO, a caller/callee/kind/offset tuple Set is built once from the
complete closure edges. The helper follows predecessors from TO toward FROM,
checking each callee equals the current index, the caller exists one depth
closer, and the whole edge tuple is present in the original evidence. The source
must exist at depth0 with no predecessor. A node-count iteration bound and
strictly decreasing depths protect against cycles/broken chains. Any error
returns Err, never a partially successful path. Real edges retain their caller,
callee and file offset; structural failures without an edge use null positions.

After reaching FROM, nodes/edges are reversed into original forward direction.
The inherited dependencies BFS orders adjacency by callee, then Direct /
Reference / Indirect, then offset; equal-hop routes use first discovery. This
does not optimize bytes or prefer an all-Direct path over a shorter model path.

```text
path_nodes.first.index = FROM
path_nodes.last.index = TO
path_nodes.length = path_edges.length + 1
hop_count = path_edges.length = prepared TO depth
path_edges[i].caller = path_nodes[i].index
path_edges[i].callee = path_nodes[i+1].index
```

FROM=TO gives one node, zero edges, hop_count0, even for an import. It does not
prove a nonempty cycle; use cycles witnesses for that. An imported source can
normally only reach itself; a local source can reach an imported destination.
There is no search-limited state: this query does not silently truncate.

## Meaning, output and related queries

Direct means a recorded call/tail-call dependency, Reference means ref.func
reference taken, and Indirect means a static table candidate. These steps are
not an actual execution trace or stack. CallEdge has no opcode, so this feature
does not guess call versus return_call or perform extra decoding. Use an edge's
file offset with the separate locate-decode query for instruction evidence.

Whole-module graph_complete, diagnostics, warning and unresolved_count are
preserved, even for call_ref outside the path. unresolved_count still means
unresolved table sites without static candidates, not all diagnostic entries.
Not-found only means no recorded path **in this direction within this model**.
No path byte sum, retained, frequency, source-change impact, recompilation,
deletion or gzip benefit is calculated. Graph completeness is not full Wasm
semantic or execution certification.

Text shows FROM -> TO, safe names, state, SHA-256, warnings, path node identities,
original edge kinds/file offsets, hop_count and prepared closure count. A
not-found result has an explicit explanation and no empty-chain success table.
Zero-step results explicitly say they do not demonstrate a nonempty cycle.
Imports have encoded_size null, not a measured zero-byte host body.

JSON: `moonsize-function-path-between`, schema_version1. It includes source,
target_index, all ordered path_nodes/path_edges, nullable hop_count, prepared
closure count and complete module diagnostics. It is separate from the original
moonsize-function-path root-query format. Old APIs and JSON remain unchanged.

Typical workflow:

```text
name search -> actual indices
-> dependencies/dependents for outgoing/incoming model sets
-> path-between for one specified relation
-> locate-offset with locate-decode for actual edge instructions
```

why-index remains a model-root-to-target query; why-root still accepts only a
real model root. Neither old entry is relaxed or rewritten by this feature.

## API and migration

Three new types: FunctionPathBetweenStatus (BetweenPathFound/BetweenPathNotFound),
FunctionPathBetweenReport and FunctionPathBetweenError. Errors wrap the original
FunctionDependenciesError, invalid TO/count, or optional actual edge
caller/callee/offset with a reconstruction reason. Four new functions:

```moonbit
function_path_between(Bytes, Int, Int) -> Result[FunctionPathBetweenReport, FunctionPathBetweenError]
describe_function_path_between_error(FunctionPathBetweenError) -> String
render_function_path_between(FunctionPathBetweenReport) -> String
render_function_path_between_json(FunctionPathBetweenReport) -> String
```

Options adds only path_between: (Int, Int)?=None and path_between_json: String?=None.
No old signatures, error enums, output schemas, dependencies or package version
change. This source feature is not republished to Mooncakes.

## Actual local verification (2026-10-29, Windows native)

Moon0.1.20260915 (2e1a46d), Node24.18.0. The controlled130B input has SHA-256
`bef050f03cb12940e1b153c40de0f2ba54cda02e658719bd87a79d220cc93dc8`.
The fixed byte constructor exports only function5 (entry), has no start section,
and element segments reference3 and0. FROM1 is therefore **not a model root**;
this is checked from fixture declarations, without running the old why query.
It may still be reachable from other roots; non-root does not mean unreachable.

The real CLI returned this exact path for1 ->4:

| Position | Function | Identity | Node encoded B | Outgoing selected edge |
| ---: | ---: | --- | ---: | --- |
| 0 | 1 | local | 17 | 1 ->2, Direct, file67 |
| 1 | 2 | local | 7 | 2 ->4, Direct, file84 |
| 2 | 4 | local | 5 | none |

hop_count2, nodes3=edges2+1. Complete prepared closure count5 of7, not just the
three path nodes. Parallel direct67 wins before69; the equal-length route via3
is not chosen because dependencies first discovers2. Raw opcode/immediate
bytes at67/84 are verified independently as[16,2]/[16,4]; exported edges still
have no invented opcode field. The named intermediate contains newline, ESC
and a Chinese character, safely escaped in text/JSON.

New unit cases also verify1 ->0 via2, with imported destination size null;
1 ->3 chooses Reference71 rather than parallel Indirect candidate76. Directional
0 ->1 and1 ->5 are not-found, empty nodes/edges, hop_count null. Same-index0/1
return hop_count0, one node, no edges despite any existing self-loop. Repeated
queries produce deterministic JSON. Corrupted private-helper predecessors,
endpoints, depths, missing evidence/source/caller and cyclic chains all fail;
no second public graph query is added to reconstruction.

The134B gap input has SHA-256
`4368f888598462ad6601e8cc1115ea15444d3a5487ad7507acb482489bf63bbe`.
Function6/file108 call_ref lies outside the path and remains diagnosed;
unresolved_count0 is unchanged. Unit reports retain that incompleteness for
found/not-found/zero-step states; all pass through the same strict runner check.
The strict CLI case is the found1 ->4 case: exit3, strict.json absent. Existing
sentinel case returns1 without changing original bytes or printing save success.
Input hashes remain unchanged after every process.

Three new combined unit tests passed on first execution; four real analyzer
calls returned0/0/3/1. An initial native type check found only the new tests'
Debug-dependent status assertion, corrected to pattern assertions without adding
a public trait. No old failure or old regression was run locally. Interface,
format/native checks, one release build and new script syntax checks are recorded
separately from tests. Existing CI retains all old checks and adds only the new
four-call script; final-SHA success is confirmed after normal push.

Evidence: `_build/function-path-between-verification/run-YATz7z/` contains argv,
logs, input hashes, results.json, full new-path.json, original inputs and intact
sentinel. API generation/audit is saved in its sibling review directory. These
build artifacts are local evidence, not committed package contents.

```sh
moon test --target native function_path_between_wbtest.mbt
node scripts/test-function-path-between.mjs _build/native/release/build/cmd/main/main.exe
```

Each script run uses a new directory. Local old/full tests, old CLI, demos,
probes, V8, performance and browser/PDF were not run. Original pictures, AGENTS,
plans and evidence remain outside the commit. Version0.5.1; no package publish.
