// Exactly four analyzer processes, with fixed source bytes as the oracle.
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import {spawnSync} from 'node:child_process';
const cli=path.resolve(process.argv[2]||'_build/native/release/build/cmd/main/main.exe');
assert(fs.existsSync(cli),'Build the native CLI first.');
const parent=path.resolve('_build/module-opcodes-verification');fs.mkdirSync(parent,{recursive:true});
const dir=fs.mkdtempSync(path.join(parent,'run-'));
const cat=(...items)=>Buffer.concat(items.map(item=>Buffer.from(item)));
const section=(id,p)=>{assert(p.length<128);return cat([id,p.length],p);};
const sha=b=>crypto.createHash('sha256').update(b).digest('hex');
const first=Buffer.from('01027f0240034041001a4180011a4300000000fc001a4300000000fc011a0b0b0b','hex');
const second=Buffer.from('0041011a4180011a0b','hex');assert.equal(first.length,33);assert.equal(second.length,9);
const prefix=Buffer.from('0061736d01000000010401600000020701016d016600000303020000','hex');
const code=cat([0x82,0,0xa1,0],first,[9],second),name=Buffer.from('target"<&');
const bytes=cat(prefix,section(10,code),section(0,cat([4],Buffer.from('name'),section(1,cat([1,1,name.length],name)))));
assert.equal(code.length,47);assert.equal(bytes.length,98);
const bad=Buffer.from(bytes);bad[69]=255;
const expectedGroups=[
  {mnemonic:'i32.const',count:4,encoded_bytes:10,function_count:2},
  {mnemonic:'f32.const',count:2,encoded_bytes:10,function_count:1},
  {mnemonic:'drop',count:6,encoded_bytes:6,function_count:2},
  {mnemonic:'end',count:4,encoded_bytes:4,function_count:2},
  {mnemonic:'block',count:1,encoded_bytes:2,function_count:1},
  {mnemonic:'i32.trunc_sat_f32_s',count:1,encoded_bytes:2,function_count:1},
  {mnemonic:'i32.trunc_sat_f32_u',count:1,encoded_bytes:2,function_count:1},
  {mnemonic:'loop',count:1,encoded_bytes:2,function_count:1},
];
const functionExpectations=[
  {index:1,offset:32,prefix_hex:'a100',body_size:33,total_size:35,locals_offset:34,locals_hex:'01027f',count:15,instruction_bytes:30,
    encodings:['0240','0340','4100','1a','418001','1a','4300000000','fc00','1a','4300000000','fc01','1a','0b','0b','0b']},
  {index:2,offset:67,prefix_hex:'09',body_size:9,total_size:10,locals_offset:68,locals_hex:'00',count:5,instruction_bytes:8,
    encodings:['4101','1a','418001','1a','0b']},
];
fs.writeFileSync(path.join(dir,'input.wasm'),bytes,{flag:'wx'});fs.writeFileSync(path.join(dir,'bad.wasm'),bad,{flag:'wx'});
const sentinel=Buffer.from('keep opcode statistics\n');fs.writeFileSync(path.join(dir,'existing.json'),sentinel,{flag:'wx'});
const records=[];
function run(args,status){
  const p=spawnSync(cli,args,{cwd:dir,encoding:'utf8',timeout:10000}),text=(p.stdout||'')+(p.stderr||'');
  fs.writeFileSync(path.join(dir,'case-'+records.length+'.log'),text,{flag:'wx'});
  records.push({argv:[cli,...args],status:p.status,error:p.error?.message??null});
  fs.writeFileSync(path.join(dir,'processes.json'),JSON.stringify(records,null,2)+'\n');
  assert.ifError(p.error);assert.equal(p.signal,null);assert.equal(p.status,status,text);
  assert.deepEqual(fs.readFileSync(path.join(dir,'input.wasm')),bytes);assert.deepEqual(fs.readFileSync(path.join(dir,'bad.wasm')),bad);
  assert.deepEqual(fs.readFileSync(path.join(dir,'existing.json')),sentinel);return text;
}
const text=run(['input.wasm','--opcode-stats','--top','1'],0);
assert(text.includes('MODULE FUNCTION OPCODE STATISTICS'));assert(text.includes('Imported functions: 1; local functions: 2'));
assert(text.includes('Code bytes: 49 = header 2 + count encoding 2 + body prefixes 3 + locals 4 + instructions 38'));
assert(text.includes('Instructions: 20; complete instruction encoding bytes: 38'));assert(text.includes('OPCODE GROUPS: showing 1 of 8'));
const rows=text.split(/\r?\n/).filter(line=>/^[a-z0-9._]+  \d+  \d+  \d+$/.test(line));assert.deepEqual(rows,['i32.const  4  2  10']);
const saved=run(['input.wasm','--opcode-stats-json','new-opcodes.json','--top','1'],0);
assert(saved.includes('Module opcode statistics written to new-opcodes.json'));assert(!saved.includes('MODULE FUNCTION OPCODE STATISTICS'));
const report=JSON.parse(fs.readFileSync(path.join(dir,'new-opcodes.json')));
assert.equal(report.format,'moonsize-module-opcodes');assert.equal(report.schema_version,1);assert.equal(report.sha256,sha(bytes));assert.equal(report.file_size,98);
assert.deepEqual(report.code_section,{id:10,kind:'code',offset:28,payload_size:47,total_size:49});
assert.deepEqual(report.count_encoding,{file_offset:30,size:2});assert.equal(bytes.subarray(30,32).toString('hex'),'8200');
for(const [key,value]of Object.entries({imported_function_count:1,local_function_count:2,code_header_bytes:2,count_encoding_bytes:2,body_prefix_bytes:3,locals_encoding_bytes:4,instruction_bytes:38,instruction_count:20}))assert.equal(report[key],value,key);
assert.deepEqual(report.groups,expectedGroups);assert.equal(report.functions.length,2);
for(const [i,f]of report.functions.entries()){
  const want=functionExpectations[i],s=f.stat;
  for(const key of ['index','offset','body_size','total_size'])assert.equal(s[key],want[key]);
  assert.equal(s.name,i===0?'target"<&':null);assert.equal(s.raw_name,i===0?'target"<&':null);assert.equal(s.display_name,i===0?'target"<&':'(unnamed)');
  assert.deepEqual(f.locals_encoding,{file_offset:want.locals_offset,size:want.locals_hex.length/2});
  assert.equal(f.instruction_count,want.count);assert.equal(f.instruction_bytes,want.instruction_bytes);
  assert.equal(bytes.subarray(want.offset,want.locals_offset).toString('hex'),want.prefix_hex);
  assert.equal(bytes.subarray(want.locals_offset,want.locals_offset+f.locals_encoding.size).toString('hex'),want.locals_hex);
  let cursor=want.locals_offset+f.locals_encoding.size;
  for(const hex of want.encodings){const size=hex.length/2;assert.equal(bytes.subarray(cursor,cursor+size).toString('hex'),hex);cursor+=size;}
  assert.equal(cursor,want.offset+want.total_size);
  assert(!Object.hasOwn(f,'instructions'));assert(!Object.hasOwn(f,'groups'));
}
assert.equal(report.code_section.total_size,report.code_header_bytes+report.count_encoding_bytes+report.body_prefix_bytes+report.locals_encoding_bytes+report.instruction_bytes);
assert.equal(report.functions.reduce((n,f)=>n+f.stat.total_size,0),45);
assert.equal(report.functions.reduce((n,f)=>n+f.instruction_bytes,0),report.instruction_bytes);
assert.equal(report.groups.reduce((n,g)=>n+g.encoded_bytes,0),report.instruction_bytes);
assert.equal(report.functions.reduce((n,f)=>n+f.instruction_count,0),report.instruction_count);
assert.equal(report.groups.reduce((n,g)=>n+g.count,0),report.instruction_count);
for(const g of report.groups)assert(g.function_count>0&&g.function_count<=2&&g.function_count<=g.count);
assert.equal(report.groups.reduce((n,g)=>n+g.function_count,0),11); // Not the local-function count.
assert(!Object.hasOwn(report,'instructions'));assert(!Object.hasOwn(report,'graph_complete'));
const broken=run(['bad.wasm','--opcode-stats-json','should-not-exist.json'],1);
assert(broken.includes('function 2'));assert(broken.includes('69'));assert(!broken.includes('Module opcode statistics written to'));
assert(!fs.existsSync(path.join(dir,'should-not-exist.json')));
const refused=run(['input.wasm','--opcode-stats-json','existing.json'],1);
assert(refused.includes('output already exists'));assert(!refused.includes('Module opcode statistics written to'));
fs.writeFileSync(path.join(dir,'results.json'),JSON.stringify({input_sha256:sha(bytes),bad_sha256:sha(bad),input_size:bytes.length,
  groups:expectedGroups,functions:functionExpectations,ledger:{code:49,header:2,count_encoding:2,body_prefixes:3,locals:4,instructions:38,instruction_count:20,entry_bytes:45},
  bad_function_index:2,bad_file_offset:69,records,inputs_and_existing_output_unchanged:true,
  scope:'Four new-feature analyzer calls only; no old suites/scripts, probes, V8 matrix, browser/PDF or performance benchmark'},null,2)+'\n',{flag:'wx'});
console.log('Module-opcode regressions passed (4 process cases). Evidence: '+dir);
