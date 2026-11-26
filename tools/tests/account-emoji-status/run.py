import argparse
import json
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser()
parser.add_argument('--source', type=Path, default=root / 'submodules/telegram-ios/submodules/TelegramCore/Sources/TelegramEngine/AccountData/TelegramEngineAccountData.swift')
parser.add_argument('--filter')
args = parser.parse_args()
def block(source, marker):
    start = source.index(marker); end = source.index('{', start) + 1; depth = 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}'); end += 1
    return source[start:end].replace('public ', '')
source = args.source.read_text()
fixture = Path(__file__).with_name('AccountEmojiStatusTests.swift').read_text()
support = '\n'.join(block(source, marker) for marker in ['private final class AccountEmojiStatusRequestDependencyTag:', 'private func _internal_setAccountEmojiStatus('] if marker in source)
methods = '\n'.join(block(source, '        public func '+name+'(') for name in ['setEmojiStatusWithResult', 'setEmojiStatus', 'setStarGiftStatus'])
if '        public func setStarGiftStatusWithResult(' in source:
    methods += '\n' + block(source, '        public func setStarGiftStatusWithResult(')
else:
    methods += '\n' + block(source, '        public func setStarGiftStatus(').replace('func setStarGiftStatus(', 'func setStarGiftStatusWithResult(')
fixture = fixture.replace('__CORE_SUPPORT__', support).replace('__CORE__', methods)
with tempfile.TemporaryDirectory(prefix='account-emoji-status-') as directory:
    directory = Path(directory)
    dependency = json.dumps(str(root / 'submodules/telegram-ios/submodules/SSignalKit'))
    (directory / 'Package.swift').write_text('''// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "AccountEmojiStatus", platforms: [.macOS(.v10_13)], dependencies: [.package(path: ''' + dependency + ''')], targets: [.testTarget(name: "AccountEmojiStatusTests", dependencies: [.product(name: "SwiftSignalKit", package: "SSignalKit")], path: "Tests")])
''')
    (directory / 'Tests').mkdir()
    (directory / 'Tests/AccountEmojiStatusTests.swift').write_text(fixture)
    command = ['swift', 'test', '--package-path', str(directory), '--disable-sandbox', '--jobs', '4']
    if args.filter: command += ['--filter', args.filter]
    raise SystemExit(subprocess.run(command).returncode)
