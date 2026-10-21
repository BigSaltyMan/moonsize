// Small real-CLI contract check, not a mode/link/error combination matrix.
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';

const repo = fileURLToPath(new URL('../', import.meta.url));
const cli = path.resolve(process.argv[2] || '_build/native/release/build/cmd/main/main.exe');
assert(fs.existsSync(cli), 'Build the native CLI first.');
const parent = path.join(repo, '_build/data-segments-verification');
fs.mkdirSync(parent, {recursive:true});
const dir = fs.mkdtempSync(path.join(parent, 'run-'));
const bytes = Buffer.from('0061736d0100000005030100010c01030b140300410b0b036162630100020041000b0378797a', 'hex');
assert(WebAssembly.validate(bytes), 'V8 must independently accept the mixed fixture.');
const input = path.join(dir, 'mixed.wasm'), output = path.join(dir, 'data.json');
fs.writeFileSync(input, bytes, {flag:'wx'});
const digest = value => crypto.createHash('sha256').update(value).digest('hex');
const records = [];
function run(args, status) {
  const r = spawnSync(cli, args, {cwd:dir, encoding:'utf8', timeout:10000});
  assert.ifError(r.error); assert.equal(r.signal, null);
  const log = `cli-${records.length}.log`;
  fs.writeFileSync(path.join(dir, log), r.stdout+r.stderr, {flag:'wx'});
  records.push({args, status:r.status, log});
  assert.equal(r.status, status, r.stdout+r.stderr);
  assert.equal(digest(fs.readFileSync(input)), digest(bytes), 'input changed');
  return r.stdout+r.stderr;
}
const plain = run([input], 0);
assert(!plain.includes('DATA SEGMENT ENCODINGS'), 'default report must remain unchanged');
const top = run([input, '--data-json', output, '--top', '1', '--strict', '--baseline', input, '--max-size', '0B'], 0);
assert(top.includes('Showing 1 of 3 entries'));
assert(top.includes('payload 6 B; entry metadata 13 B; section overhead 3 B'));
assert(top.includes('payload file offset 24'));
assert(!top.includes('payload file offset 35'));
const encoded = fs.readFileSync(output);
const report = JSON.parse(encoded);
assert.equal(report.schema_version, 1);
assert.equal(report.format, 'moonsize-data-segments');
assert.equal(report.summary.total_size, 22);
assert.equal(report.summary.entry_count, 3);
assert.equal(report.datacount, 3);
assert.equal(report.summary.file_offset, 16);
assert.deepEqual(report.entries.map(e=>[e.index,e.mode,e.memory_index,e.encoding.file_offset,e.encoding.size,e.payload.file_offset,e.payload.size,e.offset_status]), [
  [0,'active',0,19,8,24,3,'not_evaluated'],
  [1,'passive',null,27,2,29,0,'not_applicable'],
  [2,'active',0,29,9,35,3,'not_evaluated'],
]);
assert.deepEqual(report.entries[0].offset_expression, {file_offset:20,size:3});
assert.equal(report.entries[1].offset_expression, null);
for(const e of report.entries) {
  assert.equal(e.encoding.size, e.mode_size+e.memory_index_size+(e.offset_expression?.size??0)+e.payload_length_size+e.payload.size);
  assert.equal(e.payload.file_offset+e.payload.size, e.encoding.file_offset+e.encoding.size);
}
assert.equal(report.summary.total_size, report.summary.header_size+report.summary.count_size+report.entries.reduce((n,e)=>n+e.encoding.size,0));
assert.equal(report.summary.payload_size, report.entries.reduce((n,e)=>n+e.payload.size,0));
const all = run([input, '--data-segments', '--top', '3'], 0);
assert(all.includes('Showing 3 of 3 entries'));
assert(all.indexOf('payload file offset 24') < all.indexOf('payload file offset 35'));
assert(all.indexOf('payload file offset 35') < all.indexOf('payload file offset 29'));
const bad = path.join(dir, 'bad.wasm'), badOutput = path.join(dir, 'bad.json');
fs.writeFileSync(bad, Buffer.from('0061736d010000000b020103', 'hex'), {flag:'wx'});
const failure = run([bad, '--data-json', badOutput], 1);
assert(failure.includes('invalid data encoding at offset 11'));
assert(!/section report|DATA SEGMENT ENCODINGS|written to/.test(failure));
assert(!fs.existsSync(badOutput));
const refused = run([input, '--data-json', output], 1);
assert(/output already exists:/.test(refused));
assert(!/section report|DATA SEGMENT ENCODINGS|written to/.test(refused));
assert.deepEqual(fs.readFileSync(output), encoded);
// Three comparison flows only. abc repeats twice after the change, xyz disappears.
const afterBytes = Buffer.from('0061736d0100000005030100010c01030b0d03010361626301036162630100', 'hex');
assert(WebAssembly.validate(afterBytes), 'V8 must accept the comparison input.');
const after = path.join(dir, 'after.wasm'), diffOutput = path.join(dir, 'diff.json');
fs.writeFileSync(after, afterBytes, {flag:'wx'});
const diffText = run([after, '--baseline', input, '--diff-data', '--data-json', diffOutput, '--top', '1', '--strict', '--max-size', '0B'], 0);
assert(diffText.includes('DATA SEGMENT CONTENT COMPARISON'));
assert(diffText.includes('before 22; after 15; delta -7'));
assert(diffText.includes('payload 0 B; entry metadata -7 B; section overhead 0 B'));
assert(diffText.includes('Showing 1 of 3 content groups'));
const diffBytes = fs.readFileSync(diffOutput), diff = JSON.parse(diffBytes);
assert.equal(diff.format, 'moonsize-data-segments-diff');
assert.equal(diff.schema_version, 1);
assert.equal(diff.baseline.path, input);
assert.equal(diff.current.path, after);
assert.equal(diff.baseline.sha256, digest(bytes));
assert.equal(diff.current.sha256, digest(afterBytes));
assert.deepEqual(diff.baseline.details, report, 'retain the complete original single-file detail format');
assert.equal(diff.current.details.entries.length, 3);
assert.equal(diff.current.details.entries[0].mode, 'passive');
assert.deepEqual(diff.delta, {section_size:-7,payload_size:0,entry_metadata_size:-7,section_overhead_size:0});
assert.equal(diff.groups.length, 3, 'Top must not truncate JSON');
const abc = diff.groups.find(g=>g.sha256===digest(Buffer.from('abc')));
assert(abc);
assert.equal(abc.kind, 'shared_payload');
assert.equal(abc.payload_length, 3);
assert.deepEqual(abc.baseline_indices, [0]);
assert.deepEqual(abc.current_indices, [0,1]);
assert.deepEqual(abc.baseline, {count:1,payload_size:3,encoded_size:8,metadata_size:5});
assert.deepEqual(abc.current, {count:2,payload_size:6,encoded_size:10,metadata_size:4});
assert.deepEqual(abc.delta, {count:1,payload_size:3,encoded_size:2,metadata_size:-1});
for (const g of diff.groups) {
  assert.equal(g.sha256.length, 64);
  assert.equal(g.delta.count, g.current.count-g.baseline.count);
  for (const key of ['payload_size','encoded_size','metadata_size']) assert.equal(g.delta[key], g.current[key]-g.baseline[key]);
  for (const [side, raw] of [['baseline',bytes],['current',afterBytes]]) {
    for(const index of g[side+'_indices']) {
      const p = diff[side].details.entries[index].payload;
      assert.equal(digest(raw.subarray(p.file_offset,p.file_offset+p.size)), g.sha256);
      assert.equal(p.size, g.payload_length);
    }
  }
}
assert.equal(diff.groups.reduce((n,g)=>n+g.delta.payload_size,0), diff.delta.payload_size);
assert.equal(diff.groups.reduce((n,g)=>n+g.delta.metadata_size,0), diff.delta.entry_metadata_size);
assert.equal(diff.groups.reduce((n,g)=>n+g.delta.encoded_size,0), diff.delta.payload_size+diff.delta.entry_metadata_size);
assert.equal(diff.delta.section_size, diff.delta.payload_size+diff.delta.entry_metadata_size+diff.delta.section_overhead_size);
const badDiffOutput = path.join(dir, 'bad-diff.json');
const badDiff = run([after, '--baseline', bad, '--diff-data', '--data-json', badDiffOutput], 1);
assert(badDiff.includes('baseline: invalid data encoding at offset 11'));
assert(!/section report|DATA SEGMENT|written to/.test(badDiff));
assert(!fs.existsSync(badDiffOutput));
const protectedDiff = run([after, '--baseline', input, '--diff-data', '--data-json', diffOutput], 1);
assert(protectedDiff.includes('output already exists:'));
assert(!/section report|DATA SEGMENT|written to/.test(protectedDiff));
assert.deepEqual(fs.readFileSync(diffOutput), diffBytes);
assert.deepEqual(fs.readFileSync(after), afterBytes);
assert.deepEqual(fs.readFileSync(output), encoded);
fs.writeFileSync(path.join(dir, 'verification.json'), JSON.stringify({input_sha256:digest(bytes),input_bytes:bytes.length,records},null,2)+'\n', {flag:'wx'});
console.log(`Data-segment CLI regressions passed (${records.length} process cases, 2 V8-validated modules). Evidence: ${dir}`);
