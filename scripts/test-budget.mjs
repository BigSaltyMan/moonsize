// Actual process contracts; V8 checks fixture legality independently of moonsize.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import crypto from 'node:crypto';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
const cli = path.resolve(process.argv[2] || '_build/native/release/build/cmd/main/main.exe');
const parent = path.resolve(os.tmpdir());
const work = fs.mkdtempSync(path.join(parent, 'moonsize-budget-'));
let cases = 0, fixtures = 0, serial = 0;
const cat = (...items) => Buffer.concat(items.map(x => Buffer.from(x)));
const leb = n => { const a=[]; do { let b=n&127; n>>>=7; a.push(b|(n?128:0)); } while(n); return Buffer.from(a); };
const str = s => cat(leb(Buffer.byteLength(s)), Buffer.from(s));
const section = (id,b) => cat([id],leb(b.length),b);
const hash = b => crypto.createHash('sha256').update(b).digest('hex');
function fixture(label, funcs, {table=false, indirect=false, empty=false}={}) {
  const bodies = funcs.map(([,n]) => indirect ? Buffer.from([0,65,0,17,0,0,11]) : cat([0],Buffer.alloc(n,1),[11]));
  const code = empty ? null : section(10,cat(leb(bodies.length),...bodies.map(b=>cat(leb(b.length),b))));
  const names = funcs.flatMap(([name],index)=>name===null?[]:[[index,name]]);
  const data=cat(Buffer.from('0061736d01000000','hex'),
    ...(empty?[]:[section(1,Buffer.from([1,96,0,0])),section(3,cat(leb(funcs.length),Buffer.alloc(funcs.length)))]),
    ...(table?[section(4,Buffer.from([1,112,0,1]))]:[]),
    ...(funcs.length?[section(7,cat([1],str('run'),[0,0]))]:[]),
    ...(code?[code]:[]),
    ...(names.length?[section(0,cat(str('name'),section(1,cat(leb(names.length),...names.map(([i,n])=>cat(leb(i),str(n)))))))]:[]));
  assert(WebAssembly.validate(data),'V8 rejected '+label);fixtures++;
  const file=path.join(work,label+'.wasm');fs.writeFileSync(file,data);
  return {file,data,code:code?.length||0,packageBytes:funcs.reduce((n,[s],i)=>n+(s?.startsWith('pkg.')?leb(bodies[i].length).length+bodies[i].length:0),0)};
}
function run(args,status=0) {
  const r=spawnSync(cli,args,{encoding:'utf8',timeout:5000,maxBuffer:8*1024*1024});cases++;
  assert(!r.error&&!r.signal,`${r.error||r.signal}: ${args.join(' ')}`);
  assert.equal(r.status,status,`${args.join(' ')}\n${r.stdout}\n${r.stderr}`);
  return r.stdout+r.stderr;
}
const rule=(metric,max_bytes,mode='absolute',extra={})=>({id:metric,metric,mode,max_bytes,...extra});
function config(value) {
  const file=path.join(work,`config-${serial++}.json`);fs.writeFileSync(file,typeof value==='string'?value:JSON.stringify(value));return file;
}
function evaluate(current,rules,{baseline=null,status=0,extra=[]}={}) {
  const output=path.join(work,`report-${serial++}.json`),md=path.join(work,`report-${serial++}.md`);
  const cfg=config({version:1,rules});
  const text=run([current.file,'--budget',cfg,'--budget-json',output,'--budget-md',md,...(baseline?['--baseline',baseline.file]:[]),...extra],status);
  const json=JSON.parse(fs.readFileSync(output,'utf8')),markdown=fs.readFileSync(md,'utf8');
  assert.equal(json.format,'moonsize-budget');assert.equal(json.schema_version,1);assert.equal(json.config_version,1);
  assert.equal(json.exit_code,status);assert.equal(json.current.sha256,hash(current.data));assert.equal(json.current.path,current.file);
  assert.equal(json.current.raw_bytes,current.data.length);assert.equal(json.current.code_bytes,current.code);
  if(json.baseline) assert.equal(json.baseline.sha256,hash(baseline.data));
  assert(text.includes(`Overall: ${json.status}; exit code ${status}`));
  assert(markdown.includes(`## Size budget: ${json.status}`));assert(markdown.includes(json.current.sha256));
  assert.equal(json.rules.length,rules.length);
  return {json,markdown,text,output,md,cfg};
}
try {
  const small=fixture('small',[['pkg.target',1],['other.helper',0]]);
  const large=fixture('large',[['pkg.target',500],['other.helper',0]]);
  const empty=fixture('empty',[],{empty:true});
  const gone=fixture('gone',[['other.helper',0]]);
  const unknown=fixture('unknown',[['pkg.target',1],[null,0]]);
  const dynamic=fixture('dynamic',[['entry',0]],{table:true,indirect:true});
  const repeated=evaluate(small,[rule('file.gzip',2147483647),rule('file.gzip',2147483647,'absolute',{id:'gzip-again'})],{extra:['--compress']});
  const gzip=repeated.json.rules[0].current;
  assert.equal(gzip,repeated.json.rules[1].current);
  assert.match(repeated.text,new RegExp(`gzip\\s+${gzip}\\s+B`));
  assert.equal(repeated.json.current.whole_gzip_bytes,gzip);
  for(const [metric,expected] of [['file.raw',small.data.length],['code.raw',small.code],['file.gzip',gzip],['package.raw',small.packageBytes]]) {
    const extra=metric==='package.raw'?{package:'pkg'}:{};
    const same=evaluate(small,[rule(metric,expected,'absolute',extra)]);
    assert.equal(same.json.rules[0].current,expected);assert.equal(same.json.rules[0].baseline,null);assert.equal(same.json.rules[0].delta,null);
    assert.equal(evaluate(small,[rule(metric,expected-1,'absolute',extra)],{status:3}).json.rules[0].status,'exceeded');
    assert.equal(evaluate(small,[rule(metric,0,'growth',extra)],{baseline:small}).json.rules[0].delta,0);
    const growth=evaluate(large,[rule(metric,2147483647,'growth',extra)],{baseline:small});
    const delta=growth.json.rules[0].delta;assert(delta>0,'fixture must grow: '+metric);
    evaluate(large,[rule(metric,delta,'growth',extra)],{baseline:small});
    evaluate(large,[rule(metric,delta-1,'growth',extra)],{baseline:small,status:3});
    const shrink=evaluate(small,[rule(metric,0,'growth',extra)],{baseline:large});assert(shrink.json.rules[0].delta<0);
  }
  evaluate(empty,[rule('code.raw',0),rule('file.raw',8)]);
  const mixed=evaluate(unknown,[rule('file.raw',0),rule('package.raw',2147483647,'absolute',{package:'pkg'}),rule('code.raw',2147483647)],{status:1});
  assert.deepEqual(mixed.json.rules.map(r=>r.status),['exceeded','unavailable','passed']);
  assert.equal(mixed.json.rules[1].current,null);assert(mixed.json.rules[1].reason.includes('coverage insufficient'));
  assert.equal(mixed.json.current.attribution.unattributed_functions,1);
  assert.equal(mixed.json.rules[1].current_package_present,true);
  const disappeared=evaluate(gone,[rule('package.raw',0,'growth',{package:'pkg'})],{baseline:small});
  assert.equal(disappeared.json.rules[0].current,0);assert(disappeared.json.rules[0].reason.includes('disappeared'));
  const appeared=evaluate(small,[rule('package.raw',0,'growth',{package:'pkg'})],{baseline:gone,status:3});
  assert.equal(appeared.json.rules[0].baseline,0);assert(appeared.json.rules[0].reason.includes('newly observed'));
  const absent=evaluate(gone,[rule('package.raw',0,'growth',{package:'pkg'})],{baseline:gone,status:1});
  assert.equal(absent.json.rules[0].current,null);assert(absent.json.rules[0].reason.includes('label not found'));
  evaluate(small,[rule('package.raw',small.packageBytes,'absolute',{package:'pkg'}),rule('file.raw',2147483647,'growth')],{baseline:unknown});
  const escaped=evaluate(small,[rule('file.raw',0,'absolute',{id:'x|`<tag>\n*[]\\'})],{status:3});
  for(const entity of ['&#124;','&#96;','&lt;','&#10;','&#42;','&#91;','&#92;'])assert(escaped.markdown.includes(entity));
  assert(!escaped.markdown.includes('<tag>'));
  const invalids=['{',null,[],{}, {version:2,rules:[rule('file.raw',1)]}, {version:1,rules:[]},
    {version:1,rules:'no'}, {version:1,rules:[null]}, {version:1,rules:[rule('file.raw',0)],typo:true},
    ...[-1,0.5,2147483648,'1KB',null,true].map(n=>({version:1,rules:[rule('file.raw',n)]})),
    ...[{id:''},{id:'  '},{metric:'file.br'},{mode:'percent'},{package:null},{extra:1},{metric:'package.raw'},{metric:'package.raw',package:''}].map(x=>({version:1,rules:[rule('file.raw',0,'absolute',x)]})),
    {version:1,rules:[rule('file.raw',0),rule('file.raw',0)]}];
  for(const c of invalids) {
    const text=run(['absent.wasm','--budget',config(c)],2);assert(!text.includes('cannot read absent.wasm'));assert(!text.includes('SECTION'));
  }
  const absolute=config({version:1,rules:[rule('file.raw',2147483647)]});
  for(const token of ['1.0','1e0','1.00000000000000000001','2147483647.000000000000001','-0']) {
    const raw=`{"version":1,"rules":[{"id":"numeric","metric":"file.raw","mode":"absolute","max_bytes":${token}}]}`;
    const text=run(['absent.wasm','--budget',config(raw)],2);assert(!text.includes('cannot read absent.wasm'));
  }
  const growth=config({version:1,rules:[rule('file.raw',0,'growth')]});
  assert.match(run(['absent.wasm','--budget',growth],2),/require --baseline/);
  run(['absent.wasm','--budget',growth,'--baseline',''],2);
  run(['absent.wasm','--budget',growth,'--baseline','--strict'],2);
  for(const flag of ['--budget','--budget-json','--budget-md']) {
    run(['absent.wasm',flag],2);run(['absent.wasm',flag,''],2);run(['absent.wasm',flag,'--strict'],2);
  }
  run(['absent.wasm','--budget-json','x.json'],2);run(['absent.wasm','--budget-md','x.md'],2);
  for(const options of [['--max-size','1KB'],['--html','x.html'],['--call-graph','x.json'],['--why-index','0'],['--why-root','0'],['--experiment','x.json'],['--experiment-context','x.json']]) {
    const text=run(['absent.wasm','--budget',absolute,...options],2);assert(!text.includes('cannot read absent.wasm'));
  }
  run([small.file,'--budget',absolute,'--budget-json','x.txt'],2);run([small.file,'--budget',absolute,'--budget-md','x.txt'],2);
  run(['absent.wasm','--budget',absolute],1);run([small.file,'--budget',path.join(work,'absent.json')],1);
  const bad=path.join(work,'bad.wasm');fs.writeFileSync(bad,'bad');
  run([bad,'--budget',absolute],1);run([small.file,'--budget',growth,'--baseline',bad],1);
  for(const args of [[bad,'--budget',absolute],[small.file,'--budget',growth,'--baseline',bad]]) {
    const output=path.join(work,`bad-input-${serial++}.json`);
    const text=run([...args,'--budget-json',output],1);assert(!fs.existsSync(output));assert(!text.includes('SIZE BUDGET'));
  }
  for(const format of ['json','md']) {
    const file=path.join(work,'keep.'+format);fs.writeFileSync(file,'KEEP');
    run([small.file,'--budget',absolute,'--budget-'+format,file],1);assert.equal(fs.readFileSync(file,'utf8'),'KEEP');
    run([small.file,'--budget',absolute,'--budget-'+format,path.join(work,'missing',file.split(path.sep).at(-1))],1);
    const directory=path.join(work,'directory.'+format);fs.mkdirSync(directory);run([small.file,'--budget',absolute,'--budget-'+format,directory],1);
    for(const exists of [false,true]) {
      const target=path.join(work,`strict-${format}-${exists}.${format}`);if(exists)fs.writeFileSync(target,'KEEP');
      const text=run([dynamic.file,'--budget',absolute,'--strict','--budget-'+format,target],3);
      assert(!text.includes('SIZE BUDGET'));assert(!text.includes('SECTION'));assert(text.includes('--strict'));
      if(exists)assert.equal(fs.readFileSync(target,'utf8'),'KEEP');else assert(!fs.existsSync(target));
    }
  }
  const inputJson=path.join(work,'input.json');fs.writeFileSync(inputJson,small.data);
  run([inputJson,'--budget',absolute,'--budget-json',inputJson],1);assert(fs.readFileSync(inputJson).equals(small.data));
  const alias=path.join(work,'alias.json');fs.linkSync(small.file,alias);
  run([small.file,'--budget',absolute,'--budget-json',alias],1);assert(fs.readFileSync(small.file).equals(small.data));
  const first=path.join(work,'not-created.json'),second=path.join(work,'exists.md');fs.writeFileSync(second,'KEEP');
  run([small.file,'--budget',absolute,'--budget-json',first,'--budget-md',second],1);assert(!fs.existsSync(first));
  const partial=path.join(work,'partial.json');
  const failure=run([small.file,'--budget',absolute,'--budget-json',partial,'--budget-md',path.join(work,'missing','summary.md')],1);
  assert(!failure.includes('all reports'));assert.equal(JSON.parse(fs.readFileSync(partial)).status,'passed');
  run([small.file,'--max-size','100KB']);assert.match(run([small.file,'--max-size','0B'],3),/over the budget/);
  run([dynamic.file,'--budget',absolute]);
  evaluate(small,[rule('file.raw',2147483647)],{extra:['--strict','--compress','--retained','--dead-code','--top','1']});
  evaluate(small,[rule('file.raw',2147483647,'growth')],{baseline:small,extra:['--diff-functions','--top','0']});
  console.log(`Budget CLI regressions passed (${cases} process cases, ${fixtures} V8-validated modules).`);
} finally {
  assert.equal(path.dirname(work),parent);assert(path.basename(work).startsWith('moonsize-budget-'));
  fs.rmSync(work,{recursive:true,force:true});
}
