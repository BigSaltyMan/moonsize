// Four analyzer processes only. Fixed raw encodings provide the location oracle.
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import {spawnSync} from 'node:child_process';
const cli=path.resolve(process.argv[2]||'_build/native/release/build/cmd/main/main.exe');
assert(fs.existsSync(cli),'Build the native CLI first.');
const parent=path.resolve('_build/opcode-search-verification');fs.mkdirSync(parent,{recursive:true});
const dir=fs.mkdtempSync(path.join(parent,'run-'));
const cat=(...items)=>Buffer.concat(items.map(item=>Buffer.from(item)));
const section=(id,p)=>{assert(p.length<128);return cat([id,p.length],p);};
const sha=b=>crypto.createHash('sha256').update(b).digest('hex');
const first=Buffer.from('01027f0240034041001a4180011a4341000000fc001a4300000000fc011a0b0b0b','hex');
const second=Buffer.from('0041011a4180011a0b','hex');
const prefix=Buffer.from('0061736d01000000010401600000020701016d016600000303020000','hex');
const rawName='same\ni32.const"<&',name=Buffer.from(rawName);
assert.equal(name.length,17);assert.equal(first.length,33);assert.equal(second.length,9);
const bytes=cat(prefix,Buffer.from('0606017f0041000b','hex'),section(10,cat([0x82,0,0xa1,0],first,[9],second)),
  section(0,cat([4],Buffer.from('name'),section(1,cat([2,1,name.length],name,[2,name.length],name)))),
  section(0,cat([9],Buffer.from('i32.consti32.const'))),section(11,cat([1,1,9],Buffer.from('i32.const'))));
assert.equal(bytes.length,168);assert.equal(bytes[57],0x41); // f32 immediate, not an instruction.
const functions=[
  {index:1,offset:40,total_size:35,body_size:33,bodyOffset:42,locals:'01027f',
    encodings:['0240','0340','4100','1a','418001','1a','4341000000','fc00','1a','4300000000','fc01','1a','0b','0b','0b'],
    sites:[{ordinal:2,mnemonic:'i32.const',file_offset:49,body_relative_offset:7,encoded_size:2},
      {ordinal:4,mnemonic:'i32.const',file_offset:52,body_relative_offset:10,encoded_size:3}]},
  {index:2,offset:75,total_size:10,body_size:9,bodyOffset:76,locals:'00',
    encodings:['4101','1a','418001','1a','0b'],
    sites:[{ordinal:0,mnemonic:'i32.const',file_offset:77,body_relative_offset:1,encoded_size:2},
      {ordinal:2,mnemonic:'i32.const',file_offset:80,body_relative_offset:4,encoded_size:3}]},
];
fs.writeFileSync(path.join(dir,'input.wasm'),bytes,{flag:'wx'});
const sentinel=Buffer.from('keep opcode search evidence\n');fs.writeFileSync(path.join(dir,'existing.json'),sentinel,{flag:'wx'});
const records=[];
function run(args,status){
  const p=spawnSync(cli,args,{cwd:dir,encoding:'utf8',timeout:10000}),text=(p.stdout||'')+(p.stderr||'');
  fs.writeFileSync(path.join(dir,'case-'+records.length+'.log'),text,{flag:'wx'});
  records.push({argv:[cli,...args],status:p.status,error:p.error?.message??null});
  fs.writeFileSync(path.join(dir,'processes.json'),JSON.stringify(records,null,2)+'\n');
  assert.ifError(p.error);assert.equal(p.signal,null);assert.equal(p.status,status,text);
  assert.deepEqual(fs.readFileSync(path.join(dir,'input.wasm')),bytes);
  assert.deepEqual(fs.readFileSync(path.join(dir,'existing.json')),sentinel);return text;
}
const text=run(['input.wasm','--find-opcode','i32.const','--top','1'],0);
assert(text.includes('OPCODE LOCATION SEARCH'));assert(text.includes('Scanned local functions: 2 = matched 2 + unmatched 0'));
assert(text.includes('Instructions: 20; matches: 4'));assert(text.includes('Instruction bytes: 38 = matched 10 + other 28'));
assert(text.includes('MATCHES: showing 1 of 4'));assert(text.includes('Query: "i32.const"'));
const rows=text.split(/\r?\n/).filter(s=>/^\d+  \d+  \d+  \d+  \d+  /.test(s));
assert.deepEqual(rows,['1  2  49  7  2  '+JSON.stringify(rawName)]);
assert(!text.includes(rawName));
const saved=run(['input.wasm','--find-opcode','i32.const','--find-opcode-json','new-matches.json','--top','1'],0);
assert(saved.includes('Opcode search written to new-matches.json'));assert(!saved.includes('OPCODE LOCATION SEARCH'));
const report=JSON.parse(fs.readFileSync(path.join(dir,'new-matches.json')));
assert.equal(report.format,'moonsize-opcode-search');assert.equal(report.schema_version,1);
assert.equal(report.file_size,168);assert.equal(report.sha256,sha(bytes));assert.equal(report.query,'i32.const');
const summary={imported_function_count:1,scanned_local_function_count:2,matched_function_count:2,unmatched_function_count:0,
  instruction_count:20,instruction_bytes:38,match_count:4,matched_encoded_bytes:10,other_instruction_bytes:28};
for(const [k,v]of Object.entries(summary))assert.equal(report[k],v,k);
assert.equal(report.functions.length,2);assert(!Object.hasOwn(report,'sites'));
for(const [i,f]of report.functions.entries()){
  const want=functions[i],stat=f.stat;
  for(const key of ['index','offset','total_size','body_size'])assert.equal(stat[key],want[key]);
  assert.equal(stat.name,rawName);assert.equal(stat.raw_name,rawName);
  assert.equal(f.match_count,2);assert.equal(f.matched_encoded_bytes,5);assert.deepEqual(f.sites,want.sites);
  assert.equal(bytes.subarray(want.bodyOffset,want.bodyOffset+want.locals.length/2).toString('hex'),want.locals);
  let cursor=want.bodyOffset+want.locals.length/2;
  for(const [ordinal,hex]of want.encodings.entries()){
    assert.equal(bytes.subarray(cursor,cursor+hex.length/2).toString('hex'),hex);
    const site=f.sites.find(s=>s.ordinal===ordinal);
    if(site){assert.equal(site.file_offset,cursor);assert.equal(site.body_relative_offset,cursor-want.bodyOffset);assert.equal(site.encoded_size,hex.length/2);assert(hex.startsWith('41'));}
    cursor+=hex.length/2;
  }
  assert.equal(cursor,want.offset+want.total_size);assert(!Object.hasOwn(f,'instructions'));
}
assert.equal(report.scanned_local_function_count,report.matched_function_count+report.unmatched_function_count);
assert.equal(report.match_count,report.functions.reduce((n,f)=>n+f.match_count,0));
assert.equal(report.match_count,report.functions.reduce((n,f)=>n+f.sites.length,0));
assert.equal(report.matched_encoded_bytes,report.functions.reduce((n,f)=>n+f.sites.reduce((s,x)=>s+x.encoded_size,0),0));
assert.equal(report.instruction_bytes,report.matched_encoded_bytes+report.other_instruction_bytes);
const jsonBefore=fs.readdirSync(dir).filter(f=>f.endsWith('.json')).sort();
const absent=run(['input.wasm','--find-opcode','i64.const'],0);
assert(absent.includes('No matching mnemonic in the decoded local function instructions.'));
assert(absent.includes('Scanned local functions: 2 = matched 0 + unmatched 2'));assert(absent.includes('matches: 0'));
assert.deepEqual(fs.readdirSync(dir).filter(f=>f.endsWith('.json')).sort(),jsonBefore);
assert(!absent.includes('Opcode search written to'));
const refused=run(['input.wasm','--find-opcode','i32.const','--find-opcode-json','existing.json'],1);
assert(refused.includes('output already exists'));assert(!refused.includes('Opcode search written to'));
fs.writeFileSync(path.join(dir,'results.json'),JSON.stringify({input_sha256:sha(bytes),input_size:bytes.length,summary,functions,
  records,input_and_existing_output_unchanged:true,scope:'Four new-feature CLI calls only; no old suites, V8/probe/performance or browser/PDF'},null,2)+'\n',{flag:'wx'});
console.log('Opcode-search regressions passed (4 process cases). Evidence: '+dir);
