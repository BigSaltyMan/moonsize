# Two-function dependency set comparison

Source addition after public **0.5.1**, not a new Mooncakes release. Indices12/47
are syntax placeholders:

```sh
moonsize app.wasm --compare-dependencies 12 47 --top 20
moonsize app.wasm --compare-dependencies 12 47 --compare-dependencies-json new-overlap.json --top 1
moonsize app.wasm --compare-dependencies 12 47 --strict
```

This compares two outgoing closures in **one input**, not two builds. Indices
include preceding imported functions. Any valid local/imported function can be
selected, even if not exported or reachable from model roots. Each closure
includes its start; do not remove a start to reinterpret the word dependency.
An index may therefore be shared, and two different mutually reachable starts
may have equal closures.

Only Top, strict and own JSON combine. Baseline, other queries, budgets, HTML
and other analysis modes are rejected before input/config/output I/O. JSON
requires the explicit pair and a new nonempty `.json` path. Existing decimal
Int bounds, parameter values, help routing, unknown options and `--` are unchanged.

| Result | Exit |
| --- | ---: |
| Completed, including empty groups or identical starts | 0 |
| Input, index, evidence or output failure | 1 |
| Missing/invalid arguments or mode conflict | 2 |
| Strict refusal of incomplete whole-module graph | 3 |

A valid decimal outside the real function space is index error1. Invalid numeric
syntax is parameter error2. Left/right index errors retain role, index and
count; evidence errors wrap the old FunctionDependenciesError, preserving its
actual file position and reason. Outer/read/decode errors retain WasmError.
Empty modules have no valid start.

## Reuse and ordering

One parse_module and path_inventory prepare an identity list; both indices are
checked, then build(data) is called once. Different starts each invoke the
existing dependencies_closure once. Equal starts reuse the first nodes/edges,
so there is only one BFS. Public function_dependencies is not called twice.
There is no analyze, retained, entrypoints, SCC, per-intersection path query or
extra opcode decode. The old dependencies implementation is not rewritten.

Each old helper validates and sorts the graph evidence again. **One graph build
does not mean all preparation happens once**, nor that the complete pipeline
parses only once. Inventory/build retain their existing internal parsing costs.

Left/right node indices are sorted ascending. Two Sets feed one inventory scan
that partitions every complete function index. Names, modules, body bytes and
hashes do not determine membership. The report stores each identity once in
functions, index-ordered, and all groups refer to it by index. Group order is
shared, left_only, right_only, neither, each with ascending indices.

Both helpers' full original-direction edges are retained in their existing
caller/offset/callee/kind order: parallel positions, multiple kinds, self-loops,
back edges and static candidates survive. One edge may appear on both sides;
their counts cannot be added as unique call sites. Reference is ref.func taken,
Indirect is a static candidate, and neither implies a known runtime call.

## Four-set and byte ledgers

For closures A/B (each including its start), full index space U:

```text
shared = A intersect B
left_only = A minus B
right_only = B minus A
neither = U minus (A union B)
```

The four sets are disjoint and cover every valid index. These equations hold
separately for function counts and local encoded bytes:

```text
all = shared + left_only + right_only + neither
left = left_only + shared
right = right_only + shared
union = left_only + right_only + shared
all = union + neither
```

Every group has indices.length=function_count=local_count+imported_count. Side
and union totals include local/imported counts separately. Local weight is
actual total_size including the function body length prefix, once per index.
Imports count as functions but encoded_size stays null; they have no body bytes
in this file, not a measured zero-cost host. Code header/count, data, type, name
and all other sections are outside this byte ledger. No extra left-plus-right
byte total is computed.

Single-side membership is only relative to these two starts: a third export,
start or element root can still reach it. neither is not dead code; shared is
not simultaneous execution, global sharing or entrypoint attribution. There
is no retained, deduplication, split, deletion, recompilation or gzip benefit.

entrypoints analyzes all exported function groups and start/element roots for
its own exclusive/shared definitions. This query does not analyze third-party
roots or borrow those attribution meanings. Use the two reports separately.

## Text, JSON and protection

Text shows safe left/right names, SHA-256, all four summaries, complete ledgers
and module warnings. The first three groups each receive their own Top limit.
Their display copies sort local bytes descending then index ascending, with
imports last and explicitly unmeasured. Neither has only a summary in text.
Rendering does not modify the ascending library/JSON indices.

JSON is `moonsize-dependency-overlap`, schema_version1. It includes the entire
identity list, both full closure index arrays/edge arrays, all four groups and
all count/byte summaries. Top never truncates the library result or JSON and
is not a resource limit. Complete evidence memory grows with the graph.

Whole-module diagnostics are stored once, not duplicated by BFS. A call_ref
outside both closures still makes graph_complete false. unresolved_count keeps
its original table-site meaning, not diagnostic count. Strict checks that
whole-module flag before any output preflight or creation. The new destination
uses existing unified check_outputs, write_output and native exclusive creation,
including alias protection. It never deletes/truncates an existing target.
Message streams and the existing nontransactional output boundary are unchanged.

## Public API and migration

Three new types: DependencyOverlapGroup, DependencyOverlapReport,
DependencyOverlapError. Group.kind uses the four fixed strings above. Errors
are OverlapInputError(WasmError), InvalidOverlapTarget(role,index,count), or
OverlapEvidenceError(FunctionDependenciesError). Four new functions:

```moonbit
compare_function_dependencies(Bytes, Int, Int) -> Result[DependencyOverlapReport, DependencyOverlapError]
describe_dependency_overlap_error(DependencyOverlapError) -> String
render_dependency_overlap(DependencyOverlapReport, Int) -> String
render_dependency_overlap_json(DependencyOverlapReport) -> String
```

Options adds only compare_dependencies: (Int,Int)?=None and
compare_dependencies_json: String?=None. Old report types/signatures, errors,
JSON formats and algorithms remain unchanged. Version/dependencies unchanged;
this is not a newly published package feature.

## Actual targeted verification (2026-10-29, Windows native)

Moon0.1.20260915 (2e1a46d), Node24.18.0, one native release build. Normal input
is134B, SHA-256 `4bc13ffc04a8eefd9122f4f05a7c3ea3f09b138af45c6bbfb5141691152e0f76`.
It contains import0 and locals1..7, with total_size17/7/7/5/3/3/3. Body starts are
file67/84/91/98/103/106/109. Export entry is local5; elements name4 and0.
The two selected starts1/2 are not required to be root-reachable.

Actual query1/2 closures:

```text
left  = [0,1,3,4]
right = [0,2,3,4,7]
```

| Group | Indices | Functions | Local | Imported | Local encoded B |
| --- | --- | ---: | ---: | ---: | ---: |
| shared | 0,3,4 | 3 | 2 | 1 | 12 |
| left_only | 1 | 1 | 1 | 0 | 17 |
| right_only | 2,7 | 2 | 2 | 0 | 10 |
| neither | 5,6 | 2 | 2 | 0 | 6 |

```text
8 functions = local7 + imported1 = 3 + 1 + 2 + 2
left4 = left_only1 + shared3
right5 = right_only2 + shared3
union6 = left_only1 + right_only2 + shared3
all8 = union6 + neither2

45 local B = shared12 + left_only17 + right_only10 + neither6
left29 = left_only17 + shared12
right22 = right_only10 + shared12
union39 = left_only17 + right_only10 + shared12
all45 = union39 + neither6
```

neither contains exported function5, an explicit example of why it is not a
dead-code label. Imported0 is shared with encoded_size null; shared12B are the
local3/4 bodies, not a zero-size host measurement.

Complete left edges (8): `1->3 D68,D70; 1->4 R72,I77; 1->1 D80;
3->4 D92; 3->0 D94; 4->3 D99`. Right edges (5): `2->3 D85; 2->7 D87;
3->4 D92; 3->0 D94; 4->3 D99`. D/R/I mean Direct/Reference/Indirect candidate.
Parallel sites, reference/candidate kinds, self-loop and back edges are retained;
the shared evidence remains on both sides, without adding counts as unique sites.
The script checks fixed tuples and raw opcode bytes independently of product
membership logic. All full indices are unique in the four-set ledger.

Swapping1/2 swaps only the side groups/evidence. Same1/1 has shared[0,1,3,4],
empty single-side groups and neither[2,5,6,7]. Different mutually reachable3/4
have the same closure[0,3,4]. Import0 versus local1 has shared[0], empty left_only,
right_only[1,3,4] and neither[2,5,6,7]. These are new unit cases, not calls to old
public queries. A separately prepared inventory/graph and the existing private
helpers are checked against the fixed expected partition in the second test.
An out-of-range encoded callee8 propagates evidence at file68 with its reason;
left/right bounds and malformed outer input are distinguished.

Gap input is138B, SHA-256
`60f19584f36ac1f2fa5386d317f7fc1b16fc5c6f1b9d26780cad3df1e4ecdcea`.
Function6/file109 call_ref is outside both closures and retained once in module
diagnostics. unresolved_count remains0. Strict CLI returns3 before preflight
and strict.json is absent. Existing JSON sentinel returns1 with unchanged bytes
and no save-success message. Every process checks both input hashes and sentinel.

Exactly3 combined new unit tests passed on their first execution;4 analyzer
processes returned0/0/3/1. Top1 renders one row in each of the first three tables,
while JSON keeps all8 identities, both complete closures/edges and all4 groups,
including neither5/6. The renderer is tested not to mutate library/JSON order;
imports follow local rows in text and remain null in JSON.

Interface/native/format checks, script syntax and diff checks are recorded
separately from tests. Source audit confirms one build and at most two old BFS
calls, with the equal-index reuse branch. No mock or new generic test framework.
Old/full local suites, old CLI, demos, probes, V8, performance and browser/PDF
were not run. Existing CI retains its regressions and adds only this four-call
script; final SHA/CI is confirmed after normal push, separate from local proof.

Evidence: `_build/dependency-overlap-verification/run-ozAmeH/` (raw argv, logs,
input hashes, results.json and complete new-overlap.json). Generated API snapshot
and readable-HEAD audit live in the sibling review directory. These artifacts,
original pictures, AGENTS and all plans are excluded from the commit.

```sh
moon test --target native dependency_overlap_wbtest.mbt
node scripts/test-dependency-overlap.mjs _build/native/release/build/cmd/main/main.exe
```

Each CLI-script run creates a fresh evidence directory without overwriting old
reports. Version0.5.1 and dependencies unchanged; Mooncakes was not published.
