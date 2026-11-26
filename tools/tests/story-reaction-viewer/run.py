import argparse
import json
from pathlib import Path
import subprocess
import tempfile
root=Path(__file__).resolve().parents[3]
parser=argparse.ArgumentParser()
parser.add_argument('--source',type=Path,default=root/'packages/StoriesUI/Sources/StoriesUI/StoryModalController.swift')
args=parser.parse_args();source=args.source.read_text()
start=source.index('        }, like: {')
start=source.index('current, state in',start)+len('current, state in')
end=source.index('        }, showLikePanel:',start)
fixture=Path(__file__).with_name('StoryReactionViewerTests.swift').read_text().replace('__ACTION__',source[start:end])
with tempfile.TemporaryDirectory(prefix='story-reaction-viewer-') as directory:
    path=Path(directory);dependency=json.dumps(str(root/'submodules/telegram-ios/submodules/SSignalKit'))
    (path/'Package.swift').write_text('// swift-tools-version:5.9\nimport PackageDescription\nlet package=Package(name:"StoryReactionViewer",platforms:[.macOS(.v10_13)],dependencies:[.package(path:'+dependency+')],targets:[.testTarget(name:"StoryReactionViewerTests",dependencies:[.product(name:"SwiftSignalKit",package:"SSignalKit")],path:"Tests")])\n')
    (path/'Tests').mkdir();(path/'Tests/StoryReactionViewerTests.swift').write_text(fixture)
    raise SystemExit(subprocess.run(['swift','test','--package-path',str(path),'--disable-sandbox','--jobs','4']).returncode)
