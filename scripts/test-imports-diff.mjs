// Four analyzer calls only. Validate each of the three legal fixtures once.
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import {spawnSync} from 'node:child_process';

const cli=path.resolve(process.argv[2]||'_build/native/release/build/cmd/main/main.exe');
assert(fs.existsSync(cli),'Build the native CLI first.');
const parent=path.resolve('_build/imports-diff-verification');fs.mkdirSync(parent,{recursive:true});
const dir=fs.mkdtempSync(path.join(parent,'run-'));
const cat=(...items)=>Buffer.concat(items.map(b=>Buffer.from(b)));
const leb=n=>{const a=[];do{const v=n&127;n>>>=7;a.push(v|(n?128:0));}while(n);return Buffer.from(a);};
const wide=n=>{assert(n<128);return Buffer.from([n|128,0]);};
const name=(s,w=false)=>cat(w?wide(Buffer.byteLength(s)):leb(Buffer.byteLength(s)),Buffer.from(s));
const entry=(m,f,d,w=false)=>cat(name(m,w),name(f,w),d);
const sha=b=>crypto.createHash('sha256').update(b).digest('hex');
const header=Buffer.from('0061736d01000000010702600000600000','hex');
function module(entries,w=false){const payload=cat(w?wide(entries.length):leb(entries.length),...entries);
  return cat(header,[2],w?wide(payload.length):leb(payload.length),payload);}
const beforeEntries=[entry('env','same',[0,0]),entry('env','same',[0,0]),
  entry('env','grow',[1,112,0,0]),entry('env','flip',[0,0]),
  entry('a|b','c',[0,0]),entry('a','b|c',[0,0]),entry('','\n"雪',[3,127,0]),
  entry('env','gone',[3,126,0]),entry('env','stable',[2,0,0])];
const afterEntries=[beforeEntries[4],entry('env','same',[0,129,0],true),
  entry('env','grow',[1,112,1,0,1]),entry('env','flip',[3,127,0]),beforeEntries[5],
  entry('env','grow',[1,111,0,0]),entry('','\n"雪',[3,127,1]),
  entry('env','stable',[2,1,0,2]),entry('env','fresh',[4,0,0])];
const baseline=module(beforeEntries), current=module(afterEntries,true);
const reordered=module([8,6,5,4,3,2,1,0,7].map(i=>beforeEntries[i]));
for(const [label,data] of [['baseline',baseline],['current',current],['reordered',reordered]]){
  assert(WebAssembly.validate(data),'V8 rejected '+label+' import comparison fixture.'); // Each once.
  fs.writeFileSync(path.join(dir,label+'.wasm'),data,{flag:'wx'});
}
const before=path.join(dir,'baseline.wasm'), after=path.join(dir,'current.wasm');
const shuffle=path.join(dir,'reordered.wasm'), output=path.join(dir,'imports-diff.json');
const records=[];
function run(file,args,status){
  const p=spawnSync(cli,[file,'--baseline',before,'--diff-imports',...args],{cwd:dir,encoding:'utf8',timeout:10000});
  const log=(p.stdout||'')+(p.stderr||'');
  fs.writeFileSync(path.join(dir,'case-'+records.length+'.log'),log,{flag:'wx'});
  records.push({input:file,args:['--baseline',before,'--diff-imports',...args],status:p.status,error:p.error?.message||null});
  assert.ifError(p.error);assert.equal(p.signal,null);assert.equal(p.status,status,log);
  for(const [f,b]of [[before,baseline],[after,current],[shuffle,reordered]])assert.equal(sha(fs.readFileSync(f)),sha(b));
  return log;
}
const text=run(after,['--top','1'],0);
assert(text.includes('HOST IMPORT INVENTORY COMPARISON'));
assert(text.includes('Declarations: baseline 9, current 9; overlap 6, removed 3, added 3; delta 0'));
assert(text.includes('Inventory counts changed; type compatibility is not evaluated.'));
assert(text.includes('Baseline import section bytes: 101 B = header 2 B + count prefix 1 B + declarations 98 B'));
assert(text.includes('Current import section bytes: 112 B = header 3 B + count prefix 2 B + declarations 107 B'));
assert(text.includes('Delta import section bytes: 11 B = header 1 B + count prefix 1 B + declarations 9 B'));
assert(text.includes('IMPORT GROUPS: showing 1 of 10'));
assert(text.includes('"env"  "grow"  table  count_increased  1  2  1  0  1  1  14'));
assert(!text.includes('"env"  "fresh"  tag  added'));
const confirmation=run(after,['--imports','--imports-json',output,'--top','1'],0);
assert(confirmation.includes('Imports comparison written to '));assert(!confirmation.includes('HOST IMPORT INVENTORY COMPARISON'));
const saved=fs.readFileSync(output), report=JSON.parse(saved);
assert.equal(report.format,'moonsize-imports-diff');assert.equal(report.schema_version,1);
assert.equal(report.type_compatibility,'not_evaluated');assert.equal(report.inventory_changed,true);
assert.deepEqual(report.comparison_key,['module_name','field','kind']);assert.equal(report.delta_direction,'current - baseline');
assert.deepEqual(report.counts,{baseline_entry_count:9,current_entry_count:9,overlap_count:6,removed_count:3,added_count:3,count_delta:0});
for(const [side,data]of [[report.baseline,baseline],[report.current,current]]){
  assert.equal(side.format,'moonsize-imports');assert.equal(side.schema_version,1);
  assert.equal(side.file_size,data.length);assert.equal(side.sha256,sha(data));assert.equal(side.entries.length,9);
  assert.deepEqual(side.entries.map(e=>e.ordinal),[0,1,2,3,4,5,6,7,8]);
}
for(const s of [report.baseline.ledger,report.current.ledger,report.delta]){
  assert.equal(s.import_section_total_bytes,s.section_header_bytes+s.count_prefix_bytes+s.entry_bytes);
  assert.equal(s.entry_bytes,s.module_name_encoding_bytes+s.field_name_encoding_bytes+s.descriptor_bytes);
  assert.equal(s.module_name_encoding_bytes,s.module_length_prefix_bytes+s.module_utf8_bytes);
  assert.equal(s.field_name_encoding_bytes,s.field_length_prefix_bytes+s.field_utf8_bytes);
}
for(const k of Object.keys(report.delta))assert.equal(report.delta[k],report.current.ledger[k]-report.baseline.ledger[k]);
assert.equal(report.groups.length,10);
assert.equal(report.groups.reduce((n,g)=>n+g.baseline_entry_bytes,0),98);
assert.equal(report.groups.reduce((n,g)=>n+g.current_entry_bytes,0),107);
assert.equal(report.groups.reduce((n,g)=>n+g.entry_bytes_delta,0),9);
const matched=[new Set(),new Set()];
for(const g of report.groups){
  assert.equal(g.overlap_count,Math.min(g.baseline_count,g.current_count));
  assert.equal(g.removed_count,g.baseline_count-g.overlap_count);assert.equal(g.added_count,g.current_count-g.overlap_count);
  assert.equal(g.count_delta,g.current_count-g.baseline_count);assert.equal(g.entry_bytes_delta,g.current_entry_bytes-g.baseline_entry_bytes);
  for(const [i,side,ordinals,total]of [[0,report.baseline,g.baseline_ordinals,g.baseline_entry_bytes],[1,report.current,g.current_ordinals,g.current_entry_bytes]]){
    assert.deepEqual(ordinals,[...ordinals].sort((a,b)=>a-b));let bytes=0;
    for(const ordinal of ordinals){assert(!matched[i].has(ordinal));matched[i].add(ordinal);const e=side.entries[ordinal];
      assert.equal(e.module,g.module);assert.equal(e.field,g.field);assert.equal(e.kind,g.kind);bytes+=e.encoding.size;}
    assert.equal(bytes,total);
  }
}
assert.equal(matched[0].size,9);assert.equal(matched[1].size,9);
const lex=(a,b)=>a<b?-1:a>b?1:0;
assert.deepEqual(report.groups,[...report.groups].sort((a,b)=>(b.added_count+b.removed_count)-(a.added_count+a.removed_count)||Math.abs(b.entry_bytes_delta)-Math.abs(a.entry_bytes_delta)||lex(a.module,b.module)||lex(a.field,b.field)||lex(a.kind,b.kind)));
assert.deepEqual(report.groups[0].current_ordinals,[2,5]);
assert.equal(report.groups.filter(g=>(g.module==='a|b'&&g.field==='c')||(g.module==='a'&&g.field==='b|c')).length,2);
assert.equal(report.groups.filter(g=>g.field==='flip').length,2);
assert.equal(report.baseline.entries[0].type_index,0);assert.equal(report.current.entries[1].type_index,1);
assert.equal(report.baseline.entries[6].mutability,0);assert.equal(report.current.entries[6].mutability,1);
assert.equal(report.current.entries[5].value_type,'externref');assert.equal(report.baseline.entries[2].value_type,'funcref');
assert.deepEqual(report.current.entries[7].limits,{flags:1,minimum:0,maximum:2});
const noCountChanges=run(shuffle,['--top','1'],0);
assert(noCountChanges.includes('Declarations: baseline 9, current 9; overlap 9, removed 0, added 0; delta 0'));
assert(noCountChanges.includes('No changes to names, kinds or declaration counts; type compatibility is not evaluated.'));
assert(noCountChanges.includes('Delta import section bytes: 0 B = header 0 B + count prefix 0 B + declarations 0 B'));
assert(noCountChanges.includes('IMPORT GROUPS: showing 1 of 8'));
const refused=run(after,['--imports-json',output],1);
assert(refused.includes('output already exists'));assert(!refused.includes('Imports comparison written to '));
assert.deepEqual(fs.readFileSync(output),saved);
fs.writeFileSync(path.join(dir,'results.json'),JSON.stringify({
  baseline_size:baseline.length,baseline_sha256:sha(baseline),current_size:current.length,current_sha256:sha(current),
  reordered_size:reordered.length,reordered_sha256:sha(reordered),cli_sha256:sha(fs.readFileSync(cli)),node:process.version,
  independent_validation:'Three legal fixtures, each validated by Node/V8 once; no instantiation/execution',
  counts:report.counts,delta:report.delta,records,
},null,2)+'\n',{flag:'wx'});
console.log('Imports-diff CLI regressions passed (4 process cases, 3 independently validated fixtures). Evidence: '+dir);
