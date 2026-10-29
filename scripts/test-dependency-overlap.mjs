// Exactly four analyzer calls. No old queries, V8, probes or performance runs.
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import {spawnSync} from 'node:child_process';
const cli=path.resolve(process.argv[2]||'_build/native/release/build/cmd/main/main.exe');
assert(fs.existsSync(cli),'Build the native CLI first.');
const parent=path.resolve('_build/dependency-overlap-verification');fs.mkdirSync(parent,{recursive:true});
const dir=fs.mkdtempSync(path.join(parent,'run-'));
const cat=(...items)=>Buffer.concat(items.map(item=>Buffer.from(item)));
const leb=n=>{const a=[];do{const b=n&127;n>>>=7;a.push(b|(n?128:0));}while(n);return Buffer.from(a);};
const str=s=>cat(leb(Buffer.byteLength(s)),Buffer.from(s));
const section=(id,payload)=>cat([id],leb(payload.length),payload);
const sha=b=>crypto.createHash('sha256').update(b).digest('hex');
function fixture(gap=false){
 const bodies=[
  [0,16,3,16,3,210,4,26,65,0,17,0,0,16,1,11],
  [0,16,3,16,7,11], [0,16,4,16,0,11], [0,16,3,11], [0,11],
  gap?[0,210,0,20,0,11]:[0,11], [0,11],
 ];
 const parts=[Buffer.from('0061736d01000000','hex'),
  section(1,[1,96,0,0]),section(2,[1,1,109,1,102,0,0]),
  section(3,[7,0,0,0,0,0,0,0]),section(4,[1,112,0,1]),
  section(7,cat([1],str('entry'),[0,5])),
  section(9,[2,0,65,0,11,1,4,3,0,1,0]),
 ];
 const chunks=[leb(bodies.length)],relative=[];let cursor=chunks[0].length;
 for(const body of bodies){const prefix=leb(body.length);chunks.push(prefix,Buffer.from(body));relative.push(cursor+prefix.length);cursor+=prefix.length+body.length;}
 const payload=cat(...chunks),start=parts.reduce((n,b)=>n+b.length,0)+1+leb(payload.length).length;
 parts.push(section(10,payload),section(0,cat(str('name'),section(1,cat([1,2],str('shared\n\u001b雪'))))));
 return {bytes:cat(...parts),offsets:relative.map(n=>n+start),bodies};
}
const normal=fixture(),gap=fixture(true);
assert.equal(normal.bytes.length,134);assert.equal(gap.bytes.length,138);
assert.deepEqual(normal.offsets,[67,84,91,98,103,106,109]);
const input=path.join(dir,'overlap.wasm'),bad=path.join(dir,'gap.wasm'),existing=path.join(dir,'existing.json');
fs.writeFileSync(input,normal.bytes,{flag:'wx'});fs.writeFileSync(bad,gap.bytes,{flag:'wx'});
const sentinel=Buffer.from('keep overlap evidence\n');fs.writeFileSync(existing,sentinel,{flag:'wx'});
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
const text=run(['overlap.wasm','--compare-dependencies','1','2','--top','1'],0);
assert(text.includes('FUNCTION DEPENDENCY SET COMPARISON'));
assert(text.includes('Left #1:')&&text.includes('Right #2:'));
assert(text.includes(JSON.stringify('shared\n\u001b雪')));
assert(text.includes('shared: showing 1 of 3')&&text.includes('left_only: showing 1 of 1')&&text.includes('right_only: showing 1 of 2'));
assert(!text.includes('neither: showing'));
assert.equal((text.match(/^\d+  (?:local|imported)  /gm)||[]).length,3);
for(const row of ['3  local  7','1  local  17','2  local  7'])assert(text.includes(row));
assert(text.includes('all 8 = shared 3 + left_only 1 + right_only 2 + neither 2'));
assert(text.includes('all 45 = shared 12 + left_only 17 + right_only 10 + neither 6'));
assert(text.includes('Left local bytes: 29 = left_only 17 + shared 12'));
assert(text.includes('Right local bytes: 22 = right_only 10 + shared 12'));
assert(text.includes('Union local bytes: 39 = left_only 17 + right_only 10 + shared 12'));
assert(text.includes('All local bytes: 45 = union 39 + neither 6'));
assert(text.includes('Complete closure edges: left 8, right 5'));
const saved=run(['overlap.wasm','--compare-dependencies','1','2','--compare-dependencies-json','new-overlap.json','--top','1'],0);
assert(saved.includes('Dependency comparison written to new-overlap.json'));assert(!saved.includes('FUNCTION DEPENDENCY SET COMPARISON'));
const report=JSON.parse(fs.readFileSync(path.join(dir,'new-overlap.json')));
assert.equal(report.format,'moonsize-dependency-overlap');assert.equal(report.schema_version,1);
assert.equal(report.file_size,134);assert.equal(report.sha256,sha(normal.bytes));assert.equal(report.left_index,1);assert.equal(report.right_index,2);
assert.deepEqual(report.functions.map(n=>n.index),[0,1,2,3,4,5,6,7]);assert.equal(report.functions[0].encoded_size,null);assert.equal(report.functions[0].imported,true);
assert.deepEqual(report.left_reachable,[0,1,3,4]);assert.deepEqual(report.right_reachable,[0,2,3,4,7]);
assert.deepEqual(report.groups.map(g=>[g.kind,g.indices]),[['shared',[0,3,4]],['left_only',[1]],['right_only',[2,7]],['neither',[5,6]]]);
assert.deepEqual(report.groups.map(g=>[g.function_count,g.local_count,g.imported_count,g.local_encoded_bytes]),[[3,2,1,12],[1,1,0,17],[2,2,0,10],[2,2,0,6]]);
const tuple=e=>[e.caller,e.callee,e.kind,e.offset];
const leftEdges=[[1,3,'direct',68],[1,3,'direct',70],[1,4,'reference',72],[1,4,'indirect',77],[1,1,'direct',80],[3,4,'direct',92],[3,0,'direct',94],[4,3,'direct',99]];
const rightEdges=[[2,3,'direct',85],[2,7,'direct',87],[3,4,'direct',92],[3,0,'direct',94],[4,3,'direct',99]];
assert.deepEqual(report.left_edges.map(tuple),leftEdges);assert.deepEqual(report.right_edges.map(tuple),rightEdges);
const sizes=[null,17,7,7,5,3,3,3],seen=new Set();
for(const group of report.groups){let bytes=0,imports=0;assert.equal(group.indices.length,group.function_count);assert.equal(group.function_count,group.local_count+group.imported_count);
 for(const index of group.indices){assert(!seen.has(index));seen.add(index);assert.equal(report.functions[index].encoded_size,sizes[index]);if(index===0)imports++;else bytes+=sizes[index];}
 assert.equal(bytes,group.local_encoded_bytes);assert.equal(imports,group.imported_count);
}
assert.deepEqual([...seen].sort((a,b)=>a-b),[0,1,2,3,4,5,6,7]);
for(const [edges,indices] of [[report.left_edges,report.left_reachable],[report.right_edges,report.right_reachable]])for(const e of edges){assert(indices.includes(e.caller)&&indices.includes(e.callee));assert.equal(normal.bytes[e.offset],{direct:16,reference:210,indirect:17}[e.kind]);assert.equal(e.candidate,e.kind==='indirect');}
const [shared,left,right,neither]=report.groups;
assert.equal(report.function_count,8);assert.equal(report.local_function_count,7);assert.equal(report.imported_function_count,1);
assert.equal(report.function_count,report.groups.reduce((n,g)=>n+g.function_count,0));assert.equal(report.local_encoded_bytes,report.groups.reduce((n,g)=>n+g.local_encoded_bytes,0));
for(const side of ['left','right']){const g=side==='left'?left:right;
 assert.equal(report[side+'_function_count'],g.function_count+shared.function_count);
 assert.equal(report[side+'_local_encoded_bytes'],g.local_encoded_bytes+shared.local_encoded_bytes);
 assert.equal(report[side+'_function_count'],report[side+'_local_count']+report[side+'_imported_count']);}
assert.equal(report.union_function_count,shared.function_count+left.function_count+right.function_count);
assert.equal(report.function_count,report.union_function_count+neither.function_count);
assert.equal(report.union_local_encoded_bytes,shared.local_encoded_bytes+left.local_encoded_bytes+right.local_encoded_bytes);
assert.equal(report.local_encoded_bytes,report.union_local_encoded_bytes+neither.local_encoded_bytes);
assert.equal(report.union_function_count,report.union_local_count+report.union_imported_count);
assert.equal(report.local_encoded_bytes,45);assert.equal(report.left_local_encoded_bytes,29);assert.equal(report.right_local_encoded_bytes,22);assert.equal(report.union_local_encoded_bytes,39);
assert.equal(report.graph_complete,true);assert.equal(report.unresolved_count,0);assert.deepEqual(report.diagnostics,[]);
const strict=run(['gap.wasm','--compare-dependencies','1','2','--strict','--compare-dependencies-json','strict.json'],3);
assert(strict.includes('--strict: refusing')&&strict.includes('function 6, offset 109: call_ref'));
assert(!fs.existsSync(path.join(dir,'strict.json')));assert(!strict.includes('Dependency comparison written to'));
const refused=run(['overlap.wasm','--compare-dependencies','1','2','--compare-dependencies-json','existing.json'],1);
assert(refused.includes('output already exists'));assert(!refused.includes('Dependency comparison written to'));
fs.writeFileSync(path.join(dir,'results.json'),JSON.stringify({input_size:134,input_sha256:sha(normal.bytes),gap_size:138,gap_sha256:sha(gap.bytes),
 query:{left:1,right:2},left_reachable:report.left_reachable,right_reachable:report.right_reachable,groups:report.groups,left_edges:report.left_edges,right_edges:report.right_edges,
 ledger:{functions:8,local:7,imports:1,left_functions:4,right_functions:5,union_functions:6,local_bytes:45,left_bytes:29,right_bytes:22,union_bytes:39},
 strict_diagnostic:{caller:6,offset:109,opcode:'call_ref'},strict_output_absent:true,inputs_and_existing_output_unchanged:true,records,
 scope:'Three new unit tests and four CLI cases only; no old suite/scripts, probes, V8, performance or browser'},null,2)+'\n',{flag:'wx'});
console.log('Dependency-overlap regressions passed (4 process cases). Evidence: '+dir);
