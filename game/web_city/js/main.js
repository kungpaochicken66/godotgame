// The Three.js city: boot, the shared app object, the frame loop and the performance record.
// design/city-threejs.md. Godot stays the game; this page draws the city and forwards input (js/bridge.js).
//
// Modules (each its own file, each `export async function init(app)` returning
// {update(dt, t)?, onMessage(msg)?, afterRender()?}, all optional):
//   world   the city's moving things, weather and night, lights, sky (rules.js holds the ported rules)
//   people  the fifty-odd townsfolk
//   kids    the Lantern Lane children (the player's and friends'), drawn from Godot's rigs and poses
//   camera  orbit, zoom, pan, Look and its glides, picking; owns app.camera's pose
//   hud     the page's buttons (action, Look, Pause, weather, Reset view, Town), toasts, input routing
// A module that is missing or fails to start is reported and skipped: the rest of the city still runs.
import * as THREE from '../vendor/three.module.js';
import { loadConsts } from './consts.js';
import { loadPack } from './meshpack.js';
import { Bridge, PROTOCOL } from './bridge.js';
import { CityClock } from './clock.js';

const MODULES = ['world', 'people', 'kids', 'camera', 'hud'];
const PERF_EVERY = 1.0;   // seconds between perf messages to Godot

export const app = {
  THREE,
  C: null,
  params: new URLSearchParams(location.search),
  scene: null,
  camera: null,
  renderer: null,
  canvas: null,
  city: null,          // the mesh pack: {root, byPath, materials, lights, meshes}
  clock: new CityClock(),
  bridge: new Bridge(),
  modules: {},
  failed: {},          // module name -> error text
  state: {
    hello: null,       // Godot's hello (me, platform, strings, locale)
    states: null,      // the newest City states (net/city.gd client form, as JSON)
    frame: null,       // the newest frame message (me, kids, ...)
    link: false,       // whether Godot is there
  },
  events: new EventTarget(),
  perf: { frames: 0, samples: [], last: null, startedAt: 0, firstFrameAt: 0, loadMs: 0 },
  /** The page's text in the game's language (Godot sends the translations in hello). */
  tr(text) {
    const s = app.state.hello && app.state.hello.strings;
    return (s && s[text]) || text;
  },
  /** Sends a message to Godot. */
  send(msg) { app.bridge.send(msg); },
  /** Looks up a node of the city by its Godot path below City, e.g. "Ferris/Wheel". */
  node(path) { return app.city.byPath.get(`City/${path}`) || null; },
};
window.LL = window.LL || {};
window.LL.app = app;
// Godot posts "window.LL&&window.LL.recv(<json>)" from the moment the page has loaded (the WebView plugin),
// and the bridge sets LL.recv only once the city's constants are in (app.bridge.open). Until then a message
// is counted and set aside, not thrown on: a throw there counted as a page error in the plugin's js_errors
// (the Mac's r2 Simulator run: 2 at startup). Godot sends everything again when the page says 'ready'.
app.earlyMessages = 0;
if (typeof window.LL.recv !== 'function') window.LL.recv = () => { app.earlyMessages++; };

function setupRenderer() {
  const canvas = document.getElementById('city');
  const renderer = new THREE.WebGLRenderer({ canvas, antialias: true, powerPreference: 'high-performance' });
  renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, Number(app.params.get('dpr')) || 2));
  renderer.setSize(window.innerWidth, window.innerHeight, false);
  renderer.outputColorSpace = THREE.SRGBColorSpace;
  renderer.toneMapping = THREE.NoToneMapping;   // Godot's city: linear tonemap, sRGB output
  renderer.shadowMap.enabled = false;            // the game has no real-time shadows (blob shadows only)
  app.canvas = canvas;
  app.renderer = renderer;
  app.scene = new THREE.Scene();
  app.scene.background = new THREE.Color(1, 1, 1);
  const orbit = app.C.CityOrbit;
  app.camera = new THREE.PerspectiveCamera(orbit.FOV, window.innerWidth / window.innerHeight, 0.1, 400);
  app.camera.position.set(0, 60, 70);
  app.camera.lookAt(0, 0, 0);
  window.addEventListener('resize', () => {
    renderer.setSize(window.innerWidth, window.innerHeight, false);
    app.camera.aspect = window.innerWidth / window.innerHeight;
    app.camera.updateProjectionMatrix();
    app.events.dispatchEvent(new Event('resize'));
  });
}

function onMessage(msg) {
  switch (msg.t) {
    case 'hello':
      app.state.hello = msg;
      app.state.link = true;
      if (msg.v !== PROTOCOL) console.warn(`bridge protocol ${msg.v}, page ${PROTOCOL}`);
      break;
    case 'frame':
      app.state.frame = msg;
      app.state.link = true;
      if (msg.clock !== undefined) app.clock.sync(msg.clock);
      break;
    case 'states':
      app.state.states = msg.s;
      break;
    case 'bench':
      // scripts/web/city_bench.gd: the scripted path. The phase tags the perf samples; a look glides in or out.
      if (msg.phase !== undefined) app.perf.phase = msg.phase || '';
      if (msg.look !== undefined && app.cameraRig) {
        if (msg.look) app.cameraRig.lookAt(msg.look);
        else {
          app.cameraRig.setLook(false);
          // dest-fix r1: the city now opens on (and Look off returns to) the strolling view; the bench's overview
          // phases keep measuring the whole block, as in r1-r3, so the runs stay comparable
          app.cameraRig.rig.cityOverview();
        }
      }
      break;
    case 'link':
      app.state.link = !!msg.up;
      break;
    case 'bye':
      app.state.link = false;
      break;
    default:
      break;
  }
  for (const name of Object.keys(app.modules)) {
    const m = app.modules[name];
    if (m && m.onMessage) m.onMessage(msg);
  }
  app.events.dispatchEvent(new CustomEvent('message', { detail: msg }));
}

async function startModules() {
  for (const name of MODULES) {
    try {
      const mod = await import(`./${name}.js`);
      app.modules[name] = (await mod.init(app)) || {};
    } catch (e) {
      app.failed[name] = String(e && e.stack ? e.stack : e);
      console.warn(`module ${name} not started:`, e);
      app.send({ t: 'log', level: 'warn', text: `module ${name} not started: ${e}` });
    }
  }
  if (!app.modules.world) {
    app.scene.add(new THREE.HemisphereLight(0xffffff, 0xd8d8d8, 2.2));   // so a partial page still shows the city
  }
}

function recordPerf(dt) {
  const p = app.perf;
  p.frames++;
  p.samples.push(dt * 1000);
  const now = performance.now() / 1000;
  if (p.last === null) p.last = now;
  if (now - p.last >= PERF_EVERY) {
    const s = p.samples.slice().sort((a, b) => a - b);
    const q = (f) => s[Math.min(s.length - 1, Math.floor(f * s.length))];
    const info = app.renderer.info;
    const sample = {
      t: 'perf', at: now, frames: s.length, fps: s.length / (now - p.last), p50: q(0.5), p95: q(0.95), max: s[s.length - 1],
      calls: info.render.calls, triangles: info.render.triangles, geometries: info.memory.geometries, textures: info.memory.textures,
      heap: performance.memory ? performance.memory.usedJSHeapSize : null,
      phase: p.phase || '',
    };
    p.lastSample = sample;
    p.samples = [];
    p.last = now;
    app.send(sample);
    app.events.dispatchEvent(new CustomEvent('perf', { detail: sample }));
  }
}

async function boot() {
  const t0 = performance.now();
  app.perf.startedAt = t0;
  app.C = await loadConsts('data/consts.json');
  setupRenderer();
  app.bridge.onMessage(onMessage);
  await app.bridge.open(app.params);
  app.city = await loadPack('data/city');
  app.scene.add(app.city.root);
  await startModules();
  app.perf.loadMs = performance.now() - t0;
  app.send({ t: 'ready', v: PROTOCOL, w: window.innerWidth, h: window.innerHeight, dpr: app.renderer.getPixelRatio(),
    load_ms: app.perf.loadMs, failed: Object.keys(app.failed), ua: navigator.userAgent });
  document.body.classList.add('ready');
  let last = performance.now();
  app.renderer.setAnimationLoop(() => {
    const nowMs = performance.now();
    const dt = Math.min(0.1, (nowMs - last) / 1000);
    last = nowMs;
    app.bridge.tick(dt);
    app.clock.advance(dt);
    const t = app.clock.viewTime();
    for (const name of MODULES) {
      const m = app.modules[name];
      if (m && m.update) {
        try {
          m.update(dt, t);
        } catch (e) {
          if (!app.failed[`${name}.update`]) {
            app.failed[`${name}.update`] = String(e && e.stack ? e.stack : e);
            console.error(e);
            app.send({ t: 'log', level: 'error', text: `${name}.update: ${e && e.stack ? e.stack : e}` });
          }
        }
      }
    }
    app.renderer.render(app.scene, app.camera);
    if (!app.perf.firstFrameAt) {
      app.perf.firstFrameAt = performance.now() - t0;
      app.send({ t: 'first_frame', ms: app.perf.firstFrameAt });
    }
    for (const name of MODULES) {
      const m = app.modules[name];
      if (m && m.afterRender) m.afterRender();
    }
    recordPerf(dt);
  });
}

boot().catch((e) => {
  console.error(e);
  const el = document.getElementById('status');
  if (el) el.style.borderTopColor = '#e0533d';   // no text: the page's words come from Godot's locales
  app.failed.boot = String(e && e.stack ? e.stack : e);
  try { app.send({ t: 'log', level: 'error', text: `boot: ${e && e.stack ? e.stack : e}` }); } catch (_) { /* nothing to tell */ }
});
