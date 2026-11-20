// Port of upstream's facility bodies: city-facilities.js `create` (lines 773-1600): the mall, hospital and
// secondary school (`windowRows`, `parapet`, `frontPorch`), the seven W1.5b programmes (`storey`, `shutters`,
// `buildTeachingBlock`, `buildHall`, `buildSmallCentre`) and the annexes (`buildClinic`, `buildPrecinct`,
// `buildWaste`, `buildPodium`), plus every `architectureParts` piece (the pure planner, run in the vm), as
// `buildArchitecture` draws them.
//
// Bodies (all floors, frozen at the finished state) merge per chunk into `Facilities_c<ix>_<iz>`; per building:
//   `Windows_<id>`  the light panes (`lightPane`), material tt_window, TEXCOORD_0 = (rank, floor / floors);
//                   upstream lights pane `order` when order < ceil(level x n), i.e. rank = order / n < level.
//   `Door_<id>_<k>` each door leaf (`markDoor`), its origin at the hinge (swing about +Y by angle x open) or
//                   at the leaf centre (slide by the given vector x open); world.json lists the motion.
// Dropped as upstream drops them when its civic GLB is present (`refinedAsset`): the porch hoods, posts,
// skylight frame and hospital roof platform that civic.glb replaces, and the secondary school's entry
// frame/canopy/clerestory parts. The Chinese name boards (`label`, `createCivicSigns`) are replaced by
// world_signs.mjs pictograms. The hospital ward's 13%-opacity window glass is left out (the ward GLB shows
// through the open bays).
import { lin, yawQuat } from './world_core.mjs';

const BASE_Y = 1.4, FLOOR = 6, DOOR_UNITS = 4.2; // design section 1: doors 2.1 m

export function buildFacilities(env) {
  const { T, city, ctx, file, makeEmitter, solids, counts, world } = env;
  const F = ctx.CityFacilities;
  // PALETTES (city-facilities.js:93-101) and `paletteFor` (105-118).
  const PALETTES = {
    mall: { wall: '#c98775', glass: '#886e59', frame: '#e4c99b' },
    hospital: { wall: '#9ac5af', glass: '#557f69', frame: '#f1ecdb' },
    school: { wall: '#e6c47c', glass: '#92734d', frame: '#a55f48' },
    secondary: { wall: '#eee8d9', glass: '#829b94', frame: '#d7cbb7' },
  };
  const civicPalette = F.civicPalette;
  // Materials (create, 795-822): [output material, base colour]. A part's drawn colour is the base colour
  // unless `box` tints it (glass/trim by the landmark palette, the civic palette for the W1.5b kinds), or
  // `buildArchitecture` resolves it (`tintPart`, the drawn colour is the part's own colour).
  const MAT = {
    silver: ['tt_paint', PALETTES.mall.wall], white: ['tt_paint', PALETTES.hospital.wall], ivory: ['tt_paint', PALETTES.school.wall],
    trim: ['tt_metal', '#ffffff'], glass: ['tt_glass', '#ffffff'], gold: ['tt_metal', '#d5ba83'], green: ['tt_paint', '#347b5d'],
    cross: ['tt_paint', '#c9493c'], terracotta: ['tt_matte', '#a95f47'], paving: ['tt_matte', '#e3ddd1'],
  };
  const records = [];

  function newRecord(building, extra) {
    const r = Object.assign({ building, parts: [], panes: [] }, extra || {});
    records.push(r); return r;
  }
  // `box` (create, 940-967): one part in floor-local coordinates (x, z from the building centre; y above the
  // floor's base, BASE_Y + floor x 6; 'roof' is above the last floor).
  function box(record, floor, x, y, z, w, h, d, mat, tilt, extra) {
    const kind = record.building.facility;
    let color = MAT[mat][1];
    if (mat === 'glass' && PALETTES[kind]) color = PALETTES[kind].glass;
    if (mat === 'trim' && PALETTES[kind]) color = PALETTES[kind].frame;
    const pal = civicPalette(kind);
    if (pal) {
      const target = mat === 'green' ? pal.glass : mat === 'gold' ? pal.frame : mat === 'silver' || mat === 'white' || mat === 'ivory' ? pal.wall : null;
      if (target) color = target;
    }
    const part = Object.assign({ floor, x, y, z, w, h, d, mat, color, tilt: tilt || null }, extra || {});
    record.parts.push(part);
    if (mat === 'glass') lightPane(record, floor, x, y, z, w, h, d);
    return part;
  }
  // `lightPane` (930-939): a lit pane just outside a glazed face; not on the hospital.
  function lightPane(record, floor, x, y, z, w, h, d) {
    if (record.building.facility === 'hospital' || typeof floor !== 'number') return;
    const thinX = w < d, dx = thinX ? Math.sign(x) * (w / 2 + 0.025) : 0, dz = thinX ? 0 : Math.sign(z) * (d / 2 + 0.025);
    record.panes.push({ floor, x: x + dx, y, z: z + dz, w: thinX ? 0.018 : w * 0.94, h: h * 0.94, d: thinX ? d * 0.94 : 0.018,
      outward: thinX ? [Math.sign(x) || 1, 0] : [0, Math.sign(z) || 1], ordinal: record.panes.length });
  }
  function markDoor(part, meta) { part.door = meta; return part; }

  // ---- shared vocabulary (1230-1300)
  const GATE = { 'x-': { x: -1, z: 0 }, 'x+': { x: 1, z: 0 }, 'z-': { x: 0, z: -1 }, 'z+': { x: 0, z: 1 } };
  const massOf = (spec) => ({ w: spec.mw || spec.w, d: spec.md || spec.d, z: spec.mz || 0 });
  function storey(record, level, mass, body, course) {
    box(record, level, 0, 3, mass.z, mass.w, 5.86, mass.d, body);
    box(record, level, 0, 0.34, mass.z, mass.w + 0.55, 0.68, mass.d + 0.55, course);
  }
  function shutters(record, level, mass, pane) {
    const kind = record.building.facility;
    const gate = /^(primary|university|library|workshop|depot|market)$/.test(kind) ? F.SITES.find((s) => s.facility === kind).gate : null;
    const win = (x, z, w, d) => {
      const thinX = w < d, nx = thinX ? Math.sign(x) : 0, nz = thinX ? 0 : Math.sign(z - mass.z);
      box(record, level, x, 3.2, z, w, 3.5, d, pane);
      lightPane(record, level, x, 3.2, z, w, 3.5, d);
      record.parts.push({ floor: level, x, y: 3.2, z, trim: Math.atan2(nx, nz), mat: 'gold', color: civicPalette(kind).frame });
    };
    const cols = Math.max(2, Math.round(mass.w / 8)), rows = Math.max(2, Math.round(mass.d / 8));
    for (let i = 0; i < cols; i++) {
      const x = (i - (cols - 1) / 2) * (mass.w - 4) / cols;
      if (gate !== 'z+') win(x, mass.z + mass.d / 2 + 0.09, 3.5, 0.2);
      if (gate !== 'z-') win(x, mass.z - mass.d / 2 - 0.09, 3.5, 0.2);
    }
    for (let j = 0; j < rows; j++) {
      const z = mass.z + (j - (rows - 1) / 2) * (mass.d - 4) / rows;
      win(mass.w / 2 + 0.09, z, 0.2, 3.5); win(-mass.w / 2 - 0.09, z, 0.2, 3.5);
    }
  }
  const column = (record, floor, x, z, size, height, mat) => box(record, floor, x, height / 2, z, size, height, size, mat);
  function parapetFor(record, mat, w, d, z) {
    z = z || 0;
    box(record, 'roof', 0, 0.2, z, w + 0.9, 0.4, d + 0.9, mat);
    [-1, 1].forEach((side) => { box(record, 'roof', 0, 0.95, z + side * (d / 2 + 0.3), w + 0.8, 1.1, 0.48, mat); box(record, 'roof', side * (w / 2 + 0.3), 0.95, z, 0.48, 1.1, d + 0.8, mat); });
  }
  function frameOf(spec, mass) {
    const g = GATE[spec.gate], onZ = g.z !== 0, facade = onZ ? mass.z + g.z * mass.d / 2 : g.x * mass.w / 2;
    const edge = ((onZ ? g.z * spec.d : g.x * spec.w) / 2) - (onZ ? g.z : g.x) * 1.5;
    return { g, onZ, facade, dir: edge > facade ? 1 : -1, span: Math.abs(edge - facade), mass, lateral: onZ ? spec.w : spec.d };
  }
  function annexFrame(annex) {
    const g = GATE[annex.gate], onZ = g.z !== 0, mass = { w: annex.w, d: annex.d, z: 0 };
    return { g, onZ, facade: onZ ? g.z * annex.d / 2 : g.x * annex.w / 2, dir: onZ ? g.z : g.x, span: 3, mass, lateral: onZ ? annex.w : annex.d };
  }
  const at = (frame, out, along) => { const line = frame.facade + frame.dir * out; return frame.onZ ? { x: along, z: line } : { x: line, z: frame.mass.z + along }; };
  function pad(record, frame, o0, o1, a0, a1, mat, height) {
    const spot = at(frame, (o0 + o1) / 2, (a0 + a1) / 2), depth = Math.abs(o1 - o0), wide = Math.abs(a1 - a0);
    box(record, 0, spot.x, height === undefined ? -0.24 : height / 2, spot.z, frame.onZ ? wide : depth, height === undefined ? 0.48 : height, frame.onZ ? depth : wide, mat);
  }
  const yardOf = (record, frame) => pad(record, frame, 0, frame.span, -frame.lateral / 2 + 2.5, frame.lateral / 2 - 2.5, 'paving');
  function portal(record, frame, mat) {
    const door = at(frame, -0.1, 0);
    const leaf = box(record, 0, door.x, 2, door.z, frame.onZ ? 5.4 : 0.3, 4, frame.onZ ? 0.3 : 5.4, 'green');
    markDoor(leaf, frame.onZ ? { hinge: [door.x - 2.7, 2, door.z], angle: -frame.dir * 1.45 } : { hinge: [door.x, 2, door.z - 2.7], angle: frame.dir * 1.45 });
    const hood = at(frame, 0.6, 0);
    box(record, 0, hood.x, 4.5, hood.z, frame.onZ ? 7.6 : 1.2, 0.5, frame.onZ ? 1.2 : 7.6, mat);
    [-1, 1].forEach((side) => { const post = at(frame, 0.55, side * 4.3); box(record, 0, post.x, 2.2, post.z, 0.5, 4.4, 0.5, mat); });
  }
  function flagpole(record, x, z) {
    box(record, 'roof', x, 0.3, z, 1.2, 0.6, 1.2, 'paving'); box(record, 'roof', x, 4.4, z, 0.22, 8.2, 0.22, 'gold'); box(record, 'roof', x + 1.4, 7.1, z, 2.6, 1.6, 0.14, 'cross');
  }
  function buildTeachingBlock(record, site, body, course, roofMat, options) {
    const mass = massOf(site), frame = frameOf(site, mass);
    for (let level = 0; level < site.floors; level++) { storey(record, level, mass, body, course); shutters(record, level, mass, 'green'); }
    yardOf(record, frame);
    box(record, 'roof', 0, 0.55, mass.z, mass.w + 1.6, 0.7, mass.d + 1.6, roofMat);
    parapetFor(record, body, mass.w, mass.d, mass.z);
    portal(record, frame, course);
    if (options.bell) {
      box(record, 'roof', 0, 1.6, mass.z - 4, 4.5, 2, 4, body); box(record, 'roof', 0, 2.7, mass.z - 4, 5.2, 0.3, 4.7, roofMat);
      const flag = at(frame, frame.span / 2, -site.w / 2 + 7); flagpole(record, flag.x, flag.z);
    }
    if (options.colonnade) {
      const spread = mass.w - 10, attic = at(frame, 1.6, 0);
      box(record, 'roof', attic.x, 1.5, attic.z, frame.onZ ? spread + 5 : 2.4, 2.4, frame.onZ ? 2.4 : spread + 5, body);
    }
  }
  function buildHall(record, site, body, course, roofMat, options) {
    const mass = massOf(site), frame = frameOf(site, mass);
    for (let level = 0; level < site.floors; level++) { storey(record, level, mass, body, course); shutters(record, level, mass, 'green'); }
    yardOf(record, frame);
    box(record, 'roof', 0, 0.5, mass.z, mass.w + 1.4, 0.6, mass.d + 1.4, course);
    if (options.sawTooth) {
      const bays = 5, span = mass.w / bays;
      for (let i = 0; i < bays; i++) {
        const x = (i - (bays - 1) / 2) * span;
        box(record, 'roof', x, 1.9, mass.z, span - 0.6, 0.32, mass.d, body, { z: -0.4 });
        box(record, 'roof', x + (span - 0.6) / 2 - 0.3, 3, mass.z, 0.3, 2.3, mass.d - 2, 'green');
      }
    } else if (options.barrel) {
      const ribs = 5, step = mass.d / ribs;
      for (let r = 0; r < ribs; r++) box(record, 'roof', 0, 1.55 + (r === 0 || r === ribs - 1 ? -0.45 : 0.35), mass.z + (r - (ribs - 1) / 2) * step, mass.w + 1, 0.55, step * 0.9, roofMat);
      box(record, 'roof', 0, 2.9, mass.z, mass.w + 1.6, 0.5, 2.2, course);
    } else box(record, 'roof', 0, 1.7, mass.z, mass.w + 1.4, 1.2, mass.d + 0.8, roofMat, { x: 0.07 });
    if (options.containers) {
      [[-3, 'gold'], [5, 'terracotta'], [13, 'green']].forEach((crate) => {
        const spot = at(frame, frame.span * 0.62, crate[0]);
        box(record, 0, spot.x, 1.5, spot.z, frame.onZ ? 6.2 : 3.4, 2.7, frame.onZ ? 3.4 : 6.2, crate[1]);
        box(record, 0, spot.x, 3.05, spot.z, frame.onZ ? 6.4 : 3.6, 0.3, frame.onZ ? 3.6 : 6.4, 'paving');
      });
    }
    parapetFor(record, body, mass.w, mass.d, mass.z);
    portal(record, frame, course);
  }
  function buildSmallCentre(record, site) {
    const mass = massOf(site), frame = frameOf(site, mass);
    for (let level = 0; level < site.floors; level++) {
      storey(record, level, mass, 'silver', 'gold'); shutters(record, level, mass, 'green');
      [-1, 1].forEach((side) => box(record, level, side * (mass.w / 2 + 0.2), 1.3, mass.z, 0.4, 2.6, mass.d - 4, 'gold'));
    }
    yardOf(record, frame);
    box(record, 'roof', 0, 0.55, mass.z, mass.w + 1.6, 0.7, mass.d + 1.6, 'silver');
    const board = at(frame, -0.4, 0);
    box(record, 'roof', board.x, 2.05, board.z, frame.onZ ? mass.w - 10 : 0.9, 2.3, frame.onZ ? 0.9 : mass.w - 10, 'gold');
    box(record, 'roof', 7, 1.35, mass.z + 7, 5.2, 1.3, 4, 'white'); box(record, 'roof', 7, 2.08, mass.z + 7, 5.6, 0.16, 4.4, 'gold');
    parapetFor(record, 'silver', mass.w, mass.d, mass.z);
    portal(record, frame, 'gold');
  }
  const PROGRAMMES = {
    primary: (r, s) => buildTeachingBlock(r, s, 'ivory', 'terracotta', 'ivory', { bell: true }),
    university: (r, s) => buildTeachingBlock(r, s, 'silver', 'ivory', 'ivory', { colonnade: true }),
    library: (r, s) => buildTeachingBlock(r, s, 'ivory', 'gold', 'white', { colonnade: true }),
    workshop: (r, s) => buildHall(r, s, 'white', 'silver', 'silver', { sawTooth: true }),
    depot: (r, s) => buildHall(r, s, 'white', 'silver', 'silver', { containers: true }),
    market: (r, s) => buildHall(r, s, 'silver', 'terracotta', 'ivory', { barrel: true }),
    'annex-mall': buildSmallCentre,
  };
  function buildClinic(record, annex) {
    const mass = { w: annex.w, d: annex.d, z: 0 }, frame = annexFrame(annex);
    storey(record, 0, mass, 'white', 'paving'); shutters(record, 0, mass, 'green');
    box(record, 0, 0, 3.75, 0, mass.w + 1.2, 0.7, mass.d + 1.2, 'terracotta');
    portal(record, frame, 'paving');
    const sign = at(frame, 0.3, 0);
    box(record, 0, sign.x, 4.9, sign.z, frame.onZ ? 3.4 : 0.26, 1.15, frame.onZ ? 0.26 : 3.4, 'cross');
    box(record, 0, sign.x, 4.3, sign.z, frame.onZ ? 1.15 : 0.26, 2.3, frame.onZ ? 0.26 : 1.15, 'cross');
  }
  function buildPrecinct(record, annex) {
    const mass = { w: annex.w, d: annex.d, z: 0 }, frame = annexFrame(annex);
    storey(record, 0, mass, 'ivory', 'gold'); shutters(record, 0, mass, 'green');
    box(record, 0, 0, 4.1, 0, mass.w + 1.6, 0.7, mass.d + 1.6, 'ivory');
    box(record, 'roof', 0, 0.22, 0, mass.w + 0.6, 0.35, mass.d + 0.6, 'ivory');
    box(record, 'roof', 0, 0.66, 0, frame.onZ ? 2.8 : 0.7, 0.36, frame.onZ ? 0.7 : 2.8, 'cross');
    box(record, 'roof', 0, 0.93, 0, frame.onZ ? 3 : 0.85, 0.12, frame.onZ ? 0.85 : 3, 'paving');
    portal(record, frame, 'gold');
  }
  function buildWaste(record, annex) {
    const mass = { w: annex.w, d: annex.d, z: 0 }, frame = annexFrame(annex);
    storey(record, 0, mass, 'white', 'silver');
    box(record, 0, 0, 4.3, 0, mass.w + 1.4, 0.7, mass.d + 1.4, 'silver');
    box(record, 'roof', 0, 0.23, 0, mass.w + 0.5, 0.34, mass.d + 0.5, 'ivory');
    const door = at(frame, -0.1, 0);
    const leaf = box(record, 0, door.x, 2.1, door.z, frame.onZ ? mass.w - 2.5 : 0.3, 4.2, frame.onZ ? 0.3 : mass.w - 2.5, 'green');
    markDoor(leaf, frame.onZ ? { slide: [-(mass.w - 2.5) * 0.62, 0] } : { slide: [0, -(mass.w - 2.5) * 0.62] });
  }
  function buildPodium(record, annex, floors) {
    const mass = { w: annex.w, d: annex.d, z: 0 }, frame = annexFrame(annex);
    for (let level = 0; level < floors; level++) { storey(record, level, mass, 'ivory', 'gold'); shutters(record, level, mass, 'green'); }
    const bays = Math.max(3, Math.round(annex.w / 7));
    for (let i = 0; i < bays; i++) {
      const post = at(frame, 1.1, (i - (bays - 1) / 2) * (annex.w - 3) / bays);
      for (let cf = 0; cf < floors; cf++) column(record, cf, post.x, post.z, 1.35, cf === floors - 1 ? 4.8 : 6, 'ivory');
    }
    const cornice = at(frame, 1.5, 0);
    box(record, 'roof', cornice.x, -0.3, cornice.z, frame.onZ ? annex.w + 0.4 : 2.6, 0.8, frame.onZ ? 2.6 : annex.w + 0.4, 'gold');
    const step = at(frame, 2.1, 0);
    box(record, 0, step.x, 0.3, step.z, frame.onZ ? annex.w - 2 : 3.2, 0.6, frame.onZ ? 3.2 : annex.w - 2, 'paving');
    box(record, 'roof', 0, 0.5, 0, annex.w + 1.4, 0.8, annex.d + 1.4, 'ivory');
    box(record, 'roof', annex.w * 0.28, 1.08, annex.d * 0.15, 3.2, 0.7, 2.3, 'white');
  }
  const ANNEX_BUILDERS = { clinic: buildClinic, precinct: buildPrecinct, waste: buildWaste, bank: buildPodium };

  // ---- the landmark trio (`windowRows`, `parapet`, `frontPorch`, `corners`)
  const hasRoom = (record, floor) => record.building.facility === 'hospital' && floor === 3 && record.building.floors > 3 && record.building.w === 44 && record.building.d === 48;
  const corners = (record, floor, mat, width) => [-1, 1].forEach((x) => [-1, 1].forEach((z) => box(record, floor, x * 21.45, 3, z * 23.45, width, 5.9, width, mat)));
  function windowRows(record, floor, wall, accent, hospital, recessedWest) {
    if (hasRoom(record, floor)) {
      [-1, 1].forEach((side) => box(record, floor, side * 15.1, 3, 0, 13.8, 5.82, 48, wall));
      box(record, floor, 0, 3, 3.3, 16.4, 5.82, 41.4, wall);
      box(record, floor, 0, 5.745, -20.475, 16.4, 0.33, 6.15, wall);
      box(record, floor, 0, 0.8825, -23.775, 16.4, 1.585, 0.45, wall);
      box(record, floor, 0, 5.3675, -23.775, 16.4, 1.085, 0.45, wall);
      [[-8, 0.4], [-2.85, 1.5], [2.85, 1.5], [8, 0.4]].forEach((pier) => box(record, floor, pier[0], 3.25, -23.775, pier[1], 3.15, 0.45, wall));
    } else box(record, floor, recessedWest ? 0.15 : 0, 3, 0, recessedWest ? 43.7 : 44, 5.82, 48, wall);
    box(record, floor, 0, 0.23, 0, 44.65, 0.46, 48.65, accent);
    [-1, 1].forEach((side) => {
      for (let i = 0; i < 7; i++) {
        const x = (i - 3) * 5.7;
        // The ward bays (room glass, 13% opacity upstream) stay open onto hospital_room.glb.
        if (!(hasRoom(record, floor) && side < 0 && i >= 2 && i <= 4)) box(record, floor, x, 3.25, side * 24.08, 4.2, 3.15, 0.18, 'glass');
        box(record, floor, x, 3.25, side * 24.22, 0.14, 3.19, 0.14, 'trim');
        box(record, floor, x, 1.63, side * 24.3, 4.65, 0.22, 0.65, wall);
      }
      for (let j = 0; j < 8; j++) {
        if (recessedWest && floor === 0 && side < 0 && (j === 3 || j === 4)) continue;
        const z = (j - 3.5) * 5.6, west = recessedWest && side < 0;
        box(record, floor, west ? -21.78 : side * 22.08, 3.25, z, 0.18, 3.15, 4.05, 'glass');
        box(record, floor, west ? -21.85 : side * 22.22, 3.25, z, 0.14, 3.19, 0.14, 'trim');
        if (!hospital) box(record, floor, side * 22.32, 1.63, z, 0.65, 0.22, 4.5, wall);
      }
    });
    if (hospital) { box(record, floor, -19.1, 3, -24.34, 1.15, 5.85, 0.42, 'green'); box(record, floor, 19.1, 3, 24.34, 1.15, 5.85, 0.42, 'green'); }
    corners(record, floor, wall, 0.95);
  }
  function parapet(record, mat) {
    box(record, 'roof', 0, 0.2, 0, 44.9, 0.4, 48.9, mat);
    [-1, 1].forEach((side) => { box(record, 'roof', 0, 0.95, side * 24.15, 44.8, 1.1, 0.48, mat); box(record, 'roof', side * 22.15, 0.95, 0, 0.48, 1.1, 48.8, mat); });
  }
  function frontPorch(record, mat, wide) {
    const leafWide = (wide - 2) / 2;
    [-1, 1].forEach((side) => markDoor(box(record, 0, side * leafWide / 2, 2.2, -24.18, leafWide, 4.35, 0.35, 'glass'), { slide: [side * leafWide * 0.92, 0] }));
    box(record, 0, 0, 2.2, -24.42, 0.24, 4.4, 0.16, 'trim');
    box(record, 0, 0, -0.24, -25.05, wide + 1, 0.48, 4, 'paving');
  }
  // `buildArchitecture` (1185-1210): the planner's parts, drawn in the part's own resolved colour.
  const ROLE = { white: 'white', glass: 'silver', gold: 'gold', cross: 'cross', green: 'green', terracotta: 'terracotta', paving: 'paving', ivory: 'ivory', silver: 'silver' };
  function buildArchitecture(record, spec) {
    const plan = F.architectureParts(record.building, spec);
    plan.parts.forEach((p) => {
      if (record.building.facility === 'secondary' && /^(school-entry-frame|school-entry-mullion|school-entry-canopy|school-roof-clerestory|school-roof-cap)$/.test(p.feature)) return;
      const mat = ROLE[p.material];
      const part = { floor: p.floor, x: p.x, y: p.y, z: p.z, w: p.w, h: p.h, d: p.d, mat, color: p.color, tilt: p.tilt || null, feature: p.feature };
      if (p.door) part.door = Object.assign({}, p.door);
      record.parts.push(part);
      if (p.material === 'glass') lightPane(record, p.floor, p.x, p.y, p.z, p.w, p.h, p.d);
    });
    record.architecture = plan;
  }

  // ---- the buildings (1500-1567) and the annexes (1569-1592)
  city.buildings.filter((b) => F.SITES.some((s) => s.facility === b.facility)).forEach((building) => {
    const record = newRecord(building);
    const site = F.SITES.find((s) => s.facility === building.facility), kind = building.facility;
    if (kind === 'mall') {
      for (let level = 0; level < building.floors; level++) {
        box(record, level, 0, 3, 0, 44, 5.86, 48, 'silver'); box(record, level, 0, 0.36, 0, 45, 0.72, 49, 'silver');
        [-1, 1].forEach((side) => {
          box(record, level, 0, 3.35, side * 24.07, 40.8, 3.9, 0.2, 'glass'); box(record, level, side * 22.07, 3.35, 0, 0.2, 3.9, 44.8, 'glass');
          box(record, level, 0, 1.29, side * 24.28, 42.3, 0.19, 0.52, 'gold'); box(record, level, side * 22.28, 1.29, 0, 0.52, 0.19, 46.3, 'gold');
          for (let span = -3; span <= 3; span++) { box(record, level, span * 5.55, 3.35, side * 24.21, 0.18, 3.94, 0.16, 'trim'); box(record, level, side * 22.21, 3.35, span * 6.2, 0.16, 3.94, 0.18, 'trim'); }
        });
        corners(record, level, 'gold', 1.15);
      }
      box(record, 0, 0, -0.56, 0, 46, 1.12, 50, 'paving');
      frontPorch(record, 'gold', 22);
      parapet(record, 'silver');
      [-1, 1].forEach((side) => box(record, 'roof', side * 4.7, 2.65, 1, 9.85, 0.18, 23, 'glass', { z: -side * 0.28 }));
      [0, 1].forEach((side) => {
        const shell = (sx, sy, sz, w, h, d) => box(record, 'roof', side ? sz : sx, sy, side ? sx : sz, side ? d : w, h, side ? w : d, 'silver');
        shell(0, 3.45, side ? -21.75 : -23.75, 23, 6.1, 0.12);
        const z = side ? -22.06 : -24.06;
        [-1, 1].forEach((sign) => { shell(sign * 11.3, 3.45, z, 0.4, 6.1, 0.75); shell(0, 3.45 + sign * 2.9, z, 22.6, 0.3, 0.75); });
      });
    } else if (kind === 'hospital') {
      for (let level = 0; level < building.floors; level++) windowRows(record, level, 'white', 'trim', true);
      box(record, 0, 0, -0.56, 0, 46, 1.12, 50, 'paving');
      frontPorch(record, 'green', 18);
      parapet(record, 'trim');
      box(record, 'roof', 16, 6.2, -24.06, 7.5, 8.6, 0.75, 'trim'); box(record, 'roof', 16, 6.2, -24.57, 5.8, 1.9, 0.3, 'cross'); box(record, 'roof', 16, 6.2, -24.57, 1.9, 6.2, 0.32, 'cross');
      box(record, 'roof', 7, 3.48, 6, 8.3, 0.18, 2.5, 'cross'); box(record, 'roof', 7, 3.49, 6, 2.5, 0.2, 8.3, 'cross');
      box(record, 'roof', 0, 3.45, -24.06, 23, 6.1, 0.75, 'trim'); box(record, 'roof', -22.06, 3.45, 0, 0.75, 6.1, 23, 'trim');
    } else if (kind === 'secondary') {
      for (let level = 0; level < building.floors; level++) windowRows(record, level, 'ivory', 'trim', false, true);
      box(record, 0, 0, -0.56, 0, 46, 1.12, 50, 'paving');
      box(record, 0, -23.05, -0.26, 0, 3.4, 0.52, 15.2, 'paving');
      parapet(record, 'ivory');
      buildArchitecture(record, site);
    } else if (PROGRAMMES[kind]) {
      const sized = Object.assign({}, site, { floors: building.floors });
      box(record, 0, 0, -0.56, 0, site.w + 2, 1.12, site.d + 2, 'paving');
      PROGRAMMES[kind](record, sized);
      buildArchitecture(record, sized);
    }
  });
  (city.annexes || []).forEach((annex) => {
    const host = city.buildings.find((b) => b.id === annex.host), builder = ANNEX_BUILDERS[annex.facility], spot = F.annexAt(annex, host);
    if (!spot || !builder) return;
    const record = newRecord({ id: annex.id, facility: annex.facility, x: spot.x, z: spot.z, w: spot.w, d: spot.d, floors: annex.floors }, { annex, host });
    builder(record, annex, annex.floors);
    buildArchitecture(record, annex);
  });

  // ---- doors to 2.1 m (design section 1): a leaf lower than 4.2 units grows upward from its sill, and the
  // frame and mullion of the same doorway grow with it.
  let raised = 0;
  records.forEach((record) => record.parts.filter((p) => p.door).forEach((leaf) => {
    const delta = DOOR_UNITS - leaf.h;
    if (delta <= 1e-9) return;
    const stem = (leaf.feature || '').replace(/-(glass|door)$/, '');
    record.parts.forEach((p) => {
      if (p === leaf || p.floor !== leaf.floor || !p.feature || p.door) return;
      if (p.feature === stem + '-frame' || p.feature === stem + '-mullion' || p.feature === stem + '-door-frame') { p.h += delta; p.y += delta / 2; }
    });
    leaf.h = DOOR_UNITS; leaf.y += delta / 2; raised++;
    if (leaf.door.hinge) leaf.door.hinge = [leaf.door.hinge[0], leaf.y, leaf.door.hinge[2]];
  }));

  // ---- emit: one node per building, its windows and door leaves.
  const doors = [];
  let paneTotal = 0;
  records.forEach((record) => {
    const b = record.building, id = b.id.replace(/-/g, '_');
    // Bodies merge per chunk (the chunk of the building centre); windows and doors stay nodes of their own.
    const [cx, cz] = env.chunkOf(b.x, b.z);
    const node = file.node('Facilities_c' + cx + '_' + cz);
    const em = makeEmitter(node);
    let top = -Infinity;
    const floorY = (floor) => BASE_Y + (floor === 'roof' ? b.floors * FLOOR : floor * FLOOR);
    const toWorld = (p) => [b.x + p.x, floorY(p.floor) + p.y, b.z + p.z];
    const trimNodes = [];
    solids.begin('building', b.id, BASE_Y, { building: b.id });
    record.parts.forEach((p, i) => {
      if (p.door) return;
      const c = toWorld(p);
      if (p.trim !== undefined) { trimNodes.push([c, p]); return; }
      const q = p.tilt ? eulerQuat(T, p.tilt) : null;
      const col = lin(p.color);
      if (p.mat === 'paving' && p.floor === 0 && p.y < 0) {
        // Plinths and yards are walking surfaces, not obstacles.
        solids.pause();
        em.box(MAT[p.mat][0], c[0], c[1], c[2], p.w, p.h, p.d, col, q);
        solids.resume();
        env.walkable.push({ kind: 'facility-yard', building: b.id, x: c[0], z: c[2], w: p.w, d: p.d, y: c[1] + p.h / 2 });
        return;
      }
      em.box(MAT[p.mat][0], c[0], c[1], c[2], p.w, p.h, p.d, col, q);
      top = Math.max(top, c[1] + p.h / 2);
      void i;
    });
    solids.end();
    record.top = top;
    // Window trims (`shutters`' shared 18-triangle frame): a back sheet, the sill and the mullion.
    trimNodes.forEach(([c, p]) => {
      const q = yawQuat(p.trim), col = lin(p.color);
      const piece = (w, h, d, y, z, keep) => {
        const off = rotateYaw(p.trim, [0, y, z]);
        em.emitMasked(MAT.gold[0], c[0] + off[0], c[1] + off[1], c[2] + off[2], w, h, d, col, q, keep);
      };
      piece(3.86, 3.86, 0.22, 0, -0.05, [4]); piece(3.94, 0.18, 0.56, -1.79, 0.09, [0, 1, 2, 3, 4]); piece(0.12, 3.48, 0.12, 0, 0.21, [0, 1, 4]);
    });
    // Window panes: the outward face only, with their rank.
    if (record.panes.length) {
      const wn = file.node('Windows_' + id), wem = makeEmitter(wn);
      const n = record.panes.length;
      const order = record.panes.slice().sort((a, c) => (Math.imul(a.ordinal + 1, 2654435761) >>> 0) - (Math.imul(c.ordinal + 1, 2654435761) >>> 0));
      order.forEach((p, k) => { p.order = k; });
      record.panes.forEach((p) => {
        const c = toWorld(p), face = p.outward[0] > 0 ? 0 : p.outward[0] < 0 ? 1 : p.outward[1] > 0 ? 4 : 5;
        wem.emitMasked('tt_window', c[0], c[1], c[2], p.w, p.h, p.d, lin('#ffd69a'), null, [face], { uv: [p.order / n, (typeof p.floor === 'number' ? p.floor : b.floors) / Math.max(1, b.floors)] });
      });
      paneTotal += n;
      world.windows.push({ node: 'Windows_' + id, building: b.id, panes: n, colour: '#ffd69a', albedo: '#ffdea6', rule: 'lit when TEXCOORD_0.x < light level (city-facilities.js refreshLights)' });
    }
    // Door leaves: each its own node, origin at the hinge (or the leaf centre for a slide).
    record.parts.filter((p) => p.door).forEach((p, k) => {
      const c = toWorld(p), name = 'Door_' + id + '_' + k;
      const dn = file.node(name);
      const pivot = p.door.hinge ? [b.x + p.door.hinge[0], floorY(p.floor) + p.door.hinge[1], b.z + p.door.hinge[2]] : c;
      dn.origin = pivot; dn.translation = pivot.map((v) => v * 0.5);
      makeEmitter(dn).box(MAT[p.mat][0], c[0], c[1], c[2], p.w, p.h, p.d, lin(p.color), p.tilt ? eulerQuat(T, p.tilt) : null, { keepBottom: true });
      doors.push({ node: name, building: b.id, height_m: p.h * 0.5, width_m: Math.max(p.w, p.d) * 0.5,
        motion: p.door.hinge ? { kind: 'swing', axis: [0, 1, 0], angle: p.door.angle } : { kind: 'slide', offset_m: [p.door.slide[0] * 0.5, 0, p.door.slide[1] * 0.5] },
        rule: 'open fraction = the building doorOpen of the town view (city-facilities.js refreshDoors)' });
    });
  });
  world.doors.push(...doors);
  records.forEach((r) => { world.buildings[r.building.id] = { body: 'Facilities_c' + env.chunkOf(r.building.x, r.building.z).join('_'), floors: r.building.floors,
    top_m: r.top * 0.5, windows: r.panes.length ? 'Windows_' + r.building.id.replace(/-/g, '_') : null }; });
  counts.facility_buildings = records.filter((r) => !r.annex).length;
  counts.facility_annexes = records.filter((r) => r.annex).length;
  counts.facility_parts = records.reduce((n, r) => n + r.parts.length, 0);
  counts.facility_window_panes = paneTotal;
  counts.facility_doors = doors.length;
  counts.facility_doors_raised = raised;
  env.facilityRecords = records;
}

function eulerQuat(T, tilt) {
  const q = new T.Quaternion().setFromEuler(new T.Euler(tilt.x || 0, tilt.y || 0, tilt.z || 0));
  return [q.x, q.y, q.z, q.w];
}
function rotateYaw(a, v) { const c = Math.cos(a), s = Math.sin(a); return [v[0] * c + v[2] * s, v[1], -v[0] * s + v[2] * c]; }
