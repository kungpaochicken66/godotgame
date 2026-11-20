#!/usr/bin/env node
// Thousand Town map data extractor (design/thousand-town.md, sections 0-2 and 12).
//
// Runs upstream's own pure layout planners in Node, in the page's build order, freezes the town at its
// finished state, converts every length to metres (upstream x 0.5) and writes game/thousand_town/data/:
//   town.json            the whole map: board, lots, buildings and doors, annexes, places, roads, crossings,
//                        bridges, canal, walks, transit, trees, waterfront, landmarks, frontage parts,
//                        facility and office parts, mesh metadata, and the source/licence block
//   district.glb         upstream's embedded tower-module GLB, decoded and rescaled to metres
//   housing.glb          upstream's embedded housing-module GLB, decoded and rescaled to metres
//   amusement.glb, civic.glb, hospital_room.glb, landscape.glb
//                        upstream's packed position/normal/colour/index arrays written as glTF 2.0 binaries
//                        (vertex colours are linear, stored as linear COLOR_0), in metres
//   *.glb.import         importer="keep", so Godot exports the files as they are and the game reads them at
//                        run time with GLTFDocument
//
//   node scripts/thousand_town/extract.mjs              write game/thousand_town/data/
//   node scripts/thousand_town/extract.mjs --out DIR    write to DIR instead (used for the byte-identity check)
//   node scripts/thousand_town/extract.mjs --check      regenerate in memory and compare every byte with the files
//
// Upstream is the pinned, read-only copy of https://github.com/YiHuiShiBY/thousand-town (CC BY 4.0). It is
// untrusted data: nothing runs from inside that folder, the pinned commit is checked, and every upstream file
// this script reads (executed or cited for constants) must match the SHA-256 recorded in FILES below. The
// planners run in a bare vm context with no require, process or Buffer; Math.random and Date throw there.
//
// Output rules: object keys sorted, integers as integers, every other number rounded to 4 decimals (0.1 mm)
// with trailing zeros removed, no timestamps. Two runs give byte-identical files.
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import zlib from 'node:zlib';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const UPSTREAM = path.join(ROOT, 'build', 'dual-host', 'thousand-town', 'upstream', 'thousand-town-1332ef2');
const DEFAULT_OUT = path.join(ROOT, 'game', 'thousand_town', 'data');
const COMMIT = '1332ef29d6208a4192bf7400e0085033fd773a3c';
const S = 0.5;  // metres per upstream unit (design/thousand-town.md section 1)

// The page's defaults (sketch.js:10). createCity reads density, skyline and playground; housing.decorate
// reads housing and skyline. The layout is the identity permutation (no ?layout= in the URL).
const SETTINGS = { seed: 20260818, density: 0.8, skyline: 1, speed: 1, daySpeed: 1, dreamLight: 0.7,
  stone: '#ece5d9', glass: '#8fa9ab', ground: '#d8d2c7', blenderModel: true, housingBlenderModel: true,
  playground: true, housing: true };

// Every upstream file this script reads, with its SHA-256 at the pinned commit. EXEC files run in the vm
// context, in index.html's script order; CITED files are only read for constants quoted in this script
// (each use names its file and line), and are hashed so a changed copy fails loudly instead of drifting.
const EXEC = [
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
const CITED = [
  ['sketch.js', 'd5162cedf2c12870b2d4e1a2566f72ffc2cdf169556cc1cc1712ccd1127bc423'],
  ['city-housing.js', '26dedc2b44c916befb44ade2a3ad4a60eff8027a332725e7d9a0250d35e66d4e'],
  ['city-transit.js', '70cf912a7651b0614745d53e16e110fb2e1f1da1d53279535a78f7dcbdeaacbe'],
  ['city-landmarks.js', 'bda5217fcb35742e0ca991b4eb95665e390c2b9ff0f320bda7af7381dce450ad'],
  ['city-materials.js', '09a4e885687ae9d4bde7147eb3c4bc8440b72debef4ae6d5d58ca2e34048151d'],
  ['assets/city-ground.runtime.min.js', '108bf59d06c69590d9f3d36999f550348472982e747f093210452ae3bece3f9a'],
  ['LICENSE', '9ba9550ad48438d0836ddab3da480b3b69ffa0aac7b7878b5a0039e7ab429411'],
];

function fail(message) {
  console.error('extract.mjs: ' + message);
  process.exit(1);
}

// ---------------------------------------------------------------------------------------------- upstream

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

function readVerified(rel, expected) {
  const file = path.join(UPSTREAM, rel);
  if (!fs.existsSync(file)) fail('missing upstream file ' + rel);
  const bytes = fs.readFileSync(file);
  const actual = crypto.createHash('sha256').update(bytes).digest('hex');
  if (actual !== expected) fail('SHA-256 mismatch for ' + rel + ': ' + actual + ' (expected ' + expected + ')');
  return bytes.toString('utf8');
}

function loadUpstream() {
  checkCommit();
  for (const [rel, sha] of CITED) readVerified(rel, sha);
  // A bare context: the UMD wrappers see no `module` and no `require`, so each one registers its API on
  // the context's global object exactly as the page's <script> tags do.
  const ctx = { console: { log() {}, warn() {}, error() {}, info() {} }, atob: globalThis.atob };
  ctx.globalThis = ctx; ctx.window = ctx; ctx.self = ctx;
  vm.createContext(ctx);
  vm.runInContext('Math.random = function () { throw new Error("Math.random is not deterministic"); };' +
    'Date = function () { throw new Error("Date is not deterministic"); }; Date.now = Date;', ctx);
  for (const [rel, sha] of EXEC) {
    const source = readVerified(rel, sha);
    try {
      vm.runInContext(source, ctx, { filename: 'upstream/' + rel });
    } catch (error) {
      fail('loading ' + rel + ' failed: ' + error.message);
    }
  }
  for (const api of ['CityRandom', 'CityModel', 'CityLife', 'CityFacilities', 'CityPlaces', 'CityHousingPlan',
    'CityLayout', 'CityWaterfront', 'CityFrontage', 'CityTransitMotion', 'CityHelipad', 'CityDistrict',
    'CityFountain', 'CityDistrictAsset', 'CityHousingAsset', 'CityAmusementAsset', 'CityCivicAsset',
    'CityHospitalRoomAsset', 'CityLandscapeAsset']) {
    if (!ctx[api]) fail('upstream API ' + api + ' did not register');
  }
  return ctx;
}

// The page's createCity (sketch.js:133-144), with the identity layout, run to its end state. Nothing here
// samples the construction clock: the result is the finished town (design section 2, "frozen").
function buildCity(up) {
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

// ---------------------------------------------------------------------------------------------- helpers

const m = (v) => v * S;
const rectM = (r) => ({ x: m(r.x), z: m(r.z), w: m(r.w), d: m(r.d) });
const GATE = { 'x-': [-1, 0], 'x+': [1, 0], 'z-': [0, -1], 'z+': [0, 1] };
const overlap = (a, b, gap = 0) => Math.abs(a.x - b.x) < (a.w + b.w) / 2 + gap && Math.abs(a.z - b.z) < (a.d + b.d) / 2 + gap;

function polyline(segments) {
  // CityLife routes: segments {x, z, dx, dz}; transit routes: segments {a: [x, z], b: [x, z]}.
  const pts = [];
  for (const s of segments) {
    const a = s.a ? s.a : [s.x, s.z];
    const b = s.b ? s.b : [s.x + s.dx, s.z + s.dz];
    if (!pts.length) pts.push([m(a[0]), m(a[1])]);
    pts.push([m(b[0]), m(b[1])]);
  }
  return pts;
}

const ENGLISH = {
  primary: 'Primary school', workshop: 'Workshop and garage', depot: 'Logistics depot',
  university: 'University and vocational college', market: 'Wholesale market', library: 'Library and culture centre',
  'annex-mall': 'Small mall', mall: 'Mall', hospital: 'Hospital', secondary: 'Secondary school',
  courtyard: 'Courtyard housing', slab: 'Garden slab housing', terrace: 'Terrace apartments', point: 'Twin-tower housing',
  office: 'Office tower', station: 'Bus and taxi station', amusement: 'Amusement park', plaza: 'Plaza', park: 'Park',
  playground: 'Sports ground', clinic: 'Community clinic', precinct: 'Police post', waste: 'Waste station', bank: 'Bank',
};

// ---------------------------------------------------------------------------------------------- the map

function buildTown(up, city) {
  const F = up.CityFacilities;
  const life = up.CityLife.create(city);
  const facilityById = Object.fromEntries((city.facilities || []).map((f) => [f.id, f]));
  const siteByFacility = Object.fromEntries(F.SITES.map((s) => [s.facility, s]));
  const frontageByBuilding = Object.fromEntries(city.frontage.sites.map((s) => [s.building.id, s]));
  const cells = up.CityLayout.cells(city);
  const lotOf = (x, z) => cells.reduce((best, cell) =>
    Math.hypot(cell.x - x, cell.z - z) < Math.hypot(best.x - x, best.z - z) ? cell : best, cells[0]);

  // ----- buildings
  const buildings = city.buildings.map((b) => {
    const lot = lotOf(b.x, b.z);
    const kind = b.housing ? 'housing' : b.facility ? 'facility' : 'tower';
    const profile = up.CityDistrict.officeProfile(b);
    const out = {
      id: b.id, kind, material_kind: b.kind, lot: lot.index, cell: lot.label,
      programme: b.facility || (b.housing ? b.housing.type : 'office'),
      name_en: ENGLISH[b.facility || (b.housing ? b.housing.type : 'office')],
      label_zh: b.label || (profile ? profile.label : null),
      name_zh: b.facility ? facilityById[b.id].name : (b.housing ? b.housing.label : (profile ? profile.label : null)),
      x: m(b.x), z: m(b.z), w: m(b.w), d: m(b.d),
      floors: b.floors, storey: m(b.floorHeight), plinth: m(1.4),
      height: m(1.4 + b.floors * b.floorHeight), roof: b.roof,
    };
    // The solid footprint. Towers and the three V2 landmarks fill their record; the seven W1.5b facilities
    // draw a smaller mass pushed back by mz inside it (city-facilities.js:38-42); housing is the 46 x 50
    // block envelope, whose wings are listed in `volumes`.
    const spec = b.facility ? siteByFacility[b.facility] : null;
    out.rect = spec && (spec.mw || spec.mz)
      ? { x: m(b.x), z: m(b.z + (spec.mz || 0)), w: m(spec.mw || spec.w), d: m(spec.md || spec.d) }
      : rectM(b);
    if (kind === 'tower') {
      // Tower modules, as city-district.js:443-467 places them: one floor module per storey, scaled
      // (w / 36, 1, d / 32), the upper storeys from `setback_floor` on scaled (0.8, 1, 0.86); the roof module
      // (none for the 'plain' helipad roof) on top.
      const glass = b.kind === 'glass', setback = glass && b.floors >= 15;
      out.office_profile = profile ? profile.id : null;
      out.palette = profile ? { wall: profile.wall, glass: profile.glass, trim: profile.trim } : null;
      out.modules = {
        floor: 'Floor_' + (glass ? 'Glass' : b.kind === 'sand' ? 'Sand' : 'Stone'),
        roof: b.roof === 'plain' ? null : 'Roof_' + (b.roof === 'solar' ? 'Solar' : b.roof === 'garden' ? 'Garden' : 'Service'),
        setback_floor: setback ? Math.floor(b.floors * 0.74) : b.floors,
        scale: [b.w / 36, 1, b.d / 32], upper_scale: [0.8, 1, 0.86],
      };
    } else if (kind === 'housing') {
      out.palette = Object.assign({}, b.housing.palette);
      out.housing_type = b.housing.type;
      out.volumes = b.housing.volumes.map((v) => ({ x: m(b.x + v.x), z: m(b.z + v.z), w: m(v.w), d: m(v.d),
        floors: v.floors, balconies: v.balconies }));
      out.courtyard = { x: m(b.x + b.housing.courtyard.x), z: m(b.z + b.housing.courtyard.z),
        w: m(b.housing.courtyard.w), d: m(b.housing.courtyard.d) };
    } else {
      out.palette = F.civicPalette(b.facility) || null;
      out.gate_side = spec.gate;
      out.mass = out.rect;
    }
    out.frontage = frontageByBuilding[b.id] ? frontageByBuilding[b.id].type : null;
    const doors = doorsFor(up, city, b, out, frontageByBuilding[b.id], facilityById[b.id]);
    out.doors = doors.doors;
    out.facade_doors = doors.facade;
    return out;
  });

  // ----- annexes, resolved where they stand in this city (CityFacilities.annexSites)
  const annexes = F.annexSites(city).map((a) => {
    const g = GATE[a.gate];
    const fp = a.footprint;
    const halfAlong = g[0] ? a.w / 2 : a.d / 2;
    const door = { x: m(a.x + g[0] * (halfAlong + 1)), z: m(a.z + g[1] * (halfAlong + 1)),
      facing: g, width: null, kind: 'entry', source: 'annex gate side (city-facilities.js ANNEXES gate)' };
    const record = { id: a.id, facility: a.facility, x: a.x, z: a.z, w: a.w, d: a.d, floors: a.floors, floorHeight: 6,
      kind: 'stone', roof: 'facility' };
    const plan = F.architectureParts(record, a);
    return {
      id: a.id, facility: a.facility, host: a.host, name_en: ENGLISH[a.facility], name_zh: a.name, label_zh: a.label,
      x: m(a.x), z: m(a.z), w: m(a.w), d: m(a.d), footprint: rectM(fp), gate_side: a.gate,
      floors: a.floors, storey: 3, height: m(1.4 + a.floors * 6), podium: !!a.podium,
      palette: F.civicPalette(a.facility), doors: [door], facade_doors: leafDoors(record, a, plan),
    };
  });

  // ----- places
  const station = city.places.find((p) => p.kind === 'station');
  const amusement = city.places.find((p) => p.kind === 'amusement');
  const plaza = city.places.find((p) => p.kind === 'plaza');
  const side = station.gateSide;
  // Station gates: assets/city-ground.runtime.min.js (station block `sa`): gateX = x + side*w/2,
  // gateWidth = 8*d/58, gateZ = z + side*(+-13)*d/58. Vehicles leave and return through them.
  const gates = [-13, 13].map((t) => ({ x: m(station.x + side * station.w / 2), z: m(station.z + side * t * station.d / 58),
    width: m(8 * station.d / 58), facing: [side, 0], kind: 'vehicle_gate',
    source: 'city-ground.runtime.min.js station gate formula' }));
  const local = (x, z) => [station.x + side * x, station.z + side * z];
  const lrect = (x, z, w, d) => { const [cx, cz] = local(x, z); return { x: m(cx), z: m(cz), w: m(w), d: m(d) }; };
  // Forecourt (Lantern Lane, derived): the station pad's south-east corner clear of the bus lanes (local
  // x 15..26, z -29..-15, see city-transit-motion.js:32 for the lanes at x 21 and z +-13) plus the pavement
  // out to the z = 0 street kerb (z = 3 m) and the avenue kerb (x = -50.5 m).
  const corner = lrect(20.5, -22, 11, 14);
  const avenue = city.roads.find((r) => r.axis === 'z' && r.x === station.roadX);
  const kerbX = m(avenue.x - side * avenue.w / 2), kerbZ = m(6);
  const fx0 = corner.x - corner.w / 2, fx1 = kerbX, fz0 = kerbZ, fz1 = corner.z + corner.d / 2;
  const forecourt = { x: (fx0 + fx1) / 2, z: (fz0 + fz1) / 2, w: fx1 - fx0, d: fz1 - fz0 };
  // Arrival (design section 3, derived): the forecourt's south-east corner, on the pavement just north of the
  // zebra across the street's west mouth, facing east along the z = 0 pedestrian street toward the canal.
  const arrival = { x: fx1 - 1.5, y: m(0.25), z: fz0 + 0.6, facing: [1, 0] };
  const places = {
    station: {
      kind: 'station', name_en: ENGLISH.station, name_zh: station.name, label_zh: station.label,
      x: m(station.x), z: m(station.z), w: m(station.w), d: m(station.d), height: m(station.height),
      gate_side: side, road_x: m(station.roadX), gates,
      // city-transit.js:149-168: the pad, the bus platform and its canopy, the taxi platform, the west strip.
      pad: lrect(0, 0, 52, 58), platform: lrect(-5, -23, 40, 9), canopy: Object.assign(lrect(-5, -23, 40, 8.8), { y: m(8.16) }),
      taxi_platform: lrect(-5, 25.7, 40, 3.8), west_strip: lrect(-24.8, -0.3, 2.4, 46.8),
      bus_bays: [[-17, -7], [-5, -7], [7, -7]].map(([x, z]) => { const p = local(x, z); return [m(p[0]), m(p[1])]; }),
      taxi_bays: [[-18, 18], [-8, 18], [2, 18], [12, 18]].map(([x, z]) => { const p = local(x, z); return [m(p[0]), m(p[1])]; }),
      forecourt, arrival,
    },
    amusement: { kind: 'amusement', name_en: ENGLISH.amusement, name_zh: amusement.name, label_zh: amusement.label,
      x: m(amusement.x), z: m(amusement.z), w: m(amusement.w), d: m(amusement.d), height: m(amusement.height),
      // city-landmarks.js:410-412: the gate opening between posts at local x +-6 on the south side z = 20.8.
      gate: { x: m(amusement.x), z: m(amusement.z + 20.8), width: m(12), facing: [0, 1] } },
    plaza: { kind: 'plaza', name_en: ENGLISH.plaza, name_zh: plaza.name, label_zh: plaza.label,
      x: m(plaza.x), z: m(plaza.z), w: m(plaza.w), d: m(plaza.d), height: m(plaza.height) },
    parks: city.parks.map((p, i) => ({ id: p.use === 'sports' ? 'sports' : 'park-' + i, use: p.use || 'park',
      x: m(p.x), z: m(p.z), w: m(p.w), d: m(p.d) })),
    sports: { x: m(city.playground.x), z: m(city.playground.z), w: m(city.playground.w), d: m(city.playground.d),
      track_radius: m(city.playground.trackRadius), track_half_straight: m(city.playground.trackHalfStraight),
      lane_width: m(city.playground.laneWidth), lanes: city.playground.lanes,
      pitch_w: m(city.playground.pitchW), pitch_d: m(city.playground.pitchD),
      playing_area: { x: m(city.playground.x), z: m(city.playground.z), w: m(40), d: m(46) } },
    block_walks: (city.blockWalks || []).map((p) => ({ x: m(p.x), z: m(p.z) })),
  };

  // ----- lots
  const lots = cells.map((cell) => {
    const inLot = buildings.filter((b) => b.lot === cell.index).map((b) => b.id);
    const tower = buildings.find((b) => b.lot === cell.index && b.kind === 'tower');
    const kind = tower ? 'tower' : cell.kind;
    return { index: cell.index, row: cell.row, col: cell.col, cell: cell.label, x: m(cell.x), z: m(cell.z),
      kind, programme: tower ? 'office' : (cell.kind === 'housing'
        ? buildings.find((b) => b.lot === cell.index).programme : cell.kind),
      name_zh: tower ? tower.label_zh : cell.name, name_en: tower ? ENGLISH.office
        : (cell.kind === 'housing' ? buildings.find((b) => b.lot === cell.index).name_en : ENGLISH[cell.kind] || null),
      buildings: inLot };
  });

  // ----- roads, crossings, bridges
  const roads = city.roads.map((r, i) => {
    let role;
    if (r.unlit) role = 'expressway_stub';
    else if (r.axis === 'z') role = Math.abs(r.x) === 96 ? 'avenue' : 'ring_road';
    else role = 'cross_street';
    const out = { id: 'road-' + i, role, axis: r.axis, x: m(r.x), z: m(r.z), w: m(r.w), d: m(r.d),
      through: r.axis === 'x' && !r.closed && !r.unlit };
    if (r.walkOnlyTo) out.walk_only_to = m(r.walkOnlyTo);
    if (r.closed) out.closed = true;
    return out;
  });
  // Junctions and zebra crossings, as the ground layer paints them (assets/city-ground.runtime.min.js, the
  // `x.crosswalks+=` block): at every x-street / z-road junction away from the bridges, one zebra across the
  // street on each side of the avenue at x = a +- (w/2 + 3), 9 stripes of 3.4 x 0.64 at 1.22 pitch; and,
  // unless the street is walk-only, one across the avenue at z = t +- (d/2 + 3), 7 stripes of 0.68 x 3.4.
  const crossings = [];
  const xRoads = city.roads.filter((r) => r.axis === 'x'), zRoads = city.roads.filter((r) => r.axis === 'z');
  for (const e of xRoads) for (const r of zRoads) {
    const a = r.x, t = e.z;
    if (a <= e.x - e.w / 2 || a >= e.x + e.w / 2 || t <= r.z - r.d / 2 || t >= r.z + r.d / 2) continue;
    if (city.bridges.some((n) => overlap({ x: a, z: t, w: 30, d: 32 }, { x: n.x, z: n.z, w: n.w + 20, d: n.d + 8 }))) continue;
    const zebras = [];
    for (const n of [-1, 1]) {
      zebras.push({ x: m(a + n * (r.w / 2 + 3)), z: m(t), w: m(3.4), d: m(8 * 1.22 + 0.64), walk_axis: 'z', stripes: 9 });
      if (!e.walkOnlyTo) zebras.push({ x: m(a), z: m(t + n * (e.d / 2 + 3)), w: m(6 * 1.3 + 0.68), d: m(3.4), walk_axis: 'x', stripes: 7 });
    }
    crossings.push({ x: m(a), z: m(t), street: roads[city.roads.indexOf(e)].id, road: roads[city.roads.indexOf(r)].id,
      zebras });
  }
  crossings.sort((p, q) => p.z - q.z || p.x - q.x);
  const bridges = city.bridges.map((b, i) => ({ id: (b.pedestrian ? 'footbridge-' : 'bridge-') + i,
    kind: b.pedestrian ? 'footbridge' : 'road_bridge', x: m(b.x), z: m(b.z), w: m(b.w), d: m(b.d) }));
  const viaducts = city.viaducts.map((v, i) => ({ id: 'viaduct-' + i, z: m(v.z), d: m(v.d), height: m(v.height),
    flat_x: m(v.flatX), ramp_x: m(v.rampX) }));
  const tunnels = city.tunnels.map((t, i) => ({ id: 'tunnel-' + i, z: m(t.z), half_d: m(t.halfD), portal_x: m(t.portalX),
    cover_x: m(t.coverX), drop: m(t.drop) }));

  // ----- canal and walks
  const canal = { x: m(city.water.x), z: m(city.water.z), w: m(city.water.w), d: m(city.water.d),
    half_width: m(city.water.w / 2), water_y: m(-0.55), color: '#688f92' };
  const walking = life.walkingRoutes.map((r, i) => ({ id: 'walk-' + i, length: m(r.length), width: m(2.8),
    points: polyline(r.segments) }));
  const riverWalk = walking.filter((w) => w.points.some((p) => Math.abs(Math.abs(p[0]) - m(23)) < 1e-6));
  const promenade = [-1, 1].map((sgn) => {
    // city-waterfront.js:44-46: the riverside promenade pavement runs from the bank (|x| 15) to |x| 27.9.
    const x0 = 15, x1 = 27.9;
    return { side: sgn, x: m(sgn * (x0 + x1) / 2), z: 0, w: m(x1 - x0), d: m(city.water.d - 2 * 30) };
  });

  // ----- transit
  const stops = city.transitStops.filter((s) => s.kind === 'bus').map((s) => ({ id: s.id, x: m(s.x), z: m(s.z),
    w: m(s.w), d: m(s.d), axis: s.axis, facing: [0, s.facing], shelter: s.shelter }));
  const taxiStop = city.transitStops.find((s) => s.kind === 'taxi');
  const taxiRank = { id: taxiStop.id, x: m(taxiStop.x), z: m(taxiStop.z), w: m(taxiStop.w), d: m(taxiStop.d),
    axis: taxiStop.axis, facing: [taxiStop.facing, 0] };
  const motion = up.CityTransitMotion.create(city);
  const stationLoop = {
    // city-transit-motion.js: every vehicle drives its rounded route at 10 units/s (5 m/s) of upstream time,
    // period 360 s, departure 5 + index*26 s; buses also follow the daily timetable from 06:00.
    speed: m(10), period: 360, bridge_rise: m(1.7),
    vehicles: motion.vehicles.map((v) => {
      const pts = v.path.segments.length ? [v.path.segments[0].a].concat(v.path.segments.map((s) => s.b)) : [];
      return { id: v.id, kind: v.bus ? 'bus' : 'taxi', index: v.index, departure: v.departure,
        bay: [m(station.x + side * v.x), m(station.z + side * v.z)], length: m(v.path.length),
        points: pts.map((p) => [m(station.x + side * p[0]), m(station.z + side * p[1])]) };
    }),
  };
  const streetLoops = life.vehicleRoutes.map((r, i) => ({ id: 'traffic-' + i, length: m(r.length),
    half_x: m(city.vehicleLaneExtents[i].halfX), half_z: m(city.vehicleLaneExtents[i].halfZ),
    points: polyline(r.segments) }));
  const transit = {
    bus_stops: stops, taxi_rank: taxiRank, station_loop: stationLoop, street_loops: streetLoops,
    rider_loop: { length: m(life.riderRoute.length), half_x: m(city.riderLaneExtents.halfX),
      half_z: m(city.riderLaneExtents.halfZ), points: polyline(life.riderRoute.segments) },
    lane_routes: life.laneRoutes.map((r, i) => ({ id: 'lane-' + i, length: m(r.length), points: polyline(r.segments) })),
    vehicles: life.vehicles.map((v) => ({ id: v.id, loop: v.route, offset: m(v.offset), speed: m(v.speed), kind: v.kind,
      color: v.color, police: !!v.police })),
  };

  // ----- trees, waterfront
  const trees = city.trees.map((t) => ({ x: m(t.x), z: m(t.z), r: m(t.r), h: m(t.h) }));
  const office = city.waterfront.civic;
  const waterfront = {
    stalls: city.waterfront.stalls.map((s) => ({ id: s.id, side: s.side, x: m(s.x), z: m(s.z), w: m(s.w), d: m(s.d),
      height: m(s.height), type: s.type, name_zh: s.name, color: s.color, hot: s.hot, seats: s.seats,
      outdoor_table: s.outdoorTable })),
    street_office: { id: office.id, kind: office.kind, name_en: 'Street office', name_zh: office.name, side: office.side,
      x: m(office.x), z: m(office.z), w: m(office.w), d: m(office.d), height: m(office.height),
      doors: [{ x: m(office.x - office.side * (office.w / 2 + 1)), z: m(office.z), facing: [-office.side, 0], width: null,
        kind: 'entry', source: 'derived: the side facing the river walk' }] },
  };

  // ----- landmarks
  const helipad = up.CityHelipad.plan(city);
  const fountain = up.CityFountain;
  const landmarks = {
    // city-landmarks.js:11 RADIUS 20, AXLE_Y 26, WHEEL_YAW -0.66, PERIOD 180; 12 cabins (line 520).
    ferris_wheel: { x: m(amusement.x), z: m(amusement.z), yaw: -0.66, radius: m(20), axle_y: m(26), cabins: 12,
      period: 180, frame_depth: m(8.6), foot_half_span: m(9.2) },
    // city-landmarks.js:42-44 rideSpecs; bases and rotors at y 0.30 (line 281-283).
    carousel: { x: m(amusement.x - 11), z: m(amusement.z + 6), y: m(0.3), radius: m(4.4), height: m(7.4), period: 45,
      modules: ['CarouselBase', 'CarouselRotor'] },
    teacups: { x: m(amusement.x - 6.5), z: m(amusement.z - 15), y: m(0.3), radius: m(2.8), height: m(3.7), period: 30,
      modules: ['TeacupsBase', 'TeacupsRotor'] },
    // city-fountain.js BASIN / RINGS (read from the module): the ring basin around the monument.
    fountain: { x: m(plaza.x), z: m(plaza.z), inner: m(fountain.BASIN.inner), outer: m(fountain.BASIN.outer),
      surface_y: m(fountain.BASIN.surfaceY), wall_y: m(fountain.BASIN.wallY),
      rings: fountain.RINGS.map((r) => ({ radius: m(r.radius), count: r.count, base_height: m(r.baseHeight), tier: r.tier })),
      jets: fountain.RINGS.reduce((n, r) => n + r.count, 0) },
    // city-landmarks.js:578-583 (refined plaza): the landscape Monument at the centre, four planters at
    // (+-13.5, +-16.2) and four benches at (+-14.8, +-6.8) turned x*PI/2.
    monument: { x: m(plaza.x), z: m(plaza.z), height: m(24.85), module: 'Monument',
      planters: [-1, 1].flatMap((x) => [-1, 1].map((z) => ({ x: m(plaza.x + x * 13.5), z: m(plaza.z + z * 16.2), module: 'Planter' }))),
      benches: [-1, 1].flatMap((x) => [-1, 1].map((z) => ({ x: m(plaza.x + x * 14.8), z: m(plaza.z + z * 6.8), yaw: x * Math.PI / 2, module: 'Bench' }))) },
    helipad: { building: helipad.buildingId, x: m(helipad.x), z: m(helipad.z), roof_y: m(helipad.roofY), radius: m(helipad.radius),
      deck: m(helipad.deck), clearance: m(helipad.clearance), cruise: m(helipad.cruise), period: helipad.period,
      circuit: { cx: m(helipad.circuit.cx), cz: m(helipad.circuit.cz), a: m(helipad.circuit.a), b: m(helipad.circuit.b),
        u: [helipad.circuit.u.x, helipad.circuit.u.z], v: [helipad.circuit.v.x, helipad.circuit.v.z] } },
    balloon_stands: city.balloonStands.map((s) => ({ id: s.id, x: m(s.x), z: m(s.z), w: m(s.w), d: m(s.d), height: m(s.height),
      facing: s.facing })),
  };

  // ----- frontage parts (box parts, axis-aligned in world space; `yaw` only turns the sign sheets)
  const frontage = {
    // city-frontage.js:627-650 role materials; city-materials.js:753-772 for the kit's stone, pavement and leaf.
    role_colors: { paving: '#e3ddd1', stone: '#ece5d9', hedge: '#6f8567', iron: '#3d4a50', shopbody: '#f0e9da',
      trim: '#f6f1e6', timber: '#937052', shopglass: '#a9c8cd', shoplit: '#e9dcc0', awning: '#ffffff',
      jamb: '#f6f1e6', reveal: '#f6f1e6', soffit: '#f6f1e6', counter: '#937052', shelf: '#937052', ledge: '#ece5d9',
      bracket: '#3d4a50', sign: '#f6f1e2', plaque: '#f6f1e2', board: '#f6f1e2' },
    sites: city.frontage.sites.map((site) => ({
      id: site.id, building: site.building.id, type: site.type, ring: m(site.ring),
      band: Object.fromEntries(Object.entries(site.band).map(([k, v]) => [k, m(v)])),
      gate_side: site.gate ? site.gate.side : null, entry_side: site.entrySide,
      entry: site.entry ? { side: site.entry.side, depth: m(site.entry.depth), opening: rectM(site.entry.opening) } : null,
      reservations: city.frontage.reservations.filter((r) => r.id === site.id).map(rectM),
      parts: site.parts.filter((p) => p.role !== 'skip').map((p) => {
        const q = { role: p.role, x: m(p.x), y: m(p.y), z: m(p.z), w: m(p.w), h: m(p.h), d: m(p.d), yaw: p.yaw };
        if (p.tint) q.tint = p.tint;
        if (p.tile) q.tile = p.tile;
        if (p.side) q.side = p.side;
        return q;
      }),
    })),
  };

  // ----- facility architecture parts (world metres; floor-local boxes placed on floor * 3 + 0.7)
  const facilityParts = [];
  const pushParts = (record, plan, host) => {
    const out = [];
    for (const p of plan.parts) {
      const level = p.floor === 'roof' ? record.floors : p.floor;
      const q = { role: p.material, feature: p.feature, color: p.color, floor: p.floor,
        x: m(record.x + p.x), y: m(1.4 + level * 6 + p.y), z: m(record.z + p.z), w: m(p.w), h: m(p.h), d: m(p.d), yaw: 0 };
      if (p.tilt) q.tilt = [p.tilt.x || 0, p.tilt.y || 0, p.tilt.z || 0];
      if (p.door) q.door = true;
      out.push(q);
    }
    facilityParts.push({ building: record.id, host: host || null, style: plan.style, parts: out,
      signs: plan.signs.map((s) => ({ x: m(record.x + s.x), y: m(1.4 + (s.floor === 'roof' ? record.floors : s.floor) * 6 + s.y),
        z: m(record.z + s.z), w: m(s.w), h: m(s.h), yaw: s.rotationY, text_zh: s.text })) });
  };
  for (const b of city.buildings) {
    if (!b.facility) continue;
    const site = siteByFacility[b.facility];
    const spec = site.mw === undefined && site.mz === undefined ? site : Object.assign({}, site, { floors: b.floors });
    const plan = F.architectureParts(b, spec);
    if (plan.parts.length) pushParts(b, plan, null);
  }
  for (const a of F.annexSites(city)) {
    const record = { id: a.id, facility: a.facility, x: a.x, z: a.z, w: a.w, d: a.d, floors: a.floors, floorHeight: 6 };
    const plan = F.architectureParts(record, a);
    if (plan.parts.length) pushParts(record, plan, a.host);
  }

  // ----- office tower parts (city-district.js officeParts: y absolute, x/z local to the tower)
  const officeParts = city.buildings.filter((b) => up.CityDistrict.officeProfile(b)).map((b) => ({
    building: b.id, profile: up.CityDistrict.officeProfile(b).id, style: up.CityDistrict.officeProfile(b).style,
    parts: up.CityDistrict.officeParts(b).map((p) => ({ role: p.material, feature: p.kind, color: p.color, floor: p.floor,
      roof: p.roof, x: m(b.x + p.x), y: m(p.y), z: m(b.z + p.z), w: m(p.w), h: m(p.h), d: m(p.d), yaw: 0 })),
  }));

  return { buildings, annexes, places, lots, roads, crossings, bridges, viaducts, tunnels, canal, walking, riverWalk,
    promenade, transit, trees, waterfront, landmarks, frontage, facilityParts, officeParts };
}

// Door leaves an architecture plan marks (city-facilities.js:472-477 doorway/leafDoor): the leaf box's centre,
// facing out of the gate face.
function leafDoors(record, spec, plan) {
  const g = GATE[spec.gate || 'z-'];
  return plan.parts.filter((p) => p.door).map((p) => ({
    x: m(record.x + p.x + g[0] * 1.0), z: m(record.z + p.z + g[1] * 1.0), facing: g,
    width: m(g[0] ? p.d : p.w), kind: 'facade', source: 'architecture door leaf (city-facilities.js leafDoor)' }));
}

// The doors of one building. `doors` are where people come and go from the street: the compound gate for a
// walled site (city-frontage.js gateSide: the recorded entrance, else the courtyard, else the nearest street),
// the lobby opening for a shop-ringed tower (city-frontage.js entry), the recorded entrance for the mall
// (city-facilities.js entranceOf). Each stands 0.5 m outside its wall or opening. `facade` lists the building's
// own door leaves inside its compound, where upstream draws them.
function doorsFor(up, city, b, out, site, facility) {
  const doors = [], facade = [];
  if (site && site.type === 'wall') {
    const g = GATE[site.gate.side];
    const half = (g[0] ? b.w : b.d) / 2 + site.ring;
    doors.push({ x: m(b.x + g[0] * (half + 1)), z: m(b.z + g[1] * (half + 1)), facing: g, width: m(8), kind: 'gate',
      source: facility ? 'frontage gate on the facility entrance side (city-frontage.js gateSide)'
        : 'frontage gate (city-frontage.js gateSide: courtyard or nearest street)' });
  } else if (site && site.type === 'shops' && site.entry) {
    const g = GATE[site.entry.side], o = site.entry.opening;
    const depth = g[0] ? o.w : o.d;
    doors.push({ x: m(o.x + g[0] * (depth / 2 + 1)), z: m(o.z + g[1] * (depth / 2 + 1)), facing: g,
      width: m(g[0] ? o.d : o.w), kind: 'lobby', source: 'frontage lobby opening (city-frontage.js entry)' });
  } else if (facility && facility.entrance) {
    const dx = facility.entrance.x - b.x, dz = facility.entrance.z - b.z;
    const g = Math.abs(dx) > Math.abs(dz) ? [Math.sign(dx), 0] : [0, Math.sign(dz)];
    doors.push({ x: m(facility.entrance.x), z: m(facility.entrance.z), facing: g, width: null, kind: 'entrance',
      source: 'facility entrance (city-facilities.js entranceOf)' });
  } else {
    // Fallback (not used by the default town, kept for robustness): the side facing the nearest street.
    let best = null;
    for (const side of Object.keys(GATE)) {
      const g = GATE[side];
      const fx = b.x + g[0] * (b.w / 2 + 2), fz = b.z + g[1] * (b.d / 2 + 2);
      const dist = Math.min(...city.roads.map((r) => Math.max(0, Math.abs(fx - r.x) - r.w / 2) + Math.max(0, Math.abs(fz - r.z) - r.d / 2)));
      if (!best || dist < best.dist) best = { side, dist, x: fx, z: fz, g };
    }
    doors.push({ x: m(best.x), z: m(best.z), facing: best.g, width: null, kind: 'entry',
      source: 'derived: frontage side facing the nearest street' });
  }
  if (b.facility) {
    const site2 = up.CityFacilities.SITES.find((s) => s.facility === b.facility);
    const spec = site2.mw === undefined && site2.mz === undefined ? site2 : Object.assign({}, site2, { floors: b.floors });
    facade.push(...leafDoors(b, spec, up.CityFacilities.architectureParts(b, spec)));
    if (!facade.length && facility && facility.entrance) {
      const g = GATE[site2.gate];
      facade.push({ x: m(facility.entrance.x), z: m(facility.entrance.z), facing: g, width: null, kind: 'facade',
        source: 'facility entrance (city-facilities.js entranceOf)' });
    }
  } else if (b.housing) {
    // city-housing.js:253-275: each wing's ground floor has its entrance at (x + w*0.15, z - d/2) on the
    // north face unless another wing stands in front; the three entry steps reach 2.05 out.
    const vols = b.housing.volumes;
    for (const v of vols) {
      const ex = v.x + v.w * 0.15, ez = v.z - v.d / 2;
      const blocked = vols.some((o) => o !== v && o.floors > 0 && Math.abs(ex - o.x) < o.w / 2 + 1.3 && Math.abs(ez - 1.4 - o.z) < o.d / 2 + 1.3);
      if (blocked) continue;
      facade.push({ x: m(b.x + ex), z: m(b.z + ez - 2.6), facing: [0, -1], width: m(2.4), kind: 'facade',
        source: 'housing wing entrance (city-housing.js floorModule)' });
    }
  } else if (site && site.entry) {
    const g = GATE[site.entry.side];
    const half = (g[0] ? b.w : b.d) / 2;
    facade.push({ x: m(b.x + g[0] * (half + 1)), z: m(b.z + g[1] * (half + 1)), facing: g, width: m(1.5 * 2), kind: 'facade',
      source: 'tower lobby door behind the opening (city-frontage.js LOBBY)' });
  }
  return { doors, facade };
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
  const total = 12 + 8 + jsonBuf.length + (binBuf.length ? 8 + binBuf.length : 0);
  header.writeUInt32LE(0x46546c67, 0); header.writeUInt32LE(2, 4); header.writeUInt32LE(total, 8);
  const jh = Buffer.alloc(8); jh.writeUInt32LE(jsonBuf.length, 0); jh.writeUInt32LE(0x4e4f534a, 4);
  const parts = [header, jh, jsonBuf];
  if (binBuf.length) { const bh = Buffer.alloc(8); bh.writeUInt32LE(binBuf.length, 0); bh.writeUInt32LE(0x004e4942, 4); parts.push(bh, binBuf); }
  return Buffer.concat(parts);
}

function unpackGlb(buf) {
  if (buf.readUInt32LE(0) !== 0x46546c67 || buf.readUInt32LE(4) !== 2) fail('not a glTF 2.0 binary');
  let at = 12, json = null, bin = Buffer.alloc(0);
  while (at < buf.length) {
    const len = buf.readUInt32LE(at), type = buf.readUInt32LE(at + 4);
    const chunk = buf.subarray(at + 8, at + 8 + len);
    if (type === 0x4e4f534a) json = JSON.parse(chunk.toString('utf8'));
    else if (type === 0x004e4942) bin = Buffer.from(chunk);
    at += 8 + len;
  }
  return { json, bin };
}

const COPYRIGHT = '仪绘士 / YiHuiShiBY, "千人小镇 · Thousand Town" (github.com/YiHuiShiBY/thousand-town @ 1332ef2), CC BY 4.0; ' +
  'converted to metres for Lantern Lane by scripts/thousand_town/extract.mjs';

// Upstream's embedded Blender GLB, rescaled from upstream units to metres: every POSITION accessor is
// multiplied by 0.5 in the binary chunk (exact in float32), its min/max with it, and every node translation.
// Normals, UVs, images and materials are untouched. Returns the new GLB and its triangle count.
function rescaleGlb(buf) {
  const { json, bin } = unpackGlb(buf);
  if ((json.extensionsRequired || []).length) fail('GLB requires extensions ' + json.extensionsRequired);
  const positions = new Set();
  for (const mesh of json.meshes) for (const prim of mesh.primitives) {
    if (prim.targets) fail('GLB has morph targets');
    positions.add(prim.attributes.POSITION);
  }
  for (const index of [...positions].sort((a, b) => a - b)) {
    const acc = json.accessors[index];
    if (acc.sparse || acc.componentType !== 5126 || acc.type !== 'VEC3') fail('unexpected POSITION accessor ' + index);
    const view = json.bufferViews[acc.bufferView];
    const stride = view.byteStride || 12;
    const base = (view.byteOffset || 0) + (acc.byteOffset || 0);
    for (let i = 0; i < acc.count; i++) for (let k = 0; k < 3; k++) {
      const off = base + i * stride + k * 4;
      bin.writeFloatLE(bin.readFloatLE(off) * S, off);
    }
    if (acc.min) acc.min = acc.min.map((v) => Math.fround(v * S));
    if (acc.max) acc.max = acc.max.map((v) => Math.fround(v * S));
  }
  for (const node of json.nodes || []) {
    if (node.matrix) fail('GLB node with a matrix');
    if (node.translation) node.translation = node.translation.map((v) => v * S);
  }
  json.asset.copyright = COPYRIGHT;
  json.asset.extras = Object.assign({}, json.asset.extras, { units: 'metres (upstream x 0.5)' });
  let triangles = 0;
  for (const mesh of json.meshes) for (const prim of mesh.primitives) {
    triangles += (prim.indices !== undefined ? json.accessors[prim.indices].count : json.accessors[prim.attributes.POSITION].count) / 3;
  }
  return { glb: packGlb(json, bin), triangles, json };
}

// A minimal glTF 2.0 binary writer for upstream's packed arrays: one node and one mesh per module, POSITION
// (metres), NORMAL, COLOR_0 (linear RGB float, as upstream stores it) and optional uint16 indices. A module may
// be split into features that share the vertex arrays and use ranges of the index array.
function writePackedGlb(name, modules, roughness) {
  const views = [], accessors = [], meshes = [], nodes = [], chunks = [];
  let offset = 0;
  const addView = (buf, target) => {
    const padded = pad4(buf, 0);
    views.push({ buffer: 0, byteOffset: offset, byteLength: buf.length, target });
    chunks.push(padded); offset += padded.length;
    return views.length - 1;
  };
  let triangles = 0;
  for (const mod of modules) {
    const pos = Float32Array.from(mod.position, (v) => Math.fround(v * S));
    const nrm = Float32Array.from(mod.normal);
    const col = Float32Array.from(mod.color);
    const count = pos.length / 3;
    if (nrm.length !== pos.length || col.length !== pos.length) fail(name + '/' + mod.name + ': attribute lengths differ');
    const min = [Infinity, Infinity, Infinity], max = [-Infinity, -Infinity, -Infinity];
    for (let i = 0; i < count; i++) for (let k = 0; k < 3; k++) {
      min[k] = Math.min(min[k], pos[i * 3 + k]); max[k] = Math.max(max[k], pos[i * 3 + k]);
    }
    const pa = accessors.push({ bufferView: addView(Buffer.from(pos.buffer), 34962), componentType: 5126, count, type: 'VEC3', min, max }) - 1;
    const na = accessors.push({ bufferView: addView(Buffer.from(nrm.buffer), 34962), componentType: 5126, count, type: 'VEC3' }) - 1;
    const ca = accessors.push({ bufferView: addView(Buffer.from(col.buffer), 34962), componentType: 5126, count, type: 'VEC3' }) - 1;
    const attributes = { POSITION: pa, NORMAL: na, COLOR_0: ca };
    let indexView = null;
    if (mod.index) {
      const idx = Uint16Array.from(mod.index);
      indexView = addView(Buffer.from(idx.buffer), 34963);
    }
    const ranges = mod.features || [{ name: mod.name, start: 0, count: mod.index ? mod.index.length : count }];
    for (const r of ranges) {
      const prim = { attributes, material: 0, mode: 4 };
      if (indexView !== null) {
        prim.indices = accessors.push({ bufferView: indexView, byteOffset: r.start * 2, componentType: 5123, count: r.count, type: 'SCALAR' }) - 1;
      }
      triangles += r.count / 3;
      meshes.push({ name: r.name, primitives: [prim] });
      nodes.push({ name: r.name, mesh: meshes.length - 1 });
    }
  }
  const json = {
    asset: { version: '2.0', generator: 'Lantern Lane scripts/thousand_town/extract.mjs', copyright: COPYRIGHT,
      extras: { units: 'metres (upstream x 0.5)', vertex_colors: 'linear' } },
    scene: 0, scenes: [{ name, nodes: nodes.map((_, i) => i) }], nodes, meshes,
    materials: [{ name: name + '_vertex_colour', pbrMetallicRoughness: { baseColorFactor: [1, 1, 1, 1], metallicFactor: 0,
      roughnessFactor: roughness } }],
    accessors, bufferViews: views, buffers: [{ byteLength: offset }],
  };
  return { glb: packGlb(json, Buffer.concat(chunks)), triangles };
}

function boundsM(b) { return { min: b.min.map(m), max: b.max.map(m) }; }

function buildMeshes(up, files) {
  const meta = {};
  const sha = (buf) => crypto.createHash('sha256').update(buf).digest('hex');
  // district.glb: upstream's gzip + base64 GLB in assets/blender-district.js (no recorded hash upstream).
  {
    const A = up.CityDistrictAsset;
    if (A.compression !== 'gzip') fail('district asset is not gzip');
    const raw = zlib.gunzipSync(Buffer.from(A.base64, 'base64'));
    const { glb, triangles, json } = rescaleGlb(raw);
    files['district.glb'] = glb;
    meta.district = { file: 'district.glb', source: 'assets/blender-district.js (gzip + base64 GLB)',
      upstream_sha256: sha(raw), upstream_bytes: raw.length, sha256: sha(glb), triangles,
      module_size: { w: m(A.meta.width), d: m(A.meta.depth), storey: m(A.meta.floorHeight) },
      eave_allowance: m(A.meta.eaveAllowance), module_triangles: A.meta.triangles,
      module_bounds: Object.fromEntries(Object.entries(A.meta.bounds).map(([k, v]) => [k, boundsM(v)])),
      roots: json.scenes[json.scene || 0].nodes.map((i) => json.nodes[i].name),
      shadow_excluded_materials: A.meta.shadowExcludedMaterials };
  }
  // housing.glb: assets/blender-housing.js, whose meta records the GLB's own SHA-256 and size.
  {
    const A = up.CityHousingAsset;
    const raw = zlib.gunzipSync(Buffer.from(A.base64, 'base64'));
    if (sha(raw) !== A.meta.sha256 || raw.length !== A.meta.bytes) fail('housing GLB does not match its recorded sha256');
    const { glb, triangles } = rescaleGlb(raw);
    files['housing.glb'] = glb;
    meta.housing = { file: 'housing.glb', source: 'assets/blender-housing.js (gzip + base64 GLB)',
      upstream_sha256: sha(raw), upstream_bytes: raw.length, sha256: sha(glb), triangles,
      storey: m(A.meta.floorHeight), base: m(A.meta.base),
      modules: A.meta.modules.map((x) => ({ name: x.name, node: x.node, triangles: x.triangles, bounds: boundsM(x.bounds) })),
      types: Object.fromEntries(Object.entries(A.meta.types).map(([k, vols]) => [k, vols.map((v) =>
        ({ x: m(v[0]), z: m(v[1]), w: m(v[2]), d: m(v[3]), floors: v[4] }))])),
      anchors: { window_outset: m(A.meta.anchors.windowOutset), emissive_outset: m(A.meta.anchors.emissiveOutset),
        entry_lamp: A.meta.anchors.entryLamp.map(m) } };
  }
  const packed = (key, file, asset, roughness, extra) => {
    const names = Object.keys(asset.modules);
    const modules = names.map((n) => Object.assign({ name: n }, asset.modules[n]));
    if (extra) extra(modules);
    const { glb, triangles } = writePackedGlb(key, modules, roughness);
    files[file] = glb;
    const metaModules = (asset.meta.modules || []).map((x) => {
      const o = { name: x.name, triangles: x.triangles, bounds: boundsM(x.bounds) };
      for (const k of ['ride', 'part', 'facility', 'floor']) if (x[k] !== undefined) o[k] = x[k];
      if (x.radius !== undefined) o.radius = m(x.radius);
      return o;
    });
    const declared = metaModules.reduce((n, x) => n + x.triangles, 0);
    if (declared !== triangles) fail(file + ': ' + triangles + ' triangles written, upstream meta says ' + declared);
    meta[key] = { file, source: asset.meta.assetId, upstream_glb_sha256: asset.meta.sha256 || (asset.meta.sourceGLB || {}).sha256,
      sha256: sha(glb), triangles, coordinate_system: asset.meta.coordinateSystem || asset.meta.coordinates || null,
      modules: metaModules };
  };
  // Roughness follows the upstream material for each pack: rides .72 (city-landmarks.js:278), civic and ward
  // .72 (city-housing.js:149 refined architecture, the same vertex-colour material), landscape .9.
  packed('amusement', 'amusement.glb', up.CityAmusementAsset, 0.72);
  packed('civic', 'civic.glb', up.CityCivicAsset, 0.72);
  packed('hospital_room', 'hospital_room.glb', up.CityHospitalRoomAsset, 0.72, (modules) => {
    modules[0].features = up.CityHospitalRoomAsset.meta.features.map((f) => ({ name: f.name, start: f.start, count: f.count }));
  });
  packed('landscape', 'landscape.glb', up.CityLandscapeAsset, 0.9);
  meta.hospital_room.features = up.CityHospitalRoomAsset.meta.features.map((f) => ({ name: f.name, role: f.role,
    triangles: f.count / 3, bounds: boundsM(f.bounds) }));
  meta.hospital_room.floor = up.CityHospitalRoomAsset.meta.floor;
  return meta;
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
  if (Array.isArray(v)) return v.every((x) => x === null || typeof x !== 'object' || (Array.isArray(x) && x.every((y) => typeof y !== 'object' || y === null)));
  return Object.values(v).every((x) => x === null || typeof x !== 'object' || (Array.isArray(x) && x.every((y) => typeof y !== 'object' || y === null)));
}

// Sorted keys; a flat object or array (only scalars, or arrays of scalars) on one line, anything else
// spread one member per line. Deterministic for a given value.
function ser(v, indent = '') {
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

// ---------------------------------------------------------------------------------------------- main

function extract() {
  const up = loadUpstream();
  const city = buildCity(up);
  const t = buildTown(up, city);
  const files = {};
  const meshes = buildMeshes(up, files);
  const frontageParts = t.frontage.sites.reduce((n, s) => n + s.parts.length, 0);
  const facilityPartCount = t.facilityParts.reduce((n, s) => n + s.parts.length, 0);
  const officePartCount = t.officeParts.reduce((n, s) => n + s.parts.length, 0);
  const town = {
    format: 1,
    units: 'metres (upstream ×0.5)',
    source: {
      title: '千人小镇 · Thousand Town', repository: 'https://github.com/YiHuiShiBY/thousand-town', commit: COMMIT,
      licence: 'CC BY 4.0', licence_url: 'https://creativecommons.org/licenses/by/4.0/', author: '仪绘士 / YiHuiShiBY',
      changes: 'design/thousand-town.md section 12', units: 'metres (upstream ×0.5)', scale: S,
      extractor: 'scripts/thousand_town/extract.mjs', build_order: 'sketch.js:133-144',
      files: Object.fromEntries(EXEC.concat(CITED).map(([rel, sha]) => [rel, sha])),
    },
    params: { seed: SETTINGS.seed, density: SETTINGS.density, skyline: SETTINGS.skyline, playground: true, housing: true,
      layout: city.layout, frozen: 'construction end state (no sampleBuilding time)' },
    constants: {
      storey: m(6), plinth: m(1.4), pavement_y: m(0.25), water_y: m(-0.55), canal_half_width: m(15),
      cross_street_width: m(12), avenue_width: m(10), ring_road_width: m(10),
      upstream_door_height: m(3.6), door_height: 2.1, walker_head_upstream: m(4.35), car_length_upstream: m(8),
    },
    board: { half_x: m(city.extentX), half_z: m(city.extentZ), w: m(2 * city.extentX), d: m(2 * city.extentZ),
      lot_xs: [-132, -60, 60, 132].map(m), lot_zs: [-200, -120, -40, 40, 120, 200].map(m) },
    palette: { stone: '#ece5d9', sand: '#d2c6b4', glass: '#8fa9ab', road: '#485657', pavement: '#e3ddd1',
      ground: '#d8d2c7', grass: '#81956d', water: '#688f92', metal: '#b3beb6', dark: '#354646', trunk: '#9d7d59',
      leaf: '#6f8567' },
    lots: t.lots, buildings: t.buildings, annexes: t.annexes, places: t.places,
    roads: t.roads, crossings: t.crossings, bridges: t.bridges, viaducts: t.viaducts, tunnels: t.tunnels,
    canal: t.canal, promenade: t.promenade, river_walk: t.riverWalk.map((w) => w.id), walking_routes: t.walking,
    transit: t.transit, trees: t.trees, waterfront: t.waterfront, landmarks: t.landmarks,
    frontage: t.frontage, facility_parts: t.facilityParts, office_parts: t.officeParts, meshes,
    counts: { buildings: t.buildings.length, annexes: t.annexes.length, lots: t.lots.length, trees: t.trees.length,
      bus_stops: t.transit.bus_stops.length, stalls: t.waterfront.stalls.length, frontage_sites: t.frontage.sites.length,
      frontage_parts: frontageParts, facility_parts: facilityPartCount, office_parts: officePartCount,
      crossings: t.crossings.length, zebras: t.crossings.reduce((n, c) => n + c.zebras.length, 0),
      roads: t.roads.length, bridges: t.bridges.length, walking_routes: t.walking.length,
      street_loops: t.transit.street_loops.length, station_vehicles: t.transit.station_loop.vehicles.length,
      glb_triangles: Object.fromEntries(Object.entries(meshes).map(([k, v]) => [k, v.triangles])) },
  };
  files['town.json'] = Buffer.from(ser(town) + '\n', 'utf8');
  // Godot: keep the GLBs as plain files (exported as is) so GLTFDocument reads them at run time.
  for (const name of Object.keys(files)) {
    if (name.endsWith('.glb')) files[name + '.import'] = Buffer.from('[remap]\n\nimporter="keep"\n', 'utf8');
  }
  return { files, town };
}

function writeAll(files, dir) {
  fs.mkdirSync(dir, { recursive: true });
  for (const name of Object.keys(files).sort()) fs.writeFileSync(path.join(dir, name), files[name]);
}

function main() {
  const args = process.argv.slice(2);
  const { files, town } = extract();
  if (args.includes('--check')) {
    // Regenerate in memory and compare every byte with the files on disk.
    let bad = 0;
    for (const name of Object.keys(files).sort()) {
      const a = path.join(DEFAULT_OUT, name);
      const same = fs.existsSync(a) && Buffer.compare(fs.readFileSync(a), files[name]) === 0;
      if (!same) { bad++; console.log('DIFFERS ' + name); }
    }
    console.log(bad ? 'THOUSAND EXTRACT CHECK: ' + bad + ' files differ' : 'THOUSAND EXTRACT CHECK: ' + Object.keys(files).length + ' files identical');
    process.exit(bad ? 1 : 0);
  }
  const outIndex = args.indexOf('--out');
  const dir = outIndex >= 0 ? path.resolve(args[outIndex + 1]) : DEFAULT_OUT;
  writeAll(files, dir);
  const c = town.counts;
  console.log('wrote ' + Object.keys(files).length + ' files to ' + path.relative(ROOT, dir));
  for (const name of Object.keys(files).sort()) {
    console.log('  ' + name.padEnd(24) + String(files[name].length).padStart(9) + '  ' + crypto.createHash('sha256').update(files[name]).digest('hex'));
  }
  console.log('counts ' + JSON.stringify(c));
}

main();
