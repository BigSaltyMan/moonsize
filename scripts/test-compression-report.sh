#!/usr/bin/env bash
# Legal CLI fixtures plus execution of the report's own chart formatters in Node.
set -euo pipefail
if [[ $# -ne 1 || ! -f "$1" || ! -x "$1" ]]; then
  echo 'usage: bash scripts/test-compression-report.sh /path/to/moonsize-cli' >&2
  exit 1
fi
command -v node >/dev/null || { echo 'Node.js is required.' >&2; exit 1; }
cli=$(cd -- "$(dirname -- "$1")" && printf '%s/%s' "$PWD" "$(basename -- "$1")")
work_dir=$(mktemp -d)
cleanup() { rm -f -- "$work_dir/"*; rmdir -- "$work_dir"; }
trap cleanup EXIT
node - "$cli" "$work_dir" <<'JS'
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const { spawnSync } = require('node:child_process');
const [cli, dir] = process.argv.slice(2);
let cases = 0;
const leb = n => { const a = []; do { const b = n & 127; n >>>= 7; a.push(b | (n ? 128 : 0)); } while (n); return a; };
const header = [0, 97, 115, 109, 1, 0, 0, 0];
const section = (id, payload) => [id, ...leb(payload.length), ...payload];
const custom = (name, payload = []) => section(0, [...leb(Buffer.byteLength(name)), ...Buffer.from(name), ...payload]);
const minimal = [...header, ...section(1, [1, 96, 0, 0]), ...section(3, [1, 0]), ...section(10, [1, 2, 0, 11])];
const repeated = custom('x', [...Buffer.from('abcabc')]);
const fixtures = [
  ['empty', header],
  ['minimal', minimal],
  ['small', [...header, ...custom('x')]],
  ['multiple', [...header, ...custom('a', [1]), ...custom('b', [2, 3])]],
  ['same-name', [...header, ...repeated, ...repeated, ...repeated]],
  ['large', [...minimal, ...custom('repeated', Array(2048).fill(65))]],
  ['tail', [...Buffer.from('0061736d0100000001040160000003030200000707010372756e00000a0902040012010b02000b', 'hex')]],
];
const names = {1:'type', 3:'function', 7:'export', 10:'code'};
// Independently read the assembled fixture's encoded ranges, including prefixes.
function ranges(bytes) {
  let at = 8;
  const read = () => { let value = 0, shift = 0, b; do { b = bytes[at++]; value += (b & 127) * 2 ** shift; shift += 7; } while (b & 128); return value; };
  const sections = [], functions = [];
  while (at < bytes.length) {
    const start = at, id = bytes[at++], length = read(), payload = at, end = at + length;
    let name = names[id];
    if (id === 0) { const n = read(); name = `custom (${bytes.subarray(at, at + n).toString('utf8')})`; }
    sections.push({ name, total: end - start, payload: length });
    if (id === 10) {
      at = payload;
      const count = read();
      for (let i = 0; i < count; i++) { const offset = at, bodySize = read(); functions.push({ offset, bodySize, size: at - offset + bodySize }); at += bodySize; }
      assert.equal(at, end);
    }
    at = end;
  }
  return { sections: sections.sort((a,b) => b.total - a.total), functions };
}
function run(args) {
  const result = spawnSync(cli, args, { encoding: 'utf8', timeout: 5000 });
  assert.ifError(result.error);
  assert.equal(result.signal, null);
  assert.equal(result.status, 0, result.stdout + result.stderr);
  cases++;
  return result.stdout;
}
function charts(script) {
  const options = {}, elements = {};
  const context = vm.createContext({
    document: { getElementById(id) { return elements[id] ??= { id, style: {} }; } },
    window: { addEventListener() {} },
    echarts: { init(element) { return { setOption(option) { options[element.id] = option; } }; } },
  });
  vm.runInContext(script + '\nglobalThis.formatBytes = BYTES;', context, { timeout: 1000 });
  return { options, context };
}
let checkedErrors = false;
for (const [name, raw] of fixtures) {
  const bytes = Buffer.from(raw), file = path.join(dir, name + '.wasm');
  assert.ok(WebAssembly.validate(bytes), `V8 rejected ${name}`);
  fs.writeFileSync(file, bytes);
  const expected = ranges(bytes);
  const text = run([file, '--compress']);
  assert.ok(!text.includes('SHARE(GZIP)'));
  assert.ok(text.includes('BY SECTION — INDEPENDENT GZIP STREAMS'));
  assert.ok(text.includes('not additive'));
  const whole = text.match(/^\s+gzip\s+(\d+) B\s+\((\d+\.\d+)% of raw, ratio ([\d.]+x)\)/m);
  assert.ok(whole, text);
  const gzip = Number(whole[1]);
  assert.equal(whole[2], (Math.trunc(gzip / bytes.length * 1000) / 10).toFixed(1));
  const rows = [...text.matchAll(/^  (.+?)\s+(\d+)\s+(\d+)\s+([\d.]+x)\s*$/gm)];
  assert.equal(rows.length, expected.sections.length);
  for (const [i, row] of rows.entries()) {
    assert.equal(row[1], expected.sections[i].name);
    assert.equal(Number(row[2]), expected.sections[i].total);
    assert.equal(row[4], (Math.trunc(Number(row[2]) / Number(row[3]) * 100) / 100).toFixed(2) + 'x');
  }
  for (const flag of [[], ['--compress']]) {
    const htmlPath = path.join(dir, name + (flag.length ? '-combined' : '') + '.html');
    run([file, ...flag, '--html', htmlPath]);
    const html = fs.readFileSync(htmlPath, 'utf8');
    assert.ok(html.includes('>Whole-file gzip<'));
    assert.ok(html.includes('Each section is compressed separately. These sizes are not additive and do not represent whole-file transfer shares.'));
    assert.ok(html.includes('independent gzip'));
    const script = [...html.matchAll(/<script>([\s\S]*?)<\/script>/g)].map(m => m[1]).find(s => s.includes('const DATA = '));
    const dataText = script.match(/const DATA = (.*);\r?\n/)[1];
    const data = JSON.parse(dataText);
    assert.equal(data.gzipSize, gzip);
    assert.equal(data.gzipError, null);
    assert.ok(data.compression_scope.includes('size, not bodySize'));
    assert.equal(data.sections.length, rows.length);
    for (const [i, row] of data.sections.entries()) {
      assert.equal(row.name, expected.sections[i].name);
      assert.equal(row.total, expected.sections[i].total);
      assert.equal(row.gzip, Number(rows[i][3]));
      assert.equal(row.gzipError, null);
    }
    for (const f of data.functions) {
      assert.equal(f.size, expected.functions[f.index].size);
      assert.equal(f.bodySize, expected.functions[f.index].bodySize);
      assert.equal(typeof f.gzip, 'number');
      assert.equal(f.gzipError, null);
      const leaf = data.modules.flatMap(m => m.children).find(c => c.name === f.name && c.value === f.size && c.gzip === f.gzip);
      assert.equal(leaf.value, f.size);
      assert.equal(leaf.gzip, f.gzip);
      assert.equal(leaf.gzipError, null);
    }
    if (name === 'small') { assert.ok(data.sections[0].gzip > data.sections[0].total); assert.match(rows[0][4], /^0\./); }
    if (name === 'same-name') assert.notEqual(data.sections.reduce((sum, s) => sum + s.gzip, 0), data.gzipSize);
    const { options, context } = charts(script);
    assert.equal(context.formatBytes(null), 'failed');
    assert.equal(context.formatBytes(undefined), 'failed');
    if (data.sections.length) {
      assert.equal(options.sections.legend.data[1], 'independent gzip');
      assert.equal(options.sections.series[1].data[0], data.sections[0].gzip);
    }
    if (data.functions.length) {
      const f = data.functions[0];
      const tooltip = options.functions.tooltip.formatter([{ dataIndex: 0 }]);
      assert.ok(tooltip.includes((f.size / f.gzip).toFixed(2) + 'x'));
      assert.equal(options.functions.series[0].data[0], f.bodySize);
      const leaf = options.treemap.series[0].data.flatMap(m => m.children).find(c => c.name === f.name && c.value === f.size && c.gzip === f.gzip);
      assert.equal(leaf.value, f.size);
      assert.equal(leaf.gzip, f.gzip);
      assert.ok(options.treemap.tooltip.formatter({ name: leaf.name, value: leaf.value, data: leaf }).includes((f.size / f.gzip).toFixed(2) + 'x'));
    }
    // Renderer-boundary injection only: no fake CLI failure switch or invalid Wasm.
    if (!checkedErrors && name === 'minimal') {
      const local = structuredClone(data);
      local.sections[0].gzip = null; local.sections[0].gzipError = 'section <local>';
      local.functions[0].gzip = null; local.functions[0].gzipError = 'function <local>';
      local.modules[0].children[0].gzip = null; local.modules[0].children[0].gzipError = 'leaf <local>';
      const rendered = charts(script.replace(dataText, JSON.stringify(local))).options;
      assert.equal(rendered.sections.series[1].data[0], null);
      assert.equal(rendered.sections.series[1].label.formatter({ value: null }), 'failed');
      assert.ok(rendered.sections.tooltip.formatter([{ dataIndex: 0 }]).includes('section &lt;local&gt;'));
      assert.ok(rendered.functions.tooltip.formatter([{ dataIndex: 0 }]).includes('function &lt;local&gt;'));
      const leaf = rendered.treemap.series[0].data[0].children[0];
      assert.ok(rendered.treemap.tooltip.formatter({ name: leaf.name, value: leaf.value, data: leaf }).includes('leaf &lt;local&gt;'));
      local.sections[0].gzipError = '';
      const emptyReason = charts(script.replace(dataText, JSON.stringify(local))).options;
      assert.ok(emptyReason.sections.tooltip.formatter([{ dataIndex: 0 }]).includes('independent gzip failed: '));
      const wholeFailed = structuredClone(data); wholeFailed.gzipSize = null; wholeFailed.gzipError = 'whole-only';
      const independent = charts(script.replace(dataText, JSON.stringify(wholeFailed))).options;
      const tip = independent.sections.tooltip.formatter([{ dataIndex: 0 }]);
      assert.ok(tip.includes('independent gzip ' + data.sections[0].gzip));
      assert.ok(!tip.includes('whole-only'));
      checkedErrors = true;
    }
  }
}
assert.ok(checkedErrors);
console.log(`Compression-report CLI regressions passed (${cases} process cases, ${fixtures.length} V8-validated modules).`);
JS
