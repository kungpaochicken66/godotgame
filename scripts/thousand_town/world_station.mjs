// Port of upstream's station building: city-transit.js `create` (lines 11-328): the pad, the waiting and
// taxi platforms, bay paint and arrows, the rain canopy with its columns, light strips, ticket booth and
// three benches, the name board and its posts. The board's Chinese text and the painted BUS/TAXI legends
// are replaced by pictograms (world_signs.mjs).
//
// The parked fleet is not baked in: the station loop (town.json transit.station_loop) moves the vehicles, so
// the bus and the taxi are written once each as templates (`vehicle`, lines 196-252), in their own frame:
// origin on the road centre line at ground level, front toward -z, wheels resting on the 0.125 m surface.
// The seated passenger figures upstream puts in them are left out (Lantern Lane draws its own riders).
import { lin, fail } from './world_core.mjs';

export function buildStation(env) {
  const { T, city, file, makeEmitter, solids, counts, lights, world } = env;
  const site = (city.places || []).find((p) => p.kind === 'station');
  if (!site) fail('no station in the city');
  const gateSide = site.gateSide === 1 || site.gateSide === -1 ? site.gateSide : (site.x < 0 ? 1 : -1);
  const sx = site.w / 52, sz = site.d / 58;
  if (sx !== 1 || sz !== 1) fail('station pad is not 52 x 58: the scaled frame is not ported');
  const yaw = gateSide < 0 ? Math.PI : 0;
  // Heights the scale checks read: the platform top and the canopy soffit (light strips' underside).
  env.scaleProbes = Object.assign(env.scaleProbes || {}, { platform_top: 0.41, canopy_soffit: 7.78 - 0.04 });
  const node = file.node('Station_c' + env.chunkOf(site.x, site.z).join('_'));
  const em = makeEmitter(node);
  em.yawFrame = { x: site.x, z: site.z, yaw };
  // Materials (82-108): [output material, colour].
  const M = {
    asphalt: ['tt_matte', '#65736e'], ivory: ['tt_paint', '#eee8d9'], teal: ['tt_paint', '#477d70'], yellow: ['tt_paint', '#ecc654'],
    glass: ['tt_glass', '#b8dce2'], metal: ['tt_metal', '#586f69'], chalk: ['tt_matte', '#f3edd8'], wood: ['tt_paint', '#927455'],
    rubber: ['tt_matte', '#283531'], strip: ['tt_lamp', '#ffd9a0'], red: ['tt_lamp', '#ffffff'],
  };
  const tinted = { headlamp: ['red', '#fff0cc'], cabin: ['red', '#ffd9a3'], seat: ['teal', '#687978'], tail: ['red', '#e63d24'] };
  const colourOf = (key) => {
    if (tinted[key]) { const [base, tint] = tinted[key]; return [M[base][0], mulHex(M[base][1], tint)]; }
    return [M[key][0], lin(M[key][1])];
  };
  let target = em;
  const box = (x, y, z, w, h, d, key, turn) => {
    const [mat, col] = colourOf(key);
    target.box(mat, x, y, z, w, h, d, col, turn ? [0, Math.sin(turn / 2), 0, Math.cos(turn / 2)] : null);
  };
  const line = (x, z, w, d, key) => box(x, 0.279, z, w, 0.018, d, key || 'chalk');
  const bays = [];
  const bay = (x, z, w, d, kind) => { [-1, 1].forEach((side) => line(x + side * w / 2, z, 0.13, d)); line(x, z + d / 2, w, 0.13); bays.push({ x, z, w, d, kind }); };
  const arrow = (x, z, heading) => {
    const c = Math.cos(heading), s = Math.sin(heading);
    line(x, z, Math.abs(c) > 0.5 ? 3.1 : 0.25, Math.abs(c) > 0.5 ? 0.25 : 3.1);
    [-1, 1].forEach((side) => { const dx = 0.85, dz = side * 0.47; box(x + dx * c - dz * s, 0.286, z + dx * s + dz * c, 1.45, 0.025, 0.21, 'chalk', -heading + side * 0.68); });
  };
  // Pad and platforms (149-155).
  box(0, 0.125, 0, 52, 0.25, 58, 'asphalt');
  box(-5, 0.33, -23, 40, 0.16, 9, 'ivory'); box(-5, 0.33, 25.7, 40, 0.16, 3.8, 'ivory'); box(-24.8, 0.33, -0.3, 2.4, 0.16, 46.8, 'ivory');
  const local = (x, z) => ({ x: site.x + Math.cos(yaw) * x + Math.sin(yaw) * z, z: site.z - Math.sin(yaw) * x + Math.cos(yaw) * z });
  [[-5, -23, 40, 9, 'waiting-platform'], [-5, 25.7, 40, 3.8, 'taxi-platform'], [-24.8, -0.3, 2.4, 46.8, 'west-strip']].forEach(([x, z, w, d, kind]) => {
    const p = local(x, z); env.walkable.push({ kind: 'station-' + kind, x: p.x, z: p.z, w, d, y: 0.41 });
  });
  { const p = local(0, 0); env.walkable.push({ kind: 'station-pad', x: p.x, z: p.z, w: 52, d: 58, y: 0.25 }); }
  [-13, 13].forEach((z, i) => arrow(22, z, i === 0 ? Math.PI : 0));
  for (let dash = -24; dash <= 24; dash += 6) line(17.2, dash, 0.13, 2.8, 'yellow');
  arrow(20.3, 1.5, Math.PI / 2); arrow(-4, 7.7, 0);
  for (let stripe = -20; stripe <= 10; stripe += 2.2) line(stripe, -16.4, 1.1, 2.1);
  // Canopy, strips, columns, booth, benches (157-195).
  box(-5, 8.16, -23, 40, 0.47, 8.8, 'ivory'); box(-5, 7.85, -23, 39.2, 0.17, 8.1, 'wood'); box(-5, 8.12, -18.56, 39.4, 0.24, 0.12, 'teal');
  box(-5, 7.78, -25.4, 38, 0.08, 0.34, 'strip'); box(-5, 7.78, -20.6, 38, 0.08, 0.34, 'strip');
  [-23, -11, 1, 13].forEach((x) => [-26, -20].forEach((z) => {
    solids.begin('station-column', 'station-column-' + x + '-' + z, 0.41);
    box(x, 4.06, z, 0.31, 7.3, 0.31, 'metal'); box(x, 0.56, z, 0.7, 0.3, 0.7, 'ivory');
    solids.end();
  }));
  solids.begin('ticket-booth', 'station-ticket-booth', 0.41);
  box(-21, 2.72, -23.2, 5.8, 4.62, 4.2, 'ivory'); box(-21, 3.0, -21.02, 4.7, 2.2, 0.16, 'glass'); box(-21, 1.88, -20.75, 5.1, 0.2, 0.75, 'teal');
  solids.end();
  [-12, 0, 11].forEach((x) => {
    solids.begin('bench', 'station-bench-' + x, 0.41);
    for (let plank = 0; plank < 3; plank++) { box(x, 1.49, -23.75 + plank * 0.41, 6.8, 0.18, 0.34, 'wood'); box(x, 1.98 + plank * 0.26, -24.12, 6.8, 0.19, 0.13, 'wood'); }
    [-1, 1].forEach((side) => box(x + side * 2.45, 0.96, -23.25, 0.25, 1.05, 1.35, 'metal'));
    solids.end();
  });
  [-17, -5, 7].forEach((x) => bay(x, -7, 7, 16, 'bus'));
  [-18, -8, 2, 12].forEach((x) => bay(x, 18, 6, 9, 'taxi'));
  // Name board and posts (258-259).
  box(-5, 9.87, -18.65, 32, 2.8, 0.38, 'ivory');
  [-17, 7].forEach((x) => box(x, 8.72, -18.65, 0.24, 1.7, 0.24, 'metal'));
  // Anchors for the pictograms that replace the painted text (sign(): 276-292).
  const boardFront = local(-5, -18.435), boardBack = local(-5, -18.865);
  env.stationSigns = {
    board: [{ x: boardFront.x, y: 9.87, z: boardFront.z, facing: [Math.sin(yaw), Math.cos(yaw)], w: 31.6, h: 2.6 },
      { x: boardBack.x, y: 9.87, z: boardBack.z, facing: [-Math.sin(yaw), -Math.cos(yaw)], w: 31.6, h: 2.6 }],
    bays: [-17, -5, 7].map((x) => ({ kind: 'bus', ...local(x, 2.9), y: 0.294, w: 5.4, h: 2.7, yaw }))
      .concat([-18, -8, 2, 12].map((x) => ({ kind: 'taxi', ...local(x, 11.75), y: 0.294, w: 5.2, h: 2.2, yaw }))),
  };
  // Lights: the two canopy strips (lamps clock x 1.7) and the platform light pools (x 0.42).
  [[-5, -25.4], [-5, -20.6]].forEach(([x, z], i) => { const p = local(x, z); lights.lamp({ kind: 'station-canopy', x: p.x, y: 7.7, z: p.z, ground: 0.41, color: '#ffd9a0', range: 16, energy: 0, omni: i === 0, strip_length: 38 }); });
  [[-5, -23, 38, 7], [-5, 25.7, 38, 3]].forEach(([x, z, w, d]) => { const p = local(x, z); lights.pool({ source: 'station', x: p.x, y: 0.45, z: p.z, w, d, level: 0.42, color: '#ffe0b0' }); });

  // ---- vehicle templates (`vehicle`, 196-252), each in its own frame at the origin.
  const templates = {};
  [['bus', true], ['taxi', false]].forEach(([kind, bus]) => {
    const tn = file.node('Station_' + (bus ? 'BusTemplate' : 'TaxiTemplate'));
    const tem = makeEmitter(tn);
    target = tem;
    const x = 0, z = 0, heading = -Math.PI / 2, c = Math.cos(heading), s = Math.sin(heading);
    const length = bus ? 12.6 : 6.9, width = bus ? 4.1 : 3.3;
    const part = (dx, y, dz, w, h, d, key) => box(x + dx * c - dz * s, y, z + dx * s + dz * c, w, h, d, key, -heading);
    part(0, bus ? 1.38 : 1.36, 0, length, bus ? 1.24 : 1.13, width, bus ? 'ivory' : 'yellow');
    const seats = bus ? 6 : 2;
    for (let seat = 0; seat < seats; seat++) {
      const px = bus ? 4.7 - Math.floor(seat / 2) * 3 : seat ? -0.9 : 0.9, pz = seat % 2 ? 0.85 : -0.85;
      part(px, bus ? 2.1 : 1.84, pz, 0.85, 0.65, 0.8, 'seat');
    }
    part(bus ? 5.1 : 1.55, bus ? 2.68 : 2.03, -0.85, 0.13, 0.22, 0.55, 'metal');
    if (bus) part(0, 3.6, 0, 9, 0.045, 0.24, 'cabin');
    part(0, bus ? 1.63 : 0.9, 0, length + 0.06, bus ? 0.62 : 0.2, width + 0.04, bus ? 'teal' : 'metal');
    if (bus) {
      [-1, 1].forEach((side) => {
        part(-0.15, 3.0, side * (width / 2 + 0.045), 11.5, 1.35, 0.11, 'glass');
        for (let pillar = -2; pillar <= 2; pillar++) part(pillar * 2.05, 3.0, side * (width / 2 + 0.11), 0.14, 1.4, 0.11, 'ivory');
      });
      part(length / 2 + 0.045, 2.97, 0, 0.1, 1.52, 3.4, 'glass'); part(-length / 2 - 0.045, 3.0, 0, 0.1, 1.23, 3.35, 'glass');
      [3.7, -2.4].forEach((dx) => { part(dx, 2.29, -width / 2 - 0.08, 1.5, 2.5, 0.13, 'glass'); part(dx, 2.29, -width / 2 - 0.17, 0.1, 2.5, 0.09, 'metal'); });
      part(0, 3.8, 0, 12.45, 0.25, 4.14, 'teal'); part(-1.1, 4.08, 0, 3.5, 0.38, 2.2, 'ivory');
    } else {
      part(-0.3, 2.23, 0, 3.5, 1.0, 2.9, 'glass'); part(-0.3, 2.8, 0, 3.64, 0.18, 3.02, 'yellow');
      [-1, 1].forEach((side) => part(-0.25, 2.26, side * 1.48, 0.15, 1.04, 0.1, 'yellow'));
      part(-0.1, 3.04, 0, 1.2, 0.32, 0.56, 'headlamp'); part(-0.1, 3.075, -0.3, 0.75, 0.12, 0.025, 'yellow');
    }
    const wheel = new T.CylinderGeometry(1, 1, 1, 12), up = new T.Vector3(0, 1, 0), turn = new T.Quaternion().setFromAxisAngle(new T.Vector3(1, 0, 0), Math.PI / 2);
    [-1, 1].forEach((side) => {
      part(length / 2 + 0.04, bus ? 1.53 : 1.48, side * width * 0.31, 0.13, 0.3, bus ? 0.62 : 0.46, 'headlamp');
      part(-length / 2 - 0.04, bus ? 1.59 : 1.49, side * width * 0.31, 0.13, 0.34, 0.38, 'tail');
      const radius = bus ? 0.7 : 0.58;
      [-1, 1].forEach((axle) => {
        const dx = axle * length * 0.31, dz = side * (width / 2 + 0.035), wx = x + dx * c - dz * s, wz = z + dx * s + dz * c;
        const q = new T.Quaternion().setFromAxisAngle(up, -heading).multiply(turn);
        tem.geometry(M.rubber[0], wheel, new T.Matrix4().compose(new T.Vector3(wx, 0.25 + radius, wz), q, new T.Vector3(radius, 0.34, radius)), lin(M.rubber[1]));
        const outside = side * 0.18;
        tem.geometry(M.metal[0], wheel, new T.Matrix4().compose(new T.Vector3(wx - outside * s, 0.25 + radius, wz + outside * c), q, new T.Vector3(radius * 0.44, 0.025, radius * 0.44)), lin(M.metal[1]));
      });
    });
    templates[kind] = { node: tn.name, length_m: length * 0.5, width_m: width * 0.5, height_m: (bus ? 4.205 : 3.135) * 0.5, front: [0, 0, -1],
      note: 'parts at the origin, front toward -z; the wheels rest on y = 0.125 m (upstream pad/road top 0.25 units)' };
  });
  target = em;
  world.vehicles = templates;
  counts.station_bays = bays.length;
  counts.station_benches = 3;
  counts.station_columns = 8;
}

function mulHex(a, b) { const x = lin(a), y = lin(b); return [x[0] * y[0], x[1] * y[1], x[2] * y[2]]; }
