# everything-zoo-r1: six animals, ready to use in Godot 4.7.2

**What this is:** a self-contained Godot 4.7.2 project with six static animal models. The import already makes them coloured: the post-import turns the vertex colours on as albedo. It also has a checker and a lineup renderer.

**What it is not:** the game. Nothing here is in Lantern Lane's catalog or gameplay, and no zoo resident is replaced.

**Attribution:** "Everything Library – Animals 0.2" © David OReilly, CC BY 4.0 (<https://creativecommons.org/licenses/by/4.0/>). The changes and the embedded license text are in [LICENSE-NOTICE.md](LICENSE-NOTICE.md) and `source_license.txt`. Anyone shipping these models must show this attribution.

| Model | Height | Triangles |
|---|---|---|
| `models/everything_panda.glb` | 1.10 m | 1198 |
| `models/everything_lion.glb` | 1.55 m | 1264 |
| `models/everything_elephant.glb` | 2.40 m | 1076 |
| `models/everything_giraffe.glb` | 2.80 m | 1182 |
| `models/everything_zebra.glb` | 1.65 m | 1576 |
| `models/everything_penguin.glb` | 1.00 m | 776 |

All the models share these properties:
- **Axes:** +Y up, the front facing +Z, the origin at the footprint centre on the ground, 1 unit = 1 m.
- **Colour:** in `COLOR_0` (linear); no texture.
- **Material:** single-sided and matte.

**Provenance:** the models are the Mac's Blender 5.2.2 run3 of `scripts/blender/everything_export.py` (handoff `script-h3`), unchanged. Their hashes are in `batch_manifest.json`, with one manifest per model in `manifests/`.

## Why the post-import

Godot 4.7.2's glTF import keeps the colours, linear, but leaves "vertex colour as albedo" off, so the models would be grey. `import/everything_post_import.gd` runs for every scene (`[importer_defaults]` in `project.godot`) and sets three things in the imported scene itself:
- `vertex_color_use_as_albedo` on;
- `vertex_color_is_srgb` off;
- the game's Lambert-wrap diffuse.

A loaded `.glb` is coloured with no further code. To use a model in another project, take the script with it and set it as that file's import script.

## Commands

Work on a disposable copy of this folder. `<godot>` is Godot 4.7.2 stable.

```sh
cp -R godot-pack /tmp/ez-work            # any new, empty location
<godot> --headless --path /tmp/ez-work --import                      # exit 0
<godot> --headless --path /tmp/ez-work -s res://check.gd             # prints EVERYTHING CHECK PASS: 103 checks, 0 failures
<godot> --path /tmp/ez-work --resolution 1280x720 -s res://render_lineup.gd -- --out=/abs/out   # GPU window
```

**The checker** (`check_report.json`, written into the work copy) checks each model for:
- the GLB hash;
- the post-import having run;
- one mesh;
- every vertex coloured, with the colours varied;
- a vertex-colour albedo that is linear, with Lambert wrap;
- no texture;
- matte;
- back faces culled;
- triangles, height, ground contact and centring.

It also reports each model's average colour (sRGB) as information, not as a gate.

**The renderer** writes `lineup_front.png` and `lineup_zoo_camera.png`: the six models and a 1.30 m box for the child, under the game's town daylight.

**Optional, checker self-test** (Python 3 standard library; Godot headless; it renders nothing):

```sh
python3 selftest/run_selftest.py --godot <godot> --work /tmp/ez-selftest   # prints SELFTEST PASS: 10 fixtures, 0 problems
```

## Results on EC2 (headless Linux, Godot 4.7.2; nothing rendered)

- **Import:** exit 0.
- **Checker:** PASS, 103 checks, 0 failures.
- **Self-test:** PASS, 10 fixtures, 0 problems:
  - the good fixture passes every check, and its colour arrives linear (0.214 stays 0.214);
  - each broken fixture fails only its own check.
- **Average colour per model** (sRGB):

| Model | Average colour (sRGB) |
|---|---|
| elephant | 0.37, 0.36, 0.34 |
| giraffe | 0.58, 0.47, 0.36 |
| lion | 0.58, 0.50, 0.43 |
| panda | 0.55, 0.53, 0.49 |
| penguin | 0.50, 0.46, 0.44 |
| zebra | 0.50, 0.49, 0.49 |

The darkness the Blender previews show is the library's own palette, most of all the elephant's. The import does not cause it.
