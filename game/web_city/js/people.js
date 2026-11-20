// The city's people on the page: binds the port of art/city_people.gd (people_core.js and its helpers
// people_pose.js, people_rules.js, people_math.js) to the twelve InstancedMeshes the city pack carries for them
// (City/People/Box, Limb, Block, Head, Skirt, six hair styles, Umbrella: one draw call each).
//
// - The instance matrices are written straight into each InstancedMesh's instanceMatrix array; a hidden
//   instance is Godot's zero-scale transform. needsUpdate is set only for the shapes that changed.
// - Instance colours: Godot multiplies the mesh's vertex colour by the MultiMesh instance colour, an
//   sRGB-encoded Color on a vertex_color_is_srgb material. The page's vertex colours are linear, so the
//   instance colour is converted the same way (THREE.Color.setRGB(..., SRGBColorSpace)) and the product matches.
// - Time: update(dt, t) poses the people at the page's view time (app.clock.viewTime(), which Pause freezes);
//   the child riders and the weather come from the newest City states (app.state.states); the cut-away regions
//   from the bridge's `cutaway` message (`regions`).
//
// app.people = {
//   setHiddenRegions(regions)   the regions whose storeys the cutaway hides ([] shows everyone)
//   snapshot(t?)                with t: poses everybody at t first (Godot's pose_at). Returns {t, writes,
//                               shapes: [{name, count, xf (12 numbers an instance, Godot's order), colors
//                               (Godot's sRGB r, g, b)}], people: [{id, kind, action, region, shown, pos}]}
//   sim                         the CityPeople itself (tests, tours)
// }
import * as THREE from '../vendor/three.module.js';
import { CityPeople } from './people_core.js';

export async function init(app) {
  const names = app.C.People.MESH_NAMES;
  const meshes = names.map((name) => {
    const m = app.node(`People/${name}`);
    if (!m || !m.isInstancedMesh) throw new Error(`people: City/People/${name} is not an InstancedMesh of the city pack`);
    if (!m.instanceColor) {
      m.instanceColor = new THREE.InstancedBufferAttribute(new Float32Array(Math.max(1, m.count) * 3).fill(1), 3);
      m.instanceColor.setUsage(THREE.DynamicDrawUsage);
    }
    return m;
  });
  const linear = new THREE.Color();
  const onColor = (m, i, r, g, b) => {
    linear.setRGB(r, g, b, THREE.SRGBColorSpace);
    const a = meshes[m].instanceColor.array;
    a[i * 3] = linear.r;
    a[i * 3 + 1] = linear.g;
    a[i * 3 + 2] = linear.b;
  };
  let states = app.state.states;
  const sim = new CityPeople({
    time: app.clock.viewTime(),
    riders: states ? states.riders : null,
    weather: states || null,
    matrices: meshes.map((m) => m.instanceMatrix.array),
    onColor,
  });
  for (let m = 0; m < meshes.length; m++) {
    if (meshes[m].count !== sim.alloc[m]) {
      throw new Error(`people: City/People/${names[m]} has ${meshes[m].count} instances, the people need ${sim.alloc[m]} (export the city again)`);
    }
  }

  /** Tells the renderer which shapes changed since the last call. */
  function flush() {
    for (let m = 0; m < meshes.length; m++) {
      if (sim.dirty[m]) {
        meshes[m].instanceMatrix.needsUpdate = true;
        sim.dirty[m] = 0;
      }
      if (sim.colorDirty[m]) {
        meshes[m].instanceColor.needsUpdate = true;
        sim.colorDirty[m] = 0;
      }
    }
  }
  flush();

  function syncStates() {
    if (app.state.states !== states) {
      states = app.state.states;
      sim.setStates(states);
    }
  }

  app.people = {
    sim,
    setHiddenRegions(regions) { sim.setHiddenRegions(regions || []); },
    snapshot(t) {
      if (t !== undefined) {
        syncStates();
        sim.poseAt(t);
        flush();
      }
      const xf = sim.snapshot();
      return {
        t: t === undefined ? sim._lastT : t,
        writes: sim.writesLast,
        shapes: names.map((name, m) => ({ name, count: sim.alloc[m], xf: xf[m], colors: sim.col[m].slice(0, sim.alloc[m] * 3) })),
        people: sim.people.map((p) => ({ id: p.id, kind: p.kind, action: p.action, region: p.region, shown: p.shown,
          pos: [p.world[9], p.world[10], p.world[11]] })),
      };
    },
  };

  return {
    update(_dt, t) {
      syncStates();
      sim.frame(t);
      flush();
    },
    onMessage(msg) {
      if (msg.t === 'cutaway') {
        sim.setHiddenRegions(msg.regions || []);
      } else if (msg.t === 'hello') {
        // the city is entered (again): Godot makes new people then, with no weather memory, no child on the
        // wheel and nothing cut away (Godot sends the cutaway again as the child moves)
        sim.newCity();
      }
    },
  };
}
