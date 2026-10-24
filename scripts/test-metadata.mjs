// Four analyzer calls only. Custom data is optional: the core is independently
// validated once, without treating malformed optional name details as core errors.
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import {spawnSync} from 'node:child_process';

const cli=path.resolve(process.argv[2]||'_build/native/release/build/cmd/main/main.exe');
assert(fs.existsSync(cli),'Build the native CLI first.');
const parent=path.resolve('_build/metadata-verification');
fs.mkdirSync(parent,{recursive:true});
const dir=fs.mkdtempSync(path.join(parent,'run-'));
const cat=(...items)=>Buffer.concat(items.map(b=>Buffer.from(b)));
const leb=n=>{const a=[];do{const v=n&127;n>>>=7;a.push(v|(n?128:0));}while(n);return Buffer.from(a);};
const wide=n=>{assert(n<128);return Buffer.from([n|128,0]);};
const str=s=>cat(leb(Buffer.byteLength(s)),Buffer.from(s));
const section=(id,b)=>cat([id],leb(b.length),b);
const custom=(name,b,nonshort=false)=>{
  const raw=Buffer.from(name), payload=cat(nonshort?wide(raw.length):leb(raw.length),raw,b);
  return cat([0],nonshort?wide(payload.length):leb(payload.length),payload);
};
const sha=b=>crypto.createHash('sha256').update(b).digest('hex');
const header=Buffer.from('0061736d01000000','hex');
const firstMap=cat(wide(3),[1],str('dup'),[1],str('dup'),[255,255,255,255,15],wide(3),Buffer.from('雪'));
const data=cat(header,
  custom('name',cat([1],wide(firstMap.length),firstMap),true),
  custom('.debug_info',[1,2,3]),custom('producers',[9,8]),
  custom('name',cat(section(1,cat([1,2],str('longer-name'))),section(42,[255,128]))),
  custom('说明',[7]),custom('说明',[]),custom('',[1]));
assert(WebAssembly.validate(data),'V8 rejected the mixed-custom core fixture.'); // Once.
const partial=cat(header,
  custom('name',cat(section(1,[2,1,2,111,107,2,3,120]),section(42,[255]),
    section(1,cat([1,3],str('later'))),[1,128])),
  custom('name',section(1,cat([1,4],str('after')))));
const input=path.join(dir,'mixed.wasm'), broken=path.join(dir,'partial-name.wasm');
const output=path.join(dir,'metadata.json');
fs.writeFileSync(input,data,{flag:'wx'});fs.writeFileSync(broken,partial,{flag:'wx'});
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
const text=run(input,['--metadata','--top','1'],0);
assert(text.includes('METADATA FILE BYTES'));
assert(text.includes('Custom sections: 7; 115 B (93.4% of file)'));
assert(text.includes('CUSTOM INSTANCES: showing 1 of 7'));
assert(text.includes('NAME SUBSECTIONS: showing 1 of 3'));
assert(text.includes('FUNCTION-NAME RECORDS: showing 1 of 4'));
assert(text.includes('"说明"  2 instances  19 B'));
assert(text.includes('"longer-name"'));assert(!text.includes('"dup"'));
assert(text.includes('name details: complete'));
const confirmation=run(input,['--metadata-json',output,'--top','1'],0);
assert(confirmation.includes('Metadata written to '));assert(!confirmation.includes('METADATA FILE BYTES'));
const saved=fs.readFileSync(output), report=JSON.parse(saved), s=report.summary;
assert.equal(report.format,'moonsize-metadata');assert.equal(report.schema_version,1);
assert.equal(report.file_size,data.length);assert.equal(data.length,123);assert.equal(report.sha256,sha(data));
assert.equal(report.byte_ledger_complete,true);assert.equal(report.custom_name_status,'complete');
assert.equal(report.name_details_status,'complete');assert.deepEqual(report.diagnostics,[]);
assert.equal(report.custom_fraction,115/123);
assert.equal(s.custom_count,7);assert.equal(s.custom_bytes,115);
assert.equal(s.custom_bytes,s.section_header_bytes+s.custom_name_encoding_bytes+s.content_bytes);
assert.equal(s.custom_bytes,report.categories.reduce((n,g)=>n+g.total_bytes,0));
assert.equal(s.custom_bytes,report.name_groups.reduce((n,g)=>n+g.total_bytes,0));
assert.deepEqual(report.categories.map(g=>g.total_bytes),[61,14,17,23,0]);
assert.deepEqual(report.customs.map(c=>c.ordinal),[0,3,1,2,4,5,6]);
assert.deepEqual(report.name_groups.find(g=>g.name==='说明').custom_ordinals,[4,5]);
assert.equal(s.name_content_bytes,45);assert.equal(s.name_subsection_bytes,45);
assert.equal(s.unbounded_name_tail_bytes,0);assert.equal(s.function_name_payload_bytes,36);
assert.equal(s.function_name_payload_bytes,s.function_name_count_prefix_bytes+s.parsed_function_record_bytes+s.function_name_unparsed_bytes);
assert.equal(s.parsed_function_record_bytes,33);
assert.equal(s.parsed_function_record_bytes,s.function_index_prefix_bytes+s.function_name_length_prefix_bytes+s.function_name_utf8_bytes);
assert.equal(s.parsed_function_record_count,4);assert.equal(report.function_names.length,4);
assert.deepEqual(report.function_names.map(r=>r.encoding.size),[13,10,5,5]);
assert.equal(report.function_names[1].function_index,4294967295);
assert.equal(report.function_names[1].name,'雪');
assert.equal(report.function_names.filter(r=>r.function_index===1&&r.name==='dup').length,2);
assert.equal(report.subsections.length,3);assert.equal(report.subsections[2].status,'opaque');
assert.equal(report.subsections[0].header_bytes,3);assert.equal(report.subsections[0].count_prefix_bytes,2);
function inside(child,parent){assert(child.offset>=parent.offset);assert(child.size>=0);
  assert(child.offset+child.size<=parent.offset+parent.size);}
for(const c of report.customs){
  inside(c.encoding,{offset:0,size:data.length});inside(c.name_encoding,c.encoding);inside(c.name_bytes,c.name_encoding);inside(c.content,c.encoding);
  assert.equal(c.encoding.size,c.section_header_bytes+c.name_encoding.size+c.content.size);
  assert.equal(c.name_encoding.size,c.name_length_prefix_bytes+c.name_bytes.size);
  assert.equal(data.subarray(c.name_bytes.offset,c.name_bytes.offset+c.name_bytes.size).toString('utf8'),c.name);
}
for(const r of report.function_names){
  const sub=report.subsections.find(s=>s.custom_ordinal===r.custom_ordinal&&s.ordinal===r.subsection_ordinal);
  inside(r.encoding,sub.payload);inside(r.name_bytes,r.encoding);
  assert.equal(r.encoding.size,r.index_prefix_bytes+r.name_length_prefix_bytes+r.name_bytes.size);
  assert.equal(data.subarray(r.name_bytes.offset,r.name_bytes.offset+r.name_bytes.size).toString('utf8'),r.name);
}
const partialText=run(broken,['--metadata'],0);
assert(partialText.includes('Byte ledger: complete; custom-name decoding: complete; name details: partial'));
assert(partialText.includes('Name contents: 35 B = bounded subsections 33 B + unbounded tails 2 B'));
assert(partialText.includes('Function-name payloads: 24 B = count prefixes 3 B + parsed records 18 B + unparsed 3 B'));
assert(partialText.includes('"later"'));assert(partialText.includes('"after"'));
assert(partialText.includes('function-name record 1:'));
assert(partialText.includes('unbounded name subsection:'));assert(partialText.includes('Diagnostics: 2'));
assert(!partialText.includes('METADATA FILE BYTES\n\nMETADATA'));
const refused=run(input,['--metadata-json',output],1);
assert(refused.includes('output already exists'));assert(!refused.includes('Metadata written to '));
assert.deepEqual(fs.readFileSync(output),saved);
fs.writeFileSync(path.join(dir,'results.json'),JSON.stringify({
  file_size:data.length,input_sha256:sha(data),partial_size:partial.length,partial_sha256:sha(partial),
  cli_sha256:sha(fs.readFileSync(cli)),independent_validation:'Node/V8 validated the mixed-custom core once; custom details are optional',
  summary:s,records,
},null,2)+'\n',{flag:'wx'});
console.log('Metadata CLI regressions passed (4 process cases, 1 V8-validated core). Evidence: '+dir);
