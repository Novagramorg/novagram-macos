import argparse
import json
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser()
parser.add_argument('--source', type=Path, default=root / 'submodules/telegram-ios/submodules/TelegramCore/Sources/TelegramEngine/Privacy/BlockedPeersContext.swift')
args = parser.parse_args()
source = args.source.read_text()
source = source[source.index('public struct BlockedPeersContextState:'):].replace('public ', '')
network = (root / 'submodules/telegram-ios/submodules/TelegramCore/Sources/Network/Network.swift').read_text()
retry = network[network.index('public func retryRequestIfNotFrozen'):network.index('\nclass Keychain:')].replace('public ', '')
fixture = Path(__file__).with_name('BlockedPeersCoreTests.swift').read_text().replace('__CONTEXT__', source).replace('__RETRY__', retry)
with tempfile.TemporaryDirectory(prefix='blocked-peers-core-') as directory:
    directory = Path(directory)
    dependency = json.dumps(str(root / 'submodules/telegram-ios/submodules/SSignalKit'))
    (directory / 'Package.swift').write_text('''// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "BlockedPeersCore", platforms: [.macOS(.v10_13)], dependencies: [.package(path: ''' + dependency + ''')], targets: [.testTarget(name: "BlockedPeersCoreTests", dependencies: [.product(name: "SwiftSignalKit", package: "SSignalKit")], path: "Tests")])
''')
    (directory / 'Tests').mkdir()
    (directory / 'Tests/BlockedPeersCoreTests.swift').write_text(fixture)
    raise SystemExit(subprocess.run(['swift', 'test', '--package-path', str(directory), '--disable-sandbox', '--jobs', '4']).returncode)
