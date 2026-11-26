import Foundation
import SwiftSignalKit
import XCTest

typealias PeerId = Int
enum EnginePeer { typealias Id = PeerId }
struct PeerNameColor { let rawValue: Int32; static let blue = PeerNameColor(rawValue: 4) }
class Peer { let id: Int; init(_ id: Int) { self.id = id } }
final class TelegramChannel: Peer {
    let hasAccess: Bool
    init(_ id: Int = 10, access: Bool = true) { hasAccess = access; super.init(id) }
}
func apiInputChannel(_ peer: Peer) -> Api.InputChannel? { guard let channel = peer as? TelegramChannel, channel.hasAccess else { return nil }; return channel.id }
protocol NetworkRequestDependencyTag { func shouldDependOn(other: NetworkRequestDependencyTag) -> Bool }
enum Api {
    typealias InputChannel = Int
    struct Chat: Equatable { let id: Int; let value: Int }
    struct User: Equatable { let id: Int; let value: Int }
    struct Data: Equatable { let chats: [Chat]; let users: [User]; let marker: Int }
    enum Updates: Equatable { case updates(Data), updatesCombined(Data), updatesTooLong }
    struct Request { let flags: Int32; let channel: InputChannel; let color: Int32?; let backgroundEmojiId: Int64? }
    enum functions { enum channels { static func updateColor(flags: Int32, channel: InputChannel, color: Int32?, backgroundEmojiId: Int64?) -> Request { .init(flags: flags, channel: channel, color: color, backgroundEmojiId: backgroundEmojiId) } } }
}
func apiUpdatesGroups(_ updates: Api.Updates) -> [Api.Chat] { switch updates { case let .updates(data), let .updatesCombined(data): return data.chats; default: return [] } }
struct AccumulatedPeers {
    let chats: [Api.Chat]; let users: [Api.User]
    init(transaction: Transaction, chats: [Api.Chat], users: [Api.User]) { self.chats = chats; self.users = users }
}
func updatePeers(transaction: Transaction, accountPeerId: PeerId, peers: AccumulatedPeers) {
    transaction.postbox.chats += peers.chats; transaction.postbox.users += peers.users
    transaction.postbox.accountIds.append(accountPeerId)
}
struct MTRpcError { let errorDescription: String }
final class Pending {
    let request: Api.Request; let tag: NetworkRequestDependencyTag?; let subscriber: Subscriber<Api.Updates, MTRpcError>; var disposed = false
    init(_ request: Api.Request, _ tag: NetworkRequestDependencyTag?, _ subscriber: Subscriber<Api.Updates, MTRpcError>) { self.request = request; self.tag = tag; self.subscriber = subscriber }
    func respond(_ marker: Int = 1) { subscriber.putNext(.updates(.init(chats: [.init(id: request.channel, value: marker)], users: [], marker: marker))); subscriber.putCompletion() }
    func fail(_ message: String = "REJECTED") { subscriber.putError(.init(errorDescription: message)) }
    func complete() { subscriber.putCompletion() }
}
final class Network {
    var requests: [Pending] = []; var onStart: ((Pending) -> Void)?
    func request(_ request: Api.Request, tag: NetworkRequestDependencyTag? = nil) -> Signal<Api.Updates, MTRpcError> {
        Signal { subscriber in
            let pending = Pending(request, tag, subscriber); self.requests.append(pending); self.onStart?(pending)
            return ActionDisposable { pending.disposed = true }
        }
    }
}
final class Transaction {
    unowned let postbox: Postbox; init(_ postbox: Postbox) { self.postbox = postbox }
    func getPeer(_ id: Int) -> Peer? { postbox.peers[id] }
}
final class Postbox {
    var peers: [Int: Peer] = [10: TelegramChannel(), 20: TelegramChannel(20)]
    var tasks: [() -> Void] = []; var chats: [Api.Chat] = []; var users: [Api.User] = []; var accountIds: [Int] = []
    func transaction<T>(_ body: @escaping (Transaction) -> T) -> Signal<T, NoError> {
        Signal { subscriber in self.tasks.append { let value = body(Transaction(self)); subscriber.putNext(value); subscriber.putCompletion() }; return EmptyDisposable }
    }
    func drain() { while !tasks.isEmpty { tasks.removeFirst()() } }
}
final class AccountStateManager { var updates: [Api.Updates] = []; func addUpdates(_ updates: Api.Updates) { self.updates.append(updates) } }
final class Account { let peerId = 99; let postbox = Postbox(); let network = Network(); let stateManager = AccountStateManager() }
__SOURCE__
final class Observation {
    var errors: [UpdatePeerNameColorAndEmojiError] = []; var completed = 0; var next = 0; var disposable: Disposable?
    func start(_ signal: Signal<Void, UpdatePeerNameColorAndEmojiError>) { disposable = signal.start(next: { [weak self] in self?.next += 1 }, error: { [weak self] in self?.errors.append($0) }, completed: { [weak self] in self?.completed += 1 }) }
    deinit { disposable?.dispose() }
}
final class ChannelColorTests: XCTestCase {
    func signal(_ a: Account, _ mode: Int = 0, id: Int = 10) -> Signal<Void, UpdatePeerNameColorAndEmojiError> {
        switch mode {
        case 1: return _internal_updatePeerNameColor(account: a, peerId: id, nameColor: .blue, backgroundEmojiId: 101)
        case 2: return _internal_updatePeerProfileColor(account: a, peerId: id, profileColor: .blue, profileBackgroundEmojiId: 202)
        default: return _internal_updatePeerNameColorAndEmoji(account: a, peerId: id, nameColor: .blue, backgroundEmojiId: 101, profileColor: .blue, profileBackgroundEmojiId: 202)
        }
    }
    func run(_ a: Account, _ mode: Int = 0, id: Int = 10) -> Observation { let o = Observation(); o.start(signal(a,mode,id:id)); return o }
    func partial(_ rejected: Int, failureFirst: Bool) {
        let a = Account(); let o = run(a); a.postbox.drain(); let accepted = 1 - rejected
        if failureFirst {
            a.network.requests[rejected].fail(); XCTAssertTrue(o.errors.isEmpty); XCTAssertFalse(a.network.requests[accepted].disposed)
            a.network.requests[accepted].respond(12)
        } else {
            a.network.requests[accepted].respond(12); a.postbox.drain(); XCTAssertEqual(a.postbox.chats.map(\.value),[12]); XCTAssertEqual(a.stateManager.updates.count,1)
            a.network.requests[rejected].fail()
        }
        a.postbox.drain(); XCTAssertEqual(a.postbox.chats.map(\.value),[12]); XCTAssertEqual(a.stateManager.updates.count,1); XCTAssertEqual(o.errors.count,1); XCTAssertEqual(o.next,0); XCTAssertEqual(o.completed,0)
    }
    func testNameFailureBeforeProfileAcceptance() { partial(0,failureFirst:true) }
    func testNameFailureAfterProfileAcceptance() { partial(0,failureFirst:false) }
    func testProfileFailureBeforeNameAcceptance() { partial(1,failureFirst:true) }
    func testProfileFailureAfterNameAcceptance() { partial(1,failureFirst:false) }
    func testColdSignalsHaveNoWork() { let a = Account(); let s = (0...2).map { signal(a,$0) }; XCTAssertTrue(a.postbox.tasks.isEmpty); XCTAssertTrue(a.network.requests.isEmpty); withExtendedLifetime(s) {} }
    func testPendingSignalsDoNotMutateOrComplete() { for m in 0...2 { let a = Account(); let o = run(a,m); a.postbox.drain(); XCTAssertTrue(a.postbox.chats.isEmpty); XCTAssertTrue(a.stateManager.updates.isEmpty); XCTAssertEqual(o.next,0); XCTAssertEqual(o.completed,0) } }
    func testSingleNameAccepted() { accepted(1) }
    func testSingleProfileAccepted() { accepted(2) }
    func accepted(_ mode: Int) { let a = Account(); let o = run(a,mode); a.postbox.drain(); a.network.requests[0].respond(8); XCTAssertEqual(o.next,0); a.postbox.drain(); XCTAssertEqual(o.next,1); XCTAssertEqual(o.completed,1); XCTAssertTrue(o.errors.isEmpty); XCTAssertEqual(a.postbox.chats.map(\.value),[8]); XCTAssertEqual(a.postbox.accountIds,[99]); XCTAssertEqual(a.stateManager.updates.count,1) }
    func testBothAcceptedInEitherOrder() { for order in [[0,1],[1,0]] { let a = Account(); let o = run(a); a.postbox.drain(); a.network.requests[order[0]].respond(order[0]); a.postbox.drain(); XCTAssertEqual(o.next,0); a.network.requests[order[1]].respond(order[1]); a.postbox.drain(); XCTAssertEqual(o.next,1); XCTAssertEqual(o.completed,1); XCTAssertTrue(o.errors.isEmpty); XCTAssertEqual(a.stateManager.updates.count,2); XCTAssertEqual(a.postbox.chats.map(\.value),order) } }
    func testSingleRejectionPreservesState() { for m in 1...2 { let a = Account(); let o = run(a,m); a.postbox.drain(); a.network.requests[0].fail(); a.postbox.drain(); XCTAssertEqual(o.errors.count,1); XCTAssertEqual(o.next,0); XCTAssertTrue(a.postbox.chats.isEmpty); XCTAssertTrue(a.stateManager.updates.isEmpty) } }
    func testEmptySingleResponseIsError() { for m in 1...2 { let a = Account(); let o = run(a,m); a.postbox.drain(); a.network.requests[0].complete(); a.postbox.drain(); XCTAssertEqual(o.errors.count,1); XCTAssertEqual(o.completed,0); XCTAssertEqual(o.next,0) } }
    func testEmptyCombinedResponseDoesNotCancelOtherField() { let a = Account(); let o = run(a); a.postbox.drain(); a.network.requests[0].complete(); a.network.requests[1].respond(); a.postbox.drain(); XCTAssertEqual(o.errors.count,1); XCTAssertEqual(a.stateManager.updates.count,1); XCTAssertEqual(o.completed,0) }
    func testNotModifiedIsSuccessWithoutWrites() { for m in 0...2 { let a = Account(); let o = run(a,m); a.postbox.drain(); for p in a.network.requests { p.fail("CHAT_NOT_MODIFIED") }; a.postbox.drain(); XCTAssertTrue(o.errors.isEmpty); XCTAssertEqual(o.next,1); XCTAssertEqual(o.completed,1); XCTAssertTrue(a.postbox.chats.isEmpty); XCTAssertTrue(a.stateManager.updates.isEmpty) } }
    func testNotModifiedPrefixIsNotAcceptance() { let a = Account(); let o = run(a,1); a.postbox.drain(); a.network.requests[0].fail("CHAT_NOT_MODIFIED_INVALID"); a.postbox.drain(); XCTAssertEqual(o.errors.count,1); XCTAssertEqual(o.next,0) }
    func testNotModifiedAndAccepted() { let a = Account(); let o = run(a); a.postbox.drain(); a.network.requests[0].fail("CHAT_NOT_MODIFIED"); a.network.requests[1].respond(); a.postbox.drain(); XCTAssertEqual(o.completed,1); XCTAssertEqual(a.stateManager.updates.count,1) }
    func testBothFailuresPreferBoostErrorRegardlessOfOrder() { for boost in 0...1 { for order in [[0,1],[1,0]] { let a = Account(); let o = run(a); a.postbox.drain(); for i in order { a.network.requests[i].fail(i == boost ? "BOOSTS_REQUIRED_12" : "REJECTED") }; a.postbox.drain(); XCTAssertEqual(o.errors.count,1); if case .channelBoostRequired? = o.errors.first {} else { XCTFail("Expected boost error") }; XCTAssertTrue(a.stateManager.updates.isEmpty) } } }
    func testSingleBoostClassification() { let a = Account(); let o = run(a,2); a.postbox.drain(); a.network.requests[0].fail("BOOSTS_REQUIRED"); if case .channelBoostRequired? = o.errors.first {} else { XCTFail() } }
    func testMissingPeerFailsWithoutRequest() { for m in 0...2 { let a = Account(); a.postbox.peers[10] = nil; let o = run(a,m); a.postbox.drain(); XCTAssertEqual(o.errors.count,1); XCTAssertTrue(a.network.requests.isEmpty) } }
    func testNonChannelFailsWithoutRequest() { let a = Account(); a.postbox.peers[10] = Peer(10); let o = run(a); a.postbox.drain(); XCTAssertEqual(o.errors.count,1); XCTAssertTrue(a.network.requests.isEmpty) }
    func testMissingAccessHashFailsWithoutRequest() { let a = Account(); a.postbox.peers[10] = TelegramChannel(access:false); let o = run(a); a.postbox.drain(); XCTAssertEqual(o.errors.count,1); XCTAssertTrue(a.network.requests.isEmpty) }
    func testFlagsAndParameters() { let a = Account(); let o = run(a); a.postbox.drain(); let p = a.network.requests.map(\.request); XCTAssertEqual(p.map(\.channel),[10,10]); XCTAssertEqual(p.map(\.flags),[5,7]); XCTAssertEqual(p.map(\.color),[4,4]); XCTAssertEqual(p.map(\.backgroundEmojiId),[101,202]); withExtendedLifetime(o) {} }
    func testProfileClearOmitsOptionalFlags() { let a = Account(); let o = Observation(); o.start(_internal_updatePeerProfileColor(account:a,peerId:10,profileColor:nil,profileBackgroundEmojiId:nil)); a.postbox.drain(); let p = a.network.requests[0].request; XCTAssertEqual(p.flags,2); XCTAssertNil(p.color); XCTAssertNil(p.backgroundEmojiId); a.network.requests[0].respond(); a.postbox.drain(); XCTAssertEqual(o.completed,1) }
    func testNamePatternClearKeepsColorFlag() { let a = Account(); let o = Observation(); o.start(_internal_updatePeerNameColor(account:a,peerId:10,nameColor:.blue,backgroundEmojiId:nil)); a.postbox.drain(); XCTAssertEqual(a.network.requests[0].request.flags,4); XCTAssertNil(a.network.requests[0].request.backgroundEmojiId); withExtendedLifetime(o) {} }
    func testAllResponsePeersAreCommitted() { for combined in [false,true] { let a = Account(); let o = run(a,1); a.postbox.drain(); let d = Api.Data(chats:[.init(id:20,value:3),.init(id:10,value:9)],users:[.init(id:30,value:4)],marker:1); a.network.requests[0].subscriber.putNext(combined ? .updatesCombined(d) : .updates(d)); a.postbox.drain(); XCTAssertEqual(a.postbox.chats,d.chats); XCTAssertEqual(a.postbox.users,d.users); XCTAssertEqual(o.completed,1) } }
    func testNonContainerUpdatesAreForwarded() { let a = Account(); let o = run(a,1); a.postbox.drain(); a.network.requests[0].subscriber.putNext(.updatesTooLong); a.postbox.drain(); XCTAssertEqual(a.stateManager.updates,[.updatesTooLong]); XCTAssertTrue(a.postbox.chats.isEmpty); XCTAssertEqual(o.completed,1) }
    func testCancelBeforeLookupSuppressesRequests() { for m in 0...2 { let a = Account(); let o = run(a,m); o.disposable?.dispose(); a.postbox.drain(); XCTAssertTrue(a.network.requests.isEmpty); XCTAssertEqual(o.completed,0) } }
    func testCancelBeforeResponseSuppressesMutations() { for m in 0...2 { let a = Account(); let o = run(a,m); a.postbox.drain(); o.disposable?.dispose(); for p in a.network.requests { XCTAssertTrue(p.disposed); p.respond() }; a.postbox.drain(); XCTAssertTrue(a.postbox.chats.isEmpty); XCTAssertTrue(a.stateManager.updates.isEmpty); XCTAssertEqual(o.completed,0) } }
    func testAcceptedQueuedCommitSurvivesCancellation() { for m in 0...2 { let a = Account(); let o = run(a,m); a.postbox.drain(); a.network.requests[0].respond(9); o.disposable?.dispose(); a.postbox.drain(); XCTAssertEqual(a.postbox.chats.map(\.value),[9]); XCTAssertEqual(a.stateManager.updates.count,1); XCTAssertEqual(o.completed,0) } }
    func testAcceptedCommitSurvivesOtherFailureBeforeDrain() { let a = Account(); let o = run(a); a.postbox.drain(); a.network.requests[0].respond(6); a.network.requests[1].fail(); a.postbox.drain(); XCTAssertEqual(a.postbox.chats.map(\.value),[6]); XCTAssertEqual(a.stateManager.updates.count,1); XCTAssertEqual(o.errors.count,1) }
    func testDuplicateResponsesOnlyCommitOnce() { for m in 0...2 { let a = Account(); let o = run(a,m); a.postbox.drain(); for p in a.network.requests { p.subscriber.putNext(.updates(.init(chats:[.init(id:10,value:1)],users:[],marker:1))); p.subscriber.putNext(.updates(.init(chats:[.init(id:10,value:2)],users:[],marker:2))); p.complete() }; a.postbox.drain(); XCTAssertEqual(a.stateManager.updates.count,m == 0 ? 2 : 1); XCTAssertTrue(a.postbox.chats.allSatisfy { $0.value == 1 }); XCTAssertEqual(o.completed,1); XCTAssertEqual(o.next,1) } }
    func testSignalsDoNotRetainAccountOrManager() { for m in 0...2 { var a: Account? = Account(); let p = a!.postbox; let n = a!.network; weak var wa = a; weak var ws = a!.stateManager; let s = signal(a!,m); a = nil; XCTAssertNil(wa); XCTAssertNil(ws); let o = Observation(); o.start(s); p.drain(); for r in n.requests { r.respond() }; p.drain(); XCTAssertEqual(o.completed,1) } }
    func testInFlightRequestsDoNotRetainAccount() { for m in 0...2 { var a: Account? = Account(); let p = a!.postbox; let n = a!.network; let o = run(a!,m); p.drain(); weak var wa = a; weak var ws = a!.stateManager; a = nil; XCTAssertNil(wa); XCTAssertNil(ws); for r in n.requests { r.respond() }; p.drain(); XCTAssertEqual(o.completed,1) } }
    func testRepeatedSubscriptionsAreIndependent() { let a = Account(); let s = signal(a,1); let x = Observation(),y = Observation(); x.start(s); y.start(s); a.postbox.drain(); XCTAssertEqual(a.network.requests.count,2); x.disposable?.dispose(); XCTAssertTrue(a.network.requests[0].disposed); XCTAssertFalse(a.network.requests[1].disposed); a.network.requests[1].respond(); a.postbox.drain(); XCTAssertEqual(y.completed,1); XCTAssertEqual(x.completed,0) }
    func testSynchronousResponses() { for m in 0...2 { let a = Account(); a.network.onStart = { $0.respond() }; let o = run(a,m); a.postbox.drain(); XCTAssertEqual(o.next,1); XCTAssertEqual(o.completed,1); XCTAssertTrue(o.errors.isEmpty) } }
    func testSharedTagsScopePeerAndField() { let a = Account(); let x = run(a),y = run(a,1),z = run(a,2),w = run(a,1,id:20); a.postbox.drain(); let tags = a.network.requests.compactMap(\.tag); guard tags.count == 5 else { return XCTFail("Missing tags") }; XCTAssertTrue(tags[0].shouldDependOn(other:tags[2])); XCTAssertTrue(tags[1].shouldDependOn(other:tags[3])); XCTAssertFalse(tags[0].shouldDependOn(other:tags[1])); XCTAssertFalse(tags[0].shouldDependOn(other:tags[4])); withExtendedLifetime((x,y,z,w)) {} }
}
