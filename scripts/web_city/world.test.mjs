// World parity: the page's ports (game/web_city/js/world_logic.js, js/rules.js) against Godot's own results
// (scripts/web_city/fixtures/world.json, written by game/tests/web_city/parity_world.gd).
//   node --test scripts/web_city/world.test.mjs
// Godot keeps Vector3 and Transform3D in float32, the ports compute in doubles: tolerances are a few float32
// ulps of the city's coordinates (|x| < 40 m), never looser than they need to be.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import { setConsts, C } from '../../game/web_city/js/consts.js';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, '../..');
setConsts(JSON.parse(readFileSync(path.join(root, 'game/web_city/data/consts.json'), 'utf8')));
const FX = JSON.parse(readFileSync(path.join(here, 'fixtures/world.json'), 'utf8'));
const W = await import('../../game/web_city/js/world_logic.js');
const R = await import('../../game/web_city/js/rules.js');

const POS = 2e-5;      // metres
const ROT = 2e-6;      // basis entries / radians
const VAL = 1e-6;      // plain numbers (float32 material parameters)

function near(a, b, tol, what) {
  assert.ok(Math.abs(a - b) <= tol, `${what}: ${a} vs ${b} (|d| ${Math.abs(a - b)} > ${tol})`);
}
function nearXf(a, b, what) {
  for (let i = 0; i < 9; i++) near(a[i], b[i], ROT, `${what} basis[${i}]`);
  for (let i = 9; i < 12; i++) near(a[i], b[i], POS, `${what} origin[${i - 9}]`);
}
function nearArr(a, b, tol, what) {
  assert.equal(a.length, b.length, `${what}: length`);
  for (let i = 0; i < a.length; i++) near(a[i], b[i], tol, `${what}[${i}]`);
}
/** Godot's Transform3D for rotation.z = angle at an origin (the wheel). */
function xfRotZ(angle, o) {
  const c = Math.cos(angle), s = Math.sin(angle);
  return [c, s, 0, -s, c, 0, 0, 0, 1, o[0], o[1], o[2]];
}
const angleDiff = (a, b) => Math.abs(R.angleDifference ? R.angleDifference(a, b) : Math.atan2(Math.sin(b - a), Math.cos(b - a)));

test('export: the world extras are present and read from Godot', () => {
  const x = C.extra.world;
  assert.ok(x && x.town_light && x.rain && x.shading, 'extra.world');
  assert.equal(x.town_light.sun_rotation_order, 2, 'the sun uses Godot\'s default YXZ order');
  assert.equal(x.rain.amount, C.CityWorld.RAIN_DROPS);
  for (const role of ['base', 'glow', 'cabin', 'ground', 'puddle']) assert.equal(x.shading[role].diffuse_mode, 2, `${role}: lambert wrap`);
});

test('ferris: wheel angle, wheel transform and every gondola after _process', () => {
  for (const s of FX.ferris) {
    const a = W.ferrisAngleAt(s.t);
    near(a, s.angle, 1e-12, `angle t=${s.t}`);
    near(a, s.angle_now, 1e-12, `angle_now t=${s.t}`);
    nearXf(xfRotZ(a, C.CityMap.FERRIS.hub), s.wheel.xf, `wheel t=${s.t}`);
    s.gondolas.forEach((g, i) => {
      const o = W.gondolaOrigin(i, a);
      nearXf([1, 0, 0, 0, 1, 0, 0, 0, 1, o[0], o[1], o[2]], g.xf, `gondola ${i} t=${s.t}`);
    });
  }
});

test('ferris: rider_transform samples', () => {
  for (const r of FX.riders) nearXf(W.riderXf(r.g, r.angle, r.slot), r.xf.xf, `rider g=${r.g} slot=${r.slot}`);
});

test('interactions: seat_transform of every INTERACTIONS key; unknown keys give null', () => {
  const keys = Object.keys(FX.seats);
  assert.equal(keys.length, Object.keys(C.CityMap.INTERACTIONS).length);
  for (const k of keys) nearXf(W.seatXf(k), FX.seats[k].xf, `seat ${k}`);
  assert.equal(W.seatXf('no_such_seat'), null);
});

test('carousel: turn angle, horse MultiMesh transforms, world and seat transforms, bobs', () => {
  for (const s of FX.carousel) {
    near(W.carouselAngleAt(s.t), s.angle, 1e-12, `angle t=${s.t}`);
    const c = C.CityMap.CAROUSEL.center;
    nearXf(W.xfYaw(W.carouselAngleAt(s.t), c[0], 0, c[1]), s.turn.xf, `turn t=${s.t}`);
    s.horses.forEach((h, i) => nearXf(W.carouselHorseLocal(i, s.t), h.xf, `horse ${i} local t=${s.t}`));
    s.world.forEach((h, i) => nearXf(W.carouselHorseXf(i, s.t), h.xf, `horse ${i} world t=${s.t}`));
    s.seats.forEach((h, i) => nearXf(W.carouselSeatXf(i, s.t), h.xf, `horse ${i} seat t=${s.t}`));
    s.bobs.forEach((b, i) => near(W.carouselBob(i, s.t), b, 1e-12, `bob ${i} t=${s.t}`));
  }
});

test('carousel: the horses\' instance colours are CABIN_COLORS as _carousel sets them', () => {
  const hc = FX.horse_colors;
  assert.equal(hc.use_colors, true, 'the MultiMesh uses colours');
  assert.equal(hc.material_is_base, true, 'the horses use the base material');
  const cols = W.horseColors();
  assert.equal(cols.length, hc.count);
  cols.forEach((c, i) => nearArr(c, hc.colors[i].color.slice(0, 3), 1e-7, `horse colour ${i}`));
});

test('vehicles: drawn poses over packets with latency, uneven frames, a pause and a resume glide', () => {
  const vp = new W.VehiclePoser();
  let states = null;
  let maxPos = 0, maxRot = 0, pausedFrames = 0, glideFrames = 0;
  const RG = C.CityWorld.RESUME_GLIDE;
  let sinceResume = Infinity;
  FX.vehicles.frames.forEach((f, k) => {
    if (f.states >= 0) states = FX.vehicles.states[f.states];
    const moved = vp.step(states, f.clock, f.dt, f.paused);
    if (f.paused) pausedFrames++;
    if (!f.paused && k > 0 && FX.vehicles.frames[k - 1].paused) sinceResume = 0;
    if (!f.paused) { sinceResume += f.dt; if (sinceResume < RG) glideFrames++; }
    assert.equal(moved, !f.paused, `frame ${k}: moves unless paused`);
    f.drawn.forEach((d, i) => {
      const got = vp.drawn[i] || { visible: false };
      assert.equal(got.visible, d[4], `frame ${k} vehicle ${i} visible`);
      if (!d[4]) return;
      const dp = Math.hypot(got.x - d[0], got.y - d[1], got.z - d[2]);
      const dr = angleDiff(got.ry, d[3]);
      maxPos = Math.max(maxPos, dp);
      maxRot = Math.max(maxRot, dr);
      assert.ok(dp < 5e-5, `frame ${k} vehicle ${i} position off by ${dp}`);
      assert.ok(dr < 1e-6, `frame ${k} vehicle ${i} heading off by ${dr}`);
    });
  });
  assert.ok(pausedFrames > 30 && glideFrames > 10, `the run covers a pause (${pausedFrames}) and a glide (${glideFrames})`);
  console.log(`  vehicles: ${FX.vehicles.frames.length} frames, max |dpos| ${maxPos.toExponential(2)} m, max |dry| ${maxRot.toExponential(2)} rad`);
});

test('vehicles: livePose follows CityRules.vehicle_pose (the decoded pos and ry of each packet)', () => {
  for (const s of FX.vehicles.states) {
    s.vehicles.forEach((v, i) => {
      const p = W.livePose(i, v, 0);
      near(p[0], v.pos[0], POS, `pos x ${i}`);
      near(p[2], v.pos[1], POS, `pos z ${i}`);
      near(p[3], v.ry, ROT, `ry ${i}`);
    });
  }
});

test('weather: _compute_weights for weather states at view times', () => {
  for (const c of FX.weights) {
    const w = W.computeWeights(c.states, c.t);
    for (const k of ['sunny', 'rain', 'night']) near(w[k], c.weights[k], 1e-12, `${JSON.stringify(c.states)} t=${c.t} ${k}`);
  }
  const none = W.computeWeights(null, 10);
  assert.deepEqual([none.sunny, none.rain, none.night], [1, 0, 0]);
});

test('weather: weather_look, _apply_look values and the 4 lights for weight mixes', () => {
  for (const c of FX.looks) {
    const w = W.computeWeights(null, 0, c.override);
    for (const k of ['sunny', 'rain', 'night']) near(w[k], c.weights[k], 1e-7, `weights ${JSON.stringify(c.override)} ${k}`);
    const look = W.weatherLook(w);
    for (const k of Object.keys(c.look)) {
      if (c.look[k] && c.look[k].color) nearArr(look[k], c.look[k].color, 1e-6, `look ${k}`);
      else near(look[k], c.look[k], VAL, `look ${k}`);
    }
    const energies = c.applied.lights.map((l, i) => C.CityWorld.LIGHTS[i].energy);
    const v = W.lookValues(look.wet, look.glow, look.rain, energies);
    const a = c.applied;
    nearArr(v.ground.albedo, a.ground.albedo.color.slice(0, 3), VAL, 'ground albedo');
    near(v.ground.roughness, a.ground.roughness, VAL, 'ground roughness');
    near(v.ground.specular, a.ground.specular, VAL, 'ground specular');
    near(v.puddle.alpha, a.puddle.alpha, VAL, 'puddle alpha');
    assert.equal(v.puddle.visible, a.puddle.visible, 'puddles visible');
    near(v.glow.energy, a.glow.energy, VAL, 'glow energy');
    near(v.cabin.energy, a.cabin.energy, VAL, 'cabin energy');
    near(v.pool.alpha, a.pool.alpha, VAL, 'pool alpha');
    assert.equal(v.pool.visible, a.pool.visible, 'pools visible');
    near(v.rain.alpha, a.rain.alpha, VAL, 'rain alpha');
    near(v.rain.ratio, a.rain.ratio, VAL, 'rain amount ratio');
    assert.equal(v.rain.emitting, a.rain.emitting, 'rain emitting');
    assert.equal(v.rain.visible, a.rain.visible, 'rain visible');
    a.lights.forEach((l, i) => {
      near(v.lights[i], l.energy, VAL, `light ${l.name} energy`);
      const spec = C.CityWorld.LIGHTS[i];
      assert.equal(`${spec.name}Light`, l.name);
      nearArr(spec.at, l.at, 1e-6, `light ${l.name} position`);
      near(spec.range, l.range, 1e-6, `light ${l.name} range`);
      assert.equal(l.shadow, false); assert.equal(l.fade, false); assert.equal(l.attenuation, 1);
      nearArr(C.CityWorld.WARM.color, l.color.color, 1e-6, `light ${l.name} colour`);
    });
  }
});

test('city light: TownWorld._city_light (sky, ambient, sun, adjustment) and the sun direction', () => {
  for (const c of FX.looks) {
    const L = W.cityLight(c.weights);
    const t = c.town;
    nearArr(L.sky.slice(0, 3), t.sky.color.slice(0, 3), 1e-6, 'sky');
    nearArr(L.ambient.slice(0, 3), t.ambient.color.slice(0, 3), 1e-6, 'ambient');
    near(L.ambient_energy, t.ambient_energy, VAL, 'ambient energy');
    nearArr(L.sun.slice(0, 3), t.sun.color.slice(0, 3), 1e-6, 'sun colour');
    near(L.sun_energy, t.sun_energy, VAL, 'sun energy');
    near(L.saturation, t.saturation, VAL, 'saturation');
    near(L.contrast, t.contrast, VAL, 'contrast');
    near(L.brightness, t.brightness, VAL, 'brightness');
    assert.equal(t.adjustment, true); assert.equal(t.fog, false); assert.equal(t.tonemap, 0, 'linear tonemap');
    nearArr(W.sunDirection(), t.sun_dir, 1e-6, 'sun direction');
  }
});

test('rain focus: rain_focus for camera poses', () => {
  for (const c of FX.rain_focus) nearArr(W.rainFocus(c.origin, c.forward), c.focus, 1e-4, `focus from ${c.origin}`);
});

test('cutaways: apply_hidden storey visibility', () => {
  const paths = W.levelPaths();
  for (const c of FX.hidden) {
    const seen = {};
    for (const bid of Object.keys(paths)) {
      const floors = C.CityMap.BUILDINGS[bid].floors;
      paths[bid].forEach((p, k) => {
        const baseY = k < floors.length ? floors[k] : C.CityMap.BUILDINGS[bid].roof;
        seen[p] = W.levelVisible(c.hidden, bid, baseY);
      });
    }
    assert.deepEqual(seen, c.visible, `hidden ${JSON.stringify(c.hidden)}`);
  }
});

test('adjustment: Godot\'s brightness, contrast, saturation order on an sRGB colour', () => {
  const out = W.applyBcs([0.2, 0.5, 0.9], 1.02, 1.04, 1.12);
  const b = [0.204, 0.51, 0.918];
  const c = b.map((x) => 0.5 + (x - 0.5) * 1.04);
  const avg = (c[0] + c[1] + c[2]) * 0.33333;
  nearArr(out, c.map((x) => avg + (x - avg) * 1.12), 1e-12, 'bcs');
});

test('rules: loop helpers agree with CityWorld._loop_at and vehicle starts', () => {
  for (const v of C.CityMap.VEHICLES) {
    const a = R.loopAt(C.CityMap.ROAD_LOOP, v.start);
    const p = R.polyPoint(C.CityMap.ROAD_LOOP, v.start * R.loopLength());
    nearArr(a, p, 1e-9, `loop start ${v.start}`);
  }
});

// Emission as Godot's Compatibility renderer draws it (the project's renderer on every platform):
// srgb_to_linear(colour * energy), not linear(colour) * energy. The Mac's r2 frames showed the night cabins
// (energy 0.45) about 2.5 times too bright on the page; the bulbs and signs (1.6) clip either way.
test('emission: Godot Compatibility order (energy, then its sRGB-to-linear) for the cabins and the glow', () => {
  const warm = C.CityWorld.WARM || [1.0, 0.768627464771271, 0.431372553110123];
  const srgb = (Array.isArray(warm) ? warm : warm.color).slice(0, 3);
  nearArr(srgb, [1.0, 0.768627464771271, 0.431372553110123], 1e-6, 'WARM is #ffc46e');
  nearArr(W.godotEmission(srgb, 0), [0, 0, 0], 0, 'no glow by day');
  const poly = (c) => c * (c * (c * 0.305306011 + 0.682171111) + 0.012522878);
  const cabin = W.godotEmission(srgb, 0.45);
  nearArr(cabin, srgb.map((c) => poly(c * 0.45)), 1e-12, 'cabins at night');
  nearArr(cabin, [0.1716, 0.0986, 0.0303], 2e-4, 'cabins at night, by hand');
  const exact = (c) => (c <= 0.04045 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4);
  srgb.forEach((c, i) => assert.ok(exact(c) * 0.45 / cabin[i] > 2.2, `r2's emission was over twice Godot's (channel ${i})`));
  const glow = W.godotEmission(srgb, 1.6);
  assert.ok(glow[0] > 1 && glow[1] > 1, 'the bulbs clip, as in Godot');
  let prev = -1;
  for (let e = 0; e <= 2; e += 0.05) {
    const v = W.godotEmission(srgb, e)[2];
    assert.ok(v >= prev, 'grows with the energy'); prev = v;
  }
});

test('emission: the formula is the engine\'s own (Godot 4.7.2 shader text, when the binary is on this host)', (t) => {
  const bin = process.env.GODOT || path.join(root, 'tools/godot/Godot_v4.7.2-stable_linux.x86_64');
  let data;
  try { data = readFileSync(bin); } catch { t.skip(`no Godot binary at ${bin}`); return; }
  const text = data.toString('latin1');
  const material = text.indexOf('EMISSION = (emission.rgb + emission_tex) * emission_energy;');
  assert.ok(material >= 0, 'StandardMaterial3D: EMISSION is the sRGB colour times the energy');
  const scene = text.indexOf('\talbedo = srgb_to_linear(albedo);\n\temission = srgb_to_linear(emission);');
  assert.ok(scene >= 0, 'Compatibility scene shader: the emission is converted after the material shader');
  assert.ok(text.includes('return color * (color * (color * 0.305306011 + 0.682171111) + 0.012522878);'), 'srgb_to_linear\'s cubic');
});
