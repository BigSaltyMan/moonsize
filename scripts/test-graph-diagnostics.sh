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
# Dynamic-table fixtures mirror the complete modules in dynamic_tables_test.mbt.
# All are independently compiled by V8 before moonsize sees them.
node - "$cli" "$work_dir" <<'JS'
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const {spawnSync} = require('node:child_process');
const [cli, dir] = process.argv.slice(2);
const u32 = n => { const out=[]; do { const b=n&127; n>>>=7; out.push(b|(n?128:0)); } while(n); return out; };
const section = (id, p) => [id, ...u32(p.length), ...p];
function tableModule(writer=[], o={}) {
  const {tail=false, call_table=0, imported=false, mixed=false, exported=false, aliases=false,
    explicit=false, typed=false, static_targets=true, same_body=false, reference_global=false} = o;
  const tt = [...(typed ? [0x63,0x70] : [0x70]), 0,1];
  const entries = mixed ? [[1,109,1,97,0,0],[1,109,1,116,1,...tt],[1,109,1,98,0,0],[1,109,1,115,1,...tt]] :
    imported ? [[1,109,1,116,1,...tt]] : [];
  if(reference_global) entries.unshift([1,109,1,103,3,0x63,0x70,0]);
  const base=mixed?2:0, target=base+1;
  const first=explicit?[0x40,0,...tt,0xd0,0x70,0x0b]:tt;
  const exports=[[3,114,117,110,0,base]];
  if(exported) exports.push([3,116,97,98,1,call_table]);
  if(aliases) exports.push([5,97,108,105,97,115,1,call_table]);
  const active=[2,call_table,0x41,0,0x0b,0,1,target], passive=[1,0,1,target];
  const prefix=[0,97,115,109,1,0,0,0,...section(1,[1,0x60,0,0]),
    ...(entries.length?section(2,[entries.length,...entries.flat()]):[]),...section(3,[3,0,0,0]),
    ...section(4,[2,...first,...tt]),...section(7,[exports.length,...exports.flat()]),
    ...section(9,static_targets?[2,...active,...passive]:[1,...passive])];
  const call=[0x41,0,tail?0x13:0x11,0,call_table];
  const caller=[0,...call,...(same_body?writer:[]),0x0b], writing=[0,...(same_body?[]:writer),0x0b];
  const payload=[3,...u32(caller.length),...caller,2,0,0x0b,...u32(writing.length),...writing];
  const callerStart=prefix.length+1+u32(payload.length).length+1+u32(caller.length).length;
  const writerStart=callerStart+caller.length+3+u32(writing.length).length;
  return {bytes:Buffer.from([...prefix,...section(10,payload)]), callOffset:callerStart+3,
    writerStart:same_body?callerStart+1+call.length:writerStart+1, caller:base, writer:base+(same_body?0:2), target, o};
}
const set=[0x41,0,0xd0,0x70,0x26,0];
const spec = (writer, o, codes, writes=[]) => ({...tableModule(writer,o), codes, writes});
const mutation='runtime_table_mutation', host='imported_table_contents', exposed='exported_table_contents', init='unmodeled_table_initializer';
const fixtures={
  private:spec([],{},[]), readonly:spec([0x41,0,0x25,0,0x1a,0xfc,0x10,0,0x1a],{},[]),
  set:spec(set,{},[mutation],[['table.set',4]]),
  init:spec([0x41,0,0x41,0,0x41,1,0xfc,0x0c,1,0],{},[mutation],[['table.init',6]]),
  copy:spec([0x41,0,0x41,0,0x41,1,0xfc,0x0e,0,1],{},[mutation],[['table.copy',6]]),
  copy_source:spec([0x41,0,0x41,0,0x41,1,0xfc,0x0e,1,0],{},[]),
  grow:spec([0xd0,0x70,0x41,1,0xfc,0x0f,0,0x1a],{},[mutation],[['table.grow',4]]),
  fill:spec([0x41,0,0xd0,0x70,0x41,1,0xfc,0x11,0],{},[mutation],[['table.fill',6]]),
  other:spec([0x41,0,0xd0,0x70,0x26,1],{},[]),
  init_other:spec([0x41,0,0x41,0,0x41,1,0xfc,0x0c,1,1],{},[]),
  after:spec(set,{same_body:true},[mutation],[['table.set',4]]),
  tail:spec(set,{same_body:true,tail:true},[mutation],[['table.set',4]]),
  imported:spec([],{imported:true},[host]), exported:spec([],{exported:true},[exposed]),
  initializer:spec([],{explicit:true,typed:true},[init]),
  initialized_other:spec([],{explicit:true,typed:true,call_table:1},[]),
  combined:spec([...set,...set],{imported:true,exported:true,aliases:true},[host,exposed,mutation,mutation],[['table.set',4],['table.set',10]]),
  local_combined:spec(set,{explicit:true,exported:true},[exposed,init,mutation],[['table.set',4]]),
  empty:spec(set,{imported:true,static_targets:false},['no_static_table_targets',host,mutation],[['table.set',4]]),
  typed_global:spec([],{mixed:true,typed:true,reference_global:true,call_table:2},[]),
  mixed_write:spec([0x41,0,0xd0,0x70,0x26,2],{mixed:true,typed:true,call_table:2},[mutation],[['table.set',4]]),
};
for(let table=0;table<4;table++) fixtures['mixed'+table]=spec([],{mixed:true,typed:true,call_table:table},table<2?[host]:[]);
for(const [name, fixture] of Object.entries(fixtures)) {
  new WebAssembly.Module(fixture.bytes);
  fs.writeFileSync(path.join(dir,'dynamic-'+name+'.wasm'),fixture.bytes);
}
// The exact original MoonBit regression fixture, with a later same-body write.
new WebAssembly.Module(Buffer.from('0061736d0100000001040160000003030200000404017000010707010372756e00000907010041000b01010a12020d0041001100004100d20126000b02000b','hex'));
const longHeap=Buffer.from([0,97,115,109,1,0,0,0,...section(1,[...u32(129),...Array(129).fill([0x60,0,0]).flat()]),...section(4,[2,0x63,0x80,1,1,1,2,0x70,0,1])]);
new WebAssembly.Module(longHeap);
fs.writeFileSync(path.join(dir,'dynamic-heap.wasm'),longHeap);
const nonnull=Buffer.from([0,97,115,109,1,0,0,0,...section(1,[1,0x60,0,0]),...section(3,[2,0,0]),...section(4,[2,0x40,0,0x64,0,0,1,0xd2,1,0x0b,0x70,0,1]),...section(7,[1,3,114,117,110,0,0]),...section(9,[1,3,0,1,1]),...section(10,[2,7,0,0x41,0,0x11,0,0,0x0b,2,0,0x0b])]);
new WebAssembly.Module(nonnull);
fs.writeFileSync(path.join(dir,'dynamic-nonnull.wasm'),nonnull);
console.log(`V8 validated ${Object.keys(fixtures).length+3} complete dynamic-table fixtures (including typed references, initializers and tail calls).`);
let cases=0;
function run(expected,args) {
  const r=spawnSync(cli,args,{encoding:'utf8',timeout:5000,maxBuffer:4*1024*1024});
  const text=(r.stdout||'')+(r.stderr||'');
  fs.writeFileSync(path.join(dir,'dynamic-last.log'),text);
  assert.ifError(r.error); assert.equal(r.signal,null,text);
  assert.equal(r.status,expected,`${args.join(' ')}\n${text}`); cases++; return text;
}
function refusal(text) {
  assert.match(text,/--strict: refusing to report an incomplete call graph/);
  assert(!/INDEX\s+SIZE|HTML report written|WebAssembly section report/.test(text),text);
}
for(const [name,fixture] of Object.entries(fixtures)) {
  const input=path.join(dir,'dynamic-'+name+'.wasm');
  const strict=run(fixture.codes.length?3:0,[input,'--strict']);
  if(fixture.codes.length) refusal(strict);
  const output=path.join(dir,'dynamic-'+name+'.json');
  run(0,[input,'--call-graph',output]);
  const json=JSON.parse(fs.readFileSync(output,'utf8'));
  assert.equal(json.graph_complete,fixture.codes.length===0,name);
  assert.equal(json.indirect_sites.length,1,name);
  const call=json.indirect_sites[0];
  assert.deepEqual(call.candidates,fixture.o.static_targets===false?[]:[fixture.target],name);
  assert.equal(json.edges.length,fixture.o.static_targets===false?0:1,name);
  if(json.edges.length) { assert.equal(json.edges[0].caller,fixture.caller); assert.equal(json.edges[0].callee,fixture.target); }
  assert.deepEqual(json.diagnostics.map(d=>d.code).sort(),fixture.codes.slice().sort(),name);
  for(const d of json.diagnostics) {
    assert.equal(d.caller,fixture.caller); assert.equal(d.offset,fixture.callOffset);
    assert.equal(d.opcode,fixture.o.tail?'return_call_indirect':'call_indirect');
    assert.equal(d.type_index,0); assert.equal(d.table_index,fixture.o.call_table||0);
    if(d.source) { assert.notEqual(d.offset,d.source.offset); assert(d.source.offset>=0 && d.source.offset<fixture.bytes.length); }
    if([host,exposed,init].includes(d.code)) { assert.equal(d.source.caller,null); assert.equal(d.source.opcode,null); }
  }
  const writes=json.diagnostics.filter(d=>d.code===mutation);
  assert.deepEqual(writes.map(d=>d.source),fixture.writes.map(([opcode,relative])=>({caller:fixture.writer,offset:fixture.writerStart+relative,opcode})),name);
}
run(0,[path.join(dir,'dynamic-heap.wasm'),'--strict']);
refusal(run(3,[path.join(dir,'dynamic-nonnull.wasm'),'--strict']));
run(0,[path.join(dir,'dynamic-nonnull.wasm'),'--call-graph',path.join(dir,'dynamic-nonnull.json')]);
const unknownInitializer=JSON.parse(fs.readFileSync(path.join(dir,'dynamic-nonnull.json'),'utf8'));
assert.deepEqual(unknownInitializer.indirect_sites[0].candidates,[]);
assert.deepEqual(unknownInitializer.edges,[]);
assert.deepEqual(unknownInitializer.diagnostics.map(d=>d.code),['no_static_table_targets',init]);
const combined=run(0,[path.join(dir,'dynamic-combined.wasm'),'--dead-code','--retained']);
assert.match(combined,/4 analysis gaps/); assert.match(combined,/imported table contents/); assert.match(combined,/exported table contents/); assert.match(combined,/table.set at function 2, offset/);
const sentinel=Buffer.from('existing dynamic-table report must survive strict refusal\n');
for(const name of ['set','tail','imported','exported','initializer','combined']) {
  const input=path.join(dir,'dynamic-'+name+'.wasm');
  for(const ext of ['json','dot','html']) {
    const flag=ext==='html'?'--html':'--call-graph', output=path.join(dir,'dynamic-protected-'+name+'.'+ext);
    assert(!fs.existsSync(output)); refusal(run(3,[input,'--strict',flag,output])); assert(!fs.existsSync(output));
    fs.writeFileSync(output,sentinel); refusal(run(3,[input,'--strict',flag,output])); assert.deepEqual(fs.readFileSync(output),sentinel);
    if(ext!=='json') {
      run(0,[input,flag,output]); const text=fs.readFileSync(output,'utf8');
      assert.match(text,/do not use them as proof that a function can be removed/);
      const reason={set:'table.set',tail:'table.set',imported:'imported table contents',exported:'exported table contents',initializer:'explicit table initializer',combined:'table.set'}[name];
      assert(text.includes(reason),name);
    }
  }
}
// Malformed encodings remain input errors, distinct from analysis gaps.
for(const payload of [[1,0x40,1,0x70,0,1,0xd0,0x70,0x0b],[1,0x63,0x80],[1,0x40,0,0x70,0,1,0xd0,0x70]]) {
  const bytes=Buffer.from([0,97,115,109,1,0,0,0,...section(4,payload),0,2,1,120]);
  assert.equal(WebAssembly.validate(bytes),false);
  const input=path.join(dir,'dynamic-bad.wasm'); fs.writeFileSync(input,bytes);
  for(const strict of [[],['--strict']]) {
    const text=run(1,[input,...strict]); assert(!/WARNING:|WebAssembly section report/.test(text));
  }
}
fs.writeFileSync(path.join(dir,'dynamic-cases'),String(cases));
JS
cases=$((cases + $(cat "$work_dir/dynamic-cases")))
echo "Graph-diagnostic CLI regressions passed ($cases process cases)."
