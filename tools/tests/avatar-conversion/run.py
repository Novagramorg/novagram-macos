import argparse
import json
from pathlib import Path
import subprocess
import tempfile
root=Path(__file__).resolve().parents[3]
parser=argparse.ArgumentParser();parser.add_argument('--source',type=Path,default=root/'packages/AvatarEditorUI/Sources/AvatarEditorUI/MediaObjectToAvatar.swift');args=parser.parse_args()
s=args.source.read_text()
a=s.index('private final class StickerToMp4Context');b=s.index('private final class StickerToMp4 {',a)
context=s[a:b].replace('private ', '').replace('public ', '').replace('any AccountContextProtocol','Context')
f=(root/'packages/AvatarEditorUI/Sources/AvatarEditorUI/AvatarVideoExport.swift').read_text();a=f.index('struct AvatarVideoFrameSequence');b=f.index('final class AvatarVideoExport',a)
fixture=Path(__file__).with_name('AvatarConversionTests.swift').read_text().replace('__CONTEXT__',context).replace('__SEQUENCE__',f[a:b])
with tempfile.TemporaryDirectory(prefix='avatar-conversion-') as directory:
 directory=Path(directory)
 (directory/'Package.swift').write_text('''// swift-tools-version:5.9
import PackageDescription
let package=Package(name:"AvatarConversion",platforms:[.macOS(.v10_13)],dependencies:[.package(path:'''+json.dumps(str(root/'submodules/telegram-ios/submodules/SSignalKit'))+''')],targets:[.testTarget(name:"AvatarConversionTests",dependencies:[.product(name:"SwiftSignalKit",package:"SSignalKit")],path:"Tests")])
''')
 (directory/'Tests').mkdir();(directory/'Tests/AvatarConversionTests.swift').write_text(fixture)
 raise SystemExit(subprocess.run(['swift','test','--package-path',str(directory),'--disable-sandbox','--jobs','4']).returncode)
