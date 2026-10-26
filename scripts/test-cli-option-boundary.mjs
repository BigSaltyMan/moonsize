// Exactly four CLI calls. Fixed eight-byte modules; no V8 checks or source probe.
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import {spawnSync} from 'node:child_process';

const cli=path.resolve(process.argv[2]||'_build/native/release/build/cmd/main/main.exe');
assert(fs.existsSync(cli),'Build the native CLI first.');
const parent=path.resolve('_build/cli-option-boundary-verification');fs.mkdirSync(parent,{recursive:true});
const dir=fs.mkdtempSync(path.join(parent,'run-')),cwd=path.join(dir,'inputs');fs.mkdirSync(cwd);
const bytes=Buffer.from('0061736d01000000','hex');
const sha=b=>crypto.createHash('sha256').update(b).digest('hex');
const inputs=[];
function input(name){fs.writeFileSync(path.join(cwd,name),bytes,{flag:'wx'});inputs.push(name);}
input('--help');
const records=[];
function run(args,status){
  const p=spawnSync(cli,args,{cwd,encoding:'utf8',timeout:10000});
  const text=(p.stdout||'')+(p.stderr||'');
  fs.writeFileSync(path.join(dir,'case-'+records.length+'.log'),text,{flag:'wx'});
  records.push({args,status:p.status,error:p.error?.message??null});
  fs.writeFileSync(path.join(dir,'processes.json'),JSON.stringify(records,null,2)+'\n');
  assert.ifError(p.error);assert.equal(p.signal,null);assert.equal(p.status,status,text);
  for(const name of inputs)assert.deepEqual(fs.readFileSync(path.join(cwd,name)),bytes,'Input changed: '+name);
  return text;
}
const unknown=run(['--summry-json'],2);
assert(unknown.startsWith('moonsize: unknown option --summry-json;'));
assert(unknown.includes('--help'));assert(!unknown.includes('moonsize: cannot read'));
const normal=run(['--top','1','--summary-json','new-summary.json','--','--help'],0);
assert(normal.includes('Analysis summary written to new-summary.json'));
assert(!normal.includes('usage: moonsize'));assert(!normal.includes('Help (no input file)'));
const output=path.join(cwd,'new-summary.json'),saved=fs.readFileSync(output),r=JSON.parse(saved);
assert.equal(r.format,'moonsize-summary');assert.equal(r.schema_version,1);
assert.deepEqual(r.input,{file_size:8,sha256:sha(bytes),wasm_version:1});
const refused=run(['--summary-json','should-not-exist.json','--','--help','--top','1'],2);
assert(refused.startsWith('moonsize: unexpected argument --top'));
assert(!refused.includes('moonsize: cannot read'));
assert(!refused.includes('Analysis summary written to '));
assert(!fs.existsSync(path.join(cwd,'should-not-exist.json')));
input('-before.wasm');input('-after.wasm');
const comparison=run(['--baseline','-before.wasm','--','-after.wasm'],0);
assert(comparison.includes('SIZE COMPARISON'));
const total=comparison.match(/^\s*total\s+(\d+)\s+(\d+)\s+([+-]?\d+)/m);
assert(total,'Missing baseline/current comparison total.');
assert.equal(Number(total[1]),8);assert.equal(Number(total[2]),8);assert.equal(Number(total[3]),0);
assert(!comparison.includes('usage: moonsize'));assert(!comparison.includes('Help (no input file)'));
assert.deepEqual(fs.readFileSync(output),saved);
fs.writeFileSync(path.join(dir,'results.json'),JSON.stringify({cwd,fixture_hex:bytes.toString('hex'),
  input_sha256:sha(bytes),inputs,records,summary_input:r.input,
  comparison:{baseline_bytes:Number(total[1]),current_bytes:Number(total[2]),delta:Number(total[3])},
  refused_output_absent:!fs.existsSync(path.join(cwd,'should-not-exist.json')),
  scope:'Argument routing only; fixed empty modules, no V8/probe/browser or legacy regression runs'},null,2)+'\n',{flag:'wx'});
console.log('CLI option-boundary regressions passed (4 process cases). Evidence: '+dir);
