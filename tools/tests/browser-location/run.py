import argparse
import json
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
base = root / 'packages/WebAppUI/Sources/WebAppUI'
parser = argparse.ArgumentParser()
parser.add_argument('--controller', type=Path, default=base / 'WebpageModalController.swift')
parser.add_argument('--filter')
parser.add_argument('--action', type=Path, default=base / 'BrowserLocationAction.swift')
args = parser.parse_args()
source = args.action.read_text()
source = '\n'.join(line for line in source.splitlines() if not line.startswith('import '))
controller = args.controller.read_text()
def block(source, marker):
    start = source.index(marker); end = source.index('{', start) + 1; depth = 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}'); end += 1
    return source[start:end].replace('public ', '').replace('fileprivate ', '')
permissions = (base / 'WebAppPermissionsState.swift').read_text()
fixture = Path(__file__).with_name('BrowserLocationTests.swift').read_text()
fixture = fixture.replace('__SOURCE__', source)
fixture = fixture.replace('__PERMISSIONS__', block(permissions, 'public struct WebAppPermissionsState:'))
fixture = fixture.replace('__METHODS__', '\n'.join(block(controller, marker) for marker in ['    fileprivate func openLocationSettings()', '    fileprivate func checkLocation()', '    fileprivate func requestLocation()', '    public func cancelPendingPageActions()', '    public override func viewWillDisappear(', '    public override func viewWillAppear('] if marker in controller))
with tempfile.TemporaryDirectory(prefix='browser-location-') as directory:
    directory = Path(directory)
    dependency = json.dumps(str(root / 'submodules/telegram-ios/submodules/SSignalKit'))
    (directory / 'Package.swift').write_text('''// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "BrowserLocation", platforms: [.macOS(.v10_13)], dependencies: [.package(path: ''' + dependency + ''')], targets: [.testTarget(name: "BrowserLocationTests", dependencies: [.product(name: "SwiftSignalKit", package: "SSignalKit")], path: "Tests")])
''')
    (directory / 'Tests').mkdir()
    (directory / 'Tests/BrowserLocationTests.swift').write_text(fixture)
    command = ['swift', 'test', '--package-path', str(directory), '--disable-sandbox', '--jobs', '4']
    if args.filter:
        command += ['--filter', args.filter]
    raise SystemExit(subprocess.run(command).returncode)
