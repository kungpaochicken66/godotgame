#!/usr/bin/env python3
"""Tests scripts/check_web_view_plugin.py: it passes on the repository and on a
small copy, and each broken copy fails the check that guards that fault.

  python3 scripts/test_check_web_view_plugin.py
"""
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TOOL = ROOT / 'scripts/check_web_view_plugin.py'
GDIP = 'game/ios/plugins/web_view/web_view.gdip'
MM = 'game/ios/plugins/web_view/src/web_view.mm'
BUILD = 'game/ios/plugins/web_view/build.sh'
INSPECT = 'game/ios/plugins/web_view/check_inspectable.sh'
PRESET = 'game/export_presets.cfg'
TV_PRESET = '''
[preset.1]

name="Apple TV"
platform="tvOS"
include_filter=""
exclude_filter="tests/*"

[preset.1.options]

plugins/WebView=true
'''
failures = 0


def check(cond, what):
    global failures
    print(('PASS ' if cond else 'FAIL ') + what)
    failures += 0 if cond else 1


def run(root=None):
    r = subprocess.run([sys.executable, str(TOOL)] + ([str(root)] if root else []), capture_output=True, text=True)
    return r.returncode, r.stdout


def make_base(base):
    """The files the tool reads, with a small page in place of the real one."""
    skip = shutil.ignore_patterns('build', '*.xcframework', '__pycache__')
    shutil.copytree(ROOT / 'game/ios/plugins', base / 'game/ios/plugins', ignore=skip)
    shutil.copy(ROOT / PRESET, base / PRESET)
    shutil.copytree(ROOT / 'tv', base / 'tv', ignore=skip)
    shutil.copytree(ROOT / 'scripts/tvos', base / 'scripts/tvos', ignore=skip)
    for name, text in {'index.html': '<!doctype html>', 'js/main.js': 'export {};', 'data/city.bin': 'bin', 'data/city.json': '{}',
                       'vendor/three.module.js': 'export {};', 'dev/tool.html': '<!doctype html>', 'dev/js/tool.js': ''}.items():
        path = base / 'game/web_city' / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)


def edit(root, rel, old, new, count=1):
    path = root / rel
    text = path.read_text(encoding='utf-8')
    found = len(re.findall(old, text, re.M))
    if found != count and not (count is None and found > 0):     # count None: every occurrence, at least one
        raise AssertionError(f'{rel}: {old!r} found {found} times, expected {count}')
    path.write_text(re.sub(old, new, text, flags=re.M), encoding='utf-8')


def append(root, rel, text):
    path = root / rel
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text((path.read_text(encoding='utf-8') if path.exists() else '') + text, encoding='utf-8')


def frameworks(root, names):
    for name in names:
        (root / 'game/ios/plugins/web_view' / name).mkdir()


# (what is broken, the change, the check that must fail)
BROKEN = [
    ('the gdip names another plugin', lambda r: edit(r, GDIP, r'name="WebView"', 'name="Web"'), 'gdip: the plugin is named WebView'),
    ('the gdip names another binary', lambda r: edit(r, GDIP, r'web_view\.xcframework', 'webview.xcframework'), 'gdip: the binary is web_view.xcframework'),
    ('the gdip names an entry point the source lacks', lambda r: edit(r, GDIP, r'"web_view_init"', '"webview_init"'), 'gdip: the entry points are'),
    ('the gdip does not link WebKit', lambda r: edit(r, GDIP, r'system=\["WebKit\.framework"\]', 'system=[]'), 'gdip: the only system framework is WebKit.framework'),
    ('the gdip asks for a permission', lambda r: append(r, GDIP, '\n[plist]\nNSCameraUsageDescription:string="x"\n'), 'gdip: no permission'),
    ('the preset does not enable the plugin', lambda r: edit(r, PRESET, r'^plugins/WebView=true\n', ''), 'preset: iPad enables plugins/WebView'),
    ('the preset disables the plugin', lambda r: edit(r, PRESET, r'^plugins/WebView=true$', 'plugins/WebView=false'), 'preset: iPad enables plugins/WebView'),
    ('the preset drops the photo plugin', lambda r: edit(r, PRESET, r'^plugins/PhotoLibrary=true\n', ''), 'preset: iPad keeps plugins/PhotoLibrary'),
    ('the page is not included', lambda r: edit(r, PRESET, r', web_city/\*"', '"'), 'preset: include_filter has web_city/*'),
    ('the page is not included (filters applied)', lambda r: edit(r, PRESET, r', web_city/\*"', '"'), 'preset: the filters ship every page file'),
    ('only the page\'s top folder is included', lambda r: edit(r, PRESET, r', web_city/\*"', ', web_city/*.html"'), 'preset: the filters ship every page file'),
    ('an earlier include entry is lost', lambda r: edit(r, PRESET, r'locale/\*\.json, ', ''), 'preset: include_filter keeps its earlier entries'),
    ('the dev folder is not excluded', lambda r: edit(r, PRESET, r', web_city/dev/\*"', '"'), 'preset: exclude_filter has tests/* and web_city/dev/*'),
    ('the dev folder is not excluded (filters applied)', lambda r: edit(r, PRESET, r', web_city/dev/\*"', '"'), 'preset: the filters ship nothing of web_city/dev/'),
    ('only the dev folder\'s top level is excluded', lambda r: edit(r, PRESET, r', web_city/dev/\*"', ', web_city/dev/*.html"'), 'preset: the filters ship nothing of web_city/dev/'),
    ('the tests are not excluded', lambda r: edit(r, PRESET, r'"tests/\*, ', '"'), 'preset: exclude_filter has tests/* and web_city/dev/*'),
    ('the exporter under tests/ is included', lambda r: [edit(r, PRESET, r', web_city/\*"', ', web_city/*, *web_city/*"'), edit(r, PRESET, r'"tests/\*, ', '"')],
     'preset: tests/web_city/ stays out'),
    ('the page has no index.html', lambda r: (r / 'game/web_city/index.html').unlink(), 'page: game/web_city/index.html exists'),
    ('an Apple TV preset enables the plugin', lambda r: append(r, PRESET, TV_PRESET), 'preset: no preset of another platform enables WebView'),
    ('an Apple TV module imports WebKit', lambda r: append(r, 'tv/native/lantern_defaults/lantern_defaults.mm', '\n#import <WebKit/WebKit.h>\n'), 'tvOS: no Apple TV file refers to WebView or WebKit'),
    ('the Apple TV notes enable the plugin', lambda r: append(r, 'scripts/tvos/README.md', '\nSet `plugins/WebView=true`.\n'), 'tvOS: no Apple TV file refers to WebView or WebKit'),
    ('the Apple TV files gain a web view source', lambda r: append(r, 'tv/native/web_view/web_view.mm', '// empty\n'), 'tvOS: no Apple TV file refers to WebView or WebKit'),
    ('the source compiles for tvOS', lambda r: edit(r, MM, r'^#if TARGET_OS_TV\n#error[^\n]*\n#endif\n', ''), 'tvOS: the source refuses to compile for tvOS'),
    ('a bound method has another name', lambda r: edit(r, MM, r'D_METHOD\("poll"\)', 'D_METHOD("take")'), 'source: the bound methods are'),
    ('a bound method is missing', lambda r: edit(r, MM, r'^\tClassDB::bind_method\(D_METHOD\("stats"\)[^\n]*\n', ''), 'source: the bound methods are'),
    ('an argument has another name', lambda r: edit(r, MM, r'"open", "root_dir", "query"', '"open", "root", "query"'), 'source: the bound methods are'),
    ('a name is bound to another method', lambda r: edit(r, MM, r'D_METHOD\("is_open"\), &LanternWebView::is_open', 'D_METHOD("is_open"), &LanternWebView::close'), 'source: one Object class binds them'),
    ('the singleton has another name', lambda r: edit(r, MM, r'Engine::Singleton\("WebView",', 'Engine::Singleton("Web",'), 'source: the Engine singleton is registered as "WebView"'),
    ('an entry point is not defined', lambda r: edit(r, MM, r'^void web_view_deinit\(\) \{', 'void web_view_stop() {'), 'source: the entry points of the gdip are defined'),
    ('the scheme has another name', lambda r: edit(r, MM, r'kLLScheme = @"lantern"', 'kLLScheme = @"lamp"'), 'source: the scheme handler serves lantern://city/'),
    ('the page has another address', lambda r: edit(r, MM, r'@"lantern://city/index\.html"', '@"lantern://city/main.html"'), 'source: the scheme handler serves lantern://city/'),
    ('the message handler has another name', lambda r: edit(r, MM, r'kLLHandlerName = @"godot"', 'kLLHandlerName = @"game"'), 'source: the page\'s message handler is named "godot"'),
    ('the message handler keeps its target', lambda r: edit(r, MM, r'@property\(nonatomic, weak\) id<WKScriptMessageHandler> target;', '@property(nonatomic, strong) id<WKScriptMessageHandler> target;'), 'source: the handler is a weak proxy'),
    ('the host itself is the message handler', lambda r: edit(r, MM, r'addScriptMessageHandler:_proxy name:', 'addScriptMessageHandler:self name:'), 'source: the handler is a weak proxy'),
    ('close leaves the message handler', lambda r: edit(r, MM, r'^\t\[_content removeScriptMessageHandlerForName:kLLHandlerName\];\n', ''), 'source: the handler is a weak proxy'),
    ('post calls another function', lambda r: edit(r, MM, r'window\.LL&&window\.LL\.recv\(%@\)', 'window.LL.receive(%@)'), 'source: post calls window.LL&&window.LL.recv(<json>)'),
    ('a file outside the root is served', lambda r: edit(r, MM, r'\tif \(!\[real hasPrefix:prefix\]\) \{\n\t\t\*status = 403;\n\t\treturn nil;\n\t\}\n', ''), 'source: path guard: the real path'),
    ('".." is not refused', lambda r: edit(r, MM, r' \|\| \[part isEqualToString:@"\.\."\]', ''), 'source: path guard: a ".." part is refused'),
    ('a missing file is not a 404', lambda r: edit(r, MM, r'\*status = 404;', '*status = 200;', count=2), 'source: a missing file is answered with an HTTP 404'),
    ('scripts have no JavaScript type', lambda r: edit(r, MM, r'@"mjs" : @"text/javascript; charset=utf-8"', '@"mjs" : @"text/plain; charset=utf-8"'), 'source: Content-Type by extension'),
    ('a type is missing', lambda r: edit(r, MM, r'^\t\t\t@"png" : @"image/png",\n', ''), 'source: Content-Type by extension'),
    ('no Content-Length', lambda r: edit(r, MM, r'^\t\t@"Content-Length" : [^\n]*\n', ''), 'source: Content-Type and Content-Length are sent'),
    ('a stopped request is answered', lambda r: edit(r, MM, r'\tif \(!\[_live containsObject:task\]\) \{\n\t\treturn;[^\n]*\n\t\}\n', ''), 'source: a stopped request is never answered'),
    ('files are read on the main thread', lambda r: edit(r, MM, r'dispatch_async\(_io, \^\{', 'dispatch_async(dispatch_get_main_queue(), ^{'), 'source: files are read off the main thread'),
    ('scrolling is only switched off in a comment', lambda r: edit(r, MM, r'^\tscroll\.scrollEnabled = NO;', '\t// scroll.scrollEnabled = NO;'), 'source: the web view is white, opaque'),
    ('link previews stay', lambda r: edit(r, MM, r'^\tview\.allowsLinkPreview = NO;\n', ''), 'source: the web view is white, opaque'),
    ('release builds are inspectable', lambda r: edit(r, MM, r'^#ifdef DEBUG_ENABLED\n(\t// Safari[^\n]*\n(?:[^\n#]*\n)+?)#endif\n', r'\1'), 'source: inspectable only in DEBUG_ENABLED builds'),
    ('inspectable without the iOS 16.4 test', lambda r: edit(r, MM, r'\tif \(@available\(iOS 16\.4, \*\)\) \{\n\t\tview\.inspectable = YES;\n\t\}\n', '\tview.inspectable = YES;\n'), 'source: inspectable only in DEBUG_ENABLED builds'),
    ('the end of the web process is ignored', lambda r: edit(r, MM, r'webViewWebContentProcessDidTerminate:', 'webViewDidClose:'), 'source: the end of the web process is counted'),
    ('a stats key is missing', lambda r: edit(r, MM, r'^\tout\["thermal"\][^\n]*\n', ''), 'source: stats has thermal'),
    ('the queue has no bound', lambda r: edit(r, MM, r'if \(ll_queue\.count >= kLLMaxQueued\)', 'if (false)'), 'source: the page\'s messages wait in a bounded queue'),
    ('post has no limit', lambda r: edit(r, MM, r' \|\| ll_in_flight\.load\(\) >= kLLMaxInFlight', ''), 'source: post drops and counts'),
    ('Godot waits for the main thread', lambda r: edit(r, MM, r'^void LanternWebView::close\(\) \{\n', 'void LanternWebView::close() {\n\tdispatch_sync(dispatch_get_main_queue(), ^{});\n'), 'source: nothing waits for the main thread'),
    ('a brace is lost', lambda r: edit(r, MM, r'^LanternWebView::LanternWebView\(\) \{\}', 'LanternWebView::LanternWebView() {'), 'source: brackets, braces and parentheses balance'),
    ('the class is called WebView', lambda r: [edit(r, MM, r'\bLanternWebView\b', 'WebView', count=None),
                                                 edit(r, 'game/ios/plugins/web_view/src/web_view.h', r'\bLanternWebView\b', 'WebView', count=None)],
     'source: the C++ class is not called WebView'),
    ('the inspector check knows only the selector string (the Mac r1 failure)', lambda r: edit(r, INSPECT, r'^\t\tif grep -E -- [^\n]*\n[^\n]*\n\t\telif ', '\t\tif '), 'check_inspectable.sh: judges'),
    ('the inspector check takes any setInspectable text in a debug library', lambda r: edit(r, INSPECT, r'U _objc_msgSend\\\$setInspectable:\$', 'setInspectable'), 'check_inspectable.sh: judges'),
    ('the release check looks for whole lines only', lambda r: edit(r, INSPECT, r'^\telif grep -F -- "setInspectable"', '\telif grep -F -x -- "setInspectable:"'), 'check_inspectable.sh: judges'),
    ('the release check reads only the strings', lambda r: edit(r, INSPECT, r'"setInspectable" "\$symbols" "\$strings"', '"setInspectable" "$strings"'), 'check_inspectable.sh: judges'),
    ('the inspector check reads only the first library', lambda r: edit(r, INSPECT, r'^while \(\( \$# \)\); do\n\tsymbols="\$1"; strings="\$2"; shift 2\n', 'symbols="$1"; strings="$2"; shift $#\nfor _ in 1; do\n'), 'check_inspectable.sh: judges'),
    ('the inspector check is missing', lambda r: (r / INSPECT).unlink(), 'check_inspectable.sh: exists and is executable'),
    ('the inspector check is not executable', lambda r: (r / INSPECT).chmod(0o644), 'check_inspectable.sh: exists and is executable'),
    ('build.sh checks the device library only', lambda r: edit(r, BUILD, r' \\\n\t\t"\$OUT/\$variant/simulator-symbols\.txt" "\$OUT/\$variant/simulator-strings\.txt"', ''), 'build.sh: lists both libraries'),
    ('build.sh does not list the simulator symbols', lambda r: edit(r, BUILD, r'^\tnm -C "\$OUT/\$variant/simulator/libweb_view\.a"[^\n]*\n', ''), 'build.sh: lists both libraries'),
    ('build.sh lost a step', lambda r: edit(r, BUILD, r'^\tif grep -F -- "\$other"[^\n]*\n[^\n]*\n\tfi\n', ''), 'build.sh: every step of photo_library/build.sh'),
    ('build.sh builds the photo plugin', lambda r: edit(r, BUILD, r'src/web_view\.mm', 'src/photo_library.mm'), 'plugin: nothing is left of the photo plugin\'s names'),
    ('build.sh is not valid bash', lambda r: append(r, BUILD, 'if then\n'), 'build.sh: bash -n accepts it'),
    ('build.sh is not executable', lambda r: (r / BUILD).chmod(0o644), 'build.sh: exists and is executable'),
    ('a plain framework is beside the two', lambda r: frameworks(r, ['web_view.debug.xcframework', 'web_view.release.xcframework', 'web_view.xcframework']), 'frameworks: web_view.debug.xcframework and web_view.release.xcframework'),
    ('only the debug framework is built', lambda r: frameworks(r, ['web_view.debug.xcframework']), 'frameworks: web_view.debug.xcframework and web_view.release.xcframework'),
]

# Changes that must still pass.
FINE = [
    ('the Apple TV notes say to leave the descriptor out', lambda r: append(r, 'scripts/tvos/README.md', '\nAlso omit `game/ios/plugins/web_view/web_view.gdip` from the TV copy.\n')),
    ('both frameworks are built', lambda r: frameworks(r, ['web_view.debug.xcframework', 'web_view.release.xcframework'])),
    ('the page has no dev folder', lambda r: shutil.rmtree(r / 'game/web_city/dev')),
    ('a comment mentions dispatch_sync', lambda r: append(r, MM, '// never dispatch_sync(dispatch_get_main_queue(), ...) here\n')),
]


def main():
    code, out = run()
    check(code == 0 and 'WEB VIEW PLUGIN CHECK PASS: 0 failures' in out and 'FAIL ' not in out, f'the repository passes (exit {code})')
    checks = out.count('PASS ')
    work = Path(tempfile.mkdtemp(prefix='web-view-check-'))
    try:
        base = work / 'base'
        make_base(base)
        code, out = run(base)
        check(code == 0 and 'FAIL ' not in out and out.count('PASS ') == checks, f'the small copy passes the same {checks} checks (exit {code})')
        for number, (what, change, label) in enumerate(BROKEN):
            root = work / f'broken{number}'
            shutil.copytree(base, root)
            change(root)
            code, out = run(root)
            failed = [l for l in out.splitlines() if l.startswith('FAIL ')]
            check(code == 1 and any(l.startswith('FAIL ' + label) for l in failed) and 'WEB VIEW PLUGIN CHECK FAIL' in out,
                  f'{what}: fails "{label}" ({len(failed)} failed, exit {code})')
        for number, (what, change) in enumerate(FINE):
            root = work / f'fine{number}'
            shutil.copytree(base, root)
            change(root)
            code, out = run(root)
            check(code == 0 and 'FAIL ' not in out, f'{what}: still passes (exit {code})')
        code, out = run(work / 'nothing-here')
        check(code == 1 and out.count('FAIL ') > 10, f'an empty folder fails (exit {code})')
        r = subprocess.run([sys.executable, str(TOOL), '--what'], capture_output=True, text=True)
        check(r.returncode == 2, f'an unknown option is refused (exit {r.returncode})')
    finally:
        shutil.rmtree(work, ignore_errors=True)
    print(f'WEB VIEW PLUGIN CHECK TEST {"PASS" if failures == 0 else "FAIL"}: {failures} failures')
    return 1 if failures else 0


if __name__ == '__main__':
    sys.exit(main())
