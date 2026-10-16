#!/usr/bin/env bash
# Build both sources in the same project with the same debug/name-preserving mode.
# Outputs stay under ignored _build/ for inspection; no published example changes.
set -euo pipefail
if [[ $# -ne 1 || ! -f "$1" || ! -x "$1" ]]; then
  echo 'usage: bash scripts/demo-function-diff.sh /path/to/moonsize-cli' >&2
  exit 1
fi
cli=$(cd -- "$(dirname -- "$1")" && printf '%s/%s' "$PWD" "$(basename -- "$1")")
repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
mkdir -p "$repo/_build"
work=$(mktemp -d "$repo/_build/function-diff-demo.XXXXXX")
printf 'name = "demo/functiondiff"\n' > "$work/moon.mod"
printf 'pkgtype(kind: "executable")\n' > "$work/moon.pkg"
artifact="$work/_build/wasm/debug/build/functiondiff.wasm"
moon version --all
for version in before after rollback; do
  source=$version
  [[ $version != rollback ]] || source=before
  cp "$repo/examples/function-diff/$source.mbt" "$work/main.mbt"
  (cd "$work" && moon build --target wasm --debug --no-strip)
  [[ -s "$artifact" ]] || { echo "missing built artifact: $artifact" >&2; exit 1; }
  cp "$artifact" "$work/$version.wasm"
done
# V8 confirms both validity and actual retained function-name metadata.
node - "$work" <<'JS'
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
for (const name of ['before', 'after', 'rollback']) {
  const data = fs.readFileSync(path.join(process.argv[2], name + '.wasm'));
  assert.ok(WebAssembly.validate(data), name);
  const module = new WebAssembly.Module(data);
  assert.ok(WebAssembly.Module.customSections(module, 'name').length > 0, name + ' has no name section');
}
JS
"$cli" "$work/after.wasm" --baseline "$work/before.wasm" --diff-functions --top 1000000 > "$work/changes.txt"
"$cli" "$work/rollback.wasm" --baseline "$work/before.wasm" --diff-functions --top 1000000 --max-size 0B > "$work/rollback.txt"
cmp -s "$work/before.wasm" "$work/rollback.wasm" || { echo 'rollback did not restore the full artifact' >&2; exit 1; }
node - "$work/changes.txt" "$work/rollback.txt" <<'JS'
const fs = require('node:fs');
const assert = require('node:assert/strict');
const [change, rollback] = process.argv.slice(2).map(p => fs.readFileSync(p, 'utf8'));
const rows = text => [...text.matchAll(/^  (matched|added-symbol|removed-symbol|ambiguous|missing-symbol)\s+(\d+|-)\s+(\d+|-)\s+(\d+)\s+(\d+)\s+([+-]?\d+)\s+(.+)$/gm)];
assert.ok(rows(change).some(r => r[1] === 'matched' && r[7].includes('classify') && Number(r[6]) > 0), 'classify growth was not found');
assert.ok(rows(change).some(r => r[1] === 'added-symbol' && /weighted_+score/.test(r[7]) && Number(r[6]) > 0), 'new weighted_score symbol was not found');
const packageSection = change.split('PACKAGE SIZE CHANGES')[1].split('MATCHING SUMMARY')[0];
assert.ok(packageSection.split('\n').some(line => /demo::functiondiff/.test(line) && /\+\d+/.test(line)), 'demo package growth was not found');
assert.ok(rows(rollback).length > 0);
assert.ok(rows(rollback).every(r => r[1] === 'matched' && Number(r[6]) === 0), 'rollback symbol differences remain');
assert.ok(rollback.includes('Function delta = matched 0 + added 0 - removed 0 + unmatched current 0 - unmatched baseline 0 = 0 B.'));
console.log('MoonBit function-diff demo passed: classify grew, weighted_score appeared, package grew; rollback restored bytes and symbols.');
JS
printf 'Demo artifacts and measured reports: %s\n' "$work"
sed -n '/^FUNCTION SIZE CHANGES/,$p' "$work/changes.txt"
