// The web city end to end: the real game (Godot headless, a solo town, tests/web_city_e2e_driver.gd takes the
// child to city_web) and the real page (headless Chromium on the bridge's own HTTP and WebSocket servers).
// Checks: hello, frames flowing, the child's kid_model arrived and is drawn, a tap ray at a ground point walks
// the Godot child toward it, a weather press changes CityWeb's weather, Town sends the child home and the page
// gets 'bye'. EC2 headless (SwiftShader): logic evidence only, never how it looks or how fast it is.
//   PLAYWRIGHT_CORE=/path/to/playwright-core node scripts/web_city/e2e.mjs [--shot=/abs/file.png] [--keep-log]
// Only the processes this script starts are stopped (by their recorded PIDs).
import { spawn } from 'node:child_process';
import fs from 'node:fs';
import { createRequire } from 'node:module';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const require = createRequire(import.meta.url);
const here = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(here, '../..');
const args = Object.fromEntries(process.argv.slice(2).map((a) => { const i = a.indexOf('='); return [a.slice(2, i < 0 ? undefined : i), i < 0 ? '1' : a.slice(i + 1)]; }));
const pw = require(process.env.PLAYWRIGHT_CORE || 'playwright-core');
const HTTP = 20000 + Math.floor(Math.random() * 20000);
const WS = HTTP + 1;
const failures = [];
const check = (ok, what) => { console.log(`${ok ? 'ok  ' : 'FAIL'} ${what}`); if (!ok) failures.push(what); return ok; };
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// ---- Godot
const started = [];
const godot = spawn(path.join(ROOT, 'scripts/godot.sh'),
  ['--headless', '--path', 'game', '--', '--driver=res://tests/web_city_e2e_driver.gd', '--web-city', `--web-city-http=${HTTP}`, `--web-city-ws=${WS}`, '--timeout=900'],
  { cwd: ROOT, stdio: ['ignore', 'pipe', 'pipe'] });
started.push(godot.pid);   // godot.sh execs Godot: this PID is Godot itself
console.log(`started Godot, pid ${godot.pid}`);
const lines = [];
let state = null;
let godotExit = null;
const onData = (buf) => {
  for (const line of buf.toString().split('\n')) {
    if (!line.trim()) continue;
    if (line.startsWith('E2E STATE ')) { try { state = JSON.parse(line.slice(10)); } catch (_) { /* partial */ } continue; }
    lines.push(line);
    if (args['keep-log'] || /E2E DRIVER|WEB CITY|SCRIPT ERROR|ERROR/.test(line)) console.log(`  godot| ${line}`);
  }
};
godot.stdout.on('data', onData);
godot.stderr.on('data', onData);
let godotExitAt = Infinity;
godot.on('exit', (code) => { godotExit = code; godotExitAt = Date.now(); });

async function until(fn, ms, step = 100) {
  const t0 = Date.now();
  for (;;) {
    const v = await fn();
    if (v) return v;
    if (Date.now() - t0 > ms) return null;
    await sleep(step);
  }
}
const sawLine = (re) => lines.some((l) => re.test(l));

/**
 * A picture of the canvas, rendered and read in one task (the page's own loop cannot clear it in between;
 * Playwright's screenshot waits for compositor frames that software WebGL delivers too slowly here). With
 * `id`, a close view of that child; else the page's camera.
 */
async function shoot(page, file, id) {
  const data = await page.evaluate((kidId) => {
    const app = window.LL.app;
    let cam = app.camera;
    if (kidId !== null) {
      const k = app.kids.get(kidId);
      if (!k) return null;
      cam = new app.THREE.PerspectiveCamera(35, app.camera.aspect, 0.1, 200);
      const p = k.group.position;
      cam.position.set(p.x + 2.2, p.y + 1.5, p.z + 2.2);
      cam.lookAt(p.x, p.y + 0.6, p.z);
    }
    app.renderer.render(app.scene, cam);
    return app.renderer.domElement.toDataURL('image/png');
  }, id);
  if (!data) return;
  fs.writeFileSync(file, Buffer.from(data.split(',')[1], 'base64'));
  console.log(`  picture: ${file}`);
}

let browser = null;
function stopAll() {
  for (const pid of started) {
    try { process.kill(pid, 'SIGTERM'); } catch (_) { /* already gone */ }
  }
}
process.on('exit', stopAll);

try {
  const urlLine = await until(() => lines.find((l) => l.startsWith('WEB CITY URL ')), 90000);
  check(!!urlLine, `the bridge prints the page's address when the child enters city_web${urlLine ? ` (${urlLine.slice(13)})` : ''}`);
  if (!urlLine) throw new Error(`no URL; last Godot lines:\n${lines.slice(-20).join('\n')}`);
  const url = urlLine.slice(13).trim();
  check(url === `http://127.0.0.1:${HTTP}/index.html?ws=${WS}`, 'on the ports given (--web-city-http, --web-city-ws)');

  // ---- Chromium (same flags as page_check.mjs)
  browser = await pw.chromium.launch({ args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
  const page = await browser.newPage({ viewport: { width: 1280, height: 720 } });
  const errors = [];
  // (the page's reconnect attempts after Godot has quit are not page errors)
  page.on('pageerror', (e) => { if (Date.now() < godotExitAt) errors.push(String(e)); });
  page.on('console', (m) => { if (m.type() === 'error' && !/status of 404/.test(m.text()) && Date.now() < godotExitAt) errors.push(m.text()); });
  const missing = [];   // 404s: page modules other workers have not written yet (checked against app.failed below)
  page.on('response', (r) => { if (r.status() === 404) missing.push(new URL(r.url()).pathname); });
  // Record every message Godot sends, by type, below the page's own code.
  await page.addInitScript(() => {
    const W = window.WebSocket;
    window.__got = { counts: {}, order: [], models: [], hello: null, last: null, states: null };
    window.WebSocket = class extends W {
      constructor(...a) {
        super(...a);
        this.addEventListener('message', (ev) => {
          let m;
          try { m = JSON.parse(ev.data); } catch (_) { return; }
          const g = window.__got;
          g.counts[m.t] = (g.counts[m.t] || 0) + 1;
          if (m.t !== 'frame' && m.t !== 'states') g.order.push(m.t);
          if (m.t === 'hello') g.hello = m;
          if (m.t === 'frame') { g.last = m; g.frameBytes = ev.data.length; }
          if (m.t === 'states') g.states = m.s;
          if (m.t === 'kid_model') g.models.push({ id: m.id, rev: m.rev, bytes: ev.data.length, poseNodes: m.pose_nodes.length });
        });
      }
    };
  });
  await page.goto(url);
  const ready = await until(() => page.evaluate(() => !!(window.LL && window.LL.app && window.LL.app.perf.firstFrameAt > 0)), 120000, 500);
  check(!!ready, 'the page loads from the bridge and draws its first frame');
  const got = () => page.evaluate(() => window.__got);
  const hello = await until(async () => (await got()).hello, 30000);
  check(!!hello && hello.v === 1 && hello.map === 'city_web' && hello.platform === 'desktop', `hello (${hello ? JSON.stringify({ v: hello.v, me: hello.me, map: hello.map, platform: hello.platform, locale: hello.locale, strings: Object.keys(hello.strings || {}).length }) : 'none'})`);
  check(await until(() => sawLine(/WEB CITY page ready/), 10000), "Godot got the page's ready");
  const me = hello ? hello.me : null;

  // ---- frames flowing
  const f0 = (await got()).counts.frame || 0;
  await sleep(3000);
  const g1 = await got();
  const nFrames = (g1.counts.frame || 0) - f0;
  check(nFrames > 20, `frames flow (${nFrames} in 3 s, ${g1.frameBytes} bytes each)`);
  const lf = g1.last;
  check(!!lf && typeof lf.clock === 'number' && lf.me && Array.isArray(lf.kids), 'a frame has clock, me and kids');
  check(!!lf && lf.clock > 0, `the frame's clock is the CityWeb clock (${lf && lf.clock})`);
  const myKid = lf && lf.kids.find((k) => k.me);
  check(!!myKid && myKid.id === me && myKid.xf.length === 12 && myKid.pose && Array.isArray(myKid.pose.x), 'the frame carries the child with its transform and pose');

  // ---- the child's model arrived and is drawn
  const model = g1.models.find((m) => m.id === me);
  check(!!model, `the child's kid_model arrived (${model ? `${model.bytes} bytes, ${model.poseNodes} pose nodes` : 'none'})`);
  check(!!myKid && !!model && myKid.pose.x.length === model.poseNodes * 12, 'the pose fits the model');
  const drawn = await page.evaluate((id) => {
    const app = window.LL.app;
    const k = app.kids && app.kids.get(id);
    if (!k || !k.model) return { ok: false, why: 'no model on the page' };
    const T = app.THREE;
    const cam = new T.PerspectiveCamera(40, 16 / 9, 0.1, 100);
    const p = k.group.position;
    cam.position.set(p.x + 2.5, p.y + 1.6, p.z + 2.5);
    cam.lookAt(p.x, p.y + 0.7, p.z);
    const r = app.renderer;   // two renders in one task: the page's own loop cannot run between them
    const visible = k.group.visible;
    k.group.visible = false;
    r.render(app.scene, cam);
    const without = r.info.render.triangles;
    k.group.visible = true;
    r.render(app.scene, cam);
    const withKid = r.info.render.triangles;
    k.group.visible = visible;
    let meshes = 0;
    k.model.root.traverse((o) => { if (o.isMesh && o.visible) meshes++; });
    return { ok: withKid > without, without, withKid, meshes, visible, pos: p.toArray() };
  }, me);
  check(drawn.ok && drawn.visible, `the child is drawn from its model (${JSON.stringify(drawn)})`);
  // dest-fix r1: the player's own child is named on the page (Godot's label; before, the page drew no names) and the
  // city opens on the strolling view that follows it (it is near the middle of the screen, not a 13 px figure)
  await page.waitForFunction((id) => { const k = window.LL.app.kids.get(id); return k && k.tag && k.tag.style.display === 'block'; }, me, { timeout: 30000 }).catch(() => {});
  const tag = await page.evaluate((id) => {
    const app = window.LL.app;
    const k = app.kids.get(id);
    if (!k || !k.tag) return null;
    const r = k.tag.getBoundingClientRect();
    const s = app.cameraRig.rig.cityState;
    return { text: k.tag.textContent, shown: k.tag.style.display === 'block', x: r.left + r.width / 2, y: r.bottom, w: innerWidth, h: innerHeight,
      out: !!s.out, distance: s.distance };
  }, me);
  check(!!tag && tag.shown && tag.text.length > 0, `the child's name tag is shown (${tag ? JSON.stringify(tag.text) : 'none'})`);
  check(!!tag && !tag.out && tag.distance < 20 && Math.abs(tag.x - tag.w / 2) < tag.w * 0.2 && Math.abs(tag.y - tag.h / 2) < tag.h * 0.35,
    `the city opens on the strolling view with the child near the middle (${tag ? `distance ${tag.distance.toFixed(1)}, tag at ${tag.x.toFixed(0)},${tag.y.toFixed(0)}` : 'none'})`);
  if (args.shot) await shoot(page, args.shot.replace(/\.png$/, '_kid.png'), me);

  // ---- a tap ray at a ground point walks the Godot child toward it
  const start = state ? state.pos : null;
  check(!!start && state.space === 'city_web', `Godot's child is in city_web (${JSON.stringify(state)})`);
  let walked = false;
  for (const target of [[start[0] + 4.0, start[1]], [start[0], start[1] + 4.0], [-26.0, 6.0], [start[0] + 3.0, start[1] - 3.0]]) {
    const d0 = Math.hypot(state.pos[0] - target[0], state.pos[1] - target[1]);
    await page.evaluate((tg) => {
      const o = [tg[0] + 6.0, 14.0, tg[1] + 9.0];
      const v = [tg[0] - o[0], -o[1], tg[1] - o[2]];
      const n = Math.hypot(...v);
      window.LL.app.send({ t: 'tap', o, d: v.map((x) => x / n) });
    }, target);
    const moved = await until(() => state && Math.hypot(state.pos[0] - target[0], state.pos[1] - target[1]) < d0 - 1.0, 8000);
    if (moved) {
      await until(() => state && Math.hypot(state.pos[0] - target[0], state.pos[1] - target[1]) < 0.8, 8000);
      const d1 = Math.hypot(state.pos[0] - target[0], state.pos[1] - target[1]);
      walked = check(true, `a tap ray at ground point [${target}] walks the child toward it (${d0.toFixed(2)} m -> ${d1.toFixed(2)} m)`);
      // software WebGL draws about a frame a second here: the page reads its socket between frames, so wait
      let onPage = null;
      await until(async () => {
        onPage = await page.evaluate((id) => window.LL.app.kids.get(id).group.position.toArray(), me);
        return Math.hypot(onPage[0] - state.pos[0], onPage[2] - state.pos[1]) < 1.0;
      }, 30000, 500);
      check(Math.hypot(onPage[0] - state.pos[0], onPage[2] - state.pos[1]) < 1.0, `the page draws the child where Godot has it (${onPage.map((x) => x.toFixed(2))} / ${state.pos.map((x) => x.toFixed(2))})`);
      break;
    }
    console.log(`  (no walk toward [${target}]; trying another ground point)`);
  }
  if (!walked) check(false, 'a tap ray at a ground point walks the child');

  // ---- a weather press changes the CityWeb weather
  const w0 = state.weather;
  const w1 = (w0 + 1) % 3;
  await page.evaluate((w) => window.LL.app.send({ t: 'weather', w }), w1);
  const wOk = await until(() => state && state.weather === w1, 8000);
  check(!!wOk, `a weather press changes CityWeb's weather (${w0} -> ${state.weather})`);
  const sOk = await until(async () => { const s = (await got()).states; return s && s.weather === w1; }, 30000, 500);
  check(!!sOk, "and the page's states say so");

  if (args.shot) await shoot(page, args.shot, null);

  // ---- Town sends the child home; the page gets bye
  await page.evaluate(() => window.LL.app.send({ t: 'home' }));
  const home = await until(() => state && state.space === 'town' && state.journey === '', 20000);
  check(!!home, `Town sends the child home (${state && state.space})`);
  const bye = await until(async () => ((await got()).counts.bye || 0) > 0, 30000, 500);
  check(!!bye, "the page gets 'bye'");
  const kidsLeft = await page.evaluate(() => window.LL.app.kids.ids().length);
  check(kidsLeft === 0, `the page drops the children after bye (${kidsLeft})`);
  check(errors.length === 0, `no page errors${errors.length ? ': ' + errors.slice(0, 5).join(' | ') : ''}`);
  const failed = await page.evaluate(() => Object.keys(window.LL.app.failed));
  console.log(`  page modules not started (other workers' files): ${failed.join(', ') || 'none'}`);
  check(missing.every((u) => failed.some((f) => u === `/js/${f}.js`)), `the only missing files are those modules (${missing.join(', ') || 'none'})`);
  check(!failed.includes('kids'), 'kids started on the page');
  const order = (await got()).order;
  console.log(`  message order (no frames/states): ${order.slice(0, 12).join(' ')}${order.length > 12 ? ' ...' : ''}`);
  await until(() => godotExit !== null, 8000);
} catch (e) {
  check(false, `e2e ran to the end: ${e && e.stack ? e.stack : e}`);
} finally {
  if (browser) await browser.close();
  stopAll();
}
const errLines = lines.filter((l) => /SCRIPT ERROR/.test(l));
check(errLines.length === 0, `no Godot script errors${errLines.length ? ': ' + errLines.slice(0, 3).join(' | ') : ''}`);
console.log(`WEB CITY E2E ${failures.length ? 'FAIL' : 'PASS'}: ${failures.length} failures (EC2 headless, software WebGL: logic only)`);
process.exit(failures.length ? 1 : 0);
