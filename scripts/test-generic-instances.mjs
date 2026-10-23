// One real probe build + one V8 validation, then exactly four analyzer calls.
// Optional third argument reuses probe.json from a previously built probe.
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import {spawnSync} from 'node:child_process';

const cli = path.resolve(process.argv[2] || '_build/native/release/build/cmd/main/main.exe');
assert(fs.existsSync(cli), 'Build the native CLI first.');
const sha = b => crypto.createHash('sha256').update(b).digest('hex');
const parent = path.resolve('_build/generic-instances-verification');
fs.mkdirSync(parent, {recursive:true});
const dir = fs.mkdtempSync(path.join(parent, 'run-'));
const source = `#inline(never)
fn[T] generic_keep(value : T) -> T { value }
struct Holder[T] { value : T }
#inline(never)
fn[T] Holder::get(self : Holder[T]) -> T { self.value }
fn main {
  println(generic_keep(7))
  println(generic_keep(2.5))
  let first : Holder[Int] = { value: 11 }
  let second : Holder[Double] = { value: 3.5 }
  println(first.get())
  println(second.get())
}
`;
let evidence;
if (process.argv[3]) {
  evidence = JSON.parse(fs.readFileSync(path.resolve(process.argv[3]), 'utf8'));
  assert.equal(fs.readFileSync(path.join(evidence.probe, 'main.mbt'), 'utf8'), source);
  assert.equal(evidence.independent_validation, 'Node/V8 WebAssembly.validate: passed');
  assert.equal(sha(fs.readFileSync(evidence.artifact)), evidence.sha256);
} else {
  const probe = path.join(dir, 'probe');
  fs.mkdirSync(probe);
  fs.writeFileSync(path.join(probe, 'moon.mod'), 'name = "probe/generics"\nversion = "0.0.0"\n');
  fs.writeFileSync(path.join(probe, 'moon.pkg'), 'pkgtype(kind: "executable")\n');
  fs.writeFileSync(path.join(probe, 'main.mbt'), source);
  const version = spawnSync('moon', ['version', '--all'], {encoding:'utf8', timeout:10000});
  assert.ifError(version.error); assert.equal(version.status, 0);
  const command = ['moon', 'build', '--target', 'wasm', '--debug', '--no-strip'];
  const built = spawnSync(command[0], command.slice(1), {cwd:probe, encoding:'utf8', timeout:120000});
  fs.writeFileSync(path.join(dir, 'build.log'), (built.stdout||'')+(built.stderr||''), {flag:'wx'});
  assert.ifError(built.error); assert.equal(built.status, 0, built.stdout+built.stderr);
  const artifact = path.join(probe, '_build/wasm/debug/build/generics.wasm');
  const data = fs.readFileSync(artifact);
  assert(WebAssembly.validate(data), 'V8 rejected the real probe.'); // Exactly once.
  const names = [];
  for (const array of WebAssembly.Module.customSections(new WebAssembly.Module(data), 'name')) {
    const b = Buffer.from(array); let p = 0;
    const u = () => { let n=0,s=0; for(let i=0;i<5;i++) {
      assert(p<b.length); const v=b[p++]; n+=(v&127)*2**s;
      if(!(v&128)) return n; s+=7;
    } throw Error('invalid probe name LEB'); };
    while(p<b.length) {
      const id=b[p++], length=u(), end=p+length; assert(end<=b.length);
      if(id===1) { const count=u(); for(let j=0;j<count;j++) {
        const index=u(), size=u(); assert(p+size<=end);
        names.push({index, raw:b.subarray(p,p+size).toString('utf8')}); p+=size;
      } }
      p=end;
    }
  }
  evidence = {probe, artifact, command, toolchain:version.stdout+version.stderr,
    sha256:sha(data), size:data.length, names,
    independent_validation:'Node/V8 WebAssembly.validate: passed'};
}
fs.writeFileSync(path.join(dir, 'probe.json'), JSON.stringify(evidence,null,2)+'\n', {flag:'wx'});
const records = [];
function run(input, args, status) {
  const before=fs.readFileSync(input);
  const p=spawnSync(cli,[input,...args], {cwd:dir, encoding:'utf8', timeout:30000});
  const log=(p.stdout||'')+(p.stderr||'');
  fs.writeFileSync(path.join(dir,'case-'+records.length+'.log'),log,{flag:'wx'});
  records.push({input, args, status:p.status, error:p.error?.message||null});
  assert.ifError(p.error); assert.equal(p.signal,null); assert.equal(p.status,status,log);
  assert.equal(sha(fs.readFileSync(input)),sha(before));
  return log;
}
const text=run(evidence.artifact,['--generics','--top','1'],0);
assert(text.includes('MOONBIT GENERIC INSTANCES'));
assert(text.includes('COVERAGE LEDGER'));
assert(text.includes('Showing 1 of '));
assert.equal((text.match(/Raw family key:/g)||[]).length,1);
const output=path.join(dir,'generics.json');
const confirmation=run(evidence.artifact,['--generics-json',output,'--top','1'],0);
assert(confirmation.includes('Generic instances written to '));
assert(!confirmation.includes('MOONBIT GENERIC INSTANCES'));
const saved=fs.readFileSync(output), report=JSON.parse(saved), c=report.coverage;
assert.equal(report.format,'moonsize-generic-instances'); assert.equal(report.schema_version,1);
assert.equal(report.file_size,evidence.size); assert.equal(report.sha256,evidence.sha256);
assert.equal(report.name_status,'available'); assert(!('graph_complete' in report));
assert.equal(c.total_functions,c.grouped_functions+c.named_ungrouped_functions+c.unnamed_functions);
assert.equal(c.total_size,c.grouped_size+c.named_ungrouped_size+c.unnamed_size);
assert.equal(c.grouped_size,report.families.reduce((n,f)=>n+f.total_size,0));
const expected=['_M0FP25probe8generics13generic__keep','_M0MP25probe8generics6Holder3get'];
for(const stem of expected) {
  const family=report.families.find(f=>f.family_key===stem); assert(family,'missing real family '+stem);
  assert.equal(family.definition_count,2); assert.equal(family.type_encoding_count,2);
  assert.deepEqual(family.instances.map(i=>i.raw_type_arguments).sort(),['GdE','GiE']);
  assert.deepEqual(family.instances.flatMap(i=>i.type_labels).sort(),['Double','Int']);
  for(const i of family.instances) assert(evidence.names.some(n=>n.index===i.index&&n.raw===i.raw_name));
  assert.equal(family.total_size,family.instances.reduce((n,i)=>n+i.total_size,0));
}
assert(report.families.length>=2,'Top must not truncate JSON');
// Existing minimal-module fixture from wasm_wbtest.mbt, not another probe.
const unnamed=path.join(dir,'unnamed.wasm');
fs.writeFileSync(unnamed,Buffer.from('0061736d01000000010401600000030201000a040102000b','hex'),{flag:'wx'});
const absent=run(unnamed,['--generics'],0);
assert(absent.includes('Name information: missing'));
assert(absent.includes('Without usable names: 1 / 3 B'));
assert(absent.includes('does not establish that the project has no generics'));
const refusal=run(evidence.artifact,['--generics-json',output],1);
assert(refusal.includes('output already exists')); assert(!refusal.includes('Generic instances written to'));
assert.deepEqual(fs.readFileSync(output),saved);
fs.writeFileSync(path.join(dir,'results.json'),JSON.stringify({
  cli_sha256:sha(fs.readFileSync(cli)), node:process.version, platform:os.platform(),
  probe_reused:Boolean(process.argv[3]), probe_sha256:evidence.sha256,
  coverage:c, families:report.families.map(f=>({key:f.family_key, definitions:f.definition_count,
    type_encodings:f.type_encoding_count, encoded_bytes:f.total_size})), records,
},null,2)+'\n',{flag:'wx'});
console.log('Generic-instance CLI regressions passed (4 process cases, 1 real probe). Evidence: '+dir);
