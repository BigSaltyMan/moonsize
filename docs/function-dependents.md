# Function transitive model referrers

Source addition after public **0.5.1**; not a new Mooncakes release. Index12 in
these syntax examples is a placeholder:

```sh
moonsize app.wasm --dependents 12 --top 20
moonsize app.wasm --dependents 12 --dependents-json new-dependents.json --top 1
moonsize app.wasm --dependents 0 --strict
```

Any valid full function index, including preceding imports, may be the target.
The function need not be exported, reachable from a model root or part of a
cycle. The reverse closure includes the target itself. Sources are not filtered
by root reachability. Only Top, strict and the mode's own JSON option combine.
Other modes, baseline, budgets and HTML are rejected before input I/O.

`--dependents-json` requires an explicit `--dependents INDEX` and a nonempty
new `.json` path. Existing numeric/value rules, unknown-option handling, `--`
and first-argument help dispatch remain unchanged.

| Result | Exit |
| --- | ---: |
| Completed, including target-only results | 0 |
| Input, parsing, target index, evidence or output failure | 1 |
| Missing/invalid parameter or conflicting modes | 2 |
| Strict refusal of incomplete whole-module graph | 3 |

A syntactically valid decimal outside the actual index space is error1; invalid
numeric syntax is error2. An empty module has no valid target. Strict checks
whole-module completeness **before output preflight or creation**. JSON uses
the existing unified target checks and native exclusive creation. Existing
files are never deleted or truncated. The existing nontransactional output
boundary is unchanged.

## Direction and evidence

| Query | Question answered in the current model |
| --- | --- |
| `--callers INDEX` | Which one-hop incoming instruction references are recorded? |
| `--dependents INDEX` | Which functions can reach this target, over any number of model edges? |
| `--dependencies INDEX` | Which functions can this target reach? |
| `--why-index INDEX` | What is one path from model roots to this target? |

Direct edges represent calls/tail calls, Reference means a reference taken by
`ref.func`, and Indirect means a static candidate. They are not all known
runtime calls. This query is not source-change impact analysis.

One inventory and one `build(data)` are reused, followed by one iterative
reverse BFS. There is no analyze, retained, SCC, per-function query loop or new
opcode decoding. Existing inventory/build routines perform their own parsing;
this is not a claim that the complete pipeline parses the file only once.

All original edges are checked before traversal: caller/callee indices in the
inventory, a caller with a local body, and an instruction file offset within
the input. Invalid evidence outside the closure also fails.

Incoming adjacency is keyed by **callee**, retaining original CallEdge records.
Each list sorts by caller, Direct/Reference/Indirect, then offset. The queue uses
a head index and each node enters only on first discovery. For original edge
`u -> v`, first discovery of u records `depth[u] = depth[v] + 1` and
`next_edge[u] = u -> v`. The target remains depth0/next_edge null despite
self-loops and back edges. Equal-length routes use deterministic first discovery.

Depth is the minimum number of **model edges to the target**, not stack depth.
Every non-target next_edge has the node as caller and a callee one depth closer
to the target. Following exactly depth such edges reaches the target. Nodes
store one edge each, not copied full paths. Output nodes sort by depth/index.

The complete internal edge list keeps **all original edges whose callee is in
the reverse closure**; each caller must also be present. A closure member may
point outward to another function: that outgoing edge is excluded. Complete
edges sort by caller/offset/callee/kind and retain parallel positions, different
kinds, self-loops, back and cross edges. The next-edge tree has nodes-minus-one
edges and does not replace complete evidence. Edges always keep their original
caller-to-callee direction, even though traversal follows them backward.

Full-module diagnostics, graph warning and graph_complete are retained,
including unsupported call_ref sites outside the source closure. Unknown targets
are never guessed. unresolved_count still means table call sites with no static
candidate, not diagnostic count. Even graph_complete=true does not certify
complete Wasm semantics or actual execution.

## Accounting and rendering

All counts include the target, except explicitly named dependents:

```text
function_count = reaching_function_count + other_function_count
reaching_function_count = reaching_local_count + reaching_imported_count
dependent_function_count = reaching_function_count - 1
local_encoded_bytes = reaching_local_encoded_bytes + other_local_encoded_bytes
reaching_local_encoded_bytes = target_local_encoded_bytes + dependent_local_encoded_bytes
edge_count = direct_edges + reference_edges + indirect_edges
```

Local weight is total_size, including the function body length prefix, counted
once per full index. Code header/count, data, type, name and other sections are
excluded. An imported node's encoded_size remains null. For an imported target,
its local-file accounting contribution is zero; this is not a measured host
body size or a claim that host calls cost nothing. An import target can have
local referrers. Target-only results have zero dependent functions and bytes.

Other functions means no modeled path to this target, not dead code. Sources
can be unreachable from model roots. Different targets' source closures can
overlap, so their bytes cannot be summed as module size. These bytes predict
neither execution, necessary retention, source-change impact nor deletion,
recompilation or gzip savings.

Text shows the target separately from Top, complete ledgers and diagnostics,
then at most Top other source rows. Names/control characters are safely escaped.
Rows show index, depth to target, local/imported identity, measured encoding
size, name and next callee/kind/file offset. A target-only result says that the
current model records no other function's path to it, not that it is unused.

JSON format is `moonsize-function-dependents`, schema_version1. It keeps target,
all nodes/next_edge, all original-direction edges, complete ledgers and module
diagnostics. Top never truncates JSON, traversal cost or evidence memory.
Unknown values remain null; raw function bodies and predicted savings are not
exported. For actual opcodes, inspect the file offsets separately with the
existing offset query; this mode performs no extra instruction decoding.

## Public API and migration

Three new types: FunctionDependentNode (node: FunctionPathNode, depth: Int,
next_edge: CallEdge?), FunctionDependentsReport and FunctionDependentsError.
The error variants wrap WasmError, an invalid target/count, or actual evidence
index/file offset/reason. Four new functions:

```moonbit
function_dependents(Bytes, Int) -> Result[FunctionDependentsReport, FunctionDependentsError]
describe_function_dependents_error(FunctionDependentsError) -> String
render_function_dependents(FunctionDependentsReport, Int) -> String
render_function_dependents_json(FunctionDependentsReport) -> String
```

Options adds only dependents=None and dependents_json=None. Existing public
signatures, dependencies query/format, errors and other JSON remain unchanged.
The node intentionally uses next_edge, not predecessor: this edge points from
the current source toward the queried target. Library parsing/rendering do no
file I/O. Version and dependencies are unchanged; no package is published.

## Actual targeted verification (2026-10-29, Windows native)

Moon 0.1.20260915 (2e1a46d), Node24.18.0, native release. The test reuses the
existing small byte fixture construction, without running old query scripts,
V8 or a compiler probe. Only isolated local5 is exported; the chosen target2
and sources do not require model-root reachability.

Normal input is **130 B**, SHA-256:
`bef050f03cb12940e1b153c40de0f2ba54cda02e658719bd87a79d220cc93dc8`.
Body starts are file66/83/90/97/102/105; local sizes are17/7/7/5/3/3.

Query target2, printed ordering and original next edges:

| Index | Depth to target | Encoded B | next_edge (caller -> callee, kind, file offset) |
| ---: | ---: | ---: | --- |
| 2 | 0 | 7 | null |
| 1 | 1 | 17 | 1 -> 2, Direct, 67 |
| 3 | 1 | 7 | 3 -> 2, Direct, 93 |
| 4 | 2 | 5 | 4 -> 1, Direct, 98 |

The three next edges strictly lower depth. Complete evidence has **9 edges**:
`1->2 D67, D69; 1->3 R71, I76; 1->1 D79; 2->4 D84; 3->4 D91;
3->2 D93; 4->1 D98`. D/R/I mean Direct/Reference/Indirect, not execution counts.
Raw bytes at file86 are `[16,0]`: the real target2 -> import0 outgoing call.
Import0 is not in this reverse closure, and that edge is excluded. This tests
the direction-specific filter, rather than copying the forward caller filter.

```text
7 functions = local6 + import1 = reaching4 + other3
reaching4 = local4 + import0; dependents3 = 4 - target1
42 local encoded B = reaching36 + other6
36 reaching local B = target7 + dependents29
9 complete internal edges = Direct7 + Reference1 + Indirect1
3 next-edge tree edges = 4 nodes - 1
```

The unit test also queries imported target0: nodes0/2/1/3/4 at depths0/1/2/2/3,
all10 original edges, local closure36B, target contribution0 and dependent36B.
The imported target's encoded_size stays null. Isolated target5 has only itself,
3 local B, zero other sources/bytes/edges. A self-loop target remains depth0/null.
For target3, parallel Reference71 wins before candidate76; reversing helper input
edges preserves nodes, depth, next edges and full edges. Next chains and full
ledgers are checked, including invalid whole-graph evidence outside the closure.

Gap input is **134 B**, SHA-256:
`4368f888598462ad6601e8cc1115ea15444d3a5487ad7507acb482489bf63bbe`.
Function6/file108 call_ref is outside target2's source closure, but remains a
module diagnostic. unresolved_count is still0. Strict returns3 before output
checks/create; strict.json is absent. Existing sentinel returns1 and is intact.
Both inputs retain their hashes after every process.

Exactly **3 new combined unit tests passed on the first run** and **4 analyzer
processes returned0/0/3/1**. Top1 text has one non-target source row while JSON
keeps4nodes/9edges. Interface generation, format/native check, one release build,
script syntax and diff checks are separate from running tests. Local old/full
suites, old CLI, demos, probes, V8, performance and browser/PDF were not run.
Existing CI retains old checks and only adds this four-process script. Final
SHA/CI is verified after normal push; this historical local record is not itself
remote CI proof. Pictures, AGENTS, plans and build evidence are not committed.

Local evidence: `_build/function-dependents-verification/run-dR6VSE/`, including
processes.json, case0..3 logs, results.json, unchanged sentinel and complete
new-dependents.json. API snapshot/audit is in the sibling review directory.
Reproduce only these new tests/process cases:

```sh
moon test --target native function_dependents_wbtest.mbt
node scripts/test-function-dependents.mjs _build/native/release/build/cmd/main/main.exe
```

The script always creates a new evidence directory and never overwrites older
reports. Test data and scripts are deterministic; paths remain per-run records.

## Explicit pair path (source addition after public 0.5.1)

`--path-between FROM TO` reconstructs one deterministic shortest path from one
complete dependencies query, allowing non-root/imported endpoints. It does not
run another graph search or relax why-root. Not-found has empty paths/null hops;
same-index has zero hops. No Top; only own JSON and strict combine. Workflow:
name search -> dependencies/dependents sets -> explicit pair path -> locate-decode
for actual instruction offsets. [Contract and real evidence](function-path-between.md).
