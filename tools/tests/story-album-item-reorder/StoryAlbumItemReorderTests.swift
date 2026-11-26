import Foundation
import XCTest
import SwiftSignalKit

typealias PeerId = Int
extension Int { static var stars: Int { -123456 }; var namespace: Int { self >= 100 ? 1 : 0 }; func toInt64() -> Int64 { Int64(self) } }
struct EngineMedia: Equatable { let value: Int; init(_ value: Int) { self.value = value }; func _asMedia() -> Int { value } }
typealias TelegramMediaFile = Int
struct EngineStoryPrivacy: Equatable { let base: Int; let additionallyIncludePeers: [Int]; init(_ value: Stories.Item.Privacy) { base = value.base; additionallyIncludePeers = value.additionallyIncludePeers } }
struct Peer { let id: Int }
struct PeerReference: Equatable { let id: Int; init(_ peer: Peer) { id = peer.id } }
struct EnginePeer: Equatable { let id: Int; init(_ peer: Peer) { id = peer.id } }
struct StoryId: Equatable, Hashable { let peerId: Int; let id: Int32 }
struct EngineStoryItem: Equatable {
    struct Views: Equatable { let seenCount: Int; let reactedCount: Int; let forwardCount: Int; let seenPeers: [EnginePeer]; let reactions: [MessageReaction]; let hasList: Bool }
    enum ForwardInfo: Equatable {
        case known(EnginePeer, Int32, Bool), unknown(String, Bool)
        init(_ info: Stories.ForwardInfo, transaction: Transaction) { self = .unknown("",false) }
        init(_ info: Stories.ForwardInfo, peers: [Int: Peer]) { self = .unknown("",false) }
    }
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
extension Int { var fileId: MediaId { .init(namespace: 1,id: Int64(self)) } }
struct Entity: Equatable { enum Kind: Equatable { case CustomEmoji(Int,Int64) }; let type: Kind }
enum Reaction: Equatable { case custom(Int64) }
enum Area: Equatable { case reaction(Int,Reaction,Int) }
struct StoryListContextState {
    struct Item { let id: StoryId; let storyItem: EngineStoryItem; var peer: EnginePeer? = nil }
    struct Folder: Equatable { let id: Int64; let title: String }
    var items: [Item] = []
    var pinnedIds: [Int32] = []
    var availableFolders: [Folder] = []
    var totalCount = 0
    var peerReference: PeerReference? = nil
    var isCached = false
    var hasCache = false
    var isLoading = false
    var loadMoreToken: AnyHashable? = AnyHashable(0)
    var allEntityFiles: [MediaId: TelegramMediaFile] = [:]
    var unrelatedMetadata = 7
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
    enum ForwardInfo { case known(peerId: Int, storyId: Int32, isModified: Bool), unknown(name: String, isModified: Bool) }
    struct Item {
        struct Privacy: Equatable { let base: Int; let additionallyIncludePeers: [Int] }
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
        var privacy: Privacy? = nil
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
        var isLiveStream: Bool { false }
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
struct StoryItemsTableEntry { let value: CodableEntry; let id: Int32; let expirationTimestamp: Int; let isCloseFriends: Bool; let isLiveStream: Bool }
final class Transaction {
    var peer: Peer? = .init(id: 10)
    var cache: [ItemCacheEntryId: CodableEntry] = [:]
    var writes = 0
    var media: [MediaId: Int] = [:]
    func getMedia(_ id: MediaId) -> Any? { media[id] }
    var stories: [StoryId: CodableEntry] = [:]
    var storyItems: [StoryItemsTableEntry] = []
    func getStoryItems(peerId: Int) -> [StoryItemsTableEntry] { storyItems }
    func setStoryItems(peerId: Int, items: [StoryItemsTableEntry]) { storyItems = items; writes += 1 }
    func getStory(id: StoryId) -> CodableEntry? { stories[id] }
    func setStory(id: StoryId, value: CodableEntry) { stories[id] = value; writes += 1 }
    func getPeer(_ id: Int) -> Peer? { peer }
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
    var pending: [Pending] = []
    var subscriptions = 0
    func transaction<T>(_ f: @escaping (Transaction) -> T) -> Signal<T, NoError> {
        Signal { subscriber in
            self.subscriptions += 1
            let run = { subscriber.putNext(f(self.storage)); subscriber.putCompletion() }
            if self.hold || self.delayAt.contains(self.subscriptions) {
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
    struct InputPeer { let id: Int }
    enum StoryItem {
        case item(Stories.Item), placeholder(Int32), deleted(Int32)
        var id: Int32 { switch self { case let .item(item): return item.id; case let .placeholder(id), let .deleted(id): return id } }
    }
    struct AlbumData { let albumId: Int32; let title: String; var iconPhoto: Int? = nil; var iconVideo: Int? = nil }
    enum StoryAlbum { case storyAlbum(AlbumData) }
    enum stories {
        struct StoriesData { let count: Int32; let stories: [Api.StoryItem]; let pinnedToTop: [Int32]?; var chats: [Int] = []; var users: [Int] = [] }
        struct AlbumsData { let albums: [StoryAlbum] }
        enum Stories { case stories(StoriesData) }
        enum Albums { case albums(AlbumsData), albumsNotModified }
    }
    enum functions { enum stories {
        static func updateAlbum(flags: Int32, peer: InputPeer, albumId: Int32, title: String?, deleteStories: [Int32]?, addStories: [Int32]?, order: [Int32]?) -> RequestData<Api.StoryAlbum> { .init(kind: "mutation",offset: 0,peer: peer.id,album: albumId,flags: flags,added: addStories,removed: deleteStories,order: order) }
        static func getAlbumStories(peer: InputPeer, albumId: Int32, offset: Int32, limit: Int32) -> RequestData<Api.stories.Stories> { .init(kind: "album", offset: Int(offset), peer: peer.id, album: albumId) }
        static func getStoriesArchive(peer: InputPeer, offsetId: Int32, limit: Int32) -> RequestData<Api.stories.Stories> { .init(kind: "archive", offset: Int(offsetId), peer: peer.id) }
        static func getPinnedStories(peer: InputPeer, offsetId: Int32, limit: Int32) -> RequestData<Api.stories.Stories> { .init(kind: "profile", offset: Int(offsetId), peer: peer.id) }
        static func getAlbums(peer: InputPeer, hash: Int) -> RequestData<Api.stories.Albums> { .init(kind: "folders", offset: 0, peer: peer.id) }
    } }
}
struct MTRpcError: Error {}
struct RequestData<T> { let kind: String; let offset: Int; let peer: Int; var album: Int32? = nil; var flags: Int32 = 0; var added: [Int32]? = nil; var removed: [Int32]? = nil; var order: [Int32]? = nil }
final class Request {
    let kind: String; let offset: Int; let peer: Int; let album: Int32?
    let flags: Int32; let added: [Int32]?; let removed: [Int32]?; let order: [Int32]?
    var next: ((Any) -> Void)?; var error: (() -> Void)?; var completed: (() -> Void)?
    var cancelled = false
    init<T>(_ data: RequestData<T>) { kind = data.kind; offset = data.offset; peer = data.peer; album = data.album; flags = data.flags; added = data.added; removed = data.removed; order = data.order }
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
    var storyUpdates: Signal<[InternalStoryUpdate], NoError> { pipe.signal() }
    var published: [[InternalStoryUpdate]] = []
    func injectStoryUpdates(updates: [InternalStoryUpdate]) { published.append(updates); send(updates) }
    func send(_ updates: [InternalStoryUpdate]) { pipe.putNext(updates) }
}
final class Account { let peerId = 10; let postbox = Postbox(); let network = Network(); let stateManager = StateManager() }
__HELPER__
__REORDER_HELPER__
__MEMBERSHIP_HELPERS__
final class Context {
    typealias State = StoryListContextState
    let account: Account
    let peerId = 10
    let isArchived: Bool
    let folderId: Int64?
    let queue = Queue.mainQueue()
    var stateValue = State() { didSet { onState?(stateValue) } }
    var onState: ((State) -> Void)?
    var completionCallbacksByToken: [AnyHashable: [() -> Void]] = [:]
    var subscriptions = 0
    __PROPERTIES__
    init(_ account: Account = Account(), folder: Int64? = 7, archived: Bool = false) { self.account = account; folderId = folder; isArchived = archived; __INITIALIZATION_READY__ }
    func begin() { subscribeToStoryUpdates() }
    __LOAD__
    __FINISH__
    __UPDATE_LIFECYCLE__
    __SUBSCRIBE__
    __RELOAD__
    __DEINIT__
    __MUTATE__
    __REORDER_ITEMS__
    __ADD__
    __REMOVE__
}

final class StoryAlbumItemReorderTests: XCTestCase {
    func key(_ album: Int64? = 7) -> ItemCacheEntryId {
        let key = ValueBoxKey(length: album == nil ? 9 : 17); key.setInt64(0,value: 10); key.setInt8(8,value: 0)
        if let album { key.setInt64(9,value: album) }; return .init(collectionId: 1,key: key)
    }
    func seed(_ c: Context) {
        c.stateValue.items = [3,1,2].map { .init(id: .init(peerId: 10,id: $0),storyItem: .init(id: $0,folderIds: [7])) }
        c.stateValue.totalCount = 200; c.stateValue.loadMoreToken = AnyHashable(100); c.stateValue.hasCache = true
        for album: Int64? in [nil,7,8] {
            c.account.postbox.storage.cache[key(album)] = CodableEntry(CachedPeerStoryListHead(items: [.item(.init(id: 3)),.placeholder(1),.item(.init(id: 2))],pinnedIds: [3],totalCount: 200,folders: [.init(id: 8,title: "unrelated")]))
        }
    }
    func response(_ id: Int32 = 7) -> Api.StoryAlbum { .storyAlbum(.init(albumId: id,title: "album")) }
    func request(_ c: Context) -> Request? { c.account.network.requests.last(where: { $0.kind == "mutation" }) }
    func page(_ ids: [Int32], count: Int32? = nil) -> Api.stories.Stories {
        .stories(.init(count: count ?? Int32(ids.count),stories: ids.map { .item(.init(id: $0)) },pinnedToTop: nil))
    }
    func testPendingRequestDoesNotChangeVisibleOrderOrCachedHead() {
        let c = Context(); seed(c); let d = c.reorderItemsInFolder(itemIds: [2,1,3])
        XCTAssertEqual(c.stateValue.items.map { $0.id.id },[3,1,2]); XCTAssertEqual(c.account.postbox.storage.writes,0)
        XCTAssertEqual(request(c)?.flags,8); XCTAssertEqual(request(c)?.order,[2,1,3]); XCTAssertNil(request(c)?.added); XCTAssertNil(request(c)?.removed); d.dispose()
    }
    func testFailurePreservesPartialCountPlaceholdersAndOrder() {
        let c = Context(); seed(c); var results: [Bool] = []
        let d = c.reorderItemsInFolder(itemIds: [2,1,3],completion: { results.append($0) }); request(c)?.fail()
        XCTAssertEqual(results,[false]); XCTAssertEqual(c.stateValue.items.map { $0.id.id },[3,1,2]); XCTAssertEqual(c.stateValue.totalCount,200)
        let head = c.account.postbox.storage.cache[key()]?.get(CachedPeerStoryListHead.self)
        XCTAssertEqual(head?.totalCount,200); XCTAssertEqual(head?.items.map(\.id),[3,1,2]); XCTAssertEqual(head?.pinnedIds,[3]); XCTAssertEqual(head?.folders.first?.title,"unrelated")
        if case .placeholder = head?.items[1] {} else { XCTFail("Placeholder removed") }
        XCTAssertTrue(c.account.stateManager.published.isEmpty); d.dispose()
    }
    func testWrongAlbumResponseFails() {
        let c = Context(); seed(c); var results: [Bool] = []
        let d = c.reorderItemsInFolder(itemIds: [2,1,3],completion: { results.append($0) }); request(c)?.succeed(response(8))
        XCTAssertEqual(results,[false]); XCTAssertEqual(c.account.postbox.storage.writes,0); XCTAssertEqual(c.account.network.requests.count,1); d.dispose()
    }
    func testEmptyResponseReportsFailure() {
        let c = Context(); seed(c); var results: [Bool] = []
        let d = c.reorderItemsInFolder(itemIds: [2,1,3],completion: { results.append($0) }); request(c)?.empty()
        XCTAssertEqual(results,[false]); XCTAssertEqual(c.account.postbox.storage.writes,0); d.dispose()
    }
    func testProfileContextRejectsReorder() {
        let c = Context(folder: nil); var results: [Bool] = []
        let d = c.reorderItemsInFolder(itemIds: [1],completion: { results.append($0) })
        XCTAssertEqual(results,[false]); XCTAssertTrue(c.account.network.requests.isEmpty); d.dispose()
    }
    func testInvalidAlbumIdsAreNotClamped() {
        for id: Int64 in [0,-1,Int64(Int32.max)+1] {
            let c = Context(folder: id); var results: [Bool] = []
            let d = c.reorderItemsInFolder(itemIds: [1],completion: { results.append($0) })
            XCTAssertEqual(results,[false]); XCTAssertTrue(c.account.network.requests.isEmpty); XCTAssertEqual(c.account.postbox.storage.writes,0); d.dispose()
        }
    }
    func testInvalidStoryIdsFailWithoutChanges() {
        for ids: [Int32] in [[0],[1,-1],[2,0,3]] {
            let c = Context(); seed(c); var results: [Bool] = []
            let d = c.reorderItemsInFolder(itemIds: ids,completion: { results.append($0) })
            XCTAssertEqual(results,[false]); XCTAssertTrue(c.account.network.requests.isEmpty); XCTAssertEqual(c.account.postbox.storage.writes,0); d.dispose()
        }
    }
    func testDuplicatesNormalizeInRequestedOrder() {
        let c = Context(); seed(c); let d = c.reorderItemsInFolder(itemIds: [2,2,3,1,3])
        XCTAssertEqual(request(c)?.order,[2,3,1]); XCTAssertEqual(c.stateValue.items.count,3); d.dispose()
    }
    func testEmptyOrderIsNoOp() {
        let c = Context(); seed(c); var results: [Bool] = []
        let d = c.reorderItemsInFolder(itemIds: [],completion: { results.append($0) })
        XCTAssertEqual(results,[true]); XCTAssertTrue(c.account.network.requests.isEmpty); XCTAssertEqual(c.account.postbox.storage.writes,0); XCTAssertTrue(c.account.stateManager.published.isEmpty); d.dispose()
    }
    func testMissingPeerFailsWithoutCacheEdit() {
        let c = Context(); seed(c); c.account.postbox.storage.peer = nil; var results: [Bool] = []
        let d = c.reorderItemsInFolder(itemIds: [2,3,1],completion: { results.append($0) })
        XCTAssertEqual(results,[false]); XCTAssertTrue(c.account.network.requests.isEmpty); XCTAssertEqual(c.account.postbox.storage.writes,0); d.dispose()
    }
    func testAcceptedOrderUsesServerOrderAndRetainsPartialCountWhileRefreshing() {
        let c = Context(); seed(c); var results: [Bool] = []
        let d = c.reorderItemsInFolder(itemIds: [2,1,3],completion: { results.append($0) }); request(c)?.succeed(response())
        XCTAssertEqual(results,[true]); XCTAssertEqual(c.stateValue.items.map { $0.id.id },[3,1,2]); XCTAssertEqual(c.stateValue.totalCount,200)
        XCTAssertEqual(c.account.network.requests.last?.kind,"album"); XCTAssertEqual(c.account.network.requests.last?.offset,0)
        c.account.network.requests.last?.succeed(page([2,4,1,3])); XCTAssertEqual(c.stateValue.items.map { $0.id.id },[2,4,1,3]); XCTAssertEqual(c.stateValue.totalCount,4); d.dispose()
    }
    func testAcceptanceInvalidatesOnlyTargetHead() {
        let c = Context(); seed(c); let d = c.reorderItemsInFolder(itemIds: [2,1,3]); request(c)?.succeed(response())
        XCTAssertNil(c.account.postbox.storage.cache[key()]); XCTAssertNotNil(c.account.postbox.storage.cache[key(nil)]); XCTAssertNotNil(c.account.postbox.storage.cache[key(8)]); d.dispose()
    }
    func testRefreshFailureRetainsItemsCountAndRetryCursor() {
        let c = Context(); seed(c); let d = c.reorderItemsInFolder(itemIds: [2,1,3]); request(c)?.succeed(response()); c.account.network.requests.last?.fail()
        XCTAssertEqual(c.stateValue.totalCount,200); XCTAssertEqual(c.stateValue.items.map { $0.id.id },[3,1,2]); XCTAssertFalse(c.stateValue.isLoading)
        XCTAssertEqual(c.stateValue.loadMoreToken,AnyHashable(0)); XCTAssertNil(c.account.postbox.storage.cache[key()]); d.dispose()
    }
    func testCancellationDuringPeerLookup() {
        let c = Context(); seed(c); c.account.postbox.hold = true; var results: [Bool] = []
        let d = c.reorderItemsInFolder(itemIds: [2,1,3],completion: { results.append($0) }); d.dispose(); c.account.postbox.flush()
        XCTAssertTrue(results.isEmpty); XCTAssertTrue(c.account.network.requests.isEmpty); XCTAssertEqual(c.account.postbox.storage.writes,0); XCTAssertEqual(c.stateValue.items.map { $0.id.id },[3,1,2])
    }
    func testCancellationDuringRequest() {
        let c = Context(); seed(c); var results: [Bool] = []
        let d = c.reorderItemsInFolder(itemIds: [2,1,3],completion: { results.append($0) }); let pending = request(c); d.dispose(); pending?.succeed(response())
        XCTAssertTrue(pending?.cancelled == true); XCTAssertTrue(results.isEmpty); XCTAssertEqual(c.account.postbox.storage.writes,0); XCTAssertTrue(c.account.stateManager.published.isEmpty)
    }
    func testCancellationDuringCommit() {
        let c = Context(); seed(c); var results: [Bool] = []
        let d = c.reorderItemsInFolder(itemIds: [2,1,3],completion: { results.append($0) }); c.account.postbox.hold = true
        request(c)?.succeed(response()); d.dispose(); c.account.postbox.flush()
        XCTAssertTrue(results.isEmpty); XCTAssertEqual(c.account.postbox.storage.writes,0); XCTAssertTrue(c.account.stateManager.published.isEmpty)
    }
    func testCompletionAndNotificationWaitForCommit() {
        let c = Context(); seed(c); var results: [Bool] = []
        let d = c.reorderItemsInFolder(itemIds: [2,1,3],completion: { results.append($0) }); c.account.postbox.hold = true
        request(c)?.succeed(response()); XCTAssertTrue(results.isEmpty); XCTAssertTrue(c.account.stateManager.published.isEmpty)
        c.account.postbox.hold = false; c.account.postbox.flush(); XCTAssertEqual(results,[true]); XCTAssertEqual(c.account.stateManager.published.count,1); d.dispose()
    }
    func testAllMatchingOpenAlbumsRefreshButOtherListsDoNot() {
        let account = Account(); let origin = Context(account); seed(origin)
        let same = Context(account); same.stateValue = origin.stateValue; same.begin()
        let other = Context(account,folder: 8); other.stateValue = origin.stateValue; other.begin()
        let profile = Context(account,folder: nil); profile.stateValue = origin.stateValue; profile.begin()
        let d = origin.reorderItemsInFolder(itemIds: [2,1,3]); request(origin)?.succeed(response())
        XCTAssertEqual(account.network.requests.filter { $0.kind == "album" }.count,2); XCTAssertTrue(origin.stateValue.isLoading); XCTAssertTrue(same.stateValue.isLoading)
        XCTAssertFalse(other.stateValue.isLoading); XCTAssertFalse(profile.stateValue.isLoading); XCTAssertEqual(other.stateValue.items.map { $0.id.id },[3,1,2]); d.dispose()
    }
    func testOldPageIsCanceledAndCompletionMovesToReplacement() {
        let c = Context(); seed(c); c.begin(); var completions = 0; c.loadMore { completions += 1 }; let old = c.account.network.requests.last
        let d = c.reorderItemsInFolder(itemIds: [2,1,3]); request(c)?.succeed(response())
        XCTAssertTrue(old?.cancelled == true); XCTAssertEqual(completions,0); old?.succeed(page([99])); XCTAssertFalse(c.stateValue.items.contains(where: { $0.id.id == 99 }))
        c.account.network.requests.last?.succeed(page([2,1,3])); XCTAssertEqual(completions,1); d.dispose()
    }
    func testCurrentListChangesAreNotReplacedByCapturedItems() {
        let c = Context(); seed(c); let d = c.reorderItemsInFolder(itemIds: [2,1,3])
        c.stateValue.items = [.init(id: .init(peerId: 10,id: 4),storyItem: .init(id: 4,text: "new story")),.init(id: .init(peerId: 10,id: 1),storyItem: .init(id: 1,text: "edited"))]
        c.stateValue.totalCount = 205; request(c)?.succeed(response())
        XCTAssertEqual(c.stateValue.items.map { $0.id.id },[4,1]); XCTAssertEqual(c.stateValue.items.last?.storyItem.text,"edited"); XCTAssertEqual(c.stateValue.totalCount,205); d.dispose()
    }
    func testOwnerReleaseDuringRequestSuppressesCompletion() {
        let account = Account(); var c: Context? = Context(account); seed(c!); weak var owner = c; var results: [Bool] = []
        let d = c!.reorderItemsInFolder(itemIds: [2,1,3],completion: { results.append($0) }); let pending = request(c!); c = nil
        XCTAssertNil(owner); pending?.succeed(response()); XCTAssertTrue(results.isEmpty); XCTAssertEqual(account.network.requests.count,1); d.dispose()
    }
    func testSynchronousAcceptanceOwnsRefreshRequest() {
        let c = Context(); seed(c); c.account.network.onRequest = { request in if request.kind == "mutation" { request.succeed(self.response()) } }
        var results: [Bool] = []; let d = c.reorderItemsInFolder(itemIds: [2,1,3],completion: { results.append($0) })
        XCTAssertEqual(results,[true]); XCTAssertEqual(c.account.network.requests.last?.kind,"album"); XCTAssertFalse(c.account.network.requests.last?.cancelled ?? true)
        c.account.network.requests.last?.succeed(page([2,1,3])); XCTAssertFalse(c.stateValue.isLoading); XCTAssertEqual(c.stateValue.items.map { $0.id.id },[2,1,3]); d.dispose()
    }
    func testDisposalDuringRefreshPublicationDoesNotLeaveLoaderStuck() {
        let c = Context(); seed(c); let owner = MetaDisposable(); var results: [Bool] = []
        owner.set(c.reorderItemsInFolder(itemIds: [2,1,3],completion: { results.append($0) })); c.onState = { _ in owner.dispose() }
        request(c)?.succeed(response()); XCTAssertTrue(results.isEmpty); c.account.network.requests.last?.succeed(page([2,1,3])); XCTAssertFalse(c.stateValue.isLoading)
    }
    func testForeignPeerReorderEventIsIgnored() {
        let c = Context(); seed(c); c.begin(); c.account.stateManager.send([.updateAlbumOrder(peerId: 20,albumId: 7)])
        XCTAssertTrue(c.account.network.requests.isEmpty); XCTAssertEqual(c.account.postbox.storage.writes,0); XCTAssertEqual(c.stateValue.items.map { $0.id.id },[3,1,2])
    }
}
