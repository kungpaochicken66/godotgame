"""Extract selected animals from the Everything Library .blend as one GLB each (Lantern Lane).

Run in Blender (5.2.2 used for the first batch), background mode, on the untouched source file:

  blender -b --factory-startup <source.blend> --python-exit-code 1 --python scripts/blender/everything_export.py -- \
      --spec art/everything-zoo-r1/spec.json --out <empty output folder> [--no-previews]

What it does, per asset in the spec:
  1. Takes exactly the named mesh object (nothing else: no preview plane, no alternative variant, no
     neighbour), evaluated with its modifiers, and bakes its world transform (the library's meshes are
     Y-up under rotated parents).
  2. Turns it by the spec's yaw, scales it uniformly to the target height, and moves its origin to
     the footprint centre on the ground (min z = 0). Blender -Y is the front; glTF writes it as +Z.
  3. Keeps only the named colour attribute (as COLOR_0), drops UVs and other colour layers, and gives
     it one plain matte material (roughness 1, metallic 0) whose colour comes from that attribute.
  4. Exports one binary glTF. No animation, skin, morph, camera, light or image.
  5. Re-imports the GLB into a clean scene and checks it (one mesh, the colour attribute, no image,
     triangle count, height, ground contact, centring), exports it a second time and compares bytes.
  6. Writes a manifest per asset, a batch manifest with every hash, the embedded licence text, a log,
     and (unless --no-previews) small Workbench previews: front and side per asset, and a lineup with a
     1.30 m stand-in for the child. Previews are 320 x 320 PNGs.

It never saves the .blend and checks the source file's SHA-256 before and after. Any failed check
stops with exit code 1 and the reason in the log; nothing is silently skipped.
"""
import bpy
import bmesh
import hashlib
import json
import math
import os
import shutil
import sys
import tempfile
from mathutils import Matrix, Vector

LOG = []


def log(msg):
    LOG.append(msg)
    print("EVERYTHING " + msg)


def fail(msg, out=None):
    log("FAIL " + msg)
    if out:
        with open(os.path.join(out, "export_log.txt"), "w") as f:
            f.write("\n".join(LOG) + "\n")
    sys.exit(1)


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    out = {"previews": True}
    i = 0
    while i < len(argv):
        if argv[i] == "--spec":
            out["spec"] = argv[i + 1]; i += 2
        elif argv[i] == "--out":
            out["out"] = argv[i + 1]; i += 2
        elif argv[i] == "--no-previews":
            out["previews"] = False; i += 1
        else:
            fail("unknown argument %s" % argv[i])
    if "spec" not in out or "out" not in out:
        fail("usage: -- --spec <spec.json> --out <empty folder> [--no-previews]")
    return out


# ------------------------------------------------------------------ glTF exporter options

REQUIRED = ["export_format", "use_selection", "export_yup"]


def export_options(path):
    props = set(bpy.ops.export_scene.gltf.get_rna_type().properties.keys())
    wanted = {
        "filepath": path,
        "export_format": "GLB",
        "use_selection": True,
        "export_yup": True,
        "export_apply": True,
        "export_animations": False,
        "export_skins": False,
        "export_morph": False,
        "export_cameras": False,
        "export_lights": False,
        "export_texcoords": False,
        "export_normals": True,
        "export_tangents": False,
        "export_materials": "EXPORT",
        "export_extras": False,
        "export_image_format": "NONE",
    }
    for k in REQUIRED:
        if k not in props:
            fail("this Blender's glTF exporter has no option %s" % k)
    # The colour attribute: newer exporters choose it by mode, older ones by a flag.
    if "export_vertex_color" in props:
        wanted["export_vertex_color"] = "ACTIVE"
        if "export_all_vertex_colors" in props:
            wanted["export_all_vertex_colors"] = False
        if "export_active_vertex_color_when_no_material" in props:
            wanted["export_active_vertex_color_when_no_material"] = True
    elif "export_colors" in props:
        wanted["export_colors"] = True
    else:
        fail("this Blender's glTF exporter has no vertex colour option")
    used = {k: v for k, v in wanted.items() if k in props}
    dropped = sorted(k for k in wanted if k not in props)
    return used, dropped


# ------------------------------------------------------------------ geometry

def parent_chain(obj):
    """The names of an object's parents, nearest first (Blender has no parent_recursive)."""
    out = []
    p = obj.parent
    while p is not None:
        out.append(p.name)
        p = p.parent
    return out


DEGENERATE_EDGE = 1e-7    # m: two corners of a triangle this close count as one point (truly degenerate only)
DEGENERATE_AREA = 1e-14   # m^2 (the h2 giraffe's smallest triangle is far above this; nothing real is touched)
DUP_QUANT = 1e-6          # m: positions are compared on this grid when looking for duplicate faces


def _colour_layer(bm, kind, name):
    domain, dtype = kind
    layers = bm.loops.layers if domain == "CORNER" else bm.verts.layers
    layer = (layers.float_color if dtype == "FLOAT_COLOR" else layers.color).get(name)
    if layer is None:
        fail("colour attribute %s (%s, %s) is not in the BMesh" % (name, domain, dtype))
    return layer


def _loop_colour(f, kind, layer):
    """The colour of each corner of a face, from the kept colour attribute (corner or point domain)."""
    if kind[0] == "CORNER":
        return [tuple(round(x, 4) for x in l[layer]) for l in f.loops]
    return [tuple(round(x, 4) for x in l.vert[layer]) for l in f.loops]


def clean_triangles(me, kind, color_name):
    """Triangulates (fixed methods), then, explicitly diagnosed and recorded, never silently:
    1. degenerate triangles (shortest edge < DEGENERATE_EDGE or area < DEGENERATE_AREA): removed;
    2. duplicate faces (the same three positions): classified by winding and per-corner colour.
       Same winding and same colours is a pure duplicate: the later face is removed. Opposite winding
       is a two-sided pair (the library builds thin parts as reversed twins; the material is single-
       sided, so each twin shows one side): both are kept. Same winding with different colours is
       kept and reported for review.
    (h2: the giraffe's GLB held 1182 triangles; Blender's importer merged a duplicate pair to 1181.)
    Then vertices left without a face are removed."""
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.triangulate(bm, faces=bm.faces[:], quad_method="BEAUTY", ngon_method="BEAUTY")
    bm.faces.ensure_lookup_table()
    bm.faces.index_update()
    bm.normal_update()
    layer = _colour_layer(bm, kind, color_name)
    degenerate = []
    for f in bm.faces:
        vs = [v.co for v in f.verts]
        shortest = min((vs[0] - vs[1]).length, (vs[1] - vs[2]).length, (vs[2] - vs[0]).length)
        area = f.calc_area()
        if shortest < DEGENERATE_EDGE or area < DEGENERATE_AREA:
            c = f.calc_center_median()
            degenerate.append((f, {"face": f.index, "area_m2": area, "shortest_edge_m": shortest,
                                   "centre": [round(c.x, 5), round(c.y, 5), round(c.z, 5)]}))
    gone = {f.index for f, _ in degenerate}
    groups = {}
    for f in bm.faces:
        if f.index in gone:
            continue
        key = tuple(sorted(tuple(round(x / DUP_QUANT) for x in v.co) for v in f.verts))
        groups.setdefault(key, []).append(f)
    duplicates = []
    remove_dup = []
    for key, fs in groups.items():
        if len(fs) < 2:
            continue
        first = fs[0]
        for other in fs[1:]:
            same_winding = first.normal.dot(other.normal) > 0.0
            # Colours compared per position, so the corner order does not matter.
            def by_pos(f):
                cols = _loop_colour(f, kind, layer)
                return sorted(zip([tuple(round(x / DUP_QUANT) for x in l.vert.co) for l in f.loops], cols))
            same_colour = by_pos(first) == by_pos(other)
            c = other.calc_center_median()
            entry = {"faces": [first.index, other.index], "same_winding": same_winding, "same_colours": same_colour,
                     "area_m2": other.calc_area(), "centre": [round(c.x, 5), round(c.y, 5), round(c.z, 5)]}
            if same_winding and same_colour:
                entry["action"] = "removed face %d (pure duplicate of %d)" % (other.index, first.index)
                remove_dup.append(other)
            else:
                entry["action"] = "kept both (%s)" % ("two-sided pair" if not same_winding else "same place, different colours: review")
            duplicates.append(entry)
    doomed = [f for f, _ in degenerate] + remove_dup
    if doomed:
        bmesh.ops.delete(bm, geom=doomed, context="FACES_ONLY")
    loose = [v for v in bm.verts if not v.link_faces]
    if loose:
        bmesh.ops.delete(bm, geom=loose, context="VERTS")
    bm.to_mesh(me)
    bm.free()
    me.update()
    return {"triangles_removed": len(doomed), "degenerate_removed": [d for _, d in degenerate],
            "duplicate_pairs": duplicates, "duplicates_removed": len(remove_dup),
            "duplicate_pairs_kept": sum(1 for d in duplicates if d["action"].startswith("kept")),
            "loose_vertices_removed": len(loose),
            "rule": "degenerate: shortest edge < %g m or area < %g m^2; duplicate: same positions on a %g m grid" % (
                DEGENERATE_EDGE, DEGENERATE_AREA, DUP_QUANT)}


def glb_triangles(path):
    """Triangles as written in the GLB itself (index counts, or vertex counts without indices)."""
    import struct
    with open(path, "rb") as f:
        data = f.read()
    n = struct.unpack_from("<I", data, 12)[0]
    js = json.loads(data[20:20 + n].decode("utf-8"))
    total = 0
    for m in js.get("meshes", []):
        for prim in m.get("primitives", []):
            if prim.get("mode", 4) != 4:
                fail("%s: a primitive is not triangles (mode %s)" % (path, prim.get("mode")))
            acc = prim["indices"] if "indices" in prim else prim["attributes"]["POSITION"]
            total += js["accessors"][acc]["count"] // 3
    return total


def world_bounds(mesh):
    xs = [v.co.x for v in mesh.vertices]
    ys = [v.co.y for v in mesh.vertices]
    zs = [v.co.z for v in mesh.vertices]
    return Vector((min(xs), min(ys), min(zs))), Vector((max(xs), max(ys), max(zs)))


def triangles(mesh):
    mesh.calc_loop_triangles()
    return len(mesh.loop_triangles)


def prepared_mesh(src, color_name, yaw_deg, target_h):
    dg = bpy.context.evaluated_depsgraph_get()
    try:
        ev = src.evaluated_get(dg)
        me = bpy.data.meshes.new_from_object(ev, preserve_all_data_layers=True, depsgraph=dg)
    except Exception:
        me = bpy.data.meshes.new_from_object(src, preserve_all_data_layers=True)
    evaluated_tris = triangles(me)                       # the source as evaluated (with its modifiers)
    me.transform(src.matrix_world)                       # bake parents, rotation and scale
    if src.matrix_world.determinant() < 0:   # a mirrored transform turns the faces inside out
        try:
            me.flip_normals()
        except AttributeError:
            bm = bmesh.new()
            bm.from_mesh(me)
            bmesh.ops.reverse_faces(bm, faces=bm.faces)
            bm.to_mesh(me)
            bm.free()
    me.transform(Matrix.Rotation(math.radians(yaw_deg), 4, "Z"))
    lo, hi = world_bounds(me)
    h = hi.z - lo.z
    if h <= 1e-6:
        fail("%s has no height" % src.name)
    s = target_h / h
    me.transform(Matrix.Scale(s, 4))
    lo, hi = world_bounds(me)
    me.transform(Matrix.Translation(Vector((-(lo.x + hi.x) * 0.5, -(lo.y + hi.y) * 0.5, -lo.z))))
    # Colour: keep exactly the named attribute.
    names = [a.name for a in me.color_attributes]
    if color_name not in names:
        fail("%s has no colour attribute %s (has %s)" % (src.name, color_name, names))
    for n in names:
        if n != color_name:
            me.color_attributes.remove(me.color_attributes[n])
    ca = me.color_attributes[color_name]
    try:
        me.color_attributes.active_color = ca
    except Exception:
        me.color_attributes.active_color_name = color_name
    try:
        me.color_attributes.render_color_index = list(me.color_attributes).index(ca)
    except Exception:
        pass
    while me.uv_layers:
        me.uv_layers.remove(me.uv_layers[0])
    removed = clean_triangles(me, (ca.domain, ca.data_type), color_name)
    me.materials.clear()
    me.materials.append(matte_material(color_name))
    removed["source_triangles_evaluated"] = evaluated_tris
    return me, s, h, (ca.domain, ca.data_type), removed


_MAT = {}


def matte_material(color_name):
    if color_name in _MAT:
        return _MAT[color_name]
    m = bpy.data.materials.new("everything_matte")
    try:
        m.use_nodes = True   # deprecated in Blender 5 (always on); harmless where it still exists
    except (AttributeError, TypeError):
        pass
    nt = m.node_tree
    if nt is None:
        fail("the material has no node tree")
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    col = nt.nodes.new("ShaderNodeVertexColor")
    col.layer_name = color_name
    bsdf.inputs["Roughness"].default_value = 1.0
    bsdf.inputs["Metallic"].default_value = 0.0
    # Single-sided (glTF doubleSided false): thin parts are reversed twin faces in the library, so each
    # side is drawn by its own face, as in the game's other models (back faces culled).
    try:
        m.use_backface_culling = True
    except AttributeError:
        pass
    nt.links.new(col.outputs["Color"], bsdf.inputs["Base Color"])
    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    _MAT[color_name] = m
    return m


# ------------------------------------------------------------------ export and checks

def select_only(obj):
    for o in bpy.context.view_layer.objects:
        if o.select_get():
            o.select_set(False)
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj


def export(obj, path):
    opts, dropped = export_options(path)
    select_only(obj)
    res = bpy.ops.export_scene.gltf(**opts)
    if "FINISHED" not in res:
        fail("export of %s returned %s" % (obj.name, res))
    return opts, dropped


def check_reimport(path, a, tris_expected, color_name, dup_kept=0):
    """Imports the GLB into a new empty scene and measures it. Returns the measurements."""
    images_before = len(bpy.data.images)
    before = set(bpy.data.objects.keys())
    win_scene = bpy.context.scene
    coll = bpy.data.collections.new("check_" + a["asset_id"])
    win_scene.collection.children.link(coll)
    layer_coll = bpy.context.view_layer.layer_collection.children[coll.name]
    bpy.context.view_layer.active_layer_collection = layer_coll
    res = bpy.ops.import_scene.gltf(filepath=path)
    if "FINISHED" not in res:
        fail("re-import of %s returned %s" % (path, res))
    new = [bpy.data.objects[n] for n in set(bpy.data.objects.keys()) - before]
    meshes = [o for o in new if o.type == "MESH"]
    others = [o.type for o in new if o.type != "MESH"]
    if len(meshes) != 1:
        fail("%s re-imports as %d meshes (%s other objects)" % (path, len(meshes), others))
    m = meshes[0]
    bpy.context.view_layer.update()
    me = m.data.copy()
    me.transform(m.matrix_world)
    lo, hi = world_bounds(me)
    tris = triangles(me)
    colors = [c.name for c in me.color_attributes]
    images = len(bpy.data.images) - images_before
    got = {"triangles": tris, "height": hi.z - lo.z, "min_z": lo.z,
           "center_xy": [(lo.x + hi.x) * 0.5, (lo.y + hi.y) * 0.5],
           "size": [hi.x - lo.x, hi.y - lo.y, hi.z - lo.z], "color_attributes": colors,
           "images": images, "other_objects": others}
    problems = []
    # Blender's importer merges a face that repeats another's corners; only the kept duplicate pairs
    # (diagnosed and recorded at preparation) may account for a shortfall, exactly.
    if tris != tris_expected and tris != tris_expected - dup_kept:
        problems.append("re-imported triangles %d, file %d, kept duplicate pairs %d" % (tris, tris_expected, dup_kept))
    if abs(got["height"] - a["target_height"]) > 0.005:
        problems.append("height %.4f, target %.2f" % (got["height"], a["target_height"]))
    if abs(lo.z) > 0.002:
        problems.append("lowest point %.4f, not on the ground" % lo.z)
    if max(abs(got["center_xy"][0]), abs(got["center_xy"][1])) > 0.002:
        problems.append("footprint not centred %s" % got["center_xy"])
    if not colors:
        problems.append("no colour attribute after re-import")
    if images:
        problems.append("%d image(s) came with it" % images)
    for o in new:
        bpy.data.objects.remove(o, do_unlink=True)
    bpy.data.meshes.remove(me)
    win_scene.collection.children.unlink(coll)
    bpy.data.collections.remove(coll)
    if problems:
        fail("%s: %s" % (a["asset_id"], "; ".join(problems)))
    return got


# ------------------------------------------------------------------ previews

def preview(objs, path, view, size=320):
    scene = bpy.data.scenes.new("preview")
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.render.resolution_x = size
    scene.render.resolution_y = size
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.film_transparent = False
    shading = scene.display.shading
    shading.light = "STUDIO"
    shading.color_type = "VERTEX"
    world = bpy.data.worlds.new("preview_world")
    world.color = (0.86, 0.9, 0.86)
    scene.world = world
    lo = Vector((1e9, 1e9, 1e9))
    hi = Vector((-1e9, -1e9, -1e9))
    for o in objs:
        scene.collection.objects.link(o)
        # From the mesh and the location (these objects carry no rotation or scale): matrix_world and
        # bound_box are not refreshed for new or moved objects in background mode.
        mlo, mhi = world_bounds(o.data)
        lo = Vector(map(min, lo, mlo + o.location))
        hi = Vector(map(max, hi, mhi + o.location))
    cam_data = bpy.data.cameras.new("preview_cam")
    cam_data.type = "ORTHO"
    centre = (lo + hi) * 0.5
    span = max(hi.x - lo.x, hi.y - lo.y, hi.z - lo.z) * 1.15
    cam_data.ortho_scale = span
    cam = bpy.data.objects.new("preview_cam", cam_data)
    scene.collection.objects.link(cam)
    d = span * 3.0
    if view == "front":       # the camera stands in front of the animal: on Blender -Y, looking +Y
        cam.location = centre + Vector((0, -d, 0))
        cam.rotation_euler = (math.radians(90), 0, 0)
    else:                     # side: on Blender +X, looking -X (the front points left in the image)
        cam.location = centre + Vector((d, 0, 0))
        cam.rotation_euler = (math.radians(90), 0, math.radians(90))
    cam_data.clip_end = d * 4
    scene.camera = cam
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True, scene=scene.name)
    for o in objs:
        scene.collection.objects.unlink(o)
    bpy.data.objects.remove(cam, do_unlink=True)
    bpy.data.cameras.remove(cam_data)
    bpy.data.scenes.remove(scene)
    bpy.data.worlds.remove(world)


# ------------------------------------------------------------------ main

def main():
    a = args()
    out = os.path.abspath(a["out"])
    os.makedirs(out, exist_ok=True)
    if os.listdir(out):
        fail("output folder %s is not empty" % out)
    for sub in ["models", "manifests", "previews"]:
        os.makedirs(os.path.join(out, sub), exist_ok=True)
    with open(a["spec"]) as f:
        spec = json.load(f)
    bpy.context.view_layer.update()   # the source objects' world transforms are current
    src_path = bpy.data.filepath
    src_hash = sha256(src_path)
    log("blender %s, source %s sha256 %s" % (bpy.app.version_string, os.path.basename(src_path), src_hash))
    if src_hash != spec["source_sha256"]:
        fail("source SHA-256 %s does not match the spec %s" % (src_hash, spec["source_sha256"]), out)
    # The embedded licence (a text block in the file), copied verbatim.
    lic = [t.as_string() for t in bpy.data.texts]
    if not any("Creative Commons Attribution 4.0" in t for t in lic):
        fail("no embedded licence text naming CC BY 4.0 was found", out)
    with open(os.path.join(out, "source_license.txt"), "w") as f:
        f.write("\n\n---\n\n".join(lic))
    color_name = spec["color_attribute"]
    batch = {"batch": spec["batch"], "blender": bpy.app.version_string,
             "blender_build": bpy.app.build_hash.decode() if isinstance(bpy.app.build_hash, bytes) else str(bpy.app.build_hash),
             "source_file": os.path.basename(src_path), "source_sha256": src_hash,
             "spec_sha256": sha256(a["spec"]), "assets": []}
    made = []
    tmp = tempfile.mkdtemp(prefix="everything_repeat_")
    for asset in spec["assets"]:
        aid = asset["asset_id"]
        src = bpy.data.objects.get(asset["source_object"])
        if src is None or src.type != "MESH":
            fail("%s: source object %s is missing or not a mesh" % (aid, asset["source_object"]), out)
        parent = src.parent.name if src.parent else ""
        root = src
        while root.parent:
            root = root.parent
        chain = parent_chain(src)
        if asset["source_parent"] not in chain:
            fail("%s: %s is not under %s (parents %s)" % (aid, src.name, asset["source_parent"], chain), out)
        # Report (never export) the other meshes under the same parent, e.g. the alternative lion.
        siblings = [o.name for o in bpy.data.objects if o.type == "MESH" and o != src
                    and asset["source_parent"] in parent_chain(o)]
        me, scale, src_h, ca_kind, removed = prepared_mesh(src, color_name, float(asset.get("yaw_deg", 0)), float(asset["target_height"]))
        src_tris = removed["source_triangles_evaluated"]
        tris = triangles(me)
        if tris + removed["triangles_removed"] != src_tris:
            fail("%s: %d triangles prepared + %d removed is not the source's %d" % (aid, tris, removed["triangles_removed"], src_tris), out)
        log("%s: source %d triangles; degenerate removed %s; duplicate pairs %s; %d loose vertices removed" % (
            aid, src_tris, removed["degenerate_removed"], removed["duplicate_pairs"], removed["loose_vertices_removed"]))
        obj = bpy.data.objects.new(aid, me)
        bpy.context.scene.collection.objects.link(obj)
        glb = os.path.join(out, "models", aid + ".glb")
        opts, dropped = export(obj, glb)
        h1 = sha256(glb)
        rep = os.path.join(tmp, aid + ".glb")
        export(obj, rep)
        h2 = sha256(rep)
        if h1 != h2:
            fail("%s: two exports differ (%s, %s)" % (aid, h1, h2), out)
        file_tris = glb_triangles(glb)
        if file_tris != tris:
            fail("%s: the GLB holds %d triangles, %d were prepared" % (aid, file_tris, tris), out)
        got = check_reimport(glb, asset, file_tris, color_name, removed["duplicate_pairs_kept"])
        got["file_triangles"] = file_tris
        got["importer_merged"] = file_tris - got["triangles"]
        got["accounted_by_kept_duplicate_pairs"] = removed["duplicate_pairs_kept"]
        log("%s: GLB %d triangles; Blender re-import %d (merged %d; kept duplicate pairs %d)" % (
            aid, file_tris, got["triangles"], got["importer_merged"], removed["duplicate_pairs_kept"]))
        lo, hi = world_bounds(me)
        man = {"asset_id": aid, "species": asset["species"], "batch": spec["batch"],
               "source": {"file": os.path.basename(src_path), "sha256": src_hash, "object": src.name,
                          "parent": parent, "root": root.name, "other_meshes_under_parent_not_exported": siblings},
               "license": "CC BY 4.0, Everything Library (c) David OReilly",
               "changes": ["extracted alone", "world transform baked", "yaw %.1f deg" % float(asset.get("yaw_deg", 0)),
                           "uniform scale %.6f (source height %.4f m to %.2f m)" % (scale, src_h, asset["target_height"]),
                           "origin at footprint centre on the ground", "only colour attribute %s kept" % color_name,
                           "UVs removed", "triangulated (beauty)",
                           "%d degenerate and %d pure duplicate triangle(s) removed" % (len(removed["degenerate_removed"]), removed["duplicates_removed"]),
                           "one matte vertex-colour material"],
               "units": spec["units"], "target_height": asset["target_height"],
               "bounds": [hi.x - lo.x, hi.z - lo.z, hi.y - lo.y],
               "bounds_note": "glTF axes: x width, y height, z length",
               "triangles": tris, "source_triangles": src_tris, "degenerate": removed, "color_attribute": {"name": color_name, "domain": ca_kind[0], "type": ca_kind[1]},
               "glb": "models/%s.glb" % aid, "glb_sha256": h1, "glb_bytes": os.path.getsize(glb),
               "reimport_check": got, "exporter_options": {k: v for k, v in opts.items() if k != "filepath"},
               "exporter_options_not_in_this_blender": dropped}
        with open(os.path.join(out, "manifests", aid + ".manifest.json"), "w") as f:
            json.dump(man, f, indent=1, sort_keys=True)
        batch["assets"].append({"asset_id": aid, "glb": man["glb"], "glb_sha256": h1, "triangles": tris,
                                "height": asset["target_height"], "source_object": src.name})
        log("%s: %s from %s, %d triangles, height %.2f m, %s" % (aid, os.path.basename(glb), src.name, tris, asset["target_height"], h1))
        made.append((aid, obj))
    shutil.rmtree(tmp, ignore_errors=True)
    if a["previews"]:
        for aid, obj in made:
            for view in ["front", "side"]:
                preview([obj], os.path.join(out, "previews", "%s_%s.png" % (aid, view)), view)
        # Lineup: every animal side by side in spec order, and a 1.30 m box for the child, front view.
        x = 0.0
        moved = []
        for aid, obj in made:
            lo, hi = world_bounds(obj.data)
            obj.location.x = x - lo.x
            x += (hi.x - lo.x) + 0.6
            moved.append(obj)
        kid = bpy.data.meshes.new("child_130")
        bm = bmesh.new()
        bmesh.ops.create_cube(bm, size=1.0)
        bm.to_mesh(kid)
        bm.free()
        kid.transform(Matrix.Translation(Vector((0, 0, 0.5))))
        kid.transform(Matrix.Diagonal(Vector((0.45, 0.3, 1.30, 1.0))))
        kid_obj = bpy.data.objects.new("child_130", kid)
        kid_obj.location.x = x + 0.2
        preview(moved + [kid_obj], os.path.join(out, "previews", "lineup_front.png"), "front", 960)
        bpy.data.objects.remove(kid_obj, do_unlink=True)
        for obj in moved:
            obj.location.x = 0.0
    files = sorted(os.path.relpath(os.path.join(r, n), out) for r, _, ns in os.walk(out) for n in ns)
    batch["files"] = {p: sha256(os.path.join(out, p)) for p in files if p != "batch_manifest.json"}
    end_hash = sha256(src_path)
    if end_hash != src_hash:
        fail("the source file changed during the run (%s)" % end_hash, out)
    batch["source_sha256_after"] = end_hash
    log("source unchanged after the run: %s" % end_hash)
    with open(os.path.join(out, "batch_manifest.json"), "w") as f:
        json.dump(batch, f, indent=1, sort_keys=True)
    log("PASS %d assets" % len(made))
    with open(os.path.join(out, "export_log.txt"), "w") as f:
        f.write("\n".join(LOG) + "\n")


main()
