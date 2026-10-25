from pathlib import Path
import sys,xml.etree.ElementTree as ET,hashlib,json
p=Path(sys.argv[1])/'LanternLane'/'Launch Screen.storyboard'
before=p.read_bytes();root=ET.fromstring(before)
assert root.attrib['targetRuntime'] in ['iOS.CocoaTouch','AppleTV']
root.set('type','com.apple.InterfaceBuilder.AppleTV.Storyboard');root.set('targetRuntime','AppleTV')
for x in list(root):
 if x.tag=='device':root.remove(x)
for x in root.findall('./dependencies/deployment'):x.set('identifier','tvOS')
# The asset catalog is exported, but the shared template placeholder is not.
assert (p.parent/'Images.xcassets/SplashImage.imageset/Contents.json').is_file()
for element in root.iter():
 for key,value in list(element.attrib.items()):
  if value == '$launch_screen_image_file_name':element.set(key,'SplashImage')
view=root.find('./scenes/scene/objects/viewController/view/rect')
if view is not None:view.set('width','1920');view.set('height','1080')
p.write_bytes(b'<?xml version="1.0" encoding="UTF-8"?>\n'+ET.tostring(root,encoding='utf-8')+b'\n')
print(json.dumps({'storyboard':str(p),'before':hashlib.sha256(before).hexdigest(),'after':hashlib.sha256(p.read_bytes()).hexdigest(),'reason':'Upstream tvOS exporter emits iOS storyboard; converted to native AppleTV document type per Xcode tvOS template'}))
# The shared Apple template also includes visionOS privacy placeholders; tvOS
# exporter omitted the removal already implemented in the same revision's iOS exporter.
import plistlib,re
info=p.parent/'LanternLane-Info.plist'
s=info.read_text()
for key in ['$hand_tracking_usage_description','$accessory_tracking_usage_description']:
 s=s.replace(key,'')
assert not re.search(r'\$[a-z_][a-z_0-9]*',s),'Unresolved exporter placeholder'
v=plistlib.loads(s.encode())
for key in ['NSPhotoLibraryUsageDescription', 'NSCameraUsageDescription', 'NSMicrophoneUsageDescription']:
 if v.get(key) == '':v.pop(key)
v.pop('UIRequiresFullScreen', None) # Deprecated iOS template setting, no TV effect.
info.write_bytes(plistlib.dumps(v))
print('Removed unsupported visionOS template placeholders; Info.plist valid.')
