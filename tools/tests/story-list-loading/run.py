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
    start = source.index(marker, 0 if marker.startswith('private func _internal_') else source.index('public final class PeerStoryListContext:')); brace = source.index('{', start); depth = 1; end = brace + 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}'); end += 1
    return source[start:end]
properties = source[source.index('        private var isLoadingMore:'):source.index('        private var updatesDisposable:')]
loading = block('        func loadMore(')
if '                if self.updatesDisposable == nil && self.folderId == nil {' in loading:
    begin = loading.index('                if self.updatesDisposable == nil && self.folderId == nil {')
    end = loading.rindex('            })')
    loading = loading[:begin] + '                self.subscribeToStoryUpdates()\n' + loading[end:]
finish = block('        private func finishLoading(') if '        private func finishLoading(' in source else ''
dispose = 'self.requestDisposable.dispose()' if 'private let requestDisposable = MetaDisposable()' in properties else 'self.requestDisposable?.dispose()'
fixture = Path(__file__).with_name('StoryListLoadingTests.swift').read_text()
for key, value in [('__PROPERTIES__',properties),('__LOAD__',loading),('__FINISH__',finish),('__DISPOSE__',dispose)]: fixture = fixture.replace(key,value)
fixture = fixture.replace('__INITIALIZATION_READY__', 'self.isInitialized = true; self.initializationPromise.set(true)' if 'private var isInitialized' in source else '')
entity_helpers = '\n'.join(block(marker) for marker in ['private func _internal_storyEntityFileIds(', 'private func _internal_storyEntityFiles(', 'private func _internal_prunedStoryEntityFiles('] if marker in source)
fixture = fixture.replace('import SwiftSignalKit', 'import SwiftSignalKit\n' + entity_helpers, 1)
with tempfile.TemporaryDirectory(prefix='story-list-loading-') as directory:
    directory=Path(directory)
    dependency=json.dumps(str(root/'submodules/telegram-ios/submodules/SSignalKit'))
    (directory/'Package.swift').write_text('''// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "StoryListLoading", platforms: [.macOS(.v10_13)], dependencies: [.package(path: '''+dependency+''')], targets: [.testTarget(name: "StoryListLoadingTests", dependencies: [.product(name: "SwiftSignalKit", package: "SSignalKit")], path: "Tests")])
''')
    (directory/'Tests').mkdir(); (directory/'Tests/StoryListLoadingTests.swift').write_text(fixture)
    raise SystemExit(subprocess.run(['swift','test','--package-path',str(directory),'--disable-sandbox','--jobs','4']).returncode)
