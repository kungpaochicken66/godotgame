// The page's camera input and HUD in headless Chromium (Playwright, software WebGL), in the harness (?harness=1):
// a drag orbits, the wheel zooms, a right drag pans, a tap on the ground reaches the harness as a 'tap' ray and
// the harness child walks there; Look picks a building and glides in, Esc glides back out; Pause stops the
// page's clock and leaving Look resumes it; each weather button changes the harness weather; the action button
// and Ride home send their requests; a toast shows. EC2-headless evidence only: logic, never looks or speed.
//   node scripts/web_city/input_check.mjs [--shots=/abs/dir] [--dpr=0.5]
// Playwright as in page_check.mjs ($PLAYWRIGHT_CORE). Screenshots: <shots>/camhud_<name>.png when --shots is given.
import { createRequire } from 'node:module';
import { startServer } from './serve.mjs';

const require = createRequire(import.meta.url);
const args = Object.fromEntries(process.argv.slice(2).map((a) => { const i = a.indexOf('='); return [a.slice(2, i < 0 ? undefined : i), i < 0 ? '1' : a.slice(i + 1)]; }));
const pw = require(process.env.PLAYWRIGHT_CORE || 'playwright-core');
const port = 8890 + Math.floor(Math.random() * 100);
const server = await startServer(port);
const failures = [];
const check = (ok, what) => { console.log(`${ok ? 'ok  ' : 'FAIL'} ${what}`); if (!ok) failures.push(what); };
// software WebGL draws a frame in about a second at full size: the check renders at half resolution so that
// glides and walks finish in reasonable time (the camera and input work in CSS pixels either way)
const dpr = args.dpr || '0.5';
const MINE = ['camera', 'hud'];
const browser = await pw.chromium.launch({ args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });

async function open(page, query) {
  const errors = [];
  page.on('pageerror', (e) => errors.push(String(e)));
  page.on('console', (m) => { if (m.type() === 'error') errors.push(m.text()); });
  await page.goto(`http://127.0.0.1:${port}/index.html?${query}`);
  await page.waitForFunction(() => window.LL && window.LL.app && window.LL.app.perf.firstFrameAt > 0 && window.LL.app.state.hello
    && window.LL.app.cameraRig && window.LL.app.hud, null, { timeout: 240000 });
  // record what the page sends and what the harness receives
  await page.evaluate(() => {
    const a = window.LL.app;
    window.__sent = [];
    const h = a.bridge._harness;
    const recv = h.receive.bind(h);
    h.receive = (m) => { window.__sent.push(m); recv(m); };
  });
  return errors;
}

const shot = async (page, name) => {
  if (!args.shots) return;
  // a screenshot waits for a drawn frame: slow under software WebGL on a loaded machine; never a failure here
  await page.screenshot({ path: `${args.shots}/camhud_${name}.png`, timeout: 180000 }).catch((e) => console.log(`note: screenshot ${name} not taken (${String(e).split('\n')[0]})`));
};
const state = (page) => page.evaluate(() => {
  const a = window.LL.app;
  const r = a.cameraRig.rig;
  const h = a.bridge._harness;
  return { yaw: r.cityState.yaw, pitch: r.cityState.pitch, distance: r.cityState.distance, out: r.cityState.out,
    pan: r.cityState.pan || null, look: r.look, looking: a.cameraRig.isLooking(), gliding: r.cityGliding(),
    focus: r.cur.focus.slice(), lookFocus: r.lookView ? r.lookView.focus.slice() : null, paused: a.clock.isPaused(),
    hpos: h.pos.slice(), htarget: h.target ? h.target.slice() : null, weather: h.weather,
    sent: window.__sent.map((m) => m.t) };
});
const sentSince = (page, n) => page.evaluate((k) => window.__sent.slice(k), n);
const sentCount = (page) => page.evaluate(() => window.__sent.length);
/** Waits until the camera has come to rest (no glide, the smoothing within 1 mm of its goal). */
const settle = (page, timeout = 120000) => page.waitForFunction(() => {
  const r = window.LL.app.cameraRig.rig;
  if (r.cityGliding()) return false;
  const c = r.cur;
  const g = r.goal;
  return Math.abs(c.distance - g.distance) < 1e-3 && Math.hypot(c.focus[0] - g.focus[0], c.focus[1] - g.focus[1], c.focus[2] - g.focus[2]) < 1e-3
    && Math.abs(c.yaw - g.yaw) < 1e-4 && Math.abs(c.pitch - g.pitch) < 1e-4;
}, null, { timeout, polling: 100 });
/** Screen (CSS px) of a world point through the page's camera. */
const screenOf = (page, p) => page.evaluate((q) => {
  const a = window.LL.app;
  const v = new a.THREE.Vector3(q[0], q[1], q[2]).project(a.camera);
  const r = a.canvas.getBoundingClientRect();
  return [r.left + (v.x * 0.5 + 0.5) * r.width, r.top + (-v.y * 0.5 + 0.5) * r.height];
}, p);
/** What CityOrbit.pick_place answers for the ray through a client point (the page's own module). */
const pickAt = (page, p) => page.evaluate(async (q) => {
  const O = await import('./js/orbit.js');
  const r = window.LL.app.cameraRig.ray(q[0], q[1]);
  return O.pickPlace(r.o, r.d);
}, p);
/** A client point whose ray meets no Look place. */
const emptySpot = (page) => page.evaluate(async () => {
  const O = await import('./js/orbit.js');
  const w = window.innerWidth;
  const h = window.innerHeight;
  const canvas = window.LL.app.canvas;
  for (let y = 0.05; y < 1; y += 0.05) {
    for (let x = 0.05; x < 1; x += 0.05) {
      if (document.elementFromPoint(x * w, y * h) !== canvas) continue;   // not under a button
      const r = window.LL.app.cameraRig.ray(x * w, y * h);
      if (O.pickPlace(r.o, r.d) === '') return [x * w, y * h];
    }
  }
  return null;
});
const unexpected = (errors, failed) => errors.filter((e) => {
  if (/404 \(Not Found\)|Failed to fetch dynamically imported module/.test(e)) {
    return MINE.some((m) => failed.includes(m));   // a missing other module is not this check's concern
  }
  return true;
});

try {
  const page = await browser.newPage({ viewport: { width: 1280, height: 720 } });
  const errors = await open(page, `harness=1&dpr=${dpr}`);
  const failedMods = await page.evaluate(() => Object.keys(window.LL.app.failed));
  check(!MINE.some((m) => failedMods.includes(m)) && !failedMods.some((m) => /^(camera|hud)\./.test(m)), `camera and hud started (not started: ${failedMods.join(', ') || 'none'})`);
  await settle(page);
  let s0 = await state(page);
  // dest-fix r1 (the user's acceptance on the installed r3): the city opens on the strolling view that follows the child
  check(!s0.out && s0.distance < 20 && Math.abs(s0.yaw) < 1e-9 && !s0.looking, `the city opens on the strolling view (distance ${s0.distance.toFixed(2)}, not the overview)`);

  // a drag on the ground orbits, and is never a tap
  let n = await sentCount(page);
  await page.mouse.move(640, 500);
  await page.mouse.down();
  for (let i = 1; i <= 10; i++) await page.mouse.move(640 + i * 20, 500 + i * 3);
  await page.mouse.up();
  let s = await state(page);
  check(Math.abs(s.yaw - s0.yaw) > 0.3 && s.pitch > s0.pitch, `a drag orbits (yaw ${s0.yaw.toFixed(3)} -> ${s.yaw.toFixed(3)}, pitch ${s0.pitch.toFixed(3)} -> ${s.pitch.toFixed(3)})`);
  check(!(await sentSince(page, n)).some((m) => m.t === 'tap'), 'the drag sent no tap');

  // the wheel zooms (forward: closer)
  const d0 = s.distance;
  await page.mouse.move(640, 360);
  for (let i = 0; i < 4; i++) await page.mouse.wheel(0, -100);
  await page.waitForFunction((d) => window.LL.app.cameraRig.rig.cityState.distance < d - 1, d0, { timeout: 10000 }).catch(() => {});
  s = await state(page);
  check(s.distance < d0 * 0.75 && !s.out, `the wheel zooms in (distance ${d0.toFixed(2)} -> ${s.distance.toFixed(2)}, out ${s.out})`);
  await settle(page);

  // a right drag pans, and is never a tap
  n = await sentCount(page);
  await page.mouse.move(700, 400);
  await page.mouse.down({ button: 'right' });
  for (let i = 1; i <= 8; i++) await page.mouse.move(700 - i * 25, 400 + i * 10);
  await page.mouse.up({ button: 'right' });
  s = await state(page);
  check(s.pan && Math.hypot(s.pan[0], s.pan[2]) > 1.0, `a right drag pans (pan ${s.pan ? s.pan.map((x) => x.toFixed(2)).join(', ') : 'none'})`);
  check(!(await sentSince(page, n)).some((m) => m.t === 'tap'), 'the right drag sent no tap');
  await settle(page);

  // Reset view glides back to the strolling view (dest-fix r1; was the overview) and clears the pan
  await page.click('[data-name=CityReset]');
  s = await state(page);
  check(s.gliding && !s.out && s.distance < 20 && !s.pan, 'Reset view starts a glide back to the strolling view (no pan)');
  await settle(page);

  // a tap on the ground: a 'tap' ray reaches the harness and the child walks there
  s0 = await state(page);
  n = await sentCount(page);
  const tapAt = [560, 560];
  const expect = await page.evaluate((p) => window.LL.app.cameraRig.ray(p[0], p[1]), tapAt);
  await page.mouse.click(tapAt[0], tapAt[1]);
  const taps = (await sentSince(page, n)).filter((m) => m.t === 'tap');
  check(taps.length === 1, `one tap message reached the harness (${taps.length})`);
  if (taps.length) {
    const t = taps[0];
    const same = t.o.every((x, i) => Math.abs(x - expect.o[i]) < 1e-6) && t.d.every((x, i) => Math.abs(x - expect.d[i]) < 1e-6);
    const unit = Math.abs(Math.hypot(...t.d) - 1) < 1e-9;
    check(same && unit && t.d[1] < 0, `the tap is the camera ray through the point (o ${t.o.map((x) => x.toFixed(2))}, d ${t.d.map((x) => x.toFixed(3))})`);
  }
  s = await state(page);
  check(s.htarget !== null, `the harness child has a target (${s.htarget ? s.htarget.map((x) => x.toFixed(2)) : 'none'})`);
  await page.waitForFunction((p0) => { const h = window.LL.app.bridge._harness; return Math.hypot(h.pos[0] - p0[0], h.pos[1] - p0[1]) > 0.5; }, s0.hpos, { timeout: 60000 }).catch(() => {});
  s = await state(page);
  check(Math.hypot(s.hpos[0] - s0.hpos[0], s.hpos[1] - s0.hpos[1]) > 0.5, `the harness child moved (${s0.hpos.map((x) => x.toFixed(2))} -> ${s.hpos.map((x) => x.toFixed(2))})`);

  // Look: the button lights, a tap on a building glides in to it, Esc glides back out
  n = await sentCount(page);
  await page.click('[data-name=CityLook]');
  s = await state(page);
  const lit = await page.evaluate(() => document.querySelector('[data-name=CityLook]').classList.contains('ll-lit')
    && !document.querySelector('[data-name=CityPause]').hidden);
  check(s.looking && lit, 'Look turns on (the button lit, Pause shown)');
  check((await sentSince(page, n)).some((m) => m.t === 'look' && m.on === true), "a 'look' on message was sent");
  // dest-fix r2: the places are picked on the whole block, as city_tour does (rig.city_overview). Since dest-fix r1
  // the camera starts in the strolling view, which follows the harness child; it is still walking from the tap
  // above, so a screen point taken here moved before the click (the Mac's Chrome run: "a tap on the office glides
  // in" failed with look ''). The overview stands still, as the r1-r3 view did here.
  await page.evaluate(() => window.LL.app.cameraRig.rig.cityOverview());
  await settle(page);
  const office = await screenOf(page, [-17.0, 5.0, -8.0]);
  const pickOffice = await pickAt(page, office);
  check(pickOffice === 'office', `the office is on screen at ${office.map((x) => x.toFixed(0))} (pick_place: ${pickOffice})`);
  const lf0 = s.lookFocus;
  n = await sentCount(page);
  await page.mouse.click(office[0], office[1]);
  s = await state(page);
  check(s.look === 'office' && s.gliding && s.lookFocus && (!lf0 || lf0.join() !== s.lookFocus.join()), `a tap on the office glides in to it (look ${s.look}, focus ${s.lookFocus})`);
  check(!(await sentSince(page, n)).some((m) => m.t === 'tap'), 'in Look the tap is not sent to Godot');
  await settle(page);
  s = await state(page);
  check(Math.hypot(s.focus[0] + 17, s.focus[1] - 3.6, s.focus[2] + 6.5) < 0.05, `the camera came to rest on the office (focus ${s.focus.map((x) => x.toFixed(2))})`);
  await shot(page, 'look_office');
  // Esc leaves Look, gliding back to the strolling view, the child again (dest-fix r1; was the overview)
  n = await sentCount(page);
  await page.keyboard.press('Escape');
  s = await state(page);
  check(!s.looking && s.look === '' && s.gliding && !s.out, 'Esc leaves Look with a glide back to the strolling view');
  check((await sentSince(page, n)).some((m) => m.t === 'look' && m.on === false), "a 'look' off message was sent");
  await settle(page);
  s = await state(page);
  check(Math.hypot(s.focus[0] - s.hpos[0], s.focus[2] - s.hpos[1]) < 0.6 && !s.out, `back on the child (focus ${s.focus.map((x) => x.toFixed(2))}, child ${s.hpos.map((x) => x.toFixed(2))})`);
  // the places below are picked on the whole block
  await page.evaluate(() => window.LL.app.cameraRig.rig.cityOverview());
  await settle(page);

  // Look again: the cafe, then a tap on empty space glides out while Look stays on
  await page.click('[data-name=CityLook]');
  const cafe = await screenOf(page, [-2.0, 2.0, -6.0]);
  check((await pickAt(page, cafe)) === 'cafe', `the cafe is on screen at ${cafe.map((x) => x.toFixed(0))}`);
  await page.mouse.click(cafe[0], cafe[1]);
  s = await state(page);
  check(s.look === 'cafe' && s.gliding, `a tap on the cafe glides in to it (${s.look})`);
  await settle(page);
  const empty = await emptySpot(page);
  check(empty !== null, `an empty spot on screen (${empty ? empty.map((x) => x.toFixed(0)) : 'none'})`);
  if (empty) await page.mouse.click(empty[0], empty[1]);
  s = await state(page);
  check(s.look === '' && s.looking && s.gliding && s.out, 'a tap on empty space glides back out, Look stays on');
  await settle(page);
  await page.click('[data-name=CityLook]');

  // Pause: only while looking; leaving Look resumes
  await settle(page);
  const pauseHidden = await page.evaluate(() => document.querySelector('[data-name=CityPause]').hidden);
  check(pauseHidden, 'Pause is hidden out of Look');
  await page.click('[data-name=CityLook]');
  n = await sentCount(page);
  await page.click('[data-name=CityPause]');
  s = await state(page);
  check(s.paused, 'Pause stops the page clock (app.clock.isPaused())');
  check((await sentSince(page, n)).some((m) => m.t === 'pause' && m.on === true), "a 'pause' on message was sent");
  const v0 = await page.evaluate(() => window.LL.app.clock.viewTime());
  await page.waitForTimeout(1500);
  const v1 = await page.evaluate(() => window.LL.app.clock.viewTime());
  check(v1 === v0, `the view clock stands still while paused (${v0.toFixed(3)} -> ${v1.toFixed(3)})`);
  await page.click('[data-name=CityLook]');
  s = await state(page);
  check(!s.looking && !s.paused, 'leaving Look resumes the city');

  // the weather buttons change the harness weather (and the lit button follows the states)
  for (const [i, name] of [[1, 'rain'], [2, 'night'], [0, 'sunny']]) {
    await page.click(`[data-name=Weather_${name}]`);
    s = await state(page);
    const on = await page.waitForFunction((k) => {
      const b = document.querySelectorAll('#hud .ll-glass');
      return b[k] && b[k].classList.contains('ll-on');
    }, i, { timeout: 15000 }).then(() => true).catch(() => false);
    check(s.weather === i && on, `${name}: harness weather ${s.weather}, its button lit ${on}`);
    if (name === 'night') await shot(page, 'weather_night');
  }

  // the action button follows frame.me.ctx and sends 'act'; Ride home sends 'home'; a toast shows
  await page.evaluate(() => {
    const h = window.LL.app.bridge._harness;
    const deliver = h.deliver;
    h.deliver = (m) => { if (m.t === 'frame') m.me.ctx = { type: 'city_use', label: 'Sit down', icon: 'sit' }; deliver(m); };
  });
  const actShown = await page.waitForFunction(() => { const b = document.querySelector('[data-name=Action]'); return b && !b.hidden && b.textContent === 'Sit down'; }, null, { timeout: 15000 }).then(() => true).catch(() => false);
  check(actShown, 'the action button shows the context');
  n = await sentCount(page);
  await page.click('[data-name=Action]');
  await page.click('[data-name=RideHome]');
  const sent = (await sentSince(page, n)).map((m) => m.t);
  check(sent.includes('act') && sent.includes('home'), `the action button and Ride home send their requests (${sent.filter((t) => t === 'act' || t === 'home').join(', ')})`);
  await page.evaluate(() => window.LL.recv({ t: 'toast', text: 'You found the cafe!' }));
  const toastOn = await page.waitForFunction(() => Number(getComputedStyle(document.querySelector('#hud .ll-toast')).opacity) > 0.5
    && document.querySelector('#hud .ll-toast').textContent === 'You found the cafe!', null, { timeout: 15000, polling: 50 }).then(() => true).catch(() => false);
  check(toastOn, 'a toast shows');
  await shot(page, 'act_toast');
  const camMsgs = await page.evaluate(() => window.__sent.filter((m) => m.t === 'cam').length);
  check(camMsgs > 3, `'cam' messages are sent (${camMsgs})`);
  const bad = unexpected(errors, failedMods);
  check(bad.length === 0, `no page errors from the camera or HUD${bad.length ? ': ' + bad.slice(0, 5).join(' | ') : ''}`);

  await page.close();   // one software-rendered page at a time

  // the HUD on a phone held sideways and on an iPad: every button at least 44 CSS px, all inside the view
  for (const [name, w, h] of [['phone', 852, 393], ['ipad', 1366, 1024]]) {
    const p2 = await browser.newPage({ viewport: { width: w, height: h } });
    const e2 = await open(p2, 'harness=1&dpr=0.25');   // layout only: the smallest render
    await p2.click('[data-name=CityLook]');
    const boxes = await p2.evaluate(() => [...document.querySelectorAll('#hud button')].filter((b) => !b.hidden)
      .map((b) => { const r = b.getBoundingClientRect(); return { n: b.dataset.name, x: r.left, y: r.top, w: r.width, h: r.height }; }));
    const small = boxes.filter((b) => b.w < 44 || b.h < 44);
    const outside = boxes.filter((b) => b.x < 0 || b.y < 0 || b.x + b.w > w || b.y + b.h > h);
    check(small.length === 0 && outside.length === 0, `${name} ${w}x${h}: ${boxes.length} buttons, all >= 44 px and inside${small.length ? ', small: ' + small.map((b) => b.n) : ''}${outside.length ? ', outside: ' + outside.map((b) => b.n) : ''}`);
    await shot(p2, name);
    const b2 = unexpected(e2, await p2.evaluate(() => Object.keys(window.LL.app.failed)));
    check(b2.length === 0, `${name}: no page errors from the camera or HUD`);
    await p2.close();
  }
} finally {
  await browser.close();
  server.close();
}
console.log(`WEB CITY INPUT ${failures.length ? 'FAIL' : 'PASS'}: ${failures.length} failures (EC2 headless, software WebGL: logic only)`);
process.exit(failures.length ? 1 : 0);
