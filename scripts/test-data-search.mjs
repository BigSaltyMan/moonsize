// Exactly four analyzer calls. Expectations come from fixture construction and
// direct input bytes, never from the analyzer's metadata or match calculation.
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import {spawnSync} from 'node:child_process';

const cli=path.resolve(process.argv[2]||'_build/native/release/build/cmd/main/main.exe');
assert(fs.existsSync(cli),'Build the native CLI first.');
const parent=path.resolve('_build/data-search-verification');fs.mkdirSync(parent,{recursive:true});
const dir=fs.mkdtempSync(path.join(parent,'run-'));
const sha=b=>crypto.createHash('sha256').update(b).digest('hex');
function leb(n){const a=[];do{const b=n&127;n>>>=7;a.push(b|(n?128:0));}while(n);return Buffer.from(a);}
const section=(id,p)=>Buffer.concat([Buffer.from([id]),leb(p.length),p]);
const payloads=[Buffer.from('aaa'),Buffer.concat([Buffer.from([0,255]),Buffer.from('雪雪'),Buffer.from('aa\0')]),Buffer.from('ab'),Buffer.from('c'),Buffer.alloc(0)];
const entries=payloads.map(p=>Buffer.concat([Buffer.from([1]),leb(p.length),p]));
const dataPayload=Buffer.concat([leb(entries.length),...entries]);
// An aa-bearing custom name is deliberately outside the searched payloads.
const prefix=Buffer.concat([Buffer.from('0061736d01000000','hex'),section(0,Buffer.from([2,97,97]))]);
const input=Buffer.concat([prefix,section(11,dataPayload)]);
const offsets=[];let cursor=prefix.length+1+leb(dataPayload.length).length+leb(entries.length).length;
for(let i=0;i<entries.length;i++){offsets.push(cursor+1+leb(payloads[i].length).length);cursor+=entries[i].length;}
const expected=[{segment_index:0,payload_offset:0,file_offset:offsets[0],size:2},
  {segment_index:0,payload_offset:1,file_offset:offsets[0]+1,size:2},
  {segment_index:1,payload_offset:8,file_offset:offsets[1]+8,size:2}];
const inputPath=path.join(dir,'input.wasm');fs.writeFileSync(inputPath,input,{flag:'wx'});
const sentinel=Buffer.from('keep existing evidence\n'),target=path.join(dir,'existing.json');fs.writeFileSync(target,sentinel,{flag:'wx'});
const records=[];
function run(args,status){
  const p=spawnSync(cli,args,{cwd:dir,encoding:'utf8',timeout:10000});
  const text=(p.stdout||'')+(p.stderr||'');
  fs.writeFileSync(path.join(dir,'case-'+records.length+'.log'),text,{flag:'wx'});
  records.push({argv:[cli,...args],status:p.status,error:p.error?.message??null});
  fs.writeFileSync(path.join(dir,'processes.json'),JSON.stringify(records,null,2)+'\n');
  assert.ifError(p.error);assert.equal(p.signal,null);assert.equal(p.status,status,text);
  assert.equal(sha(fs.readFileSync(inputPath)),sha(input));assert.deepEqual(fs.readFileSync(target),sentinel);
  return text;
}
const text=run(['input.wasm','--find-data','aa','--top','1'],0);
assert(text.includes('MATCHES: showing 1 of 3'));
assert(text.includes('Segments: 5 = matched 2 + unmatched 3'));assert(text.includes('Occurrences: 3'));
const rows=text.split(/\r?\n/).filter(line=>/^\d+  \d+  \d+  \d+$/.test(line));
assert.deepEqual(rows,[`0  0  ${offsets[0]}  2`]);
const saved=run(['input.wasm','--find-data','aa','--top','1','--find-data-json','new-search.json'],0);
assert(saved.includes('Data search written to new-search.json'));assert(!saved.includes('DATA PAYLOAD LITERAL SEARCH'));
const report=JSON.parse(fs.readFileSync(path.join(dir,'new-search.json')));
assert.equal(report.format,'moonsize-data-search');assert.equal(report.schema_version,1);
assert.equal(report.sha256,sha(input));assert.equal(report.file_size,input.length);
assert.equal(report.query,'aa');assert.equal(report.query_size,2);assert.equal(report.occurrence_count,3);
assert.deepEqual(report.matches,expected);
assert.equal(report.segment_count,5);assert.equal(report.matched_segment_count,2);assert.equal(report.unmatched_segment_count,3);
const original=fs.readFileSync(inputPath);
for(const hit of report.matches){
  assert.deepEqual(original.subarray(hit.file_offset,hit.file_offset+hit.size),Buffer.from('aa'));
  assert.equal(hit.file_offset,offsets[hit.segment_index]+hit.payload_offset);
  assert(hit.payload_offset+hit.size<=payloads[hit.segment_index].length);
}
const source=report.data_segments,summary=source.summary;
assert.equal(source.entries.length,5);assert(source.entries.every(e=>e.memory_index===null));
assert.equal(summary.total_size,summary.header_size+summary.count_size+source.entries.reduce((n,e)=>n+e.encoding.size,0));
assert.equal(summary.total_size,summary.payload_size+summary.entry_metadata_size+summary.section_overhead_size);
assert.deepEqual(source.entries.map(e=>e.payload.file_offset),offsets);
const none=run(['input.wasm','--find-data','not-present'],0);
assert(none.includes('Occurrences: 0'));assert(none.includes('No matches in data payloads.'));
assert(none.includes('Segments: 5 = matched 0 + unmatched 5'));
const refused=run(['input.wasm','--find-data','aa','--find-data-json','existing.json'],1);
assert(refused.includes('output already exists'));assert(!refused.includes('Data search written to'));
fs.writeFileSync(path.join(dir,'results.json'),JSON.stringify({input_sha256:sha(input),input_size:input.length,
  expected_matches:expected,segment_partition:{total:5,matched:2,unmatched:3},records,
  byte_ledger:summary,input_and_existing_output_unchanged:true,
  scope:'Four new-feature calls only; no legacy tests, V8 matrix, probe, browser or benchmark'},null,2)+'\n',{flag:'wx'});
console.log('Data-search regressions passed (4 process cases). Evidence: '+dir);
