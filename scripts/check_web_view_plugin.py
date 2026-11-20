#!/usr/bin/env python3
"""Linux checks of the iOS WebView plugin (game/ios/plugins/web_view, design/city-threejs.md).

The plugin is built on the Mac only (Xcode). These checks read the files:

1. web_view.gdip: the name, the binary, the entry points, WebKit.framework;
2. game/export_presets.cfg: the iPad preset enables the plugin and ships
   web_city/* but not web_city/dev/* (Godot's own filter rules, applied to the
   files of game/web_city);
3. the Apple TV files (tv/, scripts/tvos/) do not refer to WebView or WebKit:
   tvOS has no WebKit;
4. the source: the scheme, the message handler, the bound methods, the guard
   against paths that leave the root, the settings of the web view;
5. build.sh keeps the structure of photo_library/build.sh, and its Web Inspector check
   (check_inspectable.sh) runs on both libraries and judges sample listings right.

  python3 scripts/check_web_view_plugin.py [repository root]
  python3 scripts/check_web_view_plugin.py --export   # also exports the iPad .pck from a copy (slow)
"""
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parents[1]
BOUND = {'open': ['root_dir', 'query'], 'close': [], 'post': ['json'], 'poll': [], 'is_open': [], 'stats': []}
MIME = {'html': 'text/html', 'js': 'text/javascript', 'mjs': 'text/javascript', 'json': 'application/json',
        'bin': 'application/octet-stream', 'png': 'image/png', 'css': 'text/css'}
STATS = ['thermal', 'footprint_mb', 'dropped', 'web_process_terminated']
TV_WORDS = re.compile(r'WebKit|WKWebView|\bWebView\b|web_view\.(?:debug\.|release\.)?xcframework|libweb_view')
TEXT_SUFFIXES = {'.md', '.py', '.sh', '.patch', '.plist', '.json', '.h', '.mm', '.m', '.cpp', '.swift', '.svg', '.cfg', '.txt', ''}
failures = 0


def check(cond, what, detail=''):
    global failures
    print(('PASS ' if cond else 'FAIL ') + what + (f': {detail}' if detail and not cond else ''))
    failures += 0 if cond else 1
    return cond


def read(path):
    return path.read_text(encoding='utf-8') if path.is_file() else ''


def parse_cfg(text):
    """Godot's ConfigFile, as far as these files use it: {section: {key: raw value}}."""
    out, section = {}, None
    for line in text.splitlines():
        line = line.strip()
        m = re.fullmatch(r'\[(.+)\]', line)
        if m:
            section = out.setdefault(m.group(1), {})
        elif '=' in line and section is not None and not line.startswith(';'):
            key, value = line.split('=', 1)
            section[key.strip()] = value.strip()
    return out


def unquote(value):
    return value[1:-1] if len(value) >= 2 and value[0] == value[-1] == '"' else value


def filters(value):
    """EditorExportPlatform::_edit_filter_list: split at commas, strip, drop empties."""
    return [f.strip() for f in unquote(value).split(',') if f.strip()]


def matchn(pattern, text):
    """Godot's String.matchn: '*' is any text (also '/'), '?' any one character but '.'."""
    rx = ''.join('.*' if c == '*' else '[^.]' if c == '?' else re.escape(c) for c in pattern)
    return re.fullmatch(rx, text, re.I | re.S) is not None


def ships(path, include, exclude):
    """Whether the filters alone export res://<path> (include, then exclude; both forms of the path)."""
    def hit(patterns):
        return any(matchn(p, 'res://' + path) or matchn(p, path) for p in patterns)
    return hit(include) and not hit(exclude)


def strip_comments(text, blank_strings=False):
    """Removes // and /* */ comments; string and character literals stay (or become empty)."""
    out, i, n = [], 0, len(text)
    while i < n:
        two = text[i:i + 2]
        if two == '//':
            while i < n and text[i] != '\n':
                i += 1
        elif two == '/*':
            end = text.find('*/', i + 2)
            i = n if end < 0 else end + 2
        elif text[i] in '"\'':
            quote, j = text[i], i + 1
            while j < n and text[j] != quote and text[j] != '\n':
                j += 2 if text[j] == '\\' else 1
            out.append(quote + quote if blank_strings else text[i:j + 1])
            i = j + 1
        else:
            out.append(text[i])
            i += 1
    return ''.join(out)


def balanced(text):
    stack, pairs = [], {')': '(', ']': '[', '}': '{'}
    for c in strip_comments(text, blank_strings=True):
        if c in '([{':
            stack.append(c)
        elif c in pairs:
            if not stack or stack.pop() != pairs[c]:
                return False
    return not stack


def inside_debug(code, word):
    """Every line with `word` is inside an #ifdef DEBUG_ENABLED block (and there is one)."""
    depth, debug_at, found = 0, [], 0
    for line in code.splitlines():
        s = line.strip()
        if re.match(r'#\s*if', s):
            depth += 1
            if re.match(r'#\s*ifdef\s+DEBUG_ENABLED\b', s) or re.match(r'#\s*if\s+defined\s*\(\s*DEBUG_ENABLED\s*\)\s*$', s):
                debug_at.append(depth)
        elif re.match(r'#\s*else|#\s*elif', s):
            if debug_at and debug_at[-1] == depth:
                debug_at.pop()
        elif re.match(r'#\s*endif', s):
            if debug_at and debug_at[-1] == depth:
                debug_at.pop()
            depth -= 1
        elif word in s:
            found += 1
            if not debug_at:
                return False
    return found > 0


def check_gdip(plugin):
    cfg = parse_cfg(read(plugin / 'web_view.gdip'))
    config, deps = cfg.get('config', {}), cfg.get('dependencies', {})
    check(unquote(config.get('name', '')) == 'WebView', 'gdip: the plugin is named WebView', config.get('name', 'missing'))
    check(unquote(config.get('binary', '')) == 'web_view.xcframework', 'gdip: the binary is web_view.xcframework', config.get('binary', 'missing'))
    check(unquote(config.get('initialization', '')) == 'web_view_init' and unquote(config.get('deinitialization', '')) == 'web_view_deinit',
          'gdip: the entry points are web_view_init and web_view_deinit')

    def items(key):
        try:
            return json.loads(deps.get(key, 'null'))
        except ValueError:
            return None
    check(items('system') == ['WebKit.framework'], 'gdip: the only system framework is WebKit.framework', deps.get('system', 'missing'))
    check(all(items(k) == [] for k in ('linked', 'embedded', 'capabilities', 'files', 'linker_flags')),
          'gdip: nothing else is linked, embedded or required')
    check(not any('UsageDescription' in k for k in cfg.get('plist', {})), 'gdip: no permission (usage description) is declared')
    return config


def check_preset(root):
    cfg = parse_cfg(read(root / 'game/export_presets.cfg'))
    presets = {s: v for s, v in cfg.items() if re.fullmatch(r'preset\.\d+', s)}
    ipad = [s for s, v in presets.items() if unquote(v.get('name', '')) == 'iPad' and unquote(v.get('platform', '')) == 'iOS']
    if not check(len(ipad) == 1, 'preset: one iOS preset named iPad', f'found {len(ipad)}'):
        return [], []
    preset, options = presets[ipad[0]], cfg.get(ipad[0] + '.options', {})
    check(options.get('plugins/WebView') == 'true', 'preset: iPad enables plugins/WebView', options.get('plugins/WebView', 'missing'))
    check(options.get('plugins/PhotoLibrary') == 'true', 'preset: iPad keeps plugins/PhotoLibrary')
    include, exclude = filters(preset.get('include_filter', '')), filters(preset.get('exclude_filter', ''))
    check('web_city/*' in include, 'preset: include_filter has web_city/*', ', '.join(include))
    check({'locale/*.json', 'data/*.json', 'private/deployment.json'} <= set(include), 'preset: include_filter keeps its earlier entries', ', '.join(include))
    check('web_city/dev/*' in exclude and 'tests/*' in exclude, 'preset: exclude_filter has tests/* and web_city/dev/*', ', '.join(exclude))
    page = root / 'game/web_city'
    files = sorted(p.relative_to(root / 'game').as_posix() for p in page.rglob('*') if p.is_file())
    public = [f for f in files if not f.startswith('web_city/dev/')]
    dev = [f for f in files if f.startswith('web_city/dev/')] + ['web_city/dev/probe.html', 'web_city/dev/tools/probe.js']
    check('web_city/index.html' in public, 'page: game/web_city/index.html exists')
    missed = [f for f in public if not ships(f, include, exclude)]
    check(bool(public) and not missed, f'preset: the filters ship every page file ({len(public)} outside dev/)', ', '.join(missed[:5]))
    leaked = [f for f in dev if ships(f, include, exclude)]
    check(not leaked, f'preset: the filters ship nothing of web_city/dev/ ({len(dev)} paths tried)', ', '.join(leaked[:5]))
    check(not ships('tests/web_city/export.gd', include, exclude), 'preset: tests/web_city/ stays out')
    others = [unquote(v.get('name', s)) for s, v in presets.items()
              if unquote(v.get('platform', '')) != 'iOS' and cfg.get(s + '.options', {}).get('plugins/WebView') == 'true']
    check(not others, 'preset: no preset of another platform enables WebView', ', '.join(others))
    return include, exclude


def check_tv(root, source):
    hits = []
    for base in ('tv', 'scripts/tvos'):
        for path in sorted((root / base).rglob('*')):
            if not path.is_file() or path.suffix.lower() not in TEXT_SUFFIXES:
                continue
            if 'web_view' in path.name.lower() or 'webview' in path.name.lower():
                hits.append(f'{path.relative_to(root)} (file name)')
                continue
            for number, line in enumerate(path.read_text(encoding='utf-8', errors='replace').splitlines(), 1):
                if TV_WORDS.search(line):
                    hits.append(f'{path.relative_to(root)}:{number}')
    check((root / 'tv').is_dir() and (root / 'scripts/tvos').is_dir(), 'tvOS: tv/ and scripts/tvos/ are there to read')
    check(not hits, 'tvOS: no Apple TV file refers to WebView or WebKit', ', '.join(hits[:5]))
    code = strip_comments(source)
    guard = re.search(r'#\s*if\s+TARGET_OS_TV\s*\n\s*#\s*error\b', code)
    check(guard is not None and guard.start() < code.find('<WebKit/WebKit.h>'), 'tvOS: the source refuses to compile for tvOS before it imports WebKit')


def check_source(plugin, config):
    header, source = read(plugin / 'src/web_view.h'), read(plugin / 'src/web_view.mm')
    check(bool(header) and bool(source), 'source: src/web_view.h and src/web_view.mm exist')
    code, hcode = strip_comments(source), strip_comments(header)
    check(balanced(header) and balanced(source), 'source: brackets, braces and parentheses balance')

    bound = {}
    for m in re.finditer(r'ClassDB::bind_method\(\s*D_METHOD\(([^)]*)\)\s*,\s*&(\w+)::(\w+)\s*\)', code):
        names = re.findall(r'"([^"]*)"', m.group(1))
        bound[names[0]] = (names[1:], m.group(2), m.group(3))
    check({k: v[0] for k, v in bound.items()} == BOUND, 'source: the bound methods are open(root_dir, query), close, post(json), poll, is_open, stats',
          ', '.join(f'{k}({", ".join(v[0])})' for k, v in sorted(bound.items())))
    classes = {v[1] for v in bound.values()}
    cls = classes.pop() if len(classes) == 1 else ''
    check(bool(cls) and all(k == v[2] for k, v in bound.items()) and re.search(r'class\s+' + cls + r'\s*:\s*public\s+Object\b', hcode) is not None
          and f'GDCLASS({cls}, Object)' in hcode, 'source: one Object class binds them, each to the method of the same name', cls or 'several classes')
    sigs = {'open': r'bool\s+open\(const String &\w+, const String &\w+\)', 'close': r'void\s+close\(\)', 'post': r'\w+\s+post\(const String &\w+\)',
            'poll': r'PackedStringArray\s+poll\(\)', 'is_open': r'bool\s+is_open\(\) const', 'stats': r'Dictionary\s+stats\(\) const'}
    wrong = [k for k, rx in sigs.items() if not re.search(rx, hcode)]
    check(not wrong, 'source: the header declares open -> bool, poll -> PackedStringArray, is_open -> bool, stats -> Dictionary', ', '.join(wrong))
    check(cls != 'WebView', 'source: the C++ class is not called WebView (WebKit has an Objective-C class of that name)')

    init, deinit = unquote(config.get('initialization', '')), unquote(config.get('deinitialization', ''))
    check(bool(init) and re.search(r'^void ' + re.escape(init) + r'\(\) \{', code, re.M) is not None
          and bool(deinit) and re.search(r'^void ' + re.escape(deinit) + r'\(\) \{', code, re.M) is not None,
          'source: the entry points of the gdip are defined')
    check(re.search(r'add_singleton\(Engine::Singleton\("WebView",', code) is not None, 'source: the Engine singleton is registered as "WebView"')

    check('@"lantern"' in code and re.search(r'setURLSchemeHandler:\w+ forURLScheme:', code) is not None and '@"lantern://city/index.html"' in code
          and '@"city"' in code, 'source: the scheme handler serves lantern://city/ and the page is lantern://city/index.html')
    check('@"godot"' in code and re.search(r'addScriptMessageHandler:\w+ name:', code) is not None,
          'source: the page\'s message handler is named "godot"')
    proxy = re.search(r'@interface (\w+) : NSObject <WKScriptMessageHandler>\s*\n\s*@property\s*\([^)]*\bweak\b[^)]*\)', code)
    check(proxy is not None and re.search(r'addScriptMessageHandler:_?\w*proxy\w* name:', code, re.I) is not None
          and 'removeScriptMessageHandlerForName:' in code, 'source: the handler is a weak proxy, and close removes it')
    check('window.LL&&window.LL.recv(%@)' in code and 'evaluateJavaScript:' in code, 'source: post calls window.LL&&window.LL.recv(<json>)')

    check('realpath(' in code and re.search(r'if \(!\[\w+ hasPrefix:\w+\]\) \{\s*\*status = 403;', code) is not None,
          'source: path guard: the real path of a file must begin with the real root, else 403')
    check(re.search(r'isEqualToString:@"\.\."\]\) \{\s*return nil;', code) is not None, 'source: path guard: a ".." part is refused')
    check(re.search(r'\*status = 404;', code) is not None and 'statusCode:status' in code and 'NSHTTPURLResponse' in code,
          'source: a missing file is answered with an HTTP 404 response')
    types = dict(re.findall(r'@"(\w+)" : @"([^";]+)', code))
    wrong = [f'{k} -> {types.get(k, "missing")}' for k, v in MIME.items() if types.get(k) != v]
    check(not wrong, 'source: Content-Type by extension (html, js, mjs, json, bin, png, css)', ', '.join(wrong))
    check('@"Content-Type"' in code and '@"Content-Length"' in code, 'source: Content-Type and Content-Length are sent')
    check('stopURLSchemeTask:' in code and re.search(r'if \(!\[_live containsObject:\w+\]\) \{\s*return;', code) is not None,
          'source: a stopped request is never answered')
    check(re.search(r'dispatch_async\(_io,', code) is not None, 'source: files are read off the main thread')

    settings = ['scrollEnabled = NO', 'bounces = NO', 'contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever',
                'allowsBackForwardNavigationGestures = NO', 'allowsLinkPreview = NO', 'opaque = YES', 'backgroundColor = UIColor.whiteColor',
                'UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight']
    missing = [s for s in settings if s not in code]
    check(not missing, 'source: the web view is white, opaque, full-window, with no scrolling, bouncing, back gesture or link preview', ', '.join(missing))
    check(inside_debug(code, 'inspectable') and re.search(r'@available\(iOS 16\.4, \*\)', code) is not None,
          'source: inspectable only in DEBUG_ENABLED builds, on iOS 16.4 or later')
    check('webViewWebContentProcessDidTerminate:' in code and re.search(r'll_terminated\+\+;', code) is not None,
          'source: the end of the web process is counted and handled')
    missing = [k for k in STATS if f'out["{k}"]' not in code]
    check(not missing and 'thermalState' in code and 'phys_footprint' in code, 'source: stats has thermal, footprint_mb, dropped, web_process_terminated', ', '.join(missing))
    check('os_unfair_lock_lock(' in code and re.search(r'if \(ll_queue\.count >= kLLMaxQueued\)', code) is not None,
          'source: the page\'s messages wait in a bounded queue behind a lock')
    check(re.search(r'll_in_flight\.load\(\) >= kLLMaxInFlight', code) is not None and 'll_dropped++' in code, 'source: post drops and counts when too many calls are in flight')
    waits = [w for w in ('dispatch_sync(', 'dispatch_semaphore_wait(', 'dispatch_group_wait(', 'performSelectorOnMainThread', 'sleep(') if w in code]
    check(not waits, 'source: nothing waits for the main thread or the page', ', '.join(waits))
    return source


def check_build(root, plugin):
    build, model = plugin / 'build.sh', root / 'game/ios/plugins/photo_library/build.sh'
    check(build.is_file() and os.access(build, os.X_OK), 'build.sh: exists and is executable')
    bash = shutil.which('bash')
    if bash and build.is_file():
        r = subprocess.run([bash, '-n', str(build)], capture_output=True, text=True)
        check(r.returncode == 0, 'build.sh: bash -n accepts it', r.stderr.strip())

    def lines(path, rename):
        text = read(path)
        if rename:
            text = text.replace('photo_library', 'web_view').replace('PhotoLibrary', 'WebView')
        return [l.strip() for l in text.splitlines() if l.strip() and not l.strip().startswith('#')]
    ours, want = iter(lines(build, False)), lines(model, True)
    missing = [l for l in want if not any(l == o for o in ours)]     # an ordered subsequence
    check(bool(want) and not missing, f'build.sh: every step of photo_library/build.sh, renamed, in the same order ({len(want)} lines)', '; '.join(missing[:2]))
    stale = []
    for path in sorted(plugin.rglob('*')):
        inner = path.relative_to(plugin)
        if not path.is_file() or inner.parts[0] == 'build' or '.xcframework' in inner.parts[0] or path.name == 'README.md':
            continue
        text = read_any(path)
        if path.name == 'build.sh':     # its comments name the script it follows
            text = '\n'.join(l for l in text.splitlines() if not l.strip().startswith('#'))
        if re.search(r'photo_library|PhotoLibrary|Photos\.framework', text):
            stale.append(inner.as_posix())
    check(not stale, 'plugin: nothing is left of the photo plugin\'s names', ', '.join(stale))
    check_inspectable(plugin, build)
    debug, release, plain = (plugin / f'web_view.{v}xcframework' for v in ('debug.', 'release.', ''))
    if debug.exists() or release.exists() or plain.exists():
        check(debug.exists() and release.exists() and not plain.exists(),
              'frameworks: web_view.debug.xcframework and web_view.release.xcframework, and no plain web_view.xcframework')
    else:
        print('NOTE frameworks: not built here (run build.sh on the Mac)')


# Sample listings for check_inspectable.sh, in the forms the Mac's nm -C and strings -a print.
STUB = '                 U _objc_msgSend$setInspectable:\n'
OTHER_SYMBOLS = '                 U _objc_msgSend$addSubview:\n0000000000000000 T web_view_init()\n'
OTHER_STRINGS = 'cancelAll\nstats\n'
INSPECTABLE_CASES = [   # (what, variant, [(symbols, strings) per library], expected exit)
    ('a debug pair with the selector stub passes', 'debug', [(OTHER_SYMBOLS + STUB, OTHER_STRINGS)] * 2, 0),
    ('a debug pair with the selector string passes', 'debug', [(OTHER_SYMBOLS, OTHER_STRINGS + 'setInspectable:\n')] * 2, 0),
    ('a debug library without either fails', 'debug', [(OTHER_SYMBOLS, OTHER_STRINGS)], 1),
    ('a debug simulator library without either fails', 'debug', [(OTHER_SYMBOLS + STUB, OTHER_STRINGS), (OTHER_SYMBOLS, OTHER_STRINGS)], 1),
    ('a defined, not sent, setInspectable: symbol fails', 'debug', [(OTHER_SYMBOLS + '0000000000000000 T _objc_msgSend$setInspectable:\n', OTHER_STRINGS)], 1),
    ('another selector with the same start fails', 'debug', [(OTHER_SYMBOLS + '                 U _objc_msgSend$setInspectableX:\n', OTHER_STRINGS + 'setInspectableX:\n')], 1),
    ('the getter alone fails', 'debug', [(OTHER_SYMBOLS + '                 U _objc_msgSend$isInspectable\n', OTHER_STRINGS + 'isInspectable\n')], 1),
    ('an empty listing fails', 'debug', [('', OTHER_STRINGS)], 1),
    ('a clean release pair passes', 'release', [(OTHER_SYMBOLS, OTHER_STRINGS)] * 2, 0),
    ('a release library with the selector stub fails', 'release', [(OTHER_SYMBOLS + STUB, OTHER_STRINGS)], 1),
    ('a release library with the selector string fails', 'release', [(OTHER_SYMBOLS, OTHER_STRINGS + 'setInspectable:\n')], 1),
    ('a release simulator library with the stub as text fails', 'release', [(OTHER_SYMBOLS, OTHER_STRINGS), (OTHER_SYMBOLS, '_objc_msgSend$setInspectable:\n')], 1),
    ('an odd number of listings is refused', 'debug', [(OTHER_SYMBOLS + STUB, None)], 2),
]


def check_inspectable(plugin, build):
    """check_inspectable.sh exists, build.sh runs it on the device and the simulator listings, and it judges samples right."""
    tool = plugin / 'check_inspectable.sh'
    check(tool.is_file() and os.access(tool, os.X_OK), 'check_inspectable.sh: exists and is executable')
    calls = re.search(r'bash "\$HERE/check_inspectable\.sh" "\$variant" "\$OUT/\$variant/symbols\.txt" "\$OUT/\$variant/strings\.txt" \\\n'
                      r'\s*"\$OUT/\$variant/simulator-symbols\.txt" "\$OUT/\$variant/simulator-strings\.txt"\n', read(build)) if build.is_file() else None
    lists = all(re.search(rf'^\t{cmd} "\$OUT/\$variant/{lib}/libweb_view\.a" > "\$OUT/\$variant/{out}"$', read(build) if build.is_file() else '', re.M)
                for cmd, lib, out in (('nm -C', 'device', 'symbols.txt'), ('strings -a', 'device', 'strings.txt'),
                                      ('nm -C', 'simulator', 'simulator-symbols.txt'), ('strings -a', 'simulator', 'simulator-strings.txt')))
    check(calls is not None and lists, 'build.sh: lists both libraries with nm -C and strings -a and runs check_inspectable.sh on all four listings')
    bash = shutil.which('bash')
    if not (bash and tool.is_file()):
        return
    wrong = []
    work = Path(tempfile.mkdtemp(prefix='lantern-inspectable-'))
    try:
        for n, (what, variant, pairs, want) in enumerate(INSPECTABLE_CASES):
            args = []
            for i, (symbols, strings) in enumerate(pairs):
                for kind, text in (('symbols', symbols), ('strings', strings)):
                    if text is None:
                        continue
                    path = work / f'{n}-{i}-{kind}.txt'
                    path.write_text(text)
                    args.append(str(path))
            r = subprocess.run([bash, str(tool), variant] + args, capture_output=True, text=True)
            if r.returncode != want:
                wrong.append(f'{what} (exit {r.returncode}, want {want})')
    finally:
        shutil.rmtree(work, ignore_errors=True)
    check(not wrong, f'check_inspectable.sh: judges {len(INSPECTABLE_CASES)} sample listings right', '; '.join(wrong[:3]))


def read_any(path):
    try:
        return path.read_text(encoding='utf-8')
    except (UnicodeDecodeError, OSError):
        return ''


def check_export(root):
    """Exports the iPad preset's .pck from a copy of game/ with three probe files, and reads the result."""
    godot = root / 'scripts/godot.sh'
    work = Path(tempfile.mkdtemp(prefix='lantern-webview-'))
    try:
        game = work / 'game'
        shutil.copytree(root / 'game', game, ignore=shutil.ignore_patterns('private'))
        probes = {'web_city/ll_probe_ship.js': b'// LL-PROBE-SHIP-c41d07\n', 'web_city/dev/ll_probe_dev.html': b'<!-- LL-PROBE-DEV-7f3a91 -->\n',
                  'web_city/dev/deep/ll_probe_deep.js': b'// LL-PROBE-DEEP-52e0bb\n', 'tests/web_city/ll_probe_tests.js': b'// LL-PROBE-TESTS-9a6f13\n'}
        for name, data in probes.items():
            (game / name).parent.mkdir(parents=True, exist_ok=True)
            (game / name).write_bytes(data)
        out = work / 'ipad.pck'
        r = subprocess.run([str(godot), '--headless', '--path', str(game), '--export-pack', 'iPad', str(out)],
                           capture_output=True, text=True, timeout=1500)
        pck = out.read_bytes() if out.exists() else b''
        check(r.returncode == 0 and len(pck) > 0, f'export: the iPad .pck is written (exit {r.returncode}, {len(pck)} bytes)')
        for line in sorted({l.strip() for l in (r.stdout + r.stderr).splitlines() if 'plugin' in l.lower()}):
            print('NOTE export says: ' + line[:200])
        page = [p for p in sorted((game / 'web_city').rglob('*')) if p.is_file() and 'dev' not in p.relative_to(game).parts]
        missing = [p.relative_to(game).as_posix() for p in page if p.relative_to(game).as_posix().encode() not in pck or p.read_bytes() not in pck]
        check(bool(pck) and not missing, f'export: the .pck holds every page file, by path and with its exact bytes ({len(page)} files, '
              f'{sum(p.stat().st_size for p in page)} bytes)', ', '.join(missing[:5]))
        check(bool(pck) and b'll_probe_dev' not in pck and b'LL-PROBE-DEV-7f3a91' not in pck and b'll_probe_deep' not in pck and b'LL-PROBE-DEEP-52e0bb' not in pck,
              'export: the .pck holds nothing of web_city/dev/ (two probe files, by name and by bytes)')
        check(bool(pck) and b'll_probe_tests' not in pck and b'LL-PROBE-TESTS-9a6f13' not in pck, 'export: the .pck holds nothing of tests/web_city/ (a probe file)')
    finally:
        shutil.rmtree(work, ignore_errors=True)


def main():
    args = [a for a in sys.argv[1:] if a != '--export']
    if len(args) > 1 or any(a.startswith('-') for a in args):
        print(__doc__)
        return 2
    root = Path(args[0]).resolve() if args else HERE
    plugin = root / 'game/ios/plugins/web_view'
    config = check_gdip(plugin)
    check_preset(root)
    source = check_source(plugin, config)
    check_tv(root, source)
    check_build(root, plugin)
    if '--export' in sys.argv[1:]:
        check_export(root)
    print(f'WEB VIEW PLUGIN CHECK {"PASS" if failures == 0 else "FAIL"}: {failures} failures')
    return 1 if failures else 0


if __name__ == '__main__':
    sys.exit(main())
