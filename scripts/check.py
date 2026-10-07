#!/usr/bin/env python3
"""Dependency-free repository checks.

- Browser design preview: locale completeness and local HTML references.
- Godot game: six complete UI catalogs with matching placeholders, every
  user-facing literal in the scripts present in the English catalog, and (when
  fontTools is available, e.g. tools/venv) every catalog character covered by
  the bundled fonts.
- English paths and English source/documentation text.
"""
import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LOCALES = ('en', 'zh-CN', 'ja', 'es', 'fr', 'de')
SKIP_DIRS = {'.git', '__pycache__', '.godot', 'tools', 'build', 'exports'}


def load_catalog(path):
    pairs = []
    data = json.loads(path.read_text(), object_pairs_hook=lambda items: pairs.extend(items) or dict(items))
    assert len(pairs) == len(data), f'Duplicate keys: {path}'
    return data


def check_catalogs(folder):
    base = load_catalog(folder / 'en.json')
    assert base and all(key == value for key, value in base.items()), f'{folder}/en.json must map English to itself'
    for locale in LOCALES:
        data = load_catalog(folder / f'{locale}.json')
        assert data.keys() == base.keys(), f'Mismatched message keys: {folder}/{locale}.json'
        for key, value in data.items():
            assert isinstance(value, str) and value.strip(), f'Empty message: {locale} {key!r}'
            assert re.findall(r'%[ds]', key) == re.findall(r'%[ds]', value), f'Placeholder mismatch: {locale} {key!r}'
    names = json.loads((folder / 'languages.json').read_text())
    assert set(names) == set(LOCALES), f'{folder}/languages.json'
    return base


def check_fonts(folder):
    try:
        from fontTools.ttLib import TTFont
    except ImportError:
        return 'skipped (fontTools not installed; use tools/venv/bin/python)'
    fonts = ROOT / 'game/assets/fonts'
    cmaps = [set(TTFont(fonts / f).getBestCmap()) for f in
             ('Nunito-Variable.ttf', 'MPLUSRounded1c-Bold-subset.ttf', 'NotoSansSC-subset.ttf')]
    covered = set().union(*cmaps)
    text = ''.join(''.join(load_catalog(folder / f'{c}.json').values()) for c in LOCALES)
    text += ''.join(json.loads((folder / 'languages.json').read_text()).values())
    # Non-ASCII characters written directly in script strings must render too.
    for gd in (ROOT / 'game/scripts').rglob('*.gd'):
        for lit in re.findall(r'"((?:[^"\\]|\\.)*)"', gd.read_text()):
            text += ''.join(ch for ch in lit if ord(ch) > 127)
    missing = sorted({ch for ch in text if ord(ch) > 32 and ord(ch) not in covered})
    assert not missing, f'Characters missing from bundled fonts (run scripts/build_fonts.py): {"".join(missing)}'
    # Chinese text should not silently fall back to Japanese glyph shapes.
    zh = {ch for ch in ''.join(load_catalog(folder / 'zh-CN.json').values()) if ord(ch) > 0x2e80}
    zh_missing = sorted(ch for ch in zh if ord(ch) not in cmaps[2])
    assert not zh_missing, f'Chinese characters missing from NotoSansSC subset: {"".join(zh_missing)}'
    return f'{len(set(text))} characters covered'


def main():
    preview = check_catalogs(ROOT / 'design/locales')
    game = check_catalogs(ROOT / 'game/locale')
    strings = subprocess.run([sys.executable, str(ROOT / 'scripts/extract_strings.py')], capture_output=True, text=True)
    assert strings.returncode == 0, 'User-facing strings missing from game/locale/en.json:\n' + strings.stdout
    fonts = check_fonts(ROOT / 'game/locale')
    for path in ROOT.rglob('*'):
        rel = path.relative_to(ROOT)
        if SKIP_DIRS.intersection(rel.parts):
            continue
        assert rel.as_posix().isascii(), f'Non-English path: {path}'
        if not path.is_file() or path.suffix not in {'.md', '.js', '.html', '.css', '.py', '.txt', '.gd', '.cfg', '.godot', '.tscn', '.sh'}:
            continue
        text = path.read_text()
        if path.name != 'project.godot':  # holds the localized app names for the home screen
            assert not re.search(r'[\u3040-\u30ff\u3400-\u9fff]', text), f'Unlocalized source text: {path}'
        if path.suffix == '.html':
            for reference in re.findall(r'(?:src|href)="([^"#]+)"', text):
                if '://' not in reference and '${' not in reference:
                    assert (path.parent / reference.split('?')[0]).exists(), (path, reference)
        if path.suffix == '.md':
            for reference in re.findall(r'\]\(([^)#]+)\)', text):
                if '://' not in reference:
                    assert (path.parent / reference).exists(), f'Broken link in {rel}: {reference}'
    print(f'PASS: preview {len(preview)} and game {len(game)} messages complete in {len(LOCALES)} languages; '
          f'game strings extracted; fonts {fonts}; English paths and sources; links.')


if __name__ == '__main__':
    main()
