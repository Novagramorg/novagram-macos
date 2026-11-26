import argparse
import json
from pathlib import Path
import subprocess
import tempfile
root=Path(__file__).resolve().parents[3]
parser=argparse.ArgumentParser();parser.add_argument('--baseline',action='store_true');args=parser.parse_args()
source=(root/'packages/AvatarEditorUI/Sources/AvatarEditorUI/EditedAvatarVideoComposition.swift').read_text()
controller=(root/'packages/AvatarEditorUI/Sources/AvatarEditorUI/VideoAvatarModalController.swift').read_text()
def block(text,marker):
 a=text.index(marker);b=text.index('{',a)+1;depth=1
 while depth:
  depth+=(text[b]=='{')-(text[b]=='}');b+=1
 return text[a:b]
if args.baseline:
 controller=subprocess.check_output(['git','show','6bb9f7ec39259d7a4537820620f775bd82b8becf:packages/AvatarEditorUI/Sources/AvatarEditorUI/VideoAvatarModalController.swift'],cwd=root,text=True)
 method=block(controller,'    private func currentVideoComposition()').replace('private ','')
 a=source.index('func editedAvatarVideoComposition(');b=source.index('func prepareEditedAvatarVideo',a)
 previous='''extension CGRect {func apply(multiplier:CGSize)->CGRect {CGRect(x:origin.x*multiplier.width,y:origin.y*multiplier.height,width:width*multiplier.width,height:height*multiplier.height)}}
final class CropSelection {let selectedRect:CGRect;init(_ rect:CGRect) {selectedRect=rect}}
final class CropView {let selectionRectView:CropSelection;let playerSize:CGSize;init(_ rect:CGRect,_ size:CGSize) {selectionRectView=CropSelection(rect);playerSize=size}}
final class PriorController {
 let asset:AVComposition
 let track:AVAssetTrack
 let videoSize:CGSize
 let genericView:CropView
 init(_ asset:AVComposition,_ track:AVAssetTrack,_ rect:CGRect,_ size:CGSize) {self.asset=asset;self.track=track;let transformed=track.naturalSize.applying(track.preferredTransform);videoSize=CGSize(width:abs(transformed.width),height:abs(transformed.height));genericView=CropView(rect,size)}
'''+method+'''
}
func editedAvatarVideoComposition(track:AVAssetTrack,duration:CMTime,selection:CGRect?=nil,viewSize:CGSize?=nil)->AVVideoComposition? {
 guard let asset=track.asset as? AVComposition else {return nil}
 return PriorController(asset,track,selection ?? CGRect(origin:.zero,size:track.naturalSize),viewSize ?? track.naturalSize).currentVideoComposition()
}
'''
 source=source[:a]+previous+source[b:]
selection=block(controller,'public func selectVideoAvatar(').replace('public ','')
state=controller[controller.index('public enum VideoAvatarGeneratorState'):controller.index('public class VideoAvatarModalController')]
with tempfile.TemporaryDirectory(prefix='avatar-video-composition-') as directory:
 directory=Path(directory)
 (directory/'Package.swift').write_text('''// swift-tools-version:5.9
import PackageDescription
let package=Package(name:"AvatarComposition",platforms:[.macOS(.v10_13)],dependencies:[.package(path:'''+json.dumps(str(root/'submodules/telegram-ios/submodules/SSignalKit'))+''')],targets:[.testTarget(name:"CompositionTests",dependencies:[.product(name:"SwiftSignalKit",package:"SSignalKit")],path:"Tests")])
''')
 (directory/'Tests').mkdir()
 (directory/'Tests/EditedAvatarVideoComposition.swift').write_text(source)
 (directory/'Tests/AvatarVideoExport.swift').write_text((root/'packages/AvatarEditorUI/Sources/AvatarEditorUI/AvatarVideoExport.swift').read_text())
 (directory/'Tests/EditedAvatarVideoExport.swift').write_text((root/'packages/AvatarEditorUI/Sources/AvatarEditorUI/EditedAvatarVideoExport.swift').read_text())
 (directory/'Tests/GeometryTests.swift').write_text(Path(__file__).with_name('GeometryTests.swift').read_text())
 (directory/'Tests/NativeTests.swift').write_text(Path(__file__).with_name('NativeTests.swift').read_text().replace('__SELECTION__',selection).replace('__STATE__',state))
 command=['swift','test','--package-path',str(directory),'--disable-sandbox','--jobs','4']
 if args.baseline:command+=['--filter','(NativeCropTests|SelectionTests)']
 raise SystemExit(subprocess.run(command).returncode)
