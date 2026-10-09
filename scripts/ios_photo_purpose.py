#!/usr/bin/env python3
"""Prepares an exported Godot iOS project for add-only Photos saving.

The game only adds photos, so it must declare NSPhotoLibraryAddUsageDescription
and never NSPhotoLibraryUsageDescription (full library access). Godot's iOS
export always writes an (empty) NSPhotoLibraryUsageDescription and bundles only
the English InfoPlist.strings. This tool, run on the Mac after export:

1. removes NSPhotoLibraryUsageDescription from <App>/<App>-Info.plist, makes sure
   the add-only key is there, and fails unless exactly the add-only key remains;
2. writes the purpose string (from game/locale/*.json) into each language's
   <App>/<lang>.lproj/InfoPlist.strings, keeping other entries;
3. registers the six InfoPlist.strings variants in project.pbxproj (file
   references, the InfoPlist.strings variant group and knownRegions).

Running it again changes nothing.

  python3 scripts/ios_photo_purpose.py /path/to/exported/project   # the folder with <App>.xcodeproj
"""
import hashlib
import json
import plistlib
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
KEY = 'Lantern Lane saves the photos you take to your photo library.'
ADD = 'NSPhotoLibraryAddUsageDescription'
FULL = 'NSPhotoLibraryUsageDescription'
LPROJ = {'en': 'en', 'zh-CN': 'zh-Hans', 'ja': 'ja', 'es': 'es', 'fr': 'fr', 'de': 'de'}


def escape(text):
    return text.replace('\\', '\\\\').replace('"', '\\"')


def quote(name):
    return name if re.fullmatch(r'[A-Za-z0-9_.]+', name) else f'"{name}"'


def file_id(app, lproj):
    return hashlib.sha1(f'{app} InfoPlist.strings {lproj}'.encode()).hexdigest()[:24].upper()


def fix_info_plist(path):
    with open(path, 'rb') as f:
        info = plistlib.load(f)
    info.pop(FULL, None)
    if not info.get(ADD):
        info[ADD] = KEY
    with open(path, 'wb') as f:
        plistlib.dump(info, f)
    with open(path, 'rb') as f:
        check = plistlib.load(f)
    if FULL in check or not check.get(ADD):
        raise SystemExit(f'{path}: expected only {ADD}')
    return check[ADD]


def write_strings(app_dir):
    for code, lproj in LPROJ.items():
        text = json.loads((ROOT / f'game/locale/{code}.json').read_text(encoding='utf-8'))[KEY]
        target = app_dir / f'{lproj}.lproj' / 'InfoPlist.strings'
        target.parent.mkdir(exist_ok=True)
        old = target.read_text(encoding='utf-8') if target.exists() else '/* Localized versions of Info.plist keys */\n'
        lines = [l for l in old.splitlines() if not l.startswith(f'"{ADD}"')]
        lines.append(f'"{ADD}" = "{escape(text)}";')
        target.write_text('\n'.join(lines) + '\n', encoding='utf-8')


def register(pbxproj, app):
    text = pbxproj.read_text(encoding='utf-8')
    m = re.search(r'\n(\t+)(\w{24}) /\* InfoPlist\.strings \*/ = \{\n\t+isa = PBXVariantGroup;\n\t+children = \(\n(.*?)\t+\);', text, re.S)
    if not m:
        raise SystemExit('No InfoPlist.strings variant group in project.pbxproj')
    children = m.group(3)
    indent = re.search(r'(\t+)\w{24} /\*', children).group(1) if re.search(r'\w{24} /\*', children) else m.group(1) + '\t\t'
    new_children = children
    new_refs = ''
    for lproj in LPROJ.values():
        path = f'{lproj}.lproj/InfoPlist.strings'
        if re.search(r'path = "?' + re.escape(path) + r'"?;', text):
            ref = re.search(r'(\w{24}) /\* [^*]* \*/ = \{isa = PBXFileReference;[^\n]*path = "?' + re.escape(path), text).group(1)
        else:
            ref = file_id(app, lproj)
            new_refs += (f'\t\t{ref} /* {lproj} */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.strings; '
                         f'name = {quote(lproj)}; path = {quote(path)}; sourceTree = "<group>"; }};\n')
        if ref not in new_children:
            new_children += f'{indent}{ref} /* {lproj} */,\n'
    text = text[:m.start(3)] + new_children + text[m.end(3):]
    if new_refs:
        end = text.index('/* End PBXFileReference section */')
        text = text[:end] + new_refs + text[end:]
    k = re.search(r'knownRegions = \(\n(.*?)\t+\);', text, re.S)
    if not k:
        raise SystemExit('No knownRegions in project.pbxproj')
    regions = k.group(1)
    have = {r.strip().strip(',').strip('"') for r in regions.splitlines() if r.strip()}
    rindent = re.match(r'(\t+)', regions).group(1) if regions.strip() else '\t\t\t\t'
    for lproj in LPROJ.values():
        if lproj not in have:
            regions += f'{rindent}{quote(lproj)},\n'
    text = text[:k.start(1)] + regions + text[k.end(1):]
    pbxproj.write_text(text, encoding='utf-8')


def main():
    if len(sys.argv) != 2:
        print(__doc__)
        return 2
    project = Path(sys.argv[1])
    projs = list(project.glob('*.xcodeproj'))
    if len(projs) != 1:
        print('Expected one .xcodeproj in', project)
        return 1
    app = projs[0].stem
    app_dir = project / app
    info = app_dir / f'{app}-Info.plist'
    purpose = fix_info_plist(info)
    write_strings(app_dir)
    register(projs[0] / 'project.pbxproj', app)
    print(f'{info.name}: only {ADD} ("{purpose}")')
    print('InfoPlist.strings registered for: ' + ', '.join(LPROJ.values()))
    return 0


if __name__ == '__main__':
    sys.exit(main())
