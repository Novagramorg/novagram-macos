import argparse
import json
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser()
parser.add_argument('--source', type=Path, default=root / 'submodules/telegram-ios/submodules/TelegramCore/Sources/TelegramEngine/Peers/UpdatePeerInfo.swift')
parser.add_argument('--filter')
args = parser.parse_args()
source = args.source.read_text()
source = source[source.index('public enum UpdatePeerEmojiStatusError'):].replace('public ', '')
fixture = Path(__file__).with_name('ChannelEmojiStatusTests.swift').read_text().replace('__SOURCE__', source)
with tempfile.TemporaryDirectory(prefix='channel-emoji-status-') as directory:
    directory = Path(directory)
    dependency = json.dumps(str(root / 'submodules/telegram-ios/submodules/SSignalKit'))
    (directory / 'Package.swift').write_text('''// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "ChannelEmojiStatus", platforms: [.macOS(.v10_13)], dependencies: [.package(path: ''' + dependency + ''')], targets: [.testTarget(name: "ChannelEmojiStatusTests", dependencies: [.product(name: "SwiftSignalKit", package: "SSignalKit")], path: "Tests")])
''')
    (directory / 'Tests').mkdir()
    (directory / 'Tests/ChannelEmojiStatusTests.swift').write_text(fixture)
    command = ['swift', 'test', '--package-path', str(directory), '--disable-sandbox', '--jobs', '4']
    if args.filter: command += ['--filter', args.filter]
    raise SystemExit(subprocess.run(command).returncode)
