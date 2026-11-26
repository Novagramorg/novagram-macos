import Foundation
import XCTest
import SwiftSignalKit

typealias PeerId = Int
typealias TelegramMediaFile = Int
extension Int { static var stars: Int { -123456 }; var namespace: Int { self >= 100 ? 1 : 0 }; func toInt64() -> Int64 { Int64(self) } }
struct EngineMedia: Equatable { let value: Int; init(_ value: Int) { self.value = value } }
struct EngineStoryPrivacy: Equatable { let value: Int; init(_ value: Int) { self.value = value } }
struct Peer { let id: Int }
struct PeerReference: Equatable { let id: Int; init(_ peer: Peer) { id = peer.id } }
struct EnginePeer: Equatable { let id: Int; init(_ peer: Peer) { id = peer.id } }
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
    func send(_ updates: [InternalStoryUpdate]) { pipe.putNext(updates) }
}
final class Account { let peerId = 10; let postbox = Postbox(); let network = Network(); let stateManager = StateManager() }
__MEMBERSHIP_HELPERS__
final class Context {
    typealias State = StoryListContextState
    let account: Account
    let peerId: Int
    let isArchived: Bool
    let folderId: Int64?
    let queue = Queue.mainQueue()
    var stateValue = State() { didSet { onState?(stateValue) } }
    var onState: ((State) -> Void)?
    var completionCallbacksByToken: [AnyHashable: [() -> Void]] = [:]
    var subscriptions = 0
    __PROPERTIES__
    init(_ account: Account = Account(), folder: Int64? = 7, archived: Bool = false, peer: Int = 10) { self.account = account; self.peerId = peer; folderId = folder; isArchived = archived; __INITIALIZATION_READY__ }
    func begin() { subscribeToStoryUpdates() }
    __LOAD__
    __FINISH__
    __UPDATE_LIFECYCLE__
    __SUBSCRIBE__
    __RELOAD__
    __DEINIT__
}

final class StoryLiveUpdatesTests: XCTestCase {
    func seed(_ c: Context, ids: [Int32] = [3,1,2], partial: Bool = false) {
        c.stateValue.items = ids.map { .init(id: .init(peerId: 10,id: $0),storyItem: .init(id: $0, timestamp: Int($0),folderIds: c.folderId.map { [$0] })) }
        c.stateValue.totalCount = partial ? 100 : ids.count; c.stateValue.loadMoreToken = partial ? AnyHashable(100) : nil
        c.stateValue.hasCache = true; c.stateValue.availableFolders = [.init(id: 7,title: "kept")]
    }
    func added(_ id: Int32, peer: Int = 10, text: String = "new", pinned: Bool = true, folders: [Int64]? = nil) -> InternalStoryUpdate {
        var item = Stories.Item(id: id,text: text); item.timestamp = Int(id); item.isPinned = pinned; item.folderIds = folders
        return .added(peerId: peer,item: .item(item))
    }
    func ids(_ c: Context) -> [Int32] { c.stateValue.items.map { $0.storyItem.id } }
    func page(_ ids: [Int32]) -> Api.stories.Stories { .stories(.init(count: Int32(ids.count),stories: ids.map { .item(.init(id: $0,text: "server")) },pinnedToTop: nil)) }
    func testAlbumReceivesMetadataWithoutChangingCustomOrder() {
        let c = Context(); seed(c); c.begin(); c.account.stateManager.send([added(1,folders: [7])])
        XCTAssertEqual(ids(c),[3,1,2]); XCTAssertEqual(c.stateValue.items[1].storyItem.text,"new"); XCTAssertTrue(c.account.network.requests.isEmpty)
    }
    func testAlbumMetadataUsesAlbumCacheKeyOnly() {
        let c = Context(); seed(c); c.begin(); c.account.stateManager.send([added(1,folders: [7])])
        XCTAssertEqual(c.account.postbox.storage.cache.count,1)
        let cache = c.account.postbox.storage.cache.first
        XCTAssertEqual(cache?.key.key.length,17); XCTAssertEqual(cache?.key.key.fields[9],7); XCTAssertTrue(cache?.value.get(CachedPeerStoryListHead.self)?.folders.isEmpty == true)
    }
    func testDeletedAlbumStoryDisappearsAndRefetchesServerOrder() {
        let c = Context(); seed(c); c.begin(); c.account.stateManager.send([.deleted(peerId: 10,id: 1)])
        XCTAssertEqual(ids(c),[3,2]); XCTAssertEqual(c.stateValue.totalCount,2); XCTAssertEqual(c.account.network.requests.first?.offset,0)
        c.account.network.requests.first?.succeed(page([2,3])); XCTAssertEqual(ids(c),[2,3]); XCTAssertFalse(c.stateValue.isLoading)
    }
    func testDeletedStoryIsRemovedFromCacheBeforeRefreshFailure() {
        let c = Context(); seed(c); c.begin(); c.account.stateManager.send([.deleted(peerId: 10,id: 1)]); c.account.network.requests.first?.fail()
        let cached = c.account.postbox.storage.cache.first?.value.get(CachedPeerStoryListHead.self)
        let cachedIds = cached?.items.map { $0.id }; XCTAssertEqual(cachedIds,[3,2]); XCTAssertEqual(ids(c),[3,2]); XCTAssertNotNil(c.stateValue.loadMoreToken)
    }
    func testProfileArchiveFlagDoesNotRemoveAlbumMembership() {
        let c = Context(); seed(c); c.begin(); c.account.stateManager.send([added(1,pinned: false,folders: [7])])
        XCTAssertEqual(ids(c),[3,1,2]); XCTAssertEqual(c.stateValue.items[1].storyItem.isPinned,false)
    }
    func testUnknownAlbumMembershipPreservesExistingStory() {
        let c = Context(); seed(c); c.begin(); c.account.stateManager.send([added(1,pinned: false)])
        XCTAssertEqual(ids(c),[3,1,2]); XCTAssertEqual(c.stateValue.items[1].storyItem.text,"new"); XCTAssertTrue(c.account.network.requests.isEmpty)
    }
    func testExplicitMembershipRemovalKeepsGlobalPinsAndRefreshes() {
        let c = Context(); seed(c); c.stateValue.pinnedIds = [1,3]; c.begin(); c.account.stateManager.send([added(1,folders: [])])
        XCTAssertEqual(ids(c),[3,2]); XCTAssertEqual(c.stateValue.pinnedIds,[1,3]); XCTAssertEqual(c.account.network.requests.first?.offset,0)
    }
    func testNewAlbumMemberWaitsForServerPosition() {
        let c = Context(); seed(c); c.begin(); c.account.stateManager.send([added(4,folders: [7])])
        XCTAssertEqual(ids(c),[3,1,2]); XCTAssertEqual(c.account.network.requests.count,1)
        c.account.network.requests.first?.succeed(page([3,4,1,2])); XCTAssertEqual(ids(c),[3,4,1,2])
    }
    func testNonMemberOrUnknownNewStoryDoesNotEnterAlbum() {
        let c = Context(); seed(c); c.begin(); c.account.stateManager.send([added(4,folders: [9]),added(5)])
        XCTAssertEqual(ids(c),[3,1,2]); XCTAssertTrue(c.account.network.requests.isEmpty); XCTAssertEqual(c.account.postbox.storage.writes,0)
    }
    func testAlbumTopPinsDoNotReorderCustomSequence() {
        let c = Context(); seed(c); c.begin(); c.account.stateManager.send([.updatePinnedToTopList(peerId: 10,ids: [2])])
        XCTAssertEqual(c.stateValue.pinnedIds,[2]); XCTAssertEqual(ids(c),[3,1,2])
    }
    func testForeignPeerAndReadEventsDoNotReadOrWriteStore() {
        let c = Context(folder: nil); seed(c); c.begin(); c.account.stateManager.send([added(1,peer: 20),.deleted(peerId: 20,id: 3),.read(peerId: 10,maxId: 3)])
        XCTAssertEqual(ids(c),[3,1,2]); XCTAssertEqual(c.account.postbox.subscriptions,0)
    }
    func testProfileNewStoryUpdatesCountAndPinOrder() {
        let c = Context(folder: nil); seed(c,ids: [1,2]); c.stateValue.pinnedIds = [1]; c.begin(); c.account.stateManager.send([added(3)])
        XCTAssertEqual(ids(c),[1,3,2]); XCTAssertEqual(c.stateValue.totalCount,3)
    }
    func testProfileRemovalAlsoClearsTopPin() {
        let c = Context(folder: nil); seed(c); c.stateValue.pinnedIds = [1]; c.begin(); c.account.stateManager.send([added(1,pinned: false)])
        XCTAssertEqual(ids(c),[3,2]); XCTAssertTrue(c.stateValue.pinnedIds.isEmpty); XCTAssertEqual(c.stateValue.totalCount,2)
    }
    func testDeletingUnloadedTopPinClearsIdWithoutChangingUnknownCount() {
        let c = Context(folder: nil); seed(c,partial: true); c.stateValue.pinnedIds = [99]; c.begin(); c.account.stateManager.send([.deleted(peerId: 10,id: 99)])
        XCTAssertTrue(c.stateValue.pinnedIds.isEmpty); XCTAssertEqual(c.stateValue.totalCount,100)
    }
    func testArchiveKeepsStoryWhenRemovedFromProfile() {
        let c = Context(folder: nil,archived: true); seed(c); c.begin(); c.account.stateManager.send([added(1,pinned: false)])
        XCTAssertEqual(ids(c),[3,2,1]); XCTAssertEqual(c.stateValue.items.last?.storyItem.isPinned,false)
    }
    func testQueuedUpdatesCannotResurrectDeletedStory() {
        let c = Context(folder: nil); seed(c); c.begin(); c.account.postbox.hold = true
        c.account.stateManager.send([added(1)]); c.account.stateManager.send([.deleted(peerId: 10,id: 1)])
        XCTAssertEqual(c.account.postbox.pending.count,1)
        if c.account.postbox.pending.count > 1 { c.account.postbox.pending[1].run() }
        c.account.postbox.flush(); XCTAssertFalse(ids(c).contains(1))
    }
    func testCacheWritesCompleteBeforeNextUpdateReads() {
        let c = Context(folder: nil); seed(c); c.begin(); c.account.postbox.hold = true
        c.account.stateManager.send([added(1,text: "first")]); c.account.stateManager.send([added(1,text: "second")]); c.account.postbox.pending.first?.run()
        XCTAssertEqual(c.account.postbox.pending.count,2); XCTAssertEqual(c.account.postbox.storage.writes,0)
        c.account.postbox.flush(); XCTAssertEqual(c.stateValue.items.first(where: { $0.storyItem.id == 1 })?.storyItem.text,"second")
        let cached = c.account.postbox.storage.cache.first?.value.get(CachedPeerStoryListHead.self)?.items
        let text = cached?.compactMap { item -> String? in if case let .item(item) = item, item.id == 1 { return item.text }; return nil }.first
        XCTAssertEqual(text,"second")
    }
    func testOwnerReleaseCancelsPendingUpdateRead() {
        let a = Account(); var c: Context? = Context(a,folder: nil); weak var owner = c; seed(c!); c?.begin(); a.postbox.hold = true; a.stateManager.send([added(1)])
        c = nil; XCTAssertNil(owner); XCTAssertFalse(a.postbox.pending.first?.active == true); a.postbox.flush(); XCTAssertEqual(a.postbox.storage.writes,0)
    }
    func testOwnerReleaseCancelsPendingCacheWrite() {
        let a = Account(); var c: Context? = Context(a,folder: nil); seed(c!); c?.begin(); a.postbox.hold = true; a.stateManager.send([added(1)]); a.postbox.pending.first?.run()
        c = nil; a.postbox.flush(); XCTAssertEqual(a.postbox.storage.writes,0)
    }
    func testMembershipChangeCancelsPendingPageAndTransfersCompletion() {
        let c = Context(); seed(c,partial: true); c.begin(); var completed = 0
        c.loadMore(completion: { completed += 1 }); let old = c.account.network.requests.first
        c.account.stateManager.send([.deleted(peerId: 10,id: 1)])
        XCTAssertTrue(old?.cancelled == true); XCTAssertEqual(completed,0); XCTAssertEqual(c.account.network.requests.last?.offset,0)
        old?.succeed(page([1,9])); c.account.network.requests.last?.succeed(page([2,3])); XCTAssertEqual(ids(c),[2,3]); XCTAssertEqual(completed,1)
    }
    func testRepeatedSubscribeDoesNotDuplicateWork() {
        let c = Context(folder: nil); seed(c); c.begin(); c.begin(); c.account.stateManager.send([added(1)])
        XCTAssertEqual(c.account.postbox.storage.writes,1)
    }
    func testSameBatchAddDeleteRemovesStoryAndCount() {
        let c = Context(folder: nil); seed(c,ids: []); c.begin(); c.account.stateManager.send([added(1),.deleted(peerId: 10,id: 1)])
        XCTAssertTrue(ids(c).isEmpty); XCTAssertEqual(c.stateValue.totalCount,0)
    }
    func testReentrantQueuedEventRetainsItsPendingRead() {
        let c = Context(folder: nil); seed(c); c.begin(); c.account.postbox.delayAt = [3]
        var reentered = false
        c.onState = { [weak c] _ in
            if !reentered { reentered = true; c?.account.stateManager.send([self.added(1,text: "second")]) }
        }
        c.account.stateManager.send([added(1,text: "first")])
        XCTAssertTrue(c.account.postbox.pending.first?.active == true)
        c.account.postbox.flush()
        XCTAssertEqual(c.stateValue.items.first(where: { $0.storyItem.id == 1 })?.storyItem.text,"second")
    }
    func testPlaceholderUpdateDoesNotEraseFullStory() {
        let c = Context(); seed(c); c.begin(); c.account.stateManager.send([.added(peerId: 10,item: .placeholder(1))])
        XCTAssertEqual(ids(c),[3,1,2]); XCTAssertEqual(c.account.postbox.storage.writes,0)
    }
}

extension StoryLiveUpdatesTests {
    func views(_ n:Int = 50) -> Stories.Item.Views { .init(seenCount:n,reactedCount:n+1,forwardCount:n+2,seenPeerIds:[10],reactions:[4],hasList:true) }
    func viewUpdate(_ n:Int = 50, peer:Int = 10, id:Int32 = 1) -> InternalStoryUpdate { .updateViews(peerId:peer,views:[id:views(n)]) }
    func testViewsReachProfileArchiveAndAlbumWithoutInsertionOrReload() {
        for (folder,archived):(Int64?,Bool) in [(nil,false),(nil,true),(7,false)] {
            let c=Context(folder:folder,archived:archived); seed(c); c.begin(); c.account.stateManager.send([viewUpdate()])
            XCTAssertEqual(ids(c),[3,1,2]); XCTAssertEqual(c.stateValue.items[1].storyItem.views?.seenCount,50); XCTAssertEqual(c.stateValue.items[1].storyItem.views?.reactedCount,51); XCTAssertEqual(c.stateValue.items[1].storyItem.views?.forwardCount,52)
            XCTAssertEqual(c.stateValue.items[1].storyItem.views?.seenPeers.map(\.id),[10]); XCTAssertEqual(c.stateValue.items[1].storyItem.views?.reactions,[4]); XCTAssertEqual(c.stateValue.items[1].storyItem.views?.hasList,true)
            XCTAssertEqual(c.stateValue.totalCount,3); XCTAssertTrue(c.account.network.requests.isEmpty); XCTAssertEqual(c.account.postbox.storage.writes,0)
        }
    }
    func testViewsPreserveCurrentVisibleStoryMetadata() {
        let c=Context(); seed(c); var story=c.stateValue.items[1].storyItem
        story.text="edited"; story.folderIds=[7,8]; story.myReaction=9; story.isPinned=false; story.isEdited=true; story.media=EngineMedia(42); story.alternativeMediaList=[EngineMedia(43)]
        c.stateValue.items[1] = .init(id:.init(peerId:10,id:1),storyItem:story,peer:EnginePeer(.init(id:99)))
        c.stateValue.pinnedIds=[3]; c.begin(); c.account.stateManager.send([viewUpdate()])
        let item=c.stateValue.items[1]; XCTAssertEqual(item.storyItem.text,"edited"); XCTAssertEqual(item.storyItem.folderIds,[7,8]); XCTAssertEqual(item.storyItem.myReaction,9); XCTAssertFalse(item.storyItem.isPinned); XCTAssertTrue(item.storyItem.isEdited)
        XCTAssertEqual(item.storyItem.media,EngineMedia(42)); XCTAssertEqual(item.storyItem.alternativeMediaList,[EngineMedia(43)]); XCTAssertEqual(item.peer?.id,99); XCTAssertEqual(c.stateValue.pinnedIds,[3]); XCTAssertEqual(c.stateValue.unrelatedMetadata,7)
    }
    func testMissingStoryIsNotCreatedByViewsEvent() {
        let c=Context(); seed(c); c.begin(); c.account.stateManager.send([viewUpdate(id:99)]); XCTAssertEqual(ids(c),[3,1,2]); XCTAssertEqual(c.account.postbox.storage.writes,0); XCTAssertTrue(c.account.network.requests.isEmpty)
    }
    func testUnrelatedPeerDoesNotStartLookupOrRefresh() {
        let c=Context(); seed(c); c.begin(); c.account.stateManager.send([viewUpdate(peer:20)]); XCTAssertEqual(c.account.postbox.subscriptions,0); XCTAssertNil(c.stateValue.items[1].storyItem.views)
    }
    func testRepeatedIdenticalViewsDoNotPublishStateAgain() {
        let c=Context(); seed(c); c.begin(); var emissions=0; c.onState={ _ in emissions+=1 }
        c.account.stateManager.send([viewUpdate()]); c.account.stateManager.send([viewUpdate()]); XCTAssertEqual(emissions,1)
    }
    func testCountsCanDecreaseAndHasListCanClear() {
        let c=Context(); seed(c); c.begin(); c.account.stateManager.send([viewUpdate()]); c.account.stateManager.send([.updateViews(peerId:10,views:[1:.init()])])
        let result=c.stateValue.items[1].storyItem.views; XCTAssertEqual(result?.seenCount,0); XCTAssertEqual(result?.reactedCount,0); XCTAssertEqual(result?.forwardCount,0); XCTAssertEqual(result?.seenPeers.count,0); XCTAssertEqual(result?.reactions,[]); XCTAssertEqual(result?.hasList,false)
    }
    func testViewsDoNotSerializeOlderVisibleStoryIntoCache() {
        let c=Context(); seed(c); c.begin(); let key=ValueBoxKey(length:17); key.setInt64(0,value:10); key.setInt8(8,value:0); key.setInt64(9,value:7)
        let id=ItemCacheEntryId(collectionId:1,key:key)
        c.account.postbox.storage.cache[id]=CodableEntry(CachedPeerStoryListHead(items:[.item(.init(id:1,text:"newer cached payload",views:views(200)))],pinnedIds:[],totalCount:200,folders:[]))
        c.account.stateManager.send([viewUpdate()]); XCTAssertEqual(c.account.postbox.storage.writes,0)
        if case let .item(item)=c.account.postbox.storage.cache[id]?.get(CachedPeerStoryListHead.self)?.items.first { XCTAssertEqual(item.text,"newer cached payload"); XCTAssertEqual(item.views?.seenCount,200) } else { XCTFail() }
    }
    func testDelayedLookupUsesCurrentVisibleCaptionAndMembership() {
        let c=Context(); seed(c); c.begin(); c.account.postbox.hold=true; c.account.stateManager.send([viewUpdate()])
        var story=c.stateValue.items[1].storyItem; story.text="edited during lookup"; story.folderIds=[8]
        c.stateValue.items[1] = .init(id:.init(peerId:10,id:1),storyItem:story)
        c.account.postbox.hold=false; c.account.postbox.flush(); XCTAssertEqual(c.stateValue.items[1].storyItem.text,"edited during lookup"); XCTAssertEqual(c.stateValue.items[1].storyItem.folderIds,[8]); XCTAssertEqual(c.stateValue.items[1].storyItem.views?.seenCount,50)
    }
    func testDelayedViewsCannotResurrectRemovedVisibleStory() {
        let c=Context(); seed(c); c.begin(); c.account.postbox.hold=true; c.account.stateManager.send([viewUpdate()]); c.stateValue.items.remove(at:1)
        c.account.postbox.hold=false; c.account.postbox.flush(); XCTAssertEqual(ids(c),[3,2])
    }
    func testQueuedViewsAreAppliedInDeliveryOrder() {
        let c=Context(); seed(c); c.begin(); c.account.postbox.hold=true; c.account.stateManager.send([viewUpdate(50)]); c.account.stateManager.send([viewUpdate(20)])
        c.account.postbox.hold=false; c.account.postbox.flush(); XCTAssertEqual(c.stateValue.items[1].storyItem.views?.seenCount,20)
    }
    func testViewsCancelOlderPageAndMigrateCompletion() {
        let c=Context(); seed(c,partial:true); c.begin(); var completed=0; c.loadMore(completion:{completed+=1})
        let old=c.account.network.requests[0]; c.account.stateManager.send([viewUpdate()]); XCTAssertTrue(old.cancelled); XCTAssertEqual(c.stateValue.items[1].storyItem.views?.seenCount,50); XCTAssertEqual(completed,0)
        old.succeed(page([1])); XCTAssertEqual(ids(c),[3,1,2])
        XCTAssertEqual(c.account.network.requests.last?.offset,0); c.account.network.requests.last?.fail(); XCTAssertEqual(completed,1); XCTAssertEqual(c.stateValue.items[1].storyItem.views?.seenCount,50)
    }
    func testPendingViewsLookupDoesNotRetainContext() {
        let a=Account(); a.postbox.hold=true; var c:Context?=Context(a); seed(c!); c!.begin(); a.stateManager.send([viewUpdate()]); weak var weakContext=c; c=nil
        XCTAssertNil(weakContext); a.postbox.hold=false; a.postbox.flush(); XCTAssertEqual(a.postbox.storage.writes,0)
    }
    func testMismatchedVisibleIdentityIsIgnored() {
        let c=Context(); seed(c); c.stateValue.items[1] = .init(id:.init(peerId:10,id:1),storyItem:.init(id:2)); c.begin(); c.account.stateManager.send([viewUpdate()]); XCTAssertNil(c.stateValue.items[1].storyItem.views)
    }
    func testMixedViewsAndMembershipKeepBothChanges() {
        let c=Context(folder:nil); seed(c); var story=c.stateValue.items[1].storyItem; story.folderIds=[8]; c.stateValue.items[1] = .init(id:.init(peerId:10,id:1),storyItem:story)
        c.begin(); c.account.stateManager.send([viewUpdate(),.updateAlbumMembership(peerId:10,albumId:7,added:[1],removed:[])])
        let updated=c.stateValue.items.first(where:{$0.id.id==1})!.storyItem; XCTAssertEqual(updated.views?.seenCount,50); XCTAssertEqual(updated.folderIds,[8,7])
    }
}

extension StoryLiveUpdatesTests {
    func testPartialReactionUpdatesProfileArchiveAndAlbumWithoutReordering() {
        for (folder,archived):(Int64?,Bool) in [(nil,false),(nil,true),(7,false)] {
            let c=Context(folder:folder,archived:archived); seed(c); c.begin()
            c.account.stateManager.send([.updateMyReaction(peerId:10,id:1,reaction:2)])
            XCTAssertEqual(c.stateValue.items[1].storyItem.myReaction,2); XCTAssertEqual(ids(c),[3,1,2]); XCTAssertEqual(c.stateValue.totalCount,3); XCTAssertTrue(c.account.network.requests.isEmpty); XCTAssertEqual(c.account.postbox.storage.writes,0)
        }
    }
    func testPartialReactionAndRollbackUseActualCounterReducer() {
        let c=Context(peer:100)
        let initial=EngineStoryItem.Views(seenCount:20,reactedCount:2,forwardCount:4,seenPeers:[],reactions:[.init(value:1,count:2,chosenOrder:nil)],hasList:true)
        c.stateValue.items=[.init(id:.init(peerId:100,id:1),storyItem:.init(id:1,views:initial))]; c.stateValue.totalCount=1; c.stateValue.loadMoreToken=nil; c.begin()
        c.account.stateManager.send([.updateMyReaction(peerId:100,id:1,reaction:2)])
        XCTAssertEqual(c.stateValue.items[0].storyItem.views?.reactedCount,3); XCTAssertEqual(c.stateValue.items[0].storyItem.myReaction,2)
        c.account.stateManager.send([.updateMyReaction(peerId:100,id:1,reaction:nil)])
        XCTAssertEqual(c.stateValue.items[0].storyItem.views,initial); XCTAssertNil(c.stateValue.items[0].storyItem.myReaction)
    }
    func testRepeatedReactionEventDoesNotCountTwice() {
        let c=Context(peer:100); c.stateValue.items=[.init(id:.init(peerId:100,id:1),storyItem:.init(id:1))]; c.stateValue.loadMoreToken=nil; c.begin()
        c.account.stateManager.send([.updateMyReaction(peerId:100,id:1,reaction:2),.updateMyReaction(peerId:100,id:1,reaction:2)])
        XCTAssertEqual(c.stateValue.items[0].storyItem.views?.reactedCount,1); XCTAssertEqual(c.stateValue.items[0].storyItem.views?.reactions.first?.count,1)
    }
    func testPartialReactionPreservesNewerCaptionMediaAndMembership() {
        let c=Context(); seed(c); c.begin(); c.account.postbox.hold=true
        c.account.stateManager.send([.updateMyReaction(peerId:10,id:1,reaction:2)])
        var item=c.stateValue.items[1].storyItem; item.text="newer caption"; item.media=EngineMedia(999); item.folderIds=[8]; item.isExpired=true; item.isEdited=false
        c.stateValue.items[1] = .init(id:.init(peerId:10,id:1),storyItem:item,peer:EnginePeer(.init(id:99)))
        c.account.postbox.hold=false; c.account.postbox.flush()
        let result=c.stateValue.items[1]; XCTAssertEqual(result.storyItem.myReaction,2); XCTAssertEqual(result.storyItem.text,"newer caption"); XCTAssertEqual(result.storyItem.media,EngineMedia(999)); XCTAssertEqual(result.storyItem.folderIds,[8]); XCTAssertTrue(result.storyItem.isExpired); XCTAssertFalse(result.storyItem.isEdited); XCTAssertEqual(result.peer?.id,99)
    }
    func testPartialReactionCannotInsertDeletedOrMissingStory() {
        let c=Context(); seed(c); c.begin(); c.account.postbox.hold=true
        c.account.stateManager.send([.updateMyReaction(peerId:10,id:1,reaction:2)]); c.stateValue.items.remove(at:1)
        c.account.postbox.hold=false; c.account.postbox.flush(); XCTAssertEqual(ids(c),[3,2]); XCTAssertEqual(c.account.postbox.storage.writes,0)
    }
    func testPartialReactionForAnotherPeerIsIgnored() {
        let c=Context(); seed(c); c.begin(); c.account.stateManager.send([.updateMyReaction(peerId:100,id:1,reaction:2)])
        XCTAssertNil(c.stateValue.items[1].storyItem.myReaction); XCTAssertEqual(c.account.postbox.subscriptions,0)
    }
}

final class SearchDeletionContext {
    typealias State = StoryListContextState
    var stateValue = State()
    var publications = 0
    func consume(_ updates: [InternalStoryUpdate]) {
        var finalUpdatedState: State?
        for update in updates {
            switch update {
__SEARCH_DELETE__
            default: break
            }
        }
        if let finalUpdatedState { stateValue = finalUpdatedState; publications += 1 }
    }
}
extension StoryLiveUpdatesTests {
    func search(_ ids: [Int32] = [1,2,3], partial: Bool = false) -> SearchDeletionContext {
        let c = SearchDeletionContext()
        c.stateValue.items = ids.map { .init(id: .init(peerId: 10, id: $0), storyItem: .init(id: $0)) }
        c.stateValue.totalCount = partial ? 100 : ids.count
        c.stateValue.loadMoreToken = partial ? AnyHashable("next") : nil
        return c
    }
    func testSearchDeletionRemovesLoadedStoryAndAdjustsCount() {
        let c = search(); c.consume([.deleted(peerId: 10, id: 2)])
        XCTAssertEqual(c.stateValue.items.map { $0.id.id }, [1,3]); XCTAssertEqual(c.stateValue.totalCount, 2); XCTAssertEqual(c.publications, 1)
    }
    func testSearchDeletionPreservesOtherPeerWithSameStoryId() {
        let c = search([1]); c.stateValue.items.append(.init(id: .init(peerId: 20, id: 1), storyItem: .init(id: 1))); c.stateValue.totalCount = 2
        c.consume([.deleted(peerId: 10, id: 1)])
        XCTAssertEqual(c.stateValue.items.map { $0.id.peerId }, [20]); XCTAssertEqual(c.stateValue.totalCount, 1)
    }
    func testSearchDeletionBatchUsesAccumulatedStateAndIgnoresRepeats() {
        let c = search(); c.consume([.deleted(peerId: 10, id: 1), .deleted(peerId: 10, id: 1), .deleted(peerId: 10, id: 3)])
        XCTAssertEqual(c.stateValue.items.map { $0.id.id }, [2]); XCTAssertEqual(c.stateValue.totalCount, 1); XCTAssertEqual(c.publications, 1)
    }
    func testSearchUnknownDeletionDoesNotGuessCountOrPublish() {
        let c = search(partial: true); c.consume([.deleted(peerId: 10, id: 99)])
        XCTAssertEqual(c.stateValue.totalCount, 100); XCTAssertEqual(c.publications, 0)
    }
    func testSearchPartialDeletionPreservesPaginationAndUnloadedCount() {
        let c = search(partial: true); c.consume([.deleted(peerId: 10, id: 1)])
        XCTAssertEqual(c.stateValue.totalCount, 99); XCTAssertEqual(c.stateValue.loadMoreToken?.base as? String, "next")
    }
    func testSearchDeletionClampsMalformedCountWithoutOverflow() {
        let c = search(); c.stateValue.totalCount = Int.min; c.consume([.deleted(peerId: 10, id: 1)])
        XCTAssertEqual(c.stateValue.totalCount, 2)
    }
    func testSearchDeletionRemovesDuplicateRowsButDecrementsUniqueStoryOnce() {
        let c = search([1,1,2]); c.stateValue.totalCount = 10; c.consume([.deleted(peerId: 10, id: 1)])
        XCTAssertEqual(c.stateValue.items.map { $0.id.id }, [2]); XCTAssertEqual(c.stateValue.totalCount, 9)
    }
    func testSearchDeletionReleasesUnusedEmojiFilesAndPreservesSharedOnes() {
        let c = search([1,2])
        var first = c.stateValue.items[0].storyItem; first.entities = [.init(type: .CustomEmoji(0, 11)), .init(type: .CustomEmoji(0, 12))]
        var second = c.stateValue.items[1].storyItem; second.entities = [.init(type: .CustomEmoji(0, 12))]
        c.stateValue.items[0] = .init(id: .init(peerId: 10, id: 1), storyItem: first)
        c.stateValue.items[1] = .init(id: .init(peerId: 10, id: 2), storyItem: second)
        c.stateValue.allEntityFiles = [11.fileId: 11, 12.fileId: 12]
        c.consume([.deleted(peerId: 10, id: 1)])
        XCTAssertEqual(c.stateValue.allEntityFiles, [12.fileId: 12])
    }
}
