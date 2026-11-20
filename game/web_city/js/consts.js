// The city's constants, exported from the Godot scripts (tests/web_city/export.gd -> data/consts.json), and
// the helpers that read Godot's JSON convention (scripts/web/web_json.gd). Ports read every number from here,
// never retype one: C.CityMap.WEATHER_BLEND, C.CityRules.<CONST>, C.PeopleData.PEOPLE, ...
//
//   Vector2 -> [x, y]; Vector3 -> [x, y, z]; Rect2 -> {rect: [x, y, w, h]}; Color -> {color: [r, g, b, a]}
//   (sRGB-encoded, as written in Godot); Transform3D -> {xf: [12]}; Basis -> {basis: [9]};
//   Quaternion -> {quat: [x, y, z, w]}; Dictionary keys are strings (an int key 3 is "3").
import * as THREE from '../vendor/three.module.js';

export let C = null;

export async function loadConsts(url = 'data/consts.json') {
  const r = await fetch(url);
  if (!r.ok) throw new Error(`consts: HTTP ${r.status}`);
  C = await r.json();
  return C;
}

/** For Node tests: install an already parsed consts object. */
export function setConsts(obj) { C = obj; return C; }

export const isRect = (o) => o && typeof o === 'object' && Array.isArray(o.rect);
export const isColor = (o) => o && typeof o === 'object' && Array.isArray(o.color);

/** A Rect2 as {x, y, w, h, ex, ey} (ex, ey = the end corner). */
export function rect(o) {
  const [x, y, w, h] = o.rect;
  return { x, y, w, h, ex: x + w, ey: y + h };
}

export function rectHas(r, px, py, eps = 0) {
  return px >= r.x - eps && px <= r.ex + eps && py >= r.y - eps && py <= r.ey + eps;
}

/** A Godot Color as a THREE.Color in the renderer's working (linear) space. */
export function color(o, out = new THREE.Color()) {
  const c = Array.isArray(o) ? o : o.color;
  return out.setRGB(c[0], c[1], c[2], THREE.SRGBColorSpace);
}

/** Godot's Color.lightened / darkened on sRGB values (PropsCity.col's "shade"), returned as raw sRGB [r,g,b,a]. */
export function shadeSrgb(c, amount) {
  const [r, g, b, a] = Array.isArray(c) ? c : c.color;
  if (amount >= 0) return [r + (1 - r) * amount, g + (1 - g) * amount, b + (1 - b) * amount, a];
  const k = 1 + amount;
  return [r * k, g * k, b * k, a];
}

export const v3 = (a) => new THREE.Vector3(a[0], a[1], a[2]);

// GDScript built-ins that ports use, with Godot's exact behaviour.
export const clamp = (x, a, b) => Math.min(Math.max(x, a), b);
export const lerp = (a, b, t) => a + (b - a) * t;
export const smoothstep = (a, b, x) => {
  if (Math.abs(a - b) < 1e-5) return x <= a ? 0 : 1;   // Godot 4: equal edges -> a step
  const t = clamp((x - a) / (b - a), 0, 1);
  return t * t * (3 - 2 * t);
};
/** Godot's fposmod: always in [0, b). */
export const fposmod = (a, b) => { const r = a % b; return r < 0 ? r + b : r; };
/** Godot's posmod on ints. */
export const posmod = (a, b) => { const r = a % b; return r < 0 ? r + b : r; };
export const TAU = Math.PI * 2;
/** Godot's lerp_angle. */
export function lerpAngle(from, to, w) {
  const diff = fposmod(to - from, TAU);
  const dist = fposmod(2 * diff, TAU) - diff;
  return from + dist * w;
}
/** Godot's angle_difference (to - from, wrapped to [-PI, PI]). */
export function angleDifference(from, to) {
  const diff = fposmod(to - from, TAU);
  return fposmod(2 * diff, TAU) - diff;
}
