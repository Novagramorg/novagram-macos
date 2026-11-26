import Foundation
import XCTest
import SwiftSignalKit

typealias PeerId = Int
extension Int { static var stars: Int { -123456 }; var namespace: Int { self >= 100 ? 1 : 0 }; func toInt64() -> Int64 { Int64(self) } }
struct EngineMedia: Equatable { let value: Int; init(_ value: Int) { self.value = value } }
struct EngineStoryPrivacy: Equatable { let value: Int; init(_ value: Int) { self.value = value } }
struct Peer { let id: Int }
struct PeerReference: Equatable { let id: Int; init(_ peer: Peer) { id = peer.id } }
struct EnginePeer: Equatable { typealias Id = Int; let id: Int; init(_ peer: Peer) { id = peer.id } }
struct StoryId: Equatable, Hashable { let peerId: Int; let id: Int32 }
struct EngineStoryItem: Equatable {
    struct Views: Equatable { let seenCount: Int; let reactedCount: Int; let forwardCount: Int; let seenPeers: [EnginePeer]; let reactions: [MessageReaction]; let hasList: Bool }
    struct ForwardInfo: Equatable { init(_ info: Stories.ForwardInfo, transaction: Transaction) {}
        init(_ info: Stories.ForwardInfo, peers: [Int: Peer]) {} }
    var id: Int32
    var timestamp = 0
    var expirationTimestamp = 100
    var media = EngineMedia(1)
    var alternativeMediaList: [EngineMedia] = []
    var mediaAreas: [Area] = []
    var text = "old"
    var entities: [Entity] = []
    var views: Views? = nil
    var privacy: EngineStoryPrivacy? = nil
    var isPinned = true
    var isExpired = false
    var isPublic = true
    var isPending = false
    var isCloseFriends = false
    var isContacts = false
    var isSelectedContacts = false
    var isForwardingDisabled = false
    var isEdited = false
    var isMy = true
    var myReaction: Int? = nil
    var forwardInfo: ForwardInfo? = nil
    var music: EngineMedia? = nil
    var author: EnginePeer? = nil
    var folderIds: [Int64]? = nil
    func asStoryItem() -> Stories.Item { .init(id: id, text: text, views: views.map { .init(seenCount:$0.seenCount,reactedCount:$0.reactedCount,forwardCount:$0.forwardCount,seenPeerIds:$0.seenPeers.map(\.id),reactions:$0.reactions,hasList:$0.hasList) }, myReaction:myReaction, folderIds: folderIds) }
}
typealias MessageTextEntity = Entity
typealias MediaArea = Area
struct MediaId: Hashable { let namespace: Int; let id: Int64 }
typealias TelegramMediaFile = Int
extension Int { var fileId: MediaId { .init(namespace: 1,id: Int64(self)) } }
struct Entity: Equatable { enum Kind: Equatable { case CustomEmoji(Int,Int64) }; let type: Kind }
enum Reaction: Equatable { case custom(Int64) }
enum Area: Equatable { case reaction(Int,Reaction,Int) }
struct StoryListContextState {
    struct Item { let id: StoryId; let storyItem: EngineStoryItem; var peer: EnginePeer? = nil }
    struct Folder: Equatable { let id: Int64; let title: String }
    var peerReference: PeerReference? = nil
    var items: [Item] = []
    var availableLanguages: [String] = []
    var availableFolders: [Folder] = []
    var pinnedIds: [Int32] = []
    var totalCount = 0
    var loadMoreToken: AnyHashable? = AnyHashable(0)
    var isCached = false
    var hasCache = false
    var allEntityFiles: [MediaId: TelegramMediaFile] = [:]
    var isLoading = false

}
enum StoryListContext { typealias State = StoryListContextState }
struct MessageReaction: Equatable, ExpressibleByIntegerLiteral {
    typealias Reaction = Int
    var value: Int
    var count: Int32
    var chosenOrder: Int?
    init(value: Int, count: Int32, chosenOrder: Int?) { self.value=value; self.count=count; self.chosenOrder=chosenOrder }
    init(integerLiteral value: Int) { self.init(value:value,count:1,chosenOrder:nil) }
}
__REACTION_REDUCER__
enum Stories {
    enum ForwardInfo { case known(Int, Int32, Bool) }
    struct Item {
        struct Views { var seenCount = 0; var reactedCount = 0; var forwardCount = 0; var seenPeerIds: [Int] = []; var reactions: [MessageReaction] = []; var hasList = false; __VIEWS_EMPTY__ }
        var id: Int32
        var timestamp = 0
        var expirationTimestamp = 100
        var media: Int? = 1
        var alternativeMediaList: [Int] = []
        var mediaAreas: [Area] = []
        var text = "old"
        var entities: [Entity] = []
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
        var myReaction: Int? = nil
        var forwardInfo: Stories.ForwardInfo? = nil
        var music: Int? = nil
        var authorId: Int? = nil
        var folderIds: [Int64]? = nil
    }
    enum StoredItem {
        case item(Item), placeholder(Int32)
        var id: Int32 { switch self { case let .item(item): return item.id; case let .placeholder(id): return id } }
        init?(apiStoryItem: Api.StoryItem, peerId: Int, transaction: Transaction) {
            switch apiStoryItem {
            case let .item(item): self = .item(item)
            case let .placeholder(id): self = .placeholder(id)
            case .deleted: return nil
            }
        }
    }
}
struct CodableEntry { let value: Any; init?(_ value: Any) { self.value = value }; func get<T>(_ type: T.Type) -> T? { value as? T } }
struct CachedPeerStoryListHead { let items: [Stories.StoredItem]; let pinnedIds: [Int32]; let totalCount: Int32; let folders: [StoryListContextState.Folder] }
final class ValueBoxKey: Hashable {
    let length: Int; var fields: [Int: Int64] = [:]
    init(length: Int) { self.length = length }
    func setInt64(_ offset: Int, value: Int64) { fields[offset] = value }
    func setInt8(_ offset: Int, value: Int8) { fields[offset] = Int64(value) }
    static func ==(lhs: ValueBoxKey, rhs: ValueBoxKey) -> Bool { lhs.length == rhs.length && lhs.fields == rhs.fields }
    func hash(into hasher: inout Hasher) { hasher.combine(length); for k in fields.keys.sorted() { hasher.combine(k); hasher.combine(fields[k]) } }
}
struct ItemCacheEntryId: Hashable { let collectionId: Int; let key: ValueBoxKey }
enum Namespaces { enum Peer { static let CloudChannel = 1 }; enum Media { static let CloudFile = 1 }; enum CachedItemCollection { static let cachedPeerStoryListHeads = 1 } }
final class Transaction {
    var peer: Peer? = .init(id: 10)
    var cache: [ItemCacheEntryId: CodableEntry] = [:]
    var writes = 0
    var media: [MediaId: Int] = [:]
    func getMedia(_ id: MediaId) -> Any? { media[id] }
    var extraPeers: [Int: Peer] = [:]
    func getPeer(_ id: Int) -> Peer? { peer?.id == id ? peer : extraPeers[id] }
    func retrieveItemCacheEntry(id: ItemCacheEntryId) -> CodableEntry? { cache[id] }
    func putItemCacheEntry(id: ItemCacheEntryId, entry: CodableEntry) { cache[id] = entry; writes += 1 }
    func removeItemCacheEntry(id: ItemCacheEntryId) { cache.removeValue(forKey: id); writes += 1 }
}
final class Postbox {
    final class Pending {
        var active = true
        let action: () -> Void
        init(_ action: @escaping () -> Void) { self.action = action }
        func run() { if active { active = false; action() } }
    }
    let storage = Transaction()
    var hold = false
    var delayAt: Set<Int> = []
    var delayDeliveryAt: Set<Int> = []
    var pending: [Pending] = []
    var subscriptions = 0
    func transaction<T>(_ f: @escaping (Transaction) -> T) -> Signal<T, NoError> {
        Signal { subscriber in
            self.subscriptions += 1
            let run: () -> Void
            if self.delayDeliveryAt.contains(self.subscriptions) {
                let value = f(self.storage)
                run = { subscriber.putNext(value); subscriber.putCompletion() }
            } else {
                run = { subscriber.putNext(f(self.storage)); subscriber.putCompletion() }
            }
            if self.hold || self.delayDeliveryAt.contains(self.subscriptions) || self.delayAt.contains(self.subscriptions) {
                let operation = Pending(run); self.pending.append(operation)
                return ActionDisposable { operation.active = false }
            }
            run(); return EmptyDisposable
        }
    }
    func flush() {
        var index = 0
        while index < pending.count && index < 100 { pending[index].run(); index += 1 }
    }
}
struct AccumulatedPeers { init(transaction: Transaction, chats: [Int], users: [Int]) {} }
func updatePeers(transaction: Transaction, accountPeerId: Int, peers: AccumulatedPeers) {}
func apiInputPeer(_ peer: Peer) -> Api.InputPeer? { peer.id > 0 ? .init(id: peer.id) : nil }
enum Api {
    struct MediaArea {}
    struct PeerValue { let peerId: Int }
    struct FoundStoryData { let peer: PeerValue; let story: StoryItem }
    enum FoundStory { case foundStory(FoundStoryData) }
    struct InputPeer { let id: Int }
    enum StoryItem {
        case item(Stories.Item), placeholder(Int32), deleted(Int32)
        var id: Int32 { switch self { case let .item(item): return item.id; case let .placeholder(id), let .deleted(id): return id } }
    }
    struct AlbumData { let albumId: Int32; let title: String; var iconPhoto: Int? = nil; var iconVideo: Int? = nil }
    enum StoryAlbum { case storyAlbum(AlbumData) }
    enum stories {
        struct FoundStoriesData { let count: Int32; let stories: [FoundStory]; let nextOffset: String?; var chats: [Int] = []; var users: [Int] = [] }
        enum FoundStories { case foundStories(FoundStoriesData) }
        struct StoriesData { let count: Int32; let stories: [Api.StoryItem]; let pinnedToTop: [Int32]?; var chats: [Int] = []; var users: [Int] = [] }
        struct AlbumsData { let albums: [StoryAlbum] }
        enum Stories { case stories(StoriesData) }
        enum Albums { case albums(AlbumsData), albumsNotModified }
    }
    enum functions { enum stories {
        static func searchPosts(flags: Int32, hashtag: String?, area: Api.MediaArea?, peer: InputPeer?, offset: String, limit: Int32) -> RequestData<Api.stories.FoundStories> { .init(kind: "search", offset: 0, peer: peer?.id ?? 0, searchOffset: offset) }
        static func getAlbumStories(peer: InputPeer, albumId: Int32, offset: Int32, limit: Int32) -> RequestData<Api.stories.Stories> { .init(kind: "album", offset: Int(offset), peer: peer.id, album: albumId) }
        static func getStoriesArchive(peer: InputPeer, offsetId: Int32, limit: Int32) -> RequestData<Api.stories.Stories> { .init(kind: "archive", offset: Int(offsetId), peer: peer.id) }
        static func getPinnedStories(peer: InputPeer, offsetId: Int32, limit: Int32) -> RequestData<Api.stories.Stories> { .init(kind: "profile", offset: Int(offsetId), peer: peer.id) }
        static func getAlbums(peer: InputPeer, hash: Int) -> RequestData<Api.stories.Albums> { .init(kind: "folders", offset: 0, peer: peer.id) }
    } }
}
struct MTRpcError: Error { init() {}; init(errorCode: Int32, errorDescription: String) {} }
struct RequestData<T> { let kind: String; let offset: Int; let peer: Int; var album: Int32? = nil; var searchOffset: String = "" }
final class Request {
    let kind: String; let offset: Int; let peer: Int; let album: Int32?; let searchOffset: String
    var next: ((Any) -> Void)?; var error: (() -> Void)?; var completed: (() -> Void)?
    var cancelled = false
    init<T>(_ data: RequestData<T>) { kind = data.kind; offset = data.offset; peer = data.peer; album = data.album; searchOffset = data.searchOffset }
    func succeed(_ result: Any) { next?(result); completed?() }
    func fail() { error?() }
    func empty() { completed?() }
}
final class Network {
    var requests: [Request] = []
    var onRequest: ((Request) -> Void)?
    func request<T>(_ data: RequestData<T>) -> Signal<T, MTRpcError> {
        Signal { subscriber in
            let request = Request(data); request.next = { subscriber.putNext($0 as! T) }; request.error = { subscriber.putError(.init()) }; request.completed = subscriber.putCompletion
            self.requests.append(request); self.onRequest?(request)
            return ActionDisposable { request.cancelled = true; request.next = nil; request.error = nil; request.completed = nil }
        }
    }
}
enum InternalStoryUpdate {
    case added(peerId: Int, item: Stories.StoredItem)
    case deleted(peerId: Int, id: Int32)
    case updatePinnedToTopList(peerId: Int, ids: [Int32])
    case updateAlbumMembership(peerId: Int, albumId: Int64, added: [Int32], removed: [Int32])
    case updateAlbumOrder(peerId: Int, albumId: Int64)
    case read(peerId: Int, maxId: Int32)
    case updateViews(peerId: Int, views: [Int32: Stories.Item.Views])
    case updateMyReaction(peerId: Int, id: Int32, reaction: Int?)
}
final class StateManager {
    let pipe = ValuePipe<[InternalStoryUpdate]>()
    var subscribers = 0
    var storyUpdates: Signal<[InternalStoryUpdate], NoError> {
        Signal { [weak self] subscriber in
            guard let self else { return EmptyDisposable }
            self.subscribers += 1
            let d = self.pipe.signal().start(next: subscriber.putNext)
            return ActionDisposable { [weak self] in d.dispose(); self?.subscribers -= 1 }
        }
    }
    func send(_ updates: [InternalStoryUpdate]) { pipe.putNext(updates) }
}
final class Account { let peerId = 10; let postbox = Postbox(); let network = Network(); let stateManager = StateManager() }

func apiMediaAreasFromMediaAreas(_ areas: [MediaArea], transaction: Transaction?) -> [Api.MediaArea] { areas.isEmpty ? [] : [.init()] }
enum Source { case hashtag(Int?, String), mediaArea(MediaArea) }
__HELPERS__
__CONTEXT__

final class StorySearchUpdatesTests: XCTestCase {
    func context(_ a: Account = Account(), source: Source = .hashtag(nil, "test")) -> SearchContext { SearchContext(queue: .mainQueue(), account: a, source: source) }
    func page(_ ids: [Int32], next: String? = nil, text: String = "page", count: Int32 = 100) -> Api.stories.FoundStories {
        .foundStories(.init(count: count, stories: ids.map { .foundStory(.init(peer: .init(peerId: 10), story: .item(.init(id: $0, text: text)))) }, nextOffset: next))
    }
    func ready(_ a: Account = Account(), next: String? = "next") -> SearchContext {
        let c = context(a); a.network.requests[0].succeed(page([1,2], next: next)); return c
    }
    func added(_ id: Int32 = 1, text: String) -> InternalStoryUpdate { .added(peerId: 10, item: .item(.init(id: id, text: text))) }
    func testSubscribesBeforeFirstPage() {
        let a = Account(); let c = context(a); XCTAssertEqual(a.stateManager.subscribers, 1); _ = c
    }
    func testDeletionBeforeInitialPageDoesNotResurrectResult() {
        let a = Account(); let c = context(a); a.stateManager.send([.deleted(peerId: 10, id: 1)])
        a.network.requests[0].succeed(page([1,2])); a.postbox.flush()
        XCTAssertEqual(c.stateValue.items.map { $0.id.id }, [2])
    }
    func testEditBeforeInitialPageIsReplayedOntoResult() {
        let a = Account(); let c = context(a); a.stateManager.send([added(text: "newer")])
        a.network.requests[0].succeed(page([1])); a.postbox.flush()
        XCTAssertEqual(c.stateValue.items.first?.storyItem.text, "newer")
    }
    func testDelayedUpdateLookupsCannotReverseEventOrder() {
        let a = Account(); let c = ready(a); a.postbox.hold = true
        a.stateManager.send([added(text: "first")]); a.stateManager.send([added(text: "second")])
        if a.postbox.pending.count > 1 { a.postbox.pending[1].run() }
        a.postbox.pending[0].run(); a.postbox.flush()
        XCTAssertEqual(c.stateValue.items.first?.storyItem.text, "second")
    }
    func testClosingSearchCancelsPendingUpdateLookup() {
        let a = Account(); var c: SearchContext? = ready(a); weak var weakContext = c; a.postbox.hold = true
        a.stateManager.send([added(text: "late")]); XCTAssertFalse(a.postbox.pending.isEmpty)
        c = nil; XCTAssertNil(weakContext); XCTAssertEqual(a.stateManager.subscribers, 0)
        XCTAssertTrue(a.postbox.pending.allSatisfy { !$0.active })
    }
    func testCounterUpdateReachesLoadedSearchItem() {
        let a = Account(); let c = ready(a)
        a.stateManager.send([.updateViews(peerId: 10, views: [1: .init(seenCount: 77, reactedCount: 4)])])
        XCTAssertEqual(c.stateValue.items.first?.storyItem.views?.seenCount, 77)
    }
    func testFailedNextPagePreservesPaginationAndCanRetry() {
        let a = Account(); let c = ready(a); var completed = 0
        c.loadMore(completion: { completed += 1 }); a.network.requests[1].fail()
        XCTAssertEqual(c.stateValue.loadMoreToken?.base as? String, "next"); XCTAssertEqual(c.stateValue.items.count, 2); XCTAssertEqual(c.stateValue.totalCount, 100); XCTAssertEqual(completed, 1)
        c.loadMore(completion: nil); XCTAssertEqual(a.network.requests.count, 3)
    }
    func testFailedInitialPageRemainsRetryableWithoutClaimingCache() {
        let a = Account(); let c = context(a); a.network.requests[0].fail()
        XCTAssertEqual(c.stateValue.loadMoreToken?.base as? String, ""); XCTAssertFalse(c.stateValue.hasCache); XCTAssertFalse(c.stateValue.isLoading)
        c.loadMore(completion: nil); XCTAssertEqual(a.network.requests.count, 2)
    }
    func testExhaustedPaginationCompletesCallbackImmediately() {
        let a = Account(); let c = ready(a, next: nil); var completed = 0
        c.loadMore(completion: { completed += 1 }); XCTAssertEqual(completed, 1); XCTAssertEqual(a.network.requests.count, 1)
    }
    func testMissingScopedPeerDoesNotBroadenSearch() {
        let a = Account(); a.postbox.storage.peer = nil; let c = context(a, source: .hashtag(10, "test"))
        XCTAssertTrue(a.network.requests.isEmpty); XCTAssertFalse(c.stateValue.isLoading)
    }
    func testPendingDeletionDuringNextPageCannotBeUndoneByOverlappingPage() {
        let a = Account(); let c = ready(a); c.loadMore(completion: nil)
        a.stateManager.send([.deleted(peerId: 10, id: 1)]); a.network.requests[1].succeed(page([1,3])); a.postbox.flush()
        XCTAssertEqual(c.stateValue.items.map { $0.id.id }, [2,3])
    }
    func testPendingEditDuringPageIsNotOverwrittenByOlderPagePayload() {
        let a = Account(); let c = ready(a); c.loadMore(completion: nil)
        a.stateManager.send([added(3, text: "latest")]); a.network.requests[1].succeed(page([3], text: "old")); a.postbox.flush()
        XCTAssertEqual(c.stateValue.items.last?.storyItem.text, "latest")
    }
    func testPageCompletionWaitsForQueuedUpdatesBeforeCallbacks() {
        let a = Account(); let c = ready(a); var completed = false
        c.loadMore(completion: { completed = true; XCTAssertEqual(c.stateValue.items.first?.storyItem.text, "latest") })
        a.postbox.hold = true; a.stateManager.send([added(text: "latest")]); a.network.requests[1].succeed(page([3]))
        if a.postbox.pending.count > 1 { a.postbox.pending[1].run() }
        XCTAssertFalse(completed); a.postbox.flush(); XCTAssertTrue(completed)
    }
    func testRepeatedCursorStopsPagination() {
        let a = Account(); let c = ready(a); c.loadMore(completion: nil); a.network.requests[1].succeed(page([3], next: "next"))
        XCTAssertNil(c.stateValue.loadMoreToken)
    }
    func testEmptyTransportCompletionReleasesLoadingAndCallbacks() {
        let a = Account(); let c = ready(a); var completed = false
        c.loadMore(completion: { completed = true }); a.network.requests[1].empty()
        XCTAssertFalse(c.stateValue.isLoading); XCTAssertTrue(completed); XCTAssertEqual(c.stateValue.loadMoreToken?.base as? String, "next")
    }
}

extension StorySearchUpdatesTests {
    func testCounterUpdateResolvesSeenPeersWithoutChangingCaption() {
        let a = Account(); let c = ready(a); a.postbox.storage.extraPeers[77] = .init(id: 77)
        a.stateManager.send([.updateViews(peerId: 10, views: [1: .init(seenCount: 30, seenPeerIds: [77])])])
        XCTAssertEqual(c.stateValue.items.first?.storyItem.views?.seenPeers.map(\.id), [77]); XCTAssertEqual(c.stateValue.items.first?.storyItem.text, "page")
    }
    func testCounterEventForNewPageItemIsReplayed() {
        let a = Account(); let c = ready(a); c.loadMore(completion: nil)
        a.stateManager.send([.updateViews(peerId: 10, views: [3: .init(seenCount: 99)])]); a.network.requests[1].succeed(page([3]))
        XCTAssertEqual(c.stateValue.items.last?.storyItem.views?.seenCount, 99)
    }
    func testFailedPageWaitsForQueuedUpdateAndPreservesItsState() {
        let a = Account(); let c = ready(a); var completed = false; c.loadMore(completion: { completed = true })
        a.postbox.hold = true; a.stateManager.send([added(text: "latest")]); a.network.requests[1].fail()
        XCTAssertFalse(completed); a.postbox.flush(); XCTAssertTrue(completed)
        XCTAssertEqual(c.stateValue.items.first?.storyItem.text, "latest"); XCTAssertEqual(c.stateValue.loadMoreToken?.base as? String, "next")
    }
    func testSynchronousCompletionCallbackCanStartNextPageWithoutLosingCancellation() {
        let a = Account(); var c: SearchContext? = ready(a); weak var weakContext = c
        a.network.onRequest = { request in
            if request.searchOffset == "next" { request.succeed(self.page([3], next: "after")) }
        }
        c!.loadMore(completion: { [weak c] in c?.loadMore(completion: nil) })
        XCTAssertEqual(a.network.requests.count, 3); XCTAssertEqual(a.network.requests.last?.searchOffset, "after")
        XCTAssertFalse(a.network.requests.last?.cancelled ?? true); c = nil
        XCTAssertNil(weakContext); XCTAssertTrue(a.network.requests.last?.cancelled ?? false)
    }
    func testConcurrentLoadCallbacksCoalesceAndCompleteOnceOnFailure() {
        let a = Account(); let c = ready(a); var completed = 0
        c.loadMore(completion: { completed += 1 }); c.loadMore(completion: { completed += 1 })
        XCTAssertEqual(a.network.requests.count, 2); a.network.requests[1].fail(); XCTAssertEqual(completed, 2)
        c.loadMore(completion: nil); XCTAssertEqual(a.network.requests.count, 3)
    }
    func testClosingSearchDuringQueuedPageReleasesAccount() {
        var a: Account? = Account(); weak var weakAccount = a; let postbox = a!.postbox; let network = a!.network
        var c: SearchContext? = context(a!); weak var weakContext = c; postbox.hold = true
        network.requests[0].succeed(page([1])); c = nil; a = nil
        XCTAssertNil(weakContext); XCTAssertNil(weakAccount); XCTAssertTrue(postbox.pending.allSatisfy { !$0.active })
        for pending in postbox.pending { pending.action() }
    }
    func testInvalidIdsAreNotAddedToSearchResults() {
        let a = Account(); let c = context(a); a.network.requests[0].succeed(page([0,-1,1]))
        XCTAssertEqual(c.stateValue.items.map { $0.id.id }, [1])
    }
    func testUnsupportedPageItemsDoNotStopAnAdvancingCursor() {
        let a = Account(); let c = context(a)
        a.network.requests[0].succeed(Api.stories.FoundStories.foundStories(.init(count: 5, stories: [.foundStory(.init(peer: .init(peerId: 10), story: .placeholder(1)))], nextOffset: "advance")))
        XCTAssertTrue(c.stateValue.items.isEmpty); XCTAssertEqual(c.stateValue.loadMoreToken?.base as? String, "advance")
        c.loadMore(completion: nil); XCTAssertEqual(a.network.requests.count, 2)
    }
    func testSameIdInDifferentPeersRemainsDistinctAndUpdatesOnlyMatchingPeer() {
        let a = Account(); a.postbox.storage.extraPeers[20] = .init(id: 20); let c = context(a)
        let result = Api.stories.FoundStories.foundStories(.init(count: 2, stories: [10,20].map { .foundStory(.init(peer: .init(peerId: $0), story: .item(.init(id: 1)))) }, nextOffset: nil))
        a.network.requests[0].succeed(result); a.stateManager.send([.updateViews(peerId: 20, views: [1: .init(seenCount: 55)])])
        XCTAssertEqual(c.stateValue.items.count, 2); XCTAssertNil(c.stateValue.items[0].storyItem.views); XCTAssertEqual(c.stateValue.items[1].storyItem.views?.seenCount, 55)
    }
    func testPageAndEditResolveAndPruneEmojiFiles() {
        let a = Account(); a.postbox.storage.media = [11.fileId: 11, 12.fileId: 12]; let c = context(a)
        var item = Stories.Item(id: 1); item.entities = [.init(type: .CustomEmoji(0,11))]
        a.network.requests[0].succeed(Api.stories.FoundStories.foundStories(.init(count: 1, stories: [.foundStory(.init(peer: .init(peerId: 10), story: .item(item)))], nextOffset: nil)))
        XCTAssertEqual(c.stateValue.allEntityFiles, [11.fileId: 11])
        item.entities = [.init(type: .CustomEmoji(0,12))]; a.stateManager.send([.added(peerId: 10, item: .item(item))])
        XCTAssertEqual(c.stateValue.allEntityFiles, [12.fileId: 12])
    }
    func testScopedSearchIgnoresUnrelatedPeerUpdatesWithoutLookup() {
        let a = Account(); let c = context(a, source: .hashtag(10,"test")); a.network.requests[0].succeed(page([1]))
        let count = a.postbox.subscriptions
        a.stateManager.send([.deleted(peerId: 20,id: 1), .updateViews(peerId: 20,views: [1: .init(seenCount: 55)])])
        XCTAssertEqual(a.postbox.subscriptions, count); XCTAssertEqual(c.stateValue.items.count, 1)
    }
    func testOldPageJournalDoesNotOverrideALaterRetry() {
        let a = Account(); let c = ready(a); c.loadMore(completion: nil)
        a.stateManager.send([added(text: "during failed page")]); a.network.requests[1].fail()
        c.loadMore(completion: nil); a.network.requests[2].succeed(page([1], text: "fresh retry"))
        XCTAssertEqual(c.stateValue.items.first?.storyItem.text, "fresh retry")
    }
}

extension StorySearchUpdatesTests {
    func testPreviouslyConsumedCursorCannotCreatePaginationCycle() {
        let a = Account(); let c = ready(a)
        c.loadMore(completion: nil); a.network.requests[1].succeed(page([3], next: "after"))
        c.loadMore(completion: nil); a.network.requests[2].succeed(page([4], next: "next"))
        XCTAssertNil(c.stateValue.loadMoreToken)
        c.loadMore(completion: nil); XCTAssertEqual(a.network.requests.count, 3)
    }
}
