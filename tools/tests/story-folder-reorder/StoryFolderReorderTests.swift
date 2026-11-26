import Foundation
import XCTest
import SwiftSignalKit

typealias PeerId = Int
extension Int { func toInt64() -> Int64 { Int64(self) } }
struct EngineMedia: Equatable { let value: Int; init(_ value: Int) { self.value = value } }
struct EngineStoryPrivacy: Equatable { let value: Int; init(_ value: Int) { self.value = value } }
struct Peer { let id: Int }
struct PeerReference: Equatable { let id: Int; init(_ peer: Peer) { id = peer.id } }
struct EnginePeer: Equatable { let id: Int; init(_ peer: Peer) { id = peer.id } }
struct StoryId: Equatable { let peerId: Int; let id: Int32 }
struct EngineStoryItem: Equatable {
    struct Views: Equatable { let seenCount: Int; let reactedCount: Int; let forwardCount: Int; let seenPeers: [EnginePeer]; let reactions: [Int]; let hasList: Bool }
    struct ForwardInfo: Equatable { init(_ info: Stories.ForwardInfo, transaction: Transaction) {}
        init(_ info: Stories.ForwardInfo, peers: [Int: Peer]) {} }
    var id: Int32
    var timestamp = 0
    var expirationTimestamp = 100
    var media = EngineMedia(1)
    var alternativeMediaList: [EngineMedia] = []
    var mediaAreas: [Int] = []
    var text = "old"
    var entities: [Int] = []
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
    func asStoryItem() -> Stories.Item { .init(id: id, text: text) }
}
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
    var unrelatedMetadata = 7
}
enum StoryListContext { typealias State = StoryListContextState }
enum Stories {
    enum ForwardInfo { case known(Int, Int32, Bool) }
    struct Item {
        struct Views { var seenCount = 0; var reactedCount = 0; var forwardCount = 0; var seenPeerIds: [Int] = []; var reactions: [Int] = []; var hasList = false }
        var id: Int32
        var text = "old"
        var timestamp = 0
        var expirationTimestamp = 100
        var media: Int? = 1
        var alternativeMediaList: [Int] = []
        var mediaAreas: [Int] = []
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
enum Namespaces { enum CachedItemCollection { static let cachedPeerStoryListHeads = 1 } }
final class Transaction {
    var peer: Peer? = .init(id: 10)
    var cache: [ItemCacheEntryId: CodableEntry] = [:]
    var writes = 0
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
    enum Bool { case boolTrue, boolFalse }
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
        static func reorderAlbums(peer: InputPeer, order: [Int32]) -> RequestData<Api.Bool> { .init(kind: "reorder",offset: 0,peer: peer.id,stories: order) }
        static func deleteAlbum(peer: InputPeer, albumId: Int32) -> RequestData<Api.Bool> { .init(kind: "delete", offset: 0, peer: peer.id, album: albumId) }
        static func updateAlbum(flags: Int32, peer: InputPeer, albumId: Int32, title: String?, deleteStories: [Int32]?, addStories: [Int32]?, order: [Int32]?) -> RequestData<Api.StoryAlbum> { .init(kind: "rename", offset: Int(flags), peer: peer.id, album: albumId, title: title ?? "", stories: (deleteStories ?? []) + (addStories ?? []) + (order ?? [])) }
        static func createAlbum(peer: InputPeer, title: String, stories: [Int32]) -> RequestData<Api.StoryAlbum> { .init(kind: "create", offset: 0, peer: peer.id, title: title, stories: stories) }
        static func getAlbumStories(peer: InputPeer, albumId: Int32, offset: Int32, limit: Int32) -> RequestData<Api.stories.Stories> { .init(kind: "album", offset: Int(offset), peer: peer.id, album: albumId) }
        static func getStoriesArchive(peer: InputPeer, offsetId: Int32, limit: Int32) -> RequestData<Api.stories.Stories> { .init(kind: "archive", offset: Int(offsetId), peer: peer.id) }
        static func getPinnedStories(peer: InputPeer, offsetId: Int32, limit: Int32) -> RequestData<Api.stories.Stories> { .init(kind: "profile", offset: Int(offsetId), peer: peer.id) }
        static func getAlbums(peer: InputPeer, hash: Int) -> RequestData<Api.stories.Albums> { .init(kind: "folders", offset: 0, peer: peer.id) }
    } }
}
struct MTRpcError: Error {}
struct RequestData<T> { let kind: String; let offset: Int; let peer: Int; var album: Int32? = nil; var title = ""; var stories: [Int32] = [] }
final class Request {
    let kind: String; let offset: Int; let peer: Int; let album: Int32?
    let title: String; let stories: [Int32]
    var next: ((Any) -> Void)?; var error: (() -> Void)?; var completed: (() -> Void)?
    var cancelled = false
    init<T>(_ data: RequestData<T>) { kind = data.kind; offset = data.offset; peer = data.peer; album = data.album; title = data.title; stories = data.stories }
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
    case read(peerId: Int, maxId: Int32)
    case updateMyReaction(peerId: Int, id: Int32, reaction: Int?)
}
final class StateManager {
    let pipe = ValuePipe<[InternalStoryUpdate]>()
    var storyUpdates: Signal<[InternalStoryUpdate], NoError> { pipe.signal() }
    func send(_ updates: [InternalStoryUpdate]) { pipe.putNext(updates) }
}
final class Account { let peerId = 10; let postbox = Postbox(); let network = Network(); let stateManager = StateManager() }
__HELPER__
final class Context {
    typealias State = StoryListContextState
    let account: Account
    let peerId = 10
    let isArchived: Bool
    let queue = Queue.mainQueue()
    var stateValue = State() { didSet { onState?(stateValue) } }
    var onState: ((State) -> Void)?
    init(_ account: Account = Account(), archived: Bool = false) { self.account = account; self.isArchived = archived }
    __REORDER__
}
final class StoryFolderReorderTests: XCTestCase {
    func key(_ archive: Bool = false) -> ItemCacheEntryId { let key = ValueBoxKey(length: 9); key.setInt64(0,value: 10); key.setInt8(8,value: archive ? 1 : 0); return .init(collectionId: 1,key: key) }
    func folders(_ ids: [Int64]) -> [StoryListContextState.Folder] { ids.map { .init(id: $0,title: "folder \($0)") } }
    func seed(_ c: Context) {
        c.stateValue.availableFolders = folders([1,2,3]); c.stateValue.totalCount = 300
        c.stateValue.items = [.init(id: .init(peerId: 10,id: 10),storyItem: .init(id: 10))]
        c.account.postbox.storage.cache[key()] = CodableEntry(CachedPeerStoryListHead(items: [.item(.init(id: 90))],pinnedIds: [90],totalCount: 500,folders: folders([1,2,3])))
    }
    func cache(_ c: Context) -> CachedPeerStoryListHead? { c.account.postbox.storage.cache[key()]?.get(CachedPeerStoryListHead.self) }
    func testWaitsForServerAcceptance() {
        let c = Context(); seed(c); let d = c.reorderFolders(ids: [3,1,2]); XCTAssertEqual(c.stateValue.availableFolders.map(\.id),[1,2,3]); XCTAssertEqual(c.account.postbox.storage.writes,0)
        c.account.network.requests.first?.succeed(Api.Bool.boolTrue); XCTAssertEqual(c.stateValue.availableFolders.map(\.id),[3,1,2]); XCTAssertEqual(cache(c)?.folders.map(\.id),[3,1,2]); d.dispose()
    }
    func testFalseAndRpcFailurePreserveOrder() {
        for fail in [false,true] {
            let c = Context(); seed(c); var results: [Bool] = []; let d = c.reorderFolders(ids: [3,1,2],completion: { results.append($0) })
            if fail { c.account.network.requests.first?.fail() } else { c.account.network.requests.first?.succeed(Api.Bool.boolFalse) }
            XCTAssertEqual(results,[false]); XCTAssertEqual(c.stateValue.availableFolders.map(\.id),[1,2,3]); XCTAssertEqual(c.account.postbox.storage.writes,0); d.dispose()
        }
    }
    func testKeepsProfileStoriesPinsAndTotal() {
        let c = Context(); seed(c); let d = c.reorderFolders(ids: [3,2,1]); c.account.network.requests.first?.succeed(Api.Bool.boolTrue)
        XCTAssertEqual(cache(c)?.items.map(\.id),[90]); XCTAssertEqual(cache(c)?.pinnedIds,[90]); XCTAssertEqual(cache(c)?.totalCount,500); XCTAssertEqual(c.stateValue.totalCount,300); d.dispose()
    }
    func testPreservesConcurrentRenamesInsertionsAndDeletions() {
        let c = Context(); seed(c); let d = c.reorderFolders(ids: [3,1,2])
        c.stateValue.availableFolders = [.init(id: 1,title: "new"),.init(id: 2,title: "two"),.init(id: 4,title: "live")]
        c.account.postbox.storage.cache[key()] = CodableEntry(CachedPeerStoryListHead(items: [],pinnedIds: [],totalCount: 7,folders: [.init(id: 1,title: "cached-new"),.init(id: 2,title: "two"),.init(id: 5,title: "cache-live")]))
        c.account.network.requests.first?.succeed(Api.Bool.boolTrue)
        XCTAssertEqual(c.stateValue.availableFolders.map(\.id),[1,2,4]); XCTAssertEqual(c.stateValue.availableFolders.first?.title,"new"); XCTAssertEqual(cache(c)?.folders.map(\.id),[1,2,5]); XCTAssertEqual(cache(c)?.folders.first?.title,"cached-new"); XCTAssertEqual(cache(c)?.totalCount,7); d.dispose()
    }
    func testDeduplicatesRequestIdsInOrder() {
        let c = Context(); seed(c); let d = c.reorderFolders(ids: [3,3,1,2,1]); XCTAssertEqual(c.account.network.requests.first?.stories,[3,1,2]); c.account.network.requests.first?.succeed(Api.Bool.boolTrue); XCTAssertEqual(c.stateValue.availableFolders.map(\.id),[3,1,2]); d.dispose()
    }
    func testInvalidIdsFailWithoutClamping() {
        for id: Int64 in [0,-1,Int64(Int32.max)+1,Int64.min] {
            let c = Context(); seed(c); var results: [Bool] = []; let d = c.reorderFolders(ids: [3,id,1],completion: { results.append($0) })
            XCTAssertEqual(results,[false]); XCTAssertTrue(c.account.network.requests.isEmpty); XCTAssertEqual(c.account.postbox.storage.writes,0); XCTAssertEqual(c.stateValue.availableFolders.map(\.id),[1,2,3]); d.dispose()
        }
    }
    func testEmptyOrderIsNoOp() {
        let c = Context(); seed(c); var results: [Bool] = []; let d = c.reorderFolders(ids: [],completion: { results.append($0) })
        XCTAssertEqual(results,[true]); XCTAssertTrue(c.account.network.requests.isEmpty); XCTAssertEqual(c.account.postbox.storage.writes,0); XCTAssertEqual(c.stateValue.availableFolders.map(\.id),[1,2,3]); d.dispose()
    }
    func testMissingPeerFails() {
        let c = Context(); seed(c); c.account.postbox.storage.peer = nil; var results: [Bool] = []; let d = c.reorderFolders(ids: [3,2,1],completion: { results.append($0) })
        XCTAssertEqual(results,[false]); XCTAssertTrue(c.account.network.requests.isEmpty); XCTAssertEqual(c.account.postbox.storage.writes,0); d.dispose()
    }
    func testEmptyResponseFails() {
        let c = Context(); seed(c); var results: [Bool] = []; let d = c.reorderFolders(ids: [3,2,1],completion: { results.append($0) }); c.account.network.requests.first?.empty()
        XCTAssertEqual(results,[false]); XCTAssertEqual(c.account.postbox.storage.writes,0); d.dispose()
    }
    func testCancellationDuringValidation() {
        let c = Context(); seed(c); c.account.postbox.hold = true; var results: [Bool] = []; let d = c.reorderFolders(ids: [3,2,1],completion: { results.append($0) }); d.dispose(); c.account.postbox.flush()
        XCTAssertTrue(results.isEmpty); XCTAssertTrue(c.account.network.requests.isEmpty); XCTAssertEqual(c.stateValue.availableFolders.map(\.id),[1,2,3])
    }
    func testCancellationDuringRequest() {
        let c = Context(); seed(c); var results: [Bool] = []; let d = c.reorderFolders(ids: [3,2,1],completion: { results.append($0) }); d.dispose(); c.account.network.requests.first?.succeed(Api.Bool.boolTrue)
        XCTAssertTrue(results.isEmpty); XCTAssertTrue(c.account.network.requests.first?.cancelled == true); XCTAssertEqual(c.stateValue.availableFolders.map(\.id),[1,2,3]); XCTAssertEqual(c.account.postbox.storage.writes,0)
    }
    func testCancellationDuringCommit() {
        let c = Context(); seed(c); var results: [Bool] = []; let d = c.reorderFolders(ids: [3,2,1],completion: { results.append($0) }); c.account.postbox.hold = true; c.account.network.requests.first?.succeed(Api.Bool.boolTrue); d.dispose(); c.account.postbox.flush()
        XCTAssertTrue(results.isEmpty); XCTAssertEqual(c.stateValue.availableFolders.map(\.id),[1,2,3]); XCTAssertEqual(c.account.postbox.storage.writes,0)
    }
    func testPublicationWaitsForCommit() {
        let c = Context(); seed(c); var results: [Bool] = []; let d = c.reorderFolders(ids: [3,2,1],completion: { results.append($0) }); c.account.postbox.hold = true; c.account.network.requests.first?.succeed(Api.Bool.boolTrue)
        XCTAssertTrue(results.isEmpty); XCTAssertEqual(c.stateValue.availableFolders.map(\.id),[1,2,3]); c.account.postbox.flush(); XCTAssertEqual(results,[true]); XCTAssertEqual(c.stateValue.availableFolders.map(\.id),[3,2,1]); d.dispose()
    }
    func testReentrantDisposalSuppressesCompletion() {
        let c = Context(); seed(c); let owner = MetaDisposable(); var results: [Bool] = []
        owner.set(c.reorderFolders(ids: [3,2,1],completion: { results.append($0) })); c.onState = { _ in owner.dispose() }; c.account.network.requests.first?.succeed(Api.Bool.boolTrue)
        XCTAssertTrue(results.isEmpty)
    }
    func testOwnerReleaseDuringRequestAndCommit() {
        for commit in [false,true] {
            let account = Account(); var c: Context? = Context(account); seed(c!); weak var weakContext = c; var results: [Bool] = []
            let d = c!.reorderFolders(ids: [3,2,1],completion: { results.append($0) }); if commit { account.postbox.hold = true; account.network.requests.first?.succeed(Api.Bool.boolTrue) }
            c = nil; XCTAssertNil(weakContext); account.postbox.flush(); XCTAssertTrue(results.isEmpty); d.dispose()
        }
    }
    func testSynchronousSuccessCompletesOnce() {
        let c = Context(); seed(c); c.account.network.onRequest = { $0.succeed(Api.Bool.boolTrue) }; var results: [Bool] = []
        let d = c.reorderFolders(ids: [2,3,1],completion: { results.append($0) }); XCTAssertEqual(results,[true]); XCTAssertEqual(cache(c)?.folders.map(\.id),[2,3,1]); d.dispose()
    }
    func testArchiveContextDoesNotOverwriteArchiveCache() {
        let c = Context(archived: true); seed(c); c.account.postbox.storage.cache[key(true)] = CodableEntry(CachedPeerStoryListHead(items: [],pinnedIds: [],totalCount: 123,folders: []))
        let d = c.reorderFolders(ids: [3,2,1]); c.account.network.requests.first?.succeed(Api.Bool.boolTrue)
        XCTAssertEqual(cache(c)?.folders.map(\.id),[3,2,1]); XCTAssertEqual(c.account.postbox.storage.cache[key(true)]?.get(CachedPeerStoryListHead.self)?.totalCount,123); d.dispose()
    }
    func testAbsentProfileCacheDoesNotInventStoryHead() {
        let c = Context(); seed(c); c.account.postbox.storage.cache.removeAll(); let d = c.reorderFolders(ids: [3,2,1]); c.account.network.requests.first?.succeed(Api.Bool.boolTrue)
        XCTAssertNil(cache(c)); XCTAssertEqual(c.stateValue.availableFolders.map(\.id),[3,2,1]); d.dispose()
    }
}
