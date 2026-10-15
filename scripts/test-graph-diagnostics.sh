#!/usr/bin/env bash
# Requires Node.js for independent Wasm validation and parsed JSON assertions.
set -euo pipefail

if [[ $# -ne 1 || ! -f "$1" || ! -x "$1" ]]; then
  echo "usage: bash scripts/test-graph-diagnostics.sh /path/to/moonsize-cli" >&2
  exit 1
fi
command -v node >/dev/null || { echo 'Node.js is required for fixture validation and JSON checks.' >&2; exit 1; }
cli=$(cd -- "$(dirname -- "$1")" && printf '%s/%s' "$PWD" "$(basename -- "$1")")
work_dir=$(mktemp -d)
cleanup() {
  rm -f -- "$work_dir/"*
  rmdir -- "$work_dir"
}
trap cleanup EXIT
cases=0
fail() { echo "FAIL: $*" >&2; exit 1; }

expect_status() {
  local expected=$1 log=$2 status
  shift 2
  if "$cli" "$@" >"$log" 2>&1; then status=0; else status=$?; fi
  if [[ $status -ne $expected ]]; then
    cat "$log" >&2
    fail "expected exit $expected, got $status: $*"
  fi
  cases=$((cases + 1))
}

expect_reference() {
  grep -Fq 'function 0, offset 42: call_ref: reference-call target analysis is not implemented.' "$1" || fail "missing reference-call site and reason"
  grep -Fq 'do not use them as proof that a function can be removed.' "$1" || fail "missing removal limitation"
}

expect_refusal() {
  grep -Fq -- '--strict: refusing to report an incomplete call graph' "$1" || fail "missing strict refusal"
  if grep -Eq '^(SECTION|SIZE|Retained size|Dead code)|INDEX[[:space:]]+SIZE|HTML report written' "$1"; then
    fail "strict mode printed a normal analysis report"
  fi
}

# Validate actual fixture bytes with V8, independently of moonsize's parser.
node - "$work_dir" <<'JS'
const fs = require('node:fs');
const path = require('node:path');
const dir = process.argv[2];
const section = (id, payload) => [id, payload.length, ...payload];
function moduleBytes(expr, { imported=false, table=false, active=false } = {}) {
  const target = imported ? 2 : 1;
  const body = [0, ...expr, 0x0b];
  return Buffer.from([
    0, 97, 115, 109, 1, 0, 0, 0,
    ...section(1, [1, 0x60, 0, 0]),
    ...(imported ? section(2, [1, 1, 109, 1, 102, 0, 0]) : []),
    ...section(3, [2, 0, 0]),
    ...(table || active ? section(4, [1, 0x70, 0, 1]) : []),
    ...section(7, [1, 3, 114, 117, 110, 0, imported ? 1 : 0]),
    ...section(9, active ? [1, 0, 0x41, 0, 0x0b, 1, target] : [1, 3, 0, 1, target]),
    ...section(10, [2, body.length, ...body, 2, 0, 0x0b]),
  ]);
}
const fixtures = {
  reference: moduleBytes([0xd2, 1, 0x14, 0]),
  tail: moduleBytes([0xd2, 1, 0x15, 0]),
  twice: moduleBytes([0xd2, 1, 0x14, 0, 0xd2, 1, 0x14, 0]),
  mixed: moduleBytes([0x41, 0, 0x11, 0, 0, 0xd2, 1, 0x14, 0], {table:true}),
  static: moduleBytes([0x41, 0, 0x11, 0, 0, 0xd2, 1, 0x15, 0], {active:true}),
  imported: moduleBytes([0xd2, 2, 0x15, 0], {imported:true}),
  ref_only: moduleBytes([0xd2, 1, 0x1a]),
  indirect_tail: moduleBytes([0x41, 0, 0x13, 0, 0], {table:true}),
  direct: Buffer.from('0061736d0100000001040160000003030200000707010372756e00000a0902040012010b02000b', 'hex'),
};
for (const [name, bytes] of Object.entries(fixtures)) {
  try { new WebAssembly.Module(bytes); }
  catch (error) { throw new Error(`invalid Wasm fixture ${name}: ${error.message}`); }
  fs.writeFileSync(path.join(dir, name + '.wasm'), bytes);
}
console.log(`Validated ${Object.keys(fixtures).length} Wasm fixtures with V8.`);
JS

expect_status 0 "$work_dir/reference.log" "$work_dir/reference.wasm" --dead-code --retained
expect_reference "$work_dir/reference.log"
grep -Fxq 'Dead code' "$work_dir/reference.log" || fail "non-strict report missing"
expect_status 3 "$work_dir/strict.log" "$work_dir/reference.wasm" --strict --dead-code --retained
expect_reference "$work_dir/strict.log"
expect_refusal "$work_dir/strict.log"
expect_status 3 "$work_dir/tail.log" "$work_dir/tail.wasm" --strict
expect_refusal "$work_dir/tail.log"
grep -Fq 'function 0, offset 42: return_call_ref: reference-call target analysis is not implemented.' "$work_dir/tail.log" || fail "missing tail reference diagnostic"
expect_status 0 "$work_dir/mixed.log" "$work_dir/mixed.wasm"
grep -Fq 'WARNING: the call graph has 2 analysis gaps.' "$work_dir/mixed.log" || fail "mixed gaps miscounted"
grep -Fq 'function 0, offset 48: call_indirect: no static table targets are resolvable.' "$work_dir/mixed.log" || fail "table gap missing"
grep -Fq 'function 0, offset 53: call_ref: reference-call target analysis is not implemented.' "$work_dir/mixed.log" || fail "reference gap missing"

for source in reference mixed; do
  for format in json dot html; do
    output="$work_dir/$source.$format"
    mode=--call-graph
    [[ $format != html ]] || mode=--html
    expect_status 0 "$work_dir/export-$source-$format.log" "$work_dir/$source.wasm" "$mode" "$output"
    [[ -s "$output" ]] || fail "export missing: $output"
    if [[ $format != json ]]; then
      grep -Fq 'reference-call target analysis is not implemented.' "$output" || fail "export lost reference diagnostic"
      grep -Fq 'do not use them as proof that a function can be removed.' "$output" || fail "export lost limitation"
      if [[ $source == mixed ]]; then
        grep -Fq 'call_indirect: no static table targets are resolvable.' "$output" || fail "export lost table diagnostic"
      fi
    fi
  done
done

node - "$work_dir" <<'JS'
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const dir = process.argv[2];
for (const source of ['reference', 'mixed']) {
  const json = JSON.parse(fs.readFileSync(path.join(dir, source + '.json'), 'utf8'));
  assert.equal(json.schema_version, 1);
  assert.equal(json.graph_complete, false);
  assert.match(json.modeling_scope, /dynamic table contents are not solved/);
  assert.equal(json.functions.length, 2);
  assert.equal(json.edges.length, 1); // ref.func only, no fabricated reference-call callee
  assert.deepEqual(json.roots, [0, 1]);
  const ref = {code:'unmodeled_reference_call', caller:0, offset:source === 'mixed' ? 53 : 42, opcode:'call_ref', type_index:0, table_index:null};
  const expected = source === 'reference' ? [ref] : [
    {code:'no_static_table_targets', caller:0, offset:48, opcode:'call_indirect', type_index:0, table_index:0}, ref,
  ];
  assert.deepEqual(json.diagnostics, expected);
}
JS

printf '%s\n' 'existing report must survive strict refusal' >"$work_dir/sentinel"
for format in json dot html; do
  mode=--call-graph
  [[ $format != html ]] || mode=--html
  output="$work_dir/refused.$format"
  [[ ! -e "$output" ]] || fail "refusal output already exists"
  expect_status 3 "$work_dir/refused-$format.log" "$work_dir/reference.wasm" --strict "$mode" "$output"
  expect_reference "$work_dir/refused-$format.log"
  expect_refusal "$work_dir/refused-$format.log"
  [[ ! -e "$output" ]] || fail "strict mode created $output"
  cp -- "$work_dir/sentinel" "$output"
  expect_status 3 "$work_dir/existing-$format.log" "$work_dir/reference.wasm" --strict "$mode" "$output"
  expect_refusal "$work_dir/existing-$format.log"
  cmp -s -- "$work_dir/sentinel" "$output" || fail "strict mode changed existing $output"
done

expect_status 0 "$work_dir/direct.log" "$work_dir/direct.wasm" --strict --dead-code --retained
grep -Fq '0 of 2 functions are unreachable from the roots' "$work_dir/direct.log" || fail "Commit 1 dead-code regression"
awk '$1 == 1 && $2 == 0 && $3 == 5 && $4 == 8 && $5 == 1 { found=1 } END { exit !found }' "$work_dir/direct.log" || fail "Commit 1 retained-size regression"
echo "Graph-diagnostic CLI regressions passed ($cases process cases)."
