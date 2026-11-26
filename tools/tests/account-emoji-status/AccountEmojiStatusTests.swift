import Foundation
import CoreFoundation
import SwiftSignalKit
import XCTest

typealias PeerId = Int
class Peer { let id: Int; init(_ id: Int) { self.id = id } }
struct EnginePeer { let peer: Peer; init(_ peer: Peer) { self.peer = peer } }
struct MediaId: Equatable { let id: Int64 }
final class TelegramMediaFile { let fileId: MediaId; var isCustomEmoji = true; init(_ id: Int64) { fileId = .init(id: id) } }
struct PeerEmojiStatus: Equatable { enum Content: Equatable { case emoji(fileId: Int64); case starGift(id: Int64, fileId: Int64, title: String, slug: String, patternFileId: Int64, innerColor: Int32, outerColor: Int32, patternColor: Int32, textColor: Int32) }; let content: Content; let expirationDate: Int32? }
final class TelegramUser: Peer {
    let name: String; let status: PeerEmojiStatus?
    init(_ id: Int, name: String = "current", status: PeerEmojiStatus? = nil) { self.name = name; self.status = status; super.init(id) }
    func withUpdatedEmojiStatus(_ status: PeerEmojiStatus?) -> TelegramUser { .init(id, name: name, status: status) }
}
struct RecentMediaItem { let file: TelegramMediaFile; init(_ file: TelegramMediaFile) { self.file = file } }
struct RecentMediaItemId { let rawValue: Int64; init(_ id: MediaId) { rawValue = id.id } }
struct CodableEntry { let value: RecentMediaItem; init?(_ value: RecentMediaItem) { self.value = value } }
struct OrderedItemListEntry { let id: Int64; let contents: CodableEntry }
enum Namespaces { enum OrderedItemList { static let CloudRecentStatusEmoji = 1 } }
struct Settings { var focusIntentStatusEnabled = true; var focusIntentStatusFallback: Int? = 123; var other = 456 }
final class Transaction {
    unowned let postbox: Postbox; init(_ postbox: Postbox) { self.postbox = postbox }
    func getPeer(_ id: Int) -> Peer? { postbox.peers[id] }
    func storeMediaIfNotPresent(media: TelegramMediaFile) { if postbox.media[media.fileId.id] == nil { postbox.media[media.fileId.id] = media } }
    func addOrMoveToFirstPositionOrderedItemListItem(collectionId: Int, item: OrderedItemListEntry, removeTailIfCountExceeds: Int) { postbox.recent.removeAll { $0 == item.id }; postbox.recent.insert(item.id, at: 0); postbox.recent = Array(postbox.recent.prefix(removeTailIfCountExceeds)) }
}
func updatePeersCustom(transaction: Transaction, peers: [TelegramUser], update: (TelegramUser?, TelegramUser) -> TelegramUser) { for peer in peers { transaction.postbox.peers[peer.id] = update(transaction.postbox.peers[peer.id] as? TelegramUser, peer) } }
final class Postbox {
    var peers: [Int: Peer] = [1: TelegramUser(1)]; var media: [Int64: TelegramMediaFile] = [:]; var recent: [Int64] = []; var settings = Settings()
    var autoCommit = true; var tasks: [() -> Void] = []
    func transaction<T>(_ body: @escaping (Transaction) -> T) -> Signal<T, NoError> {
        Signal { subscriber in
            let run = { let result = body(Transaction(self)); subscriber.putNext(result); subscriber.putCompletion() }
            if self.autoCommit { run() } else { self.tasks.append(run) }
            return EmptyDisposable
        }
    }
    func drain() { while !tasks.isEmpty { tasks.removeFirst()() } }
}
enum Api {
    enum Bool { case boolTrue, boolFalse }
    struct Status { let flags: Int32; let documentId: Int64; let until: Int32? }
    struct Collectible { let flags: Int32; let collectibleId: Int64; let until: Int32? }
    enum EmojiStatus { case emojiStatus(Status), inputEmojiStatusCollectible(Collectible), emojiStatusEmpty }
    enum functions { enum account { static func updateEmojiStatus(emojiStatus: EmojiStatus) -> EmojiStatus { emojiStatus } } }
}
enum RpcError { case generic }
final class Pending<T, E> {
    let subscriber: Subscriber<T, E>; var disposed = false; var onDispose: (() -> Void)?
    init(_ subscriber: Subscriber<T, E>) { self.subscriber = subscriber }
    func send(_ value: T) { subscriber.putNext(value) }
    func respond(_ value: T) { subscriber.putNext(value); subscriber.putCompletion() }
    func complete() { subscriber.putCompletion() }
    func fail(_ error: E) { subscriber.putError(error) }
    func dispose() { if !disposed { disposed = true; onDispose?() } }
}
protocol NetworkRequestDependencyTag { func shouldDependOn(other: NetworkRequestDependencyTag) -> Bool }
final class Network {
    var tags: [NetworkRequestDependencyTag?] = []
    var requests: [(Api.EmojiStatus, Pending<Api.Bool, RpcError>)] = []; var onSubscribe: (() -> Void)?
    func request(_ request: Api.EmojiStatus, tag: NetworkRequestDependencyTag? = nil) -> Signal<Api.Bool, RpcError> {
        Signal { subscriber in
            let pending = Pending(subscriber); self.requests.append((request, pending)); self.tags.append(tag); self.onSubscribe?()
            return ActionDisposable { pending.dispose() }
        }
    }
}
final class Account { let peerId = 1; let postbox = Postbox(); let network = Network() }
enum SetEmojiStatusError { case generic }
struct StarGift {
    struct UniqueGift {
        enum Attribute { case model(String, TelegramMediaFile, Int, Int), pattern(String, TelegramMediaFile, Int), backdrop(String, Int, Int32, Int32, Int32, Int32, Int), other }
        let id: Int64; let title: String; let slug: String; let attributes: [Attribute]
    }
}
__CORE_SUPPORT__
final class AccountData {
    let account: Account; init(_ account: Account) { self.account = account }
    __CORE__
}
struct GiftFixture {
    static let model = TelegramMediaFile(101), pattern = TelegramMediaFile(202)
    static let attributes: [StarGift.UniqueGift.Attribute] = [.model("model", model, 1, 1), .pattern("pattern", pattern, 1), .backdrop("backdrop", 1, 0, 2, 3, 4, 1)]
    static func gift(_ attributes: [StarGift.UniqueGift.Attribute] = attributes) -> StarGift.UniqueGift { .init(id: 300, title: "gift", slug: "gift-1", attributes: attributes) }
}
final class Observation {
    var errors = 0; var completed = 0; var disposable: Disposable?
    func start<E>(_ signal: Signal<Never, E>) { disposable = signal.start(error: { [weak self] _ in self?.errors += 1 }, completed: { [weak self] in self?.completed += 1 }) }
    deinit { disposable?.dispose() }
}
enum Mode: CaseIterable { case emoji, legacyEmoji, gift, legacyGift; var isGift: Bool { self == .gift || self == .legacyGift }; var isLegacy: Bool { self == .legacyEmoji || self == .legacyGift } }
final class AccountEmojiStatusTests: XCTestCase {
    func run(_ account: Account, mode: Mode, file: TelegramMediaFile? = TelegramMediaFile(10), gift: StarGift.UniqueGift = GiftFixture.gift(), until: Int32? = 123) -> Observation {
        let result = Observation(); let data = AccountData(account)
        switch mode {
        case .emoji: result.start(data.setEmojiStatusWithResult(file: file, expirationDate: until))
        case .legacyEmoji: result.start(data.setEmojiStatus(file: file, expirationDate: until))
        case .gift: result.start(data.setStarGiftStatusWithResult(starGift: gift, expirationDate: until))
        case .legacyGift: result.start(data.setStarGiftStatus(starGift: gift, expirationDate: until))
        }
        return result
    }
    func status(_ account: Account) -> PeerEmojiStatus? { (account.postbox.peers[1] as? TelegramUser)?.status }
    func testAllVariantsLeaveCacheUnchangedBeforeServerResponse() { for mode in Mode.allCases { let a = Account(); let o = run(a,mode:mode); XCTAssertNil(status(a)); XCTAssertTrue(a.postbox.media.isEmpty); XCTAssertTrue(a.postbox.recent.isEmpty); XCTAssertEqual(o.completed,0); XCTAssertEqual(a.network.requests.count,1) } }
    func testFalseResultNeverChangesStatusOrRecents() { for mode in Mode.allCases { let a = Account(); let o = run(a,mode:mode); a.network.requests[0].1.respond(.boolFalse); a.postbox.drain(); XCTAssertNil(status(a)); XCTAssertTrue(a.postbox.media.isEmpty); XCTAssertTrue(a.postbox.recent.isEmpty); XCTAssertEqual(o.errors,mode.isLegacy ? 0 : 1); XCTAssertEqual(o.completed,mode.isLegacy ? 1 : 0) } }
    func testTransportFailureDoesNotChangeLocalStatus() { for mode in Mode.allCases { let a = Account(); let o = run(a,mode:mode); a.network.requests[0].1.fail(.generic); a.postbox.drain(); XCTAssertNil(status(a)); XCTAssertTrue(a.postbox.media.isEmpty); XCTAssertEqual(o.errors,mode.isLegacy ? 0 : 1); XCTAssertEqual(o.completed,mode.isLegacy ? 1 : 0) } }
    func testEmptyResponseFailsResultVariantsWithoutMutation() { for mode in Mode.allCases { let a = Account(); let o = run(a,mode:mode); a.network.requests[0].1.complete(); a.postbox.drain(); XCTAssertNil(status(a)); XCTAssertTrue(a.postbox.media.isEmpty); XCTAssertEqual(o.errors,mode.isLegacy ? 0 : 1) } }
    func testSuccessfulVariantsCommitBeforeCompletion() { for mode in Mode.allCases { let a = Account(); let o = run(a,mode:mode); a.postbox.autoCommit = false; a.network.requests[0].1.respond(.boolTrue); XCTAssertNil(status(a)); XCTAssertEqual(o.completed,0); a.postbox.drain(); XCTAssertNotNil(status(a)); XCTAssertEqual(status(a)?.expirationDate,123); XCTAssertEqual(o.completed,1); XCTAssertEqual(o.errors,0) } }
    func testCollectiblePreservesAllMetadataAndStoresBothFiles() { let a = Account(); let o = run(a,mode:.gift); a.network.requests[0].1.respond(.boolTrue); XCTAssertEqual(status(a),.init(content:.starGift(id:300,fileId:101,title:"gift",slug:"gift-1",patternFileId:202,innerColor:0,outerColor:2,patternColor:3,textColor:4),expirationDate:123)); XCTAssertTrue(a.postbox.media[101] === GiftFixture.model); XCTAssertTrue(a.postbox.media[202] === GiftFixture.pattern); XCTAssertTrue(a.postbox.recent.isEmpty); XCTAssertEqual(o.completed,1) }
    func testMissingGiftAttributesCannotIssueClearRequest() { for mode in [Mode.gift,.legacyGift] { for index in 0..<3 { let a = Account(); var attrs = GiftFixture.attributes; attrs.remove(at:index); let o = run(a,mode:mode,gift:GiftFixture.gift(attrs)); XCTAssertTrue(a.network.requests.isEmpty); XCTAssertTrue(a.postbox.media.isEmpty); XCTAssertNil(status(a)); XCTAssertEqual(o.errors,mode.isLegacy ? 0 : 1) } } }
    func testEmptyGiftCannotChangeExistingStatus() { for mode in [Mode.gift,.legacyGift] { let a = Account(); let old = PeerEmojiStatus(content:.emoji(fileId:77),expirationDate:nil); a.postbox.peers[1] = TelegramUser(1,status:old); let o = run(a,mode:mode,gift:GiftFixture.gift([])); XCTAssertEqual(status(a),old); XCTAssertTrue(a.network.requests.isEmpty); XCTAssertEqual(o.errors,mode.isLegacy ? 0 : 1) } }
    func testNormalSelectionUpdatesRecentsOnlyAfterAcceptance() { let a = Account(); a.postbox.recent = [10,20]; let o = run(a,mode:.legacyEmoji,file:TelegramMediaFile(20)); XCTAssertEqual(a.postbox.recent,[10,20]); a.network.requests[0].1.respond(.boolTrue); XCTAssertEqual(a.postbox.recent,[20,10]); XCTAssertEqual(o.completed,1) }
    func testRecentListRemainsBounded() { let a = Account(); a.postbox.recent = (1...32).map(Int64.init); let o = run(a,mode:.legacyEmoji,file:TelegramMediaFile(99)); a.network.requests[0].1.respond(.boolTrue); XCTAssertEqual(a.postbox.recent.count,32); XCTAssertEqual(a.postbox.recent.first,99); XCTAssertFalse(a.postbox.recent.contains(32)); XCTAssertEqual(o.completed,1) }
    func testClearWaitsForAcceptedResponse() { for mode in [Mode.emoji,.legacyEmoji] { let a = Account(); a.postbox.peers[1] = TelegramUser(1,status:.init(content:.emoji(fileId:10),expirationDate:nil)); let o = run(a,mode:mode,file:nil); XCTAssertNotNil(status(a)); guard case .emojiStatusEmpty = a.network.requests[0].0 else { return XCTFail() }; a.network.requests[0].1.respond(.boolTrue); XCTAssertNil(status(a)); XCTAssertEqual(o.completed,1) } }
    func testRejectedClearKeepsExistingStatus() { let a = Account(); let old = PeerEmojiStatus(content:.emoji(fileId:10),expirationDate:nil); a.postbox.peers[1] = TelegramUser(1,status:old); let o = run(a,mode:.legacyEmoji,file:nil); a.network.requests[0].1.respond(.boolFalse); XCTAssertEqual(status(a),old); XCTAssertEqual(o.completed,1) }
    func testCommitUsesCurrentPeerFields() { for mode in Mode.allCases { let a = Account(); let o = run(a,mode:mode); a.postbox.peers[1] = TelegramUser(1,name:"changed"); a.network.requests[0].1.respond(.boolTrue); XCTAssertEqual((a.postbox.peers[1] as? TelegramUser)?.name,"changed"); XCTAssertNotNil(status(a)); XCTAssertEqual(o.completed,1) } }
    func testMissingPeerDoesNotGetInvented() { let a = Account(); let o = run(a,mode:.gift); a.postbox.peers[1] = nil; a.network.requests[0].1.respond(.boolTrue); XCTAssertNil(a.postbox.peers[1]); XCTAssertEqual(o.completed,1) }
    func testOtherPeerIsNotMutated() { let a = Account(); let other = TelegramUser(2); a.postbox.peers[2] = other; let o = run(a,mode:.gift); a.network.requests[0].1.respond(.boolTrue); XCTAssertTrue(a.postbox.peers[2] === other); XCTAssertEqual(o.completed,1) }
    func testCancellationBeforeResponseLeavesCacheUnchanged() { for mode in Mode.allCases { let a = Account(); let o = run(a,mode:mode); o.disposable?.dispose(); XCTAssertTrue(a.network.requests[0].1.disposed); a.network.requests[0].1.respond(.boolTrue); a.postbox.drain(); XCTAssertNil(status(a)); XCTAssertTrue(a.postbox.media.isEmpty); XCTAssertEqual(o.completed,0) } }
    func testAcceptedCommitSurvivesObserverCancellation() { for mode in Mode.allCases { let a = Account(); let o = run(a,mode:mode); a.postbox.autoCommit = false; a.network.requests[0].1.respond(.boolTrue); o.disposable?.dispose(); a.postbox.drain(); XCTAssertNotNil(status(a)); XCTAssertEqual(o.completed,0) } }
    func testResultSignalsDoNotRetainAccount() { for isGift in [true,false] { var account: Account? = Account(); let network = account!.network; weak var weakAccount = account; let observer = Observation(); if isGift { let s = AccountData(account!).setStarGiftStatusWithResult(starGift:GiftFixture.gift(),expirationDate:nil); account = nil; XCTAssertNil(weakAccount); observer.start(s) } else { let s = AccountData(account!).setEmojiStatusWithResult(file:TelegramMediaFile(10),expirationDate:nil); account = nil; XCTAssertNil(weakAccount); observer.start(s) }; network.requests[0].1.respond(.boolTrue); XCTAssertEqual(observer.completed,1) } }
    func testLegacySignalsDoNotRetainAccount() { for isGift in [true,false] { var account: Account? = Account(); let network = account!.network; weak var weakAccount = account; let s: Signal<Never,NoError> = isGift ? AccountData(account!).setStarGiftStatus(starGift:GiftFixture.gift(),expirationDate:nil) : AccountData(account!).setEmojiStatus(file:TelegramMediaFile(10),expirationDate:nil); account = nil; XCTAssertNil(weakAccount); let o = Observation(); o.start(s); network.requests[0].1.respond(.boolTrue); XCTAssertEqual(o.completed,1) } }
    func testAllVariantsShareNetworkDependencyTag() { let a = Account(); let observations = Mode.allCases.map { run(a,mode:$0) }; XCTAssertEqual(a.network.tags.count,4); for first in a.network.tags { for second in a.network.tags { XCTAssertTrue(first.flatMap { x in second.map { x.shouldDependOn(other:$0) } } ?? false) } }; withExtendedLifetime(observations) {} }
    func testCollectibleWireFieldsUseGiftIdentity() { let a = Account(); let o = run(a,mode:.gift,until:nil); guard case let .inputEmojiStatusCollectible(value) = a.network.requests[0].0 else { return XCTFail() }; XCTAssertEqual(value.collectibleId,300); XCTAssertEqual(value.flags,0); XCTAssertNil(value.until); withExtendedLifetime(o) {} }
    func testDuplicateReplyCommitsOneRecentEntry() { let a = Account(); let o = run(a,mode:.legacyEmoji); a.network.requests[0].1.send(.boolTrue); a.network.requests[0].1.send(.boolTrue); a.network.requests[0].1.complete(); XCTAssertEqual(a.postbox.recent,[10]); XCTAssertEqual(o.completed,1) }
    func testColdSignalsDoNotSendBeforeSubscription() { let a = Account(); let d = AccountData(a); let signals: [Any] = [d.setEmojiStatusWithResult(file:TelegramMediaFile(10),expirationDate:nil), d.setStarGiftStatusWithResult(starGift:GiftFixture.gift(),expirationDate:nil)]; XCTAssertTrue(a.network.requests.isEmpty); XCTAssertNil(status(a)); withExtendedLifetime(signals) {} }
    func testExistingMediaIsNotReplaced() { let a = Account(); let old = TelegramMediaFile(101); a.postbox.media[101] = old; let o = run(a,mode:.gift); a.network.requests[0].1.respond(.boolTrue); XCTAssertTrue(a.postbox.media[101] === old); XCTAssertEqual(o.completed,1) }
}
