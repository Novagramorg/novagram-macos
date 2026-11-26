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
update = ''
if 'private enum StoryFolderMutationResult' in source:
    helper = block('private enum StoryFolderMutationResult') + '\n' + block('private func _internal_updateStoryFolder(')
    update = block('        private func updateFolder(')
delete = block('        func removeFolder(')
rename = block('        func renameFolder(')
if not helper:
    delete = delete.replace('id: Int64)', 'id: Int64, completion: @escaping (Bool) -> Void = { _ in })',1)
    rename = rename.replace('title: String)', 'title: String, completion: @escaping (Bool) -> Void = { _ in })',1)
fixture = Path(__file__).with_name('StoryFolderMutationTests.swift').read_text()
for key,value in [('__HELPER__',helper),('__UPDATE__',update),('__DELETE__',delete),('__RENAME__',rename)]: fixture=fixture.replace(key,value)
with tempfile.TemporaryDirectory(prefix='story-folder-mutations-') as directory:
    directory=Path(directory)
    dependency=json.dumps(str(root/'submodules/telegram-ios/submodules/SSignalKit'))
    (directory/'Package.swift').write_text('''// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "StoryFolderMutation", platforms: [.macOS(.v10_13)], dependencies: [.package(path: '''+dependency+''')], targets: [.testTarget(name: "StoryFolderMutationTests", dependencies: [.product(name: "SwiftSignalKit", package: "SSignalKit")], path: "Tests")])
''')
    (directory/'Tests').mkdir(); (directory/'Tests/StoryFolderMutationTests.swift').write_text(fixture)
    raise SystemExit(subprocess.run(['swift','test','--package-path',str(directory),'--disable-sandbox','--jobs','4']).returncode)
