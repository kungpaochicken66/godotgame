// The people's maths: Godot's Vector3, Basis and Transform3D on preallocated Float32Arrays, so that the port
// of art/city_people.gd (people_core.js, people_pose.js) rounds where Godot rounds (its vectors and transforms
// are single precision; GDScript's own numbers are doubles, as JavaScript's are) and allocates nothing per frame.
//
// Layouts:
//   vector     Float32Array(3)
//   transform  Float32Array(12): the basis's x, y, z columns, then the origin (Godot's order, as mesh_pack.gd
//              writes it). A basis is a transform whose origin is not read.
// Temporaries come from two pools that the caller rewinds with resetPools() (once per person per update):
// a pooled value is valid until the next rewind and must be copied (set3, setX) into anything that lives longer.
// No DOM, no Three.js: importable in Node.

export const f = Math.fround;

const NV = 1536;
const NX = 512;
const VP = [];
const XP = [];
for (let i = 0; i < NV; i++) VP.push(new Float32Array(3));
for (let i = 0; i < NX; i++) XP.push(new Float32Array(12));
let vi = 0;
let xi = 0;
let vPeak = 0;
let xPeak = 0;

/** Rewinds both pools (every pooled value is free again). */
export function resetPools() {
  if (vi > vPeak) vPeak = vi;
  if (xi > xPeak) xPeak = xi;
  vi = 0;
  xi = 0;
}

/** The most temporaries used between two rewinds so far: [vectors, transforms] (tests watch the head room). */
export function poolPeaks() { return [Math.max(vPeak, vi), Math.max(xPeak, xi), NV, NX]; }

function nv() {
  if (vi >= NV) throw new Error('people_math: vector pool exhausted');
  return VP[vi++];
}

function nx() {
  if (xi >= NX) throw new Error('people_math: transform pool exhausted');
  return XP[xi++];
}

// ---------------------------------------------------------------- vectors

/** A pooled Vector3. */
export function V(x, y, z) {
  const o = nv();
  o[0] = x; o[1] = y; o[2] = z;
  return o;
}

export function set3(dst, src) {
  dst[0] = src[0]; dst[1] = src[1]; dst[2] = src[2];
  return dst;
}

export function setV(dst, x, y, z) {
  dst[0] = x; dst[1] = y; dst[2] = z;
  return dst;
}

export function vadd(a, b) {
  const o = nv();
  o[0] = a[0] + b[0]; o[1] = a[1] + b[1]; o[2] = a[2] + b[2];
  return o;
}

/** a + (x, y, z). */
export function vaddc(a, x, y, z) {
  const o = nv();
  o[0] = a[0] + f(x); o[1] = a[1] + f(y); o[2] = a[2] + f(z);
  return o;
}

export function vsub(a, b) {
  const o = nv();
  o[0] = a[0] - b[0]; o[1] = a[1] - b[1]; o[2] = a[2] - b[2];
  return o;
}

/** Vector3 * float (the float becomes single precision first, as Godot's real_t parameter does). */
export function vmul(a, s) {
  const o = nv();
  const k = f(s);
  o[0] = a[0] * k; o[1] = a[1] * k; o[2] = a[2] * k;
  return o;
}

export function vneg(a) {
  const o = nv();
  o[0] = -a[0]; o[1] = -a[1]; o[2] = -a[2];
  return o;
}

/** Vector3.lerp: from + (to - from) * weight, each step in single precision. */
export function vlerp(a, b, t) {
  const o = nv();
  const k = f(t);
  o[0] = a[0] + f(f(b[0] - a[0]) * k);
  o[1] = a[1] + f(f(b[1] - a[1]) * k);
  o[2] = a[2] + f(f(b[2] - a[2]) * k);
  return o;
}

export function dot(a, b) {
  return f(f(f(a[0] * b[0]) + f(a[1] * b[1])) + f(a[2] * b[2]));
}

export function lenSq(a) {
  return f(f(f(a[0] * a[0]) + f(a[1] * a[1])) + f(a[2] * a[2]));
}

export function len(a) { return f(Math.sqrt(lenSq(a))); }

export function dist(a, b) {
  const x = f(b[0] - a[0]);
  const y = f(b[1] - a[1]);
  const z = f(b[2] - a[2]);
  return f(Math.sqrt(f(f(f(x * x) + f(y * y)) + f(z * z))));
}

export function cross(a, b) {
  const o = nv();
  o[0] = f(a[1] * b[2]) - f(a[2] * b[1]);
  o[1] = f(a[2] * b[0]) - f(a[0] * b[2]);
  o[2] = f(a[0] * b[1]) - f(a[1] * b[0]);
  return o;
}

/** Vector3.normalized (a zero vector stays zero). */
export function vnorm(a) {
  const o = nv();
  const l2 = lenSq(a);
  if (l2 === 0) {
    o[0] = 0; o[1] = 0; o[2] = 0;
  } else {
    const l = f(Math.sqrt(l2));
    o[0] = a[0] / l; o[1] = a[1] / l; o[2] = a[2] / l;
  }
  return o;
}

// ---------------------------------------------------------------- 2D helpers (plain numbers, single precision)

/** Vector2.distance_to. */
export function dist2(ax, ay, bx, by) {
  const x = f(ax - bx);
  const y = f(ay - by);
  return f(Math.sqrt(f(f(x * x) + f(y * y))));
}

// ---------------------------------------------------------------- bases and transforms

export function setX(dst, src) {
  for (let i = 0; i < 12; i++) dst[i] = src[i];
  return dst;
}

/** A pooled identity transform. */
export function xIdentity() {
  const o = nx();
  o[0] = 1; o[1] = 0; o[2] = 0; o[3] = 0; o[4] = 1; o[5] = 0; o[6] = 0; o[7] = 0; o[8] = 1; o[9] = 0; o[10] = 0; o[11] = 0;
  return o;
}

/** Basis(Vector3.RIGHT, angle). */
export function rotX(angle) {
  const o = nx();
  const a = f(angle);
  const c = f(Math.cos(a));
  const s = f(Math.sin(a));
  o[0] = 1; o[1] = 0; o[2] = 0;
  o[3] = 0; o[4] = c; o[5] = s;
  o[6] = 0; o[7] = -s; o[8] = c;
  o[9] = 0; o[10] = 0; o[11] = 0;
  return o;
}

/** Basis(Vector3.UP, angle). */
export function rotY(angle) {
  const o = nx();
  const a = f(angle);
  const c = f(Math.cos(a));
  const s = f(Math.sin(a));
  o[0] = c; o[1] = 0; o[2] = -s;
  o[3] = 0; o[4] = 1; o[5] = 0;
  o[6] = s; o[7] = 0; o[8] = c;
  o[9] = 0; o[10] = 0; o[11] = 0;
  return o;
}

/** Basis(Vector3.BACK, angle) (BACK is +z). */
export function rotZ(angle) {
  const o = nx();
  const a = f(angle);
  const c = f(Math.cos(a));
  const s = f(Math.sin(a));
  o[0] = c; o[1] = s; o[2] = 0;
  o[3] = -s; o[4] = c; o[5] = 0;
  o[6] = 0; o[7] = 0; o[8] = 1;
  o[9] = 0; o[10] = 0; o[11] = 0;
  return o;
}

/** Basis.from_scale(Vector3(x, y, z)) with an origin: Transform3D(Basis.from_scale(...), Vector3(ox, oy, oz)). */
export function xScale(sx, sy, sz, ox = 0, oy = 0, oz = 0) {
  const o = nx();
  o[0] = sx; o[1] = 0; o[2] = 0;
  o[3] = 0; o[4] = sy; o[5] = 0;
  o[6] = 0; o[7] = 0; o[8] = sz;
  o[9] = ox; o[10] = oy; o[11] = oz;
  return o;
}

/** Basis(x, y, z): the three vectors are its columns. */
export function bCols(x, y, z) {
  const o = nx();
  o[0] = x[0]; o[1] = x[1]; o[2] = x[2];
  o[3] = y[0]; o[4] = y[1]; o[5] = y[2];
  o[6] = z[0]; o[7] = z[1]; o[8] = z[2];
  o[9] = 0; o[10] = 0; o[11] = 0;
  return o;
}

/** Basis * Basis (origin zero). */
export function bMul(a, b) {
  const o = nx();
  for (let c = 0; c < 9; c += 3) {
    const b0 = b[c];
    const b1 = b[c + 1];
    const b2 = b[c + 2];
    o[c] = a[0] * b0 + a[3] * b1 + a[6] * b2;
    o[c + 1] = a[1] * b0 + a[4] * b1 + a[7] * b2;
    o[c + 2] = a[2] * b0 + a[5] * b1 + a[8] * b2;
  }
  o[9] = 0; o[10] = 0; o[11] = 0;
  return o;
}

/** Basis * Basis.from_scale(Vector3(sx, sy, sz)) (origin zero). */
export function bScaled(a, sx, sy, sz) {
  const o = nx();
  const x = f(sx);
  const y = f(sy);
  const z = f(sz);
  o[0] = a[0] * x; o[1] = a[1] * x; o[2] = a[2] * x;
  o[3] = a[3] * y; o[4] = a[4] * y; o[5] = a[5] * y;
  o[6] = a[6] * z; o[7] = a[7] * z; o[8] = a[8] * z;
  o[9] = 0; o[10] = 0; o[11] = 0;
  return o;
}

/** Basis * Vector3. */
export function bXform(a, v) {
  const o = nv();
  const x = v[0];
  const y = v[1];
  const z = v[2];
  o[0] = a[0] * x + a[3] * y + a[6] * z;
  o[1] = a[1] * x + a[4] * y + a[7] * z;
  o[2] = a[2] * x + a[5] * y + a[8] * z;
  return o;
}

/** Basis * Vector3(x, y, z). */
export function bXformc(a, x, y, z) {
  const o = nv();
  const fx = f(x);
  const fy = f(y);
  const fz = f(z);
  o[0] = a[0] * fx + a[3] * fy + a[6] * fz;
  o[1] = a[1] * fx + a[4] * fy + a[7] * fz;
  o[2] = a[2] * fx + a[5] * fy + a[8] * fz;
  return o;
}

/** Transform3D * Vector3. */
export function xPoint(a, v) {
  const o = nv();
  const x = v[0];
  const y = v[1];
  const z = v[2];
  o[0] = f(a[0] * x + a[3] * y + a[6] * z) + a[9];
  o[1] = f(a[1] * x + a[4] * y + a[7] * z) + a[10];
  o[2] = f(a[2] * x + a[5] * y + a[8] * z) + a[11];
  return o;
}

/** Transform3D * Vector3(x, y, z). */
export function xPointc(a, x, y, z) {
  const o = nv();
  const fx = f(x);
  const fy = f(y);
  const fz = f(z);
  o[0] = f(a[0] * fx + a[3] * fy + a[6] * fz) + a[9];
  o[1] = f(a[1] * fx + a[4] * fy + a[7] * fz) + a[10];
  o[2] = f(a[2] * fx + a[5] * fy + a[8] * fz) + a[11];
  return o;
}

/** Transform3D(basis, origin). */
export function xOf(basis, origin) {
  const o = nx();
  for (let i = 0; i < 9; i++) o[i] = basis[i];
  o[9] = origin[0]; o[10] = origin[1]; o[11] = origin[2];
  return o;
}

/** Transform3D * Transform3D. */
export function xMul(a, b) {
  const o = nx();
  for (let c = 0; c < 9; c += 3) {
    const b0 = b[c];
    const b1 = b[c + 1];
    const b2 = b[c + 2];
    o[c] = a[0] * b0 + a[3] * b1 + a[6] * b2;
    o[c + 1] = a[1] * b0 + a[4] * b1 + a[7] * b2;
    o[c + 2] = a[2] * b0 + a[5] * b1 + a[8] * b2;
  }
  const x = b[9];
  const y = b[10];
  const z = b[11];
  o[9] = f(a[0] * x + a[3] * y + a[6] * z) + a[9];
  o[10] = f(a[1] * x + a[4] * y + a[7] * z) + a[10];
  o[11] = f(a[2] * x + a[5] * y + a[8] * z) + a[11];
  return o;
}

/** Basis.inverse() (Godot's cofactor form; origin zero). */
export function bInverse(a) {
  const o = nx();
  // rows[r][c] = a[c * 3 + r]
  const m00 = a[0], m01 = a[3], m02 = a[6];
  const m10 = a[1], m11 = a[4], m12 = a[7];
  const m20 = a[2], m21 = a[5], m22 = a[8];
  const co0 = f(f(m11 * m22) - f(m12 * m21));
  const co1 = f(f(m12 * m20) - f(m10 * m22));
  const co2 = f(f(m10 * m21) - f(m11 * m20));
  const det = f(f(f(m00 * co0) + f(m01 * co1)) + f(m02 * co2));
  const s = f(1 / det);
  // set(xx, xy, xz, yx, yy, yz, zx, zy, zz) fills the rows
  o[0] = co0 * s;
  o[3] = f(f(m02 * m21) - f(m01 * m22)) * s;
  o[6] = f(f(m01 * m12) - f(m02 * m11)) * s;
  o[1] = co1 * s;
  o[4] = f(f(m00 * m22) - f(m02 * m20)) * s;
  o[7] = f(f(m02 * m10) - f(m00 * m12)) * s;
  o[2] = co2 * s;
  o[5] = f(f(m01 * m20) - f(m00 * m21)) * s;
  o[8] = f(f(m00 * m11) - f(m01 * m10)) * s;
  o[9] = 0; o[10] = 0; o[11] = 0;
  return o;
}

/** Transform3D.affine_inverse(). */
export function xAffineInverse(a) {
  const o = bInverse(a);
  const x = -a[9];
  const y = -a[10];
  const z = -a[11];
  o[9] = o[0] * x + o[3] * y + o[6] * z;
  o[10] = o[1] * x + o[4] * y + o[7] * z;
  o[11] = o[2] * x + o[5] * y + o[8] * z;
  return o;
}

// ---------------------------------------------------------------- GDScript's scalar built-ins

export const TAU = Math.PI * 2;

export function clampf(x, a, b) { return x < a ? a : (x > b ? b : x); }

export function lerpf(a, b, t) { return a + (b - a) * t; }

/** Godot's fposmod. */
export function fposmod(x, y) {
  let v = x % y;
  if ((v < 0 && y > 0) || (v > 0 && y < 0)) v += y;
  v += 0.0;
  return v;
}

/** Godot's posmod (integers). */
export function posmod(x, y) {
  let v = x % y;
  if ((v < 0 && y > 0) || (v > 0 && y < 0)) v += y;
  return v;
}

/** Godot's angle_difference: fmod, not fposmod. */
export function angleDifference(from, to) {
  const d = (to - from) % TAU;
  return ((2.0 * d) % TAU) - d;
}

export function lerpAngle(from, to, w) { return from + angleDifference(from, to) * w; }

/** Godot's wrapf. */
export function wrapf(value, min, max) {
  const range = max - min;
  if (Math.abs(range) < 1e-5) return min;
  let result = value - range * Math.floor((value - min) / range);
  if (isEqualApprox(result, max)) return min;
  return result;
}

function isEqualApprox(a, b) {
  if (a === b) return true;
  let tol = 1e-5 * Math.abs(a);
  if (tol < 1e-5) tol = 1e-5;
  return Math.abs(a - b) < tol;
}
