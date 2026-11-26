import argparse
import json
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser()
parser.add_argument('--source', type=Path, default=root / 'packages/ChatUI/Sources/ChatUI/InstantVideoPIP.swift')
args = parser.parse_args()
source = args.source.read_text()
controller = source[source.index('public class InstantVideoPIP:'):]
controller = controller.replace('public ', '').replace('private ', '')
alignment = source[source.index('enum InstantVideoPIPCornerAlignment'):source.index('public class InstantVideoPIPView')]
fixture = Path(__file__).with_name('PipTests.swift').read_text().replace('__CONTROLLER__', controller).replace('__ALIGNMENT__', alignment)
with tempfile.TemporaryDirectory(prefix='instant-video-pip-') as directory:
    directory = Path(directory)
    dependency = json.dumps(str(root / 'submodules/telegram-ios/submodules/SSignalKit'))
    (directory / 'Package.swift').write_text('''// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "InstantVideoPip", platforms: [.macOS(.v10_13)], dependencies: [.package(path: ''' + dependency + ''')], targets: [.testTarget(name: "PipTests", dependencies: [.product(name: "SwiftSignalKit", package: "SSignalKit")], path: "Tests")])
''')
    (directory / 'Tests').mkdir()
    (directory / 'Tests/PipTests.swift').write_text(fixture)
    raise SystemExit(subprocess.run(['swift', 'test', '--package-path', str(directory), '--disable-sandbox', '--jobs', '4']).returncode)
