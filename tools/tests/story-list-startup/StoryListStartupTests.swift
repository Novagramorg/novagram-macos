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
__MEMBERSHIP_HELPERS__
final class Context {
    typealias State = StoryListContextState
    let account: Account
    let peerId: Int
    let isArchived: Bool
    let folderId: Int64?
    let queue: Queue
    let statePromise = Promise<State>()
    var stateValue: State { didSet { statePromise.set(.single(stateValue)); onState?(stateValue) } }
    var onState: ((State) -> Void)?
    var completionCallbacksByToken: [AnyHashable: [() -> Void]] = [:]
    var subscriptions = 0
    __PROPERTIES__
    convenience init(_ account: Account = Account(), folder: Int64? = 7, archived: Bool = false) { self.init(queue: .mainQueue(),account: account,peerId: 10,isArchived: archived,folderId: folder) }
    __INITIALIZER__
    func begin() { subscribeToStoryUpdates() }
    __LOAD__
    __FINISH__
    __UPDATE_LIFECYCLE__
    __SUBSCRIBE__
    __RELOAD__
    __DEINIT__
}

final class StoryListStartupTests: XCTestCase {
    func key(_ album: Int64? = 7, archived: Bool = false) -> ItemCacheEntryId {
        let key = ValueBoxKey(length: album == nil ? 9 : 17); key.setInt64(0,value: 10); key.setInt8(8,value: archived ? 1 : 0)
        if let album { key.setInt64(9,value: album) }; return .init(collectionId: 1,key: key)
    }
    func seed(_ account: Account, album: Int64? = 7, archived: Bool = false, ids: [Int32] = [3,1,2], main: Bool = true) {
        let items = ids.map { Stories.StoredItem.item(.init(id: $0,timestamp: Int($0),folderIds: album.map { [$0] })) }
        let head = CachedPeerStoryListHead(items: items,pinnedIds: [],totalCount: 200,folders: [.init(id: 7,title: "album")])
        account.postbox.storage.cache[key(album,archived: archived)] = CodableEntry(head)
        if main && album != nil { account.postbox.storage.cache[key(nil,archived: archived)] = CodableEntry(head) }
    }
    func added(_ id: Int32, text: String = "updated", folders: [Int64]? = [7]) -> InternalStoryUpdate {
        .added(peerId: 10,item: .item(.init(id: id,timestamp: Int(id),text: text,folderIds: folders)))
    }
    func page(_ ids: [Int32], text: String = "server", count: Int32? = nil) -> Api.stories.Stories {
        .stories(.init(count: count ?? Int32(ids.count),stories: ids.map { .item(.init(id: $0,timestamp: Int($0),text: text,folderIds: [7])) },pinnedToTop: nil))
    }
    func ids(_ c: Context) -> [Int32] { c.stateValue.items.map { $0.id.id } }
    func albumRequests(_ a: Account) -> [Request] { a.network.requests.filter { $0.kind == "album" } }
    func testCacheReadIsCanceledWhenOwnerReleases() {
        let a = Account(); seed(a); a.postbox.delayAt = [1]
        var c: Context? = Context(a); weak var owner = c; let pending = a.postbox.pending.first
        XCTAssertTrue(pending?.active == true); c = nil
        XCTAssertNil(owner); XCTAssertFalse(pending?.active == true); a.postbox.flush(); XCTAssertTrue(a.network.requests.isEmpty)
    }
    func testCacheDeliveryIsCanceledAfterSnapshotAlreadyRead() {
        let a = Account(); seed(a); a.postbox.delayDeliveryAt = [1]
        var c: Context? = Context(a); weak var owner = c; c = nil; XCTAssertNil(owner)
        XCTAssertFalse(a.postbox.pending.first?.active == true); a.postbox.flush(); XCTAssertTrue(a.network.requests.isEmpty)
    }
    func testInitialStateIsPublishedWhileCacheLoads() {
        let a = Account(); a.postbox.delayAt = [1]; let c = Context(a); var values: [StoryListContextState] = []
        let d = c.statePromise.get().start(next: { values.append($0) })
        XCTAssertEqual(values.count,1); XCTAssertTrue(values.first?.isLoading == true); d.dispose()
    }
    func testExternalLoadWaitsForCacheAndCompletesOnce() {
        let a = Account(); seed(a); a.postbox.delayAt = [1]; let c = Context(a); var completions = 0
        c.loadMore { completions += 1 }; c.loadMore { completions += 1 }
        XCTAssertTrue(a.network.requests.isEmpty); XCTAssertEqual(a.postbox.subscriptions,1)
        a.postbox.flush(); XCTAssertEqual(albumRequests(a).count,1); XCTAssertEqual(completions,0)
        albumRequests(a).last?.succeed(page([1,2,3])); XCTAssertEqual(completions,2)
    }
    func testAlbumCacheWorksWithoutMainProfileHead() {
        let a = Account(); seed(a,main: false); let c = Context(a)
        XCTAssertEqual(ids(c),[3,1,2]); XCTAssertTrue(c.stateValue.hasCache); XCTAssertEqual(c.stateValue.totalCount,200); XCTAssertEqual(c.stateValue.peerReference?.id,10)
    }
    func testMissingAlbumHeadKeepsMainFolderMetadataAndPeer() {
        let a = Account(); seed(a); a.postbox.storage.cache.removeValue(forKey: key()); let c = Context(a)
        XCTAssertTrue(ids(c).isEmpty); XCTAssertFalse(c.stateValue.hasCache); XCTAssertEqual(c.stateValue.availableFolders.first?.id,7); XCTAssertEqual(c.stateValue.peerReference?.id,10)
    }
    func testColdCacheStillPublishesKnownPeer() {
        let a = Account(); let c = Context(a); XCTAssertEqual(c.stateValue.peerReference?.id,10); XCTAssertFalse(c.stateValue.hasCache)
    }
    func testCacheDuplicatesKeepCurrentPayloadWithoutDuplicateRows() {
        let a = Account(); seed(a)
        a.postbox.storage.cache[key()] = CodableEntry(CachedPeerStoryListHead(items: [.item(.init(id: 1,text: "old")),.placeholder(9),.item(.init(id: 1,text: "new")),.item(.init(id: 2))],pinnedIds: [],totalCount: 1,folders: []))
        let c = Context(a); XCTAssertEqual(ids(c),[1,2]); XCTAssertEqual(c.stateValue.items.first?.storyItem.text,"new"); XCTAssertEqual(c.stateValue.totalCount,2)
    }
    func testProfileCacheRetainsPinOrdering() {
        let a = Account(); seed(a,album: nil)
        a.postbox.storage.cache[key(nil)] = CodableEntry(CachedPeerStoryListHead(items: [1,2,3].map { .item(.init(id: $0,timestamp: Int($0))) },pinnedIds: [1],totalCount: 3,folders: []))
        let c = Context(a,folder: nil); XCTAssertEqual(ids(c),[1,3,2]); XCTAssertEqual(c.stateValue.pinnedIds,[1])
    }
    func testCachedEmojiAndReactionFilesAreLoaded() {
        let a = Account(); seed(a)
        a.postbox.storage.media[.init(namespace: 1,id: 44)] = 44; a.postbox.storage.media[.init(namespace: 1,id: 55)] = 55
        let value = Stories.Item(id: 1,mediaAreas: [.reaction(0,.custom(55),0)],entities: [.init(type: .CustomEmoji(0,44))])
        a.postbox.storage.cache[key()] = CodableEntry(CachedPeerStoryListHead(items: [.item(value)],pinnedIds: [],totalCount: 1,folders: []))
        let c = Context(a); XCTAssertEqual(Set(c.stateValue.allEntityFiles.values),Set([44,55]))
    }
    func testUpdatesSubscribeBeforeCacheReadFinishes() {
        let a = Account(); seed(a); a.postbox.delayAt = [1]; let c = Context(a)
        XCTAssertEqual(a.stateManager.subscribers,1); a.stateManager.send([added(1)])
        XCTAssertEqual(a.postbox.subscriptions,1); XCTAssertTrue(a.network.requests.isEmpty)
        a.postbox.flush(); XCTAssertEqual(c.stateValue.items.first(where: { $0.id.id == 1 })?.storyItem.text,"updated"); XCTAssertEqual(albumRequests(a).count,1)
    }
    func testDeletionBeforeCacheDeliveryDoesNotResurrectStory() {
        let a = Account(); seed(a); a.postbox.delayDeliveryAt = [1]; let c = Context(a)
        a.stateManager.send([.deleted(peerId: 10,id: 1)]); a.postbox.flush()
        XCTAssertEqual(ids(c),[3,2]); XCTAssertEqual(c.stateValue.totalCount,199); XCTAssertEqual(albumRequests(a).count,1)
        albumRequests(a).last?.fail(); XCTAssertEqual(ids(c),[3,2])
    }
    func testBufferedEventsApplyInArrivalOrder() {
        let a = Account(); seed(a); a.postbox.delayAt = [1]; let c = Context(a)
        a.stateManager.send([added(1,text: "first")]); a.stateManager.send([added(1,text: "second")]); a.stateManager.send([.deleted(peerId: 10,id: 2)])
        a.postbox.flush(); XCTAssertEqual(ids(c),[3,1]); XCTAssertEqual(c.stateValue.items.last?.storyItem.text,"second"); XCTAssertEqual(albumRequests(a).count,1)
    }
    func testInitialPageCannotOverwriteNewerMetadata() {
        let a = Account(); seed(a); let c = Context(a); let old = albumRequests(a).first
        a.stateManager.send([added(1)]); XCTAssertTrue(old?.cancelled == true)
        old?.succeed(page([1],text: "stale")); XCTAssertEqual(c.stateValue.items.first(where: { $0.id.id == 1 })?.storyItem.text,"updated")
        XCTAssertEqual(albumRequests(a).count,2); albumRequests(a).last?.succeed(page([3,1,2],text: "fresh"))
        XCTAssertEqual(c.stateValue.items.first(where: { $0.id.id == 1 })?.storyItem.text,"fresh")
    }
    func testInitialPageCannotResurrectDeletedStory() {
        let a = Account(); seed(a); let c = Context(a); let old = albumRequests(a).first
        a.stateManager.send([.deleted(peerId: 10,id: 1)]); old?.succeed(page([1,2,3]))
        XCTAssertTrue(old?.cancelled == true); XCTAssertEqual(ids(c),[3,2]); albumRequests(a).last?.fail(); XCTAssertEqual(ids(c),[3,2])
    }
    func testProfileInitialPageCanceledByNewMembership() {
        let a = Account(); seed(a,album: nil); let c = Context(a,folder: nil)
        let old = a.network.requests.first(where: { $0.kind == "profile" })
        a.stateManager.send([.updateAlbumMembership(peerId: 10,albumId: 7,added: [],removed: [1])])
        XCTAssertTrue(old?.cancelled == true); XCTAssertEqual(a.network.requests.filter { $0.kind == "profile" }.count,2)
        XCTAssertTrue(c.stateValue.isLoading)
    }
    func testAlbumOrderDuringFirstPageRestartsAtZero() {
        let a = Account(); seed(a); let c = Context(a); let old = albumRequests(a).first
        a.stateManager.send([.updateAlbumOrder(peerId: 10,albumId: 7)])
        XCTAssertTrue(old?.cancelled == true); XCTAssertEqual(albumRequests(a).count,2); XCTAssertEqual(albumRequests(a).last?.offset,0); XCTAssertTrue(c.stateValue.isLoading)
    }
    func testUpdateDuringDelayedPageCommitCancelsObsoleteWrite() {
        let a = Account(); seed(a); let c = Context(a); let old = albumRequests(a).first
        a.postbox.delayAt.insert(a.postbox.subscriptions+1); old?.succeed(page([1],text: "stale"))
        let commit = a.postbox.pending.last; a.stateManager.send([added(1)])
        XCTAssertFalse(commit?.active == true); a.postbox.flush()
        XCTAssertEqual(c.stateValue.items.first(where: { $0.id.id == 1 })?.storyItem.text,"updated")
        let head = a.postbox.storage.cache[key()]?.get(CachedPeerStoryListHead.self)
        if case let .item(value) = head?.items.first(where: { $0.id == 1 }) { XCTAssertEqual(value.text,"updated") } else { XCTFail("Missing current cached story") }
    }
    func testManualLoadDuringUpdateCommitWaits() {
        let a = Account(); seed(a); let c = Context(a); albumRequests(a).first?.succeed(page(Array(1...100).map(Int32.init),count: 200))
        a.postbox.hold = true; a.stateManager.send([added(1)]); var completions = 0; let before = albumRequests(a).count
        c.loadMore { completions += 1 }; XCTAssertEqual(albumRequests(a).count,before)
        a.postbox.hold = false; a.postbox.flush(); XCTAssertEqual(albumRequests(a).count,before+1)
        albumRequests(a).last?.succeed(page([101])); XCTAssertEqual(completions,1)
    }
    func testCanceledFirstPageCallbacksMoveToReplacement() {
        let a = Account(); seed(a); let c = Context(a); var completions = 0; c.loadMore { completions += 1 }
        let old = albumRequests(a).first; a.stateManager.send([added(1)]); old?.succeed(page([1]))
        XCTAssertEqual(completions,0); albumRequests(a).last?.succeed(page([1,2,3])); XCTAssertEqual(completions,1)
    }
    func testSynchronousBufferedUpdateDoesNotAutoLoadSecondPage() {
        let a = Account(); seed(a); a.postbox.delayAt = [1]; let c = Context(a)
        a.stateManager.send([added(1)])
        a.network.onRequest = { request in if request.kind == "album" { request.succeed(self.page(Array(1...100).map(Int32.init),count: 200)) } }
        a.postbox.flush(); XCTAssertEqual(albumRequests(a).count,1); XCTAssertEqual(c.stateValue.loadMoreToken,AnyHashable(100))
    }
    func testOwnerReleaseCancelsBufferedUpdatesAndStartup() {
        let a = Account(); seed(a); a.postbox.delayAt = [1]; var c: Context? = Context(a); weak var owner = c
        a.stateManager.send([added(1)]); c = nil; XCTAssertNil(owner); XCTAssertEqual(a.stateManager.subscribers,0)
        a.postbox.flush(); XCTAssertTrue(a.network.requests.isEmpty); XCTAssertEqual(a.postbox.storage.writes,0)
    }
    func testUnrelatedEventsDoNotRestartFirstPage() {
        let a = Account(); seed(a); let c = Context(a); let first = albumRequests(a).first
        a.stateManager.send([.deleted(peerId: 20,id: 1),.read(peerId: 10,maxId: 3)])
        XCTAssertFalse(first?.cancelled ?? true); XCTAssertEqual(albumRequests(a).count,1); XCTAssertEqual(ids(c),[3,1,2])
    }
    func testOtherAlbumOrderDoesNotRestartFirstPage() {
        let a = Account(); seed(a); let c = Context(a); let first = albumRequests(a).first
        a.stateManager.send([.updateAlbumOrder(peerId: 10,albumId: 8)])
        XCTAssertFalse(first?.cancelled ?? true); XCTAssertEqual(albumRequests(a).count,1); XCTAssertEqual(ids(c),[3,1,2])
    }
    func testProfilePinsDoNotRestartArchiveFirstPage() {
        let a = Account(); seed(a,album: nil,archived: true); let c = Context(a,folder: nil,archived: true)
        let first = a.network.requests.first
        a.stateManager.send([.updatePinnedToTopList(peerId: 10,ids: [1])])
        XCTAssertFalse(first?.cancelled ?? true); XCTAssertEqual(a.network.requests.count,1); XCTAssertEqual(ids(c),[3,2,1])
    }
    func testReentrantPaginationFromCachePublicationStartsOneRequest() {
        let a = Account(); seed(a); a.postbox.delayAt = [1]; let c = Context(a)
        var requested = false; c.onState = { [weak c] state in if state.hasCache && !requested { requested = true; c?.loadMore(completion: nil) } }
        a.postbox.flush(); XCTAssertEqual(albumRequests(a).count,1)
    }
}
