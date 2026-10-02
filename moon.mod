// Moonsize — a WebAssembly binary size analyzer.
//
// Step 2 scope: decode the module preamble and section table, then attribute the
// code section to named functions and roll those bytes up per module.
name = "BigSaltyMan/moonsize"

version = "0.1.0"

license = "Apache-2.0"

preferred_target = "native"

keywords = [ "wasm", "webassembly", "size", "cli", "profiling" ]

description = "Analyse the size of a WebAssembly module: section layout, per-function byte budgets and per-module roll-ups."

import {
  "moonbitlang/x@0.5.5",
}