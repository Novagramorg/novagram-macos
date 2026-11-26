import argparse
import json
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser()
parser.add_argument('--source', type=Path, default=root / 'packages/StoriesUI/Sources/StoriesUI/SelectStoryModalController.swift')
args = parser.parse_args()
source = args.source.read_text()
source = source[source.index('private final class Arguments'):]
a = source.index('private func _id_row(')
b = source.index('public func SelectStoryModalController(', a)
source = source[:a] + '''private func entries(_ state: State, arguments: Arguments) -> InputDataSignalValue {
    InputDataSignalValue(state: state, arguments: arguments)
}
''' + source[b:]
source = source.replace('public func SelectStoryModalController', 'private func SelectStoryModalController')
source = source.replace('InputDataSignalValue(entries: entries(state, arguments: arguments))', 'entries(state, arguments: arguments)')
if 'albumContext: PeerStoryListContext?' not in source:
    source = source.replace('    let toggleSelected:', '    let retry: () -> Void = {}\n    let toggleSelected:', 1)
    source = source.replace('listContext: PeerStoryListContext?, callback:', 'listContext: PeerStoryListContext?, albumContext: PeerStoryListContext? = nil, callback:')
fixture = Path(__file__).with_name('StoryAlbumPickerTests.swift').read_text().replace('__PRODUCTION__',source)
with tempfile.TemporaryDirectory(prefix='story-album-picker-') as directory:
    directory = Path(directory)
    dependency = json.dumps(str(root / 'submodules/telegram-ios/submodules/SSignalKit'))
    (directory / 'Package.swift').write_text('''// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "StoryAlbumPicker", platforms: [.macOS(.v10_13)], dependencies: [.package(path: ''' + dependency + ''')], targets: [.testTarget(name: "StoryAlbumPickerTests", dependencies: [.product(name: "SwiftSignalKit", package: "SSignalKit")], path: "Tests")])
''')
    (directory / 'Tests').mkdir()
    (directory / 'Tests/StoryAlbumPickerTests.swift').write_text(fixture)
    raise SystemExit(subprocess.run(['swift', 'test', '--package-path', str(directory), '--disable-sandbox', '--jobs', '4']).returncode)
