import Foundation
import XCTest
import SwiftSignalKit

typealias PeerId = Int
enum EnginePeer { typealias Id = PeerId }
enum Namespaces { enum Peer { static let CloudUser = 0 } }
extension Int { var namespace: Int { self < 10000 ? 0 : 1 } }
struct Peer: Equatable {
    let id: Int
    var version = 0
    var valid = true
}
struct RenderedPeer: Equatable {
    let peer: Peer
    var peerId: Int { peer.id }
}
protocol CachedPeerData {}
struct CachedUserData: CachedPeerData {
    struct Flags: OptionSet {
        let rawValue: Int
        static let isBlockedFromStories = Flags(rawValue: 1)
        static let other = Flags(rawValue: 2)
    }
    var flags: Flags = []
    var isBlocked = false
    func withUpdatedFlags(_ value: Flags) -> CachedUserData { var copy = self; copy.flags = value; return copy }
    func withUpdatedIsBlocked(_ value: Bool) -> CachedUserData { var copy = self; copy.isBlocked = value; return copy }
}
struct MTRpcError: Error { let errorDescription: String }
enum Api {
    typealias Chat = Peer
    typealias User = Peer
    struct InputPeer { let id: Int }
    struct PeerId { let peerId: Int }
    struct PeerBlockedData { let peerId: PeerId }
    enum PeerBlocked { case peerBlocked(PeerBlockedData) }
    struct BlockedData { let blocked: [PeerBlocked]; let chats: [Chat]; let users: [User] }
    struct BlockedSliceData { let count: Int32; let blocked: [PeerBlocked]; let chats: [Chat]; let users: [User] }
    enum Bool { case boolTrue, boolFalse }
    enum contacts { enum Blocked { case blocked(BlockedData), blockedSlice(BlockedSliceData) } }
    enum functions {
        enum contacts {
            static func getBlocked(flags: Int32, offset: Int32, limit: Int32) -> PageRequest { .init(flags: flags, offset: offset, limit: limit) }
            static func block(flags: Int32, id: InputPeer) -> MutationRequest { .init(kind: "add", flags: flags, ids: [id.id], limit: 0) }
            static func unblock(flags: Int32, id: InputPeer) -> MutationRequest { .init(kind: "remove", flags: flags, ids: [id.id], limit: 0) }
            static func setBlocked(flags: Int32, id: [InputPeer], limit: Int32) -> MutationRequest { .init(kind: "set", flags: flags, ids: id.map(\.id), limit: limit) }
        }
    }
}
func apiInputPeer(_ peer: Peer) -> Api.InputPeer? { peer.valid ? .init(id: peer.id) : nil }
final class Transaction {
    var peers: [Int: Peer] = [:]
    var cached: [Int: CachedPeerData] = [:]
    func getPeer(_ id: Int) -> Peer? { peers[id] }
    func updatePeerCachedData(peerIds: Set<Int>, update: (Int, CachedPeerData?) -> CachedPeerData?) {
        for id in peerIds { cached[id] = update(id, cached[id]) }
    }
}
struct AccumulatedPeers {
    let peers: [Peer]
    init(transaction: Transaction, chats: [Api.Chat], users: [Api.User]) { peers = chats + users }
}
func updatePeers(transaction: Transaction, accountPeerId: Int, peers: AccumulatedPeers) {
    for peer in peers.peers { transaction.peers[peer.id] = peer }
}
final class Postbox {
    let storage = Transaction()
    var delayNext = false
    var finish: (() -> Void)?
    func transaction<T>(_ f: @escaping (Transaction) -> T) -> Signal<T, NoError> {
        Signal { subscriber in
            let perform = { subscriber.putNext(f(self.storage)); subscriber.putCompletion() }
            if self.delayNext {
                self.delayNext = false
                self.finish = perform
                return ActionDisposable { self.finish = nil }
            }
            perform()
            return EmptyDisposable
        }
    }
}
struct PageRequest { let flags: Int32; let offset: Int32; let limit: Int32 }
struct MutationRequest { let kind: String; let flags: Int32; let ids: [Int]; let limit: Int32 }
final class PendingPage {
    let request: PageRequest
    var subscriber: Subscriber<Api.contacts.Blocked, MTRpcError>?
    var cancelled = false
    init(_ request: PageRequest) { self.request = request }
    func send(_ ids: [Int], count: Int32? = nil, missing: Set<Int> = [], version: Int = 0) {
        let peers = ids.filter { !missing.contains($0) }.map { Peer(id: $0, version: version) }
        let blocked = ids.map { Api.PeerBlocked.peerBlocked(.init(peerId: .init(peerId: $0))) }
        if let count {
            subscriber?.putNext(.blockedSlice(.init(count: count, blocked: blocked, chats: [], users: peers)))
        } else {
            subscriber?.putNext(.blocked(.init(blocked: blocked, chats: [], users: peers)))
        }
        subscriber?.putCompletion()
    }
    func frozen() { subscriber?.putError(.init(errorDescription: "FROZEN_METHOD_INVALID")) }
    func finishEmpty() { subscriber?.putCompletion() }
}
final class PendingMutation {
    let request: MutationRequest
    var subscriber: Subscriber<Api.Bool, MTRpcError>?
    var cancelled = false
    init(_ request: MutationRequest) { self.request = request }
    func succeed(_ accepted: Bool = true) { subscriber?.putNext(accepted ? .boolTrue : .boolFalse); subscriber?.putCompletion() }
    func fail() { subscriber?.putError(.init(errorDescription: "ERROR")) }
}
final class Network {
    var pages: [PendingPage] = []
    var mutations: [PendingMutation] = []
    var onPageStart: ((PendingPage) -> Void)?
    var onMutationStart: ((PendingMutation) -> Void)?
    func request(_ request: PageRequest) -> Signal<Api.contacts.Blocked, MTRpcError> {
        Signal { subscriber in
            let pending = PendingPage(request)
            pending.subscriber = subscriber
            self.pages.append(pending)
            self.onPageStart?(pending)
            return ActionDisposable { pending.cancelled = true; pending.subscriber = nil }
        }
    }
    func request(_ request: MutationRequest) -> Signal<Api.Bool, MTRpcError> {
        Signal { subscriber in
            let pending = PendingMutation(request)
            pending.subscriber = subscriber
            self.mutations.append(pending)
            self.onMutationStart?(pending)
            return ActionDisposable { pending.cancelled = true; pending.subscriber = nil }
        }
    }
}
final class Account {
    let postbox = Postbox()
    let network = Network()
    let peerId = 0
}

__RETRY__
__CONTEXT__

final class StateBox {
    var value = BlockedPeersContextState(isLoadingMore: false, canLoadMore: true, totalCount: nil, peers: [])
    var ids: [Int] { value.peers.map(\.peerId) }
}
final class Rig {
    let account = Account()
    let context: BlockedPeersContext
    let state = StateBox()
    let subscription: Disposable
    init(subject: BlockedPeersContext.Subject = .blocked) {
        context = BlockedPeersContext(account: account, subject: subject)
        let state = self.state
        subscription = context.state.start(next: { state.value = $0 })
    }
    deinit { subscription.dispose() }
    func peer(_ id: Int, blocked: Bool = false) {
        account.postbox.storage.peers[id] = Peer(id: id)
        account.postbox.storage.cached[id] = CachedUserData(isBlocked: blocked)
    }
    func cached(_ id: Int) -> CachedUserData? { account.postbox.storage.cached[id] as? CachedUserData }
}

final class BlockedPeersCoreTests: XCTestCase {
    func testBulkReplacementClearsPeerAddedSinceSignalCreation() {
        let rig = Rig()
        rig.account.network.pages[0].send([1])
        rig.peer(2)
        let bulk = rig.context.updatePeerIds([1])
        let add = rig.context.add(peerId: 2).start()
        rig.account.network.mutations[0].succeed()
        XCTAssertEqual(rig.cached(2)?.isBlocked, true)
        let replace = bulk.start()
        rig.account.network.mutations[1].succeed()
        XCTAssertEqual(rig.cached(2)?.isBlocked, false)
        XCTAssertEqual(rig.state.ids, [1])
        add.dispose(); replace.dispose()
    }
    func testMutationCancelsPendingPageTransaction() {
        let rig = Rig()
        rig.peer(2)
        rig.account.postbox.delayNext = true
        rig.account.network.pages[0].send([1])
        XCTAssertNotNil(rig.account.postbox.finish)
        let add = rig.context.add(peerId: 2).start()
        rig.account.network.mutations[0].succeed()
        XCTAssertNil(rig.account.postbox.finish)
        XCTAssertEqual(rig.state.ids, [2])
        add.dispose()
    }
    func testIndependentMutationResultsReplaceObsoleteRefreshes() {
        let rig = Rig()
        rig.account.network.pages[0].send([1, 2, 3], count: 6)
        let first = rig.context.remove(peerId: 1).start()
        let second = rig.context.remove(peerId: 2).start()
        rig.account.network.mutations[1].succeed()
        XCTAssertEqual(rig.state.ids, [1, 3])
        rig.account.network.mutations[0].succeed()
        XCTAssertEqual(rig.state.ids, [3])
        XCTAssertEqual(rig.account.network.pages.count, 3)
        if rig.account.network.pages.count == 3 {
            XCTAssertTrue(rig.account.network.pages[1].cancelled)
            rig.account.network.pages[1].send([1, 3])
            XCTAssertEqual(rig.state.ids, [3])
            rig.account.network.pages[2].send([3, 4, 5, 6])
            XCTAssertEqual(rig.state.ids, [3, 4, 5, 6])
        }
        first.dispose(); second.dispose()
    }
    func testCancelledBulkOperationDoesNotCommitPrivacyFlags() {
        let rig = Rig()
        rig.account.network.pages[0].send([1])
        rig.peer(1, blocked: true)
        rig.peer(2)
        let bulk = rig.context.updatePeerIds([2]).start()
        bulk.dispose()
        rig.account.network.mutations[0].succeed()
        XCTAssertEqual(rig.cached(1)?.isBlocked, true)
        XCTAssertEqual(rig.cached(2)?.isBlocked, false)
        XCTAssertEqual(rig.state.ids, [1])
    }
    func testBulkOperationDoesNotRetainClosedContext() {
        let account = Account()
        account.postbox.storage.peers[1] = Peer(id: 1)
        var context: BlockedPeersContext? = BlockedPeersContext(account: account, subject: .stories)
        let operation = context!.updatePeerIds([1]).start()
        weak var weakContext = context
        context = nil
        XCTAssertNil(weakContext)
        account.network.mutations[0].succeed()
        XCTAssertEqual((account.postbox.storage.cached[1] as? CachedUserData)?.flags, .isBlockedFromStories)
        operation.dispose()
    }
    func testFailedRefreshAfterMutationKeepsCommittedRows() {
        let rig = Rig()
        rig.account.network.pages[0].send([1, 2])
        let remove = rig.context.remove(peerId: 1).start()
        rig.account.network.mutations[0].succeed()
        if rig.account.network.pages.count == 2 { rig.account.network.pages[1].finishEmpty() }
        XCTAssertEqual(rig.state.ids, [2])
        XCTAssertFalse(rig.state.value.isLoadingMore)
        XCTAssertTrue(rig.state.value.canLoadMore)
        rig.context.loadMore()
        XCTAssertEqual(rig.account.network.pages.last?.request.offset, 0)
        remove.dispose()
    }
    func testInitialLoadingUsesSubjectAndFirstPageLimit() {
        for stories in [false, true] {
            let rig = Rig(subject: stories ? .stories : .blocked)
            XCTAssertTrue(rig.state.value.isLoadingMore)
            let request = rig.account.network.pages[0].request
            XCTAssertEqual(request.flags, stories ? 1 : 0)
            XCTAssertEqual(request.offset, 0)
            XCTAssertEqual(request.limit, 200)
            rig.context.loadMore()
            XCTAssertEqual(rig.account.network.pages.count, 1)
        }
    }
    func testRawOffsetIncludesMissingAndDuplicatePeers() {
        let rig = Rig()
        rig.account.network.pages[0].send([1, 1, 2, 3], count: 8, missing: [2])
        XCTAssertEqual(rig.state.ids, [1, 3])
        rig.context.loadMore()
        XCTAssertEqual(rig.account.network.pages[1].request.offset, 4)
        XCTAssertEqual(rig.account.network.pages[1].request.limit, 100)
    }
    func testAllUnrenderablePageStillAdvancesOffsetAndLimit() {
        let rig = Rig()
        rig.account.network.pages[0].send([1, 2], count: 4, missing: [1, 2])
        rig.context.loadMore()
        XCTAssertEqual(rig.account.network.pages[1].request.offset, 2)
        XCTAssertEqual(rig.account.network.pages[1].request.limit, 100)
    }
    func testOverlappingPageRefreshesPeerMetadata() {
        let rig = Rig()
        rig.account.network.pages[0].send([1, 2], count: 5)
        rig.context.loadMore()
        rig.account.network.pages[1].send([2, 3], count: 5, version: 9)
        XCTAssertEqual(rig.state.ids, [1, 2, 3])
        XCTAssertEqual(rig.state.value.peers[1].peer.version, 9)
        rig.context.loadMore()
        XCTAssertEqual(rig.account.network.pages.last?.request.offset, 4)
    }
    func testFinalSliceStopsAtServerCount() {
        let rig = Rig()
        rig.account.network.pages[0].send([1, 2], count: 2)
        XCTAssertFalse(rig.state.value.canLoadMore)
        rig.context.loadMore()
        XCTAssertEqual(rig.account.network.pages.count, 1)
    }
    func testEmptySliceStopsEvenWithStalePositiveCount() {
        let rig = Rig()
        rig.account.network.pages[0].send([], count: 5)
        XCTAssertFalse(rig.state.value.canLoadMore)
        XCTAssertEqual(rig.state.value.totalCount, 5)
        rig.context.loadMore()
        XCTAssertEqual(rig.account.network.pages.count, 1)
    }
    func testCompleteResponseCountIncludesUnrenderableEntries() {
        let rig = Rig()
        rig.account.network.pages[0].send([1, 2], missing: [2])
        XCTAssertEqual(rig.state.ids, [1])
        XCTAssertEqual(rig.state.value.totalCount, 2)
        XCTAssertFalse(rig.state.value.canLoadMore)
    }
    func testNegativeCountCannotFallBelowVisiblePeers() {
        let rig = Rig()
        rig.account.network.pages[0].send([1], count: -1)
        XCTAssertEqual(rig.state.value.totalCount, 1)
        XCTAssertFalse(rig.state.value.canLoadMore)
    }
    func testEmptyCompletionAllowsRetryAtSameOffset() {
        let rig = Rig()
        rig.account.network.pages[0].send([1, 1, 2], count: 5)
        rig.context.loadMore()
        rig.account.network.pages[1].finishEmpty()
        XCTAssertFalse(rig.state.value.isLoadingMore)
        rig.context.loadMore()
        XCTAssertEqual(rig.account.network.pages.map { $0.request.offset }, [0, 3, 3])
    }
    func testFrozenRequestPreservesRowsAndKnownCount() {
        let rig = Rig()
        rig.account.network.pages[0].send([1], count: 5)
        rig.context.loadMore()
        rig.account.network.pages[1].frozen()
        XCTAssertFalse(rig.state.value.isLoadingMore)
        XCTAssertFalse(rig.state.value.canLoadMore)
        XCTAssertEqual(rig.state.ids, [1])
        XCTAssertEqual(rig.state.value.totalCount, 5)
    }
    func testReadyObserverCanStartNextPageWithoutCancellation() {
        let rig = Rig()
        var advance = true
        let subscription = rig.context.state.start(next: { state in
            if advance, !state.isLoadingMore, state.canLoadMore {
                advance = false
                rig.context.loadMore()
            }
        })
        rig.account.network.pages[0].send([1, 1], count: 4)
        XCTAssertEqual(rig.account.network.pages.count, 2)
        XCTAssertEqual(rig.account.network.pages[1].request.offset, 2)
        XCTAssertFalse(rig.account.network.pages[1].cancelled)
        subscription.dispose()
    }
    func testPageSubscriptionIsReleasedWithContext() {
        let account = Account()
        var context: BlockedPeersContext? = BlockedPeersContext(account: account, subject: .blocked)
        weak var weakContext = context
        context = nil
        XCTAssertNil(weakContext)
        XCTAssertTrue(account.network.pages[0].cancelled)
    }
    func testPendingPageTransactionIsCancelledWithContext() {
        let account = Account()
        var context: BlockedPeersContext? = BlockedPeersContext(account: account, subject: .blocked)
        account.postbox.delayNext = true
        account.network.pages[0].send([1])
        XCTAssertNotNil(account.postbox.finish)
        weak var weakContext = context
        context = nil
        XCTAssertNil(weakContext)
        XCTAssertNil(account.postbox.finish)
    }
    func testRejectedAddDoesNotChangeCacheOrList() {
        for failure in [false, true] {
            let rig = Rig()
            rig.account.network.pages[0].send([])
            rig.peer(1)
            var failed = false
            let operation = rig.context.add(peerId: 1).start(error: { _ in failed = true })
            if failure { rig.account.network.mutations[0].fail() } else { rig.account.network.mutations[0].succeed(false) }
            XCTAssertTrue(failed)
            XCTAssertEqual(rig.cached(1)?.isBlocked, false)
            XCTAssertTrue(rig.state.ids.isEmpty)
            operation.dispose()
        }
    }
    func testRejectedRemoveDoesNotChangeCacheOrList() {
        for failure in [false, true] {
            let rig = Rig()
            rig.peer(1, blocked: true)
            rig.account.network.pages[0].send([1])
            var failed = false
            let operation = rig.context.remove(peerId: 1).start(error: { _ in failed = true })
            if failure { rig.account.network.mutations[0].fail() } else { rig.account.network.mutations[0].succeed(false) }
            XCTAssertTrue(failed)
            XCTAssertEqual(rig.cached(1)?.isBlocked, true)
            XCTAssertEqual(rig.state.ids, [1])
            operation.dispose()
        }
    }
    func testConfirmedAddCancelsInitialPageAndRefreshesFromZero() {
        let rig = Rig()
        rig.peer(2)
        let operation = rig.context.add(peerId: 2).start()
        XCTAssertFalse(rig.account.network.pages[0].cancelled)
        rig.account.network.mutations[0].succeed()
        XCTAssertTrue(rig.account.network.pages[0].cancelled)
        XCTAssertEqual(rig.cached(2)?.isBlocked, true)
        XCTAssertEqual(rig.state.ids, [2])
        XCTAssertEqual(rig.account.network.pages.count, 2)
        rig.account.network.pages[0].send([1])
        if rig.account.network.pages.count == 2 { rig.account.network.pages[1].send([2, 1]) }
        XCTAssertEqual(rig.state.ids, [2, 1])
        operation.dispose()
    }
    func testConfirmedRemoveCannotBeReinsertedByOldPage() {
        let rig = Rig()
        rig.peer(1, blocked: true)
        rig.account.network.pages[0].send([1, 2], count: 4)
        rig.context.loadMore()
        let operation = rig.context.remove(peerId: 1).start()
        rig.account.network.mutations[0].succeed()
        XCTAssertTrue(rig.account.network.pages[1].cancelled)
        XCTAssertEqual(rig.cached(1)?.isBlocked, false)
        rig.account.network.pages[1].send([1, 3])
        XCTAssertEqual(rig.state.ids, [2])
        XCTAssertEqual(rig.account.network.pages.last?.request.offset, 0)
        if rig.account.network.pages.count == 3 { rig.account.network.pages[2].send([2, 3, 4]) }
        XCTAssertEqual(rig.state.ids, [2, 3, 4])
        operation.dispose()
    }
    func testRepeatedAddDoesNotInflateCount() {
        let rig = Rig()
        rig.account.network.pages[0].send([1, 2])
        let operation = rig.context.add(peerId: 1).start()
        rig.account.network.mutations[0].succeed()
        XCTAssertEqual(rig.state.value.totalCount, 2)
        XCTAssertEqual(rig.state.ids, [1, 2])
        operation.dispose()
    }
    func testRepeatedRemovalDoesNotDecreaseCountTwice() {
        let rig = Rig()
        rig.account.network.pages[0].send([1, 2])
        let first = rig.context.remove(peerId: 1).start()
        let second = rig.context.remove(peerId: 1).start()
        rig.account.network.mutations[0].succeed()
        rig.account.network.mutations[1].succeed()
        XCTAssertEqual(rig.state.value.totalCount, 1)
        XCTAssertEqual(rig.state.ids, [2])
        first.dispose(); second.dispose()
    }
    func testStoryMutationsPreserveMainBlockAndOtherFlags() {
        let rig = Rig(subject: .stories)
        rig.account.network.pages[0].send([])
        rig.peer(1, blocked: true)
        rig.account.postbox.storage.cached[1] = CachedUserData(flags: .other, isBlocked: true)
        let add = rig.context.add(peerId: 1).start()
        XCTAssertEqual(rig.account.network.mutations[0].request.flags, 1)
        rig.account.network.mutations[0].succeed()
        XCTAssertEqual(rig.cached(1)?.flags, [.other, .isBlockedFromStories])
        XCTAssertEqual(rig.cached(1)?.isBlocked, true)
        let remove = rig.context.remove(peerId: 1).start()
        rig.account.network.mutations[1].succeed()
        XCTAssertEqual(rig.cached(1)?.flags, .other)
        XCTAssertEqual(rig.cached(1)?.isBlocked, true)
        add.dispose(); remove.dispose()
    }
    func testLoadingObserverMutationSupersedesOuterPage() {
        let rig = Rig()
        rig.account.network.pages[0].send([1], count: 4)
        rig.peer(2)
        rig.account.network.onMutationStart = { $0.succeed() }
        var mutate = true
        var operation: Disposable?
        let subscription = rig.context.state.start(next: { state in
            if mutate, state.isLoadingMore {
                mutate = false
                operation = rig.context.add(peerId: 2).start()
            }
        })
        rig.context.loadMore()
        XCTAssertEqual(rig.account.network.pages.count, 2)
        XCTAssertEqual(rig.account.network.pages.last?.request.offset, 0)
        XCTAssertFalse(rig.account.network.pages.last!.cancelled)
        XCTAssertEqual(rig.state.ids, [2, 1])
        operation?.dispose(); subscription.dispose()
    }
    func testMutationObserverLoadMoreDoesNotStartDuplicateRefresh() {
        let rig = Rig()
        rig.account.network.pages[0].send([1])
        rig.peer(2)
        let subscription = rig.context.state.start(next: { state in
            if !state.isLoadingMore, state.canLoadMore { rig.context.loadMore() }
        })
        let operation = rig.context.add(peerId: 2).start()
        rig.account.network.mutations[0].succeed()
        XCTAssertEqual(rig.account.network.pages.count, 2)
        XCTAssertFalse(rig.account.network.pages.last!.cancelled)
        subscription.dispose(); operation.dispose()
    }
    func testBulkRejectionDoesNotCommitLocalPrivacyChanges() {
        for failure in [false, true] {
            let rig = Rig(subject: .stories)
            rig.account.network.pages[0].send([1])
            rig.peer(2)
            rig.account.postbox.storage.cached[1] = CachedUserData(flags: .isBlockedFromStories)
            var failed = false
            let operation = rig.context.updatePeerIds([2]).start(error: { _ in failed = true })
            XCTAssertEqual(rig.state.ids, [1])
            XCTAssertEqual(rig.cached(1)?.flags, .isBlockedFromStories)
            XCTAssertEqual(rig.cached(2)?.flags, [])
            if failure { rig.account.network.mutations[0].fail() } else { rig.account.network.mutations[0].succeed(false) }
            XCTAssertTrue(failed)
            XCTAssertEqual(rig.cached(1)?.flags, .isBlockedFromStories)
            XCTAssertEqual(rig.cached(2)?.flags, [])
            operation.dispose()
        }
    }
    func testBulkReplacementDeduplicatesAndUsesRequestedLength() {
        let rig = Rig(subject: .stories)
        rig.account.network.pages[0].send([1, 2, 3, 4])
        let operation = rig.context.updatePeerIds([3, 3]).start()
        let request = rig.account.network.mutations[0].request
        XCTAssertEqual(request.flags, 1)
        XCTAssertEqual(request.ids, [3])
        XCTAssertEqual(request.limit, 1)
        rig.account.network.mutations[0].succeed()
        XCTAssertEqual(rig.state.ids, [3])
        XCTAssertEqual(rig.cached(3)?.flags, .isBlockedFromStories)
        XCTAssertEqual(rig.state.value.totalCount, 1)
        XCTAssertEqual(rig.account.network.pages.last?.request.offset, 0)
        operation.dispose()
    }
    func testBulkMissingOrInvalidPeerFailsWithoutSendingPartialList() {
        for missing in [false, true] {
            let rig = Rig()
            rig.account.network.pages[0].send([1])
            if !missing { rig.account.postbox.storage.peers[2] = Peer(id: 2, valid: false) }
            var failed = false
            let operation = rig.context.updatePeerIds([1, 2]).start(error: { _ in failed = true })
            XCTAssertTrue(failed)
            XCTAssertTrue(rig.account.network.mutations.isEmpty)
            XCTAssertEqual(rig.state.ids, [1])
            operation.dispose()
        }
    }
    func testBulkEmptyListUsesZeroLimitAndClearsAfterAcceptance() {
        let rig = Rig()
        rig.account.network.pages[0].send([1, 2])
        let operation = rig.context.updatePeerIds([]).start()
        XCTAssertEqual(rig.state.ids, [1, 2])
        XCTAssertEqual(rig.account.network.mutations[0].request.limit, 0)
        rig.account.network.mutations[0].succeed()
        XCTAssertTrue(rig.state.ids.isEmpty)
        XCTAssertEqual(rig.state.value.totalCount, 0)
        XCTAssertEqual(rig.cached(1)?.isBlocked, false)
        operation.dispose()
    }
    func testCancelledMutationLeavesCacheUntouched() {
        let rig = Rig()
        rig.account.network.pages[0].send([])
        rig.peer(1)
        let operation = rig.context.add(peerId: 1).start()
        operation.dispose()
        rig.account.network.mutations[0].succeed()
        XCTAssertTrue(rig.account.network.mutations[0].cancelled)
        XCTAssertEqual(rig.cached(1)?.isBlocked, false)
        XCTAssertTrue(rig.state.ids.isEmpty)
    }
    func testMutationDoesNotRetainClosedContext() {
        let account = Account()
        account.postbox.storage.peers[1] = Peer(id: 1)
        var context: BlockedPeersContext? = BlockedPeersContext(account: account, subject: .blocked)
        let operation = context!.add(peerId: 1).start()
        weak var weakContext = context
        context = nil
        XCTAssertNil(weakContext)
        account.network.mutations[0].succeed()
        XCTAssertEqual((account.postbox.storage.cached[1] as? CachedUserData)?.isBlocked, true)
        operation.dispose()
    }
}
