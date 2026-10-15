# moonsize

```sh
moon add BigSaltyMan/moonsize
```

A size analyzer for WebAssembly, built for MoonBit's output. It reads a `.wasm`
file, measures every section, attributes the code section to named functions,
follows the call graph, and reports what could be deleted.

The analysis model follows [Twiggy](https://github.com/rustwasm/twiggy): sizes
are attributed to individual functions, functions are grouped by package, and
reachability from the module's roots decides what is really used.

Chinese version: [README.zh.md](README.zh.md).

## Building

```sh
moon build --release
./_build/native/release/build/cmd/main/main.exe app.wasm
```

The module declares `supported_targets = "+native"`, so a project that depends on
it builds with `--target native` as well.

## Usage

```
usage: moonsize <file.wasm> [--top <n>] [--retained] [--dead-code]
                 [--compress] [--strict] [--call-graph <path>] [--html <path>]
                 [--max-size <size>] [--baseline <path.wasm>]

Report the section table of a WebAssembly binary, rank its heaviest
functions, roll the bytes up by module, and follow the call graph to
find what can be deleted.

  --top <n>            how many functions to rank (default 10)
  --retained           what deleting each function would free
  --dead-code          functions no root can reach
  --compress           what the file and each section cost gzip-compressed
  --strict             refuse to report when the call graph is incomplete,
                       instead of reporting it with a warning
  --call-graph <path>  write the call graph as .dot or .json
  --html <path>        write the charts as a self-contained HTML report
  --max-size <size>    fail with exit code 3 above this size, where size is
                       bytes or a KB/MB/GB count such as 10KB or 1.5MB
  --baseline <path>    compare against another module and print the change;
                       --max-size then bounds the growth, not the file

Exit codes: 0 ok, 1 unreadable input, 2 bad command line, 3 over budget.
```

Without flags it prints the section table, the heaviest functions and the
per-package roll-up. `--retained` and `--dead-code` add their sections and can
be combined. `--call-graph` and `--html` each write a file instead of printing
a report, so they are used on their own:

```sh
moonsize app.wasm --retained --dead-code        # the full text report
moonsize app.wasm --html report.html            # charts, opens in a browser
moonsize app.wasm --call-graph graph.dot        # for Graphviz
```

## Using the library

The parsing, the analysis and every report are ordinary packages in this module,
so a program can take the numbers instead of the text. `moon add
BigSaltyMan/moonsize` and import it; `Options::default` is the way in, because
`Options` is read-only and no other package may write one.

```moonbit
fn main {
  let bytes : Bytes = read("app.wasm")
  match @moonsize.parse_module(bytes) {
    Ok(parsed) =>
      match @moonsize.analyze(bytes, parsed) {
        Ok(analysis) => {
          let options = @moonsize.Options::default("app.wasm")
          // What the five heaviest functions cost, as text or as numbers:
          // `analysis.stats` and `analysis.retained` are there to be read.
          println(@moonsize.render_top_functions(analysis.stats, analysis.data.length(), 5))
          println(@moonsize.render_graph_warning(analysis.graph))
          println(@moonsize.render_dead_code(analysis, 5))
          println(@moonsize.render_retained(analysis, 5))
          println(@moonsize.render_html(analysis, options.path))
        }
        Err(error) => println(@moonsize.describe_error(error))
      }
    Err(error) => println(@moonsize.describe_error(error))
  }
}
```

The library does no I/O, so reading the file and choosing an exit code stay with
the caller. `supported_targets = "+native"` applies to a program that depends on
this module too: build it with `--target native`.

## Analysis

Everything below is built on one idea: a function's bytes only matter if
something can call it.

### Symbol names

Attribution starts with the names in the binary's name section, and MoonBit does
not publish how it mangles them, so the rules here were read back from the name
section of real builds (`moonc` 0.1.20260920, the `wasm` backend):

- a symbol is `_M0<kind>` and then a path: `F` a function, `M` a method, `I` a
  trait implementation;
- the package is `B` for the builtin package, `C` for `moonbitlang/core`, or `P`
  and an index — which runs into the first component's own length, so `P55probe`
  is index `5` followed by `5probe`;
- a component is its length and then its name, and the length counts the *mangled*
  name;
- anything that cannot appear in an identifier is escaped as `_` and the byte in
  hex, and a literal underscore is doubled: `to__string_2einner` is
  `to_string.inner`, `_24default__impl` is `$default_impl`, and a non-ASCII
  character is escaped one byte at a time, so `中` is `_e4_b8_ad`;
- a generic instantiation carries `G...E` with one code per argument, where a
  builtin is a single letter, a tuple is `U...E`, and a named type is `R` and a
  path;
- a closure is either an environment named `__moonbit_<fn>` or a body carrying
  `C<id>l<line>`, the id of the closure and the line it was written on;
- a trait implementation names two packages, its type's and its trait's.

The reports print the path through `display_name`. `demangle_full` is the fuller
decoder, for callers that want escapes resolved, arguments spelled out and
closures marked. Both are display aids rather than a codec: when one cannot
decode a symbol exactly it returns it untouched, because a report that invents a
name is worse than one that shows a raw symbol. The known limits are where that
happens — a generic argument whose type code is not one of the letters a build
produced (`Int`, `Double`, `String`, `Bool`, `Char`, `Byte`, `Float`, `Int64`,
`UInt64`, `Unit`) is left undecoded rather than guessed, a named argument is only
decoded as the last one in its list because its path has no terminator to
separate it from what follows, and a symbol over 4096 bytes is refused outright
so a forged name cannot drive the walk into a deep recursion.

### The call graph

The decoder walks every function body instruction by instruction — the full MVP
instruction set, the `0xFC` saturating and bulk-memory opcodes, the exception
handling and tail-call opcodes MoonBit emits, and the `0xFB` garbage-collection
opcodes its `wasm-gc` backend uses. Each body contributes:

- `call x` and `return_call x` — precise edges to `x`;
- `ref.func x` — a reference, which counts as reachable because the function may
  run later as a closure;
- `call_indirect` and `return_call_indirect` — *conservative* edges to static
  element candidates in the selected table;
- `call_ref` and `return_call_ref` — recognised call sites with an
  `UnmodeledReferenceCall` diagnostic. Target analysis is not implemented,
  including when `ref.func` immediately precedes the call. No target is guessed.

Static candidates have limits. A module may fill a table at run time
— `table.set`, `table.init`, or the host handing it functions — and a table with
**no element segment at all** then says nothing about who sits in it. Those
indirect call sites, including indirect tail calls, contribute no edges and
produce incomplete-graph diagnostics. Dead-code and retained-size results may
then be inaccurate. The report says so above everything else:

```
WARNING: the call graph has 1 analysis gap.
  function 0, offset 42: call_ref: reference-call target analysis is not implemented.

Dead-code and retained-size results may be inaccurate; do not use them as proof that a function can be removed.
```

`--dead-code` and `--retained` repeat it under their titles, and `--strict` turns
these recognised incomplete cases into a refusal — no report, exit code 3.

`call_ref` and `return_call_ref` make the graph incomplete even if every table
call has candidates. `analyze` still returns `Ok(Analysis)`: a modelling gap is
distinct from malformed input. Diagnostics retain their category, full caller
index, file offset, actual opcode, type index and optional table index.

`graph_complete` means no gaps were detected within the current scope:
`analysis.graph.diagnostics` is empty. Dynamic table writes, host-provided
contents and all Wasm call mechanisms are not fully modelled. A successful
`--strict` run is not a completeness certificate.

A function is a **root** if the outside world can reach it: it is exported, it is
the start function, or it is referenced by an element segment. Reachability and
retained sizes describe paths in the current graph model.

### Parser bounds and Reader API

`Reader::read_u32_leb()` returns `Result[UInt, WasmError]` across the full
`0..4294967295` range. Non-shortest encodings remain accepted within five bytes;
illegal fifth-byte high bits or continuation produce `LebOverflow(offset)`.
Lengths, counts, indices and integer instruction operands pass through one
checked internal conversion and currently support `0..2147483647`. Larger
valid u32 encodings produce `ValueOutOfRange(offset, value)`, an implementation
limit rather than a claim that the unsigned encoding is invalid Wasm.

`Reader::new(data)` still covers the whole buffer. The new
`Reader::new_range(data, start, length)` returns `Result[Reader, WasmError]`
and restricts reads to `[start, start + length)`. Negative or out-of-buffer
requests return `InvalidReadRange(offset, length, start, end)`.
`seek(offset)` now returns `Result[Unit, WasmError]`; handle that result when
migrating callers. Seeking to the end is allowed; reading there returns
`UnexpectedEnd`. Failed seek and `read_bytes` operations leave the cursor
unchanged. Every reported offset is absolute within the file.

Section payloads, function bodies, locals, instruction immediates and optional
name subsections use bounded readers. The outer custom-section name is
structural and must fit its payload. Optional name metadata remains tolerant of
damaged entries, preserving earlier names without borrowing following bytes.
Parsing and range failures return CLI exit code `1`, including with `--strict`,
and never create or overwrite JSON, DOT or HTML reports. They are distinct from
call-graph gaps refused with code `3`.

`parse_module` accepts Core Wasm binary version `1` only and checks standard
section uniqueness and order. Custom sections may repeat, including with the
same name, anywhere between standard sections. The explicit order is Type,
Import, Function, Table, Memory, Tag, Global, Export, Start, Element, DataCount,
Code, Data; numeric section ids alone do not give this order.

Local function declarations and code bodies must have equal counts; imports
are excluded. Both payloads must be consumed completely, and every code body
must fit its declared range. Missing sections count as zero. Current inputs
and `--baseline` use the same checks before reports are printed or written.
`analyze(data, parsed)` also revalidates the bytes and derives its section table
from them, so stale or modified metadata cannot bypass these checks.

These are the basic structure checks needed for size analysis. The tool does
not yet provide full WebAssembly type and instruction-semantic validation.
Type/call index validity, signed LEB numeric semantics and full 64-bit constant
storage remain limited; dynamic table analysis also retains its documented
limitations.

Parsing function signatures are unchanged. External exhaustive matches on
`WasmError` must handle five new variants:

| Variant | Fields |
|---|---|
| `UnsupportedVersion` | version-field offset, raw unsigned `UInt` value |
| `DuplicateSection` | second section's id-byte offset, kind |
| `InvalidSectionOrder` | current id-byte offset, kind, preceding standard kind |
| `FunctionCodeCountMismatch` | related section's id-byte offset, kind, local declaration count, body count |
| `TrailingSectionBytes` | first unconsumed payload byte offset, kind |

Version errors point to offset `4`; mismatch errors use the code section when
present, otherwise the function section. These failures return input error
`1`, including under `--strict`, rather than graph-incompleteness code `3`.

### Diagnostic API and export migration

This is an intentional API extension. `CallGraph` now has
`diagnostics : Array[GraphDiagnostic]`; match `GraphDiagnosticKind` on
`NoStaticTableTargets` or `UnmodeledReferenceCall`. Total gaps come from this
array. `Analysis.unresolved_count` still counts only table calls with no static
candidates; it can be zero while the graph has reference-call gaps.

`scan_calls` now returns `CallKind::Reference` for `call_ref` and
`return_call_ref`, with `type_index = Some(type)` and the original offset.
External exhaustive matches on `CallKind` must add this branch. `ref.func`
continues to create a reference edge, not a call site.

Use `render_graph_warning(analysis.graph)`, `render_dead_code(analysis, top)`
and `render_retained(analysis, top)`. The last two read diagnostics internally;
the old separate arrays, file-size argument and optional `unresolved` count
are removed. The library example above and `_probe/` use these signatures.

JSON exports retain `module`, `functions`, `roots`, `edges` and `indirect_sites`,
and add `schema_version: 1`, `graph_complete`, `modeling_scope` and `diagnostics`.
Each diagnostic has `code`, `caller`, `offset`, `opcode`, `type_index` and
`table_index` (null for reference calls). Stable codes are
`no_static_table_targets` and `unmodeled_reference_call`; complete graphs carry
an empty array. Diagnostics sort by caller and offset.

Non-strict JSON, DOT and HTML exports carry their own limitations: JSON contains
structured diagnostics and scope, DOT has a graph-level warning label, and HTML
shows diagnostics at the top and limits alongside dead-code results. Sharing an
export preserves this information. Strict refusal occurs before writing a new
file or changing an existing one, for all three formats.

### Retained size

`SIZE` is a function on its own. `RETAINED` is what deleting it would actually
free: its own bytes plus every function that becomes unreachable with it, with
`DIES` counting how many that is.

That set is exactly the functions the deleted one *dominates* — those every path
from a root has to pass through. Taking the module's graph, adding a virtual root
above the real ones, and computing the dominator tree gives every function's
retained size in one pass. Cycles fall out of the fixpoint rather than needing a
special case, and the answer is exact rather than an approximation from local
predecessor counts: if two branches both call a function, deleting one branch
does not free it, but deleting the point where both branches meet does.

Reading the table:

- `RETAINED == SIZE` — the function is load-bearing only for itself. Deleting it
  saves its own bytes and nothing more.
- `RETAINED ≫ SIZE` with a high `DIES` — a good candidate. Removing it takes a
  whole subtree with it.
- `IND` — the function can be reached through a `call_indirect`, so removing it
  requires checking every dependent table entry and indirect call before removal.

Both numbers are printed on purpose. `SIZE` says how much the compiler could win
by making the function smaller; `RETAINED` says how much it wins by removing it,
which is usually the cheaper change.

### Dead code

The list contains functions unreachable from roots within the current model.
Inspect diagnostics and modelling limits before considering removal; an
incomplete graph does not prove a function can be removed.

MoonBit's compiler does dead-code elimination well, so a small program usually
reports none — that is a finding too.

### Compressed size

A WebAssembly module is not served raw. It is served gzipped, and how much that
saves depends on what the bytes are: machine code compresses a little, symbol
names and strings compress a lot, and already-packed data barely moves at all. A
section table read raw therefore misleads in both directions, and `--compress`
answers the question a network asks instead:

```
COMPRESSED SIZE
  raw   10675 B
  gzip   5207 B  (48.7% of raw, ratio 2.05x)

  BY SECTION

  SECTION              RAW  GZIP  RATIO  SHARE(GZIP)
  code                5166  2712  1.90x        52.0%
  custom (name)       4975  1983  2.50x        38.0%
  data                 252   174  1.44x         3.3%
  custom (producers)    71    95  0.74x         1.8%
  type                  59    66  0.89x         1.2%
  function              50    63  0.79x         1.2%
  import                37    61  0.60x         1.1%
  export                21    45  0.46x         0.8%
  global                13    34  0.38x         0.6%
  element                8    32  0.25x         0.6%
  table                  7    31  0.22x         0.5%
  memory                 5    29  0.17x         0.5%
  datacount              3    27  0.11x         0.5%
```

`SHARE(GZIP)` is what the section costs as a share of the compressed file rather
than of the raw one, and it is the column to read. Here the code section is 48.3%
of the file raw but 52.0% of it compressed, while the name section goes the other
way — 46.6% raw, 38.0% compressed. The bytes the compiler emitted are the ones
worth attacking; the symbol names are close to free on the wire, which is worth
knowing before spending an afternoon on `--strip`.

Two things to keep in mind reading it. It is an estimate: the compressor runs at
its default level, which is the level servers use, but a server may be configured
differently, and it compresses the whole response rather than each section on its
own. And every section is compressed as its own stream, so each pays its own gzip
container of about twenty bytes — which is invisible for a section of kilobytes
and dominant for one of a handful of bytes, and is why the smallest sections
above read as growing when compressed. The shares barely notice, because twenty
bytes is nothing against a table of kilobytes.

A piece the compressor refuses is reported as a failure, never as its raw size:
`gzip failed: ...` in the text report, `N/A` with the reason on hover in the HTML
card. Printing the raw size would read as a ratio of 1.00x, and that is a
different claim from "nothing was measured".

### Judging what can be deleted

1. Start with `--dead-code`. Every row there is free to remove; check that
   nothing outside the module calls it by name (an exported name would have made
   it a root, so this is already accounted for).
2. Then look at `--retained` for large `RETAINED` values with `DIES` above zero.
   Those are the functions whose removal cascades.
3. Treat `IND` rows with care: an indirect candidate can only be removed when the
   table entry and the call sites go with it.

## Example output

A 10,675-byte MoonBit program (`--target wasm`, debug), reduced to the analysis
sections:

```
Retained size

    #  INDEX  SIZE  RETAINED  DIES    SHARE  IND  FUNCTION
    1     47   158      5162    46    48.3%       ____moonbit__main
    2     39   301      1773    10    16.6%       int::Int::to__string_2einner
    3     37    24       887     8     8.3%       println
    4     34     9       819     5     7.6%       moonbit.println
    5     33   206       810     4     7.5%       moonbit.fprintln
    6     28    49       717     7     6.7%       moonbit.decref
    7     29   409       668     6     6.2%       moonbit.gc.free
    8     43   633       633     0     5.9%       int__to__string__dec

  DIES counts the other functions that become unreachable with this one.
  IND marks a function an indirect call could reach.

Dead code

  0 of 47 functions are unreachable from the roots
  0 bytes (0.0% of file)

  every function is reachable
```

`____moonbit__main` retains 5,162 bytes — 48.3% of the file, 46 functions — which
is what a program with a single entry point looks like: everything hangs off it.
`int__to__string__dec` is the largest single function at 633 bytes but retains
only itself, so shrinking it is a compiler problem rather than a deletion.

`--call-graph graph.dot` writes the same graph for Graphviz, with dead functions
dashed and indirect edges dotted; `--call-graph graph.json` writes it with the
roots, every edge and every indirect site's candidate set.

## HTML report

`--html <path>` writes the same analysis as one self-contained page: no server,
no build step, no network. Open the file and the four charts are there, with the
compressed sizes the text report only shows under `--compress`.

![moonsize HTML report](examples/report.png)

A worked example is checked in at [`examples/report.html`](examples/report.html),
generated from [`examples/fib.wasm`](examples/fib.wasm) — a 10,675-byte MoonBit
program. It is one file: the chart library is inlined, so it can be moved,
emailed or opened from anywhere. The source it was built from is
[`examples/fib.mbt`](examples/fib.mbt), which is also a package here: building
`--target wasm` produces the example alongside the tool.

**Four headline numbers.** File size, the code section, what the file costs
gzipped, and how much of it is unreachable. The gzip card carries the share of
raw and the ratio underneath, and the dead-code card turns red when there is
anything to delete, which is the one number most people open the report for.

**Sections** — a horizontal bar per section, widest first, with the share of the
file in the tooltip. This is the stage-one section table, drawn. Both bar charts
are sized to their row count, so every row keeps its label; a fixed-height box
makes ECharts drop most of them, and the rows that survive look like headings for
the unlabelled ones below.

The sections chart has two views, switched by the `raw` / `gzip` legend in its
corner: the same bars measured before and after compression. They share one axis
and overlap exactly, so switching shows how much shorter the compressed bars are
instead of rescaling the axis to hide it — the code section barely moves, the
name section loses half its length. The tooltip gives both numbers and the ratio
in either view.

**Top 20 functions by body size** — what the compiler could shrink. Body size is
used rather than the encoded size so that the ranking answers "where is the
code", not "where are the size prefixes".

**Modules** — a donut of how the code section divides between packages, as a
share of the code section rather than of the file, so the slices mean "which
package is responsible for the code". Slices below 0.5% are rolled into a
single `other` slice, named on hover: a slice that thin cannot carry a label, and leaving it in draws a sliver nobody can read or aim at. Labels sit
inside the ring, so they never collide with the legend.

**Treemap** — module → function, where area is bytes. This is the one chart that
shows the whole binary at once: the big cells are the functions worth looking at,
and cells are drawn red when the function is unreachable. The area stays the raw
size — a treemap drawn by compressed bytes would be a different chart, and a less
useful one — so the compressed size and ratio are reported in the tooltip
instead of drawn.

Hovering any bar, slice or cell shows the exact bytes and percentage. Every
number in the page comes from the same `Analysis` the text report uses, so the
two cannot disagree — including the compressed ones, which the page computes with
the same compressor and the same level as `--compress`.

The library is vendored in [`assets/echarts.min.js`](assets/README.md) and inlined
into the page. When that file is not next to the working directory — running a
installed binary from elsewhere, say — the page falls back to a CDN `<script
src>` tag instead and the command says so; that report needs a network
connection to draw.

## CI integration

`--max-size` turns the report into a gate, and `--baseline` turns it into a
comparison, so a build can fail on growth instead of on a number somebody has to
keep updating by hand.

```sh
moonsize app.wasm --max-size 100KB                     # a ceiling on the file
moonsize app.wasm --baseline main.wasm --max-size 5KB  # at most 5 KB of growth
```

With a baseline, `--max-size` bounds the *change*, not the file: the question a
pull request asks is what it costs, not how big the program already was. A run
with a baseline prints the comparison after the report, largest current group first,
with the change as bytes and as a share of what it was:

```
SIZE COMPARISON

                      baseline  current  delta
  total                  10675    11039  +364  (+3.4%)
  code                    5166     5299  +133  (+2.5%)
  custom (name)           4975     5205  +230  (+4.6%)
  data                     252      252  0  (0.0%)
  custom (producers)        71       71  0  (0.0%)
  ...
```

Standard sections compare by kind. Custom sections group by their complete,
case-sensitive names: repeated names produce one row containing their summed
encoded sizes. Empty names are valid, and a custom section named `code` remains
separate from the standard code section. Sizes include each section's actual
id, length encoding and full payload, including the custom name encoding;
legal non-shortest length encodings therefore count their extra bytes.

For example, two `x` sections of 4 and 6 bytes compared with two of 5 and 8 bytes
produce one row:

```text
              baseline  current  delta
  custom (x)        10       13  +3  (+30.0%)
```

This compares a name's total encoded size without attempting to pair individual
same-name custom sections across builds. Reordering sections does not change
the result. Ties use descending baseline size, then standard binary section
order followed by custom name order (`String::compare`). Deleted groups remain
visible against zero.

`total` is the entire file, including its eight-byte header. Group increases
and decreases may cancel, and equal group sizes do not imply equal content.
With a baseline, `--max-size` still limits only the whole-file growth, including
when some groups grow while the total is unchanged.

The exit codes are `0` ok, `1` unreadable input, `2` bad command line and `3`
over budget or refused by `--strict`, so a job can tell a broken input apart
from a broken build.

This repository gates itself in [`.github/workflows/ci.yml`](.github/workflows/ci.yml):
formatting, `moon check --target native --deny-warn`, `moon test`, and the
checked-in example held to a budget. The local setup action pins MoonBit
`0.10.13+cbb11c36f` to match local formatting and tests, and runs `moon update`
before dependency resolution. A toolchain upgrade should update local checks
and CI together.

```yaml
- uses: ./.github/actions/setup-moonbit
- name: The example stays inside its budget
  run: moon run cmd/main -- --max-size 100KB examples/fib.wasm
```

For another project that produces a `.wasm`, install the compatible toolchain
with the official installer before applying its size budget:

```yaml
- name: Setup MoonBit
  run: |
    curl -fsSL https://cli.moonbitlang.com/install/unix.sh | bash -s '0.10.13+cbb11c36f'
    echo "$HOME/.moon/bin" >> "$GITHUB_PATH"
- run: moon update
- run: moon build --target wasm --release
- name: Size budget
  run: moonsize _build/wasm/release/build/app/app.wasm --max-size 250KB
```

To catch growth rather than an absolute size, build the base branch too and pass
it as the baseline; `--max-size` then reads as the allowance:

```yaml
- name: Build the base branch
  run: |
    git worktree add "$RUNNER_TEMP/base" "origin/${{ github.base_ref }}"
    (cd "$RUNNER_TEMP/base" && moon build --target wasm --release)
- name: Size budget
  run: |
    moonsize _build/wasm/release/build/app/app.wasm \
      --baseline "$RUNNER_TEMP/base/_build/wasm/release/build/app/app.wasm" \
      --max-size 5KB
```

[`.github/workflows/size-check.yml`](.github/workflows/size-check.yml) does that
on every pull request. `examples/` is a package of this module, so both sides
build the example the same way and the comparison is between two builds of the
same source:

```sh
moon build --target wasm                        # -> examples wasm
moon run cmd/main -- that.wasm --baseline base.wasm --max-size 5KB
```

## Development

The key decisions, the known limits of the symbol rules, the role AI tools
played, and the provenance of everything vendored are written down in
[`docs/devlog.md`](docs/devlog.md).

```sh
moon check --target native --deny-warn
moon test
moon build --target native --release
bash scripts/test-tail-calls.sh _build/native/release/build/cmd/main/main.exe
bash scripts/test-graph-diagnostics.sh _build/native/release/build/cmd/main/main.exe
bash scripts/test-parser-boundaries.sh _build/native/release/build/cmd/main/main.exe
```

The diagnostic CLI script requires Node.js to validate its Wasm fixtures with
V8 and assert fields in parsed JSON. The parser script also uses Node.js for a
five-second timeout per CLI process, distinguishing timeouts, crashes and
expected input errors. All three scripts run in Git Bash or Linux after building
the native executable. Complete-module fixtures are cross-checked with V8;
Reader-only and optional metadata tests are kept separate.

The test suite covers the instruction table one opcode at a time — every entry
carries a canonical encoding and the length the specification gives it — and pins
three real MoonBit function bodies, including one whose locals use two-byte
garbage-collection reference types, so a wrong immediate width fails a test
instead of quietly producing a wrong call graph.

### Regenerating the example

The numbers quoted in [`examples/report.html`](examples/report.html) and in this
README — the file size, the section shares, the retained sizes — are read out of a
real build rather than written by hand. Changing
[`examples/fib.mbt`](examples/fib.mbt) or moving to a new toolchain makes them
stale, and all three steps have to be run again:

```sh
moon build --target wasm
moon run cmd/main -- --html examples/report.html examples/fib.wasm
# then re-capture examples/report.png from that page
```

The first step builds `examples/` and leaves the artifact at
`_build/wasm/debug/build/examples/examples.wasm`; `examples/fib.wasm` is a copy of
it, the report is generated from that, and the screenshot is a capture of the
report at 1400px wide and full height. Nothing under `examples/` is edited by
hand, so a stale number there means a stale build rather than a typo.

`.moonignore` keeps the rendered page out of the published package — it is
1.2 MB of what would otherwise be a 2.4 MB module, and nobody `moon add`s this
for a screenshot — while the source, the example binary and the chart library
all ship.
