#!/usr/bin/env bash
# Git Bash/Linux; fixture identities and expected matches are specified explicitly.
set -euo pipefail
if [[ $# -ne 1 || ! -f "$1" || ! -x "$1" ]]; then
  echo 'usage: bash scripts/test-function-diff.sh /path/to/moonsize-cli' >&2
  exit 1
fi
command -v node >/dev/null || { echo 'Node.js is required.' >&2; exit 1; }
cli=$(cd -- "$(dirname -- "$1")" && printf '%s/%s' "$PWD" "$(basename -- "$1")")
work_dir=$(mktemp -d)
cleanup() { rm -f -- "$work_dir/"*; rmdir -- "$work_dir"; }
trap cleanup EXIT
node - "$cli" "$work_dir" <<'JS'
const fs = require('node:fs'), path = require('node:path');
const assert = require('node:assert/strict');
const { spawnSync } = require('node:child_process');
const [cli, dir] = process.argv.slice(2);
let cases = 0, fixtures = 0;
const header = Buffer.from('0061736d01000000', 'hex');
const leb = n => { const a=[]; do { const b=n&127; n>>>=7; a.push(b|(n?128:0)); } while(n); return Buffer.from(a); };
const cat = (...b) => Buffer.concat(b);
const section = (id,payload) => cat(Buffer.from([id]), leb(payload.length), payload);
const nameBytes = text => cat(leb(Buffer.byteLength(text)), Buffer.from(text));
function module(defs, imported=0) {
  const parts = [header, section(1,Buffer.from([1,96,0,0]))];
  if (imported) parts.push(section(2, cat(leb(imported), ...Array.from({length:imported},()=>Buffer.from([1,109,1,102,0,0])))));
  parts.push(section(3, cat(leb(defs.length),Buffer.alloc(defs.length))));
  const bodies = defs.map(([name,n])=> { const body=cat(Buffer.from([0]),Buffer.alloc(n,1),Buffer.from([11])); return cat(leb(body.length),body); });
  const code = section(10,cat(leb(defs.length),...bodies)); parts.push(code);
  const entries = defs.flatMap(([name],i)=>name===null?[]:[cat(leb(i+imported),nameBytes(name))]);
  if(entries.length) parts.push(section(0,cat(nameBytes('name'),section(1,cat(leb(entries.length),...entries)))));
  return {data:cat(...parts), stats:defs.map(([name,n],i)=>({name,index:i+imported,size:bodies[i].length})), code:code.length};
}
const empty = {data:header,stats:[],code:0};
const named = module([['p/a',0],['p/b',4]]);
const reordered = module([['p/b',4],['p/a',0]]);
const shifted = module([['p/b',4],['p/a',0]],2);
const growingBefore = module([['p/grow',0],['p/shrink',5],['old/gone',0]]);
const growingAfter = module([['p/grow',4],['p/shrink',2],['new/added',1]]);
const dup = module([['dup',0],['dup',2]]), single = module([['dup',1]]);
const dupAfter = module([['dup',1],['dup',3]]);
const missing = module([[null,0],['',2],['(unnamed)',1]]);
const mangled = '_M0FPB7printlnGsE';
const indirect = {data:Buffer.from('0061736d01000000010401600000030201000404017000010a0901070041001300000b','hex'),stats:[{name:null,index:0,size:8}],code:11};
const comparisons = [
  ['self',named,named,[['matched',0,0,'p/a'],['matched',1,1,'p/b']]],
  ['reorder',named,reordered,[['matched',0,1,'p/a'],['matched',1,0,'p/b']]],
  ['imports',named,shifted,[['matched',0,3,'p/a'],['matched',1,2,'p/b']]],
  ['changes',growingBefore,growingAfter,[['matched',0,0,'p/grow'],['matched',1,1,'p/shrink'],['removed-symbol',2,null,'old/gone'],['added-symbol',null,2,'new/added']]],
  ['one-duplicate',dup,single,[['ambiguous',0,null,'dup'],['ambiguous',1,null,'dup'],['ambiguous',null,0,'dup']]],
  ['both-duplicate',dup,dupAfter,[['ambiguous',0,null,'dup'],['ambiguous',1,null,'dup'],['ambiguous',null,0,'dup'],['ambiguous',null,1,'dup']]],
  ['absent-duplicate',dup,empty,[['ambiguous',0,null,'dup'],['ambiguous',1,null,'dup']]],
  ['missing',missing,missing,[['missing-symbol',0,null,null],['missing-symbol',1,null,null],['missing-symbol',null,0,null],['missing-symbol',null,1,null],['matched',2,2,'(unnamed)']]],
  ['display-collision',module([[mangled,0]]),module([['println',0]]),[['removed-symbol',0,null,mangled],['added-symbol',null,0,'println']]],
  ['prefix',module([['f',125]]),module([['f',126]]),[['matched',0,0,'f']]],
  ['empty-code',empty,{data:cat(header,Buffer.from([10,1,0])),stats:[],code:3},[]],
  ['incomplete-baseline',indirect,empty,[['missing-symbol',0,null,null]]],
  ['unicode',module([['包/函数',0]]),module([['包/函数',1]]),[['matched',0,0,'包/函数']]],
];
function write(label,fixture) {
  const file=path.join(dir,label+'.wasm');
  assert.ok(WebAssembly.validate(fixture.data),'V8 rejected '+label);
  fs.writeFileSync(file,fixture.data); fixtures++;
  return file;
}
function run(args,expected=0) {
  const r=spawnSync(cli,args,{encoding:'utf8',timeout:5000});
  assert.ifError(r.error); assert.equal(r.signal,null);
  assert.equal(r.status,expected,r.stdout+r.stderr); cases++;
  return r.stdout+r.stderr;
}
const signed=n=>n>0?'+'+n:String(n);
const total=f=>f.stats.reduce((s,x)=>s+x.size,0);
const rows=text=>[...text.matchAll(/^  (matched|added-symbol|removed-symbol|ambiguous|missing-symbol)\s+(\d+|-)\s+(\d+|-)\s+(\d+)\s+(\d+)\s+([+-]?\d+)\s+(.+)$/gm)].map(r=>[r[1],r[2]==='-'?null:+r[2],r[3]==='-'?null:+r[3],+r[4],+r[5],+r[6],r[7]==='<missing symbol>'?null:JSON.parse(r[7])]);
const lexical=(a,b)=>a===b?0:a<b?-1:1;
function check(text,before,after,expected) {
  for(const heading of ['FUNCTION SIZE CHANGES','PACKAGE SIZE CHANGES','MATCHING SUMMARY','CODE OVERHEAD']) assert.ok(text.includes(heading));
  const sizes=(fixture,index)=>index===null?0:fixture.stats.find(s=>s.index===index).size;
  const wanted=expected.map(([status,b,c,name])=>[status,b,c,sizes(before,b),sizes(after,c),sizes(after,c)-sizes(before,b),name]);
  wanted.sort((a,b)=>Math.abs(b[5])-Math.abs(a[5])||lexical(a[6],b[6])||lexical(a[0],b[0])||(a[1]??-1)-(b[1]??-1)||(a[2]??-1)-(b[2]??-1));
  const actual=rows(text);
  assert.deepEqual(actual,wanted);
  assert.equal(actual.reduce((s,r)=>s+r[5],0),total(after)-total(before));
  const packageText=text.split('PACKAGE SIZE CHANGES')[1].split('MATCHING SUMMARY')[0];
  const packages=[...packageText.matchAll(/^\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+([+-]?\d+)\s+(".*")$/gm)];
  assert.equal(packages.reduce((s,r)=>s+Number(r[1]),0),before.stats.length);
  assert.equal(packages.reduce((s,r)=>s+Number(r[2]),0),after.stats.length);
  assert.equal(packages.reduce((s,r)=>s+Number(r[3]),0),total(before));
  assert.equal(packages.reduce((s,r)=>s+Number(r[4]),0),total(after));
  for(const row of packages) assert.equal(+row[5],+row[4]-row[3]);
  const summary=text.split('MATCHING SUMMARY')[1].split('CODE OVERHEAD')[0];
  for(const status of ['matched','added-symbol','removed-symbol','ambiguous','missing-symbol']) {
    const expectedRows=wanted.filter(r=>r[0]===status);
    const r=summary.match(new RegExp('^  '+status+'\\s+(\\d+)\\s+(\\d+)\\s+(\\d+)\\s+(\\d+)$','m'));
    assert.ok(r,status);
    assert.deepEqual(r.slice(1).map(Number),[expectedRows.filter(r=>r[1]!==null).length,expectedRows.filter(r=>r[2]!==null).length,expectedRows.reduce((s,r)=>s+r[3],0),expectedRows.reduce((s,r)=>s+r[4],0)]);
  }
  const overhead=text.split('CODE OVERHEAD')[1];
  for(const [label,b,c] of [['code section',before.code,after.code],['function encoding',total(before),total(after)],['code overhead',before.code-total(before),after.code-total(after)]]) {
    const line=overhead.split('\n').find(line=>line.trimStart().startsWith(label+' '));
    assert.ok(line,label); assert.deepEqual(line.trim().slice(label.length).trim().split(/\s+/),[String(b),String(c),signed(c-b)]);
  }
  const fileLine=text.split('FUNCTION SIZE CHANGES')[1].split('\n').find(line=>/^  file\s/.test(line));
  assert.deepEqual(fileLine.trim().split(/\s+/).slice(1),[String(before.data.length),String(after.data.length),signed(after.data.length-before.data.length)]);
}
for(const [label,before,after,expected] of comparisons) {
  const b=write(label+'-before',before), a=write(label+'-after',after);
  check(run([a,'--baseline',b,'--diff-functions','--top','1000']),before,after,expected);
}
const b=write('base',named), a=write('current',module([['p/a',3],['p/b',4]]));
const delta=fs.statSync(a).size-fs.statSync(b).size;
assert.ok(delta>0);
run([a,'--baseline',b,'--diff-functions','--max-size',delta+'B']);
assert.ok(run([a,'--baseline',b,'--diff-functions','--max-size',(delta-1)+'B'],3).includes('over the baseline'));
const m=write('unnamed-base',module([[null,0]])), n=write('unnamed-current',module([[null,3]]));
const md=fs.statSync(n).size-fs.statSync(m).size;
run([n,'--baseline',m,'--diff-functions','--max-size',md+'B']);
run([n,'--baseline',m,'--diff-functions','--max-size',(md-1)+'B'],3);
const summary=run([n,'--baseline',m,'--diff-functions','--top','0']);
assert.ok(summary.includes('MATCHING SUMMARY')); assert.ok(summary.includes('CODE OVERHEAD'));
assert.ok(summary.includes('missing-symbol')); assert.ok(summary.includes('detail rankings hidden'));
assert.ok(!summary.includes('RAW_SYMBOL')); assert.ok(!summary.includes('BASE_FUNCS'));
const combined=run([a,'--baseline',b,'--diff-functions','--compress','--retained','--dead-code','--strict','--top','1']);
assert.equal(rows(combined).length,1); assert.ok(combined.includes('COMPRESSED SIZE')); assert.ok(combined.includes('Retained size'));
assert.ok(!run([a,'--baseline',b]).includes('FUNCTION SIZE CHANGES'));
assert.ok(!run(['absent.wasm','--diff-functions'],2).includes('cannot read'));
for(const [flag,extension] of [['--html','html'],['--call-graph','json'],['--call-graph','dot']]) {
  for(const exists of [false,true]) {
    const out=path.join(dir,'protected-'+exists+'.'+extension);
    if(exists) fs.writeFileSync(out,'preserve this report');
    run(['absent.wasm','--baseline','absent-baseline','--diff-functions',flag,out],2);
    if(exists) assert.equal(fs.readFileSync(out,'utf8'),'preserve this report'); else assert.ok(!fs.existsSync(out));
  }
}
const malformed=path.join(dir,'malformed.wasm'); fs.writeFileSync(malformed,Buffer.from('0061736d02000000','hex'));
const badImports=path.join(dir,'bad-imports.wasm'); fs.writeFileSync(badImports,cat(header,Buffer.from([2,1,1])));
for(const args of [[a,'--baseline',malformed],[malformed,'--baseline',b],[a,'--baseline','missing-baseline.wasm'],[a,'--baseline',badImports]]) {
  const text=run([...args,'--diff-functions'],1);
  assert.ok(!/FUNCTION SIZE CHANGES|WebAssembly section report|SIZE COMPARISON|Top \d/.test(text),'partial report after preparation failure');
}
const i=write('indirect',indirect);
const strict=run([i,'--baseline',b,'--diff-functions','--strict'],3);
assert.ok(strict.includes('--strict: refusing')); assert.ok(!strict.includes('FUNCTION SIZE CHANGES'));
assert.ok(run([i,'--baseline',b,'--diff-functions']).includes('FUNCTION SIZE CHANGES'));
// A non-code change must still consume the whole-file budget, with no function delta.
const extra={...named,data:cat(named.data,section(0,cat(nameBytes('extra'),Buffer.from([1,2,3]))))};
const e=write('non-code-growth',extra);
assert.ok(run([e,'--baseline',b,'--diff-functions','--max-size','0B'],3).includes('over the baseline'));
check(run([e,'--baseline',b,'--diff-functions','--top','1000']),named,extra,[['matched',0,0,'p/a'],['matched',1,1,'p/b']]);
console.log(`Function-diff CLI regressions passed (${cases} process cases, ${fixtures} V8-validated modules).`);
JS
