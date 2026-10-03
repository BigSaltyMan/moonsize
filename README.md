# moonsize

A size analyzer for WebAssembly, built for MoonBit's output. It reads a `.wasm`
file, measures every section, attributes the code section to named functions,
follows the call graph, and reports what could be deleted.

The analysis model follows [Twiggy](https://github.com/rustwasm/twiggy): sizes
are attributed to individual functions, functions are grouped by package, and
reachability from the module's roots decides what is really used.

## Building

```sh
moon build --release
./_build/native/release/build/cmd/main/main.exe app.wasm
```

## Usage

```
moonsize <file.wasm> [--top <n>] [--retained] [--dead-code]
                     [--call-graph <path>]

  --top <n>            how many functions to rank (default 10)
  --retained           what deleting each function would free
  --dead-code          functions no root can reach
  --call-graph <path>  write the call graph as .dot or .json
```

Without flags it prints the section table, the heaviest functions and the
per-package roll-up. `--retained` and `--dead-code` add their sections and can
be combined; `--call-graph` writes a file instead of a report, so it is used on
its own.

## Analysis

Everything below is built on one idea: a function's bytes only matter if
something can call it.

### The call graph

The decoder walks every function body instruction by instruction — the full MVP
instruction set, the `0xFC` saturating and bulk-memory opcodes, the exception
handling and tail-call opcodes MoonBit emits, and the `0xFB` garbage-collection
opcodes its `wasm-gc` backend uses. Each body contributes:

- `call x` — a precise edge to `x`;
- `ref.func x` — a reference, which counts as reachable because the function may
  run later as a closure;
- `call_indirect` — a *conservative* edge to every function any element segment
  places in that table. The table's contents are not known statically, so the
  candidates are all of them; a missing edge would mean a missing function and a
  function wrongly reported dead, which is the one mistake worth avoiding here.

A function is a **root** if the outside world can reach it: it is exported, it is
the start function, or it sits in a table. Everything reachable from those roots
is live; everything else is dead.

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
  is only safe if no table entry and no indirect call expects it.

Both numbers are printed on purpose. `SIZE` says how much the compiler could win
by making the function smaller; `RETAINED` says how much it wins by removing it,
which is usually the cheaper change.

### Dead code

Anything unreachable from the roots cannot run: no export reaches it, no start
function, no table entry, and no chain of calls from any of those. Its bytes are
already paid for and never used, so the list is a deletion list.

MoonBit's compiler does dead-code elimination well, so a small program usually
reports none — that is a finding too.

### Judging what can be deleted

1. Start with `--dead-code`. Every row there is free to remove; check that
   nothing outside the module calls it by name (an exported name would have made
   it a root, so this is already accounted for).
2. Then look at `--retained` for large `RETAINED` values with `DIES` above zero.
   Those are the functions whose removal cascades.
3. Treat `IND` rows with care: an indirect candidate can only be removed when the
   table entry and the call sites go with it.

## Example output

A 10,645-byte MoonBit program (`--target wasm`, debug), reduced to the analysis
sections:

```
Retained size

    #  INDEX  SIZE  RETAINED  DIES    SHARE  IND  FUNCTION
    1     47   158      5162    46    48.4%       ____moonbit__main
    2     39   301      1773    10    16.6%       int::Int::to__string_2einner
    3     37    24       887     8     8.3%       println
    4     34     9       819     5     7.6%       moonbit.println
    5     33   206       810     4     7.6%       moonbit.fprintln
    6     28    49       717     7     6.7%       moonbit.decref
    7     29   409       668     6     6.2%       moonbit.gc.free
    8     43   633       633     0     5.9%       int__to__string__dec

  DIES counts the other functions that become unreachable with this one.
  IND marks a function a call_indirect could reach.

Dead code

  0 of 47 functions are unreachable from the roots
  0 bytes (0.0% of file)

  every function is reachable
```

`____moonbit__main` retains 5,162 bytes — 48.4% of the file, 46 functions — which
is what a program with a single entry point looks like: everything hangs off it.
`int__to__string__dec` is the largest single function at 633 bytes but retains
only itself, so shrinking it is a compiler problem rather than a deletion.

`--call-graph graph.dot` writes the same graph for Graphviz, with dead functions
dashed and indirect edges dotted; `--call-graph graph.json` writes it with the
roots, every edge and every indirect site's candidate set.

## Development

```sh
moon check --target native --deny-warn
moon test
```

The test suite covers the instruction table one opcode at a time — every entry
carries a canonical encoding and the length the specification gives it — and pins
three real MoonBit function bodies, including one whose locals use two-byte
garbage-collection reference types, so a wrong immediate width fails a test
instead of quietly producing a wrong call graph.
