// Bold pictogram signs (Lantern Lane; replaces upstream's Chinese-only sign atlases, design section 0).
//
// No text: every sign is a pictogram built from filled shapes with thick strokes (stroke >= 0.08 of the
// icon, about 0.1 m on a 1.3 m plate), on a high-contrast plate with a dark rim, sized for reading at
// 10-15 m from the follow camera (lantern pilot: broad silhouettes read, thin lines fail). Geometry, not a
// texture: flat triangles in COLOR_0, material tt_sign (a soft emission at night), so a sign stays crisp at
// any distance and needs no texture import.
//
// Placement (all derived from data, never hand-placed):
//   - a totem (post + double-sided plate, centre 2.6 m) beside every building's street door (town.json
//     `doors[0]`), every annex door, the station, the parks and the sports ground;
//   - plates on upstream's own sign boards: the station name board (bus + taxi), the bus stop signs and
//     shelter boards, the taxi rank board, every market stall's name board, the street office board, the
//     amusement park gate beam and the plaza monument plaque;
//   - ink-only bus and taxi pictograms painted in the station bays (upstream's BUS / TAXI legends).
import { lin, overlaps } from './world_core.mjs';

// ---- the icon set: shapes in a unit square (-0.5..0.5), layer 1 = ink, 2 = cut-out (plate colour), 3 = ink
const TAU = Math.PI * 2;
const circlePts = (cx, cy, r, n = 28, a0 = 0, a1 = TAU) => { const p = []; const full = Math.abs(a1 - a0 - TAU) < 1e-9; const k = full ? n : n + 1; for (let i = 0; i < k; i++) { const a = a0 + (a1 - a0) * i / n; p.push([cx + Math.cos(a) * r, cy + Math.sin(a) * r]); } return p; };
const rect = (x0, y0, x1, y1, layer = 1) => ({ layer, pts: [[x0, y0], [x1, y0], [x1, y1], [x0, y1]] });
const poly = (pts, layer = 1) => ({ layer, pts });
const circle = (cx, cy, r, layer = 1) => ({ layer, pts: circlePts(cx, cy, r) });
const sector = (cx, cy, r, a0, a1, layer = 1) => ({ layer, pts: [[cx, cy], ...circlePts(cx, cy, r, 20, a0, a1)] });
const arc = (cx, cy, r0, r1, a0, a1, layer = 1) => { const o = circlePts(cx, cy, r1, 20, a0, a1), i = circlePts(cx, cy, r0, 20, a0, a1).reverse(); return { layer, pts: o.concat(i) }; };
const ring = (cx, cy, r0, r1, layer = 1) => ({ layer, pts: circlePts(cx, cy, r1, 32), hole: circlePts(cx, cy, r0, 32).reverse() });
const line = (x0, y0, x1, y1, w, layer = 1) => { const dx = x1 - x0, dy = y1 - y0, l = Math.hypot(dx, dy), nx = -dy / l * w / 2, ny = dx / l * w / 2; return { layer, pts: [[x0 + nx, y0 + ny], [x0 - nx, y0 - ny], [x1 - nx, y1 - ny], [x1 + nx, y1 + ny]] }; };
const round = (x0, y0, x1, y1, r, layer = 1) => { const p = []; [[x1 - r, y0 + r, -Math.PI / 2], [x1 - r, y1 - r, 0], [x0 + r, y1 - r, Math.PI / 2], [x0 + r, y0 + r, Math.PI]].forEach(([cx, cy, a]) => { for (let i = 0; i <= 6; i++) { const t = a + i * Math.PI / 12; p.push([cx + Math.cos(t) * r, cy + Math.sin(t) * r]); } }); return { layer, pts: p }; };
const star = (cx, cy, r, layer = 2) => { const p = []; for (let i = 0; i < 10; i++) { const a = Math.PI / 2 + i * Math.PI / 5, rr = i % 2 ? r * 0.42 : r; p.push([cx + Math.cos(a) * rr, cy + Math.sin(a) * rr]); } return { layer, pts: p }; };

export const ICONS = {
  bus: [round(-0.36, -0.3, 0.36, 0.4, 0.09), rect(-0.27, 0.05, 0.27, 0.3, 2), circle(-0.19, -0.17, 0.065, 2), circle(0.19, -0.17, 0.065, 2), rect(-0.31, -0.42, -0.15, -0.28), rect(0.15, -0.42, 0.31, -0.28)],
  taxi: [round(-0.4, -0.22, 0.4, 0.08, 0.07), poly([[-0.27, 0.06], [0.27, 0.06], [0.19, 0.3], [-0.19, 0.3]]), rect(-0.11, 0.3, 0.11, 0.42), poly([[-0.2, 0.09], [0.2, 0.09], [0.15, 0.25], [-0.15, 0.25]], 2), circle(-0.26, -0.08, 0.055, 2), circle(0.26, -0.08, 0.055, 2), rect(-0.34, -0.36, -0.18, -0.2), rect(0.18, -0.36, 0.34, -0.2)],
  cross: [rect(-0.13, -0.38, 0.13, 0.38), rect(-0.38, -0.13, 0.38, 0.13)],
  // A schoolhouse with a clock tower (the tower and clock set it apart from the housing pictogram).
  school: [rect(-0.44, -0.4, 0.44, 0.02), rect(-0.15, 0.02, 0.15, 0.27), poly([[-0.21, 0.26], [0.21, 0.26], [0, 0.44]]), circle(0, 0.13, 0.075, 2),
    rect(-0.08, -0.4, 0.08, -0.14, 2), rect(-0.34, -0.22, -0.2, -0.08, 2), rect(0.2, -0.22, 0.34, -0.08, 2)],
  university: [poly([[-0.44, 0.14], [0, 0.34], [0.44, 0.14], [0, -0.06]]), poly([[-0.25, 0.02], [0.25, 0.02], [0.25, -0.2], [0, -0.3], [-0.25, -0.2]]), line(0.34, 0.15, 0.34, -0.2, 0.06), circle(0.34, -0.23, 0.06)],
  book: [poly([[-0.44, -0.28], [-0.03, -0.36], [-0.03, 0.26], [-0.44, 0.34]]), poly([[0.03, -0.36], [0.44, -0.28], [0.44, 0.34], [0.03, 0.26]]), line(-0.36, 0.12, -0.11, 0.07, 0.05, 2), line(-0.36, -0.04, -0.11, -0.09, 0.05, 2), line(0.11, 0.07, 0.36, 0.12, 0.05, 2), line(0.11, -0.09, 0.36, -0.04, 0.05, 2)],
  wrench: [line(-0.3, -0.3, 0.12, 0.12, 0.15), circle(0.2, 0.2, 0.19), circle(0.31, 0.31, 0.11, 2), circle(-0.3, -0.3, 0.08)],
  truck: [rect(-0.44, -0.18, 0.1, 0.28), poly([[0.13, -0.18], [0.44, -0.18], [0.44, 0.04], [0.33, 0.18], [0.13, 0.18]]), rect(0.19, 0.0, 0.33, 0.12, 2), circle(-0.27, -0.25, 0.11), circle(0.28, -0.25, 0.11), circle(-0.27, -0.25, 0.04, 2), circle(0.28, -0.25, 0.04, 2)],
  apple: [circle(-0.09, -0.06, 0.27), circle(0.09, -0.06, 0.27), line(0, 0.16, 0.05, 0.38, 0.06), poly([[0.06, 0.3], [0.2, 0.39], [0.32, 0.32], [0.16, 0.25]])],
  bag: [poly([[-0.32, -0.38], [0.32, -0.38], [0.27, 0.16], [-0.27, 0.16]]), arc(0, 0.16, 0.11, 0.18, 0, Math.PI)],
  shield: [poly([[-0.33, 0.36], [0.33, 0.36], [0.33, 0.02], [0, -0.4], [-0.33, 0.02]]), star(0, 0.04, 0.17)],
  bank: [poly([[-0.42, 0.16], [0.42, 0.16], [0, 0.4]]), rect(-0.42, -0.4, 0.42, -0.29), rect(-0.39, 0.1, 0.39, 0.17), rect(-0.325, -0.29, -0.215, 0.1), rect(-0.145, -0.29, -0.035, 0.1), rect(0.035, -0.29, 0.145, 0.1), rect(0.215, -0.29, 0.325, 0.1)],
  briefcase: [round(-0.4, -0.32, 0.4, 0.18, 0.06), arc(0, 0.18, 0.1, 0.17, 0, Math.PI), rect(-0.4, -0.08, 0.4, -0.03, 2), rect(-0.06, -0.12, 0.06, 0.01)],
  home: [rect(-0.3, -0.38, 0.3, 0.06), poly([[-0.44, 0.02], [0.44, 0.02], [0, 0.4]]), rect(0.17, 0.16, 0.28, 0.38), rect(-0.08, -0.38, 0.08, -0.08, 2), rect(-0.24, -0.16, -0.14, -0.04, 2)],
  bin: [poly([[-0.26, -0.4], [0.26, -0.4], [0.31, 0.17], [-0.31, 0.17]]), rect(-0.36, 0.2, 0.36, 0.29), rect(-0.09, 0.29, 0.09, 0.36), rect(-0.14, -0.3, -0.07, 0.08, 2), rect(0.07, -0.3, 0.14, 0.08, 2)],
  flag: [rect(-0.32, -0.42, -0.24, 0.4), poly([[-0.24, 0.38], [0.38, 0.26], [-0.24, 0.1]]), rect(-0.42, -0.42, -0.14, -0.34)],
  tree: [circle(0, 0.13, 0.25), circle(-0.17, -0.01, 0.17), circle(0.17, -0.01, 0.17), rect(-0.055, -0.4, 0.055, -0.08)],
  wheel: [ring(0, 0.1, 0.23, 0.31), line(-0.3, 0.1, 0.3, 0.1, 0.05), line(0, -0.2, 0, 0.4, 0.05), line(-0.21, -0.11, 0.21, 0.31, 0.05), line(-0.21, 0.31, 0.21, -0.11, 0.05), circle(0, 0.1, 0.07), line(0, 0.1, -0.24, -0.42, 0.07), line(0, 0.1, 0.24, -0.42, 0.07)],
  fountain: [poly([[-0.4, -0.18], [0.4, -0.18], [0.32, -0.38], [-0.32, -0.38]]), line(0, -0.18, 0, 0.32, 0.08), arc(-0.16, -0.02, 0.1, 0.17, 0, Math.PI), arc(0.16, -0.02, 0.1, 0.17, 0, Math.PI), circle(0, 0.36, 0.06)],
  ball: [ring(0, 0, 0.3, 0.38), poly(circlePts(0, 0, 0.13, 5, Math.PI / 2, Math.PI / 2 + TAU).slice(0, 5)), line(0, 0.13, 0, 0.3, 0.05), line(-0.12, 0.04, -0.28, 0.1, 0.05), line(0.12, 0.04, 0.28, 0.1, 0.05), line(-0.08, -0.1, -0.17, -0.25, 0.05), line(0.08, -0.1, 0.17, -0.25, 0.05)],
  skewer: [line(-0.38, -0.38, 0.36, 0.36, 0.06), circle(-0.15, -0.15, 0.12), circle(0.03, 0.03, 0.12), circle(0.21, 0.21, 0.12)],
  hotpot: [poly([[-0.33, 0.0], [0.33, 0.0], [0.27, -0.33], [-0.27, -0.33]]), rect(-0.4, 0.0, 0.4, 0.07), rect(-0.46, -0.1, -0.33, -0.03), rect(0.33, -0.1, 0.46, -0.03), line(-0.15, 0.13, -0.15, 0.38, 0.06), line(0, 0.13, 0, 0.4, 0.06), line(0.15, 0.13, 0.15, 0.38, 0.06)],
  pan: [circle(-0.09, 0, 0.29), line(0.16, 0, 0.46, 0, 0.1), circle(-0.09, 0, 0.17, 2), circle(-0.09, 0, 0.07, 3)],
  dessert: [sector(0, -0.04, 0.36, Math.PI, TAU), circle(-0.12, 0.06, 0.15), circle(0.12, 0.06, 0.15), circle(0, 0.2, 0.14)],
  cup: [poly([[-0.21, 0.2], [0.21, 0.2], [0.15, -0.4], [-0.15, -0.4]]), line(0.05, 0.2, 0.2, 0.43, 0.06), rect(-0.19, -0.02, 0.19, 0.05, 2)],
  bowl: [sector(0, -0.06, 0.34, Math.PI, TAU), rect(-0.4, -0.06, 0.4, 0.0), line(-0.04, 0.02, 0.3, 0.42, 0.05), line(0.08, 0.0, 0.42, 0.34, 0.05)],
};

// Plate colours by category (sRGB): plate, ink, rim. All pairs exceed a 4.5:1 contrast ratio.
export const CATEGORY = {
  transit: ['#1b7f4b', '#ffffff', '#1e2a2a'], health: ['#ffffff', '#d62839', '#1e2a2a'], education: ['#1d4e89', '#ffffff', '#f5f1e6'],
  shopping: ['#a4167f', '#ffffff', '#f5f1e6'], food: ['#c2410c', '#ffffff', '#1e2a2a'], civic: ['#243b6b', '#ffffff', '#f5f1e6'],
  leisure: ['#087e8b', '#ffffff', '#f5f1e6'], housing: ['#7f5539', '#ffffff', '#f5f1e6'], work: ['#3d4a52', '#ffffff', '#f5f1e6'],
  recycling: ['#237032', '#ffffff', '#f5f1e6'],
};
const PROGRAMME_ICON = {
  primary: ['school', 'education'], secondary: ['school', 'education'], university: ['university', 'education'], library: ['book', 'education'],
  hospital: ['cross', 'health'], clinic: ['cross', 'health'], mall: ['bag', 'shopping'], 'annex-mall': ['bag', 'shopping'],
  market: ['apple', 'food'], workshop: ['wrench', 'work'], depot: ['truck', 'work'], office: ['briefcase', 'work'],
  courtyard: ['home', 'housing'], slab: ['home', 'housing'], terrace: ['home', 'housing'], point: ['home', 'housing'],
  precinct: ['shield', 'civic'], bank: ['bank', 'civic'], waste: ['bin', 'recycling'], civic: ['flag', 'civic'],
  station: ['bus', 'transit'], bus: ['bus', 'transit'], taxi: ['taxi', 'transit'], park: ['tree', 'leisure'], sports: ['ball', 'leisure'],
  amusement: ['wheel', 'leisure'], plaza: ['fountain', 'leisure'],
  grill: ['skewer', 'food'], hotpot: ['hotpot', 'food'], griddle: ['pan', 'food'], dessert: ['dessert', 'food'], juice: ['cup', 'food'], deli: ['bowl', 'food'],
};
export { PROGRAMME_ICON };

export function buildSigns(env) {
  const { T, city, town, file, makeChunked, solids, counts, world } = env;
  const em = makeChunked('Signs');
  const out = [];
  // Triangulated shape -> world triangles. `frame`: centre c, right r, up u, normal n (unit vectors).
  const tri = (pts, hole) => {
    const contour = pts.map((p) => new T.Vector2(p[0], p[1])), holes = hole ? [hole.map((p) => new T.Vector2(p[0], p[1]))] : [];
    if (T.ShapeUtils.isClockWise(contour)) contour.reverse();
    holes.forEach((h) => { if (!T.ShapeUtils.isClockWise(h)) h.reverse(); });
    const all = contour.concat(...holes), faces = T.ShapeUtils.triangulateShape(contour, holes), outT = [];
    faces.forEach((f) => {
      const [a, b, c] = f.map((i) => all[i]);
      const area = (b.x - a.x) * (c.y - a.y) - (c.x - a.x) * (b.y - a.y);
      outT.push(area >= 0 ? [a, b, c] : [a, c, b]);
    });
    return outT;
  };
  const face = (frame, size, shapes, colours, offset0, mirror) => {
    shapes.forEach((s) => {
      const col = lin(s.layer === 2 ? colours[0] : colours[1]);
      const lift = offset0 + s.layer * 0.02;
      tri(s.pts, s.hole).forEach((t) => {
        const P = t.map((v) => {
          const u = (mirror ? -v.x : v.x) * size, w = v.y * size;
          return [frame.c[0] + frame.r[0] * u + frame.u[0] * w + frame.n[0] * lift, frame.c[1] + frame.r[1] * u + frame.u[1] * w + frame.n[1] * lift, frame.c[2] + frame.r[2] * u + frame.u[2] * w + frame.n[2] * lift];
        });
        em.triangles('tt_sign', mirror ? [P[0], P[2], P[1]] : P, col);
      });
    });
  };
  // A plate: a rim slab (thin box), then the plate face and the icon on one or both sides.
  const plate = (c, n, size, icon, category, opts) => {
    opts = opts || {};
    const [plateHex, inkHex, rimHex] = CATEGORY[category];
    const N = [n[0], 0, n[1]], R = [n[1], 0, -n[0]], U = [0, 1, 0];
    const yaw = Math.atan2(n[0], n[1]);
    const depth = opts.depth || 0.08;
    em.box('tt_sign', c[0], c[1], c[2], size * 1.12, size * 1.12, depth, lin(rimHex), [0, Math.sin(yaw / 2), 0, Math.cos(yaw / 2)], { keepBottom: true });
    const sides = opts.single ? [1] : [1, -1];
    sides.forEach((s) => {
      const frame = { c, r: R.map((v) => v * s), u: U, n: N.map((v) => v * s) };
      face(frame, size, [round(-0.5, -0.5, 0.5, 0.5, 0.12, 0)], [plateHex, plateHex], depth / 2 + 0.01, false);
      face(frame, size * 0.8, ICONS[icon], [plateHex, inkHex], depth / 2 + 0.01, false);
    });
    out.push({ kind: opts.kind || 'plate', icon, category, x_m: c[0] * 0.5, y_m: c[1] * 0.5, z_m: c[2] * 0.5, facing: [n[0], n[1]], size_m: size * 0.5,
      double_sided: !opts.single, target: opts.target || null });
  };
  // Ink-only paint on the ground (station bays): `fwd` is the icon's up direction on the ground.
  const paint = (c, fwd, size, icon, hex, target) => {
    const frame = { c, r: [-fwd[1], 0, fwd[0]], u: [fwd[0], 0, fwd[1]], n: [0, 1, 0] };
    face(frame, size, ICONS[icon].filter((s) => s.layer !== 2), [hex, hex], 0, false);
    out.push({ kind: 'ground-paint', icon, category: 'transit', x_m: c[0] * 0.5, y_m: c[1] * 0.5, z_m: c[2] * 0.5, facing: [0, 1], size_m: size * 0.5, double_sided: false, target });
  };
  // ---- totems beside the street doors, placed clear of every solid and off the roads.
  const blocked = (x, z, r) => {
    const probe = { x, z, w: 2 * r, d: 2 * r };
    if (city.roads.some((rd) => overlaps(probe, rd, 0.2))) return true;
    if (overlaps(probe, city.water, 0.5)) return true;
    return solids.items.some((s) => {
      if (s.rect) return overlaps(probe, s.rect, 0.3);
      const xs = s.poly.map((p) => p[0]), zs = s.poly.map((p) => p[1]);
      return overlaps(probe, { x: (Math.min(...xs) + Math.max(...xs)) / 2, z: (Math.min(...zs) + Math.max(...zs)) / 2, w: Math.max(...xs) - Math.min(...xs), d: Math.max(...zs) - Math.min(...zs) }, 0.3);
    });
  };
  const TOTEM_PLATE = 2.6, TOTEM_CENTRE = 5.2; // units: a 1.3 m plate centred 2.6 m up
  const totem = (door, icon, category, target) => {
    // town.json doors are in metres and stand 0.5 m outside the wall or opening.
    const dx = door.x * 2, dz = door.z * 2, f = door.facing, side = [f[1], -f[0]];
    const half = (door.width ? door.width * 2 : 4) / 2;
    const tries = [];
    for (const out2 of [1.2, 2.4, 0.6, 3.6]) for (const lateral of [half + 1.6, -(half + 1.6), half + 3.2, -(half + 3.2)]) tries.push([out2, lateral]);
    for (const [o, l] of tries) {
      const x = dx + f[0] * o + side[0] * l, z = dz + f[1] * o + side[1] * l;
      if (blocked(x, z, 0.8)) continue;
      solids.begin('sign', 'sign-' + target, 0.25);
      em.box('tt_metal', x, 0.25 + (TOTEM_CENTRE - TOTEM_PLATE / 2) / 2, z, 0.24, TOTEM_CENTRE - TOTEM_PLATE / 2 - 0.25 + 0.2, 0.24, lin('#3d4a52'));
      solids.end();
      plate([x, TOTEM_CENTRE, z], f, TOTEM_PLATE, icon, category, { kind: 'totem', target });
      return true;
    }
    return false;
  };
  // Fallback where no clear totem spot exists: a single-sided plate on the facade above the door (the door
  // stands 0.5 m outside its wall, so the plate sits 0.42 m behind that point), centred 0.75 m over the
  // 2.1 m door on the 0.7 m building floor.
  const wallPlate = (door, icon, category, target) => {
    const f = door.facing, x = door.x * 2 - f[0] * 0.84, z = door.z * 2 - f[1] * 0.84;
    plate([x, 1.4 + 4.2 + 1.5, z], f, 2.2, icon, category, { kind: 'wall', single: true, target });
    return true;
  };
  let missed = [];
  const iconFor = (programme) => PROGRAMME_ICON[programme] || ['flag', 'civic'];
  town.buildings.forEach((b) => {
    const [icon, cat] = iconFor(b.programme);
    const door = b.doors && b.doors[0];
    if (!door || !(totem(door, icon, cat, b.id) || wallPlate(door, icon, cat, b.id))) missed.push(b.id);
  });
  town.annexes.forEach((a) => {
    const [icon, cat] = iconFor(a.facility);
    const door = (a.doors && a.doors[0]) || null;
    if (!door || !(totem(door, icon, cat, a.id) || wallPlate(door, icon, cat, a.id))) missed.push(a.id);
  });
  // The station: totem at the arrival forecourt, pictograms on the name board, bay paint.
  const st = town.places.station;
  // The station's own totem faces east, toward the street the player arrives and leaves by.
  if (!totem({ x: st.arrival.x, z: st.arrival.z, facing: st.arrival.facing, width: 1 }, 'bus', 'transit', 'station')) missed.push('station');
  (env.stationSigns.board || []).forEach((bd, i) => [-1, 1].forEach((k) => {
    const r = [bd.facing[1], -bd.facing[0]];
    plate([bd.x + r[0] * k * 4, bd.y, bd.z + r[1] * k * 4], bd.facing, 2.4, k < 0 ? 'bus' : 'taxi', 'transit', { kind: 'board', single: true, target: 'station-board-' + i });
  }));
  (env.stationSigns.bays || []).forEach((bay, i) => paint([bay.x, bay.y, bay.z], [-Math.sin(bay.yaw), Math.cos(bay.yaw) * -1], Math.min(bay.w, bay.h) * 0.9, bay.kind, '#f3edd8', 'station-bay-' + i));
  // Bus stops: upstream's own boards (bus-sign boards, shelter sign boxes); taxi rank board.
  // Plates straddle upstream's boards: the plate slab is as deep as the board plus a margin, so the two
  // faces sit just outside it.
  (env.busSigns || []).forEach((s, i) => plate([s.x, 2.325, s.z + s.facing * 0.3], [0, s.facing], 1.2, 'bus', 'transit', { kind: 'stop', depth: 0.17, target: s.stop || 'bus-sign-' + i }));
  (env.shelters || []).forEach((s, i) => plate([s.sign.x, s.sign.y, s.sign.z], [0, s.facing], 1.1, 'bus', 'transit', { kind: 'stop', depth: 0.28, target: 'bus-shelter-' + i }));
  if (env.taxiSign) plate([env.taxiSign.x, 2.69, env.taxiSign.z], env.taxiSign.facing, 1.6, 'taxi', 'transit', { kind: 'stop', depth: 1.8, target: 'taxi-rank' });
  // Market stalls: a food plate on each name board, facing the river walk.
  (env.stallSigns || []).forEach((s) => { const [icon, cat] = iconFor(s.type); plate([s.x - s.side * 0.12, s.y, s.z], [-s.side, 0], 1.8, icon, cat, { kind: 'stall', target: s.id }); });
  if (env.officeSign) plate([env.officeSign.x + env.officeSign.facing[0] * 0.1, env.officeSign.y + 1.6, env.officeSign.z], env.officeSign.facing, 2.0, 'flag', 'civic', { kind: 'board', target: 'c-civic' });
  if (env.amusementSign) plate([env.amusementSign.x, 4.77 + 0.31 + 1.45, env.amusementSign.z - 0.4], [0, 1], 2.6, 'wheel', 'leisure', { kind: 'gate', target: 'amusement' });
  if (env.plazaSign) plate([env.plazaSign.x, env.plazaSign.y, env.plazaSign.z + 0.08], [0, 1], 1.4, 'fountain', 'leisure', { kind: 'plaque', single: true, target: 'plaza' });
  // Parks and the sports ground: a totem at the lawn edge facing the nearest cross street.
  city.parks.forEach((p, i) => {
    const road = city.roads.filter((r) => r.axis === 'x').sort((a, b) => Math.abs(a.z - p.z) - Math.abs(b.z - p.z))[0];
    const s = Math.sign(road.z - p.z) || 1;
    const door = { x: (p.x + 8) * 0.5, z: (p.z + s * (p.d / 2 - 2.5)) * 0.5, facing: [0, s], width: 1 };
    const [icon, cat] = iconFor(p.use === 'sports' ? 'sports' : 'park');
    if (!totem(door, icon, cat, p.use === 'sports' ? 'sports' : 'park-' + i)) missed.push('park-' + i);
  });
  world.signs = out;
  counts.signs = out.length;
  counts.sign_totems = out.filter((s) => s.kind === 'totem').length;
  counts.signs_unplaced = missed;
}
