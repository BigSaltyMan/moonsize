// Exactly four analyzer calls; expected bytes/hex/ASCII come from raw Buffers.
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import {spawnSync} from 'node:child_process';

const cli=path.resolve(process.argv[2]||'_build/native/release/build/cmd/main/main.exe');
assert(fs.existsSync(cli),'Build the native CLI first.');
const parent=path.resolve('_build/data-preview-verification');fs.mkdirSync(parent,{recursive:true});
const dir=fs.mkdtempSync(path.join(parent,'run-'));
const sha=b=>crypto.createHash('sha256').update(b).digest('hex');
function leb(n){const a=[];do{const b=n&127;n>>>=7;a.push(b|(n?128:0));}while(n);return Buffer.from(a);}
const payload=Buffer.concat([Buffer.from('00094142434445464748494a4b4c4d4e4f501b7f20ff','hex'),Buffer.from('雪'),Buffer.from('0123456789abcdefghijklmnopqrstuvwxyz')]);
assert.equal(payload.length,61);
const payloads=[Buffer.from('BEFORE'),payload,Buffer.from('NEIGHBOR')];
const entries=payloads.map(p=>Buffer.concat([Buffer.from([1]),leb(p.length),p]));
const sectionPayload=Buffer.concat([leb(entries.length),...entries]);
const bytes=Buffer.concat([Buffer.from('0061736d01000000','hex'),Buffer.from([11]),leb(sectionPayload.length),sectionPayload]);
const payloadStart=8+1+leb(sectionPayload.length).length+leb(entries.length).length+entries[0].length+1+leb(payload.length).length;
const inputPath=path.join(dir,'input.wasm');fs.writeFileSync(inputPath,bytes,{flag:'wx'});
const sentinel=Buffer.from('preserve preview evidence\n'),target=path.join(dir,'existing.json');fs.writeFileSync(target,sentinel,{flag:'wx'});
const records=[];
function run(args,status){
  const p=spawnSync(cli,args,{cwd:dir,encoding:'utf8',timeout:10000});
  const text=(p.stdout||'')+(p.stderr||'');
  fs.writeFileSync(path.join(dir,'case-'+records.length+'.log'),text,{flag:'wx'});
  records.push({argv:[cli,...args],status:p.status,error:p.error?.message??null});
  fs.writeFileSync(path.join(dir,'processes.json'),JSON.stringify(records,null,2)+'\n');
  assert.ifError(p.error);assert.equal(p.signal,null);assert.equal(p.status,status,text);
  assert.equal(sha(fs.readFileSync(inputPath)),sha(bytes));assert.deepEqual(fs.readFileSync(target),sentinel);
  return text;
}
const text=run(['input.wasm','--data-preview','1','--data-offset','1','--data-limit','20'],0);
assert(text.includes('DATA PAYLOAD BYTE PREVIEW'));assert(text.includes('Returned: 20 bytes; remaining: 40 bytes'));
assert(text.includes(`Input SHA-256: ${sha(bytes)}`));assert(!text.includes('\x1b'));assert(!text.includes('\t'));assert(!text.includes('雪'));
const rows=text.split(/\r?\n/).filter(line=>/^\s*\d+\s+\d+  [a-f0-9]{2}(?: |$)/.test(line));
const expectedRows=[];
for(let pos=1;pos<21;pos+=16){
  const chunk=payload.subarray(pos,Math.min(pos+16,21));
  const hex=[...chunk].map(b=>b.toString(16).padStart(2,'0')).join(' ');
  const ascii=[...chunk].map(b=>b>=32&&b<=126?String.fromCharCode(b):'.').join('');
  expectedRows.push(String(pos).padStart(14)+'  '+String(payloadStart+pos).padStart(11)+'  '+hex.padEnd(47)+'  '+ascii);
}
assert.deepEqual(rows,expectedRows);
const saved=run(['input.wasm','--data-preview','1','--data-offset','1','--data-limit','4096','--data-preview-json','new-preview.json'],0);
assert(saved.includes('Data preview written to new-preview.json'));assert(!saved.includes('DATA PAYLOAD BYTE PREVIEW'));
const report=JSON.parse(fs.readFileSync(path.join(dir,'new-preview.json')));
assert.equal(report.format,'moonsize-data-preview');assert.equal(report.schema_version,1);
assert.equal(report.sha256,sha(bytes));assert.equal(report.file_size,bytes.length);
assert.equal(report.segment_count,3);assert.equal(report.segment.index,1);
assert.equal(report.segment.mode,'passive');assert.equal(report.segment.memory_index,null);assert.equal(report.segment.offset_expression,null);
assert.deepEqual(report.segment.payload,{file_offset:payloadStart,size:payload.length});
assert.equal(report.payload_offset,1);assert.equal(report.requested_limit,4096);assert.equal(report.returned_size,60);assert.equal(report.remaining_bytes,0);
assert.deepEqual(report.window,{file_offset:payloadStart+1,size:60});
assert.equal(report.hex,payload.subarray(1).toString('hex'));assert.equal(report.hex.length,report.returned_size*2);
assert(/^[a-f0-9]+$/.test(report.hex));
const original=fs.readFileSync(inputPath);
assert.deepEqual(Buffer.from(report.hex,'hex'),original.subarray(report.window.file_offset,report.window.file_offset+report.window.size));
assert.equal(report.segment.payload.size,report.payload_offset+report.returned_size+report.remaining_bytes);
const invalid=run(['input.wasm','--data-preview','1','--data-offset',String(payload.length+1),'--data-preview-json','must-not-exist.json'],1);
assert(invalid.includes('payload offset 62 is outside 0..61'));assert(!invalid.includes('Data preview written to'));
assert(!fs.existsSync(path.join(dir,'must-not-exist.json')));
const refused=run(['input.wasm','--data-preview','1','--data-preview-json','existing.json'],1);
assert(refused.includes('output already exists'));assert(!refused.includes('Data preview written to'));
fs.writeFileSync(path.join(dir,'results.json'),JSON.stringify({input_sha256:sha(bytes),input_size:bytes.length,
  selected_payload:{index:1,file_offset:payloadStart,size:payload.length},text_window:{payload_offset:1,file_offset:payloadStart+1,returned_size:20,remaining_bytes:40,hex:payload.subarray(1,21).toString('hex'),rows:expectedRows},
  json_window:{payload_offset:report.payload_offset,requested_limit:report.requested_limit,...report.window,returned_size:report.returned_size,remaining_bytes:report.remaining_bytes,hex:report.hex},
  records,input_and_existing_output_unchanged:true,invalid_output_absent:true,
  scope:'Four new-feature analyzer calls only; no legacy suites/scripts, source probes, V8 matrix, browser or performance checks'},null,2)+'\n',{flag:'wx'});
console.log('Data-preview regressions passed (4 process cases). Evidence: '+dir);
