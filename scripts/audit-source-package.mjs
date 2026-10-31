// CI package-boundary validation, never a registry-consumer or publication step.
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';

const [sha, evidenceArg, ...extra] = process.argv.slice(2);
assert(/^[0-9a-f]{40}$/.test(sha || '') && evidenceArg && extra.length === 0,
  'Usage: node scripts/audit-source-package.mjs <full-source-commit> <new-evidence-directory>');
const repository = path.resolve(fileURLToPath(new URL('../', import.meta.url)));
const evidence = path.resolve(evidenceArg);
assert(!fs.existsSync(evidence), 'Evidence directory must be new');
fs.mkdirSync(evidence, {recursive: true});
if (process.env.GITHUB_OUTPUT) fs.appendFileSync(process.env.GITHUB_OUTPUT,
  'evidence_dir=' + path.relative(process.cwd(), evidence).split(path.sep).join('/') + '\n');
const digest = b => crypto.createHash('sha256').update(b).digest('hex');
const python = process.platform === 'win32' ? 'python' : 'python3';
const commands = [];
const result = {
  format: 'moonsize-source-package-audit', schema_version: 1, source_sha: sha,
  manifest_version: '0.5.1', published: false, registry_consumer: false,
  platform: process.platform, node: process.version, commands, passed: false,
};
let stage = 'source-identity';
function save() { fs.writeFileSync(path.join(evidence, 'results.json'), JSON.stringify(result, null, 2) + '\n'); }
function sourceInventory(root, relative = '') {
  const files = {};
  for (const entry of fs.readdirSync(path.join(root, relative), {withFileTypes: true})) {
    const name = relative ? relative + '/' + entry.name : entry.name;
    if (['_build', '.mooncakes', 'target', 'node_modules'].includes(name.split('/')[0])) continue;
    assert(!entry.isSymbolicLink(), 'Unexpected source link: ' + name);
    if (entry.isDirectory()) Object.assign(files, sourceInventory(root, name));
    else { const bytes = fs.readFileSync(path.join(root, name)); files[name] = {size: bytes.length, sha256: digest(bytes)}; }
  }
  return files;
}
function invoke(label, executable, args, cwd, expected = 0, timeout = 240000) {
  const p = spawnSync(executable, args, {cwd, shell: false, encoding: 'utf8', timeout, maxBuffer: 8 * 1024 * 1024});
  const prefix = String(commands.length).padStart(2, '0') + '-' + label;
  fs.writeFileSync(path.join(evidence, prefix + '.stdout.txt'), p.stdout || '', {flag: 'wx'});
  fs.writeFileSync(path.join(evidence, prefix + '.stderr.txt'), p.stderr || '', {flag: 'wx'});
  commands.push({stage, executable, argv: args, cwd, expected_status: expected,
    status: p.status, signal: p.signal, error: p.error?.message || null,
    timeout_ms: timeout, max_buffer_bytes: 8 * 1024 * 1024,
    stdout: prefix + '.stdout.txt', stderr: prefix + '.stderr.txt'});
  save();
  assert.ifError(p.error); assert.equal(p.signal, null, label + ': killed');
  assert.equal(p.status, expected, label + ': inspect the recorded stdout/stderr');
  return (p.stdout || '') + (p.stderr || '');
}
try {
  const resolved = invoke('resolve-source', 'git', ['rev-parse', '--verify', sha + '^{commit}'], repository).trim();
  assert.equal(resolved, sha);
  if (process.env.CI) assert.equal(sha, process.env.GITHUB_SHA, 'CI must audit its final GITHUB_SHA');
  result.toolchain = invoke('toolchain', 'moon', ['version', '--all'], repository).trim();
  const temp = fs.mkdtempSync(path.join(fs.realpathSync(os.tmpdir()), 'moonsize-package-audit-'));
  assert(!temp.startsWith(repository + path.sep), 'Clean export must be outside repository');
  result.temporary_directory = temp;
  const exportZip = path.join(temp, 'source-export.zip');
  const source = path.join(temp, 'source');
  const extracted = path.join(temp, 'package-extracted');
  stage = 'clean-source-export';
  invoke('git-archive', 'git', ['archive', '--format=zip', '--output=' + exportZip, sha], repository);
  result.source_archive_sha256 = digest(fs.readFileSync(exportZip));
  // Helper is committed alongside this script; the CI SHA check prevents drift.
  invoke('extract-source', python, [path.join(repository, 'scripts/audit-source-package.py'), 'extract', exportZip, source], repository);
  const committedFiles = sourceInventory(source);
  fs.writeFileSync(path.join(evidence, 'source-files.json'), JSON.stringify(committedFiles, null, 2) + '\n', {flag: 'wx'});
  const helper = path.join(source, 'scripts/audit-source-package.py');
  stage = 'package-list';
  invoke('package-list', 'moon', ['package', '--list'], source);
  stage = 'actual-package';
  invoke('moon-package', 'moon', ['package'], source);
  // Packaging must not redefine which bytes count as the committed baseline.
  assert.deepEqual(sourceInventory(source), committedFiles,
    'Packaging changed committed source bytes or generated unexplained root files');
  result.clean_source_bytes_preserved = true;
  const publish = path.join(source, '_build/publish');
  const packages = fs.readdirSync(publish).filter(f => f.endsWith('.zip'));
  assert.equal(packages.length, 1, 'Expected one actual generated package ZIP');
  const packageZip = path.join(publish, packages[0]);
  fs.copyFileSync(packageZip, path.join(evidence, 'package.zip'), fs.constants.COPYFILE_EXCL);
  result.package = {path: 'package.zip', generated_filename: packages[0], size: fs.statSync(packageZip).size, sha256: digest(fs.readFileSync(packageZip))};
  stage = 'zip-content-audit';
  invoke('audit-members', python, [helper, 'audit', source, packageZip, extracted, evidence], source);
  const members = JSON.parse(fs.readFileSync(path.join(evidence, 'members.json'), 'utf8'));
  assert.equal(members.passed, true, 'Actual ZIP content audit did not pass');
  result.members = {path: 'members.json', file_count: members.file_count,
    runtime_file_count: members.runtime_file_count,
    manifest_name: members.manifest_name, manifest_version: members.manifest_version};
  const packageRoot = path.resolve(members.package_root);
  assert(packageRoot === extracted || packageRoot.startsWith(extracted + path.sep), 'Package root outside extraction');
  stage = 'package-dependencies';
  invoke('package-update', 'moon', ['update'], packageRoot);
  stage = 'package-api-probe';
  const probe = path.join(packageRoot, '_package_audit_probe');
  fs.mkdirSync(probe);
  const probeSource = fs.readFileSync(path.join(packageRoot, 'scripts/source-package-probe.mbt.txt'));
  fs.writeFileSync(path.join(probe, 'main.mbt'), probeSource, {flag: 'wx'});
  fs.writeFileSync(path.join(probe, 'moon.pkg'), 'import { "BigSaltyMan/moonsize" @lib }\npkgtype(kind: "executable")\nsupported_targets = "+native"\n', {flag: 'wx'});
  fs.writeFileSync(path.join(evidence, 'api-probe-source.mbt.txt'), probeSource, {flag: 'wx'});
  const probeOutput = invoke('api-probe', 'moon', ['run', '--target', 'native', '_package_audit_probe'], packageRoot);
  const probeLine = probeOutput.split(/\r?\n/).find(s => s.startsWith('{"format":"moonsize-source-package-api-probe"'));
  assert(probeLine, 'Structured package API probe result missing');
  const probeReport = JSON.parse(probeLine);
  assert.equal(probeReport.status, 'passed');
  assert.deepEqual([probeReport.fixture_size, probeReport.functions, probeReport.local_encoded_bytes,
    probeReport.dependency_nodes, probeReport.dependency_edges, probeReport.dependent_nodes,
    probeReport.dependent_edges, probeReport.path_hops], [54,3,12,2,3,2,3,1]);
  fs.writeFileSync(path.join(evidence, 'api-probe.json'), JSON.stringify(probeReport, null, 2) + '\n', {flag: 'wx'});
  result.api_probe = {passed: true, source_sha256: digest(probeSource), log: commands.at(-1).stdout,
    identity: 'unpacked local package API probe, not public registry consumption'};
  // Preserve the owned probe outside the module before the one CLI release build.
  const preservedProbe = path.join(temp, 'validated-api-probe');
  assert(probe.startsWith(packageRoot + path.sep) && !fs.existsSync(preservedProbe));
  fs.renameSync(probe, preservedProbe);
  stage = 'package-cli-build';
  invoke('native-release-build', 'moon', ['build', '--target', 'native', '--release'], packageRoot);
  const cli = path.join(packageRoot, '_build/native/release/build/cmd/main/main.exe');
  result.cli = {sha256: digest(fs.readFileSync(cli)), size: fs.statSync(cli).size,
    source: 'actual ZIP extracted into a fresh external directory'};
  // Same fixed 54-byte fixture used by the package API probe. No V8 or execution.
  const fixture = Buffer.from('0061736d01000000010401600000020701016d01660000030302000007090105656e74727900010a0d0208001002100210010b02000b', 'hex');
  const smoke = path.join(evidence, 'smoke'); fs.mkdirSync(smoke);
  const wasm = path.join(smoke, 'fixture.wasm'); fs.writeFileSync(wasm, fixture, {flag: 'wx'});
  result.input = {size: fixture.length, sha256: digest(fixture)};
  stage = 'package-cli-smoke';
  const htmlPath = path.join(smoke, 'new.html'), dotPath = path.join(smoke, 'new.dot');
  invoke('cli-html', cli, [wasm, '--html', htmlPath], smoke);
  const html = fs.readFileSync(htmlPath, 'utf8');
  assert(/<!doctype html>/i.test(html) && /<html\b/i.test(html));
  assert(html.includes('ECharts') && html.includes('ECharts, styles, scripts and measured data are embedded'));
  assert(!/<script\b[^>]*\bsrc\s*=/i.test(html), 'External script dependency');
  const chartSource = fs.readFileSync(path.join(packageRoot, 'assets/echarts.min.js'), 'utf8');
  assert(html.includes(chartSource.replaceAll('</script', '<\\/script').replaceAll('</SCRIPT', '<\\/SCRIPT')),
    'Vendored ECharts source not inlined');
  invoke('cli-dependents-dot', cli, [wasm, '--dependents', '2', '--dependents-dot', dotPath], smoke);
  const dot = fs.readFileSync(dotPath);
  const text = dot.toString('utf8');
  assert(text.startsWith('digraph moonsize_dependents {'));
  assert.deepEqual(text.split('\n').filter(s => /^  fn_\d+ \[/.test(s)).map(s => Number(s.match(/fn_(\d+)/)[1])), [1,2]);
  assert.deepEqual(text.split('\n').filter(s => /^  fn_\d+ ->/.test(s)), [
    '  fn_1 -> fn_2 [style=solid, label="direct; file offset 44"];',
    '  fn_1 -> fn_2 [style=solid, label="direct; file offset 46"];',
    '  fn_1 -> fn_1 [style=solid, label="direct; file offset 48"];',
  ]);
  const refused = invoke('cli-existing-dot', cli, [wasm, '--dependents', '2', '--dependents-dot', dotPath], smoke, 1);
  assert(refused.includes('output already exists') && !refused.includes('DOT written to'));
  assert(fs.readFileSync(dotPath).equals(dot), 'Existing DOT changed');
  assert(fs.readFileSync(wasm).equals(fixture), 'Input changed');
  result.smoke = {passed: true, exit_codes: [0,0,1], inline_echarts: true, exclusive_output_preserved: true,
    html_sha256: digest(Buffer.from(html)), dot_sha256: digest(dot)};
  result.passed = true; stage = 'complete'; save();
  console.log('Source-package audit passed: ' + evidence);
} catch (error) {
  result.failed_stage = stage; result.error = error.stack || String(error);
  result.failure_kind = stage === 'zip-content-audit' ? 'package-content-or-safety' :
    /download|ENOTFOUND|ECONN|timed out|network|registry/i.test(error.message) ? 'network-or-dependency' : 'stage-command-or-contract';
  save(); console.error('Source-package audit failed at ' + stage + ': ' + error.message); process.exitCode = 1;
}
