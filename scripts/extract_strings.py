#!/usr/bin/env python3
"""List user-facing English strings in the Godot scripts.

The Godot UI passes English source text through translation, so every visible
literal must be a key in game/locale/en.json. This finds candidate literals
(capitalized text) and skips code identifiers such as node names and paths.

  python3 scripts/extract_strings.py            # print strings missing from en.json
  python3 scripts/extract_strings.py --all      # print every user-facing string
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
GAME = ROOT / 'game'
SCAN = ['scripts/core', 'scripts/net', 'scripts/ui', 'scripts/world', 'scripts/art', 'scripts/main.gd']
LITERAL = re.compile(r'"((?:[^"\\]|\\.)*)"')
# Lines where capitalized literals are code, not text a child reads.
SKIP_LINE = re.compile(
    r'\.name = |name = "|get_node|find_child|_seat\(|has_method|[gs]et_meta|add_to_group|call_group|'
    r'print|push_warning|push_error|printerr|Seat%d|class_name|preload|load\(|\bassert\b|'
    r'add_theme_|set_color\(|set_stylebox\(|set_constant\(|get_theme_|ICONS|<path|<rect|<circle|<svg')


def candidates():
    found = {}
    for entry in SCAN:
        path = GAME / entry
        files = [path] if path.is_file() else sorted(path.rglob('*.gd'))
        for f in files:
            for n, line in enumerate(f.read_text().splitlines(), 1):
                code = line.split('##')[0]
                if code.lstrip().startswith('#') or SKIP_LINE.search(code):
                    continue
                for text in re.findall(r'\btr\("((?:[^"\\]|\\.)*)"\)', code):
                    found.setdefault(text, f'{f.relative_to(ROOT)}:{n}')
                for text in LITERAL.findall(code):
                    sentence = re.match(r'%[sd] [a-z]', text) is not None  # e.g. "%s loves ..."
                    if not text or not (text[0].isupper() or sentence) or text.startswith(('res:', 'user:')):
                        continue
                    if re.fullmatch(r'[A-Z][A-Za-z0-9]*', text) and text in IDENTIFIER_WORDS:
                        continue
                    found.setdefault(text, f'{f.relative_to(ROOT)}:{n}')
    return found


# Capitalized single words that are identifiers rather than UI text.
IDENTIFIER_WORDS = {'Town', 'Room', 'Items', 'Spots', 'Model', 'Pivot', 'HairCap', 'WishingTree', 'Bell',
                    'Plaza', 'MenuStage', 'World', 'Main', 'Label', 'Button', 'LineEdit',
                    'PanelContainer', 'HBoxContainer', 'VBoxContainer',
                    'Seat0', 'Sleep0', 'Support0', 'Light0', 'AtticFrame', 'Merged', 'Forest'}


def main():
    en = json.loads((GAME / 'locale/en.json').read_text())
    found = candidates()
    show_all = '--all' in sys.argv
    missing = {k: v for k, v in found.items() if k not in en}
    for text, where in sorted((found if show_all else missing).items()):
        print(f'{where}\t{text}')
    if not show_all:
        print(f'{len(found)} user-facing strings, {len(missing)} missing from game/locale/en.json', file=sys.stderr)
    return 1 if missing and not show_all else 0


if __name__ == '__main__':
    sys.exit(main())
