// A static file server for the Three.js city's page (game/web_city), for desktop work and headless checks.
//   node scripts/web_city/serve.mjs [--port=8780] [--root=game/web_city]
// It serves files only, from the root only, to 127.0.0.1 only. Godot's own desktop bridge serves the same
// files when the game runs (scripts/web/web_city_bridge.gd); this one needs no Godot.
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const args = Object.fromEntries(process.argv.slice(2).map((a) => a.replace(/^--/, '').split('=')));
const root = path.resolve(args.root || path.join(here, '../../game/web_city'));
const port = Number(args.port || 8780);
const TYPES = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.mjs': 'text/javascript; charset=utf-8',
  '.json': 'application/json', '.bin': 'application/octet-stream', '.txt': 'text/plain; charset=utf-8', '.css': 'text/css' };

export function startServer(p = port, r = root) {
  const server = http.createServer((req, res) => {
    const url = new URL(req.url, 'http://127.0.0.1');
    let rel = decodeURIComponent(url.pathname);
    if (rel.endsWith('/')) rel += 'index.html';
    const file = path.resolve(r, '.' + rel);
    if (!file.startsWith(r + path.sep) && file !== r) { res.writeHead(403); res.end(); return; }
    fs.readFile(file, (err, data) => {
      if (err) { res.writeHead(404); res.end(); return; }
      res.writeHead(200, { 'Content-Type': TYPES[path.extname(file)] || 'application/octet-stream', 'Cache-Control': 'no-store' });
      res.end(data);
    });
  });
  return new Promise((resolve) => server.listen(p, '127.0.0.1', () => resolve(server)));
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  startServer().then(() => console.log(`serving ${root} at http://127.0.0.1:${port}/`));
}
