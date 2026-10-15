#!/usr/bin/env bash
# Run in Git Bash or Linux. Node provides timeouts and independent V8 validation.
set -euo pipefail
if [[ $# -ne 1 || ! -f "$1" || ! -x "$1" ]]; then
  echo 'usage: bash scripts/test-module-structure.sh /path/to/moonsize-cli' >&2
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
  # Expected input failures are captured explicitly; set -e never treats an
  # arbitrary nonzero status, signal, timeout or launch error as a passing case.
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

no_report() {
  if grep -Eq 'WARNING:|refusing to report|^(Retained size|Dead code)|INDEX[[:space:]]+SIZE|SECTION[[:space:]]|HTML report written|Size comparison' "$1"; then
    fail "structure failure emitted a warning or partial report: $1"
  fi
}

node - "$work_dir" "$repo" <<'JS'
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const [dir, repo] = process.argv.slice(2);
const header = '0061736d01000000';
const type = '010401600000';
const one = '03020100';
const body = '0a040102000b';
// Every bad fixture isolates its intended defect: order and count failures
// use otherwise complete, correctly bounded payloads.
const bad = {
  version0: ['0061736d00000000', 'unsupported WebAssembly version 0 at offset 4'],
  version2: ['0061736d02000000', 'unsupported WebAssembly version 2 at offset 4'],
  version_max: ['0061736dffffffff', 'unsupported WebAssembly version 4294967295 at offset 4'],
  duplicate_type: [header + '010100010100', 'duplicate type section at offset 11'],
  duplicate_code: [header + '0a01000a0100', 'duplicate code section at offset 11'],
  duplicate_start: [header + type + one + '080100080100' + body, 'duplicate start section at offset 21'],
  duplicate_datacount: [header + '0c01000c0100', 'duplicate datacount section at offset 11'],
  import_order: [header + '030100020100', 'import section appears after function section at offset 11'],
  custom_order: [header + '03010000020178020100', 'import section appears after function section at offset 15'],
  datacount_order: [header + '0a01000c0100', 'datacount section appears after code section at offset 11'],
  tag_order: [header + type + '0601000d03010000', 'tag section appears after global section at offset 17'],
  missing_code: [header + type + one, 'function/code count mismatch: 1 declaration, 0 bodies'],
  missing_function: [header + body, 'function/code count mismatch: 0 declarations, 1 body'],
  empty_code: [header + type + one + '0a0100', 'function/code count mismatch: 1 declaration, 0 bodies'],
  empty_function: [header + type + '030100' + body, 'function/code count mismatch: 0 declarations, 1 body'],
  unequal: [header + type + '0303020000' + body, 'function/code count mismatch: 2 declarations, 1 body'],
  trailing_function: [header + '03020000', 'unexpected trailing bytes in function section at offset 11'],
  trailing_code: [header + '0a020000', 'unexpected trailing bytes in code section at offset 11'],
  missing_type_index: [header + type + '03020200', 'unexpected end of input at offset 18'],
  body_bounds: [header + type + one + '0a03010300', 'unexpected end of input at offset 22'],
};
for (const [name, [hex]] of Object.entries(bad)) {
  const bytes = Buffer.from(hex, 'hex');
  assert.equal(WebAssembly.validate(bytes), false, `malformed module unexpectedly valid: ${name}`);
  fs.writeFileSync(path.join(dir, name + '.wasm'), bytes);
}
fs.writeFileSync(path.join(dir, 'bad-cases.txt'), Object.entries(bad).map(([name, [, reason]]) => `${name}|${reason}`).join('\n') + '\n');
const valid = {
  empty: header,
  empty_function: header + '030100',
  empty_code: header + '0a0100',
  equal_two: header + type + '03030200000a070202000b02000b',
  same_custom: header + '0002017800020178',
  interleaved_custom: header + '0002017801010000020178030100000201780a010000020178',
  datacount: header + '0c01000a0100',
  imported: header + type + '020701016d01660000' + one + body,
  imported_only: header + type + '020701016d01660000',
  tag: header + type + '0501000d03010000060100',
};
for (const [name, hex] of Object.entries(valid)) {
  const bytes = Buffer.from(hex, 'hex');
  // V8's exception-handling capability is checked separately. A missing
  // feature is reported as a validator limitation, never as an illegal sample.
  if (name === 'tag' && typeof WebAssembly.Tag !== 'function') {
    console.log('V8 lacks WebAssembly.Tag; independent tag validation unavailable.');
  } else {
    new WebAssembly.Module(bytes);
  }
  fs.writeFileSync(path.join(dir, 'valid_' + name + '.wasm'), bytes);
}
const example = fs.readFileSync(path.join(repo, 'examples', 'fib.wasm'));
new WebAssembly.Module(example);
fs.writeFileSync(path.join(dir, 'valid_example.wasm'), example);
fs.writeFileSync(path.join(dir, 'valid-cases.txt'), [...Object.keys(valid), 'example'].join('\n') + '\n');
console.log(`V8 cross-check: ${Object.keys(bad).length} malformed, ${Object.keys(valid).length + 1} valid complete modules (tag capability checked separately).`);
JS

while IFS='|' read -r name reason; do
  for mode in plain strict; do
    flags=()
    [[ $mode != strict ]] || flags+=(--strict)
    log="$work_dir/$name-$mode.log"
    expect_status 1 "$log" "$work_dir/$name.wasm" "${flags[@]}" --dead-code --retained
    grep -Fq "$reason" "$log" || fail "wrong error category or position: $name"
    no_report "$log"
    # Baselines go through the same parser before any normal output.
    log="$work_dir/baseline-$name-$mode.log"
    expect_status 1 "$log" "$work_dir/valid_empty.wasm" --baseline "$work_dir/$name.wasm" "${flags[@]}" --dead-code --retained
    grep -Fq "$reason" "$log" || fail "wrong baseline error: $name"
    no_report "$log"
  done
done <"$work_dir/bad-cases.txt"

# All error categories protect nonexistent and existing JSON/DOT/HTML paths,
# for both the current input and a bad baseline, in plain and strict modes.
printf '%s\n' 'existing report must survive structure failure' >"$work_dir/sentinel"
for name in version2 duplicate_type import_order unequal trailing_function trailing_code; do
  for source in current baseline; do
    input="$work_dir/$name.wasm"
    baseline=()
    if [[ $source == baseline ]]; then
      input="$work_dir/valid_empty.wasm"
      baseline=(--baseline "$work_dir/$name.wasm")
    fi
    for format in json dot html; do
      output_mode=--call-graph
      [[ $format != html ]] || output_mode=--html
      for strict in no yes; do
        flags=()
        [[ $strict != yes ]] || flags+=(--strict)
        output="$work_dir/$name-$source-$strict.$format"
        log="$work_dir/export.log"
        [[ ! -e "$output" ]] || fail "report path unexpectedly exists"
        expect_status 1 "$log" "$input" "${baseline[@]}" "${flags[@]}" "$output_mode" "$output"
        no_report "$log"
        [[ ! -e "$output" ]] || fail 'structure failure created a report'
        cp -- "$work_dir/sentinel" "$output"
        expect_status 1 "$log" "$input" "${baseline[@]}" "${flags[@]}" "$output_mode" "$output"
        no_report "$log"
        cmp -s -- "$work_dir/sentinel" "$output" || fail 'structure failure overwrote a report'
      done
    done
  done
done

while IFS= read -r name; do
  expect_status 0 "$work_dir/valid-$name.log" "$work_dir/valid_$name.wasm" --strict --dead-code --retained
done <"$work_dir/valid-cases.txt"
echo "Module-structure CLI regressions passed ($cases process cases)."
