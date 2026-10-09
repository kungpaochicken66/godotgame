#!/usr/bin/env python3
"""Integrate the 42 model_complete furniture references (production models r2) from FROZEN batches (read-only).

Sources (tools/nookipedia-model-production, never modified here):
  - b011-furn-r2 (38 ceiling items + 4 wall items v2), minus the 11 ids its DEFECT NOTICE (validator v2.4, inside-out
    pieces) says not to integrate; those 11 come from their repaired versions in b012-furn-r3.
Every batch must match its FROZEN record and the expected digest, every GLB its manifest hash, and every asset the
game's own contract (anchor origin, size class band, footprint); otherwise nothing is written. Accepted GLBs are
copied byte-for-byte to game/assets/models/<id>.glb; the catalog block "production models r2" in
game/scripts/core/catalog.gd and the six locale catalogs (names from design/model-release-r2-names.tsv) are
generated. The 42 references are the model_complete furniture rows of progress/backlog_inventory.csv.

  python3 scripts/build_furniture_r2.py            # build
  python3 scripts/build_furniture_r2.py --check    # verify only (exit 1 on any difference)
"""
import csv
import hashlib
import json
import shutil
import struct
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LAB = ROOT / 'tools/nookipedia-model-production'
MODELS = ROOT / 'game/assets/models'
CATALOG = ROOT / 'game/scripts/core/catalog.gd'
LOCALES = ['en', 'zh-CN', 'ja', 'es', 'fr', 'de']
NAMES = ROOT / 'design/model-release-r2-names.tsv'
H = 1.30
BATCHES = {'b011-furn-r2': '1b10021d3e43daa9d83f80e9aabad6fcfca9d308ceb04fdca809ba292ac86abe',
           'b012-furn-r3': 'cd8e0084737c79dac2f8ad01eb6a0cf9d2b48e3209cad7704fea212a4ceafda5'}
# INTEGRATION_QUEUE.md DEFECT NOTICE (2026-10-07): these b011 versions fail validator v2.4 G2 inside_out; the
# repaired versions are frozen in b012-furn-r3. The other 31 b011 assets pass v2.4.
B011_DEFECTIVE = {'barrel_wood_pendant', 'ceiling_spotlight_bar', 'cone_shade_pendant', 'crystal_chandelier',
                  'drum_shade_pendant', 'enamel_pendant', 'nordic_pendant', 'paper_lantern_string', 'red_paper_lantern',
                  'tiered_lantern_cluster', 'umbrella_pendant'}
BEGIN = '\t# BEGIN production models r2'
END = '\t# END production models r2'


def sha(b: bytes) -> str:
    return hashlib.sha256(b).hexdigest()


def gd_vec(v) -> str:
    return 'Vector3(%s)' % ', '.join(_num(x) for x in v)


def _num(x) -> str:
    s = ('%.3f' % x).rstrip('0').rstrip('.')
    return s + '.0' if '.' not in s else s


def main() -> int:
    check_only = '--check' in sys.argv
    refs = [r for r in csv.DictReader(open(LAB / 'progress/backlog_inventory.csv', encoding='utf-8'))
            if r['type'] == 'furniture' and r['stage'] == 'model_complete']
    ids = sorted({r['asset_id'] for r in refs})
    assert len(refs) == 42 and len(ids) == 42, (len(refs), len(ids))
    manifests = {}
    for b, want in BATCHES.items():
        d = LAB / 'batches' / b
        frozen = (d / 'FROZEN').read_text().strip().split('sha256(BATCH_MANIFEST.json)=')[1].strip()
        got = sha((d / 'BATCH_MANIFEST.json').read_bytes())
        if not (frozen == got == want):
            print(f'FAIL {b}: BATCH_MANIFEST {got}, FROZEN {frozen}, expected {want}')
            return 1
        manifests[b] = json.loads((d / 'BATCH_MANIFEST.json').read_text())['assets']
    assert set(manifests['b012-furn-r3']) == B011_DEFECTIVE
    names = {}
    rows = NAMES.read_text(encoding='utf-8').strip().split('\n')
    hdr = rows[0].split('\t')
    for line in rows[1:]:
        c = line.split('\t')
        names[c[0]] = dict(zip(hdr[1:], c[1:]))
    assert set(names) == set(ids), set(names) ^ set(ids)
    en = json.loads((ROOT / 'game/locale/en.json').read_text())
    entries, glbs, bad = {}, {}, []
    for aid in ids:
        b = 'b012-furn-r3' if aid in B011_DEFECTIVE else 'b011-furn-r2'
        a = manifests[b][aid]
        glb = (LAB / 'batches' / b / a['glb']).read_bytes()
        m = json.loads((LAB / 'batches' / b / a['manifest']).read_text())
        if sha(glb) != a['sha256'] or m['mesh']['glb_sha256'] != a['sha256']:
            bad.append(f'{aid}: GLB hash')
        if not all(v for k, v in m['validation'].items() if k.startswith('G')):
            bad.append(f'{aid}: validation gates')
        w, h, dep = m['bounds']
        mn, mx = m['bounds_min'], m['bounds_max']
        cls, anchor = m['size_class'], m['anchor']
        if anchor == 'ceiling' and abs(mx[1]) > 0.01:
            bad.append(f'{aid}: ceiling origin is not the hook (top {mx[1]})')
        offset = None
        if anchor == 'wall':
            if mn[2] < -0.02 or abs((mn[0] + mx[0]) / 2) > 0.02:
                bad.append(f'{aid}: wall origin is not on the back plane, centered in x')
            cy = (mn[1] + mx[1]) / 2
            if abs(cy) > 0.02:
                # The lab's G3 checks the back plane and x only; the game hangs wall items by their vertical
                # center. Shift the model in the game (catalog model_offset) instead of rewriting frozen bytes.
                offset = [0.0, round(-cy, 3), 0.0]
        if anchor not in ('wall', 'ceiling'):
            bad.append(f'{aid}: anchor {anchor}')
        f32 = struct.unpack('<f', struct.pack('<f', round(h, 3)))[0]   # the game stores bounds as float32
        if cls == 'small' and not (0.2 * H <= f32 <= 0.45 * H):
            bad.append(f'{aid}: small items are 0.2-0.45 H tall ({h:.3f} m)')
        r = round(min(0.75 * max(w, dep) + 0.15, max(w, dep) * 0.5), 2)
        e = {'name': names[aid]['en'], 'category': 'Cozy things', 'space': 'home', 'radius': r, 'layer': 'mounted',
             'color': -1, 'seats': 0, 'size_class': cls, 'anchor': anchor}
        if anchor == 'wall':
            e['mount_height'] = round(min(max(1.5, h / 2 + 0.35), 2.75 - h / 2), 2)
        e['bounds'] = [round(x, 3) for x in m['bounds']]
        if offset:
            e['model_offset'] = offset
        e['tabletop_eligible'] = False
        e['model'] = f'res://assets/models/{aid}.glb'
        entries[aid] = (e, b, a['sha256'], sorted((m.get('markers') or {}).keys()))
        glbs[aid] = (b, a['glb'], a['sha256'])
        if names[aid]['en'] in en and not check_only and not (MODELS / f'{aid}.glb').exists():
            bad.append(f'{aid}: display name "{names[aid]["en"]}" is already used')
    if bad:
        print('FAIL\n  ' + '\n  '.join(bad))
        return 1
    lines = [BEGIN + ' (generated by scripts/build_furniture_r2.py; frozen, validated batches',
             '\t# b011-furn-r2 and b012-furn-r3 (the 11 repaired ceiling items); see design/model-release-r2.md)']
    for aid, (e, b, h, markers) in entries.items():
        parts = []
        for k, v in e.items():
            if k in ('bounds', 'model_offset'):
                parts.append(f'"{k}": {gd_vec(v)}')
            elif isinstance(v, bool):
                parts.append(f'"{k}": {"true" if v else "false"}')
            elif isinstance(v, str):
                parts.append(f'"{k}": "{v}"')
            else:
                parts.append(f'"{k}": {v}')
        lines.append(f'\t"{aid}": {{' + ', '.join(parts) + '},')
    lines.append(END)
    block = '\n'.join(lines)
    src = CATALOG.read_text()
    if BEGIN in src:
        new_src = src[:src.index(BEGIN)] + block + src[src.index(END) + len(END):]
    else:
        anchor = '\t# END production models r1\n'
        new_src = src.replace(anchor, anchor + block + '\n', 1)
    locale_new = {}
    for code in LOCALES:
        p = ROOT / f'game/locale/{code}.json'
        js = json.loads(p.read_text())
        for aid in ids:
            key, val = names[aid]['en'], names[aid][code]
            if key in js and js[key] != val:
                print(f'FAIL {code}: "{key}" already means "{js[key]}"')
                return 1
            js[key] = val
        locale_new[p] = json.dumps(dict(sorted(js.items())), indent=2, ensure_ascii=False) + '\n'
    if check_only:
        ok = new_src == src and all(p.read_text() == t for p, t in locale_new.items())
        for aid, (b, rel, h) in glbs.items():
            p = MODELS / f'{aid}.glb'
            ok = ok and p.exists() and sha(p.read_bytes()) == h
        print(f"{'PASS' if ok else 'FAIL'}: {len(entries)} models (b011 {sum(1 for v in glbs.values() if v[0] == 'b011-furn-r2')}, "
              f"b012 {sum(1 for v in glbs.values() if v[0] == 'b012-furn-r3')}), catalog block and locales")
        return 0 if ok else 1
    for aid, (b, rel, h) in glbs.items():
        dst = MODELS / f'{aid}.glb'
        if not dst.exists() or sha(dst.read_bytes()) != h:
            shutil.copyfile(LAB / 'batches' / b / rel, dst)
    CATALOG.write_text(new_src)
    for p, t in locale_new.items():
        p.write_text(t)
    for aid, (e, b, h, markers) in entries.items():
        print(f'{aid}\t{b}\t{h}\t{e["anchor"]}\t{e["size_class"]}\t{"+".join(markers) or "-"}')
    print(f'{len(entries)} models copied, catalog block and six locales written')
    return 0


if __name__ == '__main__':
    sys.exit(main())
