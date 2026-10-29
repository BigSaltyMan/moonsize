// Exactly four analyzer calls. No old queries, V8, probes or performance runs.
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import {spawnSync} from 'node:child_process';
const cli=path.resolve(process.argv[2]||'_build/native/release/build/cmd/main/main.exe');
assert(fs.existsSync(cli),'Build the native CLI first.');
const parent=path.resolve('_build/function-path-between-verification');fs.mkdirSync(parent,{recursive:true});
const dir=fs.mkdtempSync(path.join(parent,'run-'));
const cat=(...items)=>Buffer.concat(items.map(item=>Buffer.from(item)));
const leb=n=>{const a=[];do{const b=n&127;n>>>=7;a.push(b|(n?128:0));}while(n);return Buffer.from(a);};
const str=s=>cat(leb(Buffer.byteLength(s)),Buffer.from(s));
const section=(id,payload)=>cat([id],leb(payload.length),payload);
const sha=b=>crypto.createHash('sha256').update(b).digest('hex');
function fixture(gap=false){
 const bodies=[
  [0,16,2,16,2,210,3,26,65,0,17,0,0,16,1,11],
  [0,16,4,16,0,11], [0,16,4,16,2,11], [0,16,1,11], [0,11],
  gap?[0,210,0,20,0,11]:[0,11],
 ];
 const parts=[Buffer.from('0061736d01000000','hex'),
  section(1,[1,96,0,0]),section(2,[1,1,109,1,102,0,0]),
  section(3,[6,0,0,0,0,0,0]),section(4,[1,112,0,1]),
  section(7,cat([1],str('entry'),[0,5])),
  section(9,[2,0,65,0,11,1,3,3,0,1,0]),
 ];
 const chunks=[leb(bodies.length)],relative=[];let cursor=chunks[0].length;
 for(const body of bodies){const prefix=leb(body.length);chunks.push(prefix,Buffer.from(body));relative.push(cursor+prefix.length);cursor+=prefix.length+body.length;}
 const payload=cat(...chunks),start=parts.reduce((n,b)=>n+b.length,0)+1+leb(payload.length).length;
 parts.push(section(10,payload),section(0,cat(str('name'),section(1,cat([1,2],str('shared\n\u001b雪'))))));
 return {bytes:cat(...parts),offsets:relative.map(n=>n+start),bodies};
}
const normal=fixture(),gap=fixture(true);
assert.equal(normal.bytes.length,130);assert.equal(gap.bytes.length,134);
assert.deepEqual(normal.offsets,[66,83,90,97,102,105]);
const input=path.join(dir,'between.wasm'),bad=path.join(dir,'gap.wasm'),existing=path.join(dir,'existing.json');
fs.writeFileSync(input,normal.bytes,{flag:'wx'});fs.writeFileSync(bad,gap.bytes,{flag:'wx'});
const sentinel=Buffer.from('keep path-between evidence\n');fs.writeFileSync(existing,sentinel,{flag:'wx'});
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
// Explicit raw declarations: only export function5; no start; elements3 and0.
assert.deepEqual([...normal.bytes.subarray(38,50)],[7,9,1,5,101,110,116,114,121,0,5,9]);
const rootEvidence={function_exports:[5],start:null,element_functions:[3,0],source:1,source_is_model_root:false};
assert(![...rootEvidence.function_exports,...rootEvidence.element_functions].includes(1));
const text=run(['between.wasm','--path-between','1','4'],0);
assert(text.includes('FUNCTION-TO-FUNCTION MODEL PATH'));
assert(text.includes('Query: 1 -> 4')&&text.includes('Status: found'));
assert(text.includes(JSON.stringify('shared\n\u001b雪')));
assert(text.includes('Hops: 2')&&text.includes('Prepared closure functions: 5 of 7'));
assert(text.includes('1  2  direct  67')&&text.includes('2  4  direct  84'));
assert.equal((text.match(/^\d+  (?:local|imported)  /gm)||[]).length,3);
const saved=run(['between.wasm','--path-between','1','4','--path-between-json','new-path.json'],0);
assert(saved.includes('Function path written to new-path.json'));assert(!saved.includes('FUNCTION-TO-FUNCTION MODEL PATH'));
const report=JSON.parse(fs.readFileSync(path.join(dir,'new-path.json')));
assert.equal(report.format,'moonsize-function-path-between');assert.equal(report.schema_version,1);
assert.equal(report.file_size,130);assert.equal(report.sha256,sha(normal.bytes));assert.equal(report.source.index,1);assert.equal(report.target_index,4);
assert.equal(report.status,'found');assert.equal(report.hop_count,2);assert.equal(report.prepared_closure_function_count,5);assert.equal(report.function_count,7);
assert.deepEqual(report.path_nodes.map(n=>n.index),[1,2,4]);
assert.deepEqual(report.path_edges.map(e=>[e.caller,e.callee,e.kind,e.offset]),[[1,2,'direct',67],[2,4,'direct',84]]);
assert.equal(report.path_nodes.length,report.path_edges.length+1);assert.equal(report.hop_count,report.path_edges.length);
for(let i=0;i<report.path_nodes.length;i++){
 const n=report.path_nodes[i];assert.equal(n.imported,false);assert.equal(n.encoded_size,normal.bodies[n.index-1].length+1);
 if(i<report.path_edges.length){const e=report.path_edges[i];assert.equal(e.caller,n.index);assert.equal(e.callee,report.path_nodes[i+1].index);assert.equal(normal.bytes[e.offset],16);assert.equal(normal.bytes[e.offset+1],e.callee);assert.equal(e.candidate,false);assert(!('opcode' in e));}
}
assert.equal(report.graph_complete,true);assert.equal(report.unresolved_count,0);assert.deepEqual(report.diagnostics,[]);
const strict=run(['gap.wasm','--path-between','1','4','--strict','--path-between-json','strict.json'],3);
assert(strict.includes('--strict: refusing')&&strict.includes('function 6, offset 108: call_ref'));
assert(!fs.existsSync(path.join(dir,'strict.json')));assert(!strict.includes('Function path written to'));
const refused=run(['between.wasm','--path-between','1','4','--path-between-json','existing.json'],1);
assert(refused.includes('output already exists'));assert(!refused.includes('Function path written to'));
fs.writeFileSync(path.join(dir,'results.json'),JSON.stringify({input_size:130,input_sha256:sha(normal.bytes),gap_size:134,gap_sha256:sha(gap.bytes),
 query:{source:1,target:4},root_evidence:rootEvidence,path_nodes:report.path_nodes,path_edges:report.path_edges,hop_count:report.hop_count,
 prepared_closure_function_count:report.prepared_closure_function_count,path_identity:{nodes:3,edges:2,nodes_equal_edges_plus_one:true},
 strict_diagnostic:{caller:6,offset:108,opcode:'call_ref'},strict_output_absent:true,inputs_and_existing_output_unchanged:true,records,
 scope:'Three new unit tests and four CLI cases only; no old suite/scripts, probes, V8, performance or browser'},null,2)+'\n',{flag:'wx'});
console.log('Function-path-between regressions passed (4 process cases). Evidence: '+dir);
