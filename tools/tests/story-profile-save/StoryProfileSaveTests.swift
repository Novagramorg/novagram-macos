import Foundation
import XCTest
import SwiftSignalKit

typealias PeerId = Int
struct StoryId: Hashable { let peerId: Int; let id: Int32 }
struct CodableEntry {
    let value: Any?
    init?(_ value: Any) { self.value = value }
    init(data: Data) { self.value = nil }
    func get<T>(_ type: T.Type) -> T? { value as? T }
}
enum Stories {
    enum StoredItem: Equatable { case item(Item), placeholder(Int32) }
    struct Item: Equatable {
        struct Privacy: Equatable { let base: Int; let additionallyIncludePeers: [Int] }
        var id: Int32
        var timestamp = 1
        var expirationTimestamp = 2
        var media = 3
        var alternativeMediaList = [4]
        var mediaAreas = [5]
        var text = "original"
        var entities = [6]
        var views = 7
        var privacy: Privacy? = .init(base: 0, additionallyIncludePeers: [])
        var isPinned = true
        var isExpired = false
        var isPublic = true
        var isCloseFriends = false
        var isContacts = false
        var isSelectedContacts = false
        var isForwardingDisabled = true
        var isEdited = false
        var isMy = true
        var myReaction = 8
        var forwardInfo = 9
        var music = 10
        var authorId = 11
        var folderIds = [12]
        var isLiveStream: Bool { media == 99 }
    }
}
struct StoryItemsTableEntry {
    let value: CodableEntry
    let id: Int32
    let expirationTimestamp: Int
    let isCloseFriends: Bool
    let isLiveStream: Bool
}
struct EngineStoryItem {
    let item: Stories.Item
    var id: Int32 { item.id }
    func asStoryItem() -> Stories.Item { item }
}
struct Peer { let id: Int }
struct MTRpcError: Error {}
enum Api {
    enum Bool { case boolTrue, boolFalse }
    struct InputPeer { let id: Int }
    enum functions { enum stories {
        static func togglePinned(peer: InputPeer, id: [Int32], pinned: Bool) -> RequestData { .init(peer: peer.id, ids: id, pinned: pinned) }
    } }
}
struct RequestData { let peer: Int; let ids: [Int32]; let pinned: Api.Bool }
func apiInputPeer(_ peer: Peer) -> Api.InputPeer? { peer.id > 0 ? .init(id: peer.id) : nil }
final class Transaction {
    var peer: Peer? = .init(id: 10)
    var stories: [StoryId: CodableEntry] = [:]
    var lists: [Int: [StoryItemsTableEntry]] = [:]
    var writes = 0
    func getPeer(_ id: Int) -> Peer? { peer }
    func getStory(id: StoryId) -> CodableEntry? { stories[id] }
    func setStory(id: StoryId, value: CodableEntry) { stories[id] = value; writes += 1 }
    func getStoryItems(peerId: Int) -> [StoryItemsTableEntry] { lists[peerId] ?? [] }
    func setStoryItems(peerId: Int, items: [StoryItemsTableEntry]) { lists[peerId] = items; writes += 1 }
}
final class Postbox {
    let storage = Transaction()
    var delayNext = false
    var finish: (() -> Void)?
    var subscriptions = 0
    func transaction<T>(_ f: @escaping (Transaction) -> T) -> Signal<T, NoError> {
        Signal { subscriber in
            self.subscriptions += 1
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
enum InternalStoryUpdate: Equatable { case added(peerId: Int, item: Stories.StoredItem) }
final class StateManager {
    var updates: [InternalStoryUpdate] = []
    var onUpdates: (() -> Void)?
    func injectStoryUpdates(updates: [InternalStoryUpdate]) { self.updates += updates; onUpdates?() }
}
final class Account { let postbox = Postbox(); let network = Network(); let stateManager = StateManager() }

__SOURCE__

final class StoryProfileSaveTests: XCTestCase {
    func drain() { let done = expectation(description: "main"); DispatchQueue.main.async { done.fulfill() }; wait(for: [done], timeout: 2) }
    func entry(_ item: Stories.Item) -> StoryItemsTableEntry { .init(value: CodableEntry(Stories.StoredItem.item(item))!, id: item.id, expirationTimestamp: item.expirationTimestamp, isCloseFriends: item.isCloseFriends, isLiveStream: item.isLiveStream) }
    func references(_ ids: [Int32] = [1]) -> [Int32: EngineStoryItem] { Dictionary(uniqueKeysWithValues: ids.map { ($0, .init(item: .init(id: $0))) }) }
    func setup() -> Account {
        let account = Account()
        for peer in [10, 20] {
            account.postbox.storage.lists[peer] = [entry(.init(id: 1)), entry(.init(id: 2))]
            account.postbox.storage.stories[.init(peerId: peer, id: 1)] = CodableEntry(Stories.StoredItem.item(.init(id: 1)))
        }
        return account
    }
    func cached(_ a: Account, _ peer: Int = 10, _ id: Int32 = 1) -> Stories.Item? { if case let .item(item) = a.postbox.storage.getStory(id: .init(peerId: peer, id: id))?.get(Stories.StoredItem.self) { return item }; return nil }
    func listed(_ a: Account, _ peer: Int = 10, _ id: Int32 = 1) -> Stories.Item? { if case let .item(item) = a.postbox.storage.lists[peer]?.first(where: { $0.id == id })?.value.get(Stories.StoredItem.self) { return item }; return nil }
    func testUnsubscribedRequestDoesNothing() {
        let a = setup(); _ = _internal_updateStoriesArePinned(account: a, peerId: 10, ids: references(), isPinned: false); drain()
        XCTAssertEqual(a.postbox.subscriptions, 0); XCTAssertEqual(a.postbox.storage.writes, 0); XCTAssertTrue(a.stateManager.updates.isEmpty)
    }
    func testPendingRequestLeavesListAndCacheUnchanged() {
        let a = setup(); let d = _internal_updateStoriesArePinned(account: a, peerId: 10, ids: references(), isPinned: false).start(); drain()
        XCTAssertEqual(a.postbox.storage.writes, 0); XCTAssertEqual(listed(a)?.isPinned, true); XCTAssertEqual(cached(a)?.isPinned, true); XCTAssertTrue(a.stateManager.updates.isEmpty); d.dispose()
    }
    func testRejectedRequestFailsWithoutChanges() {
        let a = setup(); var errors = 0; var completed = 0
        let d = _internal_updateStoriesArePinned(account: a, peerId: 10, ids: references(), isPinned: false).start(error: { _ in errors += 1 }, completed: { completed += 1 })
        a.network.requests.first?.fail(); drain()
        XCTAssertEqual(errors, 1); XCTAssertEqual(completed, 0); XCTAssertEqual(a.postbox.storage.writes, 0); XCTAssertTrue(a.stateManager.updates.isEmpty); d.dispose()
    }
    func testAcceptedArchiveUpdatesBothCachesAndOnlyRequestedPeer() {
        let a = setup(); let d = _internal_updateStoriesArePinned(account: a, peerId: 10, ids: references(), isPinned: false).start()
        a.network.requests.first?.succeed([1]); drain()
        XCTAssertEqual(listed(a)?.isPinned, false); XCTAssertEqual(cached(a)?.isPinned, false); XCTAssertEqual(listed(a, 20)?.isPinned, true); XCTAssertEqual(cached(a, 20)?.isPinned, true); XCTAssertEqual(listed(a, 10, 2)?.isPinned, true); d.dispose()
    }
    func testEventsFollowCacheCommitBeforeCompletion() {
        let a = setup(); var events: [String] = []
        a.stateManager.onUpdates = { XCTAssertEqual(self.cached(a)?.isPinned, false); XCTAssertEqual(self.listed(a)?.isPinned, false); XCTAssertTrue(Thread.isMainThread); events.append("update") }
        let d = _internal_updateStoriesArePinned(account: a, peerId: 10, ids: references(), isPinned: false).start(completed: { events.append("complete") })
        a.network.requests.first?.succeed(); drain(); XCTAssertEqual(events, ["update", "complete"]); d.dispose()
    }
    func testLatestFieldsInBothCachesSurviveAcceptance() {
        let a = setup(); let d = _internal_updateStoriesArePinned(account: a, peerId: 10, ids: references(), isPinned: false).start()
        var latestList = Stories.Item(id: 1); latestList.text = "latest list"; latestList.views = 50; latestList.folderIds = [90]; latestList.expirationTimestamp = 30
        var latestCache = Stories.Item(id: 1); latestCache.text = "latest cache"; latestCache.media = 99; latestCache.privacy = .init(base: 2, additionallyIncludePeers: [30]); latestCache.myReaction = 8
        a.postbox.storage.lists[10] = [entry(latestList), entry(.init(id: 3))]; a.postbox.storage.stories[.init(peerId: 10, id: 1)] = CodableEntry(Stories.StoredItem.item(latestCache))
        a.network.requests.first?.succeed(); drain(); latestList.isPinned = false; latestCache.isPinned = false
        XCTAssertEqual(listed(a), latestList); XCTAssertEqual(cached(a), latestCache); XCTAssertNotNil(listed(a, 10, 3)); XCTAssertEqual(a.stateManager.updates, [.added(peerId: 10, item: .item(latestList))]); d.dispose()
    }
    func testDeletedStoryIsNotResurrectedByLateAcceptance() {
        let a = setup(); let d = _internal_updateStoriesArePinned(account: a, peerId: 10, ids: references(), isPinned: true).start()
        a.postbox.storage.lists[10] = []; a.postbox.storage.stories[.init(peerId: 10, id: 1)] = CodableEntry(data: Data())
        a.network.requests.first?.succeed(); drain()
        XCTAssertNil(cached(a)); XCTAssertTrue(a.postbox.storage.lists[10]?.isEmpty == true); XCTAssertTrue(a.stateManager.updates.isEmpty); d.dispose()
    }
    func testCacheOnlyStoryPublishesLatestMetadata() {
        let a = setup(); a.postbox.storage.lists[10] = []; var latest = Stories.Item(id: 1); latest.text = "cache only"
        a.postbox.storage.stories[.init(peerId: 10, id: 1)] = CodableEntry(Stories.StoredItem.item(latest))
        let d = _internal_updateStoriesArePinned(account: a, peerId: 10, ids: references(), isPinned: false).start(); a.network.requests.first?.succeed(); drain(); latest.isPinned = false
        XCTAssertEqual(cached(a), latest); XCTAssertEqual(a.stateManager.updates, [.added(peerId: 10, item: .item(latest))]); XCTAssertTrue(a.postbox.storage.lists[10]?.isEmpty == true); d.dispose()
    }
    func testArchiveReferenceCanBeSavedWhenNotInActiveCache() {
        let a = Account(); var story = Stories.Item(id: 7); story.isPinned = false
        let d = _internal_updateStoriesArePinned(account: a, peerId: 10, ids: [7: .init(item: story)], isPinned: true).start(); drain(); XCTAssertTrue(a.stateManager.updates.isEmpty)
        a.network.requests.first?.succeed(); drain(); story.isPinned = true
        XCTAssertEqual(a.stateManager.updates, [.added(peerId: 10, item: .item(story))]); XCTAssertTrue(a.postbox.storage.lists.isEmpty); d.dispose()
    }
    func testPlaceholderDoesNotPreventSavingArchiveReference() {
        let a = Account(); a.postbox.storage.stories[.init(peerId: 10, id: 1)] = CodableEntry(Stories.StoredItem.placeholder(1))
        let d = _internal_updateStoriesArePinned(account: a, peerId: 10, ids: references(), isPinned: false).start(); a.network.requests.first?.succeed(); drain()
        var story = Stories.Item(id: 1); story.isPinned = false
        XCTAssertEqual(a.stateManager.updates, [.added(peerId: 10, item: .item(story))]); d.dispose()
    }
    func testUnexpectedResponseIdsCannotRetargetMutation() {
        let a = setup(); let d = _internal_updateStoriesArePinned(account: a, peerId: 10, ids: references(), isPinned: false).start(); a.network.requests.first?.succeed([2, 3]); drain()
        XCTAssertEqual(listed(a)?.isPinned, false); XCTAssertEqual(listed(a, 10, 2)?.isPinned, true); XCTAssertEqual(cached(a)?.isPinned, false); d.dispose()
    }
    func testEmptyRequestIsNoOp() {
        let a = setup(); var completed = 0; let d = _internal_updateStoriesArePinned(account: a, peerId: 10, ids: [:], isPinned: false).start(completed: { completed += 1 }); drain()
        XCTAssertEqual(completed, 1); XCTAssertEqual(a.postbox.storage.writes, 0); XCTAssertTrue(a.network.requests.isEmpty); d.dispose()
    }
    func testMismatchedReferenceIdentityIsRejected() {
        let a = setup(); var errors = 0; let d = _internal_updateStoriesArePinned(account: a, peerId: 10, ids: [1: .init(item: .init(id: 9))], isPinned: false).start(error: { _ in errors += 1 }); drain()
        XCTAssertEqual(errors, 1); XCTAssertTrue(a.network.requests.isEmpty); XCTAssertEqual(a.postbox.storage.writes, 0); d.dispose()
    }
    func testMissingAndInvalidPeerFail() {
        for peer: Peer? in [nil, .init(id: -1)] {
            let a = setup(); a.postbox.storage.peer = peer; var errors = 0
            let d = _internal_updateStoriesArePinned(account: a, peerId: 10, ids: references(), isPinned: false).start(error: { _ in errors += 1 }); drain()
            XCTAssertEqual(errors, 1); XCTAssertTrue(a.network.requests.isEmpty); d.dispose()
        }
    }
    func testRequestUsesSortedIdsAndRequestedDirection() {
        for pinned in [false, true] {
            let a = setup(); let d = _internal_updateStoriesArePinned(account: a, peerId: 10, ids: references([2, 1]), isPinned: pinned).start()
            XCTAssertEqual(a.network.requests.first?.data.peer, 10); XCTAssertEqual(a.network.requests.first?.data.ids, [1, 2])
            XCTAssertEqual(a.network.requests.first?.data.pinned, pinned ? .boolTrue : .boolFalse); d.dispose()
        }
    }
    func testValidationCancellationDoesNotStartRequest() {
        let a = setup(); a.postbox.delayNext = true; let d = _internal_updateStoriesArePinned(account: a, peerId: 10, ids: references(), isPinned: false).start()
        d.dispose(); a.postbox.finish?(); drain(); XCTAssertTrue(a.network.requests.isEmpty); XCTAssertEqual(a.postbox.storage.writes, 0)
    }
    func testRequestCancellationLeavesCachesAndEventsUnchanged() {
        let a = setup(); let d = _internal_updateStoriesArePinned(account: a, peerId: 10, ids: references(), isPinned: false).start()
        d.dispose(); a.network.requests.first?.succeed(); drain(); XCTAssertEqual(a.postbox.storage.writes, 0); XCTAssertTrue(a.stateManager.updates.isEmpty); XCTAssertTrue(a.network.requests.first?.cancelled == true)
    }
    func testCommitCancellationDoesNotPublishOrComplete() {
        let a = setup(); var completed = false; let d = _internal_updateStoriesArePinned(account: a, peerId: 10, ids: references(), isPinned: false).start(completed: { completed = true })
        a.postbox.delayNext = true; a.network.requests.first?.succeed(); XCTAssertNotNil(a.postbox.finish); d.dispose(); a.postbox.finish?(); drain()
        XCTAssertFalse(completed); XCTAssertEqual(a.postbox.storage.writes, 0); XCTAssertTrue(a.stateManager.updates.isEmpty)
    }
    func testSynchronousAcceptanceCommitsOnce() {
        let a = setup(); a.network.onRequest = { $0.succeed() }; var completed = 0
        let d = _internal_updateStoriesArePinned(account: a, peerId: 10, ids: references(), isPinned: false).start(completed: { completed += 1 }); drain()
        XCTAssertEqual(completed, 1); XCTAssertEqual(a.stateManager.updates.count, 1); XCTAssertEqual(cached(a)?.isPinned, false); d.dispose()
    }
}
