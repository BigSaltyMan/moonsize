// Exactly four analyzer calls; fixed Buffers/BigInt supply independent expectations.
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import {spawnSync} from 'node:child_process';
const cli=path.resolve(process.argv[2]||'_build/native/release/build/cmd/main/main.exe');
assert(fs.existsSync(cli),'Build the native CLI first.');
const parent=path.resolve('_build/function-locals-verification');fs.mkdirSync(parent,{recursive:true});
const dir=fs.mkdtempSync(path.join(parent,'run-'));
const cat=(...items)=>Buffer.concat(items.map(item=>Buffer.from(item)));
const section=(id,p)=>{assert(p.length<128);return cat([id,p.length],p);};
const sha=b=>crypto.createHash('sha256').update(b).digest('hex');
const body=Buffer.from('840082007f007f017f0363700b','hex');
const prefix=Buffer.from('0061736d01000000010401600000020701016d016600000303020000','hex');
const code=cat([2,body.length|128,0],body,[2,0,11]),name=Buffer.from('target"<&');
const bytes=cat(prefix,section(10,code),section(0,cat([4],Buffer.from('name'),section(1,cat([1,1,name.length],name)))));
assert.equal(bytes.length,70);assert.equal(body.length,13);
const expected=[
  {quantity:2,start:'0',end:'2',offset:35,quantity_hex:'8200',type_hex:'7f',label:'i32'},
  {quantity:0,start:'2',end:'2',offset:38,quantity_hex:'00',type_hex:'7f',label:'i32'},
  {quantity:1,start:'2',end:'3',offset:40,quantity_hex:'01',type_hex:'7f',label:'i32'},
  {quantity:3,start:'3',end:'6',offset:42,quantity_hex:'03',type_hex:'6370',label:null},
];
fs.writeFileSync(path.join(dir,'input.wasm'),bytes,{flag:'wx'});
const sentinel=Buffer.from('keep locals evidence\n'),target=path.join(dir,'existing.json');fs.writeFileSync(target,sentinel,{flag:'wx'});
const records=[];
function run(args,status){
  const p=spawnSync(cli,['input.wasm',...args],{cwd:dir,encoding:'utf8',timeout:10000}),text=(p.stdout||'')+(p.stderr||'');
  fs.writeFileSync(path.join(dir,'case-'+records.length+'.log'),text,{flag:'wx'});
  records.push({argv:[cli,'input.wasm',...args],status:p.status,error:p.error?.message??null});
  fs.writeFileSync(path.join(dir,'processes.json'),JSON.stringify(records,null,2)+'\n');
  assert.ifError(p.error);assert.equal(p.signal,null);assert.equal(p.status,status,text);
  assert.equal(sha(fs.readFileSync(path.join(dir,'input.wasm'))),sha(bytes));assert.deepEqual(fs.readFileSync(target),sentinel);return text;
}
const text=run(['--locals','1','--top','1'],0);
assert(text.includes('FUNCTION LOCAL DECLARATIONS'));assert(text.includes('GROUPS: showing 1 of 4'));
assert(text.includes('Groups: 4; declared variables (excluding parameters): 6'));
const rows=text.split(/\r?\n/).filter(line=>/^\d+  \d+  \[/.test(line));assert.equal(rows.length,1);
assert.equal(rows[0],'0  2  [0,2)  i32  7f  [35,38)  3');
const saved=run(['--locals','1','--locals-json','new-locals.json','--top','1'],0);
assert(saved.includes('Function locals written to new-locals.json'));assert(!saved.includes('FUNCTION LOCAL DECLARATIONS'));
const report=JSON.parse(fs.readFileSync(path.join(dir,'new-locals.json')));
assert.equal(report.format,'moonsize-function-locals');assert.equal(report.schema_version,1);
assert.equal(report.sha256,sha(bytes));assert.equal(report.file_size,70);assert.equal(report.target.index,1);assert.equal(report.target.imported,false);
assert.equal(report.target.encoded_size,15);assert.deepEqual(report.entry,{file_offset:31,size:15});
assert.deepEqual(report.prefix,{file_offset:31,size:2});assert.deepEqual(report.body,{file_offset:33,size:13});
assert.deepEqual(report.locals_encoding,{file_offset:33,size:12});assert.deepEqual(report.group_count_encoding,{file_offset:33,size:2});
assert.deepEqual(report.body_remainder,{file_offset:45,size:1});assert.equal(report.group_count,4);
assert.equal(report.declared_count_decimal,'6');assert.equal(report.quantity_encoding_bytes,5);assert.equal(report.type_encoding_bytes,5);
assert.equal(bytes.subarray(31,33).toString('hex'),'8d00');assert.equal(bytes.subarray(33,35).toString('hex'),'8400');
assert.equal(report.groups.length,4);
let sum=0n,groupBytes=0;
for(const [i,want]of expected.entries()){
  const got=report.groups[i],qSize=want.quantity_hex.length/2,tSize=want.type_hex.length/2;
  assert.equal(got.group_index,i);assert.equal(got.quantity,want.quantity);assert.equal(typeof got.quantity,'number');
  assert.equal(got.declared_ordinal_start_decimal,want.start);assert.equal(got.declared_ordinal_end_decimal,want.end);
  assert.equal(BigInt(got.declared_ordinal_start_decimal),sum);sum+=BigInt(want.quantity);assert.equal(BigInt(got.declared_ordinal_end_decimal),sum);
  assert.deepEqual(got.encoding,{file_offset:want.offset,size:qSize+tSize});
  assert.deepEqual(got.quantity_encoding,{file_offset:want.offset,size:qSize});
  assert.deepEqual(got.type_encoding,{file_offset:want.offset+qSize,size:tSize});
  assert.equal(bytes.subarray(want.offset,want.offset+qSize).toString('hex'),want.quantity_hex);
  assert.equal(bytes.subarray(want.offset+qSize,want.offset+qSize+tSize).toString('hex'),want.type_hex);
  assert.equal(got.type_hex,want.type_hex);assert.equal(got.type_label,want.label);groupBytes+=got.encoding.size;
}
assert.equal(sum,BigInt(report.declared_count_decimal));
assert.equal(report.entry.size,report.prefix.size+report.body.size);
assert.equal(report.body.size,report.locals_encoding.size+report.body_remainder.size);
assert.equal(report.locals_encoding.size,report.group_count_encoding.size+groupBytes);
assert.equal(groupBytes,report.quantity_encoding_bytes+report.type_encoding_bytes);
assert(!('graph_complete'in report));assert(!('parameters'in report));
const empty=run(['--locals','2'],0);
assert(empty.includes('Zero declaration groups'));assert(empty.includes('Groups: 0; declared variables (excluding parameters): 0'));
assert(empty.includes('Group count: file offset 47, size 1 B'));assert(empty.includes('Locals: file offset 47, size 1 B'));
const refused=run(['--locals','1','--locals-json','existing.json'],1);
assert(refused.includes('output already exists'));assert(!refused.includes('Function locals written to'));
fs.writeFileSync(path.join(dir,'results.json'),JSON.stringify({input_sha256:sha(bytes),input_size:bytes.length,expected_groups:expected,
  counts:{groups:4,declared_count_decimal:'6'},byte_ledger:{entry:15,prefix:2,body:13,locals:12,group_count:2,quantities:5,types:5,undecoded_remainder:1},
  records,input_and_existing_output_unchanged:true,
  scope:'Four new-feature analyzer calls only; no old suites/scripts, probes, V8 matrix, browser/PDF or benchmark'},null,2)+'\n',{flag:'wx'});
console.log('Function-locals regressions passed (4 process cases). Evidence: '+dir);
