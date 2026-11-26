import argparse
import json
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser()
parser.add_argument('--source', type=Path, default=root / 'packages/LocationUI/Sources/LocationUI/LocationRequest.swift')
parser.add_argument('--filter')
parser.add_argument('--legacy', action='store_true')
args = parser.parse_args()
source = args.source.read_text().replace('@objc ', '').replace('public ', '')
if args.legacy:
    for version in ['10.14', '10.15', '11.0']:
        source = source.replace(f'if #available(macOS {version}, *)', 'if false')
fixture = Path(__file__).with_name('LocationRequestTests.swift').read_text().replace('__SOURCE__', source).replace('__MODERN__', 'false' if args.legacy else 'true')
with tempfile.TemporaryDirectory(prefix='location-request-') as directory:
    directory = Path(directory)
    dependency = json.dumps(str(root / 'submodules/telegram-ios/submodules/SSignalKit'))
    (directory / 'Package.swift').write_text('''// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "LocationRequest", platforms: [.macOS(.v10_13)], dependencies: [.package(path: ''' + dependency + ''')], targets: [.testTarget(name: "LocationRequestTests", dependencies: [.product(name: "SwiftSignalKit", package: "SSignalKit")], path: "Tests")])
''')
    (directory / 'Tests').mkdir()
    (directory / 'Tests/LocationRequestTests.swift').write_text(fixture)
    command = ['swift', 'test', '--package-path', str(directory), '--disable-sandbox', '--jobs', '4']
    if args.filter:
        command += ['--filter', args.filter]
    raise SystemExit(subprocess.run(command).returncode)
