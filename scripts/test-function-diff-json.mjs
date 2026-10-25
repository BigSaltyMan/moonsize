// Four analyzer calls; validate each legal input once, without execution.
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import {spawnSync} from 'node:child_process';

const cli=path.resolve(process.argv[2]||'_build/native/release/build/cmd/main/main.exe');
assert(fs.existsSync(cli),'Build the native CLI first.');
const parent=path.resolve('_build/function-diff-json-verification');fs.mkdirSync(parent,{recursive:true});
const dir=fs.mkdtempSync(path.join(parent,'run-'));
const cat=(...items)=>Buffer.concat(items.map(item=>Buffer.from(item)));
const leb=n=>{const out=[];do{let b=n&127;n=Math.floor(n/128);if(n)b|=128;out.push(b);}while(n);return Buffer.from(out);};
const section=(id,payload)=>cat([id],leb(payload.length),payload);
const sha=data=>crypto.createHash('sha256').update(data).digest('hex');
const special='pkg/keep"\n雪';
function moduleBytes(entries,wide=false){
  const prefix=cat(Buffer.from('0061736d01000000010401600000020701016d01660000','hex'),section(3,cat(leb(entries.length),entries.map(()=>0))));
  const count=wide?[entries.length|128,0]:leb(entries.length);
  const payload=cat(count,...entries.map(([,n])=>cat(leb(n+2),[0],Buffer.alloc(n,1),[11])));
  const header=cat([10],wide?[payload.length|128,0]:leb(payload.length));
  let cursor=prefix.length+header.length+count.length;
  const stats=entries.map(([raw,n],i)=>{const stat={index:i+1,name:raw??'(unnamed)',raw_name:raw,module_name:raw?raw.slice(0,raw.lastIndexOf('/')):'(unnamed)',
    offset:cursor,body_size:n+2,prefix_size:1,total_size:n+3};cursor+=stat.total_size;return stat;});
  const names=entries.flatMap(([name],i)=>name===null?[]:[cat(leb(i+1),leb(Buffer.byteLength(name)),Buffer.from(name))]);
  const bytes=cat(prefix,header,payload,section(0,cat([4],Buffer.from('name'),section(1,cat(leb(names.length),...names)))),wide?section(0,cat([3],Buffer.from('pad'),[0])):[]);
  return {bytes,stats};
}
const baseline=moduleBytes([[special,0],['old/gone',1],['dup/shared',0],['dup/shared',2],[null,1]]);
const current=moduleBytes([['new/added',2],['dup/shared',1],[special,2],['dup/shared',0],[null,0],[null,1]],true);
assert(WebAssembly.validate(baseline.bytes),'Node/V8 rejected baseline fixture.');
assert(WebAssembly.validate(current.bytes),'Node/V8 rejected current fixture.'); // Once each.
assert(current.bytes.length>baseline.bytes.length,'Growth gate fixture must grow.');
const before=path.join(dir,'before.wasm'),after=path.join(dir,'after.wasm'),bad=path.join(dir,'bad-baseline.wasm');
const output=path.join(dir,'function-diff.json'),gateOutput=path.join(dir,'growth.json'),badOutput=path.join(dir,'bad.json');
fs.writeFileSync(before,baseline.bytes,{flag:'wx'});fs.writeFileSync(after,current.bytes,{flag:'wx'});
const badBytes=Buffer.from('0061736d02000000','hex');fs.writeFileSync(bad,badBytes,{flag:'wx'});
const records=[];
function run(args,status){
  const p=spawnSync(cli,[after,...args],{cwd:dir,encoding:'utf8',timeout:10000});
  const log=(p.stdout||'')+(p.stderr||'');fs.writeFileSync(path.join(dir,'case-'+records.length+'.log'),log,{flag:'wx'});
  records.push({args,status:p.status,error:p.error?.message||null});
  assert.ifError(p.error);assert.equal(p.signal,null);assert.equal(p.status,status,log);
  for(const [file,bytes]of [[before,baseline.bytes],[after,current.bytes],[bad,badBytes]])assert.equal(sha(fs.readFileSync(file)),sha(bytes));
  return log;
}
const pair=['--baseline',before,'--diff-functions-json'];
const text=run([...pair,output,'--top','1'],0);
assert(text.includes('Function and package comparison written to '));assert(text.includes('FUNCTION SIZE CHANGES'));assert(text.includes('MATCHING SUMMARY'));
assert(/^\s*file\s+112\s+128\s+\+16\s*$/m.test(text));
assert(/^\s*function encoding\s+19\s+24\s+\+5\s*$/m.test(text));
assert(/^\s*code section\s+22\s+29\s+\+7\s*$/m.test(text));
assert(/^\s*code overhead\s+3\s+5\s+\+2\s*$/m.test(text));
assert(/^\s*matched\s+1\s+1\s+3\s+5\s*$/m.test(text));
assert(!text.includes('"schema_version"'));
const saved=fs.readFileSync(output),report=JSON.parse(saved),b=report.baseline,c=report.current,d=report.delta,m=report.matching;
assert.equal(report.format,'moonsize-function-diff');assert.equal(report.schema_version,1);
assert.deepEqual(Object.keys(report).sort(),['format','schema_version','baseline','current','delta','matching','functions','packages','scope'].sort());
assert.deepEqual(b,{sha256:sha(baseline.bytes),file_size:112,code:{code_size:22,function_count:5,function_bytes:19,overhead:3}});
assert.deepEqual(c,{sha256:sha(current.bytes),file_size:128,code:{code_size:29,function_count:6,function_bytes:24,overhead:5}});
assert.deepEqual(d,{file_bytes:16,code_bytes:7,function_bytes:5,code_overhead_bytes:2,non_code_bytes:9});
const expectedMatching={matched_baseline:{count:1,bytes:3},matched_current:{count:1,bytes:5},added_symbols:{count:1,bytes:5},removed_symbols:{count:1,bytes:4},
  ambiguous_baseline:{count:2,bytes:8},ambiguous_current:{count:2,bytes:7},missing_baseline:{count:1,bytes:4},missing_current:{count:2,bytes:7},matched_delta:2};
assert.deepEqual(m,expectedMatching);assert.equal(report.functions.length,10);assert.equal(report.packages.length,5);
const counts=new Map(),seen={baseline:new Set(),current:new Set()};
for(const row of report.functions){
  counts.set(row.status,(counts.get(row.status)||0)+1);
  for(const [key,fixture]of [['baseline',baseline],['current',current]]){
    const stat=row[key];if(stat===null)continue;
    assert(!seen[key].has(stat.index));seen[key].add(stat.index);assert.deepEqual(stat,fixture.stats[stat.index-1]);
  }
  assert.equal(row.delta,(row.current?.total_size||0)-(row.baseline?.total_size||0));
  if(row.status==='matched'){assert.equal(row.baseline.index,1);assert.equal(row.current.index,3);assert.equal(row.raw_name,special);}
  else {assert(row.baseline===null||row.current===null);}
  if(row.status==='missing-symbol'){assert.equal(row.raw_name,null);assert.equal((row.baseline||row.current).raw_name,null);}
}
assert.deepEqual(Object.fromEntries([...counts].sort()),{'added-symbol':1,ambiguous:4,matched:1,'missing-symbol':3,'removed-symbol':1});
assert.deepEqual([...seen.baseline].sort((a,b)=>a-b),[1,2,3,4,5]);assert.deepEqual([...seen.current].sort((a,b)=>a-b),[1,2,3,4,5,6]);
assert.deepEqual(report.packages,[
  {name:'new',baseline_functions:0,current_functions:1,baseline_size:0,current_size:5,delta:5},
  {name:'old',baseline_functions:1,current_functions:0,baseline_size:4,current_size:0,delta:-4},
  {name:'(unnamed)',baseline_functions:1,current_functions:2,baseline_size:4,current_size:7,delta:3},
  {name:'pkg',baseline_functions:1,current_functions:1,baseline_size:3,current_size:5,delta:2},
  {name:'dup',baseline_functions:2,current_functions:2,baseline_size:8,current_size:7,delta:-1},
]);
for(const [side,coverage]of [['baseline',['matched_baseline','removed_symbols','ambiguous_baseline','missing_baseline']],['current',['matched_current','added_symbols','ambiguous_current','missing_current']]]){
  assert.equal(report[side].code.function_bytes,coverage.reduce((n,k)=>n+m[k].bytes,0));assert.equal(report[side].code.function_count,coverage.reduce((n,k)=>n+m[k].count,0));
  assert.equal(report[side].code.code_size,report[side].code.function_bytes+report[side].code.overhead);
  assert.equal(report.packages.reduce((n,p)=>n+p[side+'_size'],0),report[side].code.function_bytes);
}
assert.equal(report.functions.reduce((n,r)=>n+r.delta,0),d.function_bytes);assert.equal(report.packages.reduce((n,r)=>n+r.delta,0),d.function_bytes);
assert.equal(d.code_bytes,d.function_bytes+d.code_overhead_bytes);assert.equal(d.file_bytes,d.code_bytes+d.non_code_bytes);
assert(report.scope.includes('not cross-build semantic identity'));assert(!('graph_complete'in report));assert(!('retained'in report));
const gate=run([...pair,gateOutput,'--diff-functions','--max-size','0B','--top','1'],3);
assert(gate.includes('Function and package comparison written to '));assert(gate.includes('grew by 16 bytes over the baseline, budget 0 bytes'));assert.deepEqual(JSON.parse(fs.readFileSync(gateOutput)),report);
const invalid=run(['--baseline',bad,'--diff-functions-json',badOutput],1);
assert(invalid.includes('baseline:'));assert(invalid.includes(bad));assert(invalid.includes('unsupported WebAssembly version 2'));
assert(!fs.existsSync(badOutput));assert(!invalid.includes('written to'));assert(!invalid.includes('FUNCTION SIZE CHANGES'));
const refused=run([...pair,output],1);
assert(refused.includes('output already exists'));assert(!refused.includes('written to'));assert.deepEqual(fs.readFileSync(output),saved);
fs.writeFileSync(path.join(dir,'results.json'),JSON.stringify({baseline:b,current:c,delta:d,matching:m,cli_sha256:sha(fs.readFileSync(cli)),node:process.version,v8:process.versions.v8,
  independent_validation:'Each legal fixture validated by Node/V8 once; no instantiation or execution',records},null,2)+'\n',{flag:'wx'});
console.log('Function-diff-JSON CLI regressions passed (4 process cases, 2 V8 validations). Evidence: '+dir);
