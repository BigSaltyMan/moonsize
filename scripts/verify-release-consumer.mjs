// Install an exact public Mooncakes version in a fresh, repository-external
// consumer. No local path dependency or copied implementation is permitted.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import crypto from 'node:crypto';
import {spawnSync} from 'node:child_process';

const version = process.argv[2];
if (!/^0\.\d+\.\d+$/.test(version ?? '')) {
  throw Error('Usage: node scripts/verify-release-consumer.mjs 0.x.y [evidence.json]');
}
const cwd = fs.mkdtempSync(path.join(os.tmpdir(), 'moonsize-public-consumer-'));
function moon(args) {
  const p = spawnSync('moon', args, {cwd, encoding: 'utf8', timeout: 240000});
  if (p.error || p.status !== 0) throw Error(`${args.join(' ')}: ${p.error ?? ''}\n${p.stdout}\n${p.stderr}`);
  return p.stdout + p.stderr;
}
fs.writeFileSync(path.join(cwd, 'moon.mod'), 'name = "review/releaseconsumer"\nversion = "0.1.0"\n');
fs.writeFileSync(path.join(cwd, 'moon.pkg'), 'import { "BigSaltyMan/moonsize" }\npkgtype(kind: "executable")\nsupported_targets = "+native"\n');
// Keep the public 0.4 consumer usable; newer APIs must not enter its source.
const withData = Number(version.split('.')[1]) >= 5;
const dataSource = withData ? `
  let data_module : Bytes = [0,97,115,109,1,0,0,0,5,3,1,0,1,12,1,3,11,20,3,0,65,11,11,3,97,98,99,1,0,2,0,65,0,11,3,120,121,122]
  let details = match @moonsize.inspect_data_segments(data_module) { Ok(r) => r; Err(e) => abort(@moonsize.describe_error(e)) }
  guard details.entries.length() == 3 && details.section_size == 22 else { abort("data entries") }
  guard details.section_size == details.payload_size + details.entry_metadata_size + details.header_size + details.count_size else { abort("data ledger") }
  let compared = match @moonsize.compare_data_segments(data_module, data_module) { Ok(r) => r; Err(_) => abort("data self comparison") }
  guard compared.delta.section_size == 0 && compared.delta.payload_size == 0 && compared.delta.entry_metadata_size == 0 && compared.delta.section_overhead_size == 0 else { abort("data self delta") }
  let data_parsed = match @moonsize.parse_module(data_module) { Ok(r) => r; Err(e) => abort(@moonsize.describe_error(e)) }
  let data_analysis = match @moonsize.analyze(data_module, data_parsed) { Ok(r) => r; Err(e) => abort(@moonsize.describe_error(e)) }
  let html = @moonsize.render_html_with_data_segments(data_analysis, "consumer.wasm", details, echarts="/* consumer stub; no browser assertion */")
  guard html.contains("dataSegments") && html.contains("not_evaluated") else { abort("HTML data entry point") }
` : '';
const source = `fn main {
  // Complete 39-byte module: exported 0 tail-calls local 1.
  let data : Bytes = [0,97,115,109,1,0,0,0,1,4,1,96,0,0,3,3,2,0,0,7,7,1,3,114,117,110,0,0,10,9,2,4,0,18,1,11,2,0,11]
  let parsed = match @moonsize.parse_module(data) { Ok(p) => p; Err(e) => abort(@moonsize.describe_error(e)) }
  let analysis = match @moonsize.analyze(data, parsed) { Ok(a) => a; Err(e) => abort(@moonsize.describe_error(e)) }
  guard analysis.stats.length() == 2 && analysis.reachable.contains(1) else { abort("parse/stat/tail-call regression") }
  guard analysis.stats[0].total_size == 5 && analysis.stats[1].total_size == 3 else { abort("encoded ranges") }
  let graph = match @moonsize.build(data) { Ok(g) => g; Err(e) => abort(@moonsize.describe_error(e)) }
  guard @moonsize.is_graph_complete(graph) else { abort("unexpected gap") }
  let query = match @moonsize.explain_function(data, 1, root=0) { Ok(q) => q; Err(e) => abort(@moonsize.describe_function_path_error(e)) }
  match query.status { PathFound => (); _ => abort("path missing") }
  guard query.steps.length() == 1 else { abort("path edges") }
  guard query.steps[0].opcode.name() == "return_call" else { abort("path opcode") }
  for (limit, expected) in [(39, 0), (0, 3)] {
    let config = "{\\"version\\":1,\\"rules\\":[{\\"id\\":\\"raw\\",\\"metric\\":\\"file.raw\\",\\"mode\\":\\"absolute\\",\\"max_bytes\\":\\{limit}}]}"
    let budget = match @moonsize.compile_budget_text(config) { Ok(b) => b; Err(_) => abort("compile budget") }
    let report = match @moonsize.evaluate_budget(budget, data) { Ok(r) => r; Err(e) => abort(@moonsize.describe_budget_error(e)) }
    guard report.exit_code == expected else { abort("budget result") }
  }
  let changes = match @moonsize.compare_modules(data, data) { Ok(d) => d; Err(_) => abort("diff") }
  ignore(@moonsize.render_function_diff(changes, 10))
  let experiment = match @moonsize.experiment_report(data, data, "before.wasm", "after.wasm", Json::null()) { Ok(r) => r; Err(e) => abort(e) }
  ignore(@moonsize.render_experiment_html(experiment))
  ignore(@moonsize.render_function_path_json(query))
  ignore(@moonsize.Options::default("app.wasm"))
${dataSource}
  println("public consumer: parse/stat/build/path/diff/experiment/budget 0/3 passed")
}
`;
fs.writeFileSync(path.join(cwd, 'main.mbt'), source);
const add = moon(['add', `BigSaltyMan/moonsize@${version}`]);
const modulePath = path.join(cwd, '.mooncakes/BigSaltyMan/moonsize');
const manifest = fs.readFileSync(path.join(modulePath, 'moon.mod'), 'utf8');
if (!manifest.includes(`version = "${version}"`)) throw Error('Resolved a different version');
const log = [add, moon(['check', '--target', 'native', '--deny-warn']), moon(['run', '--target', 'native', '.'])].join('\n');
if (!log.includes('public consumer:')) throw Error('Consumer did not execute');
const result = {
  version, package: `BigSaltyMan/moonsize@${version}`, source: 'public Mooncakes dependency, no local override',
  toolchain: moon(['version', '--all']).trim(), platform: process.platform,
  source_sha256: crypto.createHash('sha256').update(source).digest('hex'),
  cases: ['parse/stat', 'safe build', 'tail-call path with real opcode', 'function/package diff', 'experiment', 'budget passed 0', 'budget exceeded 3', 'Options constructor', ...(withData ? ['data ledger', 'data self comparison', 'HTML data entry point'] : [])],
  status: 'passed', output: log.trim(),
};
if (process.argv[3]) fs.writeFileSync(process.argv[3], JSON.stringify(result, null, 2) + '\n');
console.log(JSON.stringify({version, status: result.status, cwd, cases: result.cases}));
