// Exactly four analyzer calls. Validate the named core once; the other fixture
// only removes its optional final name custom section, leaving core bytes intact.
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import {spawnSync} from 'node:child_process';

const cli=path.resolve(process.argv[2]||'_build/native/release/build/cmd/main/main.exe');
assert(fs.existsSync(cli),'Build the native CLI first.');
const parent=path.resolve('_build/duplicate-functions-verification');
fs.mkdirSync(parent,{recursive:true});
const dir=fs.mkdtempSync(path.join(parent,'run-'));
const cat=(...items)=>Buffer.concat(items.map(b=>Buffer.from(b)));
const leb=n=>{const a=[];do{const v=n&127;n>>>=7;a.push(v|(n?128:0));}while(n);return Buffer.from(a);};
const str=s=>cat(leb(Buffer.byteLength(s)),Buffer.from(s));
const section=(id,b)=>cat([id],leb(b.length),b);
const sha=b=>crypto.createHash('sha256').update(b).digest('hex');
const bodies=[[0,11],[0,11],[0,11],[0,1,11],[0,1,11],[0,0,11],[0,0,11],
  [0,1,1,11],[0,1,1,11],[1,1,127,11]].map(b=>Buffer.from(b));
const types=[0,1,0,0,1,0,0,0,1,0];
const parts=[Buffer.from('0061736d01000000','hex'),
  section(1,[2,96,0,0,96,1,127,0]),section(2,[1,1,109,1,102,0,0]),
  section(3,[10,...types])];
const chunks=[leb(bodies.length)], expected=[];
let relative=chunks[0].length;
for(const [i,body] of bodies.entries()){
  const prefix=i===8?Buffer.from([132,0]):leb(body.length);
  expected.push({index:i+1,type_index:types[i],prefix_size:prefix.length,
    body_size:body.length,total_size:prefix.length+body.length,relative});
  chunks.push(prefix,body);relative+=prefix.length+body.length;
}
const payload=cat(...chunks), codeStart=parts.reduce((n,b)=>n+b.length,0)+1+leb(payload.length).length;
for(const row of expected){row.offset=codeStart+row.relative;row.body_offset=row.offset+row.prefix_size;delete row.relative;}
parts.push(section(10,payload));
const core=cat(...parts);
const names=new Map([[1,'alpha'],[2,'beta'],[4,'same'],[6,'same'],[8,'prefix-one'],[9,'prefix-two"\n雪']]);
const nameMap=cat(leb(names.size),...Array.from(names,([i,name])=>cat(leb(i),str(name))));
const data=cat(core,section(0,cat(str('name'),section(1,nameMap))));
assert(WebAssembly.validate(data),'V8 rejected the duplicate-body fixture.'); // Once.
assert.deepEqual(data.subarray(0,core.length),core);
const input=path.join(dir,'named.wasm'), unnamed=path.join(dir,'unnamed.wasm'), output=path.join(dir,'duplicates.json');
fs.writeFileSync(input,data,{flag:'wx'});fs.writeFileSync(unnamed,core,{flag:'wx'});
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
const text=run(input,['--duplicates','--top','1'],0);
assert(text.includes('IDENTICAL FUNCTION BODIES'));
assert(text.includes('Showing 1 of 4 duplicate groups'));
assert(text.includes('Body bytes: 30 B = duplicate-group members 26 B + singletons 4 B'));
assert(text.includes('Encoded bytes: 41 B = body 30 B + length prefixes 11 B'));
assert(text.includes('TYPE INDEX  PREFIX B'));
assert(text.includes(JSON.stringify(names.get(9))));
assert.equal((text.match(/Group SHA-256:/g)||[]).length,1);
const confirmation=run(input,['--duplicates-json',output,'--top','1'],0);
assert(confirmation.includes('Duplicate function bodies written to '));
assert(!confirmation.includes('IDENTICAL FUNCTION BODIES'));
const saved=fs.readFileSync(output), report=JSON.parse(saved), s=report.summary;
assert.equal(report.format,'moonsize-duplicate-function-bodies');assert.equal(report.schema_version,1);
assert.equal(report.file_size,data.length);assert.equal(report.sha256,sha(data));
assert(!('graph_complete' in report));assert.equal(report.groups.length,4);
assert.equal(s.local_function_count,10);assert.equal(s.duplicate_member_count,9);
assert.equal(s.singleton_function_count,1);assert.equal(s.duplicate_group_count,4);
assert.equal(s.total_body_bytes,s.duplicate_body_bytes+s.singleton_body_bytes);
assert.equal(s.total_encoded_bytes,s.total_body_bytes+s.total_prefix_bytes);
assert.deepEqual(report.groups.map(g=>g.member_body_bytes),[8,6,6,6]);
assert.deepEqual(report.groups.map(g=>g.body_size),[4,3,3,2]);
assert(report.groups[1].sha256<report.groups[2].sha256);
const seen=new Set();
for(const group of report.groups){
  assert.equal(group.member_count,group.members.length);
  assert.equal(group.member_body_bytes,group.member_count*group.body_size);
  assert.equal(group.member_total_bytes,group.member_body_bytes+group.member_prefix_bytes);
  assert.equal(group.member_prefix_bytes,group.members.reduce((n,d)=>n+d.prefix_size,0));
  const indices=group.members.map(d=>d.index);assert.deepEqual(indices,[...indices].sort((a,b)=>a-b));
  for(const definition of group.members){
    assert(!seen.has(definition.index));seen.add(definition.index);
    for(const [key,value] of Object.entries(expected[definition.index-1]))assert.equal(definition[key],value);
    assert.equal(definition.raw_name,names.get(definition.index)??null);
    assert.equal(definition.name,names.get(definition.index)??'(unnamed)');
    const bytes=data.subarray(definition.body_offset,definition.body_offset+definition.body_size);
    assert.deepEqual(bytes,bodies[definition.index-1]);assert.equal(sha(bytes),group.sha256);
    assert.equal(group.body_size,bytes.length);assert(!('body' in definition));
  }
}
assert.equal(seen.size,9);assert(!seen.has(0));assert(!seen.has(10)); // Import and distinct locals excluded.
assert.deepEqual(report.groups[0].members.map(d=>d.type_index),[0,1]);
assert.deepEqual(report.groups[0].members.map(d=>d.prefix_size),[1,2]);
assert.deepEqual(report.groups[0].members.map(d=>d.total_size),[5,6]);
assert.deepEqual(report.groups[3].members.map(d=>d.index),[1,2,3]);
const noNames=run(unnamed,['--duplicates','--top','1'],0);
assert(noNames.includes('Showing 1 of 4 duplicate groups'));
assert(noNames.includes('(unnamed)'));assert(!noNames.includes('No identical function bodies found.'));
assert(noNames.includes('Encoded bytes: 41 B = body 30 B + length prefixes 11 B'));
const refused=run(input,['--duplicates-json',output],1);
assert(refused.includes('output already exists'));assert(!refused.includes('Duplicate function bodies written to '));
assert.deepEqual(fs.readFileSync(output),saved);
fs.writeFileSync(path.join(dir,'results.json'),JSON.stringify({
  file_size:data.length,input_sha256:sha(data),unnamed_size:core.length,unnamed_sha256:sha(core),
  cli_sha256:sha(fs.readFileSync(cli)),independent_validation:'Node/V8 validated named core once; unnamed removes only the final custom section',
  summary:s,groups:report.groups,records,
},null,2)+'\n',{flag:'wx'});
console.log('Duplicate-function CLI regressions passed (4 process cases, 1 V8-validated core). Evidence: '+dir);
