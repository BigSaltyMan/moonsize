// Exactly four analyzer calls. Reuse the fixed function-instructions fixture;
// no probe build, old CLI execution or repeated V8 validation.
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import {spawnSync} from 'node:child_process';

const cli=path.resolve(process.argv[2]||'_build/native/release/build/cmd/main/main.exe');
assert(fs.existsSync(cli),'Build the native CLI first.');
const parent=path.resolve('_build/file-offset-decode-verification');fs.mkdirSync(parent,{recursive:true});
const dir=fs.mkdtempSync(path.join(parent,'run-'));
const cat=(...items)=>Buffer.concat(items.map(item=>Buffer.from(item)));
const section=(id,payload)=>{assert(payload.length<128);return cat([id,payload.length],payload);};
const sha=b=>crypto.createHash('sha256').update(b).digest('hex');
const body=Buffer.from('01027f0240034041001a4180011a4300000000fc001a4300000000fc011a0b0b0b','hex');
const name=Buffer.from('target"<&');
const input=cat(Buffer.from('0061736d01000000010401600000020701016d016600000303020000','hex'),
  section(10,cat([2,body.length|128,0],body,[2,0,11])),
  section(0,cat([4],Buffer.from('name'),section(1,cat([1,1,name.length],name)))));
assert.equal(body.length,33);assert.equal(input.length,90);
assert.deepEqual(input.subarray(33,36),Buffer.from([1,2,127]));
assert.deepEqual(input.subarray(43,46),Buffer.from([0x41,0x80,1]));
const bad=Buffer.from(input);bad[47]=255; // Deliberately invalid opcode, lengths unchanged.
fs.writeFileSync(path.join(dir,'input.wasm'),input,{flag:'wx'});
fs.writeFileSync(path.join(dir,'bad-target.wasm'),bad,{flag:'wx'});
const sentinel=Buffer.from('preserve decoded evidence\n'),target=path.join(dir,'existing.json');fs.writeFileSync(target,sentinel,{flag:'wx'});
const records=[];
function run(args,status){
  const p=spawnSync(cli,args,{cwd:dir,encoding:'utf8',timeout:10000});
  const text=(p.stdout||'')+(p.stderr||'');
  fs.writeFileSync(path.join(dir,'case-'+records.length+'.log'),text,{flag:'wx'});
  records.push({argv:[cli,...args],status:p.status,error:p.error?.message??null});
  fs.writeFileSync(path.join(dir,'processes.json'),JSON.stringify(records,null,2)+'\n');
  assert.ifError(p.error);assert.equal(p.signal,null);assert.equal(p.status,status,text);
  assert.equal(sha(fs.readFileSync(path.join(dir,'input.wasm'))),sha(input));
  assert.equal(sha(fs.readFileSync(path.join(dir,'bad-target.wasm'))),sha(bad));assert.deepEqual(fs.readFileSync(target),sentinel);
  return text;
}
const text=run(['input.wasm','--locate-offset','45','--locate-decode'],0);
assert(text.includes('Function index: 1; name: "target\\\"<&"'));
assert(text.includes('Region: function_body'));assert(text.includes('Region file range: offset 33, size 33 bytes'));
assert(text.includes('DECODED FUNCTION LOCATION'));assert(text.includes('Status: decoded'));assert(text.includes('Detail: instruction'));
assert(text.includes('Instruction ordinal: 4; mnemonic: "i32.const"'));
assert(text.includes('Detail file range: offset 43, size 3 bytes'));assert(text.includes('Detail relative offset: 2 bytes'));
assert(text.includes('Body-relative offset: 10 bytes'));assert(!text.includes('byte_role'));
const saved=run(['input.wasm','--locate-offset','34','--locate-decode','--locate-offset-json','new-detail.json'],0);
assert(saved.includes('File offset location written to new-detail.json'));assert(!saved.includes('WASM FILE OFFSET LOCATION'));
const report=JSON.parse(fs.readFileSync(path.join(dir,'new-detail.json')));
assert.equal(report.format,'moonsize-file-offset-decoded');assert.equal(report.schema_version,1);assert.equal(report.decode_status,'decoded');
const base=report.location;assert.equal(typeof base,'object');assert.equal(base.format,'moonsize-file-offset');assert.equal(base.schema_version,1);
assert.equal(base.file_size,input.length);assert.equal(base.sha256,sha(input));assert.equal(base.offset,34);
assert.equal(base.function.index,1);assert.equal(base.function.raw_name,'target"<&');
assert.deepEqual(base.function.encoding,{file_offset:31,size:35});assert.deepEqual(base.function.size_prefix,{file_offset:31,size:2});
assert.deepEqual(base.region,{kind:'function_body',file_offset:33,size:33,relative_offset:1});
assert.deepEqual(report.detail,{kind:'locals_encoding',file_offset:33,size:3,relative_offset:1,instruction:null});
assert.equal(base.region.size,3+30);assert.equal(base.offset,report.detail.file_offset+report.detail.relative_offset);
assert.equal(input[base.offset],2); // locals count inside fixed 01 02 7f encoding
assert(!('byte_role'in report.detail));assert(!('instructions'in report));
const failed=run(['bad-target.wasm','--locate-offset','34','--locate-decode','--locate-offset-json','must-not-exist.json'],1);
assert(failed.toLowerCase().includes('unknown opcode'));assert(!failed.includes('written to'));
assert(!failed.includes('WASM FILE OFFSET LOCATION'));assert(!fs.existsSync(path.join(dir,'must-not-exist.json')));
const refused=run(['input.wasm','--locate-offset','45','--locate-decode','--locate-offset-json','existing.json'],1);
assert(refused.includes('output already exists'));assert(!refused.includes('written to'));
fs.writeFileSync(path.join(dir,'results.json'),JSON.stringify({input_size:input.length,input_sha256:sha(input),bad_target_sha256:sha(bad),
  bad_target:{invalid:true,changed_file_offset:47,replacement:255,outer_lengths_unchanged:true},
  instruction_location:{query:45,function_index:1,file_offset:43,size:3,relative_offset:2,body_relative_offset:10,ordinal:4,mnemonic:'i32.const',fixture_hex:input.subarray(43,46).toString('hex')},
  locals_location:{query:34,function_index:1,...report.detail,fixture_hex:input.subarray(33,36).toString('hex')},body_ledger:{body:33,locals:3,instructions:30},
  records,input_and_existing_output_unchanged:true,decode_failure_output_absent:true,
  scope:'Three new unit tests and four new CLI calls; reused fixed fixture without old suites, probes, V8 matrix, performance or browser/PDF checks'},null,2)+'\n',{flag:'wx'});
console.log('File-offset-decode regressions passed (4 process cases). Evidence: '+dir);
