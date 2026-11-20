// Loads the Three.js city's page in headless Chromium (Playwright, software WebGL) and checks that it starts:
// no page errors, every module started, frames drawn, the city's nodes present. EC2-headless evidence only:
// it proves the page's logic runs, never how it looks or how fast it is on a device.
//   node scripts/web_city/page_check.mjs [--query=harness=1] [--shot=/abs/file.png] [--seconds=4]
// Playwright: the playwright-core package is found through $PLAYWRIGHT_CORE (a path to the package) or the
// usual module resolution. No browser is downloaded here.
import { createRequire } from 'node:module';
import { startServer } from './serve.mjs';

const require = createRequire(import.meta.url);
const args = Object.fromEntries(process.argv.slice(2).map((a) => { const i = a.indexOf('='); return [a.slice(2, i < 0 ? undefined : i), i < 0 ? '1' : a.slice(i + 1)]; }));
const pw = require(process.env.PLAYWRIGHT_CORE || 'playwright-core');
const port = 8790 + Math.floor(Math.random() * 100);
const server = await startServer(port);
const failures = [];
const check = (ok, what) => { console.log(`${ok ? 'ok  ' : 'FAIL'} ${what}`); if (!ok) failures.push(what); };
const browser = await pw.chromium.launch({ args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
try {
  const page = await browser.newPage({ viewport: { width: 1280, height: 720 } });
  const errors = [];
  page.on('pageerror', (e) => errors.push(String(e)));
  page.on('console', (m) => { if (m.type() === 'error') errors.push(m.text()); });
  await page.goto(`http://127.0.0.1:${port}/index.html?${args.query || 'harness=1'}`);
  await page.waitForFunction(() => window.LL && window.LL.app && window.LL.app.perf.firstFrameAt > 0, null, { timeout: 60000 });
  await page.waitForTimeout(Number(args.seconds || 4) * 1000);
  // A loaded 2-CPU EC2 under software WebGL can draw only a few frames a second: wait for frames, not time.
  await page.waitForFunction(() => window.LL.app.perf.frames > 10, null, { timeout: 180000 }).catch(() => {});
  const r = await page.evaluate(() => {
    const a = window.LL.app;
    return { failed: a.failed, modules: Object.keys(a.modules), frames: a.perf.frames, loadMs: a.perf.loadMs, first: a.perf.firstFrameAt,
      nodes: a.city.byPath.size, calls: a.renderer.info.render.calls, tris: a.renderer.info.render.triangles, link: a.state.link };
  });
  console.log(JSON.stringify(r));
  check(errors.length === 0, `no page errors${errors.length ? ': ' + errors.slice(0, 5).join(' | ') : ''}`);
  check(Object.keys(r.failed).length === 0, `every module started${Object.keys(r.failed).length ? ': ' + Object.keys(r.failed).join(', ') : ''}`);
  check(r.frames > 10, `frames drawn (${r.frames})`);
  check(r.nodes > 100, `city nodes (${r.nodes})`);
  if (args.shot) await page.screenshot({ path: args.shot, timeout: 240000 });
} finally {
  await browser.close();
  server.close();
}
console.log(`WEB CITY PAGE ${failures.length ? 'FAIL' : 'PASS'}: ${failures.length} failures (EC2 headless, software WebGL: logic only)`);
process.exit(failures.length ? 1 : 0);
