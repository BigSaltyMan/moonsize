// Four analyzer calls only; validate the named fixture once without execution.
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import {spawnSync} from 'node:child_process';

const cli=path.resolve(process.argv[2]||'_build/native/release/build/cmd/main/main.exe');
assert(fs.existsSync(cli),'Build the native CLI first.');
const parent=path.resolve('_build/function-search-verification');fs.mkdirSync(parent,{recursive:true});
const dir=fs.mkdtempSync(path.join(parent,'run-'));
const cat=(...items)=>Buffer.concat(items.map(item=>Buffer.from(item)));
const leb=value=>{const bytes=[];do{let byte=value&127;value=Math.floor(value/128);if(value)byte|=128;bytes.push(byte);}while(value);return Buffer.from(bytes);};
const section=(id,payload)=>cat([id],leb(payload.length),payload);
const sha=bytes=>crypto.createHash('sha256').update(bytes).digest('hex');
const raw='_M0FP34demo6sample3src8classify';
const unsafeName='classify\nrow\t\x1b\u0085\u2028雪';
const names=[[0,'classify-import'],[1,raw],[2,raw],[3,unsafeName],[4,'Classify']];
const bodies=[Buffer.from([0,11]),Buffer.from([0,1,11]),Buffer.from([0,1,1,11]),Buffer.from([0,11]),Buffer.from([0,11])];
const data=cat(Buffer.from('0061736d01000000010401600000020701016d01660000','hex'),
  section(3,cat([5,0,0,0,0,0])),
  section(10,cat([5],...bodies.map((body,i)=>cat(i===1?[body.length|128,0]:leb(body.length),body)))),
  section(0,cat([4],Buffer.from('name'),section(1,cat(leb(names.length),...names.map(([index,name])=>{
    const bytes=Buffer.from(name);return cat(leb(index),leb(bytes.length),bytes);
  }))))));
assert(WebAssembly.validate(data),'Node/V8 rejected the named function-search fixture.'); // Once.
const input=path.join(dir,'named.wasm'),output=path.join(dir,'search.json');fs.writeFileSync(input,data,{flag:'wx'});
const query='classify',records=[];
function run(args,status){
  const proc=spawnSync(cli,[input,...args],{cwd:dir,encoding:'utf8',timeout:10000});
  const log=(proc.stdout||'')+(proc.stderr||'');
  fs.writeFileSync(path.join(dir,'case-'+records.length+'.log'),log,{flag:'wx'});
  records.push({args,status:proc.status,error:proc.error?.message||null});
  assert.ifError(proc.error);assert.equal(proc.signal,null);assert.equal(proc.status,status,log);
  assert.equal(sha(fs.readFileSync(input)),sha(data));return log;
}
const text=run(['--find-functions',query,'--top','1'],0);
assert(text.includes('LOCAL FUNCTION NAME SEARCH'));assert(text.includes('Query: "classify"'));
assert(text.includes('Local functions: 5 = named 4 + unnamed 1'));
assert(text.includes('Named functions: 4 = matched 3 + unmatched 1'));
assert(text.includes('Matched encoded bytes: 13 B = body 9 B + length prefixes 4 B'));
assert(text.includes('MATCHES: showing 1 of 3'));
assert(text.includes('2  3  5  raw+display  "demo::sample::src::classify"'));
assert(text.includes('body-length prefix file offset 37'));
assert(!text.includes('classify\\nrow'));assert(!text.includes('classify-import'));
const confirmation=run(['--find-functions',query,'--find-functions-json',output,'--top','1'],0);
assert(confirmation.includes('Function search written to '));assert(!confirmation.includes('NAME COVERAGE'));
const saved=fs.readFileSync(output),report=JSON.parse(saved);
assert.equal(report.format,'moonsize-function-search');assert.equal(report.schema_version,1);
assert.equal(report.file_size,data.length);assert.equal(report.sha256,sha(data));assert.equal(report.query,query);
assert(report.matching_rule.includes('Case-sensitive literal substring'));
assert.equal(report.local_function_count,5);assert.equal(report.named_count,4);assert.equal(report.unnamed_count,1);
assert.equal(report.match_count,3);assert.equal(report.unmatched_named_count,1);
assert.equal(report.local_function_count,report.named_count+report.unnamed_count);
assert.equal(report.named_count,report.match_count+report.unmatched_named_count);
assert.equal(report.matched_encoded_bytes,13);assert.equal(report.matched_body_bytes,9);assert.equal(report.matched_prefix_bytes,4);
assert.equal(report.matched_encoded_bytes,report.matched_body_bytes+report.matched_prefix_bytes);
assert.equal(report.matches.length,3);assert.deepEqual(report.matches.map(m=>m.index),[2,3,1]);
const expected=[
  {index:2,name:'demo::sample::src::classify',raw_name:raw,module_name:'demo::sample::src',offset:37,body_size:3,total_size:5,matched_raw_name:true,matched_display_name:true},
  {index:3,name:unsafeName,raw_name:unsafeName,module_name:'(top-level)',offset:42,body_size:4,total_size:5,matched_raw_name:true,matched_display_name:true},
  {index:1,name:'demo::sample::src::classify',raw_name:raw,module_name:'demo::sample::src',offset:34,body_size:2,total_size:3,matched_raw_name:true,matched_display_name:true},
];
assert.deepEqual(report.matches,expected);
assert.equal(report.matches.reduce((sum,m)=>sum+m.body_size,0),report.matched_body_bytes);
assert.equal(report.matches.reduce((sum,m)=>sum+m.total_size-m.body_size,0),report.matched_prefix_bytes);
assert.equal(report.matches.reduce((sum,m)=>sum+m.total_size,0),report.matched_encoded_bytes);
assert(!('graph_complete'in report));assert(report.scope.includes('No match does not prove a function is absent'));
const none=run(['--find-functions','does-not-match'],0);
assert(none.includes('Named functions: 4 = matched 0 + unmatched 4'));
assert(none.includes('No matches in the available local function names.'));
assert(none.includes('Matched encoded bytes: 0 B = body 0 B + length prefixes 0 B'));
const refused=run(['--find-functions',query,'--find-functions-json',output],1);
assert(refused.includes('output already exists'));assert(!refused.includes('written to'));assert.deepEqual(fs.readFileSync(output),saved);
fs.writeFileSync(path.join(dir,'results.json'),JSON.stringify({input_size:data.length,input_sha256:sha(data),cli_sha256:sha(fs.readFileSync(cli)),
  node:process.version,v8:process.versions.v8,independent_validation:'One Node/V8 validation; no instantiation or execution',
  query,matching_indices:report.matches.map(m=>m.index),local_function_count:report.local_function_count,named_count:report.named_count,
  unnamed_count:report.unnamed_count,match_count:report.match_count,unmatched_named_count:report.unmatched_named_count,
  matched_body_bytes:report.matched_body_bytes,matched_prefix_bytes:report.matched_prefix_bytes,matched_encoded_bytes:report.matched_encoded_bytes,records},null,2)+'\n',{flag:'wx'});
console.log('Function-search CLI regressions passed (4 process cases, 1 V8 validation). Evidence: '+dir);
