// Port of upstream's ground layer: assets/city-ground.runtime.min.js, `CityGround.create` (minified `Jt`),
// plus its pure high-mast planner (`planHighMasts`, minified `Ja`) and city-playground.js `create`.
//
// The bundle is a generated file with no authored source upstream, so this port follows the minified code
// call by call. Comments name the minified identifiers (`v` box, `Je` lamp pairs, `bt` bench, ...) so a
// reader can find the source. Everything is in upstream units here; world_core writes metres.
//
// Kept: every static mesh the builder emits through its box batches (`v`, `vr`, `Se`), its height-field
// surfaces (`Ce`, `en`, `rn`), the bank coping and bench instances of the landscape asset, the high-mast
// shafts, the instanced trees, shrubs, grass tufts, flowers and bicycle wheels, and the playground.
// Recorded as data instead of geometry: the spot lights (`Br`, createStreetLighting), the light pools, the
// canal fountain droplets (animated), the viaduct flow strips (animated colour).
// Not ported (design section 0/12): the Reflector water (Godot draws its own water at the canal rect), the
// waterfall "cosmic edge" shader quads, the festival flags (National Day dressing), the firework sprites.
import { lin, mul, hr, overlaps as V, yawQuat, quatMul } from './world_core.mjs';

export function buildGround(env) {
  const { T, city: m, life: Y, rng, em, solids, lights, counts } = env;
  const A = m.water, ye = m.extentX, H = m.extentZ;
  const we = A.x - A.w / 2, fe = A.x + A.w / 2, oa = A.z - A.d / 2, Pr = A.z + A.d / 2;
  const J = new T.Vector3(0, 1, 0);

  // ---- materials (city-materials.js kit and the bundle's own `$({...})` materials), as output material
  // and linear colour. Emissive groups carry their emission colour.
  const K = {
    ground: ['tt_matte', lin('#d8d2c7')], road: ['tt_matte', lin('#485657')], pavement: ['tt_matte', lin('#e3ddd1')],
    stone: ['tt_matte', lin('#ece5d9')], grass: ['tt_matte', lin('#81956d')], metal: ['tt_metal', lin('#b3beb6')],
    trunk: ['tt_matte', lin('#9d7d59')], leaf: ['tt_matte', lin('#6f8567')],
  };
  const E = ['tt_matte', lin('#e5f3f7')];   // ground-road-markings
  const ia = ['tt_matte', lin('#a9bbc5')];  // ground-paving-joints
  const Ha = ['tt_matte', lin('#8a7653')];  // ground-tree-soil
  const R = ['tt_paint', lin('#927455')];   // ground-bench-timber
  const B = ['tt_metal', lin('#476576')];   // ground-street-furniture
  const fa = ['tt_matte', lin('#eee9d7')], et = ['tt_matte', lin('#c8cf8a')]; // flowers
  const ee = ['tt_fixture', lin('#ffd29b')]; // ground-fixed-ice-light (emissive colour)
  const Ae = [ee, ['tt_fixture', lin('#ff7a5c')], ['tt_fixture', lin('#5cd9a4')], ['tt_fixture', lin('#5c9dff')], ['tt_fixture', lin('#d67aff')]];
  const Qe = ['tt_lamp', lin('#ffd6a0')];   // ground-lamp-head (emissive colour)
  const vt = ['tt_matte', lin('#454e48')];  // bank-waterline-stain
  const Pa = ['tt_paint', lin('#4b5320')];  // ground-civic-mailbox
  const h = K;

  const x = { furniture: [], lampAnchors: [], lampPairGaps: [], planting: [], lightStrips: [], parkSeating: [],
    crosswalks: 0, stopLines: 0, curbSegments: 0, benches: 0, lamps: 0, bins: 0, streetTrees: 0, pedestrianBridges: 0,
    shrubs: 0, grassTufts: 0, flowers: 0, lawnLamps: 0, busShelters: 0, busSigns: 0, vendingMachines: 0, mailboxes: 0,
    bikeRacks: 0, bicycles: 0, taxiRanks: 0, refinedBankSegments: [] };
  const Ta = []; // night light anchors (`Br`)
  // Heights the scale checks read (upstream units, the literals used below): bench seat top (`bt` slats),
  // pavement and road tops, kerb top, bus shelter soffit (`mn` roof underside), road bridge deck and rail.
  env.scaleProbes = Object.assign(env.scaleProbes || {}, { bench_seat_top: 1.35, pavement: 0.25, road_top: 0.25, kerb_top: 0.38,
    shelter_soffit: 7.35 - 0.07, bridge_deck: 1.95, bridge_rail_top: 3.82 });

  // `v`: an axis-aligned box given by its top and height.
  let cur = em;
  function v(cx, cz, w, d, top, height, mat) { if (w <= 0 || d <= 0 || height <= 0) return; cur.box(mat[0], cx, top - height / 2, cz, w, height, d, mat[1]); }
  // `vr`: a box centred at y, turned about Y.
  function vr(cx, cy, cz, w, hh, d, yaw, mat) { cur.box(mat[0], cx, cy, cz, w, hh, d, mat[1], yawQuat(yaw)); }
  function Ze(cx, cz, w, d, top, height, kind) { v(cx, cz, w, d, top, height, ee); x.lightStrips.push({ x: cx, z: cz, w, d, top, height, kind }); }
  let Et = 0;
  function ua(cx, cz, w, d, top, height) { v(cx, cz, w, d, top, height, Ae[Et++ % Ae.length]); }
  function Br(host, kind, local, target, color, power, range, angle, span) {
    const u = { kind, x: (host.x || 0) + local[0], y: local[1], z: host.z + local[2],
      tx: (host.x || 0) + target[0], ty: target[1], tz: host.z + target[2], color, power, range, angle, span: span || null };
    Ta.push(u); return u;
  }
  // `pe`: subtract intervals.
  function pe(a, b, cuts) {
    let t = [[a, b]];
    cuts.forEach((n) => {
      const i = [];
      t.forEach((o) => { if (n[1] <= o[0] || n[0] >= o[1]) { i.push(o); return; } if (n[0] > o[0]) i.push([o[0], n[0]]); if (n[1] < o[1]) i.push([n[1], o[1]]); });
      t = i;
    });
    return t;
  }
  const routeRects = { walking: null, vehicle: null };
  function Ye(e, routes, walking) {
    const key = walking ? 'walking' : 'vehicle';
    if (!routeRects[key]) {
      const i = [];
      routes.forEach((o) => o.segments.forEach((s) => {
        const f = Math.abs(s.dx) > Math.abs(s.dz), u = walking ? 1.4 : 4.55, p = walking ? 1.4 : 2.2;
        i.push({ x: s.x + s.dx / 2, z: s.z + s.dz / 2, w: Math.abs(s.dx) + 2 * (f ? u : p), d: Math.abs(s.dz) + 2 * (f ? p : u) });
      }));
      routeRects[key] = i;
    }
    return routeRects[key].every((o) => !V(e, o, 0));
  }
  // `cr`: may a piece of street furniture stand here?
  function cr(e, kind, except) {
    if (kind === 'lamp' && (m.viaducts || []).some((t) => Math.abs(e.z - t.z) < 7.5 + e.d / 2 + 0.5 && Math.abs(e.x) < t.flatX + t.rampX + 0.5)) return false;
    if ((m.reservations || []).some((t) => (except && except.indexOf(t) >= 0 ? false : V(e, t, 0.7)))) return false;
    if (m.playground && V(e, { x: m.playground.x, z: m.playground.z, w: 40, d: 46 }, 0.4)) return false;
    if (!Y || Math.abs(e.x) + e.w / 2 > ye - 1 || Math.abs(e.z) + e.d / 2 > H - 1 || V(e, A, 0.75)) return false;
    if (m.bridges.some((t) => V(e, { x: t.x, z: t.z, w: t.w + 20, d: t.d + 8 }, 0.8))) return false;
    if (m.roads.some((t) => V(e, t, 0.5)) || m.buildings.some((t) => V(e, t, 1.6))) return false;
    if (!Ye(e, Y.walkingRoutes, true) || !Ye(e, Y.vehicleRoutes, false)) return false;
    if (x.furniture.some((t) => V(e, t, 1.5))) return false;
    if (m.parks.some((t) => V(e, { x: t.x, z: t.z, w: 2.6, d: t.d - 10 }, 0.6) || V(e, { x: t.x, z: t.z, w: t.w - 8, d: 2.6 }, 0.6))) return false;
    return !m.trees.some((t) => {
      const n = Math.max(0, Math.abs(t.x - e.x) - e.w / 2), i = Math.max(0, Math.abs(t.z - e.z) - e.d / 2);
      return Math.hypot(n, i) < t.r * (kind === 'lamp' ? 1.3 : 0.65) + 0.4;
    });
  }
  // `Ir`: the road bridge deck height; `Ht`: the viaduct deck height.
  const Ir = (e, rx, az) => 0.25 + 1.7 * hr((e.w / 2 + 10 - Math.abs(rx - e.x)) / 10) * hr((e.d / 2 + 4 - Math.abs(az - e.z)) / 4);
  const Ht = (e, rx, az) => 0.25 + (e.height - 0.25) * hr((e.flatX + e.rampX - Math.abs(rx)) / e.rampX) * hr((e.d / 2 + 2.7 - Math.abs(az - e.z)) / 1.2);
  // `en`: a side wall along x at depth z, from y -0.1 to the profile; `rn`: along z at x.
  function en(z, x0, x1, fn, flip) {
    const pts = [];
    for (let f = 0; f < 12; f++) {
      const u = x0 + (x1 - x0) * f / 12, p = x0 + (x1 - x0) * (f + 1) / 12, w = fn(u, z), M2 = fn(p, z);
      const P = (a, b) => [a, b, z];
      if (flip) pts.push(P(u, -0.1), P(p, M2), P(u, w), P(p, -0.1), P(p, M2), P(u, -0.1));
      else pts.push(P(u, w), P(p, M2), P(u, -0.1), P(u, -0.1), P(p, M2), P(p, -0.1));
    }
    em.triangles(h.stone[0], pts, h.stone[1]);
  }
  function rn(xx, z0, z1, fn) {
    const pts = [];
    for (let o = 0; o < 8; o++) {
      const s = z0 + (z1 - z0) * o / 8, f = z0 + (z1 - z0) * (o + 1) / 8, u = fn(xx, s), p = fn(xx, f);
      pts.push([xx, u, s], [xx, p, f], [xx, -0.1, s], [xx, -0.1, s], [xx, p, f], [xx, -0.1, f]);
    }
    em.triangles(h.stone[0], pts, h.stone[1]);
  }
  // `Ce`: a height-field strip of nx by nz quads.
  function Ce(mat, x0, x1, z0, z1, nx, nz, fn, lift) {
    const pts = [], P = (a, b) => [a, fn(a, b) + (lift || 0), b];
    for (let w = 0; w < nz; w++) for (let k = 0; k < nx; k++) {
      const l = x0 + (x1 - x0) * k / nx, d = x0 + (x1 - x0) * (k + 1) / nx, g = z0 + (z1 - z0) * w / nz, y = z0 + (z1 - z0) * (w + 1) / nz;
      pts.push(P(l, g), P(l, y), P(d, g), P(d, g), P(l, y), P(d, y));
    }
    em.triangles(mat[0], pts, mat[1]);
  }
  // A rod from a to b with a square section (`Se`).
  const tmpV = new T.Vector3(), tmpQ = new T.Quaternion();
  function Se(a, b, r, mat) {
    tmpV.set(b[0] - a[0], b[1] - a[1], b[2] - a[2]); const n = tmpV.length();
    tmpQ.setFromUnitVectors(J, tmpV.normalize());
    em.box(mat[0], (a[0] + b[0]) / 2, (a[1] + b[1]) / 2, (a[2] + b[2]) / 2, r, n, r, mat[1], [tmpQ.x, tmpQ.y, tmpQ.z, tmpQ.w]);
  }
  // A solid item: everything emitted inside fn() is reduced to footprints for solids.json.
  function item(kind, id, base, fn) { solids.begin(kind, id, base); try { return fn(); } finally { solids.end(); } }
  let itemSeq = 0;
  const nid = (k) => k + '-' + (itemSeq++);

  // ---- high masts (`Ja` + `Pe`), planned first: their reservations shape every later check.
  const Pe = (c) => ({ x: c.vertical.x + c.offsetX, z: c.horizontal.z + c.offsetZ, y: 0.25 });
  x.highMasts = planHighMasts(m, Y);
  x.highMasts.forEach((e) => { const r = Pe(e); x.furniture.push({ x: r.x, z: r.z, w: 1.44, d: 1.44, kind: 'high-mast', top: r.y + 18.5 }); });

  // ---- ground slabs (`la`), carved around the tunnels.
  const Gr = m.tunnels || [], it = Gr.reduce((e, r) => Math.max(e, r.portalX), 0);
  const ft = Gr.slice().sort((e, r) => e.z - r.z).map((e) => ({ back: e.z - e.halfD - 0.35, front: e.z + e.halfD + 0.35 }));
  function la(x0, x1, top, height) {
    const n = (o, s, f, u) => { if (s > o && u > f) v((o + s) / 2, (f + u) / 2, s - o, u - f, top, height, h.ground); };
    let i = -H;
    ft.forEach((o) => { n(x0, x1, i, o.back); n(x0, Math.min(x1, -it), o.back, o.front); n(Math.max(x0, it), x1, o.back, o.front); i = o.front; });
    n(x0, x1, i, H);
  }
  la(-ye, ye, -2, 3.2); la(-ye, we, 0, 2); la(fe, ye, 0, 2);
  if (oa > -H) v(A.x, (-H + oa) / 2, A.w, oa + H, 0, 2, h.ground);
  if (Pr < H) v(A.x, (Pr + H) / 2, A.w, H - Pr, 0, 2, h.ground);
  const Be = Math.min(Pr, H);
  const L = env.ctx.CityLandscapeAsset;
  const coping = L.modules.Coping, benchModule = L.modules.Bench;
  const Wr = !!(coping && coping.position.length);
  const ut = m.bridges.map((e) => [e.z - e.d / 2 - 4, e.z + e.d / 2 + 4]).concat(ft.map((e) => [e.back - 3.3, e.front + 3.3]));
  const lt = ut.concat(m.roads.filter((e) => e.axis === 'x').map((e) => [e.z - e.d / 2 - 3.6, e.z + e.d / 2 + 3.6]));
  // River-walk pavements, bank copings (the canal walls), bank light strips and their blue spots.
  [we - 7, fe + 7].forEach((e) => pe(-Be, Be, lt).forEach((r) => v(e, (r[0] + r[1]) / 2, 11.8, r[1] - r[0], 0.25, 0.25, h.pavement)));
  [we - 0.5, fe + 0.5].forEach((e) => {
    pe(-Be, Be, ut).forEach((r) => {
      for (let a = Math.ceil((r[1] - r[0]) / 4), t = (r[1] - r[0]) / a, n = 0; n < a; n++) x.refinedBankSegments.push({ x: e, z: r[0] + (n + 0.5) * t, d: t });
    });
    pe(-Be, Be, lt).forEach((r) => {
      if (r[1] - r[0] > 0.4) {
        Ze(e, (r[0] + r[1]) / 2, 0.16, r[1] - r[0] - 0.4, 0.355, 0.035, 'bank');
        const a = e < A.x ? -1 : 1, t = (r[0] + r[1]) / 2 - A.z;
        Br(A, 'river-blue', [a * (A.w / 2 - 0.12), -0.12, t], [0, -1.6, t], '#4276ad', 24, 38, 1.4, [0, 0, (r[1] - r[0] - 0.6) / 2]);
      }
    });
  });
  // `blender-bank-coping`: the landscape Coping module instanced along both banks (scale z = d / 4).
  const copingGeo = moduleGeometry(T, coping);
  const benchGeo = moduleGeometry(T, benchModule);
  const tm = new T.Matrix4(), tq = new T.Quaternion(), tp = new T.Vector3(), ts = new T.Vector3();
  x.refinedBankSegments.forEach((e) => {
    tp.set(e.x, 0, e.z); ts.set(1, 1, e.d / 4); tq.identity(); tm.compose(tp, tq, ts);
    item('canal-wall', nid('canal-wall'), 0.25, () => em.geometry('tt_matte', copingGeo, tm, null));
  });
  counts.canal_wall_segments = x.refinedBankSegments.length;
  // The bank edge is where walking stops: each coping segment is a solid strip (its top is only 0.16 m above
  // the promenade, so the band rule would not catch it; the water is 0.4 m below).
  x.refinedBankSegments.forEach((e, i) => solids.items.push({ kind: 'canal-wall', id: 'canal-wall-' + i, rect: { x: e.x, z: e.z, w: 1, d: e.d }, bottom: -0.55, top: 0.32 }));
  // Waterline stain on the wall faces.
  const tn = (m.tunnels || []).map((e) => [e.z - e.halfD - 0.9, e.z + e.halfD + 0.9]);
  [we, fe].forEach((e) => pe(-Be, Be, tn).forEach((r) => v(e + (e < A.x ? 0.02 : -0.02), (r[0] + r[1]) / 2, 0.1, r[1] - r[0], -0.06, 0.52, vt)));
  // The canal fountain at the water centre: a ring of stones, the pedestal, the nozzle cap.
  const O = { x: A.x, z: A.z };
  cur = env.fountainEmitter;
  item('canal-fountain', 'canal-fountain', -0.55, () => {
    for (let ca = 0; ca < 10; ca++) { const ha = ca * Math.PI / 5; vr(O.x + 4.9 * Math.cos(ha), -0.79, O.z + 4.9 * Math.sin(ha), 3.34, 1.3, 1.15, Math.PI / 2 - ha, h.stone); }
    v(O.x, O.z, 2.3, 2.3, -0.12, 1.5, h.stone); v(O.x, O.z, 1.15, 1.15, 1.05, 2.2, h.stone); v(O.x, O.z, 2, 2, 1.32, 0.3, h.stone); v(O.x, O.z, 0.55, 0.55, 1.62, 0.55, h.metal);
    for (let va = 0; va < 6; va++) { const da = va * Math.PI / 3; vr(O.x + 1.35 * Math.cos(da), 1.32, O.z + 1.35 * Math.sin(da), 0.38, 0.38, 0.38, Math.PI / 2 - da, h.metal); }
  });
  for (let ma = 0; ma < 8; ma++) { const xa = ma * Math.PI / 4; vr(O.x + 1.75 * Math.cos(xa), -0.555, O.z + 1.75 * Math.sin(xa), 1.5, 0.05, 0.5, Math.PI / 2 - xa, E); }
  cur = em;
  // The droplets (`wa`/`Ma`): 46 in the central jet, 9 on each of six ring nozzles, 16 in the spray, on
  // their own seeded generator; recorded as data (world.json canal_fountain) for Godot to animate.
  const Vr = 9.5, ge = rng((m.seed ^ 989307334) >>> 0), Me = [];
  const wa = (px, py, pz, vx, vy, vz, sc, phase) => Me.push({ x: px, y: py, z: pz, vx, vy, vz, s: sc, phase, period: (vy + Math.sqrt(vy * vy + 2 * Vr * (py + 0.55))) / Vr });
  const nn = Math.sqrt(2 * Vr * 6.65);
  for (let pa = 0; pa < 46; pa++) wa(O.x, 1.55, O.z, 0, nn, 0, 0.32 + ge() * 0.1, pa / 46);
  const on = 5 * Math.cos(24 * Math.PI / 180), dt = 5 * Math.sin(24 * Math.PI / 180);
  for (let Nr = 0; Nr < 6; Nr++) { const Dr = Nr * Math.PI / 3; for (let ga = 0; ga < 9; ga++) wa(O.x + 1.35 * Math.cos(Dr), 1.4, O.z + 1.35 * Math.sin(Dr), dt * Math.cos(Dr), on, dt * Math.sin(Dr), 0.22 + ge() * 0.07, (ga + Nr * 0.41) / 9 % 1); }
  for (let mt = 0; mt < 16; mt++) { const xt = ge() * Math.PI * 2, wt = 0.4 + ge() * 0.7; wa(O.x + (ge() - 0.5) * 0.8, 7.7 + ge() * 0.6, O.z + (ge() - 0.5) * 0.8, Math.cos(xt) * wt, 0.15 + ge() * 0.4, Math.sin(xt) * wt, 0.15 + ge() * 0.07, ge()); }
  for (let _r = 0; _r < 6; _r++) { const Mt = _r * Math.PI / 3; Br(A, 'fountain-colour', [4.25 * Math.cos(Mt), -0.22, 4.25 * Math.sin(Mt)], [0, 4.2, 0], '#ffffff', 42, 15, 1).phase = _r / 6; }
  env.canalFountain = { x: O.x, z: O.z, gravity: Vr, droplets: Me, basin: { inner: 4.325, outer: 4.9, surface_y: -0.55 } };

  // ---- walk rects (`Or`) and the roads: surfaces, kerbs, joints, junction corners, centre dashes.
  const Or = [];
  if (m.waterfront || Array.isArray(m.blockWalks)) Y.walkingRoutes.forEach((e) => e.segments.forEach((r) => {
    const a = { x: r.x + r.dx / 2, z: r.z + r.dz / 2, w: Math.abs(r.dx) + 2.8, d: Math.abs(r.dz) + 2.8 };
    if (!Or.some((t) => t.x === a.x && t.z === a.z && t.w === a.w && t.d === a.d)) Or.push(a);
  }));
  const sa = (m.places || []).filter((e) => e.kind === 'station').map((e) => {
    const r = e.gateSide === 1 || e.gateSide === -1 ? e.gateSide : e.x < 0 ? 1 : -1, a = Number.isFinite(e.roadX) ? e.roadX : e.x < 0 ? -96 : 96;
    return { site: e, gateSide: r, road: m.roads.find((t) => t.axis === 'z' && Math.abs(t.x - a) < 0.01), gateX: e.x + r * e.w / 2, gateWidth: 8 * e.d / 58, gateZ: [-13, 13].map((t) => e.z + r * t * e.d / 58) };
  });
  m.roads.forEach((e) => {
    const r = e.axis === 'x', a = r ? e.x - e.w / 2 : e.z - e.d / 2, t = r ? e.x + e.w / 2 : e.z + e.d / 2;
    const n = m.roads.filter((f) => f.axis !== e.axis), i = [], o = [], s = [];
    n.forEach((f) => {
      if (!(Math.abs(f.x - e.x) >= (f.w + e.w) / 2 || Math.abs(f.z - e.z) >= (f.d + e.d) / 2)) {
        const u = r ? f.x : f.z, p = (r ? f.w : f.d) / 2;
        if (!r) i.push([u - p, u + p]);
        o.push([u - p - 3.6, u + p + 3.6]); s.push([u - p - 5.1, u + p + 5.1]);
      }
    });
    if (r) m.bridges.forEach((f) => { if (Math.abs(e.z - f.z) < 0.1) { const c = [f.x - f.w / 2 - 10, f.x + f.w / 2 + 10]; i.push(c); o.push(c.slice()); s.push(c.slice()); } });
    if (r) Gr.forEach((f) => {
      if (Math.abs(e.z - f.z) > 0.1) return;
      [[Math.max(a, fe), Math.min(t, f.portalX)], [Math.max(a, -f.portalX), Math.min(t, we)]].forEach((u) => { if (u[1] > u[0]) { i.push(u); s.push([u[0] - 5.1, u[1] + 5.1]); } });
    });
    if (r && e.walkOnlyTo) [[fe, e.walkOnlyTo], [-e.walkOnlyTo, we]].forEach((f) => { if (f[1] > f[0]) { i.push(f); s.push([f[0] - 2, f[1]]); } });
    pe(a, t, i).forEach((f) => { const u = (f[0] + f[1]) / 2, p = f[1] - f[0]; v(r ? u : e.x, r ? e.z : u, r ? p : e.w, r ? e.d : p, 0.25, 0.25, h.road); });
    if (r && e.walkOnlyTo) [-1, 1].forEach((f) => v(f * (fe + e.walkOnlyTo) / 2, e.z, e.walkOnlyTo - fe, e.d + 0.5, 0.25, 0.25, h.pavement));
    [-1, 1].forEach((f) => {
      const u = o.slice(), p = (r ? e.d : e.w) / 2, w = f * (p + 0.2), M2 = f * (p + 1.9), l = [];
      Or.forEach((d) => {
        const g = Math.abs(r ? e.z + w - d.z : e.x + w - d.x);
        if (g < (r ? d.d : d.w) / 2 + 0.175) { const y = r ? d.x : d.z, W = r ? d.w : d.d; l.push([y - W / 2, y + W / 2]); }
      });
      sa.forEach((d) => { if (!r && e === d.road && f === -d.gateSide) d.gateZ.forEach((g) => u.push([g - d.gateWidth / 2, g + d.gateWidth / 2])); });
      pe(a, t, u).forEach((d) => {
        const g = (d[0] + d[1]) / 2, y = d[1] - d[0];
        v(r ? g : e.x + M2, r ? e.z + M2 : g, r ? y : 3.2, r ? 3.2 : y, 0.25, 0.25, h.pavement);
        // Kerb stones (`curbSegments`): 3.76-unit stones, cut at walk crossings.
        for (let W = d[0]; W < d[1] - 0.06; W += 3.8) {
          const S2 = Math.min(3.76, d[1] - W - 0.025);
          pe(W, W + S2, l).forEach((F) => { const z = F[1] - F[0], N = (F[0] + F[1]) / 2; v(r ? N : e.x + w, r ? e.z + w : N, r ? z : 0.35, r ? 0.35 : z, 0.38, 0.38, h.stone); x.curbSegments++; });
        }
        const U = [];
        l.map((F) => [Math.max(d[0], F[0]), Math.min(d[1], F[1])]).filter((F) => F[1] > F[0]).sort((F, z) => F[0] - z[0]).forEach((F) => {
          const z = U[U.length - 1]; if (z && F[0] <= z[1]) z[1] = Math.max(z[1], F[1]); else U.push(F);
        });
        U.forEach((F) => { const z = (F[0] + F[1]) / 2, N = F[1] - F[0]; v(r ? z : e.x + w, r ? e.z + w : z, r ? N : 0.6, r ? 0.6 : N, 0.25, 0.25, h.pavement); });
        v(r ? g : e.x + M2, r ? e.z + M2 : g, r ? y : 0.045, r ? 0.045 : y, 0.258, 0.014, ia);
        for (let Q = Math.ceil(d[0] / 9) * 9; Q < d[1] - 0.1; Q += 9) v(r ? Q : e.x + M2, r ? e.z + M2 : Q, r ? 0.06 : 3.1, r ? 3.1 : 0.06, 0.258, 0.014, ia);
      });
      if (!r) n.forEach((d) => { if (!(Math.abs(d.x - e.x) > d.w / 2)) [-1, 1].forEach((g) => v(e.x + M2, d.z + g * (d.d / 2 + 1.8), 3.8, 3.6, 0.25, 0.25, h.pavement)); });
    });
    pe(a + 3, t - 3, s).forEach((f) => { for (let u = Math.ceil(f[0] / 9) * 9; u + 3.2 < f[1]; u += 9) v(r ? u + 1.6 : e.x, r ? e.z : u + 1.6, r ? 3.2 : 0.22, r ? 0.22 : 3.2, 0.264, 0.014, E); });
  });
  counts.kerb_stones = x.curbSegments;
  if (m.waterfront) [-1, 1].forEach((e) => [-1, 1].forEach((r) => v(A.x + e * 23, r * 9.55, 2.8, 0.12, 0.25, 0.25, h.pavement)));
  sa.forEach((e) => {
    if (!e.road) return;
    const r = e.road.x - e.gateSide * e.road.w / 2, a = e.gateX - e.gateSide * 0.1, t = r + e.gateSide * 0.5;
    e.gateZ.forEach((n) => v((a + t) / 2, n, Math.abs(t - a), e.gateWidth, 0.25, 0.25, h.road));
  });
  // Zebra crossings and stop lines at every junction away from the bridges.
  m.roads.filter((e) => e.axis === 'x').forEach((e) => m.roads.filter((r) => r.axis === 'z').forEach((r) => {
    const a = r.x, t = e.z;
    if (a <= e.x - e.w / 2 || a >= e.x + e.w / 2 || t <= r.z - r.d / 2 || t >= r.z + r.d / 2) return;
    if (m.bridges.some((n) => V({ x: a, z: t, w: 30, d: 32 }, { x: n.x, z: n.z, w: n.w + 20, d: n.d + 8 }, 0))) return;
    [-1, 1].forEach((n) => {
      const i = a + n * (r.w / 2 + 3), o = t + n * (e.d / 2 + 3);
      for (let s = -4; s <= 4; s++) v(i, t + s * 1.22, 3.4, 0.64, 0.267, 0.017, E);
      if (!e.walkOnlyTo) for (let f = -3; f <= 3; f++) v(a + f * 1.3, o, 0.68, 3.4, 0.267, 0.017, E);
      if (!e.walkOnlyTo) v(a + n * (r.w / 2 + 6), t - n * e.d / 4, 0.32, e.d / 2 - 0.8, 0.269, 0.019, E);
      v(a + n * r.w / 4, t + n * (e.d / 2 + 6), r.w / 2 - 0.8, 0.32, 0.269, 0.019, E);
      x.crosswalks += e.walkOnlyTo ? 1 : 2; x.stopLines += 1;
    });
  }));

  // ---- parks: lawn, cross paths, lawn lamps; the sports park is the playground.
  const za = [];
  m.parks.forEach((e) => {
    v(e.x, e.z, e.w, e.d, 0.12, 0.12, h.grass);
    const r = e.w / 2 - 4, a = e.d / 2 - 5;
    [-1, 1].forEach((i) => { v(e.x, e.z + i * a, r * 2 + 2.6, 2.6, 0.25, 0.14, h.pavement); v(e.x + i * r, e.z, 2.6, a * 2 - 2.6, 0.25, 0.14, h.pavement); });
    if (e.use === 'sports' && m.playground) { playground(env, m.playground, h); return; }
    const t = [], n = [];
    m.trees.forEach((i) => { const o = Math.max(0.9, i.r * 0.28); if (Math.abs(i.z - e.z) < o + 1.3) t.push([i.x - o, i.x + o]); if (Math.abs(i.x - e.x) < o + 1.3) n.push([i.z - o, i.z + o]); });
    pe(e.x - r, e.x + r, t).forEach((i) => v((i[0] + i[1]) / 2, e.z, i[1] - i[0], 2.6, 0.25, 0.14, h.pavement));
    pe(e.z - a, e.z + a, n).forEach((i) => v(e.x, (i[0] + i[1]) / 2, 2.6, i[1] - i[0], 0.252, 0.142, h.pavement));
    [[1, 0], [-1, 0], [0, 1], [0, -1]].forEach((i) => {
      for (let o = 1; o <= 2; o++) {
        const s = e.x + i[0] * o * r / 2 + i[1] * 1.9, f = e.z + i[1] * o * a / 2 + i[0] * 1.9;
        if (m.trees.some((u) => Math.hypot(u.x - s, u.z - f) < Math.max(1.4, u.r * 0.55))) continue;
        item('lawn-lamp', nid('lawn-lamp'), 0.12, () => { v(s, f, 0.3, 0.3, 0.3, 0.26, B); v(s, f, 0.13, 0.13, 1.52, 1.24, B); v(s, f, 0.5, 0.5, 1.72, 0.18, Qe); });
        za.push({ x: s, z: f, y: 0.31, w: 6.5, d: 6.5 }); x.lawnLamps++;
        lights.lamp({ kind: 'lawn', x: s, y: 1.63, z: f, ground: 0.12, color: '#ffd6a0', range: 6.5, energy: 0, omni: false });
      }
    });
  });
  // Block walks: the pavement strips that carry the walking routes through two blocks.
  if (Y) {
    const pave = (rx, az, tw, nd) => {
      let i = [{ x: rx, z: az, w: tw, d: nd }];
      [A].concat(m.bridges.map((s) => ({ x: s.x, z: s.z, w: s.w + 20, d: s.d + 8 }))).forEach((s) => {
        const f = [];
        i.forEach((u) => {
          if (!V(u, s, 0)) { f.push(u); return; }
          const p = u.x - u.w / 2, w = u.x + u.w / 2, M2 = u.z - u.d / 2, l = u.z + u.d / 2;
          const d = Math.max(p, s.x - s.w / 2), g = Math.min(w, s.x + s.w / 2), y = Math.max(M2, s.z - s.d / 2), W = Math.min(l, s.z + s.d / 2);
          [[p, d, M2, l], [g, w, M2, l], [d, g, M2, y], [d, g, W, l]].forEach((S2) => { if (S2[1] > S2[0] && S2[3] > S2[2]) f.push({ x: (S2[0] + S2[1]) / 2, z: (S2[2] + S2[3]) / 2, w: S2[1] - S2[0], d: S2[3] - S2[2] }); });
        });
        i = f;
      });
      i.forEach((s) => v(s.x, s.z, s.w, s.d, 0.25, 0.25, h.pavement));
    };
    const ln = Array.isArray(m.blockWalks) ? m.blockWalks : [{ x: -60, z: 40 }, { x: 132, z: 120 }];
    ln.forEach((r) => {
      const a = r.x + 30, t = r.z - 32.5, n = r.z + 32.5;
      const ok = Y.walkingRoutes.some((o) => o.segments.some((s) => Math.abs(s.x - a) < 0.01 && Math.abs(s.dx) < 0.01 && Math.abs(Math.min(s.z, s.z + s.dz) - t) < 0.01 && Math.abs(Math.max(s.z, s.z + s.dz) - n) < 0.01));
      if (!ok) return;
      if (Array.isArray(m.blockWalks) || (m.waterfront && r.z > 100)) { [t, n].forEach((o) => pave(r.x, o, 62.8, 2.8)); [r.x - 30, a].forEach((o) => pave(o, r.z, 2.8, 62.2)); return; }
      v(a, r.z, 2.5, 65, 0.25, 0.25, h.pavement); if (r.z > 100) v(r.x, n, 60 - 2.5, 2.5, 0.25, 0.25, h.pavement);
    });
  }

  // ---- bridges: footbridges (`cn`) and road bridges with their ramps, rails and rail light strips.
  const walk = env.walkable;
  function footbridge(e) {
    const r = e.x, a = e.z, t = e.w / 2, n = e.d / 2, i = (o, s) => Ir(e, o, s);
    v(r, a, e.w, e.d, 1.7, 0.5, h.stone); v(r, a, e.w, e.d, 1.95, 0.25, h.pavement);
    [-1, 1].forEach((o) => {
      v(r + o * 11.5, a, 1.5, e.d - 1.4, 1.2, 3.2, h.stone);
      const s = o < 0 ? r - t - 10 : fe, f = o < 0 ? we : r + t + 10;
      Ce(h.pavement, Math.min(s, f), Math.max(s, f), a - n - 4, a + n + 4, 17, 26, i);
    });
    [-1, 1].forEach((o) => {
      const s = a + o * (n - 0.24);
      item('bridge-rail', nid('footbridge-rail'), 1.95, () => {
        v(r, s, e.w - 2, 0.17, 3.3, 0.17, h.metal); v(r, s, e.w - 2, 0.1, 2.6, 0.1, h.metal);
        for (let f = r - t + 1.4; f <= r + t - 1.4; f += 4.5) v(f, s, 0.17, 0.17, 3.28, 1.33, h.metal);
      });
    });
    x.pedestrianBridges++;
    walk.push({ kind: 'footbridge', x: e.x, z: e.z, w: e.w + 20, d: e.d + 8, profile: 'bridge', bridge: { x: e.x, z: e.z, w: e.w, d: e.d } });
  }
  m.bridges.forEach((e) => {
    const r = e.x, a = e.z, t = e.w / 2, n = e.d / 2;
    if (e.pedestrian) { footbridge(e); return; }
    v(r, a, e.w, e.d, 1.7, 0.5, h.stone); v(r, a, e.w, 10.2, 1.95, 0.25, h.road);
    [-1, 1].forEach((s) => { v(r, a + s * 6.3, e.w, 2.4, 1.95, 0.25, h.pavement); v(r + s * 11.5, a, 1.5, e.d - 1.4, 1.2, 3.2, h.stone); });
    const i = (s, f) => Ir(e, s, f);
    [-1, 1].forEach((s) => {
      const f = s < 0 ? r - t - 10 : r + t, u = f + 10;
      Ce(h.road, f, u, a - 5.1, a + 5.1, 12, 1, i);
      [-1, 1].forEach((M2) => { const l = M2 < 0 ? a - n : a + 5.1; Ce(h.pavement, f, u, l, l + 2.4, 12, 1, i); });
      const p = s < 0 ? r - t - 10 : fe, w = s < 0 ? we : r + t + 10;
      [-1, 1].forEach((M2) => { const l = M2 < 0 ? a - n - 4 : a + n; Ce(h.pavement, p, w, l, l + 4, 18, 8, i); const d = s < 0 ? we : fe; rn(d, s < 0 ? l : l + 4, s < 0 ? l + 4 : l, i); });
    });
    [-1, 1].forEach((s) => {
      const f = a + s * (n - 0.24);
      item('bridge-rail', nid('bridge-rail'), 1.95, () => {
        v(r, f, A.w + 6, 0.17, 3.82, 0.17, h.metal); v(r, f, A.w + 6, 0.1, 2.76, 0.1, h.metal);
        for (let u = r - A.w / 2 - 3; u <= r + A.w / 2 + 3; u += 4.5) {
          v(u, f, 0.17, 0.17, 3.8, 1.85, h.metal);
          if (u + 4.5 <= r + A.w / 2 + 3) Ze(u + 2.25, f, 3.8, 0.1, 3.855, 0.035, 'bridge');
        }
      });
    });
    for (let o = r - t - 8; o < r + t + 8; o += 8) Ce(E, o, o + 2.8, a - 0.11, a + 0.11, 4, 1, i, 0.014);
    walk.push({ kind: 'road-bridge', x: e.x, z: e.z, w: e.w + 20, d: e.d + 8, profile: 'bridge', bridge: { x: e.x, z: e.z, w: e.w, d: e.d } });
  });

  // ---- viaducts: deck, ramps, piers, rails with light strips; their lamps are placed with the others.
  const $e = [];
  (m.viaducts || []).forEach((e) => {
    const r = e.z, a = e.height, t = e.flatX, n = e.rampX, i = t + n, o = (l, d) => Ht(e, l, d);
    v(0, r, t * 2, 12, a - 0.25, 0.55, h.stone); v(0, r, t * 2, 10.2, a, 0.25, h.road);
    [-1, 1].forEach((l) => v(0, r + l * 6.3, t * 2, 2.4, a, 0.25, h.pavement));
    [-1, 1].forEach((l) => {
      const d = l < 0 ? -i : t;
      Ce(h.road, d, d + n, r - 5.1, r + 5.1, 15, 1, o);
      [-1, 1].forEach((g) => { const y = g < 0 ? r - 7.5 : r + 5.1; Ce(h.pavement, d, d + n, y, y + 2.4, 15, 1, o); en(y + (g < 0 ? 0 : 2.4), d, d + n, o, g > 0); });
    });
    [16, 48, 80, 112, 136, 160].forEach((l) => [-1, 1].forEach((d) => {
      const g = d * l, y = l > t ? o(g, r) - 0.3 : a - 0.8;
      item('viaduct-pier', nid('viaduct-pier'), 0, () => v(g, r, 2.6, 7.5, y, y + 1.2, h.stone));
    }));
    [-1, 1].forEach((l) => {
      const d = r + l * 5.86;
      v(0, d, t * 2 - 4, 0.17, a + 1.87, 0.17, h.metal); v(0, d, t * 2 - 4, 0.1, a + 1.31, 0.1, h.metal);
      for (let g = -t + 2.2; g <= t - 2.2; g += 4.5) { v(g, d, 0.17, 0.17, a + 1.85, 1.85, h.metal); if (g + 4.5 <= t - 2.2) Ze(g + 2.25, d, 3.8, 0.1, a + 1.905, 0.035, 'bridge'); }
    });
    for (let s = r < 0 ? 1 : -1, f = r + s * 7.69, u = -t + 6; u <= t - 6 + 1e-9; u += 12) $e.push({ x: u + 6, z: f, top: a });
    const span = t - 12 + Math.floor(n / 24) * 24;
    for (let w = -span; w <= span + 1e-9; w += 24) [-1, 1].forEach((l) => ba(w, r + l * 6.35, -l, o(w, r) - 0.31, true, false, true));
    for (let M2 = -i + 1; M2 < i - 3.8; M2 += 8) Ce(E, M2, M2 + 2.8, r - 0.11, r + 0.11, 4, 1, o, 0.014);
    walk.push({ kind: 'viaduct', x: 0, z: e.z, w: 2 * i, d: e.d, profile: 'viaduct', viaduct: { z: e.z, d: e.d, height: e.height, flatX: e.flatX, rampX: e.rampX } });
  });
  env.viaductFlowStrips = $e.map((e) => ({ x: e.x, y: e.top - 0.25, z: e.z, w: 11.6, h: 0.5, d: 0.38 }));

  // ---- tunnels: the dropped road, walls, the portal cover, light strips and wall spots.
  Gr.forEach((e) => {
    const r = e.z, a = e.halfD, t = e.portalX - e.coverX, n = 0.25 - e.drop;
    const i = (s) => 0.25 - e.drop * hr(Math.min(1, Math.max(0, (e.portalX - Math.abs(s)) / t)));
    [-1, 1].forEach((s) => {
      const f = s < 0 ? -e.portalX : e.coverX, u = s < 0 ? -e.coverX : e.portalX;
      Ce(h.road, f, u, r - a, r + a, 14, 1, (g) => i(g));
      for (let p = 0; p < 8; p++) {
        const w = f + (u - f) * p / 8, M2 = f + (u - f) * (p + 1) / 8, l = Math.max(0.6, 0.6 - Math.min(i(w), i(M2)));
        [-1, 1].forEach((g) => v((w + M2) / 2, r + g * (a + 0.175), M2 - w, 0.35, 0, l, h.stone));
      }
      const d = s * (e.coverX - 0.6);
      v(d, r, 1.2, a * 2 + 0.7, 1.9, 2.1, h.stone); Ze(s * (e.coverX - 1.4), r, 0.25, a * 2, -0.02, 0.1, 'tunnel');
    });
    v(0, r, e.coverX * 2, a * 2 + 1.8, n, 0.5, h.road);
    [-1, 1].forEach((s) => {
      [-1, 1].forEach((f) => v(f * (17 + e.coverX) / 2, r + s * (a + 0.175), e.coverX - 17, 0.35, 0, -n, h.stone));
      v(0, r + s * (a + 0.175), 34, 0.35, -0.8, -0.8 - n, h.stone);
    });
    [-1, 1].forEach((s) => v(s * (17 + e.coverX) / 2, r, e.coverX - 17, a * 2 + 0.3, 0.25, 0.45, h.pavement));
    v(0, r, 34, a * 2 + 1.8, -0.8, 0.5, h.stone);
    for (let o = -30; o <= 30; o += 8) { if (Math.abs(o) < 17) continue; [-1, 1].forEach((s) => Ze(o, r + s * 3, 7, 0.5, -0.12, 0.06, 'tunnel')); }
    [-1, 1].forEach((s) => [-1, 1].forEach((f) => [0.32, 0.66, 0.92, 1.22].forEach((u) => {
      const p = s * (e.portalX - t * u), w = Math.min(-0.3, i(p) + 2.45);
      Br(e, 'tunnel-wall', [p, w, f * (a - 0.24)], [p, i(p) + 0.4, 0], '#ffe6bc', 28, 15, 1.25, [1.2, 0, 0]);
    })));
    walk.push({ kind: 'tunnel', x: 0, z: e.z, w: 2 * e.portalX, d: 2 * e.halfD, profile: 'tunnel', tunnel: { z: e.z, halfD: e.halfD, portalX: e.portalX, coverX: e.coverX, drop: e.drop } });
  });

  // ---- benches (`bt`): timber slats on metal supports, on a pavement pad.
  function bt(e, r, a, parkId) {
    const n = { x: e, z: r, w: a ? 6.4 : 3.2, d: a ? 3.2 : 6.4, kind: 'bench', alongX: a, top: 2.42 };
    if (!cr(n, 'bench')) return false;
    if (parkId) n.parkId = parkId;
    const i = (s, f, u, p, w, M2, l) => v(e + (a ? s : -f), r + (a ? f : s), a ? u : p, a ? p : u, w, M2, l);
    v(e, r, n.w, n.d, 0.26, 0.08, h.pavement);
    item('bench', nid('bench'), 0.25, () => {
      for (let o = 0; o < 3; o++) { i(0, -0.48 + o * 0.45, 5.3, 0.38, 1.35, 0.18, R); i(0, 0.69, 5.3, 0.14, 1.78 + o * 0.29, 0.22, R); }
      [-1, 1].forEach((s) => { i(s * 1.95, 0, 0.2, 1.38, 1.17, 0.91, B); i(s * 2.48, -0.03, 0.14, 1.36, 1.84, 0.15, B); i(s * 2.48, 0.65, 0.14, 0.14, 2.42, 1.25, B); });
    });
    x.benches++; x.furniture.push(n); return true;
  }
  // ---- street lamps (`Je` pairs, `ba` single lamps): pole, base, arm, head and the emissive lens.
  function Je(axis, center, slot, offsets, filter, compact) {
    compact = !!compact;
    if (axis === 'z' && x.highMasts.some((l) => Math.abs(l.vertical.x - center) < 0.01 && Math.abs(l.horizontal.z - slot) < 16)) return true;
    const o = [0]; for (let s = 2; s <= 18; s += 2) o.push(s, -s);
    for (let f = 0; f < o.length; f++) for (let u = 0; u < offsets.length; u++) {
      const p = slot + o[f], w = offsets[u];
      if (axis === 'z' && x.highMasts.some((l) => Math.abs(l.vertical.x - center) < 0.01 && Math.abs(l.horizontal.z - p) < 16)) continue;
      const M2 = [-1, 1].map((l) => {
        const d = axis === 'x' ? p : center + l * w, g = axis === 'x' ? center + l * w : p, y = -l;
        return { x: d, z: g, inward: y, rect: compact ? { x: d, z: g, w: 0.82, d: 0.82, kind: 'lamp' } : axis === 'x' ? { x: d, z: g + y * 0.5, w: 0.82, d: 2.5, kind: 'lamp' } : { x: d + y * 0.5, z: g, w: 2.5, d: 0.82, kind: 'lamp' } };
      });
      const spaced = M2.every((l) => (!filter || filter(l)) &&
        (!compact || !x.highMasts.some((d) => Math.abs(l.x + (axis === 'z' ? l.inward * 1.08 : 0) - d.vertical.x) < 12 && Math.abs(l.z + (axis === 'x' ? l.inward * 1.08 : 0) - d.horizontal.z) < 16)) &&
        !x.lampAnchors.some((d) => {
          if ((d.axis === 'z') !== (axis === 'x') || d.y > 0.4) return false;
          const g = d.axis === 'z' ? d.x : d.x - d.inward * 1.08, y = d.axis === 'z' ? d.z - d.inward * 1.08 : d.z;
          return Math.abs(axis === 'x' ? y - l.z : g - l.x) < (compact ? 3 : 1.1) && Math.abs(axis === 'x' ? g - l.x : y - l.z) < (compact ? 18 : 12);
        }));
      if (spaced && M2.every((l) => (compact ? Ge(l.rect, 'lamp') : cr(l.rect, 'lamp')))) {
        M2.forEach((l) => ba(l.x, l.z, l.inward, 0, false, compact, axis === 'x'));
        return true;
      }
    }
    x.lampPairGaps.push({ axis, center, slot }); return false;
  }
  function ba(e, r, a, t, force, compact, alongX) {
    const o = alongX !== false;
    const s = compact ? { x: e, z: r, w: 0.82, d: 0.82, kind: 'lamp' } : o ? { x: e, z: r + a * 0.5, w: 0.82, d: 2.5, kind: 'lamp' } : { x: e + a * 0.5, z: r, w: 2.5, d: 0.82, kind: 'lamp' };
    if (!force && !cr(s, 'lamp')) return false;
    const base = 0.25 + t;
    item('lamp', nid('lamp'), base, () => {
      [[0, 0.62, 0.62, 0.48, 0.22], [0, 0.2, 0.2, 8.35, 8.09], [a * 0.52, 1.24, 0.2, 8.43, 0.2], [a * 1.08, 0.88, 0.5, 8.47, 0.23], [a * 1.08, 0.74, 0.4, 8.505, 0.28]].forEach((u, p) => {
        v(e + (o ? 0 : u[0]), r + (o ? u[0] : 0), u[o ? 2 : 1], u[o ? 1 : 2], u[3] + t, u[4], p === 4 ? Qe : B);
      });
    });
    if (!o && Math.abs(e - A.x) < 40 && Math.abs(r) === 44) Ze(e + a * 1.08, r, 0.58, 0.18, 8.505, 0.035, 'lamp');
    const f = { x: e + (o ? 0 : a * 1.08), z: r + (o ? a * 1.08 : 0), y: 0.31 + t, inward: a };
    if (o) f.axis = 'z';
    x.lampAnchors.push(f); x.lamps++;
    if (!force) x.furniture.push(s);
    return true;
  }
  [-1, 1].forEach((e) => [-38, 38].forEach((r) => bt(A.x + e * 19, r, false)));
  [-226, -186, -146, -106, -66, -26, 26, 66, 106, 146, 186, 226].forEach((e) => Je('z', A.x, e, [26.75]));
  m.parks.forEach((e, r) => {
    if (e.use === 'sports') return;
    const a = { id: 'park-' + r, x: e.x, z: e.z, targetBenches: 4, minimumBenches: 3, benchCount: 0 };
    const t = [[10, 9, true], [-10, -9, true], [-10, 9, true], [10, -9, true], [10, 13, false], [-10, -13, false], [-10, 13, false], [10, -13, false], [9, 7, false], [-9, -7, false], [-9, 7, false], [9, -7, false]];
    t.some((n) => {
      const i = e.x + n[0], o = e.z + n[1], s = n[2];
      if (Math.abs(n[0]) + (s ? 3.2 : 1.6) > e.w / 2 - 6 || Math.abs(n[1]) + (s ? 1.6 : 3.2) > e.d / 2 - 7) return false;
      if (bt(i, o, s, a.id)) a.benchCount++;
      return a.benchCount >= a.targetBenches;
    });
    x.parkSeating.push(a);
  });
  m.roads.filter((e) => e.axis === 'z').forEach((e) => [-234.5, -168.5, -151.5, -88.5, -71.5, -8.5, 8.5, 71.5, 88.5, 151.5, 168.5, 234.5].forEach((r) =>
    Je('z', e.x, r, [8.1, 8.5], (a) => Math.abs(a.z - e.z) < e.d / 2 - 2)));
  m.roads.filter((e) => e.axis === 'x').forEach((e) => {
    const r = e.x < 0 ? -1 : 1, a = e.unlit ? [e.x] : [36, 72, 118, 156].map((n) => r * n);
    const t = (n) => Math.abs(n.x - e.x) < e.w / 2 - 1 && !(m.tunnels || []).some((i) => Math.abs(i.z - e.z) < 0.1 && Math.abs(n.x) < i.portalX);
    a.forEach((n) => { if (t({ x: n })) Je('x', e.z, n, [e.d / 2 + 2.5, e.d / 2 + 3.4], t); });
  });

  // ---- high masts: plinth, base, bolts, tapered shafts, service box, crown with eight lamp arms.
  const shaft = (cx, cz, cy, rBottom, rTop, height) => {
    const g = new T.CylinderGeometry(rTop, rBottom, height, 8, 1);
    em.geometry(B[0], g, new T.Matrix4().makeTranslation(cx, cy, cz), B[1]); g.dispose();
  };
  x.highMasts.forEach((e, idx) => {
    const r = Pe(e), a = r.x, t = r.z, n = r.y;
    const ib = (l, d, g, y, W, S2, U, Q) => em.box(U[0], a + l, n + d, t + g, y, W, S2, U[1], Q || null);
    const o = (l, d, g, y) => {
      const W = new T.Vector3(d[0] - l[0], d[1] - l[1], d[2] - l[2]), S2 = new T.Quaternion().setFromUnitVectors(J, W.clone().normalize());
      ib((l[0] + d[0]) / 2, (l[1] + d[1]) / 2, (l[2] + d[2]) / 2, g, W.length(), g, y, [S2.x, S2.y, S2.z, S2.w]);
    };
    item('high-mast', 'high-mast-' + idx, 0.25, () => {
      ib(0, 0.1, 0, 1.35, 0.2, 1.35, h.stone); ib(0, 0.25, 0, 1.02, 0.1, 1.02, h.metal);
      [-0.36, 0.36].forEach((l) => [-0.36, 0.36].forEach((d) => ib(l, 0.334, d, 0.09, 0.068, 0.09, B)));
      shaft(a, t, n + 1.02, 0.285, 0.265, 1.42);
    });
    shaft(a, t, n + 9.36, 0.255, 0.115, 15.38);
    ib(0, 1.73, 0, 0.58, 0.1, 0.58, h.metal); ib(0, 1, -0.277, 0.3, 0.82, 0.035, h.metal); ib(0, 1, -0.298, 0.24, 0.73, 0.018, B); ib(0.073, 1.03, -0.318, 0.045, 0.045, 0.021, h.metal);
    ib(0, 17.18, 0, 0.6, 0.44, 0.6, h.metal); shaft(a, t, n + 17.7, 0.14, 0.09, 0.65); shaft(a, t, n + 18.23, 0.045, 0.018, 0.54);
    for (let s = 0; s < 8; s++) {
      const f = s * Math.PI / 4, u = Math.cos(f), p = Math.sin(f);
      o([u * 0.2, 17.05, p * 0.2], [u * 1.42, 17.44, p * 1.42], 0.12, B); o([u * 0.08, 16.73, p * 0.08], [u * 0.95, 17.3, p * 0.95], 0.055, h.metal);
      const w = new T.Quaternion().setFromAxisAngle(J, -f).multiply(new T.Quaternion().setFromAxisAngle(new T.Vector3(0, 0, 1), Math.PI / 15));
      const l = (d, g, y, W, S2) => { const U = new T.Vector3(0, d, 0).applyQuaternion(w); ib(u * 1.71 + U.x, 17.49 + U.y, p * 1.71 + U.z, g, y, W, S2, [w.x, w.y, w.z, w.w]); };
      l(0, 0.98, 0.18, 0.46, B); l(-0.1, 0.86, 0.055, 0.37, h.metal); l(-0.132, 0.77, 0.012, 0.29, Qe);
    }
    x.lampAnchors.push({ x: a, z: t, y: n + 0.31, inward: 0, axis: 'z', highMast: true }); x.lamps++;
  });

  // ---- planting (`dn`): shrubs, ornamental grass tufts and flowers, in parks and along the river.
  const Ee = [[], []];
  const flowerGeo = (() => {
    const pts = [];
    const e = (s, f, u, p) => s.push(...f, ...u, ...p);
    for (let r = 0; r < 5; r++) {
      const a = r * Math.PI * 2 / 5, t = Math.cos(a), n = Math.sin(a), i = [t * 0.115, 0.01, n * 0.115];
      for (let o = 0; o < 6; o++) {
        const s = (f) => { const u = f * Math.PI / 3; return [i[0] + t * Math.cos(u) * 0.115 - n * Math.sin(u) * 0.075, 0.024 * Math.cos(u), i[2] + n * Math.cos(u) * 0.115 + t * Math.sin(u) * 0.075]; };
        e(pts, i, s(o), s(o + 1));
      }
    }
    return flatGeometry(T, pts);
  })();
  function vn(e, r) {
    if ((m.reservations || []).some((a) => V(e, a, 0.5)) || !Y) return false;
    if (Math.abs(e.x - r.x) + e.w / 2 > r.w / 2 || Math.abs(e.z - r.z) + e.d / 2 > r.d / 2) return false;
    if (Math.abs(e.x) + e.w / 2 > ye - 1 || Math.abs(e.z) + e.d / 2 > H - 1 || V(e, A, 1)) return false;
    if (m.roads.some((a) => V(e, a, 3.6)) || m.bridges.some((a) => V(e, { x: a.x, z: a.z, w: a.w + 20, d: a.d + 8 }, 0.8))) return false;
    if (m.buildings.some((a) => V(e, a, 1.6)) || !Ye(e, Y.walkingRoutes, true) || !Ye(e, Y.vehicleRoutes, false)) return false;
    if (x.furniture.some((a) => V(e, a, 0.65)) || x.planting.some((a) => V(e, a, 0.7))) return false;
    if (m.parks.some((a) => V(e, { x: a.x, z: a.z, w: 2.6, d: a.d - 10 }, 0.5) || V(e, { x: a.x, z: a.z, w: a.w - 8, d: 2.6 }, 0.5))) return false;
    return !m.trees.some((a) => { const t = Math.max(0, Math.abs(a.x - e.x) - e.w / 2), n = Math.max(0, Math.abs(a.z - e.z) - e.d / 2); return Math.hypot(t, n) < a.r * 0.27 + 0.4; });
  }
  (function dn() {
    const e = rng((m.seed ^ 1103720103) >>> 0), shrubs = [], tufts = [];
    const shrubGeo = new T.IcosahedronGeometry(1, 1);
    const tuftPts = [];
    const tri = (U, Q, F, z) => U.push(...Q, ...F, ...z, ...Q, ...z, ...F);
    for (let o = 0; o < 5; o++) {
      const s = o * Math.PI * 2 / 5, f = Math.cos(s), u = Math.sin(s), p = o === 0 ? 1 : 0.59 + o * 0.065, w = o === 0 ? 0.18 : 0.35;
      const M2 = [-u * 0.035, 0, f * 0.035], l = [u * 0.035, 0, -f * 0.035], d = [f * w * 0.45 - u * 0.068, p * 0.55, u * w * 0.45 + f * 0.068], g = [f * w * 0.45 + u * 0.068, p * 0.55, u * w * 0.45 - f * 0.068], y = [f * w, p, u * w];
      tri(tuftPts, M2, l, d); tri(tuftPts, l, g, d); tri(tuftPts, d, g, y);
    }
    const tuftGeo = flatGeometry(T, tuftPts);
    function S2(U, Q, F, z, N, river) {
      const _e = { x: U, z: Q, w: F, d: z, kind: river ? 'river' : 'park', top: 1.7 };
      if (!vn(_e, N)) return false;
      x.planting.push(_e);
      if (river) v(U, Q, F, z, 0.12, 0.12, h.grass);
      for (let Oe = 0; Oe < 3; Oe++) {
        const de = U + (Oe - 1) * F * 0.19, br = Q + (Oe === 1 ? -0.1 : 0.075) * z, yr = 0.46 + e() * 0.24, Ar = Math.min(F * 0.225, z * 0.26);
        shrubs.push([de, 0.12 + yr * 0.86, br, Ar * (0.89 + e() * 0.1), yr, Ar * (0.9 + e() * 0.1), e() * Math.PI * 2, 0.82 + e() * 0.17]);
      }
      for (let je = 0; je < 8; je++) {
        const Cr = je * Math.PI * 2 / 8 + (e() - 0.5) * 0.2, Xe = U + Math.cos(Cr) * F * 0.35, ir = Q + Math.sin(Cr) * z * 0.34, fr = e() * Math.PI * 2, ur = 0.63 + e() * 0.2, Sr = 0.47 + e() * 0.27;
        tufts.push([Xe, 0.12, ir, ur, Sr, ur, fr, 0.83 + e() * 0.16]);
        if (je % 3 === 0) { const Fr = 0.72 + e() * 0.22; Ee[(je + x.planting.length) % 4 === 0 ? 1 : 0].push([Xe + Math.cos(fr) * 0.18 * ur, 0.12 + Sr, ir - Math.sin(fr) * 0.18 * ur, Fr, Fr, Fr, fr, 1]); }
      }
      return true;
    }
    m.parks.forEach((U) => {
      if (U.use === 'sports') return;
      const Q = { x: U.x, z: U.z, w: U.w - 11.2, d: U.d - 13.2 }, F = []; let z = 0;
      [-14, -7, 7, 14].forEach((N) => [-16, -8, 8, 16].forEach((Tz) => F.push({ x: N, z: Tz, rank: e() })));
      F.sort((N, Tz) => N.rank - Tz.rank).some((N) => { if (S2(U.x + N.x + (e() - 0.5) * 1.4, U.z + N.z + (e() - 0.5) * 1.4, 4.5 + e() * 1.3, 3.6 + e() * 0.7, Q, false)) z++; return z === 8; });
    });
    [-1, 1].forEach((U) => {
      const Q = U < 0 ? we : fe, F = { x: Q + U * 16.1, z: A.z, w: 4.2, d: A.d - 8 };
      [-137, -111, -46, 46, 111, 137].forEach((z) => S2(F.x, A.z + z, 4, 5.6 + e() * 0.7, F, true));
    });
    const inst = (geo, mat, list, shade) => list.forEach((s) => {
      tm.compose(tp.set(s[0], s[1], s[2]), tq.setFromAxisAngle(J, s[6]), ts.set(s[3], s[4], s[5]));
      em.geometry(mat[0], geo, tm, shade ? [mat[1][0] * s[7] * 0.98, mat[1][1] * s[7], mat[1][2] * s[7] * 0.96] : mat[1]);
    });
    inst(shrubGeo, h.leaf, shrubs, true); inst(tuftGeo, h.grass, tufts, true);
    counts.shrubs = shrubs.length; counts.grass_tufts = tufts.length;
  })();
  function Ge(e, kind) { return cr(e, kind || 'street') && !x.planting.some((a) => V(e, a, 0.65)); }

  // ---- bus shelters (`mn`) and bus stop signs (`xn`).
  function mn(e, r, a) {
    const t = { x: e, z: r, w: 13.4, d: 3.8, kind: 'bus-shelter', top: 7.6 };
    if (!Ge(t)) return false;
    v(e, r, t.w, t.d, 0.27, 0.12, h.pavement);
    item('bus-shelter', 'bus-shelter-' + x.busShelters, 0.27, () => {
      v(e - 0.55, r, 11.2, 3.4, 7.6, 0.24, h.metal); v(e - 0.55, r, 10.9, 3.15, 7.35, 0.07, h.stone);
      [-1, 1].forEach((n) => { v(e - 0.55 + n * 4.8, r - a * 1.15, 0.18, 0.18, 7.36, 7.09, B); v(e - 0.55 + n * 2.6, r - a * 0.57, 0.22, 0.86, 1.37, 1.1, B); });
      v(e - 0.55, r - a * 0.57, 7.2, 0.95, 1.57, 0.2, R); v(e - 0.55, r - a * 0.98, 7.2, 0.12, 2.65, 0.64, R);
      v(e + 5.8, r + a * 0.6, 0.16, 0.16, 5.9, 5.63, B); v(e + 5.8, r + a * 0.6, 0.9, 0.18, 6.05, 1.3, h.stone);
    });
    v(e + 5.8, r + a * 0.7, 0.72, 0.035, 5.83, 0.12, ee);
    env.shelters.push({ x: e, z: r, facing: a, sign: { x: e + 5.8, y: 5.4, z: r + a * 0.6 } });
    x.furniture.push(t); x.busShelters++; return true;
  }
  const Sa = (m.transitStops || []).filter((e) => e.kind === 'bus'), Xr = [];
  Sa.filter((e) => e.shelter).forEach((e) => [0, -5, 5, -10, 10].forEach((r) => Xr.push([e.x + r, e.z, e.facing])));
  Sa.forEach((e) => Xr.push([e.x, e.z, e.facing]));
  [[-141, 90, -1], [-123, 90, -1], [-141, -90, 1], [-123, -90, 1], [123, -10, 1], [141, -10, 1]].forEach((e) => Xr.push(e));
  Xr.some((e) => (mn(e[0], e[1], e[2]), x.busShelters >= 3));
  function xn(e, r, a, stop) {
    const t = { x: e, z: r, w: 1.7, d: 0.6, kind: 'bus-sign', top: 3.15 };
    if (!Ge(t)) return false;
    item('bus-sign', 'bus-sign-' + x.busSigns, 0.25, () => { v(e, r, 0.2, 0.2, 3.15, 3, B); v(e, r + a * 0.3, 1.55, 0.07, 2.85, 1.05, h.stone); });
    v(e, r + a * 0.35, 1.05, 0.04, 2.52, 0.8, ee);
    env.busSigns.push({ x: e, z: r, facing: a, stop: stop.id });
    x.furniture.push(t); x.busSigns++; return true;
  }
  Sa.forEach((e) => {
    const r = x.furniture.some((a) => a.kind === 'bus-shelter' && Math.hypot(a.x - e.x, a.z - e.z) < 11);
    if (!r) [[0, 0], [0, e.facing * 0.8], [0, e.facing * 1.8], [-3.4, 0], [3.4, 0], [0, e.facing * 3.6]].some((a) => xn(e.x + a[0], e.z + a[1], e.facing, e));
  });
  (m.transitStops || []).forEach((e) => {
    if (e.kind !== 'taxi') return;
    const r = e.axis === 'x', a = { x: e.x, z: e.z, w: e.w, d: e.d, kind: 'taxi-rank', top: 3.1 };
    const t = (m.places || []).find((l) => l.kind === 'station');
    const n = t ? (m.reservations || []).filter((l) => l.kind === 'station' && Math.abs(l.x - t.x) < 1 && Math.abs(l.z - t.z) < 1) : null;
    if (!cr(a, 'lamp', n)) return;
    const o = r ? e.w : e.d;
    for (let f = -1; f <= 1; f += 2) {
      const u = r ? e.x + f * o * 0.3 : e.x, p = r ? e.z : e.z + f * o * 0.3;
      v(u, p, r ? 7.4 : 2.6, r ? 2.6 : 7.4, 0.26, 0.06, E); v(u, p, r ? 7.4 : 2.9, r ? 2.9 : 7.4, 0.265, 0.05, E);
    }
    const w = e.x + (r ? 0 : e.facing * 2.4), M2 = e.z + (r ? e.facing * 2.4 : 0);
    item('taxi-sign', 'taxi-sign', 0.25, () => { v(w, M2, 0.34, 0.34, 3.3, 3.05, B); v(w, M2 + (r ? e.facing * 0.34 : 0), 1.7, r ? 0.5 : 1.7, 3.14, 0.9, h.stone); });
    env.taxiSign = { x: w, z: M2, facing: [r ? 0 : e.facing, r ? e.facing : 0] };
    x.furniture.push(a); x.taxiRanks++;
  });

  // ---- bike racks (`wn`): hoops, three bicycles each (frames as rods, wheels as tori).
  const wheels = [];
  function wn(e, r) {
    const a = { x: e, z: r, w: 5.6, d: 6.2, kind: 'bike-rack', top: 2.9, bicycles: 3 };
    if (!Ge(a)) return false;
    v(e, r, a.w, a.d, 0.27, 0.12, h.pavement);
    item('bike-rack', 'bike-rack-' + x.bikeRacks, 0.27, () => [-2, 0, 2].forEach((t) => {
      const n = r + t;
      v(e + 0.2, n - 0.35, 0.12, 0.12, 2.2, 1.93, B); v(e + 0.2, n + 0.35, 0.12, 0.12, 2.2, 1.93, B); v(e + 0.2, n, 0.12, 0.82, 2.26, 0.12, B);
      const i = (w, M2, l) => [e + w, M2, n + (l || 0)];
      const o = i(-1.35, 1.165), s = i(0, 1.07), f = i(-0.45, 2.3), u = i(0.95, 2.15), p = i(1.35, 1.165);
      [[o, s], [o, f], [f, s], [f, u], [s, u], [u, p]].forEach((w) => Se(w[0], w[1], 0.105, B));
      Se(f, i(-0.5, 2.58), 0.09, h.metal); Se(u, i(1.04, 2.66), 0.09, h.metal); Se(i(1.04, 2.66, -0.42), i(1.04, 2.66, 0.42), 0.09, B);
      v(e - 0.52, n, 0.72, 0.34, 2.72, 0.15, B); v(e, n, 0.35, 0.62, 1.12, 0.1, h.metal);
      wheels.push([e - 1.35, 1.165, n], [e + 1.35, 1.165, n]);
    }));
    x.furniture.push(a); x.bikeRacks++; x.bicycles += 3; return true;
  }
  [[-163, 130], [-163, 108], [163, -30], [163, -50], [-145, 155]].some((e) => (wn(e[0], e[1]), x.bikeRacks >= 2));
  if (wheels.length) {
    const torus = new T.TorusGeometry(0.82, 0.075, 6, 16);
    wheels.forEach((e) => em.geometry(B[0], torus, new T.Matrix4().makeTranslation(e[0], e[1], e[2]), B[1]));
    torus.dispose();
  }
  // ---- vending machines (`gn`), mailboxes (`Ba`), bins (`zn`).
  function gn(e, r, a) {
    const t = { x: e, z: r, w: 1.15, d: 0.85, kind: 'vending', top: 2.15 };
    if (!Ge(t)) return false;
    v(e, r, 1.3, 1, 0.16, 0.16, h.pavement);
    item('vending', 'vending-' + x.vendingMachines, 0.25, () => { v(e, r, 1.15, 0.8, 2.05, 1.87, B); v(e, r, 1.2, 0.85, 2.15, 0.1, h.metal); });
    if (a === 'n' || a === 's') v(e, r + (a === 'n' ? -0.44 : 0.44), 0.82, 0.05, 1.92, 1.28, ee); else v(e + (a === 'w' ? -0.44 : 0.44), r, 0.05, 0.82, 1.92, 1.28, ee);
    x.furniture.push(t); x.vendingMachines++; return true;
  }
  const Yr = (list, count) => { const a = x.vendingMachines; list.some((t) => (gn(t[0], t[1], t[2]), x.vendingMachines >= a + count)); };
  const St = [];
  x.furniture.filter((e) => e.kind === 'bus-shelter').forEach((e) => {
    const r = Math.abs(e.z - 80) < Math.abs(e.z + 80) ? 'n' : 's';
    [[-9.6], [9.6], [-11.5], [11.5], [-13], [13]].forEach((a) => St.push([e.x + a[0], e.z, r]));
  });
  Yr(St, 3);
  Yr([[30.9, -228, 'w'], [30.9, 228, 'w'], [30.9, -223, 'w'], [30.9, 223, 'w'], [30.9, -233, 'w'], [30.9, 233, 'w']], 2);
  Yr([[19, -100, 'w'], [-19, 100, 'e'], [19, -94, 'w'], [-19, 94, 'e'], [19, -106, 'w'], [-19, 106, 'e']], 2);
  const Ft = m.parks.filter((e) => e.use !== 'sports').sort((e, r) => r.w * r.d - e.w * e.d);
  if (Ft.length) { const Re = Ft[0], $r = Re.x - Re.w / 2 + 1.5; Yr([[$r, Re.z + 3, 'n'], [$r, Re.z - 3, 'n'], [$r, Re.z + 6, 'n'], [$r, Re.z - 6, 'n']], 1); }
  function Ba(e, r, a) {
    const t = { x: e, z: r, w: 1.05, d: 0.75, kind: 'mailbox', top: 1.5 };
    if (!Ge(t)) return false;
    item('mailbox', 'mailbox-' + x.mailboxes, 0.25, () => { v(e, r, 0.26, 0.26, 0.42, 0.42, h.metal); v(e, r, 1.05, 0.75, 1.36, 1.08, Pa); v(e, r, 1.1, 0.8, 1.5, 0.14, Pa); });
    if (a === 'n' || a === 's') v(e, r + (a === 'n' ? -0.39 : 0.39), 0.5, 0.06, 1.18, 0.1, ee); else v(e + (a === 'e' ? 0.39 : -0.39), r, 0.06, 0.5, 1.18, 0.1, ee);
    x.furniture.push(t); x.mailboxes++; return true;
  }
  const Ue = m.waterfront && m.waterfront.civic;
  if (Ue) { const Mn = Ue.side > 0 ? 'w' : 'e'; [[Ue.d / 2 + 1.9], [-Ue.d / 2 - 1.9], [Ue.d / 2 + 3.6], [-Ue.d / 2 - 3.6]].some((e) => Ba(Ue.x, Ue.z + e[0], Mn)); }
  const Te = (m.transitStops || []).find((e) => e.kind === 'taxi');
  if (Te) [[2.4, Te.d / 2 + 2.2], [-2.4, Te.d / 2 + 2.2], [2.4, -Te.d / 2 - 2.2]].some((e) => Ba(Te.x + e[0], Te.z + e[1], 'e'));
  const ke = (m.places || []).find((e) => e.kind === 'plaza');
  if (ke) { const Jr = ke.z - ke.d / 2 - 1.6; [[ke.x - 12, Jr], [ke.x + 12, Jr], [ke.x - 20, Jr], [ke.x + 20, Jr]].some((e) => Ba(e[0], e[1], 'n')); }
  function zn(e, r) {
    const a = { x: e, z: r, w: 1.7, d: 1.3, kind: 'bin', top: 1.14 };
    if (x.bins >= 60 || !Ge(a, 'lamp') || x.furniture.some((o) => o.kind === 'bin' && Math.hypot(o.x - e, o.z - r) < 34)) return false;
    v(e, r, 1.9, 1.5, 0.14, 0.14, h.pavement);
    item('bin', 'bin-' + x.bins, 0.25, () => { v(e, r, 1.7, 1.3, 1, 0.86, h.stone); v(e, r, 0.84, 0.64, 1.12, 0.2, h.metal); v(e, r, 0.62, 0.44, 1.14, 0.05, B); });
    v(e, r, 1.42, 1.02, 1.06, 0.1, h.grass);
    [[0, -0.6, 1.5, 0.07], [0, 0.6, 1.5, 0.07], [-0.74, 0, 0.07, 1.06], [0.74, 0, 0.07, 1.06]].forEach((o) => v(e + o[0], r + o[1], o[2], o[3], 1.03, 0.08, ee));
    for (let t = 0; t < 5; t++) { const n = t * Math.PI * 2 / 5 + 0.4, i = 1.02 + t * 0.05; Ee[(x.bins + t) % 4 === 0 ? 1 : 0].push([e + Math.cos(n) * 0.52, 1.06, r + Math.sin(n) * 0.4, i, i, i, n, 1]); }
    x.bins++; x.furniture.push(a); return true;
  }
  const Le = [];
  [-1, 1].forEach((e) => [-142, -62, 62, 142].forEach((r) => Le.push([e * 19, r])));
  m.parks.forEach((e) => { if (e.use !== 'sports') [1, -1].forEach((r) => Le.push([e.x + r * (e.w / 2 - 1.5), e.z])); });
  (Array.isArray(m.blockWalks) ? m.blockWalks : [{ x: -60, z: 40 }, { x: 132, z: 120 }]).forEach((e) => {
    if (Y.walkingRoutes.some((a) => a.segments.some((t) => Math.abs(t.x - (e.x + 30)) < 0.01 && Math.abs(t.dx) < 0.01))) { Le.push([e.x - 26.5, e.z + 15]); Le.push([e.x + 26.5, e.z - 15]); }
  });
  m.roads.filter((e) => e.axis === 'x' && !e.unlit).forEach((e) => [54, 138].forEach((r) => {
    if ((m.tunnels || []).some((a) => Math.abs(a.z - e.z) < 0.1 && r < a.portalX)) return;
    [-1, 1].forEach((a) => Le.push([e.x < 0 ? -r : r, e.z + a * 7.4]));
  }));
  m.roads.filter((e) => e.axis === 'z').forEach((e) => [-120, -40, 40, 120].forEach((r) => [-1, 1].forEach((a) => Le.push([e.x + a * 7.4, r]))));
  (m.transitStops || []).forEach((e) => { if (e.kind === 'bus') [-9.8, 9.8].forEach((r) => Le.push([e.x + r, e.z])); });
  Le.some((e) => (zn(e[0], e[1]), x.bins >= 60));
  // Flowers (`Kr` "all-warm-white-flowers" / "all-apricot-flowers"): per-instance colour cycles.
  const flowerColours = [['#eee9d7', '#e8e2c8', '#f2eddf'], ['#c8cf8a', '#d3d499', '#e5dfba']];
  [0, 1].forEach((k) => Ee[k].forEach((s, f) => {
    tm.compose(tp.set(s[0], s[1], s[2]), tq.setFromAxisAngle(J, s[6]), ts.set(s[3], s[4], s[5]));
    em.geometry('tt_matte', flowerGeo, tm, lin(flowerColours[k][f % 3]));
  }));
  counts.flowers = Ee[0].length + Ee[1].length;

  // ---- street trees (`Sn`/`Fn`), seeded; drawn with the park trees by `Bn` below.
  const Gt = [], Rr = rng((m.seed ^ 1595579507) >>> 0), rr = [];
  m.roads.forEach((e) => { if (e.axis === 'x') m.roads.forEach((r) => { if (r.axis === 'z') rr.push({ x: r.x, z: e.z, w: 28, d: 28 }); }); });
  m.bridges.forEach((e) => rr.push({ x: e.x, z: e.z, w: e.w + 28, d: e.d + 28 }));
  sa.forEach((e) => e.gateZ.forEach((r) => rr.push({ x: e.gateX, z: r, w: 28, d: 28 })));
  Or.forEach((e) => rr.push({ x: e.x, z: e.z, w: e.w + 28, d: e.d + 28 }));
  rr.push({ x: A.x, z: A.z, w: A.w + 8, d: A.d });
  function Sn(e, r) {
    const a = { x: e, z: r, w: 1.6, d: 1.6, kind: 'street-tree', top: 8.2 };
    if (rr.some((t) => V(a, t, 0)) || !Ge(a)) return false;
    x.streetTrees++; x.furniture.push(a); Gt.push({ x: e, z: r, r: 1.75, h: 8.2, street: true }); return true;
  }
  function Fn(e, r, a) {
    const t = e.axis === 'x', n = (t ? e.x - e.w / 2 : e.z - e.d / 2) + 7 + a, i = (t ? e.x + e.w / 2 : e.z + e.d / 2) - 7;
    for (let o = n + Rr() * 6; o < i;) { const s = (Rr() - 0.5) * 2.4, f = t ? o + s : e.x + r, u = t ? e.z + r : o + s; Sn(f, u); o += 19 + Rr() * 7; }
  }
  m.roads.forEach((e) => { if (e.axis === 'x' && e.z !== 0) return; [-1, 1].forEach((r) => Fn(e, r * ((e.axis === 'x' ? e.d : e.w) / 2 + 3 + Rr() * 0.8), r < 0 ? 0 : 11)); });

  // ---- the pedestrian stretch of the z = 0 street (`Tr`): festoons, gates, bollards, benches, planters,
  // chess table, cart, menu boards and a kiosk.
  let Tr = null; m.roads.forEach((e) => { if (e.walkOnlyTo) Tr = e; });
  if (Tr && Y) {
    const Pn = Tr.walkOnlyTo;
    const okWalk = (t) => !(Math.abs(t.x) + t.w / 2 > Pn + 0.2 || Math.abs(t.z) + t.d / 2 > Tr.d / 2 + 0.2 ||
      (m.reservations || []).some((n) => V(t, n, 0.7)) || V(t, A, 1) || m.bridges.some((n) => V(t, { x: n.x, z: n.z, w: n.w + 20, d: n.d + 8 }, 0.8)) ||
      m.buildings.some((n) => V(t, n, 1.6)) || !Ye(t, Y.walkingRoutes, true) || x.furniture.some((n) => V(t, n, 1.2)) || x.planting.some((n) => V(t, n, 0.7)) ||
      m.trees.some((n) => { const i = Math.max(0, Math.abs(n.x - t.x) - t.w / 2), o = Math.max(0, Math.abs(n.z - t.z) - t.d / 2); return Math.hypot(i, o) < n.r * 0.65 + 0.4; }));
    const place = (t) => (okWalk(t) ? (x.furniture.push(t), true) : false);
    const walkBench = (t, n, i) => {
      if (!place({ x: t, z: n, w: 4.4, d: 2.3, kind: 'walk-bench', top: 2.3 })) return;
      v(t, n, 3.9, 1.7, 0.26, 0.08, h.pavement);
      item('bench', nid('walk-bench'), 0.25, () => {
        for (let o = 0; o < 3; o++) { v(t, n + i * (-0.45 + o * 0.45), 3.3, 0.38, 1.33, 0.16, R); v(t, n + i * 0.62, 3.3, 0.13, 1.62 + o * 0.29, 0.2, R); }
        [-1, 1].forEach((s) => { v(t + s * 1.5, n, 0.16, 1.3, 1.15, 0.89, B); v(t + s * 1.5, n + i * 0.66, 0.13, 0.13, 2.28, 1.25, B); });
      });
      x.benches++;
    };
    [36, 72].forEach((t) => [-1, 1].forEach((n) => {
      const i = [-1, 1].map((w) => {
        let M2 = null;
        x.furniture.forEach((l) => { if (l.kind === 'lamp' && !(Math.abs(l.x - n * t) > 4.2 || Math.abs(Math.abs(l.z) - 8.5) > 1.2) && l.z * w > 0) M2 = { x: l.x, z: l.z }; });
        return M2;
      });
      if (!i[0] || !i[1]) return;
      const o = [];
      for (let s = 0; s <= 5; s++) { const f = s / 5; o.push([i[0].x + (i[1].x - i[0].x) * f, 8.3 - 2.05 * 4 * f * (1 - f), i[0].z + (i[1].z - i[0].z) * f]); }
      for (let u = 0; u < 5; u++) Se(o[u], o[u + 1], 0.12, B);
      [o[1], o[2], o[3], o[4], [(o[2][0] + o[3][0]) / 2, (o[2][1] + o[3][1]) / 2, (o[2][2] + o[3][2]) / 2]].forEach((w) => {
        Se([w[0], w[1] - 0.02, w[2]], [w[0], w[1] - 0.48, w[2]], 0.05, B); ua(w[0], w[2], 0.5, 0.5, w[1] - 0.48, 0.62);
        env.lanterns.push({ kind: 'walk-festoon', x: w[0], y: w[1] - 0.79, z: w[2] });
      });
    }));
    [-1, 1].forEach((t) => {
      const n = t * 87; let i = 0;
      [-1, 1].forEach((o) => { if (place({ x: n, z: o * 5, w: 1.6, d: 1.6, kind: 'walk-gate', top: 9.5 })) i++; });
      if (i === 2) {
        item('walk-gate', 'walk-gate-' + (t < 0 ? 'w' : 'e'), 0.25, () => [-1, 1].forEach((o) => { v(n, o * 5, 1.6, 2, 0.5, 0.5, h.stone); v(n, o * 5, 1.5, 1.5, 9.5, 9, h.stone); }));
        v(n, 0, 1.1, 13.2, 10.2, 0.7, R); v(n, 0, 1.5, 14.2, 10.95, 0.75, h.stone); v(n, 0, 0.3, 3, 9.45, 0.85, E); v(n, 0, 0.32, 2.6, 9.02, 0.1, ee);
        [-2.8, 2.8].forEach((o) => { Se([n, 9.5, o], [n, 9.02, o], 0.05, B); ua(n, o, 0.5, 0.5, 9.02, 0.62); env.lanterns.push({ kind: 'walk-gate', x: n, y: 8.71, z: o }); });
        env.walkGates.push({ x: n, z: 0, facing: [t, 0] });
      }
      [-4.8, -2.4, 0, 2.4, 4.8].forEach((o) => {
        if (place({ x: t * 90.5, z: o, w: 0.7, d: 0.7, kind: 'walk-bollard', top: 1.24 }))
          item('bollard', nid('bollard'), 0.25, () => { v(t * 90.5, o, 0.5, 0.5, 1.1, 1.1, h.stone); v(t * 90.5, o, 0.6, 0.6, 1.24, 0.14, B); });
      });
    });
    [-68, -44, 44, 68].forEach((t) => { walkBench(t, -4.2, -1); walkBench(t, 4.2, 1); });
    [[-84, -4.4], [-58, 4.4], [-38, -4.4], [38, -4.4], [76, 4.4], [84, -4.4]].forEach((t) => {
      if (place({ x: t[0], z: t[1], w: 1.8, d: 1.8, kind: 'walk-planter', top: 1.6 }))
        item('planter', nid('walk-planter'), 0.25, () => { v(t[0], t[1], 1.5, 1.5, 0.92, 0.8, h.stone); vr(t[0], 1.22, t[1], 1.05, 0.68, 1.05, 0, h.grass); vr(t[0], 1.3, t[1], 0.78, 0.5, 0.78, Math.PI / 4, h.grass); });
    });
    if (place({ x: -60, z: -4.2, w: 3.6, d: 3.6, kind: 'walk-chess', top: 1.3 })) item('chess-table', 'walk-chess', 0.25, () => {
      v(-60, -4.2, 0.9, 0.9, 0.75, 0.75, h.stone); v(-60, -4.2, 1.5, 1.5, 1.17, 0.14, h.stone);
      [[-0.33, -0.33], [0.33, 0.33]].forEach((t) => v(-60 + t[0], -4.2 + t[1], 0.62, 0.62, 1.185, 0.02, E));
      [[-1.35, 1.35], [1.35, -1.35]].forEach((t) => v(-60 + t[0], -4.2 + t[1], 0.5, 0.5, 0.9, 0.5, R));
    });
    if (place({ x: 57, z: 4.2, w: 3.4, d: 2.4, kind: 'walk-cart', top: 3.7 })) item('cart', 'walk-cart', 0.25, () => {
      [[-1.15, -0.5], [1.15, -0.5], [-1.15, 0.5], [1.15, 0.5]].forEach((t) => v(57 + t[0], 4.2 + t[1], 0.1, 0.1, 0.58, 0.58, B));
      v(57, 4.2, 2.6, 1.3, 1.35, 0.62, R);
      [[-1.25, -0.55], [1.25, -0.55], [-1.25, 0.55], [1.25, 0.55]].forEach((t) => v(57 + t[0], 4.2 + t[1], 0.09, 0.09, 3.55, 2.2, B));
      v(57, 4.2, 2.9, 0.12, 1.7, 3.67, R);
      [[-1.55, -0.3], [-0.85, 0.25], [1.35, 0.3]].forEach((t) => v(57 + t[0], 4.2 + t[1], 0.5, 0.42, 1.6, 0.26, E));
      v(57.5, 4.35, 0.55, 0.5, 1.66, 0.32, h.grass);
    });
    [51, 62.5].forEach((t) => {
      if (place({ x: t, z: 3.6, w: 1.1, d: 0.5, kind: 'walk-sign', top: 1.25 })) item('menu-board', nid('walk-sign'), 0.25, () => {
        v(t, 3.6, 0.9, 0.07, 1.22, 1.02, R); v(t, 3.53, 0.74, 0.03, 1.05, 0.62, E); [-0.3, 0.3].forEach((n) => v(t + n, 3.6, 0.08, 0.34, 0.12, 0.12, B));
      });
    });
    if (place({ x: -80, z: -4.2, w: 2.8, d: 2.4, kind: 'walk-kiosk', top: 2.8 })) {
      item('kiosk', 'walk-kiosk', 0.25, () => { v(-80, -4.2, 2.2, 1.8, 2.5, 2.4, R); v(-80, -4.2, 2.7, 2.3, 2.75, 0.25, h.stone); v(-80, -3.1, 1.7, 0.42, 1.18, 0.1, B); });
      v(-80, -3.27, 1.5, 0.06, 2.4, 0.12, ee);
    }
  }

  // ---- the river walk: benches (the landscape Bench module), festoon posts and lantern strings.
  function Wa(e) {
    return !((m.reservations || []).some((r) => V(e, r, 0.7)) || m.bridges.some((r) => V(e, { x: r.x, z: r.z, w: r.w + 20, d: r.d + 8 }, 0.8)) ||
      m.buildings.some((r) => V(e, r, 1.6)) || (Y && !Ye(e, Y.walkingRoutes, true)) || x.furniture.some((r) => V(e, r, 1.2)) || x.planting.some((r) => V(e, r, 0.7)) ||
      m.trees.some((r) => { const a = Math.max(0, Math.abs(r.x - e.x) - e.w / 2), t = Math.max(0, Math.abs(r.z - e.z) - e.d / 2); return Math.hypot(a, t) < r.r * 0.65 + 0.4; }));
  }
  [-1, 1].forEach((e) => [96, 118, 178].forEach((r) => {
    const a = e * 17.6;
    if (!Wa({ x: a, z: r, w: 3.4, d: 4.6, kind: 'river-bench', top: 2.25 })) return;
    v(a, r, 2.1, 4.2, 0.26, 0.08, h.pavement);
    tm.compose(tp.set(a, 0, r), tq.setFromAxisAngle(J, -e * Math.PI / 2), ts.set(3.3 / 4.6, 1.12, 1.3));
    item('bench', nid('river-bench'), 0.25, () => em.geometry('tt_matte', benchGeo, tm, null));
    x.furniture.push({ x: a, z: r, w: 3.4, d: 4.6, kind: 'river-bench', top: 2.25 }); x.benches++;
  }));
  [-1, 1].forEach((e) => {
    const r = [-146, -106, -66, -26, 26, 66, 106, 146].map((l) => {
      let d = null;
      x.furniture.forEach((g) => { if (g.kind === 'lamp' && Math.abs(g.x - e * 26.75) < 0.6 && Math.abs(g.z - l) < 0.5) d = { z: l, y: 8.3 }; });
      if (d) return d;
      if (!Wa({ x: e * 26.75, z: l, w: 0.5, d: 0.5, kind: 'festoon-post', top: 8.35 })) return null;
      item('festoon-post', nid('festoon-post'), 0.25, () => v(e * 26.75, l, 0.28, 0.28, 8.35, 8.35, B));
      x.furniture.push({ x: e * 26.75, z: l, w: 0.5, d: 0.5, kind: 'festoon-post', top: 8.35 });
      return { z: l, y: 8.3 };
    });
    for (let a = 1; a < r.length; a++) {
      if (!r[a - 1] || !r[a]) continue;
      const t = r[a - 1].z, n = r[a].z;
      if (n - t > 44) continue;
      const i = [];
      for (let o = 0; o <= 8; o++) { const s = o / 8; i.push([e * 26.75, 8.3 - 2.6 * 4 * s * (1 - s), t + (n - t) * s]); }
      for (let f = 0; f < 8; f++) Se(i[f], i[f + 1], 0.12, B);
      const u = 8.3 - 2.6, p = (t + n) / 2;
      if (Wa({ x: e * 26.75, z: p, w: 0.5, d: 0.5, kind: 'festoon-post', top: u + 0.06 })) {
        item('festoon-post', nid('festoon-post'), 0.25, () => v(e * 26.75, p, 0.22, 0.22, u + 0.06, u + 0.06, B));
        x.furniture.push({ x: e * 26.75, z: p, w: 0.5, d: 0.5, kind: 'festoon-post', top: u + 0.06 });
      }
      for (let w = 1; w <= 7; w++) {
        const M2 = i[w];
        Se([M2[0], M2[1] - 0.02, M2[2]], [M2[0], M2[1] - 0.45, M2[2]], 0.05, B); ua(M2[0], M2[2], 0.5, 0.5, M2[1] - 0.45, 0.62);
        env.lanterns.push({ kind: 'bank-festoon', x: M2[0], y: M2[1] - 0.76, z: M2[2] });
      }
    }
  });
  // Infill lamps: compact single lamps every 24 units along the canal and the avenues, and the cross streets.
  for (let Hr = -228; Hr <= 228; Hr += 24) {
    Je('z', A.x, Hr, [26.75], null, true);
    m.roads.filter((e) => e.axis === 'z').forEach((e) => Je('z', e.x, Hr, [8.1, 8.5, 6.4, 6.8], (r) => Math.abs(r.z - e.z) < e.d / 2 - 2 && !(m.viaducts || []).some((a) => Math.abs(r.z - a.z) < 8.5), true));
  }
  m.roads.filter((e) => e.axis === 'x' && !e.unlit).forEach((e) => {
    const r = (t) => Math.abs(t.x - e.x) < e.w / 2 - 1 && !(m.tunnels || []).some((n) => Math.abs(n.z - e.z) < 0.1 && Math.abs(t.x) < n.portalX);
    for (let a = 36; a <= 156; a += 24) if (r({ x: a * Math.sign(e.x) })) Je('x', e.z, a * Math.sign(e.x), [e.d / 2 + 2.5, e.d / 2 + 3.4, e.d / 2 + 1.4], r, true);
  });

  // ---- trees (`Bn`): the park trees from the plan and the street trees, trunks, branches, crowns, beds.
  (function Bn() {
    const list = m.trees.concat(Gt);
    const r = rng((m.seed ^ 698825665) >>> 0), a = rng((m.seed ^ 1779776441) >>> 0);
    const trunkGeo = new T.CylinderGeometry(0.66, 1, 1, 7, 1);
    // Crowns: upstream uses an IcosahedronGeometry(1, 2) (320 triangles) displaced by a fixed noise. The same
    // noise on detail 1 (80 triangles) keeps the silhouette at a quarter of the cost (budget, design section 8).
    const crownGeo = new T.IcosahedronGeometry(1, 1);
    const pa = crownGeo.getAttribute('position');
    for (let o = 0; o < pa.count; o++) {
      const s = pa.getX(o), f = pa.getY(o), u = pa.getZ(o), p = 1 + 0.1 * Math.sin(s * 11 + f * 6) * Math.cos(u * 9 - f * 3) + 0.055 * Math.sin(f * 18 + u * 7);
      pa.setXYZ(o, s * p, f * p, u * p);
    }
    crownGeo.computeVertexNormals();
    const bedGeo = new T.CylinderGeometry(1, 1, 0.035, 12);
    const I = new T.Vector3(), G = new T.Vector3(), W = new T.Vector3(), S2 = new T.Vector3(), U = new T.Vector3(), Q = new T.Euler(), C = new T.Quaternion(), b = new T.Matrix4();
    const leafLin = lin('#6f8567');
    const F = (N, Tz, _e) => { U.subVectors(Tz, N); const Oe = U.length(); C.setFromUnitVectors(J, U.normalize()); I.copy(N).add(Tz).multiplyScalar(0.5); G.set(_e, Oe, _e); b.compose(I, C, G); em.geometry(h.trunk[0], trunkGeo, b, h.trunk[1]); };
    const crown = (col) => em.geometry(h.leaf[0], crownGeo, b, col);
    list.forEach((z, N) => {
      const Tc = ['#5f8a43', '#71984d', '#49763b', '#88a958'];
      solids.begin('tree', 'tree-' + N, 0.12);
      if (z.street) {
        const _e = Math.max(0.24, z.r * 0.14), Oe = N - m.trees.length;
        W.set(z.x, 0.14, z.z); S2.set(z.x, z.h * 0.72, z.z); F(W, S2, _e);
        solids.end();
        for (let de = 0; de < 5; de++) {
          const br = de * Math.PI * 2 / 5, yr = de === 4 ? 0.06 : 0.5, Ar = z.x + Math.cos(br) * z.r * yr, je = z.z + Math.sin(br) * z.r * yr, Cr = z.h * (de === 4 ? 0.88 : 0.74), Xe = z.r * (de === 4 ? 0.62 : 0.7);
          I.set(Ar, Cr, je); G.set(Xe, Xe * 1.14, Xe); Q.set(0, br, 0); C.setFromEuler(Q); b.compose(I, C, G);
          crown(lin(Tc[Oe % Tc.length]));
          if (de < 3) { W.set(z.x, z.h * 0.5, z.z); S2.set(Ar, Cr - Xe * 0.3, je); F(W, S2, _e * 0.42); }
        }
        I.set(z.x, 0.147, z.z); G.set(z.r * 0.3, 1, z.r * 0.3); C.identity(); b.compose(I, C, G); em.geometry(Ha[0], bedGeo, b, Ha[1]);
        return;
      }
      const ir = 0.9 + a() * 0.1, fr = a(), ur = Tc[Math.min(Tc.length - 1, Math.floor(fr * Tc.length))], Sr = Math.max(0.28, z.r * 0.12);
      W.set(z.x, 0.14, z.z); S2.set(z.x + (r() - 0.5) * 0.5, z.h * 0.62, z.z + (r() - 0.5) * 0.5); F(W, S2, Sr);
      solids.end();
      for (let Fe = 0; Fe < 5; Fe++) {
        const Za = Fe * Math.PI * 2 / 5 + r() * 0.65, Xt = Fe === 4 ? 0.08 : 0.4 + r() * 0.16, Zt = z.x + Math.cos(Za) * z.r * Xt, Yt = z.z + Math.sin(Za) * z.r * Xt;
        const $t = z.h * (Fe === 4 ? 0.79 : 0.62 + r() * 0.12), ta = z.r * (0.57 + r() * 0.17);
        I.set(Zt, $t, Yt); G.set(ta * (0.82 + r() * 0.22) * ir, ta * (1.05 + r() * 0.28) * ir, ta * (0.8 + r() * 0.3) * ir);
        Q.set((r() - 0.5) * 0.4, Za, (r() - 0.5) * 0.35); C.setFromEuler(Q); b.compose(I, C, G);
        const kn = r() * 0.02 + r() * 0.02 + r() * 0.04;
        const base = lin(ur); crown([base[0] * (0.96 + kn), base[1] * (0.96 + kn), base[2] * (0.96 + kn)]);
        if (Fe < 3) { W.set(z.x, z.h * 0.38, z.z); S2.set(Zt, $t - ta * 0.25, Yt); F(W, S2, Sr * 0.48); }
      }
      I.set(z.x, 0.147, z.z); G.set(z.r * 0.27, 1, z.r * 0.27); C.identity(); b.compose(I, C, G); em.geometry(Ha[0], bedGeo, b, Ha[1]);
    });
    void leafLin;
    counts.trees = list.length; counts.street_trees = Gt.length;
  })();

  // ---- lights as data: the street lamps (createStreetLighting), the bundle's spot anchors and light pools.
  x.lampAnchors.forEach((a, i) => lights.lamp({ kind: a.highMast ? 'high-mast' : 'street', x: a.x, y: a.y + (a.highMast ? 17.05 : 8.06), z: a.z,
    ground: a.y - 0.06, color: '#ffe5bc', range: a.highMast ? 42 : 26, angle: a.highMast ? 1.18 : 1.42, energy: a.highMast ? 480 : 100, omni: true, spot: true, index: i }));
  Ta.forEach((u) => lights.spot(u));
  const pools = x.lampAnchors.map((e) => (e.highMast ? { x: e.x, z: e.z, y: 0.31, w: 48, d: 48, level: 0.75 } :
    e.axis === 'z' ? { x: e.x, z: e.z + e.inward * 3.5, y: e.y, w: 26, d: 13 } : { x: e.x + e.inward * 3.5, z: e.z, y: e.y, w: Math.abs(e.x - A.x) < 40 ? 9 : 14, d: 26 }));
  m.bridges.forEach((e) => { for (const r of [-1, 1]) pools.push({ x: e.x + r * 7, z: e.z, y: Ir(e, e.x + r * 7, e.z) + 0.035, w: 14, d: Math.min(7, e.d - 1) }); });
  za.forEach((e) => pools.push(e));
  const stalls = (m.waterfront && m.waterfront.stalls) || [];
  pools.forEach((e, r) => { const a = x.lampAnchors[r]; if (a && a.axis !== 'z' && stalls.some((t) => Math.abs(e.x - t.x) < 10 && Math.abs(e.z - t.z) < t.d / 2 + 8)) { e.w = 7; e.d = 14; e.level = 0.55; } });
  pools.forEach((p) => lights.pool({ source: 'ground', x: p.x, y: p.y, z: p.z, w: p.w, d: p.d, level: p.level === undefined ? 1 : p.level, color: '#ffcf91' }));

  Object.assign(counts, { lamps: x.lamps, high_masts: x.highMasts.length, benches: x.benches, bins: x.bins, bus_shelters: x.busShelters, bus_signs: x.busSigns,
    vending_machines: x.vendingMachines, mailboxes: x.mailboxes, bike_racks: x.bikeRacks, bicycles: x.bicycles, taxi_ranks: x.taxiRanks, lawn_lamps: x.lawnLamps,
    crosswalks: x.crosswalks, stop_lines: x.stopLines, pedestrian_bridges: x.pedestrianBridges, light_strips: x.lightStrips.length, lamp_pair_gaps: x.lampPairGaps.length });
  env.groundDetails = x;
}

// `planHighMasts` (minified `Ja`): one 18.5-unit mast at the nearest avenue junction on each bank, at the
// first clear corner offset. Ported because the bundle is not executed.
export function planHighMasts(c, h) {
  const roads = c.roads, D = c.water, out = [], seen = new Set(), K = [];
  [h.walkingRoutes, h.vehicleRoutes].forEach((L, P) => L.forEach((b) => b.segments.forEach((C) => {
    const I = Math.abs(C.dx) > Math.abs(C.dz), G = P ? 4.55 : 1.4, J = P ? 2.2 : 1.4;
    K.push({ x: C.x + C.dx / 2, z: C.z + C.dz / 2, w: Math.abs(C.dx) + 2 * (I ? G : J), d: Math.abs(C.dz) + 2 * (I ? J : G) });
  })));
  const ok = (L) => !(Math.abs(L.x) + 0.72 > c.extentX - 1 || Math.abs(L.z) + 0.72 > c.extentZ - 1 || V(L, D, 0.75) || (c.reservations || []).some((P) => V(L, P, 0.7)) ||
    roads.some((P) => V(L, P, 0.5)) || c.buildings.some((P) => V(L, P, 1.6)) || (c.playground && V(L, { x: c.playground.x, z: c.playground.z, w: 40, d: 46 }, 0.4)) ||
    c.bridges.some((P) => V(L, { x: P.x, z: P.z, w: P.w + 20, d: P.d + 8 }, 0.8)) || K.some((P) => V(L, P, 0)) ||
    c.parks.some((P) => V(L, { x: P.x, z: P.z, w: 2.6, d: P.d - 10 }, 0.6) || V(L, { x: P.x, z: P.z, w: P.w - 8, d: 2.6 }, 0.6))) &&
    !c.trees.some((P) => Math.hypot(Math.max(0, Math.abs(P.x - L.x) - 0.72), Math.max(0, Math.abs(P.z - L.z) - 0.72)) < P.r * 1.3 + 0.4);
  [-1, 1].forEach((L) => {
    const P = roads.filter((b) => b.axis === 'z' && (b.x - D.x) * L > 0).sort((b, C) => Math.abs(b.x - D.x) - Math.abs(C.x - D.x))[0];
    if (!P) return;
    roads.filter((b) => b.axis === 'x' && !b.unlit && V(b, P, 0)).forEach((b) => {
      const key = P.x + ',' + b.z;
      if (seen.has(key)) return;
      seen.add(key);
      let I = null;
      [1.4, 1.7, 2, 2.4, 2.8, 3.2, 3.6].some((G) => [[L, -1], [L, 1], [-L, -1], [-L, 1]].some((Jc) => {
        if (b.walkOnlyTo && Jc[0] !== L) return false;
        const site = { vertical: P, horizontal: b, offsetX: Jc[0] * (P.w / 2 + G), offsetZ: Jc[1] * (b.d / 2 + G) };
        const Hp = { x: site.vertical.x + site.offsetX, z: site.horizontal.z + site.offsetZ };
        if (ok({ x: Hp.x, z: Hp.z, w: 1.44, d: 1.44 })) { I = site; return true; }
        return false;
      }));
      if (I) out.push(I);
    });
  });
  return out;
}

// city-playground.js `create`: the sports ground's track, turf, pitch lines, goals and bleachers.
function playground(env, site, kit) {
  const { T, em, solids } = env;
  const track = ['tt_matte', lin('#be604e')], turf = ['tt_matte', lin('#5f9448')], stripe = ['tt_matte', lin('#73a257')], chalk = ['tt_paint', lin('#f3f1e4')];
  const box = (bx, bz, w, d, top, height, mat) => em.box(mat[0], site.x + bx, top - height / 2, site.z + bz, w, height, d, mat[1]);
  const outline = (radius) => {
    const shape = new T.Shape(), a = site.trackHalfStraight;
    shape.moveTo(radius, -a); shape.lineTo(radius, a); shape.absarc(0, a, radius, 0, Math.PI, false); shape.lineTo(-radius, -a);
    shape.absarc(0, -a, radius, Math.PI, Math.PI * 2, false); shape.closePath(); return shape;
  };
  const stadium = (radius, inner, y, mat) => {
    const shape = outline(radius); if (inner > 0) shape.holes.push(outline(inner));
    const geo = new T.ShapeGeometry(shape, 40);
    const tr = new T.Matrix4().makeRotationX(-Math.PI / 2); tr.setPosition(site.x, y, site.z);
    em.geometry(mat[0], geo, tr, mat[1]); geo.dispose();
  };
  const rectangleLine = (bx, bz, w, d, y) => { box(bx, bz - d / 2, w, 0.09, y, 0.016, chalk); box(bx, bz + d / 2, w, 0.09, y, 0.016, chalk); box(bx - w / 2, bz, 0.09, d, y, 0.016, chalk); box(bx + w / 2, bz, 0.09, d, y, 0.016, chalk); };
  const radius = site.trackRadius, inner = radius - site.lanes * site.laneWidth;
  stadium(radius + 0.65, 0, 0.28, kit.pavement); stadium(radius, inner, 0.3, track); stadium(inner, 0, 0.305, turf);
  for (let band = 0; band < 8; band += 2) box(0, -site.pitchD / 2 + (band + 0.5) * site.pitchD / 8, site.pitchW, site.pitchD / 8, 0.321, 0.012, stripe);
  for (let lane = 0; lane <= site.lanes; lane++) stadium(inner + lane * site.laneWidth + 0.035, inner + lane * site.laneWidth - 0.035, 0.33, chalk);
  box(inner + (radius - inner) / 2, -2, radius - inner, 0.11, 0.335, 0.012, chalk);
  for (let start = 0; start < site.lanes; start++) box(inner + start + 0.5, -2.5 - start * 0.65, 0.65, 0.08, 0.336, 0.012, chalk);
  rectangleLine(0, 0, site.pitchW, site.pitchD, 0.35); box(0, 0, site.pitchW, 0.09, 0.35, 0.016, chalk);
  const circle = new T.RingGeometry(2.35, 2.44, 64), tr = new T.Matrix4().makeRotationX(-Math.PI / 2); tr.setPosition(site.x, 0.352, site.z);
  em.geometry(chalk[0], circle, tr, chalk[1]); circle.dispose();
  box(0, 0, 0.17, 0.17, 0.352, 0.012, chalk);
  [-1, 1].forEach((side) => {
    rectangleLine(0, side * (site.pitchD / 2 - 2), 8.4, 4, 0.35); rectangleLine(0, side * (site.pitchD / 2 - 0.9), 5.2, 1.8, 0.351);
    const front = side * (site.pitchD / 2 + 0.18), back = front + side * 1.55;
    solids.begin('goal', 'goal-' + (side < 0 ? 'n' : 's'), 0.3);
    [-1, 1].forEach((post) => { box(post * 2.5, front, 0.16, 0.16, 2.95, 2.6, chalk); box(post * 2.5, back, 0.1, 0.1, 2.95, 2.6, chalk); box(post * 2.5, (front + back) / 2, 0.12, 1.55, 2.95, 0.12, chalk); });
    box(0, front, 5.16, 0.16, 2.95, 0.16, chalk);
    for (let netX = -2.5; netX <= 2.51; netX += 0.5) box(netX, back, 0.025, 0.025, 2.89, 2.5, chalk);
    for (let netY = 0.4; netY < 2.95; netY += 0.42) box(0, back, 5, 0.025, netY, 0.025, chalk);
    solids.end();
  });
  solids.begin('bleachers', 'bleachers', 0.3);
  for (let step = 0; step < 3; step++) { box(-19.65 + step * 0.64, 0, 0.64, 11.6, 1.7 - step * 0.48, 1.43 - step * 0.48, kit.pavement); box(-19.65 + step * 0.64, 0, 0.58, 11.4, 1.77 - step * 0.48, 0.07, kit.stone); }
  solids.end();
  env.walkable.push({ kind: 'sports-track', x: site.x, z: site.z, w: 2 * (radius + 0.65), d: 2 * (radius + 0.65 + site.trackHalfStraight), y: 0.33 });
}

// A BufferGeometry from upstream's packed module arrays (position, normal, colour; non-indexed).
export function moduleGeometry(T, data) {
  const g = new T.BufferGeometry();
  g.setAttribute('position', new T.Float32BufferAttribute(Array.from(data.position), 3));
  g.setAttribute('normal', new T.Float32BufferAttribute(Array.from(data.normal), 3));
  if (data.color) g.setAttribute('color', new T.Float32BufferAttribute(Array.from(data.color), 3));
  if (data.index) g.setIndex(Array.from(data.index));
  return g;
}
// Non-indexed points with flat normals (upstream `Ca`: computeVertexNormals on a non-indexed geometry).
export function flatGeometry(T, pts) {
  const g = new T.BufferGeometry();
  g.setAttribute('position', new T.Float32BufferAttribute(pts, 3));
  g.computeVertexNormals(); return g;
}
void quatMul;
