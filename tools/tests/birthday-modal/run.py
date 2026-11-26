import argparse
import json
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser()
parser.add_argument('--source', type=Path, default=root / 'packages/ChatUI/Sources/ChatUI/ChatServiceItem.swift')
args = parser.parse_args()
s = args.source.read_text();s = s[s.index('    public func openSuggestBirthday('):]
def block(s, marker):
    a=s.index(marker);b=s.index('{',a)+1;depth=1
    while depth:
        depth += (s[b]=='{')-(s[b]=='}');b+=1
    return s[a:b]
fixture=Path(__file__).with_name('BirthdayModalTests.swift').read_text()
helper=(root/'packages/ChatUI/Sources/ChatUI/ChatBirthdaySaveAction.swift').read_text()
helper='\n'.join(line for line in helper.splitlines() if not line.startswith('import '))
fixture=fixture.replace('__HELPER__',helper)
fixture=fixture.replace('__ACCEPT__',block(s,'accept: {').split('accept: ',1)[1])
fixture=fixture.replace('__HIDE__',block(s,'bottomLayout?.interactions.processURL =').split(' = ',1)[1])
fixture=fixture.replace('__LIFECYCLE__','\n'.join(block(s,'                override func '+name) for name in ['viewWillAppear(', 'viewWillDisappear(']))
with tempfile.TemporaryDirectory(prefix='birthday-modal-') as directory:
    directory=Path(directory);dependency=json.dumps(str(root/'submodules/telegram-ios/submodules/SSignalKit'))
    (directory/'Package.swift').write_text('''// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "BirthdayModal", platforms: [.macOS(.v10_13)], dependencies: [.package(path: '''+dependency+''')], targets: [.testTarget(name: "BirthdayModalTests", dependencies: [.product(name: "SwiftSignalKit", package: "SSignalKit")], path: "Tests")])
''')
    (directory/'Tests').mkdir();(directory/'Tests/BirthdayModalTests.swift').write_text(fixture)
    raise SystemExit(subprocess.run(['swift','test','--package-path',str(directory),'--disable-sandbox','--jobs','4']).returncode)
