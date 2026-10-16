// Build real source artifacts, budget measured values, and prove exact rollback.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import assert from 'node:assert/strict';
const repo=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const cli=path.resolve(process.argv[2]||'_build/native/release/build/cmd/main/main.exe');
const out=path.join(repo,'_build/budget-demo');fs.mkdirSync(out,{recursive:true});
fs.writeFileSync(path.join(out,'run.log'),'Real source budget evidence\n');
const hash=b=>crypto.createHash('sha256').update(b).digest('hex');
function run(command,args,cwd=repo,status=0) {
  const r=spawnSync(command,args,{cwd,encoding:'utf8',timeout:60000,maxBuffer:16*1024*1024});
  fs.appendFileSync(path.join(out,'run.log'),JSON.stringify({command,args,cwd,status:r.status,stdout:r.stdout,stderr:r.stderr})+'\n');
  assert(!r.error&&!r.signal,`${r.error||r.signal}`);assert.equal(r.status,status,`${command} ${args.join(' ')}\n${r.stdout}\n${r.stderr}`);
  return r.stdout;
}
function fresh(name) {
  const file=path.join(out,name);assert.equal(path.dirname(file),out);
  if(fs.existsSync(file))fs.unlinkSync(file);return file;
}
const before=`///|
#inline(never)
fn budget_value(n : Int) -> String { "base: " + n.to_string() }

///|
fn main { for n in 0..<4 { println(budget_value(n)) } }
`;
const after=`///|
#inline(never)
fn budget_value(n : Int) -> String { "base: " + n.to_string() }

///|
#inline(never)
fn budget_feature(n : Int) -> String {
  if n % 2 == 0 { "optional report: even values now include a detailed explanation" }
  else { "optional report: odd values now include another detailed explanation" }
}

///|
fn main { for n in 0..<4 { println(budget_value(n)); println(budget_feature(n)) } }
`;
fs.writeFileSync(path.join(out,'moon.mod'),'name = "demo/budgetdemo"\n');
fs.writeFileSync(path.join(out,'moon.pkg'),'pkgtype(kind: "executable")\n');
const toolchain=run('moon',['version','--all']).trim();
const artifacts={};
for(const variant of ['before','after','rollback']) {
  const source=variant==='after'?after:before;
  fs.writeFileSync(path.join(out,'main.mbt'),source);fs.writeFileSync(path.join(out,variant+'.source.txt'),source);
  run('moon',['build','--target','wasm','--debug','--no-strip'],out);
  const built=path.join(out,'_build/wasm/debug/build/budgetdemo.wasm');assert(fs.statSync(built).size>0);
  const file=path.join(out,variant+'.wasm');fs.copyFileSync(built,file);
  const bytes=fs.readFileSync(file);assert(WebAssembly.validate(bytes));
  const stdout=run('moonrun',[file]);fs.writeFileSync(path.join(out,variant+'.stdout.txt'),stdout);
  artifacts[variant]={path:file,sha256:hash(bytes),bytes:bytes.length,source_sha256:hash(source),stdout};
}
assert.equal(artifacts.before.sha256,artifacts.rollback.sha256);assert.equal(artifacts.before.stdout,artifacts.rollback.stdout);
assert.equal(artifacts.before.stdout,artifacts.after.stdout.split(/(?<=\n)/).filter(s=>s.startsWith('base: ')).join(''));
const metrics=['file.raw','file.gzip','code.raw','package.raw'];
const rule=(metric,mode,max_bytes)=>({id:metric,metric,mode,max_bytes,...(metric==='package.raw'?{package:'demo::budgetdemo'}:{})});
function configuration(name,rules) {
  const file=path.join(out,name+'.config.json');fs.writeFileSync(file,JSON.stringify({version:1,rules},null,2)+'\n');return file;
}
function budget(name,variant,cfg,baseline=null,status=0) {
  const json=fresh(name+'.json'),md=fresh(name+'.md');
  const stdout=run(cli,[artifacts[variant].path,'--budget',cfg,'--budget-json',json,'--budget-md',md,...(baseline?['--baseline',artifacts[baseline].path]:[])],repo,status);
  fs.writeFileSync(path.join(out,name+'.txt'),stdout);
  const result=JSON.parse(fs.readFileSync(json));assert.equal(result.exit_code,status);assert.equal(result.current.sha256,artifacts[variant].sha256);
  if(result.baseline)assert.equal(result.baseline.sha256,artifacts[baseline].sha256);
  assert(result.rules.every(r=>r.status!=='unavailable'));return result;
}
const probe=configuration('probe',metrics.map(m=>rule(m,'absolute',2147483647)));
const b=budget('before-measured','before',probe),a=budget('after-measured','after',probe);
assert.equal(a.current.attribution.unattributed_functions,0);
const deltas=metrics.map((m,i)=>a.rules[i].current-b.rules[i].current);
assert(deltas[0]>0&&deltas[2]>0&&deltas[3]>0,'The added feature must grow file, code and attributed functions');
const passing=configuration('passing',metrics.map((m,i)=>rule(m,'growth',Math.max(0,deltas[i]))));
const passed=budget('passed','after',passing,'before',0);
assert.deepEqual(passed.rules.map(r=>r.delta),deltas);
const failing=configuration('exceeded',metrics.map((m,i)=>rule(m,'growth',Math.max(0,deltas[i]-1))));
const refused=budget('exceeded','after',failing,'before',3);
assert(refused.rules.some(r=>r.id==='file.raw'&&r.status==='exceeded'&&r.reason.includes('exceeds max_bytes')));
for(let i=0;i<metrics.length;i++)assert.equal(refused.rules[i].status,deltas[i]>0?'exceeded':'passed');
const self=budget('before-self','before',passing,'before'),rollback=budget('rollback','rollback',passing,'before');
assert.deepEqual(rollback.rules,self.rules);assert.equal(rollback.current.sha256,self.current.sha256);
const sample=budget('example-config','after',path.join(repo,'examples/budget.json'),'before');assert.equal(sample.status,'passed');
// A missing input is an error, never a successful budget-refusal demonstration.
run(cli,[path.join(out,'absent.wasm'),'--budget',probe],repo,1);
const results={toolchain,build:{command:'moon build --target wasm --debug --no-strip',target:'wasm',mode:'debug',strip:false},
  cli_sha256:hash(fs.readFileSync(cli)),artifacts,deltas:Object.fromEntries(metrics.map((m,i)=>[m,deltas[i]])),
  positive_exit:passed.exit_code,negative_exit:refused.exit_code,rollback_exact:true,
  interpretation:'Optional output is intentionally added. Base output is preserved; not full behavioral equivalence. Budgets measure complete artifacts and symbol-attributed function bytes, never hypothetical deletion savings.'};
fs.writeFileSync(path.join(out,'results.json'),JSON.stringify(results,null,2)+'\n');
console.log('Budget source demo passed: '+JSON.stringify(results.deltas)+'; exits 0/3; exact rollback.');
console.log('Evidence: '+out);
