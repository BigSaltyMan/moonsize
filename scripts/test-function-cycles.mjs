// Exactly four analyzer processes. No probes, V8 matrix or old regressions.
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import {spawnSync} from 'node:child_process';
const cli=path.resolve(process.argv[2]||'_build/native/release/build/cmd/main/main.exe');
assert(fs.existsSync(cli),'Build the native CLI first.');
const parent=path.resolve('_build/function-cycles-verification');fs.mkdirSync(parent,{recursive:true});
const dir=fs.mkdtempSync(path.join(parent,'run-'));
const cat=(...items)=>Buffer.concat(items.map(item=>Buffer.from(item)));
const leb=n=>{const a=[];do{const b=n&127;n>>>=7;a.push(b|(n?128:0));}while(n);return Buffer.from(a);};
const str=s=>cat(leb(Buffer.byteLength(s)),Buffer.from(s));
const section=(id,payload)=>cat([id],leb(payload.length),payload);
const sha=b=>crypto.createHash('sha256').update(b).digest('hex');
function fixture(gap=false){
 const bodies=[
  [0,16,1,16,1,11],
  [0,210,3,26,65,0,17,0,0,11],
  [0,16,2,11], [0,16,5,11], [0,11], [0,210,6,26,11],
  gap?[0,210,0,20,0,11]:[0,11],
 ];
 const parts=[Buffer.from('0061736d01000000','hex'),
  section(1,[1,96,0,0]),section(2,[1,1,109,1,102,0,0]),
  section(3,[7,0,0,0,0,0,0,0]),section(4,[1,112,0,1]),
  section(7,cat([1],str('entry'),[0,4])),
  section(9,[2,0,65,0,11,1,3,3,0,2,6,0]),
 ];
 const chunks=[leb(bodies.length)],relative=[];let cursor=chunks[0].length;
 for(const body of bodies){const prefix=leb(body.length);chunks.push(prefix,Buffer.from(body));relative.push(cursor+prefix.length);cursor+=prefix.length+body.length;}
 const payload=cat(...chunks),codeStart=parts.reduce((n,b)=>n+b.length,0)+1+leb(payload.length).length;
 parts.push(section(10,payload),section(0,cat(str('name'),section(1,cat([1,2],str('pair\n\u001b雪'))))));
 return {bytes:cat(...parts),offsets:relative.map(n=>n+codeStart),bodies};
}
const normal=fixture(),gap=fixture(true);
const input=path.join(dir,'cycles.wasm'),bad=path.join(dir,'gap.wasm'),existing=path.join(dir,'existing.json');
fs.writeFileSync(input,normal.bytes,{flag:'wx'});fs.writeFileSync(bad,gap.bytes,{flag:'wx'});
const sentinel=Buffer.from('keep cycle evidence\n');fs.writeFileSync(existing,sentinel,{flag:'wx'});
const records=[];
function run(args,status){
 const p=spawnSync(cli,args,{cwd:dir,encoding:'utf8',timeout:10000});
 const text=(p.stdout||'')+(p.stderr||'');
 fs.writeFileSync(path.join(dir,'case-'+records.length+'.log'),text,{flag:'wx'});
 records.push({argv:[cli,...args],status:p.status,error:p.error?.message??null});
 fs.writeFileSync(path.join(dir,'processes.json'),JSON.stringify(records,null,2)+'\n');
 assert.ifError(p.error);assert.equal(p.signal,null);assert.equal(p.status,status,text);
 assert.equal(sha(fs.readFileSync(input)),sha(normal.bytes));assert.equal(sha(fs.readFileSync(bad)),sha(gap.bytes));assert.deepEqual(fs.readFileSync(existing),sentinel);
 return text;
}
const text=run(['cycles.wasm','--cycles','--top','1'],0);
assert(text.includes('FUNCTION REFERENCE CYCLE COMPONENTS'));
assert(text.includes('COMPONENTS: showing 1 of 3'));
assert(text.includes('Functions: 8 = imports 1 + local 7'));
assert(text.includes('Functions: 8 = cyclic 4 + non-cyclic 4'));
assert(text.includes('Local encoded bytes: 40 = cyclic 29 + other 11'));
assert(text.includes('Member #2')&&text.includes('Member #3'));assert(!text.includes('Member #1'));
assert(text.includes('pair\\n\\u001b雪'));assert(text.includes(sha(normal.bytes)));
const saved=run(['cycles.wasm','--cycles-json','new-cycles.json','--top','1'],0);
assert(saved.includes('Function cycles written to new-cycles.json'));assert(!saved.includes('FUNCTION REFERENCE CYCLE COMPONENTS'));
const report=JSON.parse(fs.readFileSync(path.join(dir,'new-cycles.json')));
assert.equal(report.format,'moonsize-function-cycles');assert.equal(report.schema_version,1);
assert.equal(report.file_size,normal.bytes.length);assert.equal(report.sha256,sha(normal.bytes));
assert.deepEqual(report.components.map(c=>c.component_id),[2,1,6]);
assert.deepEqual(report.components.map(c=>c.members.map(n=>n.index)),[[2,3],[1],[6]]);
assert.deepEqual(report.components.map(c=>[c.local_encoded_bytes,c.internal_edge_count,c.direct_edges,c.reference_edges,c.indirect_edges]),[[16,3,1,1,1],[7,2,2,0,0],[6,1,0,1,0]]);
const off=index=>normal.offsets[index-1];
const expected=[[[2,3,'reference',off(2)+1],[2,3,'indirect',off(2)+6],[3,2,'direct',off(3)+1]],[[1,1,'direct',off(1)+1],[1,1,'direct',off(1)+3]],[[6,6,'reference',off(6)+1]]];
const seen=new Set();let cyclicBytes=0,cyclicCount=0;
for(let i=0;i<report.components.length;i++){
 const c=report.components[i];assert.deepEqual(c.internal_edges.map(e=>[e.caller,e.callee,e.kind,e.offset]),expected[i]);
 assert.equal(c.internal_edge_count,c.direct_edges+c.reference_edges+c.indirect_edges);
 let total=0;
 for(const n of c.members){assert(!seen.has(n.index));seen.add(n.index);assert.equal(n.imported,false);assert.equal(n.encoded_size,normal.bodies[n.index-1].length+1);total+=n.encoded_size;}
 assert.equal(c.local_encoded_bytes,total);cyclicBytes+=total;cyclicCount+=c.node_count;
 for(const e of c.internal_edges){assert.equal(normal.bytes[e.offset],{direct:16,reference:210,indirect:17}[e.kind]);assert.equal(e.candidate,e.kind==='indirect');assert(c.members.some(n=>n.index===e.caller)&&c.members.some(n=>n.index===e.callee));}
}
assert.equal(report.function_count,report.cyclic_function_count+report.non_cyclic_function_count);
assert.equal(report.cyclic_function_count,cyclicCount);assert.equal(cyclicCount,4);
assert.equal(report.local_encoded_bytes,report.cyclic_local_encoded_bytes+report.other_local_encoded_bytes);
assert.equal(report.cyclic_local_encoded_bytes,cyclicBytes);assert.equal(cyclicBytes,29);
assert.equal(report.graph_complete,true);assert.equal(report.unresolved_count,0);assert.deepEqual(report.diagnostics,[]);
const strict=run(['gap.wasm','--cycles','--strict','--cycles-json','strict.json'],3);
assert(strict.includes('--strict: refusing'));assert(strict.includes('call_ref'));
assert(!fs.existsSync(path.join(dir,'strict.json')));assert(!strict.includes('Function cycles written to'));
const refused=run(['cycles.wasm','--cycles-json','existing.json'],1);
assert(refused.includes('output already exists'));assert(!refused.includes('Function cycles written to'));
fs.writeFileSync(path.join(dir,'results.json'),JSON.stringify({input_size:normal.bytes.length,input_sha256:sha(normal.bytes),gap_size:gap.bytes.length,gap_sha256:sha(gap.bytes),
 body_offsets:normal.offsets,component_summary:report.components.map(c=>({id:c.component_id,members:c.members.map(n=>n.index),bytes:c.local_encoded_bytes,direct:c.direct_edges,reference:c.reference_edges,indirect:c.indirect_edges})),
 function_count:8,cyclic_function_count:4,non_cyclic_function_count:4,local_bytes:40,cyclic_bytes:29,other_bytes:11,
 gap_diagnostic:{caller:7,offset:gap.offsets[6]+3,opcode:'call_ref'},strict_output_absent:true,inputs_and_existing_output_unchanged:true,records,
 scope:'Three new unit tests and exactly four CLI cases; no old suites, probes, V8 matrix, performance or browser'},null,2)+'\n',{flag:'wx'});
console.log('Function-cycles regressions passed (4 process cases). Evidence: '+dir);
