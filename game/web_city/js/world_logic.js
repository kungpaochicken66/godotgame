// The moving city's pure logic, ported function by function from world/city_world.gd (the wheel, the
// carousel, the vehicles' drawn poses, the weather's weights and look, rain focus, cutaways, seats) and
// world/town_world.gd (_city_light). No DOM and no WebGL: Node tests import this file
// (scripts/web_city/world.test.mjs) and compare it with Godot's own results (tests/web_city/parity_world.gd).
// js/world.js applies these numbers to the Three.js scene.
//
// Transforms are Godot's 12 floats (basis x, y, z columns, then origin), the same layout as the mesh pack
// and the bridge (meshpack.js matrixFrom12 turns one into a Matrix4). Every function that runs per frame
// writes into an `out` array its caller reuses.
import { C, clamp, lerp, smoothstep, lerpAngle, TAU } from './consts.js';
import { gondolaAngle, weatherWeights, vehiclePose } from './rules.js';

const HALF_PI = Math.PI * 0.5;

// ------------------------------------------------------------------ transforms

/** A transform rotated `ry` about +Y (Godot's Basis(Vector3.UP, ry)) at (x, y, z), written into `out`. */
export function xfYaw(ry, x, y, z, out = new Array(12)) {
  const c = Math.cos(ry);
  const s = Math.sin(ry);
  out[0] = c; out[1] = 0; out[2] = -s;
  out[3] = 0; out[4] = 1; out[5] = 0;
  out[6] = s; out[7] = 0; out[8] = c;
  out[9] = x; out[10] = y; out[11] = z;
  return out;
}

/** a * b for Godot 12-float transforms (Transform3D's operator *), written into `out` (may not alias a or b). */
export function xfMul(a, b, out = new Array(12)) {
  for (let col = 0; col < 3; col++) {
    const bx = b[col * 3], by = b[col * 3 + 1], bz = b[col * 3 + 2];
    out[col * 3] = a[0] * bx + a[3] * by + a[6] * bz;
    out[col * 3 + 1] = a[1] * bx + a[4] * by + a[7] * bz;
    out[col * 3 + 2] = a[2] * bx + a[5] * by + a[8] * bz;
  }
  const ox = b[9], oy = b[10], oz = b[11];
  out[9] = a[0] * ox + a[3] * oy + a[6] * oz + a[9];
  out[10] = a[1] * ox + a[4] * oy + a[7] * oz + a[10];
  out[11] = a[2] * ox + a[5] * oy + a[8] * oz + a[11];
  return out;
}

// ------------------------------------------------------------------ the Ferris wheel

/** The wheel's angle at a clock time (CityWorld.ferris_angle_at: CityRules' gondola 0 angle). */
export function ferrisAngleAt(t) { return gondolaAngle(0, t); }

/** A gondola's rim angle in the wheel's x-y plane (CityWorld.gondola_angle). */
export function wheelGondolaAngle(i, angle) {
  return -HALF_PI + angle + TAU * i / Number(C.CityMap.FERRIS.gondolas);
}

/** Where gondola i hangs at a wheel angle (CityWorld.gondola_transform; the basis is the identity): [x, y, z]. */
export function gondolaOrigin(i, angle, out = [0, 0, 0]) {
  const f = C.CityMap.FERRIS;
  const r = Number(f.radius);
  const a = wheelGondolaAngle(i, angle);
  out[0] = f.hub[0] + Math.cos(a) * r;
  out[1] = f.hub[1] + Math.sin(a) * r;
  out[2] = f.hub[2];
  return out;
}

const _go = [0, 0, 0];
/** Where a rider sits in gondola i (CityWorld.rider_transform), as 12 floats. */
export function riderXf(i, angle, slot, out = new Array(12)) {
  gondolaOrigin(i, angle, _go);
  const even = ((slot % 2) + 2) % 2 === 0;
  const sx = even ? -0.5 : 0.5;
  const ry = even ? HALF_PI : -HALF_PI;
  return xfYaw(ry, _go[0] + sx, _go[1] - Number(C.CityMap.FERRIS.hang), _go[2], out);
}

// ------------------------------------------------------------------ interactions

/** Where an avatar sits or stands for an INTERACTIONS entry (CityWorld.seat_transform); null when unknown. */
export function seatXf(key, out = new Array(12)) {
  const it = C.CityMap.INTERACTIONS[key];
  if (!it) return null;
  return facingXf(String(it.region), it.pos, String(it.kind), out);
}

/** CityWorld._facing_transform. */
export function facingXf(rid, pos, kind, out = new Array(12)) {
  const M = C.CityMap;
  const y = rid === 'ground' ? 0 : Number(M.REGIONS[rid].y);
  let dx = 0, dz = -1;
  if (kind === 'ride') {
    dx = 0;
    dz = Math.sign(M.FERRIS.hub[2] - pos[1]);
  } else {
    const rects = [];
    for (const f of M.FURNITURE) if (String(f.region) === rid) rects.push(f.rect.rect);
    if (rid === 'ground') {
      for (const s of M.GROUND_SOLIDS) if (s.rect && String(s.kind) !== 'stair_base') rects.push(s.rect.rect);
    }
    let best = Infinity;
    for (const r of rects) {
      const qx = clamp(pos[0], r[0], r[0] + r[2]);
      const qz = clamp(pos[1], r[1], r[1] + r[3]);
      const dist = Math.hypot(qx - pos[0], qz - pos[1]);
      if (dist < best) {
        best = dist;
        if (dist > 0.02) { dx = (qx - pos[0]) / dist; dz = (qz - pos[1]) / dist; } else { dx = 0; dz = -1; }
      }
    }
  }
  return xfYaw(Math.atan2(dx, dz), pos[0], y, pos[1], out);
}

// ------------------------------------------------------------------ the carousel

/** The platform's turn at a clock time (CityWorld.carousel_angle_at). */
export function carouselAngleAt(t) {
  const p = Number(C.CityMap.CAROUSEL.period);
  const u = t / p;
  return TAU * (u - Math.floor(u));
}

/** How high horse i rides above its lowest point (CityWorld.carousel_bob). */
export function carouselBob(i, t) {
  const c = C.CityMap.CAROUSEL;
  const phase = TAU * t / Number(c.bob_period) + i * HALF_PI;
  return Number(c.bob) * 0.5 * (1 - Math.cos(phase));
}

/** Horse i in the turning platform's frame (CityWorld.carousel_horse_local), 12 floats. */
export function carouselHorseLocal(i, t, out = new Array(12)) {
  const P = C.PropsCity;
  const phi = TAU * i / Number(C.CityMap.CAROUSEL.horses);
  const ring = Number(P.CAROUSEL_RING);
  return xfYaw(phi - Math.PI, Math.cos(phi) * ring, Number(P.CAROUSEL_DECK) + carouselBob(i, t), -Math.sin(phi) * ring, out);
}

const _turn = new Array(12);
const _local = new Array(12);
/** Horse i in the world (CityWorld.carousel_horse_transform). */
export function carouselHorseXf(i, t, out = new Array(12)) {
  const c = C.CityMap.CAROUSEL.center;
  xfYaw(carouselAngleAt(t), c[0], 0, c[1], _turn);
  carouselHorseLocal(i, t, _local);
  return xfMul(_turn, _local, out);
}

/** Where a rider sits on horse i (CityWorld.carousel_seat_transform). */
export function carouselSeatXf(i, t, out = new Array(12)) {
  carouselHorseXf(i, t, out);
  const up = Number(C.PropsCity.SADDLE_Y) + 0.05;
  out[9] += out[3] * up; out[10] += out[4] * up; out[11] += out[5] * up;
  return out;
}

/** The horses' instance colours as CityWorld._carousel sets them (sRGB, as stored in Godot): [[r, g, b], ...]. */
export function horseColors() {
  const cols = C.CityMap.CABIN_COLORS;
  const n = Number(C.CityMap.CAROUSEL.horses);
  const out = [];
  for (let i = 0; i < n; i++) {
    const c = cols[i % cols.length].color;
    out.push([c[0], c[1], c[2]]);
  }
  return out;
}

// ------------------------------------------------------------------ vehicles

const _vp = [0, 0, 0];
/**
 * A vehicle's live pose (CityWorld._live_pose): along the road from its arc position and speed when the state
 * has them (extrapolated by up to 0.5 s since the packet), else the state's pos and ry. Writes [x, y, z, ry].
 */
export function livePose(i, st, since, out = [0, 0, 0, 0]) {
  if (st.s !== undefined && i < C.CityMap.VEHICLES.length) {
    const speed = (st.stopped || Number(st.dwell ?? 0) > 0) ? 0 : Number(st.v ?? 0);
    vehiclePose(i, Number(st.s) + speed * clamp(since, 0, 0.5), _vp);
    out[0] = _vp[0]; out[1] = 0; out[2] = _vp[1]; out[3] = _vp[2];
    return out;
  }
  const p = st.pos || [0, 0, 0];
  if (p.length === 2) { out[0] = p[0]; out[1] = 0; out[2] = p[1]; } else { out[0] = p[0]; out[1] = p[1]; out[2] = p[2]; }
  out[3] = Number(st.ry ?? 0);
  return out;
}

/**
 * The vehicles as drawn (CityWorld._pose_vehicles and set_paused's resume glide): eased between packets,
 * frozen while paused, gliding RESUME_GLIDE seconds from the frozen pose to the live one on resume.
 * `drawn[i]` = {x, y, z, ry, visible} after each step(); nothing is allocated per step after warm-up.
 */
export class VehiclePoser {
  constructor() {
    this.drawn = [];
    this._shown = [];      // [x, y, z, ry] or null
    this._frozen = [];     // [x, y, z, ry] or null
    this._glide = 0;
    this._wasPaused = false;
    this._target = [0, 0, 0, 0];
  }

  _slot(list, i) {
    while (list.length <= i) list.push(null);
    if (!list[i]) list[i] = [0, 0, 0, 0];
    return list[i];
  }

  /** CityWorld.set_paused(false): the glide starts from the poses last drawn. */
  resume() {
    this._glide = Number(C.CityWorld.RESUME_GLIDE);
    for (let i = 0; i < this._frozen.length; i++) this._frozen[i] = null;
    for (let i = 0; i < this._shown.length; i++) {
      const s = this._shown[i];
      if (!s) continue;
      const f = this._slot(this._frozen, i);
      f[0] = s[0]; f[1] = s[1]; f[2] = s[2]; f[3] = s[3];
    }
  }

  /**
   * One frame. `states` = the newest City states (client form), `now` = the city clock (est_time), `delta` =
   * the frame's seconds, `paused` = whether this screen's view is paused. Returns false while paused
   * (nothing moves), true otherwise.
   */
  step(states, now, delta, paused) {
    if (paused) {
      this._wasPaused = true;
      return false;
    }
    if (this._wasPaused) {
      this._wasPaused = false;
      this.resume();
    }
    const vs = (states && states.vehicles) || [];
    const stTime = states && states.time !== undefined ? Number(states.time) : now;
    if (this._glide > 0) this._glide = Math.max(0, this._glide - delta);
    const RG = Number(C.CityWorld.RESUME_GLIDE);
    const tgt = this._target;
    for (let i = 0; i < vs.length; i++) {
      livePose(i, vs[i], now - stTime, tgt);
      let x = tgt[0], y = tgt[1], z = tgt[2], ry = tgt[3];
      const from = this._frozen[i];
      const prev = this._shown[i];
      if (this._glide > 0 && from) {
        const k = smoothstep(0, 1, 1 - this._glide / RG);
        x = lerp(from[0], x, k); y = lerp(from[1], y, k); z = lerp(from[2], z, k);
        ry = lerpAngle(from[3], ry, k);
      } else if (prev) {
        if (Math.hypot(prev[0] - x, prev[1] - y, prev[2] - z) < 6.0) {
          const f = 1 - Math.exp(-14 * delta);
          x = lerp(prev[0], x, f); y = lerp(prev[1], y, f); z = lerp(prev[2], z, f);
          ry = lerpAngle(prev[3], ry, f);
        }
      }
      const s = this._slot(this._shown, i);
      s[0] = x; s[1] = y; s[2] = z; s[3] = ry;
      while (this.drawn.length <= i) this.drawn.push({ x: 0, y: 0, z: 0, ry: 0, visible: false });
      const d = this.drawn[i];
      d.x = x; d.y = y; d.z = z; d.ry = ry; d.visible = true;
    }
    for (let i = vs.length; i < this.drawn.length; i++) this.drawn[i].visible = false;
    return true;
  }
}

// ------------------------------------------------------------------ weather

const _wstate = { weather: 0, since: 0, prev: null };
const _sunnyPrev = [1, 0, 0];
/**
 * The weather mix drawn at view time t (CityWorld._compute_weights): from an override (tests, previews) or
 * the states' weather, normalised over CityMap.WEATHERS; sunny when neither says anything.
 */
export function computeWeights(states, t, override = null, out = { sunny: 1, rain: 0, night: 0 }) {
  let w = null;
  if (override && Object.keys(override).length) {
    w = override;
  } else if (states && states.weather !== undefined) {
    const ws = _wstate;
    ws.prev = states.prev ?? states.weather_prev ?? _sunnyPrev;
    ws.since = Number(states.since ?? states.weather_since ?? -Number(C.CityMap.WEATHER_BLEND));
    ws.weather = Math.trunc(Number(states.weather));
    w = weatherWeights(ws, t);
  } else {
    out.sunny = 1; out.rain = 0; out.night = 0;
    return out;
  }
  const names = C.CityMap.WEATHERS;
  let sum = 0;
  for (const k of names) sum += Math.max(0, Number(w[k] ?? 0));
  if (sum < 1e-6) {
    out.sunny = 1; out.rain = 0; out.night = 0;
    return out;
  }
  for (const k of names) out[k] = Math.max(0, Number(w[k] ?? 0)) / sum;
  return out;
}

/**
 * The look blended by the weights (CityWorld.weather_look): every WEATHER_LOOK field; colours are summed
 * as Godot stores them (sRGB components, [r, g, b, a]).
 */
let _lookKeys = null;
let _lookFor = null;
/** [[weather name, [field names]]] of WEATHER_LOOK, computed once per consts object. */
function lookKeys() {
  if (_lookFor !== C) {
    const looks = C.CityMap.WEATHER_LOOK;
    _lookKeys = Object.keys(looks).map((w) => [w, Object.keys(looks[w])]);
    _lookFor = C;
  }
  return _lookKeys;
}

export function weatherLook(weights, out = {}) {
  const looks = C.CityMap.WEATHER_LOOK;
  const keys = lookKeys();
  for (const [wname, fields] of keys) {
    for (const k of fields) {
      if (Array.isArray(out[k])) out[k].fill(0); else out[k] = 0;
    }
  }
  for (const [wname, fields] of keys) {
    const w = Number(weights[wname] ?? 0);
    const look = looks[wname];
    for (const k of fields) {
      const v = look[k];
      if (v && v.color) {
        if (!Array.isArray(out[k])) out[k] = [0, 0, 0, 0];
        for (let j = 0; j < 4; j++) out[k][j] += v.color[j] * w;
      } else {
        out[k] = Number(out[k] ?? 0) + Number(v) * w;
      }
    }
  }
  return out;
}

/**
 * The linear emission Godot's Compatibility renderer (the project's renderer on every platform) draws for a
 * StandardMaterial3D with sRGB `emission` colour and `emission_energy_multiplier` energy. Its material shader
 * computes EMISSION = emission.rgb * emission_energy in sRGB, and its scene shader then converts that product
 * with srgb_to_linear, a cubic approximation (Godot 4.7.2 scene shader: "emission = srgb_to_linear(emission);").
 * So the energy is applied before the conversion: a Three.js emissive of linear(colour) * energy is too bright
 * below 1 (2.3 to 2.6 times for the night cabins, energy 0.45; city-web r2, Mac review). Returns [r, g, b].
 */
export function godotEmission(srgb, energy, out = [0, 0, 0]) {
  for (let i = 0; i < 3; i++) {
    const c = Math.max(0, srgb[i] * energy);
    out[i] = c * (c * (c * 0.305306011 + 0.682171111) + 0.012522878);
  }
  return out;
}

/**
 * What CityWorld._apply_look sets for (wet, glow, rain): every material and node parameter, as numbers.
 * Colours are Godot's (sRGB) values.
 */
export function lookValues(wet, glow, rain, lightEnergies, out = null) {
  out = out || { ground: { albedo: [0, 0, 0], roughness: 0, specular: 0 }, puddle: { alpha: 0, visible: false },
    glow: { energy: 0 }, cabin: { energy: 0 }, pool: { alpha: 0, visible: false },
    rain: { alpha: 0, ratio: 0, emitting: false, visible: false }, lights: [] };
  out.ground.albedo[0] = 1 - 0.2 * wet; out.ground.albedo[1] = 1 - 0.18 * wet; out.ground.albedo[2] = 1 - 0.13 * wet;
  out.ground.roughness = lerp(0.92, 0.32, wet);
  out.ground.specular = lerp(0.3, 0.75, wet);
  out.puddle.alpha = 0.6 * wet;
  out.puddle.visible = wet > 0.003;
  out.glow.energy = 1.6 * glow;
  out.cabin.energy = 0.45 * glow;
  out.pool.alpha = 0.5 * glow;
  out.pool.visible = glow > 0.003;
  out.rain.alpha = 0.5 * rain;
  out.rain.ratio = rain;
  out.rain.emitting = rain > 0.003;
  out.rain.visible = rain > 0.003;
  const n = lightEnergies ? lightEnergies.length : 0;
  out.lights.length = n;
  for (let i = 0; i < n; i++) out.lights[i] = lightEnergies[i] * glow;
  return out;
}

/** CityWorld._update_weather's change test: applies only when (wet, glow, rain) moved by 1e-4 or more. */
export class WeatherApplier {
  constructor() { this.applied = [-1, -1, -1]; }
  /** True when the look must be applied now (and records it as applied). */
  needs(wet, glow, rain, force = false) {
    const a = this.applied;
    if (!force && Math.hypot(wet - a[0], glow - a[1], rain - a[2]) < 1e-4) return false;
    a[0] = wet; a[1] = glow; a[2] = rain;
    return true;
  }
}

// ------------------------------------------------------------------ the city's light (town_world.gd)

/** The town's light settings the city keeps (export_world.gd extra: copied from town_world.gd, checked by parity). */
export function townLight() { return C.extra.world.town_light; }

/**
 * TownWorld._city_light(weights): the sky, ambient and sun blended between the WEATHER_LOOK entries, and the
 * colour adjustment. Colours are Godot's stored (sRGB) values [r, g, b, a].
 */
export function cityLight(weights, out = null) {
  out = out || { sky: [0, 0, 0, 0], ambient: [0, 0, 0, 0], sun: [0, 0, 0, 0], ambient_energy: 0, sun_energy: 0,
    saturation: 0, contrast: 0, brightness: 0 };
  const looks = C.CityMap.WEATHER_LOOK;
  out.sky.fill(0); out.ambient.fill(0); out.sun.fill(0);
  out.ambient_energy = 0; out.sun_energy = 0; out.saturation = 0;
  let total = 0;
  for (const w in weights) total += Number(weights[w]);
  for (const w in weights) {
    const look = looks[w] || looks.sunny;
    const k = Number(weights[w]) / Math.max(total, 0.0001);
    for (let j = 0; j < 4; j++) {
      out.sky[j] += look.sky.color[j] * k;
      out.ambient[j] += look.ambient.color[j] * k;
      out.sun[j] += look.sun.color[j] * k;
    }
    out.ambient_energy += Number(look.ambient_energy) * k;
    out.sun_energy += Number(look.sun_energy) * k;
    out.saturation += Number(look.saturation) * k;
  }
  const tl = townLight();
  out.contrast = Number(tl.contrast);
  out.brightness = Number(tl.brightness);
  return out;
}

/**
 * The direction the town's sun shines along (its -Z), from Godot's rotation_degrees with Godot's default
 * Euler order YXZ (basis = Ry * Rx * Rz): [x, y, z], unit length.
 */
export function sunDirection(deg = townLight().sun_rotation_degrees, out = [0, 0, 0]) {
  const x = deg[0] * Math.PI / 180, y = deg[1] * Math.PI / 180, z = deg[2] * Math.PI / 180;
  // -Z column of Ry*Rx*Rz: Rz leaves z alone, so it is -(Ry * Rx * e_z).
  const ezx = 0, ezy = -Math.sin(x), ezz = Math.cos(x);     // Rx * (0, 0, 1)
  const bx = Math.cos(y) * ezx + Math.sin(y) * ezz;          // Ry * that
  const by = ezy;
  const bz = -Math.sin(y) * ezx + Math.cos(y) * ezz;
  void z;
  out[0] = -bx; out[1] = -by; out[2] = -bz;
  return out;
}

/**
 * Godot's colour adjustment (brightness, contrast, saturation) on one sRGB-encoded colour, as its tonemap
 * pass applies it after the linear-to-sRGB conversion. The page's adjust pass runs the same in GLSL.
 */
export function applyBcs(rgb, brightness, contrast, saturation, out = [0, 0, 0]) {
  let r = rgb[0] * brightness, g = rgb[1] * brightness, b = rgb[2] * brightness;
  r = 0.5 + (r - 0.5) * contrast; g = 0.5 + (g - 0.5) * contrast; b = 0.5 + (b - 0.5) * contrast;
  const avg = (r + g + b) * 0.33333;
  out[0] = avg + (r - avg) * saturation; out[1] = avg + (g - avg) * saturation; out[2] = avg + (b - avg) * saturation;
  return out;
}

// ------------------------------------------------------------------ rain focus

/**
 * The point the camera looks at on the ground, kept on the map (CityWorld.rain_focus): `o` the camera's
 * position, `f` its forward (-Z) direction. Writes [x, 0, z].
 */
export function rainFocus(o, f, out = [0, 0, 0]) {
  let px = o[0], pz = o[2];
  if (f[1] < -0.05) {
    const k = -o[1] / f[1];
    px = o[0] + f[0] * k;
    pz = o[2] + f[2] * k;
  }
  const r = C.CityMap.OUTER_PAVEMENT.rect;
  out[0] = clamp(px, r[0], r[0] + r[2]);
  out[1] = 0;
  out[2] = clamp(pz, r[1], r[1] + r[3]);
  return out;
}

// ------------------------------------------------------------------ cutaways

/** Whether a storey node (its building id and meta base_y) is drawn under `hidden` (CityWorld.apply_hidden). */
export function levelVisible(hidden, bid, baseY) {
  if (!hidden || !Object.prototype.hasOwnProperty.call(hidden, bid)) return true;
  return Number(baseY ?? 0) <= Number(hidden[bid]) + 0.05;
}

/** The storey node paths of every building: {bid: ["Buildings/<bid>/L0", ..., "Buildings/<bid>/Roof"]}. */
export function levelPaths() {
  const out = {};
  for (const bid of Object.keys(C.CityMap.BUILDINGS)) {
    const floors = C.CityMap.BUILDINGS[bid].floors;
    const list = [];
    for (let k = 0; k < floors.length; k++) list.push(`Buildings/${bid}/L${k}`);
    list.push(`Buildings/${bid}/Roof`);
    out[bid] = list;
  }
  return out;
}

// ------------------------------------------------------------------ rain (reference of the GPU shader)

/** The rain's emitter constants (CityWorld._build_rain), in one place for world.js's shader and the tests. */
export function rainSpec() {
  const W = C.CityWorld;
  const R = C.extra.world.rain;
  const d = R.direction;
  const n = Math.hypot(d[0], d[1], d[2]);
  return {
    amount: Number(W.RAIN_DROPS), half: Number(W.RAIN_HALF), top: Number(W.RAIN_TOP),
    lifetime: Number(R.lifetime), boxY: Number(R.box_y), dir: [d[0] / n, d[1] / n, d[2] / n],
    spreadDeg: Number(R.spread), vmin: Number(R.velocity_min), vmax: Number(R.velocity_max),
    gravity: R.gravity, size: R.size, color: R.color,
  };
}
