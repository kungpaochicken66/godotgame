"""Install manifest-verified TV brand assets into a disposable Godot export."""
from pathlib import Path
import hashlib, json, shutil, struct, sys
source, export = map(Path, sys.argv[1:3])
manifest = json.loads((source / 'manifest.json').read_text())
assets = export / 'LanternLane/Images.xcassets'
brand = assets / 'AppIcon.brandassets'
mappings = {}
for layer in ('back', 'middle', 'front'):
    for scale in (1, 2):
        mappings[f'app_icon_{layer}_{scale}x.png'] = brand / f'App Icon.imagestack/{layer.title()}.imagestacklayer/Content.imageset/AppIcon-400x240-{layer.title()}@{scale}x.png'
    mappings[f'app_icon_app_store_{layer}_1x.png'] = brand / f'App Icon - App Store.imagestack/{layer.title()}.imagestacklayer/Content.imageset/AppIcon-1280x768-{layer.title()}@1x.png'
for scale in (1, 2):
    mappings[f'top_shelf_{scale}x.png'] = brand / f'Top Shelf Image.imageset/TopShelf-1920x720@{scale}x.png'
    mappings[f'top_shelf_wide_{scale}x.png'] = brand / f'Top Shelf Image Wide.imageset/TopShelfWide-2320x720@{scale}x.png'
assert set(mappings) == set(manifest), 'Unexpected brand manifest'
for name, target in mappings.items():
    data = (source / name).read_bytes()
    assert hashlib.sha256(data).hexdigest() == manifest[name]['sha256'], name
    assert list(struct.unpack('>II', data[16:24])) == manifest[name]['size'], name
    assert target.is_file(), target
# Validate every input and export path before changing any asset.
for name, target in mappings.items():
    shutil.copyfile(source / name, target)
splash = assets / 'SplashImage.imageset'
assert splash.is_dir()
# Remove only the two known generated Godot splash files replaced by our catalog.
for old in ('splash@2x.png', 'splash@3x.png'):
    if (splash / old).is_file(): (splash / old).unlink()
for scale in (1, 2):
    shutil.copyfile(source / f'top_shelf_{scale}x.png', splash / f'lantern-tv-{scale}x.png')
(splash / 'Contents.json').write_text(json.dumps({'images': [{'idiom': 'tv', 'scale': f'{s}x', 'filename': f'lantern-tv-{s}x.png'} for s in (1, 2)], 'info': {'author': 'xcode', 'version': 1}}, indent=2) + '\n')
print(json.dumps({'brand_assets_installed': len(mappings), 'launch_image': 'original Lantern Lane top shelf art', 'source_manifest_sha256': hashlib.sha256((source / 'manifest.json').read_bytes()).hexdigest()}))
