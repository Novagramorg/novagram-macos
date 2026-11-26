import argparse
import json
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
base = root / 'packages/WebAppUI/Sources/WebAppUI'
parser = argparse.ArgumentParser()
parser.add_argument('--controller', type=Path, default=base / 'WebpageModalController.swift')
parser.add_argument('--action', type=Path, default=base / 'BrowserEmojiPermissionAction.swift')
parser.add_argument('--alerts', type=Path, default=root / 'packages/AlertsUI/Sources/AlertsUI/ModalAlertController.swift')
parser.add_argument('--filter')
args = parser.parse_args()
def block(source, marker):
    start = source.index(marker); end = source.index('{', start) + 1; depth = 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}'); end += 1
    return source[start:end].replace('public ', '').replace('fileprivate ', '')
controller = args.controller.read_text()
fixture = Path(__file__).with_name('BrowserEmojiPermissionTests.swift').read_text()
fixture = fixture.replace('__SOURCE__', '\n'.join(line for line in args.action.read_text().splitlines() if not line.startswith('import ')))
fixture = fixture.replace('__PERMISSIONS__', block((base / 'WebAppPermissionsState.swift').read_text(), 'public struct WebAppPermissionsState:'))
alerts = args.alerts.read_text()
a = alerts.index('public func showDismissableModalAlert(')
fixture = fixture.replace('__ALERT__', alerts[a:].strip().replace('public ', '', 1))
markers = ['    public func cancelPendingPageActions()', '    public override func viewWillDisappear(', '    public override func viewWillAppear(']
methods = '\n'.join(block(controller, marker) for marker in markers)
if '    fileprivate func requestEmojiStatusAccess()' in controller:
    methods += '\n' + block(controller, '    fileprivate func requestEmojiStatusAccess()')
else:
    a = controller.index('        case "web_app_request_emoji_status_access":')
    b = controller.index('        case "web_app_request_file_download":', a)
    methods += '\nfunc requestEmojiStatusAccess() { guard let window else { return }; let context = self.context\n' + controller[a:b].split('\n', 1)[1] + '\n}'
fixture = fixture.replace('__METHODS__', methods)
with tempfile.TemporaryDirectory(prefix='browser-emoji-permission-') as directory:
    directory = Path(directory)
    dependency = json.dumps(str(root / 'submodules/telegram-ios/submodules/SSignalKit'))
    (directory / 'Package.swift').write_text('''// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "BrowserEmojiPermission", platforms: [.macOS(.v10_13)], dependencies: [.package(path: ''' + dependency + ''')], targets: [.testTarget(name: "BrowserEmojiPermissionTests", dependencies: [.product(name: "SwiftSignalKit", package: "SSignalKit")], path: "Tests")])
''')
    (directory / 'Tests').mkdir()
    (directory / 'Tests/BrowserEmojiPermissionTests.swift').write_text(fixture)
    command = ['swift', 'test', '--package-path', str(directory), '--disable-sandbox', '--jobs', '4']
    if args.filter:
        command += ['--filter', args.filter]
    raise SystemExit(subprocess.run(command).returncode)
