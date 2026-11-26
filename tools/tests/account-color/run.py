import argparse
import json
from pathlib import Path
import subprocess
import tempfile

root=Path(__file__).resolve().parents[3]
parser=argparse.ArgumentParser()
parser.add_argument('--source',type=Path,default=root/'submodules/telegram-ios/submodules/TelegramCore/Sources/TelegramEngine/AccountData/UpdateAccountPeerName.swift')
args=parser.parse_args()
def block(s,marker):
    a=s.index(marker);b=s.index('{',a)+1;depth=1
    while depth:
        depth+=(s[b]=='{')-(s[b]=='}');b+=1
    return s[a:b].replace('public ','')
s=args.source.read_text()
markers=['public enum UpdateNameColor {','public enum UpdateNameColorAndEmojiError {','private final class AccountPeerColorRequestDependencyTag:','private func _internal_applyAccountPeerColor(','func _internal_updateNameColorAndEmoji(']
source='\n'.join(block(s,m) for m in markers if m in s)
fixture=Path(__file__).with_name('AccountColorTests.swift').read_text().replace('__SOURCE__',source)
with tempfile.TemporaryDirectory(prefix='account-color-') as directory:
    directory=Path(directory);dependency=json.dumps(str(root/'submodules/telegram-ios/submodules/SSignalKit'))
    (directory/'Package.swift').write_text('''// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "AccountColor", platforms: [.macOS(.v10_13)], dependencies: [.package(path: '''+dependency+''')], targets: [.testTarget(name: "AccountColorTests", dependencies: [.product(name: "SwiftSignalKit", package: "SSignalKit")], path: "Tests")])
''')
    (directory/'Tests').mkdir();(directory/'Tests/AccountColorTests.swift').write_text(fixture)
    raise SystemExit(subprocess.run(['swift','test','--package-path',str(directory),'--disable-sandbox','--jobs','4']).returncode)
