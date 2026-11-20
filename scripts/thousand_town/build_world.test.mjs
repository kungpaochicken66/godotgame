#!/usr/bin/env node
// Checks for build_world.mjs (design/thousand-town.md sections 1 and 8).
//
//   node scripts/thousand_town/build_world.test.mjs     build twice in memory, compare the bytes, run the checks
//   node scripts/thousand_town/build_world.mjs --check  compare a fresh build with the files on disk + the checks
//
// What is checked: determinism; the pinned upstream hashes (re-hashed here); the GLB structure (accessors,
// index bounds, unit normals, colour range, finite positions inside the board); scale against the 1.30 m
// child (doors 2.1 m, storey 3.0 m, lamps, benches, stools, kerbs, canopy headroom, the wheel); the budgets;
// every element of the checkpoint's "Not extractable" list present with named nodes; the provenance table
// (every range inside its hash-checked file and naming the function, every minified anchor found once); the
// solids (well formed, the arrival point free); the signs (all placed, plate size, contrast).
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import * as C from './world_core.mjs';
import { build, PROVENANCE, REQUIRED, BUDGET } from './build_world.mjs';
import { CATEGORY } from './world_signs.mjs';

const H = 1.3; // the child (design/object-scale-and-surfaces.md)

export function runChecks(result) {
  const lines = [];
  let checks = 0, failures = 0;
  const ok = (cond, label) => { checks++; if (!cond) { failures++; lines.push('FAIL ' + label); } };
  const { files, worldJson: W, lightsJson: L, solidsJson: S, env } = result;
  const counts = W.counts;

  // ---- pinned upstream and local hashes, re-hashed here
  const table = C.hashTable();
  for (const [key, sha] of Object.entries(table)) {
    const file = key.startsWith('upstream/') ? path.join(C.UPSTREAM, key.slice(9)) : path.join(C.ROOT, key);
    const actual = fs.existsSync(file) ? crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex') : null;
    ok(actual === sha, 'hash of ' + key);
  }
  ok(JSON.stringify(W.source.files) === JSON.stringify(table), 'world.json records the hash table');
  ok(W.source.commit === C.COMMIT, 'pinned commit recorded (loadUpstream refuses any other)');

  // ---- GLB structure
  for (const [name, buf] of Object.entries(files)) {
    if (!name.endsWith('.glb')) continue;
    ok(buf.readUInt32LE(0) === 0x46546c67 && buf.readUInt32LE(4) === 2 && buf.readUInt32LE(8) === buf.length, name + ' header');
    const jl = buf.readUInt32LE(12), json = JSON.parse(buf.subarray(20, 20 + jl).toString('utf8'));
    const binAt = 20 + jl, bin = buf.subarray(binAt + 8, binAt + 8 + buf.readUInt32LE(binAt));
    ok(json.buffers[0].byteLength <= bin.length, name + ' buffer length');
    const acc = (i) => json.accessors[i];
    const view = (a) => json.bufferViews[a.bufferView];
    let bad = 0, worldBad = 0;
    const local = new Set();
    const mark = (ni, inLocal) => { const n = json.nodes[ni]; const l = inLocal || !!(n.translation || n.rotation); if (l && n.mesh !== undefined) local.add(n.mesh); (n.children || []).forEach((c) => mark(c, l)); };
    json.scenes[0].nodes.forEach((n) => mark(n, false));
    json.meshes.forEach((mesh, mi) => mesh.primitives.forEach((p) => {
      const pa = acc(p.attributes.POSITION), na = acc(p.attributes.NORMAL), ca = acc(p.attributes.COLOR_0), ia = acc(p.indices);
      if (pa.count !== na.count || pa.count !== ca.count) bad++;
      if (ca.componentType !== 5123 || !ca.normalized || ca.type !== 'VEC4') bad++;
      const pv = view(pa), nv = view(na), cv = view(ca), iv = view(ia);
      const f32 = (v, i) => bin.readFloatLE(v.byteOffset + i * 4);
      for (let i = 0; i < pa.count; i += Math.max(1, Math.floor(pa.count / 4000))) {
        const x = f32(pv, i * 3), y = f32(pv, i * 3 + 1), z = f32(pv, i * 3 + 2);
        if (![x, y, z].every(Number.isFinite)) bad++;
        if (!local.has(mi) && (Math.abs(x) > 98 || Math.abs(z) > 130 || y < -3.5 || y > 70)) worldBad++;
        const n = Math.hypot(f32(nv, i * 3), f32(nv, i * 3 + 1), f32(nv, i * 3 + 2));
        if (Math.abs(n - 1) > 1e-3) bad++;
        if (bin.readUInt16LE(cv.byteOffset + i * 8 + 6) !== 65535) bad++;
      }
      const big = ia.componentType === 5125;
      for (let i = 0; i < ia.count; i++) { const v = big ? bin.readUInt32LE(iv.byteOffset + i * 4) : bin.readUInt16LE(iv.byteOffset + i * 2); if (v >= pa.count) { bad++; break; } }
      if (ia.count % 3) bad++;
    }));
    ok(bad === 0, name + ' accessors, unit normals, RGBA16 colours, index bounds (' + bad + ' bad)');
    ok(worldBad === 0, name + ' world-space vertices inside the board (' + worldBad + ' outside)');
    ok(json.asset.copyright && json.asset.copyright.includes('CC BY 4.0'), name + ' carries the CC BY credit');
    ok(files[name + '.import'] && files[name + '.import'].toString() === '[remap]\n\nimporter="keep"\n', name + ' has its keep import');
  }

  // ---- scale (design section 1; the child H = 1.30 m)
  const doors = W.animate.doors;
  ok(doors.length > 0 && doors.every((d) => d.height_m >= 2.1 - 1e-6 && d.height_m <= 2.4), 'doors 2.1 m (min ' + Math.min(...doors.map((d) => d.height_m)) + ')');
  const nodes = Object.fromEntries(Object.values(W.files).flatMap((f) => f.nodes_list.map((n) => [n.name, n])));
  // Storeys: every facility and housing body tops out at plinth 0.7 m + floors x 3.0 m + its roof kit.
  for (const b of env.town.buildings.filter((x) => x.kind !== 'tower')) {
    const rec = W.buildings[b.id];
    ok(rec && rec.top_m >= 0.7 + b.floors * 3 && rec.top_m <= 0.7 + b.floors * 3 + 5.5, b.id + ' (' + b.programme + '): ' + b.floors + ' storeys of 3.0 m (top ' + (rec && rec.top_m.toFixed(2)) + ' m)');
  }
  ok(nodes.Facilities_c3_1 && nodes.Facilities_c3_1.aabb[4] > 0.7 + 18, 'the hospital chunk rises above six storeys');
  const streetLamps = L.lamps.filter((l) => l.kind === 'street');
  ok(streetLamps.length > 50 && streetLamps.every((l) => l.position[1] - l.ground_y > 2.5 * H && l.position[1] - l.ground_y < 5), 'street lamp heads 3.25-5 m above their ground (' + streetLamps.length + ')');
  const lampSolids = S.solids.filter((s) => s.kind === 'lamp' && s.rect);
  ok(lampSolids.length > 50 && lampSolids.every((s) => Math.max(s.rect.w, s.rect.d) <= 0.5 && s.top > 3.5), 'lamp posts: slim footprint, tall (' + lampSolids.length + ')');
  const benches = S.solids.filter((s) => s.kind === 'bench');
  ok(benches.length > 10 && benches.every((s) => { const r = s.rect || null; return s.top > 0.45 && s.top < H + 0.05 && (!r || (Math.max(r.w, r.d) >= 1.2 && Math.max(r.w, r.d) <= 3.6)); }), 'benches: backrest below the child\'s head, 1.2-3.6 m long (' + benches.length + ')');
  const probes = env.scaleProbes;
  const seat = (probes.bench_seat_top - probes.pavement) * C.S;
  ok(seat > 0.4 && seat < 0.6, 'bench seat ' + seat.toFixed(3) + ' m above the pavement (child knee to hip)');
  const stool = (probes.stool_seat_top - probes.market_ground) * C.S;
  ok(stool > 0.4 && stool < 0.6, 'market stool seat ' + stool.toFixed(3) + ' m');
  const kerb = (probes.kerb_top - probes.road_top) * C.S;
  ok(kerb > 0.04 && kerb < 0.12, 'kerb step ' + kerb.toFixed(3) + ' m (walkable)');
  const canopy = (probes.canopy_soffit - probes.platform_top) * C.S;
  ok(canopy > 2.2, 'station canopy headroom ' + canopy.toFixed(2) + ' m');
  const shelter = (probes.shelter_soffit - probes.pavement) * C.S;
  ok(shelter > 2.2, 'bus shelter headroom ' + shelter.toFixed(2) + ' m');
  const rail = (probes.bridge_rail_top - probes.bridge_deck) * C.S;
  ok(rail > 0.8 && rail < 1.2, 'road bridge rail ' + rail.toFixed(2) + ' m above the deck');
  ok(W.animate.ferris_wheel.radius_m === 10 && W.animate.ferris_wheel.axle_y_m === 13, 'ferris wheel radius 10 m, axle 13 m');
  ok(W.animate.vehicles.bus.length_m === 6.3 && W.animate.vehicles.taxi.length_m === 3.45, 'bus 6.3 m, taxi 3.45 m');

  // ---- budgets
  const B = W.budgets;
  ok(B.surfaces_total <= BUDGET.surfaces_total, 'surfaces (draw calls if all drawn) ' + B.surfaces_total + ' <= ' + BUDGET.surfaces_total);
  ok(B.surfaces_worst_view <= BUDGET.surfaces_worst_view, 'draw calls, worst street view as authored ' + B.surfaces_worst_view + ' <= ' + BUDGET.surfaces_worst_view);
  ok(B.merged_worst_view <= BUDGET.merged_worst_view, 'draw calls, worst street view merged per chunk ' + B.merged_worst_view + ' <= ' + BUDGET.merged_worst_view);
  ok(B.merged_arrival_view <= BUDGET.merged_arrival_view, 'draw calls, arrival view merged per chunk ' + B.merged_arrival_view + ' <= ' + BUDGET.merged_arrival_view);
  ok(B.triangles_total <= BUDGET.triangles_total, 'triangles ' + B.triangles_total + ' <= ' + BUDGET.triangles_total);
  for (const [k, lim] of Object.entries(BUDGET.triangles_per_file)) ok(W.files[k] && W.files[k].triangles <= lim, k + ' triangles ' + (W.files[k] && W.files[k].triangles) + ' <= ' + lim);
  ok(B.largest_node.triangles <= BUDGET.triangles_per_node, 'largest node ' + B.largest_node.name + ' ' + B.largest_node.triangles + ' <= ' + BUDGET.triangles_per_node);
  ok(B.file_bytes_total <= BUDGET.file_bytes_total, 'bytes ' + B.file_bytes_total + ' <= ' + BUDGET.file_bytes_total);
  ok(B.real_light_candidates >= BUDGET.real_lights, 'real-light candidates ' + B.real_light_candidates);

  // ---- every element present
  for (const [el, keys] of Object.entries(REQUIRED)) ok(keys.every((k) => counts[k] > 0), 'element ' + el + ' built (' + keys.map((k) => k + '=' + counts[k]).join(', ') + ')');
  const need = ['CanalFountain', 'Station_c0_2', 'Station_BusTemplate', 'Station_TaxiTemplate', 'Amusement_c3_2', 'FerrisWheel', 'FerrisSupports', 'FerrisAxle', 'FerrisRotor', 'Plaza_c2_2', 'BalloonCarts_Balloons', 'StreetOffice_c1_0', 'StreetOffice_Windows']
    .concat(Array.from({ length: 12 }, (_, i) => 'FerrisCabin_' + String(i).padStart(2, '0')));
  need.forEach((n) => ok(W.nodes[n], 'node ' + n));
  ok(Object.keys(W.nodes).filter((n) => /^Stall_.*_Awning$/.test(n)).length === counts.stalls, 'an awning node per stall');
  ok(Object.keys(W.nodes).filter((n) => /^Ground_c\d_\d$/.test(n)).length === 16, '16 ground chunks');
  // Windows: every lit building but the hospital (its ward lights the interior) and the waste station (no
  // glazing), plus the four housing blocks and the street office.
  ok(W.animate.windows.length === 14 + 4 + 1 && W.animate.windows.every((w) => W.nodes[w.node] && w.panes > 0), 'window groups (' + W.animate.windows.length + ')');
  ok(W.animate.doors.every((d) => W.nodes[d.node] && /^Door_/.test(d.node)), 'door nodes (' + W.animate.doors.length + ')');
  ok(env.town.buildings.filter((b) => b.kind !== 'tower').every((b) => W.buildings[b.id] && W.nodes[W.buildings[b.id].body]), 'a body chunk for every facility and housing block');
  ok(env.town.annexes.every((a) => W.buildings[a.id] && W.nodes[W.buildings[a.id].body]), 'a body chunk for every annex');
  ok(W.animate.canal_fountain.droplets.length === 116, 'canal fountain: 116 droplets');

  // ---- provenance
  const sources = result.up.sources;
  const listed = new Set(PROVENANCE.map((p) => p.element));
  Object.keys(REQUIRED).forEach((el) => ok(listed.has(el), 'provenance lists ' + el));
  PROVENANCE.forEach((p) => {
    const src = sources[p.file];
    ok(!!src && table['upstream/' + p.file], 'provenance ' + p.element + ': ' + p.file + ' is hash-checked');
    ok(p.functions && p.functions.length > 4 && p.port && p.output, 'provenance ' + p.element + ': functions, port and output named');
    ok(fs.existsSync(path.join(path.dirname(fileURLToPath(import.meta.url)), p.port.split(' ')[0])), 'provenance ' + p.element + ': port file exists');
    if (!src) return;
    if (p.anchor) ok(src.split(p.anchor).length === 2, 'provenance ' + p.element + ': anchor found once in ' + p.file);
    if (p.lines) {
      const all = src.split('\n'), [a, b] = p.lines;
      ok(a >= 1 && b >= a && b <= all.length, 'provenance ' + p.element + ': lines ' + a + '-' + b + ' inside ' + p.file + ' (' + all.length + ')');
      const first = p.functions.split(/[ :,(]/)[0];
      const text = all.slice(a - 1, b).join('\n');
      ok(text.includes(first), 'provenance ' + p.element + ': lines ' + a + '-' + b + ' contain "' + first + '"');
    }
  });

  // ---- solids and walkables
  ok(S.solids.length > 300 && S.solids.every((s) => (s.rect ? s.rect.w > 0 && s.rect.d > 0 : s.poly.length === 4) && s.top > s.bottom), 'solids well formed (' + S.solids.length + ')');
  const kinds = new Set(S.solids.map((s) => s.kind));
  ['lamp', 'bench', 'bus-shelter', 'canal-wall', 'fence', 'stall', 'building', 'station-column', 'ticket-booth', 'tree'].forEach((k) => ok(kinds.has(k), 'solids include ' + k));
  const arr = env.town.places.station.arrival;
  const inside = S.solids.filter((s) => s.rect && Math.abs(s.rect.x - arr.x) < s.rect.w / 2 + 0.3 && Math.abs(s.rect.z - arr.z) < s.rect.d / 2 + 0.3);
  ok(inside.length === 0, 'the arrival point is clear of solids' + (inside.length ? ' (' + inside.map((s) => s.id).join(',') + ')' : ''));
  ok(S.walkable.some((w) => w.kind === 'road-bridge') && S.walkable.some((w) => w.kind === 'footbridge') && S.walkable.some((w) => w.kind.startsWith('station-')), 'walkables: bridges and the station platforms');

  // ---- signs
  const signs = W.signs;
  ok(counts.signs_unplaced.length === 0, 'every sign placed' + (counts.signs_unplaced.length ? ' (missing ' + counts.signs_unplaced.join(',') + ')' : ''));
  ok(signs.filter((s) => s.kind === 'totem' || s.kind === 'wall').length >= env.town.buildings.length + env.town.annexes.length, 'a totem (or a wall plate) per building and annex');
  ok(signs.filter((s) => s.kind !== 'ground-paint').every((s) => s.size_m >= 0.5), 'plates at least 0.5 m');
  ok(signs.filter((s) => s.kind === 'totem').every((s) => s.size_m >= 1.2 && s.y_m > 2 && s.y_m < 3.2), 'totem plates 1.3 m at camera height');
  const luminance = (hex) => { const c = C.lin(hex); return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]; };
  const contrast = (a, b) => { const x = luminance(a), y = luminance(b); return (Math.max(x, y) + 0.05) / (Math.min(x, y) + 0.05); };
  Object.entries(CATEGORY).forEach(([k, [plate, ink]]) => ok(contrast(plate, ink) >= 4.5, 'sign contrast ' + k + ' ' + contrast(plate, ink).toFixed(1)));
  lines.push('budgets: draw calls as authored ' + B.surfaces_total + ' total, arrival view ' + B.surfaces_arrival_view + ', worst view ' + B.surfaces_worst_view +
    '; merged per chunk: arrival ' + B.merged_arrival_view + ', worst ' + B.merged_worst_view + '; triangles ' + B.triangles_total + ' (arrival view ' + B.triangles_arrival_view +
    ', worst view ' + B.triangles_worst_view + '); bytes ' + B.file_bytes_total + '; largest node ' + B.largest_node.name + ' ' + B.largest_node.triangles);
  return { checks, failures, lines };
}

async function main() {
  const a = await build(), b = await build();
  let same = 0, diff = [];
  for (const name of Object.keys(a.files)) { if (b.files[name] && Buffer.compare(a.files[name], b.files[name]) === 0) same++; else diff.push(name); }
  const report = runChecks(a);
  report.checks++; if (diff.length) { report.failures++; report.lines.push('FAIL determinism: ' + diff.join(', ')); }
  report.lines.forEach((l) => console.log(l));
  console.log('determinism: ' + same + '/' + Object.keys(a.files).length + ' files byte-identical across two builds');
  console.log('THOUSAND WORLD TESTS: ' + report.checks + ' checks, ' + report.failures + ' failures');
  process.exit(report.failures ? 1 : 0);
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) main();
