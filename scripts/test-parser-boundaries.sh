#!/usr/bin/env bash
# Node.js supplies portable process timeouts and an independent Wasm validator.
set -euo pipefail

if [[ $# -ne 1 || ! -f "$1" || ! -x "$1" ]]; then
  echo 'usage: bash scripts/test-parser-boundaries.sh /path/to/moonsize-cli' >&2
  exit 1
fi
command -v node >/dev/null || { echo 'Node.js is required.' >&2; exit 1; }
cli=$(cd -- "$(dirname -- "$1")" && printf '%s/%s' "$PWD" "$(basename -- "$1")")
repo=$(cd -- "$(dirname -- "$0")/.." && pwd)
work_dir=$(mktemp -d)
cleanup() { rm -f -- "$work_dir/"*; rmdir -- "$work_dir"; }
trap cleanup EXIT
cases=0
fail() { echo "FAIL: $*" >&2; exit 1; }

expect_status() {
  local expected=$1 log=$2
  shift 2
  # No shell around the CLI: timeout, signals, launch failures and unexpected
  # exit codes are distinct failures, never accepted as an expected input error.
  node - "$cli" "$expected" "$log" "$@" <<'JS'
const fs = require('node:fs');
const {spawnSync} = require('node:child_process');
const [cli, expected, log, ...args] = process.argv.slice(2);
const result = spawnSync(cli, args, {encoding:'utf8', timeout:5000, maxBuffer:4*1024*1024});
fs.writeFileSync(log, (result.stdout || '') + (result.stderr || ''));
function fail(reason) {
  console.error(`FAIL: ${reason}: ${args.join(' ')}`);
  console.error(fs.readFileSync(log, 'utf8'));
  process.exit(1);
}
if (result.error?.code === 'ETIMEDOUT') fail('CLI timed out after 5000 ms');
if (result.error) fail(`CLI launch/I/O failure: ${result.error.message}`);
if (result.signal) fail(`CLI crashed or was signalled: ${result.signal}`);
if (result.status > 128 || result.status < 0) fail(`CLI crashed: status ${result.status}`);
if (result.status !== Number(expected)) fail(`expected exit ${expected}, got ${result.status}`);
JS
  cases=$((cases + 1))
}

node - "$work_dir" "$repo" <<'JS'
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const [dir, repo] = process.argv.slice(2);
const header = '0061736d01000000';
const declarations = '01040160000003020100';
const following = '000100'; // A real custom section with an empty outer name.
const fixtures = {
  overflow: ['018080808010', 'LEB128 integer at offset 9'],
  overlong: ['01808080808000', 'LEB128 integer at offset 9'],
  truncated: ['0180', 'unexpected end of input at offset 9'],
  range: ['018080808008', 'unsigned value at offset 9 exceeds the supported integer range'],
  range_max: ['01ffffffff0f', 'unsigned value at offset 9 exceeds the supported integer range'],
  section: ['010401', 'unexpected end of input at offset 10'],
  section_wrap: ['01ffffffff07', 'unexpected end of input at offset 14'],
  body: [declarations + '0a03010300' + following, 'unexpected end of input at offset 22'],
  body_wrap: [declarations + '0a0601ffffffff07' + following, 'unexpected end of input at offset 26'],
  string: ['0703010278' + '0003000000', 'unexpected end of input at offset 12'],
  imports: ['020301016d' + '0003000000', 'unexpected end of input at offset 13'],
  start: ['0800' + following, 'unexpected end of input at offset 10'],
  element: ['090401004180' + following, 'unexpected end of input at offset 13'],
  custom_name: ['00020361' + following, 'unexpected end of input at offset 11'],
  custom_leb: ['000180' + following, 'unexpected end of input at offset 10'],
  huge_count: ['0205ffffffff07', 'unexpected end of input at offset 15'],
  huge_body_count: ['0a05ffffffff07', 'unexpected end of input at offset 15'],
  body_index: ['01040160000003030200000707010372756e00000a08020300128002000b', 'unexpected end of input at offset 34'],
  large_operand: [declarations + '0a0a0108001080808080080b', 'unsigned value at offset 24 exceeds the supported integer range'],
};
const manifest = [];
for (const [name, [hex, reason]] of Object.entries(fixtures)) {
  const bytes = Buffer.from(header + hex, 'hex');
  assert.equal(WebAssembly.validate(bytes), false, `malformed module unexpectedly valid: ${name}`);
  fs.writeFileSync(path.join(dir, name + '.wasm'), bytes);
  manifest.push(`${name}|${reason}`);
}
fs.writeFileSync(path.join(dir, 'bad-cases.txt'), manifest.join('\n') + '\n');
// Full valid modules, independently validated. Raw Reader tests for the full
// u32 range, signed LEB boundaries and name-subsection tolerance live in MoonBit.
const valid = {
  non_short: Buffer.from(header + '0185008100600000030201000707810001720080000a860081008200000b', 'hex'),
  direct: Buffer.from(header + '01040160000003030200000707010372756e00000a0902040012010b02000b', 'hex'),
  reference: Buffer.from(header + '01040160000003030200000707010372756e0000090501030001010a0b020600d20114000b02000b', 'hex'),
  example: fs.readFileSync(path.join(repo, 'examples', 'fib.wasm')),
};
for (const [name, bytes] of Object.entries(valid)) {
  new WebAssembly.Module(bytes);
  fs.writeFileSync(path.join(dir, name + '.wasm'), bytes);
}
console.log(`V8 cross-check: ${Object.keys(fixtures).length} malformed and ${Object.keys(valid).length} valid complete modules.`);
JS

while IFS='|' read -r name reason; do
  for mode in plain strict; do
    flags=()
    [[ $mode != strict ]] || flags+=(--strict)
    log="$work_dir/$name-$mode.log"
    expect_status 1 "$log" "$work_dir/$name.wasm" "${flags[@]}"
    grep -Fq "$reason" "$log" || fail "wrong error category or position for $name"
    if grep -Eq 'WARNING:|refusing to report|^(Retained size|Dead code)|INDEX[[:space:]]+SIZE' "$log"; then
      fail "parser error became a graph warning or normal report: $name"
    fi
  done
done <"$work_dir/bad-cases.txt"

# Parsing failures must not create or overwrite any export, even under --strict.
printf '%s\n' 'existing report must survive parse failure' >"$work_dir/sentinel"
for format in json dot html; do
  mode=--call-graph
  [[ $format != html ]] || mode=--html
  for strict in no yes; do
    flags=()
    [[ $strict != yes ]] || flags+=(--strict)
    output="$work_dir/refused-$strict.$format"
    [[ ! -e "$output" ]] || fail "report path unexpectedly exists"
    expect_status 1 "$work_dir/new-$strict-$format.log" "$work_dir/overflow.wasm" "${flags[@]}" "$mode" "$output"
    [[ ! -e "$output" ]] || fail "parser created a report"
    cp -- "$work_dir/sentinel" "$output"
    expect_status 1 "$work_dir/existing-$strict-$format.log" "$work_dir/body.wasm" "${flags[@]}" "$mode" "$output"
    cmp -s -- "$work_dir/sentinel" "$output" || fail "parser overwrote an existing report"
  done
done

expect_status 0 "$work_dir/non-short.log" "$work_dir/non_short.wasm" --strict --dead-code --retained
grep -Fq '0 of 1 functions are unreachable from the roots' "$work_dir/non-short.log" || fail "legal padded LEB module rejected or misanalysed"
expect_status 0 "$work_dir/direct.log" "$work_dir/direct.wasm" --strict --dead-code --retained
awk '$1 == 1 && $2 == 0 && $3 == 5 && $4 == 8 && $5 == 1 { found=1 } END { exit !found }' "$work_dir/direct.log" || fail "Commit 1 retained-size regression"
expect_status 3 "$work_dir/reference.log" "$work_dir/reference.wasm" --strict
grep -Fq 'call_ref: reference-call target analysis is not implemented.' "$work_dir/reference.log" || fail "Commit 2 diagnostic regression"
expect_status 0 "$work_dir/example.log" "$work_dir/example.wasm"
echo "Parser-boundary CLI regressions passed ($cases process cases)."
