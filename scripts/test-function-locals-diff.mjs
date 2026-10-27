// Exactly four analyzer processes. Fixed Buffers and BigInt are the oracle.
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import {spawnSync} from 'node:child_process';
const cli=path.resolve(process.argv[2]||'_build/native/release/build/cmd/main/main.exe');
assert(fs.existsSync(cli),'Build the native CLI first.');
const parent=path.resolve('_build/function-locals-diff-verification');fs.mkdirSync(parent,{recursive:true});
const dir=fs.mkdtempSync(path.join(parent,'run-'));
const cat=(...items)=>Buffer.concat(items.map(item=>Buffer.from(item)));
const sha=b=>crypto.createHash('sha256').update(b).digest('hex');
const beforeBody=Buffer.from('04027f007f017e006370ff','hex');
const afterBody=Buffer.from('850082007f007f017f00637003638000ffff','hex');
const pre=Buffer.from('0061736d01000000010401600000','hex');
const beforePrefix=cat(pre,Buffer.from('020701016d016600000303020000','hex'));
const afterPrefix=cat(pre,Buffer.from('020d02016d01660000016d016700000303020000','hex'));
const section=p=>cat([10,p.length],p);
const before=cat(beforePrefix,section(cat([2,0x8b,0],beforeBody,[2,0,255])));
const after=cat(afterPrefix,section(cat([2,0x82,0,0,255,18],afterBody)));
assert.equal(before.length,47);assert.equal(after.length,60);
const fixtures={baseline:{bytes:before,index:1,entry:31,prefix:2,body:33,bodySize:11,countSize:1,locals:10,remainder:1,
  groups:[{quantity:2,type:'7f',qhex:'02',offset:34},{quantity:0,type:'7f',qhex:'00',offset:36},{quantity:1,type:'7e',qhex:'01',offset:38},{quantity:0,type:'6370',qhex:'00',offset:40}]},
 current:{bytes:after,index:3,entry:41,prefix:1,body:42,bodySize:18,countSize:2,locals:16,remainder:2,
  groups:[{quantity:2,type:'7f',qhex:'8200',offset:44},{quantity:0,type:'7f',qhex:'00',offset:47},{quantity:1,type:'7f',qhex:'01',offset:49},{quantity:0,type:'6370',qhex:'00',offset:51},{quantity:3,type:'638000',qhex:'03',offset:54}]}};
fs.writeFileSync(path.join(dir,'before.wasm'),before,{flag:'wx'});fs.writeFileSync(path.join(dir,'after.wasm'),after,{flag:'wx'});
const sentinel=Buffer.from('keep locals comparison\n');fs.writeFileSync(path.join(dir,'existing.json'),sentinel,{flag:'wx'});
const records=[];
function run(args,status){
  const p=spawnSync(cli,args,{cwd:dir,encoding:'utf8',timeout:10000}),text=(p.stdout||'')+(p.stderr||'');
  fs.writeFileSync(path.join(dir,'case-'+records.length+'.log'),text,{flag:'wx'});
  records.push({argv:[cli,...args],status:p.status,error:p.error?.message??null});
  fs.writeFileSync(path.join(dir,'processes.json'),JSON.stringify(records,null,2)+'\n');
  assert.ifError(p.error);assert.equal(p.signal,null);assert.equal(p.status,status,text);
  assert.deepEqual(fs.readFileSync(path.join(dir,'before.wasm')),before);assert.deepEqual(fs.readFileSync(path.join(dir,'after.wasm')),after);
  assert.deepEqual(fs.readFileSync(path.join(dir,'existing.json')),sentinel);return text;
}
const args=['after.wasm','--locals','3','--baseline','before.wasm','--baseline-locals','1'];
const text=run([...args,'--top','1'],0);
assert(text.includes('FUNCTION LOCAL DECLARATIONS COMPARISON'));assert(text.includes('Baseline: function 1'));
assert(text.includes('Current: function 3'));assert(text.includes('TYPE ENCODINGS: showing 1 of 4'));
assert.equal(text.split(/\r?\n/).filter(line=>/^[0-9a-f]+  (unknown|i32|i64)  (shared_encoding|baseline_only|current_only)/.test(line)).length,1);
assert(text.includes('Declared count (excluding parameters)  3  6  3'));
assert(text.includes('Entry bytes  13  19  6'));assert(text.includes('Prefix bytes  2  1  -1'));
const saved=run([...args,'--locals-json','new-diff.json','--top','1'],0);
assert(saved.includes('Function locals comparison written to new-diff.json'));assert(!saved.includes('FUNCTION LOCAL DECLARATIONS COMPARISON'));
const report=JSON.parse(fs.readFileSync(path.join(dir,'new-diff.json')));
assert.equal(report.format,'moonsize-function-locals-diff');assert.equal(report.schema_version,1);
function checkSide(got,want){
  assert.equal(typeof got,'object');assert.equal(got.format,'moonsize-function-locals');assert.equal(got.schema_version,1);
  assert.equal(got.sha256,sha(want.bytes));assert.equal(got.file_size,want.bytes.length);assert.equal(got.target.index,want.index);
  assert.equal(got.target.imported,false);assert.equal(got.groups.length,want.groups.length);
  assert.deepEqual(got.entry,{file_offset:want.entry,size:want.prefix+want.bodySize});
  assert.deepEqual(got.prefix,{file_offset:want.entry,size:want.prefix});assert.deepEqual(got.body,{file_offset:want.body,size:want.bodySize});
  assert.deepEqual(got.locals_encoding,{file_offset:want.body,size:want.locals});
  assert.deepEqual(got.group_count_encoding,{file_offset:want.body,size:want.countSize});
  assert.deepEqual(got.body_remainder,{file_offset:want.body+want.locals,size:want.remainder});
  let sum=0n,qbytes=0,tbytes=0;
  for(const [i,g]of got.groups.entries()){
    const w=want.groups[i],qs=w.qhex.length/2,ts=w.type.length/2;
    assert.equal(g.group_index,i);assert.equal(g.quantity,w.quantity);assert.equal(typeof g.quantity,'number');
    assert.equal(g.declared_ordinal_start_decimal,sum.toString());sum+=BigInt(w.quantity);assert.equal(g.declared_ordinal_end_decimal,sum.toString());
    assert.equal(g.type_hex,w.type);assert.equal(g.type_label,w.type==='7f'?'i32':w.type==='7e'?'i64':null);
    assert.deepEqual(g.encoding,{file_offset:w.offset,size:qs+ts});
    assert.deepEqual(g.quantity_encoding,{file_offset:w.offset,size:qs});assert.deepEqual(g.type_encoding,{file_offset:w.offset+qs,size:ts});
    assert.equal(want.bytes.subarray(w.offset,w.offset+qs).toString('hex'),w.qhex);
    assert.equal(want.bytes.subarray(w.offset+qs,w.offset+qs+ts).toString('hex'),w.type);
    qbytes+=qs;tbytes+=ts;
  }
  assert.equal(got.declared_count_decimal,sum.toString());assert.equal(got.quantity_encoding_bytes,qbytes);assert.equal(got.type_encoding_bytes,tbytes);
  assert.equal(got.locals_encoding.size,want.countSize+qbytes+tbytes);
}
checkSide(report.baseline,fixtures.baseline);checkSide(report.current,fixtures.current);
assert.equal(before.subarray(31,33).toString('hex'),'8b00');assert.equal(after[41],18);
assert.equal(after.subarray(42,44).toString('hex'),'8500');
const expectedDelta={entry_bytes:6,prefix_bytes:-1,body_bytes:7,locals_bytes:6,group_count_encoding_bytes:1,quantity_encoding_bytes:2,type_encoding_bytes:3,body_remainder_bytes:1,group_count:1,declared_count_delta_decimal:'3'};
assert.deepEqual(report.delta,expectedDelta);
assert.deepEqual(report.type_encodings.map(r=>r.type_hex),['6370','638000','7e','7f']);
const expectedRows=[{hex:'6370',b:[3],c:[3],presence:'shared_encoding'}, {hex:'638000',b:[],c:[4],presence:'current_only'},
  {hex:'7e',b:[2],c:[],presence:'baseline_only'},{hex:'7f',b:[0,1],c:[0,1,2],presence:'shared_encoding'}];
let beforeBytes=0,afterBytes=0,groupDelta=0,quantityDelta=0n;
for(const [i,row]of report.type_encodings.entries()){
  const expected=expectedRows[i];assert.equal(row.presence,expected.presence);
  for(const [side,indices]of [['baseline',expected.b],['current',expected.c]]){
    const got=row[side],groups=indices.map(n=>fixtures[side].groups[n]);
    assert.deepEqual(got.group_indices,indices);assert.equal(got.group_count,indices.length);
    assert.equal(got.declared_count_decimal,groups.reduce((n,g)=>n+BigInt(g.quantity),0n).toString());
    assert.equal(got.quantity_encoding_bytes,groups.reduce((n,g)=>n+g.qhex.length/2,0));
    assert.equal(got.type_encoding_bytes,groups.reduce((n,g)=>n+g.type.length/2,0));
    assert.equal(got.group_bytes,got.quantity_encoding_bytes+got.type_encoding_bytes);
  }
  for(const key of ['group_count','quantity_encoding_bytes','type_encoding_bytes','group_bytes'])assert.equal(row.delta[key],row.current[key]-row.baseline[key]);
  assert.equal(row.delta.declared_count_delta_decimal,(BigInt(row.current.declared_count_decimal)-BigInt(row.baseline.declared_count_decimal)).toString());
  beforeBytes+=row.baseline.group_bytes;afterBytes+=row.current.group_bytes;groupDelta+=row.delta.group_bytes;quantityDelta+=BigInt(row.delta.declared_count_delta_decimal);
}
assert.equal(beforeBytes,9);assert.equal(afterBytes,14);assert.equal(groupDelta,5);assert.equal(quantityDelta,3n);
const selfArgs=['after.wasm','--locals','3','--baseline','after.wasm','--baseline-locals','3','--locals-json','self-diff.json'];
run(selfArgs,0);const self=JSON.parse(fs.readFileSync(path.join(dir,'self-diff.json')));
assert.deepEqual(self.baseline,self.current);checkSide(self.current,fixtures.current);
for(const [key,value]of Object.entries(self.delta))assert.equal(value,key.endsWith('_decimal')?'0':0);
for(const row of self.type_encodings){assert.deepEqual(row.baseline,row.current);for(const [key,value]of Object.entries(row.delta))assert.equal(value,key.endsWith('_decimal')?'0':0);}
assert.deepEqual(self.type_encodings.find(r=>r.type_hex==='7f').current.group_indices,[0,1,2]);
const refused=run([...args,'--locals-json','existing.json'],1);
assert(refused.includes('output already exists'));assert(!refused.includes('Function locals comparison written to'));
fs.writeFileSync(path.join(dir,'results.json'),JSON.stringify({baseline_sha256:sha(before),current_sha256:sha(after),baseline_index:1,current_index:3,
  byte_and_count_delta:expectedDelta,type_encodings:report.type_encodings,records,inputs_and_existing_output_unchanged:true,
  scope:'Four new-feature calls only; no old suites/scripts, probes, V8 matrix, browser/PDF or benchmark'},null,2)+'\n',{flag:'wx'});
console.log('Function-locals-diff regressions passed (4 process cases). Evidence: '+dir);
