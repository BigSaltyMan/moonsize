// Real CLI regressions. All generated files stay under an isolated _build folder.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const cli = path.resolve(process.argv[2] || path.join(root, '_build/native/release/build/cmd/main/main.exe'));
const baseDir = path.join(root, '_build/experiment-tests');
fs.mkdirSync(baseDir, {recursive: true});
const dir = fs.mkdtempSync(path.join(baseDir, 'run-'));
let cases = 0;
const file = name => path.join(dir, name);
const sha = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
const header = Buffer.from('0061736d01000000', 'hex');
const fixture = Buffer.from('0061736d01000000010401600000030201000a040102000b', 'hex');
const indirect = Buffer.from('0061736d01000000010401600000030201000404017000010a0901070041001300000b', 'hex');
for (const [name, bytes] of [['empty.wasm', header], ['body.wasm', fixture], ['indirect.wasm', indirect]]) {
  assert(WebAssembly.validate(bytes), name);
  fs.writeFileSync(file(name), bytes);
}
fs.writeFileSync(file('bad.wasm'), 'not wasm');
function run(args, status = 0) {
  const r = spawnSync(cli, args, {cwd: root, encoding: 'utf8', timeout: 15000});
  assert.ifError(r.error);
  assert.equal(r.signal, null);
  assert.equal(r.status, status, `${args.join(' ')}\n${r.stdout}\n${r.stderr}`);
  cases++;
  return r.stdout + r.stderr;
}
function invoke(name, before = 'empty.wasm', after = 'body.wasm', extra = [], status = 0) {
  return run([file(after), '--baseline', file(before), '--experiment', file(name), ...extra], status);
}
function read(name) {return JSON.parse(fs.readFileSync(file(name), 'utf8'));}
invoke('growth.json');
const growth = read('growth.json');
assert.equal(growth.schema_version, 1);
assert.equal(growth.raw_delta, fixture.length - header.length);
assert.equal(growth.baseline.sha256, sha(header));
assert.equal(growth.current.sha256, sha(fixture));
assert.equal(growth.build_comparability, 'not-recorded');
assert.equal(growth.validation_status, 'not-recorded');
for (const [name, bytes, artifact] of [['empty.wasm', header, growth.baseline], ['body.wasm', fixture, growth.current]]) {
  const text = run([file(name), '--compress', '--top', '0']);
  const size = Number(text.match(/^\s*gzip\s+(\d+)\s+B/m)?.[1]);
  assert(Number.isInteger(size));
  assert.equal(artifact.whole_gzip_bytes, size);
  assert.equal(artifact.raw_bytes, bytes.length);
}
assert.equal(growth.whole_gzip_delta, growth.current.whole_gzip_bytes - growth.baseline.whole_gzip_bytes);
invoke('shrink.json', 'body.wasm', 'empty.wasm');
assert.equal(read('shrink.json').raw_delta, -growth.raw_delta);
assert.equal(read('shrink.json').whole_gzip_delta, -growth.whole_gzip_delta);
invoke('self.json', 'body.wasm', 'body.wasm', ['--top', '0']);
const self = read('self.json');
assert.equal(self.raw_delta, 0);
assert.equal(self.whole_gzip_delta, 0);
assert.deepEqual(self.functions, []);
assert.equal(self.matching.missing_baseline.count, 1);
assert.equal(self.matching.missing_current.count, 1);
assert.equal(self.current_code.function_bytes + self.current_code.overhead_bytes, self.current_code.section_bytes);
assert.equal(growth.baseline_code.section_bytes, 0);
assert.equal(growth.current_code.section_bytes, 6);

const build = {revision: 'before-source-sha', command: 'moon build --target wasm --release --no-strip', toolchain: 'pinned', target: 'wasm', mode: 'release', strip: false, features: []};
const context = {title: '<script>alert("title")</script>', hypothesis: 'Remove an optional output; retain base behavior', baseline: build, current: {...build, revision: 'after-source-sha'}, validation: {status: 'passed', command: 'test base behavior', notes: '<img src=x onerror=alert(1)>'}};
function writeContext(value) {fs.writeFileSync(file('context.json'), JSON.stringify(value));}
writeContext(context);
invoke('recorded.json', 'empty.wasm', 'body.wasm', ['--experiment-context', file('context.json')]);
assert.equal(read('recorded.json').build_comparability, 'same-declared-settings');
assert.equal(read('recorded.json').validation_status, 'passed');
assert.match(read('recorded.json').context_provenance, /Self-reported/);
invoke('recorded.html', 'empty.wasm', 'body.wasm', ['--experiment-context', file('context.json')]);
const html = fs.readFileSync(file('recorded.html'), 'utf8');
assert(!html.includes('<script>') && !html.includes('<img src=x'));
assert(html.includes('&lt;script&gt;'));
assert(html.includes('sha256') && html.includes(sha(fixture)));
assert(html.includes('Self-reported') && html.includes('whole-file gzip'));
assert(!/<script\b|<link\b|<iframe\b|<img\b/i.test(html), 'Experiment HTML must work without scripts or external resources');
context.current.mode = 'debug'; context.current.strip = true;
context.validation.status = 'failed';
writeContext(context);
invoke('confounded.json', 'body.wasm', 'empty.wasm', ['--experiment-context', file('context.json')]);
assert.deepEqual(read('confounded.json').different_build_fields, ['mode', 'strip']);
assert.equal(read('confounded.json').validation_status, 'failed');
context.validation.status = 'not-run'; context.validation.command = '';
writeContext(context);
invoke('not-run.json', 'body.wasm', 'empty.wasm', ['--experiment-context', file('context.json')]);
assert.equal(read('not-run.json').validation_status, 'not-run');

const invalidContexts = [[], {typo: true}, {...context, current: {...context.current, strip: 'false'}}, {...context, validation: {status: 'passed', command: '', notes: ''}}, {...context, validation: {...context.validation, status: 'unknown'}}];
for (const [i, value] of invalidContexts.entries()) {
  writeContext(value);
  const output = `invalid-${i}.json`;
  assert.match(invoke(output, 'empty.wasm', 'body.wasm', ['--experiment-context', file('context.json')], 1), /context/);
  assert(!fs.existsSync(file(output)));
}
fs.writeFileSync(file('context.json'), '{');
assert.match(invoke('malformed-context.json', 'missing.wasm', 'missing.wasm', ['--experiment-context', file('context.json')], 1), /invalid experiment context/);
assert(!fs.existsSync(file('malformed-context.json')));
invoke('missing-context.json', 'empty.wasm', 'body.wasm', ['--experiment-context', file('missing-context-input.json')], 1);

for (const [i, before, after] of [[0, 'bad.wasm', 'body.wasm'], [1, 'empty.wasm', 'bad.wasm'], [2, 'missing.wasm', 'body.wasm'], [3, 'empty.wasm', 'missing.wasm']]) {
  invoke(`bad-input-${i}.json`, before, after, [], 1);
  assert(!fs.existsSync(file(`bad-input-${i}.json`)));
}
for (const args of [
  [file('missing'), '--experiment', file('usage.json')],
  [file('missing'), '--baseline', file('missing'), '--experiment', file('usage.txt')],
  [file('missing'), '--experiment-context', file('missing')],
  ...['--retained', '--compress', '--dead-code', '--diff-functions'].map(flag => [file('missing'), '--baseline', file('missing'), '--experiment', file('usage.json'), flag]),
  ...['--html', '--call-graph'].map(flag => [file('missing'), '--baseline', file('missing'), '--experiment', file('usage.json'), flag, file('other')]),
]) {
  assert.match(run(args, 2), /--experiment/);
  assert(!fs.existsSync(file('usage.json')));
}
for (const [i, before, after] of [[0, 'indirect.wasm', 'body.wasm'], [1, 'empty.wasm', 'indirect.wasm']]) {
  invoke(`gap-${i}.json`, before, after);
  const report = read(`gap-${i}.json`);
  const artifact = i === 0 ? report.baseline : report.current;
  assert.equal(artifact.graph_complete, false);
  assert(artifact.diagnostics.length > 0);
  assert.match(invoke(`strict-gap-${i}.json`, before, after, ['--strict'], 3), /incomplete/);
  assert(!fs.existsSync(file(`strict-gap-${i}.json`)));
}
invoke('strict-complete.json', 'empty.wasm', 'body.wasm', ['--strict']);
invoke('budget-refused.json', 'empty.wasm', 'body.wasm', ['--max-size', '0B'], 3);
assert.equal(read('budget-refused.json').raw_delta, growth.raw_delta);
assert.equal(read('budget-refused.json').raw_growth_budget_bytes, 0);
assert.equal(read('budget-refused.json').raw_growth_budget_passed, false);
invoke('budget-ok.json', 'body.wasm', 'empty.wasm', ['--max-size', '0B']);
assert.equal(read('budget-ok.json').raw_growth_budget_passed, true);
invoke('budget-refused.html', 'empty.wasm', 'body.wasm', ['--max-size', '0B'], 3);
assert.match(fs.readFileSync(file('budget-refused.html'), 'utf8'), /Raw growth budget/);
assert.match(fs.readFileSync(file('budget-refused.html'), 'utf8'), /Passed: false/);
fs.writeFileSync(file('existing.json'), 'keep me');
assert.match(invoke('existing.json', 'empty.wasm', 'body.wasm', [], 1), /already exists/);
assert.equal(fs.readFileSync(file('existing.json'), 'utf8'), 'keep me');
// Protect input aliases: current/baseline paths can contain JSON suffixes too.
fs.writeFileSync(file('protected-input.json'), fixture);
run([file('protected-input.json'), '--baseline', file('empty.wasm'), '--experiment', path.relative(root, file('protected-input.json'))], 1);
assert.equal(sha(fs.readFileSync(file('protected-input.json'))), sha(fixture));
fs.writeFileSync(file('protected-baseline.json'), header);
run([file('body.wasm'), '--baseline', file('protected-baseline.json'), '--experiment', path.relative(root, file('protected-baseline.json'))], 1);
assert.equal(sha(fs.readFileSync(file('protected-baseline.json'))), sha(header));
// Actual filesystem write error: parent does not exist.
invoke('missing-parent/report.json', 'empty.wasm', 'body.wasm', [], 1);
assert(!fs.existsSync(file('missing-parent/report.json')));
console.log(`Optimization experiments: ${cases} CLI scenarios passed; evidence ${dir}`);
