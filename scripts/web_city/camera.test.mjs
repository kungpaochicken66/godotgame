// Camera parity: the page's port (game/web_city/js/orbit.js and camera.js CityRig) against Godot's own camera
// rig and CityOrbit (fixture from game/tests/web_city/parity_camera.gd -> fixtures/camera.json).
//   node --test scripts/web_city/camera.test.mjs
//
// Tolerances (absolute, |port - Godot|). Godot computes Vector2/Vector3/Transform3D in 32-bit floats and the
// port in doubles; its scalars (yaw, pitch, distance) are doubles in both, but the distances come out of a
// bisection whose decisions are made on float32 transforms:
//   LEN    lengths and positions (m): camera origin, focus, pan, distance, ray origin  1e-4 m
//   UNIT   basis columns and ray directions (unitless)                                 1e-6
//   ANG    yaw and pitch (rad)                                                         1e-9 rad
//   PX     projected screen points (px)                                                1e-3 px
//   EXACT  factors, times, scales (gesture positions and lengths are float32 px: PX)  1e-9
// Strings, booleans and dictionary key sets must match exactly; so must every pick_place answer.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { setConsts, C } from '../../game/web_city/js/consts.js';
import * as O from '../../game/web_city/js/orbit.js';
import { CityRig } from '../../game/web_city/js/camera.js';

const here = path.dirname(fileURLToPath(import.meta.url));
setConsts(JSON.parse(fs.readFileSync(path.join(here, '../../game/web_city/data/consts.json'), 'utf8')));
const F = JSON.parse(fs.readFileSync(path.join(here, 'fixtures/camera.json'), 'utf8'));

const TOL = { LEN: 1e-4, UNIT: 1e-6, ANG: 1e-9, PX: 1e-3, EXACT: 1e-9 };
const worst = { LEN: 0, UNIT: 0, ANG: 0, PX: 0, EXACT: 0 };

const KIND = {
  yaw: 'ANG', pitch: 'ANG', distance: 'LEN', focus: 'LEN', pan: 'LEN', origin: 'LEN', o: 'LEN', basis: 'UNIT',
  dir: 'UNIT', d: 'UNIT', glide_t: 'EXACT', t0: 'EXACT', scale: 'EXACT', moved: 'PX', delta: 'PX', start: 'PX',
  last: 'PX',
};

/** Compares Godot's value `e` with the port's `a`; returns the first difference as text, or null. */
function diff(e, a, where, kind) {
  if (typeof e === 'number') {
    if (typeof a !== 'number' || Number.isNaN(a)) return `${where}: Godot ${e}, port ${a}`;
    const err = Math.abs(e - a);
    if (err > worst[kind]) worst[kind] = err;
    return err <= TOL[kind] ? null : `${where}: Godot ${e}, port ${a} (|d| ${err.toExponential(2)} > ${kind} ${TOL[kind]})`;
  }
  if (e === null || typeof e !== 'object') return e === a ? null : `${where}: Godot ${JSON.stringify(e)}, port ${JSON.stringify(a)}`;
  if (Array.isArray(e)) {
    if (!Array.isArray(a) || a.length !== e.length) return `${where}: Godot ${JSON.stringify(e)}, port ${JSON.stringify(a)}`;
    for (let i = 0; i < e.length; i++) {
      const r = diff(e[i], a[i], `${where}[${i}]`, kind);
      if (r) return r;
    }
    return null;
  }
  if (a === null || typeof a !== 'object') return `${where}: Godot ${JSON.stringify(e)}, port ${JSON.stringify(a)}`;
  const ek = Object.keys(e).sort();
  const ak = Object.keys(a).filter((k) => a[k] !== undefined).sort();
  if (ek.join() !== ak.join()) return `${where}: keys Godot [${ek}], port [${ak}]`;
  for (const k of ek) {
    const r = diff(e[k], a[k], `${where}.${k}`, KIND[k] || kind);
    if (r) return r;
  }
  return null;
}

const same = (e, a, where, kind = 'EXACT') => { const r = diff(e, a, where, kind); assert.equal(r, null, r || ''); };

// Godot's function name -> the port's, with the args as the fixture writes them
const CALLS = {
  max_distance: (a) => O.maxDistance(...a),
  overview: (a) => O.overview(...a),
  reset: (a) => O.reset(...a),
  stroll: (a) => O.stroll(...a),   // dest-fix r1
  zoom_levels: (a) => O.zoomLevels(...a),
  look_state: (a) => O.lookState(...a),
  pose: (a) => O.pose(...a),
  pose_xform: (a) => O.poseXform(...a),
  orbit: (a) => O.orbit(...a),
  zoom: (a) => O.zoom(...a),
  pan: (a) => O.pan(...a),
  follow_pose: (a) => O.followPose(...a),
  apply_pan: (a) => O.applyPan(...a),
  step_yaw: (a) => O.stepYaw(...a),
  step_zoom: (a) => O.stepZoom(...a),
  clamp_state: (a) => O.clampState(...a),
  wheel_factor: (a) => O.wheelFactor(...a),
  pinch_factor: (a) => O.pinchFactor(...a),
  glide: (a) => O.glide(...a),
  smooth: (a) => O.smooth(...a),
  project: (a) => O.project(...a),
  ray: (a) => O.ray(...a),
};
const RET_KIND = { max_distance: 'LEN', zoom_levels: 'LEN', apply_pan: 'LEN', project: 'PX' };

test('CityOrbit functions match Godot', () => {
  const seen = new Set();
  for (const [i, c] of F.calls.entries()) {
    const fn = CALLS[c.fn];
    assert.ok(fn, `no port for ${c.fn}`);
    seen.add(c.fn);
    const args = JSON.parse(JSON.stringify(c.args));
    same(c.ret, fn(args), `calls[${i}] ${c.fn}(${JSON.stringify(c.args).slice(0, 120)})`, RET_KIND[c.fn] || 'EXACT');
  }
  assert.equal(seen.size, Object.keys(CALLS).length, 'every ported function is sampled');
});

test('pick_place answers every ray as Godot does', () => {
  let n = 0;
  for (const [i, p] of F.pick.entries()) {
    assert.equal(O.pickPlace(p.o, p.d), p.key, `pick[${i}] o ${p.o} d ${p.d}`);
    n++;
  }
  assert.ok(n > 1000 && F.pick.some((p) => p.key === '') && new Set(F.pick.map((p) => p.key)).size >= 12, 'samples cover every place and empty space');
});

test('gesture arbitration matches Godot', () => {
  for (const [i, g] of F.gestures.entries()) {
    const [src, on, pos, t, scale, button] = g.new;
    const ge = O.gestureNew(src, on, pos, t, scale, button);
    same(g.start, ge, `gestures[${i}].new`);
    for (const [k, m] of g.moves.entries()) {
      O.gestureMove(ge, [m[0], m[1]], m[2], m[3]);
      same(g.after[k], ge, `gestures[${i}].after[${k}]`);
    }
    for (const [t2, want] of g.end) assert.equal(O.gestureEnd(ge, t2), want, `gestures[${i}] end at ${t2}`);
  }
});

function rigRecord(rig, view) {
  const xf = rig.xform();
  const r = {
    xf: { basis: xf.basis.slice(), origin: xf.origin.slice() },
    state: rig.cityState,
    look: rig.look,
    look_view: rig.lookView || {},
    gliding: rig.cityGliding(),
    glide_t: rig.glideT,
  };
  if (rig.curOk) r.cur = { yaw: rig.cur.yaw, pitch: rig.cur.pitch, distance: rig.cur.distance, focus: rig.cur.focus.slice() };
  return { r, view };
}

for (const run of F.rig) {
  test(`camera rig at ${run.view[0]}x${run.view[1]} replays Godot's sequence frame by frame`, () => {
    const view = run.view.slice();
    const rig = new CityRig(() => view);
    rig.child[0] = run.start_child[0]; rig.child[1] = run.start_child[1]; rig.child[2] = run.start_child[2];
    let k = 0;
    const check = (op, frame) => {
      const want = run.records[k++];
      assert.ok(want && want.op === op && want.frame === frame, `record ${k - 1} is op ${op} frame ${frame}`);
      const { r } = rigRecord(rig, view);
      const where = `${run.view.join('x')} op ${op} ${JSON.stringify(run.ops[op])} frame ${frame}`;
      const { rays, op: _o, frame: _f, ...rest } = want;
      same(rest, r, where);
      if (rays) {
        for (const [j, ry] of rays.entries()) {
          const mine = O.ray(rig.xform(), view, ry.screen);
          same({ o: ry.o, d: ry.d }, { o: mine.origin, d: mine.dir }, `${where} ray ${j}`);
          assert.equal(O.pickPlace(ry.o, ry.d), ry.key, `${where} ray ${j}: pick on Godot's ray`);
          assert.equal(O.pickPlace(mine.origin, mine.dir), ry.key, `${where} ray ${j}: pick on the port's ray`);
        }
      }
    };
    for (const [i, op] of run.ops.entries()) {
      switch (op[0]) {
        case 'enter': rig.enterCity(); break;
        case 'frames':
          for (let f = 0; f < op[1]; f++) {
            rig.process(op[2]);
            check(i, f);
          }
          continue;
        case 'orbit': rig.cityOrbit([op[1], op[2]]); break;
        case 'pan': rig.cityPan([op[1], op[2]]); break;
        case 'zoom': rig.cityZoom(op[1]); break;
        case 'wheel': rig.cityZoom(O.wheelFactor(op[1])); break;
        case 'pinch': rig.cityZoom(O.pinchFactor(op[1], op[2])); break;
        case 'step_zoom': rig.cityStepZoom(op[1]); break;
        case 'rotate': rig.rotateStep(op[1]); break;
        case 'toggle_zoom': rig.toggleZoom(); break;
        case 'reset': rig.cityReset(); break;
        case 'look_at': rig.cityLookAt(op[1]); break;
        case 'look_out': rig.cityLookOut(); break;
        case 'child': rig.child[0] = op[1]; rig.child[1] = op[2]; rig.child[2] = op[3]; break;
        case 'snap': rig.snap(); break;
        case 'reduce': rig.reduceMotion = op[1]; break;
        case 'view': view[0] = op[1]; view[1] = op[2]; break;
        case 'rays': break;
        default: assert.fail(`unknown op ${op[0]}`);
      }
      check(i, -1);
    }
    assert.equal(k, run.records.length, 'every record compared');
  });
}

test('worst differences (informational)', () => {
  console.log(`worst |port - Godot|: ${Object.entries(worst).map(([k, v]) => `${k} ${v.toExponential(2)} (tol ${TOL[k]})`).join(', ')}`);
});

test('every English text the HUD can show is in PAGE_STRINGS', async () => {
  const { PAGE_STRINGS } = await import('../../game/web_city/js/strings.js');
  const src = fs.readFileSync(path.join(here, '../../game/web_city/js/hud.js'), 'utf8');
  const found = new Set();
  const grab = (re) => { for (const m of src.matchAll(re)) for (const g of m.slice(1)) if (g) found.add(g); };
  grab(/button\('[^']*', '[^']*', '([^']+)'/g);                 // tooltips and accessible names
  grab(/say\([a-zA-Z]+, '([^']+)'/g);                           // labels
  grab(/app\.tr\('([^']+)'\)/g);
  grab(/const [lp]t = [a-z]+ \? '([^']+)' : '([^']+)'/g);        // the two-state labels (Look, Pause)
  const wt = src.match(/const WEATHER_TEXT = \{([^}]*)\}/);
  for (const m of wt[1].matchAll(/'([^']+)'/g)) found.add(m[1]);
  for (const b of Object.values(C.CityMap.BUILDINGS)) found.add(String(b.name));   // "City · <building>"
  const missing = [...found].filter((s) => !PAGE_STRINGS.includes(s));
  assert.deepEqual(missing, [], 'texts the page shows but PAGE_STRINGS lacks');
  const unused = PAGE_STRINGS.filter((s) => !found.has(s));
  assert.deepEqual(unused, [], 'PAGE_STRINGS entries the page never shows');
  assert.ok(found.size >= 15, `found ${found.size} texts`);
});
