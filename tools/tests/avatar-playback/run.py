import argparse
import json
from pathlib import Path
import subprocess
import tempfile
root=Path(__file__).resolve().parents[3]
parser=argparse.ArgumentParser();parser.add_argument('--baseline',action='store_true');args=parser.parse_args()
controller=(Path('/tmp/VideoAvatarModalController-before-playback.swift') if args.baseline else root/'packages/AvatarEditorUI/Sources/AvatarEditorUI/VideoAvatarModalController.swift').read_text()
scrubber=(Path('/tmp/VideoEditorScrubbler-before-drag.swift') if args.baseline else root/'packages/AvatarEditorUI/Sources/AvatarEditorUI/VideoEditorScrubbler.swift').read_text()
def block(s,marker):
 a=s.index(marker);b=s.index('{',a)+1;depth=1
 while depth:
  depth+=(s[b]=='{')-(s[b]=='}');b+=1
 return s[a:b]
values=block(scrubber,'public struct VideoScrubberValues').replace('public ','')
methods='\n'.join(block(controller,marker).replace('private ','').replace('public ','') for marker in ['    private func applyValuesToPlayer','    @discardableResult private func seekToNormal','    private func play()','    public override func viewWillAppear','    public override func viewWillDisappear'])
viewDidLoad=block(controller,'    public override func viewDidLoad()')
if args.baseline:
 a=viewDidLoad.index('        let duration =');b=viewDidLoad.index('        genericView.scrubberView.updateValues',a)
 notification=block(viewDidLoad,'        self.playToEndObserver =')
else:
 a=viewDidLoad.index('        guard let initialValues =');b=viewDidLoad.index('        genericView.scrubberView.updateValues',a);notification=''
initialization=viewDidLoad[a:b]
a=scrubber.index('            let value = difference.x /');a=scrubber.rfind('        distance.set(handler:',0,a)
drag=block(scrubber[a:],'distance.set(handler:').split('handler: ',1)[1]
rangeSource=(root/'packages/AvatarEditorUI/Sources/AvatarEditorUI/EditedAvatarVideoExport.swift').read_text();rangeSource=block(rangeSource,'struct EditedAvatarVideoRange')
initial=(root/'packages/AvatarEditorUI/Sources/AvatarEditorUI/EditedAvatarVideoPlayback.swift').read_text().replace('import Foundation','')
fixture=Path(__file__).with_name('AvatarPlaybackTests.swift').read_text().replace('__VALUES__',values).replace('__METHODS__',methods).replace('__INITIALIZATION__',initialization).replace('__NOTIFICATION__',notification).replace('__DRAG__',drag).replace('__RANGE__',rangeSource).replace('__INITIAL__',initial)
with tempfile.TemporaryDirectory(prefix='avatar-playback-') as directory:
 directory=Path(directory)
 (directory/'Package.swift').write_text('''// swift-tools-version:5.9
import PackageDescription
let package=Package(name:"AvatarPlayback",platforms:[.macOS(.v10_13)],dependencies:[.package(path:'''+json.dumps(str(root/'submodules/telegram-ios/submodules/SSignalKit'))+''')],targets:[.testTarget(name:"PlaybackTests",dependencies:[.product(name:"SwiftSignalKit",package:"SSignalKit")],path:"Tests")])
''')
 (directory/'Tests').mkdir();(directory/'Tests/AvatarPlaybackTests.swift').write_text(fixture)
 raise SystemExit(subprocess.run(['swift','test','--package-path',str(directory),'--disable-sandbox','--jobs','4']).returncode)
