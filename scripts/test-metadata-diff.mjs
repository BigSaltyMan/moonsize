// Exactly four analyzer calls. Validate each legal outer module once, never execute it.
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import {spawnSync} from 'node:child_process';

const cli=path.resolve(process.argv[2]||'_build/native/release/build/cmd/main/main.exe');
assert(fs.existsSync(cli),'Build the native CLI first.');
const parent=path.resolve('_build/metadata-diff-verification');fs.mkdirSync(parent,{recursive:true});
const dir=fs.mkdtempSync(path.join(parent,'run-'));
const cat=(...parts)=>Buffer.concat(parts.map(x=>Buffer.from(x)));
const sha=b=>crypto.createHash('sha256').update(b).digest('hex');
const leb=n=>{const out=[];do{let b=n&127;n>>>=7;out.push(b|(n?128:0));}while(n);return Buffer.from(out);};
const wide=n=>{assert(n<128);return Buffer.from([n|128,0]);};
const head=Buffer.from('0061736d01000000','hex');
function custom(name,content,nonshort=false){
  const raw=Buffer.from(name),payload=cat(nonshort?wide(raw.length):leb(raw.length),raw,content);
  const prefix=nonshort?wide(payload.length):leb(payload.length);
  return {name,bytes:cat([0],prefix,payload),section_header_bytes:1+prefix.length,
    name_encoding_bytes:(nonshort?2:leb(raw.length).length)+raw.length,content_bytes:content.length};
}
function fixture(rows,extra=Buffer.alloc(0)){
  return {rows,bytes:cat(head,extra,...rows.map(r=>r.bytes))};
}
const before=fixture([custom('name',[1,1,0]),custom('x',[1]),custom('x',[2]),
  custom('.debug_info',[1,2]),custom('producers',[7]),custom('',[])]);
const after=fixture([custom('name',[1,1,0]),custom('x',[1,2,3,4],true),
  custom('.debug_info',[1]),custom('other',[3,4,5]),custom('',[])],Buffer.from([5,3,1,0,0]));
const partial=fixture([custom('name',[1,128]),custom('x',[9])]);
for(const [label,f]of [['baseline',before],['current',after],['partial',partial]]){
  assert(WebAssembly.validate(f.bytes),'V8 rejected '+label+' outer fixture.'); // Once each.
}
const baseline=path.join(dir,'before.wasm'),current=path.join(dir,'after.wasm'),partialInput=path.join(dir,'partial.wasm');
const output=path.join(dir,'metadata-diff.json'),partialOutput=path.join(dir,'partial-diff.json');
for(const [file,f]of [[baseline,before],[current,after],[partialInput,partial]])fs.writeFileSync(file,f.bytes,{flag:'wx'});
const records=[];
function run(file,args,status){
  const p=spawnSync(cli,[file,...args],{cwd:dir,encoding:'utf8',timeout:10000});
  const log=(p.stdout||'')+(p.stderr||'');
  fs.writeFileSync(path.join(dir,'case-'+records.length+'.log'),log,{flag:'wx'});
  records.push({file,args,status:p.status,error:p.error?.message??null});
  fs.writeFileSync(path.join(dir,'processes.json'),JSON.stringify(records,null,2)+'\n');
  assert.ifError(p.error);assert.equal(p.signal,null);assert.equal(p.status,status,log);
  for(const [input,f]of [[baseline,before],[current,after],[partialInput,partial]])assert.equal(sha(fs.readFileSync(input)),sha(f.bytes));
  return log;
}
const keys=['custom_count','custom_encoded_bytes','section_header_bytes','name_encoding_bytes','content_bytes'];
function totals(rows){return {custom_count:rows.length,custom_encoded_bytes:rows.reduce((n,r)=>n+r.bytes.length,0),
  section_header_bytes:rows.reduce((n,r)=>n+r.section_header_bytes,0),
  name_encoding_bytes:rows.reduce((n,r)=>n+r.name_encoding_bytes,0),content_bytes:rows.reduce((n,r)=>n+r.content_bytes,0)};}
function verify(r,b,c){
  assert.equal(r.format,'moonsize-metadata-diff');assert.equal(r.schema_version,1);
  for(const [input,f]of [[r.baseline,b],[r.current,c]]){
    assert.equal(typeof input,'object');assert.equal(input.format,'moonsize-metadata');
    assert.equal(input.sha256,sha(f.bytes));assert.equal(input.file_size,f.bytes.length);
    assert.equal(input.customs.length,f.rows.length);assert.equal(input.byte_ledger_complete,true);
    const t=totals(f.rows);assert.equal(input.summary.custom_bytes,t.custom_encoded_bytes);
    for(const [ordinal,row]of f.rows.entries()){
      const actual=input.customs.find(x=>x.ordinal===ordinal);assert(actual);
      assert.equal(actual.name,row.name);assert.equal(actual.encoding.size,row.bytes.length);
      assert.equal(actual.section_header_bytes,row.section_header_bytes);
      assert.equal(actual.name_encoding.size,row.name_encoding_bytes);assert.equal(actual.content.size,row.content_bytes);
    }
  }
  const bt=totals(b.rows),ct=totals(c.rows);
  for(const key of keys)assert.equal(r.delta[key],ct[key]-bt[key]);
  assert.equal(r.delta.custom_encoded_bytes,r.delta.section_header_bytes+r.delta.name_encoding_bytes+r.delta.content_bytes);
  assert.equal(r.baseline_non_custom_bytes,b.bytes.length-bt.custom_encoded_bytes);
  assert.equal(r.current_non_custom_bytes,c.bytes.length-ct.custom_encoded_bytes);
  assert.equal(r.delta_file_bytes,c.bytes.length-b.bytes.length);
  assert.equal(r.delta_file_bytes,r.delta.custom_encoded_bytes+r.delta_non_custom_bytes);
  assert.deepEqual(r.categories.map(g=>g.name),['name','producers','debug','other','unavailable']);
  for(const groups of [r.categories,r.name_groups]){
    for(const key of keys){
      assert.equal(groups.reduce((n,g)=>n+g.baseline[key],0),bt[key]);
      assert.equal(groups.reduce((n,g)=>n+g.current[key],0),ct[key]);
      assert.equal(groups.reduce((n,g)=>n+g.delta[key],0),r.delta[key]);
    }
    for(const g of groups){
      const matches=row=>g.kind==='category'?(row.name==='name'?'name':row.name==='producers'?'producers':row.name.startsWith('.debug_')?'debug':'other')===g.name:row.name===g.name;
      const bi=b.rows.flatMap((row,i)=>matches(row)?[i]:[]),ci=c.rows.flatMap((row,i)=>matches(row)?[i]:[]);
      assert.deepEqual(g.baseline_ordinals,bi);assert.deepEqual(g.current_ordinals,ci);
      assert.deepEqual(g.baseline,totals(bi.map(i=>b.rows[i])));assert.deepEqual(g.current,totals(ci.map(i=>c.rows[i])));
    }
  }
}
const text=run(current,['--baseline',baseline,'--diff-metadata','--metadata','--top','1'],0);
assert(text.includes('CUSTOM ENCODING COMPARISON (current - baseline)'));
assert(text.includes('FULL-NAME GROUPS: showing 1 of 6'));
assert(text.includes('Custom delta: -3 B = headers -1 B + name encodings -5 B + contents 3 B; count delta -1'));
assert(text.includes('File delta: 2 B = custom -3 B + non-custom 5 B'));
assert.equal(text.match(/name details: complete/g)?.length,2);
const names=text.split('FULL-NAME GROUPS:')[1].split('\nSCOPE')[0];
assert(names.includes('"producers"'));assert(!names.includes('"other"'));
const confirmation=run(current,['--baseline',baseline,'--diff-metadata','--metadata-json',output,'--top','1'],0);
assert(confirmation.includes('Metadata comparison written to '));assert(!confirmation.includes('OUTER BYTE LEDGER'));
const saved=fs.readFileSync(output),r=JSON.parse(saved);verify(r,before,after);
assert.equal(r.name_groups.length,6);assert.deepEqual(r.name_groups.find(g=>g.name==='x').baseline_ordinals,[1,2]);
assert.deepEqual(r.name_groups.find(g=>g.name==='x').current_ordinals,[1]);
run(partialInput,['--baseline',baseline,'--diff-metadata','--metadata-json',partialOutput],0);
const pr=JSON.parse(fs.readFileSync(partialOutput));verify(pr,before,partial);
assert.equal(pr.current.name_details_status,'partial');assert.equal(pr.current.custom_name_status,'complete');
assert(pr.current.diagnostics.length>0);assert(pr.current.customs.some(x=>x.unbounded_tail!==null));
assert(pr.comparison_scope.includes('not compared'));
const rejected=run(current,['--baseline',baseline,'--diff-metadata','--metadata-json',output],1);
assert(/exists|cannot safely|already/i.test(rejected),rejected);
assert(!rejected.includes('Metadata comparison written to '));assert.deepEqual(fs.readFileSync(output),saved);
fs.writeFileSync(path.join(dir,'results.json'),JSON.stringify({cli_sha256:sha(fs.readFileSync(cli)),
  independent_validation:'Node/V8 validated each of three outer fixtures once; no instantiation/execution',
  baseline_sha256:sha(before.bytes),current_sha256:sha(after.bytes),partial_sha256:sha(partial.bytes),
  baseline_size:before.bytes.length,current_size:after.bytes.length,
  baseline_totals:totals(before.rows),current_totals:totals(after.rows),delta:r.delta,
  delta_file_bytes:r.delta_file_bytes,delta_non_custom_bytes:r.delta_non_custom_bytes,records},null,2)+'\n',{flag:'wx'});
console.log('Metadata-diff regressions passed (4 process cases). Evidence: '+dir);
console.log('File delta '+r.delta_file_bytes+' B = custom '+r.delta.custom_encoded_bytes+' B + non-custom '+r.delta_non_custom_bytes+' B.');
