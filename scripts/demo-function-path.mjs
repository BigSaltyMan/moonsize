// Rebuild one isolated MoonBit project, discover indices, query, change and roll back.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';

const repo = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const cli = path.resolve(process.argv[2] || '_build/native/release/build/cmd/main/main.exe');
const out = path.join(repo, '_build/function-path-demo');
fs.mkdirSync(out, {recursive: true});
fs.writeFileSync(path.join(out, 'run.log'), 'Function-path rebuild and query evidence\n');
const sha = data => crypto.createHash('sha256').update(data).digest('hex');
function run(command, args, cwd = repo) {
  const r = spawnSync(command, args, {cwd, encoding: 'utf8', timeout: 60000, maxBuffer: 16 * 1024 * 1024});
  fs.appendFileSync(path.join(out, 'run.log'), JSON.stringify({command, args, cwd,
    status: r.status, stdout: r.stdout, stderr: r.stderr}) + '\n');
  assert(!r.error && !r.signal && r.status === 0,
    `${command} ${args.join(' ')}: ${r.error || r.signal || r.status}\n${r.stdout || ''}\n${r.stderr || ''}`);
  return r.stdout;
}
function fresh(name) {
  const file = path.join(out, name);
  assert.equal(path.dirname(file), out);
  if (fs.existsSync(file)) fs.unlinkSync(file);
  return file;
}
const beforeSource = `///|
#inline(never)
fn path_target(n : Int) -> String {
  if n % 2 == 0 { "optional explanation: even" } else { "optional explanation: odd" }
}

///|
#inline(never)
fn path_upstream(n : Int) -> Unit {
  println("base: " + n.to_string())
  println(path_target(n))
}

///|
fn main {
  for n in 0..<4 { path_upstream(n) }
}
`;
const afterSource = beforeSource.replace('  println(path_target(n))\n', '');
fs.writeFileSync(path.join(out, 'moon.mod'), 'name = "demo/functionpath"\n');
fs.writeFileSync(path.join(out, 'moon.pkg'), 'pkgtype(kind: "executable")\n');
const toolchain = run('moon', ['version', '--all']).trim();
const measurements = {};
for (const variant of ['before', 'after', 'rollback']) {
  const source = variant === 'after' ? afterSource : beforeSource;
  fs.writeFileSync(path.join(out, 'main.mbt'), source);
  fs.writeFileSync(path.join(out, `${variant}.mbt` + '.txt'), source);
  run('moon', ['build', '--target', 'wasm', '--debug', '--no-strip'], out);
  const artifact = path.join(out, '_build/wasm/debug/build/functionpath.wasm');
  assert(fs.statSync(artifact).size > 0);
  const file = path.join(out, `${variant}.wasm`);
  fs.copyFileSync(artifact, file);
  assert(WebAssembly.validate(fs.readFileSync(file)), 'V8 rejected the rebuilt source artifact');
  const stdout = run('moonrun', [file]);
  fs.writeFileSync(path.join(out, `${variant}.stdout.txt`), stdout);
  const graphFile = fresh(`${variant}.graph.json`);
  run(cli, [file, '--call-graph', graphFile]);
  const graph = JSON.parse(fs.readFileSync(graphFile));
  const targets = graph.functions.filter(f => /path_+target/.test(f.name));
  if (variant === 'after') {
    assert.equal(targets.length, 0, 'Removed target is still emitted');
  } else {
    assert.equal(targets.length, 1, 'Target must have one emitted symbol');
    const target = targets[0].index;
    const defaultFile = fresh(`${variant}.default-path.json`);
    run(cli, [file, '--why-index', String(target), '--why-json', defaultFile]);
    const defaultPath = JSON.parse(fs.readFileSync(defaultFile));
    // Discover a real export root from the actual module, never compiler indices.
    const roots = defaultPath.model_roots.filter(r => r.reasons.some(s => s.kind === 'export'));
    let selected;
    for (const root of roots) {
      const candidateFile = fresh(`${variant}.root-${root.index}.json`);
      run(cli, [file, '--why-index', String(target), '--why-root', String(root.index), '--why-json', candidateFile]);
      const candidate = JSON.parse(fs.readFileSync(candidateFile));
      if (candidate.status === 'found' && candidate.nodes.some(n => /path_+upstream/.test(n.name))) {
        selected = candidate;
        fs.copyFileSync(candidateFile, path.join(out, `${variant}.path.json`));
        break;
      }
    }
    assert(selected, 'No actual exported entry reaches upstream and target');
    assert(selected.steps.every(s => Number.isInteger(s.offset) && s.opcode));
    fs.writeFileSync(path.join(out, `${variant}.path.txt`), run(cli,
      [file, '--why-index', String(target), '--why-root', String(selected.path_root)]));
  }
  measurements[variant] = {sha256: sha(fs.readFileSync(file)), bytes: fs.statSync(file).size,
    source_sha256: sha(source), stdout};
}
assert.deepEqual(measurements.rollback, measurements.before, 'Rollback must restore bytes, source and behavior');
const beforePath = JSON.parse(fs.readFileSync(path.join(out, 'before.path.json')));
const rollbackPath = JSON.parse(fs.readFileSync(path.join(out, 'rollback.path.json')));
assert.deepEqual(rollbackPath, beforePath, 'Rollback must restore actual indices, offsets and root explanations');
assert.equal(measurements.after.stdout, measurements.before.stdout.split(/(?<=\n)/)
  .filter(line => line.startsWith('base: ')).join(''));
const build = {command: 'moon build --target wasm --debug --no-strip', toolchain,
  target: 'wasm', mode: 'debug', strip: false, features: []};
const context = {title: 'Remove the upstream reference to path_target',
  hypothesis: 'Remove optional output at its upstream call, rebuild and measure complete artifacts.',
  baseline: {...build, revision: measurements.before.source_sha256},
  current: {...build, revision: measurements.after.source_sha256},
  validation: {status: 'passed', command: 'node scripts/demo-function-path.mjs',
    notes: 'Base output is unchanged. Optional output is intentionally removed; this is not full behavioral equivalence. Rollback restores exact Wasm bytes and the complete path report.'}};
const contextFile = path.join(out, 'experiment-context.json');
fs.writeFileSync(contextFile, JSON.stringify(context, null, 2) + '\n');
for (const ext of ['json', 'html']) {
  run(cli, [path.join(out, 'after.wasm'), '--baseline', path.join(out, 'before.wasm'),
    '--experiment', fresh(`experiment.${ext}`), '--experiment-context', contextFile]);
}
const experiment = JSON.parse(fs.readFileSync(path.join(out, 'experiment.json')));
assert.equal(experiment.baseline.sha256, measurements.before.sha256);
assert.equal(experiment.current.sha256, measurements.after.sha256);
assert.equal(experiment.raw_delta, measurements.after.bytes - measurements.before.bytes);
assert.equal(experiment.build_comparability, 'same-declared-settings');
const evidence = {toolchain, cli_sha256: sha(fs.readFileSync(cli)),
  target_index: beforePath.target.index, selected_root: beforePath.path_root,
  path: beforePath.nodes.map(n => ({index: n.index, name: n.name})),
  measurements, raw_delta: experiment.raw_delta, whole_gzip_delta: experiment.whole_gzip_delta,
  interpretation: 'Model reference path, not execution. Savings are whole-artifact rebuild measurements, never sums of path bytes.'};
fs.writeFileSync(path.join(out, 'results.json'), JSON.stringify(evidence, null, 2) + '\n');
console.log(`Function-path source demo passed: ${beforePath.steps.length} edges; rebuilt raw delta ${experiment.raw_delta}, whole-gzip delta ${experiment.whole_gzip_delta}; exact rollback.`);
console.log('Evidence: ' + out);
