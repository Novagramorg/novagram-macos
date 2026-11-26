import Foundation
import XCTest
import SwiftSignalKit

struct StoryId: Hashable { let peerId: Int; let id: Int32 }
struct EngineStoryItem { let id: Int32 }
enum PinError { case generic }
final class Request {
    let peer: Int; let ids: [Int32]
    var subscriber: Subscriber<Never, PinError>?
    var cancelled = false
    init(_ peer: Int, _ ids: [Int32]) { self.peer = peer; self.ids = ids }
    func succeed() { subscriber?.putCompletion() }
    func fail() { subscriber?.putError(.generic) }
}
final class Messages {
    var requests: [Request] = []
    var onStart: ((Request) -> Void)?
    func updatePinnedToTopStories(peerId: Int, ids: [Int32]) -> Signal<Never, PinError> {
        Signal { subscriber in
            let request = Request(peerId, ids); request.subscriber = subscriber; self.requests.append(request); self.onStart?(request)
            return ActionDisposable { request.cancelled = true; request.subscriber = nil }
        }
    }
}
final class Engine { let messages = Messages() }
final class Context { let engine = Engine(); let window = Window() }
final class Window {
    var progress: [MetaDisposable] = []
    var alerts = 0; var texts: [String] = []
}
func alert(for window: Window, info: String) { window.alerts += 1 }
func showModalText(for window: Window, text: String) { window.texts.append(text) }
func showModalProgress<T,E>(signal: Signal<T,E>, for window: Window) -> Signal<T,E> {
    Signal { subscriber in
        let child = MetaDisposable(); window.progress.append(child)
        child.set(signal.start(next: subscriber.putNext, error: { error in subscriber.putError(error); child.dispose() }, completed: { subscriber.putCompletion(); child.dispose() }))
        return child
    }
}
struct Strings {
    let unknownError = "error"
    func storyMediaTooltipPinnedOther(_ count: Int) -> String { "pinned \(count)" }
    func storyMediaTooltipUnpinnedOther(_ count: Int) -> String { "unpinned \(count)" }
    func storyMediaTooltipLimitOther(_ count: Int) -> String { "limit \(count)" }
}
func strings() -> Strings { .init() }
class Controller {
    var onDisappear: (() -> Void)?
    func viewWillDisappear(_ animated: Bool) { onDisappear?() }
    func viewWillAppear(_ animated: Bool) {}
}
struct ListState { var pinnedIds: [Int32] = []; var metadata = "old" }
struct GridState {
    enum Collection { case all; var stableId: Int64 { 0 } }
    var collectionStates: [Int64: ListState] = [0: .init()]
    var selectedCollection: Int64 = 0
    var selected: Set<StoryId>?
    __STATE__
    __MAIN_STATE__
}
final class Grid: Controller {
    let context = Context()
    let peerId = 10
    let stateValue = Atomic(value: GridState())
    let deleteStoriesDisposable = MetaDisposable()
    var deleteStoriesOperationId: UUID?
    var acceptsStoryDeletion = true
    let profileStoriesDisposable = MetaDisposable()
    var profileStoriesOperationId: UUID?
    var acceptsStoryProfileChanges = true
    let pinStoriesDisposable = MetaDisposable()
    var pinStoriesOperationId: UUID?
    var acceptsStoryPinning = true
    let collectionMutationDisposable = MetaDisposable()
    var collectionMutationOperationId: UUID?
    var acceptsCollectionMutation = true
    var collectionMutationGeneration = UUID()
    let collectionsDisposable = MetaDisposable()
    let actionsDisposable = DisposableSet()
    var togglePinned: ((EngineStoryItem) -> Void)?
    var togglePinSelected: (() -> Void)?
    var toggles = 0
    var onUpdate: (() -> Void)?
    func updateState(_ f: (GridState) -> GridState) { _ = stateValue.modify(f); onUpdate?() }
    func toggleSelection() { toggles += 1; updateState { state in var state = state; state.selected = state.selected == nil ? [] : nil; return state } }
    var selected: Set<StoryId>? { stateValue.with { $0.selected } }
    var pins: [Int32] { stateValue.with { $0.state?.pinnedIds ?? [] } }
    func setPins(_ ids: [Int32]) { updateState { state in var state = state; state.collectionStates[0]?.pinnedIds = ids; return state } }
    func select(_ ids: [Int32]?, peer: Int = 10) { updateState { state in var state = state; state.selected = ids.map { Set($0.map { StoryId(peerId: peer, id: $0) }) }; return state } }
    override init() {
        super.init()
        let context = self.context; let peerId = self.peerId; let maxPinLimit = 3
        __HELPER__
        __ACTIONS__
    }
    __DISAPPEAR__
    __APPEAR__
    __DEINIT__
}

final class StoryTopPinUITests: XCTestCase {
    func testProfileChangesAndDeletionBlockSingleAndBulkPinning() {
        for profile in [false,true] {
            let grid = Grid(); grid.select([1])
            if profile { grid.profileStoriesOperationId = UUID() } else { grid.deleteStoriesOperationId = UUID() }
            grid.togglePinned?(.init(id: 1)); grid.togglePinSelected?()
            XCTAssertTrue(grid.context.engine.messages.requests.isEmpty); XCTAssertTrue(grid.context.window.texts.isEmpty)
        }
    }
    func testSinglePinWaitsForAcceptance() {
        let grid = Grid(); grid.togglePinned?(.init(id: 2))
        XCTAssertTrue(grid.context.window.texts.isEmpty); XCTAssertEqual(grid.pins, [])
        grid.context.engine.messages.requests.first?.succeed()
        XCTAssertEqual(grid.context.window.texts, ["pinned 1"]); XCTAssertEqual(grid.pins, [2])
    }
    func testFailureKeepsStateAndAllowsRetry() {
        let grid = Grid(); grid.setPins([1]); grid.togglePinned?(.init(id: 2)); grid.context.engine.messages.requests.first?.fail()
        XCTAssertEqual(grid.pins, [1]); XCTAssertEqual(grid.context.window.alerts, 1); XCTAssertTrue(grid.context.window.texts.isEmpty)
        grid.togglePinned?(.init(id: 2)); XCTAssertEqual(grid.context.engine.messages.requests.count, 2)
    }
    func testBulkPinsPreserveExistingOrder() {
        let grid = Grid(); grid.setPins([3, 1]); grid.select([2]); grid.togglePinSelected?()
        XCTAssertEqual(grid.context.engine.messages.requests.first?.peer, 10); XCTAssertEqual(grid.context.engine.messages.requests.first?.ids, [3, 1, 2])
        XCTAssertEqual(grid.selected?.count, 1); XCTAssertTrue(grid.context.window.texts.isEmpty)
        grid.context.engine.messages.requests.first?.succeed(); XCTAssertEqual(grid.pins, [3, 1, 2]); XCTAssertNil(grid.selected)
    }
    func testBulkFailureDoesNotClearSelection() {
        let grid = Grid(); grid.select([1, 2]); grid.togglePinSelected?(); grid.context.engine.messages.requests.first?.fail()
        XCTAssertEqual(grid.selected?.count, 2); XCTAssertEqual(grid.toggles, 0); XCTAssertTrue(grid.context.window.texts.isEmpty); XCTAssertEqual(grid.context.window.alerts, 1)
    }
    func testBulkLimitCountsExistingPinsAndKeepsSelection() {
        let grid = Grid(); grid.setPins([1, 2]); grid.select([3, 4]); grid.togglePinSelected?()
        XCTAssertTrue(grid.context.engine.messages.requests.isEmpty); XCTAssertEqual(grid.context.window.texts, ["limit 3"]); XCTAssertEqual(grid.selected?.count, 2); XCTAssertEqual(grid.toggles, 0)
    }
    func testOversizedSelectionKeepsSelection() {
        let grid = Grid(); grid.select([1, 2, 3, 4]); grid.togglePinSelected?()
        XCTAssertTrue(grid.context.engine.messages.requests.isEmpty); XCTAssertEqual(grid.selected?.count, 4); XCTAssertEqual(grid.toggles, 0)
    }
    func testSinglePinHonorsLimitButUnpinIsAllowed() {
        let grid = Grid(); grid.setPins([1, 2, 3]); grid.togglePinned?(.init(id: 4))
        XCTAssertTrue(grid.context.engine.messages.requests.isEmpty); XCTAssertEqual(grid.context.window.texts, ["limit 3"])
        grid.togglePinned?(.init(id: 2)); XCTAssertEqual(grid.context.engine.messages.requests.last?.ids, [1, 3])
        grid.context.engine.messages.requests.last?.succeed(); XCTAssertEqual(grid.pins, [1, 3]); XCTAssertEqual(grid.context.window.texts.last, "unpinned 1")
    }
    func testEmptySelectionDoesNotUnpinAll() {
        for selection: [Int32]? in [nil, []] {
            let grid = Grid(); grid.setPins([1]); grid.select(selection); grid.togglePinSelected?()
            XCTAssertTrue(grid.context.engine.messages.requests.isEmpty); XCTAssertEqual(grid.toggles, 0); XCTAssertTrue(grid.context.window.texts.isEmpty)
        }
    }
    func testBulkPinsDoNotDuplicateAlreadyPinnedIds() {
        let grid = Grid(); grid.setPins([3, 1]); grid.select([2, 3]); grid.togglePinSelected?()
        XCTAssertEqual(grid.context.engine.messages.requests.first?.ids, [3, 1, 2])
    }
    func testUnknownListDoesNotReplaceRemotePins() {
        let grid = Grid(); grid.updateState { state in var state = state; state.collectionStates[0] = nil; return state }; grid.select([1])
        grid.togglePinSelected?(); grid.togglePinned?(.init(id: 1)); XCTAssertTrue(grid.context.engine.messages.requests.isEmpty)
    }
    func testForeignPeerSelectionDoesNotPinSameNumericId() {
        let grid = Grid(); grid.select([1], peer: 20); grid.togglePinSelected?()
        XCTAssertTrue(grid.context.engine.messages.requests.isEmpty); XCTAssertEqual(grid.selected?.first?.peerId, 20)
    }
    func testPendingRequestRejectsReentrantActions() {
        let grid = Grid(); grid.context.engine.messages.onStart = { [weak grid] _ in grid?.context.engine.messages.onStart = nil; grid?.togglePinned?(.init(id: 2)) }
        grid.togglePinned?(.init(id: 1)); grid.select([3]); grid.togglePinSelected?()
        XCTAssertEqual(grid.context.engine.messages.requests.count, 1); XCTAssertTrue(grid.context.window.texts.isEmpty)
    }
    func testSuccessPreservesNewSelectionAndLatestMetadata() {
        let grid = Grid(); grid.select([1]); grid.togglePinSelected?(); grid.select([1, 2])
        grid.updateState { state in var state = state; state.collectionStates[0]?.metadata = "new"; return state }
        grid.context.engine.messages.requests.first?.succeed()
        XCTAssertEqual(grid.selected, Set([StoryId(peerId: 10, id: 2)])); XCTAssertEqual(grid.toggles, 0); XCTAssertEqual(grid.stateValue.with { $0.state?.metadata }, "new")
    }
    func testSuccessDoesNotReenterSelectionAfterUserLeaves() {
        let grid = Grid(); grid.select([1]); grid.togglePinSelected?(); grid.select(nil); grid.context.engine.messages.requests.first?.succeed()
        XCTAssertNil(grid.selected); XCTAssertEqual(grid.toggles, 0)
    }
    func testNextPinUsesAcceptedListBeforeContextRefresh() {
        let grid = Grid(); grid.togglePinned?(.init(id: 1)); grid.context.engine.messages.requests.first?.succeed(); grid.togglePinned?(.init(id: 2))
        XCTAssertEqual(grid.context.engine.messages.requests.last?.ids, [1, 2])
    }
    func testDisappearCancelsBeforeSuperclassReentry() {
        let grid = Grid(); grid.togglePinned?(.init(id: 1)); let request = grid.context.engine.messages.requests.first
        grid.onDisappear = { request?.succeed() }; grid.viewWillDisappear(false)
        XCTAssertTrue(request?.cancelled == true); XCTAssertTrue(grid.context.window.texts.isEmpty); XCTAssertEqual(grid.pins, [])
        grid.togglePinned?(.init(id: 2)); XCTAssertEqual(grid.context.engine.messages.requests.count, 1)
    }
    func testReappearanceAllowsNewOperation() {
        let grid = Grid(); grid.togglePinned?(.init(id: 1)); grid.viewWillDisappear(false); grid.viewWillAppear(false); grid.togglePinned?(.init(id: 2))
        grid.context.engine.messages.requests.first?.fail(); grid.context.engine.messages.requests.last?.succeed()
        XCTAssertEqual(grid.context.engine.messages.requests.count, 2); XCTAssertEqual(grid.pins, [2]); XCTAssertEqual(grid.context.window.alerts, 0)
    }
    func testProgressCancellationAllowsRetryWithoutSuccess() {
        let grid = Grid(); grid.togglePinned?(.init(id: 1)); grid.context.window.progress.first?.dispose()
        grid.togglePinned?(.init(id: 2)); XCTAssertEqual(grid.context.engine.messages.requests.count, 2); XCTAssertTrue(grid.context.window.texts.isEmpty)
    }
    func testPendingRequestDoesNotRetainOwner() {
        var grid: Grid? = Grid(); weak var owner = grid; let context = grid!.context
        grid?.togglePinned?(.init(id: 1)); grid = nil
        XCTAssertNil(owner); XCTAssertTrue(context.engine.messages.requests.first?.cancelled == true)
    }
    func testAlbumActionsUseCompleteProfilePinList() {
        let grid = Grid(); grid.setPins([3, 1])
        grid.updateState { state in var state = state; state.collectionStates[9] = .init(pinnedIds: [1]); state.selectedCollection = 9; return state }
        grid.select([2]); grid.togglePinSelected?()
        XCTAssertEqual(grid.context.engine.messages.requests.first?.ids, [3, 1, 2])
        grid.context.engine.messages.requests.first?.succeed()
        XCTAssertEqual(grid.stateValue.with { $0.collectionStates[0]?.pinnedIds }, [3, 1, 2]); XCTAssertEqual(grid.stateValue.with { $0.collectionStates[9]?.pinnedIds }, [3, 1, 2])
        grid.togglePinned?(.init(id: 3)); XCTAssertEqual(grid.context.engine.messages.requests.last?.ids, [1, 2])
    }
    func testReentrantDisappearanceDuringStateUpdateSuppressesToast() {
        let grid = Grid(); grid.togglePinned?(.init(id: 1))
        grid.onUpdate = { [weak grid] in grid?.viewWillDisappear(false) }
        grid.context.engine.messages.requests.first?.succeed()
        XCTAssertTrue(grid.context.window.texts.isEmpty)
    }
    func testSynchronousSuccessReleasesBusyState() {
        let grid = Grid(); grid.context.engine.messages.onStart = { $0.succeed() }
        grid.togglePinned?(.init(id: 1)); grid.togglePinned?(.init(id: 2))
        XCTAssertEqual(grid.context.engine.messages.requests.count, 2); XCTAssertEqual(grid.pins, [1, 2]); XCTAssertNil(grid.pinStoriesOperationId)
    }
}
