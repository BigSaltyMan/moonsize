// Consume an explicitly selected run with real Graphviz layout. No analyzer runs.
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import {spawnSync} from 'node:child_process';

const args = process.argv.slice(2);
if (args.length < 1 || args.length > 2 || !args[0]) {
  console.error('Usage: node scripts/verify-dependencies-dot-graphviz.mjs <evidence-directory> [dot-executable]');
  process.exit(2);
}
const evidence = path.resolve(args[0]);
const output = path.join(evidence, 'graphviz');
const executable = args[1] || 'dot';
const timeout = 30000;
const maxBuffer = 8 * 1024 * 1024;
const sha = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
const expectedEdges = [
  ['fn_1', 'fn_3', 'direct; file offset 68', 'solid'],
  ['fn_1', 'fn_3', 'direct; file offset 70', 'solid'],
  ['fn_1', 'fn_4', 'reference; file offset 72', 'dashed'],
  ['fn_1', 'fn_4', 'indirect candidate; file offset 77', 'dotted'],
  ['fn_1', 'fn_1', 'direct; file offset 80', 'solid'],
  ['fn_3', 'fn_4', 'direct; file offset 92', 'solid'],
  ['fn_3', 'fn_0', 'direct; file offset 94', 'solid'],
  ['fn_4', 'fn_3', 'direct; file offset 99', 'solid'],
];
// Independent fixture expectations: never read label text back from product DOT.
const specialRawName = '雪 "quote" \\N|\\G|\\E|\\n|\\l|\\r\n\t\u001b"]; injected -> fn_99; //';
const specialVisibleName = '雪 "quote" \\N|\\G|\\E|\\n|\\l|\\r\\u000a\\u0009\\u001b"]; injected -> fn_99; //';
const expectedNodeText = {
  fn_0: ['#0: m.f', 'imported; encoded size not measured', 'BFS depth 2'],
  fn_1: ['#1: (unnamed)', 'local; encoded size 17 B', 'BFS depth 0', 'query target'],
  fn_3: ['#3: ' + specialVisibleName, 'local; encoded size 7 B', 'BFS depth 1'],
  fn_4: ['#4: (unnamed)', 'local; encoded size 5 B', 'BFS depth 1'],
};
const expectedGapDiagnostics = [{
  code: 'unmodeled_reference_call', caller: 6, offset: 109,
  opcode: 'call_ref', type_index: 0, table_index: null,
}];
const commands = [];
const graphs = [];
const failures = [];
let dotPath = null;
let version = null;

function write(name, data) {
  fs.writeFileSync(path.join(output, name), data, {flag: 'wx'});
}

function resolveExecutable(command) {
  const hasPath = command.includes('/') || command.includes('\\');
  const extensions = process.platform === 'win32'
    ? ['', ...(process.env.PATHEXT || '.EXE;.CMD;.BAT').split(';')]
    : [''];
  const bases = hasPath
    ? [path.resolve(command)]
    : (process.env.PATH || '').split(path.delimiter).filter(Boolean).map(p => path.join(p, command));
  for (const base of bases) {
    for (const extension of extensions) {
      const candidate = base + extension;
      try {
        if (!fs.statSync(candidate).isFile()) continue;
        fs.accessSync(candidate, fs.constants.X_OK);
        return path.resolve(candidate);
      } catch (error) {
        if (!['ENOENT', 'ENOTDIR', 'EACCES'].includes(error.code)) throw error;
      }
    }
  }
  throw new Error('Graphviz executable not found or not executable: ' + command);
}

function invoke(label, argv, stdoutName) {
  const result = spawnSync(dotPath, argv, {
    shell: false, cwd: evidence, encoding: 'utf8', timeout, maxBuffer,
  });
  write(stdoutName, result.stdout || '');
  write(label + '.stderr.txt', result.stderr || '');
  const record = {
    argv: [dotPath, ...argv], shell: false, timeout_ms: timeout, max_buffer_bytes: maxBuffer,
    status: result.status, signal: result.signal,
    error: result.error ? {code: result.error.code, message: result.error.message} : null,
    stdout: stdoutName, stderr: label + '.stderr.txt',
  };
  commands.push(record);
  if (result.error) throw new Error(label + ': ' + result.error.code + ': ' + result.error.message);
  assert.equal(result.signal, null, label + ' terminated by signal');
  assert.equal(result.status, 0, label + ' exited nonzero; inspect ' + record.stderr);
  return result;
}

function drawnText(item) {
  assert(Array.isArray(item._ldraw_), 'missing layout drawing operations');
  const texts = item._ldraw_.filter(op => op.op === 'T').map(op => op.text);
  assert(texts.every(text => typeof text === 'string'), 'invalid layout text operation');
  return texts;
}

function validateGraph(graph, inputBytes, incomplete) {
  assert.equal(graph.name, 'moonsize_dependencies');
  assert.equal(graph.directed, true);
  assert.equal(graph.strict, false);
  assert.equal(graph.rankdir, 'LR');
  assert.equal(graph.input_sha256, sha(inputBytes));
  assert.equal(graph.file_size, String(inputBytes.length));
  assert.equal(graph.target_index, '1');
  assert.equal(graph.graph_complete, String(!incomplete));
  assert.equal(graph.unresolved_count, '0');
  assert.equal(typeof graph.modeling_scope, 'string');
  assert(graph.modeling_scope.includes('not execution'));
  assert.equal(typeof graph.diagnostics_json, 'string');
  // Graphviz's JSON parser has already decoded its JSON string layer. The
  // custom DOT attribute is JSON text; parse exactly once, without unescaping
  // or deleting any remaining backslashes. Malformed data is a hard failure.
  const diagnostics = JSON.parse(graph.diagnostics_json);
  assert.deepEqual(diagnostics, incomplete ? expectedGapDiagnostics : []);
  assert.equal(typeof graph.graph_warning, 'string');
  if (incomplete) {
    assert(graph.graph_warning.includes('function 6, offset 109: call_ref'));
  } else assert.equal(graph.graph_warning, '');

  assert(Array.isArray(graph.objects));
  assert.equal(graph.objects.length, 4);
  const byId = new Map();
  const byName = new Map();
  for (const node of graph.objects) {
    assert(Number.isSafeInteger(node._gvid), 'invalid Graphviz object id');
    assert(!byId.has(node._gvid) && !byName.has(node.name), 'duplicate node/id');
    byId.set(node._gvid, node.name);
    byName.set(node.name, node);
  }
  assert.deepEqual([...byName.keys()].sort(), ['fn_0', 'fn_1', 'fn_3', 'fn_4']);
  for (const [name, node] of byName) {
    assert.equal(node.shape, name === 'fn_0' ? 'ellipse' : 'box');
    assert.deepEqual(drawnText(node), expectedNodeText[name], name + ' rendered text differs');
  }
  const target = byName.get('fn_1');
  assert.equal(target.style, 'filled');
  assert.equal(target.fillcolor, 'lightyellow');
  assert.equal(Number(target.penwidth), 2);
  assert(!drawnText(byName.get('fn_0')).some(text => text.includes('0 B')));

  assert(Array.isArray(graph.edges));
  assert.equal(graph.edges.length, 8);
  const actualEdges = graph.edges.map(edge => {
    assert(byId.has(edge.tail) && byId.has(edge.head), 'edge endpoint outside subgraph');
    assert.deepEqual(drawnText(edge), [edge.label], 'edge label drawing differs');
    return [byId.get(edge.tail), byId.get(edge.head), edge.label, edge.style];
  });
  // Sorted arrays are multisets: parallel edges retain multiplicity, unlike Set.
  const multiset = edges => edges.map(edge => JSON.stringify(edge)).sort();
  assert.deepEqual(multiset(actualEdges), multiset(expectedEdges));
  const title = drawnText(graph);
  assert.equal(title[0], 'Query target #1; nodes 4; edges 8');
  assert(title.some(text => text.includes('Direct: solid; reference: dashed; indirect candidate: dotted')));
  if (incomplete) {
    assert(title.includes('WARNING: incomplete graph; diagnostics 1'));
    assert(title.some(text => text.includes('function 6, offset 109: call_ref')));
  }
  return {
    node_count: 4, edge_count: 8, predecessor_tree_edge_count: 3,
    graphviz_id_to_node: Object.fromEntries(byId), edge_multiset: actualEdges,
    node_drawn_text: Object.fromEntries([...byName].map(([name, node]) => [name, drawnText(node)])),
    special_name_node: 'fn_3', special_raw_name: specialRawName,
    special_visible_name: specialVisibleName, title_drawn_text: title, diagnostics,
    structure_passed: true, layout_text_passed: true,
  };
}

try {
  assert(fs.statSync(evidence).isDirectory(), 'evidence directory required');
  // No search for latest runs and no overwrite of earlier consumer evidence.
  fs.mkdirSync(output);
  try {
    dotPath = resolveExecutable(executable);
    const result = invoke('version', ['-V'], 'version.stdout.txt');
    version = (result.stdout + result.stderr).trim();
    assert(/graphviz/i.test(version), 'unrecognized Graphviz version output');
    for (const [inputName, dotName, incomplete] of [
      ['overlap.wasm', 'new.dot', false], ['gap.wasm', 'gap.dot', true],
    ]) {
      const record = {input: inputName, dot: dotName, passed: false};
      graphs.push(record);
      try {
        const inputBytes = fs.readFileSync(path.join(evidence, inputName));
        const dotBytes = fs.readFileSync(path.join(evidence, dotName));
        Object.assign(record, {input_size: inputBytes.length, input_sha256: sha(inputBytes), dot_sha256: sha(dotBytes)});
        const stdoutName = dotName + '.json';
        const result = invoke(dotName, ['-Tjson', path.join(evidence, dotName)], stdoutName);
        const graph = JSON.parse(result.stdout);
        Object.assign(record, validateGraph(graph, inputBytes, incomplete), {passed: true, output: stdoutName});
      } catch (error) {
        record.error = error.stack || String(error);
        failures.push(dotName + ': ' + error.message);
      }
    }
  } catch (error) {
    failures.push(error.stack || String(error));
  }
  const result = {
    format: 'moonsize-dependencies-dot-graphviz-verification', schema_version: 1,
    source_sha: process.env.GITHUB_SHA || null,
    evidence_directory: evidence, executable_requested: executable, executable_path: dotPath,
    version, commands, graphs, failures, passed: failures.length === 0 && graphs.length === 2,
    scope: 'Actual Graphviz -Tjson parsing, layout and output text contract. No manual visual, font-glyph, browser or print acceptance.',
  };
  write('results.json', JSON.stringify(result, null, 2) + '\n');
  if (!result.passed) throw new Error(failures.join('\n') || 'Both Graphviz outputs were not checked');
  console.log('Graphviz dependency DOT consumer checks passed (2 layouts): ' + output);
} catch (error) {
  console.error('Graphviz dependency DOT consumer verification failed: ' + (error.stack || error));
  process.exitCode = 1;
}
