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
    let queue = Queue.mainQueue()
    var stateValue = State() { didSet { onState?(stateValue) } }
    var onState: ((State) -> Void)?
    init(_ account: Account = Account()) { self.account = account }
    __CREATE__
}
enum External {
    __EXTERNAL__
}

final class StoryAlbumCreationTests: XCTestCase {
    func key(_ album: Int64? = nil, archive: Bool = false, peer: Int64 = 10) -> ItemCacheEntryId {
        let key = ValueBoxKey(length: album == nil ? 9 : 17)
        key.setInt64(0, value: peer); key.setInt8(8,value: archive ? 1 : 0)
        if let album { key.setInt64(9,value: album) }
        return ItemCacheEntryId(collectionId: 1,key: key)
    }
    func seed(_ c: Context) {
        c.stateValue.items = [1,2,3].map { .init(id: .init(peerId: 10,id: $0),storyItem: .init(id: $0)) }
        c.stateValue.availableFolders = [.init(id: 4,title: "existing")]
        c.stateValue.totalCount = 150
        c.account.postbox.storage.cache[key()] = CodableEntry(CachedPeerStoryListHead(items: [.item(.init(id: 90,text: "latest"))],pinnedIds: [90],totalCount: 200,folders: [.init(id: 4,title: "cached")]))
    }
    func cache(_ c: Context, _ album: Int64? = nil) -> CachedPeerStoryListHead? { c.account.postbox.storage.cache[key(album)]?.get(CachedPeerStoryListHead.self) }
    func response(_ id: Int32 = 7, title: String = "server") -> Api.StoryAlbum { .storyAlbum(.init(albumId: id,title: title)) }
    func testOnlySelectedStoriesSeedAlbum() {
        let c = Context(); seed(c)
        let d = c.addFolder(title: "new",items: [.init(id: 2)],completion: { _ in })
        c.account.network.requests.first?.succeed(response())
        XCTAssertEqual(cache(c,7)?.items.map(\.id),[2]); XCTAssertEqual(cache(c,7)?.totalCount,1); d.dispose()
    }
    func testEmptyAlbumDoesNotCopyProfile() {
        let c = Context(); seed(c)
        let d = c.addFolder(title: "new",items: [],completion: { _ in })
        c.account.network.requests.first?.succeed(response())
        XCTAssertEqual(cache(c,7)?.items.count,0); XCTAssertEqual(cache(c,7)?.totalCount,0); d.dispose()
    }
    func testPreservesLatestMainCache() {
        let c = Context(); seed(c)
        let d = c.addFolder(title: "new",items: [],completion: { _ in })
        c.account.network.requests.first?.succeed(response())
        XCTAssertEqual(cache(c)?.items.map(\.id),[90]); XCTAssertEqual(cache(c)?.pinnedIds,[90]); XCTAssertEqual(cache(c)?.totalCount,200)
        XCTAssertEqual(cache(c)?.folders.first?.title,"cached"); d.dispose()
    }
    func testUsesServerTitleInStateAndCache() {
        let c = Context(); seed(c)
        let d = c.addFolder(title: "requested",items: [],completion: { _ in })
        c.account.network.requests.first?.succeed(response(title: "accepted"))
        XCTAssertEqual(c.stateValue.availableFolders.last?.title,"accepted"); XCTAssertEqual(cache(c)?.folders.last?.title,"accepted"); d.dispose()
    }
    func testDeduplicatesSubmittedStoriesPreservingOrder() {
        let c = Context(); let d = c.addFolder(title: "new",items: [.init(id: 3),.init(id: 1),.init(id: 3)],completion: { _ in })
        XCTAssertEqual(c.account.network.requests.first?.stories,[3,1]); c.account.network.requests.first?.succeed(response())
        XCTAssertEqual(cache(c,7)?.items.map(\.id),[3,1]); XCTAssertEqual(cache(c,7)?.totalCount,2); d.dispose()
    }
    func testInvalidIdsFailWithoutRequestOrMutation() {
        for id: Int32 in [0,-1] {
            let c = Context(); seed(c); var ids: [Int64?] = []
            let d = c.addFolder(title: "new",items: [.init(id: id)],completion: { ids.append($0) })
            XCTAssertTrue(c.account.network.requests.isEmpty); XCTAssertEqual(ids.count,1); XCTAssertTrue(ids.first.map { $0 == nil } ?? false); XCTAssertEqual(c.account.postbox.storage.writes,0); d.dispose()
        }
    }
    func testPendingStoriesFailWithoutRequest() {
        let c = Context(); var item = EngineStoryItem(id: 2); item.isPending = true
        let d = c.addFolder(title: "new",items: [item],completion: { XCTAssertNil($0) })
        XCTAssertTrue(c.account.network.requests.isEmpty); d.dispose()
    }
    func testFailureDoesNotMutateAndReportsNilOnce() {
        let c = Context(); seed(c); var results: [Int64?] = []
        let d = c.addFolder(title: "new",items: [],completion: { results.append($0) }); c.account.network.requests.first?.fail()
        XCTAssertEqual(results.count,1); XCTAssertTrue(results.first.map { $0 == nil } ?? false); XCTAssertEqual(c.stateValue.availableFolders.count,1); XCTAssertEqual(c.account.postbox.storage.writes,0); d.dispose()
    }
    func testMissingPeerFailsWithoutRequest() {
        let c = Context(); c.account.postbox.storage.peer = nil; var results: [Int64?] = []
        let d = c.addFolder(title: "new",items: [],completion: { results.append($0) })
        XCTAssertEqual(results.count,1); XCTAssertTrue(results.first.map { $0 == nil } ?? false); XCTAssertTrue(c.account.network.requests.isEmpty); XCTAssertEqual(c.account.postbox.storage.writes,0); d.dispose()
    }
    func testCancelPendingRequest() {
        let c = Context(); seed(c); var count = 0
        let d = c.addFolder(title: "new",items: [],completion: { _ in count += 1 }); d.dispose(); c.account.network.requests.first?.succeed(response())
        XCTAssertTrue(c.account.network.requests.first?.cancelled == true); XCTAssertEqual(count,0); XCTAssertEqual(c.account.postbox.storage.writes,0)
    }
    func testCancelPendingCacheWrite() {
        let c = Context(); seed(c); var count = 0
        let d = c.addFolder(title: "new",items: [],completion: { _ in count += 1 }); c.account.postbox.hold = true
        c.account.network.requests.first?.succeed(response()); d.dispose(); c.account.postbox.flush()
        XCTAssertEqual(count,0); XCTAssertEqual(c.account.postbox.storage.writes,0); XCTAssertEqual(c.stateValue.availableFolders.count,1)
    }
    func testPublishesOnlyAfterCacheCommit() {
        let c = Context(); seed(c); var ids: [Int64?] = []
        let d = c.addFolder(title: "new",items: [],completion: { ids.append($0) }); c.account.postbox.hold = true
        c.account.network.requests.first?.succeed(response()); XCTAssertTrue(ids.isEmpty); XCTAssertEqual(c.stateValue.availableFolders.count,1)
        c.account.postbox.flush(); XCTAssertEqual(ids,[7]); XCTAssertEqual(c.stateValue.availableFolders.count,2); d.dispose()
    }
    func testContextCanDeallocateDuringRequest() {
        let account = Account(); var c: Context? = Context(account); weak var weakContext = c; var count = 0
        let d = c!.addFolder(title: "new",items: [],completion: { _ in count += 1 }); c = nil
        XCTAssertNil(weakContext); account.network.requests.first?.succeed(response()); XCTAssertEqual(count,0); d.dispose()
    }
    func testContextCanDeallocateDuringCacheWrite() {
        let account = Account(); var c: Context? = Context(account); weak var weakContext = c; var count = 0
        let d = c!.addFolder(title: "new",items: [],completion: { _ in count += 1 }); account.postbox.hold = true
        account.network.requests.first?.succeed(response()); c = nil; XCTAssertNil(weakContext); account.postbox.flush(); XCTAssertEqual(count,0); d.dispose()
    }
    func testStoresFolderWithoutExistingProfileCache() {
        let c = Context(); let d = c.addFolder(title: "new",items: [],completion: { _ in }); c.account.network.requests.first?.succeed(response())
        XCTAssertEqual(cache(c)?.folders,[.init(id: 7,title: "server")]); XCTAssertNotNil(cache(c,7)); d.dispose()
    }
    func testCapsAlbumHeadButPreservesTotal() {
        let c = Context(); let d = c.addFolder(title: "new",items: (1...120).map { .init(id: Int32($0)) },completion: { _ in })
        c.account.network.requests.first?.succeed(response()); XCTAssertEqual(cache(c,7)?.items.count,100); XCTAssertEqual(cache(c,7)?.totalCount,120); d.dispose()
    }
    func testExistingFolderNotDuplicated() {
        let c = Context(); seed(c)
        let d = c.addFolder(title: "new",items: [],completion: { _ in }); c.account.network.requests.first?.succeed(response(4,title: "accepted"))
        XCTAssertEqual(c.stateValue.availableFolders,[.init(id: 4,title: "accepted")]); XCTAssertEqual(cache(c)?.folders,[.init(id: 4,title: "accepted")]); d.dispose()
    }
    func testConcurrentCreatesKeepBothAndCurrentState() {
        let c = Context(); seed(c)
        let a = c.addFolder(title: "A",items: [],completion: { _ in }); let b = c.addFolder(title: "B",items: [],completion: { _ in })
        c.stateValue.availableFolders.append(.init(id: 5,title: "live"))
        c.account.network.requests[1].succeed(response(8)); c.account.network.requests[0].succeed(response(7))
        XCTAssertEqual(c.stateValue.availableFolders.map(\.id),[4,5,8,7]); XCTAssertEqual(cache(c)?.folders.map(\.id),[4,8,7]); a.dispose(); b.dispose()
    }
    func testSynchronousResponseCommitsBeforeCallback() {
        let c = Context(); seed(c); var count = 0; c.account.network.onRequest = { $0.succeed(self.response()) }
        let d = c.addFolder(title: "new",items: [.init(id: 2)],completion: { id in count += 1; XCTAssertEqual(id,7); XCTAssertEqual(self.cache(c,7)?.items.map(\.id),[2]) })
        XCTAssertEqual(count,1); d.dispose()
    }
    func testExternalCancellationOwnsCacheTransaction() {
        let c = Context(); seed(c); var count = 0
        let d = External.addFolderExternal(account: c.account,peerId: 10,title: "new",completion: { _ in count += 1 }); c.account.postbox.hold = true
        c.account.network.requests.first?.succeed(response()); d.dispose(); c.account.postbox.flush()
        XCTAssertEqual(count,0); XCTAssertEqual(c.account.postbox.storage.writes,0)
    }
    func testExternalUsesServerTitleAndPreservesProfile() {
        let c = Context(); seed(c); var ids: [Int64?] = []
        let d = External.addFolderExternal(account: c.account,peerId: 10,title: "new",completion: { ids.append($0) }); c.account.network.requests.first?.succeed(response())
        XCTAssertEqual(ids,[7]); XCTAssertEqual(cache(c)?.folders.last?.title,"server"); XCTAssertEqual(cache(c)?.items.map(\.id),[90]); XCTAssertEqual(cache(c,7)?.items.count,0); d.dispose()
    }
    func testExternalFailure() {
        let c = Context(); var ids: [Int64?] = []
        let d = External.addFolderExternal(account: c.account,peerId: 10,title: "new",completion: { ids.append($0) }); c.account.network.requests.first?.fail()
        XCTAssertEqual(ids.count,1); XCTAssertTrue(ids.first.map { $0 == nil } ?? false); XCTAssertEqual(c.account.postbox.storage.writes,0); d.dispose()
    }
    func testEmptyResponseReportsFailureOnce() {
        let c = Context(); var ids: [Int64?] = []
        let d = c.addFolder(title: "new",items: [],completion: { ids.append($0) }); c.account.network.requests.first?.empty()
        XCTAssertEqual(ids.count,1); XCTAssertTrue(ids.first.map { $0 == nil } ?? false); XCTAssertEqual(c.account.postbox.storage.writes,0); d.dispose()
    }
    func testExternalEmptyResponseReportsFailureOnce() {
        let c = Context(); var ids: [Int64?] = []
        let d = External.addFolderExternal(account: c.account,peerId: 10,title: "new",completion: { ids.append($0) }); c.account.network.requests.first?.empty()
        XCTAssertEqual(ids.count,1); XCTAssertTrue(ids.first.map { $0 == nil } ?? false); d.dispose()
    }
    func testDisposalDuringStatePublicationSuppressesCompletion() {
        let c = Context(); seed(c); var count = 0; let owner = MetaDisposable()
        owner.set(c.addFolder(title: "new",items: [],completion: { _ in count += 1 }))
        c.onState = { _ in owner.dispose() }
        c.account.network.requests.first?.succeed(response())
        XCTAssertEqual(count,0); XCTAssertEqual(cache(c)?.folders.last?.id,7)
    }
    func testCancelPeerResolution() {
        let c = Context(); c.account.postbox.hold = true; var count = 0
        let d = c.addFolder(title: "new",items: [],completion: { _ in count += 1 }); d.dispose(); c.account.postbox.flush()
        XCTAssertTrue(c.account.network.requests.isEmpty); XCTAssertEqual(count,0); XCTAssertEqual(c.account.postbox.storage.writes,0)
    }
    func testOtherAlbumAndArchiveCachesUnaffected() {
        let c = Context(); seed(c)
        let old = CodableEntry(CachedPeerStoryListHead(items: [.item(.init(id: 99))],pinnedIds: [],totalCount: 50,folders: []))
        c.account.postbox.storage.cache[key(9)] = old; c.account.postbox.storage.cache[key(archive: true)] = old
        let d = c.addFolder(title: "new",items: [.init(id: 2)],completion: { _ in }); c.account.network.requests.first?.succeed(response())
        XCTAssertEqual(cache(c,9)?.items.map(\.id),[99]); XCTAssertEqual(c.account.postbox.storage.cache[key(archive: true)]?.get(CachedPeerStoryListHead.self)?.totalCount,50); d.dispose()
    }
    func testExternalStoresFolderWithoutExistingProfileCache() {
        let c = Context()
        let d = External.addFolderExternal(account: c.account,peerId: 10,title: "new",completion: { _ in }); c.account.network.requests.first?.succeed(response())
        XCTAssertEqual(cache(c)?.folders,[.init(id: 7,title: "server")]); XCTAssertEqual(cache(c,7)?.totalCount,0); d.dispose()
    }

}
