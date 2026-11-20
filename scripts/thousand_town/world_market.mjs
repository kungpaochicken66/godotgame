// Port of upstream's night market and street office bodies: city-waterfront.js `create` (lines 181-499):
// the promenade slab, seams and ground light lines; per stall the awning posts, striped canvas (the
// landscape CanopyStripe module), rafters, valance, counter, cabinet panels, the hot carts (plate, hood, flue,
// grill/griddle/pot, bowls), the outdoor table and stools or the bar stools, the drinks and deli goods, the
// festoon bulbs and two lanterns; then the two-storey street office with its windows.
//
// Nodes:
//   Market_c<ix>_<iz>         the promenade (chunked like the ground)
//   Market_c<ix>_<iz>         also every stall body (posts, counter, stools, table, menu board)
//   Stall_<id>_Awning         each stall's canvas stripes, rafters and valance (sway or fold it as a unit)
//   Market_Goods_c<ix>_<iz>   the food and drink on show; upstream hides it while the market is closed
//   Market_Lights_c<ix>_<iz>  the festoon bulbs and the lanterns (tt_lamp; upstream glow 2.6 x lamps while
//                             the market is busy, 0.12 x lamps when it is empty)
//   StreetOffice_c<chunk>     the street office; StreetOffice_Windows its duty windows (rank = lit order)
// The Chinese stall and office names (`sign`) are replaced by world_signs.mjs pictograms.
import { lin } from './world_core.mjs';

export function buildMarket(env) {
  const { T, city, file, makeEmitter, makeChunked, solids, counts, lights, world } = env;
  const M = {
    wood: ['tt_paint', '#a98361'], frame: ['tt_paint', '#ede8d8'], fabric: ['tt_paint', '#ffffff'], metal: ['tt_metal', '#536b69'],
    goods: ['tt_paint', '#ffffff'], paving: ['tt_matte', '#e2dcca'], seams: ['tt_matte', '#c5b9a3'], glow: ['tt_lamp', '#ffffff'],
  };
  // Heights the scale checks read: the stool seat top (`stool`: cylinder at 1.15, 0.4 high) and the slab.
  env.scaleProbes = Object.assign(env.scaleProbes || {}, { stool_seat_top: 1.15 + 0.4 / 2, market_ground: 0.29 });
  const colourOf = (mat, tint) => (tint ? mul3(lin(M[mat][1]), lin(tint)) : lin(M[mat][1]));
  const boxGeo = new T.BoxGeometry(1, 1, 1), sphereGeo = new T.SphereGeometry(1, 8, 6), cylGeo = new T.CylinderGeometry(1, 1, 1, 8), bulbGeo = new T.IcosahedronGeometry(1, 0);
  const canopyData = env.ctx.CityLandscapeAsset.modules.CanopyStripe;
  const canopyGeo = new T.BufferGeometry();
  canopyGeo.setAttribute('position', new T.Float32BufferAttribute(Array.from(canopyData.position), 3));
  canopyGeo.setAttribute('normal', new T.Float32BufferAttribute(Array.from(canopyData.normal), 3));
  const up = new T.Vector3(0, 1, 0);
  const part = (em, g, mat, x, y, z, w, h, d, tint, yaw) => {
    const glowMat = mat === 'glow';
    em.geometry(M[mat][0], g, new T.Matrix4().compose(new T.Vector3(x, y, z), new T.Quaternion().setFromAxisAngle(up, yaw || 0), new T.Vector3(w, h, d)), glowMat ? lin(tint || '#fff4d8') : colourOf(mat, tint));
  };
  // The promenade (231-251).
  const promenade = makeChunked('Market');
  const water = city.water, shore = Math.abs(water.d) / 2 - 30, crossings = [];
  city.roads.filter((r) => r.axis === 'x').forEach((r) => crossings.push([r.z - r.d / 2, r.z + r.d / 2]));
  city.bridges.forEach((b) => crossings.push([b.z - (b.d / 2 + 4), b.z + (b.d / 2 + 4)]));
  const spans = []; let cursor = -shore;
  crossings.sort((a, b) => a[0] - b[0]).concat([[shore + 1, shore + 2]]).forEach((cut) => { if (cut[0] > cursor + 0.5) spans.push([cursor, Math.min(cut[0], shore)]); cursor = Math.max(cursor, cut[1]); });
  for (const side of [-1, 1]) for (const [a, b] of spans) {
    const z = (a + b) / 2, len = b - a;
    part(promenade, boxGeo, 'paving', side * 25.8, 0.275, z, 20.6, 0.03, len);
    part(promenade, boxGeo, 'seams', side * 18.5, 0.294, z, 0.22, 0.009, len);
    part(promenade, boxGeo, 'seams', side * 25.8, 0.294, z, 0.12, 0.009, len);
    for (let joint = Math.ceil(a / 6) * 6; joint < b; joint += 6) part(promenade, boxGeo, 'seams', side * 25.8, 0.294, joint, 20.6, 0.008, 0.055);
    if (len > 14) promenade.box('tt_fixture', side * 16.6, 0.29, z, 0.16, 0.05, len - 9, lin('#ffb45e'));
    env.walkable.push({ kind: 'market-promenade', x: side * 25.8, z, w: 20.6, d: len, y: 0.29 });
  }
  // The stalls (306-420). Bodies merge into the promenade chunks; goods and lights into their own chunked
  // nodes (Market_Goods_c*, Market_Lights_c*) so Godot can hide or light them as groups; each awning is a
  // node of its own.
  const bodies = promenade, goodsEm = makeChunked('Market_Goods'), lightsEm = makeChunked('Market_Lights');
  goodsEm.split = false; lightsEm.split = false;
  const stalls = (city.waterfront && city.waterfront.stalls) || [];
  const stallRecords = [];
  stalls.forEach((s) => {
    const id = s.id.replace(/-/g, '_').replace(/__/g, '_m'), base = 'Stall_' + id;
    const awning = file.node(base + '_Awning');
    const E = { body: bodies, awning: makeEmitter(awning), goods: goodsEm, glow: lightsEm };
    const pick = (mat, group) => (group ? E[group] : mat === 'goods' ? E.goods : mat === 'glow' ? E.glow : E.body);
    const canopy = { grill: '#a36f55', hotpot: '#94736b', griddle: '#b39463', dessert: '#7e9388', juice: '#b49b68', deli: '#83938e' }[s.type] || s.color;
    const at = (dx, dz) => ({ x: s.x + s.side * dx, z: s.z + dz });
    const b = (mat, dx, y, dz, w, h, d, tint, group) => { const p = at(dx, dz); part(pick(mat, group), boxGeo, mat, p.x, y, p.z, w, h, d, tint); };
    const cyl = (mat, dx, y, dz, r, h, tint) => { const p = at(dx, dz); part(pick(mat), cylGeo, mat, p.x, y, p.z, r, h, r, tint); };
    const puff = (mat, dx, y, dz, rx, ry, rz, tint) => { const p = at(dx, dz); part(pick(mat), sphereGeo, mat, p.x, y, p.z, rx, ry, rz, tint); };
    solids.begin('stall', s.id, 0.29, { stall: s.id });
    for (const dx of [-2.45, 2.45]) for (const dz of [-2.7, 2.7]) b('frame', dx, 2.93, dz, 0.15, 5.24, 0.15);
    solids.pause();
    for (let stripe = 0; stripe < 8; stripe++) {
      const dz = -2.595 + stripe * 0.7417, tint = stripe % 2 ? '#f3ead6' : canopy;
      part(E.awning, canopyGeo, 'fabric', s.x, 0, s.z + dz, 1, 1, 1, tint, s.side < 0 ? Math.PI : 0);
    }
    for (const dx of [-2.42, 2.42]) b('wood', dx, 5.34, 0, 0.12, 0.14, 5.55, undefined, 'awning');
    for (const dz of [-2.7, 2.7]) b('wood', 0, 5.34, dz, 5, 0.14, 0.12, undefined, 'awning');
    b('frame', -2.66, 4.95, 0, 0.14, 0.9, 5.65, undefined, 'awning');
    solids.resume();
    b('wood', 2.52, 2.8, -2.25, 0.12, 2.05, 0.85, '#506559');
    for (let menu = 0; menu < 4; menu++) b('goods', 2.6, 2.2 + menu * 0.33, -2.25, 0.025, 0.06, 0.6, '#f1dfb9');
    if (s.hot) { cyl('goods', -1.25, 2.18, 0, 0.24, 0.15, '#e9e1c6'); cyl('goods', -0.86, 2.19, 0.34, 0.11, 0.2, '#f5ead5'); }
    const cm = s.hot ? 'metal' : 'wood', ct = s.hot ? '#4d6260' : undefined;
    b(cm, 0.6, 1.25, 0, 0.7, 1.9, 5.4, ct); b(cm, 1.8, 1.25, -1.075, 1.7, 1.9, 3.25, ct); b(cm, 1.8, 1.25, 2.475, 1.7, 1.9, 0.45, ct);
    b('frame', 0.4, 2.29, 0, 1.1, 0.16, 5.7); b('frame', 1.85, 2.29, -1.15, 1.8, 0.16, 3.4); b('frame', 1.85, 2.29, 2.55, 1.8, 0.16, 0.6);
    for (const dz of [-1.75, 0, 1.75]) b('fabric', 0.22, 1.34, dz, 0.06, 1.5, 1.6, s.hot ? '#78877e' : '#af9272');
    b('wood', 0.18, 0.48, 0, 0.08, 0.22, 5.3);
    for (const dz of [-1.75, 0, 1.75]) b('metal', 0.17, 1.8, dz, 0.08, 0.08, 0.48, '#d7d4c5');
    const stool = (dx, dz) => { const p = at(dx, dz); part(E.body, cylGeo, 'wood', p.x, 1.15, p.z, 0.34, 0.4, 0.34, '#c8b391'); part(E.body, boxGeo, 'frame', p.x, 0.95, p.z, 0.5, 0.42, 0.5, '#8c7a63'); };
    if (s.hot) {
      b('metal', 0.55, 2.47, 0, 0.9, 0.16, 4.4, '#6c8381'); b('frame', 1.3, 4.62, 0, 2.2, 0.5, 3.2, '#5d6b64'); b('metal', 2.1, 5.12, 0, 0.4, 0.5, 0.4, '#4d6260');
      if (s.type === 'grill') {
        b('goods', 1.3, 2.64, -0.65, 1.85, 0.18, 2.5, '#465650');
        for (let k = 0; k < 5; k++) { const dz = -1.55 + k * 0.43; b('goods', 1.25, 2.78, dz, 1.9, 0.055, 0.06, '#c4a079'); for (const dx of [0.75, 1.15, 1.55]) puff('goods', dx, 2.88, dz, 0.16, 0.12, 0.15, k % 2 ? '#b67e54' : '#b39160'); }
      } else if (s.type === 'griddle') {
        cyl('goods', 1.3, 2.63, -0.9, 0.76, 0.14, '#465650'); cyl('goods', 1.3, 2.73, -0.9, 0.62, 0.06, '#c6a16d'); b('goods', 0.55, 2.8, -1.75, 0.85, 0.06, 0.1, '#a98e68');
      } else {
        cyl('goods', 1.3, 2.76, -0.9, 0.6, 0.42, '#8c5a44'); puff('goods', 1.3, 3.19, -0.9, 0.3, 0.28, 0.3, '#efe9dd'); puff('goods', 1.15, 3.7, -0.72, 0.42, 0.34, 0.42, '#efe9dd');
      }
      b('goods', 0.45, 2.59, -0.1, 0.9, 0.08, 1.1, '#87958a');
      for (let k = 0; k < 3; k++) { const dz = -0.45 + k * 0.35; cyl('goods', 0.55, 2.8, dz, 0.18, 0.34, '#ede4d1'); cyl('goods', 0.55, 2.98, dz, 0.145, 0.025, '#b98c55'); }
      { const p = at(-1.25, 0); part(E.body, cylGeo, 'frame', p.x, 1.05, p.z, 0.24, 1.9, 0.24); part(E.body, cylGeo, 'wood', p.x, 2.02, p.z, 0.95, 0.16, 0.95, '#c99a63'); }
      for (let k = 0; k < 5; k++) { const angle = Math.PI / 2 + k * Math.PI * 2 / 5; stool(-1.25 + Math.cos(angle) * 1.05, Math.sin(angle) * 1.55); }
    } else for (let k = 0; k < 4; k++) stool(-1.05, (k - 1.5) * 1.55);
    if (s.type === 'deli') {
      for (const dz of [-1.6, -0.4, 2.5]) { b('goods', 1.55, 2.44, dz, 1.9, 0.08, 0.55, '#87958a'); for (let k = 0; k < 4; k++) puff('goods', 0.9 + k * 0.35, 2.58, dz, 0.14, 0.1, 0.18, k % 2 ? '#a5795f' : '#b5a16c'); }
    } else if (!s.hot) {
      const servingZ = [-1.6, -0.4, 2.5];
      for (let k = 0; k < 3; k++) {
        const dz = servingZ[k], drink = s.type === 'juice' ? ['#bd9660', '#a0ac72', '#bf8a6d'][k] : ['#ccad78', '#a47c62', '#98a17b'][k];
        cyl('goods', 1.9, 2.83, dz, 0.3, 0.9, drink); cyl('goods', 1.9, 3.31, dz, 0.32, 0.06, '#ede4d1'); b('goods', 1.53, 2.52, dz, 0.18, 0.09, 0.11, '#596b63');
        cyl('goods', 0.55, 2.61, dz, 0.19, 0.46, '#ede4d1'); cyl('goods', 0.55, 2.86, dz, 0.155, 0.025, drink);
      }
      b('goods', 0.55, 2.42, 2.55, 1.2, 0.08, 0.5, '#84917c');
      for (let k = 0; k < 4; k++) puff('goods', 0.18 + k * 0.25, 2.64, 2.55, 0.13, 0.17, 0.14, s.type === 'juice' ? '#c49a60' : '#c6b18c');
    }
    solids.end();
    // `lampTrain` (282-291), `lantern` (292-299).
    const step = 5 / 6;
    for (let i = 0; i < 7; i++) {
      const dz = -2.5 + step * i, y = 4.4 - 0.42 * (1 - Math.pow(dz / 2.5, 2)), p = at(-2.5, dz);
      part(E.glow, bulbGeo, 'glow', p.x, y, p.z, 0.22, 0.22, 0.22, '#ffcf87');
      if (i) { const q = at(-2.5, dz - step / 2); part(E.body, boxGeo, 'metal', q.x, y + 0.13, q.z, 0.07, 0.07, step * 0.98, '#3c4a49'); }
    }
    const lanterns = [];
    [-2.35, 2.35].forEach((dz) => {
      const p = at(-0.15, dz), hang = 3.8;
      part(E.glow, sphereGeo, 'glow', p.x, hang, p.z, 0.5, 0.65, 0.5, '#d8483c');
      part(E.body, boxGeo, 'frame', p.x, hang + 0.74, p.z, 0.44, 0.16, 0.44, '#c8a86a');
      part(E.body, boxGeo, 'metal', p.x, hang + 1.215, p.z, 0.06, 0.79, 0.06, '#3c4a49');
      part(E.body, boxGeo, 'wood', p.x, hang - 0.72, p.z, 0.13, 0.34, 0.13, '#c8a86a');
      lanterns.push({ x: p.x, y: hang, z: p.z });
      env.lanterns.push({ kind: 'market', stall: s.id, x: p.x, y: hang, z: p.z, color: '#d8483c' });
    });
    lights.lamp({ kind: 'market-stall', x: s.x, y: 4.6, z: s.z, ground: 0.29, color: '#ffb45e', range: 9, energy: 0, omni: true, stall: s.id });
    lights.pool({ source: 'stall', x: s.x, y: 0.33, z: s.z, w: 4.8, d: 5.8, level: 0.58, color: '#ffd9a0' });
    lights.pool({ source: 'stall', x: s.x - s.side * 3.7, y: 0.33, z: s.z, w: 3.2, d: 4.8, level: 0.28, color: '#ffd9a0' });
    const [cx, cz] = env.chunkOf(s.x, s.z);
    stallRecords.push({ id: s.id, awning: base + '_Awning', body_chunk: 'Market_c' + cx + '_' + cz, goods: 'Market_Goods_c' + cx + '_' + cz, lights: 'Market_Lights_c' + cx + '_' + cz, type: s.type, hot: !!s.hot,
      x_m: s.x * 0.5, z_m: s.z * 0.5, side: s.side, sign: { ...at(-2.75, 0), y: 4.95 } });
  });
  world.stalls = stallRecords.map(({ sign, ...r }) => r);
  env.stallSigns = stallRecords.map((r) => ({ id: r.id, type: r.type, x: r.sign.x, y: r.sign.y, z: r.sign.z, side: r.side }));
  counts.stalls = stalls.length;
  counts.stall_lanterns = stalls.length * 2;
  // The street office (421-444).
  const office = city.waterfront && city.waterfront.civic;
  if (office) {
    const on = file.node('StreetOffice_c' + env.chunkOf(office.x, office.z).join('_')), oem = makeEmitter(on);
    const ob = (mat, x, y, z, w, h, d, tint) => part(oem, boxGeo, mat, x, y, z, w, h, d, tint);
    solids.begin('building', office.id, 0.29, { building: office.id });
    ob('frame', office.x, 2.9, office.z, office.w - 0.3, 5.2, office.d - 0.4, '#e1d6bc');
    solids.end();
    ob('frame', office.x, 8.05, office.z, office.w - 0.3, 5.1, office.d - 0.4, '#e1d6bc');
    ob('wood', office.x, 5.56, office.z, office.w, 0.22, office.d, '#879580'); ob('wood', office.x, 10.72, office.z, office.w, 0.28, office.d, '#718778');
    const wn = file.node('StreetOffice_Windows'), wem = makeEmitter(wn), n = 8;
    let i = 0;
    for (let floor = 0; floor < 2; floor++) for (let col = 0; col < 4; col++) {
      const x = office.x - office.side * (office.w / 2 - 0.18), z = office.z + (col - 1.5) * 3.7, y = 3 + floor * 5.15;
      ob('metal', x, y, z, 0.13, 2.8, 2.5, '#586b62'); ob('frame', x, y, z, 0.1, 3.12, 2.82, '#efe8d8');
      ob('frame', x - office.side * 0.12, y - 1.48, z, 0.38, 0.16, 2.98, '#efe8d8'); ob('metal', x - office.side * 0.14, y, z, 0.06, 2.8, 0.105, '#d8d0be');
      wem.emitMasked('tt_window', x - office.side * 0.085, y, z, 0.025, 2.6, 2.3, lin('#ffd69a'), null, [office.side < 0 ? 0 : 1], { uv: [((i * 3) % n) / n, floor / 2] });
      i++;
    }
    world.windows.push({ node: 'StreetOffice_Windows', building: office.id, panes: n, colour: '#ffd69a', albedo: '#ffe1b1', rule: 'lit when TEXCOORD_0.x < light level (city-waterfront.js setTownView: count = ceil(level x 8))' });
    env.officeSign = { x: office.x - office.side * (office.w / 2 - 0.04), y: 4.25, z: office.z, facing: [-office.side, 0] };
  }
}

function mul3(a, b) { return [a[0] * b[0], a[1] * b[1], a[2] * b[2]]; }
