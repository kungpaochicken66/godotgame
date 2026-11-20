// The WebView plugin's posts while the page is starting (headless Chromium, as on iOS: a webkit message handler
// is present, so the bridge picks the 'webkit' transport). From document start, every 2 ms, it makes the plugin's
// exact call, window.LL&&window.LL.recv(<message>), and records any throw. evaluateJavaScript is not subject
// to the page's CSP, so the expression is written out rather than passed to eval, which the CSP forbids.
// Before r3, main.js set LL.app well before the bridge set LL.recv. A post in between threw
// "window.LL.recv is not a function", and the plugin counted it in js_errors (the Mac's r2 Simulator run: 2).
//   node scripts/web_city/early_post_check.mjs [--runs=3]
import { createRequire } from 'node:module';
import { startServer } from './serve.mjs';

const require = createRequire(import.meta.url);
const args = Object.fromEntries(process.argv.slice(2).map((a) => { const i = a.indexOf('='); return [a.slice(2, i < 0 ? undefined : i), i < 0 ? '1' : a.slice(i + 1)]; }));
const pw = require(process.env.PLAYWRIGHT_CORE || 'playwright-core');
const port = 8690 + Math.floor(Math.random() * 100);
await startServer(port);
const failures = [];
const check = (ok, what) => { console.log(`${ok ? 'ok  ' : 'FAIL'} ${what}`); if (!ok) failures.push(what); };
const INIT = () => {
  window.webkit = { messageHandlers: { godot: { postMessage() {} } } };
  const log = { posts: 0, beforeLL: 0, early: 0, after: 0, threw: [], readyAt: null };
  window.__earlyPosts = log;
  const msg = { t: 'frame', at: 0 };
  const tick = () => {
    const now = performance.now();
    const app = window.LL && window.LL.app;
    const opened = !!(app && app.bridge && app.bridge.kind !== 'none');
    log.posts++;
    try {
      window.LL && window.LL.recv(msg);   // the plugin's script
      if (!window.LL) log.beforeLL++; else if (!opened) log.early++; else log.after++;
    } catch (e) {
      log.threw.push(`${Math.round(now)} ms: ${e.name}: ${e.message}`);
    }
    if (log.readyAt === null && document.body && document.body.classList.contains('ready')) log.readyAt = now;
    if (log.readyAt === null || now - log.readyAt < 300) setTimeout(tick, 2);
  };
  setTimeout(tick, 0);
};
const browser = await pw.chromium.launch({ args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
let exercised = 0;
try {
  for (let i = 1; i <= Number(args.runs || 3); i++) {
    const page = await browser.newPage({ viewport: { width: 1280, height: 720 } });
    const pageErrors = [];
    page.on('pageerror', (e) => pageErrors.push(String(e)));
    await page.addInitScript(INIT);
    await page.goto(`http://127.0.0.1:${port}/index.html`);
    await page.waitForFunction(() => window.__earlyPosts && window.__earlyPosts.readyAt !== null, null, { timeout: 180000 });
    await page.waitForTimeout(400);
    const r = await page.evaluate(() => ({ ...window.__earlyPosts, earlyMessages: window.LL.app.earlyMessages, kind: window.LL.app.bridge.kind }));
    console.log(JSON.stringify({ run: i, posts: r.posts, beforeLL: r.beforeLL, early: r.early, after: r.after, threw: r.threw.length, earlyMessages: r.earlyMessages, kind: r.kind }));
    check(r.kind === 'webkit', `run ${i}: the bridge took the iOS transport (${r.kind})`);
    check(r.threw.length === 0, `run ${i}: no post threw${r.threw.length ? ': ' + r.threw.slice(0, 3).join(' | ') : ''}`);
    check(pageErrors.length === 0, `run ${i}: no page errors${pageErrors.length ? ': ' + pageErrors.slice(0, 3).join(' | ') : ''}`);
    check(r.after > 0, `run ${i}: posts reached the bridge after it opened (${r.after})`);
    if (r.early > 0) exercised++;
    await page.close();
  }
  check(exercised > 0, `the window between LL and the bridge was exercised (in ${exercised} runs)`);
} finally {
  await browser.close();
}
console.log(`EARLY POST CHECK ${failures.length ? 'FAIL' : 'PASS'}: ${failures.length} failures (EC2 headless: logic only)`);
process.exit(failures.length ? 1 : 0);
