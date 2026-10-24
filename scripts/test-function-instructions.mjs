// Exactly four analyzer calls; one independent validation, no execution.
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import {spawnSync} from 'node:child_process';

const cli=path.resolve(process.argv[2]||'_build/native/release/build/cmd/main/main.exe');
assert(fs.existsSync(cli),'Build the native CLI first.');
const parent=path.resolve('_build/function-instructions-verification');
fs.mkdirSync(parent,{recursive:true});
const dir=fs.mkdtempSync(path.join(parent,'run-'));
const cat=(...items)=>Buffer.concat(items.map(item=>Buffer.from(item)));
const section=(id,payload)=>{assert(payload.length<128);return cat([id,payload.length],payload);};
const sha=bytes=>crypto.createHash('sha256').update(bytes).digest('hex');
const body=Buffer.from('01027f0240034041001a4180011a4300000000fc001a4300000000fc011a0b0b0b','hex');
assert.equal(body.length,33);
const name=Buffer.from('target"<&');
const data=cat(Buffer.from('0061736d01000000010401600000020701016d016600000303020000','hex'),
  section(10,cat([2,body.length|128,0],body,[2,0,11])),
  section(0,cat([4],Buffer.from('name'),section(1,cat([1,1,name.length],name)))));
assert(WebAssembly.validate(data),'Node/V8 rejected the mixed instruction fixture.'); // Once.
const input=path.join(dir,'instructions.wasm'), output=path.join(dir,'instructions.json');
fs.writeFileSync(input,data,{flag:'wx'});
const records=[];
function run(args,status){
  const proc=spawnSync(cli,[input,...args],{cwd:dir,encoding:'utf8',timeout:10000});
  const log=(proc.stdout||'')+(proc.stderr||'');
  fs.writeFileSync(path.join(dir,'case-'+records.length+'.log'),log,{flag:'wx'});
  records.push({args,status:proc.status,error:proc.error?.message||null});
  assert.ifError(proc.error);assert.equal(proc.signal,null);assert.equal(proc.status,status,log);
  assert.equal(sha(fs.readFileSync(input)),sha(data));return log;
}
const text=run(['--instructions','1','--top','1'],0);
assert(text.includes('FUNCTION INSTRUCTION ENCODING'));
assert(text.includes('Function 1: target"<&'));
assert(text.includes('Entry: file offset 31, size 35 B'));
assert(text.includes('Body: file offset 33, size 33 B'));
assert(text.includes('Encoded bytes: 35 B = prefix 2 B + body 33 B'));
assert(text.includes('Body bytes: 33 B = locals encoding 3 B + instructions 30 B'));
assert(text.includes('Instructions: 15; grouped bytes: 30 B'));
assert(text.includes('OPCODE GROUPS: showing 1 of 8'));
assert(text.includes('f32.const  2  10'));
assert(text.includes('INSTRUCTIONS: showing 1 of 15'));
assert(text.includes('0  block  36  3  2'));
assert(!text.includes('i32.trunc_sat_f32_s  1  2'));
assert(text.includes('not execution frequencies'));
const confirmation=run(['--instructions','1','--instructions-json',output,'--top','1'],0);
assert(confirmation.includes('Function instructions written to '));
assert(!confirmation.includes('FUNCTION INSTRUCTION ENCODING'));
const saved=fs.readFileSync(output), report=JSON.parse(saved);
assert.equal(report.format,'moonsize-function-instructions');assert.equal(report.schema_version,1);
assert.equal(report.file_size,data.length);assert.equal(report.sha256,sha(data));
assert.equal(report.index,1);assert.equal(report.name,'target"<&');assert.equal(report.raw_name,'target"<&');
assert.deepEqual(report.entry,{file_offset:31,size:35});assert.deepEqual(report.prefix,{file_offset:31,size:2});
assert.deepEqual(report.body,{file_offset:33,size:33});assert.deepEqual(report.locals_encoding,{file_offset:33,size:3});
assert.equal(report.entry.size,report.prefix.size+report.body.size);
assert.equal(report.body.size,report.locals_encoding.size+report.instruction_bytes);
const names=['block','loop','i32.const','drop','i32.const','drop','f32.const','i32.trunc_sat_f32_s','drop','f32.const','i32.trunc_sat_f32_u','drop','end','end','end'];
const sizes=[2,2,2,1,3,1,5,2,1,5,2,1,1,1,1];
assert.equal(report.instruction_count,15);assert.equal(report.instructions.length,15);
assert.deepEqual(report.instructions.map(i=>i.mnemonic),names);
assert.deepEqual(report.instructions.map(i=>i.encoded_size),sizes);
let cursor=36;const grouped=new Map();
for(const [ordinal,i]of report.instructions.entries()){
  assert.equal(i.ordinal,ordinal);assert.equal(i.file_offset,cursor);assert.equal(i.body_relative_offset,cursor-33);
  assert(i.encoded_size>0);assert(!('operands'in i));cursor+=i.encoded_size;
  const g=grouped.get(i.mnemonic)||{count:0,encoded_bytes:0};g.count++;g.encoded_bytes+=i.encoded_size;grouped.set(i.mnemonic,g);
}
assert.equal(cursor,66);assert.equal(report.instruction_bytes,30);
const expected=[...grouped].map(([mnemonic,g])=>({mnemonic,...g})).sort((a,b)=>b.encoded_bytes-a.encoded_bytes||b.count-a.count||(a.mnemonic<b.mnemonic?-1:a.mnemonic>b.mnemonic?1:0));
assert.deepEqual(report.groups,expected);assert.equal(report.groups.length,8);
assert.equal(report.groups.reduce((sum,g)=>sum+g.count,0),report.instruction_count);
assert.equal(report.groups.reduce((sum,g)=>sum+g.encoded_bytes,0),report.instruction_bytes);
assert(!('graph_complete'in report));
const refusedOutput=path.join(dir,'imported.json');
const imported=run(['--instructions','0','--instructions-json',refusedOutput],1);
assert(imported.includes('imported and has no local body'));
assert(!fs.existsSync(refusedOutput));assert(!imported.includes('written to'));assert(!imported.includes('BYTE LEDGER'));
const refused=run(['--instructions','1','--instructions-json',output],1);
assert(refused.includes('output already exists'));assert(!refused.includes('written to'));assert.deepEqual(fs.readFileSync(output),saved);
fs.writeFileSync(path.join(dir,'results.json'),JSON.stringify({input_sha256:sha(data),input_size:data.length,
  cli_sha256:sha(fs.readFileSync(cli)),node:process.version,v8:process.versions.v8,
  independent_validation:'One Node/V8 validation of this fixture; no instantiation or execution',records,
  entry:report.entry,body:report.body,locals_encoding:report.locals_encoding,instruction_bytes:report.instruction_bytes,instruction_count:report.instruction_count},null,2)+'\n',{flag:'wx'});
console.log('Function-instructions CLI regressions passed (4 process cases, 1 V8 validation). Evidence: '+dir);
