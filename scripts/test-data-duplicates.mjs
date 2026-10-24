// Four analyzer calls only. Independently validate the mixed fixture once.
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import {spawnSync} from 'node:child_process';

const cli=path.resolve(process.argv[2]||'_build/native/release/build/cmd/main/main.exe');
assert(fs.existsSync(cli),'Build the native CLI first.');
const parent=path.resolve('_build/data-duplicates-verification');fs.mkdirSync(parent,{recursive:true});
const dir=fs.mkdtempSync(path.join(parent,'run-'));
const cat=(...items)=>Buffer.concat(items.map(b=>Buffer.from(b)));
const wide=n=>{assert(n<128);return Buffer.from([n|128,0]);};
const sha=b=>crypto.createHash('sha256').update(b).digest('hex');
const header=Buffer.from('0061736d01000000','hex');
const bodies=[cat([0,65,11,11,3],Buffer.from('abc')),
  cat([129,0,131,0],Buffer.from('abc')),
  cat([2,129,0,65,22,11,3],Buffer.from('abc')),
  cat([1,2],Buffer.from('xy')),cat([130,0,0,65,0,11,2],Buffer.from('xy')),
  cat([1,3],Buffer.from('xyz')),Buffer.from([1,0]),Buffer.from([0,65,0,11,128,0])];
const payload=cat(wide(bodies.length),...bodies);
const data=cat(header,[5,5,2,0,1,0,1],[12,1,8],[11],wide(payload.length),payload);
assert(WebAssembly.validate(data),'V8 rejected the mixed duplicate-data fixture.'); // Once.
const input=path.join(dir,'mixed.wasm'), absent=path.join(dir,'no-data.wasm'), output=path.join(dir,'data-duplicates.json');
fs.writeFileSync(input,data,{flag:'wx'});fs.writeFileSync(absent,header,{flag:'wx'});
const records=[];
function run(file,args,status){
  const p=spawnSync(cli,[file,...args],{cwd:dir,encoding:'utf8',timeout:10000});
  const log=(p.stdout||'')+(p.stderr||'');
  fs.writeFileSync(path.join(dir,'case-'+records.length+'.log'),log,{flag:'wx'});
  records.push({input:file,args,status:p.status,error:p.error?.message||null});
  assert.ifError(p.error);assert.equal(p.signal,null);assert.equal(p.status,status,log);
  assert.equal(sha(fs.readFileSync(input)),sha(data));assert.equal(sha(fs.readFileSync(absent)),sha(header));return log;
}
const text=run(input,['--data-duplicates','--top','1'],0);
assert(text.includes('DUPLICATE DATA PAYLOADS'));
assert(text.includes('Duplicate groups: 3; segments: 8 = duplicate-group members 7 + singletons 1'));
assert(text.includes('Payload bytes: 16 B = duplicate-group members 13 B + singletons 3 B'));
assert(text.includes('Entry encoding bytes: 51 B = payload 16 B + metadata 35 B'));
assert(text.includes('Data section bytes: 56 B = section header 3 B + count prefix 2 B + entries 51 B'));
assert(text.includes('DUPLICATE GROUPS: showing 1 of 3'));
assert(text.includes('Group #0; SHA-256:')||text.includes('Group #0; SHA-256 '));
assert(!text.includes('Group #3;'));assert(!text.includes('Group #6;'));
assert(text.includes('Members: showing 3 of 3 (preview limit 20)'));
assert(text.includes('2  active  1  10  3  38'));
const confirmation=run(input,['--data-duplicates-json',output,'--top','1'],0);
assert(confirmation.includes('Duplicate data payloads written to '));assert(!confirmation.includes('DUPLICATE DATA PAYLOADS'));
const saved=fs.readFileSync(output), report=JSON.parse(saved), s=report.summary, source=report.data_segments;
assert.equal(report.format,'moonsize-data-duplicates');assert.equal(report.schema_version,1);
assert.equal(report.file_size,74);assert.equal(data.length,74);assert.equal(report.sha256,sha(data));
assert.equal(source.format,'moonsize-data-segments');assert.equal(source.schema_version,1);assert.equal(source.file_size,74);
assert.equal(source.datacount,8);assert.equal(source.summary.entry_count,8);assert.equal(source.entries.length,8);
assert.equal(source.summary.total_size,56);assert.equal(source.summary.header_size,3);assert.equal(source.summary.count_size,2);
assert.deepEqual(report.groups.map(g=>g.id),[0,3,6]);
assert.deepEqual(report.groups.map(g=>g.member_indices),[[0,1,2],[3,4],[6,7]]);
assert.deepEqual(report.groups.map(g=>g.member_payload_bytes),[9,4,0]);
assert.deepEqual(report.groups.map(g=>g.member_metadata_bytes),[16,9,8]);
assert.deepEqual(report.groups.map(g=>g.member_encoded_bytes),[25,13,8]);
assert.equal(s.segment_count,s.duplicate_member_count+s.singleton_count);
assert.equal(s.total_payload_bytes,s.duplicate_member_payload_bytes+s.singleton_payload_bytes);
assert.equal(s.total_entry_encoded_bytes,s.total_payload_bytes+s.total_entry_metadata_bytes);
assert.equal(s.data_section_bytes,s.section_header_bytes+s.count_prefix_bytes+s.total_entry_encoded_bytes);
assert.equal(s.duplicate_group_count,3);assert.equal(s.duplicate_member_count,7);assert.equal(s.singleton_count,1);
assert.equal(s.duplicate_member_payload_bytes,13);assert.equal(s.singleton_payload_bytes,3);
assert.equal(s.duplicate_member_encoded_bytes,46);assert.equal(s.singleton_encoded_bytes,5);
for(const key of ['payload','metadata','encoded']){
  assert.equal(report.groups.reduce((n,g)=>n+g['member_'+key+'_bytes'],0),s['duplicate_member_'+key+'_bytes']);
}
const expected=[
  ['active',0,23,8,28,3,24,3,1,0,1],['passive',null,31,7,35,3,null,0,2,0,2],
  ['active',1,38,10,45,3,41,3,1,2,1],['passive',null,48,4,50,2,null,0,1,0,1],
  ['active',0,52,9,59,2,55,3,2,1,1],['passive',null,61,5,63,3,null,0,1,0,1],
  ['passive',null,66,2,68,0,null,0,1,0,1],['active',0,68,6,74,0,69,3,1,0,2],
];
for(const [i,e]of source.entries.entries()){
  const [mode,memory,offset,size,pOffset,pSize,exprOffset,exprSize,modeSize,memorySize,lengthSize]=expected[i];
  assert.equal(e.index,i);assert.equal(e.mode,mode);assert.equal(e.memory_index,memory);
  assert.deepEqual(e.encoding,{file_offset:offset,size});assert.deepEqual(e.payload,{file_offset:pOffset,size:pSize});
  assert.deepEqual(e.offset_expression,exprOffset===null?null:{file_offset:exprOffset,size:exprSize});
  assert.equal(e.offset_status,mode==='active'?'not_evaluated':'not_applicable');
  assert.equal(e.mode_size,modeSize);assert.equal(e.memory_index_size,memorySize);assert.equal(e.payload_length_size,lengthSize);
  assert.equal(size,modeSize+memorySize+exprSize+lengthSize+pSize);
  assert.deepEqual(data.subarray(offset,offset+size),bodies[i]);
}
const seen=new Set();
for(const g of report.groups){
  assert.equal(g.id,Math.min(...g.member_indices));assert.equal(g.member_count,g.member_indices.length);
  assert.equal(g.member_payload_bytes,g.member_count*g.payload_size);
  assert.equal(g.member_encoded_bytes,g.member_payload_bytes+g.member_metadata_bytes);
  assert.deepEqual(g.member_indices,[...g.member_indices].sort((a,b)=>a-b));
  for(const index of g.member_indices){assert(!seen.has(index));seen.add(index);const e=source.entries[index];
    const bytes=data.subarray(e.payload.file_offset,e.payload.file_offset+e.payload.size);
    assert.equal(bytes.length,g.payload_size);assert.equal(sha(bytes),g.sha256);
  }
}
assert.equal(seen.size,7);assert(!seen.has(5));assert.equal(report.groups[2].payload_size,0);
const none=run(absent,['--data-duplicates'],0);
assert(none.includes('Data section: absent; DataCount absent'));
assert(none.includes('No identical data payload groups found.'));
assert(none.includes('Duplicate groups: 0; segments: 0 = duplicate-group members 0 + singletons 0'));
assert(none.includes('Data section bytes: 0 B = section header 0 B + count prefix 0 B + entries 0 B'));
const refused=run(input,['--data-duplicates-json',output],1);
assert(refused.includes('output already exists'));assert(!refused.includes('Duplicate data payloads written to '));
assert.deepEqual(fs.readFileSync(output),saved);
fs.writeFileSync(path.join(dir,'results.json'),JSON.stringify({
  file_size:data.length,input_sha256:sha(data),absent_sha256:sha(header),cli_sha256:sha(fs.readFileSync(cli)),node:process.version,
  independent_validation:'Mixed fixture validated by Node/V8 once; no instantiation or execution',summary:s,records,
},null,2)+'\n',{flag:'wx'});
console.log('Data-duplicates CLI regressions passed (4 process cases, 1 V8-validated mixed fixture). Evidence: '+dir);
