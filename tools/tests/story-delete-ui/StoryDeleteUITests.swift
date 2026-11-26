import Foundation
import XCTest
import SwiftSignalKit

typealias PeerId = Int
struct StoryId: Hashable { let peerId: Int; let id: Int32 }
struct EngineStoryItem { let id: Int32 }
struct StoryContentItem { let peerId: Int?; let storyItem: EngineStoryItem }
struct Peer { let id: Int }
struct Slice { let peer: Peer; let item: StoryContentItem; var nextItemId: Int? = 1; var previousItemId: Int? = nil }
struct StoryState { var slice: Slice? }
enum Direction: Equatable { case next, previous }
enum Navigation { case item(Direction) }
final class Stories {
    var stateValue: StoryState? = .init(slice: .init(peer: .init(id: 10), item: .init(peerId: 10, storyItem: .init(id: 1))))
    var navigation: [Direction] = []
    func navigate(navigation: Navigation) { if case let .item(value) = navigation { self.navigation.append(value) } }
}
enum DeleteError { case generic }
final class Request {
    let peer: Int; let ids: [Int32]
    var subscriber: Subscriber<Never, DeleteError>?
    var cancelled = false
    init(_ peer: Int, _ ids: [Int32]) { self.peer = peer; self.ids = ids }
    func succeed() { subscriber?.putCompletion() }
    func fail() { subscriber?.putError(.generic) }
}
final class Messages {
    var requests: [Request] = []
    var onStart: ((Request) -> Void)?
    func deleteStories(peerId: Int, ids: [Int32]) -> Signal<Never, DeleteError> {
        Signal { subscriber in
            let request = Request(peerId, ids); request.subscriber = subscriber; self.requests.append(request); self.onStart?(request)
            return ActionDisposable { request.cancelled = true; request.subscriber = nil }
        }
    }
}
final class Engine { let messages = Messages() }
final class Context { let engine = Engine(); let window = Window() }
final class Window {
    var confirmations: [(Int) -> Void] = []
    var progress: [MetaDisposable] = []
    var alerts = 0; var successes = 0
    var keyUpHandler: (() -> Void)?
    func removeObserver(for object: AnyObject) {}
}
func verifyAlert_button(for window: Window, information: String, ok: String, successHandler: @escaping (Int) -> Void, presentation: Int = 0) { window.confirmations.append(successHandler) }
func alert(for window: Window, info: String) { window.alerts += 1 }
func showModalSuccess(for window: Window, icon: Int, delay: Int) -> Signal<Never, NoError> { window.successes += 1; return .complete() }
func showModalProgress<T,E>(signal: Signal<T,E>, for window: Window) -> Signal<T,E> {
    Signal { subscriber in
        let child = MetaDisposable(); window.progress.append(child)
        child.set(signal.start(next: subscriber.putNext, error: { error in subscriber.putError(error); child.dispose() }, completed: { subscriber.putCompletion(); child.dispose() }))
        return child
    }
}
struct Strings {
    let storyConfirmDelete = "delete"; let modalDelete = "delete"; let unknownError = "error"
    func storyMediaDeleteConfirmOther(_ count: Int) -> String { String(count) }
}
func strings() -> Strings { .init() }
let darkAppearance = 0
struct Theme { struct Icons { let successModalProgress = 1 }; let icons = Icons() }
let theme = Theme()
class Controller {
    var onDisappear: (() -> Void)?
    func viewWillDisappear(_ animated: Bool) { onDisappear?() }
    func viewWillAppear(_ animated: Bool) {}
}
struct View { func animateDisappear(_ id: Int) {} }
final class Viewer: Controller {
    let context = Context(); let stories = Stories(); let genericView = View(); let initialId = 0
    var window: Window? { context.window }
    var closed = false
    var acceptsStoryDeletion = true
    let profileStoryDisposable = MetaDisposable()
    var profileStoryOperationId: UUID?
    var acceptsStoryProfileChanges = true
    var closes = 0
    let deleteStoryDisposable = MetaDisposable()
    var deleteStoryOperationId: UUID?
    var delete: ((StoryContentItem) -> Void)?
    override init() {
        super.init()
        let context = self.context
        __VIEW_DELETE__
        delete = deleteStory
    }
    __VIEW_DISAPPEAR__
    func close() { closed = true; closes += 1; viewWillDisappear(false) }
    deinit { deleteStoryDisposable.dispose() }
}
struct GridState { var selected: Set<StoryId>? = nil }
final class Grid: Controller {
    let collectionMutationDisposable = MetaDisposable()
    var collectionMutationOperationId: UUID?
    var acceptsCollectionMutation = true
    var collectionMutationGeneration = UUID()
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
    var deleteSingle: ((EngineStoryItem) -> Void)?
    var deleteSelected: (() -> Void)?
    var toggles = 0
    func updateState(_ f: (GridState) -> GridState) { _ = stateValue.modify(f) }
    func toggleSelection() { toggles += 1; updateState { state in var state = state; state.selected = state.selected == nil ? [] : nil; return state } }
    var selected: Set<StoryId>? { stateValue.with { $0.selected } }
    func select(_ ids: [Int32]?) { updateState { state in var state = state; state.selected = ids.map { Set($0.map { StoryId(peerId: 10, id: $0) }) }; return state } }
    override init() {
        super.init()
        let context = self.context; let peerId = self.peerId
        __GRID_HELPER__
        __GRID_ACTIONS__
    }
    __GRID_DISAPPEAR__
    __GRID_APPEAR__
    deinit { deleteStoriesDisposable.dispose() }
}

final class StoryDeleteUITests: XCTestCase {
    func testViewerPendingProfileChangePreventsDeleteConfirmation() {
        let viewer = Viewer(); viewer.profileStoryOperationId = UUID(); viewer.delete?(item())
        XCTAssertTrue(viewer.context.window.confirmations.isEmpty); XCTAssertTrue(viewer.context.engine.messages.requests.isEmpty)
    }
    func testViewerProfileChangeStartedAfterConfirmationPreventsDeleteRequest() {
        let viewer = Viewer(); viewer.delete?(item()); viewer.profileStoryOperationId = UUID(); viewer.context.window.confirmations.first?(0)
        XCTAssertTrue(viewer.context.engine.messages.requests.isEmpty)
    }
    func testGridOtherStoryMutationsPreventConfirmedDeletion() {
        for profile in [false,true] {
            let grid = Grid(); grid.deleteSingle?(.init(id: 1))
            if profile { grid.profileStoriesOperationId = UUID() } else { grid.pinStoriesOperationId = UUID() }
            grid.context.window.confirmations.first?(0); XCTAssertTrue(grid.context.engine.messages.requests.isEmpty)
        }
    }
    func testViewerDisappearanceCannotAcceptReentrantConfirmation() {
        let viewer = Viewer(); viewer.delete?(item())
        viewer.onDisappear = { [weak viewer] in viewer?.context.window.confirmations.first?(0) }
        viewer.viewWillDisappear(false)
        XCTAssertTrue(viewer.context.engine.messages.requests.isEmpty)
    }
    func testViewerDisappearanceInvalidatesBeforeReentrantCompletion() {
        let viewer = Viewer(); viewer.delete?(item()); viewer.context.window.confirmations.first?(0)
        viewer.onDisappear = { [weak viewer] in viewer?.context.engine.messages.requests.first?.succeed() }
        viewer.viewWillDisappear(false)
        XCTAssertTrue(viewer.stories.navigation.isEmpty); XCTAssertEqual(viewer.closes, 0)
    }
    func testGridDisappearanceInvalidatesBeforeReentrantCompletion() {
        let grid = Grid(); grid.deleteSingle?(.init(id: 1)); grid.context.window.confirmations.first?(0)
        grid.onDisappear = { [weak grid] in grid?.context.engine.messages.requests.first?.succeed() }
        grid.viewWillDisappear(false)
        XCTAssertEqual(grid.context.window.successes, 0)
    }
    func item(_ peer: Int? = 10, _ id: Int32 = 1) -> StoryContentItem { .init(peerId: peer, storyItem: .init(id: id)) }
    func testConfirmationUsesCapturedPeerAndStoryAfterNavigation() {
        let viewer = Viewer(); viewer.delete?(item())
        viewer.stories.stateValue?.slice = .init(peer: .init(id: 20), item: item(20, 2))
        viewer.context.window.confirmations.first?(0)
        XCTAssertEqual(viewer.context.engine.messages.requests.first?.peer, 10)
        XCTAssertEqual(viewer.context.engine.messages.requests.first?.ids, [1])
        viewer.context.engine.messages.requests.first?.succeed()
        XCTAssertTrue(viewer.stories.navigation.isEmpty); XCTAssertEqual(viewer.closes, 0)
    }
    func testViewerWaitsForAcceptanceBeforeNavigation() {
        let viewer = Viewer(); viewer.delete?(item()); viewer.context.window.confirmations.first?(0)
        XCTAssertTrue(viewer.stories.navigation.isEmpty)
        viewer.context.engine.messages.requests.first?.succeed()
        XCTAssertEqual(viewer.stories.navigation, [.next])
    }
    func testViewerFailureStaysOnStoryAndCanRetry() {
        let viewer = Viewer(); viewer.delete?(item()); viewer.context.window.confirmations.first?(0)
        viewer.context.engine.messages.requests.first?.fail()
        XCTAssertTrue(viewer.stories.navigation.isEmpty); XCTAssertEqual(viewer.closes, 0); XCTAssertEqual(viewer.context.window.alerts, 1)
        viewer.delete?(item()); XCTAssertEqual(viewer.context.window.confirmations.count, 2)
    }
    func testAcceptedDeletionFallsBackToPreviousOrClose() {
        for previous in [false,true] {
            let viewer = Viewer(); viewer.stories.stateValue?.slice?.nextItemId = nil; viewer.stories.stateValue?.slice?.previousItemId = previous ? 1 : nil
            viewer.delete?(item()); viewer.context.window.confirmations.first?(0); viewer.context.engine.messages.requests.first?.succeed()
            XCTAssertEqual(viewer.stories.navigation, previous ? [.previous] : []); XCTAssertEqual(viewer.closes, previous ? 0 : 1)
        }
    }
    func testAutomaticAdvanceBeforeCompletionIsNotRepeated() {
        let viewer = Viewer(); viewer.delete?(item()); viewer.context.window.confirmations.first?(0)
        viewer.stories.stateValue?.slice = .init(peer: .init(id: 10), item: item(10, 2))
        viewer.context.engine.messages.requests.first?.succeed()
        XCTAssertTrue(viewer.stories.navigation.isEmpty)
    }
    func testViewerClosedBeforeConfirmationCannotDelete() {
        let viewer = Viewer(); viewer.delete?(item()); viewer.close(); viewer.context.window.confirmations.first?(0)
        XCTAssertTrue(viewer.context.engine.messages.requests.isEmpty)
    }
    func testViewerClosingCancelsPendingDeleteObservation() {
        let viewer = Viewer(); viewer.delete?(item()); viewer.context.window.confirmations.first?(0); viewer.close()
        XCTAssertTrue(viewer.context.engine.messages.requests.first?.cancelled == true)
        viewer.context.engine.messages.requests.first?.fail(); XCTAssertEqual(viewer.context.window.alerts, 0)
    }
    func testUnknownStoryPeerCannotDeleteCurrentStory() {
        let viewer = Viewer(); viewer.delete?(item(nil)); viewer.context.window.confirmations.first?(0)
        XCTAssertTrue(viewer.context.window.confirmations.isEmpty); XCTAssertTrue(viewer.context.engine.messages.requests.isEmpty)
    }
    func testPendingViewerDeletionCannotStartDuplicateRequest() {
        let viewer = Viewer(); viewer.delete?(item()); viewer.context.window.confirmations.first?(0)
        viewer.context.window.confirmations.first?(0); viewer.delete?(item())
        XCTAssertEqual(viewer.context.engine.messages.requests.count, 1); XCTAssertEqual(viewer.context.window.confirmations.count, 1)
    }
    func testGridSingleSuccessWaitsForAcceptance() {
        let grid = Grid(); grid.deleteSingle?(.init(id: 1)); grid.context.window.confirmations.first?(0)
        XCTAssertEqual(grid.context.window.successes, 0)
        grid.context.engine.messages.requests.first?.succeed(); XCTAssertEqual(grid.context.window.successes, 1)
    }
    func testGridFailureKeepsSelectionAndReportsError() {
        let grid = Grid(); grid.select([1,2]); grid.deleteSelected?(); grid.context.window.confirmations.first?(0)
        grid.context.engine.messages.requests.first?.fail()
        XCTAssertEqual(grid.context.window.successes, 0); XCTAssertEqual(grid.context.window.alerts, 1)
        XCTAssertEqual(grid.selected?.count, 2); XCTAssertEqual(grid.toggles, 0)
    }
    func testGridUsesConfirmedSnapshotAndPreservesNewSelection() {
        let grid = Grid(); grid.select([1,2]); grid.deleteSelected?(); grid.select([2,3]); grid.context.window.confirmations.first?(0)
        XCTAssertEqual(Set(grid.context.engine.messages.requests.first?.ids ?? []), Set([1,2]))
        grid.context.engine.messages.requests.first?.succeed()
        XCTAssertEqual(grid.selected, Set([StoryId(peerId: 10, id: 3)])); XCTAssertEqual(grid.toggles, 0)
    }
    func testGridExitsSelectionOnlyWhenAcceptedDeletionEmptiesIt() {
        let grid = Grid(); grid.select([1,2]); grid.deleteSelected?(); grid.context.window.confirmations.first?(0)
        XCTAssertEqual(grid.toggles, 0); grid.context.engine.messages.requests.first?.succeed()
        XCTAssertNil(grid.selected); XCTAssertEqual(grid.toggles, 1)
    }
    func testGridDoesNotReenterSelectionIfUserAlreadyExited() {
        let grid = Grid(); grid.select([1]); grid.deleteSelected?(); grid.context.window.confirmations.first?(0); grid.select(nil)
        grid.context.engine.messages.requests.first?.succeed()
        XCTAssertNil(grid.selected); XCTAssertEqual(grid.toggles, 0)
    }
    func testEmptySelectionDoesNotOpenConfirmationOrRequest() {
        let grid = Grid(); grid.select([]); grid.deleteSelected?(); grid.context.window.confirmations.first?(0)
        XCTAssertTrue(grid.context.window.confirmations.isEmpty); XCTAssertTrue(grid.context.engine.messages.requests.isEmpty)
    }
    func testGridDisappearanceCancelsPendingAndIgnoresConfirmation() {
        let grid = Grid(); grid.deleteSingle?(.init(id: 1)); grid.context.window.confirmations.first?(0); grid.viewWillDisappear(false)
        XCTAssertTrue(grid.context.engine.messages.requests.first?.cancelled == true)
        grid.context.window.confirmations.first?(0); XCTAssertEqual(grid.context.engine.messages.requests.count, 1)
        grid.context.engine.messages.requests.first?.succeed(); XCTAssertEqual(grid.context.window.successes, 0)
    }
    func testGridCanRetryAfterProgressCancellationAndReappearance() {
        let grid = Grid(); grid.deleteSingle?(.init(id: 1)); grid.context.window.confirmations.first?(0); grid.context.window.progress.last?.dispose()
        grid.context.window.confirmations.first?(0); XCTAssertEqual(grid.context.engine.messages.requests.count, 2)
        grid.viewWillDisappear(false); grid.viewWillAppear(false); grid.context.window.confirmations.first?(0)
        XCTAssertEqual(grid.context.engine.messages.requests.count, 3)
    }
    func testSynchronousDeletionIsNotLeftBusy() {
        let grid = Grid(); grid.context.engine.messages.onStart = { $0.succeed() }
        grid.deleteSingle?(.init(id: 1)); grid.context.window.confirmations.first?(0); grid.context.window.confirmations.first?(0)
        XCTAssertEqual(grid.context.window.successes, 2); XCTAssertEqual(grid.context.engine.messages.requests.count, 2)
    }
    func testViewerReleaseCancelsRequestAndDoesNotRetainController() {
        var viewer: Viewer? = Viewer(); weak var weakViewer = viewer
        viewer?.delete?(item()); viewer?.context.window.confirmations.first?(0)
        let request = viewer?.context.engine.messages.requests.first; viewer = nil
        XCTAssertNil(weakViewer); XCTAssertTrue(request?.cancelled == true)
    }
    func testGridReleaseCancelsRequestAndDoesNotRetainController() {
        var grid: Grid? = Grid(); weak var weakGrid = grid
        grid?.deleteSingle?(.init(id: 1)); grid?.context.window.confirmations.first?(0)
        let request = grid?.context.engine.messages.requests.first; grid = nil
        XCTAssertNil(weakGrid); XCTAssertTrue(request?.cancelled == true)
    }
}
