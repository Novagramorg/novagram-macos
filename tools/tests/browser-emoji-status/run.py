import argparse
import json
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
base = root / 'packages/WebAppUI/Sources/WebAppUI'
parser = argparse.ArgumentParser()
parser.add_argument('--action', type=Path, default=base / 'BrowserEmojiStatusAction.swift')
parser.add_argument('--controller', type=Path, default=base / 'WebpageModalController.swift')
parser.add_argument('--core', type=Path, default=root / 'submodules/telegram-ios/submodules/TelegramCore/Sources/TelegramEngine/AccountData/TelegramEngineAccountData.swift')
parser.add_argument('--modal', type=Path, default=base / 'WebbotEmojisetModal.swift')
parser.add_argument('--filter')
args = parser.parse_args()
def block(source, marker):
    start = source.index(marker); end = source.index('{', start) + 1; depth = 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}'); end += 1
    return source[start:end].replace('public ', '').replace('fileprivate ', '')
fixture = Path(__file__).with_name('BrowserEmojiStatusTests.swift').read_text()
fixture = fixture.replace('__ACTION__', '\n'.join(line for line in args.action.read_text().splitlines() if not line.startswith('import ')))
core = args.core.read_text()
marker = '        public func setEmojiStatusWithResult(' if 'func setEmojiStatusWithResult(' in core else '        public func setEmojiStatus('
fixture = fixture.replace('__CORE__', block(core, marker).replace('func setEmojiStatus(', 'func setEmojiStatusWithResult('))
support = '\n'.join(block(core, marker) for marker in ['private final class AccountEmojiStatusRequestDependencyTag:', 'private func _internal_setAccountEmojiStatus('] if marker in core)
fixture = fixture.replace('__CORE_SUPPORT__', support)
modal = args.modal.read_text()
fixture = fixture.replace('__MODAL__', block(modal, ' public enum EmojiSetResultStatus') + '\n' + block(modal, 'public func WebbotEmojisetModal('))
controller = args.controller.read_text()
methods = '\n'.join(block(controller, marker) for marker in ['    public func cancelPendingPageActions()', '    public override func viewWillDisappear(', '    public override func viewWillAppear('])
if '    fileprivate func setEmojiStatus(' in controller:
    methods += '\n' + block(controller, '    fileprivate func setEmojiStatus(')
else:
    a = controller.index('        case "web_app_set_emoji_status":'); b = controller.index('        case "web_app_request_emoji_status_access":', a)
    methods += '\nfunc setEmojiStatus(_ json: [String: Any]?) { guard let window else { return }; let context = self.context\n' + controller[a:b].split('\n', 1)[1] + '\n}'
fixture = fixture.replace('__METHODS__', methods)
with tempfile.TemporaryDirectory(prefix='browser-emoji-status-') as directory:
    directory = Path(directory)
    dependency = json.dumps(str(root / 'submodules/telegram-ios/submodules/SSignalKit'))
    (directory / 'Package.swift').write_text('''// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "BrowserEmojiStatus", platforms: [.macOS(.v10_13)], dependencies: [.package(path: ''' + dependency + ''')], targets: [.testTarget(name: "BrowserEmojiStatusTests", dependencies: [.product(name: "SwiftSignalKit", package: "SSignalKit")], path: "Tests")])
''')
    (directory / 'Tests').mkdir()
    (directory / 'Tests/BrowserEmojiStatusTests.swift').write_text(fixture)
    command = ['swift', 'test', '--package-path', str(directory), '--disable-sandbox', '--jobs', '4']
    if args.filter: command += ['--filter', args.filter]
    raise SystemExit(subprocess.run(command).returncode)
