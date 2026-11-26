import argparse
import json
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser()
parser.add_argument('--source', type=Path, default=root / 'packages/WebAppUI/Sources/WebAppUI/WebAppPermissionsState.swift')
parser.add_argument('--profile', type=Path, default=root / 'packages/PeerInfoUI/Sources/PeerInfoUI/UserInfoEntries.swift')
args = parser.parse_args()
source = args.source.read_text()
source = source[source.index('public struct WebAppPermissionsState:'):].replace('public ', '')
profile = args.profile.read_text()
a = profile.index('    func togglePermissionsGeo()'); b = profile.index('    func toggleCopyProtection(', a)
fixture = Path(__file__).with_name('WebAppPermissionsTests.swift').read_text().replace('__SOURCE__', source).replace('__PROFILE__', profile[a:b])
with tempfile.TemporaryDirectory(prefix='web-app-permissions-') as directory:
    directory = Path(directory)
    dependency = json.dumps(str(root / 'submodules/telegram-ios/submodules/SSignalKit'))
    (directory / 'Package.swift').write_text('''// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "WebAppPermissions", platforms: [.macOS(.v10_13)], dependencies: [.package(path: ''' + dependency + ''')], targets: [.testTarget(name: "WebAppPermissionsTests", dependencies: [.product(name: "SwiftSignalKit", package: "SSignalKit")], path: "Tests")])
''')
    (directory / 'Tests').mkdir()
    (directory / 'Tests/WebAppPermissionsTests.swift').write_text(fixture)
    raise SystemExit(subprocess.run(['swift', 'test', '--package-path', str(directory), '--disable-sandbox', '--jobs', '4']).returncode)
