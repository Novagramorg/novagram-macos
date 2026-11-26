import Foundation
import XCTest
import SwiftSignalKit

typealias PeerId = Int
extension Int { var namespace: Int { self == 20 ? 2 : 1 } }
enum Namespaces { enum Peer { static let CloudChannel = 2 } }
struct StoryId: Hashable { let peerId: Int; let id: Int32 }
struct EngineStoryItem { let id: Int32; var isPinned = true }
struct Peer: Equatable { let id: Int; func _asPeer() -> Peer { self } }
struct StoryContentItem { let peerId: Int?; let storyItem: EngineStoryItem; var peer: Peer? { peerId.map { Peer(id: $0) } } }
struct Slice { let peer: Peer; let item: StoryContentItem }
struct StoryState { var slice: Slice? }
final class Stories { var stateValue: StoryState? = .init(slice: .init(peer: .init(id: 10), item: .init(peerId: 10, storyItem: .init(id: 1)))) }
enum ProfileError { case generic }
final class Request {
    let peer: Int; let ids: [Int32: EngineStoryItem]; let pinned: Bool
    var subscriber: Subscriber<Never, ProfileError>?
    var cancelled = false
    init(_ peer: Int, _ ids: [Int32: EngineStoryItem], _ pinned: Bool) { self.peer = peer; self.ids = ids; self.pinned = pinned }
    func succeed() { subscriber?.putCompletion() }
    func fail() { subscriber?.putError(.generic) }
}
final class Messages {
    var requests: [Request] = []
    var onStart: ((Request) -> Void)?
    func updateStoriesArePinned(peerId: Int, ids: [Int32: EngineStoryItem], isPinned: Bool) -> Signal<Never, ProfileError> {
        Signal { subscriber in
            let request = Request(peerId, ids, isPinned); request.subscriber = subscriber; self.requests.append(request); self.onStart?(request)
            return ActionDisposable { request.cancelled = true; request.subscriber = nil }
        }
    }
}
final class Engine { let messages = Messages() }
final class Context { let engine = Engine(); let window = Window() }
final class Window {
    var progress: [MetaDisposable] = []
    var alerts = 0; var texts: [String] = []; var titles: [String?] = []
    var keyUpHandler: (() -> Void)?
    func removeObserver(for object: AnyObject) {}
}
func alert(for window: Window, info: String) { window.alerts += 1 }
func showModalText(for window: Window, text: String, title: String? = nil) { window.texts.append(text); window.titles.append(title) }
func showModalProgress<T,E>(signal: Signal<T,E>, for window: Window) -> Signal<T,E> {
    Signal { subscriber in
        let child = MetaDisposable(); window.progress.append(child)
        child.set(signal.start(next: subscriber.putNext, error: { error in subscriber.putError(error); child.dispose() }, completed: { subscriber.putCompletion(); child.dispose() }))
        return child
    }
}
struct Strings {
    let unknownError = "error"
    let storyTooltipSavedToProfileChannel = "saved channel"; let storyTooltipSavedToProfile = "saved"
    let storyTooltipRemovedFromProfileChannel = "removed channel"; let storyTooltipRemovedFromProfile = "removed"
    let storyTooltipSavedTitle = "saved title"; let storyTooltipRemovedTitle = "removed title"
}
func strings() -> Strings { .init() }
class Controller {
    var onDisappear: (() -> Void)?
    func viewWillDisappear(_ animated: Bool) { onDisappear?() }
    func viewWillAppear(_ animated: Bool) {}
}
enum Tooltip: Equatable { case addedToProfile(Peer), removedFromProfile(Peer) }
final class View {
    var tooltips: [Tooltip] = []
    func showTooltip(_ tooltip: Tooltip) { tooltips.append(tooltip) }
    func animateDisappear(_ id: Int) {}
}
final class Viewer: Controller {
    let context = Context(); let stories = Stories(); let genericView = View(); let initialId = 0
    var window: Window? { context.window }
    var closed = false
    var acceptsStoryDeletion = true
    let deleteStoryDisposable = MetaDisposable()
    var deleteStoryOperationId: UUID?
    let profileStoryDisposable = MetaDisposable()
    var profileStoryOperationId: UUID?
    var acceptsStoryProfileChanges = true
    var toggleProfile: ((StoryContentItem) -> Void)?
    override init() {
        super.init()
        let context = self.context
        __VIEW_ACTION__
    }
    __VIEW_DISAPPEAR__
    __VIEW_APPEAR__
    deinit { __VIEW_DISPOSAL__ }
}
struct ListItem { let id: StoryId; let storyItem: EngineStoryItem }
struct ListState { var items: [ListItem] = [] }
struct GridState {
    var collectionStates: [Int64: ListState] = [0: .init()]
    var selectedCollection: Int64 = 0
    var selected: Set<StoryId>?
    var state: ListState? { collectionStates[selectedCollection] ?? collectionStates[0] }
    var mainState: ListState? { collectionStates[0] }
}
final class Grid: Controller {
    let context = Context()
    let peerId: Int
    let stateValue = Atomic(value: GridState())
    let deleteStoriesDisposable = MetaDisposable()
    var deleteStoriesOperationId: UUID?
    var acceptsStoryDeletion = true
    let pinStoriesDisposable = MetaDisposable()
    var pinStoriesOperationId: UUID?
    var acceptsStoryPinning = true
    let profileStoriesDisposable = MetaDisposable()
    var profileStoriesOperationId: UUID?
    var acceptsStoryProfileChanges = true
    let collectionMutationDisposable = MetaDisposable()
    var collectionMutationOperationId: UUID?
    var acceptsCollectionMutation = true
    var collectionMutationGeneration = UUID()
    let collectionsDisposable = MetaDisposable()
    let actionsDisposable = DisposableSet()
    var toggleStory: ((EngineStoryItem) -> Void)?
    var archiveSelected: (() -> Void)?
    var toggles = 0
    var onUpdate: (() -> Void)?
    func updateState(_ f: (GridState) -> GridState) { _ = stateValue.modify(f); onUpdate?() }
    func toggleSelection() { toggles += 1; updateState { state in var state = state; state.selected = state.selected == nil ? [] : nil; return state } }
    var selected: Set<StoryId>? { stateValue.with { $0.selected } }
    func select(_ ids: [Int32]?, peer: Int? = nil) { updateState { state in var state = state; state.selected = ids.map { Set($0.map { StoryId(peerId: peer ?? peerId, id: $0) }) }; return state } }
    func setItems(_ ids: [Int32], collection: Int64 = 0, peer: Int? = nil) { updateState { state in var state = state; state.collectionStates[collection] = .init(items: ids.map { .init(id: .init(peerId: peer ?? peerId, id: $0), storyItem: .init(id: $0)) }); return state } }
    init(isArchived: Bool = false, peer: Int = 10) {
        self.peerId = peer
        super.init()
        let context = self.context; let peerId = self.peerId
        __HELPER__
        __ACTIONS__
    }
    __GRID_DISAPPEAR__
    __GRID_APPEAR__
    __GRID_DEINIT__
}

final class StoryProfileUITests: XCTestCase {
    func item(_ id: Int32 = 1, peer: Int? = 10, pinned: Bool = true) -> StoryContentItem { .init(peerId: peer, storyItem: .init(id: id, isPinned: pinned)) }
    func testViewerWaitsForAcceptanceAndUsesCapturedIdentity() {
        let viewer = Viewer(); viewer.toggleProfile?(item())
        XCTAssertTrue(viewer.genericView.tooltips.isEmpty); XCTAssertEqual(viewer.context.engine.messages.requests.first?.peer, 10); XCTAssertEqual(viewer.context.engine.messages.requests.first?.ids.keys.sorted(), [1]); XCTAssertEqual(viewer.context.engine.messages.requests.first?.pinned, false)
        viewer.context.engine.messages.requests.first?.succeed(); XCTAssertEqual(viewer.genericView.tooltips, [.removedFromProfile(.init(id: 10))])
    }
    func testViewerFailureDoesNotShowSuccessAndCanRetry() {
        let viewer = Viewer(); viewer.toggleProfile?(item()); viewer.context.engine.messages.requests.first?.fail()
        XCTAssertTrue(viewer.genericView.tooltips.isEmpty); XCTAssertEqual(viewer.context.window.alerts, 1)
        viewer.toggleProfile?(item()); XCTAssertEqual(viewer.context.engine.messages.requests.count, 2)
    }
    func testViewerSaveDirectionUsesCapturedStory() {
        let viewer = Viewer(); viewer.toggleProfile?(item(pinned: false)); viewer.context.engine.messages.requests.first?.succeed()
        XCTAssertEqual(viewer.context.engine.messages.requests.first?.pinned, true); XCTAssertEqual(viewer.genericView.tooltips, [.addedToProfile(.init(id: 10))])
    }
    func testViewerNavigationSuppressesOldSuccessTooltip() {
        for changedPeer in [false,true] {
            let viewer = Viewer(); viewer.toggleProfile?(item()); let next = changedPeer ? item(1, peer: 20) : item(2)
            viewer.stories.stateValue?.slice = .init(peer: .init(id: next.peerId!), item: next)
            viewer.context.engine.messages.requests.first?.succeed(); XCTAssertTrue(viewer.genericView.tooltips.isEmpty)
        }
    }
    func testViewerRejectsMissingPeerAndClosedActions() {
        let viewer = Viewer(); viewer.toggleProfile?(item(peer: nil)); viewer.closed = true; viewer.toggleProfile?(item())
        XCTAssertTrue(viewer.context.engine.messages.requests.isEmpty)
    }
    func testViewerBlocksDuplicateAndDeleteOverlap() {
        let viewer = Viewer(); viewer.deleteStoryOperationId = UUID(); viewer.toggleProfile?(item()); XCTAssertTrue(viewer.context.engine.messages.requests.isEmpty)
        viewer.deleteStoryOperationId = nil; viewer.context.engine.messages.onStart = { [weak viewer] _ in viewer?.context.engine.messages.onStart = nil; viewer?.toggleProfile?(self.item()) }
        viewer.toggleProfile?(item()); viewer.toggleProfile?(item(2)); XCTAssertEqual(viewer.context.engine.messages.requests.count, 1)
    }
    func testViewerDisappearInvalidatesBeforeReentrantCompletion() {
        let viewer = Viewer(); viewer.toggleProfile?(item()); let request = viewer.context.engine.messages.requests.first
        viewer.onDisappear = { request?.succeed() }; viewer.viewWillDisappear(false)
        XCTAssertTrue(request?.cancelled == true); XCTAssertTrue(viewer.genericView.tooltips.isEmpty)
        viewer.toggleProfile?(item()); XCTAssertEqual(viewer.context.engine.messages.requests.count, 1)
    }
    func testViewerReappearanceAndProgressCancellationAllowRetry() {
        let viewer = Viewer(); viewer.toggleProfile?(item()); viewer.context.window.progress.first?.dispose(); viewer.toggleProfile?(item())
        XCTAssertEqual(viewer.context.engine.messages.requests.count, 2); viewer.viewWillDisappear(false); viewer.viewWillAppear(false); viewer.toggleProfile?(item())
        XCTAssertEqual(viewer.context.engine.messages.requests.count, 3); XCTAssertTrue(viewer.genericView.tooltips.isEmpty)
    }
    func testViewerRequestDoesNotRetainOwner() {
        var viewer: Viewer? = Viewer(); weak var owner = viewer; let context = viewer!.context
        viewer?.toggleProfile?(item()); viewer = nil; XCTAssertNil(owner); XCTAssertTrue(context.engine.messages.requests.first?.cancelled == true)
    }
    func testViewerSynchronousAcceptanceReleasesBusyState() {
        let viewer = Viewer(); viewer.context.engine.messages.onStart = { $0.succeed() }
        viewer.toggleProfile?(item()); viewer.toggleProfile?(item()); XCTAssertEqual(viewer.context.engine.messages.requests.count, 2); XCTAssertNil(viewer.profileStoryOperationId)
    }
    func testGridSingleWaitsForAcceptanceAndShowsCorrectDirection() {
        for archived in [false,true] { for peer in [10,20] {
            let grid = Grid(isArchived: archived, peer: peer); grid.toggleStory?(.init(id: 1)); XCTAssertTrue(grid.context.window.texts.isEmpty)
            XCTAssertEqual(grid.context.engine.messages.requests.first?.pinned, archived); XCTAssertEqual(grid.context.engine.messages.requests.first?.peer, peer)
            grid.context.engine.messages.requests.first?.succeed()
            XCTAssertEqual(grid.context.window.texts, [(archived ? "saved" : "removed") + (peer == 20 ? " channel" : "")]); XCTAssertEqual(grid.context.window.titles.first!, archived ? "saved title" : "removed title")
        } }
    }
    func testGridFailureKeepsSelectionAndCanRetry() {
        let grid = Grid(); grid.setItems([1,2]); grid.select([1,2]); grid.archiveSelected?(); grid.context.engine.messages.requests.first?.fail()
        XCTAssertEqual(grid.selected?.count, 2); XCTAssertEqual(grid.context.window.alerts, 1); XCTAssertTrue(grid.context.window.texts.isEmpty)
        grid.archiveSelected?(); XCTAssertEqual(grid.context.engine.messages.requests.count, 2)
    }
    func testGridBulkSuccessClearsOnlySubmittedSelection() {
        let grid = Grid(); grid.setItems([1,2]); grid.select([1]); grid.archiveSelected?(); XCTAssertEqual(grid.selected?.count, 1)
        grid.select([1,2]); grid.context.engine.messages.requests.first?.succeed()
        XCTAssertEqual(grid.selected, Set([StoryId(peerId: 10, id: 2)])); XCTAssertEqual(grid.toggles, 0); XCTAssertEqual(grid.context.window.texts, ["removed"])
    }
    func testGridBulkSuccessEndsSelectionOnlyWhenEmpty() {
        let grid = Grid(); grid.setItems([1,2]); grid.select([1,2]); grid.archiveSelected?(); grid.context.engine.messages.requests.first?.succeed()
        XCTAssertNil(grid.selected); XCTAssertEqual(grid.toggles, 1); XCTAssertEqual(grid.context.window.texts, ["removed"]); XCTAssertNil(grid.context.window.titles.first!)
    }
    func testGridSuccessDoesNotReopenExitedSelection() {
        let grid = Grid(); grid.setItems([1]); grid.select([1]); grid.archiveSelected?(); grid.select(nil); grid.context.engine.messages.requests.first?.succeed()
        XCTAssertNil(grid.selected); XCTAssertEqual(grid.toggles, 0)
    }
    func testMissingSelectedStoryRejectsWholeAction() {
        let grid = Grid(); grid.setItems([1]); grid.select([1,2]); grid.archiveSelected?()
        XCTAssertTrue(grid.context.engine.messages.requests.isEmpty); XCTAssertEqual(grid.selected?.count, 2); XCTAssertEqual(grid.context.window.alerts, 1); XCTAssertTrue(grid.context.window.texts.isEmpty)
    }
    func testForeignSelectionCannotRetargetNumericStoryId() {
        let grid = Grid(); grid.setItems([1]); grid.select([1], peer: 20); grid.archiveSelected?()
        XCTAssertTrue(grid.context.engine.messages.requests.isEmpty); XCTAssertEqual(grid.selected?.first?.peerId, 20); XCTAssertEqual(grid.context.window.alerts, 1)
    }
    func testAlbumSelectionCanResolveMainListStory() {
        let grid = Grid(); grid.setItems([1,2]); grid.setItems([2], collection: 9)
        grid.updateState { state in var state = state; state.selectedCollection = 9; return state }; grid.select([1,2]); grid.archiveSelected?()
        XCTAssertEqual(grid.context.engine.messages.requests.first?.ids.keys.sorted(), [1,2])
    }
    func testEmptySelectionDoesNotSendRequestOrToast() {
        for selection: [Int32]? in [nil,[]] {
            let grid = Grid(); grid.select(selection); grid.archiveSelected?(); XCTAssertTrue(grid.context.engine.messages.requests.isEmpty); XCTAssertTrue(grid.context.window.texts.isEmpty); XCTAssertEqual(grid.toggles, 0)
        }
    }
    func testGridDuplicateAndOtherMutationsCannotOverlap() {
        let grid = Grid(); grid.setItems([1]); grid.select([1]); grid.pinStoriesOperationId = UUID(); grid.archiveSelected?(); grid.toggleStory?(.init(id: 1))
        XCTAssertTrue(grid.context.engine.messages.requests.isEmpty); grid.pinStoriesOperationId = nil; grid.deleteStoriesOperationId = UUID(); grid.toggleStory?(.init(id: 1)); XCTAssertTrue(grid.context.engine.messages.requests.isEmpty)
        grid.deleteStoriesOperationId = nil; grid.context.engine.messages.onStart = { [weak grid] _ in grid?.context.engine.messages.onStart = nil; grid?.archiveSelected?() }
        grid.toggleStory?(.init(id: 1)); grid.archiveSelected?(); XCTAssertEqual(grid.context.engine.messages.requests.count, 1)
    }
    func testGridDisappearCancelsBeforeReentrantCompletion() {
        let grid = Grid(); grid.toggleStory?(.init(id: 1)); let request = grid.context.engine.messages.requests.first
        grid.onDisappear = { request?.succeed() }; grid.viewWillDisappear(false)
        XCTAssertTrue(request?.cancelled == true); XCTAssertTrue(grid.context.window.texts.isEmpty); grid.toggleStory?(.init(id: 1)); XCTAssertEqual(grid.context.engine.messages.requests.count, 1)
    }
    func testGridReappearanceAndProgressCancellationAllowRetry() {
        let grid = Grid(); grid.toggleStory?(.init(id: 1)); grid.context.window.progress.first?.dispose(); grid.toggleStory?(.init(id: 1))
        XCTAssertEqual(grid.context.engine.messages.requests.count, 2); grid.viewWillDisappear(false); grid.viewWillAppear(false); grid.toggleStory?(.init(id: 1)); XCTAssertEqual(grid.context.engine.messages.requests.count, 3)
    }
    func testGridRequestDoesNotRetainOwner() {
        var grid: Grid? = Grid(); weak var owner = grid; let context = grid!.context
        grid?.toggleStory?(.init(id: 1)); grid = nil; XCTAssertNil(owner); XCTAssertTrue(context.engine.messages.requests.first?.cancelled == true)
    }
    func testGridReentrantDisappearanceSuppressesToast() {
        let grid = Grid(); grid.setItems([1]); grid.select([1]); grid.archiveSelected?(); grid.onUpdate = { [weak grid] in grid?.viewWillDisappear(false) }
        grid.context.engine.messages.requests.first?.succeed(); XCTAssertTrue(grid.context.window.texts.isEmpty)
    }
    func testGridSynchronousSuccessAllowsNextRequest() {
        let grid = Grid(); grid.context.engine.messages.onStart = { $0.succeed() }; grid.toggleStory?(.init(id: 1)); grid.toggleStory?(.init(id: 2))
        XCTAssertEqual(grid.context.engine.messages.requests.count, 2); XCTAssertNil(grid.profileStoriesOperationId)
    }
}
