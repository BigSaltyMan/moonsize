import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';

const host = process.env.HOST || '127.0.0.1';
const port = Number(process.env.PORT || 5173);
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', 'examples');
const types = {'.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.css': 'text/css; charset=utf-8', '.json': 'application/json; charset=utf-8', '.wasm': 'application/wasm'};

const server = http.createServer((request, response) => {
  const requested = decodeURIComponent((request.url || '/').split('?')[0]);
  const relative = requested === '/' ? '/report.html' : requested;
  const file = path.resolve(root, `.${relative}`);
  if (file !== root && !file.startsWith(`${root}${path.sep}`)) {
    response.writeHead(403); response.end('Forbidden'); return;
  }
  fs.stat(file, (statError, stat) => {
    if (statError || !stat.isFile()) { response.writeHead(404); response.end('Not found'); return; }
    response.writeHead(200, {'Content-Type': types[path.extname(file)] || 'application/octet-stream'});
    fs.createReadStream(file).pipe(response);
  });
});

server.listen(port, host, () => {
  console.log(`moonsize visual server: http://${host}:${port}/`);
  console.log(`serving: ${root}`);
});
