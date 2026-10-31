# Source delivery and actual package boundary

`moon add BigSaltyMan/moonsize@0.5.1` installs the published **library
dependency**, not an independent CLI. This source still declares0.5.1 and
contains additions that have not been published under a new version. A matching
version string alone does not identify the same code. Historical
[migration](migration-0.5.md) and
[v0.5.1 release](https://github.com/BigSaltyMan/moonsize/releases/tag/v0.5.1)
records retain their original identity.

For current CLI features, build from an explicit full source commit. These are
instructions for the user; the source-delivery task does not build locally:

```sh
git clone https://github.com/BigSaltyMan/moonsize.git
cd moonsize
SOURCE_SHA='replace-with-full-40-character-source-commit'
git checkout --detach "$SOURCE_SHA"
moon build --target native --release
./_build/native/release/build/cmd/main/main.exe --help
```

The library/CLI targets native. The CI setup pins MoonBit0.10.13+cbb11c36f
(moon0.1.20260915); each audit records actual `moon version --all`, Node and
platform values. Read [toolchain compatibility](toolchain-compatibility.md).

## Find the task, then the command

These links describe implemented source features, not promises about the
published0.5.1 interface. [Seven help topics](cli-help.md) remain the compact
parameter guide; the READMEs contain the full current option list.

| Task | Existing guides |
| --- | --- |
| Ordinary reports, budgets and comparisons | [Summary JSON](summary-json.md), [budgets](budgets.md), [function/module comparison](function-diff-json.md), [experiments](optimization-experiments.md), [HTML](html-report.md), [output protection](output-protection.md) |
| Find a function and investigate its encoding | [Name search](function-search.md), [instruction bytes](function-instructions.md), [locals](function-locals.md), [local accesses](function-local-accesses.md), [module opcodes](module-opcodes.md), [opcode search](opcode-search.md), [duplicates](duplicate-functions.md), [generics](generic-instances.md), [file offsets](file-offset.md), [file ranges](file-range.md) |
| References, paths, closures, cycles and DOT | [Call sites](function-calls.md), [callers](function-callers.md), [explicit pair paths](function-path-between.md), [outgoing closure and DOT](function-dependencies.md), [incoming closure and DOT](function-dependents.md), [set comparison](dependency-overlap.md), [cycles](function-cycles.md), [entrypoints](entrypoints.md), [model retained boundaries](retained-size-boundaries.md) |
| Data and metadata | [Data entries/comparison/duplicates](data-segments.md), [UTF-8/hex search](data-search.md), [bounded windows](data-preview.md), [custom/name inspection and outer comparison](metadata.md) |
| Host imports and exports | [Imports and comparison](imports.md), [exports and comparison](exports.md) |

## Reproduce the actual package audit

From a checkout containing these audit scripts, select a local full commit and
a **new** evidence directory. No npm packages are needed; Node and Python3
standard libraries orchestrate Git and the existing MoonBit tools:

```sh
node scripts/audit-source-package.mjs "$SOURCE_SHA" \
  _build/source-package-audit/manual-unique-id
```

The script is a validation action: it packages and compiles code. CI requires
its explicit source SHA to equal final `GITHUB_SHA`. It creates a fresh temporary
directory outside the repository and uses `git archive` for that commit.
Uncommitted images, plans and AGENTS never enter the clean export. It runs
`moon package --list` and **one actual `moon package`**, then audits the resulting
ZIP, not just the source archive or printed list. Failed directories are kept;
there is no global configuration/ACL change or recursive cleanup.

Before ZIP extraction, the helper rejects absolute/traversing/noncanonical
paths, duplicate or conflicting names, links and abnormal members. Package root
comes from its actual manifest. Every member records canonical path, original
size and content SHA-256. Every actual runtime source/configuration file in the
clean export must be present with its original bytes (repository tests and the
explicitly excluded `_probe` are not runtime delivery). Unknown generated or
changed members are reported as failures rather than silently accepted.

Required checks include new library/CLI implementations, both DOT renderers,
paths/closures/overlap, native exclusive-write C/configuration, generated chart
source, vendored chart resources and licenses/NOTICE, vendored compression and
attribution, root license and task documentation. Build/cache trees, AGENTS,
plans, review attachments and repository report images must be absent. The
existing `.moonignore` changes only if an actual package audit exposes a problem.

## Package-contained execution is separate from registry consumption

The audited ZIP is extracted into a second new directory. A temporary executable
imports **that package's public library** and runs one fixed54B Wasm case:
3 functions (one import, two local definitions),12B local encoded ledger,
two-node/three-edge outgoing and incoming closures, one-hop path, four overlap
partitions and both DOT renderers. Fixed expected indices, bytes, offsets and
directions come from the fixture. This is a package API probe with compilation,
not a MoonBit unit test or `moon add @0.5.1` registry-consumer check.

The probe source is preserved outside the unpacked module before one native
release CLI build there. That CLI alone runs exactly three smoke cases against
the same fixture: HTML with embedded ECharts0; new incoming DOT0; existing DOT
refusal1 with original bytes unchanged. Its binary/input/output hashes and all
argv/status/logs are recorded. No working-repository build binary is reused.
Probe compilation and CLI release construction are separate recorded stages.

Actual public package consumption retains its meaning in
`scripts/verify-release-consumer.mjs`; this audit neither changes nor executes
that workflow. No Mooncakes publication, tag, GitHub Release or application
submission is part of this source-delivery change.

## Evidence and limits

The existing complete CI remains. One package-boundary step produces artifact
`source-package-audit-<full-SHA>`: actual `package.zip`, `members.json`, command
stdout/stderr/status, toolchain/source SHA, probe source/result, three CLI
records and HTML/DOT/input hashes, plus `results.json`. Upload is attempted even
on failure when the run directory exists; only that run directory is uploaded.
The clean source archive and external temporary build trees are not uploaded.

Source SHA, final CI URL, actual ZIP size/hash and counts come from the target
run and completion report. They are not prefilled in this self-identifying
commit. A later change to package content requires a fresh final-SHA audit.
Network/dependency setup, package content, probe and build failures retain
distinct stage/log identities; a failed download is not proof of a bad package.

Local validation for this change is limited to script syntax, documentation
links/paths and diff checks: **zero MoonBit tests, CLI invocations or builds**.
CI package execution does not redo Graphviz, visual/browser/PDF checks,
performance benchmarks or source demos. Prior [offline/PDF evidence](html-delivery.md)
keeps its historical scope. Complete Wasm semantic validation, future recompiles,
gzip benefits, other browser engines, font glyphs and physical printing remain
outside this audit. Independent gzip is not additive; retained/path/dependency
facts do not predict deletion savings. Performance limitations remain in
[performance.md](performance.md), including unmeasured50k/peak memory/real large
projects.
