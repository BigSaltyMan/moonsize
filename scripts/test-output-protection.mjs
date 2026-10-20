// Real process tests. Every attempted overwrite is confined to fresh temp data.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import {spawn, spawnSync} from 'node:child_process';

const cli = path.resolve(process.argv[2] || '_build/native/release/build/cmd/main/main.exe');
assert(fs.existsSync(cli), 'Build the native CLI first.');
const work = fs.mkdtempSync(path.join(os.tmpdir(), 'moonsize-output-'));
const fixture = Buffer.from('0061736d0100000001040160000003030200000707010372756e00000a0902040012010b02000b', 'hex');
const gap = Buffer.from('0061736d01000000010401600000030201000404017000010a0901070041001300000b', 'hex');
assert(WebAssembly.validate(fixture)); assert(WebAssembly.validate(gap));
const protectedFiles = new Set();
const hash = b => crypto.createHash('sha256').update(b).digest('hex');
const save = (file, data) => { fs.writeFileSync(file, data); protectedFiles.add(file); return file; };
const snapshots = () => new Map([...protectedFiles].map(file => [file, hash(fs.readFileSync(file))]));
const unchanged = before => { for (const [file, digest] of before) assert.equal(hash(fs.readFileSync(file)), digest, 'changed protected file: '+file); };
let cases = 0;
const skips = [];
const noSuccess = text => assert(!/written to|SIZE BUDGET|^SECTION\s|^Top \d/m.test(text), 'unexpected normal/success output: '+text);
function run(args, status, cwd=work, reason=null) {
  const before = snapshots();
  const r = spawnSync(cli, args, {cwd, encoding:'utf8', timeout:20000, maxBuffer:4*1024*1024});
  unchanged(before);
  assert.ifError(r.error); assert.equal(r.signal, null);
  assert.equal(r.status, status, JSON.stringify(args)+'\n'+r.stdout+r.stderr);
  cases++;
  const text = r.stdout+r.stderr;
  if (reason) { assert.match(text, reason); noSuccess(text); }
  return text;
}
const refusal = /output already exists:|cannot safely write output:/;
const modes = [
  ['html','--html','.html'], ['dot','--call-graph','.dot'], ['graph-json','--call-graph','.json'],
  ['experiment-html','--experiment','.html'], ['experiment-json','--experiment','.json'],
  ['path','--why-json','.json'], ['budget-json','--budget-json','.json'], ['budget-md','--budget-md','.md'],
];
try {
  for (const [name, flag, ext] of modes) {
    const dir = path.join(work, name+' 空格'); fs.mkdirSync(dir);
    const current = save(path.join(dir,'current'+ext), fixture);
    const baseline = save(path.join(dir,'baseline'+ext), fixture);
    const dynamic = save(path.join(dir,'gap.wasm'), gap);
    const malformed = save(path.join(dir,'bad.wasm'), 'not wasm');
    const config = save(path.join(dir,'config'+ext), '{"version":1,"rules":[{"id":"raw","metric":"file.raw","mode":"absolute","max_bytes":100000}]}');
    const context = save(path.join(dir,'context'+ext), 'null');
    const args = (target, input=current, extra=[]) => [input,
      ...(name.startsWith('experiment') ? ['--baseline',baseline,'--experiment-context',context] :
        name==='path' ? ['--why-index',input===dynamic?'0':'1'] :
        name.startsWith('budget') ? ['--budget',config,'--baseline',baseline] : ['--baseline',baseline]),
      flag,target,...extra];
    // Successful reports keep their old data contract; every destination is new.
    const fresh = path.join(dir,'new'+ext); run(args(fresh),0);
    const data = fs.readFileSync(fresh,'utf8'); assert(data.length>0);
    if (ext==='.json') assert.equal(JSON.parse(data).schema_version,1);
    if (ext==='.html') assert.match(data, /<html|<!doctype/i);
    protectedFiles.add(fresh);
    for (const target of [current,baseline,fresh,path.relative(dir,current),path.join(dir,'sub','..','current'+ext)]) {
      fs.mkdirSync(path.join(dir,'sub'),{recursive:true});
      run(args(target),1,dir,refusal);
    }
    // Existing config/context aliases receive the same protection as inputs.
    run(args(config),1,dir,refusal); run(args(context),1,dir,refusal);
    const hard = path.join(dir,'hard'+ext); fs.linkSync(current,hard);
    run(args(hard),1,dir,refusal); assert(fs.readFileSync(hard).equals(fixture));
    const directory = path.join(dir,'directory'+ext); fs.mkdirSync(directory);
    save(path.join(directory,'KEEP'),'directory contents');
    run(args(directory),1,dir,refusal); assert(fs.statSync(directory).isDirectory());
    run(args(path.join(dir,'missing','new'+ext)),1,dir,refusal);
    run(args(path.join(current,'new'+ext)),1,dir,refusal);
    const readonly = save(path.join(dir,'readonly'+ext),'READ ONLY'); fs.chmodSync(readonly,0o444);
    try { run(args(readonly),1,dir,refusal); } finally { fs.chmodSync(readonly,0o644); }
    // Strict wins over existing-output refusal and never creates a fresh report.
    for (const target of [path.join(dir,'strict-new'+ext),fresh]) {
      run(args(target,dynamic,['--strict']),3,dir,/incomplete/);
      if (target!==fresh) assert(!fs.existsSync(target));
    }
    const badOutput = path.join(dir,'bad-output'+ext);
    run(args(badOutput,malformed),1,dir,/magic|module|end|version/i); assert(!fs.existsSync(badOutput));
    try {
      const link = path.join(dir,'symlink'+ext); fs.symlinkSync(current,link,'file');
      run(args(link),1,dir,refusal); assert(fs.lstatSync(link).isSymbolicLink());
      const absent = path.join(dir,'never-created'+ext), dangling=path.join(dir,'dangling'+ext);
      fs.symlinkSync(absent,dangling,'file');
      run(args(dangling),1,dir,refusal); assert(fs.lstatSync(dangling).isSymbolicLink()); assert(!fs.existsSync(absent));
      const parent = path.join(dir,'parent-link'); fs.symlinkSync(dir,parent,'dir');
      run(args(path.join(parent,'current'+ext)),1,dir,refusal);
    } catch (error) {
      if (!['EPERM','EACCES','ENOSYS','ENOTSUP'].includes(error.code)) throw error;
      skips.push(name+': symbolic links unavailable: '+error.code);
    }
    if (process.platform==='win32') {
      run(args(path.join(dir,'CURRENT'+ext)),1,dir,refusal);
      // ADS and device destinations must never count as ordinary report files.
      if (name==='html') {
        run(args(current+':report'),1,dir,refusal);
        run(args('NUL'),1,dir,refusal);
      }
    }
  }
  const current = save(path.join(work,'current.wasm'),fixture);
  const baseline = save(path.join(work,'baseline.wasm'),fixture);
  const config = save(path.join(work,'budget.json'),'{"version":1,"rules":[{"id":"raw","metric":"file.raw","mode":"absolute","max_bytes":0}]}');
  const budgetArgs = (a,b) => [current,'--baseline',baseline,'--budget',config,'--budget-json',a,'--budget-md',b];
  const first=path.join(work,'first.json'), second=save(path.join(work,'second.md'),'KEEP');
  run(budgetArgs(first,second),1,work,refusal); assert(!fs.existsSync(first));
  const secondDir=path.join(work,'directory.md');fs.mkdirSync(secondDir);
  run(budgetArgs(first,secondDir),1,work,refusal);assert(!fs.existsSync(first));
  for(const [name,source] of [['input',current],['baseline',baseline],['config',config]]) {
    const alias=path.join(work,'second-'+name+'.md');fs.linkSync(source,alias);
    run(budgetArgs(first,alias),1,work,refusal);assert(!fs.existsSync(first));
    assert(fs.readFileSync(alias).equals(fs.readFileSync(source)));
  }
  const freshMd=path.join(work,'new.md');run(budgetArgs(first,freshMd),3);
  assert.equal(JSON.parse(fs.readFileSync(first)).status,'exceeded');assert(fs.readFileSync(freshMd,'utf8').includes('exceeded'));
  // A late failure may preserve the first newly created artifact; never claim a transaction.
  const partial=path.join(work,'partial.json');
  run(budgetArgs(partial,path.join(work,'absent','late.md')),1,work,refusal);
  assert.equal(JSON.parse(fs.readFileSync(partial)).status,'exceeded');
  // A real permission-denied parent (isolated directory only), not an overwrite test.
  const locked=path.join(work,'locked');fs.mkdirSync(locked);
  const target=path.join(locked,'new.json');
  if (process.platform==='win32') {
    const user=os.userInfo().username;
    const deny=spawnSync('icacls',[locked,'/deny',user+':(OI)(CI)(W)'],{encoding:'utf8'});
    if (deny.status!==0) skips.push('permission-denied parent: icacls unavailable: '+deny.status);
    else try {run([current,'--call-graph',target],1,work,refusal);assert(!fs.existsSync(target));}
    finally {const restore=spawnSync('icacls',[locked,'/remove:d',user],{encoding:'utf8'});assert.equal(restore.status,0,'restore isolated ACL');}
  } else if (process.getuid?.()===0) skips.push('permission-denied parent: root bypasses mode bits');
  else {fs.chmodSync(locked,0o555);try{run([current,'--call-graph',target],1,work,refusal);assert(!fs.existsSync(target));}finally{fs.chmodSync(locked,0o755);}}
  // Competing real CLI processes may create exactly one report, never overwrite it.
  const contested=path.join(work,'contested.json'), before=snapshots();
  const results=await Promise.all(Array.from({length:12},()=>new Promise((resolve,reject)=>{
    const p=spawn(cli,[current,'--call-graph',contested],{cwd:work});let text='';
    const timer=setTimeout(()=>{p.kill();reject(Error('race CLI timeout'));},20000);
    p.stdout.on('data',b=>text+=b);p.stderr.on('data',b=>text+=b);p.on('error',reject);
    p.on('close',(code,signal)=>{clearTimeout(timer);assert.equal(signal,null);resolve({code,text});});
  })));
  unchanged(before);cases+=results.length;
  assert.equal(results.filter(r=>r.code===0).length,1);
  for(const r of results.filter(r=>r.code!==0)){assert.equal(r.code,1);assert.match(r.text,refusal);noSuccess(r.text);}
  assert.equal(JSON.parse(fs.readFileSync(contested)).schema_version,1);
  for(const skip of skips)console.log('SKIP: '+skip);
  if(process.platform==='linux') assert(!skips.some(s=>s.includes('symbolic links')), 'Linux must exercise symlink protection');
  console.log(`Output-protection CLI regressions passed (${cases} process cases; ${skips.length} capability skips reported).`);
} finally {
  assert.equal(path.dirname(work),os.tmpdir()); assert(path.basename(work).startsWith('moonsize-output-'));
  fs.rmSync(work,{recursive:true,force:true});
}
