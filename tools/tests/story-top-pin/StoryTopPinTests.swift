import Foundation
import XCTest
import SwiftSignalKit

typealias PeerId = Int
struct Peer { let id: Int }
struct MTRpcError: Error {}
enum Api {
    enum Bool { case boolTrue, boolFalse }
    struct InputPeer { let id: Int }
    enum functions { enum stories {
        static func togglePinnedToTop(peer: InputPeer, id: [Int32]) -> RequestData { .init(peer: peer.id, ids: id) }
    } }
}
struct RequestData { let peer: Int; let ids: [Int32] }
func apiInputPeer(_ peer: Peer) -> Api.InputPeer? { peer.id > 0 ? .init(id: peer.id) : nil }
final class Transaction {
    var peer: Peer? = .init(id: 10)
    func getPeer(_ id: Int) -> Peer? { peer }
}
final class Postbox {
    let storage = Transaction()
    var delayNext = false
    var finish: (() -> Void)?
    var subscriptions = 0
    func transaction<T>(_ f: @escaping (Transaction) -> T) -> Signal<T, NoError> {
        Signal { subscriber in
            self.subscriptions += 1
            let run = { subscriber.putNext(f(self.storage)); subscriber.putCompletion() }
            if self.delayNext {
                self.delayNext = false; self.finish = run
                return ActionDisposable { self.finish = nil }
            }
            run(); return EmptyDisposable
        }
    }
}
final class Request {
    let data: RequestData
    var subscriber: Subscriber<Api.Bool, MTRpcError>?
    var cancelled = false
    init(_ data: RequestData) { self.data = data }
    func succeed(_ value: Api.Bool = .boolTrue) { subscriber?.putNext(value); subscriber?.putCompletion() }
    func fail() { subscriber?.putError(.init()) }
}
final class Network {
    var requests: [Request] = []
    var onRequest: ((Request) -> Void)?
    func request(_ data: RequestData) -> Signal<Api.Bool, MTRpcError> {
        Signal { subscriber in
            let request = Request(data); request.subscriber = subscriber; self.requests.append(request); self.onRequest?(request)
            return ActionDisposable { request.cancelled = true; request.subscriber = nil }
        }
    }
}
enum InternalStoryUpdate: Equatable { case updatePinnedToTopList(peerId: Int, ids: [Int32]) }
final class StateManager {
    var updates: [InternalStoryUpdate] = []
    var onUpdates: (() -> Void)?
    func injectStoryUpdates(updates: [InternalStoryUpdate]) { self.updates += updates; onUpdates?() }
}
final class Account { let postbox = Postbox(); let network = Network(); let stateManager = StateManager() }

__SOURCE__

final class StoryTopPinTests: XCTestCase {
    func drain() {
        let done = expectation(description: "main queue"); DispatchQueue.main.async { done.fulfill() }; wait(for: [done], timeout: 2)
    }
    func testSignalIsCold() {
        let account = Account(); _ = _internal_updatePinnedToTopStories(account: account, peerId: 10, ids: [1])
        drain(); XCTAssertEqual(account.postbox.subscriptions, 0); XCTAssertTrue(account.network.requests.isEmpty); XCTAssertTrue(account.stateManager.updates.isEmpty)
    }
    func testPendingRequestDoesNotPublish() {
        let account = Account(); var complete = false
        let operation = _internal_updatePinnedToTopStories(account: account, peerId: 10, ids: [2, 1]).start(completed: { complete = true })
        drain(); XCTAssertFalse(complete); XCTAssertTrue(account.stateManager.updates.isEmpty)
        XCTAssertEqual(account.network.requests.first?.data.peer, 10); XCTAssertEqual(account.network.requests.first?.data.ids, [2, 1]); operation.dispose()
    }
    func testRpcFailureDoesNotPublishOrComplete() {
        let account = Account(); var errors = 0; var completed = 0
        let operation = _internal_updatePinnedToTopStories(account: account, peerId: 10, ids: [1]).start(error: { _ in errors += 1 }, completed: { completed += 1 })
        account.network.requests.first?.fail(); drain()
        XCTAssertEqual(errors, 1); XCTAssertEqual(completed, 0); XCTAssertTrue(account.stateManager.updates.isEmpty); operation.dispose()
    }
    func testFalseResponseDoesNotPublishOrComplete() {
        let account = Account(); var errors = 0; var completed = 0
        let operation = _internal_updatePinnedToTopStories(account: account, peerId: 10, ids: [1]).start(error: { _ in errors += 1 }, completed: { completed += 1 })
        account.network.requests.first?.succeed(.boolFalse); drain()
        XCTAssertEqual(errors, 1); XCTAssertEqual(completed, 0); XCTAssertTrue(account.stateManager.updates.isEmpty); operation.dispose()
    }
    func testAcceptedStateIsPublishedBeforeCompletion() {
        let account = Account(); var events: [String] = []
        account.stateManager.onUpdates = { XCTAssertTrue(Thread.isMainThread); events.append("update") }
        let operation = _internal_updatePinnedToTopStories(account: account, peerId: 10, ids: [2, 1]).start(completed: { events.append("complete") })
        account.network.requests.first?.succeed(); drain()
        XCTAssertEqual(events, ["update", "complete"]); XCTAssertEqual(account.stateManager.updates, [.updatePinnedToTopList(peerId: 10, ids: [2, 1])]); operation.dispose()
    }
    func testOrderedDuplicateIdsAreNormalized() {
        let account = Account()
        let operation = _internal_updatePinnedToTopStories(account: account, peerId: 10, ids: [2, 1, 2, 3, 1]).start()
        XCTAssertEqual(account.network.requests.first?.data.ids, [2, 1, 3]); account.network.requests.first?.succeed(); drain()
        XCTAssertEqual(account.stateManager.updates, [.updatePinnedToTopList(peerId: 10, ids: [2, 1, 3])]); operation.dispose()
    }
    func testEmptyListUnpinsEverythingOnlyAfterAcceptance() {
        let account = Account(); let operation = _internal_updatePinnedToTopStories(account: account, peerId: 10, ids: []).start()
        drain(); XCTAssertTrue(account.stateManager.updates.isEmpty); XCTAssertEqual(account.network.requests.first?.data.ids, [])
        account.network.requests.first?.succeed(); drain(); XCTAssertEqual(account.stateManager.updates, [.updatePinnedToTopList(peerId: 10, ids: [])]); operation.dispose()
    }
    func testMissingAndUnusablePeersFail() {
        for peer: Peer? in [nil, .init(id: -1)] {
            let account = Account(); account.postbox.storage.peer = peer; var errors = 0; var completed = 0
            let operation = _internal_updatePinnedToTopStories(account: account, peerId: 10, ids: [1]).start(error: { _ in errors += 1 }, completed: { completed += 1 })
            drain(); XCTAssertEqual(errors, 1); XCTAssertEqual(completed, 0); XCTAssertTrue(account.network.requests.isEmpty); XCTAssertTrue(account.stateManager.updates.isEmpty); operation.dispose()
        }
    }
    func testValidationCancellationDoesNotStartRpc() {
        let account = Account(); account.postbox.delayNext = true
        let operation = _internal_updatePinnedToTopStories(account: account, peerId: 10, ids: [1]).start()
        operation.dispose(); account.postbox.finish?(); drain()
        XCTAssertTrue(account.network.requests.isEmpty); XCTAssertTrue(account.stateManager.updates.isEmpty)
    }
    func testRpcCancellationDoesNotPublishLateResult() {
        let account = Account(); var completed = false
        let operation = _internal_updatePinnedToTopStories(account: account, peerId: 10, ids: [1]).start(completed: { completed = true })
        operation.dispose(); account.network.requests.first?.succeed(); drain()
        XCTAssertTrue(account.network.requests.first?.cancelled == true); XCTAssertFalse(completed); XCTAssertTrue(account.stateManager.updates.isEmpty)
    }
    func testSynchronousAcceptanceCompletesOnce() {
        let account = Account(); account.network.onRequest = { $0.succeed() }; var completed = 0
        let operation = _internal_updatePinnedToTopStories(account: account, peerId: 10, ids: [1]).start(completed: { completed += 1 }); drain()
        XCTAssertEqual(completed, 1); XCTAssertEqual(account.stateManager.updates.count, 1); operation.dispose()
    }
    func testCancellationBeforeQueuedAcceptanceDoesNotPublish() {
        let account = Account(); var completed = false
        let operation = _internal_updatePinnedToTopStories(account: account, peerId: 10, ids: [1]).start(completed: { completed = true })
        let sent = DispatchSemaphore(value: 0)
        DispatchQueue.global().async { account.network.requests.first?.succeed(); sent.signal() }
        XCTAssertEqual(sent.wait(timeout: .now() + 2), .success)
        operation.dispose(); drain()
        XCTAssertFalse(completed); XCTAssertTrue(account.stateManager.updates.isEmpty)
    }
    func testBackgroundAcceptancePublishesOnMainBeforeCompletion() {
        let account = Account(); let done = expectation(description: "accepted"); var events: [String] = []
        account.stateManager.onUpdates = { XCTAssertTrue(Thread.isMainThread); events.append("update") }
        let operation = _internal_updatePinnedToTopStories(account: account, peerId: 10, ids: [1]).start(completed: { XCTAssertTrue(Thread.isMainThread); events.append("complete"); done.fulfill() })
        DispatchQueue.global().async { account.network.requests.first?.succeed() }
        wait(for: [done], timeout: 2); XCTAssertEqual(events, ["update", "complete"]); operation.dispose()
    }
}
