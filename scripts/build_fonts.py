#!/usr/bin/env python3
"""Subset the bundled CJK fonts to the characters the UI catalogs use.

Full CJK fonts are 4-18 MB; subsets keep the iPad app small. Re-run after
changing game/locale/*.json. Needs fontTools (tools/venv) and the source fonts
fetched by scripts/setup_tools.sh into tools/fonts-src/.

  tools/venv/bin/python scripts/build_fonts.py
"""
import json
import shutil
from pathlib import Path

from fontTools import subset
from fontTools.varLib import instancer

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / 'tools/fonts-src'
OUT = ROOT / 'game/assets/fonts'
# ASCII plus common Latin and CJK punctuation (written as escapes to keep sources ASCII).
BASE = ''.join(chr(c) for c in range(0x20, 0x7f)) + '\u2026\u00b7\u00d7\u00f7\u2014\u2013\u2018\u2019\u201c\u201d\u3001\u3002\uff0c\uff01\uff1f\uff1a\uff1b\uff08\uff09\u300c\u300d\u300e\u300f\u300a\u300b\uff05\uff0f\uff0b\uff0d\u30fb\u30fc\uff5e\u3000'
KANA = ''.join(chr(c) for c in range(0x3041, 0x3097)) + ''.join(chr(c) for c in range(0x30a1, 0x30fb))


def catalog_text(*codes):
    text = ''
    for code in codes:
        text += ''.join(json.loads((ROOT / f'game/locale/{code}.json').read_text()).values())
    text += ''.join(json.loads((ROOT / 'game/locale/languages.json').read_text()).values())
    return text


def make(source, target, text):
    opts = subset.Options()
    opts.layout_features = ['*']
    opts.name_IDs = ['*']
    opts.notdef_outline = True
    font = subset.load_font(str(SRC / source), opts)
    if 'fvar' in font:
        # Fix variable CJK fonts at a bold weight to match the rounded Latin UI font.
        font = instancer.instantiateVariableFont(font, {'wght': 700})
    sub = subset.Subsetter(opts)
    sub.populate(text=''.join(sorted(set(text))))
    sub.subset(font)
    subset.save_font(font, str(OUT / target), opts)
    print(f'{target}: {len(set(text))} characters, {(OUT / target).stat().st_size // 1024} KB')


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    all_text = catalog_text('en', 'zh-CN', 'ja', 'es', 'fr', 'de')
    make('mplusrounded1c_MPLUSRounded1c-Bold.ttf', 'MPLUSRounded1c-Bold-subset.ttf', BASE + KANA + all_text)
    make('notosanssc_NotoSansSC[wght].ttf', 'NotoSansSC-subset.ttf', BASE + all_text)
    shutil.copy(SRC / 'nunito_Nunito[wght].ttf', OUT / 'Nunito-Variable.ttf')
    for name in ['nunito', 'notosanssc']:
        shutil.copy(SRC / f'{name}_OFL.txt', OUT / f'{name.upper()}-OFL.txt')
    # Google Fonts ships M+ Rounded 1c under OFL without a separate license file.
    body = (SRC / 'nunito_OFL.txt').read_text().split('\n', 1)[1]
    (OUT / 'MPLUSROUNDED1C-OFL.txt').write_text('Copyright 2016 The Rounded M+ Project Authors.\n' + body)


if __name__ == '__main__':
    main()
