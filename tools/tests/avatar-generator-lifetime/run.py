import argparse
import json
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser()
parser.add_argument('--source', type=Path, default=root / 'packages/AvatarEditorUI/Sources/AvatarEditorUI/MediaObjectToAvatar.swift')
args = parser.parse_args()
s = args.source.read_text().split('public final class MediaObjectToAvatar {', 1)[1]
def block(source, marker):
    a=source.index(marker);b=source.index('{',a)+1;depth=1
    while depth:
        depth+=(source[b]=='{')-(source[b]=='}');b+=1
    return source[a:b]
start=block(s,'    public func start()')
if 'holder = self' in start:
    a=start.index('        let background:');b=start.index('        return signal |> afterNext')
    start=start[:a]+'        let signal = self.generate()\n'+start[b:]
fixture=Path(__file__).with_name('AvatarGeneratorLifetimeTests.swift').read_text().replace('__START__',start.replace('public ',''))
with tempfile.TemporaryDirectory(prefix='avatar-generator-lifetime-') as directory:
    directory=Path(directory)
    (directory/'Package.swift').write_text('''// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "AvatarGeneratorLifetime", platforms: [.macOS(.v10_13)], dependencies: [.package(path: '''+json.dumps(str(root/'submodules/telegram-ios/submodules/SSignalKit'))+''')], targets: [.testTarget(name: "AvatarGeneratorLifetimeTests", dependencies: [.product(name: "SwiftSignalKit", package: "SSignalKit")], path: "Tests")])
''')
    (directory/'Tests').mkdir();(directory/'Tests/AvatarGeneratorLifetimeTests.swift').write_text(fixture)
    raise SystemExit(subprocess.run(['swift','test','--package-path',str(directory),'--disable-sandbox','--jobs','4']).returncode)
