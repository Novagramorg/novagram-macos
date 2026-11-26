import argparse
import json
from pathlib import Path
import subprocess
import tempfile
root=Path(__file__).resolve().parents[3]
parser=argparse.ArgumentParser()
parser.add_argument('--adapter-source',type=Path,default=root/'packages/AvatarEditorUI/Sources/AvatarEditorUI/MakeAvatarVideo.swift')
parser.add_argument('--source',type=Path,default=root/'packages/AvatarEditorUI/Sources/AvatarEditorUI/MediaObjectToAvatar.swift')
args=parser.parse_args()
adapter='\n'.join(x for x in args.adapter_source.read_text().splitlines() if not x.startswith('import ')).replace('public ','')
source=(root/'packages/AvatarEditorUI/Sources/AvatarEditorUI/AvatarMediaPreparation.swift').read_text()
s=args.source.read_text()
classes=s[s.index('private final class FetchVideoToFile'):s.index('public final class MediaObjectToAvatar')].replace('private ','').replace('public ','').replace('any AccountContextProtocol','Context')
resource=source[source.index('func avatarMediaResourcePath'):].replace('any AccountContextProtocol','Context')
native=source[:source.index('func avatarMediaResourcePath')]
native='\n'.join(line for line in native.splitlines() if not line.startswith('import Telegram'))
with tempfile.TemporaryDirectory(prefix='avatar-media-preparation-') as directory:
 directory=Path(directory)
 (directory/'Package.swift').write_text('''// swift-tools-version:5.9
import PackageDescription
let package=Package(name:"AvatarMediaPreparation",platforms:[.macOS(.v10_13)],dependencies:[.package(path:'''+json.dumps(str(root/'submodules/telegram-ios/submodules/SSignalKit'))+''')],targets:[.testTarget(name:"SourceTests",dependencies:[.product(name:"SwiftSignalKit",package:"SSignalKit")],path:"Sources"),.testTarget(name:"NativePreparationTests",dependencies:[.product(name:"SwiftSignalKit",package:"SSignalKit")],path:"Native")])
''')
 (directory/'Sources').mkdir();(directory/'Native').mkdir()
 (directory/'Sources/SourceTests.swift').write_text(Path(__file__).with_name('SourceTests.swift').read_text().replace('__RESOURCE__',resource).replace('__CLASSES__',classes).replace('__ADAPTER__',adapter))
 (directory/'Native/AvatarMediaPreparation.swift').write_text(native)
 (directory/'Native/AvatarVideoExport.swift').write_text((root/'packages/AvatarEditorUI/Sources/AvatarEditorUI/AvatarVideoExport.swift').read_text())
 (directory/'Native/NativePreparationTests.swift').write_text(Path(__file__).with_name('NativePreparationTests.swift').read_text())
 raise SystemExit(subprocess.run(['swift','test','--package-path',str(directory),'--disable-sandbox','--jobs','4']).returncode)
