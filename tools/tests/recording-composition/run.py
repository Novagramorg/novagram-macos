import argparse
import json
from pathlib import Path
import subprocess
import tempfile
root=Path(__file__).resolve().parents[3]
parser=argparse.ArgumentParser();parser.add_argument('--baseline',action='store_true');args=parser.parse_args()
path=Path('/tmp/VideoRecorderPipeline-before-recording-composition.swift') if args.baseline else root/'packages/MediaRecorderUI/Sources/MediaRecorderUI/VideoRecorderPipeline.swift'
s=path.read_text()
def block(marker):
 a=s.index(marker);b=s.index('{',a)+1;depth=1
 while depth:
  depth+=(s[b]=='{')-(s[b]=='}');b+=1
 return s[a:b].replace('private ','')
methods='\n'.join(block(x) for x in ['private func composedRecording','private func clearComposedURL','private func finishWithComposedResult'])
if args.baseline:
 methods=methods.replace('func composedRecording(_ completion:', 'func originalComposedRecording(_ completion:')
 methods=methods.replace('self.composedRecording { path, duration in','self.composedRecording { result in\n guard let (path,duration)=result else{return}')
 methods+='\nfunc composedRecording(_ completion: @escaping ((String, Double)?) -> Void) { originalComposedRecording { path,duration in completion((path,duration)) } }'
helper=(root/'packages/MediaRecorderUI/Sources/MediaRecorderUI/RecordingVideoComposition.swift').read_text()
fixture=Path(__file__).with_name('ControlledTests.swift').read_text().replace('__METHODS__',methods).replace('__HELPERS__','\n'.join(x for x in helper.splitlines() if not x.startswith('import ')))
with tempfile.TemporaryDirectory(prefix='recording-composition-') as directory:
 directory=Path(directory)
 (directory/'Package.swift').write_text('''// swift-tools-version:5.9
import PackageDescription
let package=Package(name:"RecordingComposition",platforms:[.macOS(.v10_13)],dependencies:[.package(path:'''+json.dumps(str(root/'submodules/telegram-ios/submodules/SSignalKit'))+''')],targets:[.testTarget(name:"ControlledTests",dependencies:[.product(name:"SwiftSignalKit",package:"SSignalKit")],path:"Controlled"),.testTarget(name:"NativeTests",dependencies:[],path:"Native")])
''')
 (directory/'Controlled').mkdir();(directory/'Controlled/ControlledTests.swift').write_text(fixture)
 (directory/'Native').mkdir();(directory/'Native/RecordingVideoComposition.swift').write_text(helper)
 (directory/'Native/AvatarVideoExport.swift').write_text((root/'packages/AvatarEditorUI/Sources/AvatarEditorUI/AvatarVideoExport.swift').read_text())
 (directory/'Native/NativeTests.swift').write_text(Path(__file__).with_name('NativeTests.swift').read_text())
 command=['swift','test','--package-path',str(directory),'--disable-sandbox','--jobs','4']
 if args.baseline:command+=['--filter','CompositionTests']
 raise SystemExit(subprocess.run(command).returncode)
