import Foundation
import XCTest
import SwiftSignalKit

enum Stories {
    struct PeerState: Equatable { let maxReadId: Int32; var postboxRepresentation: PeerStateRecord { .init(entry: CodableEntry(self)!) } }
    enum ForwardInfo: Equatable { case known(Int, Int32, Bool) }
    struct Item: Equatable {
        var isLiveStream: Bool { false }
        struct Views: Equatable { var seenCount = 0; var reactedCount = 0; var forwardCount = 0; var seenPeerIds: [Int] = []; var reactions: [MessageReaction] = []; var hasList = false; __IS_EMPTY__ }
        var id: Int32
        var timestamp = 0
        var expirationTimestamp = 100
        var media: Int? = 1
        var alternativeMediaList: [Int] = []
        var mediaAreas: [Int] = []
        var text = "old"
        var entities: [Int] = []
        var views: Views? = nil
        var privacy: Int? = nil
        var isPinned = true
        var isExpired = false
        var isPublic = true
        var isCloseFriends = false
        var isContacts = false
        var isSelectedContacts = false
        var isForwardingDisabled = false
        var isEdited = false
        var isMy = true
        var myReaction: MessageReaction.Reaction? = nil
        var forwardInfo: Stories.ForwardInfo? = nil
        var music: Int? = nil
        var authorId: Int? = nil
        var folderIds: [Int64]? = nil
    }
    enum StoredItem: Equatable {
        case item(Item), placeholder(Int32)
        var id: Int32 { switch self { case let .item(item): return item.id; case let .placeholder(id): return id } }
        init?(apiStoryItem: Api.StoryItem, existingItem: Stories.Item? = nil, peerId: Int, transaction: Transaction) {
            transaction.parseCount += 1
            switch apiStoryItem {
            case let .storyItem(data):
                var item = data.item
                if data.flags & (1 << 9) != 0, let existingItem { item.views = existingItem.views; item.myReaction = existingItem.myReaction; item.isMy = existingItem.isMy; item.forwardInfo = existingItem.forwardInfo }
                self = .item(item)
            case let .placeholder(id): self = .placeholder(id)
            case .deleted, .storyItemDeleted, .unsupported: return nil
            }
        }
    }
}

final class ValueBoxKey: Hashable {
    let length: Int; var fields: [Int: Int64] = [:]
    init(length: Int) { self.length = length }
    func setInt64(_ offset: Int, value: Int64) { fields[offset] = value }
    func setInt8(_ offset: Int, value: Int8) { fields[offset] = Int64(value) }
    func getInt8(_ offset: Int) -> Int8 { Int8(fields[offset]!) }
    func getInt64(_ offset: Int) -> Int64 { fields[offset]! }
    static func ==(lhs: ValueBoxKey, rhs: ValueBoxKey) -> Bool { lhs.length == rhs.length && lhs.fields == rhs.fields }
    func hash(into hasher: inout Hasher) { hasher.combine(length); for k in fields.keys.sorted() { hasher.combine(k); hasher.combine(fields[k]) } }
}
struct ItemCacheEntryId: Hashable { let collectionId: Int; let key: ValueBoxKey }

struct StoryId: Hashable { let peerId: Int; let id: Int32 }
struct Folder: Equatable { let id: Int64; let title: String }
struct CachedPeerStoryListHead { let items: [Stories.StoredItem]; let pinnedIds: [Int32]; let totalCount: Int32; let folders: [Folder] }
enum InternalStoryUpdate { case updateViews(peerId: Int, views: [Int32: Stories.Item.Views]); case deleted(peerId: Int, id: Int32); case added(peerId: Int, item: Stories.StoredItem); case updateMyReaction(peerId: Int, id: Int32, reaction: MessageReaction.Reaction?) }
typealias AccountStateManager = StateManager
final class StateManager {
    var updates: [InternalStoryUpdate] = []
    var serverUpdates: [Api.Updates] = []
    var holdReplay = false
    var replayed = Set<Int>()
    var replayTransaction: Transaction?
    var reactionContext: StoryReactionContext?
    var storyReactionContext: StoryReactionContext? { reactionContext }
    var storyRefreshContext: StoryRefreshContext?
    var storyViewRefreshContext: StoryViewRefreshContext?
    private var replaySubscribers: [UUID: Subscriber<[Int], NoError>] = [:]
    var replayWaiters: Int { replaySubscribers.count }
    var onAddUpdates: (() -> Void)?
    func addUpdates(_ updates: Api.Updates) { serverUpdates.append(updates); onAddUpdates?() }
    func pollStateUpdateCompletion() -> Signal<[Int], NoError> {
        return Signal { subscriber in
            if !self.holdReplay { subscriber.putNext([]); subscriber.putCompletion(); return EmptyDisposable }
            let id = UUID(); self.replaySubscribers[id] = subscriber
            return ActionDisposable { [weak self] in self?.replaySubscribers.removeValue(forKey: id) }
        }
    }
    func replay(_ index: Int) {
        guard replayed.insert(index).inserted, let transaction = replayTransaction else { return }
        for item in serverUpdates[index].reactions {
            updates += replayReaction(transaction: transaction, peerId: item.peer, id: item.id, reaction: item.reaction, storyReactionContext: reactionContext)
        }
    }
    func finishReplay() {
        let subscribers = Array(replaySubscribers.values); replaySubscribers.removeAll()
        for subscriber in subscribers { subscriber.putNext([]); subscriber.putCompletion() }
    }
    var onUpdate: (() -> Void)?
    func injectStoryUpdates(updates: [InternalStoryUpdate]) { self.updates += updates; onUpdate?() }
}

typealias PeerId = Int
extension Int { func toInt64() -> Int64 { Int64(self) }; var namespace: Int { self >= 100 ? 1 : 0 } }
enum EnginePeer { typealias Id = Int }
enum Namespaces { enum CachedItemCollection { static let cachedPeerStoryListHeads = 1 }; enum Peer { static let CloudChannel = 1 } }
class Peer { let id: Int; init(id: Int) { self.id = id } }
final class TelegramUser: Peer { var storiesHidden: Bool? = false }
final class TelegramChannel: Peer { enum Status { case member }; let participationStatus = Status.member; var storiesHidden: Bool? = false }
final class TelegramGroup: Peer { enum Status { case Member }; let membership = Status.Member }
enum SubscriptionKey { case hidden, filtered }
func shouldKeepUserStoriesInFeed(peerId: Int, isContactOrMember: Bool) -> Bool { false }
struct CodableEntry: Equatable {
    let value: Any
    init(data: Data) { self.value = data }
    static func ==(lhs: CodableEntry, rhs: CodableEntry) -> Bool {
        if let a = lhs.value as? Stories.StoredItem, let b = rhs.value as? Stories.StoredItem { return a == b }
        if let a = lhs.value as? Data, let b = rhs.value as? Data { return a == b }
        return false
    }
    init?(_ value: Any) { self.value=value }
    func get<T>(_ type: T.Type) -> T? { value as? T }
}
extension Stories.StoredItem {
    var expirationTimestamp: Int { if case let .item(item)=self { return item.expirationTimestamp }; return 0 }
    var isCloseFriends: Bool { if case let .item(item)=self { return item.isCloseFriends }; return false }
    var isLiveStream: Bool { false }
}
extension Stories.Item.Views { init(apiViews: Stories.Item.Views) { self=apiViews } }
struct StoryItemsTableEntry: Equatable {
    let value: CodableEntry
    let id: Int32
    let expirationTimestamp: Int
    let isCloseFriends: Bool
    let isLiveStream: Bool
}
struct PeerStateRecord { let entry: CodableEntry }
final class Transaction {
    func isPeerContact(peerId: Int) -> Bool { false }
    func storySubscriptionsContains(key: SubscriptionKey, peerId: Int) -> Bool { false }
    func getAllStorySubscriptions(key: SubscriptionKey) -> (Int, [Int]) { (0, []) }
    func replaceAllStorySubscriptions(key: SubscriptionKey, state: Int, peerIds: [Int]) {}
    var parseCount = 0
    var peerStates: [Int: PeerStateRecord] = [:]
    var peerStateWrites = 0
    func getPeerStoryState(peerId: Int) -> PeerStateRecord? { peerStates[peerId] }
    func setPeerStoryState(peerId: Int, state: PeerStateRecord) { peerStates[peerId] = state; peerStateWrites += 1 }
    var peers = [10:Peer(id: 10),100:Peer(id: 100)]
    var rows: [Int:[StoryItemsTableEntry]] = [:]
    var stories: [StoryId: CodableEntry] = [:]
    var cache: [ItemCacheEntryId: CodableEntry] = [:]
    var storyWrites = 0
    var cacheWrites = 0
    func getStory(id: StoryId) -> CodableEntry? { stories[id] }
    func setStory(id: StoryId, value: CodableEntry) { stories[id] = value; storyWrites += 1 }
    func retrieveItemCacheEntry(id: ItemCacheEntryId) -> CodableEntry? { cache[id] }
    func putItemCacheEntry(id: ItemCacheEntryId, entry: CodableEntry) { cache[id] = entry; cacheWrites += 1 }
    var writes=0
    var peerUpdates=0
    func getPeer(_ id: Int) -> Peer? { peers[id] }
    func getStoryItems(peerId: Int) -> [StoryItemsTableEntry] { rows[peerId] ?? [] }
    func setStoryItems(peerId: Int, items: [StoryItemsTableEntry]) { rows[peerId]=items; writes+=1 }
}
final class Postbox {
    final class Pending {
        var active=true
        let run: ()->Void
        init(_ run: @escaping ()->Void) { self.run=run }
        func deliver() { if active { active=false; run() } }
    }
    let storage: Transaction
    init(storage: Transaction = Transaction()) { self.storage = storage }
    var count=0
    var onCancel: (() -> Void)?
    var afterTransaction: (() -> Void)?
    var delayAt:Set<Int>=[]
    var pending:[Pending]=[]
    func transaction<T>(_ f: @escaping (Transaction)->T) -> Signal<T,NoError> {
        Signal { subscriber in
            self.count+=1
            let run={ let value = f(self.storage); self.afterTransaction?(); subscriber.putNext(value); subscriber.putCompletion() }
            if self.delayAt.contains(self.count) {
                let pending=Pending(run); self.pending.append(pending)
                return ActionDisposable { pending.active=false; self.onCancel?() }
            }
            run(); return EmptyDisposable
        }
    }
    func flush() { for p in pending { p.deliver() } }
}

struct MTRpcError: Error { var errorDescription = "GENERIC" }
struct MessageReaction: Equatable {
    enum Reaction: Equatable { case builtin(String), custom(Int64), stars
        var apiReaction: Api.Reaction {
            switch self { case let .builtin(s): return .builtin(s); case let .custom(id): return .custom(id); case .stars: return .paid }
        }
    }
    var value: Reaction
    var count: Int32
    var chosenOrder: Int?
}
struct FullStoryRequestData { let peer: Int; let ids: [Int32] }
struct PeerReference {
    let inputPeer: Api.InputPeer
    var id: Int { inputPeer.id }
    init?(_ peer: Peer) { guard peer.id > 0 else { return nil }; inputPeer = .init(id: peer.id) }
}
struct AccumulatedPeers {
    var peers: [Int: Peer] = [:]
    init(peers: [Peer]) { self.peers = Dictionary(uniqueKeysWithValues: peers.map { ($0.id, $0) }) }
    func get(_ id: Int) -> Peer? { peers[id] }
    init(transaction: Transaction, chats: [Int], users: [Int]) {}
    init(users: [Int]) {}
}
func updatePeers(transaction: Transaction, accountPeerId: Int, peers: AccumulatedPeers) { transaction.peerUpdates += 1 }
enum FetchMessageHistoryHoleSource {
    case network(Network)
    func request(_ data: FullStoryRequestData, automaticFloodWait: Bool) -> Signal<Api.stories.Stories, MTRpcError> {
        switch self { case let .network(network): return network.request(data, automaticFloodWait: automaticFloodWait) }
    }
}
final class FullStoryRequest {
    let data: FullStoryRequestData
    var subscriber: Subscriber<Api.stories.Stories, MTRpcError>?
    var canceled = false
    init(_ data: FullStoryRequestData) { self.data = data }
    func succeed(_ stories: [Api.StoryItem]) { subscriber?.putNext(.stories(.init(stories: stories, chats: [], users: []))); subscriber?.putCompletion() }
    func fail() { subscriber?.putError(.init()) }
}
typealias ModeledStoryViews = Stories.Item.Views
enum Api {
    enum Reaction: Equatable { case reactionEmpty, builtin(String), custom(Int64), paid }
    struct DeletedStory { let id: Int32 }
    struct StoryData { let flags: Int32; let item: Stories.Item }
    enum StoryItem { case storyItem(StoryData), placeholder(Int32), deleted, storyItemDeleted(DeletedStory), unsupported(Int32)
        static func item(_ item: Stories.Item) -> Self { .storyItem(.init(flags: 0, item: item)) }
        static func min(_ item: Stories.Item) -> Self { .storyItem(.init(flags: 1 << 9, item: item)) }
        var id: Int32 { switch self { case let .storyItem(data): return data.item.id; case let .placeholder(id), let .unsupported(id): return id; case let .storyItemDeleted(value): return value.id; case .deleted: return 0 } }
    }
    struct InputPeer { let id: Int }
    struct ReactionUpdate: Equatable { let peer: Int; let id: Int32; let reaction: Reaction }
    struct Updates: Equatable { let id: Int; var reactions: [ReactionUpdate] = [] }
    struct PeerStoriesData { let peer: PeerValue; let maxReadId: Int32?; let stories: [StoryItem] }
    struct PeerValue { let peerId: Int }
    enum PeerStories { case peerStories(PeerStoriesData) }
    enum stories {
        struct PeerStoriesResult { let stories: Api.PeerStories; var chats: [Int] = []; var users: [Int] = [] }
        enum PeerStories { case peerStories(PeerStoriesResult) }
        struct CountResult { let views: [ModeledStoryViews]; var users: [Int] = [] }
        enum StoryViews { case storyViews(CountResult) }
        struct StoryResult { let stories: [StoryItem]; let chats: [Int]; let users: [Int] }
        enum Stories { case stories(StoryResult) }
    }
    enum functions { enum stories {
        static func getPeerStories(peer: InputPeer) -> PollRequestData { .init(peer: peer.id) }
        static func getStoriesViews(peer: InputPeer, id: [Int32]) -> CountRequestData { .init(peer: peer.id, ids: id) }
        static func getStoriesByID(peer: InputPeer, id: [Int32]) -> FullStoryRequestData { .init(peer: peer.id, ids: id) }
        static func sendReaction(flags: Int32, peer: InputPeer, storyId: Int32, reaction: Reaction) -> RequestData {
            .init(flags: flags, peer: peer.id, storyId: storyId, reaction: reaction)
        }
    } }
}
struct RequestData { let flags: Int32; let peer: Int; let storyId: Int32; let reaction: Api.Reaction }
func apiInputPeer(_ peer: Peer) -> Api.InputPeer? { peer.id > 0 ? .init(id: peer.id) : nil }
protocol NetworkRequestDependencyTag { func shouldDependOn(other: NetworkRequestDependencyTag) -> Bool }
struct WrappedRequestMetadata { let tag: NetworkRequestDependencyTag? }
__NETWORK_DEPENDENCY__
__DEPENDENCY_INDEX__
final class Request {
    let tag: NetworkRequestDependencyTag?
    let data: RequestData
    var subscriber: Subscriber<Api.Updates, MTRpcError>?
    var canceled = false
    init(_ data: RequestData, tag: NetworkRequestDependencyTag?) { self.data = data; self.tag = tag }
    func succeed(reactions: [Api.ReactionUpdate] = []) { subscriber?.putNext(.init(id: 7, reactions: reactions)); subscriber?.putCompletion() }
    func fail(_ description: String = "GENERIC") { subscriber?.putError(.init(errorDescription: description)) }
}
struct CountRequestData { let peer: Int; let ids: [Int32] }
final class CountRequest {
    let data: CountRequestData
    var subscriber: Subscriber<Api.stories.StoryViews, MTRpcError>?
    init(_ data: CountRequestData) { self.data = data }
    func succeed(_ views: [Stories.Item.Views]) { subscriber?.putNext(.storyViews(.init(views: views))); subscriber?.putCompletion() }
    func fail() { subscriber?.putError(.init()) }
}
struct PollRequestData { let peer: Int }
final class PollRequest {
    var subscriber: Subscriber<Api.stories.PeerStories, MTRpcError>?
    func succeed(_ stories: [Api.StoryItem]) {
        subscriber?.putNext(.peerStories(.init(stories: .peerStories(.init(peer: .init(peerId: 100), maxReadId: nil, stories: stories)))))
        subscriber?.putCompletion()
    }
}
final class Network {
    var pollRequests: [PollRequest] = []
    func request(_ data: PollRequestData) -> Signal<Api.stories.PeerStories, MTRpcError> {
        Signal { subscriber in
            let request = PollRequest(); request.subscriber = subscriber; self.pollRequests.append(request)
            return ActionDisposable { request.subscriber = nil }
        }
    }
    var countRequests: [CountRequest] = []
    func request(_ data: CountRequestData) -> Signal<Api.stories.StoryViews, MTRpcError> {
        Signal { subscriber in
            let request = CountRequest(data); request.subscriber = subscriber; self.countRequests.append(request)
            return ActionDisposable { request.subscriber = nil }
        }
    }
    var fullRequests: [FullStoryRequest] = []
    var onFullRequest: ((FullStoryRequest) -> Void)?
    func request(_ data: FullStoryRequestData, automaticFloodWait: Bool = true) -> Signal<Api.stories.Stories, MTRpcError> {
        Signal { subscriber in
            let request = FullStoryRequest(data); request.subscriber = subscriber; self.fullRequests.append(request); self.onFullRequest?(request)
            return ActionDisposable { request.canceled = true; request.subscriber = nil }
        }
    }
    var requests: [Request] = []
    var onRequest: ((Request) -> Void)?
    func request(_ data: RequestData, tag: NetworkRequestDependencyTag? = nil) -> Signal<Api.Updates, MTRpcError> {
        Signal { subscriber in
            let request = Request(data, tag: tag); request.subscriber = subscriber
            self.requests.append(request); self.onRequest?(request)
            return ActionDisposable { request.canceled = true; request.subscriber = nil }
        }
    }
}
__SUPPORT__
__VIEWS_CONTEXT__
final class Account { let storyReactionReconciliationContext = StoryReactionReconciliationContext(); let storyRefreshContext = StoryRefreshContext(); let storyReactionContext = StoryReactionContext(); let storyViewRefreshContext = StoryViewRefreshContext(); let peerId = 10; let postbox = Postbox(); let network = Network(); let stateManager = StateManager(); init() { stateManager.replayTransaction = postbox.storage; stateManager.reactionContext = storyReactionContext; stateManager.storyRefreshContext = storyRefreshContext; stateManager.storyViewRefreshContext = storyViewRefreshContext } }
__COUNT_REQUEST__
final class Messages {
    let account: Account
    init(_ account: Account) { self.account = account }
__COUNT_REFRESH__
}
__MEDIA_FETCH__
__RESOLVE__
__GET_STORIES__
__REFRESH__
__REDUCER__
__SET__
__STARS__

private let heart = MessageReaction.Reaction.builtin("❤️")
private let fire = MessageReaction.Reaction.builtin("🔥")
private func bucket(_ value: MessageReaction.Reaction, _ count: Int32, selected: Bool = false) -> MessageReaction {
    .init(value: value, count: count, chosenOrder: selected ? 0 : nil)
}
private func views(_ reacted: Int = 2, _ reactions: [MessageReaction] = []) -> Stories.Item.Views {
    .init(seenCount: 20, reactedCount: reacted, forwardCount: 4, seenPeerIds: [11, 12], reactions: reactions, hasList: true)
}
private func reduce(_ initial: Stories.Item.Views?, _ previous: MessageReaction.Reaction?, _ next: MessageReaction.Reaction?, channel: Bool = true, count: Int = 1) -> Stories.Item.Views? {
    _internal_updateStoryViewsForMyReaction(isChannel: channel, views: initial, previousReaction: previous, reaction: next, addedCount: count)
}

final class StoryReactionCounterTests: XCTestCase {
    func testUserStoryCountersRemainServerOwned() {
        let initial = views(2, [bucket(heart, 2)])
        XCTAssertEqual(reduce(initial, heart, fire, channel: false), initial)
        XCTAssertNil(reduce(nil, nil, heart, channel: false))
    }
    func testFirstChannelReactionIncrementsOneUserAndBucket() {
        let initial = views(2, [bucket(heart, 2)])
        var expected = initial; expected.reactedCount = 3; expected.reactions = [bucket(heart, 3, selected: true)]
        XCTAssertEqual(reduce(initial, nil, heart), expected)
    }
    func testSwitchUsesPreviousReactionWithoutChosenMarker() {
        let initial = views(3, [bucket(heart, 2), bucket(fire, 1)])
        var expected = initial; expected.reactions = [bucket(heart, 1), bucket(fire, 2, selected: true)]
        XCTAssertEqual(reduce(initial, heart, fire), expected)
    }
    func testRemovalUsesPreviousReactionWithoutChosenMarker() {
        let initial = views(3, [bucket(heart, 2), bucket(fire, 1)])
        var expected = initial; expected.reactedCount = 2; expected.reactions = [bucket(heart, 1), bucket(fire, 1)]
        XCTAssertEqual(reduce(initial, heart, nil), expected)
    }
    func testRepeatedReactionWithoutChosenMarkerIsIdempotent() {
        let initial = views(2, [bucket(heart, 2)])
        XCTAssertEqual(reduce(initial, heart, heart), initial)
    }
    func testRepeatedReactionWithChosenMarkerIsIdempotent() {
        let initial = views(2, [bucket(heart, 2, selected: true)])
        XCTAssertEqual(reduce(initial, heart, heart), initial)
    }
    func testServerEchoAfterOptimisticChangeDoesNotCountAgain() {
        let initial = views(2, [bucket(heart, 2)])
        let optimistic = reduce(initial, nil, fire)
        XCTAssertEqual(reduce(optimistic, fire, fire), optimistic)
        var withoutMarker = optimistic!; withoutMarker.reactions = withoutMarker.reactions.map { .init(value: $0.value, count: $0.count, chosenOrder: nil) }
        XCTAssertEqual(reduce(withoutMarker, fire, fire), withoutMarker)
    }
    func testSwitchRemovesEmptyPreviousBucket() {
        let initial = views(1, [bucket(heart, 1, selected: true)])
        var expected = initial; expected.reactions = [bucket(fire, 1, selected: true)]
        XCTAssertEqual(reduce(initial, heart, fire), expected)
    }
    func testRemoveLastReactionKeepsViewsAndViewerAvailability() {
        let initial = views(1, [bucket(heart, 1)])
        var expected = initial; expected.reactedCount = 0; expected.reactions = []
        XCTAssertEqual(reduce(initial, heart, nil), expected)
    }
    func testWrongChosenMarkerDoesNotSubtractAnotherReaction() {
        let initial = views(4, [bucket(fire, 3, selected: true), bucket(heart, 1)])
        var expected = initial; expected.reactions = [bucket(fire, 4, selected: true)]
        XCTAssertEqual(reduce(initial, heart, fire), expected)
    }
    func testMissingPreviousBucketDoesNotSubtractUnrelatedChosenBucket() {
        let initial = views(3, [bucket(fire, 3, selected: true)])
        var expected = initial; expected.reactedCount = 2; expected.reactions = [bucket(fire, 3)]
        XCTAssertEqual(reduce(initial, heart, nil), expected)
    }
    func testNewReactionClearsStaleMarkerWithoutSubtractingOtherCount() {
        let initial = views(3, [bucket(fire, 3, selected: true)])
        var expected = initial; expected.reactedCount = 4; expected.reactions = [bucket(fire, 3), bucket(heart, 1, selected: true)]
        XCTAssertEqual(reduce(initial, nil, heart), expected)
    }
    func testRepeatedRemovalIsIdempotent() {
        let initial = views(2, [bucket(fire, 2)])
        XCTAssertEqual(reduce(initial, nil, nil), initial)
        XCTAssertNil(reduce(nil, nil, nil))
    }
    func testCustomReactionSwitchUsesItsIdentity() {
        let old = MessageReaction.Reaction.custom(123), new = MessageReaction.Reaction.custom(124)
        let initial = views(5, [bucket(old, 4), bucket(new, 1)])
        var expected = initial; expected.reactions = [bucket(old, 3), bucket(new, 2, selected: true)]
        XCTAssertEqual(reduce(initial, old, new), expected)
    }
    func testNewReactionInitializesMissingChannelViews() {
        let result = reduce(nil, nil, heart)
        XCTAssertEqual(result?.reactedCount, 1); XCTAssertEqual(result?.reactions, [bucket(heart, 1, selected: true)])
    }
    func testEmptyViewsBecomeNilOnlyAfterActualRemoval() {
        let initial = Stories.Item.Views(reactedCount: 1, reactions: [bucket(heart, 1)])
        XCTAssertNil(reduce(initial, heart, nil))
        var retained = initial; retained.hasList = true
        XCTAssertEqual(reduce(retained, heart, nil)?.hasList, true)
    }
    func testOrdinaryReactionDoesNotConsumePaidBucket() {
        let initial = views(2, [bucket(.stars, 10, selected: true), bucket(heart, 1)])
        var expected = initial; expected.reactions = [bucket(.stars, 10, selected: true), bucket(fire, 1, selected: true)]
        XCTAssertEqual(reduce(initial, heart, fire), expected)
    }
    func testClearingPaidSelectionDoesNotUndoPaidCount() {
        let initial = views(2, [bucket(.stars, 10, selected: true)])
        XCTAssertEqual(reduce(initial, .stars, nil), initial)
    }
    func testPaidIncrementKeepsOrdinarySelection() {
        let initial = views(2, [bucket(heart, 1, selected: true), bucket(.stars, 10, selected: true)])
        var expected = initial; expected.reactions = [bucket(heart, 1, selected: true), bucket(.stars, 15, selected: true)]
        XCTAssertEqual(reduce(initial, heart, .stars, count: 5), expected)
    }
    func testZeroAndNegativePaidIncrementsAreNoOps() {
        let initial = views(2, [bucket(.stars, 10, selected: true)])
        XCTAssertEqual(reduce(initial, .stars, .stars, count: 0), initial)
        XCTAssertEqual(reduce(initial, .stars, .stars, count: -3), initial)
    }
}

final class StoryReactionMutationTests: XCTestCase {
    func row(_ item: Stories.StoredItem, id: Int32? = nil) -> StoryItemsTableEntry {
        .init(value: CodableEntry(item)!, id: id ?? item.id, expirationTimestamp: item.expirationTimestamp, isCloseFriends: item.isCloseFriends, isLiveStream: item.isLiveStream)
    }
    func stored(_ entry: CodableEntry?) -> Stories.Item? {
        if case let .item(item) = entry?.get(Stories.StoredItem.self) { return item }; return nil
    }
    func active(_ a: Account, peer: Int = 100) -> Stories.Item? { stored(a.postbox.storage.rows[peer]?.first?.value) }
    func individual(_ a: Account, peer: Int = 100) -> Stories.Item? { stored(a.postbox.storage.stories[.init(peerId: peer, id: 1)]) }
    func seed(_ a: Account, expired: Bool = false, edited: Bool = false, previous: MessageReaction.Reaction? = nil) -> (Stories.Item, Stories.Item) {
        var item = Stories.Item(id: 1, timestamp: 50, expirationTimestamp: 100, media: 42, alternativeMediaList: [43], mediaAreas: [44], text: "active", entities: [45], views: views(2, [bucket(heart, 2)]), privacy: 46, isPinned: false, isExpired: expired, isPublic: false, isCloseFriends: true, isContacts: true, isSelectedContacts: true, isForwardingDisabled: true, isEdited: edited, isMy: false, myReaction: previous, forwardInfo: .known(47, 2, true), music: 48, authorId: 49, folderIds: [7, 8])
        let active = item; a.postbox.storage.rows[100] = [row(.item(active))]
        item.text = "individual"; item.timestamp = 51; a.postbox.storage.stories[.init(peerId: 100, id: 1)] = CodableEntry(Stories.StoredItem.item(item))
        return (active, item)
    }
    func assertMetadata(_ actual: Stories.Item?, equals original: Stories.Item, file: StaticString = #filePath, line: UInt = #line) {
        guard var actual else { XCTFail("Missing story", file: file, line: line); return }
        actual.views = original.views; actual.myReaction = original.myReaction
        XCTAssertEqual(actual, original, file: file, line: line)
    }
    func testOrdinaryReactionPreservesAllExpirationAndEditedCombinations() {
        for expired in [false, true] { for edited in [false, true] {
            let a = Account(); let originals = seed(a, expired: expired, edited: edited)
            let d = _internal_setStoryReaction(account: a, peerId: 100, id: 1, reaction: fire).start()
            assertMetadata(active(a), equals: originals.0); assertMetadata(individual(a), equals: originals.1)
            XCTAssertEqual(active(a)?.myReaction, fire); XCTAssertEqual(individual(a)?.myReaction, fire); d.dispose()
        } }
    }
    func testPaidLocalMutationPreservesAllExpirationAndEditedCombinations() {
        for expired in [false, true] { for edited in [false, true] {
            let a = Account(); let originals = seed(a, expired: expired, edited: edited)
            let d = _internal_sendStoryStars(account: a, peerId: 100, id: 1, count: 2).start()
            assertMetadata(active(a), equals: originals.0); assertMetadata(individual(a), equals: originals.1)
            XCTAssertEqual(active(a)?.myReaction, .stars); d.dispose()
        } }
    }
    func testRepeatedReactionDoesNotWriteOrInflateCounts() {
        let a = Account(); let originals = seed(a, previous: heart)
        let d = _internal_setStoryReaction(account: a, peerId: 100, id: 1, reaction: heart).start()
        XCTAssertEqual(active(a), originals.0); XCTAssertEqual(individual(a), originals.1)
        XCTAssertEqual(a.postbox.storage.writes, 0); XCTAssertEqual(a.postbox.storage.storyWrites, 0)
        d.dispose()
    }
    func testRepeatedRemovalDoesNotWrite() {
        let a = Account(); _ = seed(a)
        let d = _internal_setStoryReaction(account: a, peerId: 100, id: 1, reaction: nil).start()
        XCTAssertEqual(a.postbox.storage.writes, 0); XCTAssertEqual(a.postbox.storage.storyWrites, 0); d.dispose()
    }
    func testMutationTargetsRequestedPeerOnly() {
        let a = Account(); let originals = seed(a)
        a.postbox.storage.rows[10] = [row(.item(originals.0))]
        a.postbox.storage.stories[.init(peerId: 10, id: 1)] = CodableEntry(Stories.StoredItem.item(originals.1))
        let d = _internal_setStoryReaction(account: a, peerId: 100, id: 1, reaction: fire).start()
        XCTAssertEqual(active(a, peer: 10), originals.0); XCTAssertEqual(individual(a, peer: 10), originals.1); d.dispose()
    }
    func testMismatchedStoredIdentityIsNotRewritten() {
        for paid in [false, true] {
            let a = Account(); let item = Stories.Item(id: 2, text: "wrong identity")
            a.postbox.storage.rows[100] = [row(.item(item), id: 1)]
            a.postbox.storage.stories[.init(peerId: 100, id: 1)] = CodableEntry(Stories.StoredItem.item(item))
            let d = (paid ? _internal_sendStoryStars(account: a, peerId: 100, id: 1, count: 2) : _internal_setStoryReaction(account: a, peerId: 100, id: 1, reaction: fire)).start()
            XCTAssertEqual(active(a), item); XCTAssertEqual(individual(a), item); XCTAssertEqual(a.postbox.storage.writes, 0); XCTAssertEqual(a.postbox.storage.storyWrites, 0); d.dispose()
        }
    }
    func testPlaceholdersDoNotBecomeStories() {
        let a = Account(); a.postbox.storage.rows[100] = [row(.placeholder(1))]
        a.postbox.storage.stories[.init(peerId: 100, id: 1)] = CodableEntry(Stories.StoredItem.placeholder(1))
        let d = _internal_setStoryReaction(account: a, peerId: 100, id: 1, reaction: fire).start()
        XCTAssertNil(active(a)); XCTAssertNil(individual(a)); XCTAssertEqual(a.postbox.storage.writes, 0); XCTAssertEqual(a.postbox.storage.storyWrites, 0); d.dispose()
    }
    func testInvalidStoryIdDoesNotMutateOrRequest() {
        for id: Int32 in [0, -1] {
            let a = Account(); _ = seed(a)
            let d = _internal_setStoryReaction(account: a, peerId: 100, id: id, reaction: fire).start()
            XCTAssertTrue(a.network.requests.isEmpty); XCTAssertTrue(a.stateManager.updates.isEmpty); XCTAssertEqual(a.postbox.count, 0); d.dispose()
        }
    }
    func testPaidReactionCannotUseOrdinarySendReactionRPC() {
        let a = Account(); let originals = seed(a)
        let d = _internal_setStoryReaction(account: a, peerId: 100, id: 1, reaction: .stars).start()
        XCTAssertEqual(active(a), originals.0); XCTAssertEqual(individual(a), originals.1); XCTAssertTrue(a.network.requests.isEmpty); XCTAssertTrue(a.stateManager.updates.isEmpty); d.dispose()
    }
    func testInvalidPaidAmountsDoNotMutate() {
        for count in [0, -1] {
            let a = Account(); let originals = seed(a)
            let d = _internal_sendStoryStars(account: a, peerId: 100, id: 1, count: count).start()
            XCTAssertEqual(active(a), originals.0); XCTAssertEqual(individual(a), originals.1); XCTAssertEqual(a.postbox.count, 0); XCTAssertTrue(a.stateManager.updates.isEmpty); d.dispose()
        }
    }
    func testMissingPeerDoesNotMutateOrRequest() {
        let a = Account(); let originals = seed(a); a.postbox.storage.peers.removeValue(forKey: 100)
        let d = _internal_setStoryReaction(account: a, peerId: 100, id: 1, reaction: fire).start()
        XCTAssertEqual(active(a), originals.0); XCTAssertEqual(individual(a), originals.1); XCTAssertTrue(a.network.requests.isEmpty); d.dispose()
    }
    func testSuccessForwardsServerUpdatesAndPreservesNewerCaption() {
        let a = Account(); _ = seed(a)
        let d = _internal_setStoryReaction(account: a, peerId: 100, id: 1, reaction: fire).start()
        var updated = active(a)!; updated.text = "edited during request"; a.postbox.storage.rows[100] = [row(.item(updated))]
        a.network.requests[0].succeed(); XCTAssertEqual(a.stateManager.serverUpdates, [.init(id: 7)]); XCTAssertEqual(active(a)?.text, "edited during request"); d.dispose()
    }
    func testReactionRPCUsesExactPeerStoryAndValue() {
        let a = Account(); _ = seed(a)
        let d = _internal_setStoryReaction(account: a, peerId: 100, id: 1, reaction: .custom(123)).start()
        let data = a.network.requests[0].data; XCTAssertEqual(data.peer, 100); XCTAssertEqual(data.storyId, 1); XCTAssertEqual(data.reaction, .custom(123)); XCTAssertEqual(data.flags, 0); d.dispose()
    }
    func testRemovingReactionSendsReactionEmpty() {
        let a = Account(); _ = seed(a, previous: heart)
        let d = _internal_setStoryReaction(account: a, peerId: 100, id: 1, reaction: nil).start()
        XCTAssertNil(active(a)?.myReaction); XCTAssertEqual(a.network.requests[0].data.reaction, .reactionEmpty); d.dispose()
    }
    func testCancellationDisposesNetworkRequest() {
        let a = Account(); _ = seed(a); var completed = 0
        let d = _internal_setStoryReaction(account: a, peerId: 100, id: 1, reaction: fire).start(completed: { completed += 1 })
        d.dispose(); XCTAssertTrue(a.network.requests[0].canceled); a.network.requests[0].succeed(); XCTAssertEqual(completed, 0); XCTAssertTrue(a.stateManager.serverUpdates.isEmpty)
    }
    func testSynchronousServerResponseCompletesOnce() {
        let a = Account(); _ = seed(a); a.network.onRequest = { $0.succeed() }; var completed = 0
        let d = _internal_setStoryReaction(account: a, peerId: 100, id: 1, reaction: fire).start(completed: { completed += 1 })
        XCTAssertEqual(completed, 1); XCTAssertEqual(a.stateManager.serverUpdates.count, 1); XCTAssertTrue(a.network.requests[0].canceled); d.dispose()
    }
    func testIndividualOnlyStoryDoesNotInvalidateActiveTable() {
        let a = Account(); let originals = seed(a); a.postbox.storage.rows.removeAll()
        let d = _internal_setStoryReaction(account: a, peerId: 100, id: 1, reaction: fire).start()
        XCTAssertEqual(a.postbox.storage.writes, 0); XCTAssertEqual(individual(a)?.myReaction, fire)
        assertMetadata(individual(a), equals: originals.1); d.dispose()
    }
    func testCancelReleasesReactionAccount() {
        var a: Account? = Account(); _ = seed(a!); weak var weakAccount = a
        let d = _internal_setStoryReaction(account: a!, peerId: 100, id: 1, reaction: fire).start()
        a = nil; d.dispose(); XCTAssertNil(weakAccount)
    }
    func testCompletionReleasesReactionAccount() {
        var a: Account? = Account(); _ = seed(a!); weak var weakAccount = a
        let d = _internal_setStoryReaction(account: a!, peerId: 100, id: 1, reaction: fire).start()
        let request = a!.network.requests[0]; a = nil; request.succeed(); XCTAssertNil(weakAccount); withExtendedLifetime(d) {}
    }

}

final class StoryReactionOverflowTests: XCTestCase {
    func testFullReactionBucketSaturatesInsteadOfCrashing() {
        let initial = views(2, [bucket(heart, Int32.max)])
        XCTAssertEqual(reduce(initial, nil, heart)?.reactions.first?.count, Int32.max)
    }
    func testFullReactedCountSaturatesInsteadOfCrashing() {
        let initial = views(Int.max)
        XCTAssertEqual(reduce(initial, nil, heart)?.reactedCount, Int.max)
    }
    func testMinimumBucketRemovalDoesNotUnderflow() {
        let initial = views(1, [bucket(heart, Int32.min, selected: true)])
        XCTAssertEqual(reduce(initial, heart, nil)?.reactions, [])
    }
    func testMinimumReactedCountRemovalDoesNotUnderflow() {
        let initial = views(Int.min, [bucket(heart, 1, selected: true)])
        XCTAssertEqual(reduce(initial, heart, nil)?.reactedCount, 0)
    }
    func testPaidIncrementSaturatesFullBucket() {
        let initial = views(2, [bucket(.stars, Int32.max - 1, selected: true)])
        XCTAssertEqual(reduce(initial, .stars, .stars, count: 2)?.reactions.first?.count, Int32.max)
    }
    func testOversizedPaidIncrementDoesNotTrap() {
        let initial = views(2, [bucket(.stars, 10, selected: true)])
        XCTAssertEqual(reduce(initial, .stars, .stars, count: Int.max), initial)
        XCTAssertEqual(reduce(initial, .stars, .stars, count: Int.min), initial)
    }
    func testOversizedPaidRequestDoesNotMutateOrTrap() {
        let a = Account(); let item = Stories.Item(id: 1, views: views())
        a.postbox.storage.stories[.init(peerId: 100, id: 1)] = CodableEntry(Stories.StoredItem.item(item))
        let d = _internal_sendStoryStars(account: a, peerId: 100, id: 1, count: Int(Int32.max) + 1).start()
        XCTAssertEqual(a.postbox.count, 0); XCTAssertEqual(a.postbox.storage.storyWrites, 0); d.dispose()
    }

}

extension StoryReactionMutationTests {
    func testRejectedReactionRestoresPreviousSelectionAndCounts() {
        let a = Account(); let original = seed(a, previous: heart)
        let d = _internal_setStoryReaction(account: a, peerId: 100, id: 1, reaction: fire).start()
        XCTAssertEqual(active(a)?.myReaction, fire); a.network.requests[0].fail()
        var expectedActive=original.0; var expectedIndividual=original.1
        expectedActive.views?.reactions=[bucket(heart,2,selected:true)]; expectedIndividual.views?.reactions=[bucket(heart,2,selected:true)]
        XCTAssertEqual(active(a), expectedActive); XCTAssertEqual(individual(a), expectedIndividual)
        XCTAssertFalse(a.storyReactionContext.isPending(.init(peerId: 100, id: 1))); d.dispose()
    }
    func testRejectedFirstReactionRestoresKnownNilSelection() {
        let a = Account(); let original = seed(a)
        let d = _internal_setStoryReaction(account: a, peerId: 100, id: 1, reaction: fire).start()
        a.network.requests[0].fail(); XCTAssertEqual(active(a), original.0); XCTAssertEqual(individual(a), original.1); d.dispose()
    }
    func testOlderFailureDoesNotUndoNewerPendingReaction() {
        let a = Account(); _ = seed(a)
        let first = _internal_setStoryReaction(account: a, peerId: 100, id: 1, reaction: heart).start()
        let second = _internal_setStoryReaction(account: a, peerId: 100, id: 1, reaction: fire).start()
        a.network.requests[0].fail(); XCTAssertEqual(active(a)?.myReaction, fire)
        a.network.requests[1].succeed(); XCTAssertEqual(active(a)?.myReaction, fire)
        XCTAssertFalse(a.storyReactionContext.isPending(.init(peerId: 100, id: 1))); first.dispose(); second.dispose()
    }
    func testAllOverlappingFailuresRestoreOriginalBaseline() {
        for newestFirst in [false, true] {
            let a = Account(); let original = seed(a)
            let first = _internal_setStoryReaction(account: a, peerId: 100, id: 1, reaction: heart).start()
            let second = _internal_setStoryReaction(account: a, peerId: 100, id: 1, reaction: fire).start()
            a.network.requests[newestFirst ? 1 : 0].fail(); a.network.requests[newestFirst ? 0 : 1].fail()
            XCTAssertEqual(active(a), original.0); XCTAssertEqual(individual(a), original.1); first.dispose(); second.dispose()
        }
    }
    func testLatestFailureRestoresEarlierSuccessfulReaction() {
        let a = Account(); _ = seed(a)
        let first = _internal_setStoryReaction(account: a, peerId: 100, id: 1, reaction: heart).start()
        let second = _internal_setStoryReaction(account: a, peerId: 100, id: 1, reaction: fire).start()
        a.network.requests[0].succeed(); a.network.requests[1].fail()
        XCTAssertEqual(active(a)?.myReaction, heart); XCTAssertEqual(individual(a)?.myReaction, heart); first.dispose(); second.dispose()
    }
    func testOlderFailureAfterNewerSuccessDoesNotRollback() {
        let a = Account(); _ = seed(a)
        let first = _internal_setStoryReaction(account: a, peerId: 100, id: 1, reaction: heart).start()
        let second = _internal_setStoryReaction(account: a, peerId: 100, id: 1, reaction: fire).start()
        a.network.requests[1].succeed(); a.network.requests[0].fail()
        XCTAssertEqual(active(a)?.myReaction, fire); XCTAssertEqual(a.stateManager.updates.count, 2); first.dispose(); second.dispose()
    }
    func testCancellationRestoresOptimisticState() {
        let a = Account(); let original = seed(a)
        let d = _internal_setStoryReaction(account: a, peerId: 100, id: 1, reaction: fire).start()
        d.dispose(); XCTAssertEqual(active(a), original.0); XCTAssertEqual(individual(a), original.1)
        XCTAssertFalse(a.storyReactionContext.isPending(.init(peerId: 100, id: 1)))
    }
    func testCancelOlderPendingReactionKeepsNewerIntent() {
        let a = Account(); _ = seed(a)
        let first = _internal_setStoryReaction(account: a, peerId: 100, id: 1, reaction: heart).start()
        let second = _internal_setStoryReaction(account: a, peerId: 100, id: 1, reaction: fire).start()
        first.dispose(); XCTAssertEqual(active(a)?.myReaction, fire); a.network.requests[1].succeed(); second.dispose()
    }
    func testQueuedInitialMutationCannotRunAfterCancellation() {
        let a = Account(); let original = seed(a); a.postbox.delayAt = [1]
        let d = _internal_setStoryReaction(account: a, peerId: 100, id: 1, reaction: fire).start()
        let queued = a.postbox.pending[0]; d.dispose(); queued.run()
        XCTAssertEqual(active(a), original.0); XCTAssertEqual(individual(a), original.1); XCTAssertTrue(a.network.requests.isEmpty)
    }
    func testFailurePatchesCurrentCaptionAndPrivacyRatherThanOldSnapshot() {
        let a = Account(); _ = seed(a)
        let d = _internal_setStoryReaction(account: a, peerId: 100, id: 1, reaction: fire).start()
        var current = active(a)!; current.text = "new caption"; current.privacy = 999; current.folderIds = [9]
        a.postbox.storage.rows[100] = [row(.item(current))]; a.network.requests[0].fail()
        XCTAssertNil(active(a)?.myReaction); XCTAssertEqual(active(a)?.text, "new caption"); XCTAssertEqual(active(a)?.privacy, 999); XCTAssertEqual(active(a)?.folderIds, [9]); d.dispose()
    }
    func testFailureDoesNotOverwriteIndependentAuthoritativeReaction() {
        let a = Account(); _ = seed(a)
        let d = _internal_setStoryReaction(account: a, peerId: 100, id: 1, reaction: fire).start()
        var current = active(a)!; current.myReaction = .custom(77)
        a.postbox.storage.rows[100] = [row(.item(current))]; a.postbox.storage.stories[.init(peerId: 100, id: 1)] = CodableEntry(Stories.StoredItem.item(current))
        a.network.requests[0].fail(); XCTAssertEqual(active(a)?.myReaction, .custom(77)); XCTAssertEqual(a.stateManager.updates.count, 1); d.dispose()
    }
    func testFailureCannotResurrectDeletedStory() {
        let a = Account(); _ = seed(a)
        let d = _internal_setStoryReaction(account: a, peerId: 100, id: 1, reaction: fire).start()
        a.postbox.storage.rows.removeAll(); a.postbox.storage.stories.removeAll(); a.network.requests[0].fail()
        XCTAssertTrue(a.postbox.storage.rows.isEmpty); XCTAssertTrue(a.postbox.storage.stories.isEmpty); XCTAssertEqual(a.stateManager.updates.count, 2); d.dispose()
    }
    func testReactionNotificationsContainNoFullStorySnapshots() {
        let a = Account(); _ = seed(a)
        let d = _internal_setStoryReaction(account: a, peerId: 100, id: 1, reaction: fire).start(); a.network.requests[0].fail()
        var selections: [MessageReaction.Reaction?] = []
        for update in a.stateManager.updates {
            switch update { case .updateViews, .added, .deleted: XCTFail("Full story snapshot"); case let .updateMyReaction(peerId, id, reaction): XCTAssertEqual(peerId, 100); XCTAssertEqual(id, 1); selections.append(reaction) }
        }
        XCTAssertEqual(selections, [fire, nil]); d.dispose()
    }
    func testReactionInvalidatesCountsRequestedBeforeAndDuringMutation() {
        let a = Account(); _ = seed(a)
        let old = a.storyViewRefreshContext.begin(peerId: 100, ids: [1])
        let d = _internal_setStoryReaction(account: a, peerId: 100, id: 1, reaction: fire).start()
        XCTAssertTrue(a.storyViewRefreshContext.take([1: views()], for: old).isEmpty)
        let during = a.storyViewRefreshContext.begin(peerId: 100, ids: [1])
        a.network.requests[0].succeed()
        XCTAssertTrue(a.storyViewRefreshContext.take([1: views()], for: during).isEmpty)
        let fresh = a.storyViewRefreshContext.begin(peerId: 100, ids: [1]); XCTAssertEqual(a.storyViewRefreshContext.take([1: views()], for: fresh).count, 1); d.dispose()
    }
    func testEmptyNetworkCompletionRecoversOptimisticReaction() {
        let a = Account(); let original = seed(a)
        let d = _internal_setStoryReaction(account: a, peerId: 100, id: 1, reaction: fire).start()
        a.network.requests[0].subscriber?.putCompletion(); XCTAssertEqual(active(a), original.0); XCTAssertEqual(individual(a), original.1); d.dispose()
    }
    func testCompletionWaitsForRecoveryCommit() {
        let a = Account(); let original = seed(a); a.postbox.delayAt = [2]; var complete = 0
        let d = _internal_setStoryReaction(account: a, peerId: 100, id: 1, reaction: fire).start(completed: { complete += 1 })
        a.network.requests[0].fail(); XCTAssertEqual(complete, 0); XCTAssertEqual(active(a)?.myReaction, fire)
        a.postbox.flush(); XCTAssertEqual(complete, 1); XCTAssertEqual(active(a), original.0); d.dispose()
    }
    func testUnknownBaselineIsNotInventedOnFailure() {
        let a = Account()
        let d = _internal_setStoryReaction(account: a, peerId: 100, id: 1, reaction: fire).start(); a.network.requests[0].fail()
        XCTAssertTrue(a.postbox.storage.rows.isEmpty); XCTAssertTrue(a.postbox.storage.stories.isEmpty)
        XCTAssertEqual(a.stateManager.updates.count, 1); XCTAssertFalse(a.storyReactionContext.isPending(.init(peerId: 100, id: 1))); d.dispose()
    }
    func testRepeatedSuccessDoesNotRetainPendingReactionState() {
        let a = Account(); _ = seed(a)
        for index in 0..<100 {
            let reaction = index % 2 == 0 ? heart : fire
            let d = _internal_setStoryReaction(account: a, peerId: 100, id: 1, reaction: reaction).start()
            XCTAssertTrue(a.storyReactionContext.isPending(.init(peerId: 100, id: 1))); a.network.requests.last?.succeed()
            XCTAssertFalse(a.storyReactionContext.isPending(.init(peerId: 100, id: 1))); d.dispose()
        }
    }
}

extension StoryReactionMutationTests {
    func testUnstoredViewerReactionUsesKnownPreviousSelection() {
        let a=Account()
        let d=_internal_setStoryReaction(account:a,peerId:100,id:1,reaction:fire,knownPreviousReaction:.some(heart)).start()
        a.network.requests[0].fail()
        if case let .updateMyReaction(_,_,reaction)=a.stateManager.updates.last { XCTAssertEqual(reaction,heart) } else { XCTFail() }
        XCTAssertEqual(a.stateManager.updates.count,2); XCTAssertTrue(a.postbox.storage.rows.isEmpty); XCTAssertTrue(a.postbox.storage.stories.isEmpty); d.dispose()
    }
    func testUnstoredViewerKnownNilIsDifferentFromUnknownBaseline() {
        let a=Account()
        let d=_internal_setStoryReaction(account:a,peerId:100,id:1,reaction:fire,knownPreviousReaction:.some(nil)).start()
        a.network.requests[0].fail()
        if case let .updateMyReaction(_,_,reaction)=a.stateManager.updates.last { XCTAssertNil(reaction) } else { XCTFail() }
        XCTAssertEqual(a.stateManager.updates.count,2); d.dispose()
    }
    func testStoredBaselineWinsOverOlderViewerReference() {
        let a=Account(); _=seed(a,previous:heart)
        let d=_internal_setStoryReaction(account:a,peerId:100,id:1,reaction:fire,knownPreviousReaction:.some(.custom(77))).start()
        a.network.requests[0].fail(); XCTAssertEqual(active(a)?.myReaction,heart); d.dispose()
    }
}

extension StoryReactionMutationTests {
    func testStoredKnownNilWinsOverOlderViewerReaction() {
        let a=Account(); _=seed(a)
        let d=_internal_setStoryReaction(account:a,peerId:100,id:1,reaction:fire,knownPreviousReaction:.some(heart)).start()
        a.network.requests[0].fail(); XCTAssertNil(active(a)?.myReaction); XCTAssertNil(individual(a)?.myReaction); d.dispose()
    }
}

extension StoryReactionMutationTests {
    func cacheKey(peer: Int = 100, archived: Int8 = 0, album: Int64? = nil) -> ItemCacheEntryId {
        let key = ValueBoxKey(length: album == nil ? 9 : 17)
        key.setInt64(0, value: Int64(peer)); key.setInt8(8, value: archived)
        if let album { key.setInt64(9, value: album) }
        return .init(collectionId: 1, key: key)
    }
    func cache(_ a: Account, key: ItemCacheEntryId, item: Stories.Item, folders: [Folder] = []) {
        a.postbox.storage.cache[key] = CodableEntry(CachedPeerStoryListHead(items: [.item(item), .placeholder(90)], pinnedIds: [90, item.id], totalCount: 57, folders: folders))
    }
    func cached(_ a: Account, key: ItemCacheEntryId) -> Stories.Item? {
        guard let value = a.postbox.storage.cache[key]?.get(CachedPeerStoryListHead.self), case let .item(item) = value.items.first else { return nil }
        return item
    }
    func testReactionUpdatesProfileArchiveAndDiscoveredAlbumCaches() {
        let a = Account(); let original = seed(a).0
        let keys = [cacheKey(), cacheKey(archived: 1), cacheKey(album: 7), cacheKey(archived: 1, album: 8)]
        for key in keys { var item = original; item.text = "cached"; cache(a, key: key, item: item) }
        let d = _internal_setStoryReaction(account: a, peerId: 100, id: 1, reaction: fire).start()
        for key in keys {
            XCTAssertEqual(cached(a, key: key)?.myReaction, fire)
            XCTAssertEqual(cached(a, key: key)?.views, reduce(original.views, nil, fire))
            XCTAssertEqual(cached(a, key: key)?.text, "cached")
            let head = a.postbox.storage.cache[key]?.get(CachedPeerStoryListHead.self)
            XCTAssertEqual(head?.pinnedIds, [90, 1]); XCTAssertEqual(head?.totalCount, 57); XCTAssertEqual(head?.items.count, 2)
        }
        a.network.requests[0].succeed(); d.dispose()
    }
    func testCacheOnlyStoryFailureRestoresCachedBaseline() {
        for previous: MessageReaction.Reaction? in [heart, nil] {
            let a = Account(); let item = Stories.Item(id: 1, views: views(2, [bucket(heart, 2)]), myReaction: previous)
            cache(a, key: cacheKey(), item: item)
            let d = _internal_setStoryReaction(account: a, peerId: 100, id: 1, reaction: fire).start()
            XCTAssertEqual(cached(a, key: cacheKey())?.myReaction, fire)
            a.network.requests[0].fail()
            XCTAssertEqual(cached(a, key: cacheKey())?.myReaction, previous)
            XCTAssertTrue(a.postbox.storage.rows.isEmpty); XCTAssertTrue(a.postbox.storage.stories.isEmpty); d.dispose()
        }
    }
    func testCurrentViewerBaselineTakesPrecedenceOverCacheOnlyBaseline() {
        let a = Account(); cache(a, key: cacheKey(), item: Stories.Item(id: 1, myReaction: heart))
        let d = _internal_setStoryReaction(account: a, peerId: 100, id: 1, reaction: fire, knownPreviousReaction: .some(nil)).start()
        a.network.requests[0].fail(); XCTAssertNil(cached(a, key: cacheKey())?.myReaction); d.dispose()
    }
    func testFailurePreservesFreshCacheMetadataAndIndependentReaction() {
        let a = Account(); _ = seed(a); cache(a, key: cacheKey(), item: Stories.Item(id: 1))
        let d = _internal_setStoryReaction(account: a, peerId: 100, id: 1, reaction: fire).start()
        var edited = cached(a, key: cacheKey())!; edited.text = "edited during RPC"; edited.folderIds = [9]; edited.privacy = 123
        cache(a, key: cacheKey(), item: edited)
        cache(a, key: cacheKey(archived: 1), item: Stories.Item(id: 1, myReaction: heart))
        a.network.requests[0].fail()
        XCTAssertNil(cached(a, key: cacheKey())?.myReaction); XCTAssertEqual(cached(a, key: cacheKey())?.text, edited.text)
        XCTAssertEqual(cached(a, key: cacheKey())?.folderIds, [9]); XCTAssertEqual(cached(a, key: cacheKey())?.privacy, 123)
        XCTAssertEqual(cached(a, key: cacheKey(archived: 1))?.myReaction, heart); d.dispose()
    }
    func testCacheTraversalFindsNestedDirectoriesAndTerminatesCycles() {
        let a = Account()
        cache(a, key: cacheKey(), item: Stories.Item(id: 2), folders: [.init(id: 7, title: "a")])
        cache(a, key: cacheKey(album: 7), item: Stories.Item(id: 3, folderIds: [8]))
        cache(a, key: cacheKey(album: 8), item: Stories.Item(id: 1, myReaction: heart, folderIds: [7]))
        let d = _internal_setStoryReaction(account: a, peerId: 100, id: 1, reaction: fire).start()
        XCTAssertEqual(cached(a, key: cacheKey(album: 8))?.myReaction, fire)
        a.network.requests[0].fail(); XCTAssertEqual(cached(a, key: cacheKey(album: 8))?.myReaction, heart); d.dispose()
    }
    func testCacheMissingAndPlaceholderEntriesAreNotInserted() {
        let a = Account(); _ = seed(a)
        a.postbox.storage.cache[cacheKey()] = CodableEntry(CachedPeerStoryListHead(items: [.placeholder(1)], pinnedIds: [], totalCount: 1, folders: []))
        let d = _internal_setStoryReaction(account: a, peerId: 100, id: 1, reaction: fire).start()
        a.network.requests[0].fail(); XCTAssertEqual(a.postbox.storage.cacheWrites, 0); XCTAssertEqual(a.postbox.storage.cache.count, 1); XCTAssertNil(cached(a, key: cacheKey())); d.dispose()
    }
    func testReactionCacheSameSelectionDoesNotWrite() {
        let a = Account(); _ = seed(a, previous: fire); cache(a, key: cacheKey(), item: Stories.Item(id: 1, myReaction: fire))
        let d = _internal_setStoryReaction(account: a, peerId: 100, id: 1, reaction: fire).start()
        a.network.requests[0].succeed(); XCTAssertEqual(a.postbox.storage.cacheWrites, 0); d.dispose()
    }
    func testReactionCacheTargetsExactPeerAndStory() {
        let a = Account(); _ = seed(a)
        cache(a, key: cacheKey(peer: 10), item: Stories.Item(id: 1, myReaction: heart))
        cache(a, key: cacheKey(), item: Stories.Item(id: 2, myReaction: heart))
        let d = _internal_setStoryReaction(account: a, peerId: 100, id: 1, reaction: fire).start()
        XCTAssertEqual(cached(a, key: cacheKey(peer: 10))?.myReaction, heart); XCTAssertEqual(cached(a, key: cacheKey())?.myReaction, heart)
        XCTAssertEqual(a.postbox.storage.cacheWrites, 0); d.dispose()
    }
    func testCancellationRollsBackCachesAndDoesNotRecreateDeletedHead() {
        let a = Account(); _ = seed(a); cache(a, key: cacheKey(), item: Stories.Item(id: 1)); cache(a, key: cacheKey(archived: 1), item: Stories.Item(id: 1))
        let d = _internal_setStoryReaction(account: a, peerId: 100, id: 1, reaction: fire).start()
        XCTAssertEqual(cached(a, key: cacheKey())?.myReaction, fire)
        a.postbox.storage.cache.removeValue(forKey: cacheKey(archived: 1)); d.dispose()
        XCTAssertNil(cached(a, key: cacheKey())?.myReaction); XCTAssertNil(a.postbox.storage.cache[cacheKey(archived: 1)])
    }
}

extension MessageReaction.Reaction {
    init?(apiReaction: Api.Reaction) {
        switch apiReaction { case .reactionEmpty: return nil; case let .builtin(value): self = .builtin(value); case let .custom(value): self = .custom(value); case .paid: self = .stars }
    }
}
enum ReplayOperation { case UpdateStorySentReaction(Int, Int32, Api.Reaction) }
func replayReaction(postbox: Postbox? = nil, transaction: Transaction, peerId: Int, id: Int32, reaction: Api.Reaction, storyReactionContext: StoryReactionContext? = nil, storyRefreshContext: StoryRefreshContext? = nil, storyViewRefreshContext: StoryViewRefreshContext? = nil) -> [InternalStoryUpdate] {
    let postbox = postbox ?? Postbox(storage: transaction)
    var storyUpdates: [InternalStoryUpdate] = []
    switch ReplayOperation.UpdateStorySentReaction(peerId, id, reaction) {
__REPLAY__
    }
    return storyUpdates
}
extension StoryReactionMutationTests {
    func assertPartial(_ events: [InternalStoryUpdate], peer: Int = 100, id: Int32 = 1, reaction: MessageReaction.Reaction?, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(events.count, 1, file: file, line: line)
        if case let .updateMyReaction(p, i, r) = events.first {
            XCTAssertEqual(p, peer, file: file, line: line); XCTAssertEqual(i, id, file: file, line: line); XCTAssertEqual(r, reaction, file: file, line: line)
        } else { XCTFail("Expected partial reaction event", file: file, line: line) }
    }
    func testServerReplayReachesProfileArchiveAndAlbumCaches() {
        let a = Account(); let original = seed(a).0
        let keys = [cacheKey(), cacheKey(archived: 1), cacheKey(album: 7)]
        for key in keys { cache(a, key: key, item: original) }
        let events = replayReaction(transaction: a.postbox.storage, peerId: 100, id: 1, reaction: .custom(27))
        for key in keys { XCTAssertEqual(cached(a, key: key)?.myReaction, .custom(27)); assertMetadata(cached(a, key: key), equals: original) }
        assertPartial(events, reaction: .custom(27))
    }
    func testServerReplayPreservesCurrentStoredMetadata() {
        let a = Account(); let originals = seed(a, expired: true, edited: false, previous: heart)
        let events = replayReaction(transaction: a.postbox.storage, peerId: 100, id: 1, reaction: .custom(27))
        assertMetadata(active(a), equals: originals.0); assertMetadata(individual(a), equals: originals.1)
        XCTAssertEqual(active(a)?.views, reduce(originals.0.views, heart, .custom(27))); assertPartial(events, reaction: .custom(27))
    }
    func testServerReplayPublishesForActiveOnlyStory() {
        let a = Account(); _ = seed(a); a.postbox.storage.stories.removeAll()
        assertPartial(replayReaction(transaction: a.postbox.storage, peerId: 100, id: 1, reaction: .builtin("🔥")), reaction: fire)
        XCTAssertEqual(active(a)?.myReaction, fire); XCTAssertTrue(a.postbox.storage.stories.isEmpty)
    }
    func testServerReplayForUnstoredViewerDoesNotCreateRecords() {
        let a = Account()
        assertPartial(replayReaction(transaction: a.postbox.storage, peerId: 100, id: 1, reaction: .reactionEmpty), reaction: nil)
        XCTAssertTrue(a.postbox.storage.rows.isEmpty); XCTAssertTrue(a.postbox.storage.stories.isEmpty); XCTAssertEqual(a.postbox.storage.writes, 0)
    }
    func testServerReplayDoesNotPublishFullStoryThatCanResurrectDeletedListItem() {
        let a = Account(); _ = seed(a)
        assertPartial(replayReaction(transaction: a.postbox.storage, peerId: 100, id: 1, reaction: .builtin("🔥")), reaction: fire)
    }
    func testServerReplayRejectsMismatchedStoredIdentity() {
        let a = Account(); let item = Stories.Item(id: 2, text: "another story", myReaction: heart)
        a.postbox.storage.rows[100] = [row(.item(item), id: 1)]; a.postbox.storage.stories[.init(peerId: 100, id: 1)] = CodableEntry(Stories.StoredItem.item(item))
        _ = replayReaction(transaction: a.postbox.storage, peerId: 100, id: 1, reaction: .builtin("🔥"))
        XCTAssertEqual(active(a), item); XCTAssertEqual(individual(a), item); XCTAssertEqual(a.postbox.storage.writes, 0); XCTAssertEqual(a.postbox.storage.storyWrites, 0)
    }
    func testRepeatedServerReplayAvoidsWritesAndCounterInflation() {
        let a = Account(); _ = seed(a)
        _ = replayReaction(transaction: a.postbox.storage, peerId: 100, id: 1, reaction: .builtin("🔥"))
        let current = active(a); let writes = a.postbox.storage.writes; let individualWrites = a.postbox.storage.storyWrites
        _ = replayReaction(transaction: a.postbox.storage, peerId: 100, id: 1, reaction: .builtin("🔥"))
        XCTAssertEqual(active(a), current); XCTAssertEqual(a.postbox.storage.writes, writes); XCTAssertEqual(a.postbox.storage.storyWrites, individualWrites)
    }
    func testServerReplayLeavesPlaceholdersAndOtherPeersUntouched() {
        let a = Account(); let item = Stories.Item(id: 1, myReaction: heart)
        a.postbox.storage.rows[10] = [row(.item(item))]; a.postbox.storage.rows[100] = [row(.placeholder(1))]
        _ = replayReaction(transaction: a.postbox.storage, peerId: 100, id: 1, reaction: .reactionEmpty)
        XCTAssertEqual(active(a, peer: 10), item); XCTAssertNil(active(a)); XCTAssertEqual(a.postbox.storage.writes, 0)
    }
    func testNotModifiedAcceptsSelectedReactionWithoutFakeUpdates() {
        let a = Account(); _ = seed(a, previous: heart); var complete = 0
        let d = _internal_setStoryReaction(account: a, peerId: 100, id: 1, reaction: fire).start(completed: { complete += 1 })
        a.network.requests[0].fail("STORY_NOT_MODIFIED")
        XCTAssertEqual(active(a)?.myReaction, fire); XCTAssertEqual(individual(a)?.myReaction, fire); XCTAssertTrue(a.stateManager.serverUpdates.isEmpty)
        XCTAssertEqual(complete, 1); XCTAssertFalse(a.storyReactionContext.isPending(.init(peerId: 100, id: 1))); d.dispose()
    }
    func testNotModifiedAcceptsReactionRemoval() {
        let a = Account(); _ = seed(a, previous: heart)
        let d = _internal_setStoryReaction(account: a, peerId: 100, id: 1, reaction: nil).start()
        a.network.requests[0].fail("STORY_NOT_MODIFIED"); XCTAssertNil(active(a)?.myReaction); XCTAssertEqual(active(a)?.views?.reactedCount, 1); d.dispose()
    }
    func testNotModifiedBecomesBaselineIfNewerIntentFails() {
        let a = Account(); _ = seed(a)
        let first = _internal_setStoryReaction(account: a, peerId: 100, id: 1, reaction: heart).start()
        let second = _internal_setStoryReaction(account: a, peerId: 100, id: 1, reaction: fire).start()
        a.network.requests[0].fail("STORY_NOT_MODIFIED"); XCTAssertEqual(active(a)?.myReaction, fire)
        a.network.requests[1].fail(); XCTAssertEqual(active(a)?.myReaction, heart); first.dispose(); second.dispose()
    }
    func testNotModifiedDoesNotOverrideNewerSuccess() {
        let a = Account(); _ = seed(a)
        let first = _internal_setStoryReaction(account: a, peerId: 100, id: 1, reaction: heart).start()
        let second = _internal_setStoryReaction(account: a, peerId: 100, id: 1, reaction: fire).start()
        a.network.requests[1].succeed(); a.network.requests[0].fail("STORY_NOT_MODIFIED"); XCTAssertEqual(active(a)?.myReaction, fire); first.dispose(); second.dispose()
    }
    func testSimilarErrorsStillRejectReaction() {
        for error in ["STORY_NOT_MODIFIED_OTHER", "STORY_NOT_FOUND", "REACTION_INVALID"] {
            let a = Account(); _ = seed(a, previous: heart)
            let d = _internal_setStoryReaction(account: a, peerId: 100, id: 1, reaction: fire).start()
            a.network.requests[0].fail(error); XCTAssertEqual(active(a)?.myReaction, heart); d.dispose()
        }
    }
}

extension StoryReactionMutationTests {
    func dependencyIndex(_ request: Request, previous: [Request]) -> Int? {
        guard let accepts = networkRequestDependency(tag: request.tag) else { return nil }
        return rustEngineDependencyIndex(candidates: previous, accepts: { accepts(.init(tag: $0.tag)) })
    }
    func testSameStoryRequestsDependOnLatestEarlierMatchingRequest() {
        let a = Account(); _ = seed(a)
        let first = _internal_setStoryReaction(account: a, peerId: 100, id: 1, reaction: heart).start()
        let second = _internal_setStoryReaction(account: a, peerId: 100, id: 1, reaction: fire).start()
        let other = _internal_setStoryReaction(account: a, peerId: 100, id: 2, reaction: heart).start()
        let last = _internal_setStoryReaction(account: a, peerId: 100, id: 1, reaction: .custom(123)).start()
        XCTAssertNil(dependencyIndex(a.network.requests[0], previous: []))
        XCTAssertEqual(dependencyIndex(a.network.requests[1], previous: Array(a.network.requests.prefix(1))), 0)
        XCTAssertEqual(dependencyIndex(a.network.requests[3], previous: Array(a.network.requests.prefix(3))), 1)
        for d in [first, second, other, last] { d.dispose() }
    }
    func testReactionRemovalDependsOnPendingSelection() {
        let a = Account(); _ = seed(a)
        let first = _internal_setStoryReaction(account: a, peerId: 100, id: 1, reaction: heart).start()
        let last = _internal_setStoryReaction(account: a, peerId: 100, id: 1, reaction: nil).start()
        XCTAssertEqual(dependencyIndex(a.network.requests[1], previous: [a.network.requests[0]]), 0); first.dispose(); last.dispose()
    }
    func testReactionDependenciesKeepOtherStoriesAndPeersIndependent() {
        let a = Account(); _ = seed(a)
        let first = _internal_setStoryReaction(account: a, peerId: 100, id: 1, reaction: heart).start()
        let otherStory = _internal_setStoryReaction(account: a, peerId: 100, id: 2, reaction: heart).start()
        let otherPeer = _internal_setStoryReaction(account: a, peerId: 10, id: 1, reaction: heart).start()
        XCTAssertNil(dependencyIndex(a.network.requests[1], previous: [a.network.requests[0]]))
        XCTAssertNil(dependencyIndex(a.network.requests[2], previous: Array(a.network.requests.prefix(2))))
        for d in [first, otherStory, otherPeer] { d.dispose() }
    }
    func testReactionDependencyIgnoresOtherRequestKinds() {
        struct Other: NetworkRequestDependencyTag { func shouldDependOn(other: NetworkRequestDependencyTag) -> Bool { true } }
        let a = Account(); _ = seed(a)
        let d = _internal_setStoryReaction(account: a, peerId: 100, id: 1, reaction: heart).start()
        guard let accepts = networkRequestDependency(tag: a.network.requests[0].tag) else { XCTFail("Missing dependency tag"); d.dispose(); return }
        XCTAssertFalse(accepts(.init(tag: Other()))); XCTAssertFalse(accepts(.init(tag: nil))); d.dispose()
    }
}

extension StoryReactionMutationTests {
    func testAcceptedReactionRemainsPendingUntilServerReplayCompletes() {
        let a = Account(); _ = seed(a); a.stateManager.holdReplay = true; var completed = 0
        let d = _internal_setStoryReaction(account: a, peerId: 100, id: 1, reaction: fire).start(completed: { completed += 1 })
        a.network.requests[0].succeed(reactions: [.init(peer: 100, id: 1, reaction: .builtin("🔥"))])
        XCTAssertEqual(completed, 0); XCTAssertTrue(a.storyReactionContext.isPending(.init(peerId: 100, id: 1)))
        a.stateManager.replay(0); a.stateManager.finishReplay()
        XCTAssertEqual(completed, 1); XCTAssertEqual(active(a)?.myReaction, fire); XCTAssertFalse(a.storyReactionContext.isPending(.init(peerId: 100, id: 1))); d.dispose()
    }
    func testOlderServerReplayPreservesNewerPendingSelectionAndFailureBaseline() {
        let a = Account(); _ = seed(a); a.stateManager.holdReplay = true
        let first = _internal_setStoryReaction(account: a, peerId: 100, id: 1, reaction: heart).start()
        let second = _internal_setStoryReaction(account: a, peerId: 100, id: 1, reaction: fire).start()
        a.network.requests[0].succeed(reactions: [.init(peer: 100, id: 1, reaction: .builtin("❤️"))]); a.stateManager.replay(0)
        XCTAssertEqual(active(a)?.myReaction, fire); assertPartial(Array(a.stateManager.updates.suffix(1)), reaction: fire)
        a.stateManager.finishReplay(); a.network.requests[1].fail()
        XCTAssertEqual(active(a)?.myReaction, heart); first.dispose(); second.dispose()
    }
    func testOlderSuccessAfterNewerReplayCannotRestoreOldSelection() {
        let a = Account(); _ = seed(a); a.stateManager.holdReplay = true
        let first = _internal_setStoryReaction(account: a, peerId: 100, id: 1, reaction: heart).start()
        let second = _internal_setStoryReaction(account: a, peerId: 100, id: 1, reaction: fire).start()
        a.network.requests[1].succeed(reactions: [.init(peer: 100, id: 1, reaction: .builtin("🔥"))]); a.stateManager.replay(0); a.stateManager.finishReplay()
        XCTAssertTrue(a.storyReactionContext.isPending(.init(peerId: 100, id: 1)))
        a.network.requests[0].succeed(reactions: [.init(peer: 100, id: 1, reaction: .builtin("❤️"))]); a.stateManager.replay(1)
        XCTAssertEqual(active(a)?.myReaction, fire); a.stateManager.finishReplay(); XCTAssertEqual(active(a)?.myReaction, fire)
        XCTAssertFalse(a.storyReactionContext.isPending(.init(peerId: 100, id: 1))); first.dispose(); second.dispose()
    }
    func testAcceptedRemovalSurvivesOlderReplay() {
        let a = Account(); _ = seed(a); a.stateManager.holdReplay = true
        let first = _internal_setStoryReaction(account: a, peerId: 100, id: 1, reaction: heart).start()
        let second = _internal_setStoryReaction(account: a, peerId: 100, id: 1, reaction: nil).start()
        a.network.requests[1].succeed(); a.stateManager.finishReplay()
        a.network.requests[0].succeed(reactions: [.init(peer: 100, id: 1, reaction: .builtin("❤️"))]); a.stateManager.replay(1); a.stateManager.finishReplay()
        XCTAssertNil(active(a)?.myReaction); first.dispose(); second.dispose()
    }
    func testNewIntentAfterNewerSuccessStillUsesAcceptedBaseline() {
        let a = Account(); _ = seed(a); a.stateManager.holdReplay = true
        let first = _internal_setStoryReaction(account: a, peerId: 100, id: 1, reaction: heart).start()
        let second = _internal_setStoryReaction(account: a, peerId: 100, id: 1, reaction: fire).start()
        a.network.requests[1].succeed(); a.stateManager.finishReplay()
        let third = _internal_setStoryReaction(account: a, peerId: 100, id: 1, reaction: .custom(12)).start()
        a.network.requests[0].succeed(reactions: [.init(peer: 100, id: 1, reaction: .builtin("❤️"))]); a.stateManager.replay(1); a.stateManager.finishReplay()
        XCTAssertEqual(active(a)?.myReaction, .custom(12)); a.network.requests[2].fail(); XCTAssertEqual(active(a)?.myReaction, fire)
        for d in [first, second, third] { d.dispose() }
    }
    func testReplayOfOtherStoryAndPeerRemainsAuthoritative() {
        let a = Account(); _ = seed(a); a.stateManager.holdReplay = true
        a.postbox.storage.rows[10] = [row(.item(Stories.Item(id: 1)))]; cache(a, key: cacheKey(), item: Stories.Item(id: 2))
        let d = _internal_setStoryReaction(account: a, peerId: 100, id: 1, reaction: fire).start()
        a.network.requests[0].succeed(reactions: [.init(peer: 10, id: 1, reaction: .custom(7)), .init(peer: 100, id: 2, reaction: .custom(8))]); a.stateManager.replay(0)
        XCTAssertEqual(active(a, peer: 10)?.myReaction, .custom(7)); XCTAssertEqual(cached(a, key: cacheKey())?.myReaction, .custom(8))
        a.stateManager.finishReplay(); d.dispose()
    }
    func testCancelAfterAcceptanceKeepsReplayProtectionUntilCommit() {
        let a = Account(); _ = seed(a); a.stateManager.holdReplay = true; var completed = 0
        let d = _internal_setStoryReaction(account: a, peerId: 100, id: 1, reaction: fire).start(completed: { completed += 1 })
        a.network.requests[0].succeed(reactions: [.init(peer: 100, id: 1, reaction: .builtin("🔥"))]); d.dispose()
        XCTAssertTrue(a.storyReactionContext.isPending(.init(peerId: 100, id: 1))); XCTAssertEqual(active(a)?.myReaction, fire)
        a.stateManager.replay(0); a.stateManager.finishReplay(); XCTAssertEqual(active(a)?.myReaction, fire)
        XCTAssertFalse(a.storyReactionContext.isPending(.init(peerId: 100, id: 1))); XCTAssertEqual(completed, 0); XCTAssertEqual(a.stateManager.replayWaiters, 0)
    }
    func testDisposedAcceptedRequestDoesNotRetainAccountWhileReplayWaits() {
        var a: Account? = Account(); _ = seed(a!); a!.stateManager.holdReplay = true; weak var weakAccount = a
        let manager = a!.stateManager
        let d = _internal_setStoryReaction(account: a!, peerId: 100, id: 1, reaction: fire).start()
        a!.network.requests[0].succeed(); d.dispose(); a = nil
        XCTAssertNil(weakAccount); manager.finishReplay(); XCTAssertEqual(manager.replayWaiters, 0); XCTAssertFalse(manager.reactionContext!.isPending(.init(peerId: 100, id: 1)))
    }
}

extension StoryReactionMutationTests {
    func testCancellationDuringSuccessfulUpdateHandoffKeepsAcceptedSelection() {
        let a = Account(); _ = seed(a); a.stateManager.holdReplay = true
        var d: Disposable?
        d = _internal_setStoryReaction(account: a, peerId: 100, id: 1, reaction: fire).start()
        a.stateManager.onAddUpdates = { d?.dispose() }
        a.network.requests[0].succeed(reactions: [.init(peer: 100, id: 1, reaction: .builtin("🔥"))])
        XCTAssertEqual(active(a)?.myReaction, fire); XCTAssertTrue(a.storyReactionContext.isPending(.init(peerId: 100, id: 1)))
        XCTAssertEqual(a.stateManager.replayWaiters, 1)
        a.stateManager.replay(0); a.stateManager.finishReplay()
        XCTAssertEqual(active(a)?.myReaction, fire); XCTAssertFalse(a.storyReactionContext.isPending(.init(peerId: 100, id: 1)))
        a.stateManager.onAddUpdates = nil; d = nil
    }
}

extension StoryReactionMutationTests {
    func testAcceptedCleanupDoesNotKeepStateManagerAfterAccountRelease() {
        var a: Account? = Account(); _ = seed(a!); a!.stateManager.holdReplay = true
        weak var manager = a!.stateManager
        let d = _internal_setStoryReaction(account: a!, peerId: 100, id: 1, reaction: fire).start()
        a!.network.requests[0].succeed(); d.dispose(); a = nil
        XCTAssertNil(manager)
    }
}

enum FullReplayOperation { case UpdateStory(Int, Api.StoryItem) }
func replayFullStory(postbox: Postbox? = nil, transaction: Transaction, peerId: Int, story: Api.StoryItem, storyReactionContext: StoryReactionContext? = nil, storyRefreshContext: StoryRefreshContext? = nil, storyViewRefreshContext: StoryViewRefreshContext? = nil) -> [InternalStoryUpdate] {
    let postbox = postbox ?? Postbox(storage: transaction)
    var storyUpdates: [InternalStoryUpdate] = []
    switch FullReplayOperation.UpdateStory(peerId, story) {
__FULL_REPLAY__
    }
    return storyUpdates
}
extension StoryReactionMutationTests {
    func publishedStory(_ events: [InternalStoryUpdate]) -> Stories.Item? {
        if case let .added(_, .item(item)) = events.first { return item }; return nil
    }
    func testMinimalStoryNotificationMatchesStoredMergedPayload() {
        let a = Account(); let original = seed(a, previous: heart).0
        let incoming = Stories.Item(id: 1, text: "new caption", views: nil, isMy: false)
        let events = replayFullStory(transaction: a.postbox.storage, peerId: 100, story: .min(incoming))
        XCTAssertEqual(publishedStory(events), active(a)); XCTAssertEqual(publishedStory(events)?.myReaction, heart)
        XCTAssertEqual(publishedStory(events)?.views, original.views); XCTAssertEqual(publishedStory(events)?.forwardInfo, original.forwardInfo)
        XCTAssertEqual(publishedStory(events)?.text, "new caption")
    }
    func testMinimalStoryUsesIndividualBaselineWhenActiveRowIsMissing() {
        let a = Account(); let original = seed(a, previous: heart).1; a.postbox.storage.rows.removeAll()
        let events = replayFullStory(transaction: a.postbox.storage, peerId: 100, story: .min(Stories.Item(id: 1, text: "new")))
        XCTAssertEqual(individual(a)?.myReaction, heart); XCTAssertEqual(individual(a)?.views, original.views)
        XCTAssertEqual(publishedStory(events), individual(a))
    }
    func testUnsupportedStoryMediaIsNotReportedAsDeletion() {
        let a = Account(); let original = seed(a)
        let events = replayFullStory(transaction: a.postbox.storage, peerId: 100, story: .unsupported(1))
        XCTAssertTrue(events.isEmpty); XCTAssertEqual(active(a), original.0); XCTAssertEqual(individual(a), original.1)
        XCTAssertEqual(a.postbox.storage.writes, 0); XCTAssertEqual(a.postbox.storage.storyWrites, 0); XCTAssertEqual(a.postbox.storage.peerStateWrites, 0)
    }
    func testServerStoryDeletionClearsIndividualRecordAndActiveRows() {
        let a = Account(); _ = seed(a)
        let events = replayFullStory(transaction: a.postbox.storage, peerId: 100, story: .storyItemDeleted(.init(id: 1)))
        XCTAssertTrue(a.postbox.storage.getStoryItems(peerId: 100).isEmpty); XCTAssertNil(individual(a))
        if case let .deleted(peer, id) = events.first { XCTAssertEqual(peer, 100); XCTAssertEqual(id, 1) } else { XCTFail("Missing deletion") }
    }
    func testServerDeletionRemovesAllDuplicateMatchingRows() {
        let a = Account(); _ = seed(a); a.postbox.storage.rows[100]!.append(a.postbox.storage.rows[100]![0])
        a.postbox.storage.rows[100]!.append(row(.item(Stories.Item(id: 2))))
        _ = replayFullStory(transaction: a.postbox.storage, peerId: 100, story: .storyItemDeleted(.init(id: 1)))
        XCTAssertEqual(a.postbox.storage.rows[100]?.map(\.id), [2])
    }
    func testSkippedStoryCannotDowngradeKnownFullPayload() {
        let a = Account(); let original = seed(a)
        let events = replayFullStory(transaction: a.postbox.storage, peerId: 100, story: .placeholder(1))
        XCTAssertEqual(active(a), original.0); XCTAssertEqual(individual(a), original.1)
        XCTAssertTrue(events.isEmpty); XCTAssertEqual(a.postbox.storage.writes, 0)
    }
    func testFullStoryUpdatePreservesPendingReactionAndCurrentCounts() {
        let a = Account(); _ = seed(a)
        let d = _internal_setStoryReaction(account: a, peerId: 100, id: 1, reaction: fire).start()
        let currentViews = active(a)?.views
        let incoming = Stories.Item(id: 1, media: 99, text: "edited remotely", views: views(20, [bucket(heart, 20)]), privacy: 17, myReaction: heart)
        let events = replayFullStory(transaction: a.postbox.storage, peerId: 100, story: .item(incoming), storyReactionContext: a.storyReactionContext)
        XCTAssertEqual(active(a)?.myReaction, fire); XCTAssertEqual(active(a)?.views, currentViews)
        XCTAssertEqual(active(a)?.text, incoming.text); XCTAssertEqual(active(a)?.media, 99); XCTAssertEqual(active(a)?.privacy, 17)
        XCTAssertEqual(publishedStory(events), active(a)); a.network.requests[0].fail(); XCTAssertNil(active(a)?.myReaction); XCTAssertEqual(active(a)?.text, incoming.text); d.dispose()
    }
    func testFullStoryUpdatePreservesPendingRemovalIncludingNilViews() {
        let a = Account(); a.postbox.storage.rows[100] = [row(.item(Stories.Item(id: 1, myReaction: heart)))]
        let d = _internal_setStoryReaction(account: a, peerId: 100, id: 1, reaction: nil).start()
        let events = replayFullStory(transaction: a.postbox.storage, peerId: 100, story: .item(Stories.Item(id: 1, views: views(), myReaction: heart)), storyReactionContext: a.storyReactionContext)
        XCTAssertNil(active(a)?.myReaction); XCTAssertNil(active(a)?.views); XCTAssertEqual(publishedStory(events), active(a)); d.dispose()
    }
    func testFullStoryForUnstoredPendingViewerUsesIncomingCountsOnce() {
        let a = Account()
        let d = _internal_setStoryReaction(account: a, peerId: 100, id: 1, reaction: fire, knownPreviousReaction: .some(nil)).start()
        let incoming = Stories.Item(id: 1, views: views(2, [bucket(heart, 2)]))
        _ = replayFullStory(transaction: a.postbox.storage, peerId: 100, story: .item(incoming), storyReactionContext: a.storyReactionContext)
        XCTAssertEqual(active(a)?.myReaction, fire); XCTAssertEqual(active(a)?.views, reduce(incoming.views, nil, fire)); d.dispose()
    }
    func testFullStoryUpdateForOtherPeerRemainsAuthoritative() {
        let a = Account(); _ = seed(a)
        let d = _internal_setStoryReaction(account: a, peerId: 100, id: 1, reaction: fire).start()
        let incoming = Stories.Item(id: 1, myReaction: heart)
        _ = replayFullStory(transaction: a.postbox.storage, peerId: 10, story: .item(incoming), storyReactionContext: a.storyReactionContext)
        XCTAssertEqual(active(a, peer: 10), incoming); d.dispose()
    }
    func testIdenticalFullStoryReplayDoesNotRewriteRecords() {
        let a = Account(); let incoming = Stories.Item(id: 1, text: "same")
        _ = replayFullStory(transaction: a.postbox.storage, peerId: 100, story: .item(incoming))
        let writes = a.postbox.storage.writes; let recordWrites = a.postbox.storage.storyWrites
        _ = replayFullStory(transaction: a.postbox.storage, peerId: 100, story: .item(incoming))
        XCTAssertEqual(a.postbox.storage.writes, writes); XCTAssertEqual(a.postbox.storage.storyWrites, recordWrites)
    }
    func testMismatchedStoredIdentityCannotSupplyMinimalFields() {
        let a = Account(); a.postbox.storage.rows[100] = [row(.item(Stories.Item(id: 2, myReaction: heart)), id: 1)]
        let events = replayFullStory(transaction: a.postbox.storage, peerId: 100, story: .min(Stories.Item(id: 1)))
        XCTAssertNil(active(a)?.myReaction); XCTAssertEqual(active(a)?.id, 1); XCTAssertEqual(publishedStory(events), active(a))
    }
    func testFullStoryReplayParsesOnceAndRetainsReadState() {
        let a = Account(); a.postbox.storage.peerStates[100] = Stories.PeerState(maxReadId: 50).postboxRepresentation
        _ = replayFullStory(transaction: a.postbox.storage, peerId: 100, story: .item(Stories.Item(id: 1)))
        XCTAssertEqual(a.postbox.storage.parseCount, 1); XCTAssertEqual(a.postbox.storage.peerStates[100]?.entry.get(Stories.PeerState.self)?.maxReadId, 50)
    }
}

extension StoryReactionMutationTests {
    func testMinimalStoryUsesCachedProfileBaselineWhenRecordsAreMissing() {
        let a = Account(); let original = Stories.Item(id: 1, views: views(7), myReaction: heart)
        cache(a, key: cacheKey(), item: original)
        let events = replayFullStory(transaction: a.postbox.storage, peerId: 100, story: .min(Stories.Item(id: 1, text: "new caption")))
        XCTAssertEqual(active(a)?.myReaction, heart); XCTAssertEqual(active(a)?.views, original.views)
        XCTAssertEqual(publishedStory(events), active(a))
    }
}

extension StoryReactionMutationTests {
    func testServerDeletionRemovesCachedProfileArchiveAndAlbums() {
        let a = Account(); let original = seed(a).0
        let keys = [cacheKey(), cacheKey(archived: 1), cacheKey(album: 7), cacheKey(archived: 1, album: 8)]
        for key in keys { cache(a, key: key, item: original, folders: [.init(id: 7, title: "keep title")]) }
        cache(a, key: cacheKey(peer: 10), item: original)
        _ = replayFullStory(transaction: a.postbox.storage, peerId: 100, story: .storyItemDeleted(.init(id: 1)))
        for key in keys {
            let head = a.postbox.storage.cache[key]?.get(CachedPeerStoryListHead.self)
            XCTAssertEqual(head?.items.map(\.id), [90]); XCTAssertEqual(head?.pinnedIds, [90]); XCTAssertEqual(head?.totalCount, 56)
            XCTAssertEqual(head?.folders, [.init(id: 7, title: "keep title")])
        }
        XCTAssertEqual(cached(a, key: cacheKey(peer: 10)), original)
    }
    func testCachedDeletionRemovesPlaceholdersAndDiscoversAlbumsBeforeRemoval() {
        let a = Account()
        a.postbox.storage.cache[cacheKey()] = CodableEntry(CachedPeerStoryListHead(items: [.placeholder(1)], pinnedIds: [1], totalCount: 1, folders: [.init(id: 7, title: "a")]))
        cache(a, key: cacheKey(album: 7), item: Stories.Item(id: 1))
        _ = replayFullStory(transaction: a.postbox.storage, peerId: 100, story: .storyItemDeleted(.init(id: 1)))
        XCTAssertEqual(a.postbox.storage.cache[cacheKey()]?.get(CachedPeerStoryListHead.self)?.items.count, 0)
        XCTAssertNil(cached(a, key: cacheKey(album: 7))); XCTAssertEqual(a.postbox.storage.cacheWrites, 2)
    }
    func testDuplicateCachedDeletionDoesNotDecrementCountsTwice() {
        let a = Account(); cache(a, key: cacheKey(), item: Stories.Item(id: 1))
        _ = replayFullStory(transaction: a.postbox.storage, peerId: 100, story: .storyItemDeleted(.init(id: 1)))
        let writes = a.postbox.storage.cacheWrites
        _ = replayFullStory(transaction: a.postbox.storage, peerId: 100, story: .storyItemDeleted(.init(id: 1)))
        XCTAssertEqual(a.postbox.storage.cache[cacheKey()]?.get(CachedPeerStoryListHead.self)?.totalCount, 56)
        XCTAssertEqual(a.postbox.storage.cacheWrites, writes)
    }
    func testCachedDeletionClampsBrokenCountAndLeavesMissingHeadsAbsent() {
        let a = Account()
        a.postbox.storage.cache[cacheKey()] = CodableEntry(CachedPeerStoryListHead(items: [.placeholder(1), .placeholder(1)], pinnedIds: [1, 1], totalCount: Int32.min, folders: []))
        _ = replayFullStory(transaction: a.postbox.storage, peerId: 100, story: .storyItemDeleted(.init(id: 1)))
        let head = a.postbox.storage.cache[cacheKey()]?.get(CachedPeerStoryListHead.self)
        XCTAssertEqual(head?.totalCount, 0); XCTAssertTrue(head?.items.isEmpty == true); XCTAssertTrue(head?.pinnedIds.isEmpty == true)
        XCTAssertEqual(a.postbox.storage.cache.count, 1)
    }
}

extension StoryReactionMutationTests {
    func testRefreshAfterLocalDeletionCannotRestoreOldStory() {
        let a = Account(); let old = seed(a).0
        let d = _internal_refreshStories(account: a, peerId: 100, ids: [1]).start()
        a.postbox.storage.rows[100] = []; a.postbox.storage.stories[.init(peerId: 100, id: 1)] = CodableEntry(data: Data())
        a.network.fullRequests[0].succeed([.item(old)])
        XCTAssertNil(individual(a)); XCTAssertTrue(a.postbox.storage.rows[100]!.isEmpty); XCTAssertTrue(a.stateManager.updates.isEmpty); d.dispose()
    }
    func testRefreshCannotOverwriteConcurrentCaptionOrPrivacyEdit() {
        let a = Account(); let old = seed(a).0
        let d = _internal_refreshStories(account: a, peerId: 100, ids: [1]).start()
        var edited = old; edited.text = "new caption"; edited.privacy = 99
        a.postbox.storage.rows[100] = [row(.item(edited))]; a.postbox.storage.stories[.init(peerId: 100, id: 1)] = CodableEntry(Stories.StoredItem.item(edited))
        a.network.fullRequests[0].succeed([.item(old)])
        XCTAssertEqual(active(a), edited); XCTAssertEqual(individual(a), edited); d.dispose()
    }
    func testRefreshMissingPeerDoesNotClearExistingStoryRecord() {
        let a = Account(); let old = seed(a).1; a.postbox.storage.peers.removeValue(forKey: 100)
        let d = _internal_refreshStories(account: a, peerId: 100, ids: [1]).start()
        XCTAssertTrue(a.network.fullRequests.isEmpty); XCTAssertEqual(individual(a), old); d.dispose()
    }
    func testRefreshUnsupportedMediaDoesNotBecomeDeletion() {
        let a = Account(); let old = seed(a)
        let d = _internal_refreshStories(account: a, peerId: 100, ids: [1]).start(); a.network.fullRequests[0].succeed([.unsupported(1)])
        XCTAssertEqual(active(a), old.0); XCTAssertEqual(individual(a), old.1); XCTAssertTrue(a.stateManager.updates.isEmpty); d.dispose()
    }
    func testRefreshPublishesSameMergedMinimalStoryAsStorage() {
        let a = Account(); let old = seed(a, previous: heart).0
        let d = _internal_refreshStories(account: a, peerId: 100, ids: [1]).start(); a.network.fullRequests[0].succeed([.min(Stories.Item(id: 1, text: "fresh"))])
        XCTAssertEqual(active(a)?.myReaction, heart); XCTAssertEqual(active(a)?.views, old.views)
        XCTAssertEqual(publishedStory(a.stateManager.updates), active(a)); d.dispose()
    }
    func testRefreshAbsentStoryRemovesActiveIndividualAndCachedCopies() {
        let a = Account(); let old = seed(a).0; cache(a, key: cacheKey(), item: old)
        let d = _internal_refreshStories(account: a, peerId: 100, ids: [1]).start(); a.network.fullRequests[0].succeed([])
        XCTAssertNil(active(a)); XCTAssertNil(individual(a)); XCTAssertNil(cached(a, key: cacheKey()))
        if case .deleted = a.stateManager.updates.last {} else { XCTFail("Missing deletion event") }; d.dispose()
    }
    func testRefreshNewerIdenticalReplyStillSupersedesOlderStaleReply() {
        let a = Account(); var old = seed(a).0; a.postbox.storage.stories[.init(peerId: 100, id: 1)] = CodableEntry(Stories.StoredItem.item(old))
        let first = _internal_refreshStories(account: a, peerId: 100, ids: [1]).start()
        let second = _internal_refreshStories(account: a, peerId: 100, ids: [1]).start()
        a.network.fullRequests[1].succeed([.item(old)]); old.text = "stale"
        a.network.fullRequests[0].succeed([.item(old)]); XCTAssertNotEqual(active(a)?.text, "stale"); first.dispose(); second.dispose()
    }
    func testRefreshNewerResponseStillAppliesAfterOlderResponseCommits() {
        let a = Account(); var old = seed(a).0; var fresh = old
        old.text = "intermediate"; fresh.text = "newest"
        let first = _internal_refreshStories(account: a, peerId: 100, ids: [1]).start()
        let second = _internal_refreshStories(account: a, peerId: 100, ids: [1]).start()
        a.network.fullRequests[0].succeed([.item(old)])
        a.network.fullRequests[1].succeed([.item(fresh)])
        XCTAssertEqual(active(a)?.text, "newest"); XCTAssertEqual(individual(a)?.text, "newest")
        first.dispose(); second.dispose()
    }
    func testRefreshNewerFailureDoesNotDiscardOlderValidReply() {
        let a = Account(); var fresh = seed(a).0; fresh.text = "fresh"
        let first = _internal_refreshStories(account: a, peerId: 100, ids: [1]).start(); let second = _internal_refreshStories(account: a, peerId: 100, ids: [1]).start()
        a.network.fullRequests[1].fail(); a.network.fullRequests[0].succeed([.item(fresh)]); XCTAssertEqual(active(a)?.text, "fresh"); first.dispose(); second.dispose()
    }
    func testRefreshFiltersInvalidAndDuplicateIds() {
        let a = Account(); _ = seed(a)
        let d = _internal_refreshStories(account: a, peerId: 100, ids: [0, 1, -2, 1, 2]).start()
        XCTAssertEqual(a.network.fullRequests.first?.data.ids, [1, 2]); d.dispose()
    }
    func testRefreshEmptyInputDoesNotRequest() {
        let a = Account(); var complete = false
        let d = _internal_refreshStories(account: a, peerId: 100, ids: []).start(completed: { complete = true })
        XCTAssertTrue(a.network.fullRequests.isEmpty); XCTAssertTrue(complete); d.dispose()
    }
    func testRefreshCannotInsertArchivedStoryIntoActiveFeed() {
        let a = Account(); let item = Stories.Item(id: 1, isExpired: true)
        let d = _internal_refreshStories(account: a, peerId: 100, ids: [1]).start(); a.network.fullRequests[0].succeed([.item(item)])
        XCTAssertTrue(a.postbox.storage.rows[100, default: []].isEmpty); XCTAssertEqual(individual(a), item); d.dispose()
    }
    func testRefreshCanceledCommitCannotMutateEvenIfQueuedClosureExecutes() {
        let a = Account(); let original = seed(a)
        let d = _internal_refreshStories(account: a, peerId: 100, ids: [1]).start()
        a.postbox.delayAt.insert(a.postbox.count + __REFRESH_COMMIT_TRANSACTION_OFFSET__); a.network.fullRequests[0].succeed([.item(Stories.Item(id: 1, text: "late"))])
        XCTAssertEqual(a.postbox.pending.count, 1)
        d.dispose(); for pending in a.postbox.pending { pending.run() }
        XCTAssertEqual(active(a), original.0); XCTAssertEqual(individual(a), original.1); XCTAssertTrue(a.stateManager.updates.isEmpty)
    }
    func testRefreshFailurePreservesAllLocalState() {
        let a = Account(); let original = seed(a)
        let d = _internal_refreshStories(account: a, peerId: 100, ids: [1]).start(); a.network.fullRequests[0].fail()
        XCTAssertEqual(active(a), original.0); XCTAssertEqual(individual(a), original.1); d.dispose()
    }
}

extension StoryReactionMutationTests {
    func testRefreshCannotOverwriteConcurrentCacheOnlyEdit() {
        let a = Account(); let original = seed(a).0; cache(a, key: cacheKey(), item: original)
        let d = _internal_refreshStories(account: a, peerId: 100, ids: [1]).start()
        var edited = original; edited.text = "new cached caption"; cache(a, key: cacheKey(), item: edited)
        a.network.fullRequests[0].succeed([.item(original)])
        XCTAssertEqual(cached(a, key: cacheKey()), edited); XCTAssertTrue(a.stateManager.updates.isEmpty); d.dispose()
    }
    func testRefreshRejectsStaleStoryButCommitsOtherRequestedStory() {
        let a = Account(); let original = seed(a).0
        let d = _internal_refreshStories(account: a, peerId: 100, ids: [1, 2]).start()
        var edited = original; edited.text = "edited"
        a.postbox.storage.rows[100] = [row(.item(edited))]
        let second = Stories.Item(id: 2, text: "second")
        a.network.fullRequests[0].succeed([.item(original), .item(second), .item(Stories.Item(id: 3))])
        XCTAssertEqual(active(a), edited)
        XCTAssertEqual(a.postbox.storage.stories[.init(peerId: 100, id: 2)]?.get(Stories.StoredItem.self), .item(second))
        XCTAssertNil(a.postbox.storage.stories[.init(peerId: 100, id: 3)]); d.dispose()
    }
    func testRefreshDuplicateResponseIdsPreserveExistingStoryAndOlderRequest() {
        let a = Account(); let original = seed(a)
        let first = _internal_refreshStories(account: a, peerId: 100, ids: [1]).start()
        let second = _internal_refreshStories(account: a, peerId: 100, ids: [1]).start()
        a.network.fullRequests[1].succeed([.item(original.0), .storyItemDeleted(.init(id: 1))])
        XCTAssertEqual(active(a), original.0); XCTAssertEqual(individual(a), original.1)
        var valid = original.0; valid.text = "valid"
        a.network.fullRequests[0].succeed([.item(valid)]); XCTAssertEqual(active(a), valid)
        first.dispose(); second.dispose()
    }
    func testRefreshServerDeletionInvalidatesFetchWithoutExistingRecord() {
        let a = Account(); let d = _internal_refreshStories(account: a, peerId: 100, ids: [1]).start()
        _ = replayFullStory(transaction: a.postbox.storage, peerId: 100, story: .storyItemDeleted(.init(id: 1)), storyRefreshContext: a.storyRefreshContext)
        a.network.fullRequests[0].succeed([.item(Stories.Item(id: 1))])
        XCTAssertNil(individual(a)); XCTAssertTrue(a.stateManager.updates.isEmpty); d.dispose()
    }
    func testRefreshIdenticalAuthoritativeUpdateSupersedesFetch() {
        let a = Account(); let original = seed(a).0
        a.postbox.storage.stories[.init(peerId: 100, id: 1)] = CodableEntry(Stories.StoredItem.item(original))
        let d = _internal_refreshStories(account: a, peerId: 100, ids: [1]).start()
        _ = replayFullStory(transaction: a.postbox.storage, peerId: 100, story: .item(original), storyRefreshContext: a.storyRefreshContext)
        var stale = original; stale.text = "stale"
        a.network.fullRequests[0].succeed([.item(stale)])
        XCTAssertEqual(active(a), original); XCTAssertTrue(a.stateManager.updates.isEmpty); d.dispose()
    }
    func testRefreshIdenticalAuthoritativeReactionSupersedesFetch() {
        let a = Account(); let original = seed(a, previous: heart).0
        let d = _internal_refreshStories(account: a, peerId: 100, ids: [1]).start()
        _ = replayReaction(transaction: a.postbox.storage, peerId: 100, id: 1, reaction: .builtin("❤️"), storyRefreshContext: a.storyRefreshContext)
        a.network.fullRequests[0].succeed([.item(Stories.Item(id: 1))])
        XCTAssertEqual(active(a), original); XCTAssertTrue(a.stateManager.updates.isEmpty); d.dispose()
    }
    func testRefreshPendingReactionKeepsSelectionAndCounters() {
        let a = Account(); _ = seed(a)
        let r = _internal_setStoryReaction(account: a, peerId: 100, id: 1, reaction: fire).start()
        let original = active(a)
        let d = _internal_refreshStories(account: a, peerId: 100, ids: [1]).start()
        a.network.fullRequests[0].succeed([.item(Stories.Item(id: 1, text: "fresh"))])
        XCTAssertEqual(active(a)?.myReaction, fire); XCTAssertEqual(active(a)?.views, original?.views)
        XCTAssertEqual(active(a)?.text, "fresh"); d.dispose(); r.dispose()
    }
    func testRefreshReactionSettlementInvalidatesSnapshotEvenIfUnchanged() {
        let a = Account(); _ = seed(a)
        let r = _internal_setStoryReaction(account: a, peerId: 100, id: 1, reaction: fire).start()
        let original = active(a)
        let d = _internal_refreshStories(account: a, peerId: 100, ids: [1]).start()
        a.network.requests[0].succeed()
        a.network.fullRequests[0].succeed([.item(Stories.Item(id: 1))])
        XCTAssertEqual(active(a), original); d.dispose(); r.dispose()
    }
    func testRefreshCancelledNewerRequestLeavesOlderRequestUsable() {
        let a = Account(); var fresh = seed(a).0; fresh.text = "fresh"
        let first = _internal_refreshStories(account: a, peerId: 100, ids: [1]).start()
        let second = _internal_refreshStories(account: a, peerId: 100, ids: [1]).start(); second.dispose()
        a.network.fullRequests[0].succeed([.item(fresh)]); XCTAssertEqual(active(a), fresh); first.dispose()
    }
    func testRefreshCancellationBeforeSnapshotCannotStartRequest() {
        let a = Account(); _ = seed(a); a.postbox.delayAt = [1]
        let d = _internal_refreshStories(account: a, peerId: 100, ids: [1]).start(); d.dispose()
        for pending in a.postbox.pending { pending.run() }
        XCTAssertTrue(a.network.fullRequests.isEmpty); XCTAssertEqual(a.postbox.storage.writes, 0)
    }
    func testRefreshMissingStoryCachesAbsenceEvenWithoutPriorRecord() {
        let a = Account(); let d = _internal_refreshStories(account: a, peerId: 100, ids: [1]).start()
        a.network.fullRequests[0].succeed([])
        XCTAssertEqual(a.postbox.storage.stories[.init(peerId: 100, id: 1)], CodableEntry(data: Data())); d.dispose()
    }
    func testRefreshPreservesInterveningEditAfterEarlierRefreshCommitted() {
        let a = Account(); var item = seed(a).0
        let first = _internal_refreshStories(account: a, peerId: 100, ids: [1]).start()
        let second = _internal_refreshStories(account: a, peerId: 100, ids: [1]).start()
        item.text = "first"; a.network.fullRequests[0].succeed([.item(item)])
        var edited = item; edited.text = "local edit"; a.postbox.storage.rows[100] = [row(.item(edited))]
        item.text = "stale fetch"; a.network.fullRequests[1].succeed([.item(item)])
        XCTAssertEqual(active(a), edited); first.dispose(); second.dispose()
    }
    func testRefreshCompletionReleasesAccountWhileCallerKeepsDisposable() {
        var a: Account? = Account(); weak var weakAccount = a
        let d = _internal_refreshStories(account: a!, peerId: 100, ids: [1]).start()
        a!.network.fullRequests[0].succeed([]); a = nil
        XCTAssertNil(weakAccount); d.dispose()
    }
    func testRefreshCancellationReleasesAccountWhileCallerKeepsDisposable() {
        var a: Account? = Account(); weak var weakAccount = a
        let d = _internal_refreshStories(account: a!, peerId: 100, ids: [1]).start()
        d.dispose(); a = nil; XCTAssertNil(weakAccount)
    }
}

extension StoryReactionMutationTests {
    func testFullUpdateRefreshesClosedProfileArchiveAndAlbumCaches() {
        let a = Account(); var original = seed(a).0; original.isPinned = true
        let keys = [cacheKey(), cacheKey(archived: 1), cacheKey(album: 7), cacheKey(archived: 1, album: 8)]
        for key in keys { cache(a, key: key, item: original) }
        var fresh = original; fresh.text = "new caption"; fresh.media = 123; fresh.privacy = 77
        _ = replayFullStory(transaction: a.postbox.storage, peerId: 100, story: .item(fresh))
        for key in keys { XCTAssertEqual(cached(a, key: key), fresh) }
    }
    func testFullUpdateRemovesProfileAndAlbumCopiesWhenMembershipChanges() {
        let a = Account(); var original = seed(a).0; original.isPinned = true
        let keys = [cacheKey(), cacheKey(archived: 1), cacheKey(album: 7), cacheKey(archived: 1, album: 8)]
        for key in keys { cache(a, key: key, item: original) }
        var fresh = original; fresh.isPinned = false; fresh.folderIds = [8]
        _ = replayFullStory(transaction: a.postbox.storage, peerId: 100, story: .item(fresh))
        for key in [cacheKey(), cacheKey(album: 7)] {
            let head = a.postbox.storage.cache[key]?.get(CachedPeerStoryListHead.self)
            XCTAssertEqual(head?.items, [.placeholder(90)]); XCTAssertEqual(head?.pinnedIds, [90]); XCTAssertEqual(head?.totalCount, 56)
        }
        for key in [cacheKey(archived: 1), cacheKey(archived: 1, album: 8)] { XCTAssertEqual(cached(a, key: key), fresh) }
    }
    func testFullUpdateUpgradesCachedPlaceholderWithoutChangingCountOrOrder() {
        let a = Account(); let key = cacheKey()
        a.postbox.storage.cache[key] = CodableEntry(CachedPeerStoryListHead(items: [.placeholder(90), .placeholder(1)], pinnedIds: [1], totalCount: 57, folders: []))
        let item = Stories.Item(id: 1)
        _ = replayFullStory(transaction: a.postbox.storage, peerId: 100, story: .item(item))
        let head = a.postbox.storage.cache[key]?.get(CachedPeerStoryListHead.self)
        XCTAssertEqual(head?.items, [.placeholder(90), .item(item)]); XCTAssertEqual(head?.totalCount, 57); XCTAssertEqual(head?.pinnedIds, [1])
    }
    func testFullUpdateUnknownAlbumMembershipPreservesExistingCachedPlacement() {
        let a = Account(); var item = seed(a).0; item.folderIds = nil
        cache(a, key: cacheKey(), item: item, folders: [.init(id: 7, title: "album")])
        cache(a, key: cacheKey(album: 7), item: item)
        var fresh = item; fresh.text = "updated"
        _ = replayFullStory(transaction: a.postbox.storage, peerId: 100, story: .item(fresh))
        XCTAssertEqual(cached(a, key: cacheKey(album: 7)), fresh)
    }
    func testFullUpdateDoesNotCreateCacheHeadsOrInsertUnloadedStories() {
        let a = Account(); let key = cacheKey()
        a.postbox.storage.cache[key] = CodableEntry(CachedPeerStoryListHead(items: [.placeholder(90)], pinnedIds: [], totalCount: 57, folders: []))
        _ = replayFullStory(transaction: a.postbox.storage, peerId: 100, story: .item(Stories.Item(id: 1, folderIds: [7])))
        XCTAssertEqual(a.postbox.storage.cache.count, 1); XCTAssertEqual(a.postbox.storage.cacheWrites, 0)
    }
    func testFullUpdateIdenticalCachePayloadDoesNotRewriteHead() {
        let a = Account(); let item = Stories.Item(id: 1)
        cache(a, key: cacheKey(), item: item)
        _ = replayFullStory(transaction: a.postbox.storage, peerId: 100, story: .item(item))
        XCTAssertEqual(a.postbox.storage.cacheWrites, 0)
    }
    func testRefreshUpdatesCachedCopyWithSameMergedPayloadAsIndividual() {
        let a = Account(); var item = seed(a).0; item.isPinned = true
        cache(a, key: cacheKey(), item: item)
        let d = _internal_refreshStories(account: a, peerId: 100, ids: [1]).start()
        item.text = "fresh"
        a.network.fullRequests[0].succeed([.item(item)])
        XCTAssertEqual(cached(a, key: cacheKey()), individual(a)); d.dispose()
    }
}

extension StoryReactionMutationTests {
    func testRefreshCancellationAfterCommitStillPublishesCommittedUpdate() {
        let a = Account(); var item = seed(a).0; item.text = "committed"
        let d = _internal_refreshStories(account: a, peerId: 100, ids: [1]).start()
        a.postbox.afterTransaction = { d.dispose() }
        a.network.fullRequests[0].succeed([.item(item)])
        XCTAssertEqual(active(a), item); XCTAssertEqual(publishedStory(a.stateManager.updates), item)
        a.postbox.afterTransaction = nil
    }
    func testFullUpdateRefreshesEveryMatchingActiveRowAndPreservesOtherStory() {
        let a = Account(); let first = Stories.Item(id: 1); let other = Stories.Item(id: 2)
        a.postbox.storage.rows[100] = [row(.item(first)), row(.item(other)), row(.item(first))]
        var fresh = first; fresh.text = "fresh"
        _ = replayFullStory(transaction: a.postbox.storage, peerId: 100, story: .item(fresh))
        XCTAssertEqual(a.postbox.storage.rows[100], [row(.item(fresh)), row(.item(other)), row(.item(fresh))])
    }
}

extension StoryReactionMutationTests {
    func countViews(_ count: Int) -> Stories.Item.Views { .init(seenCount: count, reactedCount: count, forwardCount: count, seenPeerIds: [], reactions: [], hasList: true) }
    func testCounterOrderNewerFullReplyRejectsOlderCountReply() {
        let a = Account(); _ = seed(a)
        let c = Messages(a).refreshStoryViews(peerId: 100, ids: [1]).start()
        let f = _internal_refreshStories(account: a, peerId: 100, ids: [1]).start()
        let item = Stories.Item(id: 1, text: "full", views: countViews(30))
        a.network.fullRequests[0].succeed([.item(item)])
        a.network.countRequests[0].succeed([countViews(10)])
        XCTAssertEqual(active(a)?.views, countViews(30)); XCTAssertEqual(a.stateManager.updates.count, 1)
        c.dispose(); f.dispose()
    }
    func testCounterOrderNewerCountsDoNotDiscardOlderFullMetadata() {
        let a = Account(); _ = seed(a)
        let f = _internal_refreshStories(account: a, peerId: 100, ids: [1]).start()
        let c = Messages(a).refreshStoryViews(peerId: 100, ids: [1]).start()
        a.network.countRequests[0].succeed([countViews(30)])
        a.network.fullRequests[0].succeed([.item(Stories.Item(id: 1, media: 99, text: "fresh caption", views: countViews(10)))])
        XCTAssertEqual(active(a)?.views, countViews(30)); XCTAssertEqual(active(a)?.text, "fresh caption"); XCTAssertEqual(active(a)?.media, 99)
        XCTAssertEqual(individual(a), active(a)); c.dispose(); f.dispose()
    }
    func testCounterOrderIdenticalNewerCountsStillProtectAgainstOlderFullCounts() {
        let a = Account(); let original = seed(a).0
        a.postbox.storage.stories[.init(peerId: 100, id: 1)] = CodableEntry(Stories.StoredItem.item(original))
        let f = _internal_refreshStories(account: a, peerId: 100, ids: [1]).start()
        let c = Messages(a).refreshStoryViews(peerId: 100, ids: [1]).start()
        a.network.countRequests[0].succeed([original.views!])
        a.network.fullRequests[0].succeed([.item(Stories.Item(id: 1, text: "fresh", views: countViews(1)))])
        XCTAssertEqual(active(a)?.views, original.views); XCTAssertEqual(active(a)?.text, "fresh"); c.dispose(); f.dispose()
    }
    func testCounterOrderOlderCountReplyDoesNotBlockNewerFullReply() {
        let a = Account(); _ = seed(a)
        let c = Messages(a).refreshStoryViews(peerId: 100, ids: [1]).start()
        let f = _internal_refreshStories(account: a, peerId: 100, ids: [1]).start()
        a.network.countRequests[0].succeed([countViews(10)])
        a.network.fullRequests[0].succeed([.item(Stories.Item(id: 1, text: "fresh", views: countViews(30)))])
        XCTAssertEqual(active(a)?.views, countViews(30)); XCTAssertEqual(active(a)?.text, "fresh"); c.dispose(); f.dispose()
    }
    func testCounterOrderOlderFullReplyDoesNotBlockNewerCountReply() {
        let a = Account(); _ = seed(a)
        let f = _internal_refreshStories(account: a, peerId: 100, ids: [1]).start()
        let c = Messages(a).refreshStoryViews(peerId: 100, ids: [1]).start()
        a.network.fullRequests[0].succeed([.item(Stories.Item(id: 1, text: "fresh", views: countViews(10)))])
        a.network.countRequests[0].succeed([countViews(30)])
        XCTAssertEqual(active(a)?.views, countViews(30)); XCTAssertEqual(active(a)?.text, "fresh"); c.dispose(); f.dispose()
    }
    func testCounterOrderNewerFailedFullRequestLeavesOlderCountUsable() {
        let a = Account(); _ = seed(a)
        let c = Messages(a).refreshStoryViews(peerId: 100, ids: [1]).start()
        let f = _internal_refreshStories(account: a, peerId: 100, ids: [1]).start()
        a.network.fullRequests[0].fail(); a.network.countRequests[0].succeed([countViews(20)])
        XCTAssertEqual(active(a)?.views, countViews(20)); c.dispose(); f.dispose()
    }
    func testCounterOrderCountReplyBeforeInitialFullLoadIsPreserved() {
        let a = Account()
        let f = _internal_refreshStories(account: a, peerId: 100, ids: [1]).start()
        let c = Messages(a).refreshStoryViews(peerId: 100, ids: [1]).start()
        a.network.countRequests[0].succeed([countViews(40)])
        a.network.fullRequests[0].succeed([.item(Stories.Item(id: 1, views: countViews(10)))])
        XCTAssertEqual(individual(a)?.views, countViews(40)); c.dispose(); f.dispose()
    }
    func testCounterOrderAuthoritativeFullUpdateInvalidatesOlderCountTicket() {
        let a = Account(); _ = seed(a)
        let c = Messages(a).refreshStoryViews(peerId: 100, ids: [1]).start()
        _ = replayFullStory(transaction: a.postbox.storage, peerId: 100, story: .item(Stories.Item(id: 1, views: countViews(50))), storyRefreshContext: a.storyRefreshContext, storyViewRefreshContext: a.storyViewRefreshContext)
        a.network.countRequests[0].succeed([countViews(10)])
        XCTAssertEqual(active(a)?.views, countViews(50)); XCTAssertTrue(a.stateManager.updates.isEmpty); c.dispose()
    }
    func testCounterOrderAuthoritativeReactionInvalidatesOlderCountTicket() {
        let a = Account(); _ = seed(a)
        let c = Messages(a).refreshStoryViews(peerId: 100, ids: [1]).start()
        _ = replayReaction(transaction: a.postbox.storage, peerId: 100, id: 1, reaction: .builtin("🔥"), storyRefreshContext: a.storyRefreshContext, storyViewRefreshContext: a.storyViewRefreshContext)
        let current = active(a)?.views
        a.network.countRequests[0].succeed([countViews(10)])
        XCTAssertEqual(active(a)?.views, current); XCTAssertTrue(a.stateManager.updates.isEmpty); c.dispose()
    }
    func testCounterOrderCounterCommitCancellationStillPublishesCommittedCounts() {
        let a = Account(); _ = seed(a)
        let c = Messages(a).refreshStoryViews(peerId: 100, ids: [1]).start()
        a.postbox.afterTransaction = { if a.postbox.storage.writes > 0 { c.dispose() } }
        a.network.countRequests[0].succeed([countViews(50)])
        XCTAssertEqual(active(a)?.views, countViews(50)); XCTAssertEqual(a.stateManager.updates.count, 1)
        a.postbox.afterTransaction = nil
    }
    func testCounterOrderCountReplyAfterFullDeletionDoesNotPublishGhostUpdate() {
        let a = Account(); _ = seed(a)
        let f = _internal_refreshStories(account: a, peerId: 100, ids: [1]).start()
        let c = Messages(a).refreshStoryViews(peerId: 100, ids: [1]).start()
        a.network.fullRequests[0].succeed([])
        a.network.countRequests[0].succeed([countViews(20)])
        XCTAssertNil(active(a)); XCTAssertEqual(a.stateManager.updates.count, 1); c.dispose(); f.dispose()
    }
}

extension StoryReactionMutationTests {
    func testCounterOrderMinimalFullReplyDoesNotInvalidateOlderCountReply() {
        let a = Account(); _ = seed(a)
        let c = Messages(a).refreshStoryViews(peerId: 100, ids: [1]).start()
        let f = _internal_refreshStories(account: a, peerId: 100, ids: [1]).start()
        a.network.fullRequests[0].succeed([.min(Stories.Item(id: 1, text: "fresh"))])
        a.network.countRequests[0].succeed([countViews(20)])
        XCTAssertEqual(active(a)?.text, "fresh"); XCTAssertEqual(active(a)?.views, countViews(20)); c.dispose(); f.dispose()
    }
    func testCounterOrderMinimalAuthoritativeUpdateDoesNotInvalidateCounts() {
        let a = Account(); _ = seed(a)
        let c = Messages(a).refreshStoryViews(peerId: 100, ids: [1]).start()
        _ = replayFullStory(transaction: a.postbox.storage, peerId: 100, story: .min(Stories.Item(id: 1, text: "fresh")), storyRefreshContext: a.storyRefreshContext, storyViewRefreshContext: a.storyViewRefreshContext)
        a.network.countRequests[0].succeed([countViews(20)])
        XCTAssertEqual(active(a)?.text, "fresh"); XCTAssertEqual(active(a)?.views, countViews(20)); c.dispose()
    }
    func testCounterOrderUnsupportedNewerFullReplyDoesNotRetireOlderCount() {
        let a = Account(); _ = seed(a)
        let c = Messages(a).refreshStoryViews(peerId: 100, ids: [1]).start()
        let f = _internal_refreshStories(account: a, peerId: 100, ids: [1]).start()
        a.network.fullRequests[0].succeed([.unsupported(1)]); a.network.countRequests[0].succeed([countViews(20)])
        XCTAssertEqual(active(a)?.views, countViews(20)); c.dispose(); f.dispose()
    }
    func testCounterOrderMetadataEditAfterCountStillRejectsOlderFullReply() {
        let a = Account(); _ = seed(a)
        let f = _internal_refreshStories(account: a, peerId: 100, ids: [1]).start()
        let c = Messages(a).refreshStoryViews(peerId: 100, ids: [1]).start()
        a.network.countRequests[0].succeed([countViews(20)])
        var edited = active(a)!; edited.text = "local edit"; a.postbox.storage.rows[100] = [row(.item(edited))]
        a.network.fullRequests[0].succeed([.item(Stories.Item(id: 1, text: "stale"))])
        XCTAssertEqual(active(a), edited); c.dispose(); f.dispose()
    }
    func testCounterOrderMixedBatchUsesPerStoryCounterOrdering() {
        let a = Account(); _ = seed(a)
        let f = _internal_refreshStories(account: a, peerId: 100, ids: [1, 2]).start()
        let c = Messages(a).refreshStoryViews(peerId: 100, ids: [1]).start()
        a.network.countRequests[0].succeed([countViews(20)])
        a.network.fullRequests[0].succeed([.item(Stories.Item(id: 1, text: "fresh", views: countViews(10))), .item(Stories.Item(id: 2, views: countViews(30)))])
        XCTAssertEqual(active(a)?.views, countViews(20)); XCTAssertEqual(active(a)?.text, "fresh")
        if case let .item(item) = a.postbox.storage.stories[.init(peerId: 100, id: 2)]?.get(Stories.StoredItem.self) { XCTAssertEqual(item.views, countViews(30)) } else { XCTFail("Missing second story") }
        c.dispose(); f.dispose()
    }
}

extension StoryReactionMutationTests {
    func testCounterOrderPreservedCountsReachClosedCachesAndNotification() {
        let a = Account(); let original = seed(a).0
        let keys = [cacheKey(archived: 1), cacheKey(album: 7)]
        for key in keys { cache(a, key: key, item: original) }
        let f = _internal_refreshStories(account: a, peerId: 100, ids: [1]).start()
        let c = Messages(a).refreshStoryViews(peerId: 100, ids: [1]).start()
        a.network.countRequests[0].succeed([countViews(30)])
        a.network.fullRequests[0].succeed([.item(Stories.Item(id: 1, media: 99, text: "fresh", views: countViews(10), folderIds: [7]))])
        for key in keys { XCTAssertEqual(cached(a, key: key)?.views, countViews(30)); XCTAssertEqual(cached(a, key: key)?.text, "fresh") }
        if case let .added(_, .item(item)) = a.stateManager.updates.last { XCTAssertEqual(item.views, countViews(30)); XCTAssertEqual(item.media, 99) } else { XCTFail("Missing merged update") }
        c.dispose(); f.dispose()
    }
    func testCounterOrderNewerFullReplyWithNoViewsClearsOlderCounterSnapshot() {
        let a = Account(); _ = seed(a)
        let c = Messages(a).refreshStoryViews(peerId: 100, ids: [1]).start()
        let f = _internal_refreshStories(account: a, peerId: 100, ids: [1]).start()
        a.network.fullRequests[0].succeed([.item(Stories.Item(id: 1, views: nil))])
        a.network.countRequests[0].succeed([countViews(30)])
        XCTAssertNil(active(a)?.views); XCTAssertEqual(a.stateManager.updates.count, 1); c.dispose(); f.dispose()
    }
    func testCounterOrderCanceledFullRequestDoesNotRetireOlderCountRequest() {
        let a = Account(); _ = seed(a)
        let c = Messages(a).refreshStoryViews(peerId: 100, ids: [1]).start()
        let f = _internal_refreshStories(account: a, peerId: 100, ids: [1]).start(); f.dispose()
        a.network.countRequests[0].succeed([countViews(30)])
        XCTAssertEqual(active(a)?.views, countViews(30)); c.dispose()
    }
}

extension StoryReactionMutationTests {
    func testCounterOrderNewerCountsSurviveDelayedFullLookupWithoutExistingStory() {
        let a = Account(); a.postbox.delayAt = [1]
        let f = _internal_refreshStories(account: a, peerId: 100, ids: [1]).start()
        let c = Messages(a).refreshStoryViews(peerId: 100, ids: [1]).start()
        a.network.countRequests[0].succeed([countViews(40)])
        a.postbox.flush()
        a.network.fullRequests[0].succeed([.item(Stories.Item(id: 1, views: countViews(10)))])
        XCTAssertEqual(individual(a)?.views, countViews(40)); c.dispose(); f.dispose()
    }
}

extension StoryReactionMutationTests {
    func testReconciliationFailureRefreshesAuthoritativeReactionAndCounters() {
        let a = Account(); _ = seed(a); var completed = false
        let r = _internal_setStoryReaction(account: a, peerId: 100, id: 1, reaction: fire).start(completed: { completed = true })
        a.network.requests[0].fail()
        XCTAssertTrue(completed); XCTAssertEqual(a.network.fullRequests.count, 1)
        let fresh = Stories.Item(id: 1, text: "server", views: countViews(9), myReaction: heart)
        a.network.fullRequests.first?.succeed([.item(fresh)])
        XCTAssertEqual(active(a), fresh); r.dispose()
    }
    func testReconciliationConflictingServerReactionReloadsAfterSuccess() {
        let a = Account(); _ = seed(a)
        let r = _internal_setStoryReaction(account: a, peerId: 100, id: 1, reaction: fire).start()
        _ = replayReaction(transaction: a.postbox.storage, peerId: 100, id: 1, reaction: .builtin("❤️"), storyReactionContext: a.storyReactionContext)
        XCTAssertTrue(a.network.fullRequests.isEmpty); XCTAssertEqual(active(a)?.myReaction, fire)
        a.network.requests[0].succeed()
        XCTAssertEqual(a.network.fullRequests.count, 1)
        a.network.fullRequests.first?.succeed([.item(Stories.Item(id: 1, myReaction: heart))])
        XCTAssertEqual(active(a)?.myReaction, heart); r.dispose()
    }
    func testReconciliationMatchingAcknowledgementDoesNotReload() {
        let a = Account(); _ = seed(a)
        let r = _internal_setStoryReaction(account: a, peerId: 100, id: 1, reaction: fire).start()
        _ = replayReaction(transaction: a.postbox.storage, peerId: 100, id: 1, reaction: .builtin("🔥"), storyReactionContext: a.storyReactionContext)
        a.network.requests[0].succeed(); XCTAssertTrue(a.network.fullRequests.isEmpty); r.dispose()
    }
    func testReconciliationDeferredFullCountersReloadAfterSuccess() {
        let a = Account(); _ = seed(a)
        let r = _internal_setStoryReaction(account: a, peerId: 100, id: 1, reaction: fire).start()
        let fresh = Stories.Item(id: 1, text: "edited", views: countViews(40), myReaction: heart)
        _ = replayFullStory(transaction: a.postbox.storage, peerId: 100, story: .item(fresh), storyReactionContext: a.storyReactionContext)
        a.network.requests[0].succeed(); XCTAssertEqual(a.network.fullRequests.count, 1)
        a.network.fullRequests.first?.succeed([.item(fresh)]); XCTAssertEqual(active(a), fresh); r.dispose()
    }
    func testReconciliationSuppressedCountPollTriggersRefreshAfterSettlement() {
        let a = Account(); _ = seed(a)
        let r = _internal_setStoryReaction(account: a, peerId: 100, id: 1, reaction: fire).start()
        let c = Messages(a).refreshStoryViews(peerId: 100, ids: [1]).start()
        a.network.countRequests[0].succeed([countViews(30)])
        XCTAssertTrue(a.network.fullRequests.isEmpty)
        a.network.requests[0].succeed(); XCTAssertEqual(a.network.fullRequests.count, 1); c.dispose(); r.dispose()
    }
    func testReconciliationWaitsForAllOverlappingRequests() {
        let a = Account(); _ = seed(a)
        let first = _internal_setStoryReaction(account: a, peerId: 100, id: 1, reaction: heart).start()
        let second = _internal_setStoryReaction(account: a, peerId: 100, id: 1, reaction: fire).start()
        a.network.requests[1].fail(); XCTAssertTrue(a.network.fullRequests.isEmpty)
        a.network.requests[0].fail(); XCTAssertEqual(a.network.fullRequests.count, 1)
        first.dispose(); second.dispose()
    }
    func testReconciliationCoalescesRepeatedSettlementsDuringRefresh() {
        let a = Account(); _ = seed(a)
        let first = _internal_setStoryReaction(account: a, peerId: 100, id: 1, reaction: heart).start()
        a.network.requests[0].fail(); XCTAssertEqual(a.network.fullRequests.count, 1)
        let second = _internal_setStoryReaction(account: a, peerId: 100, id: 1, reaction: fire).start()
        a.network.requests[1].fail(); XCTAssertEqual(a.network.fullRequests.count, 1)
        a.network.fullRequests.first?.succeed([.item(Stories.Item(id: 1, text: "stale"))])
        XCTAssertEqual(a.network.fullRequests.count, 2)
        a.network.fullRequests.last?.succeed([.item(Stories.Item(id: 1, text: "fresh"))])
        XCTAssertEqual(active(a)?.text, "fresh"); first.dispose(); second.dispose()
    }
    func testReconciliationRefreshFailureDoesNotLoopOrBlockReactionCompletion() {
        let a = Account(); _ = seed(a); var completed = 0
        let r = _internal_setStoryReaction(account: a, peerId: 100, id: 1, reaction: fire).start(completed: { completed += 1 })
        a.network.requests[0].fail(); a.network.fullRequests.first?.fail()
        XCTAssertEqual(completed, 1); XCTAssertEqual(a.network.fullRequests.count, 1); r.dispose()
    }
    func testReconciliationAccountRemovalCancelsRefreshWithoutRetainingAccount() {
        var a: Account? = Account(); _ = seed(a!); weak var weakAccount = a
        let r = _internal_setStoryReaction(account: a!, peerId: 100, id: 1, reaction: fire).start()
        a!.network.requests[0].fail(); let fetch = a!.network.fullRequests.first
        XCTAssertNotNil(fetch); a = nil
        XCTAssertNil(weakAccount); XCTAssertTrue(fetch?.canceled == true); r.dispose()
    }
    func testReconciliationOldReplyDoesNotOverwriteNewOptimisticReaction() {
        let a = Account(); _ = seed(a)
        let first = _internal_setStoryReaction(account: a, peerId: 100, id: 1, reaction: heart).start(); a.network.requests[0].fail()
        let second = _internal_setStoryReaction(account: a, peerId: 100, id: 1, reaction: fire).start()
        a.network.fullRequests.first?.succeed([.item(Stories.Item(id: 1, myReaction: heart))])
        XCTAssertEqual(active(a)?.myReaction, fire); first.dispose(); second.dispose()
    }
    func testReconciliationDeletedStoryIsNotRefetchedAfterFailure() {
        let a = Account(); _ = seed(a)
        let r = _internal_setStoryReaction(account: a, peerId: 100, id: 1, reaction: fire).start()
        _ = replayFullStory(transaction: a.postbox.storage, peerId: 100, story: .storyItemDeleted(.init(id: 1)), storyReactionContext: a.storyReactionContext)
        a.network.requests[0].fail(); XCTAssertTrue(a.network.fullRequests.isEmpty); XCTAssertNil(individual(a)); r.dispose()
    }
    func testReconciliationCancellationBeforeNetworkDoesNotFetch() {
        let a = Account(); _ = seed(a); a.postbox.delayAt = [1]
        let r = _internal_setStoryReaction(account: a, peerId: 100, id: 1, reaction: fire).start()
        a.stateManager.onUpdate = { r.dispose() }; a.postbox.flush(); a.stateManager.onUpdate = nil
        XCTAssertTrue(a.network.requests.isEmpty); XCTAssertTrue(a.network.fullRequests.isEmpty)
    }
}

extension StoryReactionMutationTests {
    func testReconciliationObsoletePreReactionPollDoesNotForceRefresh() {
        let a = Account(); _ = seed(a)
        let c = Messages(a).refreshStoryViews(peerId: 100, ids: [1]).start()
        let r = _internal_setStoryReaction(account: a, peerId: 100, id: 1, reaction: fire).start()
        a.network.countRequests[0].succeed([countViews(10)]); a.network.requests[0].succeed()
        XCTAssertTrue(a.network.fullRequests.isEmpty); c.dispose(); r.dispose()
    }
    func testReconciliationUnknownDeletedStoryDoesNotCreateRecordOrRefetch() {
        let a = Account()
        let r = _internal_setStoryReaction(account: a, peerId: 100, id: 1, reaction: fire, knownPreviousReaction: .some(nil)).start()
        _ = replayFullStory(transaction: a.postbox.storage, peerId: 100, story: .storyItemDeleted(.init(id: 1)), storyReactionContext: a.storyReactionContext)
        a.network.requests[0].fail()
        XCTAssertNil(a.postbox.storage.stories[.init(peerId: 100, id: 1)]); XCTAssertTrue(a.network.fullRequests.isEmpty); r.dispose()
    }
    func testReconciliationCancellationAfterNetworkStartsReloadsUncertainResult() {
        let a = Account(); _ = seed(a)
        let r = _internal_setStoryReaction(account: a, peerId: 100, id: 1, reaction: fire).start(); r.dispose()
        XCTAssertEqual(a.network.fullRequests.count, 1)
        a.network.fullRequests.first?.succeed([.item(Stories.Item(id: 1, myReaction: fire))])
        XCTAssertEqual(active(a)?.myReaction, fire)
    }
    func testReconciliationDeletionDuringQueuedLookupPreventsRequest() {
        let a = Account(); _ = seed(a)
        let r = _internal_setStoryReaction(account: a, peerId: 100, id: 1, reaction: fire).start()
        a.postbox.delayAt.insert(a.postbox.count + 2)
        a.network.requests[0].fail()
        _ = replayFullStory(transaction: a.postbox.storage, peerId: 100, story: .storyItemDeleted(.init(id: 1)), storyReactionContext: a.storyReactionContext, storyRefreshContext: a.storyRefreshContext, storyViewRefreshContext: a.storyViewRefreshContext)
        a.postbox.flush(); XCTAssertTrue(a.network.fullRequests.isEmpty); XCTAssertNil(active(a)); r.dispose()
    }
    func testReconciliationSynchronousCompletionDoesNotLeaveOccupiedSlot() {
        let a = Account(); _ = seed(a); a.network.onFullRequest = { $0.fail() }
        for _ in 0..<3 {
            let r = _internal_setStoryReaction(account: a, peerId: 100, id: 1, reaction: fire).start()
            a.network.requests.last?.fail(); r.dispose()
        }
        XCTAssertEqual(a.network.fullRequests.count, 3); XCTAssertFalse(a.storyReactionReconciliationContext.isPending(.init(peerId: 100, id: 1)))
    }
    func testReconciliationSuccessfulNewReactionDuringRefreshRequestsFollowup() {
        let a = Account(); _ = seed(a)
        let first = _internal_setStoryReaction(account: a, peerId: 100, id: 1, reaction: heart).start(); a.network.requests[0].fail()
        let second = _internal_setStoryReaction(account: a, peerId: 100, id: 1, reaction: fire).start(); a.network.requests[1].succeed()
        XCTAssertEqual(a.network.fullRequests.count, 1)
        a.network.fullRequests.first?.fail(); XCTAssertEqual(a.network.fullRequests.count, 2)
        first.dispose(); second.dispose()
    }
    func testReconciliationAccountRemovalPreventsForcedQueuedWork() {
        var a: Account? = Account(); _ = seed(a!); weak var weakAccount = a
        let r = _internal_setStoryReaction(account: a!, peerId: 100, id: 1, reaction: fire).start()
        a!.postbox.delayAt.insert(a!.postbox.count + 2); let postbox = a!.postbox; let network = a!.network
        a!.network.requests[0].fail(); a = nil; XCTAssertNil(weakAccount)
        for pending in postbox.pending { pending.run() }
        XCTAssertTrue(network.fullRequests.isEmpty); r.dispose()
    }
}

extension StoryReactionMutationTests {
    func resolve(_ a: Account, ids: [Int32] = [1], peers: [Peer] = [], completed: (() -> Void)? = nil) -> Disposable {
        resolveStories(postbox: a.postbox, source: .network(a.network), accountPeerId: a.peerId, storyIds: Set(ids.map { StoryId(peerId: 100, id: $0) }), additionalPeers: AccumulatedPeers(peers: peers), result: 7).start(next: { XCTAssertEqual($0, 7) }, completed: completed)
    }
    func testResolutionMissingPeerDoesNotCacheDeletion() {
        let a = Account(); a.postbox.storage.peers.removeValue(forKey: 100)
        let d = resolve(a)
        XCTAssertNil(a.postbox.storage.stories[.init(peerId: 100, id: 1)]); XCTAssertTrue(a.network.fullRequests.isEmpty); d.dispose()
    }
    func testResolutionUnsupportedMediaIsUnresolvedWhileValidNeighborIsSaved() {
        let a = Account(); let d = resolve(a, ids: [1, 2])
        a.network.fullRequests.first?.succeed([.unsupported(1), .item(Stories.Item(id: 2))])
        XCTAssertNil(a.postbox.storage.stories[.init(peerId: 100, id: 1)])
        XCTAssertEqual(a.postbox.storage.stories[.init(peerId: 100, id: 2)]?.get(Stories.StoredItem.self), .item(Stories.Item(id: 2))); d.dispose()
    }
    func testResolutionExplicitDeletedAndAbsentStoriesCacheAbsence() {
        let a = Account(); let d = resolve(a, ids: [1, 2])
        a.network.fullRequests.first?.succeed([.storyItemDeleted(.init(id: 1))])
        for id: Int32 in [1, 2] { XCTAssertEqual(a.postbox.storage.stories[.init(peerId: 100, id: id)], CodableEntry(data: Data())) }; d.dispose()
    }
    func testResolutionCannotOverwriteStoryArrivingWhileFetchIsPending() {
        let a = Account(); let d = resolve(a)
        let fresh = Stories.Item(id: 1, text: "local newer")
        a.postbox.storage.stories[.init(peerId: 100, id: 1)] = CodableEntry(Stories.StoredItem.item(fresh))
        a.network.fullRequests.first?.succeed([.item(Stories.Item(id: 1, text: "stale"))])
        XCTAssertEqual(individual(a), fresh); d.dispose()
    }
    func testResolutionActiveStoryCopiesLocallyWithoutRequestOrReactionLoss() {
        let a = Account(); let item = Stories.Item(id: 1, myReaction: fire)
        a.postbox.storage.rows[100] = [row(.item(item))]
        let d = resolve(a)
        XCTAssertTrue(a.network.fullRequests.isEmpty); XCTAssertEqual(individual(a), item); d.dispose()
    }
    func testResolutionCachedStoryCopiesLocallyWithoutRequest() {
        let a = Account(); let item = Stories.Item(id: 1, myReaction: heart)
        cache(a, key: cacheKey(), item: item)
        let d = resolve(a)
        XCTAssertTrue(a.network.fullRequests.isEmpty); XCTAssertEqual(individual(a), item); d.dispose()
    }
    func testResolutionExistingIndividualIsNotRefetched() {
        let a = Account(); let item = Stories.Item(id: 1)
        a.postbox.storage.stories[.init(peerId: 100, id: 1)] = CodableEntry(Stories.StoredItem.item(item))
        let d = resolve(a); XCTAssertTrue(a.network.fullRequests.isEmpty); XCTAssertEqual(a.postbox.storage.storyWrites, 0); d.dispose()
    }
    func testResolutionAdditionalPeerCanResolveBeforeStoredPeerExists() {
        let a = Account(); a.postbox.storage.peers.removeValue(forKey: 100)
        let d = resolve(a, peers: [.init(id: 100)])
        XCTAssertEqual(a.network.fullRequests.count, 1)
        a.network.fullRequests.first?.succeed([.item(Stories.Item(id: 1))]); XCTAssertNotNil(individual(a)); d.dispose()
    }
    func testResolutionInvalidIdsDoNotRequestOrWrite() {
        let a = Account(); let d = resolve(a, ids: [0, -1])
        XCTAssertTrue(a.network.fullRequests.isEmpty); XCTAssertEqual(a.postbox.storage.storyWrites, 0); d.dispose()
    }
    func testResolutionSkippedItemDoesNotOverwriteUnknownWithPlaceholder() {
        let a = Account(); let d = resolve(a)
        a.network.fullRequests.first?.succeed([.placeholder(1)])
        XCTAssertNil(a.postbox.storage.stories[.init(peerId: 100, id: 1)]); d.dispose()
    }
    func testResolutionDuplicateResponseIdIsNotChosenArbitrarily() {
        let a = Account(); let d = resolve(a)
        a.network.fullRequests.first?.succeed([.item(Stories.Item(id: 1)), .storyItemDeleted(.init(id: 1))])
        XCTAssertNil(a.postbox.storage.stories[.init(peerId: 100, id: 1)]); d.dispose()
    }
    func testResolutionFailedRequestCompletesWithoutCachingAbsence() {
        let a = Account(); var complete = false; let d = resolve(a, completed: { complete = true })
        a.network.fullRequests.first?.fail()
        XCTAssertTrue(complete); XCTAssertNil(a.postbox.storage.stories[.init(peerId: 100, id: 1)]); d.dispose()
    }
    func testResolutionMediaRevalidationRejectsUnrequestedStory() {
        let a = Account(); var result: [Stories.StoredItem] = []
        let d = _internal_getStoriesById(accountPeerId: 10, postbox: a.postbox, network: a.network, peer: PeerReference(.init(id: 100))!, ids: [1]).start(next: { result = $0 })
        a.network.fullRequests.first?.succeed([.item(Stories.Item(id: 2))])
        XCTAssertTrue(result.isEmpty); d.dispose()
    }
    func testResolutionMediaRevalidationMergesMinimalStoryFields() {
        let a = Account(); let original = seed(a, previous: heart).0; var result: [Stories.StoredItem] = []
        let d = _internal_getStoriesById(accountPeerId: 10, postbox: a.postbox, network: a.network, peer: PeerReference(.init(id: 100))!, ids: [1]).start(next: { result = $0 })
        a.network.fullRequests.first?.succeed([.min(Stories.Item(id: 1, media: 123))])
        if case let .item(item) = result.first { XCTAssertEqual(item.media, 123); XCTAssertEqual(item.myReaction, heart); XCTAssertEqual(item.views, original.views) } else { XCTFail("Missing minimal story") }; d.dispose()
    }
}

extension StoryReactionMutationTests {
    func testResolutionNewerIdenticalAbsenceSupersedesOlderStoryReply() {
        let a = Account(); a.postbox.storage.stories[.init(peerId: 100, id: 1)] = CodableEntry(data: Data())
        let first = resolve(a); let second = resolve(a)
        a.network.fullRequests[1].succeed([])
        a.network.fullRequests[0].succeed([.item(Stories.Item(id: 1))])
        XCTAssertNil(individual(a)); first.dispose(); second.dispose()
    }
    func testResolutionNewerValidReplyAppliesAfterOlderReply() {
        let a = Account(); let first = resolve(a); let second = resolve(a)
        a.network.fullRequests[0].succeed([.item(Stories.Item(id: 1, text: "older"))])
        a.network.fullRequests[1].succeed([.item(Stories.Item(id: 1, text: "newer"))])
        XCTAssertEqual(individual(a)?.text, "newer"); first.dispose(); second.dispose()
    }
    func testResolutionNewerFailedRequestDoesNotDiscardOlderSuccess() {
        let a = Account(); let first = resolve(a); let second = resolve(a)
        a.network.fullRequests[1].fail(); a.network.fullRequests[0].succeed([.item(Stories.Item(id: 1))])
        XCTAssertNotNil(individual(a)); first.dispose(); second.dispose()
    }
    func testResolutionBatchesAt100AndWaitsForEveryBatch() {
        let a = Account(); var completed = false
        let d = resolve(a, ids: Array(1...201), completed: { completed = true })
        XCTAssertEqual(a.network.fullRequests.map { $0.data.ids.count }.sorted(), [1, 100, 100])
        XCTAssertFalse(completed)
        for (index, request) in a.network.fullRequests.enumerated() {
            request.succeed(request.data.ids.map { .item(Stories.Item(id: $0)) })
            XCTAssertEqual(completed, index == 2)
        }
        XCTAssertEqual(a.postbox.storage.stories.count, 201); d.dispose()
    }
    func testResolutionCancelledQueuedCommitCannotWriteEvenIfForced() {
        let a = Account(); let d = resolve(a)
        a.postbox.delayAt.insert(a.postbox.count + __RESOLUTION_COMMIT_OFFSET__)
        a.network.fullRequests.first?.succeed([.item(Stories.Item(id: 1))])
        XCTAssertEqual(a.postbox.pending.count, 1); d.dispose()
        for pending in a.postbox.pending { pending.run() }
        XCTAssertNil(individual(a)); XCTAssertEqual(a.postbox.storage.storyWrites, 0)
    }
    func testResolutionCancellationBeforeLocalCopyCannotWrite() {
        let a = Account(); a.postbox.storage.rows[100] = [row(.item(Stories.Item(id: 1)))]; a.postbox.delayAt = [1]
        let d = resolve(a); d.dispose()
        for pending in a.postbox.pending { pending.run() }
        XCTAssertNil(individual(a)); XCTAssertEqual(a.postbox.storage.storyWrites, 0)
    }
}

extension StoryReactionMutationTests {
    func testResolutionServerDeletionWithoutStoredValueInvalidatesPendingReply() {
        let a = Account(); let d = resolve(a)
        _ = replayFullStory(postbox: a.postbox, transaction: a.postbox.storage, peerId: 100, story: .storyItemDeleted(.init(id: 1)))
        a.network.fullRequests[0].succeed([.item(Stories.Item(id: 1))])
        XCTAssertNil(individual(a)); XCTAssertEqual(a.postbox.storage.storyWrites, 0); d.dispose()
    }
    func testResolutionServerReactionWithoutStoredValueInvalidatesPendingReply() {
        let a = Account(); let d = resolve(a)
        _ = replayReaction(postbox: a.postbox, transaction: a.postbox.storage, peerId: 100, id: 1, reaction: .custom(27))
        a.network.fullRequests[0].succeed([.item(Stories.Item(id: 1))])
        XCTAssertNil(individual(a)); d.dispose()
    }
    func testResolutionLocalReactionWithoutStoredValueInvalidatesPendingReply() {
        let a = Account(); let d = resolve(a)
        let reaction = _internal_setStoryReaction(account: a, peerId: 100, id: 1, reaction: fire).start()
        a.network.fullRequests[0].succeed([.item(Stories.Item(id: 1))])
        XCTAssertNil(individual(a)); reaction.dispose(); d.dispose()
    }
    func testResolutionOtherPeerDeletionDoesNotInvalidatePendingReply() {
        let a = Account(); let d = resolve(a)
        _ = replayFullStory(postbox: a.postbox, transaction: a.postbox.storage, peerId: 10, story: .storyItemDeleted(.init(id: 1)))
        a.network.fullRequests[0].succeed([.item(Stories.Item(id: 1))])
        XCTAssertNotNil(individual(a)); d.dispose()
    }
    func testResolutionNewerUnsupportedReplyDoesNotDiscardOlderSuccess() {
        let a = Account(); let first = resolve(a); let second = resolve(a)
        a.network.fullRequests[1].succeed([.unsupported(1)])
        a.network.fullRequests[0].succeed([.item(Stories.Item(id: 1))])
        XCTAssertNotNil(individual(a)); first.dispose(); second.dispose()
    }
    func testResolutionNewerCancelledRequestDoesNotDiscardOlderSuccess() {
        let a = Account(); let first = resolve(a); let second = resolve(a); second.dispose()
        a.network.fullRequests[0].succeed([.item(Stories.Item(id: 1))])
        XCTAssertNotNil(individual(a)); first.dispose()
    }
    func testResolutionIndependentPostboxesDoNotShareOrdering() {
        let a = Account(); let b = Account(); let first = resolve(a); let second = resolve(b)
        b.network.fullRequests[0].succeed([])
        a.network.fullRequests[0].succeed([.item(Stories.Item(id: 1))])
        XCTAssertNotNil(individual(a)); XCTAssertNil(individual(b)); first.dispose(); second.dispose()
    }
    func testResolutionLeaseFinishesOnlyItsOwnTicket() {
        let a = Account(); let snapshots = [Int32(1): StoryRefreshSnapshot(transaction: a.postbox.storage, peerId: 100, id: 1)]
        var first: StoryResolutionLease? = StoryResolutionLease(postbox: a.postbox, peerId: 100, snapshots: snapshots)
        var second: StoryResolutionLease? = StoryResolutionLease(postbox: a.postbox, peerId: 100, snapshots: snapshots)
        let context = first!.context; XCTAssertTrue(context === second!.context)
        first = nil; XCTAssertTrue(context.isPending(.init(peerId: 100, id: 1)))
        second = nil; XCTAssertFalse(context.isPending(.init(peerId: 100, id: 1)))
    }
    func testResolutionRegistryDoesNotOwnPostboxOrIdleContext() {
        var postbox: Postbox? = Postbox(); weak var weakPostbox = postbox
        var lease: StoryResolutionLease? = StoryResolutionLease(postbox: postbox!, peerId: 100, snapshots: [:])
        weak var weakContext = lease?.context
        postbox = nil; XCTAssertNil(weakPostbox)
        lease = nil; XCTAssertNil(weakContext)
    }
    func testResolutionFullRefreshDeletionInvalidatesPendingReply() {
        let a = Account(); let d = resolve(a)
        let refresh = _internal_refreshStories(account: a, peerId: 100, ids: [1]).start()
        a.network.fullRequests[1].succeed([])
        a.network.fullRequests[0].succeed([.item(Stories.Item(id: 1))])
        XCTAssertNil(individual(a)); refresh.dispose(); d.dispose()
    }
}

extension StoryReactionMutationTests {
    func testResolutionQueuedMinimalReplyMergesAtCommit() {
        let a = Account(); let first = resolve(a); let second = resolve(a)
        a.postbox.delayAt.insert(a.postbox.count + __RESOLUTION_COMMIT_OFFSET__)
        a.network.fullRequests[0].succeed([.item(Stories.Item(id: 1, views: countViews(20), myReaction: heart))])
        a.postbox.delayAt.insert(a.postbox.count + __RESOLUTION_COMMIT_OFFSET__)
        a.network.fullRequests[1].succeed([.min(Stories.Item(id: 1, text: "newer", isMy: false))])
        XCTAssertEqual(a.postbox.pending.count, 2)
        a.postbox.pending[0].deliver(); a.postbox.pending[1].deliver()
        XCTAssertEqual(individual(a)?.text, "newer")
        XCTAssertEqual(individual(a)?.myReaction, heart)
        XCTAssertEqual(individual(a)?.views, countViews(20))
        first.dispose(); second.dispose()
    }
}

extension StoryReactionMutationTests {
    func testResolutionCompletedRequestReleasesOrderingContext() {
        let a = Account(); let d = resolve(a)
        weak var context: StoryRefreshContext?
        autoreleasepool { context = StoryResolutionContextRegistry.shared.context(for: a.postbox, create: false) }
        XCTAssertNotNil(context); a.network.fullRequests[0].succeed([.item(Stories.Item(id: 1))])
        XCTAssertNil(context); d.dispose()
    }
    func testResolutionFailedRequestReleasesOrderingContext() {
        let a = Account(); let d = resolve(a)
        weak var context: StoryRefreshContext?
        autoreleasepool { context = StoryResolutionContextRegistry.shared.context(for: a.postbox, create: false) }
        XCTAssertNotNil(context); a.network.fullRequests[0].fail()
        XCTAssertNil(context); d.dispose()
    }
    func testResolutionCancelledRequestReleasesOrderingContext() {
        let a = Account(); let d = resolve(a)
        weak var context: StoryRefreshContext?
        autoreleasepool { context = StoryResolutionContextRegistry.shared.context(for: a.postbox, create: false) }
        XCTAssertNotNil(context); d.dispose(); XCTAssertNil(context)
    }
    func testResolutionQueuedCommitRetainsOrderingUntilTransactionCompletes() {
        let a = Account(); let d = resolve(a)
        weak var context: StoryRefreshContext?
        autoreleasepool { context = StoryResolutionContextRegistry.shared.context(for: a.postbox, create: false) }
        a.postbox.delayAt.insert(a.postbox.count + __RESOLUTION_COMMIT_OFFSET__)
        a.network.fullRequests[0].succeed([.item(Stories.Item(id: 1))])
        XCTAssertNotNil(context); XCTAssertNil(individual(a))
        a.postbox.flush(); a.postbox.pending.removeAll()
        XCTAssertNil(context); XCTAssertNotNil(individual(a)); d.dispose()
    }
}

extension StoryReactionMutationTests {
    func testServerDeletionInvalidatesUnchangedPendingPeerPoll() {
        let a = Account(); let lease = PeerStoryPollLease(postbox: a.postbox, peerId: 100, items: [])
        _ = replayFullStory(postbox: a.postbox, transaction: a.postbox.storage, peerId: 100, story: .storyItemDeleted(.init(id: 1)))
        XCTAssertFalse(lease.context.take(peerId: 100, id: lease.id, items: []))
    }
    func testServerReactionInvalidatesUnchangedPendingPeerPoll() {
        let a = Account(); let lease = PeerStoryPollLease(postbox: a.postbox, peerId: 100, items: [])
        _ = replayReaction(postbox: a.postbox, transaction: a.postbox.storage, peerId: 100, id: 1, reaction: .custom(27))
        XCTAssertFalse(lease.context.take(peerId: 100, id: lease.id, items: []))
    }
    func testLocalReactionInvalidatesUnchangedPendingPeerPoll() {
        let a = Account(); let lease = PeerStoryPollLease(postbox: a.postbox, peerId: 100, items: [])
        let d = _internal_setStoryReaction(account: a, peerId: 100, id: 1, reaction: heart).start()
        XCTAssertFalse(lease.context.take(peerId: 100, id: lease.id, items: [])); d.dispose()
    }
    func testAssociatedStoryResolutionInvalidatesUnchangedPendingPeerPoll() {
        let a = Account(); let lease = PeerStoryPollLease(postbox: a.postbox, peerId: 100, items: []); let d = resolve(a)
        a.network.fullRequests[0].succeed([.item(.init(id: 1))])
        XCTAssertFalse(lease.context.take(peerId: 100, id: lease.id, items: [])); d.dispose()
    }
    func testFullRefreshDeletionInvalidatesUnchangedPendingPeerPoll() {
        let a = Account(); let lease = PeerStoryPollLease(postbox: a.postbox, peerId: 100, items: [])
        let d = _internal_refreshStories(account: a, peerId: 100, ids: [1]).start(); a.network.fullRequests[0].succeed([])
        XCTAssertFalse(lease.context.take(peerId: 100, id: lease.id, items: [])); d.dispose()
    }
    func testOtherPeerResolutionDoesNotInvalidatePendingPeerPoll() {
        let a = Account(); let lease = PeerStoryPollLease(postbox: a.postbox, peerId: 10, items: []); let d = resolve(a)
        a.network.fullRequests[0].succeed([.item(.init(id: 1))])
        XCTAssertTrue(lease.context.take(peerId: 10, id: lease.id, items: [])); d.dispose()
    }
}

__PEER_POLL__
extension StoryReactionMutationTests {
    func poll(_ a: Account) -> Disposable {
        _internal_pollPeerStories(postbox: a.postbox, network: a.network, accountPeerId: a.peerId, peerId: 100, stateManager: a.stateManager).start()
    }
    func testPollStartedDuringPendingReactionPreservesOptimisticChoice() {
        let a = Account(); let original = seed(a, previous: heart).0
        let r = _internal_setStoryReaction(account: a, peerId: 100, id: 1, reaction: fire).start(); let p = poll(a)
        var reply = original; reply.text = "new caption"; a.network.pollRequests[0].succeed([.item(reply)])
        XCTAssertEqual(active(a)?.myReaction, fire); XCTAssertEqual(active(a)?.text, "new caption")
        XCTAssertEqual(active(a)?.views, individual(a)?.views)
        a.network.requests[0].succeed(); XCTAssertEqual(a.network.fullRequests.count, 1); p.dispose(); r.dispose()
    }
    func testPollStartedDuringPendingReactionRemovalPreservesNilChoice() {
        let a = Account(); let original = seed(a, previous: heart).0
        let r = _internal_setStoryReaction(account: a, peerId: 100, id: 1, reaction: nil).start(); let p = poll(a)
        a.network.pollRequests[0].succeed([.item(original)])
        XCTAssertNil(active(a)?.myReaction); XCTAssertEqual(active(a)?.views, individual(a)?.views); p.dispose(); r.dispose()
    }
    func testPollAfterReactionSettlementUsesAuthoritativeReaction() {
        let a = Account(); var original = seed(a, previous: heart).0
        let r = _internal_setStoryReaction(account: a, peerId: 100, id: 1, reaction: fire).start(); a.network.requests[0].succeed()
        let p = poll(a); original.myReaction = .custom(27); a.network.pollRequests[0].succeed([.item(original)])
        XCTAssertEqual(active(a)?.myReaction, .custom(27)); p.dispose(); r.dispose()
    }
    func testPollDoesNotRetainAccountOrStateManager() {
        var a: Account? = Account(); weak var weakAccount = a; weak var weakManager = a?.stateManager
        let p = poll(a!); let network = a!.network; a = nil
        XCTAssertNil(weakAccount); XCTAssertNil(weakManager); p.dispose(); XCTAssertNil(network.pollRequests[0].subscriber)
    }
}

extension StoryReactionMutationTests {
    func testPollExplicitDeletionClearsIndividualAndDiscoverableCaches() {
        let a = Account(); let original = seed(a).0
        let keys = [cacheKey(), cacheKey(archived: 1), cacheKey(album: 7), cacheKey(archived: 1, album: 8)]
        for key in keys { cache(a, key: key, item: original) }
        let p = poll(a); a.network.pollRequests[0].succeed([.storyItemDeleted(.init(id: 1))])
        XCTAssertNil(active(a)); XCTAssertNil(individual(a))
        for key in keys {
            let head = a.postbox.storage.cache[key]?.get(CachedPeerStoryListHead.self)
            XCTAssertFalse(head?.items.contains(where: { $0.id == 1 }) ?? true)
            XCTAssertEqual(head?.totalCount, 56); XCTAssertEqual(head?.pinnedIds, [90])
        }
        XCTAssertEqual(a.stateManager.updates.count, 1)
        if case let .deleted(peerId, id) = a.stateManager.updates.first { XCTAssertEqual(peerId, 100); XCTAssertEqual(id, 1) } else { XCTFail("Missing deletion update") }
        p.dispose()
    }
    func testPollOmissionPreservesArchivedIndividualAndCacheWithoutDeletionEvent() {
        let a = Account(); let original = seed(a).0; cache(a, key: cacheKey(archived: 1), item: original)
        let p = poll(a); a.network.pollRequests[0].succeed([])
        XCTAssertNil(active(a)); XCTAssertNotNil(individual(a)); XCTAssertNotNil(cached(a, key: cacheKey(archived: 1)))
        XCTAssertTrue(a.stateManager.updates.isEmpty); p.dispose()
    }
    func testPollDeletionPublishesOnlyAfterStorageCommit() {
        let a = Account(); _ = seed(a); var observed = false
        a.stateManager.onUpdate = { observed = true; XCTAssertNil(self.active(a)); XCTAssertNil(self.individual(a)) }
        let p = poll(a); a.network.pollRequests[0].succeed([.storyItemDeleted(.init(id: 1))])
        XCTAssertTrue(observed); p.dispose()
    }
    func testPollDeletionCommitStillPublishesIfCancelledBeforeDelivery() {
        let a = Account(); _ = seed(a); let p = poll(a)
        a.postbox.afterTransaction = { p.dispose() }
        a.network.pollRequests[0].succeed([.storyItemDeleted(.init(id: 1))])
        XCTAssertNil(individual(a)); XCTAssertEqual(a.stateManager.updates.count, 1); a.postbox.afterTransaction = nil
    }
    func testPollDeletionInvalidatesPendingAssociatedResolutionWithNoStoredValue() {
        let a = Account(); let r = resolve(a); let p = poll(a)
        a.network.pollRequests[0].succeed([.storyItemDeleted(.init(id: 1))])
        a.network.fullRequests[0].succeed([.item(.init(id: 1))]); XCTAssertNil(individual(a)); p.dispose(); r.dispose()
    }
    func testPollDeletionInvalidatesPendingFullRefreshWithNoStoredValue() {
        let a = Account(); let r = _internal_refreshStories(account: a, peerId: 100, ids: [1]).start(); let p = poll(a)
        a.network.pollRequests[0].succeed([.storyItemDeleted(.init(id: 1))])
        a.network.fullRequests[0].succeed([.item(.init(id: 1))]); XCTAssertNil(individual(a)); p.dispose(); r.dispose()
    }
    func testPollDeletionDoesNotRetireNewerPollTicket() {
        let a = Account(); _ = seed(a); let p = poll(a); let newer = poll(a)
        a.network.pollRequests[0].succeed([.storyItemDeleted(.init(id: 1))])
        a.network.pollRequests[1].succeed([.item(.init(id: 2))])
        XCTAssertEqual(active(a)?.id, 2); p.dispose(); newer.dispose()
    }
    func testPollDeletionDuringPendingReactionPreventsRollbackResurrection() {
        let a = Account(); _ = seed(a, previous: heart)
        let r = _internal_setStoryReaction(account: a, peerId: 100, id: 1, reaction: fire).start(); let p = poll(a)
        a.network.pollRequests[0].succeed([.storyItemDeleted(.init(id: 1))]); a.network.requests[0].fail()
        XCTAssertNil(individual(a)); XCTAssertTrue(a.network.fullRequests.isEmpty); p.dispose(); r.dispose()
    }
}

extension StoryReactionMutationTests {
    func testPollDeletionBatchKeepsAlbumDiscoveryUntilAllDeletedItemsAreRemoved() {
        let a = Account(); let first = Stories.Item(id: 1, folderIds: [7]); let second = Stories.Item(id: 2)
        a.postbox.storage.rows[100] = [row(.item(first)), row(.item(second))]
        let key = cacheKey(album: 7)
        a.postbox.storage.cache[key] = CodableEntry(CachedPeerStoryListHead(items: [.item(first), .item(second)], pinnedIds: [1, 2], totalCount: 2, folders: []))
        let p = poll(a); a.network.pollRequests[0].succeed([.storyItemDeleted(.init(id: 1)), .storyItemDeleted(.init(id: 2))])
        let head = a.postbox.storage.cache[key]?.get(CachedPeerStoryListHead.self)
        XCTAssertEqual(head?.items, []); XCTAssertEqual(head?.pinnedIds, []); XCTAssertEqual(head?.totalCount, 0); p.dispose()
    }
    func testPollDuplicateDeletionKeepsKnownCopiesAndDoesNotPublish() {
        let a = Account(); let original = seed(a).0; let key = cacheKey(archived: 1); cache(a, key: key, item: original)
        let p = poll(a); a.network.pollRequests[0].succeed([.storyItemDeleted(.init(id: 1)), .item(original)])
        XCTAssertNotNil(active(a)); XCTAssertNotNil(individual(a)); XCTAssertNotNil(cached(a, key: key)); XCTAssertTrue(a.stateManager.updates.isEmpty); p.dispose()
    }
    func testPollDefaultPublicPathClearsDeletionCopiesWithoutManager() {
        let a = Account(); let original = seed(a).0; let key = cacheKey(archived: 1); cache(a, key: key, item: original)
        let p = _internal_pollPeerStories(postbox: a.postbox, network: a.network, accountPeerId: a.peerId, peerId: 100).start()
        a.network.pollRequests[0].succeed([.storyItemDeleted(.init(id: 1))])
        XCTAssertNil(active(a)); XCTAssertNil(individual(a)); XCTAssertNil(cached(a, key: key)); p.dispose()
    }
    func testPollCancelledQueuedDeletionPreservesCopiesAndDoesNotPublish() {
        let a = Account(); _ = seed(a); let p = poll(a); a.postbox.delayAt.insert(a.postbox.count + 1)
        a.network.pollRequests[0].succeed([.storyItemDeleted(.init(id: 1))]); p.dispose()
        for pending in a.postbox.pending { pending.run() }
        XCTAssertNotNil(active(a)); XCTAssertNotNil(individual(a)); XCTAssertTrue(a.stateManager.updates.isEmpty)
    }
}

extension StoryReactionMutationTests {
    func testFullRefreshDeletionBatchKeepsAlbumDiscovery() {
        let a = Account(); let first = Stories.Item(id: 1, folderIds: [7]); let second = Stories.Item(id: 2)
        a.postbox.storage.rows[100] = [row(.item(first)), row(.item(second))]
        let key = cacheKey(album: 7)
        a.postbox.storage.cache[key] = CodableEntry(CachedPeerStoryListHead(items: [.item(first), .item(second)], pinnedIds: [1, 2], totalCount: 2, folders: []))
        let d = _internal_refreshStories(account: a, peerId: 100, ids: [1, 2]).start()
        a.network.fullRequests[0].succeed([])
        let head = a.postbox.storage.cache[key]?.get(CachedPeerStoryListHead.self)
        XCTAssertEqual(head?.items, []); XCTAssertEqual(head?.pinnedIds, []); XCTAssertEqual(head?.totalCount, 0); d.dispose()
    }
}
