import argparse
import json
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser()
parser.add_argument('--source', type=Path, default=root / 'packages/AudioPlayerCore/Sources/AudioPlayerCore/AudioPlayerController.swift')
args = parser.parse_args()
source = args.source.read_text()
start = source.index('    private func fetch() {') if '    private func fetch() {' in source else source.index('    fileprivate func pullResource()')
body = source[start:source.index('\n\n\n}\n\npublic struct APTransition', start)]
resource = source[source.index('public struct APResource {'):source.index('public class APItem :')]
stop_start = source.index('    public func stop() {')
stop = source[stop_start:source.index('    @discardableResult public func set(trackProgress:', stop_start)]
fixture = Path(__file__).with_name('ResourceTests.swift').read_text().replace('__RESOURCE__', resource).replace('__PULL__', body.replace('fileprivate ', '')).replace('__STOP__', stop.replace('public ', ''))
with tempfile.TemporaryDirectory(prefix='audio-resource-ownership-') as directory:
    directory = Path(directory)
    dependency = json.dumps(str(root / 'submodules/telegram-ios/submodules/SSignalKit'))
    (directory / 'Package.swift').write_text('// swift-tools-version:5.9\nimport PackageDescription\nlet package = Package(name: "AudioResourceOwnership", platforms: [.macOS(.v10_13)], dependencies: [.package(path: '+dependency+')], targets: [.testTarget(name: "ResourceTests", dependencies: [.product(name: "SwiftSignalKit", package: "SSignalKit")], path: "Tests")])\n')
    (directory / 'Tests').mkdir()
    (directory / 'Tests/ResourceTests.swift').write_text(fixture)
    raise SystemExit(subprocess.run(['swift', 'test', '--package-path', str(directory), '--disable-sandbox', '--jobs', '4']).returncode)
