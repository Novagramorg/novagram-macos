import argparse
import json
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser()
parser.add_argument('--controller', type=Path, default=root / 'packages/StarsUI/Sources/StarsUI/StarGift_Nft_Controller.swift')
args = parser.parse_args()
def block(source, marker):
    start = source.index(marker)
    end = source.index('{', start) + 1
    depth = 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[start:end]
s = args.controller.read_text()
start = s.index('    let validateGift:')
switch = s.index('        switch state.source {', start)
a = s.index('        case let .previewWear(peer, gift):', switch)
b = s.index('        case let .upgrade(_, _, reference):', a)
validator = s[start:switch] + '        switch state.source {\n' + s[a:b] + '\n        default: break\n        }\n        return .none\n    }'
helper = (root / 'packages/StarsUI/Sources/StarsUI/GiftWearAction.swift').read_text()
helper = '\n'.join(line for line in helper.splitlines() if not line.startswith('import '))
fixture = Path(__file__).with_name('GiftWearTests.swift').read_text()
fixture = fixture.replace('__HELPER__', helper).replace('__VALIDATOR__', validator)
hooks = '\n'.join(block(s, marker) for marker in ['    controller.willDisappear =', '    controller.willAppear =', '    controller.onDeinit ='] if marker in s)
fixture = fixture.replace('__HOOKS__', hooks)
a = s.index('        case let .previewWear(owner, gift):', s.index('    let arguments = Arguments(context: context, window:'))
b = s.index('        case let .aboutCraft', a)
fixture = fixture.replace('__DISMISS__', s[a:b])
with tempfile.TemporaryDirectory(prefix='gift-wear-') as directory:
    directory = Path(directory)
    dependency = json.dumps(str(root / 'submodules/telegram-ios/submodules/SSignalKit'))
    (directory / 'Package.swift').write_text('''// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "GiftWear", platforms: [.macOS(.v10_13)], dependencies: [.package(path: ''' + dependency + ''')], targets: [.testTarget(name: "GiftWearTests", dependencies: [.product(name: "SwiftSignalKit", package: "SSignalKit")], path: "Tests")])
''')
    (directory / 'Tests').mkdir()
    (directory / 'Tests/GiftWearTests.swift').write_text(fixture)
    raise SystemExit(subprocess.run(['swift', 'test', '--package-path', str(directory), '--disable-sandbox', '--jobs', '4']).returncode)
