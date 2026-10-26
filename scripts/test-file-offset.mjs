// Exactly four analyzer calls. All expected ranges come from fixture encoding.
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import {spawnSync} from 'node:child_process';

const cli=path.resolve(process.argv[2]||'_build/native/release/build/cmd/main/main.exe');
assert(fs.existsSync(cli),'Build the native CLI first.');
const parent=path.resolve('_build/file-offset-verification');fs.mkdirSync(parent,{recursive:true});
const dir=fs.mkdtempSync(path.join(parent,'run-'));
const sha=b=>crypto.createHash('sha256').update(b).digest('hex');
const pieces=[Buffer.from('0061736d01000000','hex')],sections=[];
let size=8;
function add(id,hex,wide=false){
  const payload=Buffer.from(hex,'hex');assert(payload.length<128);
  const header=Buffer.from(wide?[id,payload.length|128,0]:[id,payload.length]);
  const info={index:sections.length,id,file_offset:size,header_size:header.length,payload_offset:size+header.length,payload_size:payload.length,total_size:header.length+payload.length};
  sections.push(info);pieces.push(header,payload);size+=info.total_size;return info;
}
add(0,'0178');add(1,'01600000');add(2,'01016d01660000');add(3,'020000');add(5,'010001');add(0,'0178');add(12,'02');
const code=add(10,'82008200000b02000b',true);
const data=add(11,'8200810083006162630041000b8000',true);add(0,'0178');
const bytes=Buffer.concat(pieces);assert.equal(bytes.length,78);
const functionBody={file_offset:code.payload_offset+4,size:2};
const dataPayload={file_offset:data.payload_offset+6,size:3};
const functionQuery=functionBody.file_offset+1,dataQuery=dataPayload.file_offset+1;
assert.deepEqual(bytes.subarray(functionBody.file_offset,functionBody.file_offset+functionBody.size),Buffer.from([0,11]));
assert.deepEqual(bytes.subarray(dataPayload.file_offset,dataPayload.file_offset+dataPayload.size),Buffer.from('abc'));
const inputPath=path.join(dir,'input.wasm');fs.writeFileSync(inputPath,bytes,{flag:'wx'});
const sentinel=Buffer.from('keep offset evidence\n'),target=path.join(dir,'existing.json');fs.writeFileSync(target,sentinel,{flag:'wx'});
const records=[];
function run(args,status){
  const p=spawnSync(cli,args,{cwd:dir,encoding:'utf8',timeout:10000});
  const text=(p.stdout||'')+(p.stderr||'');
  fs.writeFileSync(path.join(dir,'case-'+records.length+'.log'),text,{flag:'wx'});
  records.push({argv:[cli,...args],status:p.status,error:p.error?.message??null});
  fs.writeFileSync(path.join(dir,'processes.json'),JSON.stringify(records,null,2)+'\n');
  assert.ifError(p.error);assert.equal(p.signal,null);assert.equal(p.status,status,text);
  assert.equal(sha(fs.readFileSync(inputPath)),sha(bytes));assert.deepEqual(fs.readFileSync(target),sentinel);return text;
}
const text=run(['input.wasm','--locate-offset',String(functionQuery)],0);
assert(text.includes('WASM FILE OFFSET LOCATION'));assert(text.includes(`Query file offset: ${functionQuery} bytes`));
assert(text.includes(`Input SHA-256: ${sha(bytes)}`));assert(text.includes(`Physical section index: ${code.index}; kind: code`));
assert(text.includes(`Section file range: offset ${code.file_offset}, size ${code.total_size}; header 3, payload 9 bytes`));
assert(text.includes('Function index: 1;'));assert(text.includes('Region: function_body'));
assert(text.includes(`Region file range: offset ${functionBody.file_offset}, size 2 bytes`));assert(text.includes('Relative offset: 1 bytes'));
const saved=run(['input.wasm','--locate-offset',String(dataQuery),'--locate-offset-json','new-location.json'],0);
assert(saved.includes('File offset location written to new-location.json'));assert(!saved.includes('WASM FILE OFFSET LOCATION'));
const report=JSON.parse(fs.readFileSync(path.join(dir,'new-location.json')));
assert.equal(report.format,'moonsize-file-offset');assert.equal(report.schema_version,1);
assert.equal(report.file_size,bytes.length);assert.equal(report.sha256,sha(bytes));assert.equal(report.offset,dataQuery);
assert.equal(report.section_index,data.index);assert.equal(report.section.kind,'data');
assert.deepEqual(report.section.encoding,{file_offset:data.file_offset,size:data.total_size});
assert.deepEqual(report.section.header,{file_offset:data.file_offset,size:3});
assert.deepEqual(report.section.payload,{file_offset:data.payload_offset,size:data.payload_size});
assert.equal(report.function,null);assert.equal(report.data_segment.index,0);assert.equal(report.data_segment.mode,'passive');
assert.equal(report.data_segment.memory_index,null);assert.equal(report.data_segment.offset_expression,null);
assert.deepEqual(report.data_segment.payload,dataPayload);
assert.deepEqual(report.data_segment.encoding,{file_offset:data.payload_offset+2,size:7});
assert.deepEqual(report.region,{kind:'data_payload',...dataPayload,relative_offset:1});
assert.equal(report.offset,report.region.file_offset+report.region.relative_offset);
assert(report.region.file_offset<=dataQuery&&dataQuery<report.region.file_offset+report.region.size);
assert.equal(bytes[report.offset],0x62); // independently encoded 'b'
const invalid=run(['input.wasm','--locate-offset',String(bytes.length),'--locate-offset-json','must-not-exist.json'],1);
assert(invalid.includes('EOF has no byte'));assert(!invalid.includes('File offset location written to'));
assert(!fs.existsSync(path.join(dir,'must-not-exist.json')));
const refused=run(['input.wasm','--locate-offset',String(dataQuery),'--locate-offset-json','existing.json'],1);
assert(refused.includes('output already exists'));assert(!refused.includes('File offset location written to'));
fs.writeFileSync(path.join(dir,'results.json'),JSON.stringify({input_sha256:sha(bytes),input_size:bytes.length,sections,
  function_location:{query:functionQuery,section_index:code.index,function_index:1,kind:'function_body',...functionBody,relative_offset:1},
  data_location:{query:dataQuery,section_index:data.index,data_segment_index:0,...report.region},records,
  input_and_existing_output_unchanged:true,eof_output_absent:true,
  scope:'Four new-feature analyzer calls only; no old suites/scripts, source probes, V8 matrix, browser or benchmark'},null,2)+'\n',{flag:'wx'});
console.log('File-offset regressions passed (4 process cases). Evidence: '+dir);
