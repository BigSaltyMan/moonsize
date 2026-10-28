// Exactly four new-feature analyzer calls. Fixed Buffers provide all expectations.
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import {spawnSync} from 'node:child_process';
const cli=path.resolve(process.argv[2]||'_build/native/release/build/cmd/main/main.exe');
assert(fs.existsSync(cli),'Build the native CLI first.');
const parent=path.resolve('_build/data-hex-search-verification');fs.mkdirSync(parent,{recursive:true});
const dir=fs.mkdtempSync(path.join(parent,'run-'));
const sha=b=>crypto.createHash('sha256').update(b).digest('hex');
const cat=(...items)=>Buffer.concat(items.map(x=>Buffer.from(x)));
function leb(n){const a=[];do{const b=n&127;n>>>=7;a.push(b|(n?128:0));}while(n);return Buffer.from(a);}
const section=(id,p)=>cat([id],leb(p.length),p);
const payloads=['00ff00ff00','6100ff0062','00ff','00','','616161'].map(hex=>Buffer.from(hex,'hex'));
const entries=payloads.map(p=>cat([1],leb(p.length),p));
const dataPayload=cat(leb(entries.length),...entries);
const prefix=cat(Buffer.from('0061736d01000000','hex'),section(0,cat([4],Buffer.from('meta'),[0,255,0])));
const input=cat(prefix,section(11,dataPayload));
assert.equal(prefix.length,18);assert.equal(input.length,49);assert.equal(dataPayload.length,29);
const offsets=[23,30,37,41,44,46],encodingOffsets=[21,28,35,39,42,44];
for(const [i,p]of payloads.entries())assert.deepEqual(input.subarray(offsets[i],offsets[i]+p.length),p);
const pattern=Buffer.from([0,255,0]);
const expected=[{segment_index:0,payload_offset:0,file_offset:23,size:3},
  {segment_index:0,payload_offset:2,file_offset:25,size:3},
  {segment_index:1,payload_offset:1,file_offset:31,size:3}];
fs.writeFileSync(path.join(dir,'input.wasm'),input,{flag:'wx'});
const sentinel=Buffer.from('keep hex-search evidence\n');fs.writeFileSync(path.join(dir,'existing.json'),sentinel,{flag:'wx'});
const records=[];
function run(args,status){
  const p=spawnSync(cli,args,{cwd:dir,encoding:'utf8',timeout:10000}),text=(p.stdout||'')+(p.stderr||'');
  fs.writeFileSync(path.join(dir,'case-'+records.length+'.log'),text,{flag:'wx'});
  records.push({argv:[cli,...args],status:p.status,error:p.error?.message??null});
  fs.writeFileSync(path.join(dir,'processes.json'),JSON.stringify(records,null,2)+'\n');
  assert.ifError(p.error);assert.equal(p.signal,null);assert.equal(p.status,status,text);
  assert.deepEqual(fs.readFileSync(path.join(dir,'input.wasm')),input);
  assert.deepEqual(fs.readFileSync(path.join(dir,'existing.json')),sentinel);return text;
}
const text=run(['input.wasm','--find-data-hex','00FF00','--top','1'],0);
assert(text.includes('DATA PAYLOAD HEX SEARCH'));assert(text.includes('Query hex: 00ff00'));assert(!text.includes('00FF00'));
assert(text.includes('Segments: 6 = matched 2 + unmatched 4'));assert(text.includes('Occurrences: 3'));assert(text.includes('MATCHES: showing 1 of 3'));
assert(text.includes('31 = payload 16 + entry metadata 12 + section overhead 3'));assert(!text.includes('\0'));
const rows=text.split(/\r?\n/).filter(line=>/^\d+  \d+  \d+  \d+$/.test(line));assert.deepEqual(rows,['0  0  23  3']);
const saved=run(['input.wasm','--find-data-hex','00ff00','--find-data-json','new-hex-search.json','--top','1'],0);
assert(saved.includes('Data hex search written to new-hex-search.json'));assert(!saved.includes('DATA PAYLOAD HEX SEARCH'));
const report=JSON.parse(fs.readFileSync(path.join(dir,'new-hex-search.json')));
assert.equal(report.format,'moonsize-data-hex-search');assert.equal(report.schema_version,1);
assert.equal(report.file_size,49);assert.equal(report.sha256,sha(input));assert.equal(report.query_hex,'00ff00');assert.equal(report.query_size,3);
assert(!Object.hasOwn(report,'query'));assert.equal(report.query_hex.length,report.query_size*2);
assert.equal(report.segment_count,6);assert.equal(report.matched_segment_count,2);assert.equal(report.unmatched_segment_count,4);
assert.equal(report.occurrence_count,3);assert.equal(report.occurrence_count,report.matches.length);assert.deepEqual(report.matches,expected);
for(const hit of report.matches){
  assert.equal(hit.file_offset,offsets[hit.segment_index]+hit.payload_offset);assert.equal(hit.size,pattern.length);
  assert(hit.payload_offset+hit.size<=payloads[hit.segment_index].length);
  assert.deepEqual(input.subarray(hit.file_offset,hit.file_offset+hit.size),pattern);
}
const source=report.data_segments,summary=source.summary;
assert.equal(typeof source,'object');assert.equal(source.format,'moonsize-data-segments');assert.equal(source.entries.length,6);
assert.equal(summary.total_size,31);assert.equal(summary.payload_size,16);assert.equal(summary.entry_metadata_size,12);
assert.equal(summary.header_size,2);assert.equal(summary.count_size,1);assert.equal(summary.section_overhead_size,3);
assert.equal(summary.total_size,summary.payload_size+summary.entry_metadata_size+summary.section_overhead_size);
assert.equal(summary.total_size,summary.header_size+summary.count_size+source.entries.reduce((n,e)=>n+e.encoding.size,0));
for(const [i,e]of source.entries.entries()){
  assert.equal(e.index,i);assert.equal(e.mode,'passive');assert.equal(e.memory_index,null);
  assert.deepEqual(e.payload,{file_offset:offsets[i],size:payloads[i].length});
  assert.deepEqual(e.encoding,{file_offset:encodingOffsets[i],size:entries[i].length});
  assert.deepEqual(input.subarray(e.encoding.file_offset,e.encoding.file_offset+e.encoding.size),entries[i]);
}
const before=fs.readdirSync(dir).filter(f=>f.endsWith('.json')).sort();
const none=run(['input.wasm','--find-data-hex','deadbeef'],0);
assert(none.includes('Occurrences: 0'));assert(none.includes('No matches in data payloads.'));assert(none.includes('Segments: 6 = matched 0 + unmatched 6'));
assert(!none.includes('Data hex search written to'));assert.deepEqual(fs.readdirSync(dir).filter(f=>f.endsWith('.json')).sort(),before);
const refused=run(['input.wasm','--find-data-hex','00ff00','--find-data-json','existing.json'],1);
assert(refused.includes('output already exists'));assert(!refused.includes('Data hex search written to'));
fs.writeFileSync(path.join(dir,'results.json'),JSON.stringify({input_sha256:sha(input),input_size:input.length,query_hex:'00ff00',query_size:3,
  expected_matches:expected,segment_partition:{total:6,matched:2,unmatched:4},byte_ledger:summary,records,input_and_existing_output_unchanged:true,
  scope:'Exactly four new-feature CLI calls; no old suites/scripts, V8/probe/performance or browser/PDF'},null,2)+'\n',{flag:'wx'});
console.log('Data-hex-search regressions passed (4 process cases). Evidence: '+dir);
