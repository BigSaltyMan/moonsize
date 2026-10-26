// Exactly four CLI calls, no Wasm, V8 validation, analysis or report generation.
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';

const cli=path.resolve(process.argv[2]||'_build/native/release/build/cmd/main/main.exe');
assert(fs.existsSync(cli),'Build the native CLI first.');
const parent=path.resolve('_build/help-topics-verification');fs.mkdirSync(parent,{recursive:true});
const dir=fs.mkdtempSync(path.join(parent,'run-')),cwd=path.join(dir,'empty-cwd');fs.mkdirSync(cwd);
const topics=['overview','functions','data','interfaces','metadata','baseline','ci'];
const records=[];
function run(args,status){
  assert.deepEqual(fs.readdirSync(cwd),[],'Help working directory must remain empty.');
  const p=spawnSync(cli,args,{cwd,encoding:'utf8',timeout:10000});
  const text=(p.stdout||'')+(p.stderr||'');
  fs.writeFileSync(path.join(dir,'case-'+records.length+'.log'),text,{flag:'wx'});
  records.push({args,status:p.status,error:p.error?.message??null});
  fs.writeFileSync(path.join(dir,'processes.json'),JSON.stringify(records,null,2)+'\n');
  assert.ifError(p.error);assert.equal(p.signal,null);assert.equal(p.status,status,text);
  assert.deepEqual(fs.readdirSync(cwd),[],'Help created an unexpected file.');
  assert(!/cannot read|bad magic|unexpected end|not a WebAssembly/i.test(text),'Help attempted input parsing.');
  return text;
}
const full=run(['--help'],0);
assert(full.startsWith('usage: moonsize <file.wasm>'));
for(const token of ['--retained','--summary-json','--baseline-instructions','--diff-exports','--why-json','All report outputs refuse existing','Exit codes: 0 completed','Help (no input file)','--help-topic <topic>'])assert(full.includes(token),token);
for(const topic of topics)assert(full.includes('  '+topic+'  '));
const functions=run(['--help-topic','functions'],0);
assert(functions.startsWith('functions: Find and explain functions'));
for(const flag of ['--find-functions','--instructions','--instructions-json','--callers','--why-index','--entrypoints'])assert(functions.includes(flag),flag);
assert(functions.includes('placeholders'));assert(functions.includes('not execution traces'));
const unknown=run(['--help-topic','nonexistent'],2);
assert(unknown.includes('unknown help topic "nonexistent"'));
assert(unknown.includes('Available topics'));
for(const topic of topics)assert(unknown.includes('  '+topic+'  '));
const extra=run(['--help-topic','ci','--summary-json','should-not-exist.json'],2);
assert(extra.includes('exactly one topic'));assert(extra.includes('--help-topic <topic>'));
assert(!fs.existsSync(path.join(cwd,'should-not-exist.json')));
fs.writeFileSync(path.join(dir,'results.json'),JSON.stringify({cwd,topics,records,
  cwd_empty_after_all_calls:fs.readdirSync(cwd).length===0,
  scope:'Help only; no Wasm input, V8 checks, analyzer execution or output reports'},null,2)+'\n',{flag:'wx'});
console.log('Help-topic regressions passed (4 process cases; no input/output files). Evidence: '+dir);
