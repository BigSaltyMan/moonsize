// Exactly four analyzer calls. No old queries, V8, probes or performance runs.
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import {spawnSync} from 'node:child_process';
const cli=path.resolve(process.argv[2]||'_build/native/release/build/cmd/main/main.exe');
assert(fs.existsSync(cli),'Build the native CLI first.');
const parent=path.resolve('_build/function-dependents-verification');fs.mkdirSync(parent,{recursive:true});
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
const input=path.join(dir,'dependents.wasm'),bad=path.join(dir,'gap.wasm'),existing=path.join(dir,'existing.json');
fs.writeFileSync(input,normal.bytes,{flag:'wx'});fs.writeFileSync(bad,gap.bytes,{flag:'wx'});
const sentinel=Buffer.from('keep dependent evidence\n');fs.writeFileSync(existing,sentinel,{flag:'wx'});
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
const text=run(['dependents.wasm','--dependents','2','--top','1'],0);
assert(text.includes('FUNCTION TRANSITIVE MODEL REFERRERS'));
assert(text.includes('REFERRERS: showing 1 of 3 (target excluded)'));
assert(text.includes('Target #2:'));assert(text.includes('shared\\n\\u001b雪'));
assert.equal((text.match(/^\d+  \d+  (?:local|imported)  /gm)||[]).length,1);
assert(text.includes('1  1  local  17  '));assert(text.includes('2 / direct / 67'));
assert(text.includes('Functions: 7 = reaching 4 + other 3'));
assert(text.includes('Local encoded bytes: 42 = reaching 36 + other 6'));
assert(text.includes('Reaching local encoded bytes: 36 = target 7 + dependents 29'));
assert(text.includes('Complete closure edges: 9 = direct 7 + reference 1 + indirect candidates 1'));
assert(text.includes('Next-edge tree edges: 3'));
const saved=run(['dependents.wasm','--dependents','2','--dependents-json','new-dependents.json','--top','1'],0);
assert(saved.includes('Function dependents written to new-dependents.json'));assert(!saved.includes('FUNCTION TRANSITIVE MODEL REFERRERS'));
const report=JSON.parse(fs.readFileSync(path.join(dir,'new-dependents.json')));
assert.equal(report.format,'moonsize-function-dependents');assert.equal(report.schema_version,1);
assert.equal(report.file_size,130);assert.equal(report.sha256,sha(normal.bytes));assert.equal(report.target.index,2);
assert.deepEqual(report.nodes.map(e=>[e.node.index,e.depth]),[[2,0],[1,1],[3,1],[4,2]]);
const tuple=e=>[e.caller,e.callee,e.kind,e.offset];
const nextEdges=[null,[1,2,'direct',67],[3,2,'direct',93],[4,1,'direct',98]];
assert.deepEqual(report.nodes.map(e=>e.next_edge===null?null:tuple(e.next_edge)),nextEdges);
const expected=[
 [1,2,'direct',67],[1,2,'direct',69],[1,3,'reference',71],[1,3,'indirect',76],[1,1,'direct',79],
 [2,4,'direct',84],[3,4,'direct',91],[3,2,'direct',93],[4,1,'direct',98],
];
assert.deepEqual(report.edges.map(tuple),expected);
assert.deepEqual([...normal.bytes.subarray(86,88)],[16,0]);
assert(!report.nodes.some(e=>e.node.index===0));assert(!report.edges.some(e=>e.offset===86));
const seen=new Set(),depths=new Map(report.nodes.map(e=>[e.node.index,e.depth]));let reachedBytes=0,tree=0;
for(const e of report.nodes){
 const n=e.node;assert(!seen.has(n.index));seen.add(n.index);
 if(n.imported){assert.equal(n.index,0);assert.equal(n.encoded_size,null);assert.equal(n.import_module,'m');assert.equal(n.import_name,'f');}
 else{assert.equal(n.encoded_size,normal.bodies[n.index-1].length+1);reachedBytes+=n.encoded_size;}
 if(e.next_edge!==null){assert.equal(e.next_edge.caller,n.index);assert.equal(e.depth,depths.get(e.next_edge.callee)+1);assert(report.edges.some(edge=>JSON.stringify(edge)===JSON.stringify(e.next_edge)));tree++;}
 else{assert.equal(n.index,2);assert.equal(e.depth,0);}
}
const byIndex=new Map(report.nodes.map(e=>[e.node.index,e]));
for(const node of report.nodes){let cursor=node.node.index;for(let step=0;step<node.depth;step++){const row=byIndex.get(cursor);assert(row.next_edge!==null);cursor=row.next_edge.callee;}assert.equal(cursor,2);}
for(const e of report.edges){assert(seen.has(e.caller)&&seen.has(e.callee));assert.equal(normal.bytes[e.offset],{direct:16,reference:210,indirect:17}[e.kind]);assert.equal(e.candidate,e.kind==='indirect');}
assert.equal(tree,3);assert.equal(report.edge_count,9);assert.equal(reachedBytes,36);
assert.equal(report.function_count,report.reaching_function_count+report.other_function_count);
assert.equal(report.reaching_function_count,report.reaching_local_count+report.reaching_imported_count);
assert.equal(report.reaching_function_count,4);assert.equal(report.reaching_local_count,4);assert.equal(report.reaching_imported_count,0);
assert.equal(report.dependent_function_count,report.reaching_function_count-1);
assert.equal(report.local_encoded_bytes,report.reaching_local_encoded_bytes+report.other_local_encoded_bytes);
assert.equal(report.reaching_local_encoded_bytes,report.target_local_encoded_bytes+report.dependent_local_encoded_bytes);
assert.equal(report.target_local_encoded_bytes,7);assert.equal(report.dependent_local_encoded_bytes,29);
assert.equal(report.edge_count,report.direct_edges+report.reference_edges+report.indirect_edges);
assert.equal(report.graph_complete,true);assert.equal(report.unresolved_count,0);assert.deepEqual(report.diagnostics,[]);
const strict=run(['gap.wasm','--dependents','2','--strict','--dependents-json','strict.json'],3);
assert(strict.includes('--strict: refusing')&&strict.includes('function 6, offset 108: call_ref'));
assert(!fs.existsSync(path.join(dir,'strict.json')));assert(!strict.includes('Function dependents written to'));
const refused=run(['dependents.wasm','--dependents','2','--dependents-json','existing.json'],1);
assert(refused.includes('output already exists'));assert(!refused.includes('Function dependents written to'));
fs.writeFileSync(path.join(dir,'results.json'),JSON.stringify({input_size:130,input_sha256:sha(normal.bytes),gap_size:134,gap_sha256:sha(gap.bytes),
 target:2,nodes:report.nodes,edges:report.edges,tree_edge_count:tree,complete_edge_count:9,
 excluded_outgoing_edge:{caller:2,callee:0,kind:"direct",offset:86,raw_bytes:[16,0]},
 ledger:{function_count:7,reaching:4,other:3,reaching_local:4,reaching_imported:0,dependents:3,local_bytes:42,reaching_bytes:36,other_bytes:6,target_bytes:7,dependent_bytes:29},
 strict_diagnostic:{caller:6,offset:108,opcode:'call_ref'},strict_output_absent:true,inputs_and_existing_output_unchanged:true,records,
 scope:'Three new unit tests and four CLI cases only; no old suite/scripts, probes, V8, performance or browser'},null,2)+'\n',{flag:'wx'});
console.log('Function-dependents regressions passed (4 process cases). Evidence: '+dir);
