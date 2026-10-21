# Report output protection

This behavior is included in the 0.5.0 source. See the
[0.5 migration guide](migration-0.5.md) and the
[release record](https://github.com/BigSaltyMan/moonsize/releases/tag/v0.5.0)
for the actual publication and exact-version verification status.

All CLI report destinations follow one policy: `--html`, `--call-graph` (DOT/JSON),
`--experiment` (HTML/JSON), `--why-json`, `--budget-json`, `--budget-md` and
`--data-json` (single input or comparison) require
a **new** target. There is no overwrite flag. Failure returns 1 with
`output already exists` or `cannot safely write output`; no success notice follows.

Existing files and directories are refused, including relative/absolute,
hard-link, symbolic-link and parent-link aliases of inputs, baseline, configuration,
context or earlier evidence. Protection uses filesystem lookup and exclusive
creation, not equality of path strings. Dangling final symlinks are also refused.
Windows alternate data streams and device namespaces are not report destinations.

The current MoonBit x/fs native API opens writes in truncating mode. A small
CLI-private C helper therefore uses Windows `CreateFileW(..., CREATE_NEW, ...)`
with UTF-8 to UTF-16 path conversion, or POSIX `open(O_CREAT | O_EXCL | O_WRONLY)`.
It handles short/interrupted writes and checks close errors. Production needs no
Node dependency. The library API and report schema are unchanged.

Input/context/config parsing, fallible analysis and strict graph refusal happen
before the common output preflight. Strict gaps return 3 without creating or
overwriting reports, even if the target exists. All requested outputs are checked
before the first write. Each actual create is exclusive as well: if another
process creates that name after the check, it is refused instead of truncated.
Budget exceedance still writes explanatory evidence and returns 3.

This is **not a multi-file transaction or crash-atomic publication**. Missing
parents/permission errors/write/close failures return 1. A later failure can leave
earlier successfully created outputs, or our own partial new file. The CLI never
deletes targets to retry or roll back. It does not lock parent directories or
defend against hostile concurrent directory/reparse/mount replacement; pathname
lookups still follow parent directories. Remote/unusual filesystems can provide
weaker guarantees than local Windows/POSIX exclusive creation. Durability against
power loss is not promised.

## Update an existing report explicitly

Generate into a new staging directory, check the input hash and measurements,
then copy the accepted result to the intended published location as a separate
user-controlled step. See the two README regeneration recipes. Do not delete an
existing report merely to satisfy the production command's preflight.

## Reproduce the protection checks

```sh
moon build --target native --release
node scripts/test-output-protection.mjs _build/native/release/build/cmd/main/main.exe
```

The script creates only synthetic complete Wasm modules and evidence in a fresh
OS temporary directory. Every refusal checks the exact status/reason, current/
baseline/config/context/previous-evidence SHA-256, and absence of success output.
It tests new outputs, both budget targets checked before writing, late partial
failure, strict/input-error order, aliases, read-only targets, a permission-denied
parent and twelve competing CLI processes (exactly one creator). Symbolic-link
capability errors and permission tests that cannot run are printed as explicit
SKIP reasons; they are not counted as passed processes. Linux CI must exercise
symbolic links; a platform failure is not silently relabeled as success.
