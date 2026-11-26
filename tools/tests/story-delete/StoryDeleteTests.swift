import Foundation
import XCTest
import SwiftSignalKit

typealias PeerId = Int
struct Peer { let id: Int }
struct Item: Equatable {
    let id: Int32; var text = "old"; var folderIds: [Int64]? = nil
    var value: CodableEntry { CodableEntry(Stories.StoredItem.item(self))! }
}
enum Stories { enum StoredItem: Equatable { case item(Item), placeholder(Int32)
    var id: Int32 { switch self { case let .item(item): return item.id; case let .placeholder(id): return id } }
} }
extension Int { func toInt64() -> Int64 { Int64(self) } }
enum Namespaces { enum CachedItemCollection { static let cachedPeerStoryListHeads = 1 } }
final class ValueBoxKey: Hashable {
    let length: Int; var fields: [Int: Int64] = [:]
    init(length: Int) { self.length = length }
    func setInt64(_ offset: Int, value: Int64) { fields[offset] = value }
    func setInt8(_ offset: Int, value: Int8) { fields[offset] = Int64(value) }
    static func ==(lhs: ValueBoxKey, rhs: ValueBoxKey) -> Bool { lhs.length == rhs.length && lhs.fields == rhs.fields }
    func hash(into hasher: inout Hasher) { hasher.combine(length); for key in fields.keys.sorted() { hasher.combine(key); hasher.combine(fields[key]) } }
}
struct ItemCacheEntryId: Hashable { let collectionId: Int; let key: ValueBoxKey }
struct Folder: Equatable { let id: Int64; let title: String }
struct CachedPeerStoryListHead { let items: [Stories.StoredItem]; let pinnedIds: [Int32]; let totalCount: Int32; let folders: [Folder] }
struct StoryId: Hashable { let peerId: Int; let id: Int32 }
struct CodableEntry: Equatable {
    let data: Data
    let payload: Any?
    init(data: Data) { self.data = data; self.payload = nil }
    init?(_ value: Any) { self.data = Data(); self.payload = value }
    func get<T>(_ type: T.Type) -> T? { payload as? T }
    static func ==(lhs: CodableEntry, rhs: CodableEntry) -> Bool { lhs.data == rhs.data }
}
struct MTRpcError: Error {}
enum Api {
    struct InputPeer { let id: Int }
    enum functions { enum stories {
        static func deleteStories(peer: InputPeer, id: [Int32]) -> RequestData { .init(peer: peer.id, ids: id) }
    } }
}
struct RequestData { let peer: Int; let ids: [Int32] }
func apiInputPeer(_ peer: Peer) -> Api.InputPeer? { peer.id > 0 ? .init(id: peer.id) : nil }
final class Transaction {
    var cache: [ItemCacheEntryId: CodableEntry] = [:]
    var cacheWrites = 0
    func retrieveItemCacheEntry(id: ItemCacheEntryId) -> CodableEntry? { cache[id] }
    func putItemCacheEntry(id: ItemCacheEntryId, entry: CodableEntry) { cache[id] = entry; cacheWrites += 1 }
    func getStory(id: StoryId) -> CodableEntry? { stories[id] }
    var peers = [10: Peer(id: 10)]
    var items: [Int: [Item]] = [10: [.init(id: 1), .init(id: 2)], 20: [.init(id: 1)]]
    var stories: [StoryId: CodableEntry] = [.init(peerId: 10, id: 1): .init(data: Data([1])), .init(peerId: 10, id: 2): .init(data: Data([2])), .init(peerId: 20, id: 1): .init(data: Data([3]))]
    var writes = 0
    func getPeer(_ id: Int) -> Peer? { peers[id] }
    func getStoryItems(peerId: Int) -> [Item] { items[peerId] ?? [] }
    func setStoryItems(peerId: Int, items: [Item]) { self.items[peerId] = items; writes += 1 }
    func setStory(id: StoryId, value: CodableEntry) { stories[id] = value; writes += 1 }
}
final class Postbox {
    var resolutionInvalidations: [Int: Set<Int32>] = [:]
    let storage = Transaction()
    var delayNext = false
    var finish: (() -> Void)?
    func transaction<T>(_ f: @escaping (Transaction) -> T) -> Signal<T, NoError> {
        Signal { subscriber in
            let run = { subscriber.putNext(f(self.storage)); subscriber.putCompletion() }
            if self.delayNext {
                self.delayNext = false; self.finish = run
                return ActionDisposable { self.finish = nil }
            }
            run(); return EmptyDisposable
        }
    }
}
final class Request {
    let data: RequestData
    var subscriber: Subscriber<[Int32], MTRpcError>?
    var cancelled = false
    init(_ data: RequestData) { self.data = data }
    func succeed(_ ids: [Int32] = []) { subscriber?.putNext(ids); subscriber?.putCompletion() }
    func fail() { subscriber?.putError(.init()) }
}
final class Network {
    var requests: [Request] = []
    var onRequest: ((Request) -> Void)?
    func request(_ data: RequestData) -> Signal<[Int32], MTRpcError> {
        Signal { subscriber in
            let request = Request(data); request.subscriber = subscriber; self.requests.append(request); self.onRequest?(request)
            return ActionDisposable { request.cancelled = true; request.subscriber = nil }
        }
    }
}
enum InternalStoryUpdate: Equatable { case deleted(peerId: Int, id: Int32) }
final class StateManager {
    var updates: [InternalStoryUpdate] = []
    var onUpdates: (() -> Void)?
    func injectStoryUpdates(updates: [InternalStoryUpdate]) { self.updates += updates; onUpdates?() }
}
final class StoryRefreshContext {
    var invalidated: [Int: Set<Int32>] = [:]
    func invalidate(peerId: Int, ids: [Int32]) { invalidated[peerId, default: []].formUnion(ids) }
}
final class ReactionContext {
    var deleted = Set<StoryId>()
    func markDeleted(_ id: StoryId) { deleted.insert(id) }
}
final class Account { let storyReactionContext = ReactionContext(); let storyViewRefreshContext = StoryRefreshContext(); let storyRefreshContext = StoryRefreshContext(); let postbox = Postbox(); let network = Network(); let stateManager = StateManager() }
__CACHE_HELPERS__
__SOURCE__

final class StoryDeleteTests: XCTestCase {
    func ids(_ account: Account, _ peerId: Int = 10) -> [Int32] { account.postbox.storage.items[peerId, default: []].map(\.id) }
    func testColdOperationDoesNotMutateOrRequest() {
        let account = Account(); _ = _internal_deleteStories(account: account, peerId: 10, ids: [1])
        XCTAssertEqual(ids(account), [1, 2]); XCTAssertTrue(account.network.requests.isEmpty); XCTAssertTrue(account.stateManager.updates.isEmpty)
    }
    func testPendingRequestPreservesAllLocalStoryState() {
        let account = Account(); let operation = _internal_deleteStories(account: account, peerId: 10, ids: [1]).start()
        XCTAssertEqual(ids(account), [1, 2]); XCTAssertTrue(account.stateManager.updates.isEmpty); XCTAssertEqual(account.postbox.storage.writes, 0)
        operation.dispose()
    }
    func testServerRejectionDoesNotDeleteAndReportsError() {
        let account = Account(); var failed = false; var completed = false
        let operation = _internal_deleteStories(account: account, peerId: 10, ids: [1]).start(error: { _ in failed = true }, completed: { completed = true })
        account.network.requests.first?.fail()
        XCTAssertTrue(account.storyRefreshContext.invalidated.isEmpty)
        XCTAssertTrue(failed); XCTAssertFalse(completed); XCTAssertEqual(ids(account), [1, 2]); XCTAssertTrue(account.stateManager.updates.isEmpty); operation.dispose()
    }
    func testAcceptanceClearsBothCachesBeforeEventAndCompletion() {
        let account = Account(); var events = 0; var completed = false
        account.stateManager.onUpdates = {
            events += 1
            XCTAssertEqual(account.storyRefreshContext.invalidated[10], [1])
            XCTAssertEqual(account.postbox.resolutionInvalidations[10], [1])
            XCTAssertEqual(account.storyViewRefreshContext.invalidated[10], [1])
            XCTAssertEqual(account.storyReactionContext.deleted, [.init(peerId: 10, id: 1)])
            XCTAssertEqual(self.ids(account), [2])
            XCTAssertEqual(account.postbox.storage.stories[.init(peerId: 10, id: 1)]?.data, Data())
        }
        let operation = _internal_deleteStories(account: account, peerId: 10, ids: [1]).start(completed: { completed = true; XCTAssertEqual(events, 1) })
        account.network.requests.first?.succeed([1])
        XCTAssertTrue(completed); XCTAssertEqual(account.stateManager.updates, [.deleted(peerId: 10, id: 1)])
        account.stateManager.onUpdates = nil; operation.dispose()
    }
    func testEmptySuccessfulResultStillReconcilesRequestedDeletion() {
        let account = Account(); let operation = _internal_deleteStories(account: account, peerId: 10, ids: [1]).start()
        account.network.requests.first?.succeed([])
        XCTAssertEqual(ids(account), [2]); XCTAssertEqual(account.postbox.storage.stories[.init(peerId: 10, id: 1)]?.data, Data()); operation.dispose()
    }
    func testUnrequestedReturnedIdsCannotDeleteOtherStories() {
        let account = Account(); let operation = _internal_deleteStories(account: account, peerId: 10, ids: [1]).start()
        account.network.requests.first?.succeed([2, 99])
        XCTAssertEqual(ids(account), [2]); XCTAssertEqual(ids(account, 20), [1])
        XCTAssertEqual(account.postbox.storage.stories[.init(peerId: 20, id: 1)]?.data, Data([3]))
        XCTAssertEqual(account.postbox.storage.stories[.init(peerId: 10, id: 2)]?.data, Data([2])); operation.dispose()
    }
    func testDuplicateIdsAreSentAndPublishedOnce() {
        let account = Account(); let operation = _internal_deleteStories(account: account, peerId: 10, ids: [2, 1, 2]).start()
        XCTAssertEqual(account.network.requests.first?.data.ids, [2, 1]); account.network.requests.first?.succeed([1, 2])
        XCTAssertEqual(account.stateManager.updates, [.deleted(peerId: 10, id: 2), .deleted(peerId: 10, id: 1)]); operation.dispose()
    }
    func testEmptyInputCompletesWithoutNetworkOrMutation() {
        let account = Account(); var completed = false
        let operation = _internal_deleteStories(account: account, peerId: 10, ids: []).start(completed: { completed = true })
        XCTAssertTrue(completed); XCTAssertTrue(account.network.requests.isEmpty); XCTAssertEqual(account.postbox.storage.writes, 0); operation.dispose()
    }
    func testMissingPeerIsAnError() {
        let account = Account(); var failed = false; var completed = false
        let operation = _internal_deleteStories(account: account, peerId: 99, ids: [1]).start(error: { _ in failed = true }, completed: { completed = true })
        XCTAssertTrue(failed); XCTAssertFalse(completed); XCTAssertTrue(account.network.requests.isEmpty); operation.dispose()
    }
    func testLatestListChangesArePreservedAtCommit() {
        let account = Account(); let operation = _internal_deleteStories(account: account, peerId: 10, ids: [1]).start()
        account.postbox.storage.items[10] = [.init(id: 1), .init(id: 2, text: "new"), .init(id: 3)]
        account.network.requests.first?.succeed([1])
        XCTAssertEqual(account.postbox.storage.items[10], [.init(id: 2, text: "new"), .init(id: 3)]); operation.dispose()
    }
    func testCancellationBeforeResponseLeavesStateUnchanged() {
        let account = Account(); let operation = _internal_deleteStories(account: account, peerId: 10, ids: [1]).start()
        operation.dispose(); account.network.requests.first?.succeed([1])
        XCTAssertEqual(ids(account), [1, 2]); XCTAssertTrue(account.stateManager.updates.isEmpty)
    }
    func testCancellationDuringValidationDoesNotSendRequest() {
        let account = Account(); account.postbox.delayNext = true
        let operation = _internal_deleteStories(account: account, peerId: 10, ids: [1]).start()
        operation.dispose(); account.postbox.finish?()
        XCTAssertNil(account.postbox.finish); XCTAssertTrue(account.network.requests.isEmpty); XCTAssertEqual(ids(account), [1, 2])
    }
    func testCancellationDuringCommitDoesNotPublishOrComplete() {
        let account = Account(); var completed = false
        let operation = _internal_deleteStories(account: account, peerId: 10, ids: [1]).start(completed: { completed = true })
        account.postbox.delayNext = true; account.network.requests.first?.succeed([1])
        XCTAssertNotNil(account.postbox.finish); operation.dispose(); account.postbox.finish?()
        XCTAssertFalse(completed); XCTAssertEqual(ids(account), [1, 2]); XCTAssertTrue(account.stateManager.updates.isEmpty)
    }
    func testSynchronousAcceptanceCompletesOnce() {
        let account = Account(); account.network.onRequest = { $0.succeed([1]) }; var completed = 0
        let operation = _internal_deleteStories(account: account, peerId: 10, ids: [1]).start(completed: { completed += 1 })
        XCTAssertEqual(completed, 1); XCTAssertEqual(ids(account), [2]); operation.dispose()
    }
}

extension StoryDeleteTests {
    func key(_ peer: Int = 10, archived: Int8 = 0, album: Int64? = nil) -> ItemCacheEntryId {
        let key = ValueBoxKey(length: album == nil ? 9 : 17); key.setInt64(0, value: Int64(peer)); key.setInt8(8, value: archived)
        if let album { key.setInt64(9, value: album) }
        return .init(collectionId: 1, key: key)
    }
    func seed(_ a: Account, _ key: ItemCacheEntryId, items: [Stories.StoredItem] = [.item(.init(id: 1)), .item(.init(id: 2))], count: Int32 = 42, folders: [Folder] = []) {
        a.postbox.storage.cache[key] = CodableEntry(CachedPeerStoryListHead(items: items, pinnedIds: [2, 1], totalCount: count, folders: folders))
    }
    func head(_ a: Account, _ key: ItemCacheEntryId) -> CachedPeerStoryListHead? { a.postbox.storage.cache[key]?.get(CachedPeerStoryListHead.self) }
    func testLocalDeletionCleansAllKnownCachesBeforeNotification() {
        let a = Account(); a.postbox.storage.items[10]![0].folderIds = [7]
        let keys = [key(), key(archived: 1), key(album: 7), key(archived: 1, album: 7)]
        for k in keys { seed(a, k, folders: [.init(id: 7, title: "album")]) }
        var events = 0
        a.stateManager.onUpdates = {
            events += 1
            for k in keys { XCTAssertEqual(self.head(a, k)?.items.map(\.id), [2]); XCTAssertEqual(self.head(a, k)?.pinnedIds, [2]); XCTAssertEqual(self.head(a, k)?.totalCount, 41); XCTAssertEqual(self.head(a, k)?.folders, [.init(id: 7, title: "album")]) }
        }
        let d = _internal_deleteStories(account: a, peerId: 10, ids: [1]).start()
        XCTAssertEqual(a.postbox.storage.cacheWrites, 0); a.network.requests[0].succeed([1]); XCTAssertEqual(events, 1)
        a.stateManager.onUpdates = nil; d.dispose()
    }
    func testLocalDeleteDiscoversAlbumBeforeRemovingItsOnlyMembershipReference() {
        let a = Account(); a.postbox.storage.items[10]![0].folderIds = [9]
        a.postbox.storage.stories.removeAll(); seed(a, key(album: 9))
        let d = _internal_deleteStories(account: a, peerId: 10, ids: [1]).start(); a.network.requests[0].succeed([1])
        XCTAssertEqual(head(a, key(album: 9))?.items.map(\.id), [2]); d.dispose()
    }
    func testLocalDeleteFailureKeepsCachedStories() {
        let a = Account(); seed(a, key())
        let d = _internal_deleteStories(account: a, peerId: 10, ids: [1]).start(); a.network.requests[0].fail()
        XCTAssertEqual(head(a, key())?.items.map(\.id), [1, 2]); XCTAssertEqual(a.postbox.storage.cacheWrites, 0); d.dispose()
    }
    func testLocalDeleteCancellationBeforeAcceptanceKeepsCaches() {
        let a = Account(); seed(a, key())
        let d = _internal_deleteStories(account: a, peerId: 10, ids: [1]).start(); d.dispose(); a.network.requests[0].succeed([1])
        XCTAssertEqual(head(a, key())?.items.map(\.id), [1, 2]); XCTAssertEqual(a.postbox.storage.cacheWrites, 0)
    }
    func testLocalDeleteKeepsOtherPeerCaches() {
        let a = Account(); seed(a, key()); seed(a, key(20))
        let d = _internal_deleteStories(account: a, peerId: 10, ids: [1]).start(); a.network.requests[0].succeed([1])
        XCTAssertEqual(head(a, key())?.items.map(\.id), [2]); XCTAssertEqual(head(a, key(20))?.items.map(\.id), [1, 2]); d.dispose()
    }
    func testLocalDeleteBatchRemovesEachIdOnceFromCaches() {
        let a = Account(); seed(a, key())
        let d = _internal_deleteStories(account: a, peerId: 10, ids: [2, 1, 2]).start(); a.network.requests[0].succeed([1, 2])
        XCTAssertEqual(head(a, key())?.items.count, 0); XCTAssertEqual(head(a, key())?.totalCount, 40); XCTAssertEqual(head(a, key())?.pinnedIds, []); d.dispose()
    }
    func testLocalDeleteRetainsConcurrentCacheEditsAndOtherItems() {
        let a = Account(); seed(a, key())
        let d = _internal_deleteStories(account: a, peerId: 10, ids: [1]).start()
        let survivor = Item(id: 2, text: "edited", folderIds: [8])
        seed(a, key(), items: [.item(.init(id: 1)), .item(survivor), .placeholder(3)], count: 7, folders: [.init(id: 8, title: "new")])
        a.network.requests[0].succeed([1]); XCTAssertEqual(head(a, key())?.items, [.item(survivor), .placeholder(3)])
        XCTAssertEqual(head(a, key())?.totalCount, 6); XCTAssertEqual(head(a, key())?.folders, [.init(id: 8, title: "new")]); d.dispose()
    }
    func testLocalDeleteRemovesCachedPlaceholderWithoutCreatingAbsentHeads() {
        let a = Account(); seed(a, key(), items: [.placeholder(1)], count: 1)
        let d = _internal_deleteStories(account: a, peerId: 10, ids: [1]).start(); a.network.requests[0].succeed([])
        XCTAssertEqual(head(a, key())?.items.count, 0); XCTAssertEqual(head(a, key())?.totalCount, 0); XCTAssertEqual(a.postbox.storage.cache.count, 1); d.dispose()
    }
    func testRepeatedLocalDeleteDoesNotSubtractCachedCountAgain() {
        let a = Account(); seed(a, key())
        for _ in 0..<2 {
            let d = _internal_deleteStories(account: a, peerId: 10, ids: [1]).start(); a.network.requests.last?.succeed([]); d.dispose()
        }
        XCTAssertEqual(head(a, key())?.totalCount, 41); XCTAssertEqual(a.postbox.storage.cacheWrites, 1)
    }
}

func _internal_invalidateStoryResolution(postbox: Postbox, peerId: Int, ids: [Int32]) { postbox.resolutionInvalidations[peerId, default: []].formUnion(ids) }

extension StoryDeleteTests {
    func testBatchDeletionPreservesCacheOnlyAlbumDiscoveryForAllIds() {
        let a = Account(); a.postbox.storage.items[10] = []; a.postbox.storage.stories.removeAll()
        let items: [Stories.StoredItem] = [.item(.init(id: 1, folderIds: [7])), .item(.init(id: 2))]
        seed(a, key(), items: items, count: 2); seed(a, key(album: 7), items: items, count: 2)
        let d = _internal_deleteStories(account: a, peerId: 10, ids: [1, 2]).start(); a.network.requests[0].succeed([1, 2])
        XCTAssertEqual(head(a, key())?.items, []); XCTAssertEqual(head(a, key(album: 7))?.items, [])
        XCTAssertEqual(head(a, key(album: 7))?.totalCount, 0); XCTAssertEqual(a.postbox.storage.cacheWrites, 2); d.dispose()
    }
}
