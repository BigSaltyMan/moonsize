// Exactly four analyzer calls. No old queries, V8, probes or performance runs.
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
const args=process.argv.slice(2);
const requireGraphviz=args.includes('--require-graphviz');
const positional=args.filter(arg=>arg!=='--require-graphviz');
assert(positional.length<=1&&!positional.some(arg=>arg.startsWith('--')), 'Usage: test-dependents-dot.mjs [native-cli] [--require-graphviz]');
const cli=path.resolve(positional[0]||'_build/native/release/build/cmd/main/main.exe');
assert(fs.existsSync(cli),'Build the native CLI first.');
const parent=path.resolve('_build/dependents-dot-verification');fs.mkdirSync(parent,{recursive:true});
const dir=fs.mkdtempSync(path.join(parent,'run-'));
if(process.env.GITHUB_OUTPUT)fs.appendFileSync(process.env.GITHUB_OUTPUT,'evidence_dir='+path.relative(process.cwd(),dir).split(path.sep).join('/')+'\n');
const specialName='雪 "quote" \\N|\\G|\\E|\\n|\\l|\\r\n\t\u001b"]; injected -> fn_99; //';
// Independent expected DOT name content; program line separators are separate.
const visibleName='雪 "quote" \\N|\\G|\\E|\\n|\\l|\\r\\u000a\\u0009\\u001b"]; injected -> fn_99; //';
const quotedVisibleName=visibleName.replaceAll('\\','\\\\').replaceAll('"','\\"');
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
 parts.push(section(10,payload),section(0,cat(str('name'),section(1,cat([1,3],str(specialName))))));
 return {bytes:cat(...parts),offsets:relative.map(n=>n+start),bodies};
}
const normal=fixture(),gap=fixture(true);
assert.equal(gap.bytes.length-normal.bytes.length,4);
assert.deepEqual(normal.offsets,[66,83,90,97,102,105]);
const input=path.join(dir,'dependents.wasm'),bad=path.join(dir,'gap.wasm'),existing=path.join(dir,'sentinel.dot');
fs.writeFileSync(input,normal.bytes,{flag:'wx'});fs.writeFileSync(bad,gap.bytes,{flag:'wx'});
const sentinel=Buffer.from('keep DOT evidence\n');fs.writeFileSync(existing,sentinel,{flag:'wx'});
const records=[];
function run(args,status){
 const p=spawnSync(cli,args,{cwd:dir,encoding:'utf8',shell:false,timeout:10000,maxBuffer:4*1024*1024});
 const text=(p.stdout||'')+(p.stderr||'');
 fs.writeFileSync(path.join(dir,'case-'+records.length+'.log'),text,{flag:'wx'});
 records.push({argv:[cli,...args],status:p.status,error:p.error?.message??null});
 fs.writeFileSync(path.join(dir,'processes.json'),JSON.stringify(records,null,2)+'\n');
 assert.ifError(p.error);assert.equal(p.signal,null);assert.equal(p.status,status,text);
 assert.equal(sha(fs.readFileSync(input)),sha(normal.bytes));assert.equal(sha(fs.readFileSync(bad)),sha(gap.bytes));assert.deepEqual(fs.readFileSync(existing),sentinel);
 return text;
}
const tuples=[[1,2,'direct',67,'solid'],[1,2,'direct',69,'solid'],[1,3,'reference',71,'dashed'],[1,3,'indirect candidate',76,'dotted'],[1,1,'direct',79,'solid'],[2,4,'direct',84,'solid'],[3,4,'direct',91,'solid'],[3,2,'direct',93,'solid'],[4,1,'direct',98,'solid']];
// Narrow reader for our fixed quoted attributes, not a Graphviz parser.
function attribute(dot,key){
 const line=dot.split('\n').find(s=>s.startsWith('  '+key+'='));assert(line,'missing '+key);
 return JSON.parse(line.slice(line.indexOf('=')+1,-1));
}
function checkDot(file,bytes,incomplete){
 const dot=fs.readFileSync(path.join(dir,file),'utf8');
 assert(dot.startsWith('digraph moonsize_dependents {\n'));assert(dot.includes('rankdir=LR;'));
 assert(!dot.includes('strict digraph')&&!dot.includes('concentrate='));
 const nodes=dot.split('\n').filter(s=>/^  fn_\d+ \[/.test(s));
 assert.deepEqual(nodes.map(s=>Number(s.match(/fn_(\d+)/)[1])),[1,2,3,4]);
 assert(nodes.every(row=>row.includes('shape=box')));
 assert(nodes[1].includes('query target')&&nodes[1].includes('depth to target 0')&&nodes[1].includes('7 B'));
 assert(nodes[0].includes('depth to target 1')&&nodes[0].includes('17 B'));
 assert(nodes[3].includes('depth to target 2')&&nodes[3].includes('5 B'));
 assert.equal(nodes[2],`  fn_3 [shape=box, label="#3: ${quotedVisibleName}\\nlocal; encoded size 7 B\\ndepth to target 1"];`);
 const edges=dot.split('\n').filter(s=>/^  fn_\d+ ->/.test(s));
 assert.deepEqual(edges,tuples.map(([a,b,kind,offset,style])=>`  fn_${a} -> fn_${b} [style=${style}, label="${kind}; file offset ${offset}"];`));
 for(const [, ,kind,offset] of tuples)assert.equal(bytes[offset],{direct:16,reference:210,'indirect candidate':17}[kind]);
 assert(dot.includes('nodes 4; edges 9'));assert.equal(attribute(dot,'input_sha256'),sha(bytes));
 assert.equal(attribute(dot,'file_size'),String(bytes.length));assert.equal(attribute(dot,'target_index'),'2');
 assert.equal(attribute(dot,'graph_complete'),String(!incomplete));assert.equal(attribute(dot,'unresolved_count'),'0');
 assert(attribute(dot,'modeling_scope').includes('not actual execution'));
 const diagnostics=JSON.parse(attribute(dot,'diagnostics_json'));
 if(incomplete){assert.equal(diagnostics.length,1);assert.equal(diagnostics[0].caller,6);assert.equal(diagnostics[0].offset,108);assert.equal(diagnostics[0].opcode,'call_ref');assert(dot.includes('WARNING: incomplete graph; diagnostics 1'));assert(attribute(dot,'graph_warning').includes('function 6, offset 108: call_ref'));}
 else {assert.deepEqual(diagnostics,[]);assert.equal(attribute(dot,'graph_warning'),'');}
 assert(!dot.includes('  fn_6 [')&&!dot.includes('  fn_0 ['));
 assert(!edges.some(row=>row.startsWith('  fn_2 -> fn_0 ')));
 assert.deepEqual([...bytes.subarray(86,88)],[16,0]);
 assert(!dot.includes('dir=back'));return {file,dot_sha256:sha(Buffer.from(dot)),file_size:bytes.length,nodes:4,edges:9,next_edge_tree_edges:3,tuples,diagnostics};
}
const saved=run(['dependents.wasm','--dependents','2','--dependents-dot','new.dot','--top','1'],0);
assert(saved.includes('Function dependents DOT written to new.dot'));
assert(!saved.includes('digraph')&&!saved.includes('FUNCTION TRANSITIVE'));
const normalResult=checkDot('new.dot',normal.bytes,false);
const warningSaved=run(['gap.wasm','--dependents','2','--dependents-dot','gap.dot'],0);
assert(warningSaved.includes('Function dependents DOT written to gap.dot'));
const gapResult=checkDot('gap.dot',gap.bytes,true);
const strict=run(['gap.wasm','--dependents','2','--strict','--dependents-dot','strict.dot'],3);
assert(strict.includes('--strict: refusing')&&strict.includes('function 6, offset 108: call_ref'));assert(!fs.existsSync(path.join(dir,'strict.dot')));assert(!strict.includes('written to'));
const refused=run(['dependents.wasm','--dependents','2','--dependents-dot','sentinel.dot'],1);
assert(refused.includes('output already exists'));assert(!refused.includes('written to'));
fs.writeFileSync(path.join(dir,'results.json'),JSON.stringify({verification_sha:process.env.GITHUB_SHA||null,cli_sha256:sha(fs.readFileSync(cli)),input_sha256:sha(normal.bytes),gap_sha256:sha(gap.bytes),normal:normalResult,gap:gapResult,excluded_outgoing_edge:{caller:2,callee:0,kind:'direct',offset:86,raw_bytes:[16,0]},records,inputs_and_sentinel_unchanged:true,strict_output_absent:true,special_name:{function_index:3,raw:specialName,visible:visibleName},graphviz:{required:requireGraphviz,status:requireGraphviz?'see-graphviz/results.json':'not-executed',reason:requireGraphviz?null:'Local string checks only; Graphviz is required separately in Linux CI.'},scope:'Four analyzer calls only; no V8, old tests, probes, browser or performance.'},null,2)+'\n',{flag:'wx'});
console.log('Dependents DOT regressions passed (4 process cases). Evidence: '+dir);
if(requireGraphviz){
 const verifier=fileURLToPath(new URL('./verify-dependents-dot-graphviz.mjs',import.meta.url));
 const verification=spawnSync(process.execPath,[verifier,dir],{shell:false,encoding:'utf8',timeout:90000,maxBuffer:8*1024*1024});
 fs.writeFileSync(path.join(dir,'graphviz-verifier.log'),(verification.stdout||'')+(verification.stderr||''),{flag:'wx'});
 assert.ifError(verification.error);assert.equal(verification.signal,null);assert.equal(verification.status,0,fs.readFileSync(path.join(dir,'graphviz-verifier.log'),'utf8'));
 console.log(verification.stdout.trim());
} else console.log('Graphviz not executed locally; parsing/layout text remains for required CI verification.');
