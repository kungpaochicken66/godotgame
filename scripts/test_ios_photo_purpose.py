#!/usr/bin/env python3
"""Tests scripts/ios_photo_purpose.py on a real exported Xcode project (fixture).

  python3 scripts/test_ios_photo_purpose.py
"""
import json
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / 'scripts/fixtures/ios_export'
LPROJ = ['en', 'zh-Hans', 'ja', 'es', 'fr', 'de']
KEY = 'Lantern Lane saves the photos you take to your photo library.'
failures = 0


def check(cond, what):
    global failures
    print(('PASS ' if cond else 'FAIL ') + what)
    failures += 0 if cond else 1


def main():
    work = Path(tempfile.mkdtemp(prefix='ios-photo-'))
    proj = work / 'export'
    shutil.copytree(FIXTURE, proj)
    pbx = proj / 'LanternLane.xcodeproj/project.pbxproj'
    info_path = proj / 'LanternLane/LanternLane-Info.plist'
    with open(info_path, 'rb') as f:
        before = plistlib.load(f)
    check('NSPhotoLibraryUsageDescription' in before, 'fixture: the export has the unwanted full-access key')
    original = pbx.read_text()
    check(original.count('.lproj/InfoPlist.strings') == 1, 'fixture: the export registers only English')
    tool = [sys.executable, str(ROOT / 'scripts/ios_photo_purpose.py'), str(proj)]
    r = subprocess.run(tool, capture_output=True, text=True)
    check(r.returncode == 0, f'tool runs (exit {r.returncode})')
    with open(info_path, 'rb') as f:
        info = plistlib.load(f)
    check('NSPhotoLibraryUsageDescription' not in info, 'Info.plist: no full library access key')
    check(info.get('NSPhotoLibraryAddUsageDescription') == KEY, 'Info.plist: the add-only key with the English purpose')
    check(info.get('CFBundleIdentifier') == before.get('CFBundleIdentifier') and len(info) == len(before) - 1 + ('NSPhotoLibraryAddUsageDescription' not in before),
          'Info.plist: every other key kept')
    text = pbx.read_text()
    group = re.search(r'/\* InfoPlist\.strings \*/ = \{\n\t+isa = PBXVariantGroup;\n\t+children = \((.*?)\);', text, re.S).group(1)
    ids = re.findall(r'(\w{24}) /\* ([\w-]+) \*/', group)
    check(sorted(n for _, n in ids) == sorted(LPROJ), f'variant group has the six languages ({[n for _, n in ids]})')
    for ref, name in ids:
        defs = re.findall(re.escape(ref) + r' /\* [\w-]+ \*/ = \{isa = PBXFileReference;[^\n]*path = "?(' + re.escape(name) + r'\.lproj/InfoPlist\.strings)"?;', text)
        check(len(defs) == 1, f'{name}: one file reference to {name}.lproj/InfoPlist.strings')
    regions = re.search(r'knownRegions = \((.*?)\);', text, re.S).group(1)
    have = {x.strip().strip(',').strip('"') for x in regions.split('\n') if x.strip()}
    check(set(LPROJ) <= have and 'Base' in have, f'knownRegions has every language ({sorted(have)})')
    check(text.count('{') == text.count('}') and text.count('(') == text.count(')'), 'project.pbxproj braces and parentheses balance')
    for lp, code in zip(LPROJ, ['en', 'zh-CN', 'ja', 'es', 'fr', 'de']):
        s = (proj / f'LanternLane/{lp}.lproj/InfoPlist.strings').read_text(encoding='utf-8')
        want = json.loads((ROOT / f'game/locale/{code}.json').read_text(encoding='utf-8'))[KEY]
        check(s.count('"NSPhotoLibraryAddUsageDescription"') == 1 and want in s, f'{lp}.lproj: the purpose string in that language')
    check('Localized versions of Info.plist keys' in (proj / 'LanternLane/en.lproj/InfoPlist.strings').read_text(), 'en.lproj: existing content kept')
    snapshot = {p: p.read_bytes() for p in proj.rglob('*') if p.is_file()}
    r = subprocess.run(tool, capture_output=True, text=True)
    check(r.returncode == 0 and all(p.read_bytes() == b for p, b in snapshot.items()), 'running it again changes nothing')
    shutil.rmtree(work, ignore_errors=True)
    print(f'IOS PHOTO PURPOSE {"PASS" if failures == 0 else "FAIL"}: {failures} failures')
    return 1 if failures else 0


if __name__ == '__main__':
    sys.exit(main())
