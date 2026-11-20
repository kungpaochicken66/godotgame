// Checks the two cities' benchmark path for the web city (scripts/web/city_bench.gd --city-bench=web) end to
// end on EC2: Godot headless with its desktop bridge, the page in headless Chromium. It proves the path runs
// and every phase is tagged in the logs. The numbers it produces are EC2 software-WebGL numbers: logic only.
//   PLAYWRIGHT_CORE=... node scripts/web_city/bench_check.mjs [--scale=0.08]
import { spawn } from 'node:child_process';
import { createRequire } from 'node:module';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const require = createRequire(import.meta.url);
const pw = require(process.env.PLAYWRIGHT_CORE || 'playwright-core');
const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const args = Object.fromEntries(process.argv.slice(2).map((a) => { const i = a.indexOf('='); return [a.slice(2, i < 0 ? undefined : i), i < 0 ? '1' : a.slice(i + 1)]; }));
const HTTP = 27400 + Math.floor(Math.random() * 400) * 2;
const WS = HTTP + 1;
const USER = path.join(os.homedir(), '.local/share/godot/app_userdata/Lantern Lane');
const BENCH = path.join(USER, 'city_bench.jsonl');
const PERF = path.join(USER, 'web_city_perf.jsonl');
const failures = [];
const check = (ok, what) => { console.log(`${ok ? 'ok  ' : 'FAIL'} ${what}`); if (!ok) failures.push(what); return ok; };
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const readLines = (f) => (fs.existsSync(f) ? fs.readFileSync(f, 'utf8').split('\n').filter(Boolean).map((l) => JSON.parse(l)) : []);
const before = { bench: readLines(BENCH).length, perf: readLines(PERF).length };

const godot = spawn(path.join(ROOT, 'scripts/godot.sh'), ['--headless', '--path', 'game', '--', '--web-city', '--city-bench=web',
  `--city-bench-scale=${args.scale || '0.08'}`, '--city-bench-quit', `--web-city-http=${HTTP}`, `--web-city-ws=${WS}`], { cwd: ROOT, stdio: ['ignore', 'pipe', 'pipe'] });
const lines = [];
const onData = (b) => { for (const l of b.toString().split('\n')) if (l.trim()) { lines.push(l); if (/CITY BENCH|SCRIPT ERROR/.test(l)) console.log(`  godot| ${l}`); } };
godot.stdout.on('data', onData);
godot.stderr.on('data', onData);
let exited = null;
godot.on('exit', (c) => { exited = c; });
process.on('exit', () => { try { process.kill(godot.pid, 'SIGTERM'); } catch (_) { /* gone */ } });
const until = async (fn, ms) => { const t0 = Date.now(); while (Date.now() - t0 < ms) { const v = fn(); if (v) return v; await sleep(200); } return null; };

let browser = null;
try {
  const urlLine = await until(() => lines.find((l) => l.startsWith('WEB CITY URL ')), 120000);
  if (!check(!!urlLine, 'the child reached the web city and the bridge gave its address')) throw new Error(lines.slice(-15).join('\n'));
  browser = await pw.chromium.launch({ args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
  const page = await browser.newPage({ viewport: { width: 960, height: 540 } });
  const errors = [];
  page.on('pageerror', (e) => errors.push(String(e)));
  await page.goto(urlLine.slice(13).trim() + '&dpr=0.5');
  const looked = [];
  await page.exposeFunction('benchSaw', (k) => looked.push(k));
  await page.evaluate(() => window.LL.app.events.addEventListener('message', (e) => { if (e.detail.t === 'bench' && e.detail.look) window.benchSaw(e.detail.look); }));
  const done = await until(() => lines.some((l) => l.startsWith('CITY BENCH web DONE')), 600000);
  check(!!done, 'the benchmark path ran to the end');
  check(looked.length >= 5, `the page was sent into Look places (${[...new Set(looked)].join(', ')})`);
  check(errors.length === 0, `no page errors${errors.length ? ': ' + errors.slice(0, 3).join(' | ') : ''}`);
} catch (e) {
  console.log(String(e));
  check(false, 'the run completed');
} finally {
  if (browser) await browser.close();
}
await until(() => exited !== null, 20000);
// dest-fix r2: the logs are where Godot says (its "CITY BENCH web DONE: <path> (<run>)" line): user:// differs by
// OS (the Mac's ~/Library/Application Support/..., not the Linux folder above), and this run's lines are the ones
// carrying its run id. Without that line (an older build), the Linux folder and the lines added since the start.
const doneLine = lines.find((l) => l.startsWith('CITY BENCH web DONE'));
const m = doneLine ? /^CITY BENCH web DONE: (.+\.jsonl) \(([^)]+)\)\s*$/.exec(doneLine.trim()) : null;
const benchFile = m ? m[1] : BENCH;
const perfFile = m ? path.join(path.dirname(m[1]), 'web_city_perf.jsonl') : PERF;
const runId = m ? m[2] : null;
if (m) console.log(`  logs: ${benchFile} (run ${runId})`);
const bench = runId ? readLines(benchFile).filter((r) => r.run === runId) : readLines(BENCH).slice(before.bench);
const perf = runId ? readLines(perfFile).filter((r) => r.bench === runId) : readLines(PERF).slice(before.perf);
const run = bench.find((r) => r.t === 'run');
check(run && run.kind === 'web' && run.map === 'city_web', `a run line for the web city (${run ? run.run : 'none'})`);
const phases = new Set(bench.filter((r) => r.t === 'phase').map((r) => r.phase));
check(phases.has('overview') && phases.has('rain') && phases.has('night') && [...phases].some((p) => p.startsWith('look_')), `every kind of phase is marked (${phases.size} phases)`);
const tagged = perf.filter((r) => r.bench === (run && run.run) && r.phase);
check(tagged.length > 0, `the page's perf samples are tagged with the run and phase (${tagged.length}; phases ${[...new Set(tagged.map((r) => r.phase))].length})`);
console.log(`CITY BENCH CHECK ${failures.length ? 'FAIL' : 'PASS'}: ${failures.length} failures (EC2 headless, software WebGL: the path runs; its numbers are not device evidence)`);
process.exit(failures.length ? 1 : 0);
