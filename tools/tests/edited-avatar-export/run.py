import argparse
import json
import re
from pathlib import Path
import subprocess
import tempfile
root=Path(__file__).resolve().parents[3]
parser=argparse.ArgumentParser();parser.add_argument('--baseline-timing',action='store_true');args=parser.parse_args()
source=(root/'packages/AvatarEditorUI/Sources/AvatarEditorUI/EditedAvatarVideoExport.swift').read_text()
if args.baseline_timing:
 old=subprocess.check_output(['git','show','6bb9f7ec39259d7a4537820620f775bd82b8becf:packages/AvatarEditorUI/Sources/AvatarEditorUI/VideoAvatarModalController.swift'],cwd=root,text=True)
 a=old.index('        let wholeDuration =');b=old.index('        if #available',a)
 timing=old[a:b]
 key=re.search(r'keyFrame: (values.keyFrame.*?nil)\)\)',old).group(1)
 previous='struct PriorAsset {let duration:CMTime}\nstruct PriorValues {let leftTrim:Double;let rightTrim:Double;let keyFrame:Double?}\nstruct EditedAvatarVideoRange {\n let timeRange:CMTimeRange\n let thumbnailTime:CMTime\n let keyFrame:Double?\n init?(duration inputDuration:Double,leftTrim:Double,rightTrim:Double,keyFrame:Double?) {\n let asset=PriorAsset(duration:CMTime(seconds:inputDuration,preferredTimescale:1000))\n let values=PriorValues(leftTrim:leftTrim,rightTrim:rightTrim,keyFrame:keyFrame)\n'+timing+'\n self.timeRange=CMTimeRangeMake(start:start,duration:duration)\n self.thumbnailTime=CMTimeMakeWithSeconds(Double(values.keyFrame ?? values.leftTrim) * asset.duration.seconds, preferredTimescale:1000)\n self.keyFrame='+key+'\n }\n}\n'
 a=source.index('struct EditedAvatarVideoRange');b=source.index('private final class EditedAvatarVideoFiles')
 source=source[:a]+previous+source[b:]
s=(root/'packages/AvatarEditorUI/Sources/AvatarEditorUI/VideoAvatarModalController.swift').read_text()
state=s[s.index('public enum VideoAvatarGeneratorState'):s.index('public class VideoAvatarModalController')]
with tempfile.TemporaryDirectory(prefix='edited-avatar-export-') as directory:
 directory=Path(directory)
 (directory/'Package.swift').write_text('''// swift-tools-version:5.9
import PackageDescription
let package=Package(name:"EditedAvatarExport",platforms:[.macOS(.v10_13)],dependencies:[.package(path:'''+json.dumps(str(root/'submodules/telegram-ios/submodules/SSignalKit'))+''')],targets:[.testTarget(name:"NativeTests",dependencies:[.product(name:"SwiftSignalKit",package:"SSignalKit")],path:"Native"),.testTarget(name:"ControlledTests",dependencies:[.product(name:"SwiftSignalKit",package:"SSignalKit")],path:"Controlled")])
''')
 (directory/'Native').mkdir();(directory/'Controlled').mkdir()
 (directory/'Native/EditedAvatarVideoExport.swift').write_text(source.replace('private ','')+'\n'+state)
 (directory/'Native/AvatarVideoExport.swift').write_text((root/'packages/AvatarEditorUI/Sources/AvatarEditorUI/AvatarVideoExport.swift').read_text())
 (directory/'Native/NativeTests.swift').write_text(Path(__file__).with_name('NativeTests.swift').read_text())
 controlled='\n'.join(x for x in source.splitlines() if not x.startswith('import ')).replace('private ','')
 (directory/'Controlled/ControlledTests.swift').write_text(Path(__file__).with_name('ControlledTests.swift').read_text().replace('__SOURCE__',controlled+'\n'+state))
 command=['swift','test','--package-path',str(directory),'--disable-sandbox','--jobs','4']
 if args.baseline_timing:command += ['--filter','TimingTests.test(Key|NoKey|Short)']
 raise SystemExit(subprocess.run(command).returncode)
