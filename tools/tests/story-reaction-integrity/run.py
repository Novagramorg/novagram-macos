import argparse
import json
from pathlib import Path
import subprocess
import tempfile
root = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser()
parser.add_argument('--source', type=Path, default=root / 'submodules/telegram-ios/submodules/TelegramCore/Sources/TelegramEngine/Messages/Stories.swift')
parser.add_argument('--replay-source', type=Path, default=root / 'submodules/telegram-ios/submodules/TelegramCore/Sources/State/AccountStateManagementUtils.swift')
parser.add_argument('--facade-source', type=Path, default=root / 'submodules/telegram-ios/submodules/TelegramCore/Sources/TelegramEngine/Messages/TelegramEngineMessages.swift')
parser.add_argument('--skip-overflow', action='store_true')
parser.add_argument('--filter')
parser.add_argument('--skip-recovery-lifecycle',action='store_true')
args = parser.parse_args()
source = args.source.read_text()
def block(marker):
    start = source.index(marker); brace = source.index('{', start); end = brace + 1; depth = 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}'); end += 1
    return source[start:end].replace('public ', '')
fixture = Path(__file__).with_name('StoryReactionIntegrityTests.swift').read_text()
replay = args.replay_source.read_text()
start = replay.index('            case let .UpdateStorySentReaction(peerId, id, reaction):')
replay = replay[start:replay.index('            case let .UpdateNewAuthorization(', start)]
fixture = fixture.replace('__REPLAY__', replay)
source_saved = source
source = args.replay_source.read_text()
fixture = fixture.replace('__RESOLVE__', block('func resolveStories<T>('))
fixture = fixture.replace('__RESOLUTION_COMMIT_OFFSET__', '1' if 'switch fetched.stories' in block('func resolveStories<T>(') else '2')
source = source_saved
fixture = fixture.replace('__REFRESH_COMMIT_TRANSACTION_OFFSET__', '2' if '_internal_getStoriesById(' in block('func _internal_refreshStories(') else '1')
full = args.replay_source.read_text()
start = full.index('            case let .UpdateStory(peerId, story):')
fixture = fixture.replace('__FULL_REPLAY__',full[start:full.index('            case let .UpdateReadStories(',start)])
if 'knownPreviousReaction:' not in block('func _internal_setStoryReaction('):
    fixture += '\nfunc _internal_setStoryReaction(account: Account, peerId: EnginePeer.Id, id: Int32, reaction: MessageReaction.Reaction?, knownPreviousReaction: MessageReaction.Reaction??) -> Signal<Never, NoError> { _internal_setStoryReaction(account: account, peerId: peerId, id: id, reaction: reaction) }\n'

for marker, function in [('__MEDIA_FETCH__', 'func _internal_getStoriesById(accountPeerId: PeerId, postbox: Postbox, network:'), ('__COUNT_REQUEST__', 'func _internal_getStoryViews('), ('__REFRESH__', 'func _internal_refreshStories('), ('__GET_STORIES__', 'func _internal_getStoriesById(accountPeerId: PeerId, postbox: Postbox, source:'), ('__IS_EMPTY__', 'public var isEmpty: Bool {'), ('__REDUCER__', 'func _internal_updateStoryViewsForMyReaction('), ('__SET__', 'func _internal_setStoryReaction('), ('__STARS__', 'func _internal_sendStoryStars(')]:
    fixture = fixture.replace(marker, block(function))
support_source=(root/'submodules/telegram-ios/submodules/TelegramCore/Sources/TelegramEngine/Messages/Stories.swift').read_text()
original_source=source
support=[]
for marker in ['final class PeerStoryPollContext {', 'final class PeerStoryPollLease {', 'func _internal_invalidatePeerStoryPoll(', 'private final class StoryResolutionContextRegistry {', 'final class StoryResolutionLease {', 'func _internal_invalidateStoryResolution(', 'struct StoriesByIdResult {', 'struct StoryResolutionResult {', 'func _internal_existingStoryItem(', 'func _internal_parseStoriesById(', 'final class StoryReactionReconciliationContext {', 'private func _internal_scheduleStoryReactionReconciliation(', 'func _internal_storyUpdatesViews(', 'final class StoryRefreshContext {', 'struct StoryRefreshSnapshot:', 'final class StoryReactionRequestDependencyTag:', 'final class StoryReactionContext {', 'func _internal_applyStoryReaction(', 'private func _internal_finishStoryReaction(', 'private func _internal_storyReactionValue(', 'func _internal_storyWithReaction(']:
    if marker == "private func _internal_scheduleStoryReactionReconciliation(" and marker not in original_source:
        continue
    source=original_source if marker in original_source else support_source
    support.append(block(marker))
if '_internal_applyStoryUpdate(' in fixture:
    source=original_source if 'func _internal_applyStoryUpdate(' in original_source else support_source
    support.append(block('func _internal_applyStoryUpdate('))
source=(root/'submodules/telegram-ios/submodules/TelegramCore/Sources/TelegramEngine/Messages/StoryListContext.swift').read_text()
poll = block('public func _internal_pollPeerStories(')
if 'stateManager: AccountStateManager?' not in poll:
    poll = poll.replace('peerReference: PeerReference? = nil)', 'peerReference: PeerReference? = nil, stateManager: AccountStateManager? = nil)')
fixture = fixture.replace('__PEER_POLL__', poll)
for marker in ['private func _internal_storyWithViews(', 'func _internal_applyStoryViews(', 'func _internal_updateStoryListCacheItem(', 'func _internal_storyListCacheSnapshot(', 'private func _internal_visitStoryListCaches(', 'func _internal_removeStoriesFromListCaches(', 'func _internal_removeStoryFromListCaches(', 'func _internal_transformStoryListCacheItems(', 'func _internal_cachedStoryReactionValue(', 'func _internal_cachedStoryItemValue(']:
    support.append(block(marker))
source=(root/'submodules/telegram-ios/submodules/TelegramCore/Sources/Network/Network.swift').read_text()
fixture=fixture.replace('__NETWORK_DEPENDENCY__',block('private func networkRequestDependency('))
source=(root/'submodules/telegram-ios/submodules/MTProtoRustEngine/Sources/MTProtoRustEngineMapping/RustEngineMapping.swift').read_text()
fixture=fixture.replace('__DEPENDENCY_INDEX__',block('public func rustEngineDependencyIndex<'))
source=args.facade_source.read_text()
fixture=fixture.replace('__COUNT_REFRESH__',block('        public func refreshStoryViews('))
fixture=fixture.replace('__SUPPORT__','\n'.join(support)).replace('__VIEWS_CONTEXT__',block('final class StoryViewRefreshContext {'))
with tempfile.TemporaryDirectory(prefix='story-reaction-integrity-') as directory:
    path = Path(directory)
    dependency = json.dumps(str(root / 'submodules/telegram-ios/submodules/SSignalKit'))
    (path / 'Package.swift').write_text('// swift-tools-version:5.9\nimport PackageDescription\nlet package = Package(name: "StoryReactionIntegrity", platforms: [.macOS(.v10_13)], dependencies: [.package(path: ' + dependency + ')], targets: [.testTarget(name: "StoryReactionIntegrityTests", dependencies: [.product(name: "SwiftSignalKit", package: "SSignalKit")], path: "Tests")])\n')
    (path / 'Tests').mkdir(); (path / 'Tests/StoryReactionIntegrityTests.swift').write_text(fixture)
    command = ['swift', 'test', '--package-path', str(path), '--disable-sandbox', '--jobs', '4']
    if args.skip_overflow: command += ['--skip', 'StoryReactionOverflowTests']
    if args.filter: command += ['--filter', args.filter]
    if args.skip_recovery_lifecycle: command += ['--skip', 'StoryReactionMutationTests.testRepeatedSuccessDoesNotRetainPendingReactionState']
    raise SystemExit(subprocess.run(command).returncode)
