// Four directed process cases for the new query, using one validated fixture.
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import {spawnSync} from 'node:child_process';

const cli = path.resolve(process.argv[2] || '_build/native/release/build/cmd/main/main.exe');
assert(fs.existsSync(cli), 'Build the native CLI first.');
const parent = path.resolve('_build/function-callers-verification');
fs.mkdirSync(parent, {recursive:true});
const dir = fs.mkdtempSync(path.join(parent, 'run-'));
const cat = (...items) => Buffer.concat(items.map(item=>Buffer.from(item)));
const leb = n => { const a=[]; do { const b=n&127; n>>>=7; a.push(b|(n?128:0)); } while(n); return Buffer.from(a); };
const str = s => cat(leb(Buffer.byteLength(s)), Buffer.from(s));
const section = (id,payload) => cat([id],leb(payload.length),payload);
const bodies = [
  [0,16,0,210,0,26,65,0,17,0,0,16,0,11],
  [0,18,0,11], [0,210,0,20,0,65,0,19,0,0,11], [0,16,4,11], [0,11],
];
const parts = [Buffer.from('0061736d01000000','hex'),
  section(1,[1,96,0,0]), section(2,[1,1,109,1,102,0,0]),
  section(3,[5,0,0,0,0,0]), section(4,[1,112,0,2]),
  section(7,cat([1],str('entry'),[0,5])), section(9,[1,0,65,0,11,1,0]),
];
const chunks=[leb(bodies.length)], relative=[];
for (const body of bodies) { chunks.push(leb(body.length)); relative.push(chunks.reduce((n,b)=>n+b.length,0)); chunks.push(Buffer.from(body)); }
const code=cat(...chunks), codeStart=parts.reduce((n,b)=>n+b.length,0)+1+leb(code.length).length;
parts.push(section(10,code));
parts.push(section(0,cat(str('name'),section(1,cat([3,0],str('target"\\\n雪'),[1],str('same'),[2],str('same'))))));
const bytes=cat(...parts), offsets=relative.map(n=>n+codeStart);
assert(WebAssembly.validate(bytes), 'V8 rejected the callers fixture.'); // Exactly once.
const input=path.join(dir,'callers.wasm'), output=path.join(dir,'callers.json');
fs.writeFileSync(input,bytes,{flag:'wx'});
const sha=b=>crypto.createHash('sha256').update(b).digest('hex');
const records=[];
function run(args,status) {
  const p=spawnSync(cli,[input,...args],{cwd:dir,encoding:'utf8',timeout:10000});
  const log=p.stdout+p.stderr;
  fs.writeFileSync(path.join(dir,'case-'+records.length+'.log'),log,{flag:'wx'});
  records.push({args,status:p.status});
  assert.ifError(p.error); assert.equal(p.signal,null); assert.equal(p.status,status,log);
  assert.equal(sha(fs.readFileSync(input)),sha(bytes),'input changed');
  return log;
}
const text=run(['--callers','0','--top','1'],0);
assert(text.includes('Unique callers: 3; source instructions: 7'));
assert(text.includes('Showing 1 of 3 caller groups'));
assert(text.includes('reference taken')&&text.includes('indirect candidate'));
assert(text.includes('CALLER  KIND  OPCODE  FILE OFFSET  TYPE  TABLE'));
assert(!text.includes('Caller #2'));
const confirmation=run(['--callers','0','--top','1','--callers-json',output],0);
assert(confirmation.includes('Function callers written to '));
assert(!confirmation.includes('FUNCTION INCOMING REFERENCES'));
const saved=fs.readFileSync(output), report=JSON.parse(saved);
assert.equal(report.format,'moonsize-function-callers'); assert.equal(report.schema_version,1);
assert.equal(report.sha256,sha(bytes)); assert.equal(report.file_size,bytes.length);
assert.equal(report.target.encoded_size,null); assert.equal(report.target.imported,true);
assert.equal(report.caller_count,3); assert.equal(report.source_count,7);
assert.deepEqual(report.callers.map(g=>g.caller.index),[1,2,3]);
assert.deepEqual(report.callers[0].sources.map(s=>s.file_offset),[1,3,8,11].map(n=>offsets[0]+n));
assert.equal(report.callers[0].caller.name,report.callers[1].caller.name);
const sources=report.callers.flatMap(g=>g.sources);
assert.deepEqual(sources.map(s=>s.opcode),['call','ref.func','call_indirect','call','return_call','ref.func','return_call_indirect']);
for(const s of sources) {
  assert.equal(s.callee,0);
  assert.equal(bytes[s.file_offset],{call:16,'ref.func':210,call_indirect:17,return_call:18,return_call_indirect:19}[s.opcode]);
  assert.equal(s.candidate,s.kind==='indirect');
  assert.equal(s.table_index,s.candidate?0:null); assert.equal(s.type_index,s.candidate?0:null);
}
assert.equal(report.graph_complete,false); assert.equal(report.diagnostics.length,1);
assert.equal(report.diagnostics[0].opcode,'call_ref');
assert.equal(report.diagnostics[0].offset,offsets[2]+3);
const strictOutput=path.join(dir,'strict.json');
const refused=run(['--callers','0','--strict','--callers-json',strictOutput],3);
assert(refused.includes('--strict: refusing')); assert(!fs.existsSync(strictOutput));
assert(!refused.includes('Function callers written to'));
const existing=run(['--callers','0','--callers-json',output],1);
assert(existing.includes('output already exists')); assert(!existing.includes('Function callers written to'));
assert.deepEqual(fs.readFileSync(output),saved);
fs.writeFileSync(path.join(dir,'results.json'),JSON.stringify({input_sha256:sha(bytes),file_size:bytes.length,body_offsets:offsets,caller_count:report.caller_count,source_count:report.source_count,records},null,2)+'\n');
console.log('Function-callers CLI regressions passed (4 process cases, 1 V8-validated module). Evidence: '+dir);
