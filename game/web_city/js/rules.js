// The city's shared rules that the page draws from (core/city_rules.gd, ported function by function).
// Only what drawing needs: the wheel, the weather blend. The authority's tick (seats, boarding, traffic)
// stays in Godot; the page receives its results in the City states.
//
// Ownership: the owner wrote this core; the world worker adds the vehicle and loop helpers below it; the
// people worker keeps its own rules (walkers, cover) in people_rules.js and imports from here.
import { C, fposmod, clamp } from './consts.js';

const TAU = Math.PI * 2;

export function ferrisPeriod() { return Number(C.CityMap.FERRIS.period); }

/** Angle of gondola i (0 = the lowest point of the wheel; it grows with time: bottom, east, top, west). */
export function gondolaAngle(i, t) {
  const n = Number(C.CityMap.FERRIS.gondolas);
  return TAU * fposmod(t / ferrisPeriod() + i / n, 1.0);
}

/** Where gondola i's floor centre is (it hangs level below its rim point), as [x, y, z]. */
export function gondolaPos(i, t) {
  const f = C.CityMap.FERRIS;
  const hub = f.hub;
  const a = gondolaAngle(i, t);
  const r = Number(f.radius);
  return [hub[0] + r * Math.sin(a), hub[1] - r * Math.cos(a) - Number(f.hang), hub[2]];
}

/**
 * The weather mix {sunny, rain, night} at time t from City states (client form: weather, since, prev;
 * prev is [x, y, z] as the bridge sends a Vector3). Sums to 1. CityRules.weather_weights.
 */
export function weatherWeights(state, t) {
  if (!state) return { sunny: 1, rain: 0, night: 0 };
  const w = Math.trunc(Number(state.weather ?? 0));
  const since = Number(state.since ?? state.weather_since ?? -1e9);
  const prev = state.prev ?? state.weather_prev ?? [1, 0, 0];
  const u = clamp((t - since) / Number(C.CityMap.WEATHER_BLEND), 0, 1);
  const e = u * u * (3 - 2 * u);
  const tw = clamp(w, 0, 2);
  let mx = Number(prev[0]) * (1 - e) + (tw === 0 ? e : 0);
  let my = Number(prev[1]) * (1 - e) + (tw === 1 ? e : 0);
  let mz = Number(prev[2]) * (1 - e) + (tw === 2 ? e : 0);
  const sum = mx + my + mz;
  if (sum > 1e-12) { mx /= sum; my /= sum; mz /= sum; }
  return { sunny: mx, rain: my, night: mz };
}

export function rainAmount(state, t) { return weatherWeights(state, t).rain; }

// ---------------------------------------------------------------- world worker: vehicles and loops
// Ported from core/city_rules.gd (poly_length, loop_length, poly_point, vehicle_pose) and
// world/city_world.gd (_loop_at). Points are [x, z] arrays (Godot's Vector2 on the ground).

/** The length of a closed polygon (CityRules.poly_length). */
export function polyLength(poly) {
  let total = 0;
  for (let i = 0; i < poly.length; i++) {
    const a = poly[i];
    const b = poly[(i + 1) % poly.length];
    total += Math.hypot(b[0] - a[0], b[1] - a[1]);
  }
  return total;
}

let _loopLen = -1;
let _loopFor = null;
/** The road loop's length (CityRules.loop_length), cached: ROAD_LOOP is a constant. */
export function loopLength() {
  if (_loopLen < 0 || _loopFor !== C) { _loopLen = polyLength(C.CityMap.ROAD_LOOP); _loopFor = C; }
  return _loopLen;
}

/**
 * A point at arc position s along a closed polygon (CityRules.poly_point): writes [x, z, dirx, dirz] into
 * `out` (a 4-array, reused by callers in hot paths) and returns it.
 */
export function polyPoint(poly, s, out = [0, 0, 0, 0], total = polyLength(poly)) {
  let rest = fposmod(s, total);
  for (let i = 0; i < poly.length; i++) {
    const a = poly[i];
    const b = poly[(i + 1) % poly.length];
    const seg = Math.hypot(b[0] - a[0], b[1] - a[1]);
    if (rest <= seg || i === poly.length - 1) {
      const dx = (b[0] - a[0]) / seg;
      const dz = (b[1] - a[1]) / seg;
      const m = Math.min(rest, seg);
      out[0] = a[0] + dx * m; out[1] = a[1] + dz * m; out[2] = dx; out[3] = dz;
      return out;
    }
    rest -= seg;
  }
  out[0] = poly[0][0]; out[1] = poly[0][1]; out[2] = 1; out[3] = 0;
  return out;
}

/**
 * A vehicle's pose at arc position s on ROAD_LOOP (CityRules.vehicle_pose, without kind and colour):
 * writes [x, z, ry] into `out` and returns it. ry = atan2(dir.x, dir.z) (forward is (sin ry, cos ry)).
 */
const _pp = [0, 0, 0, 0];
export function vehiclePose(i, s, out = [0, 0, 0]) {
  polyPoint(C.CityMap.ROAD_LOOP, s, _pp, loopLength());
  out[0] = _pp[0]; out[1] = _pp[1]; out[2] = Math.atan2(_pp[2], _pp[3]);
  return out;
}

/** A point and direction a fraction t along a closed loop, by length (CityWorld._loop_at): [x, z, dirx, dirz]. */
export function loopAt(loop, t, out = [0, 0, 0, 0]) {
  const total = polyLength(loop);
  let s = fposmod(t, 1.0) * total;
  for (let i = 0; i < loop.length; i++) {
    const p0 = loop[i];
    const p1 = loop[(i + 1) % loop.length];
    const seg = Math.hypot(p1[0] - p0[0], p1[1] - p0[1]);
    if (s <= seg) {
      const k = s / seg;
      out[0] = p0[0] + (p1[0] - p0[0]) * k; out[1] = p0[1] + (p1[1] - p0[1]) * k;
      out[2] = (p1[0] - p0[0]) / seg; out[3] = (p1[1] - p0[1]) / seg;
      return out;
    }
    s -= seg;
  }
  out[0] = loop[0][0]; out[1] = loop[0][1]; out[2] = 1; out[3] = 0;
  return out;
}
