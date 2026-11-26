import Foundation
import SwiftSignalKit
import XCTest

typealias PeerId = Int
struct FileId { let id: Int64 }
final class TelegramMediaFile { let fileId: FileId; init(_ id: Int64) { fileId = .init(id: id) } }
struct PeerEmojiStatus: Equatable {
    enum Content: Equatable { case emoji(fileId: Int64); case starGift(id: Int64, fileId: Int64, title: String, slug: String, patternFileId: Int64, innerColor: Int32, outerColor: Int32, patternColor: Int32, textColor: Int32) }
    let content: Content; let expirationDate: Int32?
}
class Peer { let id: Int; init(_ id: Int) { self.id = id } }
final class TelegramChannel: Peer {
    let emojiStatus: PeerEmojiStatus?; let title: String; let hasAccess: Bool
    init(_ id: Int = 10, status: PeerEmojiStatus? = .init(content: .emoji(fileId: 1), expirationDate: nil), title: String = "channel", access: Bool = true) { emojiStatus = status; self.title = title; hasAccess = access; super.init(id) }
    func withUpdatedEmojiStatus(_ status: PeerEmojiStatus?) -> TelegramChannel { .init(id, status: status, title: title, access: hasAccess) }
}
func apiInputChannel(_ peer: Peer) -> Api.InputChannel? { guard let channel = peer as? TelegramChannel, channel.hasAccess else { return nil }; return channel.id }
struct StarGift {
    struct UniqueGift {
        enum Attribute { case model(String, TelegramMediaFile, Int, Int), pattern(String, TelegramMediaFile, Int), backdrop(String, Int, Int32, Int32, Int32, Int32, Int), other }
        let id: Int64; let title: String; let slug: String; let attributes: [Attribute]
    }
}
protocol NetworkRequestDependencyTag { func shouldDependOn(other: NetworkRequestDependencyTag) -> Bool }
enum Api {
    typealias InputChannel = Int
    struct Status { let flags: Int32; let documentId: Int64; let until: Int32? }
    struct Collectible { let flags: Int32; let collectibleId: Int64; let until: Int32? }
    enum EmojiStatus { case emojiStatus(Status), inputEmojiStatusCollectible(Collectible), emojiStatusEmpty }
    struct Updates: Equatable { let marker: Int }
    struct Request { let channel: InputChannel; let status: EmojiStatus }
    enum functions { enum channels { static func updateEmojiStatus(channel: InputChannel, emojiStatus: EmojiStatus) -> Request { .init(channel: channel, status: emojiStatus) } } }
}
struct RpcError { let errorDescription: String }
final class Pending {
    let request: Api.Request; let tag: NetworkRequestDependencyTag?; let subscriber: Subscriber<Api.Updates, RpcError>; var disposed = false
    init(_ request: Api.Request, _ tag: NetworkRequestDependencyTag?, _ subscriber: Subscriber<Api.Updates, RpcError>) { self.request = request; self.tag = tag; self.subscriber = subscriber }
    func respond(_ marker: Int = 1) { subscriber.putNext(.init(marker: marker)); subscriber.putCompletion() }
    func fail(_ message: String = "REJECTED") { subscriber.putError(.init(errorDescription: message)) }
    func complete() { subscriber.putCompletion() }
}
final class Network {
    var requests: [Pending] = []; var onStart: (() -> Void)?
    func request(_ request: Api.Request, tag: NetworkRequestDependencyTag? = nil) -> Signal<Api.Updates, RpcError> {
        Signal { subscriber in
            let pending = Pending(request, tag, subscriber); self.requests.append(pending); self.onStart?()
            return ActionDisposable { pending.disposed = true }
        }
    }
}
final class Transaction {
    unowned let postbox: Postbox; init(_ postbox: Postbox) { self.postbox = postbox }
    func getPeer(_ id: Int) -> Peer? { postbox.peers[id] }
    func storeMediaIfNotPresent(media: TelegramMediaFile) { if postbox.media[media.fileId.id] == nil { postbox.media[media.fileId.id] = media } }
}
func updatePeersCustom(transaction: Transaction, peers: [TelegramChannel], update: (TelegramChannel?, TelegramChannel) -> TelegramChannel) { for peer in peers { transaction.postbox.peers[peer.id] = update(transaction.postbox.peers[peer.id] as? TelegramChannel, peer); transaction.postbox.writes += 1 } }
final class Postbox {
    var peers: [Int: Peer] = [10: TelegramChannel(), 20: TelegramChannel(20)]; var tasks: [() -> Void] = []; var media: [Int64: TelegramMediaFile] = [:]; var writes = 0
    func transaction<T>(_ body: @escaping (Transaction) -> T) -> Signal<T, NoError> {
        Signal { subscriber in self.tasks.append { let value = body(Transaction(self)); subscriber.putNext(value); subscriber.putCompletion() }; return EmptyDisposable }
    }
    func drain() { while !tasks.isEmpty { tasks.removeFirst()() } }
}
final class AccountStateManager { var updates: [Api.Updates] = []; func addUpdates(_ updates: Api.Updates) { self.updates.append(updates) } }
final class Account { let postbox = Postbox(); let network = Network(); let stateManager = AccountStateManager() }
__SOURCE__
struct GiftFixture {
    static let model = TelegramMediaFile(101), pattern = TelegramMediaFile(202)
    static let attributes: [StarGift.UniqueGift.Attribute] = [.model("model", model, 1, 1), .pattern("pattern", pattern, 1), .backdrop("backdrop", 1, 0, 2, 3, 4, 1)]
    static func gift(_ attributes: [StarGift.UniqueGift.Attribute] = attributes) -> StarGift.UniqueGift { .init(id: 300, title: "gift", slug: "gift-1", attributes: attributes) }
}
final class Observation { var errors = 0; var completed = 0; var disposable: Disposable?; func start(_ signal: Signal<Never, UpdatePeerEmojiStatusError>) { disposable = signal.start(error: { [weak self] _ in self?.errors += 1 }, completed: { [weak self] in self?.completed += 1 }) }; deinit { disposable?.dispose() } }

final class ChannelEmojiStatusTests: XCTestCase {
    func run(_ account: Account, gift: Bool = false, clear: Bool = false, id: PeerId = 10, expires: Int32? = 123) -> Observation { let result = Observation(); result.start(gift ? _internal_updatePeerStarGiftStatus(account: account, peerId: id, starGift: GiftFixture.gift(), expirationDate: expires) : _internal_updatePeerEmojiStatus(account: account, peerId: id, fileId: clear ? nil : 99, expirationDate: expires)); return result }
    func channel(_ account: Account, _ id: Int = 10) -> TelegramChannel? { account.postbox.peers[id] as? TelegramChannel }
    func testNoMutationBeforeServerAcknowledges() { for gift in [false, true] { let a = Account(); let o = run(a, gift: gift); a.postbox.drain(); XCTAssertEqual(channel(a)?.emojiStatus?.content, .emoji(fileId: 1)); XCTAssertEqual(a.postbox.writes, 0); XCTAssertEqual(o.completed, 0) } }
    func testNetworkRejectionKeepsOldStatusAndNoMedia() { for gift in [false, true] { let a = Account(); let o = run(a, gift: gift); a.postbox.drain(); a.network.requests[0].fail(); a.postbox.drain(); XCTAssertEqual(o.errors, 1); XCTAssertEqual(o.completed, 0); XCTAssertEqual(channel(a)?.emojiStatus?.content, .emoji(fileId: 1)); XCTAssertTrue(a.postbox.media.isEmpty); XCTAssertTrue(a.stateManager.updates.isEmpty) } }
    func testEmptyRpcIsFailure() { for gift in [false, true] { let a = Account(); let o = run(a, gift: gift); a.postbox.drain(); a.network.requests[0].complete(); a.postbox.drain(); XCTAssertEqual(o.errors, 1); XCTAssertEqual(o.completed, 0); XCTAssertEqual(a.postbox.writes, 0) } }
    func testNormalAcceptedStatusCommitsAndForwardsUpdates() { let a = Account(); let o = run(a); a.postbox.drain(); a.network.requests[0].respond(42); XCTAssertEqual(a.postbox.writes, 0); XCTAssertEqual(o.completed, 0); a.postbox.drain(); XCTAssertEqual(channel(a)?.emojiStatus, .init(content: .emoji(fileId: 99), expirationDate: 123)); XCTAssertEqual(o.completed, 1); XCTAssertEqual(a.stateManager.updates, [.init(marker: 42)]) }
    func testGiftAcceptedStatusCommitsFullMetadataAndFiles() { let a = Account(); let o = run(a, gift: true); a.postbox.drain(); a.network.requests[0].respond(); a.postbox.drain(); XCTAssertEqual(channel(a)?.emojiStatus, .init(content: .starGift(id: 300, fileId: 101, title: "gift", slug: "gift-1", patternFileId: 202, innerColor: 0, outerColor: 2, patternColor: 3, textColor: 4), expirationDate: 123)); XCTAssertTrue(a.postbox.media[101] === GiftFixture.model); XCTAssertTrue(a.postbox.media[202] === GiftFixture.pattern); XCTAssertEqual(o.completed, 1); XCTAssertEqual(a.stateManager.updates.count, 1) }
    func testClearOnlyAfterAcceptance() { let a = Account(); let o = run(a, clear: true); a.postbox.drain(); XCTAssertNotNil(channel(a)?.emojiStatus); a.network.requests[0].respond(); a.postbox.drain(); XCTAssertNil(channel(a)?.emojiStatus); XCTAssertEqual(o.completed, 1) }
    func testMissingPeerDoesNotRequestOrMutate() { let a = Account(); a.postbox.peers[10] = nil; let o = run(a); a.postbox.drain(); XCTAssertEqual(o.errors, 1); XCTAssertTrue(a.network.requests.isEmpty); XCTAssertEqual(a.postbox.writes, 0) }
    func testMissingAccessHashDoesNotMutate() { let a = Account(); a.postbox.peers[10] = TelegramChannel(access: false); let o = run(a, gift: true); a.postbox.drain(); XCTAssertEqual(o.errors, 1); XCTAssertTrue(a.network.requests.isEmpty); XCTAssertEqual(channel(a)?.emojiStatus?.content, .emoji(fileId: 1)) }
    func testWrongPeerTypeDoesNotRequest() { let a = Account(); a.postbox.peers[10] = Peer(10); let o = run(a); a.postbox.drain(); XCTAssertEqual(o.errors, 1); XCTAssertTrue(a.network.requests.isEmpty) }
    func testMissingCollectibleAttributesCannotClearStatus() { for missing in 0..<3 { let a = Account(); var attributes = GiftFixture.attributes; attributes.remove(at: missing); let o = Observation(); o.start(_internal_updatePeerStarGiftStatus(account: a, peerId: 10, starGift: GiftFixture.gift(attributes), expirationDate: nil)); a.postbox.drain(); XCTAssertEqual(o.errors, 1); XCTAssertTrue(a.network.requests.isEmpty); XCTAssertEqual(channel(a)?.emojiStatus?.content, .emoji(fileId: 1)); XCTAssertEqual(a.postbox.writes, 0) } }
    func testEmptyGiftCannotClearStatus() { let a = Account(); let o = Observation(); o.start(_internal_updatePeerStarGiftStatus(account: a, peerId: 10, starGift: GiftFixture.gift([]), expirationDate: nil)); a.postbox.drain(); XCTAssertEqual(o.errors, 1); XCTAssertTrue(a.network.requests.isEmpty); XCTAssertEqual(a.postbox.writes, 0) }
    func testNotModifiedIsAcceptedAndReconcilesLocalStatus() { for gift in [false, true] { let a = Account(); let o = run(a, gift: gift); a.postbox.drain(); a.network.requests[0].fail("CHAT_NOT_MODIFIED"); XCTAssertEqual(o.completed, 0); a.postbox.drain(); XCTAssertEqual(o.errors, 0); XCTAssertEqual(o.completed, 1); XCTAssertNotEqual(channel(a)?.emojiStatus?.content, .emoji(fileId: 1)); XCTAssertTrue(a.stateManager.updates.isEmpty) } }
    func testCurrentTitleAndOtherPeerArePreserved() { let a = Account(); let o = run(a); a.postbox.drain(); a.postbox.peers[10] = TelegramChannel(title: "edited"); a.network.requests[0].respond(); a.postbox.drain(); XCTAssertEqual(channel(a)?.title, "edited"); XCTAssertEqual(channel(a,20)?.emojiStatus?.content, .emoji(fileId: 1)); XCTAssertEqual(o.completed, 1) }
    func testRemovedChannelIsNotRecreatedButUpdatesStillForwarded() { let a = Account(); let o = run(a); a.postbox.drain(); a.postbox.peers[10] = nil; a.network.requests[0].respond(); a.postbox.drain(); XCTAssertNil(channel(a)); XCTAssertEqual(o.completed, 1); XCTAssertEqual(a.stateManager.updates.count, 1) }
    func testReplacementPeerTypeIsNotOverwritten() { let a = Account(); let o = run(a); a.postbox.drain(); let peer = Peer(10); a.postbox.peers[10] = peer; a.network.requests[0].respond(); a.postbox.drain(); XCTAssertTrue(a.postbox.peers[10] === peer); XCTAssertEqual(o.completed, 1) }
    func testCancellationBeforeLookupSuppressesRequestAndMutation() { let a = Account(); let o = run(a); o.disposable?.dispose(); a.postbox.drain(); XCTAssertTrue(a.network.requests.isEmpty); XCTAssertEqual(a.postbox.writes, 0); XCTAssertEqual(o.completed, 0) }
    func testCancellationBeforeResponseSuppressesCommit() { let a = Account(); let o = run(a, gift: true); a.postbox.drain(); o.disposable?.dispose(); XCTAssertTrue(a.network.requests[0].disposed); a.network.requests[0].respond(); a.postbox.drain(); XCTAssertEqual(a.postbox.writes, 0); XCTAssertTrue(a.postbox.media.isEmpty); XCTAssertTrue(a.stateManager.updates.isEmpty) }
    func testAcceptedCommitAndUpdatesSurviveObserverCancellation() { let a = Account(); let o = run(a, gift: true); a.postbox.drain(); a.network.requests[0].respond(7); o.disposable?.dispose(); a.postbox.drain(); XCTAssertEqual(a.postbox.writes, 1); XCTAssertEqual(a.stateManager.updates, [.init(marker: 7)]); XCTAssertEqual(o.completed, 0) }
    func testSignalDoesNotRetainAccountOrStateManager() { var a: Account? = Account(); let p = a!.postbox; let n = a!.network; weak var wa = a; weak var ws = a!.stateManager; let signal = _internal_updatePeerEmojiStatus(account: a!, peerId: 10, fileId: 99, expirationDate: nil); a = nil; XCTAssertNil(wa); XCTAssertNil(ws); let o = Observation(); o.start(signal); p.drain(); n.requests[0].respond(); p.drain(); XCTAssertEqual(o.completed, 1) }
    func testRepeatedSubscriptionStartsIndependentRequest() { let a = Account(); let s = _internal_updatePeerEmojiStatus(account: a, peerId: 10, fileId: 99, expirationDate: nil); let x = Observation(),y = Observation(); x.start(s); y.start(s); a.postbox.drain(); XCTAssertEqual(a.network.requests.count, 2); x.disposable?.dispose(); XCTAssertTrue(a.network.requests[0].disposed); XCTAssertFalse(a.network.requests[1].disposed) }
    func testDuplicateResponseCommitsOnce() { let a = Account(); let o = run(a); a.postbox.drain(); let p = a.network.requests[0]; p.subscriber.putNext(.init(marker: 1)); p.subscriber.putNext(.init(marker: 2)); p.complete(); a.postbox.drain(); XCTAssertEqual(a.postbox.writes, 1); XCTAssertEqual(a.stateManager.updates, [.init(marker: 1)]); XCTAssertEqual(o.completed, 1) }
    func testNormalAndGiftRequestsShareDependencyForSamePeerOnly() { let a = Account(); let x = run(a),y = run(a,gift:true),z = run(a,id:20); a.postbox.drain(); let tags = a.network.requests.map(\.tag); if let first = tags[0], let second = tags[1], let third = tags[2] { XCTAssertTrue(first.shouldDependOn(other: second)); XCTAssertTrue(second.shouldDependOn(other: first)); XCTAssertFalse(first.shouldDependOn(other: third)) } else { XCTFail("Missing dependency tags") }; withExtendedLifetime((x,y,z)) {} }
    func testGiftRequestCarriesCollectibleIdAndExpiry() { let a = Account(); let o = run(a,gift:true); a.postbox.drain(); guard case let .inputEmojiStatusCollectible(value) = a.network.requests[0].request.status else { return XCTFail() }; XCTAssertEqual(value.collectibleId, 300); XCTAssertEqual(value.flags, 1); XCTAssertEqual(value.until, 123); withExtendedLifetime(o) {} }
    func testIndefiniteNormalRequestOmitsUntilFlag() { let a = Account(); let o = run(a,expires:nil); a.postbox.drain(); guard case let .emojiStatus(value) = a.network.requests[0].request.status else { return XCTFail() }; XCTAssertEqual(value.documentId, 99); XCTAssertEqual(value.flags, 0); XCTAssertNil(value.until); withExtendedLifetime(o) {} }
    func testClearUsesEmptyStatusConstructor() { let a = Account(); let o = run(a,clear:true); a.postbox.drain(); guard case .emojiStatusEmpty = a.network.requests[0].request.status else { return XCTFail() }; withExtendedLifetime(o) {} }
    func testExistingCachedMediaIsPreserved() { let a = Account(); let old = TelegramMediaFile(101); a.postbox.media[101] = old; let o = run(a,gift:true); a.postbox.drain(); a.network.requests[0].respond(); a.postbox.drain(); XCTAssertTrue(a.postbox.media[101] === old); XCTAssertEqual(o.completed, 1) }
}
