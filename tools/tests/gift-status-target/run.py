import argparse
import json
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser()
parser.add_argument('--reactions', type=Path, default=root / 'packages/Reactions/Sources/Reactions/Reactions.swift')
parser.add_argument('--nft', type=Path, default=root / 'packages/StarsUI/Sources/StarsUI/StarGift_Nft_Controller.swift')
parser.add_argument('--list', type=Path, default=root / 'packages/StarsUI/Sources/StarsUI/PeerMediaGiftsController.swift')
parser.add_argument('--filter')
parser.add_argument('--skip')
args = parser.parse_args()
def block(source, marker):
    start = source.index(marker); end = source.index('{', start) + 1; depth = 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}'); end += 1
    return source[start:end].replace('public ', '')
fixture = Path(__file__).with_name('GiftStatusTargetTests.swift').read_text()
fixture = fixture.replace('__REACTIONS__', block(args.reactions.read_text(), '    public func setStatus('))
nft = args.nft.read_text(); listing = args.list.read_text()
fixture = fixture.replace('__WEARED__', block(nft, '    public var weared: Bool'))
fixture = fixture.replace('__NFT_TOGGLE__', block(nft, 'toggleWear: { gift in').split(': ',1)[1])
fixture = fixture.replace('__LIST_TOGGLE__', block(listing, 'toggleWear: { option in').split(': ',1)[1])
a = listing.index('                            let weared'); b = listing.index('                            items.append(ContextMenuItem(weared', a)
fixture = fixture.replace('__MENU__', listing[a:b]+'return weared')
with tempfile.TemporaryDirectory(prefix='gift-status-target-') as directory:
    directory = Path(directory)
    dependency = json.dumps(str(root / 'submodules/telegram-ios/submodules/SSignalKit'))
    (directory / 'Package.swift').write_text('''// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "GiftStatusTarget", platforms: [.macOS(.v10_13)], dependencies: [.package(path: ''' + dependency + ''')], targets: [.testTarget(name: "GiftStatusTargetTests", dependencies: [.product(name: "SwiftSignalKit", package: "SSignalKit")], path: "Tests")])
''')
    (directory / 'Tests').mkdir()
    (directory / 'Tests/GiftStatusTargetTests.swift').write_text(fixture)
    command = ['swift', 'test', '--package-path', str(directory), '--disable-sandbox', '--jobs', '4']
    if args.filter: command += ['--filter', args.filter]
    if args.skip: command += ['--skip', args.skip]
    raise SystemExit(subprocess.run(command).returncode)
