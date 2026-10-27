#!/usr/bin/env python3
"""Repository checks for the isolated TV candidate (atv-r20-controller).

The candidate is a partial tree (game, docs, design), so Markdown links to files outside it cannot
resolve. This runs every check of scripts/check.py except link existence: six complete catalogs with
matching placeholders, every user-facing literal extracted, font coverage, English paths and sources.

  tools/venv/bin/python scripts/tv_check.py
"""
import re
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import check  # noqa: E402

ROOT = check.ROOT


def main():
    preview = check.check_catalogs(ROOT / 'design/locales')
    game = check.check_catalogs(ROOT / 'game/locale')
    strings = subprocess.run([sys.executable, str(ROOT / 'scripts/extract_strings.py')], capture_output=True, text=True)
    assert strings.returncode == 0, 'User-facing strings missing from game/locale/en.json:\n' + strings.stdout
    fonts = check.check_fonts(ROOT / 'game/locale')
    for path in ROOT.rglob('*'):
        rel = path.relative_to(ROOT)
        if check.SKIP_DIRS.intersection(rel.parts):
            continue
        assert rel.as_posix().isascii(), f'Non-English path: {path}'
        if not path.is_file() or path.suffix not in {'.md', '.js', '.html', '.css', '.py', '.txt', '.gd', '.cfg', '.godot', '.tscn', '.sh'}:
            continue
        if path.name != 'project.godot':
            assert not re.search(r'[\u3040-\u30ff\u3400-\u9fff]', path.read_text()), f'Unlocalized source text: {path}'
    print(f'PASS (TV candidate, links not checked): preview {len(preview)} and game {len(game)} messages complete in '
          f'{len(check.LOCALES)} languages; game strings extracted; fonts {fonts}; English paths and sources.')


if __name__ == '__main__':
    main()
