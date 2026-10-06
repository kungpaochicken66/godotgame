#!/usr/bin/env python3
"""Check locale completeness, English source files and local preview references."""
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
LOCALES = ('en', 'zh-CN', 'ja', 'es', 'fr', 'de')
base = json.loads((ROOT / 'design/locales/en.json').read_text())
assert base and all(key == value for key, value in base.items())
for locale in LOCALES:
    pairs = []
    data = json.loads((ROOT / f'design/locales/{locale}.json').read_text(),
                      object_pairs_hook=lambda items: pairs.extend(items) or dict(items))
    assert len(pairs) == len(data), f'Duplicate keys: {locale}'
    assert data.keys() == base.keys(), f'Mismatched message keys: {locale}'
    assert all(isinstance(value, str) and value.strip() for value in data.values()), locale
names = json.loads((ROOT / 'design/locales/languages.json').read_text())
assert set(names) == set(LOCALES)
for path in ROOT.rglob('*'):
    if '.git' in path.parts or '__pycache__' in path.parts:
        continue
    assert path.relative_to(ROOT).as_posix().isascii(), f'Non-English path: {path}'
    if not path.is_file() or path.suffix not in {'.md', '.js', '.html', '.css', '.py', '.txt'}:
        continue
    text = path.read_text()
    assert not re.search(r'[\u3040-\u30ff\u3400-\u9fff]', text), f'Unlocalized source text: {path}'
    if path.suffix == '.html':
        for reference in re.findall(r'(?:src|href)="([^"#]+)"', text):
            if '://' not in reference and '${' not in reference:
                assert (path.parent / reference.split('?')[0]).exists(), (path, reference)
print(f'PASS: {len(base)} complete messages in {len(LOCALES)} languages; English paths and sources; HTML links.')
