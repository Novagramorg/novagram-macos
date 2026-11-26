import argparse
import json
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser()
parser.add_argument('--source', type=Path, default=root / 'submodules/telegram-ios/submodules/TelegramCore/Sources/TelegramEngine/Privacy/CloseFriends.swift')
args = parser.parse_args()
source = args.source.read_text()
source = source[source.index('public '):].replace('public ', '')
network = (root / 'submodules/telegram-ios/submodules/TelegramCore/Sources/Network/Network.swift').read_text()
retry = network[network.index('public func retryRequest<T>'):network.index('public func retryRequestIfNotFrozen')].replace('public ', '')
fixture = Path(__file__).with_name('CloseFriendsTests.swift').read_text().replace('__SOURCE__', source + retry)
with tempfile.TemporaryDirectory(prefix='close-friends-') as directory:
    directory = Path(directory)
    dependency = json.dumps(str(root / 'submodules/telegram-ios/submodules/SSignalKit'))
    (directory / 'Package.swift').write_text('''// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "CloseFriends", platforms: [.macOS(.v10_13)], dependencies: [.package(path: ''' + dependency + ''')], targets: [.testTarget(name: "CloseFriendsTests", dependencies: [.product(name: "SwiftSignalKit", package: "SSignalKit")], path: "Tests")])
''')
    (directory / 'Tests').mkdir()
    (directory / 'Tests/CloseFriendsTests.swift').write_text(fixture)
    raise SystemExit(subprocess.run(['swift', 'test', '--package-path', str(directory), '--disable-sandbox', '--jobs', '4']).returncode)
