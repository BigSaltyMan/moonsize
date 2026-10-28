# Function reference cycle components

This is a source addition after public **0.5.1**, not a new Mooncakes release.

```sh
moonsize app.wasm --cycles --top 10
moonsize app.wasm --cycles-json new-cycles.json --top 1
moonsize app.wasm --cycles --strict
```

`--cycles-json` implies cycles. This independent query permits only input, own
JSON, Top and strict. Other queries, baseline, HTML, compression, budgets and
ordinary analysis flags are rejected before business I/O. Unknown-option, `--`
and first-argument help routing remain unchanged. A new `.json` destination is
required; unified preflight and native exclusive creation protect existing
files. Multi-file transactions and rollback are not added.

| Result | Exit |
| --- | ---: |
| Success, including no cyclic components | 0 |
| Input, graph evidence or output error | 1 |
| Parameter or mode combination error | 2 |
| Strict refusal of incomplete graph | 3 |

Strict checks run before output preflight and creation. An incomplete graph is
diagnosed even if no shown component contains the diagnostic site. Non-strict
reports preserve complete module diagnostics and the existing warning.

## What a component means

A strongly connected component (SCC) is a maximal group of nodes where each
can reach every other through directed model edges. This query outputs groups
of at least two functions, plus singleton groups with self-edges. Singletons
without self-edges and one-way chains are not cyclic components. All inventory
functions participate, including imports and unreachable local functions;
model roots do not filter the query or create fictitious body edges.

All three existing edge kinds participate:

| Kind | Evidence |
| --- | --- |
| direct | `call` or `return_call` |
| reference | reference taken by `ref.func` |
| indirect | a static table-call candidate |

Reference and candidate cycles **are not runtime recursion**. Even a direct-only
cycle does not prove those instructions execute. `call_ref`/`return_call_ref`
remain module-level diagnostics without guessed targets. No cyclic components
does not prove absence of recursion or host callbacks, including when
`graph_complete` is true. That field means no detected gap within the current
model, not full semantic certification.

## Algorithm, evidence and ordering

The entry prepares one function inventory and calls `build(data)` once. It
does not call `analyze`, retained, callers, per-node BFS or simple-cycle
enumeration. Basic parsing is reused inside existing build/inventory routines;
this does not claim the whole file is parsed only once.

It validates edge indices, requires a local body caller and checks instruction
offsets against the input, then derives deduplicated forward/reverse topology
from the original edges. Both Kosaraju traversals use explicit stacks. Every
original internal `CallEdge` is bucketed after SCC assignment, keeping caller,
callee, kind and file offset. Parallel positions, kinds and candidate targets
remain distinct evidence, even when their topology was deduplicated. There is
no second opcode decode to enrich the result. Indirect JSON edges carry
`candidate: true`.

Members sort by full function index. `component_id` is the minimum member
index, useful only within this input. Components sort by local encoded bytes
descending, then component ID ascending. Internal edges sort by caller, file
offset, callee, then direct/reference/indirect. Changing input edge iteration
order does not change the ordered result. SCC traversal is iterative; sorting,
graph construction and full evidence storage retain their own costs. Top is
only a text display limit, not a resource limit.

## Counts and bytes

Each local weight is `FunctionStat.total_size`: body length prefix plus body.
Imports have `encoded_size: null`, not a measured zero-byte body. Their runtime
or host cost is not measured. The report preserves these ledgers:

```text
function_count = imported_function_count + local_function_count
function_count = cyclic_function_count + non_cyclic_function_count
cyclic_function_count = sum(component.node_count)
local_encoded_bytes = cyclic_local_encoded_bytes + other_local_encoded_bytes
cyclic_local_encoded_bytes = sum(component.local_encoded_bytes)
internal_edge_count = direct_edges + reference_edges + indirect_edges
```

Disjoint component weights may be added. They are not retained size, complete
code section size or deletion/recompile/gzip savings. Code section headers,
function count and other sections are excluded. Edge counts are not execution
counts; candidate edge counts are not call-site counts. `unresolved_count`
retains its original meaning: table call sites with no static candidates, not
the number of module diagnostics.

## Reports and API migration

Text begins with the graph warning, scope and full totals, then component
summaries and every member of each displayed component. Names are escaped for
the terminal. Top limits only the number of components. JSON is complete:
`format: "moonsize-function-cycles"`, `schema_version: 1`; it contains all
components, members, internal edges, module diagnostics, warning and scope.
No runtime depth prediction or cross-build identity is produced.

```moonbit
function_cycles(Bytes) -> Result[FunctionCyclesReport, FunctionCyclesError]
describe_function_cycles_error(FunctionCyclesError) -> String
render_function_cycles(FunctionCyclesReport, Int) -> String
render_function_cycles_json(FunctionCyclesReport) -> String
```

New types are `FunctionCycleComponent`, `FunctionCyclesReport` and
`FunctionCyclesError`. Input errors wrap `WasmError`; invalid evidence retains
the actual function index, file offset and reason. Options adds `cycles: false`
and `cycles_json: None`. External full Options construction must provide these
fields; defaults remain available. No existing types, signatures, graph edge
semantics, path/callers JSON or WasmError variants are changed. The SCC helper
is private.

Use [why-index](../README.md#explaining-a-functions-reference-path) for one root-to-target model path,
[callers](function-callers.md) for all recorded incoming one-hop instructions,
and [entrypoints](entrypoints.md) for export-based reachable sets. These are
separate queries; cycles include functions outside those exported sets.

## Actual local evidence

The 128 B fixture has one import and seven local definitions. SHA-256:
`4f874186738dda2f384fc38b841fe59b9c208937fadc96754b4286d9948615c7`.
Local body starts are file 68/75/86/91/96/99/105. Only function 4 is exported;
function 1 is neither an export nor an element target, so its retained self-loop
also proves this query did not filter by root reachability.

| Component ID | Members | Encoded bytes | Direct | Reference | Indirect |
| ---: | --- | ---: | ---: | ---: | ---: |
| 2 | 2, 3 | 16 | 1 | 1 | 1 |
| 1 | 1 | 7 | 2 | 0 | 0 |
| 6 | 6 | 6 | 0 | 1 | 0 |

The first component's evidence is 2→3 reference at file 76, 2→3 indirect
candidate at file 81, and 3→2 direct at file 87. Component 1 keeps both
direct self instructions at file 69 and 71. Component 6 keeps the reference
self-edge at file 100. One-way 4→5 and isolated 7 do not create components.

```text
8 functions = 1 import + 7 local = 4 cyclic + 4 non-cyclic
40 local encoded B = 29 cyclic B + 11 other B
29 cyclic B = 16 + 7 + 6
4 cyclic functions = 2 + 1 + 1
6 internal edges = 3 direct + 2 reference + 1 indirect candidate
```

The strict fixture is 132 B, SHA-256
`82845683c910013b94d2b39ace7a770702d3dae4167d486e67fb54b8adb0503d`.
Its `call_ref` at function 7/file 108 is outside all cyclic components.
The full diagnostic is retained; no target edge is guessed. `unresolved_count`
is still zero. Strict returns 3 before creation and `strict.json` stays absent.

Three filtered combined tests passed first run (3/3) after a type-check-only
reserved-identifier warning was corrected. Exactly four analyzer processes
returned **0 / 0 / 3 / 1**: text Top 1, full JSON Top 1, strict refusal, existing
sentinel refusal. Fixed original edges/bytes validate indices, kinds, offsets,
weights, hashes and ledgers. Inputs and existing output stayed unchanged.

Evidence: `_build/function-cycles-verification/run-Lxw96w/` contains both
inputs, four logs, argv/status records, `results.json`, `new-cycles.json` and
the sentinel. API snapshots/diff are in `review-w54q02yr/` alongside that run.
Only new tests, necessary interface/format/native checks and one release build
ran locally; no old/full suite, old CLI/demos, probes, V8 matrix, performance or
browser/PDF work. Existing Linux CI keeps its full flow with only this four-call
script added; exact-SHA CI status is reported separately. Version stays 0.5.1,
dependencies are unchanged, and no Mooncakes publication is performed.

## Optional closed evidence paths (source addition after public 0.5.1)

```sh
moonsize app.wasm --cycles --cycle-witness --top 10
moonsize app.wasm --cycles-json new-witnesses.json --cycle-witness --top 1
moonsize app.wasm --cycles --cycle-witness --strict
```

`--cycle-witness` must accompany cycles or cycles-json; alone it is an argument
error before input is read. Its default is false. The old query, computation
and `moonsize-function-cycles` output remain available without the modifier.
It uses the existing cycles_json destination, preflight and native exclusive
creation; there is no new writer or output path. Success, input/path/output
failure, parameter failure and strict refusal retain exit codes 0/1/2/3.

For every component, the witness starts and ends at component_id (the minimum
function index). Selection is fixed:

1. If the start has self-edges, choose direct before reference before indirect,
   then the lowest file offset.
2. Otherwise choose the first outgoing edge by callee index, kind priority and
   file offset, in that order.
3. From that successor run one iterative BFS inside the component back to the
   start. Adjacency uses the same ordering; a head-index queue retains full
   predecessor edges. Iterative reverse reconstruction closes the path.

Only one BFS at most runs per component. The new entry calls function_cycles
once; it does not repeat parsing/build/SCC, callers queries or opcode decoding.
Local maps scale with component members/evidence, not the module's maximum
function index. Invalid membership, crossing edges, absent return paths and
broken chains fail explicitly; they do not trigger a rebuild or guessed path.

This is one representative closed model path. It may visit a subset of members,
may use a root self-loop even in a larger component, and is not a full-member
tour, unique cycle or globally shortest cycle. Reference and indirect candidate
steps do not establish actual recursion. No new byte sum is attached to a
witness: the start repeats and some members may be absent. Original component
counts and byte totals remain authoritative.

Every witness retains component_id, start_index, ordered nodes and original
CallEdge records, edge_count and three kind counts. The invariants are:

```text
witnesses.length = cycles.component_count
edge_count = edges.length >= 1
nodes.length = edge_count + 1
nodes.first = nodes.last = start_index = component_id
edges[i].caller = nodes[i]
edges[i].callee = nodes[i+1]
edge_count = direct_edges + reference_edges + indirect_edges
```

All nodes belong to the component, no interior node repeats, and every complete
edge key (caller, callee, kind, offset) occurs in original internal_edges. All
parallel evidence stays in cycles; choosing one does not remove the others.
Witnesses follow the unchanged component order. Text retains the old summary
and graph warning, then adds CLOSED MODEL WITNESS with index chains, safe names
and per-edge kind/file offset. Indirect steps say candidate. Top limits the
number of shown components, never a shown witness's steps or complete JSON.

The opt-in format is `moonsize-function-cycle-witnesses`, schema_version1. Its
cycles field is the **complete original JSON object**, not a string or partial
copy; witnesses and scope are separate fields. The old JSON builder is shared
privately, without stringify/parse. Complete module diagnostics, graph warning
and unresolved_count keep their meanings, including gaps outside the path.
Strict uses nested cycles.graph_complete and refuses before preflight/creation.

To see a step's actual opcode, separately run `--locate-offset OFFSET
--locate-decode` with its original file offset. This query does not decode or
infer opcode names and cannot combine with the separate location mode.

### Witness API and migration

```moonbit
function_cycle_witnesses(Bytes)
  -> Result[FunctionCycleWitnessReport, FunctionCycleWitnessError]
describe_function_cycle_witness_error(FunctionCycleWitnessError) -> String
render_function_cycle_witnesses(FunctionCycleWitnessReport, Int) -> String
render_function_cycle_witnesses_json(FunctionCycleWitnessReport) -> String
```

New types: FunctionCycleWitness, FunctionCycleWitnessReport and
FunctionCycleWitnessError. The error wraps the original cycles error or records
a component ID, optional actual edge offset and reason. When no edge exists,
the offset is null/absent rather than a fictional position. Options adds only
cycle_witness=false; full external record construction needs that field. Old
cycles/error types, public signatures and JSON fields are unchanged. This is
source-only after public0.5.1; no package publication is performed.

### Actual witness evidence

The unchanged 128 B cycles fixture has SHA-256
4f874186738dda2f384fc38b841fe59b9c208937fadc96754b4286d9948615c7.
The chosen paths are:

| Component | Nodes | Original kind and file offset | Witness / component edges |
| ---: | --- | --- | ---: |
| 2 | 2 → 3 → 2 | reference76, direct87 | 2 / 3 |
| 1 | 1 → 1 | direct69 | 1 / 2 |
| 6 | 6 → 6 | reference100 | 1 / 1 |

Three witnesses correspond to three components. Their node lengths are3/2/2
and edge lengths2/1/1: each has one repeated endpoint and no repeated interior.
Total witness edges4 do not replace the original six internal edges. The
parallel candidate at file81 and second direct self-edge at71 remain in the
nested cycles report. Original local byte accounting is still40=29+11 with
component bytes16/7/6; no witness-byte metric is introduced.

New unit evidence also uses a four-member component with root10: the selected
path10→20→30→10 uses direct99, indirect50 and reference60, excluding member40.
The alternative10→40→10 is shorter, but the documented successor rule chooses20.
Adding root self-edges selects direct50 over direct80/reference10/indirect0 and
returns10→10 while the original four members and eleven edges remain intact.
A two-node sparse-index case uses1000000/2000000 without a max-index array;
this is a functional check, not a performance measurement.

The unchanged 132 B gap fixture has SHA-256
82845683c910013b94d2b39ace7a770702d3dae4167d486e67fb54b8adb0503d.
Function7/file108 call_ref remains a module diagnostic outside the components.
Strict returns3 and strict.json is not created; unresolved_count remains0.
Existing sentinel refusal returns1 with original bytes unchanged.

Three new combined tests passed first run3/3. Exactly four real CLI invocations
returned0/0/3/1: Top1 witness text, complete witness JSON with Top1, strict refusal,
and existing-target refusal. Original edges, kinds, offsets, hashes and closure
were checked against fixed fixture bytes. Input and existing output stayed
unchanged. Evidence is in
_build/function-cycle-witness-verification/run-vkCpu6/ (four logs, argv/status,
results.json, new-witnesses.json, both inputs and sentinel). Interface evidence
is in review-xupx2hkm/: current moon-info output and HEAD public source-declaration
audit. The historical generated interface snapshot was OS-permission denied,
including an escalated read; no ACLs or old build/test were changed to read it.

Only the three new tests, four CLI calls, necessary info/format/native checks
and one release build ran locally. No old suites/scripts, probes, V8 matrix,
performance or browser/PDF work. CI retains its existing flow and adds only this
four-call script. Final exact-SHA CI is reported separately. Version0.5.1 and
dependencies remain unchanged; pictures, AGENTS, plans and build evidence stay
outside the commit.
