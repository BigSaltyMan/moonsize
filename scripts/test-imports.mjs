// Exactly four analyzer calls; the mixed fixture is independently validated once.
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import {spawnSync} from 'node:child_process';

const cli=path.resolve(process.argv[2]||'_build/native/release/build/cmd/main/main.exe');
assert(fs.existsSync(cli),'Build the native CLI first.');
const parent=path.resolve('_build/imports-verification');
fs.mkdirSync(parent,{recursive:true});
const dir=fs.mkdtempSync(path.join(parent,'run-'));
const cat=(...items)=>Buffer.concat(items.map(b=>Buffer.from(b)));
const leb=n=>{const a=[];do{const v=n&127;n>>>=7;a.push(v|(n?128:0));}while(n);return Buffer.from(a);};
const wide=n=>{assert(n<128);return Buffer.from([n|128,0]);};
const name=(s,w=false)=>cat(w?wide(Buffer.byteLength(s)):leb(Buffer.byteLength(s)),Buffer.from(s));
const section=(id,b)=>cat([id],leb(b.length),b);
const sha=b=>crypto.createHash('sha256').update(b).digest('hex');
const header=Buffer.from('0061736d01000000','hex');
const kinds=['function','table','memory','global','tag'];
const definitions=[
  ['env','same',[0,128,0],true],['env','table',[1,112,1,1,3]],
  ['env','same',[0,0]],['宿主','',[2,3,1,2]],
  ['','line"\\\n雪',[3,127,1]],['env','tag',[4,0,0]],
  [' spaced.module ','t',[1,111,0,0]],[' spaced.module ','m',[2,0,0]],
  ['宿主','v',[3,111,0]],
];
const chunks=definitions.map(([m,f,d,w])=>[name(m,w),name(f,w),Buffer.from(d)]);
const count=wide(definitions.length), payload=cat(count,...chunks.flat());
const typeSection=section(1,[1,96,0,0]);
const importSection=section(2,payload), data=cat(header,typeSection,importSection);
assert(WebAssembly.validate(data),'V8 rejected the five-kind import fixture.'); // Once.
const unsupported=cat(header,section(2,[1,0,0,2,4,0])); // memory64 minimum 0.
const input=path.join(dir,'mixed.wasm'), bad=path.join(dir,'memory64.wasm');
const output=path.join(dir,'imports.json'), rejected=path.join(dir,'unsupported.json');
fs.writeFileSync(input,data,{flag:'wx'});fs.writeFileSync(bad,unsupported,{flag:'wx'});
const records=[];
function run(file,args,status){
  const original=fs.readFileSync(file);
  const p=spawnSync(cli,[file,...args],{cwd:dir,encoding:'utf8',timeout:10000});
  const log=(p.stdout||'')+(p.stderr||'');
  fs.writeFileSync(path.join(dir,'case-'+records.length+'.log'),log,{flag:'wx'});
  records.push({input:file,args,status:p.status,error:p.error?.message||null});
  assert.ifError(p.error);assert.equal(p.signal,null);assert.equal(p.status,status,log);
  assert.equal(sha(fs.readFileSync(file)),sha(original));return log;
}
const text=run(input,['--imports','--top','1'],0);
assert(text.includes('HOST IMPORT DECLARATIONS'));
assert(text.includes('Declarations: 9; function 2, table 2, memory 2, global 2, tag 1'));
assert(text.includes('Import section bytes: 138 B = section header 3 B + count prefix 2 B + declarations 133 B'));
assert(text.includes('Declaration encoding bytes: 133 B = module names 64 B + field names 39 B + descriptors 30 B'));
assert(text.includes('IMPORT ENTRIES: showing 1 of 9'));
assert(text.includes('6  table  1  22'));assert(!text.includes('7  memory  1  21'));
for(const [m,n,b] of [['env',4,51],[' spaced.module ',2,43],['宿主',2,24],['',1,15]]){
  assert(text.includes(JSON.stringify(m)+'  '+n+' declarations  '+b+' B;'));
}
const confirmation=run(input,['--imports-json',output,'--top','1'],0);
assert(confirmation.includes('Imports written to '));assert(!confirmation.includes('HOST IMPORT DECLARATIONS'));
const saved=fs.readFileSync(output), report=JSON.parse(saved), s=report.ledger;
assert.equal(report.format,'moonsize-imports');assert.equal(report.schema_version,1);
assert.equal(data.length,152);assert.equal(report.file_size,data.length);assert.equal(report.sha256,sha(data));
assert.equal(report.entry_count,9);assert.equal(report.entries.length,9);
assert.deepEqual(report.kind_counts,{function:2,table:2,memory:2,global:2,tag:1});
assert.deepEqual(report.section,{offset:14,size:138});assert.deepEqual(report.count_encoding,{offset:17,size:2});
assert.equal(s.import_section_total_bytes,s.section_header_bytes+s.count_prefix_bytes+s.entry_bytes);
assert.equal(s.entry_bytes,s.module_name_encoding_bytes+s.field_name_encoding_bytes+s.descriptor_bytes);
assert.equal(s.module_name_encoding_bytes,s.module_length_prefix_bytes+s.module_utf8_bytes);
assert.equal(s.field_name_encoding_bytes,s.field_length_prefix_bytes+s.field_utf8_bytes);
assert.equal(s.entry_bytes,report.modules.reduce((n,g)=>n+g.entry_bytes,0));
assert.deepEqual(report.modules.map(g=>g.module),['env',' spaced.module ','宿主','']);
assert.deepEqual(report.modules[0].ordinals,[0,1,2,5]);
let offset=19;const counts=[0,0,0,0,0];
for(const [i,e] of report.entries.entries()){
  const [m,f,d,w]=definitions[i], [mb,fb,db]=chunks[i], kind=d[0];
  assert.equal(e.ordinal,i);assert.equal(e.kind,kinds[kind]);assert.equal(e.kind_index,counts[kind]++);
  assert.equal(e.module,m);assert.equal(e.field,f);
  assert.deepEqual(e.encoding,{offset,size:mb.length+fb.length+db.length});
  assert.deepEqual(e.module_encoding,{offset,size:mb.length});
  assert.deepEqual(e.field_encoding,{offset:offset+mb.length,size:fb.length});
  assert.deepEqual(e.descriptor,{offset:offset+mb.length+fb.length,size:db.length});
  assert.equal(e.module_utf8_bytes,Buffer.byteLength(m));assert.equal(e.field_utf8_bytes,Buffer.byteLength(f));
  assert.equal(e.module_length_prefix_bytes,w?2:1);assert.equal(e.field_length_prefix_bytes,w?2:1);
  assert.equal(e.type_index,kind===0||kind===4?0:null);
  assert.deepEqual(data.subarray(e.descriptor.offset,e.descriptor.offset+e.descriptor.size),db);
  offset+=e.encoding.size;
}
assert.equal(offset,152);
assert.deepEqual(report.entries.map(e=>e.kind_index),[0,0,1,0,0,0,1,1,1]);
assert.deepEqual(report.entries[3].limits,{flags:3,minimum:1,maximum:2});
assert.deepEqual(report.entries[6].limits,{flags:0,minimum:0,maximum:null});
assert.equal(report.entries[4].field,'line"\\\n雪');assert.equal(report.entries[4].mutability,1);
assert.equal(report.entries[8].value_type,'externref');
const failure=run(bad,['--imports-json',rejected],1);
assert(failure.includes('import encoding at offset 14: unsupported memory64 limits flags 4'));
assert(!failure.includes('HOST IMPORT DECLARATIONS'));assert(!failure.includes('Imports written to '));
assert(!fs.existsSync(rejected));
const refused=run(input,['--imports-json',output],1);
assert(refused.includes('output already exists'));assert(!refused.includes('Imports written to '));
assert.deepEqual(fs.readFileSync(output),saved);
fs.writeFileSync(path.join(dir,'results.json'),JSON.stringify({
  file_size:data.length,input_sha256:sha(data),unsupported_size:unsupported.length,unsupported_sha256:sha(unsupported),
  cli_sha256:sha(fs.readFileSync(cli)),node:process.version,
  independent_validation:'Node/V8 validated the mixed five-kind fixture once; no instantiation or execution',
  ledger:s,records,
},null,2)+'\n',{flag:'wx'});
console.log('Imports CLI regressions passed (4 process cases, 1 V8-validated core). Evidence: '+dir);
