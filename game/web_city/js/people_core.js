// The city's people, ported function by function from art/city_people.gd (city r3): about fifty townsfolk
// drawn as instances of twelve part shapes and animated as a pure function of the city's view clock.
//
// This file is the node itself: who the people are (setup), their looks and colours, the Ferris passengers,
// the per-frame scheduling (frame: the moving people every frame, the slow ones in alternating halves),
// the drawing of a pose (_draw: frames, IK/FK, every part's instance transform) and the rain behaviour
// (cover, umbrellas, the way back; staggered groups). The poses are in people_pose.js, the pure rules in
// people_rules.js, the maths in people_math.js. js/people.js binds it to the Three.js InstancedMeshes.
//
// What is exported instead of ported (consts.extra.people, tests/web_city/export_people.gd): the tables Godot
// works out once at load from the navigation: the cover spots, who reacts to rain, the static people's fixed
// routes to cover, the walkers' lanes and their ways off them. Everything that depends on time is ported.
//
// Instance buffers: one Float32Array per shape, 16 numbers per instance (a column-major 4 x 4 matrix, as
// THREE.InstancedMesh.instanceMatrix), and the instance colours as Godot's sRGB-encoded r, g, b.
// A hidden instance is Godot's `_zero`: zero scale at (0, -50, 0).
// Nothing is created per frame: no arrays, objects, closures or strings (poses, path evaluations and
// temporaries are preallocated; a weather change, four City states a second and setup may allocate). An
// engine may still box numbers passed between functions it does not inline (V8 does, measurably).
// No DOM, no Three.js: importable in Node (scripts/web_city/people.test.mjs).
import { C } from './consts.js';
import {
  hash01, seedOf, timing, floorY, ferrisRides, gondolaLap, umbrellaFor, groupDelay,
  walkLoops, loopIndex, polyProject, walkerPose, ferrisAngleAt, riderTransform, carouselSeatTransform,
} from './people_rules.js';
import {
  f, V, set3, setX, vadd, vaddc, vsub, vmul, vlerp, vnorm, dist, resetPools,
  rotX, rotY, rotZ, bMul, bScaled, bXformc, xOf, xMul, xPointc, xScale, xAffineInverse,
  clampf, fposmod, lerpAngle, wrapf,
} from './people_math.js';
import * as PP from './people_pose.js';
import { Pose, bindConsts, frames, ik, fk, along, smooth, pose as poseOf, walkCycle, mix, coverIdle, umbrellaArm, period } from './people_pose.js';

const HEX = (s) => [f(parseInt(s.slice(1, 3), 16) / 255), f(parseInt(s.slice(3, 5), 16) / 255), f(parseInt(s.slice(5, 7), 16) / 255), 1];
const COL_WHITE = HEX('#ffffff');
const COL_DARK = HEX('#2f2c2a');
const COL_BLUE = HEX('#bfe4ff');
const COL_FOOD = HEX('#e8b06a');
const COL_PAN = HEX('#3a3f47');
const COL_EGG = HEX('#f2c94c');
const COL_TRAY = HEX('#dde2e8');
const COL_PEACH = HEX('#ffc7a6');

const sameColor = (a, b) => a[0] === b[0] && a[1] === b[1] && a[2] === b[2] && a[3] === b[3];
const rgba = (o) => (Array.isArray(o) ? o : o.color);

/** How many held or placed things an action uses (prop slots A, B). */
function propsOf(action) {
  switch (action) {
    case 'type': case 'read_screen': case 'chat': case 'eat': case 'phone': case 'cook': case 'wait_tables': case 'lift':
      return 2;
    case 'drink': case 'serve_counter': case 'wipe_counter': case 'browse': case 'carry_bag': case 'row':
      return 1;
    default:
      return 0;
  }
}

export class Person {
  constructor() {
    this.id = '';
    this.kind = 0;
    this.index = 0;
    this.action = '';
    this.region = 'ground';
    this.looks = [];
    this.look = null;
    this.lookI = -1;
    this.seated = false;          // the lap rig (legs at rest under a table)
    this.legsStill = false;       // lower parts written only when the person appears (static people only)
    this.fast = false;            // posed every frame
    this.group = 0;
    this.root = new Float32Array([1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0]);
    this.seat = 0.0;              // seat height above the root (m)
    this.table = new Float32Array(2);   // (distance ahead to the edge, top height) in m
    this.offset = 0.0;
    this.rate = 1.0;
    this.slot = 6.0;
    this.partnerYaw = 0.0;        // the partner's direction (local yaw), 0 when none
    this.partnerRank = 0;         // 0 or 1 in a pair (who speaks first)
    this.pairSeed = 0;
    this.hasPartner = false;
    this.s = 1.0;                 // body scale
    this.sd = 0;
    this.wphase = 0.0;            // a walker's stride phase (0..1) this frame
    this.slots = null;            // Int32Array(P_COUNT): (shape << 16) | instance, or -1
    this.partOn = null;           // Uint8Array(P_COUNT): whether a part shows for the current look
    this.hairPart = new Map();    // hair style -> part index
    this.shown = false;
    this.pose = new Pose();
    this.world = new Float32Array(12);       // the last root * scale drawn
    this.homeWorld = new Float32Array(12);   // where its activity is, scaled (a cup left there stays there)
    // rain (r3)
    this.react = false;           // outdoors and not under cover: reacts to rain
    this.umbrella = false;        // opens an umbrella and carries on (else takes cover)
    this.legsSeat = false;        // seated on the legs rig (gets up in the rain)
    this.spot = -1;               // its cover stand spot (index into the node's spots)
    this.base = new Float32Array(0);      // its path, home end first, cover spot last (world), 3 numbers a point
    this.baseLen = new Float32Array(0);   // cumulative lengths
    this.baseReg = [];                    // the region of each point
    this.baseN = 0;
    this.laneE = 0.0;             // walkers: the path length along their lane (then the leg off it)
    this.lamD = 0.0;              // walkers: lane time at the path's start; carousel riders: the departure time
    this.laneDir = 1.0;           // walkers: +1 along their lane's direction, -1 against it
    this.laneSpeed = 1.0;
    this.phD = 0.0;               // the stride phase at the path's start
    this.rec = null;              // the current weather phase (see _begin); null: none
    this.umbHand = 1;             // the hand that holds the umbrella
  }

  tau(t) { return t * this.rate + this.offset; }
}

// scratch (never held across a person's update)
const FRD = [new Float32Array(12), new Float32Array(12), new Float32Array(12)];
const LEGS = [[new Float32Array(3), new Float32Array(3), new Float32Array(3)], [new Float32Array(3), new Float32Array(3), new Float32Array(3)]];
const JA = new Float32Array(3);
const JB = new Float32Array(3);
const HANDS = [new Float32Array(3), new Float32Array(3)];
const WP = { x: 0, z: 0, ry: 0, phase: 0 };
const PRJ = { arc: 0, dist: 0 };
const P2 = { x: 0, y: 0 };
const AT = { pos: new Float32Array(3), dx: 0, dy: 1, region: 'ground' };
const newEval = () => ({ s: 0.0, onLane: true, lam: 0.0, walked: 0.0, pd: 0.0, umb: 0.0, ph: -1.0, moving: false, back: false });

export class CityPeople {
  /**
   * Builds every person and the instance buffers, then poses everybody once (Godot's setup()).
   * opts: time (the view time of that first pose, default 0), riders ({gondola: [peers]}), weather (the City
   * states or {weather, since, prev}), matrices (one Float32Array of 16 * count per shape, e.g. each
   * InstancedMesh's instanceMatrix.array; allocated here when absent), onColor(shape, instance, r, g, b)
   * (called for every instance colour set, with Godot's sRGB-encoded values).
   */
  constructor(opts = {}) {
    const K = C.People;
    bindConsts(K);
    this.K = K;
    this.M_COUNT = K.M_COUNT;
    this.meshNames = K.MESH_NAMES;
    /** Per-frame accounting (tests and the report): instance transforms written by the last frame() or poseAt(). */
    this.writesLast = 0;
    this.people = [];
    this.byId = new Map();
    this.hiddenRegions = new Set();
    this.riders = opts.riders || {};
    this.weatherState = opts.weather === undefined ? null : opts.weather;
    this.onColor = opts.onColor || null;
    this.alloc = new Int32Array(this.M_COUNT);
    this.xf = [];                 // per shape: the instance matrices as written
    this.col = [];                // per shape: the instance colours as set (sRGB r, g, b)
    this.dirty = new Uint8Array(this.M_COUNT);        // shapes whose matrices changed (the owner clears it)
    this.colorDirty = new Uint8Array(this.M_COUNT);   // shapes whose colours changed (the owner clears it)
    this._frame = 0;
    this._lastT = -Infinity;
    this._lastKey = '';
    this._lastWkey = '';
    this._ridersKey = '';
    this._busy = [];              // the gondolas with a child aboard
    const gondolas = Math.trunc(Number(C.CityMap.FERRIS.gondolas));
    this._childLap = new Float64Array(gondolas).fill(-999999);   // gondola -> the lap in which a child was last aboard
    this._fer = new Int32Array(C.PeopleData.FERRIS_SLOTS.length * 4);
    // weather
    this.spots = [];              // every cover stand spot: {region, x, y (the ground z), h, cover, shop}
    this._wkey = '';
    this._wRain = null;
    this._wSince = NaN;
    this._wPrev = null;
    this._held = new Map();       // spot -> static person id (assigned at build)
    this._exits = new Map();      // loop * 4096 + spot -> {arc, len, leg: Float32Array (x, y pairs)}
    this._tmpA = new Pose();
    this._tmpB = new Pose();
    this._ev = newEval();
    this._w = { rain: false, since: -1.0e9, prevRain: false };
    this._gap = [f(C.extra.people.gap_dir[0]), f(C.extra.people.gap_dir[1])];
    this._setRidersKey();
    resetPools();
    this._makePeople();
    this._makeMeshes(opts.matrices || null);
    this.poseAt(opts.time === undefined ? 0.0 : opts.time);
  }

  // ===================================================================== setup

  _makePeople() {
    const D = C.PeopleData;
    const K = this.K;
    for (const e of D.PEOPLE) {
      const p = new Person();
      p.id = String(e.id);
      p.kind = K.K_STATIC;
      p.action = String(e.action);
      p.region = String(e.region);
      p.looks = [e.look];
      const poseName = String(e.pose);
      let y = floorY(p.region);
      const yo = Number(e.y_offset);
      if (poseName === 'stand' || poseName === 'run' || poseName === 'stretch') y += yo;
      else p.seat = yo;
      setX(p.root, xOf(rotY(Number(e.ry)), V(e.pos[0], y, e.pos[1])));
      p.table[0] = e.table[0];
      p.table[1] = e.table[1];
      p.seated = D.SEATED_ACTIONS.includes(p.action);
      p.legsStill = p.seated || ['serve_counter', 'wipe_counter', 'browse', 'carry_bag', 'cook'].includes(p.action);
      p.fast = ['run', 'cycle', 'row', 'stretch', 'lift', 'wait_tables'].includes(p.action);
      this._addTiming(p);
      this.people.push(p);
    }
    // partners: the nearest other seated person at the same table (within 2.2 m on the same region)
    for (const p of this.people) {
      if (!p.seated) continue;
      let best = null;
      let bd = 2.2;
      for (const q of this.people) {
        if (q === p || !q.seated || q.region !== p.region) continue;
        const d = dist(p.root.subarray(9, 12), q.root.subarray(9, 12));
        if (d < bd) {
          bd = d;
          best = q;
        }
      }
      if (best !== null) {
        const inv = xAffineInverse(p.root);
        const rel = xPointc(inv, best.root[9], best.root[10], best.root[11]);
        p.partnerYaw = Math.atan2(rel[0], rel[2]);
        p.hasPartner = true;
        p.partnerRank = p.id < best.id ? 0 : 1;
        p.pairSeed = seedOf(p.id < best.id ? p.id + best.id : best.id + p.id);
      }
    }
    for (let i = 0; i < D.WALKER_LOOKS.length; i++) {
      const p = new Person();
      p.id = `walker_${i}`;
      p.kind = K.K_WALKER;
      p.index = i;
      p.action = 'walk';
      p.looks = [D.WALKER_LOOKS[i].look];
      p.fast = true;
      this._addTiming(p);
      this.people.push(p);
    }
    for (const sl of D.FERRIS_SLOTS) {
      const p = new Person();
      p.id = `ferris_${Math.trunc(sl.slot)}`;
      p.kind = K.K_FERRIS;
      p.index = Math.trunc(sl.slot);
      p.action = 'sit_ride';
      for (const l of sl.looks) p.looks.push(l.look);
      p.seated = true;
      p.fast = true;
      p.seat = K.BENCH_Y;
      this._addTiming(p);
      this.people.push(p);
    }
    for (const c of D.CAROUSEL_RIDERS) {
      const p = new Person();
      p.id = String(c.id);
      p.kind = K.K_CAROUSEL;
      p.index = Math.trunc(c.horse);
      p.action = 'sit_ride';
      p.looks = [c.look];
      p.fast = true;
      p.seat = K.SADDLE_UP;
      this._addTiming(p);
      this.people.push(p);
    }
    this._setupWeather();
    let k = 0;
    for (const p of this.people) {
      this.byId.set(p.id, p);
      if (!p.fast) {
        p.group = k % K.SLOW_GROUPS;
        k += 1;
      }
    }
  }

  _addTiming(p) {
    const tm = timing(p.id);
    p.offset = tm.offset;
    p.rate = tm.rate;
    p.slot = tm.slot;
    p.sd = seedOf(p.id);
  }

  /** The part shapes a person needs over all its looks, then one instance per part. */
  _makeMeshes(matrices) {
    const K = this.K;
    const D = C.PeopleData;
    const white = rgba(D.WHITE);
    this.alloc.fill(0);
    for (const p of this.people) {
      p.slots = new Int32Array(K.P_COUNT).fill(-1);
      p.partOn = new Uint8Array(K.P_COUNT).fill(1);
      const need = new Map([[K.P_TORSO, K.M_BOX], [K.P_HEAD, K.M_HEAD], [K.P_UARM0, K.M_LIMB], [K.P_UARM1, K.M_LIMB],
        [K.P_FARM0, K.M_LIMB], [K.P_FARM1, K.M_LIMB], [K.P_HAND0, K.M_BLOCK], [K.P_HAND1, K.M_BLOCK]]);
      if (p.seated) {
        need.set(K.P_LAP, K.M_BOX);
        need.set(K.P_SHINS, K.M_BLOCK);
        need.set(K.P_SHOES, K.M_BLOCK);
      } else {
        need.set(K.P_PELVIS, K.M_BOX);
        for (const part of [K.P_THIGH0, K.P_THIGH1, K.P_SHIN0, K.P_SHIN1]) need.set(part, K.M_LIMB);
        need.set(K.P_SHOE0, K.M_BLOCK);
        need.set(K.P_SHOE1, K.M_BLOCK);
      }
      let hk = 0;
      for (const l of p.looks) {
        const top = String(l.top);
        const acc = String(l.accessory);
        if (top === 'dress' && !p.seated) need.set(K.P_SKIRT, K.M_SKIRT);
        if (top === 'apron' || (top === 'uniform' && !sameColor(rgba(l.top_color), white))) need.set(K.P_APRON, K.M_BLOCK);
        if (top === 'jacket') need.set(K.P_FRONT, K.M_BLOCK);
        if (acc === 'glasses') need.set(K.P_GLASSES, K.M_BLOCK);
        if (acc === 'beard') need.set(K.P_BEARD, K.M_BLOCK);
        if (acc === 'bag' && !p.seated) need.set(K.P_BAG, K.M_BLOCK);
        if (acc === 'scarf') need.set(K.P_SCARF, K.M_BLOCK);
        const hs = String(l.hair_style);
        if (K.HAIR_MESH[hs] !== undefined && !p.hairPart.has(hs) && hk < 3) {
          p.hairPart.set(hs, K.P_HAIR0 + hk);
          need.set(K.P_HAIR0 + hk, K.HAIR_MESH[hs]);
          hk += 1;
        }
      }
      for (let n = 0; n < propsOf(p.action); n++) need.set(K.P_PROP_A + n, K.M_BLOCK);
      if (p.umbrella) need.set(K.P_UMBRELLA, K.M_UMBRELLA);
      for (const [part, m] of need) {
        p.slots[part] = (m << 16) | this.alloc[m];
        this.alloc[m] += 1;
      }
    }
    for (let m = 0; m < this.M_COUNT; m++) {
      const n = this.alloc[m];
      let buf = matrices ? matrices[m] : null;
      if (buf) {
        if (buf.length < n * 16) throw new Error(`people: shape ${this.meshNames[m]} has room for ${buf.length / 16} instances, the people need ${n}`);
      } else {
        buf = new Float32Array(Math.max(1, n) * 16);
      }
      this.xf.push(buf);
      this.col.push(new Float32Array(Math.max(1, n) * 3).fill(1));
      for (let i = 0; i < n; i++) this._writeZero(m, i);
      this.dirty[m] = 1;
    }
    for (const p of this.people) this._setLook(p, 0);
  }

  // ===================================================================== looks and colours

  _setLook(p, i) {
    if (p.lookI === i) return;
    const K = this.K;
    const D = C.PeopleData;
    p.lookI = i;
    p.look = p.looks[Math.min(Math.max(i, 0), p.looks.length - 1)];
    const l = p.look;
    p.s = Number(l.scale);
    const skin = rgba(l.skin);
    const top = rgba(l.top_color);
    const bottom = rgba(l.bottom_color);
    const shoes = rgba(l.shoes);
    const accent = rgba(l.accent);
    const hair = rgba(l.hair_color);
    const white = rgba(D.WHITE);
    const kind = String(l.top);
    const acc = String(l.accessory);
    const longSleeves = kind === 'shirt' || kind === 'jacket' || kind === 'uniform';
    const bareLegs = kind === 'dress' || kind === 'sports';
    this._col(p, K.P_TORSO, top);
    this._col(p, K.P_HEAD, skin);
    this._col(p, K.P_UARM0, top);
    this._col(p, K.P_UARM1, top);
    this._col(p, K.P_FARM0, longSleeves ? top : skin);
    this._col(p, K.P_FARM1, longSleeves ? top : skin);
    this._col(p, K.P_HAND0, skin);
    this._col(p, K.P_HAND1, skin);
    this._col(p, K.P_PELVIS, kind === 'dress' ? top : bottom);
    this._col(p, K.P_THIGH0, kind === 'dress' ? skin : bottom);
    this._col(p, K.P_THIGH1, kind === 'dress' ? skin : bottom);
    this._col(p, K.P_SHIN0, bareLegs ? skin : bottom);
    this._col(p, K.P_SHIN1, bareLegs ? skin : bottom);
    this._col(p, K.P_SHOE0, shoes);
    this._col(p, K.P_SHOE1, shoes);
    this._col(p, K.P_LAP, kind === 'dress' ? top : bottom);
    this._col(p, K.P_SHINS, bareLegs ? skin : bottom);
    this._col(p, K.P_SHOES, shoes);
    this._col(p, K.P_SKIRT, top);
    this._col(p, K.P_APRON, accent);
    this._col(p, K.P_FRONT, !sameColor(top, white) ? white : COL_BLUE);
    this._col(p, K.P_GLASSES, COL_DARK);
    this._col(p, K.P_BEARD, hair);
    this._col(p, K.P_BAG, accent);
    this._col(p, K.P_SCARF, accent);
    for (const part of p.hairPart.values()) this._col(p, part, hair);
    let pa = COL_WHITE;
    let pb = COL_WHITE;
    switch (p.action) {
      case 'phone': pa = COL_DARK; break;
      case 'eat': pa = COL_FOOD; break;
      case 'cook': pa = COL_PAN; pb = COL_EGG; break;
      case 'wait_tables': pa = COL_TRAY; pb = COL_WHITE; break;
      case 'serve_counter': case 'browse': case 'carry_bag':
        pa = rgba(D.TOP_COLORS[seedOf(p.id) % D.TOP_COLORS.length]);
        break;
      case 'wipe_counter': pa = COL_BLUE; break;
      case 'row': case 'lift': pa = COL_PAN; pb = COL_PAN; break;
      default: break;
    }
    if (p.action === 'type' || p.action === 'read_screen' || p.action === 'chat' || p.action === 'eat') {
      pb = hash01(seedOf(p.id), 7) < 0.5 ? COL_WHITE : COL_PEACH;
    }
    if (p.action === 'drink') pa = hash01(seedOf(p.id), 7) < 0.5 ? COL_WHITE : COL_BLUE;
    this._col(p, K.P_PROP_A, pa);
    this._col(p, K.P_PROP_B, pb);
    const uc = K.UMBRELLA_COLORS;
    this._col(p, K.P_UMBRELLA, rgba(uc[p.sd % uc.length]));
    // whether each part shows for this look (_part_on)
    const on = p.partOn;
    on.fill(1);
    on[K.P_SKIRT] = kind === 'dress' ? 1 : 0;
    on[K.P_APRON] = (kind === 'apron' || (kind === 'uniform' && !sameColor(top, white))) ? 1 : 0;
    on[K.P_FRONT] = kind === 'jacket' ? 1 : 0;
    on[K.P_GLASSES] = acc === 'glasses' ? 1 : 0;
    on[K.P_BEARD] = acc === 'beard' ? 1 : 0;
    on[K.P_BAG] = acc === 'bag' ? 1 : 0;
    on[K.P_SCARF] = acc === 'scarf' ? 1 : 0;
    const hs = String(l.hair_style);
    for (let part = K.P_HAIR0; part <= K.P_HAIR2; part++) on[part] = (p.hairPart.has(hs) && p.hairPart.get(hs) === part) ? 1 : 0;
    p.shown = false;     // rewrite every part (the visible set may change with the look)
  }

  _col(p, part, c) {
    const sl = p.slots[part];
    if (sl < 0) return;
    const m = sl >> 16;
    const i = sl & 0xFFFF;
    const a = this.col[m];
    a[i * 3] = c[0];
    a[i * 3 + 1] = c[1];
    a[i * 3 + 2] = c[2];
    this.colorDirty[m] = 1;
    if (this.onColor) this.onColor(m, i, c[0], c[1], c[2]);
  }

  // ===================================================================== the riders

  /** The child riders, {gondola: [peers]} (City states "riders"). */
  setRiders(riders) {
    this.riders = riders || {};
    this._setRidersKey();
  }

  _setRidersKey() {
    this._ridersKey = JSON.stringify(this.riders);
    this._busy.length = 0;
    for (const g of Object.keys(this.riders)) {
      const list = this.riders[g];
      if (Array.isArray(list) && list.length > 0) this._busy.push(Math.trunc(Number(g)));
    }
  }

  /** The shared weather: the City states, or {weather, since, prev}; null: no weather known (sunny, no memory). */
  setWeather(state) { this.weatherState = state === undefined ? null : state; }

  /** Both from the City states (client form). */
  setStates(states) {
    this.setRiders(states ? states.riders : null);
    this.setWeather(states || null);
  }

  // ===================================================================== visibility

  /**
   * The regions whose storeys the cutaway hides: the people there hide with them (an empty list shows
   * everyone).
   */
  setHiddenRegions(regions) {
    this.hiddenRegions.clear();
    if (regions) for (const r of regions) this.hiddenRegions.add(String(r));
    this._lastT = -Infinity;
  }

  /**
   * Which Ferris slots ride now: this._fer, 4 numbers per slot [gondola (-1: not riding), seat, ride, variant].
   * A gondola with a child aboard, or that had one since its last bottom pass, carries none.
   */
  ferrisNow(t) {
    const lap = this._childLap;
    const busy = this._busy;
    for (let i = 0; i < busy.length; i++) {
      const g = busy[i];
      if (g >= 0 && g < lap.length) lap[g] = gondolaLap(g, t);
    }
    const fer = ferrisRides(t, this._fer);
    for (let k = 0; k < fer.length; k += 4) {
      const g = fer[k];
      if (g < 0) continue;
      let taken = false;
      for (let i = 0; i < busy.length; i++) if (busy[i] === g) taken = true;
      if (taken || (g < lap.length && lap[g] === gondolaLap(g, t))) fer[k] = -1;
    }
    return fer;
  }

  // ===================================================================== per frame

  /**
   * One frame's update: the moving people every frame, the slow ones in alternating halves. Returns the
   * number of instance transforms written.
   */
  frame(t) {
    this._weatherTick(t);
    if (t === this._lastT && this._ridersKey === this._lastKey && this._wkey === this._lastWkey) {
      this.writesLast = 0;
      return 0;        // paused: nothing moves
    }
    this._lastT = t;
    this._lastKey = this._ridersKey;
    this._lastWkey = this._wkey;
    this._frame += 1;
    this.writesLast = 0;
    const fer = this.ferrisNow(t);
    const people = this.people;
    const turn = this._frame % this.K.SLOW_GROUPS;
    const kStatic = this.K.K_STATIC;
    for (let i = 0; i < people.length; i++) {
      const p = people[i];
      const stale = p.kind === kStatic && this.hiddenRegions.has(p.region) === p.shown;
      if (p.fast || p.group === turn || !p.shown || stale) this._update(p, t, fer, false);
    }
    return this.writesLast;
  }

  /** Poses everybody at time t (deterministic; the tests use it). Returns the transforms written. */
  poseAt(t) {
    this.writesLast = 0;
    this._weatherTick(t);
    const fer = this.ferrisNow(t);
    const people = this.people;
    for (let i = 0; i < people.length; i++) this._update(people[i], t, fer, true);
    this._lastT = t;
    this._lastKey = this._ridersKey;
    this._lastWkey = this._wkey;
    return this.writesLast;
  }

  /** Poses and writes one person; `force` rewrites every part (else the still ones only when they appear). */
  _update(p, t, fer, force) {
    resetPools();
    if (p.react) {
      this._updateReact(p, t, force);
      return;
    }
    const K = this.K;
    let visibleNow = true;
    let root = p.root;
    switch (p.kind) {
      case K.K_STATIC:
        visibleNow = !this.hiddenRegions.has(p.region);
        break;
      case K.K_WALKER: {
        const w = walkerPose(p.index, t, WP);
        p.wphase = w.phase;
        root = xOf(rotY(w.ry), V(w.x, 0.0, w.z));
        break;
      }
      case K.K_FERRIS: {
        const k = p.index * 4;
        if (fer[k] < 0) {
          visibleNow = false;
        } else {
          this._setLook(p, fer[k + 3]);
          root = riderTransform(fer[k], ferrisAngleAt(t), fer[k + 1]);
        }
        break;
      }
      case K.K_CAROUSEL:
        root = carouselSeatTransform(p.index, t);
        break;
      default: break;
    }
    if (!visibleNow) {
      this._hide(p, force);
      return;
    }
    const full = force || !p.shown;
    const s = p.s;
    setX(p.world, bScaled(root, s, s, s));
    p.world[9] = root[9]; p.world[10] = root[10]; p.world[11] = root[11];
    setX(p.homeWorld, p.world);
    const po = p.pose;
    po.reset();
    poseOf(p, t, po);
    this._draw(p, po, full);
    p.shown = true;
  }

  _hide(p, force) {
    if (p.shown || force) {
      const slots = p.slots;
      for (let part = 0; part < slots.length; part++) {
        const sl = slots[part];
        if (sl >= 0) this._putZero(sl);
      }
      p.shown = false;
    }
  }

  /** A part's instance transform as last written, 12 numbers in Godot's order (tests and tours). */
  partTransform(p, part, out = new Float32Array(12)) {
    const sl = p.slots[part];
    if (sl < 0) {
      out.fill(0);
      out[10] = -50.0;
      return out;
    }
    return this._read(sl >> 16, sl & 0xFFFF, out, 0);
  }

  _read(m, i, out, at) {
    const a = this.xf[m];
    const o = i * 16;
    out[at] = a[o]; out[at + 1] = a[o + 1]; out[at + 2] = a[o + 2];
    out[at + 3] = a[o + 4]; out[at + 4] = a[o + 5]; out[at + 5] = a[o + 6];
    out[at + 6] = a[o + 8]; out[at + 7] = a[o + 9]; out[at + 8] = a[o + 10];
    out[at + 9] = a[o + 12]; out[at + 10] = a[o + 13]; out[at + 11] = a[o + 14];
    return out;
  }

  /**
   * Every instance transform as last written, shape by shape: an array of Float32Array, 12 numbers per
   * instance in Godot's order (the basis's x, y, z columns, then the origin).
   */
  snapshot() {
    const out = [];
    for (let m = 0; m < this.M_COUNT; m++) {
      const n = this.alloc[m];
      const a = new Float32Array(n * 12);
      for (let i = 0; i < n; i++) this._read(m, i, a, i * 12);
      out.push(a);
    }
    return out;
  }

  /** The person with an id (null when none). */
  person(id) { return this.byId.get(id) || null; }

  _writeZero(m, i) {
    const a = this.xf[m];
    const o = i * 16;
    a[o] = 0; a[o + 1] = 0; a[o + 2] = 0; a[o + 3] = 0;
    a[o + 4] = 0; a[o + 5] = 0; a[o + 6] = 0; a[o + 7] = 0;
    a[o + 8] = 0; a[o + 9] = 0; a[o + 10] = 0; a[o + 11] = 0;
    a[o + 12] = 0; a[o + 13] = -50.0; a[o + 14] = 0; a[o + 15] = 1;
  }

  _putZero(sl) {
    const m = sl >> 16;
    this._writeZero(m, sl & 0xFFFF);
    this.dirty[m] = 1;
    this.writesLast += 1;
  }

  /** Writes world * local (two transforms in Godot's 12-number layout) as the instance's matrix. */
  _putMul(sl, w, l) {
    const m = sl >> 16;
    const a = this.xf[m];
    const o = (sl & 0xFFFF) * 16;
    const w0 = w[0], w1 = w[1], w2 = w[2], w3 = w[3], w4 = w[4], w5 = w[5], w6 = w[6], w7 = w[7], w8 = w[8];
    a[o] = w0 * l[0] + w3 * l[1] + w6 * l[2];
    a[o + 1] = w1 * l[0] + w4 * l[1] + w7 * l[2];
    a[o + 2] = w2 * l[0] + w5 * l[1] + w8 * l[2];
    a[o + 3] = 0;
    a[o + 4] = w0 * l[3] + w3 * l[4] + w6 * l[5];
    a[o + 5] = w1 * l[3] + w4 * l[4] + w7 * l[5];
    a[o + 6] = w2 * l[3] + w5 * l[4] + w8 * l[5];
    a[o + 7] = 0;
    a[o + 8] = w0 * l[6] + w3 * l[7] + w6 * l[8];
    a[o + 9] = w1 * l[6] + w4 * l[7] + w7 * l[8];
    a[o + 10] = w2 * l[6] + w5 * l[7] + w8 * l[8];
    a[o + 11] = 0;
    a[o + 12] = f(w0 * l[9] + w3 * l[10] + w6 * l[11]) + w[9];
    a[o + 13] = f(w1 * l[9] + w4 * l[10] + w7 * l[11]) + w[10];
    a[o + 14] = f(w2 * l[9] + w5 * l[10] + w8 * l[11]) + w[11];
    a[o + 15] = 1;
    this.dirty[m] = 1;
    this.writesLast += 1;
  }

  _place(p, part, local) {
    const sl = p.slots[part];
    if (sl < 0) return;
    if (!p.partOn[part]) {
      this._putZero(sl);
      return;
    }
    this._putMul(sl, p.world, local);
  }

  // ===================================================================== drawing a pose

  _draw(p, po, full) {
    const K = PP;
    const fr = frames(po, FRD);
    const female = p.look.sex === 'f';
    const slots = p.slots;
    // the legs first: planting the lower foot on the floor lifts or lowers the whole body
    if (!p.seated) {
      for (let k = 0; k < 2; k++) {
        const sg = k === 0 ? -1.0 : 1.0;
        const hj = xPointc(fr[0], sg * K.HIP_X, 0.0, 0.0);
        if (po.legIk[k]) ik(hj, po.leg[k], K.THIGH, K.SHIN, bXformc(fr[0], 0.0, 0.25, 1.0), JA, JB);
        else fk(hj, fr[0], po.leg[k], sg, K.THIGH, K.SHIN, true, JA, JB);
        set3(LEGS[k][0], hj);
        set3(LEGS[k][1], JA);
        set3(LEGS[k][2], JB);
      }
      if (po.plant) {
        const lift = f((po.ground - (Math.min(LEGS[0][2][1], LEGS[1][2][1]) - K.SHOE_H)) * po.plantK);
        for (let k = 0; k < 3; k++) fr[k][10] += lift;
        for (let k = 0; k < 2; k++) for (let j = 0; j < 3; j++) LEGS[k][j][1] += lift;
      }
    }
    const pel = fr[0];
    const tor = fr[1];
    const head = fr[2];
    const tw = female ? 0.39 : 0.44;
    // torso and head
    const torso = bScaled(tor, tw, K.TORSO_H, K.TORSO_D);
    const tc = xPointc(tor, 0, 0.1 + K.TORSO_H * 0.5, 0);
    torso[9] = tc[0]; torso[10] = tc[1]; torso[11] = tc[2];
    this._place(p, K.P_TORSO, torso);
    const hc = xMul(head, xScale(1, 1, 1, 0, K.HEAD_C, 0));
    this._place(p, K.P_HEAD, hc);
    this._place(p, K.P_HAIR0, hc);
    this._place(p, K.P_HAIR1, hc);
    this._place(p, K.P_HAIR2, hc);
    if (slots[K.P_GLASSES] >= 0) this._place(p, K.P_GLASSES, xMul(hc, xScale(0.3, 0.07, 0.02, 0, 0.02, 0.168)));
    if (slots[K.P_BEARD] >= 0) this._place(p, K.P_BEARD, xMul(hc, xScale(0.3, 0.14, 0.06, 0, -0.12, 0.13)));
    if (slots[K.P_SCARF] >= 0) this._place(p, K.P_SCARF, xMul(tor, xScale(tw * 0.75, 0.09, K.TORSO_D + 0.04, 0, 0.55, 0.0)));
    if (slots[K.P_FRONT] >= 0) {
      this._place(p, K.P_FRONT, xMul(tor, xScale(0.12, K.TORSO_H * 0.82, 0.02, 0, 0.1 + K.TORSO_H * 0.55, K.TORSO_D * 0.5 + 0.004)));
    }
    if (slots[K.P_APRON] >= 0) {
      const apronLow = p.seated ? 0.12 : 0.38;
      this._place(p, K.P_APRON, xMul(tor, xScale(tw * 0.82, K.TORSO_H * 0.7 + apronLow, 0.025,
        0, 0.1 + K.TORSO_H * 0.35 - apronLow * 0.5, K.TORSO_D * 0.5 + 0.012)));
    }
    if (slots[K.P_BAG] >= 0) this._place(p, K.P_BAG, xMul(tor, xScale(0.08, 0.26, 0.24, tw * 0.5 + 0.06, 0.06, 0.02)));
    // arms
    const fwd = V(tor[6], tor[7], tor[8]);
    for (let k = 0; k < 2; k++) {
      const sg = k === 0 ? -1.0 : 1.0;
      const sh = xPointc(tor, sg * (tw * 0.5 + 0.045), K.SHOULDER_Y, 0.0);
      if (po.armIk[k]) ik(sh, po.arm[k], K.UARM, K.FARM + 0.04, po.pole[k], JA, JB);
      else fk(sh, tor, po.arm[k], sg, K.UARM, K.FARM + 0.04, false, JA, JB);
      const loAxis = vsub(JA, JB);
      const loDir = vnorm(loAxis);
      this._place(p, K.P_UARM0 + k, xOf(along(vsub(sh, JA), fwd, 0.115, K.UARM + 0.04, 0.12), vmul(vadd(sh, JA), 0.5)));
      const wrist = vsub(JA, vmul(loDir, K.FARM));
      this._place(p, K.P_FARM0 + k, xOf(along(loAxis, fwd, 0.098, K.FARM + 0.03, 0.1), vmul(vadd(JA, wrist), 0.5)));
      set3(HANDS[k], vsub(wrist, vmul(loDir, 0.05)));
      this._place(p, K.P_HAND0 + k, xOf(along(loAxis, fwd, 0.085, 0.1, 0.075), HANDS[k]));
    }
    // legs (a static person's resting legs only when they appear; riders' move with their gondola)
    const still = p.legsStill && p.kind === K.K_STATIC;
    if (p.seated) {
      // the lap rig is written every update (crossing the legs moves the shins)
      const hipY = pel[10];
      const shinLen = clampf(hipY - 0.06 - K.SHOE_H - po.ground, 0.18, K.SHIN);
      const ky = hipY - 0.05;
      const c = po.cross;
      const sb = bMul(rotZ(0.22 * c), rotX(-0.12 * Math.abs(c)));
      const shinC = V(0.05 * c, ky - shinLen * 0.5 + 0.03 * Math.abs(c), 0.38 + 0.03 * Math.abs(c));
      this._place(p, K.P_LAP, xScale(0.35, 0.2, 0.5, 0, hipY + 0.02 * Math.abs(c), 0.15));
      this._place(p, K.P_SHINS, xOf(bScaled(sb, 0.3, shinLen, 0.12), shinC));
      this._place(p, K.P_SHOES, xOf(bScaled(sb, 0.34, K.SHOE_H, 0.24), vadd(shinC, bXformc(sb, 0, -shinLen * 0.5 - K.SHOE_H * 0.5, 0.05))));
    } else if (full || !still) {
      this._place(p, K.P_PELVIS, xOf(bScaled(pel, female ? 0.35 : 0.34, 0.18, 0.23), xPointc(pel, 0, 0.05, 0)));
      if (slots[K.P_SKIRT] >= 0) this._place(p, K.P_SKIRT, xOf(pel, xPointc(pel, 0, 0.12, 0)));
      const footB = rotY(po.yaw);
      for (let k = 0; k < 2; k++) {
        const hj = LEGS[k][0];
        const kn = LEGS[k][1];
        const an = LEGS[k][2];
        this._place(p, K.P_THIGH0 + k, xOf(along(vsub(hj, kn), fwd, 0.155, K.THIGH + 0.03, 0.16), vmul(vadd(hj, kn), 0.5)));
        this._place(p, K.P_SHIN0 + k, xOf(along(vsub(kn, an), fwd, 0.13, K.SHIN, 0.135), vmul(vadd(kn, an), 0.5)));
        this._place(p, K.P_SHOE0 + k, xOf(bScaled(footB, 0.13, K.SHOE_H, 0.25), vadd(an, bXformc(footB, 0, -K.SHOE_H * 0.5, 0.05))));
      }
    }
    // held and placed things (held ones stay upright, facing the way the body faces)
    const upright = rotY(po.yaw + po.twist);
    for (let k = 0; k < 2; k++) {
      const on = po.propOn[k];
      const part = K.P_PROP_A + k;
      const sl = slots[part];
      if (sl < 0) continue;
      if (on < 0) this._putZero(sl);
      else if (on === 2 && po.propHome[k]) this._putMul(sl, p.homeWorld, po.propXf[k]);
      else if (on === 2) this._place(p, part, po.propXf[k]);
      else this._place(p, part, xMul(xOf(upright, HANDS[on]), po.propXf[k]));
    }
    // the umbrella in its hand, opening (wider) and folding (narrower), gone when put away
    const us = slots[K.P_UMBRELLA];
    if (us >= 0) {
      if (po.umb <= 0.0) {
        this._putZero(us);
      } else {
        const fo = smooth(po.umb / 0.15);
        const rs = (0.18 + 0.82 * smooth(po.umb)) * fo;
        this._place(p, K.P_UMBRELLA, xOf(bScaled(upright, rs, fo, rs), vaddc(HANDS[po.umbHand], 0, -0.02, 0)));
      }
    }
  }

  /** The phase (0..1) of a person's main action cycle at time t (the tests check nobody is in sync). */
  phaseOf(p, t) {
    if (p.kind === this.K.K_WALKER) return walkerPose(p.index, t, WP).phase;
    return fposmod(p.tau(t) / period(p.action), 1.0);
  }

  // ===================================================================== rain (city r3)
  //
  // Each person who reacts has a phase record `rec`, made when the shared weather changes (_begin) from where
  // the person is at that moment under the previous record (so a change mid-way never makes anybody jump), and
  // read by _eval(t). A person moves along its `base` path: home end first, cover spot last; s is the distance
  // along it. In the rain s grows (after the person's group delay, unless it was already on the way); when the
  // rain stops it shrinks back. Walkers' paths start where they leave their lane: on the way back they rejoin
  // the lane where the path leaves it and walk a little faster (or slower) until they are in step with their
  // lane clock. Carousel riders get back on when their horse comes round. Umbrella holders only open and fold
  // an umbrella.

  /** Who reacts, their umbrellas, the cover spots, and the fixed spots and paths (static people, carousel riders). */
  _setupWeather() {
    const K = this.K;
    const E = C.extra.people;
    this.spots = E.spots.map((s) => ({ region: String(s.region), x: f(s.pos[0]), y: f(s.pos[1]), h: Number(s.y), cover: String(s.cover), shop: String(s.shop) }));
    for (const p of this.people) {
      switch (p.kind) {
        case K.K_STATIC:
          // Data.is_indoor / Data.under_cover need the navigation's cover spots: who reacts is exported
          p.react = E.react[p.id] !== undefined;
          if (p.react) {
            p.umbrella = p.seated && umbrellaFor(p.id);
            if (p.seated && !p.umbrella) {
              p.seated = false;
              p.legsSeat = true;
            }
          }
          break;
        case K.K_WALKER:
          p.react = true;
          p.umbrella = umbrellaFor(p.id);
          break;
        case K.K_CAROUSEL:
          p.react = true;
          break;
        default: break;
      }
      if (p.react) {
        p.fast = true;
        p.legsStill = false;
        p.umbHand = (p.kind === K.K_WALKER || p.action === 'eat' || p.action === 'read_screen' || p.action === 'phone') ? 1 : 0;
      }
    }
    // the fixed spots: a carousel rider's canopy spot (_assign_carousel), a static person's spot and its route
    // there (_assign_static, CityNav.route), as Godot assigned them at load
    for (const p of this.people) {
      if (!p.react || p.umbrella || p.kind === K.K_WALKER) continue;
      const r = E.react[p.id];
      if (!r) continue;
      p.spot = Math.trunc(r.spot);
      if (p.kind === K.K_STATIC && r.base.length > 0) {
        const n = r.base.length;
        p.base = new Float32Array(n * 3);
        p.baseLen = new Float32Array(n);
        p.baseReg = r.base_reg.map(String);
        p.baseN = n;
        for (let i = 0; i < n; i++) {
          p.base[i * 3] = r.base[i][0];
          p.base[i * 3 + 1] = r.base[i][1];
          p.base[i * 3 + 2] = r.base[i][2];
          p.baseLen[i] = r.base_len[i];
        }
      }
    }
    for (const k of Object.keys(E.held)) this._held.set(Math.trunc(Number(k)), String(E.held[k]));
    // the walkers' ways off their lanes (_exit), once
    for (const ex of E.exits) {
      const leg = new Float32Array(ex.leg.length * 2);
      for (let i = 0; i < ex.leg.length; i++) {
        leg[i * 2] = ex.leg[i][0];
        leg[i * 2 + 1] = ex.leg[i][1];
      }
      this._exits.set(Math.trunc(ex.loop) * 4096 + Math.trunc(ex.spot), { arc: Number(ex.arc), len: Number(ex.len), leg });
    }
  }

  /**
   * The shared weather into this._w: {rain, since, prevRain}. Reads the City states ({weather: int, since,
   * prev: [sunny, rain, night]}) or the rules' shape ({weather: {weather, since, prev}}).
   */
  _weather() {
    const out = this._w;
    out.rain = false;
    out.since = -1.0e9;
    out.prevRain = false;
    let d = this.weatherState;
    if (d === null || typeof d !== 'object' || d.weather === undefined || d.weather === null) return out;
    let w = d.weather;
    if (typeof w === 'object') {
      d = w;
      w = d.weather;
    }
    out.rain = Math.trunc(Number(w)) === Number(C.PeopleData.RAIN);
    const since = d.since !== undefined ? d.since : (d.weather_since !== undefined ? d.weather_since : -1.0e9);
    out.since = Number(since);
    const prev = d.prev !== undefined ? d.prev : (d.weather_prev !== undefined ? d.weather_prev : null);
    let pr = 0.0;
    if (Array.isArray(prev) && prev.length > 1) pr = Number(prev[1]);
    out.prevRain = pr >= 0.5;
    return out;
  }

  /** Forget every weather phase (tests; a new city). */
  resetWeather() {
    this._wkey = '';
    this._wRain = null;
    for (const p of this.people) p.rec = null;
  }

  /**
   * A new city (the child enters it again; Godot makes new people then): no weather memory, no child was on
   * the wheel, nothing cut away.
   */
  newCity() {
    this.resetWeather();
    this._childLap.fill(-999999);
    this.hiddenRegions.clear();
    this._lastT = -Infinity;
  }

  _weatherTick(_t) {
    const w = this._weather();
    const since = w.since;
    // the same weather as last time (the usual frame): the key cannot have changed
    if (w.rain === this._wRain && since === this._wSince && w.prevRain === this._wPrev) return;
    this._wRain = w.rain;
    this._wSince = since;
    this._wPrev = w.prevRain;
    const key = `${w.rain ? 1 : 0}|${since.toFixed(4)}|${w.prevRain ? 1 : 0}`;
    if (key === this._wkey) return;
    this._wkey = key;
    const cur = new Map();
    for (const p of this.people) {
      if (p.react && p.rec !== null) cur.set(p.id, this._eval(p, since, newEval()));
    }
    for (const p of this.people) {
      if (p.react) this._begin(p, w, cur.get(p.id) || null);
    }
    this._assignWalkers();
  }

  /** The arc along its lane of walker `index`'s slot at lane time lam. */
  _slotArc(index, lam) {
    const w = walkerPose(index, lam, WP);
    return polyProject(walkLoops()[loopIndex(index)], w.x, w.z, PRJ).arc;
  }

  _lanePhase(index, lam) { return walkerPose(index, lam, WP).phase; }

  _plen(p) { return p.baseN > 0 ? p.baseLen[p.baseN - 1] : 0.0; }

  /** A new weather phase for one person, from its state `cur` at the change (null: no memory). */
  _begin(p, w, cur) {
    const K = this.K;
    const rain = w.rain;
    const since = w.since;
    const has = cur !== null;
    const spread = rain ? Number(C.CityMap.RAIN_COVER_SPREAD) : Number(C.CityMap.RAIN_RETURN_SPREAD);
    const rec = { rain, since };
    if (p.umbrella) {
      const a0 = has ? cur.umb : (!rain && w.prevRain ? 1.0 : 0.0);
      const rest = rain ? a0 <= 0.0 : a0 >= 1.0;
      rec.a0 = a0;
      rec.start = since + (rest ? this._groupDelay(p, since, cur, spread) : 0.0);
      p.rec = rec;
      return;
    }
    const assumed = !has && !rain && w.prevRain;
    let s0 = has ? cur.s : 0.0;
    rec.w0 = has ? cur.walked : 0.0;
    if (p.kind === K.K_WALKER) {
      const onLane = !has || cur.onLane;
      const g0 = has && onLane ? cur.lam - since : 0.0;
      rec.g0 = g0;
      rec.pd0 = has ? cur.pd : 0.0;
      rec.ph0 = has ? cur.ph : -1.0;
      if ((rain && onLane) || assumed) {
        // leaves its lane after its group's delay (at once when it was on its way back; assumed: it left
        // when the rain began, long ago)
        const moving = has && cur.moving;
        const td = assumed || moving ? since : since + this._groupDelay(p, since, cur, spread);
        rec.depart = true;
        rec.td = td;
        rec.lam_d = td + g0;
        rec.assumed = assumed;
        rec.s0 = 0.0;
        rec.start = td;
        p.rec = rec;
        return;
      }
      rec.s0 = !onLane ? s0 : 0.0;
    } else if (p.kind === K.K_CAROUSEL) {
      if ((rain && s0 <= 0.0) || assumed) {
        const td2 = assumed ? since : since + this._groupDelay(p, since, cur, spread);
        p.lamD = td2;
        this._carouselPath(p, td2);
        s0 = assumed ? this._plen(p) : 0.0;
        rec.start = td2;
      }
      rec.s0 = s0;
    } else {
      if (assumed) s0 = this._plen(p);
      rec.s0 = s0;
    }
    p.rec = rec;
    this._timing(p);
  }

  /** Data.group_delay at the person's place (_pos2). */
  _groupDelay(p, t, cur, spread) {
    this._pos2(p, t, cur);
    return groupDelay(p.sd, P2.x, P2.y, spread);
  }

  /**
   * The start time of a record whose path is known, and for a walker going back to its lane, how it meets its
   * slot again: from where it steps back onto the lane (or where it is on it), it walks along the lane toward
   * its slot (or waits under cover until the slot comes by, when that is about as quick), so that it is in step
   * again exactly; then it simply walks on.
   */
  _timing(p) {
    const K = this.K;
    const D = C.PeopleData;
    const rec = p.rec;
    const since = rec.since;
    const s0 = rec.s0;
    const big = this._plen(p);
    const rain = rec.rain;
    if (rain) {
      if (rec.start === undefined) {
        rec.start = since + (s0 <= 0.0 ? this._groupDelay(p, since, null, Number(C.CityMap.RAIN_COVER_SPREAD)) : 0.0);
      }
      return;
    }
    let start = since;
    const atSpot = s0 > 0.0 && s0 >= big - 1e-4;
    if (atSpot) start += this._groupDelay(p, since, null, Number(C.CityMap.RAIN_RETURN_SPREAD));
    rec.start = start;
    if (p.kind === K.K_CAROUSEL && s0 > 0.0) {
      // back on when the horse comes round to where the rider got off
      const per = Number(C.CityMap.CAROUSEL.period);
      const earliest = start + s0 / D.RETURN_SPEED;
      const k = Math.ceil((earliest - p.lamD) / per - 1e-9);
      rec.start = p.lamD + k * per - s0 / D.RETURN_SPEED;
      return;
    }
    if (p.kind !== K.K_WALKER) return;
    const loop = walkLoops()[loopIndex(p.index)];
    const total = loop.length;
    const v = loop.speed;
    const vr = D.LANE_RETURN_SPEED;
    let tR = since;
    let aR = 0.0;
    let phR = 0.0;
    let wR = rec.w0;
    if (s0 > 0.0) {
      const flo = Math.min(s0, p.laneE);
      tR = start + (s0 - flo) / D.RETURN_SPEED;
      aR = fposmod(this._slotArc(p.index, p.lamD) + p.laneDir * flo, total);
      wR += s0 - flo;
      phR = p.phD + wR / PP.STRIDE;
      rec.floor = flo;
    } else {
      const lam0 = since + rec.g0;
      aR = this._slotArc(p.index, lam0);
      const ph0 = rec.ph0;
      phR = ph0 >= 0.0 ? ph0 : this._lanePhase(p.index, lam0) + rec.pd0;
      rec.floor = 0.0;
    }
    // the slot is behind it by `ahead` metres along the lane (or ahead of it by total - ahead)
    const ahead = fposmod(aR - this._slotArc(p.index, tR), total);
    let gR = 0.0;
    let rate = 0.0;
    if (ahead > 0.05 && ahead < total - 0.05) {
      const tBack = ahead / (vr + v);                                  // walk back to meet it
      const tFwd = vr > v ? (total - ahead) / (vr - v) : Infinity;     // or catch it up
      const tWait = ahead / v;                                         // or wait for it to come by
      if (atSpot && tWait <= Math.min(tBack, tFwd) + 8.0) {
        rec.start = start + tWait;
        tR += tWait;
      } else if (tBack <= tFwd) {
        gR = ahead / v;
        rate = -(vr + v) / v;
      } else {
        gR = -(total - ahead) / v;
        rate = (vr - v) / v;
      }
    }
    const tMeet = tR + (rate !== 0.0 ? Math.abs(gR / rate) : 0.0);
    rec.t_r = tR;
    rec.g_r = gR;
    rec.rate = rate;
    rec.t_meet = tMeet;
    rec.ph_r = phR;
    rec.w_r = wR;
    const laneWalk = vr * (tMeet - tR);
    rec.pdb = wrapf(phR + laneWalk / PP.STRIDE - this._lanePhase(p.index, tMeet), -0.5, 0.5);
  }

  /** Where a person is for its group (the square of ground it starts from), into P2. */
  _pos2(p, t, cur) {
    const K = this.K;
    if (p.kind === K.K_WALKER) {
      const lam = cur !== null && cur.onLane ? cur.lam : t;
      const w = walkerPose(p.index, lam, WP);
      P2.x = w.x;
      P2.y = w.z;
    } else if (p.kind === K.K_CAROUSEL) {
      P2.x = f(C.CityMap.CAROUSEL.center[0]);
      P2.y = f(C.CityMap.CAROUSEL.center[1]);
    } else {
      P2.x = p.root[9];
      P2.y = p.root[11];
    }
    return P2;
  }

  /**
   * The state at time t under the current record, into out: {s, onLane, lam, walked, pd, umb, ph (a walker's
   * stride phase), moving (a walker on its lane walking to meet its slot), back (that walk is against the lane)}.
   */
  _eval(p, t, out) {
    const K = this.K;
    const D = C.PeopleData;
    const rec = p.rec;
    out.s = 0.0; out.onLane = true; out.lam = t; out.walked = 0.0; out.pd = 0.0; out.umb = 0.0; out.ph = -1.0;
    out.moving = false; out.back = false;
    const walker = p.kind === K.K_WALKER;
    if (walker) out.ph = this._lanePhase(p.index, t);
    if (rec === null) return out;
    const rain = rec.rain;
    const since = rec.since;
    const start = rec.start !== undefined ? rec.start : since;
    if (p.umbrella) {
      const a0 = rec.a0;
      const da = Math.max(0.0, t - start) / D.UMBRELLA_TIME;
      out.umb = rain ? Math.min(1.0, a0 + da) : Math.max(0.0, a0 - da);
      return out;
    }
    const s0 = rec.s0;
    const big = this._plen(p);
    const w0 = rec.w0;
    if (!walker) {
      const sv = rain ? Math.min(big, s0 + Math.max(0.0, t - start) * D.HURRY_SPEED) : Math.max(0.0, s0 - Math.max(0.0, t - start) * D.RETURN_SPEED);
      out.s = sv;
      out.onLane = sv <= 0.0;
      out.walked = w0 + Math.abs(sv - s0);
      return out;
    }
    // walkers
    if (rain) {
      if ((rec.depart === true && t < start) || big <= 0.0) {
        // still in its stride on the lane (a lane time a little off its slot keeps its place)
        const lam = t + rec.g0;
        out.lam = lam;
        out.pd = rec.pd0 * (1.0 - smooth((t - since) / 1.0));
        out.ph = fposmod(this._lanePhase(p.index, lam) + out.pd, 1.0);
        return out;
      }
      const sv2 = Math.min(big, s0 + Math.max(0.0, t - start) * D.HURRY_SPEED);
      out.s = sv2;
      out.onLane = false;
      out.lam = p.lamD;
      out.walked = w0 + Math.abs(sv2 - s0);
      out.ph = fposmod(p.phD + out.walked / PP.STRIDE, 1.0);
      return out;
    }
    const tR = rec.t_r;
    if (s0 > 0.0 && t < tR) {
      const sv3 = Math.max(rec.floor, s0 - Math.max(0.0, t - start) * D.RETURN_SPEED);
      out.s = sv3;
      out.onLane = false;
      out.lam = p.lamD;
      out.walked = w0 + Math.abs(sv3 - s0);
      out.ph = fposmod(p.phD + out.walked / PP.STRIDE, 1.0);
      return out;
    }
    const tMeet = rec.t_meet;
    if (t < tMeet) {
      const rate = rec.rate;
      const dt = Math.max(0.0, t - tR);
      out.lam = t + rec.g_r + rate * dt;
      out.moving = true;
      out.back = rate < -1.0;
      out.walked = rec.w_r + D.LANE_RETURN_SPEED * dt;
      out.ph = fposmod(rec.ph_r + D.LANE_RETURN_SPEED * dt / PP.STRIDE, 1.0);
      return out;
    }
    out.lam = t;
    out.pd = rec.pdb * (1.0 - smooth((t - tMeet) / 1.0));
    out.ph = fposmod(this._lanePhase(p.index, t) + out.pd, 1.0);
    return out;
  }

  /** Free cover spots for the walkers leaving their lanes in this phase, in the order they leave. */
  _assignWalkers() {
    const K = this.K;
    const held = new Map(this._held);
    const leaving = [];
    for (const p of this.people) {
      if (p.kind !== K.K_WALKER || !p.react || p.umbrella || p.rec === null) continue;
      if (p.rec.depart === true) leaving.push(p);
      else if (p.rec.s0 > 0.0 && p.spot >= 0) held.set(p.spot, p.id);
    }
    leaving.sort((a, b) => {
      const ta = a.rec.td;
      const tb = b.rec.td;
      if (ta < tb || (ta === tb && a.index < b.index)) return -1;
      if (tb < ta || (ta === tb && b.index < a.index)) return 1;
      return 0;
    });
    const loops = walkLoops();
    for (const p of leaving) {
      const rec = p.rec;
      const lamD = rec.lam_d;
      const li = loopIndex(p.index);
      const loop = loops[li];
      const total = loop.length;
      const w = walkerPose(p.index, lamD, WP);
      const dx = w.x;
      const dy = w.z;
      const aD = polyProject(loop, dx, dy, PRJ).arc;
      let best = -1;
      let bestCost = Infinity;
      let bestDir = 1.0;
      let bestDl = 0.0;
      for (let j = 0; j < this.spots.length; j++) {
        if (held.has(j) || this.spots[j].region !== 'ground') continue;
        const ex = this._exits.get(li * 4096 + j);
        if (ex === undefined) continue;
        const fwd = fposmod(ex.arc - aD, total);
        const dir = fwd <= total - fwd ? 1.0 : -1.0;
        const dl = dir > 0.0 ? fwd : total - fwd;
        const cost = dl + ex.len;
        if (cost < bestCost - 1e-9) {
          bestCost = cost;
          best = j;
          bestDir = dir;
          bestDl = dl;
        }
      }
      p.base = new Float32Array(0);
      p.baseReg = [];
      p.baseLen = new Float32Array(0);
      p.baseN = 0;
      p.spot = best;
      if (best < 0) continue;
      held.set(best, p.id);
      const ex2 = this._exits.get(li * 4096 + best);
      const pts3 = [[dx, dy]];
      // the lane part: along the loop through its corners
      for (let i = 0; i < loop.n; i++) {
        const rel = fposmod((loop.corner[i] - aD) * bestDir, total);
        if (rel > 1e-4 && rel < bestDl - 1e-4) pts3.push([loop.xs[i], loop.ys[i]]);
      }
      for (const q of pts3) q.push(fposmod((polyProject(loop, q[0], q[1], PRJ).arc - aD) * bestDir, total));
      pts3.sort((a, b) => (a[2] < b[2] ? -1 : (b[2] < a[2] ? 1 : 0)));
      for (let i = 0; i < ex2.leg.length; i += 2) pts3.push([ex2.leg[i], ex2.leg[i + 1]]);
      this._setPath(p, pts3);
      p.laneE = bestDl;
      p.lamD = lamD;
      p.laneDir = bestDir;
      p.laneSpeed = loop.speed;
      const ph0 = rec.ph0 !== undefined ? rec.ph0 : -1.0;
      p.phD = ph0 >= 0.0 && rec.td <= rec.since + 1e-6 ? ph0 : this._lanePhase(p.index, lamD) + (rec.pd0 !== undefined ? rec.pd0 : 0.0);
      rec.s0 = rec.assumed === true ? this._plen(p) : 0.0;
      if (rec.assumed === true) {
        rec.depart = false;
        rec.start = rec.since;
        rec.w0 = this._plen(p);
        this._timing(p);
      }
    }
  }

  /** Sets a person's path from ground points (y 0), [[x, z], ...]. */
  _setPath(p, pts) {
    const base = [];
    const lens = [];
    let acc = 0.0;
    for (let i = 0; i < pts.length; i++) {
      const qx = f(pts[i][0]);
      const qz = f(pts[i][1]);
      if (i > 0) {
        const n = base.length;
        const d = dist3(qx, 0, qz, base[n - 3], base[n - 2], base[n - 1]);
        if (d < 1e-4) continue;
        acc += d;
      }
      base.push(qx, 0, qz);
      lens.push(acc);
    }
    p.base = Float32Array.from(base);
    p.baseLen = Float32Array.from(lens);
    p.baseN = lens.length;
    p.baseReg = lens.map(() => 'ground');
  }

  /** A carousel rider's way off: from the saddle down to the deck, round the deck to the fence gap, out, to its spot. */
  _carouselPath(p, td) {
    if (p.spot < 0) return;
    const cx = f(C.CityMap.CAROUSEL.center[0]);
    const cy = f(C.CityMap.CAROUSEL.center[1]);
    const seat = carouselSeatTransform(p.index, td);
    const sx = seat[9];
    const sy = seat[10];
    const sz = seat[11];
    const aSeat = Math.atan2(-(sz - cy), sx - cx);
    const gx = this._gap[0];
    const gy = this._gap[1];
    const aGap = Math.atan2(-gy, gx);
    const da = wrapf(aGap - aSeat, -Math.PI, Math.PI);
    const pts = [sx, sy, sz];
    const deck = 0.3;
    const steps = Math.max(1, Math.ceil(Math.abs(da) / 0.5));
    for (let i = 0; i <= steps; i++) {
      const a = aSeat + da * i / steps;
      pts.push(f(cx + Math.cos(a) * 2.15), f(deck), f(cy - Math.sin(a) * 2.15));
    }
    pts.push(f(cx + gx * 2.6), f(0.13), f(cy + gy * 2.6));
    pts.push(f(cx + gx * 3.35), 0.0, f(cy + gy * 3.35));
    const q = this.spots[p.spot];
    pts.push(q.x, 0.0, q.y);
    const n = pts.length / 3;
    p.base = Float32Array.from(pts);
    p.baseLen = new Float32Array(n);
    p.baseReg = [];
    p.baseN = n;
    let acc = 0.0;
    for (let i = 0; i < n; i++) {
      if (i > 0) acc += dist3(pts[i * 3], pts[i * 3 + 1], pts[i * 3 + 2], pts[i * 3 - 3], pts[i * 3 - 2], pts[i * 3 - 1]);
      p.baseLen[i] = acc;
      p.baseReg.push('ground');
    }
  }

  /** A point on a person's path, into AT: pos, the unit direction (dx, dy) forward along the path, region. */
  _pathAt(p, s) {
    const n = p.baseN;
    const out = AT;
    if (n === 0) {
      out.pos[0] = p.root[9]; out.pos[1] = p.root[10]; out.pos[2] = p.root[11];
      out.dx = 0; out.dy = 1; out.region = p.region;
      return out;
    }
    const base = p.base;
    if (n === 1) {
      out.pos[0] = base[0]; out.pos[1] = base[1]; out.pos[2] = base[2];
      out.dx = 0; out.dy = 1; out.region = p.baseReg[0];
      return out;
    }
    const lens = p.baseLen;
    let i = 1;
    while (i < n - 1 && lens[i] < s) i += 1;
    const a = (i - 1) * 3;
    const b = i * 3;
    const seg = lens[i] - lens[i - 1];
    const u = seg > 1e-6 ? clampf((s - lens[i - 1]) / seg, 0.0, 1.0) : 1.0;
    let dx = f(base[b] - base[a]);
    let dy = f(base[b + 2] - base[a + 2]);
    const l2 = f(f(dx * dx) + f(dy * dy));
    if (f(Math.sqrt(l2)) < 1e-4) {
      dx = 0;
      dy = 1;
    } else if (l2 !== 0) {
      const l = f(Math.sqrt(l2));
      dx = f(dx / l);
      dy = f(dy / l);
    }
    const k = f(u);
    out.pos[0] = base[a] + f(f(base[b] - base[a]) * k);
    out.pos[1] = base[a + 1] + f(f(base[b + 1] - base[a + 1]) * k);
    out.pos[2] = base[a + 2] + f(f(base[b + 2] - base[a + 2]) * k);
    out.dx = dx;
    out.dy = dy;
    out.region = p.baseReg[i];
    return out;
  }

  /** The way a person faces at its cover spot: back out the way it came (watching the rain). */
  _spotRy(p) {
    const n = p.baseN;
    if (n < 2) return 0.0;
    const a = (n - 2) * 3;
    const b = (n - 1) * 3;
    return Math.atan2(f(p.base[a] - p.base[b]), f(p.base[a + 2] - p.base[b + 2]));
  }

  /** Where a person's activity is (no scale): its place, its lane point, its horse. A pooled transform or p.root. */
  _homeRoot(p, t, e) {
    const K = this.K;
    if (p.kind === K.K_WALKER) {
      const w = walkerPose(p.index, e.lam, WP);
      return xOf(rotY(w.ry), V(w.x, 0.0, w.z));
    }
    if (p.kind === K.K_CAROUSEL) return carouselSeatTransform(p.index, t);
    return p.root;
  }

  _updateReact(p, t, force) {
    const K = this.K;
    const e = this._eval(p, t, this._ev);
    const s = e.s;
    const away = s > 0.0;
    const at = away ? this._pathAt(p, s) : null;
    const region = away ? at.region : p.region;
    if (p.kind === K.K_STATIC && this.hiddenRegions.has(region)) {
      this._hide(p, force);
      return;
    }
    const full = force || !p.shown;
    const sc = p.s;
    let home = this._homeRoot(p, t, e);
    setX(p.homeWorld, bScaled(home, sc, sc, sc));
    p.homeWorld[9] = home[9]; p.homeWorld[10] = home[10]; p.homeWorld[11] = home[11];
    setX(p.world, p.homeWorld);
    const po = p.pose;
    po.reset();
    let root = home;
    const female = p.look.sex === 'f';
    if (p.kind === K.K_WALKER) {
      p.wphase = e.ph;
      if (e.back) {
        // walking back along its lane to meet its slot: it faces the way it walks
        const turned = bMul(rotY(Math.PI), home);
        turned[9] = home[9]; turned[10] = home[10]; turned[11] = home[11];
        home = turned;
        setX(p.homeWorld, bScaled(home, sc, sc, sc));
        p.homeWorld[9] = home[9]; p.homeWorld[10] = home[10]; p.homeWorld[11] = home[11];
      }
    }
    if (!away) {
      poseOf(p, t, po);
    } else {
      const big = this._plen(p);
      const rain = p.rec.rain;
      const walk = this._tmpA;
      walk.reset();
      const ph = p.kind === K.K_WALKER ? e.ph : hash01(p.sd, 5) + e.walked / PP.STRIDE;
      walkCycle(walk, fposmod(ph, 1.0), rain);
      const ks = smooth((big - s) / PP.BLEND_M);
      if (ks < 1.0) {
        const idle = this._tmpB;
        idle.reset();
        coverIdle(p, p.tau(t), idle);
        mix(walk, idle, 1.0 - ks, female);
      }
      const kh = smooth(s / (PP.BLEND_M * (p.kind === K.K_CAROUSEL ? 2.0 : 1.0)));
      if (p.kind === K.K_WALKER) p.wphase = fposmod(ph, 1.0);
      poseOf(p, t, po);
      mix(po, walk, kh, female);
      const pos = vlerp(V(home[9], home[10], home[11]), at.pos, kh);
      let dx = at.dx;
      let dy = at.dy;
      if (!rain) {
        dx = -dx;
        dy = -dy;
      }
      let ry = Math.atan2(dx, dy);
      if (ks < 1.0) ry = lerpAngle(this._spotRy(p), ry, ks);
      ry = lerpAngle(Math.atan2(home[6], home[8]), ry, kh);
      root = xOf(rotY(ry), pos);
    }
    if (p.umbrella) {
      po.umb = e.umb;
      po.umbHand = p.umbHand;
      umbrellaArm(po, female);
    }
    const wb = bScaled(root, sc, sc, sc);
    wb[9] = root[9]; wb[10] = root[10]; wb[11] = root[11];
    setX(p.world, wb);
    this._draw(p, po, full);
    p.shown = true;
  }
}

/** Vector3.distance_to on plain numbers (single precision). */
function dist3(ax, ay, az, bx, by, bz) {
  const x = f(ax - bx);
  const y = f(ay - by);
  const z = f(az - bz);
  return f(Math.sqrt(f(f(f(x * x) + f(y * y)) + f(z * z))));
}

