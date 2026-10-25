// Four real analyzer calls; validate the legal five-kind fixture once, never execute it.
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import {spawnSync} from 'node:child_process';

const cli=path.resolve(process.argv[2]||'_build/native/release/build/cmd/main/main.exe');
assert(fs.existsSync(cli),'Build the native CLI first.');
const parent=path.resolve('_build/exports-verification');fs.mkdirSync(parent,{recursive:true});
const dir=fs.mkdtempSync(path.join(parent,'run-'));
const cat=(...parts)=>Buffer.concat(parts.map(p=>Buffer.from(p)));
const leb=n=>{const out=[];do{let b=n&127;n>>>=7;out.push(b|(n?128:0));}while(n);return Buffer.from(out);};
const wide=n=>{assert(n<128);return Buffer.from([n|128,0]);};
const str=s=>cat(leb(Buffer.byteLength(s)),Buffer.from(s));
const section=(id,p)=>cat([id],leb(p.length),p);
const sha=b=>crypto.createHash('sha256').update(b).digest('hex');
const kinds=['function','table','memory','global','tag'];
const imported=[['f',[0,0]],['t',[1,0x70,0,1]],['m',[2,0,1]],['g',[3,0x7f,0]],['tag',[4,0,0]]];
const prefix=cat(Buffer.from('0061736d01000000','hex'),section(1,[1,0x60,0,0]),
  section(2,cat([5],...imported.map(([field,desc])=>cat(str('host'),str(field),desc)))));
const declarations=[['f',0],['f alias',0],['t',1],['t.alt',1],['mem',2],['g',3],['tag',4],['雪"\n',0]];
function fixture(rows){
  const encoded=rows.map(([name,kind],ordinal)=>{
    const raw=Buffer.from(name),namePrefix=ordinal===0?wide(raw.length):leb(raw.length),indexPrefix=ordinal===0?wide(0):leb(0);
    return {ordinal,name,kind,raw,namePrefix,indexPrefix,bytes:cat(namePrefix,raw,[kind],indexPrefix)};
  });
  const count=wide(rows.length),payload=cat(count,...encoded.map(e=>e.bytes)),header=cat([7],wide(payload.length));
  let offset=prefix.length+header.length+count.length;
  for(const e of encoded){e.offset=offset;offset+=e.bytes.length;}
  return {bytes:cat(prefix,header,payload),entries:encoded,sectionOffset:prefix.length,headerBytes:header.length,countBytes:count.length};
}
const legal=fixture(declarations);
assert(WebAssembly.validate(legal.bytes),'Node/V8 rejected the legal five-kind fixture.'); // Once only.
const duplicateRows=declarations.map(row=>[...row]);duplicateRows[2][0]='f';
const duplicate=fixture(duplicateRows); // Structurally framed; duplicate names are intentionally invalid.
const input=path.join(dir,'exports.wasm'),bad=path.join(dir,'duplicate-name.wasm');
const output=path.join(dir,'exports.json'),badOutput=path.join(dir,'bad.json');
fs.writeFileSync(input,legal.bytes,{flag:'wx'});fs.writeFileSync(bad,duplicate.bytes,{flag:'wx'});
const records=[];
function run(file,args,status){
  const p=spawnSync(cli,[file,...args],{cwd:dir,encoding:'utf8',timeout:10000});
  const log=(p.stdout||'')+(p.stderr||'');
  fs.writeFileSync(path.join(dir,'case-'+records.length+'.log'),log,{flag:'wx'});
  records.push({input:file,args,status:p.status,error:p.error?.message??null});
  fs.writeFileSync(path.join(dir,'processes.json'),JSON.stringify(records,null,2)+'\n');
  assert.ifError(p.error);assert.equal(p.signal,null);assert.equal(p.status,status,log);
  assert.equal(sha(fs.readFileSync(input)),sha(legal.bytes));assert.equal(sha(fs.readFileSync(bad)),sha(duplicate.bytes));
  return log;
}
const text=run(input,['--exports','--top','1'],0);
assert(text.includes('Kinds: function 3; table 2; memory 1; global 1; tag 1'));
assert(text.includes('Declarations: 8; distinct declared targets: 5'));
assert(text.includes('Alias groups: 2; alias members: 5; singleton targets: 3'));
assert(text.includes('Export section: 57 B = headers 3 B + count 2 B + declarations 52 B'));
assert(text.includes('DECLARATIONS: showing 1 of 8'));assert(text.includes('ALIAS GROUPS: showing 1 of 2'));
const declarationTable=text.split('DECLARATIONS:')[1].split('ALIAS GROUPS:')[0];
assert(declarationTable.includes('"f alias"'));assert(!declarationTable.includes('"t.alt"'));
const aliasTable=text.split('ALIAS GROUPS:')[1].split('\nSCOPE')[0];
assert(aliasTable.includes('Names: showing 3 of 3'));assert(aliasTable.includes(JSON.stringify('雪"\n')));
assert(!text.includes('雪"\n'),'Control characters must be escaped in the terminal.');
const confirmation=run(input,['--exports-json',output,'--top','1'],0);
assert(confirmation.includes('Exports written to '));assert(!confirmation.includes('EXPORT DECLARATIONS'));
const saved=fs.readFileSync(output),r=JSON.parse(saved),s=r.summary,l=r.ledger;
assert.equal(r.format,'moonsize-exports');assert.equal(r.schema_version,1);
assert.equal(r.file_size,legal.bytes.length);assert.equal(r.sha256,sha(legal.bytes));
assert.deepEqual(s,{export_count:8,kind_counts:{function:3,table:2,memory:1,global:1,tag:1},
  distinct_target_count:5,alias_group_count:2,alias_member_count:5,singleton_target_count:3});
assert.equal(l.export_section_bytes,l.section_header_bytes+l.count_prefix_bytes+l.declaration_bytes);
assert.equal(l.declaration_bytes,l.name_encoding_bytes+l.descriptor_bytes);
assert.equal(l.name_encoding_bytes,l.name_length_prefix_bytes+l.name_utf8_bytes);
assert.equal(l.descriptor_bytes,l.kind_bytes+l.target_index_prefix_bytes);
assert.equal(l.export_section_bytes,legal.bytes.length-prefix.length);
assert.equal(l.section_header_bytes,legal.headerBytes);assert.equal(l.count_prefix_bytes,legal.countBytes);
assert.equal(s.export_count,s.alias_member_count+s.singleton_target_count);
assert.equal(s.distinct_target_count,s.alias_group_count+s.singleton_target_count);
assert.equal(Object.values(s.kind_counts).reduce((n,x)=>n+x,0),s.export_count);
assert.deepEqual(r.section,{offset:legal.sectionOffset,size:legal.bytes.length-legal.sectionOffset});
assert.deepEqual(r.count_encoding,{offset:legal.sectionOffset+legal.headerBytes,size:legal.countBytes});
assert.equal(r.entries.length,8);assert.deepEqual(r.targets.map(t=>t.kind_code),[0,1,2,3,4]);
let declarationBytes=0;
for(const [i,e]of r.entries.entries()){
  const expected=legal.entries[i];assert.equal(e.ordinal,i);assert.equal(e.name,expected.name);
  assert.equal(e.kind,kinds[expected.kind]);assert.equal(e.kind_code,expected.kind);assert.equal(e.target_index,0);
  assert.deepEqual(e.encoding,{offset:expected.offset,size:expected.bytes.length});
  assert.deepEqual(e.name_encoding,{offset:expected.offset,size:expected.namePrefix.length+expected.raw.length});
  assert.equal(e.name_length_prefix_bytes,expected.namePrefix.length);assert.equal(e.name_utf8_bytes,expected.raw.length);
  assert.deepEqual(e.descriptor,{offset:expected.offset+e.name_encoding.size,size:1+expected.indexPrefix.length});
  assert.equal(e.target_index_prefix_bytes,expected.indexPrefix.length);
  declarationBytes+=e.encoding.size;
}
assert.equal(declarationBytes,l.declaration_bytes);
for(const t of r.targets){
  const ordinals=legal.entries.filter(e=>e.kind===t.kind_code).map(e=>e.ordinal);
  assert.equal(t.target_index,0);assert.equal(t.kind,kinds[t.kind_code]);assert.deepEqual(t.entry_ordinals,ordinals);
  assert.equal(t.member_count,ordinals.length);assert.equal(t.is_alias,ordinals.length>=2);
  assert.equal(t.declaration_bytes,ordinals.reduce((n,i)=>n+r.entries[i].encoding.size,0));
}
assert.equal(r.targets.reduce((n,t)=>n+t.declaration_bytes,0),l.declaration_bytes);
assert(!Object.hasOwn(r,'graph_complete'));assert(r.supported_scope.includes('not validated'));
const rejectedInput=run(bad,['--exports-json',badOutput],1);
assert(rejectedInput.includes('duplicate export name "f"'));
assert(rejectedInput.includes('at offset '+duplicate.entries[2].offset));
assert(rejectedInput.includes('first declaration at file offset '+duplicate.entries[0].offset));
assert(!rejectedInput.includes('EXPORT DECLARATIONS'));assert(!rejectedInput.includes('Exports written to '));
assert(!fs.existsSync(badOutput));
const rejectedOutput=run(input,['--exports-json',output],1);
assert(rejectedOutput.includes('output already exists'));assert(!rejectedOutput.includes('Exports written to '));
assert.deepEqual(fs.readFileSync(output),saved);
fs.writeFileSync(path.join(dir,'results.json'),JSON.stringify({input_size:legal.bytes.length,input_sha256:sha(legal.bytes),
  invalid_duplicate_sha256:sha(duplicate.bytes),cli_sha256:sha(fs.readFileSync(cli)),
  independent_validation:'Node/V8 validated the legal five-kind fixture once; no instantiation or execution',
  summary:s,ledger:l,records},null,2)+'\n',{flag:'wx'});
console.log('Exports regressions passed (4 process cases, 1 V8-validated fixture). Evidence: '+dir);
console.log('Aliases: '+s.alias_group_count+' groups / '+s.alias_member_count+' members. Export bytes '+l.export_section_bytes+' = '+l.section_header_bytes+' headers + '+l.count_prefix_bytes+' count + '+l.declaration_bytes+' declarations.');
