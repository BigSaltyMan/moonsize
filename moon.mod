// Moonsize — a WebAssembly binary size analyzer.
//
// Step 3 scope: decode the section table and the full instruction set, build the
// call graph, and report retained sizes and dead code.
name = "BigSaltyMan/moonsize"

version = "0.1.0"

license = "Apache-2.0"

preferred_target = "native"

keywords = [ "wasm", "webassembly", "size", "cli", "profiling" ]

description = "Analyse the size of a WebAssembly module: section layout, per-function byte budgets, call graph, retained sizes and dead code."

import {
  "moonbitlang/x@0.5.5",
}
