// Exactly four analyzer calls. Expectations derive only from fixed source Buffers.
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import {spawnSync} from 'node:child_process';
const cli=path.resolve(process.argv[2]||'_build/native/release/build/cmd/main/main.exe');
assert(fs.existsSync(cli),'Build the native CLI first.');
const parent=path.resolve('_build/data-preview-diff-verification');fs.mkdirSync(parent,{recursive:true});
const dir=fs.mkdtempSync(path.join(parent,'run-'));
const sha=b=>crypto.createHash('sha256').update(b).digest('hex');
const cat=(...items)=>Buffer.concat(items.map(x=>Buffer.from(x)));
function leb(n){const a=[];do{const b=n&127;n>>>=7;a.push(b|(n?128:0));}while(n);return Buffer.from(a);}
function moduleBytes(payloads){const p=cat(leb(payloads.length),...payloads.map(b=>cat([1],leb(b.length),b)));return cat(Buffer.from('0061736d01000000','hex'),[11],leb(p.length),p);}
const baseline=moduleBytes([Buffer.from('unused'),Buffer.from('9900ff414200','hex'),Buffer.from('end')]);
const current=moduleBytes([Buffer.from('x'),Buffer.from('yz'),Buffer.from('556677007f414200101112131415161718191a1b1c','hex')]);
const beforeWindow=Buffer.from('00ff414200','hex'),afterWindow=Buffer.from('007f414200101112131415161718191a1b1c','hex');
assert.equal(baseline.length,32);assert.equal(current.length,41);assert.equal(beforeWindow.length,5);assert.equal(afterWindow.length,18);
assert.deepEqual(baseline.subarray(22,27),beforeWindow);assert.deepEqual(current.subarray(23,41),afterWindow);
fs.writeFileSync(path.join(dir,'baseline.wasm'),baseline,{flag:'wx'});fs.writeFileSync(path.join(dir,'current.wasm'),current,{flag:'wx'});
const sentinel=Buffer.from('keep window-comparison evidence\n');fs.writeFileSync(path.join(dir,'existing.json'),sentinel,{flag:'wx'});
const records=[];
function run(args,status){
  const p=spawnSync(cli,args,{cwd:dir,encoding:'utf8',timeout:10000}),text=(p.stdout||'')+(p.stderr||'');
  fs.writeFileSync(path.join(dir,'case-'+records.length+'.log'),text,{flag:'wx'});
  records.push({argv:[cli,...args],status:p.status,error:p.error?.message??null});
  fs.writeFileSync(path.join(dir,'processes.json'),JSON.stringify(records,null,2)+'\n');
  assert.ifError(p.error);assert.equal(p.signal,null);assert.equal(p.status,status,text);
  assert.deepEqual(fs.readFileSync(path.join(dir,'baseline.wasm')),baseline);assert.deepEqual(fs.readFileSync(path.join(dir,'current.wasm')),current);
  assert.deepEqual(fs.readFileSync(path.join(dir,'existing.json')),sentinel);return text;
}
const args=['current.wasm','--data-preview','2','--data-offset','3','--data-limit','32','--baseline','baseline.wasm','--baseline-data-preview','1','--baseline-data-offset','1'];
const text=run(args,0);
assert(text.includes('DATA PAYLOAD WINDOW COMPARISON'));assert(text.includes('Segment: 1; payload offset: 1; limit: 32'));assert(text.includes('Segment: 2; payload offset: 3; limit: 32'));
assert(text.includes('Window file range: offset 22, size 5 bytes'));assert(text.includes('Window file range: offset 23, size 18 bytes'));
assert(text.includes('Compared positions: 18 = same 4 + different 1 + baseline-only 0 + current-only 13'));
assert(text.includes('Returned-size delta: 13 = current-only 13 - baseline-only 0'));assert(text.includes(sha(baseline)));assert(text.includes(sha(current)));
const rows=text.split(/\r?\n/).filter(s=>/^\s*\d+  /.test(s));
const expectedRows=[];
const expectedPositions=Array.from({length:18},(_,i)=>({window_relative_offset:i,status:i<5?(beforeWindow[i]===afterWindow[i]?'same_byte':'different_byte'):'current_only',
  baseline_byte:i<5?beforeWindow[i]:null,current_byte:afterWindow[i],baseline_file_offset:i<5?22+i:null,current_file_offset:23+i}));
for(let start=0;start<18;start+=16){
  const chunk=expectedPositions.slice(start,start+16),hex=value=>value===null?'--':value.toString(16).padStart(2,'0');
  expectedRows.push(String(start).padStart(13)+'  '+chunk.map(p=>hex(p.baseline_byte)).join(' ').padEnd(47)+'  '+chunk.map(p=>hex(p.current_byte)).join(' ').padEnd(47)+'  '+chunk.map(p=>({same_byte:'.',different_byte:'^',baseline_only:'B',current_only:'C'}[p.status])).join(' '));
}
assert.deepEqual(rows,expectedRows);assert.equal(rows.length,2);assert(rows[0].includes('00 ff 41 42 00 --'));
const saved=run([...args,'--data-preview-json','new-window-diff.json'],0);
assert(saved.includes('Data preview comparison written to new-window-diff.json'));assert(!saved.includes('DATA PAYLOAD WINDOW COMPARISON'));
const report=JSON.parse(fs.readFileSync(path.join(dir,'new-window-diff.json')));
assert.equal(report.format,'moonsize-data-preview-diff');assert.equal(report.schema_version,1);
const counts={same_count:4,different_count:1,baseline_only_count:0,current_only_count:13,compared_positions:18,returned_size_delta:13};
for(const[k,v]of Object.entries(counts))assert.equal(report[k],v,k);
assert.deepEqual(report.positions,expectedPositions);
for(const [side,bytes,index,payloadOffset,payloadStart,payloadSize,windowStart,windowSize,expected]of [
  [report.baseline,baseline,1,1,21,6,22,5,beforeWindow],
  [report.current,current,2,3,20,21,23,18,afterWindow],
]){
  assert.equal(typeof side,'object');assert.equal(side.format,'moonsize-data-preview');assert.equal(side.schema_version,1);
  assert.equal(side.file_size,bytes.length);assert.equal(side.sha256,sha(bytes));assert.equal(side.segment_count,3);assert.equal(side.segment.index,index);
  assert.equal(side.segment.mode,'passive');assert.equal(side.segment.memory_index,null);assert.equal(side.segment.offset_expression,null);
  assert.deepEqual(side.segment.payload,{file_offset:payloadStart,size:payloadSize});
  assert.equal(side.payload_offset,payloadOffset);assert.equal(side.requested_limit,32);assert.equal(side.returned_size,windowSize);assert.equal(side.remaining_bytes,0);
  assert.deepEqual(side.window,{file_offset:windowStart,size:windowSize});assert.equal(side.hex,expected.toString('hex'));
  assert.deepEqual(Buffer.from(side.hex,'hex'),bytes.subarray(side.window.file_offset,side.window.file_offset+side.window.size));
  assert.equal(side.segment.payload.size,side.payload_offset+side.returned_size+side.remaining_bytes);
}
function ledger(r){
  assert.equal(r.compared_positions,Math.max(r.baseline.returned_size,r.current.returned_size));assert.equal(r.positions.length,r.compared_positions);
  assert.equal(r.compared_positions,r.same_count+r.different_count+r.baseline_only_count+r.current_only_count);
  assert.equal(r.baseline.returned_size,r.same_count+r.different_count+r.baseline_only_count);
  assert.equal(r.current.returned_size,r.same_count+r.different_count+r.current_only_count);
  assert.equal(r.returned_size_delta,r.current_only_count-r.baseline_only_count);
}
ledger(report);
for(const p of report.positions){
  if(p.baseline_file_offset===null){assert.equal(p.baseline_byte,null);}else{assert.equal(baseline[p.baseline_file_offset],p.baseline_byte);}
  assert.equal(current[p.current_file_offset],p.current_byte);
}
assert.equal(report.positions[0].baseline_byte,0);assert.equal(report.positions[5].baseline_byte,null);
run(['current.wasm','--data-preview','2','--data-offset','3','--data-limit','32','--baseline','current.wasm','--baseline-data-preview','2','--baseline-data-offset','3','--data-preview-json','self.json'],0);
const self=JSON.parse(fs.readFileSync(path.join(dir,'self.json')));ledger(self);assert.deepEqual(self.baseline,self.current);
assert.equal(self.same_count,18);assert.equal(self.different_count+self.baseline_only_count+self.current_only_count,0);assert.equal(self.returned_size_delta,0);
for(const p of self.positions){assert.equal(p.status,'same_byte');assert.equal(p.baseline_byte,current[23+p.window_relative_offset]);assert.equal(p.current_byte,p.baseline_byte);}
const refused=run([...args,'--data-preview-json','existing.json'],1);
assert(refused.includes('output already exists'));assert(!refused.includes('Data preview comparison written to'));
fs.writeFileSync(path.join(dir,'results.json'),JSON.stringify({baseline_sha256:sha(baseline),current_sha256:sha(current),file_sizes:[32,41],
  selection:{baseline:{index:1,payload_offset:1,file_offset:22,size:5},current:{index:2,payload_offset:3,file_offset:23,size:18},limit:32},
  counts,positions:expectedPositions,records,inputs_and_existing_output_unchanged:true,
  scope:'Exactly four new-feature CLI calls; no old tests/scripts, probe/V8/performance or browser/PDF'},null,2)+'\n',{flag:'wx'});
console.log('Data-preview-diff regressions passed (4 process cases). Evidence: '+dir);
