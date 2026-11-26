import Foundation
import XCTest
import SwiftSignalKit

public typealias PeerId = Int
__MERGE__
struct Peer {
    let id: Int
    var isDeleted = false
    func isEqual(_ peer: Peer) -> Bool { id == peer.id && isDeleted == peer.isDeleted }
}
struct RenderedPeer {
    var peer: Peer?
}
struct BlockedPeersContextState {
    var isLoadingMore = false
    var peers: [RenderedPeer] = []
}
struct ShortPeerDeleting: Equatable { let editable: Bool }
enum GeneralViewType: Equatable { case singleItem, firstItem, innerItem, lastItem }
func bestGeneralViewType(_ list: [RenderedPeer], for peer: RenderedPeer) -> GeneralViewType {
    if list.count == 1 { return .singleItem }
    if peer.peer?.id == list.first?.peer?.id { return .firstItem }
    if peer.peer?.id == list.last?.peer?.id { return .lastItem }
    return .innerItem
}
enum RemoveError { case generic }
final class Window { var alerts = 0 }
func alert(for window: Window, info: String) { window.alerts += 1 }
struct Strings { let unknownError = "error" }
func strings() -> Strings { Strings() }
final class Request {
    let peerId: Int
    var subscriber: Subscriber<Never, RemoveError>?
    var cancelled = false
    var onDispose: (() -> Void)?
    init(peerId: Int) { self.peerId = peerId }
    func finish() { subscriber?.putCompletion() }
    func fail() { subscriber?.putError(.generic) }
}
final class BlockedContext {
    var requests: [Request] = []
    var onStart: ((Request) -> Void)?
    func remove(peerId: Int) -> Signal<Never, RemoveError> {
        Signal { subscriber in
            let request = Request(peerId: peerId)
            request.subscriber = subscriber
            self.requests.append(request)
            self.onStart?(request)
            return ActionDisposable {
                request.cancelled = true
                request.subscriber = nil
                request.onDispose?()
            }
        }
    }
}
final class Context {
    let window = Window()
    let blockedPeersContext = BlockedContext()
}

__PRODUCTION__

final class Controller {
    let context: Context
    init(context: Context = Context()) { self.context = context }
    __FIELDS__
    __METHODS__
    var pending: Set<PeerId> { __PENDING__ }
    var entries: [BlockedPeerEntry] {
        blockedPeersControllerEntries(state: stateValue.with { $0 }, blockedState: .init(peers: (1...3).map { RenderedPeer(peer: Peer(id: $0)) }))
    }
}

final class BlockedPeersUITests: XCTestCase {
    func entries(_ ids: [Int]) -> [BlockedPeerEntry] {
        blockedPeersControllerEntries(state: __STATE__(), blockedState: .init(peers: ids.map { .init(peer: Peer(id: $0)) }))
    }
    func testEntryOrderingRemainsStrictAcrossLongLists() {
        for count in [1, 2, 3, 200, 1005] {
            let entries = entries(Array(1...count))
            XCTAssertTrue(zip(entries, entries.dropFirst()).allSatisfy { $0 < $1 }, "count \(count)")
        }
    }
    func testPaginationPreservesExistingSpacerAndRows() {
        let left = entries([1, 2, 3])
        let right = entries([1, 2, 3, 4, 5])
        let (removed, inserted, updated) = mergeListsStableWithUpdates(leftList: left, rightList: right)
        XCTAssertTrue(removed.isEmpty)
        XCTAssertEqual(inserted.map { $0.1.stableId }, [.peer(4), .peer(5)])
        var applied = left
        for index in removed.reversed() { applied.remove(at: index) }
        for (index, entry, _) in inserted { applied.insert(entry, at: index) }
        for (index, entry, _) in updated { applied[index] = entry }
        XCTAssertEqual(applied, right)
    }
    func testTableTransitionsMatchListsAcrossRemovalAndEmptyStates() {
        let lists = [[], [1], [1, 2, 3, 4], [1, 3, 4], [9, 1, 3, 4], [9, 4], []]
        for (old, new) in zip(lists, lists.dropFirst()) {
            var applied = entries(old)
            let target = entries(new)
            let (removed, inserted, updated) = mergeListsStableWithUpdates(leftList: applied, rightList: target)
            for index in removed.reversed() { applied.remove(at: index) }
            for (index, entry, _) in inserted { applied.insert(entry, at: index) }
            for (index, entry, _) in updated { applied[index] = entry }
            XCTAssertEqual(applied, target)
        }
    }
    func rows(_ entries: [BlockedPeerEntry]) -> [(id: Int, enabled: Bool, editing: Bool, type: GeneralViewType)] {
        entries.compactMap {
            if case let .peerItem(_, _, peer, deleting, enabled, viewType) = $0 { return (peer.id, enabled, deleting != nil, viewType) }
            return nil
        }
    }
    func testDeletedAccountsRemainVisibleAndRemovable() {
        let entries = blockedPeersControllerEntries(state: __STATE__().withUpdatedEditing(true), blockedState: .init(peers: [.init(peer: Peer(id: 1, isDeleted: true))]))
        let items = rows(entries)
        XCTAssertEqual(items.map(\.id), [1])
        XCTAssertEqual(items.map(\.editing), [true])
        XCTAssertEqual(items.map(\.type), [.singleItem])
    }
    func testMissingPeersProduceEmptyRowRatherThanBlankSections() {
        for loading in [false, true] {
            let entries = blockedPeersControllerEntries(state: __STATE__(), blockedState: .init(isLoadingMore: loading, peers: [.init(peer: nil)]))
            XCTAssertEqual(entries.count, 1)
            XCTAssertEqual(entries.first, .empty(loading))
        }
    }
    func testMixedRowsHaveConsistentGrouping() {
        let entries = blockedPeersControllerEntries(state: __STATE__(), blockedState: .init(peers: [.init(peer: nil), .init(peer: Peer(id: 1)), .init(peer: Peer(id: 2, isDeleted: true)), .init(peer: Peer(id: 3))]))
        XCTAssertEqual(rows(entries).map(\.id), [1, 2, 3])
        XCTAssertEqual(rows(entries).map(\.type), [.firstItem, .innerItem, .lastItem])
    }
    func testEmptyLoadingChangeIsNotEqual() {
        XCTAssertNotEqual(BlockedPeerEntry.empty(true), .empty(false))
    }
    func testUnblockRequestsHaveIndependentLifetimes() {
        let controller = Controller()
        controller.removePeer(1)
        controller.removePeer(2)
        XCTAssertEqual(controller.pending, [1, 2])
        XCTAssertEqual(controller.context.blockedPeersContext.requests.map(\.cancelled), [false, false])
        XCTAssertEqual(rows(controller.entries).map(\.enabled), [false, false, true])
    }
    func testDuplicateUnblockDoesNotReplaceRequest() {
        let controller = Controller()
        controller.removePeer(1)
        controller.removePeer(1)
        XCTAssertEqual(controller.context.blockedPeersContext.requests.count, 1)
        XCTAssertFalse(controller.context.blockedPeersContext.requests[0].cancelled)
    }
    func testOutOfOrderCompletionKeepsOtherRowsDisabled() {
        let controller = Controller()
        controller.removePeer(1)
        controller.removePeer(2)
        controller.context.blockedPeersContext.requests[1].finish()
        XCTAssertEqual(controller.pending, [1])
        controller.context.blockedPeersContext.requests[0].finish()
        XCTAssertTrue(controller.pending.isEmpty)
    }
    func testFailureOnlyClearsItsOwnRowAndAllowsRetry() {
        let controller = Controller()
        controller.removePeer(1)
        controller.removePeer(2)
        controller.context.blockedPeersContext.requests[0].fail()
        XCTAssertEqual(controller.pending, [2])
        XCTAssertEqual(controller.context.window.alerts, 1)
        controller.removePeer(1)
        XCTAssertEqual(controller.context.blockedPeersContext.requests.count, 3)
        XCTAssertEqual(controller.pending, [1, 2])
    }
    func testSynchronousCompletionLeavesNoPendingRequest() {
        let controller = Controller()
        controller.context.blockedPeersContext.onStart = { $0.finish() }
        controller.removePeer(1)
        XCTAssertTrue(controller.pending.isEmpty)
        XCTAssertTrue(controller.context.blockedPeersContext.requests[0].cancelled)
        controller.removePeer(1)
        XCTAssertEqual(controller.context.blockedPeersContext.requests.count, 2)
    }
    func testSynchronousFailureClearsStateAndShowsOneError() {
        let controller = Controller()
        controller.context.blockedPeersContext.onStart = { $0.fail() }
        controller.removePeer(1)
        XCTAssertTrue(controller.pending.isEmpty)
        XCTAssertEqual(controller.context.window.alerts, 1)
    }
    func testStateObserverCannotStartDuplicateRequest() {
        let controller = Controller()
        var retry = true
        let subscription = controller.statePromise.get().start(next: { _ in
            if retry, controller.pending.contains(1) {
                retry = false
                controller.removePeer(1)
            }
        })
        controller.removePeer(1)
        XCTAssertEqual(controller.context.blockedPeersContext.requests.count, 1)
        subscription.dispose()
    }
    func testNestedDifferentPeerRequestSurvivesOuterStart() {
        let controller = Controller()
        var start = true
        let subscription = controller.statePromise.get().start(next: { _ in
            if start, controller.pending.contains(1) {
                start = false
                controller.removePeer(2)
            }
        })
        controller.removePeer(1)
        XCTAssertEqual(controller.context.blockedPeersContext.requests.count, 2)
        XCTAssertEqual(controller.context.blockedPeersContext.requests.map(\.cancelled), [false, false])
        XCTAssertEqual(controller.pending, [1, 2])
        subscription.dispose()
    }
    func testCompletionObserverCanRetrySamePeer() {
        let controller = Controller()
        controller.removePeer(1)
        var retry = true
        let subscription = controller.statePromise.get().start(next: { _ in
            if retry, controller.pending.isEmpty {
                retry = false
                controller.removePeer(1)
            }
        })
        controller.context.blockedPeersContext.requests[0].finish()
        XCTAssertEqual(controller.context.blockedPeersContext.requests.count, 2)
        XCTAssertEqual(controller.pending, [1])
        XCTAssertFalse(controller.context.blockedPeersContext.requests[1].cancelled)
        subscription.dispose()
    }
    func testDisposalReentryDoesNotClearNewRequestState() {
        let controller = Controller()
        controller.removePeer(1)
        controller.context.blockedPeersContext.requests[0].onDispose = { [weak controller] in controller?.removePeer(1) }
        controller.context.blockedPeersContext.requests[0].finish()
        XCTAssertEqual(controller.context.blockedPeersContext.requests.count, 2)
        XCTAssertEqual(controller.pending, [1])
        XCTAssertFalse(controller.context.blockedPeersContext.requests[1].cancelled)
    }
    func testClosingScreenCancelsAllPendingRequestsAndReleasesController() {
        let context = Context()
        var controller: Controller? = Controller(context: context)
        controller?.removePeer(1)
        controller?.removePeer(2)
        weak var weakController = controller
        controller = nil
        XCTAssertNil(weakController)
        XCTAssertEqual(context.blockedPeersContext.requests.map(\.cancelled), [true, true])
        context.blockedPeersContext.requests.forEach { $0.fail() }
        XCTAssertEqual(context.window.alerts, 0)
    }
}
