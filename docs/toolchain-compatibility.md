# Toolchain and online documentation compatibility

The 0.4.0 and 0.5.0 archives remain immutable historical releases. Their registry
documentation builds fail before compiling moonsize: the builder rejects the
old moon.mod.json in bikallem/compress@0.3.4. Its dependency chain also contains
bikallem/blit@0.2.2 and moonbitlang/async@0.16.7.

Original public logs:

- https://mooncakes.io/api/v0/builds/log?module=BigSaltyMan%2Fmoonsize&version=0.4.0
- https://mooncakes.io/api/v0/builds/log?module=BigSaltyMan%2Fmoonsize&version=0.5.0

Pinned-toolchain consumption had passed; that did not verify Mooncakes' separate
documentation builder. Upload acceptance is also separate from documentation
success. New-toolchain consumers could encounter the same dependency failure.

## 0.5.1 repair

The package ships the bounded synchronous implementation from the same pinned
compression/byte-helper archives. See [provenance and Apache-2.0 license](../internal/compression/README.md).
It no longer depends on those registry modules or their async adapters. Import
paths, native symbols and deprecated syntax are adapted; algorithms and default
compression settings are retained. Historical measured examples are not rewritten.
Root public function signatures, CLI modes and JSON meanings do not change.

The original regression CI remains pinned to MoonBit 0.10.13+cbb11c36f with
warnings denied. An additional current-stable-toolchain job checks native code,
the existing compression tests and actual `moon doc`. It records its toolchain;
the floating version intentionally detects future registry-ecosystem drift.

Local isolated verification used official Windows archives (SHA-256 checked):
moon 0.1.20261020, moonc v0.10.16+b1a0e846e. Check and documentation generation
passed. That compiler reports non-blocking implicit trait-method deprecations;
the current-toolchain job does not claim warning-free compatibility. The user
installation is unchanged. Public registry consumption and online documentation
must still be verified after publishing the exact patch.

The [v0.5.1 release record](https://github.com/BigSaltyMan/moonsize/releases/tag/v0.5.1)
records the actual commit, CI, package hashes, consumer checks, compressor byte
comparison and Mooncakes documentation result when completed. Merely finding
the version in search is not the acceptance criterion. No new browser/PDF or
performance matrix is claimed by this repair.

Directed local results: 18 compression tests passed on each toolchain, and the
existing 21 compression-report CLI cases passed on the pinned toolchain. Five
inputs (empty, small, repeated, deterministic noise and the unchanged fib.wasm)
produce byte-identical complete gzip streams versus public 0.5.0, not merely
equal lengths. Root generated public API is identical to the 0.5.0 baseline.
The raw record is attached to the patch Release after verification.
