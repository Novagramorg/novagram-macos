import Foundation
import XCTest
import SwiftSignalKit

enum Stories {
    enum ForwardInfo: Equatable { case known(Int, Int32, Bool) }
    struct Item: Equatable {
        struct Views: Equatable { var seenCount = 0; var reactedCount = 0; var forwardCount = 0; var seenPeerIds: [Int] = []; var reactions: [Int] = []; var hasList = false }
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

final class ValueBoxKey: Hashable {
    let length: Int; var fields: [Int: Int64] = [:]
    init(length: Int) { self.length = length }
    func setInt64(_ offset: Int, value: Int64) { fields[offset] = value }
    func setInt8(_ offset: Int, value: Int8) { fields[offset] = Int64(value) }
    static func ==(lhs: ValueBoxKey, rhs: ValueBoxKey) -> Bool { lhs.length == rhs.length && lhs.fields == rhs.fields }
    func hash(into hasher: inout Hasher) { hasher.combine(length); for k in fields.keys.sorted() { hasher.combine(k); hasher.combine(fields[k]) } }
}
struct ItemCacheEntryId: Hashable { let collectionId: Int; let key: ValueBoxKey }

struct StoryId: Hashable { let peerId: Int; let id: Int32 }
struct Folder: Equatable { let id: Int64; let title: String }
struct CachedPeerStoryListHead { let items: [Stories.StoredItem]; let pinnedIds: [Int32]; let totalCount: Int32; let folders: [Folder] }
enum InternalStoryUpdate { case updateViews(peerId: Int, views: [Int32: Stories.Item.Views]) }
final class StateManager {
    let storyViewRefreshContext = StoryViewRefreshContext()
    var updates: [InternalStoryUpdate] = []
    var onUpdate: (() -> Void)?
    func injectStoryUpdates(updates: [InternalStoryUpdate]) { self.updates += updates; onUpdate?() }
}

typealias PeerId = Int
extension Int { func toInt64() -> Int64 { Int64(self) }; var namespace: Int { self >= 100 ? 1 : 0 } }
enum EnginePeer { typealias Id = Int }
enum Namespaces { enum CachedItemCollection { static let cachedPeerStoryListHeads = 1 }; enum Peer { static let CloudChannel = 1 } }
struct Peer { let id: Int }
struct CodableEntry {
    let value: Any
    init?(_ value: Any) { self.value=value }
    func get<T>(_ type: T.Type) -> T? { value as? T }
}
extension Stories.StoredItem {
    var expirationTimestamp: Int { if case let .item(item)=self { return item.expirationTimestamp }; return 0 }
    var isCloseFriends: Bool { if case let .item(item)=self { return item.isCloseFriends }; return false }
    var isLiveStream: Bool { false }
}
extension Stories.Item.Views { init(apiViews: Stories.Item.Views) { self=apiViews } }
struct StoryItemsTableEntry {
    let value: CodableEntry
    let id: Int32
    let expirationTimestamp: Int
    let isCloseFriends: Bool
    let isLiveStream: Bool
}
final class Transaction {
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
    let storage=Transaction()
    var count=0
    var onCancel: (() -> Void)?
    var delayAt:Set<Int>=[]
    var pending:[Pending]=[]
    func transaction<T>(_ f: @escaping (Transaction)->T) -> Signal<T,NoError> {
        Signal { subscriber in
            self.count+=1
            let run={ subscriber.putNext(f(self.storage)); subscriber.putCompletion() }
            if self.delayAt.contains(self.count) {
                let pending=Pending(run); self.pending.append(pending)
                return ActionDisposable { pending.active=false; self.onCancel?() }
            }
            run(); return EmptyDisposable
        }
    }
    func flush() { for p in pending { p.deliver() } }
}
struct MTRpcError: Error {}
enum Api {
    struct InputPeer { let id: Int }
    enum StoryItem { case item(Stories.Item), placeholder(Int32), deleted }
    enum stories {
        struct Data { let views:[Stories.Item.Views]; var users:[Int]=[] }
        enum StoryViews { case storyViews(Data) }
    }
    enum functions { enum stories {
        static func getStoriesViews(peer:InputPeer,id:[Int32])->RequestData { .init(peerId:peer.id,ids:id) }
    } }
}
struct RequestData { let peerId:Int; let ids:[Int32] }
func apiInputPeer(_ peer:Peer)->Api.InputPeer? { peer.id>0 ? .init(id:peer.id) : nil }
struct AccumulatedPeers { let users:[Int] }
func updatePeers(transaction:Transaction,accountPeerId:Int,peers:AccumulatedPeers) { transaction.peerUpdates+=1 }
final class Request {
    let data:RequestData
    var subscriber:Subscriber<Api.stories.StoryViews,MTRpcError>?
    var canceled=false
    init(_ data:RequestData) { self.data=data }
    func succeed(_ views:[Stories.Item.Views]) { subscriber?.putNext(.storyViews(.init(views:views))); subscriber?.putCompletion() }
    func fail() { subscriber?.putError(.init()) }
    func empty() { subscriber?.putCompletion() }
}
final class Network {
    var requests:[Request]=[]
    var onRequest:((Request)->Void)?
    func request(_ data:RequestData)->Signal<Api.stories.StoryViews,MTRpcError> {
        Signal { subscriber in
            let request=Request(data); request.subscriber=subscriber; self.requests.append(request); self.onRequest?(request)
            return ActionDisposable { request.canceled=true; request.subscriber=nil }
        }
    }
}
__ORDERING_CONTEXT__
enum MessageReaction { typealias Reaction = Int }
__REACTION_CONTEXT__
struct StoryRefreshSnapshot {
    init(transaction: Transaction, peerId: Int, id: Int32) {}
}
final class StoryRefreshContext {
    func isPending(_ id: StoryId) -> Bool { false }
    func advance(peerId: Int, id: Int32, from: StoryRefreshSnapshot, to: StoryRefreshSnapshot, views: Stories.Item.Views? = nil) {}
}
final class Account { let storyRefreshContext = StoryRefreshContext(); let storyReactionContext = StoryReactionContext(); __ACCOUNT_ORDERING_PROPERTY__; let peerId=10; let stateManager = StateManager(); let postbox=Postbox(); let network=Network() }
__REQUEST__
__HELPERS__
final class Messages {
    let account:Account
    init(_ account:Account) { self.account=account }
    __METHOD__
}
final class StoryViewRefreshTests:XCTestCase {
    func views(_ n:Int=9)->Stories.Item.Views { .init(seenCount:n,reactedCount:n+1,forwardCount:n+2,seenPeerIds:[20],reactions:[3],hasList:true) }
    func row(_ value:Stories.StoredItem, id:Int32?=nil)->StoryItemsTableEntry { .init(value:CodableEntry(value)!,id:id ?? value.id,expirationTimestamp:value.expirationTimestamp,isCloseFriends:value.isCloseFriends,isLiveStream:value.isLiveStream) }
    func seed(_ a:Account,peer:Int=10) {
        a.postbox.storage.rows[peer]=[row(.item(.init(id:1,views:views()))),row(.item(.init(id:2,views:views(12))))]
    }
    func value(_ a:Account,_ id:Int32=1,peer:Int=10)->Stories.Item? {
        guard let row=a.postbox.storage.rows[peer]?.first(where:{$0.id==id}),case let .item(value)=row.value.get(Stories.StoredItem.self) else { return nil }; return value
    }
    func testColdSignalDoesNotRequestOrWrite() {
        let a=Account(); seed(a); _=Messages(a).refreshStoryViews(peerId:10,ids:[1]); XCTAssertTrue(a.network.requests.isEmpty); XCTAssertEqual(a.postbox.storage.writes,0)
    }
    func testNetworkFailurePreservesAllCounts() {
        let a=Account(); seed(a); var completed=0; let d=Messages(a).refreshStoryViews(peerId:10,ids:[1,2]).start(completed:{completed+=1})
        a.network.requests[0].fail(); XCTAssertEqual(value(a)?.views,views()); XCTAssertEqual(value(a,2)?.views,views(12)); XCTAssertEqual(a.postbox.storage.writes,0); XCTAssertEqual(completed,1); d.dispose()
    }
    func testEmptyResultDoesNotEraseCounts() {
        let a=Account(); seed(a); let d=Messages(a).refreshStoryViews(peerId:10,ids:[1]).start()
        a.network.requests[0].succeed([]); XCTAssertEqual(value(a)?.views,views()); XCTAssertEqual(a.postbox.storage.writes,0); d.dispose()
    }
    func testShortResponseDoesNotMisassociatePositionalCounts() {
        let a=Account(); seed(a); let d=Messages(a).refreshStoryViews(peerId:10,ids:[1,2]).start()
        a.network.requests[0].succeed([views(100)]); XCTAssertEqual(value(a)?.views,views()); XCTAssertEqual(value(a,2)?.views,views(12)); XCTAssertEqual(a.postbox.storage.writes,0); d.dispose()
    }
    func testLongResponseIsRejected() {
        let a=Account(); seed(a); let d=Messages(a).refreshStoryViews(peerId:10,ids:[1]).start()
        a.network.requests[0].succeed([views(100),views(200)]); XCTAssertEqual(value(a)?.views,views()); XCTAssertEqual(a.postbox.storage.writes,0); d.dispose()
    }
    func testMissingPeerPreservesCountsWithoutWrite() {
        let a=Account(); seed(a); a.postbox.storage.peers.removeValue(forKey:10)
        let d=Messages(a).refreshStoryViews(peerId:10,ids:[1]).start(); XCTAssertTrue(a.network.requests.isEmpty); XCTAssertEqual(value(a)?.views,views()); XCTAssertEqual(a.postbox.storage.writes,0); d.dispose()
    }
    func testEmptyNetworkCompletionDoesNotWrite() {
        let a=Account(); seed(a); var completed=0; let d=Messages(a).refreshStoryViews(peerId:10,ids:[1]).start(completed:{completed+=1})
        a.network.requests[0].empty(); XCTAssertEqual(completed,1); XCTAssertEqual(a.postbox.storage.writes,0); XCTAssertEqual(value(a)?.views,views()); d.dispose()
    }
    func testEmptyIdsDoNotRequest() {
        let a=Account(); seed(a); var completed=0; let d=Messages(a).refreshStoryViews(peerId:10,ids:[]).start(completed:{completed+=1})
        XCTAssertTrue(a.network.requests.isEmpty); XCTAssertEqual(completed,1); XCTAssertEqual(a.postbox.count,0); d.dispose()
    }
    func testInvalidIdsOnlyDoNotRequest() {
        let a=Account(); let d=Messages(a).refreshStoryViews(peerId:10,ids:[0,-1]).start(); XCTAssertTrue(a.network.requests.isEmpty); d.dispose()
    }
    func testDuplicatesAndInvalidIdsNormalizeInOrder() {
        let a=Account(); seed(a); let d=Messages(a).refreshStoryViews(peerId:10,ids:[2,0,1,2,-1]).start()
        XCTAssertEqual(a.network.requests[0].data.ids,[2,1]); a.network.requests[0].succeed([views(200),views(100)])
        XCTAssertEqual(value(a)?.views,views(100)); XCTAssertEqual(value(a,2)?.views,views(200)); d.dispose()
    }
    func testUnchangedResponseDoesNotWrite() {
        let a=Account(); seed(a); let d=Messages(a).refreshStoryViews(peerId:10,ids:[1,2]).start()
        a.network.requests[0].succeed([views(),views(12)]); XCTAssertEqual(a.postbox.storage.writes,0); d.dispose()
    }
    func testSuccessfulResponseWritesOnceAndPreservesUnrequestedStory() {
        let a=Account(); seed(a); let d=Messages(a).refreshStoryViews(peerId:10,ids:[1]).start()
        a.network.requests[0].succeed([views(100)]); XCTAssertEqual(value(a)?.views,views(100)); XCTAssertEqual(value(a,2)?.views,views(12)); XCTAssertEqual(a.postbox.storage.writes,1); d.dispose()
    }
    func testLegitimateZeroCountsAreApplied() {
        let a=Account(); seed(a); let d=Messages(a).refreshStoryViews(peerId:10,ids:[1]).start()
        let zero=Stories.Item.Views(); a.network.requests[0].succeed([zero]); XCTAssertEqual(value(a)?.views,zero); XCTAssertEqual(a.postbox.storage.writes,1); d.dispose()
    }
    func testPreviouslyUnknownCountsAreFilled() {
        let a=Account(); a.postbox.storage.rows[10]=[row(.item(.init(id:1)))]; let d=Messages(a).refreshStoryViews(peerId:10,ids:[1]).start()
        a.network.requests[0].succeed([views()]); XCTAssertEqual(value(a)?.views,views()); d.dispose()
    }
    func testLatestStoryFieldsSurviveDelayedResponse() {
        let a=Account(); seed(a); let d=Messages(a).refreshStoryViews(peerId:10,ids:[1]).start()
        var edited=Stories.Item(id:1,timestamp:40,expirationTimestamp:90,media:5,alternativeMediaList:[6],mediaAreas:[7],text:"new",entities:[8],views:views(20),privacy:4,isPinned:false,isExpired:true,isPublic:false,isCloseFriends:true,isContacts:true,isSelectedContacts:true,isForwardingDisabled:true,isEdited:true,isMy:false,myReaction:9,forwardInfo:.known(20,2,true),music:10,authorId:30,folderIds:[7,8])
        a.postbox.storage.rows[10]=[row(.item(edited))]; a.network.requests[0].succeed([views(100)]); edited.views=views(100)
        XCTAssertEqual(value(a),edited); d.dispose()
    }
    func testDeletedStoryIsNotRecreated() {
        let a=Account(); seed(a); let d=Messages(a).refreshStoryViews(peerId:10,ids:[1]).start(); a.postbox.storage.rows[10]=[]
        a.network.requests[0].succeed([views(100)]); XCTAssertTrue(a.postbox.storage.rows[10]!.isEmpty); XCTAssertEqual(a.postbox.storage.writes,0); d.dispose()
    }
    func testPlaceholderIsNotReplaced() {
        let a=Account(); a.postbox.storage.rows[10]=[row(.placeholder(1))]; let d=Messages(a).refreshStoryViews(peerId:10,ids:[1]).start()
        a.network.requests[0].succeed([views(100)]); XCTAssertNil(value(a)); XCTAssertEqual(a.postbox.storage.writes,0); d.dispose()
    }
    func testMismatchedStoredStoryIdentityIsNotUpdated() {
        let a=Account(); a.postbox.storage.rows[10]=[row(.item(.init(id:2,views:views())),id:1)]; let d=Messages(a).refreshStoryViews(peerId:10,ids:[1]).start()
        a.network.requests[0].succeed([views(100)]); XCTAssertEqual(value(a)?.id,2); XCTAssertEqual(value(a)?.views,views()); XCTAssertEqual(a.postbox.storage.writes,0); d.dispose()
    }
    func testOtherUserDoesNotRequest() {
        let a=Account(); seed(a,peer:20); let d=Messages(a).refreshStoryViews(peerId:20,ids:[1]).start(); XCTAssertTrue(a.network.requests.isEmpty); d.dispose()
    }
    func testChannelRequestUpdatesOnlyChannel() {
        let a=Account(); seed(a); seed(a,peer:100); let d=Messages(a).refreshStoryViews(peerId:100,ids:[1]).start()
        XCTAssertEqual(a.network.requests[0].data.peerId,100); a.network.requests[0].succeed([views(100)])
        XCTAssertEqual(value(a,peer:100)?.views,views(100)); XCTAssertEqual(value(a)?.views,views()); d.dispose()
    }
    func testCancellationDuringLookupPreventsRequest() {
        let a=Account(); seed(a); a.postbox.delayAt=[1]; let d=Messages(a).refreshStoryViews(peerId:10,ids:[1]).start(); d.dispose(); a.postbox.flush()
        XCTAssertTrue(a.network.requests.isEmpty); XCTAssertEqual(a.postbox.storage.writes,0)
    }
    func testCancellationDuringNetworkPreventsCommit() {
        let a=Account(); seed(a); let d=Messages(a).refreshStoryViews(peerId:10,ids:[1]).start(); d.dispose(); a.network.requests[0].succeed([views(100)])
        XCTAssertTrue(a.network.requests[0].canceled); XCTAssertEqual(a.postbox.storage.writes,0)
    }
    func testCancellationDuringResponseParsingPreventsCommit() {
        let a=Account(); seed(a); a.postbox.delayAt=[2]; let d=Messages(a).refreshStoryViews(peerId:10,ids:[1]).start()
        a.network.requests[0].succeed([views(100)]); d.dispose(); a.postbox.flush(); XCTAssertEqual(a.postbox.storage.writes,0); XCTAssertEqual(value(a)?.views,views())
    }
    func testCancellationDuringCommitPreventsWrite() {
        let a=Account(); seed(a); a.postbox.delayAt=[3]; let d=Messages(a).refreshStoryViews(peerId:10,ids:[1]).start()
        a.network.requests[0].succeed([views(100)]); d.dispose(); a.postbox.flush(); XCTAssertEqual(a.postbox.storage.writes,0); XCTAssertEqual(value(a)?.views,views())
    }
    func testRetryAfterFailureCanApplyNewCounts() {
        let a=Account(); seed(a); let messages=Messages(a); let d=messages.refreshStoryViews(peerId:10,ids:[1]).start(); a.network.requests[0].fail()
        let next=messages.refreshStoryViews(peerId:10,ids:[1]).start(); a.network.requests[1].succeed([views(100)])
        XCTAssertEqual(value(a)?.views,views(100)); XCTAssertEqual(a.postbox.storage.writes,1); d.dispose(); next.dispose()
    }
    func testSynchronousResponseCompletesExactlyOnce() {
        let a=Account(); seed(a); a.network.onRequest={ $0.succeed([self.views(100)]) }; var completed=0
        let d=Messages(a).refreshStoryViews(peerId:10,ids:[1]).start(completed:{completed+=1})
        XCTAssertEqual(completed,1); XCTAssertEqual(value(a)?.views,views(100)); XCTAssertTrue(a.network.requests[0].canceled); d.dispose()
    }
    func testCancellationReleasesRefreshOwner() {
        let a=Account(); seed(a); var messages:Messages?=Messages(a); weak var owner=messages
        let d=messages!.refreshStoryViews(peerId:10,ids:[1]).start(); messages=nil; d.dispose(); XCTAssertNil(owner)
    }
    func testCompletionReleasesRefreshOwner() {
        let a=Account(); seed(a); var messages:Messages?=Messages(a); weak var owner=messages
        let d=messages!.refreshStoryViews(peerId:10,ids:[1]).start(); messages=nil
        a.network.requests[0].succeed([views(100)]); XCTAssertNil(owner); d.dispose()
    }

}

extension StoryViewRefreshTests {
    func cacheId(_ archived: Int8 = 0, album: Int64? = nil, peer: Int = 10) -> ItemCacheEntryId {
        let key = ValueBoxKey(length: album == nil ? 9 : 17)
        key.setInt64(0,value: Int64(peer)); key.setInt8(8,value: archived)
        if let album { key.setInt64(9,value: album) }
        return .init(collectionId:1,key:key)
    }
    func cached(_ a:Account,_ key:ItemCacheEntryId) -> CachedPeerStoryListHead? { a.postbox.storage.cache[key]?.get(CachedPeerStoryListHead.self) }
    func stored(_ entry:CodableEntry?) -> Stories.Item? {
        if case let .item(item) = entry?.get(Stories.StoredItem.self) { return item }; return nil
    }
    func refresh(_ a:Account,_ value:Stories.Item.Views) {
        let d=Messages(a).refreshStoryViews(peerId:10,ids:[1]).start()
        a.network.requests.last?.succeed([value]); d.dispose()
    }
    func testIndividualExpiredStoryRefreshWithoutActiveRow() {
        let a=Account(); let id=StoryId(peerId:10,id:1)
        let item=Stories.Item(id:1,text:"current archived caption",views:views(),isExpired:true,folderIds:[7,8])
        a.postbox.storage.stories[id]=CodableEntry(Stories.StoredItem.item(item))
        refresh(a,views(50)); var expected=item; expected.views=views(50)
        XCTAssertEqual(stored(a.postbox.storage.stories[id]),expected); XCTAssertEqual(a.postbox.storage.storyWrites,1)
        XCTAssertTrue(a.postbox.storage.rows.isEmpty)
    }
    func testIndividualMissingPlaceholderAndMismatchedIdentityArePreserved() {
        for stored:Stories.StoredItem? in [nil,.placeholder(1),.item(.init(id:2,views:views()))] {
            let a=Account(); let id=StoryId(peerId:10,id:1)
            if let stored { a.postbox.storage.stories[id]=CodableEntry(stored) }
            refresh(a,views(50)); XCTAssertEqual(a.postbox.storage.storyWrites,0)
            XCTAssertEqual(a.postbox.storage.stories[id]?.get(Stories.StoredItem.self)?.id,stored?.id)
        }
    }
    func testProfileAndArchiveHeadsPatchOnlyCounts() {
        let a=Account()
        for archived:Int8 in [0,1] {
            let items:[Stories.StoredItem]=[.item(.init(id:2,views:views(12))),.placeholder(5),.item(.init(id:1,text:"newer caption",views:views(),folderIds:[7]))]
            a.postbox.storage.cache[cacheId(archived)]=CodableEntry(CachedPeerStoryListHead(items:items,pinnedIds:[2],totalCount:200,folders:[.init(id:7,title:"newer title")]))
        }
        refresh(a,views(50))
        for archived:Int8 in [0,1] {
            let head=cached(a,cacheId(archived))!; XCTAssertEqual(head.items.map(\.id),[2,5,1]); XCTAssertEqual(head.pinnedIds,[2]); XCTAssertEqual(head.totalCount,200); XCTAssertEqual(head.folders,[.init(id:7,title:"newer title")])
            if case let .item(item)=head.items[2] { XCTAssertEqual(item.views,views(50)); XCTAssertEqual(item.text,"newer caption"); XCTAssertEqual(item.folderIds,[7]) } else { XCTFail() }
            if case let .item(item)=head.items[0] { XCTAssertEqual(item.views,views(12)) } else { XCTFail() }
        }
        XCTAssertEqual(a.postbox.storage.cacheWrites,2)
    }
    func testKnownAlbumsRefreshFromFolderDirectoryWithoutActiveStory() {
        let a=Account()
        a.postbox.storage.cache[cacheId()]=CodableEntry(CachedPeerStoryListHead(items:[],pinnedIds:[],totalCount:0,folders:[.init(id:7,title:"album")]))
        for archived:Int8 in [0,1] { a.postbox.storage.cache[cacheId(archived,album:7)]=CodableEntry(CachedPeerStoryListHead(items:[.item(.init(id:1,views:views()))],pinnedIds:[1],totalCount:1,folders:[])) }
        refresh(a,views(0))
        for archived:Int8 in [0,1] {
            if case let .item(item)=cached(a,cacheId(archived,album:7))?.items.first { XCTAssertEqual(item.views,views(0)) } else { XCTFail() }
        }
        XCTAssertEqual(a.postbox.storage.cacheWrites,2)
    }
    func testAlbumDiscoveryFromIndividualStoryAndLinkedCacheTerminates() {
        let a=Account(); a.postbox.storage.stories[.init(peerId:10,id:1)]=CodableEntry(Stories.StoredItem.item(.init(id:1,views:views(),folderIds:[7])))
        for album:Int64 in [7,8] { a.postbox.storage.cache[cacheId(album:album)]=CodableEntry(CachedPeerStoryListHead(items:[.item(.init(id:1,views:views(),folderIds:[7,8]))],pinnedIds:[],totalCount:1,folders:[])) }
        refresh(a,views(50)); XCTAssertEqual(a.postbox.storage.cacheWrites,2)
        for album:Int64 in [7,8] { if case let .item(item)=cached(a,cacheId(album:album))?.items.first { XCTAssertEqual(item.views,views(50)) } else { XCTFail() } }
    }
    func testRefreshDoesNotCreateCachesOrMissingStories() {
        let a=Account(); refresh(a,views(50)); XCTAssertTrue(a.postbox.storage.cache.isEmpty); XCTAssertTrue(a.postbox.storage.stories.isEmpty); XCTAssertTrue(a.postbox.storage.rows.isEmpty)
        XCTAssertEqual(a.stateManager.updates.count,1)
    }
    func testOtherPeerCacheAndIndividualValueStayUnchanged() {
        let a=Account(); let item=Stories.Item(id:1,views:views())
        a.postbox.storage.stories[.init(peerId:100,id:1)]=CodableEntry(Stories.StoredItem.item(item))
        a.postbox.storage.cache[cacheId(peer:100)]=CodableEntry(CachedPeerStoryListHead(items:[.item(item)],pinnedIds:[],totalCount:1,folders:[]))
        refresh(a,views(50)); XCTAssertEqual(a.postbox.storage.storyWrites,0); XCTAssertEqual(a.postbox.storage.cacheWrites,0)
    }
    func testUnchangedAllStoresDoNotWriteButNotifyVisibleLists() {
        let a=Account(); seed(a); let item=Stories.Item(id:1,views:views(),folderIds:[7])
        a.postbox.storage.stories[.init(peerId:10,id:1)]=CodableEntry(Stories.StoredItem.item(item))
        for album:Int64? in [nil,7] { a.postbox.storage.cache[cacheId(album:album)]=CodableEntry(CachedPeerStoryListHead(items:[.item(item)],pinnedIds:[],totalCount:1,folders:[])) }
        refresh(a,views()); XCTAssertEqual(a.postbox.storage.writes,0); XCTAssertEqual(a.postbox.storage.storyWrites,0); XCTAssertEqual(a.postbox.storage.cacheWrites,0); XCTAssertEqual(a.stateManager.updates.count,1)
    }
    func testNotificationFollowsCommittedValues() {
        let a=Account(); seed(a); var observed=0
        a.stateManager.onUpdate={ XCTAssertEqual(self.value(a)?.views,self.views(50)); observed+=1 }
        refresh(a,views(50)); XCTAssertEqual(observed,1)
        if case let .updateViews(peer,values)=a.stateManager.updates.first { XCTAssertEqual(peer,10); XCTAssertEqual(values,[1:views(50)]) } else { XCTFail() }
    }
    func testFailureMalformedAndMissingPeerDoNotPublishViews() {
        for kind in 0..<3 {
            let a=Account(); seed(a); if kind==2 { a.postbox.storage.peers.removeValue(forKey:10) }
            let d=Messages(a).refreshStoryViews(peerId:10,ids:[1]).start()
            if kind==0 { a.network.requests.first?.fail() } else { a.network.requests.first?.succeed([]) }
            XCTAssertTrue(a.stateManager.updates.isEmpty); d.dispose()
        }
    }
    func testCancelPendingCommitDoesNotWriteOrNotify() {
        let a=Account(); seed(a); a.postbox.delayAt=[3]
        let d=Messages(a).refreshStoryViews(peerId:10,ids:[1]).start(); a.network.requests[0].succeed([views(50)])
        d.dispose(); a.postbox.flush(); XCTAssertEqual(value(a)?.views,views()); XCTAssertTrue(a.stateManager.updates.isEmpty)
    }
    func testDelayedCommitPatchesLatestCacheContent() {
        let a=Account(); a.postbox.delayAt=[3]
        let d=Messages(a).refreshStoryViews(peerId:10,ids:[1]).start(); a.network.requests[0].succeed([views(50)])
        a.postbox.storage.cache[cacheId()]=CodableEntry(CachedPeerStoryListHead(items:[.item(.init(id:1,text:"edited while waiting",views:views(),folderIds:[8]))],pinnedIds:[1],totalCount:10,folders:[]))
        a.postbox.flush()
        if case let .item(item)=cached(a,cacheId())?.items.first { XCTAssertEqual(item.views,views(50)); XCTAssertEqual(item.text,"edited while waiting"); XCTAssertEqual(item.folderIds,[8]) } else { XCTFail() }
        d.dispose()
    }
}

extension StoryViewRefreshTests {
    func testNewerSuccessfulRefreshPreventsOlderCountRollback() {
        let a=Account(); seed(a)
        let first=Messages(a).refreshStoryViews(peerId:10,ids:[1]).start()
        let second=Messages(a).refreshStoryViews(peerId:10,ids:[1]).start()
        a.network.requests[1].succeed([views(100)]); a.network.requests[0].succeed([views(50)])
        XCTAssertEqual(value(a)?.views,views(100)); XCTAssertEqual(a.stateManager.updates.count,1); XCTAssertEqual(a.postbox.storage.writes,1)
        first.dispose(); second.dispose()
    }
    func testNewerLowerCountsAlsoPreventOlderHigherRollback() {
        let a=Account(); seed(a)
        let first=Messages(a).refreshStoryViews(peerId:10,ids:[1]).start(); let second=Messages(a).refreshStoryViews(peerId:10,ids:[1]).start()
        a.network.requests[1].succeed([views(0)]); a.network.requests[0].succeed([views(100)])
        XCTAssertEqual(value(a)?.views,views(0)); XCTAssertEqual(a.stateManager.updates.count,1); first.dispose(); second.dispose()
    }
    func testEarlierSuccessIsUsableUntilNewerSuccessArrives() {
        let a=Account(); seed(a)
        let first=Messages(a).refreshStoryViews(peerId:10,ids:[1]).start(); let second=Messages(a).refreshStoryViews(peerId:10,ids:[1]).start()
        a.network.requests[0].succeed([views(100)]); XCTAssertEqual(value(a)?.views,views(100))
        a.network.requests[1].succeed([views(0)]); XCTAssertEqual(value(a)?.views,views(0)); XCTAssertEqual(a.stateManager.updates.count,2); first.dispose(); second.dispose()
    }
    func testNewerFailureDoesNotDiscardOlderSuccessfulResult() {
        let a=Account(); seed(a)
        let first=Messages(a).refreshStoryViews(peerId:10,ids:[1]).start(); let second=Messages(a).refreshStoryViews(peerId:10,ids:[1]).start()
        a.network.requests[1].fail(); a.network.requests[0].succeed([views(50)])
        XCTAssertEqual(value(a)?.views,views(50)); XCTAssertEqual(a.stateManager.updates.count,1); first.dispose(); second.dispose()
    }
    func testNewerMalformedResponseDoesNotSupersedeOlder() {
        let a=Account(); seed(a)
        let first=Messages(a).refreshStoryViews(peerId:10,ids:[1]).start(); let second=Messages(a).refreshStoryViews(peerId:10,ids:[1]).start()
        a.network.requests[1].succeed([]); a.network.requests[0].succeed([views(50)])
        XCTAssertEqual(value(a)?.views,views(50)); first.dispose(); second.dispose()
    }
    func testCanceledNewerRequestDoesNotSupersedeOlder() {
        let a=Account(); seed(a)
        let first=Messages(a).refreshStoryViews(peerId:10,ids:[1]).start(); let second=Messages(a).refreshStoryViews(peerId:10,ids:[1]).start()
        second.dispose(); a.network.requests[0].succeed([views(50)])
        XCTAssertEqual(value(a)?.views,views(50)); XCTAssertEqual(a.stateManager.updates.count,1); first.dispose()
    }
    func testCanceledNewerQueuedCommitDoesNotSupersedeOlder() {
        let a=Account(); seed(a)
        let first=Messages(a).refreshStoryViews(peerId:10,ids:[1]).start(); let second=Messages(a).refreshStoryViews(peerId:10,ids:[1]).start()
        a.postbox.delayAt=[4]; a.network.requests[1].succeed([views(100)]); second.dispose()
        a.postbox.delayAt=[]; a.network.requests[0].succeed([views(50)]); a.postbox.flush()
        XCTAssertEqual(value(a)?.views,views(50)); XCTAssertEqual(a.stateManager.updates.count,1); first.dispose()
    }
    func testDelayedOlderCommitRechecksOrderingInsideTransaction() {
        let a=Account(); seed(a); a.postbox.delayAt=[3]
        let first=Messages(a).refreshStoryViews(peerId:10,ids:[1]).start(); a.network.requests[0].succeed([views(100)])
        let second=Messages(a).refreshStoryViews(peerId:10,ids:[1]).start(); a.network.requests[1].succeed([views(0)])
        a.postbox.flush(); XCTAssertEqual(value(a)?.views,views(0)); XCTAssertEqual(a.stateManager.updates.count,1); first.dispose(); second.dispose()
    }
    func testPartiallyOverlappingBatchesPreserveIndependentResults() {
        let a=Account(); seed(a)
        let first=Messages(a).refreshStoryViews(peerId:10,ids:[1,2]).start(); let second=Messages(a).refreshStoryViews(peerId:10,ids:[2]).start()
        a.network.requests[1].succeed([views(200)]); a.network.requests[0].succeed([views(50),views(100)])
        XCTAssertEqual(value(a)?.views,views(50)); XCTAssertEqual(value(a,2)?.views,views(200)); XCTAssertEqual(a.stateManager.updates.count,2)
        if case let .updateViews(_,accepted)=a.stateManager.updates.last { XCTAssertEqual(accepted,[1:views(50)]) } else { XCTFail() }
        first.dispose(); second.dispose()
    }
    func testDisjointStoryRequestsRemainIndependent() {
        let a=Account(); seed(a)
        let first=Messages(a).refreshStoryViews(peerId:10,ids:[1]).start(); let second=Messages(a).refreshStoryViews(peerId:10,ids:[2]).start()
        a.network.requests[1].succeed([views(200)]); a.network.requests[0].succeed([views(50)])
        XCTAssertEqual(value(a)?.views,views(50)); XCTAssertEqual(value(a,2)?.views,views(200)); first.dispose(); second.dispose()
    }
    func testEqualStoryIdsFromDifferentPeersRemainIndependent() {
        let a=Account(); seed(a); seed(a,peer:100)
        let first=Messages(a).refreshStoryViews(peerId:10,ids:[1]).start(); let second=Messages(a).refreshStoryViews(peerId:100,ids:[1]).start()
        a.network.requests[1].succeed([views(200)]); a.network.requests[0].succeed([views(50)])
        XCTAssertEqual(value(a)?.views,views(50)); XCTAssertEqual(value(a,peer:100)?.views,views(200)); first.dispose(); second.dispose()
    }
    func testEqualIdsFromDifferentAccountsRemainIndependent() {
        let a=Account(),b=Account(); seed(a); seed(b)
        let first=Messages(a).refreshStoryViews(peerId:10,ids:[1]).start(); let second=Messages(b).refreshStoryViews(peerId:10,ids:[1]).start()
        b.network.requests[0].succeed([views(200)]); a.network.requests[0].succeed([views(50)])
        XCTAssertEqual(value(a)?.views,views(50)); XCTAssertEqual(value(b)?.views,views(200)); first.dispose(); second.dispose()
    }
    func testColdSignalCreationDoesNotSupersedeSubscribedRefresh() {
        let a=Account(); seed(a)
        let first=Messages(a).refreshStoryViews(peerId:10,ids:[1]).start(); let unused=Messages(a).refreshStoryViews(peerId:10,ids:[1])
        a.network.requests[0].succeed([views(50)]); XCTAssertEqual(value(a)?.views,views(50)); withExtendedLifetime(unused) {}; first.dispose()
    }
    func testEachSubscriptionToSameSignalHasItsOwnOrdering() {
        let a=Account(); seed(a); let signal=Messages(a).refreshStoryViews(peerId:10,ids:[1])
        let first=signal.start(),second=signal.start()
        a.network.requests[1].succeed([views(200)]); a.network.requests[0].succeed([views(50)])
        XCTAssertEqual(value(a)?.views,views(200)); first.dispose(); second.dispose()
    }
    func testThirdRequestDoesNotAllowSupersededFirstToReappear() {
        let a=Account(); seed(a)
        let first=Messages(a).refreshStoryViews(peerId:10,ids:[1]).start(),second=Messages(a).refreshStoryViews(peerId:10,ids:[1]).start()
        a.network.requests[1].succeed([views(100)])
        let third=Messages(a).refreshStoryViews(peerId:10,ids:[1]).start(); a.network.requests[2].fail(); a.network.requests[0].succeed([views(50)])
        XCTAssertEqual(value(a)?.views,views(100)); XCTAssertEqual(a.stateManager.updates.count,1); first.dispose(); second.dispose(); third.dispose()
    }
    func testUnchangedNewerResponseStillSupersedesOlder() {
        let a=Account(); seed(a)
        let first=Messages(a).refreshStoryViews(peerId:10,ids:[1]).start(),second=Messages(a).refreshStoryViews(peerId:10,ids:[1]).start()
        a.network.requests[1].succeed([views()]); a.network.requests[0].succeed([views(50)])
        XCTAssertEqual(value(a)?.views,views()); XCTAssertEqual(a.postbox.storage.writes,0); XCTAssertEqual(a.stateManager.updates.count,1); first.dispose(); second.dispose()
    }
    func testOlderResponseCannotRollBackIndividualOrProfileCache() {
        let a=Account(); let item=Stories.Item(id:1,text:"current caption",views:views())
        a.postbox.storage.stories[.init(peerId:10,id:1)]=CodableEntry(Stories.StoredItem.item(item)); a.postbox.storage.cache[cacheId()]=CodableEntry(CachedPeerStoryListHead(items:[.item(item)],pinnedIds:[],totalCount:1,folders:[]))
        let first=Messages(a).refreshStoryViews(peerId:10,ids:[1]).start(),second=Messages(a).refreshStoryViews(peerId:10,ids:[1]).start()
        a.network.requests[1].succeed([views(100)]); a.network.requests[0].succeed([views(50)])
        XCTAssertEqual(stored(a.postbox.storage.stories[.init(peerId:10,id:1)])?.views,views(100))
        if case let .item(item)=cached(a,cacheId())?.items.first { XCTAssertEqual(item.views,views(100)); XCTAssertEqual(item.text,"current caption") } else { XCTFail() }
        XCTAssertEqual(a.postbox.storage.storyWrites,1); XCTAssertEqual(a.postbox.storage.cacheWrites,1); first.dispose(); second.dispose()
    }
    func testReentrantRefreshFromCommitNotificationSupersedesOldBatch() {
        let a=Account(); seed(a); var nested:Disposable?
        let first=Messages(a).refreshStoryViews(peerId:10,ids:[1,2]).start()
        a.stateManager.onUpdate={
            a.stateManager.onUpdate=nil
            nested=Messages(a).refreshStoryViews(peerId:10,ids:[1]).start(); a.network.requests.last?.succeed([self.views(200)])
        }
        let second=Messages(a).refreshStoryViews(peerId:10,ids:[2]).start(); a.network.requests[1].succeed([views(100)])
        a.network.requests[0].succeed([views(50),views(60)])
        XCTAssertEqual(value(a)?.views,views(200)); XCTAssertEqual(value(a,2)?.views,views(100)); XCTAssertEqual(a.stateManager.updates.count,2)
        first.dispose(); second.dispose(); nested?.dispose()
    }
}

extension StoryViewRefreshTests {
    func pendingCount(_ context:StoryViewRefreshContext) -> Int {
        let pending=Mirror(reflecting:context).children.first(where:{$0.label=="pending"})!.value as! Atomic<[StoryId:[UUID]]>
        return pending.with { $0.values.reduce(0) { $0 + $1.count } }
    }
    func testQueuedDatabaseWorkAfterCancellationCannotCommitCounts() {
        let a=Account(); seed(a); a.postbox.delayAt=[3]
        let d=Messages(a).refreshStoryViews(peerId:10,ids:[1]).start(); a.network.requests[0].succeed([views(100)])
        let queued=a.postbox.pending[0]; d.dispose(); queued.run()
        XCTAssertEqual(value(a)?.views,views()); XCTAssertEqual(a.postbox.storage.writes,0); XCTAssertTrue(a.stateManager.updates.isEmpty)
    }
    func testCancellationInvalidatesTicketBeforeDisposingQueuedWork() {
        let a=Account(); seed(a); a.postbox.delayAt=[3]
        let d=Messages(a).refreshStoryViews(peerId:10,ids:[1]).start(); a.network.requests[0].succeed([views(100)])
        let queued=a.postbox.pending[0]; a.postbox.onCancel={ queued.run() }; d.dispose(); a.postbox.onCancel=nil
        XCTAssertEqual(value(a)?.views,views()); XCTAssertEqual(a.postbox.storage.writes,0); XCTAssertTrue(a.stateManager.updates.isEmpty)
    }
    func testCanceledOlderQueuedWorkCannotInterfereWithReplacementTicket() {
        let a=Account(); seed(a); a.postbox.delayAt=[3]
        let first=Messages(a).refreshStoryViews(peerId:10,ids:[1]).start(); a.network.requests[0].succeed([views(100)])
        let queued=a.postbox.pending[0]; first.dispose()
        let second=Messages(a).refreshStoryViews(peerId:10,ids:[1]).start(); queued.run(); a.network.requests[1].succeed([views(0)])
        XCTAssertEqual(value(a)?.views,views(0)); XCTAssertEqual(a.postbox.storage.writes,1); second.dispose()
    }
    func testTerminalRequestsReleaseTicketsWithoutExplicitDisposal() {
        for mode in 0..<4 {
            let a=Account(); seed(a); let d=Messages(a).refreshStoryViews(peerId:10,ids:[1,2]).start()
            XCTAssertEqual(pendingCount(a.storyViewRefreshContext),2)
            switch mode { case 0: a.network.requests[0].succeed([views(50),views(60)]); case 1: a.network.requests[0].fail(); case 2: a.network.requests[0].succeed([]); default: a.network.requests[0].empty() }
            XCTAssertEqual(pendingCount(a.storyViewRefreshContext),0); withExtendedLifetime(d) {}
        }
    }
    func testCanceledLookupReleasesTicketEvenIfDatabaseWorkRunsLater() {
        let a=Account(); seed(a); a.postbox.delayAt=[1]
        let d=Messages(a).refreshStoryViews(peerId:10,ids:[1]).start(); XCTAssertEqual(pendingCount(a.storyViewRefreshContext),1)
        let queued=a.postbox.pending[0]; d.dispose(); queued.run(); XCTAssertEqual(pendingCount(a.storyViewRefreshContext),0); XCTAssertTrue(a.network.requests.isEmpty)
    }
    func testRefreshContextDoesNotRetainVisitedStoryIds() {
        let a=Account()
        for id:Int32 in 1...500 {
            let d=Messages(a).refreshStoryViews(peerId:10,ids:[id]).start()
            XCTAssertEqual(pendingCount(a.storyViewRefreshContext),1)
            if id % 2 == 0 { a.network.requests.last?.succeed([views()]) } else { d.dispose() }
            XCTAssertEqual(pendingCount(a.storyViewRefreshContext),0)
        }
    }
    func testSuccessfulSupersessionImmediatelyReleasesObsoleteTickets() {
        let a=Account(); seed(a); var requests:[Disposable]=[]
        for _ in 0..<100 { requests.append(Messages(a).refreshStoryViews(peerId:10,ids:[1]).start()) }
        XCTAssertEqual(pendingCount(a.storyViewRefreshContext),100); a.network.requests.last?.succeed([views(100)])
        XCTAssertEqual(pendingCount(a.storyViewRefreshContext),0)
        for request in requests { request.dispose() }; XCTAssertEqual(pendingCount(a.storyViewRefreshContext),0)
    }
    func testCompletionReentryStartsWithReleasedTicket() {
        let a=Account(); seed(a); var nested:Disposable?; var finished=0
        let d=Messages(a).refreshStoryViews(peerId:10,ids:[1]).start(completed:{
            XCTAssertEqual(self.pendingCount(a.storyViewRefreshContext),0); finished+=1
            nested=Messages(a).refreshStoryViews(peerId:10,ids:[1]).start()
        })
        a.network.requests[0].fail(); XCTAssertEqual(finished,1); XCTAssertEqual(pendingCount(a.storyViewRefreshContext),1)
        a.network.requests[1].succeed([views(100)]); XCTAssertEqual(value(a)?.views,views(100)); XCTAssertEqual(pendingCount(a.storyViewRefreshContext),0); d.dispose(); nested?.dispose()
    }
    func testSynchronousRequestCompletionReleasesTicket() {
        let a=Account(); seed(a); a.network.onRequest={ $0.succeed([self.views(100)]) }
        let d=Messages(a).refreshStoryViews(peerId:10,ids:[1]).start(); XCTAssertEqual(pendingCount(a.storyViewRefreshContext),0); XCTAssertEqual(value(a)?.views,views(100)); d.dispose()
    }
    func testCancellationReleasesAccountAndRefreshContext() {
        var a:Account?=Account(); weak var weakAccount=a; weak var weakContext=a?.storyViewRefreshContext
        let d=Messages(a!).refreshStoryViews(peerId:10,ids:[1]).start(); a=nil; d.dispose()
        XCTAssertNil(weakAccount); XCTAssertNil(weakContext)
    }
    func testConcurrentSupersessionAndDisposalLeaveNoTickets() {
        let context=StoryViewRefreshContext()
        let requests=(0..<200).map { _ in context.begin(peerId:10,ids:[1,2]) }
        let latestAccepted=Atomic<Bool>(value:false)
        DispatchQueue.concurrentPerform(iterations:requests.count) { index in
            if index==requests.count-1 {
                let accepted=context.take([1:self.views(100),2:self.views(200)],for:requests[index])
                latestAccepted.swap(accepted.count==2)
            } else { context.finish(requests[index]) }
        }
        XCTAssertTrue(latestAccepted.with { $0 }); XCTAssertEqual(pendingCount(context),0)
        for request in requests { XCTAssertTrue(context.take([1:views()],for:request).isEmpty) }
    }
    func testConcurrentResultsAlwaysKeepNewestRequestEligible() {
        let context=StoryViewRefreshContext()
        let requests=(0..<200).map { _ in context.begin(peerId:10,ids:[1]) }
        let acceptedIndices=Atomic<Set<Int>>(value:[])
        DispatchQueue.concurrentPerform(iterations:requests.count) { index in
            if !context.take([1:self.views(index)],for:requests[index]).isEmpty {
                let _ = acceptedIndices.modify { var indices=$0; indices.insert(index); return indices }
            }
        }
        XCTAssertTrue(acceptedIndices.with { $0.contains(199) }); XCTAssertEqual(pendingCount(context),0)
    }

}

extension StoryViewRefreshTests {
    func testPendingReactionSuppressesOnlyMatchingStoryCountRefresh() {
        let a=Account(); seed(a)
        let reaction=StoryReactionContext.Request(storyId:.init(peerId:10,id:1),reaction:2)
        a.storyReactionContext.begin(reaction,previousReaction:.some(nil))
        let d=Messages(a).refreshStoryViews(peerId:10,ids:[1,2]).start(); a.network.requests[0].succeed([views(100),views(200)])
        XCTAssertEqual(value(a)?.views,views()); XCTAssertEqual(value(a,2)?.views,views(200))
        if case let .updateViews(_,values)=a.stateManager.updates.first { XCTAssertEqual(values,[2:views(200)]) } else { XCTFail() }
        _=a.storyReactionContext.finish(reaction,success:true); d.dispose()
    }
    func testPendingReactionInOtherAccountDoesNotSuppressCounts() {
        let a=Account(),b=Account(); seed(a)
        let reaction=StoryReactionContext.Request(storyId:.init(peerId:10,id:1),reaction:2); b.storyReactionContext.begin(reaction,previousReaction:.some(nil))
        let d=Messages(a).refreshStoryViews(peerId:10,ids:[1]).start(); a.network.requests[0].succeed([views(100)])
        XCTAssertEqual(value(a)?.views,views(100)); _=b.storyReactionContext.finish(reaction,success:true); d.dispose()
    }
}
