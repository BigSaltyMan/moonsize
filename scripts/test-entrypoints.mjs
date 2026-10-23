// One independently validated fixture, exactly four analyzer invocations.
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import {spawnSync} from 'node:child_process';

const cli=path.resolve(process.argv[2]||'_build/native/release/build/cmd/main/main.exe');
assert(fs.existsSync(cli),'Build the native CLI first.');
const parent=path.resolve('_build/entrypoints-verification');
fs.mkdirSync(parent,{recursive:true});
const dir=fs.mkdtempSync(path.join(parent,'run-'));
const cat=(...items)=>Buffer.concat(items.map(b=>Buffer.from(b)));
const leb=n=>{const a=[];do{const v=n&127;n>>>=7;a.push(v|(n?128:0));}while(n);return Buffer.from(a);};
const str=s=>cat(leb(Buffer.byteLength(s)),Buffer.from(s));
const section=(id,b)=>cat([id],leb(b.length),b);
const aliases=['A','alias"\\\n雪'];
const bodies=[
  [0,16,3,16,4,16,0,210,5,20,0,11],
  [0,16,3,11],[0,16,3,11],[0,11],[0,16,4,11],[0,11],
];
const exports=cat([4],str(aliases[0]),[0,1],str(aliases[1]),[0,1],str('B'),[0,2],str('memory'),[2,0]);
const names=cat([4,1],str('entry_A'),[2],str('entry_B'),[3],str('shared'),[4],str('helper'));
const data=cat(Buffer.from('0061736d01000000','hex'),
  section(1,[1,96,0,0]),section(2,[1,1,109,1,102,0,0]),
  section(3,[6,0,0,0,0,0,0]),section(5,[1,0,1]),section(7,exports),
  section(8,[5]),section(9,[2,1,0,1,5,3,0,1,4]),
  section(10,cat([6],...bodies.map(b=>cat(leb(b.length),b)))),
  section(0,cat(str('name'),section(1,names))));
assert(WebAssembly.validate(data),'V8 rejected the entrypoint fixture.'); // Once.
const input=path.join(dir,'shared.wasm'), output=path.join(dir,'entrypoints.json');
fs.writeFileSync(input,data,{flag:'wx'});
const sha=b=>crypto.createHash('sha256').update(b).digest('hex');
const records=[];
function run(args,status){
  const p=spawnSync(cli,[input,...args],{cwd:dir,encoding:'utf8',timeout:10000});
  const log=(p.stdout||'')+(p.stderr||'');
  fs.writeFileSync(path.join(dir,'case-'+records.length+'.log'),log,{flag:'wx'});
  records.push({args,status:p.status,error:p.error?.message||null});
  assert.ifError(p.error);assert.equal(p.signal,null);assert.equal(p.status,status,log);
  assert.equal(sha(fs.readFileSync(input)),sha(data));
  return log;
}
const text=run(['--entrypoints','--top','1'],0);
assert(text.includes('EXPORTED ENTRYPOINT DEPENDENCIES'));
assert(text.includes('Function export names: 3; unique entrypoint groups: 2'));
assert(text.includes('All local: 34 B = function-export union 31 B + not export-reachable 3 B'));
assert(text.includes('Export union: 31 B = sum of group-exclusive 18 B + shared (counted once) 13 B'));
assert(text.includes('ENTRYPOINT GROUPS: showing 1 of 2'));
assert(text.includes('SHARED LOCAL FUNCTIONS: showing 1 of 3'));
assert(text.includes(JSON.stringify(aliases)));
assert(text.includes('call_ref'));
const confirmation=run(['--entrypoints-json',output,'--top','1'],0);
assert(confirmation.includes('Entrypoints written to '));
assert(!confirmation.includes('EXPORTED ENTRYPOINT DEPENDENCIES'));
const saved=fs.readFileSync(output), report=JSON.parse(saved), l=report.ledger;
assert.equal(report.format,'moonsize-entrypoints');assert.equal(report.schema_version,1);
assert.equal(report.file_size,data.length);assert.equal(report.sha256,sha(data));
assert.equal(report.export_name_count,3);assert.equal(report.entrypoint_count,2);
assert.equal(report.other_exports.length,1);assert.equal(report.other_exports[0].kind,2);
assert.deepEqual(report.entrypoints.map(g=>g.index),[1,2]);
assert.deepEqual(report.entrypoints[0].aliases,aliases);
assert.deepEqual(report.entrypoints[0].reachable,[0,1,3,4,5]);
assert.equal(report.entrypoints[0].local_function_count,4);
assert.equal(report.entrypoints[0].imported_function_count,1);
assert.equal(report.entrypoints[0].reachable_model_bytes,26);
assert.equal(report.entrypoints[0].exclusive_model_bytes,13);
assert.equal(report.entrypoints[0].shared_model_bytes,13);
assert.equal(report.entrypoints[1].reachable_model_bytes,10);
assert.equal(report.entrypoints[1].exclusive_model_bytes,5);
assert.equal(report.entrypoints[1].shared_model_bytes,5);
assert.equal(l.total_local_bytes,l.export_union_bytes+l.not_export_reachable_bytes);
assert.equal(l.export_union_bytes,l.exclusive_model_bytes+l.shared_model_bytes);
assert.equal(l.exclusive_model_bytes,report.entrypoints.reduce((n,g)=>n+g.exclusive_model_bytes,0));
for(const group of report.entrypoints){
  assert.equal(group.reachable_model_bytes,group.exclusive_model_bytes+group.shared_model_bytes);
  assert.equal(group.reachable_model_bytes,group.reachable.reduce((n,i)=>n+(report.functions[i].node.encoded_size??0),0));
}
assert.equal(report.functions.length,7);assert.equal(report.functions[0].node.encoded_size,null);
assert.equal(report.functions[0].node.imported,true);
assert.deepEqual(report.functions[3].entrypoints,[1,2]);
assert.deepEqual(report.functions[4].entrypoints,[1]);
assert.equal(report.functions[4].other_root_reachable,true);
assert.deepEqual(report.other_roots.map(r=>r.index),[4,5]);
assert.equal(report.other_roots[1].reasons.length,2);
assert.deepEqual(report.other_root_reachable,[4,5]);
assert.deepEqual(report.shared_local_functions,[3,5,4]);
assert.equal(report.graph_complete,false);assert.equal(report.diagnostics.length,1);
assert.equal(report.diagnostics[0].opcode,'call_ref');
const strictTarget=path.join(dir,'strict.json');
const strict=run(['--entrypoints','--strict','--entrypoints-json',strictTarget],3);
assert(strict.includes('--strict: refusing'));assert(!fs.existsSync(strictTarget));
assert(!strict.includes('Entrypoints written to '));
assert(!strict.includes('EXPORTED ENTRYPOINT DEPENDENCIES'));
const refused=run(['--entrypoints-json',output],1);
assert(refused.includes('output already exists'));assert(!refused.includes('Entrypoints written to '));
assert.deepEqual(fs.readFileSync(output),saved);
fs.writeFileSync(path.join(dir,'results.json'),JSON.stringify({input_sha256:sha(data),file_size:data.length,
  cli_sha256:sha(fs.readFileSync(cli)),independent_validation:'Node/V8 WebAssembly.validate: passed',
  ledger:l,entrypoints:report.entrypoints,records},null,2)+'\n',{flag:'wx'});
console.log('Entrypoint CLI regressions passed (4 process cases, 1 V8-validated module). Evidence: '+dir);
