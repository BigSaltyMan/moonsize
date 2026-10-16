// Rebuild source pairs and measure model bytes, actual Wasm bytes and whole-file gzip.
// All generated projects/reports stay under _build/retained-boundaries; no source is deleted.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import assert from 'node:assert/strict';

const repo = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const cli = path.resolve(process.argv[2] || path.join(repo, '_build/native/release/build/cmd/main/main.exe'));
assert(fs.existsSync(cli), 'Build the native CLI before running this demo.');
const out = path.join(repo, '_build/retained-boundaries');
fs.mkdirSync(out, {recursive: true});
const sha = b => crypto.createHash('sha256').update(b).digest('hex');
function run(command, args, cwd = repo, expected = 0) {
  const r = spawnSync(command, args, {cwd, encoding: 'utf8', timeout: 120000, maxBuffer: 16 * 1024 * 1024});
  if (r.error || r.signal || r.status !== expected) {
    throw new Error(`${command} ${args.join(' ')}: ${r.error || r.signal || r.status}\n${r.stdout || ''}\n${r.stderr || ''}`);
  }
  return r.stdout;
}
function measure(file) {
  const bytes = fs.readFileSync(file);
  assert(WebAssembly.validate(bytes), `${file} is not a valid Wasm module for this V8`);
  const jsonPath = file + '.graph.json';
  run(cli, [file, '--call-graph', jsonPath]);
  const graph = JSON.parse(fs.readFileSync(jsonPath, 'utf8'));
  const text = run(cli, [file, '--compress', '--retained', '--dead-code', '--top', '1000000']);
  fs.writeFileSync(file + '.report.txt', text);
  const gzip = text.match(/^\s*gzip\s+(\d+)\s+B/m);
  assert(gzip, 'Whole-file gzip measurement missing');
  const sectionRows = [...text.matchAll(/^\s+(.+?)\s+(\d+)\s+(\d+)\s+([0-9.]+x)\s*$/gm)];
  const sum = sectionRows.reduce((n, r) => n + Number(r[3]), 0);
  assert(sectionRows.length > 0, 'Independent section measurements missing');
  const strictStatus = graph.graph_complete ? 0 : 3;
  run(cli, [file, '--strict', '--top', '0'], repo, strictStatus);
  return {bytes: bytes.length, sha256: sha(bytes), gzip: Number(gzip[1]), independent_section_gzip_sum: sum,
    graph_complete: graph.graph_complete, diagnostic_count: graph.diagnostics.length, strict_exit: strictStatus, graph};
}
const results = [];
function compare(name, before, after, provenance, mode) {
  const b = measure(before), a = measure(after);
  fs.writeFileSync(after + '.comparison.txt', run(cli, [after, '--baseline', before, '--top', '0']));
  const targets = b.graph.functions.filter(f => /boundary_+target/.test(f.name));
  assert.equal(targets.length, 1, name + ': target must be preserved and uniquely named');
  const target = targets[0];
  assert.equal(typeof target.retained, 'number');
  assert(!a.graph.functions.some(f => /boundary_+target/.test(f.name)), name + ': target still emitted after removal');
  if (name.startsWith('shared')) {
    assert(a.graph.functions.some(f => /boundary_+shared/.test(f.name)), 'Shared dependency disappeared');
    const shared = b.graph.functions.find(f => /boundary_+shared/.test(f.name));
    assert(shared);
    assert.equal(target.retained, target.size, 'Shared dependency must not be charged to target retention');
  }
  const entry = {case: name, provenance, mode, target_name: target.name, target_index: target.index,
    own_bytes: target.size, model_retained_bytes: target.retained,
    model_other_functions: target.retained_functions,
    before: {...b, graph: undefined}, after: {...a, graph: undefined},
    measured_raw_reduction: b.bytes - a.bytes, measured_whole_gzip_reduction: b.gzip - a.gzip};
  results.push(entry);
  // Package the same measured experiment through the reusable product API.
  // The declarations below record checks this script actually performed; the
  // report still labels them as caller-supplied, rather than claiming it ran them.
  const work = path.dirname(before);
  const sourceRebuild = mode !== 'binary-control';
  const kind = name.startsWith('shared') ? 'shared' : 'unique';
  const sourceRevision = variant => sourceRebuild
    ? sha(fs.readFileSync(path.join(repo, 'examples/retained-boundaries', `${kind}-${variant}.mbt`)))
    : sha(fs.readFileSync(variant === 'before' ? before : after));
  const build = {command: sourceRebuild ? `moon build --target wasm --${mode} --no-strip` : 'node scripts/demo-retained-boundaries.mjs (hand-encoded control)',
    toolchain: sourceRebuild ? versions.trim() : `Node ${process.version}, V8 ${process.versions.v8}`,
    target: 'wasm', mode, strip: false, features: []};
  const context = {title: `Optimization experiment: ${name}`, hypothesis: provenance,
    baseline: {...build, revision: sourceRevision('before')}, current: {...build, revision: sourceRevision('after')},
    validation: {status: 'passed', command: 'node scripts/demo-retained-boundaries.mjs',
      notes: sourceRebuild ? 'Base output is preserved; optional output is intentionally removed. Rollback restores exact Wasm bytes and complete output. This is not full behavioral equivalence.' : 'Both exported run() results equal 42. Hand-encoded binary control, not a source rebuild.'}};
  const contextPath = path.join(work, 'experiment-context.json');
  fs.writeFileSync(contextPath, JSON.stringify(context, null, 2) + '\n');
  for (const ext of ['json', 'html']) {
    const reportPath = path.join(work, `experiment.${ext}`);
    // Only this demo's named generated output is replaced on a rerun. The CLI
    // itself always refuses an existing path.
    assert(reportPath.startsWith(out + path.sep));
    if (fs.existsSync(reportPath)) fs.unlinkSync(reportPath);
    run(cli, [path.relative(repo, after), '--baseline', path.relative(repo, before), '--experiment', reportPath,
      '--experiment-context', contextPath, '--top', '20']);
  }
  const experiment = JSON.parse(fs.readFileSync(path.join(work, 'experiment.json'), 'utf8'));
  assert.equal(experiment.raw_delta, -entry.measured_raw_reduction);
  assert.equal(experiment.whole_gzip_delta, -entry.measured_whole_gzip_reduction);
  assert.equal(experiment.baseline.sha256, b.sha256);
  assert.equal(experiment.current.sha256, a.sha256);
  assert.equal(experiment.build_comparability, 'same-declared-settings');
  entry.experiment_report = path.relative(repo, path.join(work, 'experiment.html')).replaceAll('\\', '/');
  console.log(`${name}: R=${entry.model_retained_bytes}, Wasm reduction=${entry.measured_raw_reduction}, whole-gzip reduction=${entry.measured_whole_gzip_reduction}; diagnostics=${b.diagnostic_count}`);
}

const versions = run('moon', ['version', '--all']);
for (const mode of ['debug', 'release']) {
  for (const kind of ['unique', 'shared']) {
    const work = path.join(out, `${kind}-${mode}`);
    fs.mkdirSync(work, {recursive: true});
    fs.writeFileSync(path.join(work, 'moon.mod'), 'name = "demo/retainedboundaries"\n');
    fs.writeFileSync(path.join(work, 'moon.pkg'), 'pkgtype(kind: "executable")\n');
    for (const variant of ['before', 'after', 'rollback']) {
      const sourceVariant = variant === 'rollback' ? 'before' : variant;
      fs.copyFileSync(path.join(repo, 'examples/retained-boundaries', `${kind}-${sourceVariant}.mbt`), path.join(work, 'main.mbt'));
      run('moon', ['build', '--target', 'wasm', `--${mode}`, '--no-strip'], work);
      const artifact = path.join(work, '_build/wasm', mode, 'build/retainedboundaries.wasm');
      fs.copyFileSync(artifact, path.join(work, `${variant}.wasm`));
      fs.writeFileSync(path.join(work, `${variant}.stdout.txt`), run('moonrun', [path.join(work, `${variant}.wasm`)]));
    }
    assert(fs.readFileSync(path.join(work, 'before.wasm')).equals(fs.readFileSync(path.join(work, 'rollback.wasm'))), 'Rollback did not restore exact bytes');
    const lines = variant => fs.readFileSync(path.join(work, `${variant}.stdout.txt`), 'utf8').trim().split(/\r?\n/);
    assert.deepEqual(lines('rollback'), lines('before'));
    assert.deepEqual(lines('after'), kind === 'unique' ? lines('before').filter(s => s.startsWith('base: ')) : lines('before').filter((_, i) => i % 2 === 0), 'Base output changed');
    compare(`${kind}-${mode}`, path.join(work, 'before.wasm'), path.join(work, 'after.wasm'), 'MoonBit source rebuild; same project path, toolchain and flags; optional call removed', mode);
  }
}

// A separately labelled, hand-encoded Core Wasm control: an unused private table
// makes its element function a conservative root even though run() never calls it.
const u32 = n => {const a = []; do {let b = n & 127; n >>>= 7; if (n) b |= 128; a.push(b);} while (n); return a;};
const section = (id, bytes) => [id, ...u32(bytes.length), ...bytes];
const str = s => {const b = [...Buffer.from(s)]; return [...u32(b.length), ...b];};
function control(withTable) {
  const names = [withTable ? 2 : 1, 0, ...str('entry'), ...(withTable ? [1, ...str('boundary_target')] : [])];
  return Buffer.from([0,97,115,109,1,0,0,0,
    ...section(1, [1,0x60,0,1,0x7f]),
    ...section(3, withTable ? [2,0,0] : [1,0]),
    ...(withTable ? section(4, [1,0x70,0,1]) : []),
    ...section(7, [1, ...str('run'), 0,0]),
    ...(withTable ? section(9, [1,0,0x41,0,0x0b,1,1]) : []),
    ...section(10, [withTable ? 2 : 1,4,0,0x41,42,0x0b, ...(withTable ? [4,0,0x41,7,0x0b] : [])]),
    ...section(0, [...str('name'),1,...u32(names.length),...names])]);
}
const synthetic = path.join(out, 'conservative-table-control');
fs.mkdirSync(synthetic, {recursive: true});
for (const [name, table] of [['before', true], ['after', false]]) {
  const b = control(table);
  assert.equal(new WebAssembly.Instance(new WebAssembly.Module(b)).exports.run(), 42);
  fs.writeFileSync(path.join(synthetic, name + '.wasm'), b);
}
compare('conservative-table-control', path.join(synthetic, 'before.wasm'), path.join(synthetic, 'after.wasm'), 'Hand-encoded Wasm control; NOT a MoonBit recompile; identical exported run() result', 'binary-control');
const controlResult = results.at(-1);
assert.equal(controlResult.before.graph_complete, true);
assert.equal(controlResult.model_retained_bytes, 5);
assert.notEqual(controlResult.model_retained_bytes, controlResult.measured_raw_reduction);
assert(results.some(r => r.provenance.startsWith('MoonBit') && r.model_retained_bytes !== r.measured_raw_reduction));
// A valid, executable runtime-written table: known callee, but the static model
// does not solve table data flow. This is a refusal-policy case, not a saving claim.
const dynamic = Buffer.from([0,97,115,109,1,0,0,0,
  ...section(1,[1,0x60,0,1,0x7f]), ...section(3,[2,0,0]),
  ...section(4,[1,0x70,0,1]), ...section(7,[1,...str('run'),0,0]),
  ...section(9,[1,3,0,1,1]),
  ...section(10,[2,13,0,0x41,0,0xd2,1,0x26,0,0x41,0,0x11,0,0,0x0b,4,0,0x41,7,0x0b])]);
assert.equal(new WebAssembly.Instance(new WebAssembly.Module(dynamic)).exports.run(),7);
const dynamicFile = path.join(synthetic,'runtime-table.wasm');
fs.writeFileSync(dynamicFile,dynamic);
const dynamicMeasurement = measure(dynamicFile);
assert.equal(dynamicMeasurement.graph_complete,false);
assert.equal(dynamicMeasurement.strict_exit,3);
const policyCases = [{case:'runtime-table-write', ...dynamicMeasurement,
  reason_codes:dynamicMeasurement.graph.diagnostics.map(d=>d.code), graph:undefined,
  interpretation:'Valid executable module; strict refuses the unsolved table model. No removal saving is claimed.'}];
const tracked = run('git', ['ls-files', '--cached', '--others', '--exclude-standard', '-z']).split('\0').filter(p => /\.(mbt|pkg|mod)$/.test(p));
const sourceHash = crypto.createHash('sha256');
for (const f of tracked.sort()) {sourceHash.update(f); sourceHash.update(fs.readFileSync(path.join(repo, f)));}
const report = {base_commit: run('git', ['rev-parse', 'HEAD']).trim(),
  working_tree_is_dirty: run('git', ['status', '--porcelain']).length > 0,
  analyzed_source_sha256: sourceHash.digest('hex'), cli_sha256: sha(fs.readFileSync(cli)),
  script_sha256: sha(fs.readFileSync(fileURLToPath(import.meta.url))),
  platform: process.platform, arch: process.arch, node: process.version, toolchain: versions.trim(),
  source_sha256: Object.fromEntries(['unique-before','unique-after','shared-before','shared-after'].map(n=>[n,sha(fs.readFileSync(path.join(repo,'examples/retained-boundaries',n+'.mbt')))])),
  results, policy_cases:policyCases};
fs.writeFileSync(path.join(out, 'results.json'), JSON.stringify(report, null, 2) + '\n');
console.log('Evidence and raw reports: ' + out);
