// Exactly four analyzer calls; fixed source Buffers provide the oracle.
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import {spawnSync} from 'node:child_process';
const cli=path.resolve(process.argv[2]||'_build/native/release/build/cmd/main/main.exe');
assert(fs.existsSync(cli),'Build the native CLI first.');
const parent=path.resolve('_build/function-local-accesses-verification');fs.mkdirSync(parent,{recursive:true});
const dir=fs.mkdtempSync(path.join(parent,'run-'));
const cat=(...items)=>Buffer.concat(items.map(item=>Buffer.from(item)));
const section=(id,p)=>{assert(p.length<128);return cat([id,p.length],p);};
const sha=b=>crypto.createHash('sha256').update(b).digest('hex');
const body=Buffer.from('0182017f207f1a4100218001410122ff001a2080011a207f1a0b','hex');
assert.equal(body.length,26);
const prefix=Buffer.from('0061736d01000000010401600000020701016d016600000303020000','hex');
const code=cat([2,body.length|128,0],body,[4,1,1,127,11]),name=Buffer.from('target"<&');
const bytes=cat(prefix,section(10,code),section(0,cat([4],Buffer.from('name'),section(1,cat([1,1,name.length],name)))));
assert.equal(bytes.length,85);
const expected=[
  {ordinal:0,opcode:'local.get',opcode_byte:32,index:127,file_offset:37,body_offset:4,size:2,index_hex:'7f'},
  {ordinal:3,opcode:'local.set',opcode_byte:33,index:128,file_offset:42,body_offset:9,size:3,index_hex:'8001'},
  {ordinal:5,opcode:'local.tee',opcode_byte:34,index:127,file_offset:47,body_offset:14,size:3,index_hex:'ff00'},
  {ordinal:7,opcode:'local.get',opcode_byte:32,index:128,file_offset:51,body_offset:18,size:3,index_hex:'8001'},
  {ordinal:9,opcode:'local.get',opcode_byte:32,index:127,file_offset:55,body_offset:22,size:2,index_hex:'7f'},
];
const expectedGroups=[
  {local_index:127,access_count:3,get_count:2,set_count:0,tee_count:1,encoded_bytes:7,index_encoding_bytes:4,instruction_ordinals:[0,5,9]},
  {local_index:128,access_count:2,get_count:1,set_count:1,tee_count:0,encoded_bytes:6,index_encoding_bytes:4,instruction_ordinals:[3,7]},
];
fs.writeFileSync(path.join(dir,'input.wasm'),bytes,{flag:'wx'});
const sentinel=Buffer.from('keep access evidence\n');fs.writeFileSync(path.join(dir,'existing.json'),sentinel,{flag:'wx'});
const records=[];
function run(args,status){
  const p=spawnSync(cli,['input.wasm',...args],{cwd:dir,encoding:'utf8',timeout:10000}),text=(p.stdout||'')+(p.stderr||'');
  fs.writeFileSync(path.join(dir,'case-'+records.length+'.log'),text,{flag:'wx'});
  records.push({argv:[cli,'input.wasm',...args],status:p.status,error:p.error?.message??null});
  fs.writeFileSync(path.join(dir,'processes.json'),JSON.stringify(records,null,2)+'\n');
  assert.ifError(p.error);assert.equal(p.signal,null);assert.equal(p.status,status,text);
  assert.deepEqual(fs.readFileSync(path.join(dir,'input.wasm')),bytes);assert.deepEqual(fs.readFileSync(path.join(dir,'existing.json')),sentinel);return text;
}
const text=run(['--local-accesses','1','--top','1'],0);
assert(text.includes('FUNCTION LOCAL ACCESS ENCODINGS'));
assert(text.includes('GROUPS: showing 1 of 2'));assert(text.includes('ACCESS SITES: showing 1 of 5'));
assert(text.includes('Accesses: 5 = get 3 + set 1 + tee 1'));assert(text.includes('Distinct local indices: 2'));
const groupRows=text.split(/\r?\n/).filter(line=>/^\d+  \d+  \d+  \d+  \d+  \d+  \d+  \[/.test(line));
const siteRows=text.split(/\r?\n/).filter(line=>/^\d+  local\.(get|set|tee)  /.test(line));
assert.deepEqual(groupRows,['127  3  2  0  1  7  4  [0,5,9]']);
assert.deepEqual(siteRows,['0  local.get  127  37  4  2  [38,39)  1']);
const saved=run(['--local-accesses','1','--local-accesses-json','new-accesses.json','--top','1'],0);
assert(saved.includes('Function local accesses written to new-accesses.json'));assert(!saved.includes('FUNCTION LOCAL ACCESS ENCODINGS'));
const report=JSON.parse(fs.readFileSync(path.join(dir,'new-accesses.json')));
assert.equal(report.format,'moonsize-function-local-accesses');assert.equal(report.schema_version,1);
assert.equal(report.sha256,sha(bytes));assert.equal(report.file_size,85);assert.equal(report.target.index,1);assert.equal(report.target.imported,false);
assert.equal(report.target.encoded_size,28);assert.deepEqual(report.entry,{file_offset:31,size:28});
assert.deepEqual(report.prefix,{file_offset:31,size:2});assert.deepEqual(report.body,{file_offset:33,size:26});
assert.deepEqual(report.locals_encoding,{file_offset:33,size:4});assert.equal(bytes.subarray(33,37).toString('hex'),'0182017f');
for(const [key,value]of Object.entries({instruction_count:12,instruction_bytes:22,access_count:5,get_count:3,set_count:1,tee_count:1,distinct_local_index_count:2,access_encoding_bytes:13,index_encoding_bytes:8,other_instruction_bytes:9}))assert.equal(report[key],value,key);
assert.equal(report.accesses.length,5);assert.deepEqual(report.groups,expectedGroups);
for(const [i,want]of expected.entries()){
  const got=report.accesses[i];assert.equal(got.instruction_ordinal,want.ordinal);assert.equal(got.opcode,want.opcode);assert.equal(got.local_index,want.index);
  assert.equal(got.file_offset,want.file_offset);assert.equal(got.body_relative_offset,want.body_offset);assert.equal(got.encoded_size,want.size);
  assert.deepEqual(got.index_encoding,{file_offset:want.file_offset+1,size:want.size-1});
  assert.equal(bytes[want.file_offset],want.opcode_byte);
  assert.equal(bytes.subarray(want.file_offset+1,want.file_offset+want.size).toString('hex'),want.index_hex);
  // Read only these fixed expected index bytes independently of analyzer output.
  let value=0,shift=0;for(const byte of Buffer.from(want.index_hex,'hex')){value+=(byte&127)*2**shift;shift+=7;}assert.equal(value,want.index);
}
assert.equal(report.entry.size,report.prefix.size+report.body.size);
assert.equal(report.body.size,report.locals_encoding.size+report.instruction_bytes);
assert.equal(report.access_count,report.get_count+report.set_count+report.tee_count);
assert.equal(report.instruction_bytes,report.access_encoding_bytes+report.other_instruction_bytes);
assert.equal(report.access_encoding_bytes,report.access_count+report.index_encoding_bytes);
assert.equal(report.groups.reduce((n,g)=>n+g.access_count,0),report.access_count);
assert.equal(report.groups.reduce((n,g)=>n+g.encoded_bytes,0),report.access_encoding_bytes);
for(const field of ['graph_complete','parameter_count','variable_name','declaration_group'])assert(!Object.hasOwn(report,field));
const empty=run(['--local-accesses','2'],0);
assert(empty.includes('No local.get/local.set/local.tee access instructions'));assert(empty.includes('does not imply no variables'));
assert(empty.includes('Locals encoding: file offset 60, size 3 B'));assert(empty.includes('Accesses: 0 = get 0 + set 0 + tee 0'));
assert(!empty.includes('No local variables'));
const refused=run(['--local-accesses','1','--local-accesses-json','existing.json'],1);
assert(refused.includes('output already exists'));assert(!refused.includes('Function local accesses written to'));
fs.writeFileSync(path.join(dir,'results.json'),JSON.stringify({input_sha256:sha(bytes),input_size:bytes.length,target_index:1,
  expected_accesses:expected,expected_groups:expectedGroups,
  byte_ledger:{entry:28,prefix:2,body:26,locals:4,instructions:22,access_encodings:13,index_encodings:8,other_instructions:9},
  records,input_and_existing_output_unchanged:true,
  scope:'Four new-feature analyzer calls only; no old suites/scripts, probes, V8 matrix, browser/PDF or benchmark'},null,2)+'\n',{flag:'wx'});
console.log('Function-local-accesses regressions passed (4 process cases). Evidence: '+dir);
