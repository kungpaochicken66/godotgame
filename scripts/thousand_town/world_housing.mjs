// Port of upstream's housing floor detail: city-housing.js `create` (lines 104-410) with its Blender
// modules (`load`, lines 14-60, here decoded from the embedded GLB of assets/blender-housing.js, which the
// vm loads as data). Upstream takes the refined path (`canRefine`) for all four default blocks, so this port
// does too and fails if a block's wings stop matching the asset's types.
//
// Per block: `Housing_<id>` (plinths, garden, every floor module, every roof module, merged), with
//   `<node>_Windows`  one lit pane per window (material tt_window; TEXCOORD_0.x is upstream's `windowRank`,
//                     a pane is lit when rank < the block's light level, refreshLights),
//   `<node>_Door<k>`  each entrance leaf (panel and glazing together), origin at the hinge, swing +1.45 rad.
// Doors are raised from upstream's 3.6 units (1.8 m) to 4.2 (2.1 m, design section 1).
import zlib from 'node:zlib';
import { lin, fail } from './world_core.mjs';

const BASE = 1.4, FLOOR = 6, DOOR_UNITS = 4.2;

// Minimal glTF reader for the embedded housing GLB: each named module node's primitives merged, with the
// material colour baked in as a vertex colour (city-housing.js load(): colour = material.color x COLOR_0).
export function readGlbModules(T, buf) {
  if (buf.readUInt32LE(0) !== 0x46546c67) fail('housing asset is not a GLB');
  let at = 12, json = null, bin = null;
  while (at < buf.length) {
    const len = buf.readUInt32LE(at), type = buf.readUInt32LE(at + 4), chunk = buf.subarray(at + 8, at + 8 + len);
    if (type === 0x4e4f534a) json = JSON.parse(chunk.toString('utf8')); else if (type === 0x004e4942) bin = chunk;
    at += 8 + len;
  }
  const read = (index) => {
    const acc = json.accessors[index], view = json.bufferViews[acc.bufferView];
    const comps = { SCALAR: 1, VEC2: 2, VEC3: 3, VEC4: 4 }[acc.type];
    const base = (view.byteOffset || 0) + (acc.byteOffset || 0), stride = view.byteStride || 0;
    const out = [];
    const size = { 5126: 4, 5125: 4, 5123: 2, 5121: 1 }[acc.componentType];
    for (let i = 0; i < acc.count; i++) for (let k = 0; k < comps; k++) {
      const off = base + i * (stride || comps * size) + k * size;
      out.push(acc.componentType === 5126 ? bin.readFloatLE(off) : acc.componentType === 5125 ? bin.readUInt32LE(off) : acc.componentType === 5123 ? bin.readUInt16LE(off) : bin.readUInt8(off));
    }
    return out;
  };
  const modules = {};
  for (const node of json.nodes) {
    if (node.mesh === undefined) continue;
    if (node.translation || node.rotation || node.scale || node.matrix) {
      // Module nodes are authored at the origin; a transform here would change their frame.
      const t = node.translation || [0, 0, 0];
      if (node.rotation || node.scale || node.matrix || t.some((v) => Math.abs(v) > 1e-9)) fail('housing module ' + node.name + ' is not at the origin');
    }
    const pos = [], nrm = [], col = [], idx = [];
    for (const prim of json.meshes[node.mesh].primitives) {
      const p = read(prim.attributes.POSITION), n = read(prim.attributes.NORMAL);
      const c = prim.attributes.COLOR_0 !== undefined ? read(prim.attributes.COLOR_0) : null;
      const factor = (json.materials[prim.material].pbrMetallicRoughness || {}).baseColorFactor || [1, 1, 1, 1];
      const base = pos.length / 3, count = p.length / 3;
      for (let i = 0; i < count; i++) {
        pos.push(p[i * 3], p[i * 3 + 1], p[i * 3 + 2]); nrm.push(n[i * 3], n[i * 3 + 1], n[i * 3 + 2]);
        const cc = c ? [c[i * (c.length / count)], c[i * (c.length / count) + 1], c[i * (c.length / count) + 2]] : [1, 1, 1];
        col.push(factor[0] * cc[0], factor[1] * cc[1], factor[2] * cc[2]);
      }
      const ii = prim.indices !== undefined ? read(prim.indices) : [...Array(count).keys()];
      ii.forEach((v) => idx.push(base + v));
    }
    const g = new T.BufferGeometry();
    g.setAttribute('position', new T.Float32BufferAttribute(pos, 3)); g.setAttribute('normal', new T.Float32BufferAttribute(nrm, 3));
    g.setAttribute('color', new T.Float32BufferAttribute(col, 3)); g.setIndex(idx);
    modules[node.name.replace(/^Housing_/, '')] = g;
  }
  return modules;
}

export function buildHousing(env) {
  const { T, city, ctx, file, makeEmitter, solids, counts, world } = env;
  const asset = ctx.CityHousingAsset;
  const raw = zlib.gunzipSync(Buffer.from(asset.base64, 'base64'));
  const shapes = readGlbModules(T, raw);
  for (const m of asset.meta.modules) {
    if (!shapes[m.name]) fail('housing module missing: ' + m.name);
    if (shapes[m.name].index.count / 3 !== m.triangles) fail('housing module ' + m.name + ' triangle count differs from the manifest');
  }
  const leafGeo = new T.IcosahedronGeometry(1, 1), tankGeo = new T.CylinderGeometry(1, 1, 1, 12);
  const ROLE = { wall: 'tt_matte', trim: 'tt_matte', accent: 'tt_matte', dark: 'tt_matte', glass: 'tt_glass', lit: 'tt_window',
    metal: 'tt_metal', green: 'tt_matte', wood: 'tt_paint', solar: 'tt_metal', refined: 'tt_matte' };
  const features = { windows: 0, balconies: 0, entrances: 0, stairCores: 0, planters: 0, courtyardTrees: 0, solarPanels: 0, dryingRacks: 0, waterTanks: 0 };
  // `paletteFor` and `detailsFor` (87-102).
  const paletteFor = (b) => {
    const type = b.housing.type;
    return Object.assign({}, b.housing.palette, { wall: type === 'slab' ? '#e3e6d9' : type === 'point' ? '#e1dacc' : '#ece5d9', trim: '#d2c6b4',
      accent: type === 'slab' ? '#7f8c75' : '#b48b74', glass: '#8fa9ab', dark: '#465657', metal: '#718078', green: '#7d906f', wood: '#a58460', solar: '#46616a' });
  };
  const detailsFor = (b) => {
    const type = b.housing.type, court = type === 'courtyard', slab = type === 'slab', point = type === 'point';
    return { band: court ? 0.06 : slab ? 0.22 : point ? 0.08 : 0.12, bandHeight: court ? 0.08 : 0.1, frame: court ? 0.26 : 0.22,
      core: court ? 'wood' : slab ? 'accent' : point ? 'metal' : 'trim', cheek: court ? 'wood' : point ? 'metal' : 'trim',
      canopy: court ? 'wood' : slab ? 'trim' : 'metal', canopyWidth: court ? 4.05 : slab ? 4.6 : point ? 3.2 : 3.6,
      parapet: court ? 0.42 : slab ? 0.6 : point ? 0.7 : 0.9, roofRole: court ? 'wood' : point ? 'metal' : 'trim' };
  };
  // `windowRank` (77-81): FNV-1a of the window's identity.
  const windowRank = (b, v, floor, axis, sign, col) => {
    const key = [b.id, v.x, v.z, floor, axis, sign, col].join(':'); let hash = 2166136261;
    for (let i = 0; i < key.length; i++) hash = Math.imul(hash ^ key.charCodeAt(i), 16777619);
    return ((hash >>> 0) + 0.5) / 4294967296;
  };

  (city.buildings || []).forEach((b) => {
    if (b.kind !== 'housing' || !b.housing || !b.housing.volumes || !b.housing.volumes.length) return;
    const expected = asset.meta.types[b.housing.type];
    const refined = !!expected && b.housing.volumes.length === expected.length && b.housing.volumes.every((v, i) => v.x === expected[i][0] && v.z === expected[i][1] && v.w === expected[i][2] && v.d === expected[i][3]);
    if (!refined) fail('housing ' + b.id + ' does not match the refined module types (upstream would take the unrefined path)');
    const id = b.id.replace(/-/g, '_'), [cx, cz] = env.chunkOf(b.x, b.z), node = file.node('Housing_c' + cx + '_' + cz);
    const em = makeEmitter(node);
    const winNode = file.node('Windows_' + id), wem = makeEmitter(winNode);
    const record = { b, colors: paletteFor(b), detail: detailsFor(b), volumes: b.housing.volumes.map((v) => Object.assign({}, v)), doors: [], panes: 0,
      roofTop: Math.max(...asset.meta.modules.filter((x) => /^(Service_|RoofEdge|Planter)/.test(x.name)).map((x) => x.bounds.max[1])) };
    const yOf = (owner) => (owner.kind === 'ground' ? 0 : BASE + owner.floor * FLOOR);
    // `part` / `box`: an instance in the owner's frame (building centre; y from the owner's base).
    const part = (owner, role, color, shape, x, y, z, w, h, d, rx, ry, rz) => {
      const yy = yOf(owner);
      const q = new T.Quaternion().setFromEuler(new T.Euler(rx || 0, ry || 0, rz || 0));
      const mtx = new T.Matrix4().compose(new T.Vector3(b.x + x, yy + y, b.z + z), q, new T.Vector3(w, h, d));
      if (shape === 'box') {
        const target = role === 'lit' ? wem : em;
        const opts = role === 'lit' ? { uv: [owner.rank, owner.floor / b.floors] } : undefined;
        if (role === 'lit') {
          // A pane's outward face only (its normal is the facade's outward normal).
          target.emitMasked(ROLE[role], b.x + x, yy + y, b.z + z, w, h, d, lin(color), qa(q), [owner.face], opts);
        } else target.box(ROLE[role], b.x + x, yy + y, b.z + z, w, h, d, lin(color), qa(q), opts);
        return { local: { x, y, z, w, h, d }, owner, role, color };
      }
      const geo = shape === 'leaf' ? leafGeo : shape === 'tank' ? tankGeo : shapes[shape];
      // Modules carry their own vertex colours (x the white instance colour); the leaf and tank take the part colour.
      em.geometry(ROLE[role], geo, mtx, lin(color), shape === 'leaf' || shape === 'tank' ? undefined : { tintVertex: true });
      return null;
    };
    const box = (owner, role, color, x, y, z, w, h, d, yaw) => part(owner, role, color, 'box', x, y, z, w, h, d, 0, yaw || 0, 0);
    const refinedPart = (owner, name, x, y, z, sx, sy, yaw) => part(owner, 'refined', '#ffffff', name, x, y, z, sx || 1, sy || 1, 1, 0, yaw || 0, 0);
    const occupied = (volume, floor, x, z, clearance) => record.volumes.some((o) => o !== volume && o.floors > floor && Math.abs(x - o.x) < o.w / 2 + clearance && Math.abs(z - o.z) < o.d / 2 + clearance);
    function facade(owner, volume, floor, onX, sign) {
      const detail = record.detail, span = onX ? volume.d : volume.w, cols = Math.max(1, Math.floor((span - 2) / 4.7));
      const spacing = (span - 2) / cols, face = (onX ? volume.w : volume.d) / 2;
      const facing = (role, color, u, y, out, width, height, depth, own) => box(own || owner, role, color, volume.x + (onX ? sign * (face + out) : u), y, volume.z + (onX ? u : sign * (face + out)), onX ? depth : width, height, onX ? width : depth);
      for (let col = 0; col < cols; col++) {
        const u = (col - (cols - 1) / 2) * spacing;
        if (!onX && sign < 0 && (Math.abs(u + volume.w * 0.32) < 1.8 || (floor === 0 && Math.abs(u - volume.w * 0.15) < 2.1))) continue;
        const px = volume.x + (onX ? sign * (face + 1) : u), pz = volume.z + (onX ? u : sign * (face + 1));
        if (occupied(volume, floor, px, pz, 1)) continue;
        const balcony = floor > 0 && (volume.balconies === 'both' || volume.balconies === (onX ? 'x' : 'z')) && (col + floor % 2) % 2 === 0;
        const width = Math.min(balcony ? 2.4 : 1.95, spacing - 0.8), height = balcony ? 3.5 : 2.55, center = balcony ? 2.1 : 3.05;
        refinedPart(owner, 'Window', volume.x + (onX ? sign * face : u), center, volume.z + (onX ? u : sign * face), width / 1.95, height / 2.55, onX ? sign * Math.PI / 2 : sign < 0 ? Math.PI : 0);
        facing('glass', record.colors.glass, u, center, 0.35, width, height, 0.09);
        const litOwner = { kind: 'floor', floor, rank: windowRank(b, volume, floor, onX ? 'x' : 'z', sign, col), face: onX ? (sign > 0 ? 0 : 1) : (sign > 0 ? 4 : 5) };
        facing('lit', '#ffd69a', u, center, 0.409, width * 0.94, height * 0.96, 0.025, litOwner);
        record.panes++; features.windows++;
        if (!balcony) continue;
        const bw = Math.min(3.4, spacing - 0.3);
        refinedPart(owner, 'Balcony', volume.x + (onX ? sign * face : u), 0, volume.z + (onX ? u : sign * face), bw / 3.4, 1, onX ? sign * Math.PI / 2 : sign < 0 ? Math.PI : 0);
        features.balconies++; features.planters++;
      }
    }
    function floorModule(owner, volume, floor) {
      const w = volume.w, d = volume.d, x = volume.x, z = volume.z, detail = record.detail;
      box(owner, 'wall', record.colors.wall, x, 3, z, w, 5.83, d);
      for (let edge = -1; edge <= 1; edge += 2) { refinedPart(owner, 'Cornice', x, 5.91, z + edge * d / 2, w, 1, 0); refinedPart(owner, 'Cornice', x + edge * w / 2, 5.91, z, d, 1, Math.PI / 2); }
      for (let sign = -1; sign <= 1; sign += 2) { facade(owner, volume, floor, false, sign); facade(owner, volume, floor, true, sign); }
      const coreX = x - w * 0.32;
      if (!occupied(volume, floor, coreX, z - d / 2 - 0.5, 0.5)) {
        box(owner, detail.core, record.colors[detail.core], coreX, 3, z - d / 2 - 0.16, 1.55, 6, 0.36);
        box(owner, 'glass', record.colors.glass, coreX, 3.45, z - d / 2 - 0.38, 0.69, 3.8, 0.1);
        box(owner, 'trim', record.colors.trim, coreX, 3.5, z - d / 2 - 0.46, 0.78, 0.16, 0.08);
        if (floor === 0) features.stairCores++;
      }
      if (floor !== 0) return;
      const entranceZ = z - d / 2, entranceX = x + w * 0.15;
      if (occupied(volume, floor, entranceX, entranceZ - 1.4, 1.3)) return;
      refinedPart(owner, 'Entry', entranceX, 0, entranceZ, 1, 1, Math.PI);
      // The leaf (panel + glazing) swings about its street-side stile; raised to 2.1 m (sill kept).
      const panelH = DOOR_UNITS, glazeH = 2.8 + (DOOR_UNITS - 3.6);
      record.doors.push({ hinge: [entranceX - 1.2, entranceZ - 0.52], angle: 1.45,
        parts: [['dark', record.colors.dark, entranceX, panelH / 2, entranceZ - 0.52, 2.4, panelH, 0.12], ['glass', record.colors.glass, entranceX, 1.95 + (DOOR_UNITS - 3.6) / 2, entranceZ - 0.6, 2.08, glazeH, 0.08]] });
      const ground = { kind: 'ground', floor: -1 };
      const steps = [[0.425, -1.5, 3.4, 0.35, 1.1], [0.6, -1.03, 3.2, 0.7, 0.85], [0.825, -0.64, 3, 1.15, 0.5]];
      steps.forEach((s) => box(ground, 'trim', record.colors.trim, entranceX, s[0], entranceZ + s[1], s[2], s[3], s[4]));
      env.walkable.push({ kind: 'housing-steps', building: b.id, x: b.x + entranceX, z: b.z + entranceZ - 1.03, w: 3.4, d: 2.45, y_from: 0.25, y_to: BASE, toward: [0, 1] });
      const lamp = [entranceX, 3.97, entranceZ - 0.87, 1.24, 0.12, 0.34];
      box(owner, 'metal', record.colors.trim, lamp[0], lamp[1], lamp[2], lamp[3], lamp[4], lamp[5]);
      env.lights.lamp({ kind: 'housing-entry', x: b.x + lamp[0], y: BASE + lamp[1] - 0.1, z: b.z + lamp[2], ground: 0.25, color: '#ffd69a', range: 10, energy: 0, omni: false, building: b.id });
      features.entrances++;
    }
    function roofModule(owner, volume, index) {
      const x = volume.x, z = volume.z, w = volume.w, d = volume.d;
      box(owner, 'trim', record.colors.trim, x, 0.14, z, w + 0.65, 0.28, d + 0.65);
      box(owner, 'wall', record.colors.wall, x, 0.34, z, w - 0.7, 0.12, d - 0.7);
      for (let side = -1; side <= 1; side += 2) {
        refinedPart(owner, 'RoofEdge', x, 0, z + side * (d / 2 - 0.13), w, 1, 0);
        refinedPart(owner, 'RoofEdge', x + side * (w / 2 - 0.13), 0, z, d, 1, Math.PI / 2);
        refinedPart(owner, 'Planter', x + side * w * 0.27, 0, z + d * 0.27, Math.min(5, w * 0.3) / 5, 1, 0);
      }
      refinedPart(owner, 'Service_' + String.fromCharCode(65 + index), x, 0, z - d * 0.22, 1, 1, 0);
      features.planters += 2; if (index === 0) features.solarPanels += 2; else if (index === 1) features.waterTanks++; else features.dryingRacks++;
    }
    function planter(owner, x, y, z, w, d) {
      box(owner, 'accent', record.colors.accent, x, y + 0.35, z, w, 0.7, d); box(owner, 'green', record.colors.green, x, y + 0.83, z, w * 0.92, 0.45, d * 0.9); features.planters++;
    }
    function garden(owner) {
      const site = b.housing.courtyard; if (!site) return;
      box(owner, 'green', '#90a574', site.x, 0.285, site.z, site.w, 0.07, site.d);
      if (b.housing.type === 'terrace') {
        box(owner, 'trim', '#e0d4bd', site.x, 0.33, site.z, 1.35, 0.03, site.d); box(owner, 'trim', '#e0d4bd', site.x, 0.34, site.z, site.w * 0.72, 0.03, 1.25);
        planter(owner, site.x - site.w * 0.32, 0.29, site.z + site.d * 0.32, 2.2, 1.15);
      }
      const acrossX = site.w >= site.d, width = Math.min(2.8, site.w - 0.8), depth = Math.min(2.8, site.d - 0.8);
      for (let sign = -1; sign <= 1; sign += 2) {
        const x = site.x + (acrossX ? sign * site.w * 0.31 : 0), z = site.z + (acrossX ? 0 : sign * site.d * 0.31), radius = Math.min(1.5, width / 2, depth / 2);
        solids.begin('tree', 'courtyard-tree-' + b.id + (sign < 0 ? 'a' : 'b'), 0.25);
        box(owner, 'wood', record.colors.wood, x, 1.15, z, 0.27, 1.8, 0.27);
        solids.end();
        part(owner, 'green', record.colors.green, 'leaf', x, 2.65, z, radius, 1.65, radius, 0, 0, 0); features.courtyardTrees++;
      }
      const bx = site.x + (acrossX ? 0 : Math.min(3, site.w * 0.28)), bz = site.z + (acrossX ? Math.min(2, site.d * 0.26) : 0);
      solids.begin('bench', 'courtyard-bench-' + b.id, 0.25);
      box(owner, 'wood', record.colors.wood, bx, 0.9, bz, Math.min(3.4, site.w * 0.45), 0.18, 1);
      box(owner, 'wood', record.colors.wood, bx, 1.4, bz + 0.45, Math.min(3.4, site.w * 0.45), 0.8, 0.15);
      for (let edge = -1; edge <= 1; edge += 2) box(owner, 'metal', record.colors.metal, bx + edge * Math.min(1.25, site.w * 0.16), 0.56, bz, 0.16, 0.63, 0.85);
      solids.end();
    }
    const ground = { kind: 'ground', floor: -1 };
    garden(ground);
    record.volumes.forEach((v, i) => {
      solids.begin('building', b.id + '-wing' + i, 0.25, { building: b.id });
      box(ground, 'trim', '#d6cfc2', v.x, 0.82, v.z, v.w + 0.7, 1.14, v.d + 0.7);
      solids.end();
    });
    for (let floor = 0; floor < b.floors; floor++) {
      const owner = { kind: 'floor', floor };
      record.volumes.forEach((v) => { if (v.floors > floor) floorModule(owner, v, floor); });
    }
    record.volumes.forEach((v, index) => roofModule({ kind: 'roof', floor: v.floors }, v, index));
    // Door leaves.
    record.doors.forEach((door, k) => {
      const name = 'Door_' + id + '_' + k, dn = file.node(name);
      const pivot = [b.x + door.hinge[0], BASE, b.z + door.hinge[1]];
      dn.origin = pivot; dn.translation = pivot.map((v) => v * 0.5);
      const dem = makeEmitter(dn);
      // Panel and glazing in one surface (the glazing keeps its colour): one draw call a door.
      door.parts.forEach((p) => dem.box('tt_matte', b.x + p[2], BASE + p[3], b.z + p[4], p[5], p[6], p[7], lin(p[1]), null, { keepBottom: true }));
      world.doors.push({ node: name, building: b.id, height_m: DOOR_UNITS * 0.5, width_m: 1.2,
        motion: { kind: 'swing', axis: [0, 1, 0], angle: door.angle }, rule: 'open fraction = the block doorOpen of the town view (city-housing.js refreshDoors)' });
    });
    world.buildings[b.id] = { body: 'Housing_c' + cx + '_' + cz, floors: b.floors, top_m: (BASE + b.floors * FLOOR + record.roofTop) * 0.5, windows: 'Windows_' + id };
    world.windows.push({ node: 'Windows_' + id, building: b.id, panes: record.panes, colour: '#ffd69a', albedo: '#ffe0ad',
      rule: 'lit when TEXCOORD_0.x < light level (city-housing.js refreshLights: item.rank < level)' });
    counts.housing_windows = (counts.housing_windows || 0) + record.panes;
    counts.housing_doors = (counts.housing_doors || 0) + record.doors.length;
  });
  counts.housing_blocks = (city.buildings || []).filter((b) => b.kind === 'housing').length;
  counts.housing_features = features;
}
function qa(q) { return Math.abs(q.x) + Math.abs(q.y) + Math.abs(q.z) < 1e-12 ? null : [q.x, q.y, q.z, q.w]; }
