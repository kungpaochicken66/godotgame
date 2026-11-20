// The city's camera maths, ported function by function from game/scripts/world/city_orbit.gd (pure functions,
// no DOM, no THREE: importable in Node). Every number comes from C.CityOrbit and C.CityMap (data/consts.json).
//
// Conventions of the port (Godot -> JS):
//   Vector2 / Vector3            [x, y] / [x, y, z]
//   Transform3D                  {basis: [xx, xy, xz, yx, yy, yz, zx, zy, zz] (the x, y, z columns), origin: [x, y, z]}
//                                (the camera looks along -z of its basis, as Godot's and three.js's cameras do)
//   a view state (Dictionary)    {yaw, pitch, distance, out, pan?: [x, 0, z], focus?: [x, y, z]}
//   a pose (Dictionary)          {yaw, pitch, distance, focus: [3], xform}
//   a gesture (Dictionary)       {button, source, on, start: [2], last: [2], t0, scale, moved, mode, delta: [2], pinched}
// Functions that run every frame (pose, smooth, glide, pose_xform, apply_pan, max_distance) take an optional
// `out` object to fill instead of allocating; gesture_move updates its gesture in place and returns it (the
// play controller always replaces its gesture with the result, so the Godot semantics hold).
// Godot computes Vector3 / Transform3D in 32-bit floats; this port computes in doubles (parity tolerances
// in scripts/web_city/camera.test.mjs).
import { C } from './consts.js';

const TAU = Math.PI * 2;
const DEG = Math.PI / 180;

/** C.CityOrbit (the constants of city_orbit.gd). */
export const K = () => C.CityOrbit;

// ------------------------------------------------------------------ Godot built-ins, exactly

/** Godot's fposmod. */
export function fposmod(x, y) {
  let v = x % y;
  if ((v < 0 && y > 0) || (v > 0 && y < 0)) v += y;
  return v + 0.0;
}

/** Godot's angle_difference (fmod form, as in core/math/math_funcs.h). */
export function angleDifference(from, to) {
  const d = (to - from) % TAU;
  return ((2.0 * d) % TAU) - d;
}

export const clampf = (v, lo, hi) => (v < lo ? lo : (v > hi ? hi : v));
const lerpf = (a, b, t) => a + (b - a) * t;

// ------------------------------------------------------------------ the camera pose

/** Fills `out` (or a new Transform) with Basis.looking_at(-offset.normalized(), UP) at focus + offset. */
export function poseXform(focus, yaw, pitch, distance, out) {
  const o = out || { basis: new Array(9).fill(0), origin: [0, 0, 0] };
  const cp = Math.cos(pitch);
  const ox = Math.sin(yaw) * cp * distance;
  const oy = Math.sin(pitch) * distance;
  const oz = Math.cos(yaw) * cp * distance;
  // looking_at(target = -offset/|offset|): v_z = -target = offset/|offset|; v_x = UP x v_z; v_y = v_z x v_x
  const len = Math.hypot(ox, oy, oz);
  let zx = 0, zy = 0, zz = 0;
  if (len > 0) { zx = ox / len; zy = oy / len; zz = oz / len; }
  // UP (0,1,0) x (zx,zy,zz) = (zz, 0, -zx)
  let xx = zz, xy = 0, xz = -zx;
  const xl = Math.hypot(xx, xy, xz);
  if (xl < 1e-5) {   // looking straight down or up: Godot warns and takes UP.get_any_perpendicular() = (0, 0, 1) x ... ; never in the city
    xx = 1; xy = 0; xz = 0;
  } else { xx /= xl; xy /= xl; xz /= xl; }
  const yx = zy * xz - zz * xy;
  const yy = zz * xx - zx * xz;
  const yz = zx * xy - zy * xx;
  const b = o.basis;
  b[0] = xx; b[1] = xy; b[2] = xz;
  b[3] = yx; b[4] = yy; b[5] = yz;
  b[6] = zx; b[7] = zy; b[8] = zz;
  o.origin[0] = focus[0] + ox;
  o.origin[1] = focus[1] + oy;
  o.origin[2] = focus[2] + oz;
  return o;
}

/** xf.affine_inverse() * p for an orthonormal camera basis, into out [3]. */
function toView(xf, px, py, pz, out) {
  const b = xf.basis;
  const dx = px - xf.origin[0];
  const dy = py - xf.origin[1];
  const dz = pz - xf.origin[2];
  out[0] = b[0] * dx + b[1] * dy + b[2] * dz;
  out[1] = b[3] * dx + b[4] * dy + b[5] * dz;
  out[2] = b[6] * dx + b[7] * dy + b[8] * dz;
  return out;
}

const _v = [0, 0, 0];

/** Where a world point lands on screen (pixels) for a pose; null behind the camera. */
export function project(xf, view, p) {
  const v = toView(xf, p[0], p[1], p[2], _v);
  if (v[2] > -0.05) return null;
  const half = Math.tan(K().FOV * DEG * 0.5);
  return [view[0] * 0.5 + v[0] / (-v[2] * half) * view[1] * 0.5, view[1] * 0.5 - v[1] / (-v[2] * half) * view[1] * 0.5];
}

/** The world ray through a screen point: {origin: [3], dir: [3] (unit)}. */
export function ray(xf, view, screen) {
  const half = Math.tan(K().FOV * DEG * 0.5);
  const x = (screen[0] - view[0] * 0.5) / (view[1] * 0.5) * half;
  const y = -(screen[1] - view[1] * 0.5) / (view[1] * 0.5) * half;
  const b = xf.basis;
  // basis * (x, y, -1): columns x, y, z
  let dx = b[0] * x + b[3] * y - b[6];
  let dy = b[1] * x + b[4] * y - b[7];
  let dz = b[2] * x + b[5] * y - b[8];
  const l = Math.hypot(dx, dy, dz);
  dx /= l; dy /= l; dz /= l;
  return { origin: [xf.origin[0], xf.origin[1], xf.origin[2]], dir: [dx, dy, dz] };
}

let _ptsFor = null;
let _pts = null;

/** Points the overview must show: the ground of the map plus MARGIN, the buildings' roofs, the wheel. */
export function overviewPoints() {
  if (_ptsFor === C && _pts) return _pts;
  const M = C.CityMap;
  const hx = M.HALF[0] + K().MARGIN;
  const hz = M.HALF[1] + K().MARGIN;
  const pts = [];
  for (const sx of [-1.0, 1.0]) {
    for (const sz of [-1.0, 1.0]) pts.push([sx * hx, 0.0, sz * hz]);
  }
  for (const id of Object.keys(M.BUILDINGS)) {
    const b = M.BUILDINGS[id];
    const [x, y0, w, h] = b.rect.rect;
    const y = Number(b.roof);
    for (const c of [[x, y0], [x + w, y0], [x + w, y0 + h], [x, y0 + h]]) pts.push([c[0], y, c[1]]);
  }
  const f = M.FERRIS;
  const hub = f.hub;
  const rad = Number(f.radius);
  pts.push([hub[0] - rad, hub[1], hub[2]]);
  pts.push([hub[0] + rad, hub[1], hub[2]]);
  pts.push([hub[0], hub[1] + rad + 0.5, hub[2]]);
  _pts = pts;
  _ptsFor = C;
  return pts;
}

const OVERVIEW_FOCUS = [0.0, 1.5, 0.0];

/** The middle of the block (what the overview looks at). */
export function overviewFocus(out) {
  const o = out || [0, 0, 0];
  o[0] = OVERVIEW_FOCUS[0]; o[1] = OVERVIEW_FOCUS[1]; o[2] = OVERVIEW_FOCUS[2];
  return o;
}

const _fitXf = { basis: new Array(9).fill(0), origin: [0, 0, 0] };

export function fits(pts, focus, yaw, pitch, d, aspect) {
  const xf = poseXform(focus, yaw, pitch, d, _fitXf);
  const tv = Math.tan(K().FOV * DEG * 0.5);
  const th = tv * aspect;
  const fill = K().FIT_FILL;
  for (let i = 0; i < pts.length; i++) {
    const p = pts[i];
    const v = toView(xf, p[0], p[1], p[2], _v);
    if (v[2] > -0.5) return false;
    if (Math.abs(v[0]) > -v[2] * th * fill || Math.abs(v[1]) > -v[2] * tv * fill) return false;
  }
  return true;
}

/** The smallest distance at which `pts` fit the frame (aspect = width / height) for a focus, yaw and pitch. */
export function fitDistance(pts, focus, yaw, pitch, aspect) {
  let lo = 5.0;
  let hi = 600.0;
  for (let i = 0; i < 40; i++) {
    const mid = (lo + hi) * 0.5;
    if (fits(pts, focus, yaw, pitch, mid, aspect)) hi = mid;
    else lo = mid;
  }
  return hi;
}

// max_distance runs 40 bisections every frame in Godot; the result depends only on (aspect, yaw, pitch), so
// a small cache returns the same number without the work.
const MAX_CACHE = 8;
const _maxKeys = new Float64Array(MAX_CACHE * 3).fill(NaN);
const _maxVals = new Float64Array(MAX_CACHE);
let _maxNext = 0;
let _maxFor = null;

/** The zoom-out limit for a yaw: the whole block (HALF + MARGIN) in view. */
export function maxDistance(aspect, yaw = 0.0, pitch = undefined) {
  const p = pitch === undefined ? K().PITCH_OVERVIEW : pitch;
  if (_maxFor !== C) { _maxKeys.fill(NaN); _maxFor = C; }
  for (let i = 0; i < MAX_CACHE; i++) {
    if (_maxKeys[i * 3] === aspect && _maxKeys[i * 3 + 1] === yaw && _maxKeys[i * 3 + 2] === p) return _maxVals[i];
  }
  const d = fitDistance(overviewPoints(), OVERVIEW_FOCUS, yaw, p, aspect);
  const k = _maxNext;
  _maxNext = (_maxNext + 1) % MAX_CACHE;
  _maxKeys[k * 3] = aspect; _maxKeys[k * 3 + 1] = yaw; _maxKeys[k * 3 + 2] = p;
  _maxVals[k] = d;
  return d;
}

/** The overview state: looking north from the south at 45 degrees, the whole block in the frame. */
export function overview(aspect) {
  return { yaw: 0.0, pitch: K().PITCH_OVERVIEW, distance: maxDistance(aspect, 0.0, K().PITCH_OVERVIEW), out: true };
}

/** Reset view's former target and the zoom-out end: the overview. */
export function reset(aspect) { return overview(aspect); }

/** dest-fix r1: the strolling view (CityOrbit.stroll): the camera follows the child at zoom level STROLL_LEVEL. */
export function stroll(aspect) {
  const levels = zoomLevels(aspect, 0.0, K().PITCH_OVERVIEW);
  return { yaw: 0.0, pitch: K().PITCH_OVERVIEW, distance: Number(levels[K().STROLL_LEVEL]), out: false };
}

const dup = (s) => {
  const o = { ...s };
  if (s.pan) o.pan = s.pan.slice();
  if (s.focus) o.focus = s.focus.slice();
  return o;
};

/** Keep a state inside its limits (distance within [DIST_MIN, the zoom-out limit], pitch within its range). */
export function clampState(s, aspect) {
  const out = dup(s);
  out.pitch = clampf(Number(s.pitch), K().PITCH_MIN, K().PITCH_MAX);
  out.yaw = wrapYaw(Number(s.yaw));
  const top = maxDistance(aspect, out.yaw, out.pitch);
  const d = clampf(Number(s.distance), K().DIST_MIN, top);
  out.distance = d;
  out.out = d >= top - 1e-3;
  return out;
}

export function wrapYaw(y) { return fposmod(y + Math.PI, TAU) - Math.PI; }

const ZERO3 = [0, 0, 0];
const _childLift = [0, 0, 0];

/** A new, empty pose to fill (pose, smooth, glide). */
export function newPose() {
  return { yaw: 0, pitch: 0, distance: 0, focus: [0, 0, 0], xform: { basis: new Array(9).fill(0), origin: [0, 0, 0] } };
}

/** The pose for a state: the focus slides from the middle of the block to the child as the camera comes in. */
export function pose(s, aspect, child, out) {
  const o = out || newPose();
  const yaw = s.yaw;
  const pitch = s.pitch;
  let d = s.distance;
  const top = maxDistance(aspect, yaw, pitch);
  if (s.out) d = top;
  let w = clampf((top - d) / (top * (1.0 - K().FOLLOW_FULL)), 0.0, 1.0);
  w = w * w * (3.0 - 2.0 * w);
  const f = o.focus;
  if (s.focus) {
    // a Look view (look_state) looks at its own place, whoever the child is
    f[0] = s.focus[0]; f[1] = s.focus[1]; f[2] = s.focus[2];
  } else {
    _childLift[0] = child[0]; _childLift[1] = child[1] + K().FOCUS_LIFT; _childLift[2] = child[2];
    f[0] = lerpf(OVERVIEW_FOCUS[0], _childLift[0], w);
    f[1] = lerpf(OVERVIEW_FOCUS[1], _childLift[1], w);
    f[2] = lerpf(OVERVIEW_FOCUS[2], _childLift[2], w);
  }
  applyPan(f, s.pan || ZERO3, f);
  o.yaw = yaw; o.pitch = pitch; o.distance = d;
  poseXform(f, yaw, pitch, d, o.xform);
  return o;
}

let _boundsFor = null;
let _bounds = null;

/** The ground rectangle the focus may be panned within: the lot plus PAN_MARGIN, as {x, y, ex, ey}. */
export function panBounds() {
  if (_boundsFor === C && _bounds) return _bounds;
  const [x, y, w, h] = C.CityMap.LOT.rect;
  const m = K().PAN_MARGIN;
  _bounds = { x: x - m, y: y - m, ex: x + w + m, ey: y + h + m };
  _boundsFor = C;
  return _bounds;
}

/** base + pan, kept within pan_bounds() along each axis (a base already outside is not pulled back). */
export function applyPan(base, pan, out) {
  const b = panBounds();
  const o = out || [0, 0, 0];
  const bx = base[0], by = base[1], bz = base[2];
  o[0] = clampf(bx + pan[0], Math.min(b.x, bx), Math.max(b.ex, bx));
  o[1] = by;
  o[2] = clampf(bz + pan[2], Math.min(b.y, bz), Math.max(b.ey, bz));
  return o;
}

/** The close follow pose: centred on the child at the state's distance. */
export function followPose(s, child) {
  const focus = applyPan([child[0], child[1] + K().FOCUS_LIFT, child[2]], s.pan || ZERO3);
  return { yaw: s.yaw, pitch: s.pitch, distance: s.distance, focus, xform: poseXform(focus, s.yaw, s.pitch, s.distance) };
}

// ------------------------------------------------------------------ orbit and zoom

/** A drag of delta_px orbits: yaw is free, pitch stays in its range; view_h scales the sensitivity. */
export function orbit(s, deltaPx, viewH = 1080.0, aspect = 16.0 / 9.0) {
  const k = 1080.0 / Math.max(viewH, 1.0);
  const out = dup(s);
  out.yaw = wrapYaw(Number(s.yaw) - deltaPx[0] * k * K().ORBIT_YAW_PER_PX);
  out.pitch = clampf(Number(s.pitch) + deltaPx[1] * k * K().ORBIT_PITCH_PER_PX, K().PITCH_MIN, K().PITCH_MAX);
  if (s.out) out.distance = maxDistance(aspect, out.yaw, out.pitch);
  else out.distance = Math.min(Number(s.distance), maxDistance(aspect, out.yaw, out.pitch));
  return out;
}

/** Right-drag pan: moves the state's ground pan so the ground follows the cursor, within pan_bounds(). */
export function pan(s, deltaPx, viewH, aspect) {
  const out = dup(s);
  const yaw = s.yaw;
  const pitch = s.pitch;
  const d = s.out ? maxDistance(aspect, yaw, pitch) : Number(s.distance);
  const perPx = 2.0 * d * Math.tan(K().FOV * DEG * 0.5) / Math.max(viewH, 1.0);
  const rx = Math.cos(yaw), rz = -Math.sin(yaw);
  const fx = -Math.sin(yaw), fz = -Math.cos(yaw);
  const cur = s.pan || ZERO3;
  const along = deltaPx[1] * perPx / Math.max(Math.sin(pitch), 0.2);
  let nx = cur[0] - rx * deltaPx[0] * perPx + fx * along;
  let nz = cur[2] - rz * deltaPx[0] * perPx + fz * along;
  const b = panBounds();
  nx = clampf(nx, b.x, b.ex);
  nz = clampf(nz, b.y, b.ey);
  out.pan = [nx, 0.0, nz];
  return out;
}

/** Zoom by a factor (> 1: closer): distance / factor within its limits. */
export function zoom(s, factor, aspect) {
  const out = dup(s);
  const top = maxDistance(aspect, Number(s.yaw), Number(s.pitch));
  let d = Number(s.distance);
  if (s.out) d = top;
  d = clampf(d / Math.max(factor, 0.01), K().DIST_MIN, top);
  out.distance = d;
  out.out = d >= top - 1e-3;
  return out;
}

/** The zoom factor of a pinch whose finger distance went from `prev` to `cur`. */
export function pinchFactor(prev, cur) {
  if (prev < 1e-3) return 1.0;
  return clampf(cur / prev, K().PINCH_MIN, K().PINCH_MAX);
}

/** The zoom factor of mouse-wheel notches (positive: forward, closer). */
export function wheelFactor(notches) { return Math.pow(K().WHEEL_BASE, notches); }

/** Turn by one YAW_STEP (dir +1 / -1); a free yaw goes to the next grid line. */
export function stepYaw(s, dir) {
  const out = dup(s);
  const k = Number(s.yaw) / K().YAW_STEP;
  const target = dir > 0 ? Math.floor(k + 1e-6) + 1.0 : Math.ceil(k - 1e-6) - 1.0;
  out.yaw = wrapYaw(target * K().YAW_STEP);
  if (s.out) out.distance = maxDistance(16.0 / 9.0, out.yaw, Number(s.pitch));   // 16:9, as Godot does
  return out;
}

/** The discrete zoom distances (closest first): ZOOM_LEVELS steps, geometric between DIST_MIN and the limit. */
export function zoomLevels(aspect, yaw, pitch) {
  const top = maxDistance(aspect, yaw, pitch);
  const n = K().ZOOM_LEVELS;
  const out = [];
  for (let i = 0; i < n; i++) out.push(K().DIST_MIN * Math.pow(top / K().DIST_MIN, i / (n - 1)));
  return out;
}

/** One zoom level (dir +1 closer, -1 farther), clamped. */
export function stepZoom(s, dir, aspect) {
  const out = dup(s);
  const levels = zoomLevels(aspect, Number(s.yaw), Number(s.pitch));
  const d = s.out ? levels[levels.length - 1] : Number(s.distance);
  let idx = 0;
  let best = Infinity;
  for (let i = 0; i < levels.length; i++) {
    const e = Math.abs(Math.log(d) - Math.log(levels[i]));
    if (e < best) { best = e; idx = i; }
  }
  idx = Math.min(Math.max(idx - dir, 0), levels.length - 1);
  out.distance = levels[idx];
  out.out = idx === levels.length - 1;
  return out;
}

/** Glide a pose toward its goal; reduce motion snaps. Fills `out` (may be `cur` itself). */
export function smooth(cur, goal, dt, reduceMotion, out) {
  const o = out || newPose();
  if (reduceMotion) return copyPose(goal, o);
  const k = 1.0 - Math.exp(-K().SMOOTH_RATE * Math.max(dt, 0.0));
  const yaw = cur.yaw;
  const ny = wrapYaw(yaw + angleDifference(yaw, goal.yaw) * k);
  const np = lerpf(cur.pitch, goal.pitch, k);
  const nd = lerpf(cur.distance, goal.distance, k);
  const fx = lerpf(cur.focus[0], goal.focus[0], k);
  const fy = lerpf(cur.focus[1], goal.focus[1], k);
  const fz = lerpf(cur.focus[2], goal.focus[2], k);
  o.yaw = ny; o.pitch = np; o.distance = nd;
  o.focus[0] = fx; o.focus[1] = fy; o.focus[2] = fz;
  poseXform(o.focus, ny, np, nd, o.xform);
  return o;
}

/** Copies a pose into `out` (a fresh pose when omitted); the xform is recomputed as Godot's duplicate keeps it. */
export function copyPose(src, out) {
  const o = out || newPose();
  o.yaw = src.yaw; o.pitch = src.pitch; o.distance = src.distance;
  o.focus[0] = src.focus[0]; o.focus[1] = src.focus[1]; o.focus[2] = src.focus[2];
  if (src.xform) {
    for (let i = 0; i < 9; i++) o.xform.basis[i] = src.xform.basis[i];
    o.xform.origin[0] = src.xform.origin[0]; o.xform.origin[1] = src.xform.origin[1]; o.xform.origin[2] = src.xform.origin[2];
  } else {
    poseXform(o.focus, o.yaw, o.pitch, o.distance, o.xform);
  }
  return o;
}

// ------------------------------------------------------------------ gesture arbitration

/** Start a gesture (source "touch" | "mouse" | "pointer"; started_on "ground" | "thing" | "ui"). */
export function gestureNew(source, startedOn, pos, t, scale = 1.0, button = 'left') {
  return { button, source, on: startedOn, start: [pos[0], pos[1]], last: [pos[0], pos[1]], t0: t, scale,
    moved: 0.0, mode: 'pending', delta: [0, 0], pinched: false };
}

/** Feed a move (fingers = fingers down now); updates g in place and returns it. See city_orbit.gd. */
export function gestureMove(g, pos, _t, fingers = 1) {
  g.delta[0] = pos[0] - g.last[0];
  g.delta[1] = pos[1] - g.last[1];
  g.last[0] = pos[0];
  g.last[1] = pos[1];
  if (g.source === 'pointer') return g;
  const dist = Math.hypot(pos[0] - g.start[0], pos[1] - g.start[1]);
  if ((g.button || 'left') === 'right') {
    // a right drag pans, wherever it starts; it is never a tap
    g.moved = Math.max(g.moved, dist);
    if (g.moved > K().DRAG_PX * g.scale || g.mode === 'pan') g.mode = 'pan';
    return g;
  }
  if (fingers >= 2) {
    g.pinched = true;
    g.mode = 'pinch';
    return g;
  }
  if (g.pinched) {
    g.mode = 'none';
    return g;
  }
  g.moved = Math.max(g.moved, dist);
  if (g.mode === 'pending' && g.moved > K().DRAG_PX * g.scale) g.mode = g.on === 'ground' ? 'orbit' : 'none';
  else if (g.mode === 'pinch') g.mode = 'none';
  return g;
}

/** The gesture ended at time t: "tap", "hold" or "none". */
export function gestureEnd(g, t) {
  if ((g.button || 'left') === 'right') return 'none';
  if (g.source === 'pointer') return t - g.t0 <= K().TAP_SEC * 2.0 ? 'tap' : 'hold';
  if (g.mode !== 'pending' || g.pinched) return 'none';
  if (g.moved > K().DRAG_PX * g.scale) return 'none';
  return t - g.t0 <= K().TAP_SEC ? 'tap' : 'hold';
}

// ------------------------------------------------------------------ Look (city r2)

/** The pose of a Look view for a LOOK_PLACES key: {yaw, pitch, distance, out: false, focus}. */
export function lookState(key, aspect) {
  const lp = C.CityMap.LOOK_PLACES[key];
  let d = Number(lp.distance);
  if (aspect < 16.0 / 9.0) d *= Math.min((16.0 / 9.0) / Math.max(aspect, 0.1), 1.8);
  const yaw = Number(lp.yaw);
  const pitch = Number(lp.pitch) * DEG;
  d = Math.min(d, maxDistance(aspect, yaw, pitch));
  return { yaw, pitch, distance: d, out: false, focus: lp.focus.slice() };
}

function slab(o, d, lo, hi, out) {
  if (Math.abs(d) < 1e-12) {
    if (o >= lo && o <= hi) { out[0] = -Infinity; out[1] = Infinity; } else { out[0] = 1.0; out[1] = 0.0; }
    return out;
  }
  const a = (lo - o) / d;
  const b = (hi - o) / d;
  out[0] = Math.min(a, b); out[1] = Math.max(a, b);
  return out;
}

/** Interval of a ray inside a cylinder of radius r about c (ax 1: the axis is y; ax 2: the axis is z). */
function cyl(o, d, cx, cy, r, ax, out) {
  const ox = o[0] - cx;
  const oa = ax === 1 ? o[2] - cy : o[1] - cy;
  const dx = d[0];
  const da = ax === 1 ? d[2] : d[1];
  const qa = dx * dx + da * da;
  if (qa < 1e-12) {
    if (ox * ox + oa * oa <= r * r) { out[0] = -Infinity; out[1] = Infinity; } else { out[0] = 1.0; out[1] = 0.0; }
    return out;
  }
  const qb = 2.0 * (ox * dx + oa * da);
  const qc = ox * ox + oa * oa - r * r;
  const disc = qb * qb - 4.0 * qa * qc;
  if (disc < 0.0) { out[0] = 1.0; out[1] = 0.0; return out; }
  const sq = Math.sqrt(disc);
  out[0] = (-qb - sq) / (2.0 * qa);
  out[1] = (-qb + sq) / (2.0 * qa);
  return out;
}

const _iv = [0, 0];
const _b = [0, 0];
function isect(b) {
  _iv[0] = Math.max(_iv[0], b[0]);
  _iv[1] = Math.min(_iv[1], b[1]);
}

/** The LOOK_PLACES key a ray meets first, else "". */
export function pickPlace(origin, dir) {
  let best = '';
  let bestT = Infinity;
  const places = C.CityMap.LOOK_PLACES;
  for (const key of Object.keys(places)) {
    const lp = places[key];
    _iv[0] = -Infinity; _iv[1] = Infinity;
    if (lp.rect !== undefined) {
      const [rx, ry, rw, rh] = lp.rect.rect;
      const y = lp.y;
      isect(slab(origin[0], dir[0], rx, rx + rw, _b));
      isect(slab(origin[1], dir[1], y[0], y[1], _b));
      isect(slab(origin[2], dir[2], ry, ry + rh, _b));
    } else if (lp.disc) {
      const f = C.CityMap.FERRIS;
      const hub = f.hub;
      isect(slab(origin[2], dir[2], hub[2] - 0.8, hub[2] + 0.8, _b));
      isect(cyl(origin, dir, hub[0], hub[1], Number(f.radius) + 0.8, 2, _b));
    } else if (lp.circle !== undefined) {
      const c = lp.focus;
      const y2 = lp.y;
      isect(slab(origin[1], dir[1], y2[0], y2[1], _b));
      isect(cyl(origin, dir, c[0], c[2], Number(lp.circle), 1, _b));
    }
    const tIn = Math.max(_iv[0], 0.0);
    if (_iv[0] <= _iv[1] && _iv[1] >= 0.0 && tIn < bestT) {
      bestT = tIn;
      best = key;
    }
  }
  return best;
}

/** Between two poses, u in 0..1 eased (smoothstep); fills `out` (never `from`). */
export function glide(from, to, u, out) {
  const o = out || newPose();
  const k = clampf(u, 0.0, 1.0);
  const src = k <= 0.0 ? from : (k >= 1.0 ? to : null);
  if (src) {
    o.yaw = src.yaw; o.pitch = src.pitch; o.distance = src.distance;
    o.focus[0] = src.focus[0]; o.focus[1] = src.focus[1]; o.focus[2] = src.focus[2];
    poseXform(o.focus, o.yaw, o.pitch, o.distance, o.xform);
    return o;
  }
  const e = k * k * (3.0 - 2.0 * k);
  const yaw = from.yaw;
  const ny = wrapYaw(yaw + angleDifference(yaw, to.yaw) * e);
  const np = lerpf(from.pitch, to.pitch, e);
  const nd = lerpf(from.distance, to.distance, e);
  const fx = lerpf(from.focus[0], to.focus[0], e);
  const fy = lerpf(from.focus[1], to.focus[1], e);
  const fz = lerpf(from.focus[2], to.focus[2], e);
  o.yaw = ny; o.pitch = np; o.distance = nd;
  o.focus[0] = fx; o.focus[1] = fy; o.focus[2] = fz;
  poseXform(o.focus, ny, np, nd, o.xform);
  return o;
}
