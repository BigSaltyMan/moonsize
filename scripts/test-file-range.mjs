// Exactly four analyzer calls; fixed ownership oracle from the fixture encoding.
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import {spawnSync} from 'node:child_process';
const cli=path.resolve(process.argv[2]||'_build/native/release/build/cmd/main/main.exe');
assert(fs.existsSync(cli),'Build the native CLI first.');
const parent=path.resolve('_build/file-range-verification');fs.mkdirSync(parent,{recursive:true});
const dir=fs.mkdtempSync(path.join(parent,'run-'));
const sha=b=>crypto.createHash('sha256').update(b).digest('hex');
const pieces=[Buffer.from('0061736d01000000','hex')],sections=[];
let size=8;
function add(id,hex,wide=false){
 const payload=Buffer.from(hex,'hex');assert(payload.length<128);
 const header=Buffer.from(wide?[id,payload.length|128,0]:[id,payload.length]);
 const info={index:sections.length,id,file_offset:size,header_size:header.length,payload_offset:size+header.length,payload_size:payload.length,total_size:header.length+payload.length};
 sections.push(info);pieces.push(header,payload);size+=info.total_size;
}
add(0,'0178');add(1,'01600000');add(2,'01016d01660000');add(3,'020000');add(5,'010001');add(0,'0178');add(12,'02');
add(10,'82008200000b02000b',true);add(11,'8200810083006162630041000b8000',true);add(0,'0178');
const bytes=Buffer.concat(pieces);assert.equal(bytes.length,78);
const input=path.join(dir,'input.wasm');fs.writeFileSync(input,bytes,{flag:'wx'});
const sentinel=Buffer.from('keep range evidence\n'),existing=path.join(dir,'existing.json');fs.writeFileSync(existing,sentinel,{flag:'wx'});
const query={file_offset:45,size:32};
const expected=[
 ['section_header',44,3,45,2,7,null,null],
 ['code_count',47,2,47,2,7,null,null],
 ['function_size_prefix',49,2,49,2,7,1,null],
 ['function_body',51,2,51,2,7,1,null],
 ['function_size_prefix',53,1,53,1,7,2,null],
 ['function_body',54,2,54,2,7,2,null],
 ['section_header',56,3,56,3,8,null,null],
 ['data_count',59,2,59,2,8,null,null],
 ['data_entry_metadata',61,4,61,4,8,null,0],
 ['data_payload',65,3,65,3,8,null,0],
 ['data_entry_metadata',68,6,68,6,8,null,1],
 ['section_header',74,2,74,2,9,null,null],
 ['section_payload',76,2,76,1,9,null,null],
];
const records=[];
function run(args,status){
 const p=spawnSync(cli,args,{cwd:dir,encoding:'utf8',timeout:10000});
 const text=(p.stdout||'')+(p.stderr||'');
 fs.writeFileSync(path.join(dir,'case-'+records.length+'.log'),text,{flag:'wx'});
 records.push({argv:[cli,...args],status:p.status,error:p.error?.message??null});
 fs.writeFileSync(path.join(dir,'processes.json'),JSON.stringify(records,null,2)+'\n');
 assert.ifError(p.error);assert.equal(p.signal,null);assert.equal(p.status,status,text);
 assert.equal(sha(fs.readFileSync(input)),sha(bytes));assert.deepEqual(fs.readFileSync(existing),sentinel);return text;
}
const args=['input.wasm','--locate-range','45','32','--top','1'];
const text=run(args,0);
assert(text.includes('WASM FILE RANGE OWNERSHIP'));
assert(text.includes('Query file range: [45, 77), length 32 B'));
assert(text.includes('Covered size: 32 B (all parts)'));assert(text.includes('PARTS: showing 1 of 13'));
assert(text.includes('section_header  7  45  2  44  3  n/a  n/a'));
assert(!text.includes('\ncode_count  '));assert(text.includes(sha(bytes)));
const saved=run([...args,'--locate-range-json','new-range.json'],0);
assert(saved.includes('File range ownership written to new-range.json'));assert(!saved.includes('WASM FILE RANGE OWNERSHIP'));
const report=JSON.parse(fs.readFileSync(path.join(dir,'new-range.json')));
assert.equal(report.format,'moonsize-file-range');assert.equal(report.schema_version,1);
assert.equal(report.file_size,78);assert.equal(report.sha256,sha(bytes));assert.deepEqual(report.query,query);
assert.equal(report.covered_size,32);assert.equal(report.parts.length,expected.length);
let cursor=45,total=0;
for(let i=0;i<expected.length;i++){
 const [kind,start,size,hit,covered,ordinal,fn,entry]=expected[i],part=report.parts[i];
 assert.equal(part.kind,kind);assert.equal(part.section_index,ordinal);
 assert.deepEqual(part.owner_range,{file_offset:start,size});assert.deepEqual(part.overlap_range,{file_offset:hit,size:covered});
 assert.equal(part.query_relative_offset,hit-45);assert.equal(part.owner_relative_offset,hit-start);
 assert.equal(part.function?.index??null,fn);assert.equal(part.data_segment?.index??null,entry);
 assert.equal(hit,cursor);assert(hit>=start&&hit+covered<=start+size);assert(hit+covered<=77);
 assert.deepEqual(bytes.subarray(hit,hit+covered),bytes.subarray(start,start+size).subarray(hit-start,hit-start+covered));
 assert.deepEqual(part.section.encoding,{file_offset:sections[ordinal].file_offset,size:sections[ordinal].total_size});
 if(fn!==null)assert.equal(part.function.body.size,2);
 if(entry===0)assert.deepEqual(part.data_segment.payload,{file_offset:65,size:3});
 if(entry===1)assert.deepEqual(part.data_segment.payload,{file_offset:74,size:0});
 cursor+=covered;total+=covered;
}
assert.equal(cursor,77);assert.equal(total,32);assert.equal(bytes[45],0x89);assert.equal(bytes[76],1);
const emptySaved=run(['input.wasm','--locate-range','78','0','--locate-range-json','empty.json'],0);
assert(emptySaved.includes('File range ownership written to empty.json'));
const empty=JSON.parse(fs.readFileSync(path.join(dir,'empty.json')));
assert.deepEqual(empty.query,{file_offset:78,size:0});assert.deepEqual(empty.parts,[]);assert.equal(empty.covered_size,0);assert.equal(empty.sha256,sha(bytes));
const refused=run([...args,'--locate-range-json','existing.json'],1);
assert(refused.includes('output already exists'));assert(!refused.includes('File range ownership written to'));
fs.writeFileSync(path.join(dir,'results.json'),JSON.stringify({input_size:78,input_sha256:sha(bytes),query,parts:report.parts,
 covered_size:total,part_count:expected.length,empty_query:empty.query,records,input_and_existing_output_unchanged:true,
 scope:'Exactly four new-feature CLI calls; no old suites/scripts, source probes, V8 matrix, benchmarks or browser'},null,2)+'\n',{flag:'wx'});
console.log('File-range regressions passed (4 process cases). Evidence: '+dir);
