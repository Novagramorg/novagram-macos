import Foundation
import XCTest
import SwiftSignalKit

typealias PeerId = Int
class Peer { let id: Int; init(_ id: Int) { self.id = id } }
final class TelegramUser: Peer { var storiesHidden: Bool? = false }
final class TelegramChannel: Peer { enum Status { case member, left }; var participationStatus: Status = .member; var storiesHidden: Bool? = false }
final class TelegramGroup: Peer { enum Status { case Member, Left }; var membership: Status = .Member }
struct PeerReference { let id: Int; var inputPeer: Api.InputPeer { .init(id: id) } }
func apiInputPeer(_ peer: Peer) -> Api.InputPeer? { peer.id > 0 ? .init(id: peer.id) : nil }
struct StoryId: Hashable { let peerId: Int; let id: Int32 }
struct CodableEntry: Equatable {
    let value: Any
    init?<T>(_ value: T) { self.value = value }
    func get<T>(_ type: T.Type) -> T? { value as? T }
    static func ==(lhs: Self, rhs: Self) -> Bool {
        if let l = lhs.value as? Stories.StoredItem, let r = rhs.value as? Stories.StoredItem { return l == r }
        if let l = lhs.value as? Stories.PeerState, let r = rhs.value as? Stories.PeerState { return l == r }
        return false
    }
}
struct StoryItemsTableEntry: Equatable {
    let value: CodableEntry
    let id: Int32
    let expirationTimestamp: Int32
    let isCloseFriends: Bool
    let isLiveStream: Bool
}
struct PeerStateRecord { let entry: CodableEntry }
enum Stories {
    struct PeerState: Equatable {
        let maxReadId: Int32
        var postboxRepresentation: PeerStateRecord { .init(entry: CodableEntry(self)!) }
    }
    struct Item: Equatable {
        var id: Int32
        var text = "original"
        var views: Int? = 30
        var reaction: Int? = 7
        var myReaction: Int? { reaction }
        var expirationTimestamp: Int32 = 100
        var isCloseFriends = false
        var isLiveStream = false
    }
    enum StoredItem: Equatable {
        case item(Item), placeholder(Int32)
        var id: Int32 { switch self { case let .item(item): return item.id; case let .placeholder(id): return id } }
        var expirationTimestamp: Int32 { switch self { case let .item(item): return item.expirationTimestamp; case .placeholder: return 100 } }
        var isCloseFriends: Bool { switch self { case let .item(item): return item.isCloseFriends; case .placeholder: return false } }
        var isLiveStream: Bool { switch self { case let .item(item): return item.isLiveStream; case .placeholder: return false } }
        init?(apiStoryItem: Api.StoryItem, existingItem: Item? = nil, peerId: Int, transaction: Transaction) {
            switch apiStoryItem {
            case let .item(item): self = .item(item)
            case var .minimal(item):
                item.views = existingItem?.views; item.reaction = existingItem?.reaction; self = .item(item)
            case let .placeholder(id): self = .placeholder(id)
            case .unsupported, .storyItemDeleted: return nil
            }
        }
    }
}
enum Api {
    struct InputPeer { let id: Int }
    enum StoryItem {
        case item(Stories.Item), minimal(Stories.Item), placeholder(Int32), unsupported(Int32), storyItemDeleted(Int32)
        var id: Int32 { switch self { case let .item(item), let .minimal(item): return item.id; case let .placeholder(id), let .unsupported(id), let .storyItemDeleted(id): return id } }
    }
    struct PeerStoriesData { let flags: Int32 = 0; let peer: ApiPeer; let maxReadId: Int32?; let stories: [StoryItem] }
    struct ApiPeer { let peerId: Int }
    enum PeerStories { case peerStories(PeerStoriesData) }
    enum stories {
        struct Result { let stories: Api.PeerStories; let chats: [Int] = []; let users: [Int] = [] }
        enum PeerStories { case peerStories(Result) }
    }
    enum functions { enum stories { static func getPeerStories(peer: InputPeer) -> Int { peer.id } } }
}
struct AccumulatedPeers { init(transaction: Transaction, chats: [Int], users: [Int]) {} }
func updatePeers(transaction: Transaction, accountPeerId: Int, peers: AccumulatedPeers) { transaction.peerWrites += 1 }
func shouldKeepUserStoriesInFeed(peerId: Int, isContactOrMember: Bool) -> Bool { isContactOrMember }
enum SubscriptionKey: Hashable { case hidden, filtered }
final class Transaction {
    var peers: [Int: Peer] = [100: TelegramUser(100), 200: TelegramUser(200)]
    var rows: [Int: [StoryItemsTableEntry]] = [:]
    var individual: [StoryId: CodableEntry] = [:]
    var cache: [StoryId: Stories.Item] = [:]
    var states: [Int: PeerStateRecord] = [:]
    var subscriptions: [SubscriptionKey: [Int]] = [:]
    var contacts: Set<Int> = [100]
    var writes = 0
    var stateWrites = 0
    var peerWrites = 0
    var subscriptionWrites = 0
    func getPeer(_ id: Int) -> Peer? { peers[id] }
    func getStoryItems(peerId: Int) -> [StoryItemsTableEntry] { rows[peerId] ?? [] }
    func setStoryItems(peerId: Int, items: [StoryItemsTableEntry]) { rows[peerId] = items; writes += 1 }
    func getStory(id: StoryId) -> CodableEntry? { individual[id] }
    func getPeerStoryState(peerId: Int) -> PeerStateRecord? { states[peerId] }
    func setPeerStoryState(peerId: Int, state: PeerStateRecord) { states[peerId] = state; stateWrites += 1 }
    func isPeerContact(peerId: Int) -> Bool { contacts.contains(peerId) }
    func storySubscriptionsContains(key: SubscriptionKey, peerId: Int) -> Bool { (subscriptions[key] ?? []).contains(peerId) }
    func getAllStorySubscriptions(key: SubscriptionKey) -> (Int, [Int]) { (0, subscriptions[key] ?? []) }
    func replaceAllStorySubscriptions(key: SubscriptionKey, state: Int, peerIds: [Int]) { subscriptions[key] = peerIds; subscriptionWrites += 1 }
}
func _internal_cachedStoryItemValue(transaction: Transaction, peerId: Int, id: Int32) -> Stories.Item? { transaction.cache[.init(peerId: peerId, id: id)] }
__EXISTING__
final class Postbox {
    let storage = Transaction()
    var count = 0
    var delay: Set<Int> = []
    var pending: [() -> Void] = []
    func transaction<T>(_ f: @escaping (Transaction) -> T) -> Signal<T, NoError> {
        Signal { subscriber in
            self.count += 1
            let action = { subscriber.putNext(f(self.storage)); subscriber.putCompletion() }
            if self.delay.contains(self.count) { self.pending.append(action) } else { action() }
            return EmptyDisposable
        }
    }
    func flush() { let queued = pending; pending.removeAll(); for f in queued { f() } }
}
struct RpcError: Error {}
final class Network {
    final class Request {
        let peer: Int
        var subscriber: Subscriber<Api.stories.PeerStories, RpcError>?
        init(peer: Int) { self.peer = peer }
        func succeed(_ stories: [Api.StoryItem], peer: Int = 100, read: Int32? = nil) {
            subscriber?.putNext(.peerStories(.init(stories: .peerStories(.init(peer: .init(peerId: peer), maxReadId: read, stories: stories)))))
            subscriber?.putCompletion()
        }
        func fail() { subscriber?.putError(RpcError()) }
    }
    var requests: [Request] = []
    func request(_ peer: Int) -> Signal<Api.stories.PeerStories, RpcError> {
        Signal { subscriber in
            let request = Request(peer: peer); request.subscriber = subscriber; self.requests.append(request)
            return ActionDisposable { request.subscriber = nil }
        }
    }
}
final class StoryRefreshContext { func invalidate(peerId: Int, ids: [Int32]) {} }
__ORDERING__
enum Namespaces { enum Peer { static let CloudChannel = 1 } }
extension Int { var namespace: Int { 1 } }
final class StoryReactionContext {
    func pendingReaction(for id: StoryId) -> Int?? { nil }
    func requireRefresh(for id: StoryId) {}
}
enum InternalStoryUpdate { case deleted(peerId: Int, id: Int32) }
final class AccountStateManager {
    let storyReactionContext = StoryReactionContext()
    let storyRefreshContext = StoryRefreshContext()
    let storyViewRefreshContext = StoryRefreshContext()
    func injectStoryUpdates(updates: [InternalStoryUpdate]) {}
}
func _internal_applyStoryUpdate(transaction: Transaction, peerId: Int, story: Api.StoryItem, storyReactionContext: StoryReactionContext?, addToActive: Bool) -> [InternalStoryUpdate] {
    guard case .storyItemDeleted = story else { return [] }
    transaction.individual.removeValue(forKey: .init(peerId: peerId, id: story.id))
    transaction.cache.removeValue(forKey: .init(peerId: peerId, id: story.id))
    let rows = transaction.getStoryItems(peerId: peerId).filter { $0.id != story.id }
    if rows != transaction.getStoryItems(peerId: peerId) { transaction.setStoryItems(peerId: peerId, items: rows) }
    return [.deleted(peerId: peerId, id: story.id)]
}
func _internal_updateStoryViewsForMyReaction(isChannel: Bool, views: Int?, previousReaction: Int?, reaction: Int?) -> Int? { views }
func _internal_storyWithReaction(_ item: Stories.Item, isChannel: Bool, reaction: Int?, views: Int?? = nil) -> Stories.Item {
    var item = item; item.reaction = reaction; if let views { item.views = views }; return item
}
__POLL__

final class StoryPeerPollTests: XCTestCase {
    func row(_ item: Stories.StoredItem) -> StoryItemsTableEntry { .init(value: CodableEntry(item)!, id: item.id, expirationTimestamp: item.expirationTimestamp, isCloseFriends: item.isCloseFriends, isLiveStream: item.isLiveStream) }
    func seed(_ p: Postbox) { p.storage.rows[100] = [row(.item(.init(id: 1)))]; p.storage.states[100] = Stories.PeerState(maxReadId: 10).postboxRepresentation }
    func poll(_ p: Postbox, _ n: Network, reference: PeerReference? = nil, completion: (() -> Void)? = nil) -> Disposable {
        _internal_pollPeerStories(postbox: p, network: n, accountPeerId: 10, peerId: 100, peerReference: reference).start(completed: completion)
    }
    func item(_ p: Postbox) -> Stories.Item? { if case let .item(item) = p.storage.rows[100]?.first?.value.get(Stories.StoredItem.self) { return item }; return nil }
    func testFailurePreservesListReadStateAndSubscriptions() {
        let p = Postbox(); let n = Network(); seed(p); p.storage.subscriptions[.filtered] = [100]; var complete = false
        let d = poll(p, n, completion: { complete = true }); n.requests[0].fail()
        XCTAssertEqual(item(p)?.id, 1); XCTAssertEqual(p.storage.writes, 0); XCTAssertEqual(p.storage.stateWrites, 0); XCTAssertEqual(p.storage.subscriptionWrites, 0); XCTAssertTrue(complete); d.dispose()
    }
    func testValidEmptyResponseClearsList() {
        let p = Postbox(); let n = Network(); seed(p); let d = poll(p, n); n.requests[0].succeed([])
        XCTAssertEqual(p.storage.rows[100], []); d.dispose()
    }
    func testWrongPeerResponseCannotReplaceRequestedPeerOrReadState() {
        let p = Postbox(); let n = Network(); seed(p); let d = poll(p, n); n.requests[0].succeed([.item(.init(id: 2))], peer: 200, read: 90)
        XCTAssertEqual(item(p)?.id, 1); XCTAssertNil(p.storage.states[200]); XCTAssertEqual(p.storage.peerWrites, 0); d.dispose()
    }
    func testWrongFallbackPeerDoesNotRequestOtherPeer() {
        let p = Postbox(); let n = Network(); p.storage.peers.removeValue(forKey: 100)
        let d = poll(p, n, reference: .init(id: 200)); XCTAssertTrue(n.requests.isEmpty); d.dispose()
    }
    func testMatchingFallbackPeerWorks() {
        let p = Postbox(); let n = Network(); p.storage.peers.removeValue(forKey: 100)
        let d = poll(p, n, reference: .init(id: 100)); XCTAssertEqual(n.requests.first?.peer, 100); n.requests[0].succeed([.item(.init(id: 2))]); XCTAssertEqual(item(p)?.id, 2); d.dispose()
    }
    func testMinimalResponsePreservesReactionAndViews() {
        let p = Postbox(); let n = Network(); seed(p); let d = poll(p, n)
        n.requests[0].succeed([.minimal(.init(id: 1, text: "edited", views: nil, reaction: nil))])
        XCTAssertEqual(item(p)?.text, "edited"); XCTAssertEqual(item(p)?.reaction, 7); XCTAssertEqual(item(p)?.views, 30); d.dispose()
    }
    func testUnsupportedMediaPreservesKnownStoryAndSavesValidNeighbor() {
        let p = Postbox(); let n = Network(); seed(p); let d = poll(p, n)
        n.requests[0].succeed([.unsupported(1), .item(.init(id: 2))])
        XCTAssertEqual(p.storage.rows[100]?.map(\.id), [1, 2]); d.dispose()
    }
    func testExplicitDeletionRemovesKnownStory() {
        let p = Postbox(); let n = Network(); seed(p); let d = poll(p, n); n.requests[0].succeed([.storyItemDeleted(1)])
        XCTAssertEqual(p.storage.rows[100], []); d.dispose()
    }
    func testPlaceholderPreservesActiveFullStory() {
        let p = Postbox(); let n = Network(); seed(p); let d = poll(p, n); n.requests[0].succeed([.placeholder(1)])
        XCTAssertEqual(item(p)?.id, 1); d.dispose()
    }
    func testPlaceholderUsesKnownIndividualStory() {
        let p = Postbox(); let n = Network(); p.storage.individual[.init(peerId: 100, id: 1)] = CodableEntry(Stories.StoredItem.item(.init(id: 1)))
        let d = poll(p, n); n.requests[0].succeed([.placeholder(1)]); XCTAssertEqual(item(p)?.id, 1); d.dispose()
    }
    func testMinimalResponseUsesCachedBaseline() {
        let p = Postbox(); let n = Network(); p.storage.cache[.init(peerId: 100, id: 1)] = .init(id: 1)
        let d = poll(p, n); n.requests[0].succeed([.minimal(.init(id: 1, text: "updated", views: nil, reaction: nil))])
        XCTAssertEqual(item(p)?.text, "updated"); XCTAssertEqual(item(p)?.views, 30); d.dispose()
    }
    func testReadStateDoesNotRegressOnLowerResponse() {
        let p = Postbox(); let n = Network(); seed(p); let d = poll(p, n); n.requests[0].succeed([], read: 3)
        XCTAssertEqual(p.storage.states[100]?.entry.get(Stories.PeerState.self)?.maxReadId, 10); d.dispose()
    }
    func testReadStateDoesNotRegressWhenOmitted() {
        let p = Postbox(); let n = Network(); seed(p); let d = poll(p, n); n.requests[0].succeed([])
        XCTAssertEqual(p.storage.states[100]?.entry.get(Stories.PeerState.self)?.maxReadId, 10); d.dispose()
    }
    func testReadStateAdvances() {
        let p = Postbox(); let n = Network(); seed(p); let d = poll(p, n); n.requests[0].succeed([], read: 20)
        XCTAssertEqual(p.storage.states[100]?.entry.get(Stories.PeerState.self)?.maxReadId, 20); d.dispose()
    }
    func testDuplicateIdsPreserveKnownValueWithoutDuplicateRows() {
        let p = Postbox(); let n = Network(); seed(p); let d = poll(p, n)
        n.requests[0].succeed([.item(.init(id: 1, text: "first")), .item(.init(id: 1, text: "second"))])
        XCTAssertEqual(p.storage.rows[100]?.count, 1); XCTAssertEqual(item(p)?.text, "original"); d.dispose()
    }
    func testInvalidStoryIdsAreNotStored() {
        let p = Postbox(); let n = Network(); let d = poll(p, n)
        n.requests[0].succeed([.item(.init(id: 0)), .item(.init(id: -1)), .item(.init(id: 2))])
        XCTAssertEqual(p.storage.rows[100]?.map(\.id), [2]); d.dispose()
    }
    func testCancelledQueuedCommitCannotWrite() {
        let p = Postbox(); let n = Network(); seed(p); p.delay = [2]; let d = poll(p, n)
        n.requests[0].succeed([]); d.dispose(); p.flush(); XCTAssertEqual(item(p)?.id, 1); XCTAssertEqual(p.storage.writes, 0)
    }
    func testCancellationBeforeLookupCannotStartRequest() {
        let p = Postbox(); let n = Network(); p.delay = [1]; let d = poll(p, n); d.dispose(); p.flush(); XCTAssertTrue(n.requests.isEmpty)
    }
    func testMissingPeerCompletesWithoutRequest() {
        let p = Postbox(); let n = Network(); p.storage.peers.removeAll(); var complete = false
        let d = poll(p, n, completion: { complete = true }); XCTAssertTrue(complete); XCTAssertTrue(n.requests.isEmpty); d.dispose()
    }
    func testUnchangedListDoesNotWriteAgain() {
        let p = Postbox(); let n = Network(); seed(p); let d = poll(p, n); n.requests[0].succeed([.item(.init(id: 1))], read: 10)
        XCTAssertEqual(p.storage.writes, 0); XCTAssertEqual(p.storage.stateWrites, 0); d.dispose()
    }
    func testSuccessfulVisibleContactEntersFeedOnce() {
        let p = Postbox(); let n = Network(); let d = poll(p, n); n.requests[0].succeed([.item(.init(id: 1))])
        XCTAssertEqual(p.storage.subscriptions[.filtered], [100]); let d2 = poll(p, n); n.requests[1].succeed([.item(.init(id: 1))]); XCTAssertEqual(p.storage.subscriptionWrites, 1); d.dispose(); d2.dispose()
    }
    func testSuccessfulHiddenContactEntersHiddenFeed() {
        let p = Postbox(); let n = Network(); (p.storage.peers[100] as? TelegramUser)?.storiesHidden = true
        let d = poll(p, n); n.requests[0].succeed([.item(.init(id: 1))]); XCTAssertEqual(p.storage.subscriptions[.hidden], [100]); XCTAssertNil(p.storage.subscriptions[.filtered]); d.dispose()
    }
}

extension StoryPeerPollTests {
    func testNewerEmptyPollSupersedesOlderNonemptyReply() {
        let p = Postbox(); let n = Network(); let a = poll(p, n); let b = poll(p, n)
        n.requests[1].succeed([]); n.requests[0].succeed([.item(.init(id: 1))])
        XCTAssertEqual(p.storage.getStoryItems(peerId: 100), []); a.dispose(); b.dispose()
    }
    func testNewerContentWinsWhenOlderReplyArrivesLast() {
        let p = Postbox(); let n = Network(); seed(p); let a = poll(p, n); let b = poll(p, n)
        n.requests[1].succeed([.item(.init(id: 1, text: "newer"))]); n.requests[0].succeed([.item(.init(id: 1, text: "older"))])
        XCTAssertEqual(item(p)?.text, "newer"); a.dispose(); b.dispose()
    }
    func testNewerReplyCanApplyAfterOlderReply() {
        let p = Postbox(); let n = Network(); seed(p); let a = poll(p, n); let b = poll(p, n)
        n.requests[0].succeed([.item(.init(id: 1, text: "older"))]); n.requests[1].succeed([.item(.init(id: 1, text: "newer"))])
        XCTAssertEqual(item(p)?.text, "newer"); a.dispose(); b.dispose()
    }
    func testConcurrentLocalMutationIsNotOverwritten() {
        let p = Postbox(); let n = Network(); seed(p); let a = poll(p, n)
        p.storage.rows[100] = [row(.item(.init(id: 1, text: "local")))]
        n.requests[0].succeed([.item(.init(id: 1, text: "old"))])
        XCTAssertEqual(item(p)?.text, "local"); a.dispose()
    }
    func testNewerFailedPollDoesNotDiscardOlderSuccess() {
        let p = Postbox(); let n = Network(); let a = poll(p, n); let b = poll(p, n)
        n.requests[1].fail(); n.requests[0].succeed([.item(.init(id: 1))])
        XCTAssertEqual(item(p)?.id, 1); a.dispose(); b.dispose()
    }
    func testNewerCancelledPollDoesNotDiscardOlderSuccess() {
        let p = Postbox(); let n = Network(); let a = poll(p, n); let b = poll(p, n); b.dispose()
        n.requests[0].succeed([.item(.init(id: 1))]); XCTAssertEqual(item(p)?.id, 1); a.dispose()
    }
}

extension StoryPeerPollTests {
    func testAuthoritativeInvalidationWithIdenticalEmptyListRejectsOldReply() {
        let p = Postbox(); let n = Network(); let d = poll(p, n)
        _internal_invalidateStoryResolution(postbox: p, peerId: 100, ids: [1])
        n.requests[0].succeed([.item(.init(id: 1))]); XCTAssertTrue(p.storage.getStoryItems(peerId: 100).isEmpty); d.dispose()
    }
    func testOtherPeerInvalidationDoesNotRejectReply() {
        let p = Postbox(); let n = Network(); let d = poll(p, n)
        _internal_invalidateStoryResolution(postbox: p, peerId: 200, ids: [1])
        n.requests[0].succeed([.item(.init(id: 1))]); XCTAssertEqual(item(p)?.id, 1); d.dispose()
    }
    func testIndependentPostboxesDoNotShareOrdering() {
        let p = Postbox(); let other = Postbox(); let n = Network(); let a = poll(p, n); let b = poll(other, n)
        n.requests[1].succeed([]); n.requests[0].succeed([.item(.init(id: 1))]); XCTAssertEqual(item(p)?.id, 1); a.dispose(); b.dispose()
    }
    func testReadOnlyChangeDuringPollIsPreservedWithoutDiscardingNewItems() {
        let p = Postbox(); let n = Network(); seed(p); let d = poll(p, n)
        p.storage.states[100] = Stories.PeerState(maxReadId: 70).postboxRepresentation
        n.requests[0].succeed([.item(.init(id: 2))], read: 20)
        XCTAssertEqual(item(p)?.id, 2); XCTAssertEqual(p.storage.states[100]?.entry.get(Stories.PeerState.self)?.maxReadId, 70); d.dispose()
    }
    func testRepeatedColdSignalSubscriptionsHaveIndependentTickets() {
        let p = Postbox(); let n = Network()
        let signal = _internal_pollPeerStories(postbox: p, network: n, accountPeerId: 10, peerId: 100)
        let a = signal.start(); let b = signal.start(); n.requests[1].succeed([.item(.init(id: 2))]); n.requests[0].succeed([.item(.init(id: 1))])
        XCTAssertEqual(item(p)?.id, 2); a.dispose(); b.dispose()
    }
    func testRegistryDoesNotRetainPostboxOrLeaseContext() {
        var p: Postbox? = Postbox(); weak var weakPostbox = p
        var lease: PeerStoryPollLease? = PeerStoryPollLease(postbox: p!, peerId: 100, items: [])
        weak var context = lease?.context
        p = nil; XCTAssertNil(weakPostbox); lease = nil; XCTAssertNil(context)
    }
    func testSuccessFailureAndCancelReleaseContext() {
        for mode in 0...2 {
            let p = Postbox(); let n = Network(); let d = poll(p, n)
            weak var context: PeerStoryPollContext?
            autoreleasepool { context = StoryResolutionContextRegistry.shared.pollContext(for: p, create: false) }
            XCTAssertNotNil(context)
            if mode == 0 { n.requests[0].succeed([]) } else if mode == 1 { n.requests[0].fail() } else { d.dispose() }
            XCTAssertNil(context); d.dispose()
        }
    }
    func testQueuedCommitRetainsLeaseUntilDelivery() {
        let p = Postbox(); let n = Network(); p.delay = [2]; let d = poll(p, n)
        weak var context: PeerStoryPollContext?
        autoreleasepool { context = StoryResolutionContextRegistry.shared.pollContext(for: p, create: false) }
        n.requests[0].succeed([.item(.init(id: 1))]); XCTAssertNotNil(context); p.flush()
        XCTAssertEqual(item(p)?.id, 1); XCTAssertNil(context); d.dispose()
    }
}

func _internal_removeStoriesFromListCaches(transaction: Transaction, peerId: Int, ids: Set<Int32>) {
    for id in ids { transaction.cache.removeValue(forKey: .init(peerId: peerId, id: id)) }
}
