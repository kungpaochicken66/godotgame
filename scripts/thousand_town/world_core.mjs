// Thousand Town world builder, shared core (design/thousand-town.md sections 1, 2, 8; route C).
//
// - The pinned, hash-checked upstream copy and the bare vm that runs its PURE planners, exactly as
//   extract.mjs does (same commit check, same hashes, same build order). Upstream's Three.js builders are
//   never executed: the world_*.mjs modules are ports of their logic, written here.
// - The vendored three.core.js (game/web_city/vendor, r186, MIT) is used as a geometry/math library only,
//   after its SHA-256 is checked.
// - A geometry sink: everything is emitted in UPSTREAM units (so the ports read like the source) and
//   converted to metres (x 0.5) when the GLB is written.
// - A minimal, deterministic glTF 2.0 binary writer (POSITION, NORMAL, COLOR_0 linear RGBA16 normalized, optional
//   TEXCOORD_0, uint16/uint32 indices), the JSON serializer used by extract.mjs, and the solids collector.
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import { fileURLToPath, pathToFileURL } from 'node:url';

export const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
// The pinned copy lives at build/dual-host/thousand-town/upstream/ of the repository. When this script runs
// from the dual-host work copy (build/dual-host/thousand-town/work/), that folder is the work copy's sibling.
// THOUSAND_UPSTREAM overrides both.
function findUpstream() {
  const name = 'thousand-town-1332ef2';
  const candidates = [process.env.THOUSAND_UPSTREAM,
    path.join(ROOT, 'build', 'dual-host', 'thousand-town', 'upstream', name),
    path.join(ROOT, '..', 'upstream', name)].filter(Boolean);
  return candidates.find((c) => fs.existsSync(path.join(c, '.git', 'HEAD'))) || candidates[candidates.length - 1];
}
export const UPSTREAM = findUpstream();
export const DATA = path.join(ROOT, 'game', 'thousand_town', 'data');
export const COMMIT = '1332ef29d6208a4192bf7400e0085033fd773a3c';
export const S = 0.5; // metres per upstream unit (design section 1)

// The page's defaults (sketch.js:10), as extract.mjs.
export const SETTINGS = { seed: 20260818, density: 0.8, skyline: 1, speed: 1, daySpeed: 1, dreamLight: 0.7,
  stone: '#ece5d9', glass: '#8fa9ab', ground: '#d8d2c7', blenderModel: true, housingBlenderModel: true,
  playground: true, housing: true };

// Executed in the bare vm (pure planners and the embedded asset data), in index.html order. Identical to
// extract.mjs's EXEC table.
export const EXEC = [
  ['city-random.js', '441e8419826de45ee183127ef41108c944114d5aa477988ca85b05f69d393aeb'],
  ['city-model.js', '98a9b5f0c591ef375c54ebd8ee9a32759251994038ffe7847529f1047990e3a9'],
  ['assets/resident-town-runtime.min.js', '880af8b610729e46392b5eedbda92702d50fdf1a2a01f1dac0966cf796e758f4'],
  ['assets/blender-landscape.js', 'c9e57c7fb992c8d0bb220daabf688b6df5d799f011757183a5c7bed4b4438766'],
  ['assets/blender-amusement.js', '6f87a2bef9ed209c2e17c0aed75891a1e67f0f86b70e1eaf9c260d68e25416a3'],
  ['city-fountain.js', '57704231d5f2cbdad33c9199d3fcdadf6b71df548bec6055dbcb324be23baa7a'],
  ['assets/blender-district.js', '20689f5ed14d1a4cdf55c15590eb77803d902fae8d04b29dd1e9941d3cafaa47'],
  ['city-district.js', 'ea7509710467ad4671ccb7ccbea640f5716d5328ea0b2710f8fb51228ed5cfed'],
  ['assets/blender-civic.js', '3b018ed9737b1426d441e1cb2c10fccc51d183a8bedc18ed90928a0e1d73ce30'],
  ['assets/blender-hospital-room.js', '51140b0e1eb289ab03ca4c0b76bdb79fd63a81edba1740b5d43ab9f1ae5f5bc0'],
  ['city-facilities.js', '07e55c0fb704a7c874a703cf0d8b12d94caf88244d75e86a1a30c0c3cb2a42e0'],
  ['city-places.js', '84fe8a2a308b92326071656a138e89f387964b6380e0bd287d73dc19faadd03f'],
  ['city-housing-plan.js', 'b91f11b91ffcdd50adefb1667dd71b1e0543b3b1cf2eb560bf041de9a42e0572'],
  ['city-frontage.js', '208cc492911bf4be12d51e8488757ccd67d987894894dbbc9562ada53753a761'],
  ['city-layout.js', 'f11e213ee0208079fe864d8d7f75131f83181b45ec0647bb0952e85a917914b7'],
  ['assets/blender-housing.js', '0b66a60a97d56774c13b71b0e547b33ca7d1698e58a7518df11b6cbc9abfa7b8'],
  ['city-waterfront.js', '6238fdb8612ab1f55a5d28e327a506cbf1f6b45b673724b809558f0495d88480'],
  ['city-transit-motion.js', '32ea84d03640a3ced96d7e92caf15ae23e2acbdda16e2d7cdc3827ac3ba214ab'],
  ['city-helipad.js', 'bc887166dc31eceadad4f5f9ca1fc10d6afcec869aeee7c094588e98ef701dfc'],
];
// Read (and hashed) for the builder logic ported in world_*.mjs. Never executed.
export const PORTED = [
  ['assets/city-ground.runtime.min.js', '108bf59d06c69590d9f3d36999f550348472982e747f093210452ae3bece3f9a'],
  ['city-playground.js', 'bbe48283f024fea59fa80ca0c6bd364ff996063b05fe9563983b4368dea4d529'],
  ['city-housing.js', '26dedc2b44c916befb44ade2a3ad4a60eff8027a332725e7d9a0250d35e66d4e'],
  ['city-transit.js', '70cf912a7651b0614745d53e16e110fb2e1f1da1d53279535a78f7dcbdeaacbe'],
  ['city-landmarks.js', 'bda5217fcb35742e0ca991b4eb95665e390c2b9ff0f320bda7af7381dce450ad'],
  ['city-materials.js', '09a4e885687ae9d4bde7147eb3c4bc8440b72debef4ae6d5d58ca2e34048151d'],
  ['city-scene.js', '9c37166ac1c1e1da7fe7fe586660fbd83630ecf6ebf72545b13e96cd3e2254aa'], // createStreetLighting (lamp spot lights)
  ['sketch.js', 'd5162cedf2c12870b2d4e1a2566f72ffc2cdf169556cc1cc1712ccd1127bc423'],
  ['LICENSE', '9ba9550ad48438d0836ddab3da480b3b69ffa0aac7b7878b5a0039e7ab429411'],
];
// Lantern Lane files this builder reads: the vendored geometry library and W-DATA's outputs it cross-checks.
export const LOCAL = [
  ['game/web_city/vendor/three.core.js', '9edde002b066a9a05676a6127f67735b62baf399bdea529f2f7e31657da769e6'],
  ['game/thousand_town/data/town.json', '2efddfbf4061d90902d5d7dcda1423a7a27891f16fc6b821ab41059348bd849b'],
];

export function fail(message) {
  console.error('build_world: ' + message);
  process.exit(1);
}

const sha256 = (bytes) => crypto.createHash('sha256').update(bytes).digest('hex');
export { sha256 };

function checkCommit() {
  const headPath = path.join(UPSTREAM, '.git', 'HEAD');
  if (!fs.existsSync(headPath)) fail('no .git/HEAD in ' + UPSTREAM);
  let head = fs.readFileSync(headPath, 'utf8').trim();
  if (head.startsWith('ref:')) {
    const ref = head.slice(4).trim();
    const loose = path.join(UPSTREAM, '.git', ref);
    if (fs.existsSync(loose)) head = fs.readFileSync(loose, 'utf8').trim();
    else {
      const packed = path.join(UPSTREAM, '.git', 'packed-refs');
      const line = fs.existsSync(packed) && fs.readFileSync(packed, 'utf8').split('\n').find((l) => l.endsWith(' ' + ref));
      head = line ? line.split(' ')[0] : '';
    }
  }
  if (head !== COMMIT) fail('upstream copy is at ' + JSON.stringify(head) + ', expected the pinned ' + COMMIT);
}

export function readVerified(base, rel, expected) {
  const file = path.join(base, rel);
  if (!fs.existsSync(file)) fail('missing file ' + rel);
  const bytes = fs.readFileSync(file);
  const actual = sha256(bytes);
  if (expected && actual !== expected) fail('SHA-256 mismatch for ' + rel + ': ' + actual + ' (expected ' + expected + ')');
  return { bytes, sha: actual };
}

// Hash table of everything read, for the manifest and the --check.
export function hashTable() {
  const out = {};
  for (const [rel, sha] of EXEC.concat(PORTED)) out['upstream/' + rel] = sha;
  for (const [rel, sha] of LOCAL) out[rel] = sha;
  return out;
}

export function loadUpstream() {
  checkCommit();
  const sources = {};
  for (const [rel, sha] of PORTED) sources[rel] = readVerified(UPSTREAM, rel, sha).bytes.toString('utf8');
  // The bare context of extract.mjs: no require, module, process or Buffer; Math.random and Date throw.
  const ctx = { console: { log() {}, warn() {}, error() {}, info() {} }, atob: globalThis.atob };
  ctx.globalThis = ctx; ctx.window = ctx; ctx.self = ctx;
  vm.createContext(ctx);
  vm.runInContext('Math.random = function () { throw new Error("Math.random is not deterministic"); };' +
    'Date = function () { throw new Error("Date is not deterministic"); }; Date.now = Date;', ctx);
  for (const [rel, sha] of EXEC) {
    const source = readVerified(UPSTREAM, rel, sha).bytes.toString('utf8');
    sources[rel] = source;
    try { vm.runInContext(source, ctx, { filename: 'upstream/' + rel }); }
    catch (error) { fail('loading ' + rel + ' failed: ' + error.message); }
  }
  for (const api of ['CityRandom', 'CityModel', 'CityLife', 'CityFacilities', 'CityPlaces', 'CityHousingPlan',
    'CityLayout', 'CityWaterfront', 'CityFrontage', 'CityHousingAsset', 'CityLandscapeAsset']) {
    if (!ctx[api]) fail('upstream API ' + api + ' did not register');
  }
  return { ctx, sources };
}

// The page's createCity (sketch.js:133-144), as extract.mjs buildCity: identity layout, frozen end state.
export function buildCity(up) {
  const L = up.CityLayout;
  const base = up.CityModel.createCity(SETTINGS.seed, SETTINGS);
  const next = L.apply(up.CityHousingPlan.decorate(up.CityPlaces.decorate(up.CityFacilities.decorate(base)), SETTINGS),
    L.normalize(null));
  next.waterfront = { stalls: up.CityWaterfront.plan(next), civic: up.CityWaterfront.civicSite(next) };
  next.reservations.push(...next.waterfront.stalls);
  next.balloonStands = up.CityPlaces.balloonStands(next);
  next.frontage = up.CityFrontage.plan(next);
  next.reservations.push(...next.frontage.reservations);
  return next;
}

let THREE = null;
export async function loadThree() {
  if (THREE) return THREE;
  const [rel, sha] = LOCAL[0];
  readVerified(ROOT, rel, sha);
  THREE = await import(pathToFileURL(path.join(ROOT, rel)).href);
  if (THREE.REVISION !== '186') fail('unexpected three.core.js revision ' + THREE.REVISION);
  return THREE;
}

export function loadTownJson() {
  const [rel, sha] = LOCAL[1];
  return JSON.parse(readVerified(ROOT, rel, sha).bytes.toString('utf8'));
}

// ---------------------------------------------------------------------------------------------- colour

const colorCache = new Map();
// sRGB hex -> linear RGB, exactly as three's Color.set does with colour management on (what upstream's
// materials and instance colours hold). Rounded to 1e-6 so the output never depends on the last bit.
export function lin(hex) {
  if (Array.isArray(hex)) return hex;
  if (colorCache.has(hex)) return colorCache.get(hex);
  const c = new THREE.Color(hex);
  const v = [c.r, c.g, c.b].map((x) => Math.round(x * 1e6) / 1e6);
  colorCache.set(hex, v); return v;
}
export const mul = (a, b) => [a[0] * b[0], a[1] * b[1], a[2] * b[2]].map((x) => Math.round(x * 1e6) / 1e6);
// upstream "tintPart": the instance tint is target / material, so the drawn colour is the target.
export const WHITE = [1, 1, 1];

// ---------------------------------------------------------------------------------------------- materials

// Output materials. Colour lives in COLOR_0 (linear); the material carries only the surface response.
// Emissive groups carry COLOR_0 = their emission colour; Godot drives their energy by the clock.
export const MATERIALS = {
  tt_matte: { roughness: 0.92, metallic: 0, note: 'paving, roads, stone, grass, timber, markings, foliage' },
  tt_paint: { roughness: 0.66, metallic: 0.06, note: 'painted walls, cabins, awnings, signs' },
  tt_metal: { roughness: 0.46, metallic: 0.5, note: 'street furniture, frames, rails' },
  tt_glass: { roughness: 0.22, metallic: 0.14, note: 'glazing (opaque, tinted)' },
  tt_lamp: { roughness: 0.5, metallic: 0, emissive: '#ffd6a0', night: true,
    note: 'street lamp heads, lawn and plaza lamp heads: emission 0 by day, on with the lamps factor' },
  tt_fixture: { roughness: 0.48, metallic: 0.1, emissive: '#ffd29b', night: false,
    note: 'light strips, coloured lanterns, signs light boxes, canopy strips: 0.15 + 1.3 x lamps (ground-ice-light)' },
  tt_window: { roughness: 0.72, metallic: 0, emissive: '#ffd69a', night: true, windows: true,
    note: 'window light panes: TEXCOORD_0.x is the pane rank; a pane is lit when rank < the building light level' },
  tt_sign: { roughness: 0.6, metallic: 0, emissive: '#ffffff', night: true,
    note: 'pictogram faces: lit softly at night (emission = COLOR_0 x 0.35 x lamps)' },
};

// ---------------------------------------------------------------------------------------------- mesh sink

export class MeshData {
  constructor(uv) { this.pos = []; this.nrm = []; this.col = []; this.uv = uv ? [] : null; this.idx = []; }
  get vertexCount() { return this.pos.length / 3; }
  get triangleCount() { return this.idx.length / 3; }
}

export class Node {
  constructor(name) {
    this.name = name; this.surfaces = new Map(); this.children = [];
    this.translation = null; this.rotation = null; // metres; quaternion [x,y,z,w]
    this.origin = [0, 0, 0]; // upstream units subtracted from every vertex (the node's local origin)
    this.meshRef = null;     // share another node's mesh (instanced cabins)
  }
  surface(mat, uv) {
    if (!MATERIALS[mat]) fail('unknown material ' + mat);
    if (!this.surfaces.has(mat)) this.surfaces.set(mat, new MeshData(uv || !!MATERIALS[mat].windows));
    return this.surfaces.get(mat);
  }
  add(child) { this.children.push(child); return child; }
}

export class SceneFile {
  constructor(name) { this.name = name; this.roots = []; this.byName = new Map(); }
  node(name, parent) {
    if (this.byName.has(name)) return this.byName.get(name);
    if (!/^[A-Za-z0-9_]+$/.test(name)) fail('bad node name ' + name);
    const n = new Node(name);
    this.byName.set(name, n);
    (parent ? parent.children : this.roots).push(n);
    return n;
  }
  allNodes() {
    const out = [];
    const walk = (n) => { out.push(n); n.children.forEach(walk); };
    this.roots.forEach(walk); return out;
  }
}

// The chunk grid for the street layer (upstream units): avenues at x +-96 and the canal at 0 split the
// board into four columns; four rows of 129 units. 16 chunks of about 47 x 64 m.
export const CHUNK_X = [-190, -96, 0, 96, 190];
export const CHUNK_Z = [-258, -129, 0, 129, 258];
export function chunkOf(x, z) {
  let ix = 0, iz = 0;
  while (ix < CHUNK_X.length - 2 && x >= CHUNK_X[ix + 1]) ix++;
  while (iz < CHUNK_Z.length - 2 && z >= CHUNK_Z[iz + 1]) iz++;
  return [ix, iz];
}

// Unit-box faces: +x, -x, +y, -y, +z, -z (three's BoxGeometry order), as corner lists (CCW seen from outside).
const FACES = [
  { n: [1, 0, 0], v: [[1, -1, 1], [1, -1, -1], [1, 1, -1], [1, 1, 1]] },
  { n: [-1, 0, 0], v: [[-1, -1, -1], [-1, -1, 1], [-1, 1, 1], [-1, 1, -1]] },
  { n: [0, 1, 0], v: [[-1, 1, 1], [1, 1, 1], [1, 1, -1], [-1, 1, -1]] },
  { n: [0, -1, 0], v: [[-1, -1, -1], [1, -1, -1], [1, -1, 1], [-1, -1, 1]] },
  { n: [0, 0, 1], v: [[-1, -1, 1], [1, -1, 1], [1, 1, 1], [-1, 1, 1]] },
  { n: [0, 0, -1], v: [[1, -1, -1], [-1, -1, -1], [-1, 1, -1], [1, 1, -1]] },
];

function rotate(q, v) {
  if (!q) return v;
  const [x, y, z, w] = q;
  const ix = w * v[0] + y * v[2] - z * v[1], iy = w * v[1] + z * v[0] - x * v[2];
  const iz = w * v[2] + x * v[1] - y * v[0], iw = -x * v[0] - y * v[1] - z * v[2];
  return [ix * w + iw * -x + iy * -z - iz * -y, iy * w + iw * -y + iz * -x - ix * -z, iz * w + iw * -z + ix * -y - iy * -x];
}
export const yawQuat = (a) => (a ? [0, Math.sin(a / 2), 0, Math.cos(a / 2)] : null);

// The emitter. Every builder emits through one of these; `target` resolves the node for a position so the
// same port code can write chunked (ground) or per-building (facility) geometry.
export class Emitter {
  constructor(file, target, stats) {
    this.file = file; this.target = target; this.stats = stats;
    this.items = null; // solids collection (see beginItem)
    this.split = false; // split axis-aligned boxes at chunk lines (chunked targets)
    this.matrix = null; // optional THREE.Matrix4 applied to everything (site groups)
    this.yawFrame = null; // {x, z, yaw}: a site group's frame for boxes (keeps boxes analytic)
  }
  node(x, z) { return typeof this.target === 'function' ? this.target(x, z) : this.target; }

  // An oriented box: centre (cx, cy, cz), full size (w, h, d), optional quaternion, linear colour.
  // `faces` is a 6-bit mask of faces to keep; the bottom face is dropped for boxes resting on the ground.
  box(mat, cx, cy, cz, w, h, d, color, quat, opts) {
    if (!(w > 0 && h > 0 && d > 0)) return;
    if (this.yawFrame) {
      const f = this.yawFrame, c = Math.cos(f.yaw), s = Math.sin(f.yaw);
      const wx = f.x + cx * c + cz * s, wz = f.z - cx * s + cz * c;
      const q0 = yawQuat(f.yaw);
      quat = quat && q0 ? quatMul(q0, quat) : (quat || q0); cx = wx; cz = wz; cy += f.y || 0;
    }
    if (this.split && !quat) {
      const xs = cutLines(cx - w / 2, cx + w / 2, CHUNK_X), zs = cutLines(cz - d / 2, cz + d / 2, CHUNK_Z);
      if (xs.length > 2 || zs.length > 2) {
        for (let i = 0; i + 1 < xs.length; i++) for (let k = 0; k + 1 < zs.length; k++) {
          let mask = 63;
          if (i > 0) mask &= ~2; if (i + 2 < xs.length) mask &= ~1;
          if (k > 0) mask &= ~32; if (k + 2 < zs.length) mask &= ~16;
          this._box(mat, (xs[i] + xs[i + 1]) / 2, cy, (zs[k] + zs[k + 1]) / 2, xs[i + 1] - xs[i], h, zs[k + 1] - zs[k], color, null, mask, opts);
        }
        return;
      }
    }
    this._box(mat, cx, cy, cz, w, h, d, color, quat, 63, opts);
  }
  // A box keeping only the listed faces (0 +x, 1 -x, 2 +y, 3 -y, 4 +z, 5 -z, in the box's own frame).
  emitMasked(mat, cx, cy, cz, w, h, d, color, quat, keep, opts) {
    let mask = 0; keep.forEach((f) => { mask |= 1 << f; });
    this._box(mat, cx, cy, cz, w, h, d, color, quat, mask, Object.assign({ keepBottom: true }, opts || {}));
  }
  _box(mat, cx, cy, cz, w, h, d, color, quat, mask, opts) {
    const bottom = cy - h / 2;
    if (!quat && bottom <= 0.6 && !(opts && opts.keepBottom)) mask &= ~8;
    const node = (opts && opts.node) || this.node(cx, cz);
    const m = node.surface(mat, opts && opts.uv !== undefined);
    const o = node.origin;
    FACES.forEach((face, fi) => {
      if (!(mask & (1 << fi))) return;
      const base = m.vertexCount;
      const n = rotate(quat, face.n);
      for (const c of face.v) {
        const p = rotate(quat, [c[0] * w / 2, c[1] * h / 2, c[2] * d / 2]);
        m.pos.push(cx + p[0] - o[0], cy + p[1] - o[1], cz + p[2] - o[2]);
        m.nrm.push(n[0], n[1], n[2]); m.col.push(color[0], color[1], color[2]);
        if (m.uv) m.uv.push(opts && opts.uv !== undefined ? opts.uv[0] : 0, opts && opts.uv !== undefined ? opts.uv[1] : 0);
      }
      m.idx.push(base, base + 1, base + 2, base, base + 2, base + 3);
    });
    if (this.items) this.items.record(cx, cy, cz, w, h, d, quat);
  }
  // A THREE BufferGeometry under a Matrix4 (upstream units), with one colour or its own vertex colours.
  geometry(mat, geometry, matrix, color, opts) {
    const T = THREE;
    let full = matrix;
    if (this.yawFrame) {
      const f = this.yawFrame;
      const frame = new T.Matrix4().compose(new T.Vector3(f.x, f.y || 0, f.z), new T.Quaternion().setFromAxisAngle(new T.Vector3(0, 1, 0), f.yaw), new T.Vector3(1, 1, 1));
      full = frame.multiply(matrix.clone());
    }
    const pos = geometry.getAttribute('position'), nrmA = geometry.getAttribute('normal'), colA = geometry.getAttribute('color');
    const index = geometry.index;
    const nm = new T.Matrix3().getNormalMatrix(full);
    const v = new T.Vector3(), n = new T.Vector3();
    v.set(0, 0, 0).applyMatrix4(full);
    const node = (opts && opts.node) || this.node(v.x, v.z);
    const m = node.surface(mat, opts && opts.uv !== undefined);
    const o = node.origin, base = m.vertexCount;
    const flip = full.determinant() < 0;
    for (let i = 0; i < pos.count; i++) {
      v.fromBufferAttribute(pos, i).applyMatrix4(full);
      m.pos.push(v.x - o[0], v.y - o[1], v.z - o[2]);
      if (nrmA) { n.fromBufferAttribute(nrmA, i).applyMatrix3(nm).normalize(); m.nrm.push(n.x, n.y, n.z); }
      else m.nrm.push(0, 1, 0);
      if (colA && (!color || (opts && opts.tintVertex))) {
        const c = [colA.getX(i), colA.getY(i), colA.getZ(i)];
        const t = color || WHITE;
        m.col.push(c[0] * t[0], c[1] * t[1], c[2] * t[2]);
      } else m.col.push(color[0], color[1], color[2]);
      if (m.uv) m.uv.push(opts && opts.uv !== undefined ? opts.uv[0] : 0, opts && opts.uv !== undefined ? opts.uv[1] : 0);
    }
    const count = index ? index.count : pos.count;
    for (let i = 0; i < count; i += 3) {
      const a = index ? index.getX(i) : i, b = index ? index.getX(i + 1) : i + 1, c = index ? index.getX(i + 2) : i + 2;
      if (flip) m.idx.push(base + a, base + c, base + b); else m.idx.push(base + a, base + b, base + c);
    }
    if (this.items) {
      geometry.computeBoundingBox();
      const bb = geometry.boundingBox.clone().applyMatrix4(full);
      this.items.record((bb.min.x + bb.max.x) / 2, (bb.min.y + bb.max.y) / 2, (bb.min.z + bb.max.z) / 2,
        bb.max.x - bb.min.x, bb.max.y - bb.min.y, bb.max.z - bb.min.z, null);
    }
  }
  // Flat triangles (non-indexed list of [x,y,z] points) with flat normals, one colour.
  triangles(mat, points, color, opts) {
    let cx = 0, cz = 0;
    points.forEach((p) => { cx += p[0]; cz += p[2]; });
    const node = (opts && opts.node) || this.node(cx / points.length, cz / points.length);
    const m = node.surface(mat, opts && opts.uv !== undefined), o = node.origin;
    for (let i = 0; i + 2 < points.length; i += 3) {
      const a = points[i], b = points[i + 1], c = points[i + 2];
      const u = [b[0] - a[0], b[1] - a[1], b[2] - a[2]], w = [c[0] - a[0], c[1] - a[1], c[2] - a[2]];
      let n = [u[1] * w[2] - u[2] * w[1], u[2] * w[0] - u[0] * w[2], u[0] * w[1] - u[1] * w[0]];
      const len = Math.hypot(n[0], n[1], n[2]);
      if (len < 1e-12) continue;
      n = n.map((x) => x / len);
      const base = m.vertexCount;
      for (const p of [a, b, c]) {
        m.pos.push(p[0] - o[0], p[1] - o[1], p[2] - o[2]); m.nrm.push(n[0], n[1], n[2]); m.col.push(color[0], color[1], color[2]);
        if (m.uv) m.uv.push(opts && opts.uv ? opts.uv[0] : 0, opts && opts.uv ? opts.uv[1] : 0);
      }
      m.idx.push(base, base + 1, base + 2);
    }
  }
}

export function quatMul(a, b) {
  const [ax, ay, az, aw] = a, [bx, by, bz, bw] = b;
  return [ax * bw + aw * bx + ay * bz - az * by, ay * bw + aw * by + az * bx - ax * bz,
    az * bw + aw * bz + ax * by - ay * bx, aw * bw - ax * bx - ay * by - az * bz];
}

function cutLines(a, b, lines) {
  const out = [a];
  for (const l of lines) if (l > a + 1e-6 && l < b - 1e-6) out.push(l);
  out.push(b); return out;
}

// ---------------------------------------------------------------------------------------------- solids

// Collects the boxes of one solid item and reduces them to footprints: the boxes that occupy the walking
// band (from `base` + 0.5 to `base` + 3.6 upstream units, i.e. 0.25 m to 1.8 m above the item's own
// ground) are clustered by XZ overlap; each cluster becomes one rectangle (or one oriented quad for a
// single turned box).
export class ItemCollector {
  constructor() { this.items = []; this.current = null; }
  begin(kind, id, base, extra) { this.current = { kind, id, base: base || 0, boxes: [], extra: extra || null }; }
  pause() { this._paused = this.current; this.current = null; }
  resume() { this.current = this._paused; this._paused = null; }
  record(cx, cy, cz, w, h, d, quat) {
    const it = this.current;
    if (!it) return;
    const bottom = cy - h / 2, top = cy + h / 2;
    if (top < it.base + 0.5 || bottom > it.base + 3.6) return;
    let corners;
    if (quat && Math.abs(quat[0]) < 1e-9 && Math.abs(quat[2]) < 1e-9) {
      const yaw = 2 * Math.atan2(quat[1], quat[3]);
      const c = Math.cos(yaw), s = Math.sin(yaw);
      corners = [[-1, -1], [1, -1], [1, 1], [-1, 1]].map(([u, v]) => [cx + (u * w / 2) * c + (v * d / 2) * s, cz - (u * w / 2) * s + (v * d / 2) * c]);
    } else if (quat) {
      // A tilted box: its XZ bounds.
      const pts = [];
      for (const sx of [-1, 1]) for (const sy of [-1, 1]) for (const sz of [-1, 1]) {
        const p = rotate(quat, [sx * w / 2, sy * h / 2, sz * d / 2]); pts.push([cx + p[0], cz + p[2]]);
      }
      const xs = pts.map((p) => p[0]), zs = pts.map((p) => p[1]);
      const x0 = Math.min(...xs), x1 = Math.max(...xs), z0 = Math.min(...zs), z1 = Math.max(...zs);
      corners = [[x0, z0], [x1, z0], [x1, z1], [x0, z1]];
    } else corners = [[cx - w / 2, cz - d / 2], [cx + w / 2, cz - d / 2], [cx + w / 2, cz + d / 2], [cx - w / 2, cz + d / 2]];
    it.boxes.push({ corners, bottom, top, turned: !!quat });
  }
  end() {
    const it = this.current; this.current = null;
    if (!it || !it.boxes.length) return;
    const bb = it.boxes.map((b) => {
      const xs = b.corners.map((p) => p[0]), zs = b.corners.map((p) => p[1]);
      return { ...b, x0: Math.min(...xs), x1: Math.max(...xs), z0: Math.min(...zs), z1: Math.max(...zs) };
    });
    // Union-find on overlapping (or touching within 0.15 units) XZ bounds.
    const parent = bb.map((_, i) => i);
    const find = (i) => (parent[i] === i ? i : (parent[i] = find(parent[i])));
    for (let i = 0; i < bb.length; i++) for (let k = i + 1; k < bb.length; k++) {
      const a = bb[i], b = bb[k];
      if (a.x0 <= b.x1 + 0.15 && b.x0 <= a.x1 + 0.15 && a.z0 <= b.z1 + 0.15 && b.z0 <= a.z1 + 0.15) parent[find(i)] = find(k);
    }
    const groups = new Map();
    bb.forEach((b, i) => { const r = find(i); if (!groups.has(r)) groups.set(r, []); groups.get(r).push(b); });
    let part = 0;
    for (const members of [...groups.values()].sort((a, b) => a[0].x0 - b[0].x0 || a[0].z0 - b[0].z0)) {
      const solid = { kind: it.kind, id: it.id + (groups.size > 1 ? '#' + part : ''), bottom: Math.min(...members.map((b) => b.bottom)),
        top: Math.max(...members.map((b) => b.top)) };
      part++;
      if (members.length === 1 && members[0].turned) solid.poly = members[0].corners;
      else {
        const x0 = Math.min(...members.map((b) => b.x0)), x1 = Math.max(...members.map((b) => b.x1));
        const z0 = Math.min(...members.map((b) => b.z0)), z1 = Math.max(...members.map((b) => b.z1));
        solid.rect = { x: (x0 + x1) / 2, z: (z0 + z1) / 2, w: x1 - x0, d: z1 - z0 };
      }
      if (it.extra) Object.assign(solid, it.extra);
      this.items.push(solid);
    }
  }
}

// ---------------------------------------------------------------------------------------------- GLB

function pad4(buf, fill) {
  const extra = (4 - (buf.length % 4)) % 4;
  return extra ? Buffer.concat([buf, Buffer.alloc(extra, fill)]) : buf;
}
function packGlb(json, bin) {
  const jsonBuf = pad4(Buffer.from(JSON.stringify(json), 'utf8'), 0x20);
  const binBuf = pad4(bin, 0);
  const header = Buffer.alloc(12);
  header.writeUInt32LE(0x46546c67, 0); header.writeUInt32LE(2, 4);
  header.writeUInt32LE(12 + 8 + jsonBuf.length + (binBuf.length ? 8 + binBuf.length : 0), 8);
  const jh = Buffer.alloc(8); jh.writeUInt32LE(jsonBuf.length, 0); jh.writeUInt32LE(0x4e4f534a, 4);
  const parts = [header, jh, jsonBuf];
  if (binBuf.length) { const bh = Buffer.alloc(8); bh.writeUInt32LE(binBuf.length, 0); bh.writeUInt32LE(0x004e4942, 4); parts.push(bh, binBuf); }
  return Buffer.concat(parts);
}

export const COPYRIGHT = '仪绘士 / YiHuiShiBY, "千人小镇 · Thousand Town" (github.com/YiHuiShiBY/thousand-town @ 1332ef2), CC BY 4.0; ' +
  'geometry ported from its Three.js builders to metres for Lantern Lane by scripts/thousand_town/build_world.mjs';

const r6 = (x) => Math.round(x * 1e6) / 1e6;

// Writes a SceneFile as GLB. Positions are converted to metres (x S) and rounded to float32; colours,
// normals and UVs are float32. Returns { glb, stats }.
// Merge a node's surfaces whose materials map to the same output material (`remap`: {from: to}); the
// per-file remaps trade a little surface variety for draw calls (design section 8).
function mergeSurfaces(node, remap) {
  if (!remap) return;
  for (const [from, to] of Object.entries(remap)) {
    const a = node.surfaces.get(from);
    if (!a || !a.idx.length) continue;
    const b = node.surface(to);
    const base = b.vertexCount;
    for (const v of a.pos) b.pos.push(v);
    for (const v of a.nrm) b.nrm.push(v);
    for (const v of a.col) b.col.push(v);
    if (b.uv) { if (a.uv) for (const v of a.uv) b.uv.push(v); else for (let i = 0; i < a.vertexCount; i++) b.uv.push(0, 0); }
    for (const i of a.idx) b.idx.push(base + i);
    node.surfaces.delete(from);
  }
}

export function writeGlb(file) {
  if (file.remap) file.allNodes().forEach((n) => mergeSurfaces(n, file.remap));
  const views = [], accessors = [], meshes = [], nodes = [], chunks = [];
  const matNames = Object.keys(MATERIALS);
  const usedMats = new Set();
  let offset = 0;
  const addView = (buf, target) => {
    views.push({ buffer: 0, byteOffset: offset, byteLength: buf.length, target });
    const padded = pad4(buf, 0); chunks.push(padded); offset += padded.length;
    return views.length - 1;
  };
  const stats = { nodes: 0, meshNodes: 0, surfaces: 0, triangles: 0, vertices: 0, byMaterial: {} };
  const meshIndexOf = new Map();
  const writeMesh = (node) => {
    const prims = [];
    for (const mat of matNames) {
      if (!node.surfaces.has(mat)) continue;
      const m = node.surfaces.get(mat);
      if (!m.idx.length) continue;
      usedMats.add(mat);
      const count = m.vertexCount;
      const pos = new Float32Array(m.pos.length);
      for (let i = 0; i < m.pos.length; i++) pos[i] = Math.fround(r6(m.pos[i] * S));
      const min = [Infinity, Infinity, Infinity], max = [-Infinity, -Infinity, -Infinity];
      for (let i = 0; i < count; i++) for (let k = 0; k < 3; k++) { min[k] = Math.min(min[k], pos[i * 3 + k]); max[k] = Math.max(max[k], pos[i * 3 + k]); }
      const nrm = new Float32Array(m.nrm.map(r6));
      // COLOR_0 as normalized unsigned short RGBA (core glTF, the layout Blender exports): linear, alpha 1.
      const col = new Uint16Array(count * 4);
      for (let i = 0; i < count; i++) {
        for (let k = 0; k < 3; k++) col[i * 4 + k] = Math.round(Math.max(0, Math.min(1, m.col[i * 3 + k])) * 65535);
        col[i * 4 + 3] = 65535;
      }
      const attributes = {
        POSITION: accessors.push({ bufferView: addView(Buffer.from(pos.buffer), 34962), componentType: 5126, count, type: 'VEC3', min, max }) - 1,
        NORMAL: accessors.push({ bufferView: addView(Buffer.from(nrm.buffer), 34962), componentType: 5126, count, type: 'VEC3' }) - 1,
        COLOR_0: accessors.push({ bufferView: addView(Buffer.from(col.buffer), 34962), componentType: 5123, normalized: true, count, type: 'VEC4' }) - 1,
      };
      if (m.uv) {
        const uv = new Float32Array(m.uv.map(r6));
        attributes.TEXCOORD_0 = accessors.push({ bufferView: addView(Buffer.from(uv.buffer), 34962), componentType: 5126, count, type: 'VEC2' }) - 1;
      }
      const big = count > 65535;
      const idx = big ? new Uint32Array(m.idx) : new Uint16Array(m.idx);
      const indices = accessors.push({ bufferView: addView(Buffer.from(idx.buffer), 34963), componentType: big ? 5125 : 5123, count: m.idx.length, type: 'SCALAR' }) - 1;
      prims.push({ attributes, indices, material: matNames.indexOf(mat), mode: 4 });
      stats.surfaces++; stats.triangles += m.triangleCount; stats.vertices += count;
      stats.byMaterial[mat] = (stats.byMaterial[mat] || 0) + m.triangleCount;
    }
    if (!prims.length) return -1;
    meshes.push({ name: node.name, primitives: prims });
    return meshes.length - 1;
  };
  const writeNode = (node) => {
    const out = { name: node.name };
    stats.nodes++;
    if (node.translation) out.translation = node.translation.map((v) => Math.fround(r6(v)));
    if (node.rotation) out.rotation = node.rotation.map((v) => r6(v));
    let mi = -1;
    if (node.meshRef) { mi = meshIndexOf.get(node.meshRef); if (mi === undefined) fail('mesh reference before its owner: ' + node.name); }
    else { mi = writeMesh(node); meshIndexOf.set(node, mi); }
    if (mi >= 0) {
      out.mesh = mi; stats.meshNodes++;
      if (node.meshRef) { const ref = node.meshRef; for (const [mat, m] of ref.surfaces) if (m.idx.length) { stats.surfaces++; stats.triangles += m.triangleCount; } }
    }
    const index = nodes.push(out) - 1;
    const kids = node.children.map(writeNode);
    if (kids.length) out.children = kids;
    return index;
  };
  const rootIdx = file.roots.map(writeNode);
  // Materials: keep the full table in a fixed order so indices are stable across files.
  const materials = matNames.map((name) => {
    const def = MATERIALS[name];
    const mat = { name, pbrMetallicRoughness: { baseColorFactor: [1, 1, 1, 1], metallicFactor: def.metallic, roughnessFactor: def.roughness } };
    if (def.emissive) mat.emissiveFactor = lin(def.emissive);
    return mat;
  });
  const json = {
    asset: { version: '2.0', generator: 'Lantern Lane scripts/thousand_town/build_world.mjs', copyright: COPYRIGHT,
      extras: { units: 'metres (upstream x 0.5)', vertex_colors: 'linear; materials are white, COLOR_0 carries the colour' } },
    scene: 0, scenes: [{ name: file.name, nodes: rootIdx }], nodes, meshes, materials,
    accessors, bufferViews: views, buffers: [{ byteLength: offset }],
  };
  stats.materialsUsed = [...usedMats];
  return { glb: packGlb(json, Buffer.concat(chunks)), stats };
}

// ---------------------------------------------------------------------------------------------- JSON

function num(v) {
  if (!Number.isFinite(v)) fail('non-finite number in output');
  if (Number.isInteger(v)) return String(v);
  let r = Math.round(v * 1e4) / 1e4;
  if (Object.is(r, -0)) r = 0;
  return String(r);
}
function isFlat(v) {
  const flat = (x) => x === null || typeof x !== 'object' || (Array.isArray(x) && x.every((y) => typeof y !== 'object' || y === null));
  return Array.isArray(v) ? v.every(flat) : Object.values(v).every(flat);
}
// extract.mjs's serializer: sorted keys, 4-decimal numbers, flat values on one line.
export function ser(v, indent = '') {
  if (v === null) return 'null';
  if (typeof v === 'number') return num(v);
  if (typeof v === 'boolean') return v ? 'true' : 'false';
  if (typeof v === 'string') return JSON.stringify(v);
  const inner = indent + ' ';
  if (Array.isArray(v)) {
    if (!v.length) return '[]';
    if (isFlat(v)) return '[' + v.map((x) => ser(x, inner)).join(',') + ']';
    return '[\n' + v.map((x) => inner + ser(x, inner)).join(',\n') + '\n' + indent + ']';
  }
  const keys = Object.keys(v).filter((k) => v[k] !== undefined).sort();
  if (!keys.length) return '{}';
  if (isFlat(v)) return '{' + keys.map((k) => JSON.stringify(k) + ':' + ser(v[k], inner)).join(',') + '}';
  return '{\n' + keys.map((k) => inner + JSON.stringify(k) + ': ' + ser(v[k], inner)).join(',\n') + '\n' + indent + '}';
}

// Upstream-unit helpers.
export const M = (v) => v * S;
export const hr = (e) => { e = Math.max(0, Math.min(1, e)); return e * e * (3 - 2 * e); };
export const overlaps = (a, b, gap) => Math.abs(a.x - b.x) < (a.w + b.w) / 2 + gap && Math.abs(a.z - b.z) < (a.d + b.d) / 2 + gap;
