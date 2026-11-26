import argparse
import json
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser()
parser.add_argument('--core', type=Path, default=root / 'submodules/telegram-ios/submodules/TelegramCore/Sources/TelegramEngine/Peers/UpdateBotInfo.swift')
parser.add_argument('--profile', type=Path, default=root / 'packages/PeerInfoUI/Sources/PeerInfoUI/UserInfoEntries.swift')
parser.add_argument('--controller', type=Path, default=root / 'packages/PeerInfoUI/Sources/PeerInfoUI/PeerInfoController.swift')
args = parser.parse_args()
core = args.core.read_text(); profile = args.profile.read_text()
def block(source, marker):
    start = source.index(marker); end = source.index('{', start) + 1; depth = 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}'); end += 1
    return source[start:end].replace('public ', '')
fixture = Path(__file__).with_name('BotEmojiPermissionTests.swift').read_text()
fixture = fixture.replace('__CORE__', block(core, 'public enum ToggleBotEmojiStatusAccessError') + '\n' + block(core, 'func _internal_toggleBotEmojiStatusAccess('))
fixture = fixture.replace('__PROFILE__', block(profile, '    func togglePermissionsStatus()') + '\n' + (block(profile, '    func setEmojiPermissionRequestsActive(') if '    func setEmojiPermissionRequestsActive(' in profile else 'func setEmojiPermissionRequestsActive(_ active: Bool) {}'))
controller = args.controller.read_text()
fixture = fixture.replace('__LIFECYCLE__', '\n'.join(block(controller, marker) for marker in ['    public override func viewWillDisappear(', '    public override func viewWillAppear(']))
a = profile.index('        case let .botPermissionsStatus(_, value, viewType):'); b = profile.index('        case let .botPermissionsGeo', a)
fixture = fixture.replace('__ROW__', profile[profile.index('            return GeneralInteractedRowItem',a):b])
fixture = fixture.replace('__DISPOSE__', 'botEmojiStatusDisposable.dispose()' if 'botEmojiStatusDisposable.dispose()' in profile else '')
with tempfile.TemporaryDirectory(prefix='bot-emoji-permission-') as directory:
    directory = Path(directory)
    dependency = json.dumps(str(root / 'submodules/telegram-ios/submodules/SSignalKit'))
    (directory / 'Package.swift').write_text('''// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "BotEmojiPermission", platforms: [.macOS(.v10_13)], dependencies: [.package(path: ''' + dependency + ''')], targets: [.testTarget(name: "BotEmojiPermissionTests", dependencies: [.product(name: "SwiftSignalKit", package: "SSignalKit")], path: "Tests")])
''')
    (directory / 'Tests').mkdir()
    (directory / 'Tests/BotEmojiPermissionTests.swift').write_text(fixture)
    raise SystemExit(subprocess.run(['swift', 'test', '--package-path', str(directory), '--disable-sandbox', '--jobs', '4']).returncode)
