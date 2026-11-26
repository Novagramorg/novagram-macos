import Foundation
import XCTest
import SwiftSignalKit

struct PeerId: Hashable {
    struct Id: Hashable {
        let value: Int64
        func _internalGetInt64Value() -> Int64 { value }
    }
    let namespace: Int
    let id: Id
}
enum EnginePeer { typealias Id = PeerId }
enum Namespaces { enum Peer { static let CloudUser = 0 } }
protocol Peer { var id: PeerId { get } }
struct Flags: OptionSet {
    let rawValue: Int
    static let isCloseFriend = Flags(rawValue: 1)
    static let unrelated = Flags(rawValue: 2)
}
struct TelegramUser: Peer, Equatable {
    let id: PeerId
    var flags: Flags
    var name = "old"
    func withUpdatedFlags(_ flags: Flags) -> TelegramUser { var result = self; result.flags = flags; return result }
}
struct UnsupportedPeer: Peer { let id: PeerId }
final class Transaction {
    var peers: [PeerId: Peer] = [:]
    var contacts: Set<PeerId> = []
    var writes = 0
    func getContactPeerIds() -> Set<PeerId> { contacts }
    func getPeer(_ id: PeerId) -> Peer? { peers[id] }
}
func updatePeersCustom(transaction: Transaction, peers: [Peer], update: (Peer?, Peer) -> Peer?) {
    for peer in peers { transaction.peers[peer.id] = update(transaction.peers[peer.id], peer) }
    transaction.writes += 1
}
final class Postbox {
    let storage = Transaction()
    var delayNext = false
    var finish: (() -> Void)?
    func transaction<T>(_ f: @escaping (Transaction) -> T) -> Signal<T, NoError> {
        Signal { subscriber in
            let run = { subscriber.putNext(f(self.storage)); subscriber.putCompletion() }
            if self.delayNext {
                self.delayNext = false; self.finish = run
                return ActionDisposable { self.finish = nil }
            }
            run(); return EmptyDisposable
        }
    }
}
struct MTRpcError: Error {}
enum Api {
    enum Bool { case boolTrue, boolFalse }
    enum functions {
        enum contacts { static func editCloseFriends(id: [Int64]) -> [Int64] { id } }
    }
}
final class Request {
    let ids: [Int64]
    var subscriber: Subscriber<Api.Bool, MTRpcError>?
    var cancelled = false
    init(_ ids: [Int64]) { self.ids = ids }
    func succeed(_ value: Api.Bool = .boolTrue) { subscriber?.putNext(value); subscriber?.putCompletion() }
    func fail() { subscriber?.putError(MTRpcError()) }
}
final class Network {
    var requests: [Request] = []
    var onRequest: ((Request) -> Void)?
    func request(_ ids: [Int64]) -> Signal<Api.Bool, MTRpcError> {
        Signal { subscriber in
            let request = Request(ids); request.subscriber = subscriber; self.requests.append(request)
            self.onRequest?(request)
            return ActionDisposable { request.cancelled = true; request.subscriber = nil }
        }
    }
}
final class Account { let postbox = Postbox(); let network = Network() }
__SOURCE__

final class CloseFriendsTests: XCTestCase {
    func id(_ value: Int64, namespace: Int = 0) -> PeerId { .init(namespace: namespace, id: .init(value: value)) }
    func account() -> Account {
        let account = Account()
        account.postbox.storage.contacts = [id(1), id(2)]
        account.postbox.storage.peers[id(1)] = TelegramUser(id: id(1), flags: [.isCloseFriend, .unrelated])
        account.postbox.storage.peers[id(2)] = TelegramUser(id: id(2), flags: [.unrelated])
        return account
    }
    func user(_ account: Account, _ value: Int64) -> TelegramUser? { account.postbox.storage.peers[id(value)] as? TelegramUser }
    func testColdSignalDoesNotRequestOrWrite() {
        let account = account()
        _ = _internal_updateCloseFriends(account: account, peerIds: [id(2)])
        XCTAssertTrue(account.network.requests.isEmpty); XCTAssertEqual(account.postbox.storage.writes, 0)
    }
    func testPendingResponseLeavesFlagsUnchanged() {
        let account = account()
        let operation = _internal_updateCloseFriends(account: account, peerIds: [id(2)]).start()
        XCTAssertTrue(user(account, 1)?.flags.contains(.isCloseFriend) == true)
        XCTAssertFalse(user(account, 2)?.flags.contains(.isCloseFriend) == true)
        XCTAssertEqual(account.postbox.storage.writes, 0)
        operation.dispose()
    }
    func testAcceptedListCommitsBeforeCompletion() {
        let account = account(); var completed = false
        let operation = _internal_updateCloseFriends(account: account, peerIds: [id(2)]).start(completed: {
            completed = true
            XCTAssertEqual(self.user(account, 1)?.flags, [.unrelated])
            XCTAssertEqual(self.user(account, 2)?.flags, [.isCloseFriend, .unrelated])
        })
        account.network.requests.first?.succeed()
        XCTAssertTrue(completed); operation.dispose()
    }
    func testFalseResponseFailsWithoutUpdatingFlags() {
        let account = account(); var failed = false; var completed = false
        let operation = _internal_updateCloseFriends(account: account, peerIds: [id(2)]).start(error: { _ in failed = true }, completed: { completed = true })
        account.network.requests.first?.succeed(.boolFalse)
        XCTAssertTrue(failed); XCTAssertFalse(completed)
        XCTAssertEqual(account.postbox.storage.writes, 0)
        XCTAssertEqual(user(account, 1)?.flags, [.isCloseFriend, .unrelated])
        operation.dispose()
    }
    func testRpcErrorPropagatesInsteadOfIndefiniteRetry() {
        let account = account(); var failed = false
        let operation = _internal_updateCloseFriends(account: account, peerIds: [id(2)]).start(error: { _ in failed = true })
        account.network.requests.first?.fail()
        XCTAssertTrue(failed); XCTAssertEqual(account.postbox.storage.writes, 0)
        operation.dispose()
    }
    func testEmptySelectionClearsListAfterAcceptance() {
        let account = account()
        let operation = _internal_updateCloseFriends(account: account, peerIds: []).start()
        XCTAssertEqual(account.network.requests.first?.ids, [])
        account.network.requests.first?.succeed()
        XCTAssertEqual(user(account, 1)?.flags, [.unrelated]); operation.dispose()
    }
    func testDuplicateUsersAreSentOnceInFirstOccurrenceOrder() {
        let account = account()
        let operation = _internal_updateCloseFriends(account: account, peerIds: [id(2), id(1), id(2)]).start()
        XCTAssertEqual(account.network.requests.first?.ids, [2, 1]); operation.dispose()
    }
    func testWrongNamespaceDoesNotSendCollidingUserId() {
        let account = account(); var failed = false
        let invalid = id(1, namespace: 2)
        account.postbox.storage.contacts.insert(invalid)
        account.postbox.storage.peers[invalid] = TelegramUser(id: invalid, flags: [])
        let operation = _internal_updateCloseFriends(account: account, peerIds: [invalid]).start(error: { _ in failed = true })
        XCTAssertTrue(failed); XCTAssertTrue(account.network.requests.isEmpty); operation.dispose()
    }
    func testMissingSelectedContactDoesNotSendPartialList() {
        let account = account(); var failed = false
        account.postbox.storage.peers.removeValue(forKey: id(2))
        let operation = _internal_updateCloseFriends(account: account, peerIds: [id(1), id(2)]).start(error: { _ in failed = true })
        XCTAssertTrue(failed); XCTAssertTrue(account.network.requests.isEmpty); operation.dispose()
    }
    func testNonContactUserIsRejectedBeforeRequest() {
        let account = account(); var failed = false
        account.postbox.storage.contacts.remove(id(2))
        let operation = _internal_updateCloseFriends(account: account, peerIds: [id(2)]).start(error: { _ in failed = true })
        XCTAssertTrue(failed); XCTAssertTrue(account.network.requests.isEmpty); operation.dispose()
    }
    func testUnsupportedSelectedPeerIsRejected() {
        let account = account(); var failed = false
        account.postbox.storage.peers[id(2)] = UnsupportedPeer(id: id(2))
        let operation = _internal_updateCloseFriends(account: account, peerIds: [id(2)]).start(error: { _ in failed = true })
        XCTAssertTrue(failed); XCTAssertTrue(account.network.requests.isEmpty); operation.dispose()
    }
    func testCancellationBeforeResponsePreventsLocalCommit() {
        let account = account(); var completed = false
        let operation = _internal_updateCloseFriends(account: account, peerIds: [id(2)]).start(completed: { completed = true })
        operation.dispose(); account.network.requests.first?.succeed()
        XCTAssertTrue(account.network.requests.first?.cancelled == true)
        XCTAssertEqual(account.postbox.storage.writes, 0); XCTAssertFalse(completed)
    }
    func testDelayedCommitCanBeCanceled() {
        let account = account()
        let operation = _internal_updateCloseFriends(account: account, peerIds: [id(2)]).start()
        account.postbox.delayNext = true; account.network.requests.first?.succeed()
        XCTAssertNotNil(account.postbox.finish)
        operation.dispose(); account.postbox.finish?()
        XCTAssertNil(account.postbox.finish); XCTAssertEqual(account.postbox.storage.writes, 0)
    }
    func testCommitUsesCurrentContactsAndLatestMetadata() {
        let account = account()
        let operation = _internal_updateCloseFriends(account: account, peerIds: [id(2)]).start()
        account.postbox.storage.peers[id(2)] = TelegramUser(id: id(2), flags: [.unrelated], name: "new")
        account.postbox.storage.contacts.insert(id(3))
        account.postbox.storage.peers[id(3)] = TelegramUser(id: id(3), flags: [.isCloseFriend, .unrelated])
        account.network.requests.first?.succeed()
        XCTAssertEqual(user(account, 2)?.name, "new")
        XCTAssertEqual(user(account, 2)?.flags, [.isCloseFriend, .unrelated])
        XCTAssertEqual(user(account, 3)?.flags, [.unrelated]); operation.dispose()
    }
    func testDeletedContactIsNotResurrected() {
        let account = account()
        let operation = _internal_updateCloseFriends(account: account, peerIds: [id(2)]).start()
        account.postbox.storage.contacts.remove(id(2)); account.postbox.storage.peers.removeValue(forKey: id(2))
        account.network.requests.first?.succeed()
        XCTAssertNil(user(account, 2)); operation.dispose()
    }
    func testSynchronousResponseCompletesAndPreservesOtherFlags() {
        let account = account(); var completed = false
        account.network.onRequest = { $0.succeed() }
        let operation = _internal_updateCloseFriends(account: account, peerIds: [id(2)]).start(completed: { completed = true })
        XCTAssertTrue(completed); XCTAssertEqual(user(account, 2)?.flags, [.isCloseFriend, .unrelated]); operation.dispose()
    }
}
