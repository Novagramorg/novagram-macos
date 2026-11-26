import argparse
import json
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser()
parser.add_argument('--source', type=Path, default=root / 'submodules/telegram-ios/submodules/TelegramCore/Sources/TelegramEngine/Messages/StoryListContext.swift')
args = parser.parse_args()
source = args.source.read_text()
def block(marker):
    start = source.index(marker)
    brace = source.index('-> Disposable {',start) + len('-> Disposable ') if marker.startswith('        func ') else source.index('{',start)
    depth = 1; end = brace + 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}'); end += 1
    return source[start:end]
helper = ''
if 'private func _internal_reorderStoryFolders(' in source:
    helper = block('private func _internal_reorderedStoryFolders(') + '\n' + block('private func _internal_reorderStoryFolders(')
reorder = block('        func reorderFolders(')
if not helper:
    reorder = reorder.replace('ids: [Int64])', 'ids: [Int64], completion: @escaping (Bool) -> Void = { _ in })',1)
fixture = Path(__file__).with_name('StoryFolderReorderTests.swift').read_text().replace('__HELPER__',helper).replace('__REORDER__',reorder)
with tempfile.TemporaryDirectory(prefix='story-folder-reorder-') as directory:
    directory=Path(directory)
    dependency=json.dumps(str(root/'submodules/telegram-ios/submodules/SSignalKit'))
    (directory/'Package.swift').write_text('''// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "StoryFolderReorder", platforms: [.macOS(.v10_13)], dependencies: [.package(path: '''+dependency+''')], targets: [.testTarget(name: "StoryFolderReorderTests", dependencies: [.product(name: "SwiftSignalKit", package: "SSignalKit")], path: "Tests")])
''')
    (directory/'Tests').mkdir(); (directory/'Tests/StoryFolderReorderTests.swift').write_text(fixture)
    raise SystemExit(subprocess.run(['swift','test','--package-path',str(directory),'--disable-sandbox','--jobs','4']).returncode)
