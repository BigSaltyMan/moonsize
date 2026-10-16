// Actual CLI contracts. Every normal fixture is independently validated by V8.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';

const cli = path.resolve(process.argv[2] || '_build/native/release/build/cmd/main/main.exe');
assert(fs.existsSync(cli), 'Build the native CLI first.');
const tempParent = path.resolve(os.tmpdir());
const work = fs.mkdtempSync(path.join(tempParent, 'moonsize-path-'));
let cases = 0, validFixtures = 0, serial = 0;
const cat = (...items) => Buffer.concat(items.map(x=>Buffer.from(x)));
const leb = n => { const a=[]; do {const b=n&127; n>>>=7; a.push(b|(n?128:0));} while(n); return Buffer.from(a); };
const string = s=>cat(leb(Buffer.byteLength(s)),Buffer.from(s));
const section = (id,payload)=>cat([id],leb(payload.length),payload);
function fixture(label,bodies,{exports=[['run',0]],start=null,elements=[],imports=0,names=[]}={}) {
  const parts=[Buffer.from('0061736d01000000','hex'),section(1,Buffer.from([1,96,0,0]))];
  const offsets={};
  const push=(id,payload)=>{offsets[id]=parts.reduce((s,p)=>s+p.length,0);parts.push(section(id,payload));};
  if(imports) push(2,cat(leb(imports),...Array.from({length:imports},()=>Buffer.from([1,109,1,102,0,0]))));
  push(3,cat(leb(bodies.length),Buffer.alloc(bodies.length)));
  push(4,Buffer.from([1,112,0,2]));
  if(exports.length) push(7,cat(leb(exports.length),...exports.map(([name,index])=>cat(string(name),[0],leb(index)))));
  if(start!==null) push(8,leb(start));
  if(elements.length) push(9,cat(leb(elements.length),...elements.map(([mode,targets])=>cat([mode],mode===0?[65,0,11]:[0],leb(targets.length),...targets.map(leb)))));
  const chunks=[leb(bodies.length)], relative=[];
  for(const bytes of bodies) {chunks.push(leb(bytes.length));relative.push(chunks.reduce((s,p)=>s+p.length,0));chunks.push(Buffer.from(bytes));}
  const code=cat(...chunks);
  const codeStart=parts.reduce((s,p)=>s+p.length,0)+1+leb(code.length).length;
  push(10,code);
  if(names.length) push(0,cat(string('name'),section(1,cat(leb(names.length),...names.map(([i,n])=>cat(leb(i),string(n)))))));
  const data=cat(...parts), file=path.join(work,label+'.wasm');
  assert(WebAssembly.validate(data),'V8 rejected '+label);
  validFixtures++;
  fs.writeFileSync(file,data);
  return {file,data,offsets,bodies:relative.map(p=>p+codeStart),roots:[...new Set([...exports.map(e=>e[1]),...(start===null?[]:[start]),...elements.flatMap(e=>e[1])])].sort((a,b)=>a-b)};
}
function run(args,status=0) {
  const r=spawnSync(cli,args,{encoding:'utf8',timeout:5000,maxBuffer:8*1024*1024});
  assert.ifError(r.error);assert.equal(r.signal,null);assert.equal(r.status,status,r.stdout+r.stderr);cases++;
  return r.stdout+r.stderr;
}
function query(f,target,root=null,status=0) {
  const output=path.join(work,'query-'+serial+++'.json');
  run([f.file,'--why-index',String(target),...(root===null?[]:['--why-root',String(root)]),'--why-json',output],status);
  const report=JSON.parse(fs.readFileSync(output,'utf8'));
  assert.equal(report.schema_version,1); assert.equal(report.format,'moonsize-function-path');
  assert.equal(report.target.index,target);assert.equal(report.query.root_index,root);
  assert.deepEqual(report.model_roots.map(r=>r.index),f.roots);
  assert.equal(report.root_ledger_complete,true);
  assert.match(report.modeling_scope,/not an execution trace/); assert.match(report.modeling_scope,/recompiled or gzip savings/);
  if(report.status==='found') assert.equal(report.nodes.length,report.steps.length+1);
  else {assert.deepEqual(report.nodes,[]);assert.deepEqual(report.steps,[]);assert.equal(report.path_root,null);}
  for(const step of report.steps) {
    assert.equal(f.data[step.offset],{call:16,return_call:18,'ref.func':210,call_indirect:17,return_call_indirect:19}[step.opcode]);
    assert.equal(step.candidate,step.kind==='indirect');
  }
  return report;
}
const end=Buffer.from([0,11]);
const call=(index,tail=false)=>cat([0,tail?18:16],leb(index),[11]);
try {
  const direct=fixture('direct',[call(1),call(2,true),end]);
  const chain=query(direct,2);
  assert.deepEqual(chain.nodes.map(n=>n.index),[0,1,2]);
  assert.deepEqual(chain.steps.map(s=>s.opcode),['call','return_call']);
  assert.deepEqual(chain.steps.map(s=>s.offset),direct.bodies.slice(0,2).map(p=>p+1));
  assert.equal(chain.root_reasons[0].kind,'export');assert.equal(chain.root_reasons[0].section_offset,direct.offsets[7]);
  assert.equal(chain.root_reasons[0].position_granularity,'section');assert.equal(chain.root_reasons[0].ordinal,0);
  assert.match(run([direct.file,'--why-index','2']),/return_call \[direct\] at file offset/);
  assert.deepEqual(query(direct,2),chain);
  const diamond=fixture('diamond',[Buffer.from([0,16,2,16,1,11]),call(3),call(3),end]);
  assert.deepEqual(query(diamond,3).nodes.map(n=>n.index),[0,1,3]);
  const multiple=fixture('multiple',[call(3),end,call(3),end],{exports:[['second',2],['first',0]]});
  assert.deepEqual(query(multiple,3).nodes.map(n=>n.index),[0,3]);
  assert.equal(query(multiple,2,0).status,'not-found-within-model');
  assert.match(run([multiple.file,'--why-index','2','--why-root','0']),/Other roots may still reach/);
  const cycles=fixture('cycles',[Buffer.from([0,16,0,16,1,11]),call(2),Buffer.from([0,16,1,16,3,11]),end]);
  assert.deepEqual(query(cycles,3).nodes.map(n=>n.index),[0,1,2,3]);
  const roots=fixture('roots',[end],{exports:[['一"\n',0],['two',0]],start:0,elements:[[0,[0,0]]]});
  const zero=query(roots,0);
  assert.equal(zero.steps.length,0);assert.equal(zero.nodes.length,1);
  assert.deepEqual(zero.root_reasons.map(r=>r.kind),['export','export','start','conservative-element']);
  assert.equal(zero.root_reasons[0].name,'一"\n');
  for(const tail of [false,true]) {
    const f=fixture('indirect-'+tail,[Buffer.from([0,65,0,tail?19:17,0,0,11]),end],{elements:[[0,[1]]]});
    assert.deepEqual(query(f,1).nodes.map(n=>n.index),[1]);
    const selected=query(f,1,0);
    assert.deepEqual(selected.nodes.map(n=>n.index),[0,1]);
    assert.equal(selected.steps[0].kind,'indirect');assert.equal(selected.steps[0].type_index,0);assert.equal(selected.steps[0].table_index,0);
    assert.equal(selected.steps[0].offset,f.bodies[0]+3);assert.equal(selected.graph_complete,true);
    run([f.file,'--why-index','1','--why-root','0','--strict']);
  }
  for(const mode of [1,3]) {
    const f=fixture('reference-'+mode,[Buffer.from([0,210,1,26,11]),end],{elements:[[mode,[1]]]});
    assert.equal(query(f,1,0).steps[0].kind,'reference');
    const zero=query(f,1);
    assert.equal(zero.root_reasons.find(r=>r.function_index===1).element_mode,'passive-or-declarative');
    assert.equal(zero.root_reasons.find(r=>r.function_index===1).table_index,null);
  }
  const imported=fixture('imports',[call(1)],{imports:2,exports:[['run',2],['host',0]]});
  const imp=query(imported,1,2);
  assert.equal(imp.target.imported,true);assert.equal(imp.target.encoded_size,null);assert.equal(imp.target.import_module,'m');
  assert.deepEqual(imp.nodes.map(n=>n.index),[2,1]);assert.equal(imp.steps[0].offset,imported.bodies[0]+1);
  assert.equal(query(imported,0).steps.length,0);
  assert.match(run([imported.file,'--why-index','1','--why-root','2']),/no local body/);
  const duplicate=fixture('duplicate',[call(1),end],{names:[[0,'same'],[1,'same']]});
  const dup=query(duplicate,1);assert.deepEqual(dup.nodes.map(n=>n.name),['same','same']);
  const unicode=fixture('unicode',[call(1),end],{names:[[1,'函数"\n</script>']]});
  assert.equal(query(unicode,1).target.raw_name,'函数"\n</script>');
  const noRoots=fixture('no-roots',[end],{exports:[]});
  assert.equal(query(noRoots,0).status,'not-found-within-model');
  const unknown=fixture('reference-gap',[Buffer.from([0,208,0,20,0,11]),end]);
  const unknownResult=query(unknown,1);
  assert.equal(unknownResult.status,'not-found-within-model');assert.equal(unknownResult.graph_complete,false);
  assert.equal(unknownResult.diagnostics[0].code,'unmodeled_reference_call');
  const dynamic=fixture('dynamic',[Buffer.from([0,65,0,17,0,0,11]),end,Buffer.from([0,65,0,208,112,38,0,11])],{elements:[[0,[1]]]});
  const dynamicResult=query(dynamic,1,0);
  assert.equal(dynamicResult.status,'found');assert.equal(dynamicResult.graph_complete,false);
  assert.equal(dynamicResult.diagnostics[0].code,'runtime_table_mutation');
  assert.equal(dynamicResult.diagnostics[0].source.caller,2);assert.equal(dynamicResult.diagnostics[0].source.offset,dynamic.bodies[2]+5);
  for(const f of [unknown,dynamic]) for(const exists of [false,true]) {
    const output=path.join(work,`strict-${path.basename(f.file)}-${exists}.json`);
    if(exists)fs.writeFileSync(output,'KEEP');
    const text=run([f.file,'--why-index','1','--strict','--why-json',output],3);
    assert.match(text,/--strict: refusing/);assert(!text.includes('FUNCTION REFERENCE PATH'));
    if(exists)assert.equal(fs.readFileSync(output,'utf8'),'KEEP');else assert(!fs.existsSync(output));
  }
  const long=fixture('long',Array.from({length:259},(_,i)=>i===258?end:call(i+1)));
  const limited=query(long,258,null,3);
  assert.equal(limited.status,'search-limited');assert.equal(limited.search_stats.limit_reason,'depth-limit');
  assert.equal(limited.search_stats.max_depth,256);assert.equal(limited.search_stats.visited_nodes,257);
  assert.equal(limited.search_stats.indexed_edges,258);assert.equal(limited.search_stats.checked_edges,257);
  const exact=fixture('exact-depth',Array.from({length:257},(_,i)=>i===256?end:call(i+1)));
  assert.equal(query(exact,256).steps.length,256);
  for(const index of ['-1','1.5','2147483648','999999999999999','']) run(['absent','--why-index',index],2);
  run(['absent','--why-index'],2);run(['absent','--why-index','0','--why-root'],2);run(['absent','--why-index','0','--why-json'],2);
  run(['absent','--why-root','0'],2);run(['absent','--why-json',path.join(work,'orphan.json')],2);
  run(['absent','--why-index','0','--why-json','out.txt'],2);
  for(const args of [
    ['--html','out.html'],['--call-graph','out.json'],['--experiment','out.html'],['--experiment-context','context.json'],
    ['--retained'],['--dead-code'],['--compress'],['--diff-functions'],['--baseline','base.wasm'],['--max-size','0B'],['--top','0'],
  ]) {const text=run(['absent','--why-index','0',...args],2);assert(!text.includes('cannot read'));}
  for(const args of [['--why-index','2'],['--why-index','2147483647'],['--why-index','1','--why-root','1'],['--why-index','1','--why-root','2147483647']]) run([duplicate.file,...args],1);
  const empty=path.join(work,'empty.wasm');fs.writeFileSync(empty,Buffer.from('0061736d01000000','hex'));
  run([empty,'--why-index','0'],1);run(['absent.wasm','--why-index','0'],1);
  const bad=path.join(work,'bad.wasm');fs.writeFileSync(bad,'bad');run([bad,'--why-index','0'],1);
  const ghost=path.join(work,'ghost.wasm');const ghostBytes=Buffer.from(direct.data);ghostBytes[direct.bodies[0]+2]=99;fs.writeFileSync(ghost,ghostBytes);
  assert.match(run([ghost,'--why-index','0'],1),/invalid graph function index 99/);
  const existing=path.join(work,'existing.json');fs.writeFileSync(existing,'KEEP');
  run([direct.file,'--why-index','2','--why-json',existing],1);assert.equal(fs.readFileSync(existing,'utf8'),'KEEP');
  const jsonInput=path.join(work,'input.json');fs.writeFileSync(jsonInput,direct.data);
  run([jsonInput,'--why-index','2','--why-json',jsonInput],1);assert.deepEqual(fs.readFileSync(jsonInput),direct.data);
  const alias=path.join(work,'input-alias.json');fs.linkSync(jsonInput,alias);
  run([jsonInput,'--why-index','2','--why-json',alias],1);assert.deepEqual(fs.readFileSync(jsonInput),direct.data);
  run([direct.file,'--why-index','2','--why-json',path.join(work,'nonexistent','report.json')],1);
  console.log(`Function-path CLI regressions passed (${cases} process cases, ${validFixtures} V8-validated modules).`);
} finally {
  assert.equal(path.dirname(work),tempParent);assert(path.basename(work).startsWith('moonsize-path-'));
  fs.rmSync(work,{recursive:true,force:true});
}
