// The people's pure rules, ported function by function:
//   core/city_people_data.gd   hash01, seed_of, timing, floor_y, the Ferris passengers' timetable (pair_ride,
//                              ferris_rides, gondola_lap), umbrella_for, group_delay
//   core/city_rules.gd         the walkers: poly_point, poly_project, walker_pose (walk_loops() itself is found
//                              from the map at load in Godot and exported: consts.extra.people.walk_loops)
//   world/city_world.gd        where a rider sits: rider_transform (the wheel), carousel_seat_transform
// Vector arithmetic is single precision where Godot's is (people_math.js): the walkers' arc positions are
// compared with thresholds by the rain rules, so they must come out as in Godot, not merely close.
// Nothing here allocates per call: results go into the `out` the caller passes, or into pooled temporaries.
// No DOM, no Three.js: importable in Node.
import { C } from './consts.js';
import { gondolaAngle } from './rules.js';
import { f, fposmod, posmod, dist2, TAU, rotY, xOf, xMul, xPointc, V } from './people_math.js';

// ---------------------------------------------------------------- hashing (the same on every device)

function mix(x) {
  x >>>= 0;
  x = Math.imul(x ^ (x >>> 16), 0x45d9f3b) >>> 0;
  x = Math.imul(x ^ (x >>> 16), 0x45d9f3b) >>> 0;
  return (x ^ (x >>> 16)) >>> 0;
}

/** A number in [0, 1) from two integers (Data.hash01). */
export function hash01(a, b = 0) {
  const x = Math.imul(a & 0x0FFFFFFF, 0x9E3779B1) ^ Math.imul(b & 0x0FFFFFFF, 0x85EBCA77);
  return mix(x ^ 0x165667B1) / 4294967296.0;
}

/** A 32-bit seed from a string (FNV-1a over its UTF-8 bytes; the ids are ASCII). */
export function seedOf(id) {
  let h = 2166136261;
  for (let i = 0; i < id.length; i++) {
    let c = id.charCodeAt(i);
    if (c < 0x80) {
      h = Math.imul(h ^ c, 16777619) >>> 0;
    } else {
      // UTF-8 (BMP and surrogate pairs), for completeness
      if (c >= 0xd800 && c < 0xdc00 && i + 1 < id.length) c = 0x10000 + ((c - 0xd800) << 10) + (id.charCodeAt(++i) - 0xdc00);
      const bytes = c < 0x800 ? [0xc0 | (c >> 6), 0x80 | (c & 63)]
        : c < 0x10000 ? [0xe0 | (c >> 12), 0x80 | ((c >> 6) & 63), 0x80 | (c & 63)]
          : [0xf0 | (c >> 18), 0x80 | ((c >> 12) & 63), 0x80 | ((c >> 6) & 63), 0x80 | (c & 63)];
      for (const b of bytes) h = Math.imul(h ^ b, 16777619) >>> 0;
    }
  }
  return h;
}

/** A person's own clock: local time = t * rate + offset; slot is the spacing of their idle events. */
export function timing(id) {
  const s = seedOf(id);
  return { offset: 3.0 + 97.0 * hash01(s, 101), rate: 0.86 + 0.28 * hash01(s, 102), slot: 4.0 + 5.0 * hash01(s, 103) };
}

/** The phase (0..1) of a person's action cycle of `period` seconds at time t (Data.action_phase). */
export function actionPhase(id, t, period) {
  const tm = timing(id);
  return fposmod((t * tm.rate + tm.offset) / period, 1.0);
}

/** The floor height of a region ("ground" or "" is 0). */
export function floorY(region) {
  if (region === 'ground' || region === '') return 0.0;
  return Number(C.CityMap.REGIONS[region].y);
}

export function normRegion(region) { return region === '' ? 'ground' : region; }

// ---------------------------------------------------------------- the Ferris wheel's passengers

function ferrisN() { return Math.trunc(Number(C.CityMap.FERRIS.gondolas)); }
function ferrisP() { return Number(C.CityMap.FERRIS.period); }

/**
 * The ride a pair is on at time t (Data.pair_ride): fills out.gondola and out.ride and returns true, or
 * returns false between rides. out.start and out.end are the ride's first and last moments.
 */
export function pairRide(pair, t, out) {
  const n = ferrisN();
  const period = ferrisP();
  const g0 = Math.trunc(Number(C.PeopleData.FERRIS_PAIRS[pair].g0));
  const s0 = -g0 / n * period;
  const cycle = 3.0 * period - period / n;
  const c = Math.floor((t - s0) / cycle);
  const u = t - s0 - c * cycle;
  const start = s0 + c * cycle;
  const a = posmod(g0 + c, n);
  if (u < period) {
    out.gondola = a; out.ride = c * 2; out.start = start; out.end = start + period;
    return true;
  }
  if (u >= 1.5 * period && u < 2.5 * period) {
    out.gondola = posmod(a + (n >> 1), n); out.ride = c * 2 + 1; out.start = start + 1.5 * period; out.end = start + 2.5 * period;
    return true;
  }
  return false;
}

const RIDE = { gondola: 0, ride: 0, start: 0, end: 0 };

/**
 * The scheduled passengers at time t, before children are taken into account (Data.ferris_rides).
 * `out` is an Int32Array of 4 numbers per FERRIS_SLOTS entry, indexed by slot: [gondola, seat, ride, variant],
 * gondola -1 when the slot does not ride now.
 */
export function ferrisRides(t, out) {
  out.fill(-1);
  const pairs = C.PeopleData.FERRIS_PAIRS;
  for (let pi = 0; pi < pairs.length; pi++) {
    if (!pairRide(pi, t, RIDE)) continue;
    const slots = pairs[pi].slots;
    for (let k = 0; k < slots.length; k++) {
      const slot = Math.trunc(slots[k]);
      const n = C.PeopleData.FERRIS_SLOTS[slot].looks.length;
      const v = Math.trunc(hash01(slot + 7, RIDE.ride + 1000) * n) % n;
      out[slot * 4] = RIDE.gondola;
      out[slot * 4 + 1] = k;
      out[slot * 4 + 2] = RIDE.ride;
      out[slot * 4 + 3] = v;
    }
  }
  return out;
}

/** The lap index of gondola g at time t (it changes exactly at g's bottom pass). */
export function gondolaLap(g, t) {
  return Math.floor(t / ferrisP() + g / ferrisN());
}

// ---------------------------------------------------------------- weather

/** Whether a person who reacts to rain opens an umbrella (by its id). */
export function umbrellaFor(id) {
  return hash01(seedOf(id), 501) < Number(C.CityMap.UMBRELLA_SHARE);
}

/** A person's start delay after a weather change: its group's (its square of ground) plus a little of its own. */
export function groupDelay(sd, x, y, spread) {
  const cell = Number(C.PeopleData.GROUP_CELL);
  const cx = Math.floor(x / cell);
  const cy = Math.floor(y / cell);
  const g = hash01((cx + 64) * 131 + (cy + 64), 777);
  return spread * (0.72 * g + 0.26 * hash01(sd, 778));
}

// ---------------------------------------------------------------- the walkers (CityRules)

let loopsFor = null;
let loops = null;

function buildLoop(l) {
  const n = l.pts.length;
  const xs = new Float32Array(n);
  const ys = new Float32Array(n);
  for (let i = 0; i < n; i++) { xs[i] = l.pts[i][0]; ys[i] = l.pts[i][1]; }
  const seg = new Float64Array(n);       // a.distance_to(b), single precision values
  const corner = new Float64Array(n);    // _corner_arcs: the arc position of each point
  let total = 0.0;
  for (let i = 0; i < n; i++) {
    const j = (i + 1) % n;
    corner[i] = total;
    seg[i] = dist2(xs[i], ys[i], xs[j], ys[j]);
    total += seg[i];
  }
  return { n, xs, ys, seg, corner, length: total, speed: Number(l.speed), count: Math.trunc(l.count), first: Math.trunc(l.first) };
}

/** The walkers' loops (CityRules.walk_loops(), from the export): [{n, xs, ys, seg, corner, length, speed, count, first}]. */
export function walkLoops() {
  if (loopsFor !== C) {
    loops = C.extra.people.walk_loops.map(buildLoop);
    loopsFor = C;
  }
  return loops;
}

/** The loop a walker index walks (city_people.gd _loop_index). */
export function loopIndex(index) {
  const ls = walkLoops();
  for (let li = 0; li < ls.length; li++) {
    if (index >= ls[li].first && index < ls[li].first + ls[li].count) return li;
  }
  return 0;
}

/** CityRules.poly_point on a loop: out.x, out.y (the point), out.dx, out.dy (the unit direction). */
export function polyPoint(loop, s, out) {
  let rest = fposmod(s, loop.length);
  const n = loop.n;
  for (let i = 0; i < n; i++) {
    const seg = loop.seg[i];
    if (rest <= seg || i === n - 1) {
      const j = (i + 1) % n;
      const ax = loop.xs[i];
      const ay = loop.ys[i];
      const dx = f(f(loop.xs[j] - ax) / seg);
      const dy = f(f(loop.ys[j] - ay) / seg);
      const m = f(Math.min(rest, seg));
      out.x = f(ax + f(dx * m));
      out.y = f(ay + f(dy * m));
      out.dx = dx;
      out.dy = dy;
      return out;
    }
    rest -= seg;
  }
  out.x = loop.xs[0]; out.y = loop.ys[0]; out.dx = 1; out.dy = 0;
  return out;
}

/** CityRules.poly_project on a loop: out.arc (the arc position of the nearest point), out.dist (the distance to it). */
export function polyProject(loop, px, py, out) {
  let acc = 0.0;
  let bestArc = 0.0;
  let bestD = Infinity;
  const n = loop.n;
  for (let i = 0; i < n; i++) {
    const j = (i + 1) % n;
    const ax = loop.xs[i];
    const ay = loop.ys[i];
    const abx = f(loop.xs[j] - ax);
    const aby = f(loop.ys[j] - ay);
    const l2 = f(f(abx * abx) + f(aby * aby));
    const pax = f(px - ax);
    const pay = f(py - ay);
    const d0 = f(f(pax * abx) + f(pay * aby));
    let t = d0 / l2;
    t = t < 0 ? 0 : (t > 1 ? 1 : t);
    const tf = f(t);
    const qx = f(ax + f(abx * tf));
    const qy = f(ay + f(aby * tf));
    const d = dist2(qx, qy, px, py);
    const root = Math.sqrt(l2);
    if (d < bestD) {
      bestArc = f(acc + t * root);
      bestD = d;
    }
    acc += root;
  }
  out.arc = bestArc;
  out.dist = bestD;
  return out;
}

const PT = { x: 0, y: 0, dx: 0, dy: 0 };

/** Walker `index` at time t (CityRules.walker_pose): out.x, out.z, out.ry, out.phase. */
export function walkerPose(index, t, out) {
  const ls = walkLoops();
  for (let li = 0; li < ls.length; li++) {
    const l = ls[li];
    const k = index - l.first;
    if (k >= 0 && k < l.count) {
      const s = t * l.speed + l.length * k / l.count + 3.1 * l.first;
      polyPoint(l, s, PT);
      out.x = PT.x;
      out.z = PT.y;
      out.ry = Math.atan2(PT.dx, PT.dy);
      out.phase = fposmod(s / Number(C.CityRules.WALK_STRIDE) + 0.137 * index, 1.0);
      return out;
    }
  }
  out.x = 0; out.z = 0; out.ry = 0; out.phase = 0;
  return out;
}

// ---------------------------------------------------------------- the rides (CityWorld)

/** The wheel's angle at a clock time (CityWorld.ferris_angle_at: CityRules' gondola 0). */
export function ferrisAngleAt(t) { return gondolaAngle(0, t); }

/** Where a rider sits in gondola i at a wheel angle (CityWorld.rider_transform), a pooled transform. */
export function riderTransform(i, angle, slot) {
  const fe = C.CityMap.FERRIS;
  const a = -Math.PI * 0.5 + angle + TAU * i / Number(fe.gondolas);
  const r = Number(fe.radius);
  const even = slot % 2 === 0;
  const o = rotY(even ? Math.PI * 0.5 : -Math.PI * 0.5);
  // hub + Vector3(cos a * r, sin a * r, 0), then + Vector3(sx, -hang, 0)
  o[9] = f(f(fe.hub[0]) + f(Math.cos(a) * r)) + f(even ? -0.5 : 0.5);
  o[10] = f(f(fe.hub[1]) + f(Math.sin(a) * r)) + f(-Number(fe.hang));
  o[11] = f(f(fe.hub[2]) + 0) + 0;
  return o;
}

/** Where a rider sits on horse i at a clock time (CityWorld.carousel_seat_transform), a pooled transform. */
export function carouselSeatTransform(i, t) {
  const c = C.CityMap.CAROUSEL;
  const ring = Number(C.PropsCity.CAROUSEL_RING);
  const turnAngle = TAU * fposmod(t / Number(c.period), 1.0);
  const bobPhase = TAU * t / Number(c.bob_period) + i * Math.PI * 0.5;
  const bob = Number(c.bob) * 0.5 * (1.0 - Math.cos(bobPhase));
  const phi = TAU * i / Number(c.horses);
  const local = xOf(rotY(phi - Math.PI), V(Math.cos(phi) * ring, Number(C.PropsCity.CAROUSEL_DECK) + bob, -Math.sin(phi) * ring));
  const turn = xOf(rotY(turnAngle), V(c.center[0], 0.0, c.center[1]));
  const h = xMul(turn, local);
  const seat = xPointc(h, 0, Number(C.PropsCity.SADDLE_Y) + 0.05, 0);
  h[9] = seat[0]; h[10] = seat[1]; h[11] = seat[2];
  return h;
}
