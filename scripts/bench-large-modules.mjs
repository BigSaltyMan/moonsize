// Reproducible CLI wall time, not an internal profiler. Node built-ins only.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import {spawn, spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';

const repo = fileURLToPath(new URL('../', import.meta.url));
const args = process.argv.slice(2), cliArg = args.shift();
let mode = 'default', timeoutMs = 30000, sourceSha = null;
try {
  assert(cliArg && !cliArg.startsWith('--'), 'native CLI path is required');
  while (args.length) {
    const arg = args.shift();
    if (arg === '--smoke' || arg === '--large') {
      assert.equal(mode, 'default', 'select one mode'); mode = arg.slice(2);
    } else if (arg === '--timeout-ms') {
      const value = args.shift(); assert(/^\d+$/.test(value ?? ''), 'timeout must be an integer');
      timeoutMs = Number(value); assert(timeoutMs >= 1 && timeoutMs <= 2147483647, 'invalid timeout');
    } else if (arg === '--cli-source-sha') {
      sourceSha = args.shift(); assert(/^[0-9a-f]{40}$/.test(sourceSha ?? ''), 'expected full source SHA');
    } else throw Error('unknown option: '+arg);
  }
} catch (error) {
  console.error('Usage: node scripts/bench-large-modules.mjs <native-cli> [--smoke|--large] [--timeout-ms N] [--cli-source-sha SHA]\n'+error.message);
  process.exit(2);
}
const cli = path.resolve(cliArg), parent = path.join(repo, '_build/large-module-benchmark');
fs.mkdirSync(parent, {recursive:true});
const dir = fs.mkdtempSync(path.join(parent, 'run-'));
fs.mkdirSync(path.join(dir, 'inputs')); fs.mkdirSync(path.join(dir, 'logs'));
const sha = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
const now = () => process.hrtime.bigint();
const elapsed = start => Number(now()-start)/1e6;
const commandInfo = (command, args) => {
  const r = spawnSync(command, args, {cwd:repo, encoding:'utf8', timeout:10000});
  return {command:[command,...args], status:r.status, error:r.error?.message ?? null, output:((r.stdout??'')+(r.stderr??'')).trim()};
};
const result = {
  schema_version:1, mode, started_at:new Date().toISOString(), status:'running',
  workspace:commandInfo('git',['rev-parse','HEAD']),
  cli:{path:cli, sha256:null, source_commit:sourceSha,
    source_evidence:sourceSha ? 'Caller-supplied --cli-source-sha; not inferred or independently verified by this script.' : 'Unknown binary source; workspace HEAD is not binary provenance.'},
  script_sha256:sha(fs.readFileSync(fileURLToPath(import.meta.url))),
  environment:{node:process.version, v8:process.versions.v8, platform:process.platform, arch:process.arch,
    os_release:os.release(), cpu:os.cpus()[0]?.model ?? 'unknown', logical_cpus:os.cpus().length,
    toolchain:commandInfo('moon',['version','--all'])},
  contract:{timeout_ms:timeoutMs, warmups:mode==='smoke'?0:1, measured_runs:mode==='smoke'?1:3,
    clock:'process.hrtime.bigint', output:'stdout and stderr redirected to the same new log file for every run',
    time_scope:'CLI startup, file reading, analysis and text output through process close; no internal stage timing or durable-disk flush measurement',
    peak_memory:'not measured', graph_counts:'Synthetic counts inspected from fixture bytecode/static table candidates, not analyzer graph exports; real-input call/edge counts are unmeasured.'},
  control_checks:[], samples:[], errors:[],
};
try { result.cli.sha256 = sha(fs.readFileSync(cli)); }
catch (e) { result.errors.push('CLI hash unavailable: '+e.message); }

// Keep raw runs even on failure. Aggregates exist only for complete successful groups.
function stats(runs, expected) {
  if (runs.length !== expected || runs.some(r=>r.status!=='ok')) return null;
  const values = runs.map(r=>r.elapsed_ms).sort((a,b)=>a-b), mid=Math.floor(values.length/2);
  return {min_ms:values[0], median_ms:values.length%2?values[mid]:(values[mid-1]+values[mid])/2, max_ms:values.at(-1)};
}
function save() {
  fs.writeFileSync(path.join(dir,'results.json'), JSON.stringify(result,null,2)+'\n');
  const lines = ['# Large-module CLI benchmark', '', `Mode: ${mode}; status: ${result.status}.`,
    `CLI SHA-256: ${result.cli.sha256 ?? 'unavailable'}. Source: ${sourceSha ?? 'unknown'} (caller declaration only).`,
    '', '| Sample / command | Status | Median ms | Min ms | Max ms |', '| --- | --- | ---: | ---: | ---: |'];
  for (const sample of result.samples) {
    if (!sample.measurements.length) lines.push(`| ${sample.id} | ${sample.status} | — | — | — |`);
    for (const group of sample.measurements) {
      const s=group.statistics;
      lines.push(`| ${sample.id} / ${group.variant} | ${group.status} | ${s?.median_ms.toFixed(3)??'—'} | ${s?.min_ms.toFixed(3)??'—'} | ${s?.max_ms.toFixed(3)??'—'} |`);
    }
  }
  lines.push('', 'Raw commands, elapsed milliseconds, generation/validation times, counts and exit states: [results.json](results.json).',
    'Inputs: inputs/. Individual CLI/control-process output: logs/. Failed/partial groups have no aggregate.',
    'Whole CLI time includes retained analysis in both variants; their difference is not dominator time.',
    'Peak memory is unmeasured. Synthetic shape and one small real artifact do not establish general scale capacity.',
    'Retained is not rebuilt savings; independent gzip is non-additive; benchmark success does not prove graph completeness.');
  for (const error of result.errors) lines.push('', 'Failure: '+error);
  fs.writeFileSync(path.join(dir,'summary.md'),lines.join('\n')+'\n');
}
async function run(command, argv, log, limit) {
  const fd = fs.openSync(path.join(dir,log),'wx'), start=now();
  return new Promise(resolve=>{
    let child, timer, timedOut=false, error=null, spawned=false;
    try { child=spawn(command,argv,{cwd:repo,stdio:['ignore',fd,fd]}); }
    catch (e) { fs.closeSync(fd); resolve({command:[command,...argv],cwd:repo,log,status:'spawn-failed',exit_code:null,signal:null,pid:null,elapsed_ms:null,error:e.message});return; }
    child.on('spawn',()=>{spawned=true;});
    child.on('error',e=>{error=e.message;});
    timer=setTimeout(()=>{timedOut=true; child.kill('SIGKILL');},limit);
    child.on('close',(code,signal)=>{
      clearTimeout(timer); const milliseconds=elapsed(start); fs.closeSync(fd);
      resolve({command:[command,...argv],cwd:repo,log,pid:child.pid??null,exit_code:code,signal,error,
        elapsed_ms:spawned?milliseconds:null,
        status:timedOut?'timeout':error?'spawn-failed':code!==0?'unexpected-exit':'ok'});
    });
  });
}

const cat = (...parts) => Buffer.concat(parts.map(p=>Buffer.from(p)));
const leb = value => { const out=[];do{let b=value&127;value=Math.floor(value/128);if(value)b|=128;out.push(b);}while(value);return out; };
const vector = values => cat(leb(values.length),...values);
const section = (id,payload) => cat([id],leb(payload.length),payload);
function generate(p) {
  assert(p.kind==='tree'||p.kind==='indirect');
  const n=p.kind==='tree'?p.functions:p.candidates+1;
  assert(n<=50000);
  if(p.kind==='indirect') assert(p.sites*p.candidates<=32768, 'bounded candidate expansion');
  const bodies=Array.from({length:n},(_,i)=>{
    const instructions=[];
    if(p.kind==='tree') {for(const to of [2*i+1,2*i+2])if(to<n)instructions.push(cat([0x10],leb(to)));}
    else if(i===0) {for(let k=0;k<p.sites;k++)instructions.push(Buffer.from([0x41,0,0x11,0,0]));}
    const body=cat([0],...instructions,[0x0b]);return cat(leb(body.length),body);
  });
  return cat([0,97,115,109,1,0,0,0], section(1,Buffer.from([1,0x60,0,0])),
    section(3,cat(leb(n),Buffer.alloc(n))),
    p.kind==='indirect'?section(4,cat([1,0x70,0],leb(p.candidates))):[],
    section(7,Buffer.from([1,3,114,117,110,0,0])),
    p.kind==='indirect'?section(9,cat([1,0,0x41,0,0x0b],leb(p.candidates),...Array.from({length:p.candidates},(_,i)=>leb(i+1)))):[],
    section(10,vector(bodies)));
}
// Limited independent inspector for our simple fixtures, not another Wasm analyzer.
class Reader {
  constructor(bytes){this.bytes=bytes;this.pos=0;}
  byte(){assert(this.pos<this.bytes.length,'truncated fixture');return this.bytes[this.pos++];}
  uint(){let n=0,m=1;for(let i=0;i<5;i++){const b=this.byte();n+=(b&127)*m;if(b<128)return n;m*=128;}throw Error('fixture LEB too long');}
  take(n){assert(n>=0&&n<=this.bytes.length-this.pos);const b=this.bytes.subarray(this.pos,this.pos+n);this.pos+=n;return b;}
}
function inspect(bytes, synthetic) {
  const r=new Reader(bytes);r.take(8);const sections=new Map();
  while(r.pos<bytes.length){const id=r.byte(),size=r.uint();if(id)sections.set(id,r.take(size));else r.take(size);}
  const code=new Reader(sections.get(10)??Buffer.from([0]));const local=code.uint();
  let imported=0;
  if(sections.has(2)) {
    const imp=new Reader(sections.get(2)),n=imp.uint();
    for(let i=0;i<n;i++){imp.take(imp.uint());imp.take(imp.uint());if(imp.byte()!==0){imported=null;break;}imp.uint();imported++;}
  }
  const counts={local_functions:local,imported_functions:imported,direct_call_sites:null,indirect_call_sites:null,
    table_candidates:null,expected_source_edge_records:null,fixture_unique_adjacencies:null,
    analyzer_unique_adjacencies:null};
  if(!synthetic)return counts;
  const candidates=[];
  if(sections.has(9)) {
    const e=new Reader(sections.get(9));assert.equal(e.uint(),1);assert.equal(e.uint(),0);
    assert.equal(e.byte(),0x41);assert.equal(e.uint(),0);assert.equal(e.byte(),0x0b);
    const n=e.uint();for(let i=0;i<n;i++)candidates.push(e.uint());assert.equal(e.pos,e.bytes.length);
  }
  let direct=0,indirect=0;const adjacency=new Set();
  for(let caller=0;caller<local;caller++) {
    const body=new Reader(code.take(code.uint()));assert.equal(body.uint(),0);
    while(body.pos<body.bytes.length) {
      const op=body.byte();
      if(op===0x10){direct++;adjacency.add(caller+':'+body.uint());}
      else if(op===0x11){assert.equal(body.uint(),0);assert.equal(body.uint(),0);indirect++;for(const target of candidates)adjacency.add(caller+':'+target);}
      else if(op===0x41)assert.equal(body.uint(),0);
      else {assert.equal(op,0x0b);assert.equal(body.pos,body.bytes.length);}
    }
  }
  assert.equal(code.pos,code.bytes.length);
  return {...counts,direct_call_sites:direct,indirect_call_sites:indirect,table_candidates:candidates.length,
    expected_source_edge_records:direct+indirect*candidates.length,fixture_unique_adjacencies:adjacency.size};
}

try {
  // Two tiny controls, separate from the two CLI smoke measurements.
  const timeout=await run(process.execPath,['-e','setInterval(()=>{},1000)'],'logs/control-timeout.log',150);
  let dead=false;try{process.kill(timeout.pid,0);}catch(e){if(e.code==='ESRCH')dead=true;}
  assert(timeout.status==='timeout'&&dead,'controlled timed-out child must terminate');
  result.control_checks.push({...timeout,check:'timeout and child termination',passed:true});
  const missing=await run(path.join(dir,'missing-cli'),[],'logs/control-missing.log',1000);
  assert.equal(missing.status,'spawn-failed');result.control_checks.push({...missing,check:'launch failure classification',passed:true});
  const plans=mode==='smoke'?[{id:'tree-64',kind:'tree',functions:64},{id:'indirect-small',kind:'indirect',candidates:8,sites:8}]:
    [{id:'tree-1000',kind:'tree',functions:1000},{id:'tree-10000',kind:'tree',functions:10000},
      {id:'indirect-repeated',kind:'indirect',candidates:128,sites:256},{id:'fib',kind:'real'}];
  if(mode==='large')plans.push({id:'tree-50000',kind:'tree',functions:50000});
  for(const plan of plans) {
    const sample={id:plan.id,parameters:plan,status:'pending',generation_ms:null,validation_ms:null,measurements:[]};result.samples.push(sample);
    let bytes;
    try {
      const start=now();bytes=plan.kind==='real'?fs.readFileSync(path.join(repo,'examples/fib.wasm')):generate(plan);
      sample.generation_ms=elapsed(start);sample.generation_scope=plan.kind==='real'?'read existing repository artifact':'generate encoded bytes';
      sample.bytes=bytes.length;sample.sha256=sha(bytes);sample.input='inputs/'+plan.id+'.wasm';
      fs.writeFileSync(path.join(dir,sample.input),bytes,{flag:'wx'});
      const validate=now();new WebAssembly.Module(bytes);
      if(plan.kind!=='real')assert.equal(sha(generate(plan)),sample.sha256,'deterministic generation');
      sample.counts=inspect(bytes,plan.kind!=='real');
      if(plan.kind==='tree')assert.deepEqual([sample.counts.local_functions,sample.counts.direct_call_sites,sample.counts.fixture_unique_adjacencies],[plan.functions,plan.functions-1,plan.functions-1]);
      if(plan.kind==='indirect')assert.deepEqual([sample.counts.local_functions,sample.counts.indirect_call_sites,sample.counts.table_candidates,sample.counts.expected_source_edge_records,sample.counts.fixture_unique_adjacencies],[plan.candidates+1,plan.sites,plan.candidates,plan.sites*plan.candidates,plan.candidates]);
      sample.validation_ms=elapsed(validate);
      sample.validation=plan.kind==='real'?'V8 accepted; function/import counts inspected; call/table/edge counts unmeasured':'V8 accepted; deterministic generation and encoded fixture counts checked';
      if(plan.kind==='real')sample.source_input='examples/fib.wasm (small real artifact, not large-project coverage)';
    } catch(e) {sample.status='input-validation-failed';sample.error=e.message;result.errors.push(plan.id+': '+e.message);save();continue;}
    for(const variant of plan.id==='tree-10000'?['plain','retained']:['plain']) {
      const group={variant,status:'running',runs:[],statistics:null};sample.measurements.push(group);
      const argv=[path.join(dir,sample.input),...(variant==='retained'?['--retained']:[])];
      const total=result.contract.warmups+result.contract.measured_runs;
      for(let i=0;i<total;i++) {
        const runResult=await run(cli,argv,`logs/${plan.id}-${variant}-${i}.log`,timeoutMs);
        const record={...runResult,phase:i<result.contract.warmups?'warmup':'measured'};group.runs.push(record);
        if(record.status==='ok') {
          const output=fs.readFileSync(path.join(dir,record.log),'utf8');
          if(!new RegExp(`Top \\d+ of ${sample.counts.local_functions} functions by size`).test(output)) {record.status='unexpected-output';record.error='CLI local function count does not match input inspection';}
        }
        if(record.status!=='ok') {result.errors.push(`${plan.id}/${variant}: ${record.status}`);break;}
      }
      const measured=group.runs.filter(r=>r.phase==='measured');
      group.statistics=stats(measured,result.contract.measured_runs);
      group.status=group.statistics&&group.runs.every(r=>r.status==='ok')?'ok':'failed';
      save();
    }
    sample.status=sample.measurements.every(g=>g.status==='ok')?'ok':'failed';save();
  }
} catch(e) {result.errors.push(e.stack??String(e));}
result.status=result.errors.length?'failed':'ok';result.finished_at=new Date().toISOString();save();
console.log(`Large-module benchmark ${result.status}: ${result.samples.length} samples; ${result.errors.length} failures. Evidence: ${dir}`);
for(const sample of result.samples)for(const group of sample.measurements)console.log(`${sample.id}/${group.variant}: ${group.status}${group.statistics?' median '+group.statistics.median_ms.toFixed(3)+' ms':''}`);
if(result.errors.length) {console.error(result.errors.join('\n'));process.exitCode=1;}
