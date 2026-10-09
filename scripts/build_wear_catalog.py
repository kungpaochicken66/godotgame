#!/usr/bin/env python3
"""Build the in-game wearable catalog from the Modeling lane's FROZEN batches (read-only).

Every batch must match its FROZEN record (sha256 of BATCH_MANIFEST.json) and every GLB its manifest hash;
otherwise nothing is written. Accepted GLBs are copied to game/assets/wearables/<id>.glb and listed in
game/data/wearables.json. A held item (umbrella, hand-held bag) is usable only with the W9 hold contract: the
frozen wear-r2 rev5 hold records c018/c019 (same GLB bytes as c014/c013, checked here) or the accepted rev2/rev3
pilot four. Any other held item would be listed as gated and not copied (none since rev5 final acceptance).

  python3 scripts/build_wear_catalog.py            # build
  python3 scripts/build_wear_catalog.py --check    # verify only (exit 1 on any difference)
"""
import hashlib
import json
import shutil
import struct
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LAB = ROOT / 'tools/nookipedia-model-production/batches'
OUT_MODELS = ROOT / 'game/assets/wearables'
OUT_JSON = ROOT / 'game/data/wearables.json'

# Frozen v3 baseline (wear-r1a/r1b) and the frozen wear-r2 rev4 seated variants, which supersede the
# same ids in c003/c011 (later batches in this list win). EQUIP_HANDOFF.md sections 1-9.
BATCHES = ['c003-dressup', 'c004-headwear', 'c006-socks', 'c007-accessories', 'c010-tops-v3', 'c011-bottoms-v3',
           'c012-shoes-v3', 'c013-bags-v3', 'c014-umbrellas-r2', 'c016-dressup-sit', 'c017-skirts-sit']
# Expected FROZEN manifest digests (from progress/CANDIDATES.md and each FROZEN file).
EXPECTED_PREFIX = {'c003-dressup': 'aa7993b4', 'c004-headwear': 'bc169605', 'c006-socks': '0174d53a',
                   'c007-accessories': 'd83eaed1', 'c010-tops-v3': '60fe011c', 'c011-bottoms-v3': '9a3f42bc',
                   'c012-shoes-v3': '09a6c538', 'c013-bags-v3': '7eefb238', 'c014-umbrellas-r2': 'eeb283a7',
                   'c016-dressup-sit': '0629dab9', 'c017-skirts-sit': '46b00a63'}
# W9 hold-contract records (wear-r2 rev5, FROZEN 2026-10-08, evidence/wear-r2/WEAR_R2_ACCEPTANCE.md): batch ->
# (expected BATCH_MANIFEST prefix, the batch whose GLB bytes they validated).
HOLD_RECORDS = {'c018-umbrellas-hold': ('9beac0ca', 'c014-umbrellas-r2'), 'c019-bags-hold': ('8eaa1fa3', 'c013-bags-v3')}
# The rev2/rev3 pilot held items (PILOT_ACCEPTANCE.md; GLBs byte-identical to c014/c013).
PILOT_HELD = {'apple_umbrella', 'cherry_blossom_umbrella', 'basket_bag', 'apparel_shop_paper_bag'}
# Archetype -> game slot. Dress-ups occupy top and bottom (handled in game/scripts/core/wearables.gd).
SLOT = {'top': 'top', 'bottom': 'bottom', 'dress': 'dress', 'hat': 'head', 'accessory': 'face', 'sock': 'socks',
        'shoe': 'shoes', 'bag': 'bag', 'umbrella': 'hand'}
# kid_rig.gd BAND_HATS: band-like headwear sits on the hair instead of replacing it.
BAND_HATS = {'crown', 'flowers', 'clip', 'ears', 'bopper'}
CATEGORY = {'Tops': 'Tops', 'Bottoms': 'Bottoms', 'Dress-Up': 'Dress-up', 'Headwear': 'Headwear',
            'Accessories': 'Accessories', 'Socks': 'Socks', 'Shoes': 'Shoes', 'Bags': 'Bags', 'Umbrellas': 'Umbrellas'}


def sha(p: Path) -> str:
    return hashlib.sha256(p.read_bytes()).hexdigest()


def glb_mesh_parts(path: Path, aid: str) -> list:
    b = path.read_bytes()
    n = struct.unpack('<I', b[12:16])[0]
    j = json.loads(b[20:20 + n])
    return sorted(x['name'][len(aid) + 1:] for x in j['nodes'] if x.get('name', '').startswith(aid + '_'))


def main() -> int:
    check_only = '--check' in sys.argv
    entries = {}
    batches = {}
    for b in BATCHES:
        d = LAB / b
        frozen = (d / 'FROZEN').read_text().strip()
        want = frozen.split('sha256(BATCH_MANIFEST.json)=')[1].strip()
        got = sha(d / 'BATCH_MANIFEST.json')
        if want != got or not got.startswith(EXPECTED_PREFIX[b]):
            print(f'FAIL {b}: BATCH_MANIFEST {got} does not match FROZEN {want} / expected {EXPECTED_PREFIX[b]}')
            return 1
        batches[b] = got
        m = json.loads((d / 'BATCH_MANIFEST.json').read_text())
        for aid, a in m['assets'].items():
            glb = d / a['glb']
            if sha(glb) != a['sha256']:
                print(f'FAIL {b}/{aid}: GLB hash mismatch')
                return 1
            man = json.loads((d / a['manifest']).read_text())
            build = man.get('build', {})
            arch = build.get('archetype')
            ref = man['references'][0]
            parts = glb_mesh_parts(glb, aid)
            entries[aid] = {
                'name': ref['item'], 'category': CATEGORY[ref['category']], 'slot': 'hand' if man.get('held') else SLOT[arch], 'archetype': arch,
                'band': arch == 'hat' and build.get('params', {}).get('style') in BAND_HATS,
                'held': bool(man.get('held')), 'sit': any(p.endswith('_sit') for p in parts), 'parts': parts,
                'batch': b, 'sha256': a['sha256'], 'tris': man['mesh']['tris'], 'source_item_url': ref['source_item_url'],
            }
    hold = {k: 'pilot (wear-r2 rev3)' for k in PILOT_HELD}
    for h, (prefix, source) in HOLD_RECORDS.items():
        d = LAB / h
        want = (d / 'FROZEN').read_text().strip().split('sha256(BATCH_MANIFEST.json)=')[1].strip()
        got = sha(d / 'BATCH_MANIFEST.json')
        if want != got or not got.startswith(prefix):
            print(f'FAIL {h}: BATCH_MANIFEST {got} does not match FROZEN {want} / expected {prefix}')
            return 1
        batches[h] = got
        for aid, a in json.loads((d / 'BATCH_MANIFEST.json').read_text())['assets'].items():
            e = entries.get(aid)
            if e is None or e['batch'] != source or a['sha256'] != e['sha256'] or sha(d / a['glb']) != e['sha256']:
                print(f'FAIL {h}/{aid}: hold record does not cover the same GLB bytes as {source}')
                return 1
            if not json.loads((d / a['manifest']).read_text())['validation'].get('W9_hold'):
                print(f'FAIL {h}/{aid}: no W9 hold pass')
                return 1
            hold[aid] = h
    gated = {k: 'the W9 hold contract' for k, v in entries.items() if v['held'] and k not in hold}
    accepted = {k: v for k, v in sorted(entries.items()) if k not in gated}
    for k, v in accepted.items():
        if v['held']:
            v['hold'] = hold[k]
    out = {
        'source': 'tools/nookipedia-model-production frozen batches (read-only), EQUIP_HANDOFF.md sections 1-9',
        'batches': batches,
        'gated': {k: {'name': entries[k]['name'], 'category': entries[k]['category'], 'waiting_for': g}
                  for k, g in sorted(gated.items())},
        'items': {k: {f: v[f] for f in ['name', 'category', 'slot', 'band', 'held', 'hold', 'sit', 'parts', 'batch', 'sha256', 'tris'] if f in v}
                  for k, v in accepted.items()},
    }
    text = json.dumps(out, indent=1, ensure_ascii=False) + '\n'
    if check_only:
        ok = OUT_JSON.exists() and OUT_JSON.read_text() == text
        for k, v in accepted.items():
            p = OUT_MODELS / f'{k}.glb'
            ok = ok and p.exists() and sha(p) == v['sha256']
        extra = [p.name for p in OUT_MODELS.glob('*.glb') if p.stem not in accepted] if OUT_MODELS.exists() else []
        print(f"{'PASS' if ok and not extra else 'FAIL'}: {len(accepted)} accepted, {len(gated)} gated, extra {extra}")
        return 0 if ok and not extra else 1
    OUT_MODELS.mkdir(parents=True, exist_ok=True)
    OUT_JSON.parent.mkdir(parents=True, exist_ok=True)
    for k, v in accepted.items():
        dst = OUT_MODELS / f'{k}.glb'
        if not dst.exists() or sha(dst) != v['sha256']:
            shutil.copyfile(LAB / v['batch'] / 'models' / f'{k}.glb', dst)
    for p in OUT_MODELS.glob('*.glb'):
        if p.stem not in accepted:
            p.unlink()
    OUT_JSON.write_text(text)
    print(f'{len(accepted)} accepted wearables copied and listed; {len(gated)} gated (not copied)')
    return 0


if __name__ == '__main__':
    sys.exit(main())
