// Verify checked-in adapted files without installing the obsolete dependencies.
import fs from 'node:fs';
import crypto from 'node:crypto';
import {fileURLToPath} from 'node:url';

const root = fileURLToPath(new URL('../', import.meta.url));
const manifest = JSON.parse(fs.readFileSync(root + 'internal/compression/provenance.json'));
for (const entry of manifest.files) {
  const bytes = fs.readFileSync(root + entry.path);
  const actual = crypto.createHash('sha256').update(bytes).digest('hex');
  if (actual !== entry.vendored_sha256) throw Error('Changed vendored file: ' + entry.path);
}
const mod = fs.readFileSync(root + 'moon.mod', 'utf8');
if (/bikallem\/(compress|blit)|moonbitlang\/async/.test(mod)) {
  throw Error('Legacy dependency chain reintroduced');
}
for (const dir of ['blit', 'checksum', 'flate', 'gzip']) {
  if (!fs.existsSync(root + 'internal/compression/' + dir + '/moon.pkg')) {
    throw Error('Missing native package configuration: ' + dir);
  }
}
if (!fs.readFileSync(root + 'internal/compression/LICENSE', 'utf8').includes('Apache License')) {
  throw Error('Missing third-party license');
}
console.log('Vendored compression: ' + manifest.files.length + ' adapted runtime files verified.');
