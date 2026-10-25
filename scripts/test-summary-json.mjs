// Four analyzer calls; validate each legal fixture once without execution.
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import {spawnSync} from 'node:child_process';

const cli=path.resolve(process.argv[2]||'_build/native/release/build/cmd/main/main.exe');
assert(fs.existsSync(cli),'Build the native CLI first.');
const parent=path.resolve('_build/summary-json-verification');fs.mkdirSync(parent,{recursive:true});
const dir=fs.mkdtempSync(path.join(parent,'run-'));
const cat=(...items)=>Buffer.concat(items.map(item=>Buffer.from(item)));
const section=(id,payload)=>{assert(payload.length<128);return cat([id,payload.length],payload);};
const sha=bytes=>crypto.createHash('sha256').update(bytes).digest('hex');
const names=[[1,'z/root"\n雪'],[2,'alpha/leaf'],[3,'z/dead']];
const full=cat(Buffer.from('0061736d01000000010401600000020701016d01660000','hex'),
  section(3,[4,0,0,0,0]),section(7,cat([2,4],Buffer.from('host'),[0,0,3],Buffer.from('run'),[0,1])),
  section(10,[4,4,0,16,2,11,130,0,0,11,3,0,1,11,2,0,11]),
  section(0,cat([4],Buffer.from('same'),[170])),section(0,cat([4],Buffer.from('same'),[187])),
  section(0,cat([4],Buffer.from('name'),section(1,cat([names.length],...names.map(([i,name])=>{
    const bytes=Buffer.from(name);return cat([i,bytes.length],bytes);
  }))))));
const dynamic=Buffer.from('0061736d010000000104016000000303020000040401700001070d020372756e00000374626c01000907010041000b01010a12020d0041001100004100d20126000b02000b','hex');
assert(WebAssembly.validate(full),'Node/V8 rejected full summary fixture.');
assert(WebAssembly.validate(dynamic),'Node/V8 rejected dynamic-table summary fixture.'); // Once each.
const input=path.join(dir,'full.wasm'),gap=path.join(dir,'dynamic.wasm');
const output=path.join(dir,'summary.json'),gapOutput=path.join(dir,'dynamic.json'),strictOutput=path.join(dir,'strict.json');
fs.writeFileSync(input,full,{flag:'wx'});fs.writeFileSync(gap,dynamic,{flag:'wx'});
const records=[];
function run(file,args,status){
  const proc=spawnSync(cli,[file,...args],{cwd:dir,encoding:'utf8',timeout:10000});
  const log=(proc.stdout||'')+(proc.stderr||'');
  fs.writeFileSync(path.join(dir,'case-'+records.length+'.log'),log,{flag:'wx'});
  records.push({input:file,args,status:proc.status,error:proc.error?.message||null});
  assert.ifError(proc.error);assert.equal(proc.signal,null);assert.equal(proc.status,status,log);
  assert.equal(sha(fs.readFileSync(input)),sha(full));assert.equal(sha(fs.readFileSync(gap)),sha(dynamic));return log;
}
const text=run(input,['--top','1','--retained','--dead-code','--summary-json',output,'--max-size','0B'],3);
assert(text.includes('Analysis summary written to '));assert(text.includes('over the budget'));
assert(!text.includes('"schema_version"'));
const saved=fs.readFileSync(output),report=JSON.parse(saved),s=report.summary;
assert.deepEqual(Object.keys(report).sort(),['format','schema_version','input','summary','sections','functions','modules','model'].sort());
assert.equal(report.format,'moonsize-summary');assert.equal(report.schema_version,1);
assert.deepEqual(report.input,{file_size:124,sha256:sha(full),wasm_version:1});
assert.deepEqual(s,{wasm_header_bytes:8,section_count:8,section_bytes:116,defined_function_count:4,defined_body_bytes:11,defined_prefix_bytes:5,
  defined_encoded_bytes:16,reachable_defined_count:2,unreachable_defined_count:2,reachable_encoded_bytes:9,unreachable_encoded_bytes:7,module_count:3});
assert.equal(report.input.file_size,s.wasm_header_bytes+report.sections.reduce((sum,r)=>sum+r.total_size,0));
let end=8;for(const [ordinal,row]of report.sections.entries()){
  assert.equal(row.ordinal,ordinal);assert.equal(row.offset,end);assert.equal(row.id,full[row.offset]);
  assert.equal(row.total_size,row.section_header_bytes+row.payload_size);end+=row.total_size;
}
assert.equal(end,full.length);assert.deepEqual(report.sections.map(r=>r.kind),['type','import','function','export','code','custom','custom','custom']);
assert.deepEqual(report.sections.map(r=>r.custom_name_display),[null,null,null,null,null,'same','same','name']);
assert.deepEqual(report.functions.map(r=>r.index),[1,2,3,4]);assert.equal(report.functions.length,4);
assert.equal(report.functions[0].name,'z/root"\n雪');assert.equal(report.functions[0].raw_name,'z/root"\n雪');assert.equal(report.functions[3].raw_name,null);
assert.deepEqual(report.functions.map(r=>r.offset),[49,54,58,62]);assert.deepEqual(report.functions.map(r=>r.prefix_size),[1,2,1,1]);
assert.deepEqual(report.functions.map(r=>r.total_size),[5,4,4,3]);
assert.deepEqual(report.functions.map(r=>r.model_reachable),[true,true,false,false]);
assert.deepEqual(report.functions.map(r=>r.model_root),[true,false,false,false]);
assert.deepEqual(report.functions.map(r=>r.model_indirect_candidate),[false,false,false,false]);
assert.deepEqual(report.functions.map(r=>r.model_retained),[
  {own_encoded_bytes:5,dominated_encoded_bytes:9,other_dominated_function_count:1},
  {own_encoded_bytes:4,dominated_encoded_bytes:4,other_dominated_function_count:0},null,null]);
assert.deepEqual(report.modules,[
  {module_name:'(unnamed)',function_count:1,body_bytes:2,prefix_bytes:1,encoded_bytes:3,function_indices:[4]},
  {module_name:'alpha',function_count:1,body_bytes:2,prefix_bytes:2,encoded_bytes:4,function_indices:[2]},
  {module_name:'z',function_count:2,body_bytes:7,prefix_bytes:2,encoded_bytes:9,function_indices:[1,3]},
]);
assert.equal(report.modules.reduce((sum,r)=>sum+r.encoded_bytes,0),s.defined_encoded_bytes);
assert.equal(report.modules.reduce((sum,r)=>sum+r.function_count,0),s.defined_function_count);
assert.equal(s.defined_encoded_bytes,s.defined_body_bytes+s.defined_prefix_bytes);
assert.equal(s.defined_function_count,s.reachable_defined_count+s.unreachable_defined_count);
assert.equal(s.defined_encoded_bytes,s.reachable_encoded_bytes+s.unreachable_encoded_bytes);
assert.deepEqual(report.model.root_indices,[0,1]);assert.equal(report.model.graph_complete,true);assert.equal(report.model.unresolved_count,0);assert.equal(report.model.diagnostic_count,0);
assert.deepEqual(report.model.diagnostics,[]);assert(report.model.retained_scope.includes('includes the function itself'));
assert(report.model.modeling_scope.includes('not full Wasm certification'));assert(!('gzip'in report));assert(!('edges'in report.model));assert(!('budget'in report));
const warning=run(gap,['--summary-json',gapOutput],0);
assert(warning.includes('Analysis summary written to '));assert(warning.includes('WARNING:'));
const incomplete=JSON.parse(fs.readFileSync(gapOutput)),m=incomplete.model;
assert.equal(incomplete.input.sha256,sha(dynamic));assert.equal(m.graph_complete,false);assert.equal(m.unresolved_count,0);
assert.equal(m.diagnostic_count,2);assert.equal(m.diagnostics.length,2);
const byCode=new Map(m.diagnostics.map(d=>[d.code,d]));assert.equal(byCode.size,2);
for(const code of ['exported_table_contents','runtime_table_mutation']){
  const row=byCode.get(code);assert(row);assert.equal(row.caller,0);assert.equal(row.offset,56);
  assert.equal(row.opcode,'call_indirect');assert.equal(row.type_index,0);assert.equal(row.table_index,0);assert.equal(typeof row.reason,'string');assert(row.reason.length>0);
}
assert.deepEqual(byCode.get('runtime_table_mutation').source,{caller:0,offset:63,opcode:'table.set'});
assert.deepEqual(byCode.get('exported_table_contents').source,{caller:null,offset:38,opcode:null});
assert.equal(incomplete.functions[1].model_indirect_candidate,true);assert.deepEqual(m.root_indices,[0,1]);
const strict=run(gap,['--summary-json',strictOutput,'--strict'],3);
assert(strict.includes('--strict: refusing'));assert(!strict.includes('written to'));assert(!fs.existsSync(strictOutput));
const refused=run(input,['--summary-json',output],1);
assert(refused.includes('output already exists'));assert(!refused.includes('written to'));assert.deepEqual(fs.readFileSync(output),saved);
fs.writeFileSync(path.join(dir,'results.json'),JSON.stringify({input:{size:full.length,sha256:sha(full)},dynamic:{size:dynamic.length,sha256:sha(dynamic)},
  cli_sha256:sha(fs.readFileSync(cli)),node:process.version,v8:process.versions.v8,independent_validation:'Each fixture validated by Node/V8 once; no instantiation or execution',summary:s,records},null,2)+'\n',{flag:'wx'});
console.log('Summary-JSON CLI regressions passed (4 process cases, 2 V8 validations). Evidence: '+dir);
