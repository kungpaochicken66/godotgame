// The city's camera on the page: camera_rig.gd's city behaviour (CityRig, a port of _update_city and every
// city_* function) and play_controller.gd's city input (_city_input, _city_tap, _look_pick, set_city_look,
// set_city_paused, city_look_step), with the pure maths in js/orbit.js (city_orbit.gd).
//
// CityRig has no DOM and no THREE: scripts/web_city/camera.test.mjs replays Godot's recorded rig sequences
// on it (tests/web_city/parity_camera.gd). init(app) wires it to app.camera, the canvas and the bridge, and
// publishes app.cameraRig:
//   target              THREE.Vector3, the camera's focus now (what it looks at)
//   isLooking()         Look is on (taps pick places instead of walking)
//   setLook(on)         Look on / off (off glides back to the strolling view and resumes the city)
//   lookAt(key)         glide in to a CityMap.LOOK_PLACES key (turns Look on)
//   lookOut()           glide back to the overview (Look stays on, as a tap on empty space)
//   lookStep(dir)       the next / previous place of CityMap.LOOK_ORDER while looking
//   reset()             Reset view: a glide back to the strolling view that follows the child (city_reset)
//   ray(cx, cy)         {o: [3], d: [3]}: the camera ray through a client point (Godot's project_ray_origin/normal)
//   isPaused(), setPaused(on), place() (the place looked at, "" when none), gliding(), rotateStep(dir),
//   toggleZoom(), zoomIn(), zoomOut(), rig (the CityRig)
// It fires app.events 'look' and 'pause' (CustomEvent, detail {on}) when they change.
import * as O from './orbit.js';
import { C } from './consts.js';

const CAM_EVERY = 0.1;   // seconds between 'cam' messages (10 a second)
// Godot's Camera3D for the rig (camera_rig.gd _ready): near 0.2, far 220.
const NEAR = 0.2;
const FAR = 220.0;

/** camera_rig.gd's city part. viewSize() returns [w, h] of the view in the units input arrives in. */
export class CityRig {
  constructor(viewSize) {
    this.viewSize = viewSize;
    this.onCity = false;
    this.cityState = {};
    this.cur = O.newPose();          // _city_cur (valid while curOk)
    this.curOk = false;
    this.goal = O.newPose();
    this.look = '';                  // city_look
    this.lookView = null;            // city_look_view (null = {})
    this.glideFrom = O.newPose();    // _glide_from (valid while glideOk)
    this.glideOk = false;
    this.glideT = 0.0;
    this.glideDur = 0.0;
    this.reduceMotion = false;
    this.child = [0, 0, 0];          // target.global_position
    // what the stick and keys walk relative to (_yaw, _distance, _focus)
    this.yaw = 0.0;
    this.distance = 9.5;
    this.focus = [0, 0, 0];
  }

  aspect() {
    const v = this.viewSize();
    return v[0] / Math.max(v[1], 1.0);
  }

  rotateStep(dir) {
    if (this.onCity) {
      this.cityState = O.stepYaw(this.cityState, dir);
      this._snapIfReduced();
    }
  }

  /** The zoom button steps closer, and from the closest level back out to the overview. */
  toggleZoom() {
    if (!this.onCity) return;
    const before = Number(this.cityState.distance);
    // tv-diag r2 (the controller audit): +1 is closer, as Godot's camera_rig.gd toggle_zoom (it used -1 and only zoomed out)
    this.cityState = O.stepZoom(this.cityState, 1, this.aspect());
    if (isEqualApprox(Number(this.cityState.distance), before)) this.cityState = O.reset(this.aspect());
    this._snapIfReduced();
  }

  zoomIn() { if (this.onCity) this.cityStepZoom(1); }

  zoomOut() { if (this.onCity) this.cityStepZoom(-1); }

  _snapIfReduced() {
    if (this.onCity && this.reduceMotion) this.snap();
  }

  /** Arriving in the city: the strolling view that follows the child (dest-fix r1; was the overview). */
  enterCity() {
    this.onCity = true;
    this.cityState = O.stroll(this.aspect());
    this.look = '';
    this.lookView = null;
    this.glideOk = false;
    this.curOk = false;
    this.snap();
  }

  leaveCity() {
    this.onCity = false;
    this.cityState = {};
    this.look = '';
    this.lookView = null;
    this.glideOk = false;
    this.curOk = false;
  }

  /** A drag on empty ground (px since the last move) orbits. */
  cityOrbit(deltaPx) {
    if (this.onCity && this.look !== '') {
      this._lookKeepFocus(O.orbit(this.lookView, deltaPx, this.viewSize()[1], this.aspect()));
    } else if (this.onCity) {
      this.cityState = O.orbit(this.cityState, deltaPx, this.viewSize()[1], this.aspect());
      this._snapIfReduced();
    }
  }

  /** A right drag pans the view over the block (bounded; Reset view and Look clear it). */
  cityPan(deltaPx) {
    if (this.onCity && this.look !== '') {
      this.lookView = O.pan(this.lookView, deltaPx, this.viewSize()[1], this.aspect());
    } else if (this.onCity) {
      this.cityState = O.pan(this.cityState, deltaPx, this.viewSize()[1], this.aspect());
      this._snapIfReduced();
    }
  }

  cityZoom(factor) {
    if (this.onCity && this.look !== '') {
      this._lookKeepFocus(O.zoom(this.lookView, factor, this.aspect()));
    } else if (this.onCity) {
      this.cityState = O.zoom(this.cityState, factor, this.aspect());
      this._snapIfReduced();
    }
  }

  cityStepZoom(dir) {
    if (this.onCity && this.look !== '') {
      this._lookKeepFocus(O.stepZoom(this.lookView, dir, this.aspect()));
    } else if (this.onCity) {
      this.cityState = O.stepZoom(this.cityState, dir, this.aspect());
      this._snapIfReduced();
    }
  }

  /** Reset view: a glide back to the strolling view that follows the child (from Look too; dest-fix r1). */
  cityReset() {
    if (!this.onCity) return;
    this.look = '';
    this.lookView = null;
    this.cityState = O.stroll(this.aspect());
    this._startGlide();
  }

  /** The overview of the whole block (the zoom-out end; tests pick places on the whole block with it). */
  cityOverview() {
    if (!this.onCity) return;
    this.look = '';
    this.lookView = null;
    this.cityState = O.reset(this.aspect());
    this._startGlide();
  }

  /** Look off (dest-fix r1): a glide back to the strolling view (a tap on empty space still uses cityLookOut). */
  cityStroll() {
    if (!this.onCity) return;
    this.look = '';
    this.lookView = null;
    this.cityState = O.stroll(this.aspect());
    this._startGlide();
  }

  /** Look: glide in to a place of CityMap.LOOK_PLACES. */
  cityLookAt(key) {
    if (!this.onCity || !Object.prototype.hasOwnProperty.call(C.CityMap.LOOK_PLACES, key)) return;
    this.look = key;
    this.lookView = O.lookState(key, this.aspect());
    this._startGlide();
  }

  /** Leaving a place: a glide back to the overview. */
  cityLookOut() {
    if (!this.onCity) return;
    this.look = '';
    this.lookView = null;
    this.cityState = O.reset(this.aspect());
    this._startGlide();
  }

  cityGliding() { return this.glideOk; }

  _lookKeepFocus(st) {
    const focus = this.lookView.focus;
    const pan = this.lookView.pan || [0, 0, 0];
    this.lookView = st;
    this.lookView.focus = focus;
    this.lookView.pan = pan;
    this.lookView.out = false;
  }

  _startGlide() {
    if (!this.curOk) return;
    O.copyPose(this.cur, this.glideFrom);
    this.glideOk = true;
    this.glideT = 0.0;
    this.glideDur = this.reduceMotion ? 0.25 : Number(C.CityMap.LOOK_GLIDE);
  }

  /** _update_city(k, dt). */
  updateCity(k, dt) {
    const aspect = this.aspect();
    const looking = this.look !== '' && this.lookView !== null;
    const goal = O.pose(looking ? this.lookView : this.cityState, aspect, this.child, this.goal);
    if (this.glideOk) {
      this.glideT += dt;
      const u = O.clampf(this.glideT / Math.max(this.glideDur, 0.01), 0.0, 1.0);
      O.glide(this.glideFrom, goal, u, this.cur);
      if (u >= 1.0) this.glideOk = false;
    } else if (!this.curOk || k >= 1.0) {
      O.copyPose(goal, this.cur);
      this.curOk = true;
    } else {
      O.smooth(this.cur, goal, dt, this.reduceMotion, this.cur);
    }
    this.yaw = this.cur.yaw;
    this.distance = this.cur.distance;
    this.focus[0] = this.cur.focus[0]; this.focus[1] = this.cur.focus[1]; this.focus[2] = this.cur.focus[2];
  }

  /** A snap is "be there now": it ends any glide. */
  snap() {
    if (this.onCity) {
      this.glideOk = false;
      this.updateCity(1.0, 0.0);
    }
  }

  process(delta) {
    if (this.onCity) this.updateCity(0.0, delta);
  }

  /** The camera's transform now ({basis, origin}). */
  xform() { return this.cur.xform; }

  /** Ground-plane directions relative to the camera (keyboard walking), as [x, z]. */
  flatForward() { return [-Math.sin(this.yaw), -Math.cos(this.yaw)]; }

  flatRight() { return [Math.cos(this.yaw), -Math.sin(this.yaw)]; }
}

/** Godot's is_equal_approx for floats. */
function isEqualApprox(a, b) {
  if (a === b) return true;
  let tol = 0.00001 * Math.abs(a);
  if (tol < 0.00001) tol = 0.00001;
  return Math.abs(a - b) < tol;
}

/** The newest frame's position of this child (the rig's target), into out [3]. */
function childPosition(frame, out) {
  if (!frame) return false;
  const kids = frame.kids;
  if (kids) {
    for (let i = 0; i < kids.length; i++) {
      const k = kids[i];
      if (k && k.me && k.xf && k.xf.length >= 12) {
        out[0] = k.xf[9]; out[1] = k.xf[10]; out[2] = k.xf[11];
        return true;
      }
    }
  }
  const me = frame.me;
  if (me && me.pos) {
    out[0] = me.pos[0]; out[1] = 0.0; out[2] = me.pos[1];   // no rig yet: the ground under the child
    return true;
  }
  return false;
}

export async function init(app) {
  const THREE = app.THREE;
  const canvas = app.canvas;
  const cam = app.camera;
  const view = [1, 1];
  const viewSize = () => {
    view[0] = canvas.clientWidth || window.innerWidth;
    view[1] = canvas.clientHeight || window.innerHeight;
    return view;
  };
  const rig = new CityRig(viewSize);
  rig.reduceMotion = app.params.get('reduce_motion') === '1';

  // the projection: Godot's Camera3D (fov from CityOrbit, keep height = three's vertical fov)
  const applyProjection = () => {
    viewSize();
    cam.fov = C.CityOrbit.FOV;
    cam.near = NEAR;
    cam.far = FAR;
    cam.aspect = view[0] / Math.max(view[1], 1);
    cam.updateProjectionMatrix();
  };
  applyProjection();
  window.addEventListener('resize', applyProjection);
  app.events.addEventListener('resize', applyProjection);

  const target = new THREE.Vector3();
  const m4 = new THREE.Matrix4();
  const placeCamera = () => {
    const xf = rig.cur.xform;
    const b = xf.basis;
    m4.set(
      b[0], b[3], b[6], xf.origin[0],
      b[1], b[4], b[7], xf.origin[1],
      b[2], b[5], b[8], xf.origin[2],
      0, 0, 0, 1);
    cam.position.set(xf.origin[0], xf.origin[1], xf.origin[2]);
    cam.quaternion.setFromRotationMatrix(m4);
    cam.updateMatrixWorld(true);
    target.set(rig.cur.focus[0], rig.cur.focus[1], rig.cur.focus[2]);
  };

  // ---------------------------------------------------------------- the play controller's city part
  let looking = false;
  let paused = false;
  const fire = (type, on) => app.events.dispatchEvent(new CustomEvent(type, { detail: { on } }));

  function setPaused(on) {
    if (on && !looking) on = false;
    const was = paused;
    paused = on;
    app.clock.setPaused(on);
    if (was !== on) {
      app.send({ t: 'pause', on });
      fire('pause', on);
    }
  }

  function setLook(on) {
    on = !!on;
    if (on === looking) return;
    looking = on;
    if (!on) {
      setPaused(false);
      rig.cityStroll();   // dest-fix r1: back to the child (was the overview)
    }
    app.send({ t: 'look', on });
    fire('look', on);
  }

  function lookStep(dir) {
    if (!looking) return;
    const order = C.CityMap.LOOK_ORDER;
    let i = order.indexOf(rig.look);
    i = i < 0 ? (dir > 0 ? 0 : order.length - 1) : (((i + dir) % order.length) + order.length) % order.length;
    rig.cityLookAt(String(order[i]));
  }

  function ray(clientX, clientY) {
    const r = canvas.getBoundingClientRect();
    const v = [r.width || view[0], r.height || view[1]];
    const g = O.ray(rig.cur.xform, v, [clientX - r.left, clientY - r.top]);
    return { o: g.origin, d: g.dir };
  }

  function riding() {
    const f = app.state.frame;
    return f && f.me && typeof f.me.riding === 'number' ? f.me.riding : -1;
  }

  /** _city_tap: in Look a tap picks a place (or glides out); otherwise the ray goes to Godot to walk. */
  function tap(clientX, clientY) {
    const r = ray(clientX, clientY);
    if (looking) {
      const key = O.pickPlace(r.o, r.d);
      if (key !== '') rig.cityLookAt(key);
      else rig.cityLookOut();
      return;
    }
    if (riding() >= 0) return;   // riding takes no other input; Get off is the action button
    app.send({ t: 'tap', o: r.o, d: r.d });
  }

  // ---------------------------------------------------------------- input on the canvas (_city_input)
  let gesture = null;
  const touches = new Map();   // pointerId -> [x, y] (canvas px)
  let primary = -1;            // the touch that acts as the mouse (Godot emulates the mouse from the first finger)
  let pinchPrev = 0;
  const pos = [0, 0];
  const local = (e) => {
    const r = canvas.getBoundingClientRect();
    pos[0] = e.clientX - r.left;
    pos[1] = e.clientY - r.top;
    return pos;
  };
  const scale = () => viewSize()[1] / 1080.0;
  const now = (e) => (e && e.timeStamp ? e.timeStamp : performance.now()) / 1000.0;
  const fingerGap = () => {
    let a = null;
    let b = null;
    for (const p of touches.values()) {
      if (!a) a = p;
      else if (!b) b = p;
    }
    return a && b ? Math.hypot(a[0] - b[0], a[1] - b[1]) : 0;
  };
  const moved = (g) => {
    if (g.mode === 'orbit') rig.cityOrbit(g.delta);
    else if (g.mode === 'pan') rig.cityPan(g.delta);
  };

  canvas.addEventListener('pointerdown', (e) => {
    try { canvas.setPointerCapture(e.pointerId); } catch (_) { /* not capturable */ }
    if (canvas.focus) canvas.focus({ preventScroll: true });
    const p = local(e);
    const t = now(e);
    if (e.pointerType === 'mouse') {
      if (e.button === 2) gesture = O.gestureNew('mouse', 'ground', p, t, scale(), 'right');
      else if (e.button === 0) gesture = O.gestureNew('mouse', 'ground', p, t, scale());
      return;
    }
    touches.set(e.pointerId, [p[0], p[1]]);
    if (touches.size === 1) {
      primary = e.pointerId;
      gesture = O.gestureNew('touch', 'ground', p, t, scale());
    } else if (gesture) {
      O.gestureMove(gesture, gesture.last, t, touches.size);   // a second finger: a pinch, never a tap
      pinchPrev = fingerGap();
    }
  });

  canvas.addEventListener('pointermove', (e) => {
    if (e.pointerType === 'mouse') {
      if (!gesture) return;
      O.gestureMove(gesture, local(e), now(e), 1);
      moved(gesture);
      return;
    }
    const tp = touches.get(e.pointerId);
    if (!tp) return;
    const p = local(e);
    tp[0] = p[0]; tp[1] = p[1];
    if (!gesture) return;
    if (touches.size >= 2) {
      O.gestureMove(gesture, gesture.last, now(e), touches.size);
      const gap = fingerGap();
      const f = O.pinchFactor(pinchPrev, gap);
      if (f !== 1.0) rig.cityZoom(f);
      pinchPrev = gap;
    } else if (e.pointerId === primary || touches.size === 1) {
      O.gestureMove(gesture, p, now(e), 1);
      moved(gesture);
    }
  });

  const release = (e, cancelled) => {
    if (e.pointerType === 'mouse') {
      if (!gesture) return;
      const g = gesture;
      gesture = null;
      if (!cancelled && g.button === 'left' && e.button === 0 && O.gestureEnd(g, now(e)) === 'tap') tap(e.clientX, e.clientY);
      return;
    }
    if (!touches.has(e.pointerId)) return;
    touches.delete(e.pointerId);
    if (touches.size > 0) return;
    const g = gesture;
    gesture = null;
    primary = -1;
    if (g && !cancelled && O.gestureEnd(g, now(e)) === 'tap') tap(e.clientX, e.clientY);
  };
  canvas.addEventListener('pointerup', (e) => release(e, false));
  canvas.addEventListener('pointercancel', (e) => release(e, true));
  canvas.addEventListener('contextmenu', (e) => e.preventDefault());
  canvas.addEventListener('wheel', (e) => {
    e.preventDefault();
    // one notch of a mouse wheel is about 100 px (Chrome, Safari) or 3 lines: Godot's one wheel event
    const k = e.deltaMode === 1 ? 1 / 3 : (e.deltaMode === 2 ? 1 : 1 / 100);
    const notches = Math.max(-3, Math.min(3, -e.deltaY * k));
    if (notches !== 0) rig.cityZoom(O.wheelFactor(notches));
  }, { passive: false });
  // Safari's trackpad and iOS pinch arrive as gesture events where pointer events do not carry them
  let gestureScale = 1;
  canvas.addEventListener('gesturestart', (e) => { e.preventDefault(); gestureScale = e.scale || 1; });
  canvas.addEventListener('gesturechange', (e) => {
    e.preventDefault();
    if (touches.size >= 2) return;   // pointer events already pinch
    const s = e.scale || 1;
    const f = O.pinchFactor(gestureScale, s);
    if (f !== 1.0) rig.cityZoom(f);
    gestureScale = s;
  });

  window.addEventListener('keydown', (e) => {
    if (e.repeat || e.target && (e.target.tagName === 'INPUT' || e.target.tagName === 'TEXTAREA')) return;
    switch (e.key) {
      case 'Escape':
        if (looking) setLook(false);
        break;
      case 'q': case 'Q': rig.rotateStep(-1); break;
      case 'e': case 'E': rig.rotateStep(1); break;
      case 'z': case 'Z':
        if (!e.ctrlKey && !e.metaKey) rig.toggleZoom();
        break;
      case ' ': {
        const f = app.state.frame;
        if (f && f.me && f.me.ctx) {
          e.preventDefault();
          app.send({ t: 'act' });
        }
        break;
      }
      default: break;
    }
  });

  // ---------------------------------------------------------------- the frame
  const child = rig.child;
  rig.enterCity();
  placeCamera();
  let camIn = 0;

  app.cameraRig = {
    rig,
    target,
    isLooking: () => looking,
    setLook,
    lookAt(key) {
      if (!looking) setLook(true);
      rig.cityLookAt(key);
    },
    lookOut: () => rig.cityLookOut(),
    lookStep,
    reset: () => rig.cityReset(),
    ray,
    tap,
    isPaused: () => paused,
    setPaused,
    place: () => rig.look,
    gliding: () => rig.cityGliding(),
    rotateStep: (dir) => rig.rotateStep(dir),
    toggleZoom: () => rig.toggleZoom(),
    zoomIn: () => rig.zoomIn(),
    zoomOut: () => rig.zoomOut(),
  };

  return {
    update(dt) {
      childPosition(app.state.frame, child);
      rig.process(dt);
      placeCamera();
      camIn -= dt;
      if (camIn <= 0) {
        camIn = CAM_EVERY;
        const o = rig.cur.xform.origin;
        app.send({ t: 'cam', pos: [o[0], o[1], o[2]], target: [target.x, target.y, target.z] });
      }
    },
    onMessage(msg) {
      if (msg.t === 'hello') {
        // the city is entered (again): the overview, Look and Pause off (play_controller's arrival)
        if (msg.reduce_motion !== undefined) rig.reduceMotion = !!msg.reduce_motion;
        if (looking) {
          looking = false;
          app.send({ t: 'look', on: false });
          fire('look', false);
        }
        setPaused(false);
        childPosition(app.state.frame, child);
        rig.enterCity();
        placeCamera();
      } else if (msg.t === 'bye') {
        setLook(false);
      }
    },
  };
}
