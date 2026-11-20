// Port of upstream's amusement park, ferris wheel, plaza paving and balloon carts: city-landmarks.js
// `create` (lines 96-720): `amusementPark` (394-536: paving rings, gate, ticket booth, perimeter fences,
// bench, planters, `parkLights`, the wheel's A-frames, axle, rotor, `ferrisLights` rim bulbs and the twelve
// cabins with their sliding doors), `monumentPlaza` (561-628: paving, rings, joints, the six lawn lamps) and
// `balloonCarts` (630-698).
//
// Nodes (all metres, Y up):
//   Amusement_c<chunk>   static park: paving, fences, gate, booth, bench, planters, lamp posts and heads
//   FerrisWheel          the mechanism frame: translation = park centre, rotation = yaw -0.66 (WHEEL_YAW)
//     FerrisSupports     the two A-frames (static)
//     FerrisAxle         the axle (static)
//     FerrisRotor        at the axle (y 13 m); spins about its local +Z: angle = (t mod 180 s) / 180 s x 2 pi
//     FerrisCabin_00..11 each at its rest anchor (cos a R, 13 + sin a R, 0), a = k x 2 pi / 12; the anchor
//                        moves with the rotor angle but the cabin never rotates (it stays level). Two
//                        surfaces a cabin: tt_paint (frame, shell, doors drawn shut) and tt_lamp (glazing band,
//                        lamp planes); cabins k and k + 3 share one glTF mesh.
//   Plaza_c<chunk>       paving, rings and joints, lamp posts; heads in tt_lamp
//   BalloonCarts_c<chunk> the two carts; BalloonCarts_Balloons the 14 balloons (bob 0.09 m, period 12 s)
// Rides (carousel, teacups), the monument, plaza benches and planters are W-DATA's amusement.glb and
// landscape.glb, placed from town.json; the seated fares are left out (Lantern Lane draws people).
import { lin } from './world_core.mjs';

const TAU = Math.PI * 2, RADIUS = 20, AXLE_Y = 26, WHEEL_YAW = -0.66, PERIOD = 180, CABIN_SCALE = 1.45;
const CANOPY_LEADS = ['#e38a77', '#8ebfac'], CART_WOOD = '#aa8060', CART_TOP = '#ede8d9', CART_FRAME = '#e8eef0', CART_WHEEL = '#526c71', CART_STRING = '#7d8488';
const SKINS = ['#e0b48c', '#c98f63', '#f0cbab', '#a9744c'], HAIR = '#40382f';

export function buildLandmarks(env) {
  const { T, city, file, makeEmitter, solids, counts, lights, world } = env;
  const M = {
    paving: ['tt_matte', '#ded8cb'], pale: ['tt_paint', '#eee8d9'], stone: ['tt_matte', '#c5c1b5'], silver: ['tt_metal', '#e8e1d5'],
    gold: ['tt_metal', '#b99a68'], dark: ['tt_paint', '#526c71'], wood: ['tt_paint', '#aa8060'], foliage: ['tt_matte', '#789181'],
    soil: ['tt_matte', '#77695b'], glow: ['tt_lamp', '#ffdfab'], lampHead: ['tt_lamp', '#ffd9a0'],
    frame: ['tt_paint', '#e8e1d5'], // the cabin frames: silver-frame's colour in the cabin's painted surface
  };
  const colors = ['#e38a77', '#e9c768', '#8ebfac'];
  colors.forEach((c, i) => { M['shell' + i] = ['tt_paint', c]; });
  const boxGeo = new T.BoxGeometry(1, 1, 1), cylGeo = new T.CylinderGeometry(1, 1, 1, 12), sphereGeo = new T.IcosahedronGeometry(1, 1);
  const up = new T.Vector3(0, 1, 0);
  // Emission helpers in a frame: `em` places geometry under an extra matrix (the site or mechanism frame).
  const mk = (em, frame) => {
    const put = (geo, key, mtx, color) => em.geometry(M[key][0], geo, frame ? frame.clone().multiply(mtx) : mtx, color || lin(M[key][1]));
    const part = (geo, key, x, y, z, sx, sy, sz, rx, ry, rz, color) => put(geo, key, new T.Matrix4().compose(new T.Vector3(x, y, z), new T.Quaternion().setFromEuler(new T.Euler(rx || 0, ry || 0, rz || 0)), new T.Vector3(sx, sy, sz)), color);
    return {
      put, part,
      box: (key, x, y, z, w, h, d, yaw, color) => part(boxGeo, key, x, y, z, w, h, d, 0, yaw || 0, 0, color),
      cylinder: (key, x, y, z, r, h, color) => part(cylGeo, key, x, y, z, r, h, r, 0, 0, 0, color),
      rod: (key, a, b, r, geo) => {
        const s = new T.Vector3(...a), e = new T.Vector3(...b), dir = e.clone().sub(s), len = dir.length();
        put(geo || cylGeo, key, new T.Matrix4().compose(s.clone().add(e).multiplyScalar(0.5), new T.Quaternion().setFromUnitVectors(up, dir.normalize()), new T.Vector3(r, len, r)));
      },
      ring: (key, inner, outer, y, color) => { const g = new T.RingGeometry(inner, outer, 96); part(g, key, 0, y, 0, 1, 1, 1, -Math.PI / 2, 0, 0, color); g.dispose(); },
    };
  };
  const siteFrame = (site) => new T.Matrix4().makeTranslation(site.x, 0, site.z);
  const bench = (P, x, z, yaw) => {
    const plank = (key, dx, y, dz, w, h, d) => P.box(key, x + dx * Math.cos(yaw) + dz * Math.sin(yaw), y, z - dx * Math.sin(yaw) + dz * Math.cos(yaw), w, h, d, yaw);
    [-1, 1].forEach((side) => { plank('dark', side * 1.7, 0.65, 0, 0.28, 0.75, 1.15); plank('dark', side * 1.7, 1.16, -0.48, 0.16, 1.55, 0.16); });
    for (let slat = 0; slat < 3; slat++) plank('wood', 0, 1.05, (slat - 1) * 0.36, 4.6, 0.16, 0.28);
    plank('wood', 0, 1.68, -0.48, 4.6, 0.46, 0.16);
  };
  const planter = (P, x, z, size) => {
    P.cylinder('pale', x, 0.59, z, size, 0.64); P.cylinder('soil', x, 0.93, z, size - 0.2, 0.1);
    for (let i = 0; i < 7; i++) {
      const phase = i * TAU / 7, px = x + Math.cos(phase) * size * 0.5, pz = z + Math.sin(phase) * size * 0.5;
      P.part(sphereGeo, 'foliage', px, 1.13, pz, size * 0.49, 0.5, size * 0.49); P.part(sphereGeo, 'shell' + (i % 3), px, 1.53, pz, 0.23, 0.16, 0.23);
    }
  };
  const solidIn = (kind, id, base, fn) => { solids.begin(kind, id, base); fn(); solids.end(); };

  // ---- the amusement park
  const site = (city.places || []).find((p) => p.kind === 'amusement');
  if (site) {
    const park = file.node('Amusement_c' + env.chunkOf(site.x, site.z).join('_'));
    const P = mk(makeEmitter(park), siteFrame(site));
    P.box('paving', 0, 0.23, 0, site.w - 0.6, 0.08, site.d - 0.6);
    env.walkable.push({ kind: 'amusement-paving', x: site.x, z: site.z, w: site.w - 0.6, d: site.d - 0.6, y: 0.27 });
    P.ring('pale', 0, 20.2, 0.282); P.ring('shell2', 19.78, 20.12, 0.291); P.ring('gold', 17.6, 17.74, 0.293); P.ring('paving', 5.8, 6.15, 0.294);
    [-1, 1].forEach((side) => { for (let dot = 0; dot < 5; dot++) P.cylinder('shell' + (dot % 3), side * (7 + dot * 1.45), 0.298, 13.6, 0.36, 0.016); });
    // Gate pillars, perimeter fences (posts and two rails), the gate beam, the rear fence, the booth.
    [-1, 1].forEach((side) => {
      solidIn('gate-pillar', 'amusement-gate-' + (side < 0 ? 'w' : 'e'), 0.27, () => P.box('pale', side * 6, 2.54, 20.8, 0.7, 4.55, 0.7));
      solidIn('fence', 'amusement-fence-side-' + (side < 0 ? 'w' : 'e'), 0.27, () => {
        for (let post = 0; post < 8; post++) P.cylinder('silver', side * 19.4, 1.13, -20.2 + post * 5.9, 0.1, 1.7);
        [1, 1.78].forEach((y) => P.rod('silver', [side * 19.4, y, -20.2], [side * 19.4, y, 21.1], 0.065));
      });
      solidIn('fence', 'amusement-fence-front-' + (side < 0 ? 'w' : 'e'), 0.27, () => [1, 1.78].forEach((y) => P.rod('silver', [side * 6.4, y, 21.1], [side * 19.4, y, 21.1], 0.065)));
    });
    P.box('shell2', 0, 4.77, 20.8, 13.1, 0.62, 0.8);
    solidIn('fence', 'amusement-fence-rear', 0.27, () => {
      for (let rear = 0; rear < 9; rear++) P.cylinder('silver', -19.4 + rear * 4.85, 1.13, -20.2, 0.1, 1.7);
      [1, 1.78].forEach((y) => P.rod('silver', [-19.4, y, -20.2], [19.4, y, -20.2], 0.065));
    });
    solidIn('ticket-booth', 'amusement-ticket-booth', 0.27, () => {
      P.box('pale', -13.8, 2.7, 17.3, 5.4, 4.85, 5.3); P.box('shell0', -13.8, 5.19, 17.3, 6, 0.22, 5.9);
      P.box('dark', -13.8, 3.1, 19.98, 4.15, 2.05, 0.08); P.box('gold', -13.8, 2.05, 20.22, 4.4, 0.16, 0.6); P.box('silver', -13.8, 3.1, 20.04, 0.1, 2.06, 0.06);
    });
    solidIn('bench', 'amusement-bench', 0.27, () => bench(P, 12.6, 17, 0));
    solidIn('planter', 'amusement-planter-w', 0.27, () => planter(P, -14.3, -14.7, 2.1));
    solidIn('planter', 'amusement-planter-e', 0.27, () => planter(P, 14.3, -14.7, 2.1));
    // `parkLights`: six path lamps with glowing heads, the gate and booth glow strips, ride trim bands.
    const lamps = [[-18, 8], [18, -8], [-18, -18], [18, 18], [-6.8, 22], [6.8, 22]];
    lamps.forEach((l, i) => {
      solidIn('path-lamp', 'amusement-lamp-' + i, 0.27, () => { P.box('silver', l[0], 1.68, l[1], 0.13, 2.76, 0.13); P.box('pale', l[0], 3.1, l[1], 0.56, 0.48, 0.56); });
      P.box('glow', l[0], 3.12, l[1], 0.585, 0.36, 0.585);
      lights.lamp({ kind: 'amusement-path', x: site.x + l[0], y: 3.1, z: site.z + l[1], ground: 0.27, color: '#ffdfab', range: 10, energy: 0, omni: i < 2 });
    });
    P.box('glow', 0, 4.43, 20.8, 12.2, 0.13, 0.7); P.box('glow', -13.8, 5.32, 17.3, 5.8, 0.09, 5.7);
    const band = new T.CylinderGeometry(4.22, 4.22, 0.14, 32, 1, true); P.part(band, 'glow', -11, 5.9, 6, 1, 1, 1); band.dispose();
    const tea = new T.CylinderGeometry(2.76, 2.76, 0.1, 24, 1, true); P.part(tea, 'glow', -6.5, 0.4, -15, 1, 1, 1); tea.dispose();
    lamps.concat([[0, 20], [-11, 6], [-6.5, -15]]).forEach((l, i) => lights.pool({ source: 'amusement', x: site.x + l[0], y: 0.318, z: site.z + l[1], w: i < 6 ? 10.5 : 15, d: i < 6 ? 9.5 : 12, level: 0.82, color: '#ffd19a' }));
    env.amusementSign = { x: site.x, y: 4.78, z: site.z + 21.215, facing: [0, 1], w: 9.8, h: 0.5 };

    // ---- the ferris wheel
    const mech = file.node('FerrisWheel');
    mech.translation = [site.x * 0.5, 0, site.z * 0.5]; mech.rotation = [0, Math.sin(WHEEL_YAW / 2), 0, Math.cos(WHEEL_YAW / 2)];
    const sup = file.node('FerrisSupports', mech), S = mk(makeEmitter(sup), null);
    [0, 8.6].forEach((dz) => {
      const F = mk(makeEmitter(sup), new T.Matrix4().makeTranslation(0, 0, dz));
      F.rod('silver', [-9.2, 0.8, -4.3], [0, AXLE_Y, -4.3], 0.43); F.rod('silver', [9.2, 0.8, -4.3], [0, AXLE_Y, -4.3], 0.43);
      F.rod('silver', [-6.8, 8.4, -4.3], [6.8, 8.4, -4.3], 0.24);
      [-1, 1].forEach((foot) => F.box('silver', foot * 9.2, 0.56, -4.3, 2.05, 0.62, 1.8));
    });
    void S;
    // Footprints of the four feet, in world coordinates (the mechanism is turned by WHEEL_YAW).
    [0, 8.6].forEach((dz) => [-1, 1].forEach((foot) => {
      const lx = foot * 9.2, lz = -4.3 + dz, c = Math.cos(WHEEL_YAW), s = Math.sin(WHEEL_YAW);
      const wx = site.x + lx * c + lz * s, wz = site.z - lx * s + lz * c;
      const corners = [[-1.025, -0.9], [1.025, -0.9], [1.025, 0.9], [-1.025, 0.9]].map(([u, v]) => [(wx + u * c + v * s), (wz - u * s + v * c)]);
      solids.items.push({ kind: 'ferris-foot', id: 'ferris-foot-' + (dz ? 'rear' : 'front') + (foot < 0 ? 'w' : 'e'), poly: corners, bottom: 0.25, top: 8 });
    }));
    const axle = file.node('FerrisAxle', mech);
    mk(makeEmitter(axle), null).rod('gold', [0, AXLE_Y, -4.8], [0, AXLE_Y, 4.8], 0.74);
    const rotor = file.node('FerrisRotor', mech); rotor.translation = [0, AXLE_Y * 0.5, 0];
    const R = mk(makeEmitter(rotor), null);
    const rim = new T.TorusGeometry(RADIUS, 0.31, 6, 96), spokeGeo = new T.CylinderGeometry(1, 1, 1, 8);
    [-1, 1].forEach((side) => {
      R.part(rim, 'silver', 0, 0, side * 1.78, 1, 1, 1);
      for (let spoke = 0; spoke < 24; spoke++) { const ph = spoke * TAU / 24; R.rod('silver', [0, 0, side * 1.78], [Math.cos(ph) * RADIUS, Math.sin(ph) * RADIUS, side * 1.78], spoke % 2 ? 0.095 : 0.14, spokeGeo); }
    });
    for (let join = 0; join < 12; join++) { const th = join * TAU / 12, px = Math.cos(th) * RADIUS, py = Math.sin(th) * RADIUS; R.rod('silver', [px, py, -1.78], [px, py, 1.78], 0.16); }
    R.part(cylGeo, 'gold', 0, 0, 0, 1.45, 3.9, 1.45, Math.PI / 2);
    // `ferrisLights`: rim, spoke and hub light strips on both faces (vertex coloured, glow material).
    const rotorEm = makeEmitter(rotor);
    const quad = (a, b, c, d, color) => { const col = lin(color); rotorEm.triangles('tt_lamp', [a, b, c, a, c, d], col); rotorEm.triangles('tt_lamp', [a, c, b, a, d, c], col); };
    [-2.16, 2.16].forEach((z) => {
      for (let i = 0; i < 64; i++) {
        const a = i * TAU / 64, b = (i + 1) * TAU / 64, inner = 19.81, outer = 20.19;
        quad([Math.cos(a) * inner, Math.sin(a) * inner, z], [Math.cos(a) * outer, Math.sin(a) * outer, z], [Math.cos(b) * outer, Math.sin(b) * outer, z], [Math.cos(b) * inner, Math.sin(b) * inner, z], i % 16 < 8 ? '#ffe1a3' : '#edaf98');
      }
      for (let spoke = 0; spoke < 8; spoke++) {
        const a = spoke * TAU / 8, c = Math.cos(a), s = Math.sin(a), w = 0.14;
        quad([c * 1.8 - s * w, s * 1.8 + c * w, z], [c * 19.81 - s * w, s * 19.81 + c * w, z], [c * 19.81 + s * w, s * 19.81 - c * w, z], [c * 1.8 + s * w, s * 1.8 - c * w, z], spoke % 2 ? '#a8d9c1' : '#ffe1a3');
      }
      for (let hub = 0; hub < 24; hub++) {
        const a = hub * TAU / 24, b = (hub + 1) * TAU / 24;
        quad([Math.cos(a) * 1.5, Math.sin(a) * 1.5, z], [Math.cos(a) * 1.8, Math.sin(a) * 1.8, z], [Math.cos(b) * 1.8, Math.sin(b) * 1.8, z], [Math.cos(b) * 1.5, Math.sin(b) * 1.5, z], '#fff0cd');
      }
    });
    rim.dispose(); spokeGeo.dispose();
    // The twelve cabins: frames, shells, glass, warm lamp planes; doors as children. Cabins k and k + 3
    // share a mesh (same shell colour).
    const cabins = [];
    for (let id = 0; id < 12; id++) {
      const phase = id * TAU / 12, name = 'FerrisCabin_' + String(id).padStart(2, '0');
      const cab = file.node(name, mech);
      cab.translation = [Math.cos(phase) * RADIUS * 0.5, (AXLE_Y + Math.sin(phase) * RADIUS) * 0.5, 0];
      const tint = colors[id % 3];
      if (id >= 3) cab.meshRef = cabins[id % 3].node;
      else {
        const C = mk(makeEmitter(cab), new T.Matrix4().makeScale(CABIN_SCALE, CABIN_SCALE, CABIN_SCALE));
        C.box('frame', 0, -0.43, 0, 0.22, 0.86, 0.22); C.box('frame', 0, -3.97, 0, 3.24, 0.17, 2.68);
        [-1, 1].forEach((x) => [-1, 1].forEach((z) => C.box('frame', x * 1.49, -2.45, z * 1.16, 0.12, 2.95, 0.12)));
        [-1, 1].forEach((z) => {
          C.box('frame', 0, -1.02, z * 1.18, 3.14, 0.14, 0.12); C.box('frame', 0, -2.84, z * 1.18, 3.14, 0.1, 0.12);
          C.box('frame', 0, -2.02, z * 1.21, 0.1, 1.55, 0.1); C.box('frame', 0, -3.27, z * 0.76, 2.65, 0.16, 0.52);
        });
        C.box('shell' + (id % 3), 0, -0.9, 0, 3.28, 0.24, 2.72); C.box('shell' + (id % 3), 0, -3.43, 0, 3.15, 0.96, 2.58);
        // The tinted glazing band glows at night (upstream glazing.emissiveIntensity = cabin x 1.15), so it is
        // drawn with the lamp planes in tt_lamp: two surfaces a cabin.
        makeEmitter(cab).box('tt_lamp', 0, -2.04 * CABIN_SCALE, 0, 2.89 * CABIN_SCALE, 2.02 * CABIN_SCALE, 2.24 * CABIN_SCALE, lin(tint), null, { keepBottom: true });
        // The two door leaves, drawn shut (upstream slides them apart for six seconds at the boarding point).
        [-1, 1].forEach((side) => C.box('shell' + (id % 3), side * 0.74, -2.45, -1.335, 1.34, 2.6, 0.09));
        const plane = new T.PlaneGeometry(1, 1);
        [-1, 1].forEach((side) => {
          C.part(plane, 'glow', 0, -0.72, side * 1.365, 3.14, 0.2, 1, 0, side < 0 ? Math.PI : 0, 0, lin('#ffe3b3'));
          C.part(plane, 'glow', side * 1.635, -0.72, 0, 2.7, 0.2, 1, 0, side * Math.PI / 2, 0, lin('#ffe3b3'));
        });
        C.part(plane, 'glow', 0, -1.1, 0, 1.05, 0.7, 1, Math.PI / 2, 0, 0, lin('#ffe3b3'));
        plane.dispose();
      }
      cabins.push({ node: cab, phase });
    }
    world.ferris_wheel = {
      node: 'FerrisWheel', rotor: 'FerrisRotor', cabins: cabins.map((c) => c.node.name), centre_m: [site.x * 0.5, 0, site.z * 0.5], yaw: WHEEL_YAW,
      axle_y_m: AXLE_Y * 0.5, radius_m: RADIUS * 0.5, period_s: PERIOD, cabin_scale: CABIN_SCALE,
      motion: 'angle = (t mod 180) / 180 x 2 pi; FerrisRotor.rotation.z = angle; cabin k at (cos(angle + k pi / 6) x 10, 13 + sin(angle + k pi / 6) x 10, 0) in FerrisWheel space, unrotated',
      doors: 'drawn shut in the cabin mesh (upstream slides them 0.45 m apart while 1 + sin(cabin phase) < 0.006, the boarding point)',
      lights: 'rim bulbs (tt_lamp in FerrisRotor) and cabin lamp planes follow the park outline/cabin intensities (city-landmarks.js amusementLighting)',
    };
    counts.ferris_cabins = cabins.length;
  }

  // ---- the plaza (paving and lamps; the monument, benches and planters are landscape.glb modules)
  const plazaSite = (city.places || []).find((p) => p.kind === 'plaza');
  if (plazaSite) {
    const pn = file.node('Plaza_c' + env.chunkOf(plazaSite.x, plazaSite.z).join('_')), P = mk(makeEmitter(pn), siteFrame(plazaSite));
    P.box('paving', 0, 0.23, 0, plazaSite.w - 0.6, 0.08, plazaSite.d - 0.6);
    env.walkable.push({ kind: 'plaza-paving', x: plazaSite.x, z: plazaSite.z, w: plazaSite.w - 0.6, d: plazaSite.d - 0.6, y: 0.27 });
    P.ring('pale', 0, 18.25, 0.281);
    [5.8, 11.8, 17.75].forEach((r) => P.ring('stone', r, r + 0.14, 0.293));
    P.ring('gold', 7.7, 7.86, 0.299);
    for (let joint = 0; joint < 16; joint++) { const ph = joint * TAU / 16; P.box('stone', Math.sin(ph) * 12.05, 0.298, Math.cos(ph) * 12.05, 0.055, 0.012, 11.8, ph); }
    for (let lamp = 0; lamp < 6; lamp++) {
      const pa = lamp * TAU / 6 + Math.PI / 6, lx = Math.sin(pa) * 15.2, lz = Math.cos(pa) * 15.2;
      solidIn('path-lamp', 'plaza-lamp-' + lamp, 0.27, () => P.box('silver', lx, 0.9, lz, 0.13, 1.5, 0.13));
      P.box('lampHead', lx, 1.72, lz, 0.42, 0.3, 0.42);
      lights.lamp({ kind: 'plaza-lawn', x: plazaSite.x + lx, y: 1.72, z: plazaSite.z + lz, ground: 0.27, color: '#ffd9a0', range: 8, energy: 0, omni: false });
    }
    lights.pool({ source: 'plaza-flood', x: plazaSite.x, y: 0.31, z: plazaSite.z, w: 17, d: 15, level: 0.5, color: '#ffd9a0' });
    lights.lamp({ kind: 'plaza-flood', x: plazaSite.x, y: 3, z: plazaSite.z, ground: 0.27, color: '#ffd9a0', range: 18, energy: 0, omni: true, note: 'the monument flood (plaza-flood-pool); a real light candidate' });
    env.plazaSign = { x: plazaSite.x, y: 2.65, z: plazaSite.z + 2.977, facing: [0, 1], w: 4.65, h: 0.82 };
  }

  // ---- balloon carts
  const lot = site, planned = city.balloonStands || [];
  if (lot && planned.length) {
    const drawn = planned.filter((s) => Math.abs(s.x - lot.x) + s.w / 2 <= lot.w / 2 + 1e-6 && Math.abs(s.z - lot.z) + s.d / 2 <= lot.d / 2 + 1e-6 && Math.hypot(s.x - lot.x, s.z - lot.z) >= 26);
    const cn = file.node('BalloonCarts_c' + env.chunkOf(lot.x, lot.z).join('_')), cem = makeEmitter(cn);
    const bn = file.node('BalloonCarts_Balloons'), bem = makeEmitter(bn);
    const ball = new T.IcosahedronGeometry(1, 0), balloons = [];
    drawn.forEach((stand, index) => {
      const yaw = stand.facing || 0, cos = Math.cos(yaw), sin = Math.sin(yaw), ox = stand.x, oz = stand.z;
      const lead = CANOPY_LEADS[index % 2], apron = CANOPY_LEADS[(index + 1) % 2];
      const at = (x, y, z, w, h, d, tint) => cem.box('tt_paint', ox + x * cos + z * sin, y, oz - x * sin + z * cos, w, h, d, lin(tint), yaw ? [0, Math.sin(yaw / 2), 0, Math.cos(yaw / 2)] : null);
      solids.begin('balloon-cart', stand.id, 0.27);
      at(0, 1, 0.7, 3.9, 1.45, 2.6, CART_WOOD); at(0, 1.85, 0.7, 4.1, 0.24, 2.5, CART_TOP);
      at(-1.15, 2.16, 0.8, 0.5, 0.38, 0.5, lead); at(1.15, 2.16, 0.8, 0.5, 0.38, 0.5, CART_TOP);
      [-1, 1].forEach((side) => at(side * 2, 0.82, 1.35, 0.22, 1.1, 1.1, CART_WHEEL));
      [-1, 1].forEach((side) => [-1, 1].forEach((depth) => at(side * 2, 2.85, depth * 2.35, 0.14, 5.1, 0.14, CART_FRAME)));
      solids.end();
      for (let stripe = 0; stripe < 6; stripe++) at(-1.875 + stripe * 0.75, 5.48, 0, 0.75, 0.16, 5.1, stripe % 2 ? CART_TOP : lead);
      at(0, 5.13, 2.5, 4.5, 0.5, 0.1, apron);
      // The vendor figure (upstream's boxes) is left to Lantern Lane's people; the stall stays.
      at(-1.3, 5.45, -1.6, 0.1, 0.9, 0.1, CART_FRAME);
      for (let b = 0; b < 7; b++) {
        const ring = b ? (b - 1) * TAU / 6 : 0, radius = b ? 0.5 : 0;
        const bx = -1.3 + Math.cos(ring) * radius, bz = -1.6 + Math.sin(ring) * radius, by = (b ? 6.52 : 6.9) + (b % 3) * 0.12, size = 0.34 + (b % 3) * 0.02;
        at(bx, (5.9 + by) / 2, bz, 0.04, by - 5.9, 0.04, CART_STRING);
        const wx = ox + bx * cos + bz * sin, wz = oz - bx * sin + bz * cos;
        bem.geometry('tt_paint', ball, new T.Matrix4().compose(new T.Vector3(wx, by, wz), new T.Quaternion(), new T.Vector3(size, size * 1.16, size)), lin(colors[(index + b) % 3]));
        balloons.push({ x_m: wx * 0.5, y_m: by * 0.5, z_m: wz * 0.5, phase: b * TAU / 7, radius_m: [size * 0.5, size * 1.16 * 0.5, size * 0.5], colour: colors[(index + b) % 3] });
      }
    });
    world.balloons = { node: 'BalloonCarts_Balloons', count: balloons.length, period_s: 12, bob_m: 0.09, sway_m: 0.025, balloons,
      motion: 'each balloon offset (cos(p) x sway, sin(p) x bob, sin(p) x sway), p = (t mod 12) / 12 x 2 pi + phase (city-landmarks.js bobBalloons)' };
    counts.balloon_carts = drawn.length;
    void SKINS; void HAIR;
  }
}
