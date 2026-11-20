// The people's poses, ported function by function from art/city_people.gd (the Pose class, the kinematics and
// the "animation" section: every pose is a pure function of the time, of the person's own clock and of its
// place). people_core.js draws them. The order of the arithmetic follows the GDScript line by line; vectors
// are single precision as Godot's are (people_math.js). Nothing here allocates per call.
// No DOM, no Three.js: importable in Node.
import { hash01 } from './people_rules.js';
import {
  f, V, set3, setV, setX, vadd, vaddc, vsub, vmul, vlerp, dot, lenSq, len, cross, vnorm,
  rotX, rotY, rotZ, bMul, bXformc, bCols, bInverse, xOf, xMul, xPointc, xScale,
  TAU, clampf, lerpf, fposmod, lerpAngle,
} from './people_math.js';

// The constants of city_people.gd (consts.json "People"), bound once by bindConsts().
export let P_TORSO, P_HEAD, P_UARM0, P_UARM1, P_FARM0, P_FARM1, P_HAND0, P_HAND1, P_PELVIS, P_THIGH0, P_THIGH1,
  P_SHIN0, P_SHIN1, P_SHOE0, P_SHOE1, P_LAP, P_SHINS, P_SHOES, P_SKIRT, P_APRON, P_FRONT, P_GLASSES, P_BEARD,
  P_BAG, P_SCARF, P_PROP_A, P_PROP_B, P_UMBRELLA, P_HAIR0, P_HAIR1, P_HAIR2, P_COUNT;
export let K_STATIC, K_WALKER, K_FERRIS, K_CAROUSEL;
export let HIP_STAND, TORSO_H, TORSO_D, SHOULDER_Y, NECK_Y, HEAD_C, UARM, FARM, THIGH, SHIN, SHOE_H, HIP_X, SIT_HIP,
  BENCH_Y, SADDLE_UP, SLOW_GROUPS, BLEND_M, STRIDE, BODY_R;

export function bindConsts(K) {
  ({ P_TORSO, P_HEAD, P_UARM0, P_UARM1, P_FARM0, P_FARM1, P_HAND0, P_HAND1, P_PELVIS, P_THIGH0, P_THIGH1,
    P_SHIN0, P_SHIN1, P_SHOE0, P_SHOE1, P_LAP, P_SHINS, P_SHOES, P_SKIRT, P_APRON, P_FRONT, P_GLASSES, P_BEARD,
    P_BAG, P_SCARF, P_PROP_A, P_PROP_B, P_UMBRELLA, P_HAIR0, P_HAIR1, P_HAIR2, P_COUNT,
    K_STATIC, K_WALKER, K_FERRIS, K_CAROUSEL,
    HIP_STAND, TORSO_H, TORSO_D, SHOULDER_Y, NECK_Y, HEAD_C, UARM, FARM, THIGH, SHIN, SHOE_H, HIP_X, SIT_HIP,
    BENCH_Y, SADDLE_UP, SLOW_GROUPS, BLEND_M, STRIDE, BODY_R } = K);
}

export class Pose {
  constructor() {
    this.hip = 0.86;
    this.off = new Float32Array(3);          // pelvis offset (local)
    this.yaw = 0.0;                          // pelvis yaw
    this.sway = 0.0;                         // pelvis roll
    this.lean = 0.0;                         // torso pitch forward
    this.twist = 0.0;                        // torso yaw
    this.side = 0.0;                         // torso roll
    this.head = new Float32Array(3);         // pitch (down +), yaw, roll
    this.armIk = [false, false];
    this.arm = [new Float32Array(3), new Float32Array(3)];     // fk (pitch fwd, roll out, elbow) | ik target
    this.pole = [new Float32Array([0, -1, -0.3]), new Float32Array([0, -1, -0.3])];
    this.legIk = [false, false];
    this.leg = [new Float32Array(3), new Float32Array(3)];     // fk (pitch fwd, roll out, knee) | ik ankle target
    this.plant = false;                      // lift or lower the body so the lower foot stands on the floor
    this.plantK = 1.0;                       // how much of that lift applies
    this.ground = 0.0;                       // that floor's height (local)
    this.cross = 0.0;                        // a seated person's crossed legs (-1..1, the side)
    this.umb = 0.0;                          // the umbrella's opening (0 folded and put away .. 1 open)
    this.umbHand = 1;
    this.propOn = [-1, -1];                  // -1 hidden, 0/1 in that hand, 2 placed (local)
    this.propXf = [new Float32Array([1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0]), new Float32Array([1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0])];
    this.propHome = [false, false];          // placed at the person's home (a cup left on the table)
  }

  reset() {
    this.hip = HIP_STAND;
    setV(this.off, 0, 0, 0);
    this.yaw = 0.0;
    this.sway = 0.0;
    this.lean = 0.0;
    this.twist = 0.0;
    this.side = 0.0;
    setV(this.head, 0, 0, 0);
    this.armIk[0] = false;
    this.armIk[1] = false;
    setV(this.arm[0], 0.0, 0.08, 0.15);
    setV(this.arm[1], 0.0, 0.08, 0.15);
    setV(this.pole[0], -0.4, -1.0, -0.5);
    setV(this.pole[1], 0.4, -1.0, -0.5);
    this.legIk[0] = false;
    this.legIk[1] = false;
    setV(this.leg[0], 0, 0, 0);
    setV(this.leg[1], 0, 0, 0);
    this.plant = false;
    this.plantK = 1.0;
    this.ground = 0.0;
    this.cross = 0.0;
    this.umb = 0.0;
    this.propOn[0] = -1;
    this.propOn[1] = -1;
    this.propHome[0] = false;
    this.propHome[1] = false;
  }

  copyFrom(o) {
    this.hip = o.hip;
    set3(this.off, o.off);
    this.yaw = o.yaw;
    this.sway = o.sway;
    this.lean = o.lean;
    this.twist = o.twist;
    this.side = o.side;
    set3(this.head, o.head);
    for (let k = 0; k < 2; k++) {
      this.armIk[k] = o.armIk[k];
      set3(this.arm[k], o.arm[k]);
      set3(this.pole[k], o.pole[k]);
      this.legIk[k] = o.legIk[k];
      set3(this.leg[k], o.leg[k]);
      this.propOn[k] = o.propOn[k];
      setX(this.propXf[k], o.propXf[k]);
      this.propHome[k] = o.propHome[k];
    }
    this.plant = o.plant;
    this.plantK = o.plantK;
    this.ground = o.ground;
    this.cross = o.cross;
    this.umb = o.umb;
    this.umbHand = o.umbHand;
  }
}

// ===================================================================== kinematics

/** A basis whose y axis runs along `axis` (any length), x and z across it, scaled to (sx, sy, sz). */
export function along(axis, hint, sx, sy, sz) {
  const y = vnorm(axis);
  let x = cross(hint, y);
  if (lenSq(x) < 1e-6) {
    x = Math.abs(y[0]) < 0.9 ? cross(V(1, 0, 0), y) : cross(V(0, 0, 1), y);
  }
  x = vnorm(x);
  const z = vnorm(cross(x, y));
  return bCols(vmul(x, sx), vmul(y, sy), vmul(z, sz));
}

/**
 * Two-bone IK: from joint a toward target, bone lengths l1, l2, the middle joint bending toward `pole`.
 * Writes the middle joint and the end point.
 */
export function ik(a, target, l1, l2, pole, outMid, outEnd) {
  const d = vsub(target, a);
  const dl = len(d);
  const dst = clampf(dl, 0.02, l1 + l2 - 0.0005);
  const dir = dl > 1e-5 ? vnorm(d) : V(0, -1, 0);
  const cosA = clampf((l1 * l1 + dst * dst - l2 * l2) / (2.0 * l1 * dst), -1.0, 1.0);
  const sinA = Math.sqrt(1.0 - cosA * cosA);
  let p = vsub(pole, vmul(dir, dot(pole, dir)));
  if (lenSq(p) < 1e-8) p = vsub(V(0, 0, 1), vmul(dir, dir[2]));
  p = vnorm(p);
  const mid = vadd(a, vmul(vadd(vmul(dir, cosA), vmul(p, sinA)), l1));
  const end = vadd(a, vmul(dir, dst));
  set3(outMid, mid);
  set3(outEnd, end);
}

/**
 * Forward kinematics of a limb hanging down: (pitch forward, roll out, bend) on side sign sg.
 * Writes the middle joint and the end point; `bendBack` bends the lower bone backward (a knee), not forward.
 */
export function fk(a, base, ang, sg, l1, l2, bendBack, outMid, outEnd) {
  const r1 = bMul(bMul(base, rotZ(sg * ang[1])), rotX(-ang[0]));
  const mid = vadd(a, bXformc(r1, 0, -l1, 0));
  const r2 = bMul(r1, rotX(bendBack ? ang[2] : -ang[2]));
  const end = vadd(mid, bXformc(r2, 0, -l2, 0));
  set3(outMid, mid);
  set3(outEnd, end);
}

/** The pelvis, torso and head frames (person-local) for a pose, into fr[0..2] (caller-owned transforms). */
export function frames(po, fr) {
  const pel = xOf(bMul(rotY(po.yaw), rotZ(po.sway)), vaddc(po.off, 0, po.hip, 0));
  const tor = xMul(pel, bMul(bMul(rotY(po.twist), rotZ(po.side)), rotX(po.lean)));
  const hb = bMul(bMul(rotY(po.head[1]), rotX(po.head[0])), rotZ(po.head[2]));
  hb[9] = 0; hb[10] = NECK_Y; hb[11] = 0;
  const head = xMul(tor, hb);
  setX(fr[0], pel);
  setX(fr[1], tor);
  setX(fr[2], head);
  return fr;
}

const FR = [new Float32Array(12), new Float32Array(12), new Float32Array(12)];
const J0 = new Float32Array(3);
const J1 = new Float32Array(3);

/** frames(po)[2] * Vector3(x, y, z). */
function headPt(po, x, y, z) { return xPointc(frames(po, FR)[2], x, y, z); }

/** frames(po)[1] * Vector3(x, y, z). */
function torPt(po, x, y, z) { return xPointc(frames(po, FR)[1], x, y, z); }

/** The mouth (person-local) for a pose whose head is already set. */
export function mouth(po) { return headPt(po, 0, HEAD_C - 0.085, 0.2); }

// ===================================================================== animation

export function smooth(x) {
  const u = clampf(x, 0.0, 1.0);
  return u * u * (3.0 - 2.0 * u);
}

/** An eased bump over u in [0, 1]: rises over `a`, holds, falls over `b` (0 outside). */
export function bump(u, a, b) {
  if (u <= 0.0 || u >= 1.0) return 0.0;
  return Math.min(smooth(u / a), smooth((1.0 - u) / b));
}

/**
 * The idle event at personal time tau: a pooled [envelope 0..1, u 0..1 inside it (-1 outside), kind 0..1].
 * One event of `dur` seconds in every slot of the person's own length (4 to 9 s), at a varied place in it.
 */
export function event(p, tau, dur, salt) {
  const k = Math.floor(tau / p.slot);
  const sd = p.sd + salt;
  const start = k * p.slot + hash01(sd, k) * Math.max(0.0, p.slot - dur);
  const u = (tau - start) / dur;
  if (u < 0.0 || u > 1.0) return V(0.0, -1.0, hash01(sd + 1, k));
  return V(bump(u, 0.25, 0.25), u, hash01(sd + 1, k));
}

export function period(action) {
  switch (action) {
    case 'run': return 0.72;
    case 'cycle': return 0.8;
    case 'row': return 3.0;
    case 'stretch': return 18.0;
    case 'lift': return 2.6;
    case 'wipe_counter': return 1.3;
    case 'cook': return 1.7;
    case 'type': return 0.28;
    case 'wait_tables': return 14.0;
    default: return 4.0;
  }
}

/** Poses person p at time t into po (city_people.gd _pose). */
export function pose(p, t, po) {
  const tau = p.tau(t);
  const inv = 1.0 / p.s;
  const act = p.action;
  if (p.seated || p.legsSeat || act === 'cycle' || act === 'row' || p.kind === K_CAROUSEL) {
    po.hip = p.seat * inv + SIT_HIP;
  }
  // breathing for everybody
  po.off[1] += 0.006 * Math.sin(tau * TAU / 3.7);
  switch (act) {
    case 'walk': walk(p, t, po); break;
    case 'type': case 'read_screen': case 'phone': case 'eat': case 'chat': case 'drink':
      seated(p, t, tau, po, inv);
      posture(p, tau, po);
      break;
    case 'sit_ride': ride(p, tau, po); break;
    case 'cook': cook(p, tau, po, inv); break;
    case 'wait_tables': waiter(p, tau, po); break;
    case 'serve_counter': case 'wipe_counter': staff(p, tau, po, inv); break;
    case 'browse': case 'carry_bag': customer(p, tau, po, inv); break;
    case 'run': run(p, tau, po); break;
    case 'cycle': cycle(p, tau, po, inv); break;
    case 'row': row(p, tau, po, inv); break;
    case 'stretch': stretch(p, tau, po); break;
    case 'lift': lift(p, tau, po); break;
    default: break;
  }
}

/** Arms hanging relaxed, legs straight, feet on the floor. */
function stand(po) {
  po.plant = true;
  setV(po.leg[0], 0.0, 0.03, 0.04);
  setV(po.leg[1], 0.0, 0.03, 0.04);
}

function ikArm(po, k, target, pole) {
  po.armIk[k] = true;
  set3(po.arm[k], target);
  set3(po.pole[k], pole);
}

function setProp(po, k, sx, sy, sz, ox, oy, oz) {
  const x = po.propXf[k];
  x[0] = sx; x[1] = 0; x[2] = 0;
  x[3] = 0; x[4] = sy; x[5] = 0;
  x[6] = 0; x[7] = 0; x[8] = sz;
  x[9] = ox; x[10] = oy; x[11] = oz;
}

function walk(p, t, po) {
  walkCycle(po, p.wphase, false);
  const ev = event(p, p.tau(t), 2.4, 11);
  po.head[1] += ev[0] * (ev[2] < 0.5 ? 0.55 : -0.55);
  po.head[0] = 0.04 - ev[0] * 0.05;
}

/**
 * A walk cycle at a stride phase (0..1): legs swing and bend, each arm swings against the leg on its side,
 * the body bobs (the lower foot stays on the floor) and counter-turns. `hurry`: longer strides, more swing.
 */
export function walkCycle(po, phase01, hurry) {
  const ph = TAU * phase01;
  const sw = Math.sin(ph);
  const amp = hurry ? 0.53 : 0.47;
  po.plant = true;
  setV(po.leg[0], amp * sw, 0.02, 0.08 + 0.8 * Math.pow(Math.max(0.0, Math.cos(ph)), 1.5));
  setV(po.leg[1], -amp * sw, 0.02, 0.08 + 0.8 * Math.pow(Math.max(0.0, -Math.cos(ph)), 1.5));
  const a0 = -(hurry ? 0.5 : 0.42) * sw;
  setV(po.arm[0], a0, 0.07, 0.25 + (hurry ? 0.6 : 0.3) * Math.max(0.0, a0) + (hurry ? 0.35 : 0.0));
  setV(po.arm[1], -a0, 0.07, 0.25 + (hurry ? 0.6 : 0.3) * Math.max(0.0, -a0) + (hurry ? 0.35 : 0.0));
  po.twist = 0.07 * sw;
  po.yaw = -0.05 * sw;
  po.side = 0.02 * Math.sin(ph * 2.0);
  po.lean = hurry ? 0.11 : 0.05;
  po.head[1] = -0.07 * sw;
  po.head[0] = 0.04;
}

/** The hand's resting place at a table on side k (person-local), pooled. */
function tableHand(p, po, inv, k) {
  const d = p.table[1] > 0.0 ? (p.table[0] + 0.12) * inv : 0.3;
  const y = p.table[1] > 0.0 ? (p.table[1] + 0.03) * inv : po.hip + 0.05;
  return V(k === 0 ? -0.15 : 0.15, y, Math.max(d, 0.26));
}

function seated(p, t, tau, po, inv) {
  const rest0 = tableHand(p, po, inv, 0);
  const rest1 = tableHand(p, po, inv, 1);
  ikArm(po, 0, rest0, V(-0.8, -1.0, -0.4));
  ikArm(po, 1, rest1, V(0.8, -1.0, -0.4));
  po.lean = 0.08;
  let cupRest = vaddc(rest1, 0.06, 0.02, 0.04);
  const act = p.action;
  const hasCup = act !== 'drink';
  switch (act) {
    case 'type': {
      po.lean = 0.16;
      po.head[0] = 0.12;
      for (let k = 0; k < 2; k++) {
        const sg = k === 0 ? -1.0 : 1.0;
        const rest = k === 0 ? rest0 : rest1;
        const tap = Math.max(0.0, Math.sin(tau * TAU / period('type') + k * 2.1)) * 0.014;
        setV(po.arm[k], sg * (0.12 + 0.012 * Math.sin(tau * 1.3 + k)), rest[1] + 0.01 + tap, rest[2] + 0.16 * inv);
      }
      cupRest = V(0.38, rest1[1] + 0.02, rest1[2] + 0.04);
      const look = event(p, tau, 2.6, 21);
      if (look[2] < 0.5) {
        po.lean += 0.12 * look[0];
        po.head[0] -= 0.1 * look[0];
      } else {
        po.head[1] += (look[2] < 0.75 ? 0.45 : -0.45) * look[0];
      }
      break;
    }
    case 'read_screen':
      po.lean = -0.04;
      po.head[0] = 0.06;
      setV(po.arm[1], 0.24, rest1[1] + 0.005 + 0.006 * Math.sin(tau * 3.1), rest1[2] + 0.04 + 0.02 * Math.sin(tau * 0.9));
      // the other hand under the chin, elbow on the desk
      set3(po.arm[0], headPt(po, -0.04, HEAD_C - 0.17, 0.17));
      setV(po.pole[0], -0.3, -1.0, 0.5);
      po.head[2] = 0.08;
      po.head[1] = 0.1 * Math.sin(tau * 0.31);
      cupRest = V(0.4, rest1[1] + 0.02, rest1[2]);
      break;
    case 'phone': {
      po.head[2] = 0.14;
      po.head[0] = 0.04;
      set3(po.arm[0], headPt(po, -0.2, HEAD_C - 0.02, 0.04));
      setV(po.pole[0], -0.6, -1.0, 0.2);
      po.propOn[0] = 0;
      setProp(po, 0, 0.025, 0.14, 0.07, 0.03, -0.02, 0.0);
      const nod = 0.07 * Math.sin(tau * TAU / 2.3) * (0.5 + 0.5 * Math.sin(tau * 0.4));
      po.head[0] += nod;
      const gest = event(p, tau, 2.0, 31);
      set3(po.arm[1], vlerp(rest1, V(0.22, po.hip + 0.32, 0.32), gest[0]));
      break;
    }
    case 'eat': {
      po.lean = 0.14;
      po.head[0] = 0.16;
      const bite = event(p, tau, 2.2, 41);
      const plate = V(-0.08, rest0[1] + 0.02, rest0[2] + 0.08);
      po.head[0] -= 0.18 * bite[0];
      const m = vaddc(mouth(po), 0, -0.02, 0.05);
      set3(po.arm[0], vlerp(plate, m, bite[1] >= 0.0 ? bump(bite[1], 0.4, 0.4) : 0.0));
      po.propOn[0] = 0;
      setProp(po, 0, 0.06, 0.04, 0.06, 0.0, -0.02, 0.06);
      break;
    }
    case 'chat':
      chat(p, t, tau, po, rest0, rest1);
      break;
    case 'drink': {
      po.propOn[0] = 1;
      setProp(po, 0, 0.08, 0.1, 0.08, 0.0, 0.01, 0.05);
      const sip = event(p, tau, 2.4, 51);
      const u = sip[1] >= 0.0 ? bump(sip[1], 0.3, 0.35) : 0.0;
      po.head[0] -= 0.2 * u;
      set3(po.arm[1], vlerp(rest1, vaddc(mouth(po), 0.03, -0.06, 0.07), u));
      if (p.hasPartner) po.head[1] = p.partnerYaw * 0.25 * (0.5 + 0.5 * Math.sin(tau * 0.5));
      const turn = event(p, tau + 2.1, 1.8, 52);
      po.head[1] += (turn[2] < 0.5 ? 0.5 : -0.5) * turn[0] * (1.0 - u);
      break;
    }
    default: break;
  }
  if (hasCup && p.slots[P_PROP_B] >= 0) {
    // the cup on the table, lifted to the mouth now and then (every 4 to 9 s, varied)
    const sip = act !== 'chat' ? event(p, tau + 1.3, 3.0, 61) : V(0.0, -1.0, 0.0);
    po.propOn[1] = 2;
    setProp(po, 1, 0.08, 0.1, 0.08, cupRest[0] + f(0), cupRest[1] + f(0.05), cupRest[2] + f(0));
    po.propHome[1] = true;
    if (sip[1] >= 0.0 && sip[2] < 0.6 && (act === 'type' || act === 'read_screen' || act === 'eat')) {
      const reach = smooth(sip[1] / 0.2) * smooth((1.0 - sip[1]) / 0.2);
      const liftK = bump((sip[1] - 0.2) / 0.6, 0.35, 0.35);
      po.head[0] -= 0.18 * liftK;
      const m = vaddc(mouth(po), 0.03, -0.06, 0.07);
      const hand = vlerp(vlerp(po.arm[1], vsub(cupRest, V(0.0, 0.0, 0.05)), reach), m, liftK);
      set3(po.arm[1], hand);
      if (reach > 0.95) {
        po.propOn[1] = 1;
        po.propHome[1] = false;
        setProp(po, 1, 0.08, 0.1, 0.08, 0.0, 0.01, 0.05);
      }
    }
  }
}

/**
 * Posture now and then (besides the head turns and cup lifts, on its own slot so they interleave): a shift
 * of weight, leaning back, crossing the legs.
 */
function posture(p, tau, po) {
  if (p.legsSeat) {
    setV(po.leg[0], 1.45, 0.06, 1.5);
    setV(po.leg[1], 1.45, 0.06, 1.5);
  }
  const pz = event(p, tau + 3.7, 3.6, 151);
  if (pz[1] < 0.0) return;
  const sg = hash01(p.sd, Math.floor((tau + 3.7) / p.slot) + 9000) < 0.5 ? 1.0 : -1.0;
  switch (Math.trunc(pz[2] * 3.0)) {
    case 0:
      po.sway += 0.05 * pz[0] * sg;
      po.off[0] += 0.035 * pz[0] * sg;
      break;
    case 1:
      po.lean -= 0.16 * pz[0];
      po.head[0] -= 0.05 * pz[0];
      break;
    default:
      po.cross = pz[0] * sg;
      if (p.legsSeat) {
        const k = sg < 0.0 ? 0 : 1;
        setV(po.leg[k], 1.45 + 0.15 * pz[0], 0.06 - 0.32 * pz[0], 1.5 - 0.15 * pz[0]);
      }
      break;
  }
}

/**
 * Talking at a table: turns toward the partner; the speaker gestures, the listener nods. Who speaks is
 * decided on the pair's shared clock, so the two take turns.
 */
function chat(p, t, tau, po, rest0, rest1) {
  const toward = p.hasPartner ? p.partnerYaw : 0.0;
  po.head[1] = clampf(toward, -1.1, 1.1) * 0.7;
  po.twist = clampf(toward, -1.1, 1.1) * 0.25;
  const turn = Math.floor((t + (p.pairSeed % 1000) * 0.01) / 3.4);    // the pair's turn on the shared clock
  const speaker = Math.trunc(hash01(p.pairSeed, turn) * 2.0);
  const speaking = speaker === p.partnerRank || !p.hasPartner;
  if (speaking) {
    const g = 0.5 + 0.5 * Math.sin(tau * TAU / 1.6);
    set3(po.arm[1], vlerp(rest1, V(0.24, po.hip + 0.28 + 0.06 * g, 0.34), 0.4 + 0.6 * g));
    set3(po.arm[0], vlerp(rest0, V(-0.2, po.hip + 0.24, 0.3), 0.5 * (0.5 + 0.5 * Math.sin(tau * TAU / 2.3 + 1.0))));
    po.head[2] = 0.05 * Math.sin(tau * 1.7);
    po.head[0] = -0.05;
  } else {
    po.head[0] = 0.08 * Math.sin(tau * TAU / 1.1) * Math.max(0.0, Math.sin(tau * 0.9));
    po.lean = 0.12;
    set3(po.arm[0], vaddc(rest0, 0.05, 0.0, -0.02));
  }
}

function ride(p, tau, po) {
  // toward the default camera (+z in the world): the side to wave on and to look at
  const cam = bXformc(bInverse(p.world), 0, 0, 1);
  const outward = Math.atan2(cam[0], cam[2]);
  const waveK = cam[0] > 0.0 ? 1 : 0;
  if (p.kind === K_CAROUSEL) {
    setV(po.leg[0], 1.3, 0.38, 1.35);
    setV(po.leg[1], 1.3, 0.38, 1.35);
    const grip = po.hip + 0.3;
    ikArm(po, 0, V(-0.07, grip, 0.3), V(-1, -1, -0.3));
    ikArm(po, 1, V(0.07, grip, 0.3), V(1, -1, -0.3));
    po.lean = 0.1 + 0.04 * Math.sin(tau * 2.2);
  } else {
    ikArm(po, 0, V(-0.13, po.hip + 0.04, 0.3), V(-0.8, -1, -0.2));
    ikArm(po, 1, V(0.13, po.hip + 0.04, 0.3), V(0.8, -1, -0.2));
    po.lean = -0.05;
  }
  const look = event(p, tau, 3.0, 71);
  po.head[1] = clampf(outward, -1.2, 1.2) * 0.6 * look[0] + 0.3 * Math.sin(tau * 0.37);
  po.head[0] = -0.05 * look[0];
  const wave = event(p, tau + 3.3, 2.6, 72);
  if (wave[1] >= 0.0 && wave[2] < 0.55) {
    const sg = waveK === 0 ? -1.0 : 1.0;
    const up = V(sg * 0.3, po.hip + 0.85, 0.12 + 0.05 * Math.sin(tau * TAU * 1.6));
    set3(po.arm[waveK], vlerp(po.arm[waveK], vaddc(up, sg * 0.06 * Math.sin(tau * TAU * 1.6), 0, 0), wave[0]));
    setV(po.pole[waveK], sg, -0.3, 0.0);
    po.head[1] = clampf(outward, -1.2, 1.2) * 0.8 * wave[0] + po.head[1] * (1.0 - wave[0]);
  }
}

function cook(p, tau, po, inv) {
  stand(po);
  const top = (p.table[1] > 0.0 ? p.table[1] : 1.06) * inv;
  const d = (p.table[1] > 0.0 ? p.table[0] : 0.35) * inv;
  const ph = fposmod(tau / period('cook'), 1.0);
  const toss = Math.pow(Math.max(0.0, Math.sin(ph * TAU)), 3.0);
  const pan = V(-0.12, top + 0.14 + 0.05 * toss, d + 0.12 + 0.03 * toss);
  ikArm(po, 0, pan, V(-1, -0.6, -0.4));
  po.propOn[0] = 0;
  setProp(po, 0, 0.26, 0.04, 0.26, 0.05, 0.0, 0.14);
  // the food flips: up and down over the pan
  const fly = 0.22 * Math.max(0.0, Math.sin(fposmod(ph - 0.25, 1.0) * TAU));
  po.propOn[1] = 2;
  const food = bMul(rotX(fly * 9.0), xScale(0.12, 0.05, 0.12));
  const at = vaddc(pan, 0.05, 0.06 + fly, 0.12);
  food[9] = at[0]; food[10] = at[1]; food[11] = at[2];
  setX(po.propXf[1], food);
  const shake = 0.03 * Math.sin(tau * TAU * 3.0);
  ikArm(po, 1, V(0.2, top + 0.3 + shake, d + 0.18), V(1, -0.6, -0.4));
  po.lean = 0.12;
  po.head[0] = 0.3;
  const ev = event(p, tau, 2.4, 81);
  if (ev[2] < 0.5) {
    po.twist = 0.5 * ev[0];
    po.head[1] = 0.4 * ev[0];
    po.head[0] -= 0.25 * ev[0];
  } else {
    set3(po.arm[1], vlerp(po.arm[1], V(0.12, top + 0.12, d + 0.4), ev[0]));
    po.head[0] -= 0.1 * ev[0];
  }
}

function waiter(p, tau, po) {
  stand(po);
  // turns slowly between the tables, stepping as it turns
  const turnPh = tau * TAU / period('wait_tables');
  po.yaw = 0.75 * Math.sin(turnPh);
  const turning = Math.abs(Math.cos(turnPh));
  const step = Math.sin(tau * TAU * 1.5);
  setV(po.leg[0], 0.12 * step * turning, 0.03, 0.04 + 0.5 * Math.max(0.0, step) * turning);
  setV(po.leg[1], -0.12 * step * turning, 0.03, 0.04 + 0.5 * Math.max(0.0, -step) * turning);
  po.twist = 0.1 * Math.sin(turnPh + 0.6);
  // the tray on the flat hand, a cup on the tray
  ikArm(po, 0, V(-0.28, 1.1, 0.25), V(-1, -0.6, -0.5));
  po.propOn[0] = 0;
  setProp(po, 0, 0.38, 0.025, 0.38, 0.02, 0.05, 0.04);
  po.propOn[1] = 0;
  setProp(po, 1, 0.08, 0.1, 0.08, 0.0, 0.12, 0.06);
  const ev = event(p, tau, 1.8, 91);
  po.head[0] = 0.25 * ev[0] * (ev[2] < 0.6 ? 1.0 : 0.0);
  setV(po.arm[1], 0.05 + 0.6 * ev[0] * (ev[2] >= 0.6 ? 1.0 : 0.3), 0.12, 0.2 + 0.4 * ev[0]);
  po.head[1] = 0.2 * Math.sin(turnPh + 0.3);
}

function staff(p, tau, po, inv) {
  stand(po);
  const top = (p.table[1] > 0.0 ? p.table[1] : 0.96) * inv;
  const d = (p.table[1] > 0.0 ? p.table[0] : 0.4) * inv;
  const rest0 = V(-0.18, top + 0.02, d + 0.03);
  const rest1 = V(0.18, top + 0.02, d + 0.03);
  ikArm(po, 0, rest0, V(-1, -0.8, -0.6));
  ikArm(po, 1, rest1, V(1, -0.8, -0.6));
  po.lean = 0.08;
  po.sway = 0.025 * Math.sin(tau * TAU / 7.0);
  po.off[0] = 0.02 * Math.sin(tau * TAU / 7.0);
  if (p.action === 'wipe_counter') {
    const w = tau * TAU / period('wipe_counter');
    setV(po.arm[1], 0.05 + 0.13 * Math.cos(w), top + 0.035, d + 0.12 + 0.07 * Math.sin(w));
    po.propOn[0] = 1;
    setProp(po, 0, 0.15, 0.025, 0.11, 0.0, -0.05, 0.03);
    po.lean = 0.24;
    po.head[0] = 0.35;
    const ev = event(p, tau, 2.2, 101);
    po.head[0] -= 0.4 * ev[0];
    po.head[1] = 0.35 * ev[0] * (ev[2] < 0.5 ? 1.0 : -1.0);
    set3(po.arm[1], vlerp(po.arm[1], rest1, 0.7 * ev[0]));
    if (ev[0] > 0.5) po.head[0] += 0.12 * Math.sin(tau * TAU * 1.4);
  } else {
    // hand something over the counter, with a nod; between times look about
    po.head[0] = 0.08;
    const handEv = event(p, tau, 3.2, 111);
    po.propOn[0] = -1;
    if (handEv[1] >= 0.0) {
      const u = handEv[1];
      const below = V(0.24, top - 0.25, 0.12);
      const over = V(0.1, top + 0.14, d + 0.45);
      let hand = rest1;
      if (u < 0.25) hand = vlerp(rest1, below, smooth(u / 0.25));
      else if (u < 0.55) hand = vlerp(below, over, smooth((u - 0.25) / 0.3));
      else if (u < 0.8) hand = over;
      else hand = vlerp(over, rest1, smooth((u - 0.8) / 0.2));
      set3(po.arm[1], hand);
      setV(po.pole[1], 1, -0.6, -0.8);
      if (u > 0.22 && u < 0.8) {
        po.propOn[0] = 1;
        setProp(po, 0, 0.13, 0.11, 0.13, 0.0, 0.0, 0.07);
      }
      const nod = bump((u - 0.55) / 0.3, 0.4, 0.4);
      po.head[0] += 0.28 * nod - 0.1 * bump(u / 0.3, 0.3, 0.3);
      po.lean += 0.12 * bump((u - 0.4) / 0.45, 0.3, 0.3);
    } else {
      po.head[1] = 0.3 * Math.sin(tau * 0.45);
    }
  }
}

function customer(p, tau, po, inv) {
  stand(po);
  po.sway = 0.03 * Math.sin(tau * TAU / 6.0);
  po.off[0] = 0.025 * Math.sin(tau * TAU / 6.0);
  if (p.action === 'carry_bag') {
    setV(po.arm[1], 0.08, 0.05, 0.2);
    po.propOn[0] = 1;
    setProp(po, 0, 0.26, 0.3, 0.12, 0.0, -0.18, 0.0);
    setV(po.arm[0], 0.05, 0.1, 0.25);
    po.head[1] = 0.45 * Math.sin(tau * 0.33);
    po.head[0] = 0.12;
    const bagEv = event(p, tau, 2.5, 121);
    if (bagEv[2] < 0.5) {
      // points at something in the window
      po.lean = 0.2 * bagEv[0];
      po.head[0] += 0.25 * bagEv[0];
      ikArm(po, 0, vlerp(V(-0.3, 0.62, 0.05), V(-0.12, 1.15 * inv, 0.45), bagEv[0]), V(-1, -0.6, -0.4));
    } else {
      po.yaw = 0.35 * bagEv[0];
      po.head[1] = 0.6 * bagEv[0];
    }
    return;
  }
  // browse: scan the shelf, now and then take a thing down, look at it and put it back
  const shelf = (p.table[1] > 0.0 ? p.table[1] : 1.2) * inv;
  const d = (p.table[1] > 0.0 ? p.table[0] : 0.4) * inv;
  po.head[1] = 0.35 * Math.sin(tau * TAU / 7.5);
  po.head[0] = 0.1 * Math.sin(tau * TAU / 5.3) - (shelf < 1.0 ? 0.15 : -0.05);
  setV(po.arm[0], 0.08, 0.1, 0.25);
  setV(po.arm[1], 0.05, 0.08, 0.2);
  const ev = event(p, tau, 4.0, 131);
  if (ev[1] >= 0.0) {
    const u = ev[1];
    const spot = V(0.18 + 0.15 * (ev[2] - 0.5), clampf(shelf + 0.1, 0.9, 1.5), d + 0.08);
    const chest = V(0.06, po.hip + 0.28, 0.32);
    const hang = torPt(po, 0.27, 0.0, 0.08);
    let hand = hang;
    if (u < 0.2) hand = vlerp(hang, spot, smooth(u / 0.2));
    else if (u < 0.35) hand = vlerp(spot, chest, smooth((u - 0.2) / 0.15));
    else if (u < 0.7) hand = chest;
    else if (u < 0.85) hand = vlerp(chest, spot, smooth((u - 0.7) / 0.15));
    else hand = vlerp(spot, hang, smooth((u - 0.85) / 0.15));
    ikArm(po, 1, hand, V(1, -0.7, -0.5));
    if (u > 0.18 && u < 0.86) {
      po.propOn[0] = 1;
      setProp(po, 0, 0.16, 0.2, 0.05, 0.0, 0.0, 0.05);
    }
    const look = bump((u - 0.3) / 0.45, 0.2, 0.2);
    po.head[0] = po.head[0] * (1.0 - look) + 0.35 * look;
    po.head[1] *= 1.0 - look;
    po.lean = 0.1 * look;
  }
}

function run(_p, tau, po) {
  po.plant = true;
  const ph = tau * TAU / period('run');
  const sw = Math.sin(ph);
  setV(po.leg[0], 0.55 * sw, 0.02, 0.3 + 1.1 * Math.pow(Math.max(0.0, Math.cos(ph)), 1.2));
  setV(po.leg[1], -0.55 * sw, 0.02, 0.3 + 1.1 * Math.pow(Math.max(0.0, -Math.cos(ph)), 1.2));
  setV(po.arm[0], -0.55 * sw, 0.12, 1.45);
  setV(po.arm[1], 0.55 * sw, 0.12, 1.45);
  po.lean = 0.14;
  po.twist = 0.1 * sw;
  po.off[1] += 0.03 * Math.abs(Math.cos(ph));
  po.head[0] = -0.08;
}

function cycle(_p, tau, po, inv) {
  // the saddle 0.22 m behind the bike's centre, the bars 0.28 m ahead at 1.0, the cranks at 0.34
  po.off[2] = -0.22 * inv;
  const th = tau * TAU / period('cycle');
  for (let k = 0; k < 2; k++) {
    const sg = k === 0 ? -1.0 : 1.0;
    const a = th + k * Math.PI;
    const pedal = vmul(V(sg * 0.11, 0.34 + 0.13 * Math.sin(a), 0.02 + 0.13 * Math.cos(a)), inv);
    po.legIk[k] = true;
    set3(po.leg[k], vaddc(pedal, 0, SHOE_H * 0.7, -0.04));
    ikArm(po, k, vmul(V(sg * 0.2, 1.0, 0.28), inv), V(sg, -1.0, -0.5));
  }
  po.lean = 0.5;
  po.head[0] = -0.32;
  po.sway = 0.03 * Math.sin(th);
  po.twist = 0.04 * Math.sin(th);
}

function row(_p, tau, po, inv) {
  const u = fposmod(tau / period('row'), 1.0);
  // the drive (legs push, then the arms pull) and the slower recovery
  let slide = 0.0;
  if (u < 0.4) slide = 1.0 - smooth(u / 0.4);
  else slide = smooth((u - 0.4) / 0.6);
  const arms = u < 0.4 ? 1.0 - smooth((u - 0.2) / 0.2) : smooth((u - 0.5) / 0.25);
  po.off[2] = 0.3 * slide * inv;
  po.lean = -0.28 + 0.7 * slide;
  for (let k = 0; k < 2; k++) {
    const sg = k === 0 ? -1.0 : 1.0;
    po.legIk[k] = true;
    setV(po.leg[k], sg * 0.11, (0.24 + SHOE_H * 0.7) * inv, 0.72 * inv);
  }
  const chest = V(0.0, po.hip + 0.3, po.off[2] + 0.2);
  const reach = V(0.0, 0.48 * inv, 0.7 * inv);
  const handle = vlerp(chest, reach, arms);
  ikArm(po, 0, vaddc(handle, -0.12, 0, 0), V(-1, -0.5, -0.8));
  ikArm(po, 1, vaddc(handle, 0.12, 0, 0), V(1, -0.5, -0.8));
  po.propOn[0] = 2;
  setProp(po, 0, 0.42, 0.035, 0.035, handle[0] + f(0), handle[1] + f(-0.01), handle[2] + f(0.04));
  po.head[0] = -0.2 * slide;
}

// [lean, side, hand 0 target, hand 1 target]
const STRETCH_KEYS = [
  [0.0, 0.0, [-0.15, 2.05, 0.08], [0.15, 2.05, 0.08]],
  [0.0, 0.3, [-0.05, 2.0, 0.05], [0.3, 1.85, 0.05]],
  [0.0, 0.0, [-0.15, 2.05, 0.08], [0.15, 2.05, 0.08]],
  [0.0, -0.3, [-0.3, 1.85, 0.05], [0.05, 2.0, 0.05]],
  [1.05, 0.0, [-0.12, 0.3, 0.3], [0.12, 0.3, 0.3]],
  [0.05, 0.0, [0.3, 1.22, 0.12], [0.1, 1.3, 0.25]],
];

/**
 * A stretching routine on the mat: reach up, bend to each side, fold forward, cross an arm; a key pose
 * every few seconds with eased moves between them.
 */
function stretch(_p, tau, po) {
  stand(po);
  setV(po.leg[0], 0.0, 0.12, 0.03);
  setV(po.leg[1], 0.0, 0.12, 0.03);
  const n = STRETCH_KEYS.length;
  const x = fposmod(tau / period('stretch'), 1.0) * n;
  const i = Math.floor(x);
  const fr = x - i;
  const b = smooth((fr - 0.55) / 0.45);
  const k0 = STRETCH_KEYS[i % n];
  const k1 = STRETCH_KEYS[(i + 1) % n];
  po.lean = lerpf(k0[0], k1[0], b);
  po.side = lerpf(k0[1], k1[1], b);
  const hold = 0.02 * Math.sin(tau * TAU / 2.2);
  for (let k = 0; k < 2; k++) {
    const sg = k === 0 ? -1.0 : 1.0;
    const a = k0[2 + k];
    const c = k1[2 + k];
    const target = vlerp(V(a[0], a[1], a[2]), V(c[0], c[1], c[2]), b);
    ikArm(po, k, vaddc(target, 0, hold, 0), V(sg, -0.2, -0.6));
  }
  po.head[0] = 0.4 * po.lean - 0.1;
  po.head[2] = -0.4 * po.side;
}

function lift(_p, tau, po) {
  stand(po);
  setV(po.leg[0], 0.0, 0.1, 0.06);
  setV(po.leg[1], 0.0, 0.1, 0.06);
  const ph = fposmod(tau / period('lift'), 1.0);
  for (let k = 0; k < 2; k++) {
    const u = fposmod(ph + 0.5 * k, 1.0);
    const curl = bump(u / 0.6, 0.45, 0.45);
    setV(po.arm[k], 0.12, 0.1, 0.2 + 2.0 * curl);
    po.propOn[k] = k;
    setProp(po, k, 0.24, 0.08, 0.08, 0.0, -0.02, 0.0);
  }
  po.head[0] = -0.05;
}

// ===================================================================== rain: blending poses

/** The hand of arm k at the end of its forward kinematics (person-local), pooled. */
export function armEnd(po, k, female) {
  const tor = frames(po, FR)[1];
  const tw = female ? 0.39 : 0.44;
  const sg = k === 0 ? -1.0 : 1.0;
  const sh = xPointc(tor, sg * (tw * 0.5 + 0.045), SHOULDER_Y, 0.0);
  fk(sh, tor, po.arm[k], sg, UARM, FARM + 0.04, false, J0, J1);
  return V(J1[0], J1[1], J1[2]);
}

const TA = [null, null];
const TB = [null, null];

/**
 * Blends pose a toward pose b by k (into a). Arms in different modes meet as hand targets; a keeps its held
 * things (the waiter's tray, a cup) and its things left at home.
 */
export function mix(a, b, k, female) {
  for (let i = 0; i < 2; i++) {
    if (a.armIk[i] !== b.armIk[i] || a.armIk[i]) {
      TA[i] = a.armIk[i] ? V(a.arm[i][0], a.arm[i][1], a.arm[i][2]) : armEnd(a, i, female);
      TB[i] = b.armIk[i] ? b.arm[i] : armEnd(b, i, female);
    }
  }
  for (let i = 0; i < 2; i++) {
    if (!a.armIk[i] && !b.armIk[i]) {
      set3(a.arm[i], vlerp(a.arm[i], b.arm[i], k));
    } else {
      set3(a.arm[i], vlerp(TA[i], TB[i], k));
      set3(a.pole[i], vlerp(a.pole[i], b.pole[i], k));
      a.armIk[i] = true;
    }
    if (!a.legIk[i] && !b.legIk[i]) {
      set3(a.leg[i], vlerp(a.leg[i], b.leg[i], k));
    } else if (k >= 0.5) {
      a.legIk[i] = b.legIk[i];
      set3(a.leg[i], b.leg[i]);
    }
    if (a.propOn[i] < 0) {
      a.propOn[i] = b.propOn[i];
      setX(a.propXf[i], b.propXf[i]);
      a.propHome[i] = b.propHome[i];
    }
  }
  a.hip = lerpf(a.hip, b.hip, k);
  set3(a.off, vlerp(a.off, b.off, k));
  a.yaw = lerpAngle(a.yaw, b.yaw, k);
  a.sway = lerpf(a.sway, b.sway, k);
  a.lean = lerpf(a.lean, b.lean, k);
  a.twist = lerpf(a.twist, b.twist, k);
  a.side = lerpf(a.side, b.side, k);
  set3(a.head, vlerp(a.head, b.head, k));
  const pa = a.plant ? a.plantK : 0.0;
  const pb = b.plant ? b.plantK : 0.0;
  a.plantK = lerpf(pa, pb, k);
  a.plant = a.plant || b.plant;
  a.ground = lerpf(a.ground, b.ground, k);
  a.cross = lerpf(a.cross, b.cross, k);
}

/** Waiting under cover: standing, now and then glancing up at the sky or shaking the rain off. */
export function coverIdle(p, tau, po) {
  stand(po);
  po.sway = 0.02 * Math.sin(tau * TAU / 5.0);
  po.off[0] = 0.015 * Math.sin(tau * TAU / 5.0);
  const hands = hash01(p.sd, 171) < 0.5;
  if (hands) {
    ikArm(po, 0, V(-0.07, 1.08, 0.24), V(-1, -1, -0.4));
    ikArm(po, 1, V(0.07, 1.08, 0.24), V(1, -1, -0.4));
  }
  const ev = event(p, tau, 2.4, 161);
  if (ev[2] < 0.55) {
    po.head[0] = -0.45 * ev[0];
    po.head[1] = (ev[2] < 0.27 ? 0.3 : -0.3) * ev[0];
  } else {
    const sh = Math.sin(tau * TAU * 4.0) * ev[0];
    po.side = 0.05 * sh;
    po.head[2] = 0.08 * sh;
    if (!hands) {
      setV(po.arm[0], 0.1 + 0.1 * sh, 0.2 + 0.1 * ev[0], 0.3);
      setV(po.arm[1], 0.1 - 0.1 * sh, 0.2 + 0.1 * ev[0], 0.3);
    }
  }
}

/** The umbrella hand rises from wherever it was to hold the umbrella over the head as it opens. */
export function umbrellaArm(po, female) {
  if (po.umb <= 0.0) return;
  const k = po.umbHand;
  const sg = k === 0 ? -1.0 : 1.0;
  const cur = po.armIk[k] ? po.arm[k] : armEnd(po, k, female);
  const target = V(sg * 0.17, po.hip + 0.6, 0.2);
  set3(po.arm[k], vlerp(cur, target, smooth(po.umb * 3.0)));
  setV(po.pole[k], sg, -1.0, -0.6);
  po.armIk[k] = true;
}
