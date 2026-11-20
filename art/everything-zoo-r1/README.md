# everything-zoo-r1: six animals from the Everything Library

**Status:** the extraction script and spec are sealed as handoff `script-h3`; `build/dual-host/everything-zoo/SEAL-script-h3.md` has the manifest hash. Earlier handoffs stay frozen and unchanged:
- **h1** crashed on `Object.parent_recursive`, which Blender does not have.
- **h2** stopped at the giraffe. Its GLB held 1182 triangles, but Blender's re-import showed 1181: the importer merges one reversed twin pair of faces, a two-sided thin part.

`--python-exit-code 1` makes any Python error end the run with exit 1, not 0.

**Triangle rule since h3** (`clean_triangles` in the script; every case is recorded in the asset's manifest):
- **Truly degenerate triangles are removed:** shortest edge under 0.1 µm, or area under 1e-14 m².
- **Duplicates** (faces with the same three positions) are classified by winding and per-corner colour:
  - a **pure duplicate** (same winding, same colours) is removed;
  - a **reversed twin** is kept, since it is the other side of a thin part;
  - **same winding, different colours** is kept and flagged for review.
- **The material is single-sided**, so each twin draws one side.
- **Counts are exact:**
  - the triangles inside the GLB must equal the prepared count;
  - prepared plus removed must equal the source;
  - Blender's re-import may fall short of the GLB only by exactly the number of kept twin pairs, and that number is recorded.

**Source, read-only and never edited:**
- **File:** `assets-to-import/everything-animals-20261116/EverythingLibrary_Animals_002.blend`
- **SHA-256:** `7fc0a8c61b2dd2750bcc70bd4491b60e96b6cb25d0654c4a6c1b36f82a260627`
- **Contents:** 243 meshes, 0 armatures, 0 actions (`mac-inventory.json`).
- **License:** CC BY 4.0; see [LICENSE-NOTICE.md](LICENSE-NOTICE.md).

**Selection** (`spec.json`):

| Asset | Source object | Height |
|---|---|---|
| everything_panda | `Panda/base.030` | 1.10 m |
| everything_lion | `Lion/alt604` | 1.55 m |
| everything_elephant | `Elephant/base.058` | 2.40 m |
| everything_giraffe | `Giraffe/base.059` | 2.80 m |
| everything_zebra | `Zebra/base.070` | 1.65 m |
| everything_penguin | `Penguin/base.098` | 1.00 m |

`alt605`, the alternative lion, is not exported.

## Run (Mac, Blender 5.2.2)

From the project root, into a new empty folder:

```sh
blender -b --factory-startup \
  assets-to-import/everything-animals-20261116/EverythingLibrary_Animals_002.blend \
  --python-exit-code 1 --python scripts/blender/everything_export.py -- \
  --spec art/everything-zoo-r1/spec.json --out build/everything-zoo-r1/run3 \
  > build/everything-zoo-r1/run3.console.txt 2>&1; echo "exit $?"
```

**Prerequisite:** create the folder `build/everything-zoo-r1/` first, so the console file can be written.

**Disk:** the output is small. Six GLBs of about 1.6k triangles each, 12 previews at 320 px, and a 960 px lineup add up to well under 5 MB.

**What a passing run looks like:**
- exit code 0;
- `EVERYTHING PASS 6 assets` printed;
- the source SHA-256 unchanged before and after.

On any failed check the script stops with exit 1 and writes the reason to `export_log.txt`. Return the folder either way.

## Return to EC2

Send the whole `build/everything-zoo-r1/run3/` folder and `run3.console.txt`:
- `models/*.glb`;
- `manifests/*.manifest.json`;
- `batch_manifest.json`, with every file's SHA-256;
- `source_license.txt`;
- `export_log.txt`;
- `previews/*_front.png`, `*_side.png` and `lineup_front.png`.

Add the Blender binary version and platform. The owner opens every preview. If a front view does not show the animal's face, only that asset's `yaw_deg` in `spec.json` changes, and the run repeats into a new folder, `run4`.

## Then on EC2 (the owner)

The GLBs go to `game/assets/models/zoo_everything/` as **staged standalone resources**:
- **Not in gameplay:** they are not in any catalog or toy box, and no zoo resident is replaced. Rory, Topper and Zig/Zag keep their rigs and all their actions.
- **A headless Godot validation:** the import, one mesh per asset, vertex colours used as albedo, no texture, a matte material, the bounds and ground contact, triangle counts and hashes matching the manifests.
- **Credits:** the in-game credits line for CC BY 4.0, and `docs/assets.md`.
