import Foundation
import XCTest
import SwiftSignalKit

typealias PeerId = Int
typealias TelegramMediaFile = Int
extension Int { func toInt64() -> Int64 { Int64(self) } }
struct EngineMedia: Equatable { let value: Int; init(_ value: Int) { self.value = value } }
struct EngineStoryPrivacy: Equatable { let value: Int; init(_ value: Int) { self.value = value } }
struct Peer { let id: Int }
struct PeerReference: Equatable { let id: Int; init(_ peer: Peer) { id = peer.id } }
struct EnginePeer: Equatable { let id: Int; init(_ peer: Peer) { id = peer.id } }
struct StoryId: Equatable { let peerId: Int; let id: Int32 }
struct EngineStoryItem: Equatable {
    struct Views: Equatable { let seenCount: Int; let reactedCount: Int; let forwardCount: Int; let seenPeers: [EnginePeer]; let reactions: [Int]; let hasList: Bool }
    struct ForwardInfo: Equatable { init(_ info: Int, transaction: Transaction) {} }
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
    func asStoryItem() -> Stories.Item { .init(id: id, text: text) }
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
enum Stories {
    struct Item {
        struct Views { var seenCount = 0; var reactedCount = 0; var forwardCount = 0; var seenPeerIds: [Int] = []; var reactions: [Int] = []; var hasList = false }
        var id: Int32
        var text = "old"
        var timestamp = 0
        var expirationTimestamp = 100
        var media: Int? = 1
        var alternativeMediaList: [Int] = []
        var mediaAreas: [Area] = []
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
        var forwardInfo: Int? = nil
        var music: Int? = nil
        var authorId: Int? = nil
        var folderIds: [Int64]? = nil
    }
    enum StoredItem {
        case item(Item), placeholder(Int32)
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
enum Namespaces { enum Media { static let CloudFile = 1 }; enum CachedItemCollection { static let cachedPeerStoryListHeads = 1 } }
final class Transaction {
    var peer: Peer? = .init(id: 10)
    var cache: [ItemCacheEntryId: CodableEntry] = [:]
    var writes = 0
    var media: [MediaId: Int] = [:]
    func getMedia(_ id: MediaId) -> Any? { media[id] }
    func getPeer(_ id: Int) -> Peer? { peer }
    func retrieveItemCacheEntry(id: ItemCacheEntryId) -> CodableEntry? { cache[id] }
    func putItemCacheEntry(id: ItemCacheEntryId, entry: CodableEntry) { cache[id] = entry; writes += 1 }
}
final class Postbox {
    let storage = Transaction()
    var delayNext = false
    var finish: (() -> Void)?
    func transaction<T>(_ f: @escaping (Transaction) -> T) -> Signal<T, NoError> {
        Signal { subscriber in
            let run = { subscriber.putNext(f(self.storage)); subscriber.putCompletion() }
            if self.delayNext { self.delayNext = false; self.finish = run; return ActionDisposable { self.finish = nil } }
            run(); return EmptyDisposable
        }
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
        static func getAlbumStories(peer: InputPeer, albumId: Int32, offset: Int32, limit: Int32) -> RequestData<Api.stories.Stories> { .init(kind: "album", offset: Int(offset), peer: peer.id, album: albumId) }
        static func getStoriesArchive(peer: InputPeer, offsetId: Int32, limit: Int32) -> RequestData<Api.stories.Stories> { .init(kind: "archive", offset: Int(offsetId), peer: peer.id) }
        static func getPinnedStories(peer: InputPeer, offsetId: Int32, limit: Int32) -> RequestData<Api.stories.Stories> { .init(kind: "profile", offset: Int(offsetId), peer: peer.id) }
        static func getAlbums(peer: InputPeer, hash: Int) -> RequestData<Api.stories.Albums> { .init(kind: "folders", offset: 0, peer: peer.id) }
    } }
}
struct MTRpcError: Error {}
struct RequestData<T> { let kind: String; let offset: Int; let peer: Int; var album: Int32? = nil }
final class Request {
    let kind: String; let offset: Int; let peer: Int; let album: Int32?
    var next: ((Any) -> Void)?; var error: (() -> Void)?; var completed: (() -> Void)?
    var cancelled = false
    init<T>(_ data: RequestData<T>) { kind = data.kind; offset = data.offset; peer = data.peer; album = data.album }
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
final class Account { let peerId = 10; let postbox = Postbox(); let network = Network() }
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
    func subscribeToStoryUpdates() { subscriptions += 1 }
    __LOAD__
    __FINISH__
    deinit { __DISPOSE__ }
}

final class StoryListLoadingTests: XCTestCase {
    func page(_ ids: [Int32], count: Int32 = 200, pinned: [Int32]? = nil, text: String = "new") -> Api.stories.Stories { .stories(.init(count: count, stories: ids.map { .item(.init(id: $0, text: text)) }, pinnedToTop: pinned)) }
    func fullPage() -> [Int32] { Array(Int32(901)...1000).reversed() }
    func seed(_ c: Context, cached: Bool = false, offset: Int = 0) {
        c.stateValue.items = [.init(id: .init(peerId: 10, id: 1), storyItem: .init(id: 1))]; c.stateValue.totalCount = 70
        c.stateValue.availableFolders = [.init(id: 7, title: "old")]; c.stateValue.pinnedIds = [1]; c.stateValue.isCached = cached; c.stateValue.hasCache = true; c.stateValue.loadMoreToken = AnyHashable(offset)
    }
    func finishFolders(_ c: Context) { for r in c.account.network.requests where r.kind == "folders" && !r.cancelled { r.succeed(Api.stories.Albums.albumsNotModified) } }
    func testAlbumUsesRawNumericOffsetInsteadOfStoryId() {
        let c = Context(); c.loadMore(completion: nil); c.account.network.requests.first?.succeed(page(fullPage())); c.loadMore(completion: nil)
        XCTAssertEqual(c.account.network.requests.last?.offset, 100); XCTAssertEqual(c.account.network.requests.last?.album, 7)
        c.account.network.requests.last?.succeed(page(Array(Int32(801)...900).reversed())); c.loadMore(completion: nil); XCTAssertEqual(c.account.network.requests.last?.offset, 200)
    }
    func testArchiveUsesRawLastIdEvenWhenNotRenderable() {
        let c = Context(folder: nil, archived: true); var stories = fullPage().map { Api.StoryItem.item(.init(id: $0)) }; stories[99] = .placeholder(901)
        c.loadMore(completion: nil); c.account.network.requests.first?.succeed(Api.stories.Stories.stories(.init(count: 200, stories: stories, pinnedToTop: nil))); c.loadMore(completion: nil)
        XCTAssertEqual(c.account.network.requests.last?.offset, 901)
    }
    func testAlbumFilteredAndDuplicateItemsStillAdvanceRawOffset() {
        let c = Context(); var stories = Array(repeating: Api.StoryItem.item(.init(id: 300)), count: 100); stories[99] = .deleted(200)
        c.loadMore(completion: nil); c.account.network.requests.first?.succeed(Api.stories.Stories.stories(.init(count: 200, stories: stories, pinnedToTop: nil)))
        XCTAssertEqual(c.stateValue.items.count, 1); XCTAssertEqual(c.stateValue.loadMoreToken?.base as? Int, 100)
    }
    func testEntirelyFilteredPageDoesNotEndPagination() {
        let c = Context(); let stories = fullPage().map(Api.StoryItem.placeholder)
        c.loadMore(completion: nil); c.account.network.requests.first?.succeed(Api.stories.Stories.stories(.init(count: 200, stories: stories, pinnedToTop: nil)))
        XCTAssertTrue(c.stateValue.items.isEmpty); XCTAssertEqual(c.stateValue.loadMoreToken?.base as? Int, 100); XCTAssertEqual(c.stateValue.totalCount, 200)
    }
    func testFirstPageFailurePreservesCachedStateAndCanRetry() {
        let c = Context(); seed(c, cached: true); var completions = 0
        c.loadMore(completion: { completions += 1 }); c.account.network.requests.first?.fail()
        XCTAssertTrue(c.stateValue.isCached); XCTAssertEqual(c.stateValue.items.map { $0.storyItem.id }, [1]); XCTAssertEqual(c.stateValue.totalCount, 70); XCTAssertEqual(c.stateValue.availableFolders.first?.title, "old"); XCTAssertEqual(c.stateValue.loadMoreToken?.base as? Int, 0); XCTAssertEqual(completions, 1)
        c.loadMore(completion: nil); XCTAssertEqual(c.account.network.requests.count, 2)
    }
    func testLaterFailureKeepsCursorAndMetadata() {
        let c = Context(); seed(c, offset: 100); c.loadMore(completion: nil); c.account.network.requests.first?.fail()
        XCTAssertEqual(c.stateValue.loadMoreToken?.base as? Int, 100); XCTAssertEqual(c.stateValue.totalCount, 70); XCTAssertEqual(c.stateValue.availableFolders.first?.id, 7); XCTAssertEqual(c.stateValue.items.count, 1)
    }
    func testMissingPeerIsRetryableWithoutClearingCache() {
        let c = Context(); seed(c, cached: true); c.account.postbox.storage.peer = nil; var done = 0; c.loadMore(completion: { done += 1 })
        XCTAssertEqual(done, 1); XCTAssertTrue(c.account.network.requests.isEmpty); XCTAssertTrue(c.stateValue.isCached); XCTAssertNotNil(c.stateValue.loadMoreToken)
        c.account.postbox.storage.peer = .init(id: 10); c.loadMore(completion: nil); XCTAssertEqual(c.account.network.requests.count, 1)
    }
    func testSuccessReplacesCachedItemsAndEmptySuccessIsTerminal() {
        let c = Context(); seed(c, cached: true); c.loadMore(completion: nil); c.account.network.requests.first?.succeed(page([],count: 0))
        XCTAssertFalse(c.stateValue.isCached); XCTAssertTrue(c.stateValue.hasCache); XCTAssertTrue(c.stateValue.items.isEmpty); XCTAssertEqual(c.stateValue.totalCount, 0); XCTAssertNil(c.stateValue.loadMoreToken)
    }
    func testLoadingStateAndDuplicateRequests() {
        let c = Context(); var completed = 0; c.loadMore(completion: { completed += 1 }); c.loadMore(completion: { completed += 1 })
        XCTAssertTrue(c.stateValue.isLoading); XCTAssertEqual(c.account.network.requests.count, 1)
        c.account.network.requests.first?.succeed(page([1])); XCTAssertFalse(c.stateValue.isLoading); XCTAssertEqual(completed, 2)
    }
    func testTerminalLoadCompletesCallbackWithoutRequest() {
        let c = Context(); c.stateValue.loadMoreToken = nil; var done = 0; c.loadMore(completion: { done += 1 }); XCTAssertEqual(done, 1); XCTAssertTrue(c.account.network.requests.isEmpty)
    }
    func testDuplicatePageRefreshesMetadataWithoutReorderingAlbum() {
        let c = Context(); seed(c, offset: 100); c.loadMore(completion: nil); c.account.network.requests.first?.succeed(page([1,2],text: "updated"))
        XCTAssertEqual(c.stateValue.items.map { $0.storyItem.id }, [1,2]); XCTAssertEqual(c.stateValue.items.first?.storyItem.text, "updated"); XCTAssertEqual(c.stateValue.unrelatedMetadata, 7)
    }
    func testProfileReceivesPinnedIdsAndSuccessfulEmptyFolders() {
        let c = Context(folder: nil); seed(c, cached: true); c.loadMore(completion: nil)
        c.account.network.requests.first(where: { $0.kind == "profile" })?.succeed(page([3,2],pinned: [3]))
        c.account.network.requests.first(where: { $0.kind == "folders" })?.succeed(Api.stories.Albums.albums(.init(albums: [])))
        XCTAssertEqual(c.stateValue.pinnedIds, [3]); XCTAssertTrue(c.stateValue.availableFolders.isEmpty)
    }
    func testFoldersFailurePreservesCurrentFoldersOnStorySuccess() {
        let c = Context(folder: nil); seed(c); c.loadMore(completion: nil)
        c.account.network.requests.first(where: { $0.kind == "profile" })?.succeed(page([2]))
        c.account.network.requests.first(where: { $0.kind == "folders" })?.fail()
        XCTAssertEqual(c.stateValue.availableFolders, [.init(id: 7,title: "old")]); XCTAssertEqual(c.stateValue.items.map { $0.storyItem.id }, [1,2])
    }
    func testLaterPageWithoutPinnedMetadataPreservesCurrentPins() {
        let c = Context(folder: nil); seed(c, offset: 100); c.loadMore(completion: nil)
        c.account.network.requests.first(where: { $0.kind == "profile" })?.succeed(page([2])); finishFolders(c); XCTAssertEqual(c.stateValue.pinnedIds,[1])
    }
    func testFirstPageWithoutPinnedIdsClearsObsoletePins() {
        let c = Context(folder: nil); seed(c, cached: true); c.loadMore(completion: nil)
        c.account.network.requests.first(where: { $0.kind == "profile" })?.succeed(page([2])); finishFolders(c); XCTAssertEqual(c.stateValue.pinnedIds, [])
    }
    func testNonAdvancingArchiveCursorTerminates() {
        let c = Context(folder: nil, archived: true); c.stateValue.loadMoreToken = AnyHashable(901); c.loadMore(completion: nil)
        c.account.network.requests.first?.succeed(page(fullPage())); XCTAssertNil(c.stateValue.loadMoreToken)
    }
    func testEmptyCompletionReleasesLoadingAndCallbacks() {
        let c = Context(); seed(c, cached: true); var done = 0; c.loadMore(completion: { done += 1 }); c.account.network.requests.first?.empty()
        XCTAssertFalse(c.stateValue.isLoading); XCTAssertTrue(c.stateValue.isCached); XCTAssertEqual(done,1); c.loadMore(completion: nil); XCTAssertEqual(c.account.network.requests.count,2)
    }
    func testReentrantStateObserverCannotStartDuplicatePage() {
        let c = Context(); var entered = false
        c.onState = { [weak c] state in if state.isLoading && !entered { entered = true; c?.loadMore(completion: nil) } }
        c.loadMore(completion: nil); XCTAssertTrue(entered); XCTAssertEqual(c.account.network.requests.count,1)
    }
    func testSynchronousCompletionCannotLoseNextRequestOwnership() {
        let a = Account(); var first = true
        a.network.onRequest = { request in if first { first = false; request.succeed(self.page(self.fullPage())) } }
        var c: Context? = Context(a); weak var owner = c
        c?.loadMore(completion: { [weak c] in c?.loadMore(completion: nil) })
        XCTAssertEqual(a.network.requests.count,2); c = nil; XCTAssertNil(owner); XCTAssertTrue(a.network.requests.last?.cancelled == true)
    }
    func testReentrantCompletionDoesNotFinishNewPendingRequest() {
        let c = Context(); var done = 0
        c.loadMore(completion: { [weak c] in done += 1; c?.loadMore(completion: { done += 1 }) })
        c.account.network.requests.first?.succeed(page(fullPage())); XCTAssertTrue(c.stateValue.isLoading); XCTAssertEqual(done,1)
        c.account.network.requests.last?.succeed(page([500])); XCTAssertFalse(c.stateValue.isLoading); XCTAssertEqual(done,2)
    }
    func testOwnerReleaseCancelsValidation() {
        let a = Account(); a.postbox.delayNext = true; var c: Context? = Context(a); weak var owner = c
        c?.loadMore(completion: nil); c = nil; XCTAssertNil(owner); a.postbox.finish?(); XCTAssertTrue(a.network.requests.isEmpty)
    }
    func testOwnerReleaseCancelsRequestAndSuppressesLateCacheWrite() {
        let a = Account(); var c: Context? = Context(a); weak var owner = c; c?.loadMore(completion: nil); c = nil
        XCTAssertNil(owner); XCTAssertTrue(a.network.requests.first?.cancelled == true); a.network.requests.first?.succeed(page([1])); XCTAssertEqual(a.postbox.storage.writes,0)
    }
    func testOwnerReleaseCancelsPageCommit() {
        let a = Account(); var c: Context? = Context(a); c?.loadMore(completion: nil); a.postbox.delayNext = true; a.network.requests.first?.succeed(page([1]))
        XCTAssertNotNil(a.postbox.finish); c = nil; a.postbox.finish?(); XCTAssertEqual(a.postbox.storage.writes,0)
    }
    func testDuplicatePageEntriesAreNormalizedBeforeCaching() {
        let c = Context(); c.loadMore(completion: nil)
        let stories: [Api.StoryItem] = [.item(.init(id: 1,text: "old")), .item(.init(id: 1,text: "new"))]
        c.account.network.requests.first?.succeed(Api.stories.Stories.stories(.init(count: 1, stories: stories, pinnedToTop: nil)))
        XCTAssertEqual(c.account.postbox.storage.cache.first?.value.get(CachedPeerStoryListHead.self)?.items.count,1)
        XCTAssertEqual(c.stateValue.items.count,1); XCTAssertEqual(c.stateValue.items.first?.storyItem.text,"new")
    }
    func testFreshPinMetadataReordersProfileButNotAlbum() {
        for folder: Int64? in [nil,7] {
            let c = Context(folder: folder); seed(c, offset: 100); c.loadMore(completion: nil)
            c.account.network.requests.first?.succeed(page([2],pinned: [2])); finishFolders(c)
            XCTAssertEqual(c.stateValue.items.map { $0.storyItem.id }, folder == nil ? [2,1] : [1,2])
        }
    }
    func testAlbumCacheUsesAlbumIdentityAndPreservesOrder() {
        let c = Context(); c.loadMore(completion: nil); c.account.network.requests.first?.succeed(page([5,1,3]))
        let cache = c.account.postbox.storage.cache.first; XCTAssertEqual(cache?.key.key.length,17); XCTAssertEqual(cache?.key.key.fields[9],7)
        let ids = cache?.value.get(CachedPeerStoryListHead.self)?.items.compactMap { item -> Int32? in if case let .item(item) = item { return item.id }; return nil }
        XCTAssertEqual(ids,[5,1,3]); XCTAssertEqual(c.stateValue.items.map { $0.storyItem.id },[5,1,3])
    }
}
