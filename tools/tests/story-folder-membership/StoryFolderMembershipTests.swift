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
    __ADD__
    __REMOVE__
}

final class StoryFolderMembershipTests: XCTestCase {
    func key(_ album: Int64? = 7) -> ItemCacheEntryId { let key = ValueBoxKey(length: album == nil ? 9 : 17); key.setInt64(0,value: 10); key.setInt8(8,value: 0); if let album { key.setInt64(9,value: album) }; return .init(collectionId: 1,key: key) }
    func seed(_ c: Context) {
        c.stateValue.items = [3,1,2].map { .init(id: .init(peerId: 10,id: $0),storyItem: .init(id: $0,folderIds: [7])) }; c.stateValue.totalCount = 200; c.stateValue.loadMoreToken = AnyHashable(100); c.stateValue.hasCache = true
        for album: Int64? in [nil,7,8] { c.account.postbox.storage.cache[key(album)] = CodableEntry(CachedPeerStoryListHead(items: [.item(.init(id: 3)),.placeholder(1),.item(.init(id: 2))],pinnedIds: [3],totalCount: 200,folders: [])) }
    }
    func response(_ id: Int32 = 7) -> Api.StoryAlbum { .storyAlbum(.init(albumId: id,title: "album")) }
    func mutation(_ c: Context) -> Request? { c.account.network.requests.last(where: { $0.kind == "mutation" }) }
    func page(_ ids: [Int32], count: Int32? = nil) -> Api.stories.Stories { .stories(.init(count: count ?? Int32(ids.count),stories: ids.map { .item(.init(id: $0)) },pinnedToTop: nil)) }
    func stored(_ id: Int32, folders: [Int64]? = [7,8], text: String = "new content") -> Stories.Item {
        .init(id: id,text: text,folderIds: folders)
    }
    func cachedItem(_ account: Account, album: Int64? = nil, id: Int32) -> Stories.Item? {
        let head = account.postbox.storage.cache[key(album)]?.get(CachedPeerStoryListHead.self)
        guard case let .item(value) = head?.items.first(where: { $0.id == id }) else { return nil }
        return value
    }
    func testAcceptedRemovalUpdatesProfileAndArchiveCachesWithoutLosingMetadata() {
        let c = Context(); seed(c)
        let head = CachedPeerStoryListHead(items: [.item(stored(2)),.placeholder(1)],pinnedIds: [2],totalCount: 200,folders: [.init(id: 8,title: "current title")])
        c.account.postbox.storage.cache[key(nil)] = CodableEntry(head)
        let archiveKey = key(nil); archiveKey.key.setInt8(8,value: 1); c.account.postbox.storage.cache[archiveKey] = CodableEntry(head)
        let d = c.removeFromFolder(id: 7,itemIds: [2]); mutation(c)?.succeed(response())
        for key in [key(nil),archiveKey] {
            let current = c.account.postbox.storage.cache[key]?.get(CachedPeerStoryListHead.self)
            guard case let .item(item) = current?.items.first else { return XCTFail("Missing story") }
            XCTAssertEqual(item.folderIds,[8]); XCTAssertEqual(item.text,"new content")
            XCTAssertEqual(current?.pinnedIds,[2]); XCTAssertEqual(current?.totalCount,200); XCTAssertEqual(current?.folders,head.folders)
            XCTAssertEqual(current?.items.count,2)
        }
        d.dispose()
    }
    func testCommitPatchesCurrentStoryRowsAndLeavesTombstonesAndMissingRowsAlone() {
        let c = Context(); let storage = c.account.postbox.storage
        storage.stories[.init(peerId: 10,id: 2)] = CodableEntry(Stories.StoredItem.item(stored(2)))
        storage.stories[.init(peerId: 10,id: 3)] = CodableEntry(Stories.StoredItem.placeholder(3))
        storage.storyItems = [.init(value: CodableEntry(Stories.StoredItem.item(stored(2)))!,id: 2,expirationTimestamp: 100,isCloseFriends: false,isLiveStream: false)]
        let d = c.updateFolderStories(id: 7,added: [.init(id: 4)],removed: [2,3]); mutation(c)?.succeed(response())
        guard case let .item(value) = storage.stories[.init(peerId: 10,id: 2)]?.get(Stories.StoredItem.self),
              case let .item(row) = storage.storyItems.first?.value.get(Stories.StoredItem.self) else { return XCTFail("Missing stored values") }
        XCTAssertEqual(value.folderIds,[8]); XCTAssertEqual(row.folderIds,[8]); XCTAssertEqual(value.text,"new content")
        XCTAssertNil(storage.stories[.init(peerId: 10,id: 4)])
        guard case .placeholder = storage.stories[.init(peerId: 10,id: 3)]?.get(Stories.StoredItem.self) else { return XCTFail("Tombstone changed") }; d.dispose()
    }
    func testUnknownMembershipStaysUnknown() {
        let c = Context(folder: nil); c.stateValue.items = [.init(id: .init(peerId: 10,id: 2),storyItem: .init(id: 2,folderIds: nil))]
        c.account.postbox.storage.stories[.init(peerId: 10,id: 2)] = CodableEntry(Stories.StoredItem.item(stored(2,folders: nil)))
        let d = c.addToFolder(id: 7,items: [.init(id: 2)]); mutation(c)?.succeed(response())
        XCTAssertNil(c.stateValue.items.first?.storyItem.folderIds)
        guard case let .item(item) = c.account.postbox.storage.stories[.init(peerId: 10,id: 2)]?.get(Stories.StoredItem.self) else { return XCTFail("Missing story") }
        XCTAssertNil(item.folderIds); d.dispose()
    }
    func testAddedMembershipPreservesOtherAlbumsAndCurrentContent() {
        let c = Context(folder: nil); seed(c); var current = c.stateValue.items[0].storyItem
        current.folderIds = [8]; current.text = "edited during request"
        let d = c.addToFolder(id: 7,items: [.init(id: 3,text: "old reference")])
        c.stateValue.items[0] = .init(id: .init(peerId: 10,id: 3),storyItem: current)
        mutation(c)?.succeed(response()); XCTAssertEqual(c.stateValue.items[0].storyItem.folderIds,[8,7]); XCTAssertEqual(c.stateValue.items[0].storyItem.text,"edited during request"); d.dispose()
    }
    func testSharedEventReachesEveryOpenAlbumAndProfile() {
        let account = Account(); let origin = Context(account); seed(origin)
        let peerAlbum = Context(account); peerAlbum.stateValue = origin.stateValue; peerAlbum.begin()
        let profile = Context(account,folder: nil); profile.stateValue = origin.stateValue; profile.begin()
        let archive = Context(account,folder: nil,archived: true); archive.stateValue = origin.stateValue; archive.begin()
        let otherAlbum = Context(account,folder: 8); otherAlbum.stateValue = origin.stateValue; otherAlbum.begin()
        let d = origin.removeFromFolder(id: 7,itemIds: [2]); mutation(origin)?.succeed(response())
        XCTAssertFalse(origin.stateValue.items.contains(where: { $0.id.id == 2 })); XCTAssertFalse(peerAlbum.stateValue.items.contains(where: { $0.id.id == 2 }))
        for c in [profile,archive,otherAlbum] {
            XCTAssertEqual(c.stateValue.items.first(where: { $0.id.id == 2 })?.storyItem.folderIds,[])
            XCTAssertEqual(c.stateValue.items.count,3); XCTAssertEqual(c.stateValue.totalCount,200)
        }
        XCTAssertEqual(account.network.requests.filter { $0.kind == "album" }.count,2)
        XCTAssertEqual(account.stateManager.published.count,1); d.dispose()
    }
    func testNotificationWaitsForCommitAndFailurePublishesNothing() {
        let c = Context(); seed(c); let d = c.removeFromFolder(id: 7,itemIds: [2]); c.account.postbox.hold = true
        mutation(c)?.succeed(response()); XCTAssertTrue(c.account.stateManager.published.isEmpty)
        c.account.postbox.hold = false; c.account.postbox.flush(); XCTAssertEqual(c.account.stateManager.published.count,1); d.dispose()
        let failed = Context(); let f = failed.removeFromFolder(id: 7,itemIds: [2]); mutation(failed)?.fail()
        XCTAssertTrue(failed.account.stateManager.published.isEmpty); f.dispose()
    }
    func testCanceledCommitPublishesNothing() {
        let c = Context(); let d = c.removeFromFolder(id: 7,itemIds: [2]); c.account.postbox.hold = true
        mutation(c)?.succeed(response()); d.dispose(); c.account.postbox.flush(); XCTAssertTrue(c.account.stateManager.published.isEmpty)
    }
    func testEmptyChangePublishesNothing() {
        let c = Context(); let d = c.updateFolderStories(id: 7,added: [],removed: [])
        XCTAssertTrue(c.account.stateManager.published.isEmpty); d.dispose()
    }
    func testForeignPeerEventDoesNotTouchListOrCache() {
        let c = Context(); seed(c); c.begin()
        c.account.stateManager.send([.updateAlbumMembership(peerId: 20,albumId: 7,added: [],removed: [2])])
        XCTAssertEqual(c.stateValue.items.count,3); XCTAssertTrue(c.account.network.requests.isEmpty); XCTAssertEqual(c.account.postbox.storage.writes,0)
    }
    func testIndependentAlbumPageCanceledAfterMembershipAcceptedElsewhere() {
        let account = Account(); let origin = Context(account); seed(origin)
        let remote = Context(account); remote.stateValue = origin.stateValue; remote.begin(); var completions = 0
        remote.loadMore { completions += 1 }; let old = account.network.requests.last
        let d = origin.removeFromFolder(id: 7,itemIds: [2]); mutation(origin)?.succeed(response())
        XCTAssertTrue(old?.cancelled == true); old?.succeed(page([2])); XCTAssertFalse(remote.stateValue.items.contains(where: { $0.id.id == 2 }))
        for request in account.network.requests where request.kind == "album" && !request.cancelled { request.succeed(page([3,1])) }
        XCTAssertEqual(completions,1); d.dispose()
    }
    func testQueuedOppositeDeltasPreserveOtherAlbumMembership() {
        let c = Context(folder: nil); seed(c); c.begin()
        c.account.postbox.hold = true
        c.account.stateManager.send([.updateAlbumMembership(peerId: 10,albumId: 7,added: [],removed: [2])])
        c.account.stateManager.send([.updateAlbumMembership(peerId: 10,albumId: 8,added: [2],removed: [])])
        c.account.postbox.hold = false; c.account.postbox.flush()
        XCTAssertEqual(c.stateValue.items.first(where: { $0.id.id == 2 })?.storyItem.folderIds,[8]); XCTAssertTrue(c.account.network.requests.isEmpty)
    }
    func testReleasedObserverDoesNotReceiveQueuedDelta() {
        let account = Account(); var c: Context? = Context(account); seed(c!); c!.begin(); weak var weakContext = c
        account.postbox.hold = true; account.stateManager.send([.updateAlbumMembership(peerId: 10,albumId: 7,added: [],removed: [2])]); c = nil
        XCTAssertNil(weakContext); account.postbox.hold = false; account.postbox.flush(); XCTAssertTrue(account.network.requests.isEmpty)
    }
    func testOlderVisibleProfileDoesNotOverwriteNewerCachedContent() {
        let c = Context(folder: nil); seed(c)
        c.account.postbox.storage.cache[key(nil)] = CodableEntry(CachedPeerStoryListHead(items: [.item(stored(2,text: "newer cache")),.placeholder(90)],pinnedIds: [90],totalCount: 400,folders: [.init(id: 9,title: "newer folder")]))
        let d = c.removeFromFolder(id: 7,itemIds: [2]); mutation(c)?.succeed(response())
        let head = c.account.postbox.storage.cache[key(nil)]?.get(CachedPeerStoryListHead.self)
        XCTAssertEqual(cachedItem(c.account,id: 2)?.text,"newer cache"); XCTAssertEqual(cachedItem(c.account,id: 2)?.folderIds,[8])
        XCTAssertEqual(head?.pinnedIds,[90]); XCTAssertEqual(head?.totalCount,400); XCTAssertEqual(head?.items.map(\.id),[2,90]); XCTAssertEqual(head?.folders.first?.title,"newer folder"); d.dispose()
    }
    func testOtherAlbumCacheKeepsNewerPayloadAndCustomOrder() {
        let c = Context(folder: 8); seed(c); c.begin()
        c.account.postbox.storage.cache[key(8)] = CodableEntry(CachedPeerStoryListHead(items: [.placeholder(90),.item(stored(2,text: "newer cache"))],pinnedIds: [],totalCount: 400,folders: []))
        c.account.stateManager.send([.updateAlbumMembership(peerId: 10,albumId: 7,added: [],removed: [2])])
        let head = c.account.postbox.storage.cache[key(8)]?.get(CachedPeerStoryListHead.self)
        XCTAssertEqual(cachedItem(c.account,album: 8,id: 2)?.text,"newer cache"); XCTAssertEqual(cachedItem(c.account,album: 8,id: 2)?.folderIds,[8])
        XCTAssertEqual(head?.items.map(\.id),[90,2]); XCTAssertEqual(head?.totalCount,400); XCTAssertTrue(c.account.network.requests.isEmpty)
    }
    func testCombinedChangeIsOneRequestWithBothFlags() {
        let c = Context(); seed(c); let d = c.updateFolderStories(id: 7,added: [.init(id: 4)],removed: [2])
        XCTAssertEqual(c.account.network.requests.count,1); XCTAssertEqual(mutation(c)?.flags,6); XCTAssertEqual(mutation(c)?.added,[4]); XCTAssertEqual(mutation(c)?.removed,[2]); XCTAssertNil(mutation(c)?.order)
        XCTAssertEqual(c.stateValue.items.map { $0.storyItem.id },[3,1,2]); XCTAssertEqual(c.account.postbox.storage.writes,0); d.dispose()
    }
    func testErrorPreservesItemsCountAndCache() {
        let c = Context(); seed(c); var result: [Bool] = []; let d = c.updateFolderStories(id: 7,added: [.init(id: 4)],removed: [2],completion: { result.append($0) }); mutation(c)?.fail()
        XCTAssertEqual(result,[false]); XCTAssertEqual(c.stateValue.totalCount,200); XCTAssertEqual(c.stateValue.items.map { $0.storyItem.id },[3,1,2]); XCTAssertEqual(c.account.postbox.storage.writes,0); XCTAssertEqual(c.account.network.requests.count,1); d.dispose()
    }
    func testWrongAlbumResponseFailsWithoutChanges() {
        let c = Context(); seed(c); var result: [Bool] = []; let d = c.updateFolderStories(id: 7,added: [],removed: [2],completion: { result.append($0) }); mutation(c)?.succeed(response(8))
        XCTAssertEqual(result,[false]); XCTAssertEqual(c.account.postbox.storage.writes,0); XCTAssertEqual(c.stateValue.items.count,3); d.dispose()
    }
    func testEmptyResponseReportsFailure() {
        let c = Context(); seed(c); var result: [Bool] = []; let d = c.updateFolderStories(id: 7,added: [],removed: [2],completion: { result.append($0) }); mutation(c)?.empty()
        XCTAssertEqual(result,[false]); XCTAssertEqual(c.account.postbox.storage.writes,0); d.dispose()
    }
    func testDuplicateIdsNormalizeWithoutChangingOrder() {
        let c = Context(); let d = c.updateFolderStories(id: 7,added: [.init(id: 5),.init(id: 4),.init(id: 5)],removed: [2,1,2])
        XCTAssertEqual(mutation(c)?.added,[5,4]); XCTAssertEqual(mutation(c)?.removed,[2,1]); d.dispose()
    }
    func testOverlappingAddAndRemoveRejected() {
        let c = Context(); seed(c); var result: [Bool] = []; let d = c.updateFolderStories(id: 7,added: [.init(id: 2)],removed: [2],completion: { result.append($0) })
        XCTAssertEqual(result,[false]); XCTAssertTrue(c.account.network.requests.isEmpty); XCTAssertEqual(c.account.postbox.storage.writes,0); d.dispose()
    }
    func testInvalidAlbumIdsAreNotClamped() {
        for id: Int64 in [0,-1,Int64(Int32.max)+1] {
            let c = Context(); var result: [Bool] = []; let d = c.updateFolderStories(id: id,added: [],removed: [2],completion: { result.append($0) })
            XCTAssertEqual(result,[false]); XCTAssertTrue(c.account.network.requests.isEmpty); d.dispose()
        }
    }
    func testInvalidOrPendingStoryIdsRejected() {
        var pending = EngineStoryItem(id: 2); pending.isPending = true
        for item in [EngineStoryItem(id: 0),EngineStoryItem(id: -1),pending] {
            let c = Context(); var result: [Bool] = []; let d = c.updateFolderStories(id: 7,added: [item],removed: [],completion: { result.append($0) })
            XCTAssertEqual(result,[false]); XCTAssertTrue(c.account.network.requests.isEmpty); d.dispose()
        }
        let c = Context(); let d = c.updateFolderStories(id: 7,added: [],removed: [0]); XCTAssertTrue(c.account.network.requests.isEmpty); d.dispose()
    }
    func testEmptyChangeIsNoOp() {
        let c = Context(); seed(c); var result: [Bool] = []; let d = c.updateFolderStories(id: 7,added: [],removed: [],completion: { result.append($0) })
        XCTAssertEqual(result,[true]); XCTAssertTrue(c.account.network.requests.isEmpty); XCTAssertEqual(c.account.postbox.storage.writes,0); d.dispose()
    }
    func testPartialRemovalKeepsUnloadedCountAndReloadsFromZero() {
        let c = Context(); seed(c); var result: [Bool] = []; let d = c.removeFromFolder(id: 7,itemIds: [2],completion: { result.append($0) }); mutation(c)?.succeed(response())
        XCTAssertEqual(result,[true]); XCTAssertEqual(c.stateValue.items.map { $0.storyItem.id },[3,1]); XCTAssertEqual(c.stateValue.totalCount,199)
        XCTAssertEqual(c.account.network.requests.last?.kind,"album"); XCTAssertEqual(c.account.network.requests.last?.offset,0); XCTAssertNil(c.account.postbox.storage.cache[key()]); d.dispose()
    }
    func testAddedStoriesUseServerOrderAndCount() {
        let c = Context(); seed(c); let d = c.addToFolder(id: 7,items: [.init(id: 4)]); mutation(c)?.succeed(response())
        XCTAssertEqual(c.stateValue.items.map { $0.storyItem.id },[3,1,2]); XCTAssertEqual(c.stateValue.totalCount,200)
        c.account.network.requests.last?.succeed(page([1,4,3,2])); XCTAssertEqual(c.stateValue.items.map { $0.storyItem.id },[1,4,3,2]); XCTAssertEqual(c.stateValue.totalCount,4); XCTAssertFalse(c.stateValue.isLoading); d.dispose()
    }
    func testFailedRefreshDoesNotResurrectRemovedStoryOrOldCache() {
        let c = Context(); seed(c); let d = c.removeFromFolder(id: 7,itemIds: [2]); mutation(c)?.succeed(response()); c.account.network.requests.last?.fail()
        XCTAssertEqual(c.stateValue.items.map { $0.storyItem.id },[3,1]); XCTAssertEqual(c.stateValue.totalCount,199); XCTAssertNil(c.account.postbox.storage.cache[key()]); XCTAssertFalse(c.stateValue.isLoading); XCTAssertNotNil(c.stateValue.loadMoreToken); d.dispose()
    }
    func testUnknownRemovalDoesNotInventLoadedCount() {
        let c = Context(); seed(c); let d = c.removeFromFolder(id: 7,itemIds: [100]); mutation(c)?.succeed(response())
        XCTAssertEqual(c.stateValue.totalCount,200); c.account.network.requests.last?.succeed(page((101...200).map(Int32.init),count: 199)); XCTAssertEqual(c.stateValue.totalCount,199); d.dispose()
    }
    func testOnlyTargetAlbumCacheInvalidated() {
        let c = Context(); seed(c); let d = c.removeFromFolder(id: 7,itemIds: [2]); mutation(c)?.succeed(response())
        XCTAssertNil(c.account.postbox.storage.cache[key()]); XCTAssertNotNil(c.account.postbox.storage.cache[key(nil)]); XCTAssertNotNil(c.account.postbox.storage.cache[key(8)]); d.dispose()
    }
    func testOtherAlbumContextNotMutatedOrReloaded() {
        let c = Context(folder: 8); seed(c); let d = c.removeFromFolder(id: 7,itemIds: [2]); mutation(c)?.succeed(response())
        XCTAssertEqual(c.stateValue.totalCount,200); XCTAssertEqual(c.stateValue.items.count,3); XCTAssertEqual(c.account.network.requests.count,1); d.dispose()
    }
    func testMissingPeerFailsWithoutCacheChanges() {
        let c = Context(); seed(c); c.account.postbox.storage.peer = nil; var result: [Bool] = []; let d = c.removeFromFolder(id: 7,itemIds: [2],completion: { result.append($0) })
        XCTAssertEqual(result,[false]); XCTAssertTrue(c.account.network.requests.isEmpty); XCTAssertEqual(c.account.postbox.storage.writes,0); d.dispose()
    }
    func testCancellationDuringValidation() {
        let c = Context(); seed(c); c.account.postbox.hold = true; var result: [Bool] = []; let d = c.removeFromFolder(id: 7,itemIds: [2],completion: { result.append($0) }); d.dispose(); c.account.postbox.flush()
        XCTAssertTrue(result.isEmpty); XCTAssertTrue(c.account.network.requests.isEmpty); XCTAssertEqual(c.stateValue.items.count,3); XCTAssertEqual(c.account.postbox.storage.writes,0)
    }
    func testCancellationDuringRequest() {
        let c = Context(); seed(c); var result: [Bool] = []; let d = c.removeFromFolder(id: 7,itemIds: [2],completion: { result.append($0) }); d.dispose(); mutation(c)?.succeed(response())
        XCTAssertTrue(result.isEmpty); XCTAssertEqual(c.stateValue.items.count,3); XCTAssertEqual(c.account.postbox.storage.writes,0)
    }
    func testCancellationDuringCommit() {
        let c = Context(); seed(c); var result: [Bool] = []; let d = c.removeFromFolder(id: 7,itemIds: [2],completion: { result.append($0) }); c.account.postbox.hold = true; mutation(c)?.succeed(response()); d.dispose(); c.account.postbox.flush()
        XCTAssertTrue(result.isEmpty); XCTAssertEqual(c.stateValue.items.count,3); XCTAssertEqual(c.account.postbox.storage.writes,0)
    }
    func testReloadAndCompletionWaitForCommit() {
        let c = Context(); seed(c); var result: [Bool] = []; let d = c.removeFromFolder(id: 7,itemIds: [2],completion: { result.append($0) }); c.account.postbox.hold = true; mutation(c)?.succeed(response())
        XCTAssertTrue(result.isEmpty); XCTAssertEqual(c.account.network.requests.count,1); XCTAssertEqual(c.stateValue.items.count,3); c.account.postbox.hold = false; c.account.postbox.flush()
        XCTAssertEqual(result,[true]); XCTAssertEqual(c.account.network.requests.last?.kind,"album"); d.dispose()
    }
    func testOwnerReleaseDuringRequestAndCommit() {
        for commit in [false,true] {
            let account = Account(); var c: Context? = Context(account); seed(c!); weak var weakContext = c; var result: [Bool] = []; let d = c!.removeFromFolder(id: 7,itemIds: [2],completion: { result.append($0) })
            if commit { account.postbox.hold = true; mutation(c!)?.succeed(response()) }
            c = nil; XCTAssertNil(weakContext); account.postbox.flush(); XCTAssertTrue(result.isEmpty); d.dispose()
        }
    }
    func testAcceptedMutationCancelsOldPageAndTransfersCompletion() {
        let c = Context(); seed(c); var completions = 0; c.loadMore { completions += 1 }; let old = c.account.network.requests.first
        let d = c.removeFromFolder(id: 7,itemIds: [2]); mutation(c)?.succeed(response())
        XCTAssertTrue(old?.cancelled == true); XCTAssertEqual(completions,0); old?.succeed(page([2])); XCTAssertFalse(c.stateValue.items.contains(where: { $0.storyItem.id == 2 }))
        c.account.network.requests.last?.succeed(page([3,1])); XCTAssertEqual(completions,1); d.dispose()
    }
    func testReentrantDisposalDoesNotLeaveReloadStuck() {
        let c = Context(); seed(c); let owner = MetaDisposable(); var result: [Bool] = []
        owner.set(c.removeFromFolder(id: 7,itemIds: [2],completion: { result.append($0) })); c.onState = { _ in owner.dispose() }; mutation(c)?.succeed(response())
        XCTAssertTrue(result.isEmpty); c.account.network.requests.last?.succeed(page([3,1])); XCTAssertFalse(c.stateValue.isLoading); XCTAssertEqual(c.stateValue.items.map { $0.storyItem.id },[3,1])
    }
    func testSynchronousMutationResponseOwnsReload() {
        let c = Context(); seed(c); c.account.network.onRequest = { request in if request.kind == "mutation" { request.succeed(self.response()) } }; var result: [Bool] = []
        let d = c.addToFolder(id: 7,items: [.init(id: 4)],completion: { result.append($0) }); XCTAssertEqual(result,[true]); XCTAssertEqual(c.account.network.requests.last?.kind,"album"); XCTAssertFalse(c.account.network.requests.last?.cancelled ?? true)
        c.account.network.requests.last?.succeed(page([4,3,1,2])); XCTAssertEqual(c.stateValue.items.count,4); d.dispose()
    }
}
