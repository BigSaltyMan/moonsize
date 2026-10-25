// Four analyzer calls; independently validate each input once, without execution.
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import {spawnSync} from 'node:child_process';

const cli=path.resolve(process.argv[2]||'_build/native/release/build/cmd/main/main.exe');
assert(fs.existsSync(cli),'Build the native CLI first.');
const parent=path.resolve('_build/function-instructions-diff-verification');fs.mkdirSync(parent,{recursive:true});
const dir=fs.mkdtempSync(path.join(parent,'run-'));
const cat=(...items)=>Buffer.concat(items.map(item=>Buffer.from(item)));
const section=(id,payload)=>{assert(payload.length<128);return cat([id,payload.length],payload);};
const sha=bytes=>crypto.createHash('sha256').update(bytes).digest('hex');
function moduleBytes(bodies,index,label){
  const name=Buffer.from(label);
  return cat(Buffer.from('0061736d01000000010401600000020701016d016600000303020000','hex'),
    section(10,cat([2],...bodies.map((b,i)=>cat(i===0?[b.length|128,0]:[b.length],b)))),
    section(0,cat([4],Buffer.from('name'),section(1,cat([1,index,name.length],name)))));
}
const baseline=moduleBytes([Buffer.from([0,65,0,26,1,11]),Buffer.from([0,11])],1,'before-target');
const current=moduleBytes([Buffer.from([0,11]),Buffer.from([1,2,127,65,128,1,26,65,1,26,11])],2,'renamed-current');
assert(WebAssembly.validate(baseline),'Node/V8 rejected baseline fixture.'); // Once per input.
assert(WebAssembly.validate(current),'Node/V8 rejected current fixture.');
const before=path.join(dir,'before.wasm'),after=path.join(dir,'after.wasm'),output=path.join(dir,'instructions-diff.json');
fs.writeFileSync(before,baseline,{flag:'wx'});fs.writeFileSync(after,current,{flag:'wx'});
const records=[];
function run(args,status){
  const proc=spawnSync(cli,[after,...args],{cwd:dir,encoding:'utf8',timeout:10000});
  const log=(proc.stdout||'')+(proc.stderr||'');
  fs.writeFileSync(path.join(dir,'case-'+records.length+'.log'),log,{flag:'wx'});
  records.push({args,status:proc.status,error:proc.error?.message||null});
  assert.ifError(proc.error);assert.equal(proc.signal,null);assert.equal(proc.status,status,log);
  assert.equal(sha(fs.readFileSync(before)),sha(baseline));assert.equal(sha(fs.readFileSync(after)),sha(current));return log;
}
const pair=['--instructions','2','--baseline',before,'--baseline-instructions','1'];
const text=run([...pair,'--top','1'],0);
assert(text.includes('FUNCTION INSTRUCTION COMPOSITION COMPARISON'));
assert(text.includes(`Baseline: ${baseline.length} B; SHA-256 ${sha(baseline)}; function 1`));
assert(text.includes(`Current: ${current.length} B; SHA-256 ${sha(current)}; function 2`));
assert(text.includes('name: "before-target"'));assert(text.includes('name: "renamed-current"'));
assert(text.includes('entry: file offset 31, size 8 B'));assert(text.includes('entry: file offset 35, size 12 B'));
assert(text.includes('Entry bytes  8  12  4'));assert(text.includes('Prefix bytes  2  1  -1'));
assert(text.includes('Body bytes  6  11  5'));assert(text.includes('Locals bytes  1  3  2'));
assert(text.includes('Instruction bytes  5  8  3'));assert(text.includes('Instruction count  4  5  1'));
assert(text.includes('Entry delta: 4 B = prefix -1 B + body 5 B'));
assert(text.includes('Body delta: 5 B = locals 2 B + instructions 3 B'));
assert(text.includes('OPCODE COMPOSITION: showing 1 of 4'));
assert(text.includes('i32.const  1  2  1  2  5  3'));assert(!text.includes('nop  1  0'));
assert(text.includes('instruction sequences and immediate values are not compared'));
const confirmation=run([...pair,'--instructions-json',output,'--top','1'],0);
assert(confirmation.includes('Function instruction comparison written to '));assert(!confirmation.includes('BYTE AND COUNT LEDGER'));
const saved=fs.readFileSync(output),report=JSON.parse(saved),b=report.baseline,c=report.current,d=report.delta;
assert.equal(report.format,'moonsize-function-instructions-diff');assert.equal(report.schema_version,1);
assert(b&&typeof b==='object'&&!Array.isArray(b));assert(c&&typeof c==='object'&&!Array.isArray(c));
const keys=['format','schema_version','file_size','sha256','index','name','raw_name','entry','prefix','body','locals_encoding','instruction_bytes','instruction_count','groups','instructions','scope'].sort();
for(const [side,bytes,index,name,bodyOffset,entryOffset,prefixSize,bodySize,localsSize,mnemonics,sizes]of [
  [b,baseline,1,'before-target',33,31,2,6,1,['i32.const','drop','nop','end'],[2,1,1,1]],
  [c,current,2,'renamed-current',36,35,1,11,3,['i32.const','drop','i32.const','drop','end'],[3,1,2,1,1]],
]){
  assert.deepEqual(Object.keys(side).sort(),keys);assert.equal(side.format,'moonsize-function-instructions');assert.equal(side.schema_version,1);
  assert.equal(side.sha256,sha(bytes));assert.equal(side.file_size,bytes.length);assert.equal(side.index,index);assert.equal(side.name,name);assert.equal(side.raw_name,name);
  assert.deepEqual(side.entry,{file_offset:entryOffset,size:prefixSize+bodySize});assert.deepEqual(side.prefix,{file_offset:entryOffset,size:prefixSize});
  assert.deepEqual(side.body,{file_offset:bodyOffset,size:bodySize});assert.deepEqual(side.locals_encoding,{file_offset:bodyOffset,size:localsSize});
  assert.equal(side.instruction_count,mnemonics.length);assert.deepEqual(side.instructions.map(i=>i.mnemonic),mnemonics);assert.deepEqual(side.instructions.map(i=>i.encoded_size),sizes);
  let cursor=bodyOffset+localsSize;for(const [ordinal,i]of side.instructions.entries()){
    assert.equal(i.ordinal,ordinal);assert.equal(i.file_offset,cursor);assert.equal(i.body_relative_offset,cursor-bodyOffset);cursor+=i.encoded_size;
  }
  assert.equal(cursor,bodyOffset+bodySize);assert.equal(side.instruction_bytes,bodySize-localsSize);
  assert.equal(side.groups.reduce((sum,g)=>sum+g.count,0),side.instruction_count);
  assert.equal(side.groups.reduce((sum,g)=>sum+g.encoded_bytes,0),side.instruction_bytes);
}
assert.deepEqual(d,{entry_bytes:4,prefix_bytes:-1,body_bytes:5,locals_bytes:2,instruction_bytes:3,instruction_count:1});
const expected=[['i32.const',1,2,1,2,5,3],['drop',1,2,1,1,2,1],['nop',1,0,-1,1,0,-1],['end',1,1,0,1,1,0]];
assert.deepEqual(report.opcodes.map(r=>[r.mnemonic,r.baseline_count,r.current_count,r.count_delta,r.baseline_encoded_bytes,r.current_encoded_bytes,r.encoded_bytes_delta]),expected);
assert.equal(d.entry_bytes,d.prefix_bytes+d.body_bytes);assert.equal(d.body_bytes,d.locals_bytes+d.instruction_bytes);
assert.equal(d.instruction_bytes,report.opcodes.reduce((sum,r)=>sum+r.encoded_bytes_delta,0));
assert.equal(d.instruction_count,report.opcodes.reduce((sum,r)=>sum+r.count_delta,0));
const zero=run(['--instructions','2','--baseline',after,'--baseline-instructions','2','--top','1'],0);
assert(zero.includes('Entry delta: 0 B = prefix 0 B + body 0 B'));
assert(zero.includes('Body delta: 0 B = locals 0 B + instructions 0 B'));
assert(zero.includes('Instruction count  5  5  0'));
assert(zero.includes('Zero aggregate deltas do not prove equal sequences, semantics or compatibility'));
const refused=run([...pair,'--instructions-json',output],1);
assert(refused.includes('output already exists'));assert(!refused.includes('written to'));assert.deepEqual(fs.readFileSync(output),saved);
fs.writeFileSync(path.join(dir,'results.json'),JSON.stringify({baseline:{size:baseline.length,sha256:sha(baseline),index:1},current:{size:current.length,sha256:sha(current),index:2},
  cli_sha256:sha(fs.readFileSync(cli)),node:process.version,v8:process.versions.v8,independent_validation:'Each fixture validated by Node/V8 once; no instantiation or execution',delta:d,records},null,2)+'\n',{flag:'wx'});
console.log('Function-instructions-diff CLI regressions passed (4 process cases, 2 V8 validations). Evidence: '+dir);
