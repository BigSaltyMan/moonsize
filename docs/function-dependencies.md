# Function transitive model dependencies

This is a source addition after public **0.5.1**, not a new Mooncakes release.
Example index12 below is a syntax placeholder, not a measurement of your input:

```sh
moonsize app.wasm --dependencies 12 --top 20
moonsize app.wasm --dependencies 12 --dependencies-json new-dependencies.json --top 1
moonsize app.wasm --dependencies 12 --strict
```

The full function index space includes preceding imports. Any valid local or
imported function can be the target; it need not be exported, model-root
reachable or cyclic. The closure includes the target. Only Top, own JSON and
strict may combine; baseline, budgets, HTML and other query/report modes are
rejected before business I/O. JSON requires an explicit dependencies index and
a new, nonempty `.json` path. Existing argument value constraints, unknown
options, `--` and first-argument help routing are unchanged.

| Result | Exit |
| --- | ---: |
| Completed query, including only the target | 0 |
| Input, parsing, index, evidence or output failure | 1 |
| Missing/invalid parameter or mode conflict | 2 |
| Strict refusal of incomplete module graph | 3 |

A valid decimal index outside the real inventory is an input/index error1;
invalid numeric syntax is parameter error2. Empty modules have no valid target.
Strict examines the entire module's `graph_complete`, before output preflight
and creation. The new JSON destination uses existing unified path protection
and native exclusive creation. Existing files are not removed or truncated.
No rollback, new writer or multi-file transaction is introduced.

## Meaning and evidence

This is a directed transitive closure in the **current reference model**:

- Direct is a recorded `call` or `return_call` dependency.
- Reference is `ref.func`, a reference taken without necessarily calling.
- Indirect is a static table-call candidate, not a known runtime target.

The query prepares one inventory, builds once and performs one iterative BFS.
It does not call analyze, retained, SCC, per-target callers or extra opcode
decoding. Existing inventory/build routines retain their own parsing; this is
not a promise that the complete pipeline parses the file only once.

Before BFS, every original edge is checked: caller/callee index bounds, local
body caller, and file offset bounds. Bad evidence outside the target closure
also fails the query. Adjacency preserves all original edges and sorts by
callee, direct/reference/indirect, then file offset. Each function first enters
the head-index queue once. Self-loops, back edges and shared successors cannot
overwrite the target's depth0/null predecessor or duplicate weights.

Depth is the minimum number of model edges, **not runtime stack depth**. Equal
length routes choose the first-discovery edge in deterministic BFS order. A
node stores just that original predecessor, not a full copied path. Node output
sorts by depth, then index; traversal order and display order are separate.

After traversal, all original edges whose caller is in the closure are kept;
their callee must also be present. Full edges sort by caller, offset, callee,
kind. Parallel sites and kinds remain, including self/back/cross edges. They
are distinct from the BFS predecessor tree. Edge counts are not execution
counts, and candidate edges are not call-site counts.

`call_ref` and other unsolved targets keep the original full module diagnostics;
the query never guesses a new edge. Diagnostics can be outside this closure.
`unresolved_count` still counts table call sites without static candidates,
not all diagnostic entries. A complete graph flag does not certify full Wasm
semantics, absence of host dependencies or actual execution.

## Counts and local byte ledgers

Every full function index counts once. A local weight is `total_size`, including
its body length prefix. Imported nodes have `encoded_size: null`. For an import
target, `target_local_encoded_bytes = 0` is **only a local-file accounting
contribution**, not a measured zero-byte body or a claim that host calls are free.
Even import targets perform normal whole-module checks and graph construction.

```text
function_count = local_function_count + imported_function_count
function_count = reachable_function_count + other_function_count
reachable_function_count = reachable_local_count + reachable_imported_count
dependency_function_count = reachable_function_count - 1
local_encoded_bytes = reachable_local_encoded_bytes + other_local_encoded_bytes
reachable_local_encoded_bytes = target_local_encoded_bytes + dependency_local_encoded_bytes
edge_count = direct_edges + reference_edges + indirect_edges
```

Only the target is a valid closure, with zero other dependencies and zero
dependency bytes. Code section headers/count, type, data, name and other
sections are excluded from function weights. Outside this target's closure is
not dead code. Different target closures can overlap, so their byte totals
cannot simply be added. These metrics do not compute exclusive/shared
attribution, retained size, necessary retention or deletion/recompile/gzip
savings, and do not describe runtime heat.

## Reports and related queries

Text shows the target separately, so it does not consume a Top row. Dependency
rows include index, depth, identity, encoded bytes or not-measured status, safe
name and predecessor caller/kind/file offset. The full ledger and graph warning
remain visible when Top hides rows. Top is not a traversal or memory limit.
Complete nodes and edges are held in memory; no constant-memory claim is made.

JSON is independent `moonsize-function-dependencies`, `schema_version: 1`.
It contains target identity, original input SHA-256, all nodes, predecessors,
all closure edges, full counts/ledgers and module diagnostics/warning/scope.
The target predecessor and imported encoded sizes are true nulls. Top never
truncates library results or JSON. Edge records reuse CallEdge serialization;
they contain kinds and offsets, not invented opcode names. To inspect one
opcode, separately run `--locate-offset OFFSET --locate-decode`.

| Query | Question |
| --- | --- |
| [calls](function-calls.md) | Which call instructions are encoded in one local body? |
| [callers](function-callers.md) | Which recorded one-hop instructions refer to this target? |
| [why-index](../README.md#explaining-a-functions-reference-path) | What is one root-to-target model path? |
| [entrypoints](entrypoints.md) | Which functions are reachable from exported entry groups? |
| dependencies | What is the transitive model closure from any chosen function? |

These are separate modes. No source attribution or new cross-build identity is
inferred. Direct, reference and candidate edges all count as model steps.

## API and migration

```moonbit
function_dependencies(Bytes, Int)
  -> Result[FunctionDependenciesReport, FunctionDependenciesError]
describe_function_dependencies_error(FunctionDependenciesError) -> String
render_function_dependencies(FunctionDependenciesReport, Int) -> String
render_function_dependencies_json(FunctionDependenciesReport) -> String
```

New types are FunctionDependencyNode, FunctionDependenciesReport and
FunctionDependenciesError. Nodes reuse FunctionPathNode with depth and optional
CallEdge predecessor. Input errors wrap WasmError; invalid targets retain index
and inventory count; invalid graph evidence retains actual index/offset/reason.
Options adds only dependencies=None and dependencies_json=None. Exhaustive
external Options construction must supply those fields. Existing public
signatures, errors and JSON formats are unchanged. The BFS helper is private.
No dependencies, package version or Mooncakes publication are changed.

## Actual local evidence

The fixed normal input is **130 B**, SHA-256
`bef050f03cb12940e1b153c40de0f2ba54cda02e658719bd87a79d220cc93dc8`.
Its import is index0; six local bodies start at file66/83/90/97/102/105.
Only isolated function5 is exported; the query is explicitly for function1,
without an export/root check. The exact output order and first-discovery edges:

| Index | Depth | Encoded bytes | Predecessor |
| ---: | ---: | ---: | --- |
| 1 | 0 | 17 | null (target) |
| 2 | 1 | 7 | 1→2 direct@67 |
| 3 | 1 | 7 | 1→3 reference@71 |
| 0 | 2 | null (imported) | 2→0 direct@86 |
| 4 | 2 | 5 | 2→4 direct@84 |

The earlier parallel direct@67 wins over direct@69; reference@71 wins over
candidate@76 for the same successor. Both2 and3 reach4, but BFS first discovers
it from2. Direct self@79 and back edge4→1@98 leave the target at depth0/null.
Full evidence has **10** edges (direct8/reference1/indirect1), while the
predecessor tree has **4**. In caller/offset order the full edge positions are
67/69/71/76/79/84/86/91/93/98; none is dropped to obtain the tree.

```text
7 functions = 6 local + 1 import = 5 in closure + 2 other
5 in closure = 4 local + 1 import
4 dependencies = 5 in closure - target1
42 local encoded B = 36 in closure + 6 other
36 in closure B = target17 + dependencies19
10 edges = direct8 + reference1 + indirect1
```

The import0 query is also unit-tested: one node with null encoded size, zero
target/dependency local contribution, and no outgoing model edge. Isolated
local5 has only itself, encoded3 B and zero dependency bytes. Neither result
proves absence of host dependencies or runtime cost.

The gap fixture is **134 B**, SHA-256
`4368f888598462ad6601e8cc1115ea15444d3a5487ad7507acb482489bf63bbe`.
Function6/file108 call_ref is outside target1's closure. Its module diagnostic
is preserved, unresolved_count stays0, and strict returns3 before creating
strict.json. Import0's query also retains the full-module gap in the unit test.

Three filtered new combined tests passed first run3/3. Exactly four analyzer
processes returned **0 / 0 / 3 / 1**: text Top1, full JSON with Top1, strict gap
refusal, existing sentinel refusal. The script checks fixed original edges,
depths, predecessor keys, encoded lengths, bytes, hashes and ledgers; input and
sentinel stay unchanged. No old query/script is run to generate expectations.

Evidence: `_build/function-dependencies-verification/run-eTi67B/` contains both
inputs, four logs, argv/status, `results.json`, `new-dependencies.json` and the
preserved sentinel. `review-5yzvgveg/` alongside it contains the current generated
interface plus a readable HEAD declaration audit. No historical build or ACL
change was needed. Only new tests and required interface/format/native checks,
one release build and four CLI calls ran locally; old suites/CLI, demos, probes,
V8, performance and browser/PDF validation were skipped. CI retains its full
flow and adds only this lightweight four-call script; final-SHA status is
reported separately. Version stays0.5.1; no Mooncakes release is performed.
