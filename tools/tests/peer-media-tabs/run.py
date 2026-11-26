import argparse
import json
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser()
parser.add_argument('--source', type=Path, default=root / 'packages/PeerInfoUI/Sources/PeerInfoUI/PeerMediaController.swift')
args = parser.parse_args()
source = args.source.read_text()
start = source.index('    private func toggle(with mode:')
end = source.index('    deinit {', start)
fixture = Path(__file__).with_name('PeerMediaTabTests.swift').read_text().replace('__TOGGLE__', source[start:end])
with tempfile.TemporaryDirectory(prefix='peer-media-tabs-') as directory:
    directory = Path(directory)
    dependency = json.dumps(str(root / 'submodules/telegram-ios/submodules/SSignalKit'))
    (directory / 'Package.swift').write_text('''// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "PeerMediaTabs", platforms: [.macOS(.v10_13)], dependencies: [.package(path: ''' + dependency + ''')], targets: [.testTarget(name: "PeerMediaTabTests", dependencies: [.product(name: "SwiftSignalKit", package: "SSignalKit")], path: "Tests")])
''')
    (directory / 'Tests').mkdir()
    (directory / 'Tests/PeerMediaTabTests.swift').write_text(fixture)
    raise SystemExit(subprocess.run(['swift', 'test', '--package-path', str(directory), '--disable-sandbox', '--jobs', '4']).returncode)
