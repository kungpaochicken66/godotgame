// The Lantern Lane children on the page (design/city-threejs.md 6.4): the player's and friends', drawn from
// Godot's own rigs (art/kid.gd) and posed every frame as Godot poses them. Godot's side is
// scripts/web/web_city_bridge.gd; its header defines the pose format:
//   kid_model {id, rev, nick, pack, bin, pose_nodes, vis_count, vis_bits}: the rig as a mesh pack (its root
//     packed at identity), the pack indices of the posed pivots, and how many nodes the visibility bits cover;
//   frame.kids[] {id, me, rev, xf, anim, ride, level, pose: {x: 12 floats per pose node (local transform),
//     v: visibility bits of every packed node, vis_bits per number}}.
// The child's place (xf) is interpolated between frame messages (the page and Godot run at their own rates).
// A rider is re-seated in the gondola the page draws (app.world.riderTransform at app.world.ferrisAngleNow()),
// so a paused page keeps riders in their drawn gondolas. A child Godot hides, or whose level is a storey the
// cutaway hides, is not drawn. Without a model (the harness sends none) a simple stand-in is drawn.
// Every child has its own materials (pack roles "m<k>" mean different things in different packs).
import { buildPack, base64ToBuffer, matrixFrom12 } from './meshpack.js';

const SNAP_DIST = 4.0;        // m: a jump further than this (a journey, a seat) is not interpolated
const MIN_SPAN = 1 / 240;     // s: interpolation span bounds (the measured message interval, smoothed)
const MAX_SPAN = 0.25;

export async function init(app) {
  const THREE = app.THREE;
  const root = new THREE.Group();
  root.name = 'Kids';
  app.scene.add(root);
  const kids = new Map();      // id -> record
  let regions = new Set();     // the cutaway's hidden regions
  let span = 1 / 60;           // the smoothed interval between frame messages
  let lastFrameAt = -1;
  const tmpM = new THREE.Matrix4();
  const tmpP = new THREE.Vector3();
  const tmpQ = new THREE.Quaternion();
  const tmpS = new THREE.Vector3();
  const tmp12 = new Array(12).fill(0);
  let standinGeo = null;

  function now() { return performance.now() / 1000; }

  function record(id) {
    let k = kids.get(id);
    if (!k) {
      const group = new THREE.Group();
      group.name = `Kid${id}`;
      group.visible = false;
      root.add(group);
      k = {
        id, group, me: false, rev: -1, model: null, standin: null, anim: 'idle', ride: null, level: '', vis: true,
        from: { p: new THREE.Vector3(), q: new THREE.Quaternion() }, to: { p: new THREE.Vector3(), q: new THREE.Quaternion() },
        scale: new THREE.Vector3(1, 1, 1), t: 0, placed: false, seen: 0, poseWarned: false, t0: Math.random() * 10,
      };
      kids.set(id, k);
    }
    return k;
  }

  function disposeTree(obj) {
    obj.traverse((o) => {
      if (o.geometry) o.geometry.dispose();
      const mats = Array.isArray(o.material) ? o.material : (o.material ? [o.material] : []);
      for (const m of mats) {
        if (m.map) m.map.dispose();
        m.dispose();
      }
    });
  }

  function dropModel(k) {
    if (k.model) {
      k.group.remove(k.model.root);
      disposeTree(k.model.root);
      k.model = null;
    }
  }

  function dropStandin(k) {
    if (k.standin) {
      k.group.remove(k.standin.root);
      for (const m of k.standin.materials) m.dispose();
      k.standin = null;
    }
  }

  function remove(id) {
    const k = kids.get(id);
    if (!k) return;
    dropModel(k);
    dropStandin(k);
    if (k.tag) k.tag.remove();
    root.remove(k.group);
    kids.delete(id);
  }

  /** A simple child shape for one without a model: body, head, two legs (shared geometry, own colours). */
  function makeStandin(k) {
    if (!standinGeo) {
      standinGeo = {
        body: new THREE.CapsuleGeometry(0.19, 0.3, 4, 12),
        head: new THREE.SphereGeometry(0.3, 16, 12),
        leg: new THREE.CapsuleGeometry(0.075, 0.3, 4, 8),
        shadow: new THREE.CircleGeometry(0.4, 20),
      };
    }
    const hue = ((k.id * 0.618034) % 1 + 1) % 1;
    const cloth = new THREE.MeshStandardMaterial({ color: new THREE.Color().setHSL(hue, 0.55, 0.6), roughness: 0.9 });
    const skin = new THREE.MeshStandardMaterial({ color: new THREE.Color().setRGB(0.98, 0.84, 0.72, THREE.SRGBColorSpace), roughness: 0.9 });
    const shade = new THREE.MeshBasicMaterial({ color: 0x2e4020, transparent: true, opacity: 0.22, depthWrite: false });
    const r = new THREE.Group();
    r.name = 'StandIn';
    const body = new THREE.Group();
    r.add(body);
    const torso = new THREE.Mesh(standinGeo.body, cloth);
    torso.position.y = 0.55;
    body.add(torso);
    const head = new THREE.Mesh(standinGeo.head, skin);
    head.position.y = 1.0;
    body.add(head);
    const legs = [-1, 1].map((s) => {
      const pivot = new THREE.Group();
      pivot.position.set(s * 0.095, 0.36, 0);
      const leg = new THREE.Mesh(standinGeo.leg, skin);
      leg.position.y = -0.17;
      pivot.add(leg);
      body.add(pivot);
      return pivot;
    });
    const shadow = new THREE.Mesh(standinGeo.shadow, shade);
    shadow.rotation.x = -Math.PI / 2;
    shadow.position.y = 0.015;
    r.add(shadow);
    k.group.add(r);
    k.standin = { root: r, body, legs, materials: [cloth, skin, shade] };
  }

  function setModel(msg) {
    const k = record(msg.id);
    if (!msg.pack || !msg.bin) return;
    let built;
    try {
      built = buildPack(msg.pack, base64ToBuffer(msg.bin), {});   // its own materials: nothing shared
    } catch (e) {
      app.send({ t: 'log', level: 'error', text: `kids: model of ${msg.id} not built: ${e}` });
      return;
    }
    dropModel(k);
    dropStandin(k);
    const objects = [];
    built.root.traverse((o) => { if (o.userData && o.userData.packIndex !== undefined) objects[o.userData.packIndex] = o; });
    built.root.position.set(0, 0, 0);
    built.root.quaternion.identity();
    built.root.scale.set(1, 1, 1);
    k.model = {
      root: built.root, objects, poseNodes: msg.pose_nodes || [], visCount: msg.vis_count || objects.length,
      visBits: msg.vis_bits || 30, nick: msg.nick || '', label: msg.label || msg.nick || '',
    };
    setTag(k, k.model.label);
    k.rev = msg.rev;
    k.poseWarned = false;
    k.group.add(built.root);
  }

  function setPlace(k, xf) {
    matrixFrom12(xf, tmpM);
    tmpM.decompose(tmpP, tmpQ, tmpS);
    k.scale.copy(tmpS);
    if (!k.placed || tmpP.distanceTo(k.to.p) > SNAP_DIST) {
      k.from.p.copy(tmpP); k.from.q.copy(tmpQ);
      k.to.p.copy(tmpP); k.to.q.copy(tmpQ);
      k.group.position.copy(tmpP);
      k.group.quaternion.copy(tmpQ);
      k.placed = true;
      k.t = 1;
      return;
    }
    k.from.p.copy(k.group.position);
    k.from.q.copy(k.group.quaternion);
    k.to.p.copy(tmpP);
    k.to.q.copy(tmpQ);
    k.t = 0;
  }

  function applyPose(k, pose) {
    const m = k.model;
    if (!m || !pose) return;
    const x = pose.x || [];
    if (x.length !== m.poseNodes.length * 12) {
      if (!k.poseWarned) {
        k.poseWarned = true;
        app.send({ t: 'log', level: 'warn', text: `kids: pose of ${k.id} has ${x.length} numbers, model wants ${m.poseNodes.length * 12}` });
      }
    } else {
      for (let j = 0; j < m.poseNodes.length; j++) {
        const o = m.objects[m.poseNodes[j]];
        if (!o) continue;
        for (let i = 0; i < 12; i++) tmp12[i] = x[j * 12 + i];
        matrixFrom12(tmp12, tmpM);
        tmpM.decompose(o.position, o.quaternion, o.scale);
      }
    }
    const v = pose.v;
    if (Array.isArray(v)) {
      const bits = m.visBits;
      for (let i = 1; i < m.objects.length; i++) {   // the root's bit is the child's own visibility (k.vis)
        const o = m.objects[i];
        const w = v[Math.floor(i / bits)];
        if (o && w !== undefined) o.visible = ((w >>> (i % bits)) & 1) === 1;
      }
      const w0 = v[0];
      k.vis = w0 === undefined ? true : (w0 & 1) === 1;
    }
  }

  function onFrame(msg) {
    const t = now();
    if (lastFrameAt >= 0) {
      const d = Math.min(MAX_SPAN, Math.max(MIN_SPAN, t - lastFrameAt));
      span = span * 0.8 + d * 0.2;
    }
    lastFrameAt = t;
    const seen = new Set();
    for (const e of msg.kids || []) {
      const k = record(e.id);
      seen.add(e.id);
      k.me = !!e.me;
      k.anim = e.anim || 'idle';
      k.ride = e.ride || null;
      k.level = e.level || '';
      k.seen = t;
      if (Array.isArray(e.xf) && e.xf.length >= 12) setPlace(k, e.xf);
      if (e.pose) applyPose(k, e.pose);
      else if (!k.model) k.vis = true;
    }
    for (const id of [...kids.keys()]) {
      if (!seen.has(id)) remove(id);   // no longer in this city (kid_gone also says so)
    }
  }

  function riderPlace(k) {
    const w = app.world;
    if (!k.ride || !w || typeof w.riderTransform !== 'function' || typeof w.ferrisAngleNow !== 'function') return false;
    const r = w.riderTransform(k.ride.g, w.ferrisAngleNow(), k.ride.slot);
    if (!r) return false;
    if (r.isMatrix4) {
      r.decompose(k.group.position, k.group.quaternion, tmpS);
    } else if (Array.isArray(r) && r.length >= 12) {
      matrixFrom12(r, tmpM).decompose(k.group.position, k.group.quaternion, tmpS);
    } else if (r.position && r.quaternion) {
      k.group.position.copy(r.position);
      k.group.quaternion.copy(r.quaternion);
    } else if (r.isObject3D) {
      r.updateMatrixWorld();
      r.matrixWorld.decompose(k.group.position, k.group.quaternion, tmpS);
    } else {
      return false;
    }
    k.to.p.copy(k.group.position);
    k.to.q.copy(k.group.quaternion);
    k.t = 1;
    return true;
  }

  function animateStandin(k, t) {
    const s = k.standin;
    const walk = k.anim === 'walk';
    const seated = ['sit', 'swing', 'ride', 'rest', 'pedal'].includes(k.anim);
    const sw = Math.sin((t + k.t0) * 9.0);
    s.legs[0].rotation.x = seated ? -1.45 : (walk ? sw * 0.65 : 0);
    s.legs[1].rotation.x = seated ? -1.45 : (walk ? -sw * 0.65 : 0);
    s.body.position.y = walk ? Math.abs(sw) * 0.045 : 0;
  }

  // dest-fix r1: name tags. The Godot city labels every child with its (translated) name; the page had none, so
  // the player's own child was an unnamed figure among the townsfolk. A tag is a screen-space element above the
  // child's head (TAG_LIFT, as Godot's label at 1.62 m plus a margin), the same size at every zoom, drawn only
  // while the child is. The player's own tag is slightly larger.
  const TAG_LIFT = 1.75;
  const tagLayer = document.createElement('div');
  tagLayer.className = 'll-tags';
  tagLayer.style.cssText = 'position:absolute;inset:0;pointer-events:none;overflow:hidden;';
  (document.getElementById('hud') || document.body).appendChild(tagLayer);
  const tagV = new THREE.Vector3();

  function setTag(k, text) {
    if (!k.tag) {
      k.tag = document.createElement('div');
      k.tag.className = 'll-tag';
      k.tag.style.cssText = 'position:absolute;left:0;top:0;white-space:nowrap;font-weight:800;color:#344d40;'
        + 'text-shadow:0 0 3px #fffdf6,0 0 3px #fffdf6,0 0 2px #fffdf6;will-change:transform;display:none;';
      tagLayer.appendChild(k.tag);
    }
    k.tag.textContent = text || '';
  }

  function placeTag(k) {
    if (!k.tag) return;
    const cam = app.camera;
    const show = !!(k.tag.textContent && k.group.visible && cam);
    if (!show) { k.tag.style.display = 'none'; return; }
    tagV.set(k.group.position.x, k.group.position.y + TAG_LIFT * k.scale.y, k.group.position.z).project(cam);
    if (tagV.z > 1 || tagV.z < -1) { k.tag.style.display = 'none'; return; }
    const w = tagLayer.clientWidth || window.innerWidth;
    const h = tagLayer.clientHeight || window.innerHeight;
    const size = k.me ? 19 : 16;
    k.tag.style.fontSize = `calc(${size}px * var(--u, 1))`;
    k.tag.style.display = 'block';
    k.tag.style.transform = `translate(-50%, -100%) translate(${((tagV.x + 1) * 0.5 * w).toFixed(1)}px, ${((1 - tagV.y) * 0.5 * h).toFixed(1)}px)`;
  }

  function update(dt) {
    const t = now();
    for (const k of kids.values()) {
      if (!k.placed) continue;
      if (!riderPlace(k) && k.t < 1) {
        k.t = Math.min(1, k.t + dt / Math.max(span, MIN_SPAN));
        k.group.position.lerpVectors(k.from.p, k.to.p, k.t);
        k.group.quaternion.slerpQuaternions(k.from.q, k.to.q, k.t);
      }
      k.group.scale.copy(k.scale);
      if (!k.model && !k.standin) makeStandin(k);
      if (k.standin) animateStandin(k, t);
      k.group.visible = k.vis && !(k.level && regions.has(k.level));
      placeTag(k);
    }
  }

  function onMessage(msg) {
    switch (msg.t) {
      case 'kid_model': setModel(msg); break;
      case 'kid_gone': remove(msg.id); break;
      case 'frame': onFrame(msg); break;
      case 'cutaway': regions = new Set(msg.regions || []); break;
      case 'bye': for (const id of [...kids.keys()]) remove(id); break;
      default: break;
    }
  }

  if (app.state.frame) onFrame(app.state.frame);   // a frame that came before this module started

  app.kids = {
    root,
    /** The record of a child (or undefined): {id, me, group, model, standin, anim, ride, level, vis, rev}. */
    get: (id) => kids.get(id),
    ids: () => [...kids.keys()],
    /** The local child's drawn (interpolated) position as a THREE.Vector3, or null. */
    mePosition() {
      for (const k of kids.values()) if (k.me && k.placed) return k.group.position.clone();
      return null;
    },
    /** A summary for checks and tools. */
    summary() {
      return [...kids.values()].map((k) => {
        let meshes = 0;
        if (k.model) k.model.root.traverse((o) => { if (o.isMesh) meshes++; });
        return { id: k.id, me: k.me, rev: k.rev, model: !!k.model, standin: !!k.standin, meshes, visible: k.group.visible,
          anim: k.anim, ride: k.ride, level: k.level, pos: k.group.position.toArray(), poseNodes: k.model ? k.model.poseNodes.length : 0 };
      });
    },
  };
  return { update, onMessage };
}
