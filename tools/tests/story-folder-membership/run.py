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
    start = source.index(marker, 0 if marker.startswith('private func _internal_') else source.index('public final class PeerStoryListContext:')); brace = source.index('-> Disposable {',start) + len('-> Disposable ') if marker.startswith('        func ') and ('Folder' in marker) else source.index('{',start); depth = 1; end = brace + 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}'); end += 1
    return source[start:end]
properties = source[source.index('        private var isLoadingMore:'):source.index('        private var completionCallbacksByToken:')]
helper = block('private func _internal_updateStoryFolderItems(') if 'private func _internal_updateStoryFolderItems(' in source else ''
add = block('        func addToFolder(')
remove = block('        func removeFromFolder(')
if helper:
    mutate = block('        func updateFolderStories(')
else:
    add = add.replace('items: [EngineStoryItem])','items: [EngineStoryItem], completion: @escaping (Bool) -> Void = { _ in })',1)
    remove = remove.replace('itemIds: [Int32])','itemIds: [Int32], completion: @escaping (Bool) -> Void = { _ in })',1)
    mutate = """func updateFolderStories(id: Int64, added: [EngineStoryItem], removed: [Int32], completion: @escaping (Bool) -> Void = { _ in }) -> Disposable {
        let disposable = DisposableSet()
        if !added.isEmpty { disposable.add(addToFolder(id: id,items: added)) }
        if !removed.isEmpty { disposable.add(removeFromFolder(id: id,itemIds: removed)) }
        return disposable
    }"""
helpers = '\n'.join(block(marker) for marker in ['private func _internal_storyFolderIds(', 'private func _internal_storyWithFolderIds(', 'private func _internal_engineStoryWithFolderIds(', 'private func _internal_engineStoryWithViews(', 'private func _internal_engineStoryWithReaction(', 'private func _internal_mappedStoryViews('] if marker in source)
fixture = Path(__file__).with_name('StoryFolderMembershipTests.swift').read_text()
for key,value in [('__HELPER__',helper),('__ADD__',add),('__REMOVE__',remove),('__MUTATE__',mutate),('__PROPERTIES__',properties),('__LOAD__',block('        func loadMore(')),('__FINISH__',block('        private func finishLoading(')),('__SUBSCRIBE__',block('        private func subscribeToStoryUpdates(')),('__RELOAD__',block('        private func reloadAlbumStories(')),('__DEINIT__',block('        deinit {'))]: fixture=fixture.replace(key,value)
fixture = fixture.replace('__MEMBERSHIP_HELPERS__', helpers)
fixture = fixture.replace('__INITIALIZATION_READY__', 'self.isInitialized = true; self.initializationPromise.set(true)' if 'private var isInitialized' in source else '')
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

with tempfile.TemporaryDirectory(prefix='story-folder-membership-') as directory:
    directory=Path(directory)
    dependency=json.dumps(str(root/'submodules/telegram-ios/submodules/SSignalKit'))
    (directory/'Package.swift').write_text('''// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "StoryFolderMembership", platforms: [.macOS(.v10_13)], dependencies: [.package(path: '''+dependency+''')], targets: [.testTarget(name: "StoryFolderMembershipTests", dependencies: [.product(name: "SwiftSignalKit", package: "SSignalKit")], path: "Tests")])
''')
    (directory/'Tests').mkdir(); (directory/'Tests/StoryFolderMembershipTests.swift').write_text(fixture)
    raise SystemExit(subprocess.run(['swift','test','--package-path',str(directory),'--disable-sandbox','--jobs','4']).returncode)
