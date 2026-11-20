#!/usr/bin/env python3
"""Writes the checker's self-test fixtures as plain glTF binaries (no Blender, no Godot), shaped like
the Blender export: one mesh node, POSITION + NORMAL + COLOR_0 (linear float RGBA), one material with
baseColorFactor 1, metallic 0, roughness 1. One fixture is right; each other is wrong in one way.

  python3 make_fixtures.py <pack folder>   # writes <pack>/models/*.glb and <pack>/manifests/*.json

COLOR_0 values are linear, as glTF requires. The right fixture's faces are sRGB 0.5 grey (linear
0.2140), pure red, pure green and pure blue, so the checker can tell whether Godot keeps colours linear.
"""
import hashlib
import json
import os
import struct
import sys
import zlib

SRGB_HALF_LINEAR = 0.21404114  # sRGB 0.5 in linear


def box(height, lift=0.0, w=0.4):
    c = [(-w, lift, -w), (w, lift, -w), (w, lift, w), (-w, lift, w),
         (-w, lift + height, -w), (w, lift + height, -w), (w, lift + height, w), (-w, lift + height, w)]
    faces = [(0, 1, 2, 3), (7, 6, 5, 4), (0, 4, 5, 1), (1, 5, 6, 2), (2, 6, 7, 3), (3, 7, 4, 0)]
    return c, faces


def mesh_arrays(height, lift, palette):
    c, faces = box(height, lift)
    pos, nor, col = [], [], []
    for i, f in enumerate(faces):
        a, b, cc = c[f[0]], c[f[1]], c[f[2]]
        u = [b[k] - a[k] for k in range(3)]
        v = [cc[k] - a[k] for k in range(3)]
        n = [u[1] * v[2] - u[2] * v[1], u[2] * v[0] - u[0] * v[2], u[0] * v[1] - u[1] * v[0]]
        ln = sum(x * x for x in n) ** 0.5 or 1.0
        n = [x / ln for x in n]
        colour = palette[i % len(palette)] if palette else None
        for tri in [(f[0], f[1], f[2]), (f[0], f[2], f[3])]:
            for k in tri:
                pos.append(c[k])
                nor.append(n)
                if colour:
                    col.append(colour)
    return pos, nor, col


def tiny_png():
    raw = b"\x00" + b"\xff\xff\xff" * 2 + b"\x00" + b"\xff\xff\xff" * 2
    def chunk(t, d):
        return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xffffffff)
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", 2, 2, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b""))


def write_glb(path, meshes, metallic=0.0, texture=False, double_sided=False):
    """meshes: list of (pos, nor, col) for separate mesh nodes."""
    bin_ = bytearray()
    views, accessors, gl_meshes, nodes = [], [], [], []

    def add(data, fmt, count, ctype, kind, minmax=None):
        while len(bin_) % 4:
            bin_.append(0)
        off = len(bin_)
        for row in data:
            bin_.extend(struct.pack("<" + fmt, *row))
        views.append({"buffer": 0, "byteOffset": off, "byteLength": len(bin_) - off})
        acc = {"bufferView": len(views) - 1, "componentType": ctype, "count": count, "type": kind}
        if minmax:
            acc["min"], acc["max"] = minmax
        accessors.append(acc)
        return len(accessors) - 1

    material = {"pbrMetallicRoughness": {"baseColorFactor": [1, 1, 1, 1], "metallicFactor": metallic, "roughnessFactor": 1.0},
                "name": "everything_matte", "doubleSided": double_sided}
    images, textures, samplers = [], [], []
    for mi, (pos, nor, col) in enumerate(meshes):
        mn = [min(p[k] for p in pos) for k in range(3)]
        mx = [max(p[k] for p in pos) for k in range(3)]
        attrs = {"POSITION": add(pos, "3f", len(pos), 5126, "VEC3", (mn, mx)),
                 "NORMAL": add(nor, "3f", len(nor), 5126, "VEC3")}
        if col:
            attrs["COLOR_0"] = add([tuple(c) + (1.0,) for c in col], "4f", len(col), 5126, "VEC4")
        if texture:
            attrs["TEXCOORD_0"] = add([(0.0, 0.0)] * len(pos), "2f", len(pos), 5126, "VEC2")
        gl_meshes.append({"primitives": [{"attributes": attrs, "material": 0}]})
        nodes.append({"mesh": mi, "name": "mesh%d" % mi, "translation": [mi * 1.0, 0, 0]})
    if texture:
        png = tiny_png()
        while len(bin_) % 4:
            bin_.append(0)
        off = len(bin_)
        bin_.extend(png)
        views.append({"buffer": 0, "byteOffset": off, "byteLength": len(png)})
        images.append({"bufferView": len(views) - 1, "mimeType": "image/png"})
        samplers.append({})
        textures.append({"source": 0, "sampler": 0})
        material["pbrMetallicRoughness"]["baseColorTexture"] = {"index": 0}
    while len(bin_) % 4:
        bin_.append(0)
    gltf = {"asset": {"version": "2.0", "generator": "lantern-lane selftest"},
            "scene": 0, "scenes": [{"nodes": list(range(len(nodes)))}], "nodes": nodes, "meshes": gl_meshes,
            "materials": [material], "accessors": accessors, "bufferViews": views,
            "buffers": [{"byteLength": len(bin_)}]}
    if images:
        gltf.update({"images": images, "textures": textures, "samplers": samplers})
    js = json.dumps(gltf, separators=(",", ":")).encode()
    while len(js) % 4:
        js += b" "
    out = struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(bin_))
    out += struct.pack("<II", len(js), 0x4E4F534A) + js + struct.pack("<II", len(bin_), 0x004E4942) + bytes(bin_)
    with open(path, "wb") as f:
        f.write(out)
    return sum(len(m[0]) for m in meshes) // 3


def main():
    pack = sys.argv[1]
    os.makedirs(os.path.join(pack, "models"), exist_ok=True)
    os.makedirs(os.path.join(pack, "manifests"), exist_ok=True)
    g = SRGB_HALF_LINEAR
    good = [(g, g, g), (1.0, 0.0, 0.0), (0.0, 1.0, 0.0), (0.0, 0.0, 1.0)]
    cases = {
        "fx_good": ([mesh_arrays(1.0, 0.0, good)], {}, 1.0),
        "fx_no_colour": ([mesh_arrays(1.0, 0.0, None)], {}, 1.0),
        "fx_one_colour": ([mesh_arrays(1.0, 0.0, [good[1]])], {}, 1.0),
        "fx_wrong_height": ([mesh_arrays(1.2, 0.0, good)], {}, 1.0),
        "fx_floating": ([mesh_arrays(1.0, 0.3, good)], {}, 1.0),
        "fx_textured": ([mesh_arrays(1.0, 0.0, good)], {"texture": True}, 1.0),
        "fx_metal": ([mesh_arrays(1.0, 0.0, good)], {"metallic": 0.8}, 1.0),
        "fx_double_sided": ([mesh_arrays(1.0, 0.0, good)], {"double_sided": True}, 1.0),
        "fx_two_meshes": ([mesh_arrays(1.0, 0.0, good), mesh_arrays(1.0, 0.0, good)], {}, 1.0),
        "fx_wrong_sha": ([mesh_arrays(1.0, 0.0, good)], {}, 1.0),
    }
    for aid, (meshes, kw, h) in cases.items():
        path = os.path.join(pack, "models", aid + ".glb")
        tris = write_glb(path, meshes, **kw)
        sha = hashlib.sha256(open(path, "rb").read()).hexdigest()
        man = {"asset_id": aid, "target_height": h, "triangles": tris, "glb_sha256": "0" * 64 if aid == "fx_wrong_sha" else sha}
        if aid == "fx_good":
            man["colour_probe_linear"] = [g, g, g]   # the grey face, as stored in the file
        with open(os.path.join(pack, "manifests", aid + ".manifest.json"), "w") as f:
            json.dump(man, f, indent=1)
        print("FIXTURE %s %d triangles %s" % (aid, tris, sha[:12]))


if __name__ == "__main__":
    main()
