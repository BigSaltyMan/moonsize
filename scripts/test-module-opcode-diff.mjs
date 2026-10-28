// Exactly four analyzer calls. Fixed byte encodings, not analyzer-derived oracles.
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import {spawnSync} from 'node:child_process';
const cli = path.resolve(process.argv[2] || '_build/native/release/build/cmd/main/main.exe');
assert(fs.existsSync(cli), 'Build the native CLI first.');
const parent = path.resolve('_build/module-opcode-diff-verification');
fs.mkdirSync(parent, {recursive:true});
const dir = fs.mkdtempSync(path.join(parent, 'run-'));
const sha = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
const header = '0061736d01000000010401600000020701016d01660000';
const baseline = Buffer.from(header+'03030200000a0e02060041001a010b050041011a0b','hex');
const current = Buffer.from(header+'0304030000000a99008300890001017f004180011a0b050041021a0b050041031a0b','hex');
assert.equal(baseline.length,44); assert.equal(current.length,57);
const cases = [
  {bytes:baseline,file:'baseline.wasm',code:{id:10,kind:'code',offset:28,payload_size:14,total_size:16},countOffset:30,countHex:'02',
    prefixOffsets:[31,38],prefixHex:['06','05'],localsOffsets:[32,39],localsHex:['00','00'],
    instructions:[['4100','1a','01','0b'],['4101','1a','0b']],instructionCount:7,instructionBytes:9},
  {bytes:current,file:'current.wasm',code:{id:10,kind:'code',offset:29,payload_size:25,total_size:28},countOffset:32,countHex:'8300',
    prefixOffsets:[34,45,51],prefixHex:['8900','05','05'],localsOffsets:[36,46,52],localsHex:['01017f','00','00'],
    instructions:[['00','418001','1a','0b'],['4102','1a','0b'],['4103','1a','0b']],instructionCount:10,instructionBytes:14},
];
for(const c of cases) fs.writeFileSync(path.join(dir,c.file),c.bytes,{flag:'wx'});
const sentinel=Buffer.from('preserve opcode comparison evidence\n');
fs.writeFileSync(path.join(dir,'existing.json'),sentinel,{flag:'wx'});
const records=[];
function run(args,status) {
  const p=spawnSync(cli,args,{cwd:dir,encoding:'utf8',timeout:10000});
  const text=(p.stdout||'')+(p.stderr||'');
  fs.writeFileSync(path.join(dir,'case-'+records.length+'.log'),text,{flag:'wx'});
  records.push({argv:[cli,...args],status:p.status,error:p.error?.message??null});
  fs.writeFileSync(path.join(dir,'processes.json'),JSON.stringify(records,null,2)+'\n');
  assert.ifError(p.error); assert.equal(p.signal,null); assert.equal(p.status,status,text);
  for(const c of cases) assert.deepEqual(fs.readFileSync(path.join(dir,c.file)),c.bytes);
  assert.deepEqual(fs.readFileSync(path.join(dir,'existing.json')),sentinel);
  return text;
}
const baseArgs=['current.wasm','--baseline','baseline.wasm','--diff-opcodes'];
const text=run([...baseArgs,'--top','1'],0);
assert(text.includes('MODULE FUNCTION OPCODE COMPARISON'));
assert(text.includes('File delta: 13 = code 12 + non-code 1'));
assert(text.includes('Code delta: 12 = header 1 + count encoding 1 + body prefixes 2 + locals 3 + instructions 5'));
assert(text.includes('OPCODE COMPOSITION: showing 1 of 5'));
const lines=text.split(/\r?\n/).filter(s=>/^[a-z0-9._]+  (?:shared_opcode|baseline_only|current_only)  /.test(s));
assert.deepEqual(lines,['i32.const  shared_opcode  2  3  1  4  7  3  2  3  1']);
const confirmation=run([...baseArgs,'--opcode-stats-json','new-diff.json','--top','1'],0);
assert(confirmation.includes('Module opcode comparison written to new-diff.json'));
assert(!confirmation.includes('MODULE FUNCTION OPCODE COMPARISON'));
const report=JSON.parse(fs.readFileSync(path.join(dir,'new-diff.json')));
assert.equal(report.format,'moonsize-module-opcodes-diff'); assert.equal(report.schema_version,1);
const expectedDelta={file_bytes:13,code_bytes:12,non_code_bytes:1,code_header_bytes:1,count_encoding_bytes:1,
  body_prefix_bytes:2,locals_encoding_bytes:3,instruction_bytes:5,instruction_count:3,imported_function_count:0,local_function_count:1};
assert.deepEqual(report.delta,expectedDelta);
const expectedRows=[
  ['i32.const','shared_opcode',2,3,4,7,2,3],['drop','shared_opcode',2,3,2,3,2,3],
  ['end','shared_opcode',2,3,2,3,2,3],['nop','baseline_only',1,0,1,0,1,0],['unreachable','current_only',0,1,0,1,0,1],
].map(([mnemonic,status,bc,cc,bb,cb,bf,cf])=>({mnemonic,status,baseline_count:bc,current_count:cc,count_delta:cc-bc,
  baseline_encoded_bytes:bb,current_encoded_bytes:cb,encoded_bytes_delta:cb-bb,
  baseline_function_count:bf,current_function_count:cf,function_count_delta:cf-bf}));
assert.deepEqual(report.opcodes,expectedRows);
for(const [i,c]of cases.entries()) {
  const r=i===0?report.baseline:report.current;
  assert.equal(typeof r,'object');assert.equal(r.format,'moonsize-module-opcodes');assert.equal(r.schema_version,1);
  assert.equal(r.file_size,c.bytes.length);assert.equal(r.sha256,sha(c.bytes));assert.deepEqual(r.code_section,c.code);
  assert.equal(r.local_function_count,c.prefixHex.length);assert.equal(r.imported_function_count,1);
  assert.deepEqual(r.count_encoding,{file_offset:c.countOffset,size:c.countHex.length/2});
  assert.equal(c.bytes.subarray(c.countOffset,c.countOffset+r.count_encoding.size).toString('hex'),c.countHex);
  assert.equal(r.functions.length,c.prefixHex.length);
  for(const [j,f]of r.functions.entries()) {
    assert.equal(f.stat.index,j+1);assert.equal(f.stat.name,null);assert.equal(f.stat.raw_name,null);
    assert.equal(f.stat.offset,c.prefixOffsets[j]);assert.equal(f.stat.total_size-f.stat.body_size,c.prefixHex[j].length/2);
    assert.equal(c.bytes.subarray(f.stat.offset,c.localsOffsets[j]).toString('hex'),c.prefixHex[j]);
    assert.deepEqual(f.locals_encoding,{file_offset:c.localsOffsets[j],size:c.localsHex[j].length/2});
    assert.equal(c.bytes.subarray(c.localsOffsets[j],c.localsOffsets[j]+f.locals_encoding.size).toString('hex'),c.localsHex[j]);
    let cursor=c.localsOffsets[j]+f.locals_encoding.size;
    for(const hex of c.instructions[j]) {assert.equal(c.bytes.subarray(cursor,cursor+hex.length/2).toString('hex'),hex);cursor+=hex.length/2;}
    assert.equal(cursor,f.stat.offset+f.stat.total_size);
    assert.equal(f.instruction_count,c.instructions[j].length);
    assert.equal(f.instruction_bytes,c.instructions[j].reduce((n,hex)=>n+hex.length/2,0));
    assert(!Object.hasOwn(f,'instructions'));assert(!Object.hasOwn(f,'groups'));
  }
  assert.equal(r.instruction_count,c.instructionCount);assert.equal(r.instruction_bytes,c.instructionBytes);
  assert.equal(r.code_header_bytes+r.count_encoding_bytes+r.body_prefix_bytes+r.locals_encoding_bytes+r.instruction_bytes,c.code.total_size);
  assert.equal(r.groups.reduce((n,g)=>n+g.count,0),r.instruction_count);
  assert.equal(r.groups.reduce((n,g)=>n+g.encoded_bytes,0),r.instruction_bytes);
}
const d=report.delta;
assert.equal(d.file_bytes,d.code_bytes+d.non_code_bytes);
assert.equal(d.code_bytes,d.code_header_bytes+d.count_encoding_bytes+d.body_prefix_bytes+d.locals_encoding_bytes+d.instruction_bytes);
assert.equal(report.opcodes.reduce((n,g)=>n+g.count_delta,0),d.instruction_count);
assert.equal(report.opcodes.reduce((n,g)=>n+g.encoded_bytes_delta,0),d.instruction_bytes);
run(['current.wasm','--baseline','current.wasm','--diff-opcodes','--opcode-stats-json','self.json'],0);
const self=JSON.parse(fs.readFileSync(path.join(dir,'self.json')));
assert.deepEqual(self.baseline,self.current);assert.equal(self.baseline.functions.length,3);
for(const value of Object.values(self.delta))assert.equal(value,0);
assert.equal(self.opcodes.length,4);
for(const g of self.opcodes){assert.equal(g.status,'shared_opcode');for(const k of ['count_delta','encoded_bytes_delta','function_count_delta'])assert.equal(g[k],0);}
const refused=run([...baseArgs,'--opcode-stats-json','existing.json'],1);
assert(refused.includes('output already exists'));assert(!refused.includes('Module opcode comparison written to'));
fs.writeFileSync(path.join(dir,'results.json'),JSON.stringify({baseline_sha256:sha(baseline),current_sha256:sha(current),
  sizes:[baseline.length,current.length],delta:expectedDelta,opcodes:expectedRows,records,inputs_and_sentinel_unchanged:true,
  scope:'Exactly four new-feature analyzer calls; no old suites, probes, V8 matrix, performance or browser/PDF'},null,2)+'\n',{flag:'wx'});
console.log('Module-opcode-diff regressions passed (4 process cases). Evidence: '+dir);
