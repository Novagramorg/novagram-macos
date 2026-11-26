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
properties = source[source.index('        private var isLoadingMore:'):source.index('        private var completionCallbacksByToken:')]
helpers = '\n'.join(block(marker) for marker in ['private func _internal_storyFolderIds(', 'private func _internal_storyWithFolderIds(', 'private func _internal_engineStoryWithFolderIds(', 'private func _internal_engineStoryWithViews(', 'private func _internal_engineStoryWithReaction(', 'private func _internal_mappedStoryViews('] if marker in source)
fixture = Path(__file__).with_name('StoryListStartupTests.swift').read_text()
for key,value in [('__PROPERTIES__',properties),('__LOAD__',block('        func loadMore(')),('__FINISH__',block('        private func finishLoading(')),('__SUBSCRIBE__',block('        private func subscribeToStoryUpdates(')),('__RELOAD__',block('        private func reloadAlbumStories(') if '        private func reloadAlbumStories(' in source else ''),('__DEINIT__',block('        deinit {'))]: fixture=fixture.replace(key,value)
fixture = fixture.replace('__MEMBERSHIP_HELPERS__', helpers)
fixture = fixture.replace('__INITIALIZER__', block('        init(queue: Queue, account: Account, peerId: EnginePeer.Id, isArchived: Bool, folderId: Int64?)'))
fixture = fixture.replace('__UPDATE_LIFECYCLE__', '\n'.join(block(marker) for marker in ['        private func beginStoryUpdate(', '        private func finishStoryUpdate('] if marker in source))
entity_helpers = '\n'.join(block(marker) for marker in ['private func _internal_storyEntityFileIds(', 'private func _internal_storyEntityFiles(', 'private func _internal_prunedStoryEntityFiles('] if marker in source)
fixture = fixture.replace('import SwiftSignalKit', 'import SwiftSignalKit\n' + entity_helpers, 1)

reaction_source=(root/'submodules/telegram-ios/submodules/TelegramCore/Sources/TelegramEngine/Messages/Stories.swift').read_text()
def reaction_block(marker):
    start=reaction_source.index(marker); end=reaction_source.index('{',start)+1; depth=1
    while depth:
        depth+=(reaction_source[end]=='{')-(reaction_source[end]=='}');end+=1
    return reaction_source[start:end].replace('public ', '')
fixture=fixture.replace('__REACTION_REDUCER__',reaction_block('func _internal_updateStoryViewsForMyReaction(')).replace('__VIEWS_EMPTY__',reaction_block('public var isEmpty: Bool {'))

with tempfile.TemporaryDirectory(prefix='story-list-startup-') as directory:
    directory=Path(directory)
    dependency=json.dumps(str(root/'submodules/telegram-ios/submodules/SSignalKit'))
    (directory/'Package.swift').write_text('''// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "StoryListStartup", platforms: [.macOS(.v10_13)], dependencies: [.package(path: '''+dependency+''')], targets: [.testTarget(name: "StoryListStartupTests", dependencies: [.product(name: "SwiftSignalKit", package: "SSignalKit")], path: "Tests")])
''')
    (directory/'Tests').mkdir(); (directory/'Tests/StoryListStartupTests.swift').write_text(fixture)
    raise SystemExit(subprocess.run(['swift','test','--package-path',str(directory),'--disable-sandbox','--jobs','4']).returncode)
