// Parity of the Three.js city's people with the Godot city's (design/city-threejs.md §6):
//   node --test scripts/web_city/people.test.mjs
// The fixture scripts/web_city/fixtures/people.json is written by Godot itself
// (game/tests/web_city/parity_people.gd: art/city_people.gd's own instance transforms, instance colours, shown
// flags, written counts and rain states, scene by scene). This test installs the exported constants
// (game/web_city/data/consts.json), replays every scene on the page's port (game/web_city/js/people_core.js)
// with the same calls in the same order, and compares everything.
//
// Tolerances (stated, and tight: Godot's vectors and transforms are single precision and so are the port's):
//   XF_TOL     1e-5   every number of every instance transform (basis columns and origin, metres), absolute.
//                     A hidden instance must be hidden in both (zero basis at y -50).
//   COLOR_TOL  1e-6   instance colours (Godot's sRGB-encoded r, g, b): they are the same single-precision values
//   RULE_TOL   1e-5   walker positions, seats, the rain state's distances and times (metres, seconds, phases)
//   exact             who is shown, how many transforms each call wrote, the weather key, slots, seeds, hashes,
//                     timetables, cover spots
// The measured worst differences are printed as diagnostics.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import zlib from 'node:zlib';
import { fileURLToPath } from 'node:url';

const XF_TOL = 1e-5;
const COLOR_TOL = 1e-6;
const RULE_TOL = 1e-5;

const here = path.dirname(fileURLToPath(import.meta.url));
const web = path.resolve(here, '../../game/web_city');
const consts = JSON.parse(fs.readFileSync(path.join(web, 'data/consts.json'), 'utf8'));
const fx = JSON.parse(fs.readFileSync(path.join(here, 'fixtures/people.json'), 'utf8'));

const { setConsts } = await import(path.join(web, 'js/consts.js'));
setConsts(consts);
const { CityPeople } = await import(path.join(web, 'js/people_core.js'));
const R = await import(path.join(web, 'js/people_rules.js'));
const M = await import(path.join(web, 'js/people_math.js'));

const floats = (b64, gz) => {
  let buf = Buffer.from(b64, 'base64');
  if (gz) buf = zlib.gunzipSync(buf);
  return new Float32Array(buf.buffer, buf.byteOffset, buf.byteLength / 4);
};
const near = (a, b, tol) => Math.abs(a - b) <= tol;
/** The difference of two angles or phases that wrap at `period`. */
const wrapDiff = (a, b, period) => { const d = Math.abs(a - b) % period; return Math.min(d, period - d); };

function weatherOf(w) {
  // the fixture writes a Vector3 as [x, y, z]: the bridge's form, which the port reads
  return w === null || w === undefined ? null : w;
}

function offsets(alloc) {
  const out = [];
  let at = 0;
  for (const n of alloc) { out.push(at); at += n; }
  return out;
}

/** Compares the port's instance transforms with Godot's; returns the worst difference. */
function compareXf(sim, want, label) {
  const got = sim.snapshot();
  const at = offsets(fx.alloc);
  let worst = 0;
  let worstAt = '';
  let total = 0;
  for (let m = 0; m < got.length; m++) total += got[m].length;
  assert.equal(want.length, total, `${label}: transform count`);
  for (let m = 0; m < got.length; m++) {
    const g = got[m];
    for (let k = 0; k < g.length; k++) {
      const w = want[at[m] * 12 + k];
      const d = Math.abs(g[k] - w);
      if (d > worst) { worst = d; worstAt = `${fx.shapes[m]}[${Math.floor(k / 12)}].${k % 12}: page ${g[k]}, Godot ${w}`; }
    }
  }
  if (worst > XF_TOL) assert.fail(`${label}: an instance transform differs by ${worst} (> ${XF_TOL}) at ${worstAt}; ${ownerOf(sim, worstAt)}`);
  return worst;
}

/** Whose part an instance is (for a failure's message). */
function ownerOf(sim, where) {
  const m = /^(\w+)\[(\d+)\]/.exec(where);
  if (!m) return '';
  const shape = fx.shapes.indexOf(m[1]);
  const inst = Number(m[2]);
  const names = Object.keys(consts.People).filter((k) => k.startsWith('P_') && k !== 'P_COUNT');
  for (const p of sim.people) {
    for (let part = 0; part < p.slots.length; part++) {
      if (p.slots[part] === ((shape << 16) | inst)) return `${p.id} ${names.find((n) => consts.People[n] === part)}`;
    }
  }
  return '';
}

function compareColors(sim, set, label) {
  const want = floats(fx.color_sets[set], false);
  const at = offsets(fx.alloc);
  let worst = 0;
  for (let m = 0; m < sim.col.length; m++) {
    for (let k = 0; k < fx.alloc[m] * 3; k++) {
      const d = Math.abs(sim.col[m][k] - want[at[m] * 3 + k]);
      if (d > worst) worst = d;
      if (d > COLOR_TOL) assert.fail(`${label}: colour of ${fx.shapes[m]}[${Math.floor(k / 3)}] differs: page ${sim.col[m][k]}, Godot ${want[at[m] * 3 + k]}`);
    }
  }
  return worst;
}

const EV = { s: 0, onLane: true, lam: 0, walked: 0, pd: 0, umb: 0, ph: -1, moving: false, back: false };

function compareReact(sim, t, want, label) {
  let worst = 0;
  for (const id of Object.keys(want)) {
    const p = sim.person(id);
    const w = want[id];
    assert.ok(p && p.react, `${label}: ${id} reacts to rain`);
    const e = sim._eval(p, t, EV);
    assert.equal(p.spot, w.spot, `${label}: ${id} cover spot`);
    assert.equal(p.baseN, w.n, `${label}: ${id} path points`);
    assert.equal(e.onLane, w.on_lane, `${label}: ${id} on_lane`);
    assert.equal(e.moving, w.moving, `${label}: ${id} moving`);
    assert.equal(e.back, w.back, `${label}: ${id} back`);
    const ds = [Math.abs(e.s - w.s), Math.abs(e.lam - w.lam), Math.abs(e.umb - w.umb), Math.abs(e.walked - w.walked),
      w.ph < 0 ? Math.abs(e.ph - w.ph) : wrapDiff(e.ph, w.ph, 1)];
    for (const d of ds) if (d > worst) worst = d;
    assert.ok(Math.max(...ds) <= RULE_TOL, `${label}: ${id} rain state: page ${JSON.stringify(e)}, Godot ${JSON.stringify(w)}`);
  }
  return worst;
}

function checkResult(sim, step, t, writes, label, stats) {
  assert.equal(writes, step.writes, `${label}: transforms written`);
  const shown = sim.people.map((p) => (p.shown ? '1' : '0')).join('');
  assert.equal(shown, step.shown, `${label}: who is shown`);
  assert.equal(sim._wkey, step.wkey, `${label}: the weather key`);
  stats.react = Math.max(stats.react, compareReact(sim, t, step.react, label));
  if (step.xf !== undefined) {
    stats.xf = Math.max(stats.xf, compareXf(sim, floats(step.xf, true), label));
    stats.color = Math.max(stats.color, compareColors(sim, step.col, label));
    stats.snaps += 1;
  }
}

// ---------------------------------------------------------------- the pure rules

test('rules: hashes, seeds, timetables, walkers and seats equal Godot', (t) => {
  const rules = fx.rules;
  for (const [a, b, h] of rules.hash01) assert.ok(near(R.hash01(a, b), h, 1e-12), `hash01(${a}, ${b})`);
  for (const id of Object.keys(rules.seed_of)) {
    assert.equal(R.seedOf(id), rules.seed_of[id], `seed_of(${id})`);
    assert.equal(R.umbrellaFor(id), rules.umbrella_for[id], `umbrella_for(${id})`);
  }
  for (const [id, x, y, d] of rules.group_delay) {
    assert.ok(near(R.groupDelay(R.seedOf(id), Math.fround(x), Math.fround(y), 9.0), d, 1e-9), `group_delay(${id}, ${x}, ${y})`);
  }
  const loops = R.walkLoops();
  const exported = consts.extra.people.walk_loops;
  assert.equal(loops.length, exported.length);
  loops.forEach((l, i) => assert.ok(near(l.length, exported[i].length, 1e-9), `walk loop ${i} length ${l.length} vs ${exported[i].length}`));
  const out = { x: 0, z: 0, ry: 0, phase: 0 };
  const fer = new Int32Array(consts.PeopleData.FERRIS_SLOTS.length * 4);
  let worst = 0;
  rules.times.forEach((time, k) => {
    rules.walkers[k].forEach((w, index) => {
      R.walkerPose(index, time, out);
      const d = Math.max(Math.abs(out.x - w[0]), Math.abs(out.z - w[1]), wrapDiff(out.ry, w[2], Math.PI * 2), wrapDiff(out.phase, w[3], 1));
      worst = Math.max(worst, d);
      assert.ok(d <= RULE_TOL, `walker ${index} at ${time}: page ${JSON.stringify(out)}, Godot ${w}`);
    });
    R.ferrisRides(time, fer);
    const riding = [];
    for (let s = 0; s < fer.length / 4; s++) if (fer[s * 4] >= 0) riding.push([s, fer[s * 4], fer[s * 4 + 1], fer[s * 4 + 2], fer[s * 4 + 3]]);
    assert.deepEqual(riding, rules.ferris[k].slice().sort((a, b) => a[0] - b[0]), `ferris_rides(${time})`);
    rules.laps[k].forEach((lap, g) => assert.equal(R.gondolaLap(g, time), lap, `gondola_lap(${g}, ${time})`));
    const gondolas = consts.CityMap.FERRIS.gondolas;
    rules.seats[k].forEach((want, i) => {
      M.resetPools();
      const xf = i < gondolas ? R.riderTransform(i, R.ferrisAngleAt(time), i % 2) : R.carouselSeatTransform(i - gondolas, time);
      for (let c = 0; c < 12; c++) {
        worst = Math.max(worst, Math.abs(xf[c] - want[c]));
        assert.ok(near(xf[c], want[c], RULE_TOL), `seat ${i} at ${time}, number ${c}: page ${xf[c]}, Godot ${want[c]}`);
      }
    });
  });
  const pr = { arc: 0, dist: 0 };
  for (const [li, x, y, arc, dist] of rules.poly_project) {
    R.polyProject(loops[li], Math.fround(x), Math.fround(y), pr);
    assert.ok(near(pr.arc, arc, RULE_TOL) && near(pr.dist, dist, RULE_TOL), `poly_project(loop ${li}, ${x}, ${y}): page ${JSON.stringify(pr)}, Godot ${arc}, ${dist}`);
  }
  t.diagnostic(`worst walker / seat difference ${worst.toExponential(2)} (tolerance ${RULE_TOL})`);
});

// ---------------------------------------------------------------- who the people are

test('setup: every person, its rig slots, its clock and its rain role equal Godot', () => {
  const sim = new CityPeople({ time: 20, riders: {}, weather: { weather: 0, since: -4, prev: [1, 0, 0] } });
  assert.deepEqual(Array.from(sim.alloc), fx.alloc, 'instances per shape');
  assert.deepEqual(sim.meshNames, fx.shapes);
  assert.equal(sim.people.length, fx.persons.length);
  fx.persons.forEach((w, i) => {
    const p = sim.people[i];
    const what = `person ${i} (${w.id})`;
    assert.equal(p.id, w.id, what);
    for (const [mine, theirs] of [['kind', 'kind'], ['index', 'index'], ['action', 'action'], ['region', 'region'], ['seated', 'seated'],
      ['legsStill', 'legs_still'], ['fast', 'fast'], ['group', 'group'], ['partnerRank', 'partner_rank'], ['pairSeed', 'pair_seed'],
      ['hasPartner', 'has_partner'], ['sd', 'sd'], ['react', 'react'], ['umbrella', 'umbrella'], ['legsSeat', 'legs_seat'],
      ['spot', 'spot'], ['umbHand', 'umb_hand']]) {
      assert.equal(p[mine], w[theirs], `${what} ${theirs}`);
    }
    for (const [mine, theirs] of [['seat', 'seat'], ['offset', 'offset'], ['rate', 'rate'], ['slot', 'slot'], ['partnerYaw', 'partner_yaw']]) {
      assert.ok(near(p[mine], w[theirs], 1e-6), `${what} ${theirs}: page ${p[mine]}, Godot ${w[theirs]}`);
    }
    assert.deepEqual(Array.from(p.slots), w.slots, `${what} slots`);
    assert.deepEqual(Object.fromEntries(p.hairPart), w.hair_part, `${what} hair parts`);
    assert.equal(p.looks.length, w.looks, `${what} looks`);
    for (let c = 0; c < 12; c++) assert.ok(near(p.root[c], w.root[c], 1e-6), `${what} root`);
    assert.ok(near(p.table[0], w.table[0], 1e-7) && near(p.table[1], w.table[1], 1e-7), `${what} table`);
    assert.equal(p.baseN, w.base_len.length, `${what} path points`);
    w.base_len.forEach((l, k) => assert.ok(near(p.baseLen[k], l, 1e-6), `${what} path length ${k}`));
  });
});

// ---------------------------------------------------------------- the scenes

for (const scene of fx.scenes) {
  test(`scene ${scene.name}: transforms, colours, shown, written counts and rain states equal Godot`, (t) => {
    const stats = { xf: 0, color: 0, react: 0, snaps: 0 };
    const sim = new CityPeople({ time: scene.init.t, riders: scene.init.riders, weather: weatherOf(scene.init.weather) });
    checkResult(sim, scene.init, scene.init.t, sim.writesLast, `${scene.name} setup at ${scene.init.t}`, stats);
    scene.steps.forEach((step, k) => {
      const label = `${scene.name} step ${k} (${step.op}${step.t !== undefined ? ` ${step.t}` : ''})`;
      switch (step.op) {
        case 'riders': sim.setRiders(step.riders); break;
        case 'weather': sim.setWeather(weatherOf(step.weather)); break;
        case 'hidden': sim.setHiddenRegions(step.regions); break;
        case 'reset_weather': sim.resetWeather(); break;
        case 'pose': checkResult(sim, step, step.t, sim.poseAt(step.t), label, stats); break;
        case 'frame': checkResult(sim, step, step.t, sim.frame(step.t), label, stats); break;
        default: assert.fail(`${label}: unknown step`);
      }
    });
    t.diagnostic(`${scene.steps.length} steps, ${stats.snaps} full snapshots; worst transform difference ${stats.xf.toExponential(2)} (tolerance ${XF_TOL}), ` +
      `colour ${stats.color.toExponential(2)} (${COLOR_TOL}), rain state ${stats.react.toExponential(2)} (${RULE_TOL})`);
  });
}

// ---------------------------------------------------------------- determinism, Pause, no allocation pressure

test('the people are a pure function of the time: the same time poses the same, a repeated frame writes nothing', () => {
  const weather = { weather: 1, since: 500, prev: [1, 0, 0] };
  const a = new CityPeople({ time: 400, riders: {}, weather });
  const b = new CityPeople({ time: 400, riders: {}, weather });
  a.poseAt(505); a.poseAt(512.5); a.poseAt(530);
  b.poseAt(505); b.poseAt(512.5); b.poseAt(530);
  const sa = a.snapshot();
  const sb = b.snapshot();
  sa.forEach((arr, m) => assert.deepEqual(Array.from(arr), Array.from(sb[m]), `shape ${m}`));
  assert.ok(a.frame(530.5) > 0);
  assert.equal(a.frame(530.5), 0, 'paused: the same time and state writes nothing');
  a.setHiddenRegions(['gym_roof']);
  assert.ok(a.frame(530.5) > 0, 'a cutaway change runs the next frame');
  const [v, x, nv, nx] = M.poolPeaks();
  assert.ok(v < nv / 2 && x < nx / 2, `scratch pools have head room (${v}/${nv} vectors, ${x}/${nx} transforms)`);
});

test('a new city forgets the weather phases, the children on the wheel and the cutaway, like new people', () => {
  const rain = { weather: 1, since: 900, prev: [1, 0, 0] };
  const old = new CityPeople({ time: 880, riders: { 4: [7] }, weather: { weather: 0, since: -4, prev: [1, 0, 0] } });
  old.setWeather(rain);
  old.poseAt(905);
  old.setHiddenRegions(['gym_roof']);
  old.poseAt(950);
  old.setRiders({});
  old.newCity();
  old.poseAt(960);
  const fresh = new CityPeople({ time: 960, riders: {}, weather: rain });
  const a = old.snapshot();
  const b = fresh.snapshot();
  a.forEach((arr, m) => assert.deepEqual(Array.from(arr), Array.from(b[m]), `shape ${fx.shapes[m]}`));
  assert.equal(old.people.map((p) => (p.shown ? 1 : 0)).join(''), fresh.people.map((p) => (p.shown ? 1 : 0)).join(''));
});

// ---------------------------------------------------------------- the Three.js binding (js/people.js)

test('people.js writes the InstancedMeshes: matrices as the port, colours linear, needsUpdate only on change', async (t) => {
  const THREE = await import(path.join(web, 'vendor/three.module.js'));
  const { init } = await import(path.join(web, 'js/people.js'));
  const names = consts.People.MESH_NAMES;
  const nodes = new Map();
  names.forEach((name, m) => {
    const mesh = new THREE.InstancedMesh(new THREE.BufferGeometry(), new THREE.MeshBasicMaterial(), Math.max(1, fx.alloc[m]));
    mesh.count = fx.alloc[m];
    mesh.instanceColor = new THREE.InstancedBufferAttribute(new Float32Array(Math.max(1, fx.alloc[m]) * 3).fill(1), 3);
    nodes.set(`People/${name}`, mesh);
  });
  let now = 20;
  const app = { C: consts, node: (p) => nodes.get(p) || null, state: { states: null }, clock: { viewTime: () => now } };
  const mod = await init(app);
  assert.ok(app.people && typeof app.people.setHiddenRegions === 'function' && typeof app.people.snapshot === 'function');
  const ref = new CityPeople({ time: 20, riders: null, weather: null });
  const versions = () => names.map((name) => [nodes.get(`People/${name}`).instanceMatrix.version, nodes.get(`People/${name}`).instanceColor.version]);
  const sameAsRef = (label) => {
    names.forEach((name, m) => {
      const mesh = nodes.get(`People/${name}`);
      assert.deepEqual(Array.from(mesh.instanceMatrix.array.subarray(0, fx.alloc[m] * 16)), Array.from(ref.xf[m].subarray(0, fx.alloc[m] * 16)), `${label}: ${name} matrices`);
      const c = new THREE.Color();
      for (let i = 0; i < fx.alloc[m]; i++) {
        c.setRGB(ref.col[m][i * 3], ref.col[m][i * 3 + 1], ref.col[m][i * 3 + 2], THREE.SRGBColorSpace);
        const a = mesh.instanceColor.array;
        assert.ok(near(a[i * 3], c.r, 1e-6) && near(a[i * 3 + 1], c.g, 1e-6) && near(a[i * 3 + 2], c.b, 1e-6), `${label}: ${name}[${i}] linear colour`);
      }
    });
  };
  sameAsRef('after init');
  // a matrix is column-major with the last row 0 0 0 1
  const box = nodes.get('People/Box').instanceMatrix.array;
  assert.deepEqual([box[3], box[7], box[11], box[15]], [0, 0, 0, 1]);
  // frames: the same calls on the reference
  const states = { riders: { 4: [7] }, weather: 1, since: 20.5, prev: [1, 0, 0] };
  app.state.states = states;
  ref.setStates(states);
  for (const time of [20.5, 21, 21, 23.25, 30]) {
    now = time;
    mod.update(1 / 60, time);
    ref.frame(time);
    sameAsRef(`frame ${time}`);
  }
  const before = versions();
  mod.update(1 / 60, 30);   // paused: nothing written, nothing uploaded
  assert.deepEqual(versions(), before, 'a paused frame marks nothing for upload');
  mod.onMessage({ t: 'cutaway', hidden: {}, regions: ['gym_roof', 'cafe_terrace'] });
  ref.setHiddenRegions(['gym_roof', 'cafe_terrace']);
  mod.update(1 / 60, 30);
  ref.frame(30);
  sameAsRef('after cutaway');
  const after = versions();
  assert.ok(after.some((v, m) => v[0] > before[m][0]), 'the cutaway uploads the shapes that changed');
  assert.ok(after.every((v, m) => v[1] === before[m][1]), 'colours are not uploaded again when no look changed');
  const snap = app.people.snapshot(45.5);
  ref.poseAt(45.5);
  sameAsRef('snapshot(45.5)');
  assert.equal(snap.t, 45.5);
  assert.equal(snap.shapes.length, names.length);
  assert.equal(snap.shapes[0].xf.length, fx.alloc[0] * 12);
  assert.equal(snap.people.length, fx.persons.length);
  assert.equal(snap.people.filter((p) => !p.shown && p.region === 'gym_roof').length > 0, true, 'the people of a hidden region are not shown');
  t.diagnostic(`${fx.alloc.reduce((a, b) => a + b, 0)} instances in ${names.length} InstancedMeshes`);
});
