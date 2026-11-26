import argparse
import json
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser()
parser.add_argument('--row', type=Path, default=root / 'packages/EntertainmentUI/Sources/EntertainmentUI/EmojiesSectionRowItem.swift')
args = parser.parse_args()
def block(source, marker):
    start = source.index(marker)
    end = source.index('{', start) + 1
    depth = 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[start:end]
helper = (root / 'packages/EntertainmentUI/Sources/EntertainmentUI/EmojiStatusMenuAction.swift').read_text()
helper = '\n'.join(line for line in helper.splitlines() if not line.startswith('import '))
fixture = Path(__file__).with_name('EmojiStatusMenuTests.swift').read_text()
fixture = fixture.replace('__HELPER__', helper).replace('__MENU__', block(args.row.read_text(), '        if context.isPremium {'))
with tempfile.TemporaryDirectory(prefix='emoji-status-menu-') as directory:
    directory = Path(directory)
    dependency = json.dumps(str(root / 'submodules/telegram-ios/submodules/SSignalKit'))
    (directory / 'Package.swift').write_text('''// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "EmojiStatusMenu", platforms: [.macOS(.v10_13)], dependencies: [.package(path: ''' + dependency + ''')], targets: [.testTarget(name: "EmojiStatusMenuTests", dependencies: [.product(name: "SwiftSignalKit", package: "SSignalKit")], path: "Tests")])
''')
    (directory / 'Tests').mkdir()
    (directory / 'Tests/EmojiStatusMenuTests.swift').write_text(fixture)
    raise SystemExit(subprocess.run(['swift', 'test', '--package-path', str(directory), '--disable-sandbox', '--jobs', '4']).returncode)
