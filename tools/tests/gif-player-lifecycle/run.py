import argparse
import json
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser()
parser.add_argument('--source', type=Path, default=root / 'packages/TelegramMedia/Sources/GIFPlayerView.swift')
parser.add_argument('--skip')
parser.add_argument('--filter')
args = parser.parse_args()
source = args.source.read_text().replace('import TGUIKit\n', '').replace('import ObjcUtils\n', '')
source = source.replace('fileprivate ', '').replace('private ', '').replace('public ', '').replace('open ', '')
source = source.replace('TAVSampleBufferDisplayLayer : AVSampleBufferDisplayLayer', 'TAVSampleBufferDisplayLayer : ControlledSampleBufferDisplayLayer')
source = source.replace('AVAssetReader(asset:', 'ControlledAssetReader(asset:')
fixture = Path(__file__).with_name('RendererTests.swift').read_text().replace('__SOURCE__', source)
with tempfile.TemporaryDirectory(prefix='gif-player-lifecycle-') as directory:
    directory = Path(directory)
    dependency = json.dumps(str(root / 'submodules/telegram-ios/submodules/SSignalKit'))
    (directory / 'Package.swift').write_text('''// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "GifPlayerLifecycle", platforms: [.macOS(.v10_13)], dependencies: [.package(path: ''' + dependency + ''')], targets: [.testTarget(name: "RendererTests", dependencies: [.product(name: "SwiftSignalKit", package: "SSignalKit")], path: "Tests")])
''')
    (directory / 'Tests').mkdir()
    (directory / 'Tests/RendererTests.swift').write_text(fixture)
    command = ['swift', 'test', '--package-path', str(directory), '--disable-sandbox', '--jobs', '4']
    if args.skip:
        command += ['--skip', args.skip]
    if args.filter:
        command += ['--filter', args.filter]
    raise SystemExit(subprocess.run(command).returncode)
