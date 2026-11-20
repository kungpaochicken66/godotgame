// The moving city, its weather and night, its lights and sky (design/city-threejs.md §6.4, module "world").
// Ported from world/city_world.gd (_process: the wheel and gondolas, the carousel, the vehicles; the weather's
// _compute_weights / _update_weather / _apply_look; _follow_rain / rain_focus; apply_hidden) and from
// world/town_world.gd (_city_light and the environment and sun it sets). The pure logic is js/world_logic.js
// (tested against Godot by scripts/web_city/world.test.mjs); this file applies it to the Three.js scene.
//
// Lighting: Godot's Compatibility renderer multiplies every light's energy by PI and uses 1/PI Lambert terms,
// so a Godot energy E is a Three.js intensity PI * E (direct lights and the ambient colour alike). The city's
// StandardMaterial3Ds use DIFFUSE_LAMBERT_WRAP and a "specular" of 0.3 (F0 = 0.16 * s^2); the shared role
// materials are patched (onBeforeCompile, parameters only, never recreated) to shade the same way.
// Emission is not scaled like the lights: Godot's Compatibility renderer multiplies the sRGB emission colour by
// the energy and only then converts to linear, so the glow and the cabins use meshpack.setGodotEmission.
// Colour adjustment: Godot applies brightness, contrast and saturation after its linear-to-sRGB step. The page
// renders into an sRGB render target and one full-screen quad applies the same (on by default; ?adjust=0 off).
// Rain: Godot's 2400 GPU particles become one instanced draw whose vertex shader computes every streak from
// its index, a per-cycle hash and a time uniform (no per-drop CPU work). Its amount follows the rain weight
// as Godot's amount_ratio does: only drops emitted while it rains fall, so it eases in and out with no popping.
import * as THREE from '../vendor/three.module.js';
import { C } from './consts.js';
import { matrixFrom12, setGodotEmission } from './meshpack.js';
import * as L from './world_logic.js';

/** Godot light energy (Compatibility renderer, non-physical units) to Three.js intensity. */
const ENERGY = Math.PI;
/** The rain's history: (ratio, focus x, focus z) samples this far apart, newest first (covers the lifetime). */
const HIST = 24;
const HIST_STEP = 0.1;
const DIFFUSE_LAMBERT_WRAP = 2;

const RAIN_VS = /* glsl */`
uniform float uTime;
uniform float uLifetime;
uniform float uAmount;
uniform float uHalf;
uniform float uTop;
uniform float uBoxY;
uniform vec3 uDir;
uniform float uSpread;
uniform vec2 uSpeed;
uniform vec3 uGravity;
uniform vec3 uHist[${HIST}];
uniform float uPushT;
uniform float uHistStep;
attribute float aIndex;

uvec4 pcg4d(uvec4 v) {
  v = v * 1664525u + 1013904223u;
  v.x += v.y * v.w; v.y += v.z * v.x; v.z += v.x * v.y; v.w += v.y * v.z;
  v ^= v >> 16u;
  v.x += v.y * v.w; v.y += v.z * v.x; v.z += v.x * v.y; v.w += v.y * v.z;
  return v;
}

// (ratio, focus x, focus z) at time ts: slot 0 is now, slot 1 the newest push (uPushT), then HIST_STEP apart.
vec3 history(float ts) {
  if (ts >= uPushT) {
    float span = max(uTime - uPushT, 1e-4);
    return mix(uHist[1], uHist[0], clamp((ts - uPushT) / span, 0.0, 1.0));
  }
  float j = 1.0 + (uPushT - ts) / uHistStep;
  float j0 = min(floor(j), float(${HIST - 1}));
  float j1 = min(j0 + 1.0, float(${HIST - 1}));
  return mix(uHist[int(j0)], uHist[int(j1)], j - floor(j));
}

void main() {
  float phase = uTime / uLifetime + aIndex / uAmount;
  float cycle = floor(phase);
  float age = (phase - cycle) * uLifetime;
  float spawn = uTime - age;
  uvec4 h0 = pcg4d(uvec4(uint(aIndex), uint(cycle), 0x9e37u, 0x79b9u));
  uvec4 h1 = pcg4d(uvec4(uint(aIndex), uint(cycle), 0x7f4au, 0x7c15u));
  vec4 r0 = vec4(h0) * (1.0 / 4294967295.0);
  vec4 r1 = vec4(h1) * (1.0 / 4294967295.0);
  vec3 hs = history(spawn);
  if (r0.x >= hs.x) {                       // not emitted at that moment's amount ratio
    gl_Position = vec4(2.0, 2.0, 2.0, 1.0);
    return;
  }
  // ParticleProcessMaterial: box emission, direction with spread, initial velocity, gravity, align Y.
  vec3 p0 = vec3(hs.y + (r0.y * 2.0 - 1.0) * uHalf, uTop + (r0.z * 2.0 - 1.0) * uBoxY, hs.z + (r0.w * 2.0 - 1.0) * uHalf);
  float a1 = (r1.x * 2.0 - 1.0) * uSpread;
  float a2 = (r1.y * 2.0 - 1.0) * uSpread;
  vec3 dxz = vec3(sin(a1), 0.0, cos(a1));
  vec3 dyz = vec3(0.0, sin(a2), cos(a2));
  dyz.z = dyz.z / max(0.0001, sqrt(abs(dyz.z)));
  vec3 sd = vec3(dxz.x * dyz.z, dyz.y, dxz.z * dyz.z);
  vec3 bin = cross(vec3(0.0, 1.0, 0.0), uDir);
  bin = length(bin) < 0.0001 ? vec3(0.0, 0.0, 1.0) : normalize(bin);
  vec3 nrm = cross(bin, uDir);
  vec3 dir = normalize(bin * sd.x + nrm * sd.y + uDir * sd.z);
  vec3 v0 = dir * mix(uSpeed.x, uSpeed.y, r1.z);
  vec3 p = p0 + v0 * age + 0.5 * uGravity * age * age;
  vec3 vel = v0 + uGravity * age;
  vec3 ay = normalize(vel);
  vec3 ax = normalize(cross(ay, vec3(0.0, 0.0, 1.0)));
  vec3 az = normalize(cross(ax, ay));
  vec3 world = p + ax * position.x + ay * position.y + az * position.z;
  gl_Position = projectionMatrix * viewMatrix * vec4(world, 1.0);
}
`;

const RAIN_FS = /* glsl */`
uniform vec3 uColor;
uniform float uAlpha;
void main() {
  gl_FragColor = vec4(uColor, uAlpha);
  #include <colorspace_fragment>
}
`;

const ADJUST_VS = /* glsl */`
varying vec2 vUv;
void main() {
  vUv = uv;
  gl_Position = vec4(position.xy, 0.0, 1.0);
}
`;

// Godot's tonemap pass for the city: linear tonemap (identity), linear to sRGB, then brightness, contrast,
// saturation (apply_bcs). The render target is sRGB-encoded, so the sample comes back linear.
const ADJUST_FS = /* glsl */`
uniform sampler2D tScene;
uniform vec3 uBcs;
varying vec2 vUv;
vec3 toSrgb(vec3 c) {
  c = clamp(c, 0.0, 1.0);
  return mix(1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055, 12.92 * c, vec3(lessThan(c, vec3(0.0031308))));
}
void main() {
  vec3 c = toSrgb(texture2D(tScene, vUv).rgb);
  c = mix(vec3(0.0), c, uBcs.x);
  c = mix(vec3(0.5), c, uBcs.y);
  c = mix(vec3(dot(vec3(1.0), c) * 0.33333), c, uBcs.z);
  gl_FragColor = vec4(c, 1.0);
}
`;

// ------------------------------------------------------------------ Godot's shading on the role materials

const DIRECT_DIFFUSE = 'reflectedLight.directDiffuse += irradiance * BRDF_Lambert( material.diffuseContribution ) * ( 1.0 - F );';
const DIRECT_WRAP = 'reflectedLight.directDiffuse += directLight.color * ( max( 0.0, ( dot( geometryNormal, directLight.direction ) + roughness ) / ( ( 1.0 + roughness ) * ( 1.0 + roughness ) ) ) ) * BRDF_Lambert( material.diffuseContribution );';
const INDIRECT_DIFFUSE = 'vec3 diffuse = irradiance * BRDF_Lambert( material.diffuseContribution ) * ( 1.0 - singleScattering - multiScattering );';
const INDIRECT_GODOT = 'vec3 diffuse = irradiance * BRDF_Lambert( material.diffuseContribution );';
const F0_THREE = 'material.specularColor = vec3( 0.04 );';
const F0_GODOT = 'material.specularColor = vec3( 0.16 * godotSpecular * godotSpecular );';

let _patched = null;
function godotChunks() {
  if (_patched !== null) return _patched;
  const pars = THREE.ShaderChunk.lights_physical_pars_fragment;
  const frag = THREE.ShaderChunk.lights_physical_fragment;
  if (!pars.includes(DIRECT_DIFFUSE) || !pars.includes(INDIRECT_DIFFUSE) || !frag.includes(F0_THREE)) {
    _patched = false;
    return _patched;
  }
  _patched = {
    pars: pars.replace(DIRECT_DIFFUSE, DIRECT_WRAP).replace(INDIRECT_DIFFUSE, INDIRECT_GODOT),
    frag: frag.replace(F0_THREE, F0_GODOT),
  };
  return _patched;
}

/** Makes a role material shade like Godot's (lambert wrap diffuse, Godot's F0 and ambient). Parameters only. */
function godotShading(mat, specular) {
  const chunks = godotChunks();
  if (!chunks || !mat || !mat.isMeshStandardMaterial) return null;
  const u = { value: specular };
  mat.userData.godotSpecular = u;
  mat.onBeforeCompile = (shader) => {
    shader.uniforms.godotSpecular = u;
    shader.fragmentShader = `uniform float godotSpecular;\n${shader.fragmentShader}`
      .replace('#include <lights_physical_pars_fragment>', chunks.pars)
      .replace('#include <lights_physical_fragment>', chunks.frag);
  };
  mat.customProgramCacheKey = () => 'godot-city-shading-1';
  mat.needsUpdate = true;
  return u;
}

// ------------------------------------------------------------------ the module

export async function init(app) {
  const W = C.CityWorld;
  const missing = [];
  const need = (p) => { const n = app.node(p); if (!n) missing.push(p); return n; };

  // ---------------------------------------------------------------- nodes
  const wheel = need('Ferris/Wheel');
  const gondolas = [];
  for (let i = 0; i < Number(C.CityMap.FERRIS.gondolas); i++) gondolas.push(need(`Ferris/Gondola${i}`));
  const turn = need('Carousel/Turn');
  const horses = need('Carousel/Turn/Horses');
  const vehicles = [];
  for (let i = 0; i < C.CityMap.VEHICLES.length; i++) vehicles.push(need(`Moving/Vehicles/Vehicle${i}`));
  const puddles = need('Weather/Puddles');
  const pools = need('Weather/LightPools');
  const rainNode = app.node('Weather/Rain');
  const levels = [];   // [{obj, bid, baseY}]
  const lp = L.levelPaths();
  for (const bid of Object.keys(lp)) {
    for (const p of lp[bid]) {
      const n = need(p);
      if (n) levels.push({ obj: n, bid, baseY: Number(n.userData.base_y ?? 0) });
    }
  }
  if (missing.length) throw new Error(`world: city nodes missing: ${missing.join(', ')}`);

  // the horses' instance colours, as city_world sets them at build (the pack carries no instance data)
  if (horses.isInstancedMesh) {
    const col = new THREE.Color();
    L.horseColors().forEach((c, i) => {
      if (i < horses.count) horses.setColorAt(i, col.setRGB(c[0], c[1], c[2], THREE.SRGBColorSpace));
    });
    if (horses.instanceColor) horses.instanceColor.needsUpdate = true;
  }

  // ---------------------------------------------------------------- materials
  const mats = app.city.materials;
  const shading = (C.extra && C.extra.world && C.extra.world.shading) || {};
  const specular = {};
  for (const role of Object.keys(mats)) {
    const s = shading[role];
    if (s && s.diffuse_mode === DIFFUSE_LAMBERT_WRAP && !s.unshaded) specular[role] = godotShading(mats[role], Number(s.specular));
  }
  const shadingPatched = Object.values(specular).some(Boolean);
  if (!shadingPatched) console.warn('world: Godot shading not applied (three.js shader chunks changed); using Three.js defaults');

  // ---------------------------------------------------------------- lights, sky (created once)
  const scene = app.scene;
  if (!(scene.background && scene.background.isColor)) scene.background = new THREE.Color(1, 1, 1);
  const ambient = new THREE.AmbientLight(0xffffff, 0);
  ambient.name = 'CityAmbient';
  scene.add(ambient);
  const sun = new THREE.DirectionalLight(0xffffff, 0);
  sun.name = 'CitySun';
  sun.castShadow = false;
  const sd = L.sunDirection();
  sun.position.set(-sd[0] * 100, -sd[1] * 100, -sd[2] * 100);
  sun.target.position.set(0, 0, 0);
  scene.add(sun);
  scene.add(sun.target);
  const warm = new THREE.Color().setRGB(W.WARM.color[0], W.WARM.color[1], W.WARM.color[2], THREE.SRGBColorSpace);
  const points = [];
  const energies = [];
  for (const l of app.city.lights) {
    const pl = new THREE.PointLight(warm, 0, Number(l.light.range), 1);   // Godot omni: range cut-off, attenuation 1
    pl.name = `${l.object.name}Point`;
    pl.castShadow = false;
    l.object.add(pl);
    points.push(pl);
    energies.push(Number(l.meta.energy ?? 1));
  }

  // ---------------------------------------------------------------- rain
  const rs = L.rainSpec();
  const box = new THREE.BoxGeometry(rs.size[0], rs.size[1], rs.size[2]);
  const rainGeo = new THREE.InstancedBufferGeometry();
  rainGeo.index = box.index;
  rainGeo.setAttribute('position', box.getAttribute('position'));
  const idx = new Float32Array(rs.amount);
  for (let i = 0; i < rs.amount; i++) idx[i] = i;
  rainGeo.setAttribute('aIndex', new THREE.InstancedBufferAttribute(idx, 1));
  rainGeo.instanceCount = rs.amount;
  const hist = [];
  for (let i = 0; i < HIST; i++) hist.push(new THREE.Vector3(0, 0, 0));
  const rainMat = new THREE.ShaderMaterial({
    name: 'rain',
    uniforms: {
      uTime: { value: 0 }, uLifetime: { value: rs.lifetime }, uAmount: { value: rs.amount }, uHalf: { value: rs.half },
      uTop: { value: rs.top }, uBoxY: { value: rs.boxY }, uDir: { value: new THREE.Vector3(rs.dir[0], rs.dir[1], rs.dir[2]) },
      uSpread: { value: rs.spreadDeg * Math.PI / 180 }, uSpeed: { value: new THREE.Vector2(rs.vmin, rs.vmax) },
      uGravity: { value: new THREE.Vector3(rs.gravity[0], rs.gravity[1], rs.gravity[2]) },
      uHist: { value: hist }, uPushT: { value: 0 }, uHistStep: { value: HIST_STEP },
      uColor: { value: new THREE.Color().setRGB(rs.color.color[0], rs.color.color[1], rs.color.color[2], THREE.SRGBColorSpace) },
      uAlpha: { value: 0 },
    },
    vertexShader: RAIN_VS,
    fragmentShader: RAIN_FS,
    transparent: true,
    depthWrite: false,
  });
  const rain = new THREE.Mesh(rainGeo, rainMat);
  rain.name = 'RainDrops';
  rain.frustumCulled = false;
  rain.visible = false;
  scene.add(rain);
  let rainClock = 0;
  let pushT = 0;

  // ---------------------------------------------------------------- the colour adjustment pass
  const adjustOn = app.params.get('adjust') !== '0';
  const renderer = app.renderer;
  let rt = null, quadScene = null, quadCam = null, quadMat = null;
  const size = new THREE.Vector2();
  if (adjustOn) {
    renderer.getDrawingBufferSize(size);
    const aa = !!(renderer.getContext().getContextAttributes() || {}).antialias;
    rt = new THREE.WebGLRenderTarget(Math.max(1, size.x), Math.max(1, size.y), {
      samples: aa ? 4 : 0, type: THREE.UnsignedByteType, colorSpace: THREE.SRGBColorSpace,
      minFilter: THREE.LinearFilter, magFilter: THREE.LinearFilter, generateMipmaps: false, depthBuffer: true,
    });
    quadMat = new THREE.ShaderMaterial({
      name: 'adjust',
      uniforms: { tScene: { value: rt.texture }, uBcs: { value: new THREE.Vector3(1, 1, 1) } },
      vertexShader: ADJUST_VS, fragmentShader: ADJUST_FS, depthTest: false, depthWrite: false,
    });
    quadScene = new THREE.Scene();
    const quad = new THREE.Mesh(new THREE.PlaneGeometry(2, 2), quadMat);
    quad.frustumCulled = false;
    quadScene.add(quad);
    quadCam = new THREE.OrthographicCamera(-1, 1, 1, -1, 0, 1);
    renderer.info.autoReset = false;   // the frame's calls are the city's plus the quad's (reset in update)
  }

  // ---------------------------------------------------------------- state (reused every frame)
  let override = null;
  const weights = { sunny: 1, rain: 0, night: 0 };
  const look = {};
  const light = L.cityLight({ sunny: 1 });
  const applier = new L.WeatherApplier();
  let applied = L.lookValues(0, 0, 0, energies);
  const poser = new L.VehiclePoser();
  const xf = new Array(12);
  const m4 = new THREE.Matrix4();
  const o3 = [0, 0, 0];
  const camPos = new THREE.Vector3();
  const camDir = new THREE.Vector3();
  const camO = [0, 0, 0];
  const camF = [0, 0, 0];
  const focus = [0, 0, 0];
  let hidden = {};

  function applyLook(v) {
    const g = mats.ground;
    if (g) {
      g.color.setRGB(v.ground.albedo[0], v.ground.albedo[1], v.ground.albedo[2], THREE.SRGBColorSpace);
      g.roughness = v.ground.roughness;
      if (specular.ground) specular.ground.value = v.ground.specular;
    }
    if (mats.puddle) mats.puddle.opacity = v.puddle.alpha;
    puddles.visible = v.puddle.visible;
    setGodotEmission(mats.glow, v.glow.energy);     // Godot's Compatibility emission (energy before sRGB-to-linear)
    setGodotEmission(mats.cabin, v.cabin.energy);
    if (mats.pool) mats.pool.opacity = v.pool.alpha;
    pools.visible = v.pool.visible;
    rainMat.uniforms.uAlpha.value = v.rain.alpha;
    rain.visible = v.rain.visible;
    if (rainNode) rainNode.visible = v.rain.visible;
    for (let i = 0; i < points.length; i++) points[i].intensity = ENERGY * v.lights[i];
  }

  function updateWeather(t, force = false) {
    L.computeWeights(app.state.states, t, override, weights);
    L.weatherLook(weights, look);
    if (applier.needs(look.wet, look.glow, look.rain, force)) {
      applied = L.lookValues(look.wet, look.glow, look.rain, energies, applied);
      applyLook(applied);
    }
    // TownWorld._city_light, every frame like Godot's _process
    L.cityLight(weights, light);
    scene.background.setRGB(light.sky[0], light.sky[1], light.sky[2], THREE.SRGBColorSpace);
    ambient.color.setRGB(light.ambient[0], light.ambient[1], light.ambient[2], THREE.SRGBColorSpace);
    ambient.intensity = ENERGY * light.ambient_energy;
    sun.color.setRGB(light.sun[0], light.sun[1], light.sun[2], THREE.SRGBColorSpace);
    sun.intensity = ENERGY * light.sun_energy;
    if (quadMat) quadMat.uniforms.uBcs.value.set(light.brightness, light.contrast, light.saturation);
  }

  function updateRain(dt) {
    rainClock += dt;
    const cam = app.camera;
    cam.getWorldPosition(camPos);
    cam.getWorldDirection(camDir);
    camO[0] = camPos.x; camO[1] = camPos.y; camO[2] = camPos.z;
    camF[0] = camDir.x; camF[1] = camDir.y; camF[2] = camDir.z;
    L.rainFocus(camO, camF, focus);
    const ratio = applied.rain.emitting ? applied.rain.ratio : 0;
    if (rainClock - pushT >= HIST_STEP) {
      // shift the history one slot (fixed array, no allocation); slot 1 becomes the value now
      for (let i = HIST - 1; i >= 2; i--) hist[i].copy(hist[i - 1]);
      hist[1].set(ratio, focus[0], focus[2]);
      pushT = rainClock;
    }
    hist[0].set(ratio, focus[0], focus[2]);
    const u = rainMat.uniforms;
    u.uTime.value = rainClock;
    u.uPushT.value = pushT;
  }

  function poseRides(t) {
    const angle = L.ferrisAngleAt(t);
    wheel.rotation.z = angle;
    for (let i = 0; i < gondolas.length; i++) {
      L.gondolaOrigin(i, angle, o3);
      gondolas[i].position.set(o3[0], o3[1], o3[2]);
    }
    turn.rotation.y = L.carouselAngleAt(t);
    if (horses.isInstancedMesh) {
      for (let i = 0; i < horses.count; i++) {
        L.carouselHorseLocal(i, t, xf);
        horses.setMatrixAt(i, matrixFrom12(xf, m4));
      }
      horses.instanceMatrix.needsUpdate = true;
    }
  }

  function poseVehicles(dt) {
    if (!poser.step(app.state.states, app.clock.cityClock(), dt, app.clock.isPaused())) return;
    for (let i = 0; i < vehicles.length; i++) {
      const d = poser.drawn[i];
      const v = vehicles[i];
      if (!d || !d.visible) { v.visible = false; continue; }
      v.visible = true;
      v.position.set(d.x, d.y, d.z);
      v.rotation.y = d.ry;
    }
  }

  function applyHidden(h) {
    hidden = h || {};
    for (const lv of levels) lv.obj.visible = L.levelVisible(hidden, lv.bid, lv.baseY);
  }

  // first look and poses, as build() leaves them (sunny until the states say otherwise)
  updateWeather(app.clock.viewTime(), true);
  poseRides(app.clock.viewTime());
  for (const v of vehicles) v.visible = false;   // Godot hides them until the first states arrive

  const riderOut = new Array(12);
  app.world = {
    /** The weather mix drawn now {sunny, rain, night} (a copy). */
    weights() { return { sunny: weights.sunny, rain: weights.rain, night: weights.night }; },
    /** The wheel's angle as drawn now (CityWorld.ferris_angle_now): seat riders with it. */
    ferrisAngleNow() { return L.ferrisAngleAt(app.clock.viewTime()); },
    /** Where a rider sits in gondola g (CityWorld.rider_transform), as a Matrix4 (`out` reused if given). */
    riderTransform(g, angle, slot, out = new THREE.Matrix4()) { return matrixFrom12(L.riderXf(g, angle, slot, riderOut), out); },
    /** Where an avatar sits or stands for an INTERACTIONS key (CityWorld.seat_transform); null when unknown. */
    seatTransform(key, out = new THREE.Matrix4()) {
      const a = L.seatXf(key, riderOut);
      return a ? matrixFrom12(a, out) : null;
    },
    /** Hides storeys like CityWorld.apply_hidden ({building id: highest visible floor y}; {} shows all). */
    applyHidden,
    /** Pins the weather mix (tests, previews); null or {} returns to the shared weather. */
    setWeatherOverride(w) { override = w && Object.keys(w).length ? { ...w } : null; updateWeather(app.clock.viewTime(), true); },
    /** The ground point the rain falls around (CityWorld.rain_focus), [x, 0, z]. */
    rainFocus() { return focus.slice(); },
    /** Numbers for checks: what is applied now. */
    info() {
      return { weights: this.weights(), look: { wet: look.wet, glow: look.glow, rain: look.rain }, applied: JSON.parse(JSON.stringify(applied)),
        light: JSON.parse(JSON.stringify(light)), rainVisible: rain.visible, rainClock, shadingPatched, adjustOn, hidden: { ...hidden },
        lights: points.map((p) => p.intensity), sun: sun.intensity, ambient: ambient.intensity };
    },
    adjustOn,
    shadingPatched,
  };

  return {
    update(dt, t) {
      if (rt) {
        renderer.info.reset();
        renderer.getDrawingBufferSize(size);
        if (size.x !== rt.width || size.y !== rt.height) rt.setSize(Math.max(1, size.x), Math.max(1, size.y));
        renderer.setRenderTarget(rt);   // main.js renders the city into it; afterRender draws it adjusted
      }
      updateWeather(t);
      updateRain(dt);
      poseRides(t);
      poseVehicles(dt);
    },
    onMessage(msg) {
      if (msg.t === 'cutaway') applyHidden(msg.hidden || {});
    },
    afterRender() {
      if (!rt) return;
      try {
        renderer.setRenderTarget(null);
        renderer.render(quadScene, quadCam);
      } catch (e) {
        if (!app.failed['world.afterRender']) {
          app.failed['world.afterRender'] = String(e && e.stack ? e.stack : e);
          app.send({ t: 'log', level: 'error', text: `world.afterRender: ${e}` });
        }
      }
    },
  };
}
