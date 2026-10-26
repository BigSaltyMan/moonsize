// Exactly four analyzer calls; expectations come from fixed source bytes.
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import {spawnSync} from 'node:child_process';
const cli=path.resolve(process.argv[2]||'_build/native/release/build/cmd/main/main.exe');
assert(fs.existsSync(cli),'Build the native CLI first.');
const parent=path.resolve('_build/function-calls-verification');fs.mkdirSync(parent,{recursive:true});
const dir=fs.mkdtempSync(path.join(parent,'run-'));
const cat=(...items)=>Buffer.concat(items.map(item=>Buffer.from(item)));
const section=(id,p)=>{assert(p.length<128);return cat([id,p.length],p);};
const sha=b=>crypto.createHash('sha256').update(b).digest('hex');
const body=Buffer.from('00001000d2001a100010021100001300001400150012000b','hex');assert.equal(body.length,24);
const prefix=Buffer.from('0061736d01000000010401600000020701016d0166000003030200000404017000010907010041000b0100','hex');
const code=cat([2,body.length|128,0],body,[2,0,11]),name=Buffer.from('target"<&');
const bytes=cat(prefix,section(10,code),section(0,cat([4],Buffer.from('name'),section(1,cat([1,1,name.length],name)))));
const bodyStart=prefix.length+2+3;assert.equal(bodyStart,48);assert.equal(bytes.length,96);
const expected=[
  {ordinal:1,opcode:'call',kind:'direct',tail:false,offset:2,size:2,target:0,type:null,table:null},
  {ordinal:4,opcode:'call',kind:'direct',tail:false,offset:7,size:2,target:0,type:null,table:null},
  {ordinal:5,opcode:'call',kind:'direct',tail:false,offset:9,size:2,target:2,type:null,table:null},
  {ordinal:6,opcode:'call_indirect',kind:'indirect',tail:false,offset:11,size:3,target:null,type:0,table:0},
  {ordinal:7,opcode:'return_call_indirect',kind:'indirect',tail:true,offset:14,size:3,target:null,type:0,table:0},
  {ordinal:8,opcode:'call_ref',kind:'reference_call',tail:false,offset:17,size:2,target:null,type:0,table:null},
  {ordinal:9,opcode:'return_call_ref',kind:'reference_call',tail:true,offset:19,size:2,target:null,type:0,table:null},
  {ordinal:10,opcode:'return_call',kind:'direct',tail:true,offset:21,size:2,target:0,type:null,table:null},
];
const opcodeBytes={call:16,return_call:18,call_indirect:17,return_call_indirect:19,call_ref:20,return_call_ref:21};
fs.writeFileSync(path.join(dir,'input.wasm'),bytes,{flag:'wx'});
const sentinel=Buffer.from('keep call evidence\n'),target=path.join(dir,'existing.json');fs.writeFileSync(target,sentinel,{flag:'wx'});
const records=[];
function run(args,status){
  const p=spawnSync(cli,['input.wasm',...args],{cwd:dir,encoding:'utf8',timeout:10000}),text=(p.stdout||'')+(p.stderr||'');
  fs.writeFileSync(path.join(dir,'case-'+records.length+'.log'),text,{flag:'wx'});
  records.push({argv:[cli,'input.wasm',...args],status:p.status,error:p.error?.message??null});
  fs.writeFileSync(path.join(dir,'processes.json'),JSON.stringify(records,null,2)+'\n');
  assert.ifError(p.error);assert.equal(p.signal,null);assert.equal(p.status,status,text);
  assert.equal(sha(fs.readFileSync(path.join(dir,'input.wasm'))),sha(bytes));assert.deepEqual(fs.readFileSync(target),sentinel);return text;
}
const text=run(['--calls','1','--top','1'],0);
assert(text.includes('FUNCTION CALL SITES'));assert(text.includes('CALLS: showing 1 of 8'));
assert(text.includes('Calls: 8 = direct 4 + indirect 2 + reference_call 2'));assert(text.includes('Tail calls: 3 (subset)'));
const rows=text.split(/\r?\n/).filter(line=>/^\d+  \w+/.test(line));assert.equal(rows.length,1);
assert(rows[0].startsWith('1  call  direct  no  50  2  2  #0 "m.f"'));
const saved=run(['--calls','1','--calls-json','new-calls.json','--top','1'],0);
assert(saved.includes('Function calls written to new-calls.json'));assert(!saved.includes('FUNCTION CALL SITES'));
const report=JSON.parse(fs.readFileSync(path.join(dir,'new-calls.json')));
assert.equal(report.format,'moonsize-function-calls');assert.equal(report.schema_version,1);
assert.equal(report.sha256,sha(bytes));assert.equal(report.file_size,96);assert.equal(report.caller.index,1);assert.equal(report.caller.imported,false);
assert.equal(report.caller.encoded_size,26);assert.deepEqual(report.entry,{file_offset:46,size:26});
assert.deepEqual(report.prefix,{file_offset:46,size:2});assert.deepEqual(report.body,{file_offset:48,size:24});
assert.deepEqual(report.locals_encoding,{file_offset:48,size:1});assert.equal(report.instruction_count,12);assert.equal(report.instruction_bytes,23);
assert.equal(report.call_count,8);assert.equal(report.direct_count,4);assert.equal(report.indirect_count,2);assert.equal(report.reference_call_count,2);assert.equal(report.tail_count,3);
assert.equal(report.call_encoding_bytes,18);assert.equal(report.other_instruction_bytes,5);assert.equal(report.calls.length,8);
for(const [i,want]of expected.entries()){
  const got=report.calls[i];assert.equal(got.instruction_ordinal,want.ordinal);assert.equal(got.opcode,want.opcode);
  assert.equal(got.kind,want.kind);assert.equal(got.is_tail,want.tail);assert.equal(got.file_offset,bodyStart+want.offset);
  assert.equal(got.body_relative_offset,want.offset);assert.equal(got.encoded_size,want.size);
  assert.equal(got.target_index,want.target);assert.equal(got.type_index,want.type);assert.equal(got.table_index,want.table);
  assert.equal(bytes[got.file_offset],opcodeBytes[want.opcode]);
  if(want.target===null)assert.equal(got.target,null);else{
    assert.equal(got.target.index,want.target);assert.equal(got.target.imported,want.target===0);
    assert.equal(got.target.encoded_size,want.target===0?null:3);
    assert.equal(got.target.import_module,want.target===0?'m':null);assert.equal(got.target.import_name,want.target===0?'f':null);
    assert.equal(bytes[got.file_offset+1],want.target);
  }
}
assert.equal(bytes[52],210);assert(!report.calls.some(c=>c.file_offset===52));
assert.equal(report.entry.size,report.prefix.size+report.body.size);assert.equal(report.body.size,report.locals_encoding.size+report.instruction_bytes);
assert.equal(report.call_count,report.direct_count+report.indirect_count+report.reference_call_count);
assert.equal(report.instruction_bytes,report.call_encoding_bytes+report.other_instruction_bytes);
assert(!('graph_complete'in report));assert(!('unresolved_count'in report));
const empty=run(['--calls','2'],0);
assert(empty.includes('No call instructions in this local function.'));assert(empty.includes('Calls: 0 = direct 0 + indirect 0 + reference_call 0'));
assert(empty.includes('Entry: file offset 72, size 3 B'));assert(!empty.includes('imported and has no local body'));
const refused=run(['--calls','1','--calls-json','existing.json'],1);
assert(refused.includes('output already exists'));assert(!refused.includes('Function calls written to'));
fs.writeFileSync(path.join(dir,'results.json'),JSON.stringify({input_sha256:sha(bytes),input_size:bytes.length,body_offset:bodyStart,
  expected_calls:expected.map(c=>({...c,file_offset:bodyStart+c.offset})),
  counts:{instruction_count:12,call_count:8,direct_count:4,indirect_count:2,reference_call_count:2,tail_count:3},
  byte_ledger:{entry:26,prefix:2,body:24,locals:1,instructions:23,call_encodings:18,other_instructions:5},records,input_and_existing_output_unchanged:true,
  scope:'Four new-feature analyzer calls only; no old scripts/suites, probes, V8 matrix, browser/PDF or benchmark'},null,2)+'\n',{flag:'wx'});
console.log('Function-calls regressions passed (4 process cases). Evidence: '+dir);
