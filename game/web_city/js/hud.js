// The page's HUD: the Godot city HUD's city controls (ui/hud.gd), drawn over the Three.js city because the
// web view covers Godot's own HUD. Each press does what the Godot button does: camera buttons act on the
// page's camera (js/camera.js), the rest go to Godot as the same requests (design/city-threejs.md §6.3).
//   right edge, vertically centred (CameraButtons, margin 16): Rotate view left / right, Zoom, Reset view,
//     Look around / Stop looking (lit while on), Pause the city / Resume (only while looking)
//   just inside it (CityWeather, margin 96): Sunny, Rain, Night, 52 px glass buttons, the current one opaque
//   top left: "City · <building>" and Ride home        bottom centre: the action button (frame.me.ctx)
//   top centre: toasts and hints                        ?stats=1: the newest perf sample (desktop runs)
// Sizes are Godot's at its 1366 x 1024 base, scaled like its canvas_items stretch, never so small that a
// button is under 44 CSS px. Every word goes through app.tr; js/strings.js lists them all.
import { C } from './consts.js';
import { PAGE_STRINGS } from './strings.js';

// ui_kit.gd's icons (the same SVG), plus "resume": the play triangle in the text colour (ui_kit's "play" is
// white, drawn for the green action button; on the light Pause button it would not show).
const ICONS = {
  sun: "<circle cx='32' cy='32' r='11' fill='#ffcf4a'/><g stroke='#f2a93b' stroke-width='5' stroke-linecap='round'><path d='M32 6 V14 M32 50 V58 M6 32 H14 M50 32 H58 M13.6 13.6 L19.3 19.3 M44.7 44.7 L50.4 50.4 M13.6 50.4 L19.3 44.7 M44.7 19.3 L50.4 13.6'/></g>",
  rain: "<path d='M18 36 C10 36 8 26 15 23 C15 14 26 11 31 17 C35 10 48 12 48 22 C55 23 56 36 47 36 Z' fill='#cfe3f5' stroke='#5c7fa3' stroke-width='3'/><g stroke='#4f9fe8' stroke-width='4' stroke-linecap='round'><path d='M22 44 L19 52 M33 44 L30 52 M44 44 L41 52'/></g>",
  moon: "<path d='M40 8 C26 10 16 22 18 36 C20 50 34 58 48 54 C38 50 32 40 33 29 C34 19 39 12 40 8 Z' fill='#ffe28a' stroke='#c99a2e' stroke-width='3'/><circle cx='48' cy='18' r='2.5' fill='#ffe28a'/><circle cx='52' cy='30' r='1.8' fill='#ffe28a'/>",
  look: "<path d='M6 32 C16 16 48 16 58 32 C48 48 16 48 6 32 Z' fill='#fffdf6' stroke='#344d40' stroke-width='4'/><circle cx='32' cy='32' r='10' fill='#5aaef5'/><circle cx='32' cy='32' r='4.5' fill='#344d40'/><circle cx='35' cy='29' r='2' fill='#fffdf6'/>",
  pause: "<rect x='16' y='12' width='11' height='40' rx='4' fill='#344d40'/><rect x='37' y='12' width='11' height='40' rx='4' fill='#344d40'/>",
  play: "<path d='M20 12 L52 32 L20 52 Z' fill='#fffdf6' stroke='#fffdf6' stroke-width='4' stroke-linejoin='round'/>",
  resume: "<path d='M20 12 L52 32 L20 52 Z' fill='#344d40' stroke='#344d40' stroke-width='4' stroke-linejoin='round'/>",
  home: "<path d='M8 30 L32 10 L56 30' fill='none' stroke='#344d40' stroke-width='6' stroke-linecap='round' stroke-linejoin='round'/><rect x='16' y='28' width='32' height='26' rx='4' fill='#f3ead8' stroke='#344d40' stroke-width='3'/><rect x='27' y='38' width='10' height='16' rx='4' fill='#e9806e'/>",
  tram: "<rect x='10' y='14' width='44' height='30' rx='10' fill='#f2cf6b' stroke='#344d40' stroke-width='3'/><rect x='16' y='20' width='12' height='10' rx='3' fill='#d4ebf4'/><rect x='36' y='20' width='12' height='10' rx='3' fill='#d4ebf4'/><circle cx='20' cy='48' r='5' fill='#344d40'/><circle cx='44' cy='48' r='5' fill='#344d40'/><rect x='6' y='54' width='52' height='4' rx='2' fill='#b98a5e'/>",
  rotate_left: "<path d='M18 30 A16 16 0 1 1 26 46' fill='none' stroke='#344d40' stroke-width='6' stroke-linecap='round'/><path d='M8 22 L20 36 L28 20 Z' fill='#344d40'/>",
  rotate_right: "<path d='M46 30 A16 16 0 1 0 38 46' fill='none' stroke='#344d40' stroke-width='6' stroke-linecap='round'/><path d='M56 22 L44 36 L36 20 Z' fill='#344d40'/>",
  zoom: "<circle cx='28' cy='28' r='16' fill='#fffdf6' stroke='#344d40' stroke-width='6'/><path d='M40 40 L54 54' stroke='#344d40' stroke-width='7' stroke-linecap='round'/><path d='M20 28 L36 28 M28 20 L28 36' stroke='#344d40' stroke-width='5' stroke-linecap='round'/>",
  sit: "<rect x='12' y='30' width='40' height='8' rx='4' fill='#d9a466' stroke='#344d40' stroke-width='3'/><path d='M16 38 L16 54 M48 38 L48 54 M14 30 L14 10' stroke='#344d40' stroke-width='5' stroke-linecap='round'/>",
  stand: "<circle cx='32' cy='14' r='8' fill='#f2c7a5' stroke='#344d40' stroke-width='3'/><path d='M32 22 L32 42 M20 30 L44 30 M32 42 L22 56 M32 42 L42 56' stroke='#344d40' stroke-width='5' stroke-linecap='round'/>",
  cook: "<path d='M22 14 Q18 8 22 4 M32 14 Q28 8 32 4 M42 14 Q38 8 42 4' fill='none' stroke='#a3b29f' stroke-width='3' stroke-linecap='round'/><rect x='10' y='22' width='44' height='28' rx='8' fill='#e9806e'/><rect x='6' y='18' width='52' height='8' rx='4' fill='#c9604f'/><rect x='2' y='30' width='10' height='6' rx='3' fill='#4a4f55'/><rect x='52' y='30' width='10' height='6' rx='3' fill='#4a4f55'/>",
  cheer: "<path d='M32 6 L38 24 L56 24 L42 35 L47 54 L32 42 L17 54 L22 35 L8 24 L26 24 Z' fill='#f2cf6b' stroke='#344d40' stroke-width='3' stroke-linejoin='round'/>",
  book: "<path d='M8 14 C18 10 26 12 32 18 C38 12 46 10 56 14 L56 52 C46 48 38 50 32 56 C26 50 18 48 8 52 Z' fill='#edcf81' stroke='#344d40' stroke-width='3' stroke-linejoin='round'/><path d='M32 18 L32 56' stroke='#344d40' stroke-width='3'/>",
  gift: "<rect x='10' y='26' width='44' height='30' rx='5' fill='#ec8fa3' stroke='#344d40' stroke-width='3'/><rect x='6' y='18' width='52' height='10' rx='4' fill='#f4ad8a' stroke='#344d40' stroke-width='3'/><path d='M32 18 L32 56' stroke='#fffdf6' stroke-width='6'/><path d='M32 18 C24 6 14 10 20 18 Z M32 18 C40 6 50 10 44 18 Z' fill='#f2cf6b' stroke='#344d40' stroke-width='2'/>",
  door: "<rect x='16' y='8' width='32' height='48' rx='14' fill='#95c97f' stroke='#344d40' stroke-width='3'/><circle cx='40' cy='34' r='3.5' fill='#f2cf6b'/>",
  warn: "<path d='M32 8 L58 54 L6 54 Z' fill='#f2cf6b' stroke='#344d40' stroke-width='3' stroke-linejoin='round'/><path d='M32 24 L32 38' stroke='#344d40' stroke-width='6' stroke-linecap='round'/><circle cx='32' cy='46' r='3.5' fill='#344d40'/>",
};

const svg = (name) => `<svg viewBox="0 0 64 64" aria-hidden="true">${ICONS[name] || ICONS.warn}</svg>`;

const WEATHER_ICON = { sunny: 'sun', rain: 'rain', night: 'moon' };
const WEATHER_TEXT = { sunny: 'Sunny', rain: 'Rain', night: 'Night' };
const TOAST_IN = 0.15;
const TOAST_HOLD = 2.2;
const TOAST_OUT = 0.4;

// ui_kit.gd colours: PANEL #fffdf6, TEXT #344d40, ACCENT #557c5e, SOFT #e5eddc; SOFT.darkened(0.08) #d3daca,
// PANEL.lerp(SOFT, 0.5) #f2f5e9, ACCENT.lightened(0.4) #99b09e, ACCENT lightened / darkened 0.1 #66896e / #4d7055.
const CSS = `
#hud { --u: 1; font-family: -apple-system, "SF Pro Rounded", "Helvetica Neue", Arial, sans-serif; font-weight: 700; color: #344d40; }
#hud .ll-svgdefs { position: absolute; width: 0; height: 0; pointer-events: none; }
#hud .ll-col { position: absolute; top: 50%; transform: translateY(-50%); display: flex; flex-direction: column; align-items: center; }
#hud .ll-cam { right: calc(env(safe-area-inset-right, 0px) + 16px * var(--u)); gap: calc(12px * var(--u)); }
#hud .ll-weather { right: calc(env(safe-area-inset-right, 0px) + 96px * var(--u)); gap: calc(8px * var(--u)); }
#hud button { -webkit-appearance: none; appearance: none; margin: 0; padding: 0; font: inherit; color: inherit; cursor: pointer;
  display: flex; align-items: center; justify-content: center; box-sizing: border-box; touch-action: manipulation;
  -webkit-tap-highlight-color: transparent; outline: none; }
#hud button svg { display: block; flex: none; }
#hud .ll-icon { width: max(calc(68px * var(--u)), 44px); height: max(calc(68px * var(--u)), 44px); border-radius: 50%;
  background: #fffdf6; border: 2px solid #d3daca; box-shadow: 0 calc(4px * var(--u)) calc(10px * var(--u)) rgba(51, 64, 51, 0.1); }
#hud .ll-icon svg { width: calc(44px * var(--u)); height: calc(44px * var(--u)); min-width: 30px; min-height: 30px; }
#hud .ll-icon:hover { background: #f2f5e9; border-color: #99b09e; }
#hud .ll-icon:active { background: #e5eddc; border: 3px solid #557c5e; box-shadow: none; }
#hud .ll-icon.ll-lit { filter: url(#ll-lit); }
#hud .ll-glass { width: max(calc(52px * var(--u)), 44px); height: max(calc(52px * var(--u)), 44px); border-radius: 50%;
  background: rgba(255, 255, 255, 0.34); border: 2px solid rgba(255, 255, 255, 0.75); opacity: 0.72; }
#hud .ll-glass svg { width: calc(40px * var(--u)); height: calc(40px * var(--u)); min-width: 30px; min-height: 30px; }
#hud .ll-glass:hover, #hud .ll-glass:active { background: rgba(255, 255, 255, 0.5); }
#hud .ll-glass.ll-on { opacity: 1; }
#hud .ll-top { position: absolute; left: calc(env(safe-area-inset-left, 0px) + 16px * var(--u)); top: calc(env(safe-area-inset-top, 0px) + 16px * var(--u));
  background: #fffdf6; border-radius: calc(24px * var(--u)); padding: calc(16px * var(--u)) calc(20px * var(--u));
  box-shadow: 0 calc(4px * var(--u)) calc(10px * var(--u)) rgba(51, 64, 51, 0.14); display: flex; align-items: center; gap: calc(10px * var(--u)); }
#hud .ll-where { font-size: max(calc(22px * var(--u)), 14px); color: #557c5e; white-space: nowrap; pointer-events: none; }
#hud .ll-btn { min-height: max(calc(52px * var(--u)), 44px); padding: calc(10px * var(--u)) calc(16px * var(--u)); gap: calc(10px * var(--u));
  background: #fffdf6; border: 2px solid #d3daca; border-radius: calc(16px * var(--u)); font-size: max(calc(24px * var(--u)), 15px); white-space: nowrap; }
#hud .ll-btn svg { width: calc(44px * var(--u)); height: calc(44px * var(--u)); min-width: 28px; min-height: 28px; }
#hud .ll-btn:hover { background: #f2f5e9; border-color: #99b09e; }
#hud .ll-btn:active { background: #e5eddc; border: 3px solid #557c5e; }
#hud .ll-act { position: absolute; left: 50%; transform: translateX(-50%); bottom: calc(env(safe-area-inset-bottom, 0px) + 24px * var(--u));
  min-width: calc(260px * var(--u)); min-height: max(calc(88px * var(--u)), 56px); padding: calc(10px * var(--u)) calc(24px * var(--u));
  gap: calc(10px * var(--u)); background: #557c5e; color: #fffdf6; border: none; border-radius: calc(16px * var(--u));
  font-size: max(calc(28px * var(--u)), 18px); white-space: nowrap; box-shadow: 0 calc(4px * var(--u)) calc(10px * var(--u)) rgba(51, 64, 51, 0.14); }
#hud .ll-act svg { width: calc(44px * var(--u)); height: calc(44px * var(--u)); min-width: 30px; min-height: 30px; }
#hud .ll-act:hover { background: #66896e; }
#hud .ll-act:active { background: #4d7055; }
#hud .ll-toast { position: absolute; left: 50%; top: calc(env(safe-area-inset-top, 0px) + 196px * var(--u)); transform: translateX(-50%);
  max-width: calc(100vw - 32px - env(safe-area-inset-left, 0px) - env(safe-area-inset-right, 0px)); box-sizing: border-box;
  background: #557c5e; color: #fffdf6; border-radius: calc(24px * var(--u)); padding: calc(16px * var(--u)) calc(20px * var(--u));
  font-size: max(calc(24px * var(--u)), 16px); text-align: center; box-shadow: 0 calc(4px * var(--u)) calc(10px * var(--u)) rgba(51, 64, 51, 0.14);
  opacity: 0; pointer-events: none; }
#hud .ll-stats { position: absolute; right: calc(env(safe-area-inset-right, 0px) + 8px); top: calc(env(safe-area-inset-top, 0px) + 8px);
  font: 12px/1.35 ui-monospace, Menlo, Consolas, monospace; color: #fff; background: rgba(0, 0, 0, 0.55); padding: 6px 8px;
  border-radius: 6px; white-space: pre; pointer-events: none; }
#hud [hidden] { display: none !important; }
`;

export async function init(app) {
  const root = document.getElementById('hud');
  const style = document.createElement('style');
  style.textContent = CSS;
  document.head.appendChild(style);
  // Godot's modulate Color(1, 0.92, 0.6) on the lit Look button, as a colour matrix
  root.insertAdjacentHTML('beforeend', '<svg class="ll-svgdefs" aria-hidden="true"><filter id="ll-lit" color-interpolation-filters="sRGB">'
    + '<feColorMatrix type="matrix" values="1 0 0 0 0  0 0.92 0 0 0  0 0 0.6 0 0  0 0 0 1 0"/></filter></svg>');

  const rig = () => app.cameraRig || null;
  const texts = [];   // [element, english, attribute or null]
  const say = (el, english, attr = null) => {
    const rec = texts.find((t) => t[0] === el && t[2] === attr);
    if (rec) rec[1] = english;
    else texts.push([el, english, attr]);
    const s = app.tr(english);
    if (attr) el.setAttribute(attr, s);
    else el.textContent = s;
  };
  const retranslate = () => {
    for (const [el, english, attr] of texts) {
      const s = app.tr(english);
      if (attr) el.setAttribute(attr, s);
      else el.textContent = s;
    }
    refreshWhere(true);
  };
  const button = (cls, icon, tip, onPress) => {
    const b = document.createElement('button');
    b.type = 'button';
    b.className = cls;
    b.tabIndex = -1;
    b.innerHTML = svg(icon);
    if (tip) {
      say(b, tip, 'title');
      say(b, tip, 'aria-label');
    }
    b.addEventListener('pointerdown', (e) => e.preventDefault());   // never takes focus (Godot's FOCUS_NONE)
    b.addEventListener('click', (e) => {
      e.preventDefault();
      onPress();
    });
    return b;
  };
  const setIcon = (b, icon) => {
    if (b.dataset.icon === icon) return;
    b.dataset.icon = icon;
    const old = b.querySelector('svg');
    if (old) old.outerHTML = svg(icon);
    else b.insertAdjacentHTML('afterbegin', svg(icon));
  };

  // ------------------------------------------------------------ the camera column (CameraButtons)
  const cam = document.createElement('div');
  cam.className = 'll-col ll-cam';
  cam.dataset.name = 'CameraButtons';
  const rotL = button('ll-icon', 'rotate_left', 'Rotate view left', () => rig() && rig().rotateStep(-1));
  const rotR = button('ll-icon', 'rotate_right', 'Rotate view right', () => rig() && rig().rotateStep(1));
  const zoom = button('ll-icon', 'zoom', 'Zoom', () => rig() && rig().toggleZoom());
  const reset = button('ll-icon', 'home', 'Reset view', () => rig() && rig().reset());
  const look = button('ll-icon', 'look', 'Look around', () => rig() && rig().setLook(!rig().isLooking()));
  const pause = button('ll-icon', 'pause', 'Pause the city', () => rig() && rig().setPaused(!rig().isPaused()));
  rotL.dataset.name = 'RotateLeft';
  rotR.dataset.name = 'RotateRight';
  zoom.dataset.name = 'Zoom';
  reset.dataset.name = 'CityReset';
  look.dataset.name = 'CityLook';
  pause.dataset.name = 'CityPause';
  pause.dataset.icon = 'pause';
  cam.append(rotL, rotR, zoom, reset, look, pause);
  root.appendChild(cam);

  // ------------------------------------------------------------ the weather (CityWeather)
  const wcol = document.createElement('div');
  wcol.className = 'll-col ll-weather';
  wcol.dataset.name = 'CityWeather';
  const weatherBtns = [];
  C.CityMap.WEATHERS.forEach((wname, i) => {
    const b = button('ll-glass', WEATHER_ICON[wname] || 'warn', WEATHER_TEXT[wname] || wname, () => app.send({ t: 'weather', w: i }));
    b.dataset.name = `Weather_${wname}`;
    weatherBtns.push(b);
    wcol.appendChild(b);
  });
  root.appendChild(wcol);

  // ------------------------------------------------------------ top left: where, Ride home
  const top = document.createElement('div');
  top.className = 'll-top';
  const where = document.createElement('span');
  where.className = 'll-where';
  const home = button('ll-btn', 'tram', null, () => app.send({ t: 'home' }));
  home.dataset.name = 'RideHome';
  const homeLabel = document.createElement('span');
  say(homeLabel, 'Ride home');
  home.appendChild(homeLabel);
  top.append(where, home);
  root.appendChild(top);

  // ------------------------------------------------------------ the action button and the toast
  const act = button('ll-act', 'door', null, () => app.send({ t: 'act' }));
  act.dataset.name = 'Action';
  const actLabel = document.createElement('span');
  act.appendChild(actLabel);
  act.hidden = true;
  root.appendChild(act);
  const toast = document.createElement('div');
  toast.className = 'll-toast';
  toast.setAttribute('role', 'status');
  root.appendChild(toast);
  let stats = null;
  if (app.params.get('stats') === '1') {
    stats = document.createElement('div');
    stats.className = 'll-stats';
    root.appendChild(stats);
    app.events.addEventListener('perf', () => {
      const s = app.perf.lastSample;
      if (!s) return;
      const f = (v, d = 1) => (typeof v === 'number' ? v.toFixed(d) : '-');
      stats.textContent = `fps ${f(s.fps)}\np50 ${f(s.p50, 2)} ms\np95 ${f(s.p95, 2)} ms\ncalls ${s.calls}\ntriangles ${s.triangles}`;
    });
  }

  // ------------------------------------------------------------ scale (Godot's canvas_items stretch, base 1366 x 1024)
  const relayout = () => {
    const w = window.innerWidth;
    const h = window.innerHeight;
    let u = Math.min(w / 1366, h / 1024);
    // the camera column (six 68 px buttons, 12 px apart) must fit the height on a phone held sideways
    u = Math.min(u, (h - 32) / (6 * 68 + 5 * 12));
    u = Math.max(0.5, Math.min(1.25, u));
    root.style.setProperty('--u', u.toFixed(4));
  };
  relayout();
  window.addEventListener('resize', relayout);

  // ------------------------------------------------------------ state
  const buildings = Object.keys(C.CityMap.BUILDINGS).map((id) => {
    const b = C.CityMap.BUILDINGS[id];
    const [x, y, wd, ht] = b.rect.rect;
    return { name: String(b.name), x, y, ex: x + wd, ey: y + ht };
  });
  for (const b of buildings) {
    if (!PAGE_STRINGS.includes(b.name)) console.warn(`hud: "${b.name}" is not in PAGE_STRINGS`);
  }
  let whereName = null;
  function refreshWhere(force) {
    const f = app.state.frame;
    let name = '';
    if (f && f.me && f.me.pos) {
      const px = f.me.pos[0];
      const pz = f.me.pos[1];
      for (let i = 0; i < buildings.length; i++) {
        const b = buildings[i];
        if (px >= b.x && px < b.ex && pz >= b.y && pz < b.ey) name = b.name;   // Rect2.has_point: end excluded
      }
    }
    if (!force && name === whereName) return;
    whereName = name;
    where.textContent = app.tr('City') + (name !== '' ? ` · ${app.tr(name)}` : '');
  }

  let ctxType = null;
  let ctxLabel = null;
  function refreshCtx() {
    const f = app.state.frame;
    const ctx = f && f.me ? f.me.ctx : null;
    if (!ctx || !ctx.type) {
      if (!act.hidden) act.hidden = true;
      ctxType = null;
      return;
    }
    if (act.hidden) act.hidden = false;
    if (ctx.type !== ctxType || ctx.label !== ctxLabel) {
      ctxType = ctx.type;
      ctxLabel = ctx.label;
      actLabel.textContent = String(ctx.label || '');   // translated by Godot
    }
    setIcon(act, ctx.icon || 'door');
  }

  function refreshLook() {
    const r = rig();
    const looking = !!(r && r.isLooking());
    const paused = !!(r && r.isPaused());
    look.classList.toggle('ll-lit', looking);
    const lt = looking ? 'Stop looking' : 'Look around';
    say(look, lt, 'title');
    say(look, lt, 'aria-label');
    pause.hidden = !looking;
    setIcon(pause, paused ? 'resume' : 'pause');
    const pt = paused ? 'Resume' : 'Pause the city';
    say(pause, pt, 'title');
    say(pause, pt, 'aria-label');
  }

  let weatherNow = -1;
  function refreshWeather() {
    const s = app.state.states;
    const cur = s && s.weather !== undefined ? Math.trunc(Number(s.weather)) : 0;
    if (cur === weatherNow) return;
    weatherNow = cur;
    for (let i = 0; i < weatherBtns.length; i++) weatherBtns[i].classList.toggle('ll-on', i === cur);
  }

  // hud.gd show_toast: fade in 0.15 s, stay 2.2 s, fade out 0.4 s (timed by the browser, not by the frames)
  const TOAST_ALL = TOAST_IN + TOAST_HOLD + TOAST_OUT;
  const TOAST_KEYS = [{ opacity: 0 }, { opacity: 1, offset: TOAST_IN / TOAST_ALL },
    { opacity: 1, offset: (TOAST_IN + TOAST_HOLD) / TOAST_ALL }, { opacity: 0 }];
  let toastAnim = null;
  function showToast(text) {
    toast.textContent = String(text || '');
    if (toastAnim) toastAnim.cancel();
    if (toast.animate) toastAnim = toast.animate(TOAST_KEYS, { duration: TOAST_ALL * 1000, fill: 'forwards' });
    else toast.style.opacity = '1';
  }

  app.events.addEventListener('look', refreshLook);
  app.events.addEventListener('pause', refreshLook);
  refreshLook();
  refreshWeather();
  refreshWhere(true);

  app.hud = {
    toast: showToast,
    buttons: { rotL, rotR, zoom, reset, look, pause, home, act, weather: weatherBtns },
    refresh() { refreshLook(); refreshWeather(); refreshCtx(); refreshWhere(true); },
  };

  return {
    onMessage(msg) {
      switch (msg.t) {
        case 'frame':
          refreshCtx();
          refreshWhere(false);
          break;
        case 'states':
          refreshWeather();
          break;
        case 'hello':
          retranslate();
          refreshLook();
          break;
        case 'toast':
        case 'hint':
          if (msg.text) showToast(msg.text);
          break;
        default:
          break;
      }
    },
  };
}
