#!/usr/bin/env bash
# Git Bash/Linux process tests with independent V8 validation and exact numbers.
set -euo pipefail
if [[ $# -ne 1 || ! -f "$1" || ! -x "$1" ]]; then
  echo 'usage: bash scripts/test-size-comparison.sh /path/to/moonsize-cli' >&2
  exit 1
fi
command -v node >/dev/null || { echo 'Node.js is required.' >&2; exit 1; }
cli=$(cd -- "$(dirname -- "$1")" && printf '%s/%s' "$PWD" "$(basename -- "$1")")
work_dir=$(mktemp -d)
cleanup() { rm -f -- "$work_dir/"*; rmdir -- "$work_dir"; }
trap cleanup EXIT

node - "$cli" "$work_dir" <<'JS'
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const {spawnSync} = require('node:child_process');
const [cli, dir] = process.argv.slice(2);
const header = Buffer.from('0061736d01000000', 'hex');
function u32(value) {
  const bytes = [];
  do { const part = value & 127; value >>>= 7; bytes.push(part | (value ? 128 : 0)); } while (value);
  return Buffer.from(bytes);
}
function custom(name, extra = 0) {
  const bytes = Buffer.from(name, 'utf8');
  const payload = Buffer.concat([u32(bytes.length), bytes, Buffer.alloc(extra)]);
  return Buffer.concat([Buffer.from([0]), u32(payload.length), payload]);
}
function module(...sections) { return Buffer.concat([header, ...sections]); }
const hex = value => Buffer.from(value, 'hex');
const longA = 'x'.repeat(130) + 'A';
const longB = 'x'.repeat(130) + 'B';
const fixtures = {
  empty: module(),
  original: hex('0061736d0100000000020178000401780000'),
  reordered: module(custom('x', 2), custom('x')),
  grown: module(custom('x'), custom('x', 2), custom('x', 1)),
  removed: module(custom('x')),
  resized: module(custom('x', 1), custom('x', 4)),
  mixed_before: module(custom('x'), custom('x', 2), custom('y')),
  mixed_after: module(custom('x', 1), custom('x', 4), custom('z')),
  offset_before: module(custom('x'), custom('y', 4)),
  offset_after: module(custom('x', 2), custom('y', 2)),
  padded: module(hex('008300810078')),
  standard_before: module(hex('0101000a0100'), custom('code')),
  standard_after: module(hex('01810000'), custom('code', 2)),
  identities: module(custom('x'), custom('X'), custom(''), custom(' x'), custom('x '), custom('é'), custom(longB), custom(longA)),
  ties_before: module(hex('0101000c01000a0100'), custom('z', 1), custom('a', 2)),
  ties_after: module(hex('0101000c01000a0100'), custom('a', 1), custom('z', 1)),
  tied_reordered: module(custom('z', 1), hex('010100'), custom('a', 1), hex('0c01000a0100')),
};
for (const [name, bytes] of Object.entries(fixtures)) {
  new WebAssembly.Module(bytes);
  fs.writeFileSync(path.join(dir, name + '.wasm'), bytes);
}
assert.equal(fixtures.original.length, 18);
console.log(`V8 validated ${Object.keys(fixtures).length} complete Wasm comparison fixtures.`);
let cases = 0;
function run(before, after, expectedRows, {budget, status = 0, order} = {}) {
  const args = [path.join(dir, after + '.wasm'), '--baseline', path.join(dir, before + '.wasm'), '--strict'];
  if (budget !== undefined) args.push('--max-size', budget);
  const result = spawnSync(cli, args, {encoding:'utf8', timeout:5000, maxBuffer:4*1024*1024});
  const text = ((result.stdout || '') + (result.stderr || '')).replace(/\r\n/g, '\n');
  fs.writeFileSync(path.join(dir, `case-${cases + 1}.log`), text);
  const context = `${before} -> ${after}, budget ${budget ?? 'none'}\n${text}`;
  assert.ifError(result.error); // Includes timeout, launch and I/O failure.
  assert.equal(result.signal, null, `CLI crashed or was signalled: ${context}`);
  assert.equal(result.status, status, `wrong exact exit code: ${context}`);
  assert.equal((text.match(/SIZE COMPARISON\n/g) || []).length, 1, context);
  assert(!text.includes('WARNING:'), context);
  const comparison = text.slice(text.indexOf('SIZE COMPARISON\n'));
  const rows = new Map();
  for (const line of comparison.split('\n')) {
    const match = line.match(/^  (.*?)\s+(\d+)\s+(\d+)\s+([+-]?\d+)\s+\(([^)]+)\)$/);
    if (!match) continue;
    const [, label, baseline, current, delta, percent] = match;
    assert(!rows.has(label), `duplicate comparison row: ${context}`);
    const values = [Number(baseline), Number(current), Number(delta)];
    assert.equal(values[2], values[1] - values[0], context);
    if (values[2] === 0) assert.equal(percent, '0.0%', context);
    rows.set(label, values);
  }
  const expected = new Map(Object.entries(expectedRows));
  expected.set('total', [fixtures[before].length, fixtures[after].length, fixtures[after].length - fixtures[before].length]);
  assert.equal(rows.size, expected.size, `missing or extra rows: ${context}`);
  for (const [label, values] of expected) assert.deepEqual(rows.get(label), values, `wrong row ${label}: ${context}`);
  let baseSum = 0, currentSum = 0, deltaSum = 0;
  for (const [label, [baseline, current, delta]] of rows) {
    if (label !== 'total') { baseSum += baseline; currentSum += current; deltaSum += delta; }
  }
  assert.equal(baseSum + 8, fixtures[before].length, context);
  assert.equal(currentSum + 8, fixtures[after].length, context);
  assert.equal(deltaSum, rows.get('total')[2], context);
  if (order) assert.deepEqual([...rows.keys()], ['total', ...order], context);
  cases++;
  return [...rows];
}
const x = (baseline, current) => ({'custom (x)': [baseline, current, current - baseline]});
const self = run('original', 'original', x(10, 10), {budget:'0B'});
assert.deepEqual(run('original', 'reordered', x(10, 10), {budget:'0B'}), self);
assert.deepEqual(run('reordered', 'original', x(10, 10)), self);
run('original', 'grown', x(10, 15));
run('original', 'grown', x(10, 15), {budget:'5B'}); // Exactly at the budget.
run('original', 'grown', x(10, 15), {budget:'4B', status:3});
run('original', 'grown', x(10, 15), {budget:'0B', status:3});
run('grown', 'original', x(15, 10), {budget:'0B'});
run('original', 'removed', x(10, 4), {budget:'0B'});
run('original', 'resized', x(10, 13), {budget:'3B'});
run('mixed_before', 'mixed_after', {'custom (x)':[10,13,3], 'custom (y)':[4,0,-4], 'custom (z)':[0,4,4]}, {budget:'3B'});
run('mixed_after', 'mixed_before', {'custom (x)':[13,10,-3], 'custom (y)':[0,4,4], 'custom (z)':[4,0,-4]}, {budget:'0B'});
run('offset_before', 'offset_after', {'custom (x)':[4,6,2], 'custom (y)':[8,6,-2]}, {budget:'0B'});
run('offset_after', 'offset_before', {'custom (x)':[6,4,-2], 'custom (y)':[6,8,2]}, {budget:'0B'});
run('removed', 'padded', x(4, 6), {budget:'2B'});
run('standard_before', 'standard_after', {'type':[3,4,1], 'code':[3,0,-3], 'custom (code)':[7,9,2]}, {budget:'0B'});
run('standard_after', 'standard_before', {'type':[4,3,-1], 'code':[0,3,3], 'custom (code)':[9,7,-2]}, {budget:'0B'});
run('empty', 'empty', {}, {budget:'0B'});
run('empty', 'original', x(0, 10), {budget:'10B'});
run('original', 'empty', x(10, 0), {budget:'0B'});
const identityRows = {};
for (const name of ['x', 'X', '', ' x', 'x ', 'é']) {
  const size = name === '' ? 3 : (name === 'x' || name === 'X' ? 4 : 5);
  identityRows[`custom (${name})`] = [size, size, 0];
}
// 131 name bytes, two-byte name length and payload length, one id byte.
identityRows[`custom (${longA})`] = [136,136,0];
identityRows[`custom (${longB})`] = [136,136,0];
run('identities', 'identities', identityRows, {budget:'0B'});
const tieRows = {'type':[3,3,0], 'datacount':[3,3,0], 'code':[3,3,0], 'custom (a)':[6,5,-1], 'custom (z)':[5,5,0]};
const tieOrder = ['custom (a)', 'custom (z)', 'type', 'datacount', 'code'];
const tied = run('ties_before', 'ties_after', tieRows, {budget:'0B', order:tieOrder});
assert.deepEqual(run('ties_before', 'tied_reordered', tieRows, {budget:'0B', order:tieOrder}), tied);
console.log(`Size-comparison CLI regressions passed (${cases} process cases).`);
JS
