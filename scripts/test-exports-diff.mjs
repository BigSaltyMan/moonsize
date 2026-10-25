// Exactly four analyzer calls. Validate each legal fixture once; no execution/probe.
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import {spawnSync} from 'node:child_process';

const cli=path.resolve(process.argv[2]||'_build/native/release/build/cmd/main/main.exe');
assert(fs.existsSync(cli),'Build the native CLI first.');
const parent=path.resolve('_build/exports-diff-verification');fs.mkdirSync(parent,{recursive:true});
const dir=fs.mkdtempSync(path.join(parent,'run-'));
const cat=(...parts)=>Buffer.concat(parts.map(p=>Buffer.from(p)));
const leb=n=>{const a=[];do{const b=n&127;n>>>=7;a.push(b|(n?128:0));}while(n);return Buffer.from(a);};
const wide=n=>{assert(n<128);return Buffer.from([n|128,0]);};
const str=s=>cat(leb(Buffer.byteLength(s)),Buffer.from(s));
const section=(id,p)=>cat([id],leb(p.length),p);
const sha=b=>crypto.createHash('sha256').update(b).digest('hex');
const kinds=['function','table','memory','global','tag'];
const imported=[['f',[0,0]],['t',[1,0x70,0,1]],['m',[2,0,1]],['g',[3,0x7f,0]],['tag',[4,0,0]]];
function fixture(rows,padding=false,nonshort=false){
  const imports=padding?[['padding',[0,0]],...imported]:imported;
  const prefix=cat(Buffer.from('0061736d01000000','hex'),section(1,[1,0x60,0,0]),
    section(2,cat(leb(imports.length),...imports.map(([field,desc])=>cat(str('host'),str(field),desc)))));
  const encoded=rows.map(([name,kind,index],ordinal)=>{
    const raw=Buffer.from(name),namePrefix=nonshort&&ordinal===0?wide(raw.length):leb(raw.length),indexPrefix=nonshort&&ordinal===0?wide(index):leb(index);
    return {ordinal,name,kind,index,raw,namePrefix,indexPrefix,bytes:cat(namePrefix,raw,[kind],indexPrefix)};
  });
  const count=nonshort?wide(rows.length):leb(rows.length),payload=cat(count,...encoded.map(e=>e.bytes));
  const header=cat([7],nonshort?wide(payload.length):leb(payload.length));
  let offset=prefix.length+header.length+count.length;
  for(const e of encoded){e.offset=offset;offset+=e.bytes.length;}
  const sum=fn=>encoded.reduce((n,e)=>n+fn(e),0);
  const ledger={export_section_bytes:header.length+payload.length,section_header_bytes:header.length,
    count_prefix_bytes:count.length,declaration_bytes:sum(e=>e.bytes.length),
    name_encoding_bytes:sum(e=>e.namePrefix.length+e.raw.length),name_length_prefix_bytes:sum(e=>e.namePrefix.length),
    name_utf8_bytes:sum(e=>e.raw.length),descriptor_bytes:sum(e=>1+e.indexPrefix.length),
    kind_bytes:rows.length,target_index_prefix_bytes:sum(e=>e.indexPrefix.length)};
  return {bytes:cat(prefix,header,payload),entries:encoded,ledger,nonExportBytes:prefix.length};
}
const beforeRows=[['removed',0,0],['switch',0,0],['same',0,0],['alias',0,0],['table',1,0],['',0,0],['雪"\n',0,0]];
const afterRows=[['new-feature',0,1],['switch',3,0],['same',0,1],['alias',0,1],['table',1,0],['',0,1],['雪"\n',0,1]];
const before=fixture(beforeRows),after=fixture(afterRows,true,true);
const renumbered=fixture(beforeRows.map(([name,kind,index])=>[name,kind,kind===0?1:index]),true);
for(const [label,f]of [['baseline',before],['current',after],['renumbered',renumbered]]){
  assert(WebAssembly.validate(f.bytes),'V8 rejected '+label+' fixture.'); // Once each.
}
const baseline=path.join(dir,'before.wasm'),current=path.join(dir,'after.wasm'),renumberInput=path.join(dir,'renumbered.wasm');
const output=path.join(dir,'exports-diff.json');
for(const [file,f]of [[baseline,before],[current,after],[renumberInput,renumbered]])fs.writeFileSync(file,f.bytes,{flag:'wx'});
const records=[];
function run(file,args,status){
  const p=spawnSync(cli,[file,...args],{cwd:dir,encoding:'utf8',timeout:10000});
  const log=(p.stdout||'')+(p.stderr||'');
  fs.writeFileSync(path.join(dir,'case-'+records.length+'.log'),log,{flag:'wx'});
  records.push({input:file,args,status:p.status,error:p.error?.message??null});
  fs.writeFileSync(path.join(dir,'processes.json'),JSON.stringify(records,null,2)+'\n');
  assert.ifError(p.error);assert.equal(p.signal,null);assert.equal(p.status,status,log);
  for(const [input,f]of [[baseline,before],[current,after],[renumberInput,renumbered]])assert.equal(sha(fs.readFileSync(input)),sha(f.bytes));
  return log;
}
const text=run(current,['--baseline',baseline,'--diff-exports','--exports','--top','1'],0);
assert(text.includes('Names: removed 1; kind_changed 1; added 1; same_kind 5; rows 8'));
assert(text.includes('Export delta: 8 B = headers 1 B + count 1 B + declarations 6 B'));
assert(text.includes('File delta: 23 B = export 8 B + non-export 15 B'));
assert(text.includes('NAMES: showing 1 of 8'));
const names=text.split('NAMES: showing')[1];
assert(names.includes('"removed"  removed'));assert(!names.includes('"new-feature"'));
assert(text.includes('full ABI'));assert(!text.includes('breaking'));
const confirmation=run(current,['--baseline',baseline,'--diff-exports','--exports-json',output,'--top','1'],0);
assert(confirmation.includes('Exports comparison written to '));assert(!confirmation.includes('ENCODING LEDGER'));
const saved=fs.readFileSync(output),r=JSON.parse(saved),c=r.counts,d=r.delta;
assert.equal(r.format,'moonsize-exports-diff');assert.equal(r.schema_version,1);
assert.deepEqual(c,{added_count:1,removed_count:1,kind_changed_count:1,same_kind_count:5,row_count:8});
for(const [inventory,f]of [[r.baseline,before],[r.current,after]]){
  assert.equal(typeof inventory,'object');assert.equal(inventory.format,'moonsize-exports');
  assert.equal(inventory.sha256,sha(f.bytes));assert.equal(inventory.file_size,f.bytes.length);
  assert.deepEqual(inventory.ledger,f.ledger);assert.equal(inventory.entries.length,f.entries.length);
  for(const [i,e]of inventory.entries.entries()){
    const expected=f.entries[i];assert.equal(e.ordinal,i);assert.equal(e.name,expected.name);
    assert.equal(e.kind,kinds[expected.kind]);assert.equal(e.target_index,expected.index);
    assert.deepEqual(e.encoding,{offset:expected.offset,size:expected.bytes.length});
  }
  assert.equal(inventory.targets.reduce((n,t)=>n+t.member_count,0),f.entries.length);
  assert.equal(inventory.targets.reduce((n,t)=>n+t.declaration_bytes,0),f.ledger.declaration_bytes);
  for(const t of inventory.targets){
    const members=f.entries.filter(e=>e.kind===t.kind_code&&e.index===t.target_index);
    assert.deepEqual(t.entry_ordinals,members.map(e=>e.ordinal));assert.equal(t.member_count,members.length);
  }
}
assert.equal(r.baseline.targets.length,2);assert.equal(r.current.targets.length,3);
assert.deepEqual(r.baseline.targets[0].entry_ordinals,[0,1,2,3,5,6]);
assert.deepEqual(r.current.targets[0].entry_ordinals,[0,2,3,5,6]);
assert.equal(r.baseline.summary.export_count,c.removed_count+c.kind_changed_count+c.same_kind_count);
assert.equal(r.current.summary.export_count,c.added_count+c.kind_changed_count+c.same_kind_count);
assert.equal(r.rows.length,c.row_count);assert.equal(c.row_count,c.added_count+c.removed_count+c.kind_changed_count+c.same_kind_count);
assert.deepEqual(r.rows.map(row=>row.status),['removed','kind_changed','added','same_kind','same_kind','same_kind','same_kind','same_kind']);
const bm=new Map(r.baseline.entries.map(e=>[e.name,e])),cm=new Map(r.current.entries.map(e=>[e.name,e]));
for(const row of r.rows){
  const b=bm.get(row.name)??null,a=cm.get(row.name)??null;
  const status=!b?'added':!a?'removed':b.kind_code!==a.kind_code?'kind_changed':'same_kind';
  assert.equal(row.status,status);assert.deepEqual(row.baseline,b);assert.deepEqual(row.current,a);
  assert.equal(row.declaration_bytes_delta,(a?.encoding.size??0)-(b?.encoding.size??0));
  assert.equal(row.target_index_changed,status==='same_kind'?b.target_index!==a.target_index:null);
}
for(const key of Object.keys(before.ledger))assert.equal(d[key],after.ledger[key]-before.ledger[key]);
assert.equal(d.export_section_bytes,d.section_header_bytes+d.count_prefix_bytes+d.declaration_bytes);
assert.equal(d.declaration_bytes,d.name_encoding_bytes+d.descriptor_bytes);
assert.equal(d.declaration_bytes,r.rows.reduce((n,row)=>n+row.declaration_bytes_delta,0));
assert.equal(r.baseline_non_export_bytes,before.nonExportBytes);assert.equal(r.current_non_export_bytes,after.nonExportBytes);
assert.equal(r.delta_non_export_bytes,after.nonExportBytes-before.nonExportBytes);
assert.equal(r.delta_file_bytes,after.bytes.length-before.bytes.length);
assert.equal(r.delta_file_bytes,d.export_section_bytes+r.delta_non_export_bytes);
const renumberText=run(renumberInput,['--baseline',baseline,'--diff-exports','--top','20'],0);
assert(renumberText.includes('Names: removed 0; kind_changed 0; added 0; same_kind 7; rows 7'));
assert(renumberText.includes('Export delta: 0 B = headers 0 B + count 0 B + declarations 0 B'));
assert(renumberText.includes('"same"  same_kind  function #0  function #1  0  true'));
assert(renumberText.includes('"table"  same_kind  table #0  table #0  0  false'));
assert.equal(renumberText.split('NAMES: showing')[1].match(/  true$/gm)?.length,6);
for(const word of ['compatible','breaking','unchanged'])assert(!renumberText.includes(word));
const rejected=run(current,['--baseline',baseline,'--diff-exports','--exports-json',output],1);
assert(rejected.includes('output already exists'));assert(!rejected.includes('Exports comparison written to '));
assert.deepEqual(fs.readFileSync(output),saved);
fs.writeFileSync(path.join(dir,'results.json'),JSON.stringify({
  cli_sha256:sha(fs.readFileSync(cli)),baseline_size:before.bytes.length,current_size:after.bytes.length,renumbered_size:renumbered.bytes.length,
  baseline_sha256:sha(before.bytes),current_sha256:sha(after.bytes),renumbered_sha256:sha(renumbered.bytes),
  independent_validation:'Node/V8 validated all three legal fixtures once; no instantiation/execution',
  counts:c,baseline_ledger:before.ledger,current_ledger:after.ledger,delta:d,
  delta_file_bytes:r.delta_file_bytes,delta_non_export_bytes:r.delta_non_export_bytes,
  renumbered:{same_kind_count:7,function_index_changes:6,export_section_delta:0},records},null,2)+'\n',{flag:'wx'});
console.log('Exports-diff regressions passed (4 process cases). Evidence: '+dir);
console.log('File delta '+r.delta_file_bytes+' B = export '+d.export_section_bytes+' B + non-export '+r.delta_non_export_bytes+' B.');
