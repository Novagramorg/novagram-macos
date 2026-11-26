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
final class TelegramMediaFile: Equatable {
    let fileId: MediaId
    let version: Int
    init(_ id: Int64, version: Int = 1) { fileId = .init(namespace: 1,id: id); self.version = version }
    static func ==(lhs: TelegramMediaFile, rhs: TelegramMediaFile) -> Bool { lhs.fileId == rhs.fileId && lhs.version == rhs.version }
}
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
    var media: [MediaId: Any] = [:]
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

final class StoryEntityFilesTests: XCTestCase {
    func id(_ value: Int64) -> MediaId { .init(namespace: 1, id: value) }
    func item(_ story: Int32, emoji: [Int64] = [], reactions: [Int64] = [], folders: [Int64]? = [7], pinned: Bool = true) -> Stories.Item {
        .init(id: story, timestamp: Int(story), mediaAreas: reactions.map { .reaction(0, .custom($0), 0) }, entities: emoji.map { .init(type: .CustomEmoji(0, $0)) }, isPinned: pinned, folderIds: folders)
    }
    func key(_ album: Int64? = 7) -> ItemCacheEntryId {
        let key = ValueBoxKey(length: album == nil ? 9 : 17)
        key.setInt64(0, value: 10); key.setInt8(8, value: 0)
        if let album { key.setInt64(9, value: album) }
        return .init(collectionId: 1, key: key)
    }
    func seed(_ a: Account, _ items: [Stories.Item], album: Int64? = 7) {
        a.postbox.storage.cache[key(album)] = CodableEntry(CachedPeerStoryListHead(items: items.map(Stories.StoredItem.item), pinnedIds: [], totalCount: Int32(items.count), folders: []))
    }
    func files(_ a: Account, _ ids: [Int64]) {
        for value in ids { a.postbox.storage.media[id(value)] = TelegramMediaFile(value) }
    }
    func page(_ items: [Stories.Item], count: Int32? = nil) -> Api.stories.Stories {
        .stories(.init(count: count ?? Int32(items.count), stories: items.map(Api.StoryItem.item), pinnedToTop: nil))
    }
    func respond(_ a: Account, _ items: [Stories.Item], count: Int32? = nil) {
        guard let request = a.network.requests.last(where: { $0.kind != "folders" && !$0.cancelled }) else { return XCTFail("No active story request") }
        request.succeed(page(items, count: count))
        for request in a.network.requests where request.kind == "folders" && !request.cancelled { request.succeed(Api.stories.Albums.albumsNotModified) }
    }
    func expect(_ c: Context, _ expected: Set<Int64>, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(Set(c.stateValue.allEntityFiles.keys.map(\.id)), expected, file: file, line: line)
    }
    func update(_ a: Account, _ value: Stories.Item) { a.stateManager.send([.added(peerId: 10, item: .item(value))]) }
    func testNetworkPageLoadsEmojiAndReactionFiles() {
        let a = Account(); files(a, [11, 22]); let c = Context(a)
        respond(a, [item(1, emoji: [11], reactions: [22])]); expect(c, [11, 22])
        XCTAssertEqual(a.network.requests.count, 1)
    }
    func testCacheLoadsEmojiAndReactionFiles() {
        let a = Account(); files(a, [11, 22]); seed(a, [item(1, emoji: [11], reactions: [22])])
        let c = Context(a); expect(c, [11, 22])
    }
    func testDuplicateCacheEntriesDiscardSupersededReferences() {
        let a = Account(); files(a, [11, 22]); seed(a, [item(1, emoji: [11]), item(1, reactions: [22])])
        let c = Context(a); expect(c, [22]); XCTAssertEqual(c.stateValue.items.count, 1)
    }
    func testDuplicatePageEntriesUseFinalReferences() {
        let a = Account(); files(a, [11, 22]); let c = Context(a)
        respond(a, [item(1, emoji: [11]), item(1, reactions: [22])]); expect(c, [22])
    }
    func testSecondPageKeepsFirstPageResources() {
        let a = Account(); files(a, [11, 22]); let c = Context(a)
        respond(a, (1...100).map { item(Int32($0), emoji: [11]) }, count: 101)
        c.loadMore(completion: nil); respond(a, [item(101, reactions: [22])]); expect(c, [11, 22])
        XCTAssertEqual(c.stateValue.items.count, 101); XCTAssertEqual(a.network.requests.count, 2)
    }
    func testPageReplacementRemovesOnlyObsoleteReferences() {
        let a = Account(); files(a, [11, 22, 33]); let c = Context(a)
        respond(a, (1...100).map { item(Int32($0), emoji: $0 == 1 ? [11] : [33]) }, count: 101)
        c.loadMore(completion: nil); respond(a, [item(1, reactions: [22]), item(101)]); expect(c, [22, 33])
    }
    func testRefreshReplacesCachedResourceSet() {
        let a = Account(); files(a, [11, 22]); seed(a, [item(1, emoji: [11])]); let c = Context(a)
        respond(a, [item(2, emoji: [22])]); expect(c, [22])
    }
    func testEmptyRefreshReleasesCachedResources() {
        let a = Account(); files(a, [11]); seed(a, [item(1, emoji: [11])]); let c = Context(a)
        respond(a, []); expect(c, [])
    }
    func testFailurePreservesVisibleCachedResources() {
        let a = Account(); files(a, [11]); seed(a, [item(1, emoji: [11])]); let c = Context(a)
        a.network.requests.first?.fail(); expect(c, [11]); XCTAssertEqual(c.stateValue.items.count, 1)
    }
    func testMissingAndWrongTypeFilesAreIgnored() {
        let a = Account(); files(a, [11]); a.postbox.storage.media[id(22)] = "wrong type"
        let c = Context(a); respond(a, [item(1, emoji: [11, 22, 33])]); expect(c, [11])
    }
    func testMismatchedFileIdentityIsIgnoredInCacheAndNetwork() {
        let a = Account(); a.postbox.storage.media[id(11)] = TelegramMediaFile(99); seed(a, [item(1, emoji: [11])])
        let c = Context(a); expect(c, []); respond(a, [item(1, emoji: [11])]); expect(c, [])
    }
    func testRepeatedReferencesProduceOneFile() {
        let a = Account(); files(a, [11]); let c = Context(a)
        respond(a, [item(1, emoji: [11, 11], reactions: [11]), item(2, emoji: [11])]); expect(c, [11])
    }
    func testLiveEditReplacesCaptionAndReactionReferences() {
        let a = Account(); files(a, [11, 22, 33]); seed(a, [item(1, emoji: [11], reactions: [22])]); let c = Context(a)
        a.network.requests.first?.fail(); update(a, item(1, emoji: [33])); expect(c, [33])
    }
    func testLiveEditRefreshesSameFileDescriptor() {
        let a = Account(); files(a, [11]); seed(a, [item(1, emoji: [11])]); let c = Context(a)
        a.network.requests.first?.fail(); a.postbox.storage.media[id(11)] = TelegramMediaFile(11, version: 2)
        update(a, item(1, emoji: [11])); XCTAssertEqual(c.stateValue.allEntityFiles[id(11)]?.version, 2)
    }
    func testNetworkRefreshReplacesSameFileDescriptor() {
        let a = Account(); files(a, [11]); seed(a, [item(1, emoji: [11])]); let c = Context(a)
        a.postbox.storage.media[id(11)] = TelegramMediaFile(11, version: 2)
        respond(a, [item(1, emoji: [11])]); XCTAssertEqual(c.stateValue.allEntityFiles[id(11)]?.version, 2)
    }
    func testDeletionKeepsSharedReferencesUntilLastUse() {
        let a = Account(); files(a, [11, 22]); seed(a, [item(1, emoji: [11, 22]), item(2, emoji: [11])]); let c = Context(a)
        a.stateManager.send([.deleted(peerId: 10, id: 1)]); expect(c, [11])
        a.stateManager.send([.deleted(peerId: 10, id: 2)]); expect(c, [])
    }
    func testMembershipRemovalPrunesBeforeRefresh() {
        let a = Account(); files(a, [11, 22]); seed(a, [item(1, emoji: [11]), item(2, reactions: [22])]); let c = Context(a)
        a.stateManager.send([.updateAlbumMembership(peerId: 10, albumId: 7, added: [], removed: [1])]); expect(c, [22])
        a.network.requests.last?.fail(); expect(c, [22])
    }
    func testUnpinPrunesProfileReferences() {
        let a = Account(); files(a, [11]); seed(a, [item(1, emoji: [11])], album: nil); let c = Context(a, folder: nil)
        update(a, item(1, emoji: [11], pinned: false)); expect(c, [])
    }
    func testUnpinDoesNotPruneArchiveReferences() {
        let a = Account(); files(a, [11, 22]); let c = Context(a, folder: nil, archived: true)
        respond(a, [item(1, emoji: [11])]); update(a, item(1, emoji: [22], pinned: false)); expect(c, [22])
    }
    func testUnloadedAlbumAdditionDoesNotRetainUnusedFiles() {
        let a = Account(); files(a, [11, 22]); seed(a, [item(1, emoji: [11])]); let c = Context(a)
        update(a, item(2, emoji: [22])); expect(c, [11]); XCTAssertEqual(c.stateValue.items.count, 1)
    }
    func testOtherPeerEditDoesNotAffectResources() {
        let a = Account(); files(a, [11, 22]); seed(a, [item(1, emoji: [11])]); let c = Context(a)
        a.stateManager.send([.added(peerId: 20, item: .item(item(1, emoji: [22])))]); expect(c, [11])
    }
    func testCanceledPageCannotRestoreOldResources() {
        let a = Account(); files(a, [11, 22]); seed(a, [item(1, emoji: [11])]); let c = Context(a)
        let old = a.network.requests.first; update(a, item(1, emoji: [22]))
        old?.succeed(page([item(1, emoji: [11])]))
        XCTAssertTrue(old?.cancelled == true); expect(c, [22])
    }
    func testBatchedEditThenDeleteDoesNotRetainNewFiles() {
        let a = Account(); files(a, [11, 22]); seed(a, [item(1, emoji: [11])]); let c = Context(a)
        a.stateManager.send([.added(peerId: 10, item: .item(item(1, emoji: [22]))), .deleted(peerId: 10, id: 1)]); expect(c, [])
    }
    func testRemovedLastReferenceReleasesFile() {
        let a = Account(); files(a, [11]); seed(a, [item(1, emoji: [11])]); let c = Context(a)
        a.network.requests.first?.fail(); weak var file = a.postbox.storage.media[id(11)] as? TelegramMediaFile
        a.postbox.storage.media.removeAll(); XCTAssertNotNil(file)
        a.stateManager.send([.deleted(peerId: 10, id: 1)]); expect(c, []); XCTAssertNil(file)
    }
    func testOwnerReleaseReleasesFilesAndSubscription() {
        let a = Account(); files(a, [11]); seed(a, [item(1, emoji: [11])]); var c: Context? = Context(a)
        weak var file = a.postbox.storage.media[id(11)] as? TelegramMediaFile; weak var owner = c
        a.postbox.storage.media.removeAll(); c = nil; XCTAssertNil(owner); XCTAssertNil(file); XCTAssertEqual(a.stateManager.subscribers, 0)
    }
}
