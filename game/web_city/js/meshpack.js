// Reads a mesh pack (game/scripts/web/mesh_pack.gd) into a Three.js tree.
//
// Conventions, decided once here so no module has to think about them again:
// - Godot and Three.js are both Y-up and right-handed, with the camera looking down -Z. Positions and
//   transforms are used as they are.
// - Godot's front faces wind clockwise; Three.js's wind counter-clockwise. Every triangle's last two indices
//   are swapped at load, so the usual FrontSide culling matches Godot's back-face culling.
// - Vertex colours are stored as Godot keeps them (sRGB-encoded bytes). They are converted to linear floats
//   at load, which is what Three.js's colour management expects of vertex colours.
// - One material per role (base, glow, cabin, ground, puddle, pool, ...), shared by every mesh that uses it.
//   Weather and night change these materials' parameters; they are never recreated (app.materials).
import * as THREE from '../vendor/three.module.js';
import { godotEmission } from './world_logic.js';

const SRGB_TO_LINEAR = new Float32Array(256);
for (let i = 0; i < 256; i++) {
  const c = i / 255;
  SRGB_TO_LINEAR[i] = c <= 0.04045 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4);
}

/** Godot's 12-float transform (basis x, y, z columns, then origin) as a Matrix4. */
export function matrixFrom12(a, out = new THREE.Matrix4()) {
  return out.set(
    a[0], a[3], a[6], a[9],
    a[1], a[4], a[7], a[10],
    a[2], a[5], a[8], a[11],
    0, 0, 0, 1);
}

/** Sets an Object3D's position, rotation and scale from Godot's 12-float transform. */
export function applyXf(obj, a) {
  const m = matrixFrom12(a);
  m.decompose(obj.position, obj.quaternion, obj.scale);
}

/**
 * A texture from a mesh pack's optional "texture" description (mesh_pack.gd, "textures": the children's
 * packs): a GradientTexture2D drawn on a canvas, or a PNG. Null when it cannot be made here (no DOM, or
 * "missing"). Godot's UV v runs down the image, so flipY is off.
 */
export function makeTexture(t) {
  if (!t || typeof document === 'undefined') return null;
  let tex = null;
  if (t.kind === 'gradient') {
    const w = Math.max(1, t.w | 0);
    const h = Math.max(1, t.h | 0);
    const cv = document.createElement('canvas');
    cv.width = w;
    cv.height = h;
    const g2 = cv.getContext('2d');
    const [fx, fy] = [t.from[0] * w, t.from[1] * h];
    const [tx, ty] = [t.to[0] * w, t.to[1] * h];
    let grad;
    if (t.fill === 'linear') grad = g2.createLinearGradient(fx, fy, tx, ty);
    else grad = g2.createRadialGradient(fx, fy, 0, fx, fy, Math.max(1e-3, Math.hypot(tx - fx, ty - fy)));
    (t.offsets || []).forEach((o, i) => {
      const c = t.colors[i];
      const b = (x) => Math.round(Math.min(1, Math.max(0, x)) * 255);
      grad.addColorStop(Math.min(1, Math.max(0, o)), `rgba(${b(c[0])},${b(c[1])},${b(c[2])},${Math.min(1, Math.max(0, c[3]))})`);
    });
    g2.fillStyle = grad;
    g2.fillRect(0, 0, w, h);
    tex = new THREE.CanvasTexture(cv);
  } else if (t.kind === 'png' && t.png) {
    tex = new THREE.TextureLoader().load(`data:image/png;base64,${t.png}`);
  }
  if (tex) {
    tex.flipY = false;
    tex.colorSpace = THREE.SRGBColorSpace;
  }
  return tex;
}

/**
 * Sets an emissive material's glow as Godot's Compatibility renderer draws it for this energy (the material's
 * sRGB emission colour times the energy, then converted: world_logic.godotEmission). The colour is linear
 * and the intensity stays 1. Materials without an emission colour are left alone.
 */
export function setGodotEmission(mat, energy) {
  const srgb = mat && mat.userData && mat.userData.emissionSrgb;
  if (!srgb) return;
  const lin = godotEmission(srgb, energy, _emission);
  mat.emissive.setRGB(lin[0], lin[1], lin[2], THREE.LinearSRGBColorSpace);
  mat.emissiveIntensity = 1;
}
const _emission = [0, 0, 0];

/** A material for a role, from Godot's description (mesh_pack.gd Pack.describe). */
export function makeMaterial(role, d) {
  d = d || {};
  const opts = { vertexColors: !!d.vertex_color };
  const map = d.texture ? makeTexture(d.texture) : null;
  if (map) opts.map = map;
  const albedo = d.albedo || [1, 1, 1, 1];
  const color = new THREE.Color().setRGB(albedo[0], albedo[1], albedo[2], THREE.SRGBColorSpace);
  let m;
  if (d.unshaded) {
    m = new THREE.MeshBasicMaterial({ ...opts, color });
  } else {
    m = new THREE.MeshStandardMaterial({ ...opts, color, roughness: d.roughness ?? 0.92, metalness: d.metallic ?? 0 });
    if (d.emission) {
      m.userData.emissionSrgb = d.emission.slice(0, 3);
      setGodotEmission(m, d.emission_energy ?? 0);
    }
  }
  m.name = role;
  if (d.transparent) {
    m.transparent = true;
    m.opacity = albedo[3];
  }
  if (d.blend === 'add') m.blending = THREE.AdditiveBlending;
  if (d.depth_write === false) m.depthWrite = false;
  if (d.cull === 'none') m.side = THREE.DoubleSide;
  else if (d.cull === 'front') m.side = THREE.BackSide;
  return m;
}

function geometryOf(surface, buffer) {
  const g = new THREE.BufferGeometry();
  const n = surface.count;
  g.setAttribute('position', new THREE.BufferAttribute(new Float32Array(buffer, surface.pos, n * 3), 3));
  if (surface.nrm >= 0) {
    const ib = new THREE.InterleavedBuffer(new Int8Array(buffer, surface.nrm, n * 4), 4);
    g.setAttribute('normal', new THREE.InterleavedBufferAttribute(ib, 3, 0, true));
  }
  if (surface.col >= 0) {
    const src = new Uint8Array(buffer, surface.col, n * 4);
    const lin = new Float32Array(n * 4);
    for (let i = 0; i < n * 4; i += 4) {
      lin[i] = SRGB_TO_LINEAR[src[i]];
      lin[i + 1] = SRGB_TO_LINEAR[src[i + 1]];
      lin[i + 2] = SRGB_TO_LINEAR[src[i + 2]];
      lin[i + 3] = src[i + 3] / 255;
    }
    g.setAttribute('color', new THREE.BufferAttribute(lin, 4));
  }
  if (surface.uv !== undefined && surface.uv >= 0) {   // optional (mesh_pack.gd "textures")
    g.setAttribute('uv', new THREE.BufferAttribute(new Float32Array(buffer, surface.uv, n * 2), 2));
  }
  let idx;
  if (surface.idx >= 0) {
    idx = surface.i16 ? new Uint16Array(buffer, surface.idx, surface.icount) : new Uint32Array(buffer, surface.idx, surface.icount);
  } else {
    idx = n > 65535 ? new Uint32Array(n) : new Uint16Array(n);
    for (let i = 0; i < n; i++) idx[i] = i;
  }
  for (let i = 0; i + 2 < idx.length; i += 3) {   // clockwise (Godot) to counter-clockwise (Three.js)
    const t = idx[i + 1]; idx[i + 1] = idx[i + 2]; idx[i + 2] = t;
  }
  g.setIndex(new THREE.BufferAttribute(idx, 1));
  g.computeBoundingSphere();
  return g;
}

/**
 * Builds the tree. Returns {root, byPath: Map(path -> Object3D), meshes: [[{geometry, role}]],
 * materials: {role: Material}, lights: [{object, light: {...}, meta}]}.
 * `materials` may be passed in to share roles between packs (the children use the city's).
 * A pack is never edited after load: callers must not mutate geometry they did not create.
 */
export function buildPack(header, buffer, materials = {}) {
  for (const role of Object.keys(header.materials || {})) {
    if (!materials[role]) materials[role] = makeMaterial(role, header.materials[role]);
  }
  const meshes = header.meshes.map((m) => m.surfaces.map((s) => ({ geometry: geometryOf(s, buffer), role: s.material })));
  const objects = [];
  const byPath = new Map();
  const lights = [];
  let root = null;
  header.nodes.forEach((nd, i) => {
    let obj;
    if (nd.kind === 'mesh' && nd.mesh >= 0) {
      const surfaces = meshes[nd.mesh];
      if (surfaces.length === 1) {
        obj = new THREE.Mesh(surfaces[0].geometry, materials[surfaces[0].role]);
      } else {
        obj = new THREE.Group();
        surfaces.forEach((s, k) => {
          const part = new THREE.Mesh(s.geometry, materials[s.role]);
          part.name = `${nd.name}#${k}`;
          obj.add(part);
        });
      }
    } else if (nd.kind === 'multimesh' && nd.mm) {
      const surfaces = meshes[nd.mm.mesh];
      const s = surfaces[0];
      // One InstancedMesh per MultiMesh (its first surface; people's parts have one). Instances start
      // hidden (zero scale) and are the owning module's to place.
      obj = new THREE.InstancedMesh(s.geometry, materials[s.role], Math.max(1, nd.mm.count));
      obj.count = nd.mm.count;
      const zero = new THREE.Matrix4().makeScale(0, 0, 0);
      for (let k = 0; k < nd.mm.count; k++) obj.setMatrixAt(k, zero);
      obj.instanceMatrix.setUsage(THREE.DynamicDrawUsage);
      if (nd.mm.colors) {
        obj.instanceColor = new THREE.InstancedBufferAttribute(new Float32Array(Math.max(1, nd.mm.count) * 3).fill(1), 3);
        obj.instanceColor.setUsage(THREE.DynamicDrawUsage);
      }
      obj.frustumCulled = false;   // instances move anywhere; their bounds are the module's business
    } else {
      obj = new THREE.Group();
      if (nd.kind === 'light') lights.push({ object: obj, light: nd.light, meta: nd.meta || {} });
    }
    obj.name = nd.name;
    applyXf(obj, nd.xf);
    obj.visible = nd.visible !== false;
    obj.userData = { ...(nd.meta || {}), kind: nd.kind, packIndex: i };
    objects.push(obj);
    if (nd.parent >= 0) objects[nd.parent].add(obj);
    else root = obj;
    const path = nd.parent >= 0 ? `${objects[nd.parent].userData.path}/${nd.name}` : nd.name;
    obj.userData.path = path;
    byPath.set(path, obj);
  });
  return { root, byPath, meshes, materials, lights };
}

/** Fetches `<base>.json` and `<base>.bin` and builds the pack. */
export async function loadPack(base, materials = {}) {
  const [hr, br] = await Promise.all([fetch(`${base}.json`), fetch(`${base}.bin`)]);
  if (!hr.ok || !br.ok) throw new Error(`mesh pack ${base}: HTTP ${hr.status}/${br.status}`);
  const header = await hr.json();
  const buffer = await br.arrayBuffer();
  if (buffer.byteLength !== header.bytes) throw new Error(`mesh pack ${base}: ${buffer.byteLength} bytes, header says ${header.bytes}`);
  return buildPack(header, buffer, materials);
}

/** Decodes a base64 string to an ArrayBuffer (the children's packs come over the bridge). */
export function base64ToBuffer(b64) {
  const bin = atob(b64);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out.buffer;
}
