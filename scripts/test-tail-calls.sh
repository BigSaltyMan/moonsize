#!/usr/bin/env bash
# Process-level tail-call regressions. Pass the built native CLI's path.
set -euo pipefail

if [[ $# -ne 1 || ! -f "$1" || ! -x "$1" ]]; then
  echo "usage: bash scripts/test-tail-calls.sh /path/to/moonsize-cli" >&2
  exit 1
fi
cli=$(cd -- "$(dirname -- "$1")" && printf '%s/%s' "$PWD" "$(basename -- "$1")")
work_dir=$(mktemp -d)
cleanup() {
  rm -f -- "$work_dir/"*
  rmdir -- "$work_dir"
}
trap cleanup EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

expect_status() {
  local expected=$1 log=$2 status
  shift 2
  # Expected failures must survive set -e, and must return exactly the contract's code.
  if "$cli" "$@" >"$log" 2>&1; then
    status=0
  else
    status=$?
  fi
  if [[ $status -ne $expected ]]; then
    cat "$log" >&2
    fail "expected exit $expected, got $status: $*"
  fi
}

expect_warning() {
  grep -Fq 'WARNING: 1 indirect call site has no resolvable target.' "$1" || fail "missing incomplete-graph warning"
  grep -Fq 'Dead-code and retained-size results may be inaccurate; do not use them as proof that a function can be removed.' "$1" || fail "missing removal warning"
}

expect_refusal() {
  expect_warning "$1"
  grep -Fq -- '--strict: refusing to report an incomplete call graph' "$1" || fail "missing strict refusal"
  if grep -Eq '^(SECTION|SIZE|Retained size|Dead code)|INDEX[[:space:]]+SIZE|HTML report written' "$1"; then
    fail "strict mode printed a normal analysis report"
  fi
}

# 39 bytes: exported function 0 uses return_call 1, function 1 returns normally.
printf '\x00asm\x01\x00\x00\x00\x01\x04\x01\x60\x00\x00\x03\x03\x02\x00\x00\x07\x07\x01\x03run\x00\x00\x0a\x09\x02\x04\x00\x12\x01\x0b\x02\x00\x0b' >"$work_dir/direct.wasm"
[[ $(wc -c <"$work_dir/direct.wasm") -eq 39 ]] || fail "direct fixture must be 39 bytes"

# A valid empty funcref table with no static candidates for return_call_indirect.
printf '\x00asm\x01\x00\x00\x00\x01\x04\x01\x60\x00\x00\x03\x02\x01\x00\x04\x04\x01\x70\x00\x01\x07\x07\x01\x03run\x00\x00\x0a\x09\x01\x07\x00\x41\x00\x13\x00\x00\x0b' >"$work_dir/indirect.wasm"

expect_status 0 "$work_dir/direct.log" "$work_dir/direct.wasm" --strict --dead-code --retained
grep -Fq '0 of 2 functions are unreachable from the roots' "$work_dir/direct.log" || fail "tail target reported dead"
grep -Fq '0 bytes (0.0% of file)' "$work_dir/direct.log" || fail "nonzero dead bytes"
# Retained columns: rank, index, own size, retained bytes, other functions freed.
awk '$1 == 1 && $2 == 0 && $3 == 5 && $4 == 8 && $5 == 1 { found=1 } END { exit !found }' "$work_dir/direct.log" || fail "root must retain 8 bytes and one other function"
awk '$1 == 2 && $2 == 1 && $3 == 3 && $4 == 3 && $5 == 0 { found=1 } END { exit !found }' "$work_dir/direct.log" || fail "target must retain its own 3 bytes"
if grep -Fq 'WARNING:' "$work_dir/direct.log"; then
  fail "direct tail call produced a warning"
fi

expect_status 0 "$work_dir/lax.log" "$work_dir/indirect.wasm" --dead-code --retained
expect_warning "$work_dir/lax.log"
grep -Fxq 'Dead code' "$work_dir/lax.log" || fail "non-strict mode omitted the report"
grep -Fxq 'Retained size' "$work_dir/lax.log" || fail "non-strict mode omitted retained sizes"

expect_status 3 "$work_dir/strict.log" "$work_dir/indirect.wasm" --strict --dead-code --retained
expect_refusal "$work_dir/strict.log"

for mode in call-graph html; do
  output="$work_dir/refused-$mode.$([[ $mode == html ]] && echo html || echo json)"
  [[ ! -e "$output" ]] || fail "output path must not already exist"
  expect_status 3 "$work_dir/$mode.log" "$work_dir/indirect.wasm" --strict "--$mode" "$output"
  expect_refusal "$work_dir/$mode.log"
  [[ ! -e "$output" ]] || fail "strict mode wrote $output"
done

echo 'Tail-call CLI regressions passed (5 process cases).'
