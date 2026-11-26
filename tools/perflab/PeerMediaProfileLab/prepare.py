import hashlib
import json
from pathlib import Path

lab = Path(__file__).resolve().parent
root = lab.parents[2]
media = root / 'packages/PeerMediaUI/Sources/PeerMediaUI'
profile = root / 'packages/PeerInfoUI/Sources/PeerInfoUI'
hashes = {}


def read(path):
    value = path.read_text()
    hashes[str(path.relative_to(root))] = hashlib.sha256(value.encode()).hexdigest()
    return value


def between(text, start, end):
    a = text.index(start)
    return text[a:text.index(end, a)].strip()


def strip_comments(text):
    return '\n'.join(line for line in text.splitlines() if not line.lstrip().startswith('//'))


listing = read(media / 'PeerMediaListController.swift')
photos = read(media / 'PeerMediaPhotosController.swift')
gifs = read(media / 'PeerMediaGifsController.swift')
info = read(profile / 'PeerInfoController.swift')
tabs = read(profile / 'PeerMediaController.swift')
blocks = ['import Cocoa', 'import SwiftSignalKit']
blocks += [between(listing, 'public enum PeerMediaSharedEntryStableId', '\n//private func')]
blocks += [between(listing, 'public enum PeerMediaSharedEntry :', '\nprivate final class Arguments')]
blocks += [between(photos, 'private struct PeerMediaPhotosState', '\nstruct PeerMediaGridBounds').replace('private struct', 'struct', 1)]
blocks += [between(gifs, 'private struct PeerMediaGifsState', '\nprivate final class PeerMediaGifsSupplyment').replace('private struct', 'struct', 1)]
blocks += [read(media / 'PeerMediaGridSizing.swift')]
blocks += [read(root / 'packages/ChatHistoryModel/Sources/ChatHistoryModel/ChatDateId.swift')]
postbox = read(root / 'submodules/telegram-ios/submodules/Postbox/Sources/Message.swift')
blocks += [between(postbox, 'public struct MessageIndex:', '\npublic struct ChatListIndex:')]
rows = read(root / 'packages/GeneralRows/Sources/GeneralRows/GeneralRowItem.swift')
blocks += [between(rows, 'public func bestGeneralViewType<T>(_ array:[T], for item: T) -> GeneralViewType where T: Equatable', '\npublic func bestGeneralViewType<T>(_ array:[T], for i: Int)')]
a = info.index('        let inputActivity = context.account.peerInputActivities(')
a = info.index('\n', a)
b = info.index('        let inputActivityState:', a)
blocks += ['func profileActivities(_ signal: Signal<[(PeerId, PeerInputActivity)], NoError>) -> Signal<[PeerId: PeerInputActivity], NoError> {\nreturn signal' + info[a:b] + '\n}']
assert 'PeerMediaGridSizing(width: size.width, maximumColumns: 7).itemCount(height: size.height) * 10' in photos
assert 'PeerMediaGridSizing(width: atomicSize.with { $0.width }, maximumColumns: 7).columns' in photos
assert 'PeerMediaGridSizing(width: min(600, size.width - 60) - 14, maximumColumns: 4).itemCount(height: size.height)' in gifs
assert 'return PeerMediaGifsState(isLoading: isLoading, messages: messages)' in gifs
assert '.withUpdatedLoading(false).withUpdatedLoading(isLoading)' not in gifs
for name, text in [('TabHarness', tabs), ('ReferenceTabHarness', (lab / 'ReferenceTabPipeline.txt').read_text())]:
    pipeline = between(text, '        let distinctTabs: Signal<(tabs:', '        let ready = data') if name == 'TabHarness' else text
    blocks += ['final class ' + name + ': TabHarnessBase {\nfunc stream() -> Signal<TabData, NoError> {\n' + pipeline + '\nreturn data\n}\n}']
mode = read(root / 'packages/TelegramLinks/Sources/TelegramLinks/PeerMediaCollectionMode.swift')
blocks += [between(mode, 'public enum PeerMediaCollectionMode', '    public var tagsValue:') + '\n}']
(lab / 'Sources/PeerMediaProfileLab/Generated.swift').write_text(strip_comments('\n\n'.join(blocks)) + '\n')
(lab / 'provenance.json').write_text(json.dumps(hashes, indent=2) + '\n')
