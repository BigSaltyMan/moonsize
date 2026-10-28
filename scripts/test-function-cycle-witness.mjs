// Exactly four analyzer processes. No probes, V8 matrix or old regressions.
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import {spawnSync} from 'node:child_process';
const cli=path.resolve(process.argv[2]||'_build/native/release/build/cmd/main/main.exe');
assert(fs.existsSync(cli),'Build the native CLI first.');
const parent=path.resolve('_build/function-cycle-witness-verification');fs.mkdirSync(parent,{recursive:true});
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
const sentinel=Buffer.from('keep witness evidence\n');fs.writeFileSync(existing,sentinel,{flag:'wx'});
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
const text=run(['cycles.wasm','--cycles','--cycle-witness','--top','1'],0);
assert(text.includes('FUNCTION REFERENCE CYCLE COMPONENTS')&&text.includes('CLOSED MODEL WITNESS'));
assert(text.includes('COMPONENTS: showing 1 of 3')&&text.includes('WITNESSES: showing 1 of 3'));
assert(text.includes('Component #2: 2 -> 3 -> 2'));assert(!text.includes('Component #1:'));
assert(text.includes('2 -> 3  reference taken  file offset 76'));assert(text.includes('3 -> 2  direct  file offset 87'));
assert(text.includes('pair\\n\\u001b雪'))
assert(text.includes('Functions: 8 = cyclic 4 + non-cyclic 4'));
assert(text.includes('Local encoded bytes: 40 = cyclic 29 + other 11'));
const saved=run(['cycles.wasm','--cycles-json','new-witnesses.json','--cycle-witness','--top','1'],0);
assert(saved.includes('Function cycle witnesses written to new-witnesses.json'));assert(!saved.includes('CLOSED MODEL WITNESS'));
const report=JSON.parse(fs.readFileSync(path.join(dir,'new-witnesses.json'))),cycles=report.cycles;
assert.equal(report.format,'moonsize-function-cycle-witnesses');assert.equal(report.schema_version,1);
assert.equal(typeof cycles,'object');assert.equal(cycles.format,'moonsize-function-cycles');assert.equal(cycles.schema_version,1);
assert.equal(cycles.file_size,128);assert.equal(cycles.sha256,sha(normal.bytes));
assert.equal(sha(normal.bytes),'4f874186738dda2f384fc38b841fe59b9c208937fadc96754b4286d9948615c7');
assert.deepEqual(cycles.components.map(c=>c.component_id),[2,1,6]);
assert.deepEqual(cycles.components.map(c=>c.members.map(n=>n.index)),[[2,3],[1],[6]]);
assert.deepEqual(cycles.components.map(c=>[c.internal_edge_count,c.direct_edges,c.reference_edges,c.indirect_edges,c.local_encoded_bytes]),[[3,1,1,1,16],[2,2,0,0,7],[1,0,1,0,6]]);
const expectedBase=[[[2,3,'reference',76],[2,3,'indirect',81],[3,2,'direct',87]],[[1,1,'direct',69],[1,1,'direct',71]],[[6,6,'reference',100]]];
const expectedWitness=[[[2,3,'reference',76],[3,2,'direct',87]],[[1,1,'direct',69]],[[6,6,'reference',100]]];
const expectedNodes=[[2,3,2],[1,1],[6,6]];
assert.equal(report.witnesses.length,cycles.component_count);assert.equal(report.witnesses.length,3);
for(let i=0;i<3;i++){
 const c=cycles.components[i],w=report.witnesses[i];
 assert.deepEqual(c.internal_edges.map(e=>[e.caller,e.callee,e.kind,e.offset]),expectedBase[i]);
 assert.deepEqual(w.nodes,expectedNodes[i]);assert.deepEqual(w.edges.map(e=>[e.caller,e.callee,e.kind,e.offset]),expectedWitness[i]);
 assert.equal(w.component_id,c.component_id);assert.equal(w.start_index,c.component_id);
 assert(w.edge_count>=1);assert.equal(w.edge_count,w.edges.length);assert.equal(w.nodes.length,w.edge_count+1);
 assert.equal(w.nodes[0],w.start_index);assert.equal(w.nodes.at(-1),w.start_index);
 assert.equal(new Set(w.nodes.slice(0,-1)).size,w.edge_count);
 assert.equal(w.edge_count,w.direct_edges+w.reference_edges+w.indirect_edges);
 assert.equal(w.direct_edges,w.edges.filter(e=>e.kind==='direct').length);
 assert.equal(w.reference_edges,w.edges.filter(e=>e.kind==='reference').length);
 assert.equal(w.indirect_edges,w.edges.filter(e=>e.kind==='indirect').length);
 for(let j=0;j<w.edges.length;j++){
  const e=w.edges[j];assert.equal(e.caller,w.nodes[j]);assert.equal(e.callee,w.nodes[j+1]);
  assert(c.members.some(n=>n.index===e.caller)&&c.members.some(n=>n.index===e.callee));
  assert(c.internal_edges.some(original=>JSON.stringify(original)===JSON.stringify(e)));
  assert.equal(normal.bytes[e.offset],{direct:16,reference:210,indirect:17}[e.kind]);
  assert.equal(e.candidate,e.kind==='indirect');
 }
}
assert.equal(cycles.cyclic_function_count,4);assert.equal(cycles.local_encoded_bytes,40);assert.equal(cycles.cyclic_local_encoded_bytes,29);
assert.equal(cycles.other_local_encoded_bytes,11);assert.equal(cycles.graph_complete,true);assert.equal(cycles.unresolved_count,0);assert.deepEqual(cycles.diagnostics,[]);
assert.equal(cycles.components[1].internal_edge_count,2);assert.equal(report.witnesses[1].edge_count,1);
const strict=run(['gap.wasm','--cycles','--cycle-witness','--strict','--cycles-json','strict.json'],3);
assert(strict.includes('--strict: refusing')&&strict.includes('function 7, offset 108: call_ref'));
assert(!fs.existsSync(path.join(dir,'strict.json')));assert(!strict.includes('written to'));
const refused=run(['cycles.wasm','--cycle-witness','--cycles-json','existing.json'],1);
assert(refused.includes('output already exists'));assert(!refused.includes('Function cycle witnesses written to'));
fs.writeFileSync(path.join(dir,'results.json'),JSON.stringify({input_size:normal.bytes.length,input_sha256:sha(normal.bytes),gap_size:gap.bytes.length,gap_sha256:sha(gap.bytes),
 witnesses:report.witnesses,component_edge_counts:cycles.components.map(c=>c.internal_edge_count),component_encoded_bytes:cycles.components.map(c=>c.local_encoded_bytes),
 original_edge_count:6,witness_edge_count:4,strict_diagnostic:{caller:7,offset:108,opcode:'call_ref'},strict_output_absent:true,inputs_and_existing_output_unchanged:true,records,
 scope:'Exactly four new-feature CLI calls; no old queries/scripts, probes, V8 matrix, performance or browser'},null,2)+'\n',{flag:'wx'});
console.log('Function-cycle-witness regressions passed (4 process cases). Evidence: '+dir);
