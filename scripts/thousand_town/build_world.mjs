#!/usr/bin/env node
// Thousand Town world builder (route C, design/engine-route-evaluation.md; design/thousand-town.md sections
// 1, 2, 8, 9 and 12). The offline step for the parts of upstream's town that exist only as Three.js builder
// code (build/dual-host/thousand-town/CHECKPOINT.md, W-DATA's "Not extractable" list): the ground layer
// (kerbs, lamps, benches, shelters, canal walls and the rest of the street furniture), the facility bodies,
// the housing floor detail, the station building, the fences, the ferris wheel and the stall bodies. Each
// builder is ported to Node in world_*.mjs (the PROVENANCE table below names the upstream file, function
// and lines), run on the city that upstream's own pure planners build in a bare vm (as extract.mjs), and
// written to game/thousand_town/data/ in metres:
//
//   world_ground.glb  world_facilities.glb  world_housing.glb  world_station.glb  world_landmarks.glb
//   world_market.glb  world_signs.glb       (+ .glb.import, importer="keep": read with GLTFDocument)
//   world.json   the manifest: files, nodes, animation and door data, windows, vehicles, signs, fountain
//                droplets, provenance, counts and budgets, hashes
//   lights.json  street lamps and other light anchors, spot data, light pools, lanterns, real-light picks
//   solids.json  collision footprints (rects / quads, metres) and walkable surfaces
//
//   node scripts/thousand_town/build_world.mjs            write the files
//   node scripts/thousand_town/build_world.mjs --out DIR  write to DIR (the two-run byte comparison)
//   node scripts/thousand_town/build_world.mjs --check    rebuild in memory; compare with the files on disk,
//                                                         re-verify the pinned upstream hashes, run the checks
//
// Deterministic: no clocks, no randomness but upstream's seeded generators, sorted JSON keys, fixed
// float rounding (positions to 1e-6 m then float32; JSON to 1e-4). Two runs give byte-identical files.
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import * as C from './world_core.mjs';
import { buildGround } from './world_ground.mjs';
import { buildFacilities } from './world_facilities.mjs';
import { buildHousing } from './world_housing.mjs';
import { buildStation } from './world_station.mjs';
import { buildLandmarks } from './world_landmarks.mjs';
import { buildMarket } from './world_market.mjs';
import { buildSigns } from './world_signs.mjs';
import { runChecks } from './build_world.test.mjs';

const S = C.S;
const m = (v) => v * S;

// Where each ported element comes from. `lines` are 1-based inclusive ranges in the pinned file; for the
// minified ground bundle (77 physical lines) the anchor is a unique snippet of the minified source, with the
// minified function names. build_world.test.mjs checks every range and anchor against the hash-checked copy.
export const PROVENANCE = [
  { element: 'kerbs', file: 'assets/city-ground.runtime.min.js', functions: 'CityGround.create (Jt): road loop, kerb stones (curbSegments), joints', anchor: 'x.curbSegments+=1', port: 'world_ground.mjs', output: 'world_ground.glb Ground_c*' },
  { element: 'lamps', file: 'assets/city-ground.runtime.min.js', functions: 'Je (lamp pairs), ba / hn (lamp), high masts (x.highMasts.forEach), planHighMasts (Ja)', anchor: '[[0,.62,.62,.48,.22],[0,.2,.2,8.35,8.09]', port: 'world_ground.mjs', output: 'world_ground.glb (tt_lamp heads), lights.json lamps' },
  { element: 'benches', file: 'assets/city-ground.runtime.min.js', functions: 'bt (bench), walk-bench (Tr block), river benches (Wa, landscape Bench)', anchor: 'kind:"bench",alongX:a,top:2.42', port: 'world_ground.mjs', output: 'world_ground.glb' },
  { element: 'shelters', file: 'assets/city-ground.runtime.min.js', functions: 'mn (bus shelter), xn (bus sign), taxi rank', anchor: 'kind:"bus-shelter",top:7.6', port: 'world_ground.mjs', output: 'world_ground.glb' },
  { element: 'canal_walls', file: 'assets/city-ground.runtime.min.js', functions: 'refinedBankSegments + blender-bank-coping (landscape Coping), bank-waterline-stain, river-walk pavements', anchor: 'Ie.name="blender-bank-coping"', port: 'world_ground.mjs', output: 'world_ground.glb' },
  { element: 'ground_surfaces', file: 'assets/city-ground.runtime.min.js', functions: 'la (ground slabs), roads, crossings, parks, block walks, bridges (cn), viaducts, tunnels, Ce/en/rn height fields', anchor: 'la(-ye,ye,-2,3.2)', port: 'world_ground.mjs', output: 'world_ground.glb' },
  { element: 'street_furniture', file: 'assets/city-ground.runtime.min.js', functions: 'wn (bike racks), gn (vending), Ba (mailbox), zn (bins), Tr walk street, festoons (Wa), dn planting, Bn trees', anchor: 'kind:"bike-rack",top:2.9,bicycles:3', port: 'world_ground.mjs', output: 'world_ground.glb' },
  { element: 'canal_fountain', file: 'assets/city-ground.runtime.min.js', functions: 'canal fountain stones (vr), droplets (wa / Ma)', anchor: 'Lr.name="canal-fountain-water"', port: 'world_ground.mjs', output: 'world_ground.glb CanalFountain; world.json canal_fountain' },
  { element: 'sports_ground', file: 'city-playground.js', functions: 'create', lines: [4, 93], port: 'world_ground.mjs playground()', output: 'world_ground.glb' },
  { element: 'facility_bodies', file: 'city-facilities.js', functions: 'create: box, lightPane, markDoor, windowRows, parapet, frontPorch, storey, shutters, buildTeachingBlock, buildHall, buildSmallCentre, buildClinic, buildPrecinct, buildWaste, buildPodium, buildArchitecture', lines: [773, 1592], port: 'world_facilities.mjs', output: 'world_facilities.glb Facilities_c*, Windows_*, Door_*' },
  { element: 'facility_architecture', file: 'city-facilities.js', functions: 'architectureParts (pure, run in the vm)', lines: [428, 677], port: 'world_facilities.mjs', output: 'world_facilities.glb Facilities_c*' },
  { element: 'housing_floor_detail', file: 'city-housing.js', functions: 'create: facade, floorModule, roofModule, garden, planter, windowRank, paletteFor, detailsFor; load (module merge)', lines: [14, 410], port: 'world_housing.mjs', output: 'world_housing.glb Housing_c*, Windows_*, Door_*' },
  { element: 'station_building', file: 'city-transit.js', functions: 'create: pad, platforms, bays, arrows, canopy, booth, benches, name board; vehicle (templates)', lines: [11, 300], port: 'world_station.mjs', output: 'world_station.glb Station_c*, Station_BusTemplate, Station_TaxiTemplate' },
  { element: 'fences', file: 'city-landmarks.js', functions: 'amusementPark: gate, perimeter fences, booth, bench, planter, parkLights', lines: [394, 433], port: 'world_landmarks.mjs', output: 'world_landmarks.glb Amusement_c*' },
  { element: 'ferris_wheel', file: 'city-landmarks.js', functions: 'amusementPark: supports, axle, rotor, ferrisLights, cabins, doors; update (motion)', lines: [338, 536], port: 'world_landmarks.mjs', output: 'world_landmarks.glb FerrisWheel' },
  { element: 'plaza_paving', file: 'city-landmarks.js', functions: 'monumentPlaza (paving, rings, joints, lamps)', lines: [561, 628], port: 'world_landmarks.mjs', output: 'world_landmarks.glb Plaza_c*' },
  { element: 'balloon_carts', file: 'city-landmarks.js', functions: 'balloonCarts, bobBalloons', lines: [630, 711], port: 'world_landmarks.mjs', output: 'world_landmarks.glb BalloonCarts_c*, BalloonCarts_Balloons' },
  { element: 'stall_bodies', file: 'city-waterfront.js', functions: 'create: promenade, lampTrain, lantern, stool, stalls.forEach, street office', lines: [181, 444], port: 'world_market.mjs', output: 'world_market.glb Market_c*, Stall_*_Awning, Market_Goods_c*, Market_Lights_c*, StreetOffice_c*' },
  { element: 'street_lamp_lights', file: 'city-scene.js', functions: 'createStreetLighting (spot heights 8.06 / 17.05, ranges 26 / 42, intensities 100 / 480)', lines: [283, 283], port: 'world_ground.mjs', output: 'lights.json lamps' },
  { element: 'kit_colours', file: 'city-materials.js', functions: 'kit (in create: stone, road, pavement, ground, grass, metal, trunk, leaf)', lines: [752, 772], port: 'world_ground.mjs K', output: 'COLOR_0 in every file' },
];
// The "Not extractable" list of CHECKPOINT.md, each mapped to the counts that prove it was built.
export const REQUIRED = {
  kerbs: ['kerb_stones'], lamps: ['lamps', 'high_masts'], benches: ['benches'], shelters: ['bus_shelters', 'bus_signs'],
  canal_walls: ['canal_wall_segments'], facility_bodies: ['facility_buildings', 'facility_annexes'], housing_floor_detail: ['housing_windows', 'housing_blocks'],
  station_building: ['station_bays', 'station_columns'], fences: ['fences'], ferris_wheel: ['ferris_cabins'], stall_bodies: ['stalls'],
};

// Budgets (design section 8 sets the draw calls of the whole town: <= 180 iPad, <= 140 TV; this layer takes
// at most half). Triangle budgets are this builder's own, sized for the A12-class TV.
export const BUDGET = {
  surfaces_total: 300,          // every node x material in the seven files, as authored
  surfaces_worst_view: 200,     // as authored, the worst of 2,300 street views (wedge 100 deg x 200 m, ranges applied)
  merged_worst_view: 110,       // after the per-chunk merge the world builder does at load (README): <= 0.6 of 180
  merged_arrival_view: 100,     // the arrival framing, merged
  triangles_total: 700000,
  triangles_per_file: { world_ground: 300000, world_facilities: 60000, world_housing: 240000, world_station: 10000, world_landmarks: 30000, world_market: 90000, world_signs: 30000 },
  triangles_per_node: 70000,
  file_bytes_total: 48000000,
  real_lights: 4,
};

export async function build() {
  const up = C.loadUpstream();
  const T = await C.loadThree();
  const town = C.loadTownJson();
  const city = C.buildCity(up.ctx);
  const life = up.ctx.CityLife.create(city);
  const files = {}, counts = {}, stats = {};
  const solids = new C.ItemCollector();
  const lampList = [], spots = [], pools = [];
  const lights = {
    lamp: (l) => lampList.push(l),
    spot: (u) => spots.push(u),
    pool: (p) => pools.push(p),
  };
  const world = { doors: [], windows: [], signs: [], buildings: {} };
  const env = { T, ctx: up.ctx, city, life, town, rng: up.ctx.CityRandom.randomGenerator, solids, lights, counts, world, chunkOf: C.chunkOf,
    walkable: [], lanterns: [], shelters: [], busSigns: [], walkGates: [] };
  const scenes = {};
  // Per-file material merges (draw calls; design section 8). Roughness differences between the merged
  // groups are small at the follow camera's distance.
  const REMAP = {
    world_ground: { tt_paint: 'tt_matte', tt_metal: 'tt_matte', tt_fixture: 'tt_lamp' }, world_signs: { tt_metal: 'tt_sign', tt_paint: 'tt_sign' },
    world_market: { tt_paint: 'tt_matte', tt_metal: 'tt_matte', tt_fixture: 'tt_lamp' }, world_facilities: { tt_matte: 'tt_paint', tt_metal: 'tt_paint' },
    world_housing: { tt_metal: 'tt_matte', tt_paint: 'tt_matte' }, world_station: { tt_matte: 'tt_paint', tt_metal: 'tt_paint', tt_glass: 'tt_paint' },
    world_landmarks: { tt_glass: 'tt_paint', tt_metal: 'tt_paint', tt_matte: 'tt_paint' },
  };
  const newFile = (name) => {
    const file = new C.SceneFile(name); scenes[name] = file; file.remap = REMAP[name];
    const makeEmitter = (node) => { const em = new C.Emitter(file, node, stats); em.items = solids; return em; };
    const makeChunked = (prefix) => {
      const em = new C.Emitter(file, (x, z) => { const [ix, iz] = C.chunkOf(x, z); return file.node(prefix + '_c' + ix + '_' + iz); }, stats);
      em.items = solids; em.split = true; return em;
    };
    return { file, makeEmitter, makeChunked };
  };
  // ---- the seven files
  {
    const f = newFile('world_ground');
    const fountain = f.file.node('CanalFountain');
    buildGround(Object.assign(env, { em: f.makeChunked('Ground'), file: f.file, fountainEmitter: f.makeEmitter(fountain) }));
  }
  { const f = newFile('world_facilities'); buildFacilities(Object.assign(env, { file: f.file, makeEmitter: f.makeEmitter, makeChunked: f.makeChunked })); }
  { const f = newFile('world_housing'); buildHousing(Object.assign(env, { file: f.file, makeEmitter: f.makeEmitter, makeChunked: f.makeChunked })); }
  { const f = newFile('world_station'); buildStation(Object.assign(env, { file: f.file, makeEmitter: f.makeEmitter, makeChunked: f.makeChunked })); }
  { const f = newFile('world_landmarks'); buildLandmarks(Object.assign(env, { file: f.file, makeEmitter: f.makeEmitter, makeChunked: f.makeChunked })); }
  { const f = newFile('world_market'); buildMarket(Object.assign(env, { file: f.file, makeEmitter: f.makeEmitter, makeChunked: f.makeChunked })); }
  { const f = newFile('world_signs'); buildSigns(Object.assign(env, { file: f.file, makeEmitter: f.makeEmitter, makeChunked: f.makeChunked })); }
  counts.fences = solids.items.filter((s) => s.kind === 'fence').length;

  // ---- write the GLBs, measure them
  const fileStats = {}, nodeIndex = {};
  for (const name of Object.keys(scenes)) {
    const { glb, stats: st } = C.writeGlb(scenes[name]);
    void REMAP;
    files[name + '.glb'] = glb;
    files[name + '.glb.import'] = Buffer.from('[remap]\n\nimporter="keep"\n', 'utf8');
    const nodes = scenes[name].allNodes();
    const perNode = nodes.map((n) => {
      const ref = n.meshRef || n;
      let tris = 0, surf = 0;
      const bounds = [Infinity, Infinity, Infinity, -Infinity, -Infinity, -Infinity];
      for (const [mat, md] of ref.surfaces) {
        if (!md.idx.length) continue;
        surf++; tris += md.triangleCount;
        for (let i = 0; i < md.pos.length; i += 3) for (let k = 0; k < 3; k++) {
          const v = (md.pos[i + k] + ref.origin[k]) * S;
          bounds[k] = Math.min(bounds[k], v); bounds[k + 3] = Math.max(bounds[k + 3], v);
        }
        void mat;
      }
      return { name: n.name, triangles: tris, surfaces: surf, materials: [...ref.surfaces.keys()].filter((k) => ref.surfaces.get(k).idx.length), bounds: surf ? bounds : null,
        world: surf ? worldBounds(scenes[name], n, bounds) : null, mesh_owner: n.meshRef ? n.meshRef.name : null };
    });
    perNode.forEach((p) => { nodeIndex[p.name] = name + '.glb'; });
    fileStats[name] = { file: name + '.glb', bytes: glb.length, sha256: crypto.createHash('sha256').update(glb).digest('hex'), nodes: st.nodes,
      mesh_nodes: st.meshNodes, surfaces: st.surfaces, triangles: st.triangles, vertices: st.vertices, triangles_by_material: st.byMaterial, node_list: perNode };
  }
  // ---- budgets: draw calls (surfaces) in total and per view
  const arrival = town.places.station.arrival;
  let surfacesTotal = 0, trianglesTotal = 0, bytesTotal = 0, maxNode = { name: null, triangles: 0 };
  const all = [];
  for (const fs2 of Object.values(fileStats)) {
    surfacesTotal += fs2.surfaces; trianglesTotal += fs2.triangles; bytesTotal += fs2.bytes;
    fs2.node_list.forEach((n) => { if (n.world) all.push(n); if (n.triangles > maxNode.triangles) maxNode = { name: n.name, triangles: n.triangles }; });
  }
  const views = viewDrawCalls(all, arrival, city, solids);
  const budgets = { limits: BUDGET, surfaces_total: surfacesTotal, surfaces_arrival_view: views.arrival, surfaces_worst_view: views.worst, worst_view: views.worstAt,
    merged_arrival_view: views.arrivalMerged, merged_worst_view: views.worstMerged, merged_worst_view_at: views.worstMergedAt,
    views_sampled: views.count, triangles_total: trianglesTotal, triangles_arrival_view: views.arrivalTriangles, triangles_worst_view: views.worstTriangles,
    largest_node: maxNode, file_bytes_total: bytesTotal, real_light_candidates: lampList.filter((l) => l.omni).length };

  // ---- lights.json
  const P = (p) => [m(p[0]), m(p[1]), m(p[2])];
  const lightsJson = {
    format: 1, units: 'metres', source: 'upstream city-ground.runtime.min.js (lamp anchors, light pools, Br anchors), city-scene.js createStreetLighting, city-transit.js, city-landmarks.js, city-waterfront.js; positions converted x 0.5',
    schedule: {
      lamps: 'the lamps factor of the town clock (thousand_clock / upstream city-life-ext/lighting.js): on 18:30-06:00 with 15-minute fades',
      tt_lamp: 'emission = COLOR_0 x lamps: street and lawn lamp heads (upstream x 3.4), the light strips and coloured lanterns of the ground layer (upstream 0.15 + 1.3 x lamps, merged here; draw-call budget), station canopy strips (x 1.7), park and plaza lamp heads, the wheel rim bulbs and cabin glazing, market festoons and lanterns (x 2.6 while the market is busy, 0.12 when empty: city-waterfront.js)',
      tt_fixture: 'not used in the shipped files (merged into tt_lamp)',
      tt_window: 'emission = COLOR_0 for panes with TEXCOORD_0.x < the building light level, others discarded; level from thousand_sim occupancy (town-view lightLevel)',
      tt_sign: 'emission = COLOR_0 x 0.35 x lamps',
    },
    real_lights: { budget: BUDGET.real_lights, rule: 'each frame (or every 0.25 s) light the nearest omni candidates to the camera with OmniLight3D, range and colour from the entry; every other lamp is emissive only (design section 8: sun + moon + 4 omni)', energy_hint: 'upstream spot intensity 100 (street) / 480 (high mast) in Three physical units; fit to Lantern Lane exposure, see design section 9' },
    lamps: lampList.map((l, i) => ({ id: 'lamp-' + i, kind: l.kind, position: P([l.x, l.y, l.z]), ground_y: m(l.ground), colour: l.color, range_m: m(l.range), omni_candidate: !!l.omni,
      spot: l.spot ? { target: P([l.x, l.ground + 0.06, l.z]), angle: l.angle, penumbra: 0.7, decay: 2, intensity_upstream: l.energy } : undefined,
      stall: l.stall, building: l.building, strip_length_m: l.strip_length ? m(l.strip_length) : undefined, note: l.note })),
    spots: spots.map((u, i) => ({ id: 'spot-' + i, kind: u.kind, position: P([u.x, u.y, u.z]), target: P([u.tx, u.ty, u.tz]), colour: u.color, power_upstream: u.power, range_m: m(u.range), angle: u.angle,
      span_m: u.span ? u.span.map(m) : undefined, phase: u.phase })),
    pools: pools.map((p, i) => ({ id: 'pool-' + i, source: p.source, centre: P([p.x, p.y, p.z]), size_m: [m(p.w), m(p.d)], level: p.level, colour: p.color })),
    lanterns: env.lanterns.map((l, i) => ({ id: 'lantern-' + i, kind: l.kind, position: P([l.x, l.y, l.z]), colour: l.color || null, stall: l.stall })),
    window_groups: world.windows,
    viaduct_flow_strips: (env.viaductFlowStrips || []).map((s) => ({ centre: P([s.x, s.y, s.z]), size_m: [m(s.w), m(s.h), m(s.d)] })),
  };
  // ---- solids.json
  const solidsJson = {
    format: 1, units: 'metres',
    rule: 'footprints of everything that blocks walking between 0.25 m and 1.8 m above its own ground: a box of one item reaching into that band is merged with the boxes it touches into one rect, a single turned box keeps its quad. bottom/top are absolute heights.',
    solids: solids.items.map((s) => Object.assign({ kind: s.kind, id: s.id, bottom: m(s.bottom), top: m(s.top) },
      s.rect ? { rect: { x: m(s.rect.x), z: m(s.rect.z), w: m(s.rect.w), d: m(s.rect.d) } } : { poly: s.poly.map((p) => [m(p[0]), m(p[1])]) },
      s.building ? { building: s.building } : {}, s.stall ? { stall: s.stall } : {})),
    walkable: env.walkable.map((w) => {
      const o = { kind: w.kind, rect: { x: m(w.x), z: m(w.z), w: m(w.w), d: m(w.d) } };
      if (w.y !== undefined) o.y = m(w.y);
      if (w.y_from !== undefined) { o.y_from = m(w.y_from); o.y_to = m(w.y_to); o.toward = w.toward; }
      if (w.building) o.building = w.building;
      if (w.profile === 'bridge') o.profile = { kind: 'bridge', formula: 'y = 0.5 x (0.25 + 1.7 x smooth((w/2 + 10 - |X - x|) / 10) x smooth((d/2 + 4 - |Z - z|) / 4)), X Z x z w d in upstream units (= metres x 2); smooth(e) = e^2 (3 - 2e) clamped', bridge: { x: m(w.bridge.x), z: m(w.bridge.z), w: m(w.bridge.w), d: m(w.bridge.d) } };
      if (w.profile === 'viaduct') o.profile = { kind: 'viaduct', formula: 'y = 0.5 x (0.25 + (height - 0.25) x smooth((flatX + rampX - |X|) / rampX) x smooth((d/2 + 2.7 - |Z - z|) / 1.2)) (upstream units)', viaduct: { z: m(w.viaduct.z), d: m(w.viaduct.d), height: m(w.viaduct.height), flatX: m(w.viaduct.flatX), rampX: m(w.viaduct.rampX) } };
      if (w.profile === 'tunnel') o.profile = { kind: 'tunnel', formula: 'y = 0.5 x (0.25 - drop x smooth(min(1, max(0, (portalX - |X|) / (portalX - coverX)))) (upstream units)', tunnel: { z: m(w.tunnel.z), halfD: m(w.tunnel.halfD), portalX: m(w.tunnel.portalX), coverX: m(w.tunnel.coverX), drop: m(w.tunnel.drop) } };
      return o;
    }),
    datums: { pavement_y: m(0.25), road_y: m(0.25), park_lawn_y: m(0.12), building_floor_y: m(1.4), water_y: m(-0.55), kerb_top_y: m(0.38) },
  };
  // ---- world.json (manifest)
  const fountain = env.canalFountain;
  const worldJson = {
    format: 1, units: 'metres (upstream x 0.5)',
    source: { title: '千人小镇 · Thousand Town', repository: 'https://github.com/YiHuiShiBY/thousand-town', commit: C.COMMIT, licence: 'CC BY 4.0', author: '仪绘士 / YiHuiShiBY',
      changes: 'design/thousand-town.md section 12; game/thousand_town/data/README.md', builder: 'scripts/thousand_town/build_world.mjs', files: C.hashTable() },
    files: Object.fromEntries(Object.entries(fileStats).map(([k, v]) => [k, { file: v.file, bytes: v.bytes, sha256: v.sha256, nodes: v.nodes, surfaces: v.surfaces, triangles: v.triangles, vertices: v.vertices, triangles_by_material: v.triangles_by_material,
      nodes_list: v.node_list.map((n) => ({ name: n.name, triangles: n.triangles, surfaces: n.surfaces, materials: n.materials, aabb: n.world })) }])),
    materials: C.MATERIALS,
    godot: {
      load: 'GLTFDocument.append_from_file + generate_scene at run time (importer="keep"), as ThousandMap.glb_scene()',
      materials: 'replace each glTF material by name: vertex_color_use_as_albedo = true (vertex_color_is_srgb = false; COLOR_0 is linear); tt_* emission per lights.json schedule',
      chunks: 'Ground_c*, Facilities_c*, Housing_c*, Market_c*, Signs_c*: 16 cells (x cuts -48, 0, 48 m; z cuts -64.5, 0, 64.5 m) with frustum culling; visibility ranges for small nodes in visibility_ranges_m',
      visibility_ranges_m: Object.fromEntries(VISIBILITY.map(([re, r]) => [re.source, r])),
    },
    animate: {
      ferris_wheel: world.ferris_wheel, balloons: world.balloons,
      doors: world.doors, windows: world.windows, stalls: world.stalls,
      canal_fountain: { node: 'CanalFountain', centre: [m(fountain.x), 0, m(fountain.z)], gravity_m_s2: m(fountain.gravity), basin: { inner_m: m(fountain.basin.inner), outer_m: m(fountain.basin.outer), surface_y_m: m(fountain.basin.surface_y) },
        rule: 'droplet at time t: u = ((t / period + phase) mod 1) x period; p = p0 + v u - (0, g u^2 / 2, 0); upstream drives the pump level from CityFountain (city-fountain.js PROGRAM: off 22:00-05:30)',
        droplets: fountain.droplets.map((d) => ({ p0: [m(d.x), m(d.y), m(d.z)], v: [m(d.vx), m(d.vy), m(d.vz)], radius_m: m(d.s), phase: d.phase, period_s: d.period })) },
      vehicles: world.vehicles,
    },
    signs: world.signs,
    buildings: world.buildings,
    nodes: nodeIndex,
    counts, budgets,
    provenance: PROVENANCE,
    not_ported: NOT_PORTED,
    scale: {
      rule: 'upstream x 0.5 everywhere (design section 1) except doors, raised to 2.1 m (4.2 units) from their sill',
      doors_m: { min: Math.min(...world.doors.map((d) => d.height_m)), count: world.doors.length },
    },
  };
  files['world.json'] = Buffer.from(C.ser(worldJson) + '\n', 'utf8');
  files['lights.json'] = Buffer.from(C.ser(lightsJson) + '\n', 'utf8');
  files['solids.json'] = Buffer.from(C.ser(solidsJson) + '\n', 'utf8');
  return { files, worldJson, lightsJson, solidsJson, scenes, env, up };
}

// A node's axis-aligned bounds in world metres: its local vertex bounds (metres, already including the
// node's `origin`) are taken through the translations and rotations of its parents and itself.
function worldBounds(file, node, local) {
  const chain = [];
  const find = (list, path) => { for (const n of list) { const p = path.concat([n]); if (n === node) return p; const r = find(n.children, p); if (r) return r; } return null; };
  const pathTo = find(file.roots, chain) || [node];
  // The local bounds were measured with the node origin added back; nodes with a translation carry vertices
  // relative to it, so remove the origin again before applying the node transforms.
  const o = node.translation ? node.origin.map((v) => v * S) : [0, 0, 0];
  let pts = [];
  for (const x of [local[0], local[3]]) for (const y of [local[1], local[4]]) for (const z of [local[2], local[5]]) pts.push([x - o[0], y - o[1], z - o[2]]);
  for (let i = pathTo.length - 1; i >= 0; i--) {
    const n = pathTo[i];
    if (!n.translation && !n.rotation) continue;
    const q = n.rotation || [0, 0, 0, 1], t = n.translation || [0, 0, 0];
    pts = pts.map((p) => { const r = rotQ(q, p); return [r[0] + t[0], r[1] + t[1], r[2] + t[2]]; });
  }
  const b = [Infinity, Infinity, Infinity, -Infinity, -Infinity, -Infinity];
  pts.forEach((p) => { for (let k = 0; k < 3; k++) { b[k] = Math.min(b[k], p[k]); b[k + 3] = Math.max(b[k + 3], p[k]); } });
  return b;
}
function rotQ(q, v) {
  const [x, y, z, w] = q, ix = w * v[0] + y * v[2] - z * v[1], iy = w * v[1] + z * v[0] - x * v[2], iz = w * v[2] + x * v[1] - y * v[0], iw = -x * v[0] - y * v[1] - z * v[2];
  return [ix * w + iw * -x + iy * -z - iz * -y, iy * w + iw * -y + iz * -x - ix * -z, iz * w + iw * -z + ix * -y - iy * -x];
}
// Recommended visibility ranges (metres, Godot visibility_range_end; none = always): small detail fades
// with distance so a view costs what the child can actually see. The view metric below honours them.
export const VISIBILITY = [
  [/^Door_/, 45], [/^Stall_.*_Awning$/, 80], [/^Market_Goods_c/, 60], [/^Signs_c/, 90], [/^BalloonCarts/, 80],
  [/^CanalFountain$/, 150], [/^Station_(Bus|Taxi)Template$/, 0],
];
export const visibilityOf = (name) => { const r = VISIBILITY.find(([re]) => re.test(name)); return r ? r[1] : null; };

// Draw calls per view: a camera wedge on the ground plane (100 degrees wide, the follow camera's 16:9 view at
// a 60 degree vertical field, out to 200 m) counts the surfaces of every node whose bounds it touches. Views:
// the arrival framing (behind the child, looking east), and a 12 m grid of street points x 8 headings.
function viewDrawCalls(nodes, arrival, city, solids) {
  const half = 50 * Math.PI / 180, range = 200;
  const count = (cx, cz, heading) => {
    let s = 0, t = 0;
    const merged = new Map(); // chunk suffix -> material set (the per-chunk merge Godot does at load)
    const dx = Math.cos(heading), dz = Math.sin(heading);
    for (const n of nodes) {
      const b = n.world, vis = visibilityOf(n.name);
      if (vis === 0) continue; // templates are instanced elsewhere, never drawn in place
      if (vis) { const ddx = Math.max(b[0] - cx, 0, cx - b[3]), ddz = Math.max(b[2] - cz, 0, cz - b[5]); if (Math.hypot(ddx, ddz) > vis) continue; }
      if (cx >= b[0] && cx <= b[3] && cz >= b[2] && cz <= b[5]) { s += n.surfaces; t += n.triangles; continue; }
      const xs = [b[0], (b[0] + b[3]) / 2, b[3]], zs = [b[2], (b[2] + b[5]) / 2, b[5]];
      let seen = false;
      for (const x of xs) { for (const z of zs) {
        const vx = x - cx, vz = z - cz, d = Math.hypot(vx, vz);
        if (d <= range && (vx * dx + vz * dz) >= d * Math.cos(half)) { seen = true; break; }
      } if (seen) break; }
      if (seen) { s += n.surfaces; t += n.triangles; }
      if (seen || (cx >= b[0] && cx <= b[3] && cz >= b[2] && cz <= b[5])) {
        const chunk = /_c(\d_\d)$/.exec(n.name);
        const key = chunk ? 'chunk' + chunk[1] : 'mesh:' + (n.mesh_owner || n.name);
        if (!merged.has(key)) merged.set(key, new Set());
        n.materials.forEach((mm) => merged.get(key).add(mm));
      }
    }
    let ms = 0; merged.forEach((set) => { ms += set.size; });
    return [s, t, ms];
  };
  const [arrivalS, arrivalT, arrivalM] = count(arrival.x - 7 * arrival.facing[0], arrival.z - 7 * arrival.facing[1], Math.atan2(arrival.facing[1], arrival.facing[0]));
  let worst = 0, worstT = 0, worstAt = null, n = 0, worstM = 0, worstMAt = null;
  const blocked = (x, z) => solids.items.some((s) => s.kind === 'building' && s.rect && Math.abs(s.rect.x * S - x) < s.rect.w * S / 2 && Math.abs(s.rect.z * S - z) < s.rect.d * S / 2);
  for (let x = -90; x <= 90; x += 12) for (let z = -126; z <= 126; z += 12) {
    if (Math.abs(x) < 7.5 || blocked(x, z)) continue;
    for (let k = 0; k < 8; k++) {
      const [s, t, ms] = count(x, z, k * Math.PI / 4); n++;
      if (s > worst) { worst = s; worstAt = { x, z, heading_deg: k * 45 }; }
      if (ms > worstM) { worstM = ms; worstMAt = { x, z, heading_deg: k * 45 }; }
      worstT = Math.max(worstT, t);
    }
  }
  return { arrival: arrivalS, arrivalTriangles: arrivalT, worst, worstTriangles: worstT, worstAt, count: n, arrivalMerged: arrivalM, worstMerged: worstM, worstMergedAt: worstMAt };
}

// Elements upstream builds that this port does not draw, and why.
const NOT_PORTED = [
  { element: 'canal water surface (Reflector + NaturalCanalReflection shader)', why: 'design section 12: Godot draws its own water at town.json canal (y -0.275 m); a planar reflector is too costly on the TV' },
  { element: 'waterfall "cosmic edge" flows', why: 'an additive night shader on quads below the board ends; out of the walkable town and of the camera at player height' },
  { element: 'festival flags, festival flower colours, bridge flags', why: 'National Day dressing (design section 0)' },
  { element: 'Chinese name boards and sign atlases (facilities, station, market, office, park gate, plaza)', why: 'design section 0; replaced by world_signs.glb pictograms' },
  { element: 'seated fares in the wheel, bus passengers, balloon vendor', why: 'Lantern Lane draws its own people (design section 5)' },
  { element: 'carousel, teacups, monument, plaza benches and planters', why: 'already W-DATA meshes (amusement.glb, landscape.glb), placed from town.json' },
  { element: 'civic GLB modules and the hospital ward', why: 'already W-DATA meshes (civic.glb, hospital_room.glb); this port drops the boxes upstream drops when they are present' },
  { element: 'light pools, spot lights, viaduct flow strip colours, fountain droplets', why: 'dynamic: written as data (lights.json, world.json) for Godot decals, lights and particles' },
  { element: 'tree crowns at icosahedron detail 2', why: 'budget: detail 1 with the same displacement noise (80 instead of 320 triangles a crown)' },
];

function writeAll(files, dir) {
  fs.mkdirSync(dir, { recursive: true });
  for (const name of Object.keys(files).sort()) fs.writeFileSync(path.join(dir, name), files[name]);
}

async function main() {
  const args = process.argv.slice(2);
  const result = await build();
  const { files } = result;
  if (args.includes('--check')) {
    let bad = 0;
    for (const name of Object.keys(files).sort()) {
      const a = path.join(C.DATA, name);
      const same = fs.existsSync(a) && Buffer.compare(fs.readFileSync(a), files[name]) === 0;
      if (!same) { bad++; console.log('DIFFERS ' + name); }
    }
    const report = runChecks(result);
    report.lines.forEach((l) => console.log(l));
    console.log('THOUSAND WORLD CHECK: ' + Object.keys(files).length + ' files, ' + (Object.keys(files).length - bad) + ' identical; ' +
      report.checks + ' checks, ' + report.failures + ' failures');
    process.exit(bad || report.failures ? 1 : 0);
  }
  const outIndex = args.indexOf('--out');
  const dir = outIndex >= 0 ? path.resolve(args[outIndex + 1]) : C.DATA;
  writeAll(files, dir);
  console.log('wrote ' + Object.keys(files).length + ' files to ' + path.relative(C.ROOT, dir));
  for (const name of Object.keys(files).sort()) console.log('  ' + name.padEnd(28) + String(files[name].length).padStart(10) + '  ' + crypto.createHash('sha256').update(files[name]).digest('hex'));
  const b = result.worldJson.budgets;
  console.log('surfaces ' + b.surfaces_total + ' (arrival view ' + b.surfaces_arrival_view + ', worst view ' + b.surfaces_worst_view + '; merged per chunk: arrival ' + b.merged_arrival_view + ', worst ' + b.merged_worst_view + '), triangles ' + b.triangles_total +
    ' (arrival view ' + b.triangles_arrival_view + ', worst ' + b.triangles_worst_view + '), bytes ' + b.file_bytes_total);
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) main();
