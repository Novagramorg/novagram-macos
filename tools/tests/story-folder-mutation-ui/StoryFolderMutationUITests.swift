import Foundation
import XCTest
import SwiftSignalKit
extension Array {
    mutating func move(at oldIndex: Int, to newIndex: Int) { insert(remove(at: oldIndex),at: newIndex) }
}

struct Folder: Equatable { let id: Int64; let title: String }
struct StoryId: Equatable { let peerId: Int; let id: Int32 }
struct EngineStoryItem: Equatable { let id: Int32; var folderIds: [Int64]? = nil }
struct ListState: Equatable {
    struct Item: Equatable { let id: StoryId; let storyItem: EngineStoryItem }
    var availableFolders: [Folder] = []
    var isCached = false
    var loadMoreToken: AnyHashable? = AnyHashable(100)
    var marker = 0
    var items: [Item] = []
}
final class CreateRequest {
    let title: String; let items: [EngineStoryItem]
    var callback: ((Int64?) -> Void)?
    var cancelled = false
    var onDispose: (() -> Void)?
    init(title: String, items: [EngineStoryItem], callback: @escaping (Int64?) -> Void) { self.title = title; self.items = items; self.callback = callback }
    func finish(_ id: Int64?) { callback?(id) }
}
final class Request {
    let id: Int64
    let title: String?
    var callback: ((Bool) -> Void)?
    var order: [Int64] = []
    var added: [EngineStoryItem] = []
    var removed: [Int32] = []
    var cancelled = false
    var onDispose: (() -> Void)?
    init(id: Int64, title: String?, callback: @escaping (Bool) -> Void) { self.id = id; self.title = title; self.callback = callback }
    func finish(_ success: Bool) { callback?(success) }
}
final class PeerStoryListContext {
    typealias State = ListState
    var creations: [CreateRequest] = []
    var onCreate: ((CreateRequest) -> Void)?
    func addFolder(title: String, items: [EngineStoryItem], completion: @escaping (Int64?) -> Void) -> Disposable {
        let request = CreateRequest(title: title,items: items,callback: completion); creations.append(request); onCreate?(request)
        return ActionDisposable { request.cancelled = true; request.callback = nil; request.onDispose?() }
    }
    var memberships: [Request] = []
    var onMembership: ((Request) -> Void)?
    func updateFolderStories(id: Int64, added: [EngineStoryItem], removed: [Int32], completion: @escaping (Bool) -> Void = { _ in }) -> Disposable {
        let request = Request(id: id,title: nil,callback: completion); request.added = added; request.removed = removed; memberships.append(request); onMembership?(request)
        return ActionDisposable { request.cancelled = true; request.callback = nil; request.onDispose?() }
    }
    func addToFolder(id: Int64, items: [EngineStoryItem]) -> Disposable { updateFolderStories(id: id,added: items,removed: []) }
    func removeFromFolder(id: Int64, itemIds: [Int32]) -> Disposable { updateFolderStories(id: id,added: [],removed: itemIds) }
    var reorders: [Request] = []
    var onReorder: ((Request) -> Void)?
    func reorderFolders(ids: [Int64], completion: @escaping (Bool) -> Void = { _ in }) -> Disposable {
        let request = Request(id: 0,title: nil,callback: completion); request.order = ids; reorders.append(request); onReorder?(request)
        return ActionDisposable { request.cancelled = true; request.callback = nil; request.onDispose?() }
    }
    var requests: [Request] = []
    var onRequest: ((Request) -> Void)?
    func request(id: Int64, title: String?, completion: @escaping (Bool) -> Void) -> Disposable {
        let request = Request(id: id,title: title,callback: completion); requests.append(request); onRequest?(request)
        return ActionDisposable { request.cancelled = true; request.callback = nil; request.onDispose?() }
    }
    func renameFolder(id: Int64, title: String, completion: @escaping (Bool) -> Void = { _ in }) -> Disposable { request(id: id,title: title,completion: completion) }
    func removeFolder(id: Int64, completion: @escaping (Bool) -> Void = { _ in }) -> Disposable { request(id: id,title: nil,completion: completion) }
}
typealias StoryListContextState = ListState
final class Picker { let callback: ([EngineStoryItem],[EngineStoryItem]) -> Void; init(_ callback: @escaping ([EngineStoryItem],[EngineStoryItem]) -> Void) { self.callback = callback } }
func SelectStoryModalController(context: Context, folderId: Int64, peerId: Int, listContext: PeerStoryListContext?, albumContext: PeerStoryListContext? = nil, callback: @escaping ([EngineStoryItem],[EngineStoryItem]) -> Void) -> Picker { Picker(callback) }
func showModal(with picker: Picker, for window: Window) { window.pickers.append(picker) }
final class Window {
    var pickers: [Picker] = []
    var progress: [MetaDisposable] = []
    var alerts = 0
    var texts: [String] = []
    var onText: (() -> Void)?
}
func alert(for window: Window, info: String) { window.alerts += 1 }
func showModalText(for window: Window, text: String) { window.texts.append(text); window.onText?() }
func showModalProgress<T,E>(signal: Signal<T,E>, for window: Window) -> Signal<T,E> {
    Signal { subscriber in
        let child = MetaDisposable(); window.progress.append(child)
        child.set(signal.start(next: subscriber.putNext,error: { subscriber.putError($0); child.dispose() },completed: { subscriber.putCompletion(); child.dispose() }))
        return child
    }
}
struct Strings {
    let storyMediaAlbumUpdateSuccess = "renamed"; let unknownError = "error"
    func storyMediaAlbumAlertRemoved(_ title: String) -> String { "removed " + title }
    func storyMediaAlbumAlertAdded(_ title: String) -> String { "added " + title }
}
func strings() -> Strings { .init() }
class Controller {
    var onDisappear: (() -> Void)?
    func viewWillDisappear(_ animated: Bool) { onDisappear?() }
    func viewWillAppear(_ animated: Bool) {}
}
struct State {
    enum Collection: Equatable {
        case all, collection(value: Folder), add
        var stableId: Int64 { switch self { case .all: return -1; case let .collection(value): return value.id; case .add: return .max } }
    }
    var mainState: ListState? { collectionStates[-1] }
    __CONTAINS__
    var collections: [Collection] = []
    var collectionStates: [Int64: ListState] = [:]
    var selectedCollection: Int64 = -1
    var peer: Int?
    var editable = true
    func access(_ peer: Int) -> Bool { editable }
    var folderCount: Int { collections.filter { if case .collection = $0 { return true }; return false }.count }
}
struct Context { let peerId = 10; let window = Window() }
final class Grid: Controller {
    var collectionsContexts: [Int64: PeerStoryListContext] = [:]
    var addToCollection: ((State.Collection,ListState.Item?) -> Void)?
    func setupMembership() {
        let context = self.context; let peerId = self.peerId
        __MEMBERSHIP_ACTION__
    }
    __MEMBERSHIP_HELPER__
    let peerId = 10
    var createConfirmed: ((Int) -> Void)?
    func prepareCreate(title: String = "new", story: ListState.Item? = nil) {
        let text = title
        if self.window != nil {
            __CREATE_ACTION__
        }
    }
    __CREATE__
    var peerListContext: PeerStoryListContext? = PeerStoryListContext()
    var window: Window?
    override init() { super.init(); self.window = context.window }
    let context = Context()
    var isArchived = false
    var foldersLimit = 16
    var state = State()
    var stateValue: Atomic<State> { Atomic(value: state) }
    var onUpdate: (() -> Void)?
    let actionsDisposable = DisposableSet()
    let collectionsDisposable = MetaDisposable()
    let deleteStoriesDisposable = MetaDisposable()
    var deleteStoriesOperationId: UUID?
    var acceptsStoryDeletion = true
    let profileStoriesDisposable = MetaDisposable()
    var profileStoriesOperationId: UUID?
    var acceptsStoryProfileChanges = true
    let pinStoriesDisposable = MetaDisposable()
    var pinStoriesOperationId: UUID?
    var acceptsStoryPinning = true
    __FIELDS__
    var renameConfirmed: ((Int) -> Void)?
    var deleteConfirmed: ((Int) -> Void)?
    func prepareRename(_ value: Folder) {
        __TITLE__
        if let window = self.window {
            __RENAME_ACTION__
        }
    }
    func prepareDelete(_ value: Folder) {
        if self.window != nil {
            __DELETE_ACTION__
        }
    }
    func updateState(_ f: (State) -> State) { state = f(state); onUpdate?() }
    func receive(_ state: ListState) {
        let peer: Int? = 10; let isArchived = self.isArchived; let foldersLimit = self.foldersLimit; let context = self.context
        __REDUCER__
    }
    __UPDATE__
    __REORDER__
    __DISAPPEAR__
    __APPEAR__
    __DEINIT__
}

final class StoryFolderMutationUITests: XCTestCase {
    func submit(_ grid: Grid, rename: Bool, id: Int64 = 7, title: String = "edited") {
        if rename { grid.prepareRename(.init(id: id,title: title)); grid.renameConfirmed?(0) }
        else { grid.prepareDelete(.init(id: id,title: title)); grid.deleteConfirmed?(0) }
    }
    func testCompleteAlbumAbsenceOverridesStaleProfileMembership() {
        var state = State(); state.collectionStates[7] = ListState(loadMoreToken: nil)
        XCTAssertFalse(state.contains(collectionId: 7,story: .init(id: 2,folderIds: [7])))
    }
    func testCurrentProfileMembershipOverridesCapturedStory() {
        var state = State(); state.collectionStates[-1] = ListState(items: [.init(id: .init(peerId: 10,id: 2),storyItem: .init(id: 2,folderIds: []))])
        XCTAssertFalse(state.contains(collectionId: 7,story: .init(id: 2,folderIds: [7])))
    }
    func testCurrentProfileAdditionOverridesCapturedMissingMembership() {
        var state = State(); state.collectionStates[-1] = ListState(items: [.init(id: .init(peerId: 10,id: 2),storyItem: .init(id: 2,folderIds: [7]))])
        XCTAssertTrue(state.contains(collectionId: 7,story: .init(id: 2,folderIds: [])))
    }
    func testCachedAlbumAbsenceIsNotAuthoritative() {
        var state = State(); state.collectionStates[7] = ListState(isCached: true,loadMoreToken: nil)
        XCTAssertTrue(state.contains(collectionId: 7,story: .init(id: 2,folderIds: [7])))
    }
    func testPartialAlbumAbsenceUsesMembershipMetadata() {
        var state = State(); state.collectionStates[7] = ListState(loadMoreToken: AnyHashable(100))
        XCTAssertTrue(state.contains(collectionId: 7,story: .init(id: 2,folderIds: [7])))
    }
    func testLoadedAlbumMemberWinsOverStaleProfileAbsence() {
        var state = State(); state.collectionStates[7] = ListState(items: [.init(id: .init(peerId: 10,id: 2),storyItem: .init(id: 2,folderIds: nil))])
        XCTAssertTrue(state.contains(collectionId: 7,story: .init(id: 2,folderIds: [])))
    }
    func testRenameWaitsForAcceptance() {
        let grid = Grid(); submit(grid,rename: true)
        XCTAssertEqual(grid.window?.texts,[]); XCTAssertEqual(grid.peerListContext?.requests.first?.title,"edited")
        grid.peerListContext?.requests.first?.finish(true); XCTAssertEqual(grid.window?.texts,["renamed"])
    }
    func testRenameFailureAlertsWithoutSuccessAndAllowsRetry() {
        let grid = Grid(); submit(grid,rename: true); grid.peerListContext?.requests.first?.finish(false)
        XCTAssertEqual(grid.window?.texts,[]); XCTAssertEqual(grid.window?.alerts,1); submit(grid,rename: true); XCTAssertEqual(grid.peerListContext?.requests.count,2)
    }
    func testDeleteFailureAlertsAndAllowsRetry() {
        let grid = Grid(); submit(grid,rename: false); grid.peerListContext?.requests.first?.finish(false)
        XCTAssertEqual(grid.window?.alerts,1); XCTAssertEqual(grid.window?.texts,[]); submit(grid,rename: false); XCTAssertEqual(grid.peerListContext?.requests.count,2)
    }
    func testSuccessfulDeleteDoesNotShowRenameToast() {
        let grid = Grid(); submit(grid,rename: false); grid.peerListContext?.requests.first?.finish(true)
        XCTAssertEqual(grid.window?.alerts,0); XCTAssertEqual(grid.window?.texts,[])
    }
    func testDuplicateAndConflictingMutationBlocked() {
        for rename in [false,true] {
            let grid = Grid(); submit(grid,rename: rename); submit(grid,rename: rename); submit(grid,rename: !rename)
            XCTAssertEqual(grid.peerListContext?.requests.count,1)
        }
    }
    func testProgressCancellationReleasesGuard() {
        let grid = Grid(); submit(grid,rename: true); grid.window?.progress.first?.dispose()
        XCTAssertTrue(grid.peerListContext?.requests.first?.cancelled == true); submit(grid,rename: true); XCTAssertEqual(grid.peerListContext?.requests.count,2)
    }
    func testDismissalCancelsBothKindsAndIgnoresLateResponse() {
        for rename in [false,true] {
            let grid = Grid(); submit(grid,rename: rename); let request = grid.peerListContext?.requests.first; let late = request?.callback
            grid.viewWillDisappear(false); late?(true)
            XCTAssertTrue(request?.cancelled == true); XCTAssertEqual(grid.window?.texts,[]); XCTAssertEqual(grid.window?.alerts,0)
        }
    }
    func testRetainedConfirmationCannotStartAfterDismissal() {
        for rename in [false,true] {
            let grid = Grid(); grid.prepareRename(.init(id: 7,title: "new")); grid.prepareDelete(.init(id: 7,title: "old")); grid.viewWillDisappear(false)
            if rename { grid.renameConfirmed?(0) } else { grid.deleteConfirmed?(0) }
            XCTAssertEqual(grid.peerListContext?.requests.count,0)
        }
    }
    func testReappearancePermitsFreshMutation() {
        let grid = Grid(); grid.viewWillDisappear(false); grid.viewWillAppear(false); submit(grid,rename: true)
        XCTAssertEqual(grid.peerListContext?.requests.count,1)
    }
    func testSynchronousSuccessAndFailureReleaseGuard() {
        for success in [false,true] {
            let grid = Grid(); grid.peerListContext?.onRequest = { $0.finish(success) }; submit(grid,rename: true); submit(grid,rename: true)
            XCTAssertEqual(grid.peerListContext?.requests.count,2); XCTAssertEqual(grid.window?.alerts,success ? 0 : 2); XCTAssertEqual(grid.window?.texts.count,success ? 2 : 0)
        }
    }
    func testOwnerReleasedAndRequestCanceled() {
        var grid: Grid? = Grid(); let source = grid!.peerListContext!; weak var weakGrid = grid; submit(grid!,rename: true); grid = nil
        XCTAssertNil(weakGrid); XCTAssertTrue(source.requests.first?.cancelled == true)
    }
    func testConfirmationDoesNotRetainOwner() {
        for rename in [false,true] {
            var grid: Grid? = Grid(); weak var weakGrid = grid; let source = grid!.peerListContext!
            grid!.prepareRename(.init(id: 7,title: "title")); grid!.prepareDelete(.init(id: 7,title: "title")); let callback = rename ? grid!.renameConfirmed : grid!.deleteConfirmed; grid = nil
            XCTAssertNil(weakGrid); callback?(0); XCTAssertEqual(source.requests.count,0)
        }
    }
    func testMissingWindowOrContextDoesNotStart() {
        for rename in [false,true] {
            let grid = Grid(); let source = grid.peerListContext!; grid.window = nil; submit(grid,rename: rename); XCTAssertEqual(source.requests.count,0)
            grid.window = Window(); grid.peerListContext = nil; submit(grid,rename: rename); XCTAssertEqual(grid.window?.alerts,0)
        }
    }
    func testOldCompletionCannotClearNewOperation() {
        let grid = Grid(); submit(grid,rename: true); let old = grid.peerListContext?.requests.first?.callback; grid.window?.progress.first?.dispose(); submit(grid,rename: false)
        old?(true); submit(grid,rename: true); XCTAssertEqual(grid.peerListContext?.requests.count,2); XCTAssertEqual(grid.window?.texts,[])
    }
    func testDisposalReentryCannotRestartAfterDisappearance() {
        let grid = Grid(); submit(grid,rename: true)
        grid.peerListContext?.requests.first?.onDispose = { [weak grid] in if let grid { self.submit(grid,rename: false) } }
        grid.onDisappear = { [weak grid] in if let grid { self.submit(grid,rename: false) } }
        grid.viewWillDisappear(false); XCTAssertEqual(grid.peerListContext?.requests.count,1)
    }
    func testInitialRenameValueIsPreservedWithoutEditing() {
        let grid = Grid(); submit(grid,rename: true,title: "Original")
        XCTAssertEqual(grid.peerListContext?.requests.first?.title,"Original")
    }
    func testDeletingLastFolderRemovesTabsAndResetsSelection() {
        let grid = Grid(); grid.receive(.init(availableFolders: [.init(id: 7,title: "old")]))
        grid.state.selectedCollection = 7; grid.receive(.init())
        XCTAssertEqual(grid.state.collections,[]); XCTAssertEqual(grid.state.selectedCollection,-1)
    }
    func testDeletedFolderSnapshotsAreReleased() {
        let grid = Grid(); grid.state.collectionStates[7] = .init(marker: 7); grid.state.collectionStates[8] = .init(marker: 8)
        grid.receive(.init(availableFolders: [.init(id: 8,title: "kept")],marker: 20))
        XCTAssertNil(grid.state.collectionStates[7]); XCTAssertEqual(grid.state.collectionStates[8]?.marker,8); XCTAssertEqual(grid.state.collectionStates[-1]?.marker,20)
    }
    func testDeletingAnotherFolderKeepsSelectedFolder() {
        let grid = Grid(); grid.state.selectedCollection = 8; grid.receive(.init(availableFolders: [.init(id: 8,title: "kept")]))
        XCTAssertEqual(grid.state.selectedCollection,8); XCTAssertEqual(grid.state.collections,[.all,.collection(value: .init(id: 8,title: "kept")),.add])
    }
    func testRenameRefreshesTabTitle() {
        let grid = Grid(); grid.receive(.init(availableFolders: [.init(id: 7,title: "old")]))
        grid.state.selectedCollection = 7; grid.receive(.init(availableFolders: [.init(id: 7,title: "new")]))
        XCTAssertEqual(grid.state.collections,[.all,.collection(value: .init(id: 7,title: "new")),.add]); XCTAssertEqual(grid.state.selectedCollection,7)
    }
    func testReadonlyAndLimitDoNotAddCreationTab() {
        let grid = Grid(); grid.state.editable = false; grid.receive(.init(availableFolders: [.init(id: 7,title: "x")]))
        XCTAssertEqual(grid.state.collections.count,2); grid.state.editable = true; grid.foldersLimit = 1; grid.receive(.init(availableFolders: [.init(id: 7,title: "x")]))
        XCTAssertEqual(grid.state.collections.count,2)
    }
    func create(_ grid: Grid, title: String = "new", story: ListState.Item? = nil) { grid.prepareCreate(title: title,story: story); grid.createConfirmed?(0) }
    func item(_ id: Int32 = 4, peer: Int = 10, contentId: Int32? = nil) -> ListState.Item { .init(id: .init(peerId: peer,id: id),storyItem: .init(id: contentId ?? id)) }
    func testCreateSubmitsOnlyCapturedStoryAndTitle() {
        let grid = Grid(); create(grid,title: "Selected",story: item())
        XCTAssertEqual(grid.peerListContext?.creations.first?.title,"Selected"); XCTAssertEqual(grid.peerListContext?.creations.first?.items,[.init(id: 4)])
    }
    func testEmptyCollectionSubmitsNoStories() {
        let grid = Grid(); create(grid); XCTAssertEqual(grid.peerListContext?.creations.first?.items,[])
    }
    func testCreateSelectsOnlyAfterAcceptedResult() {
        let grid = Grid(); grid.state.selectedCollection = 8; create(grid); XCTAssertEqual(grid.state.selectedCollection,8)
        grid.peerListContext?.creations.first?.finish(9); XCTAssertEqual(grid.state.selectedCollection,9); XCTAssertEqual(grid.window?.alerts,0)
    }
    func testCreateFailurePreservesSelectionAndAllowsRetry() {
        let grid = Grid(); grid.state.selectedCollection = 8; create(grid); grid.peerListContext?.creations.first?.finish(nil)
        XCTAssertEqual(grid.state.selectedCollection,8); XCTAssertEqual(grid.window?.alerts,1); create(grid); XCTAssertEqual(grid.peerListContext?.creations.count,2)
    }
    func testDuplicateCreateConfirmationBlocked() {
        let grid = Grid(); create(grid); grid.createConfirmed?(0); create(grid)
        XCTAssertEqual(grid.peerListContext?.creations.count,1)
    }
    func testCreateBlocksRenameAndDelete() {
        let grid = Grid(); create(grid); submit(grid,rename: true); submit(grid,rename: false)
        XCTAssertEqual(grid.peerListContext?.requests.count,0)
    }
    func testRenameAndDeleteBlockCreate() {
        for rename in [false,true] {
            let grid = Grid(); submit(grid,rename: rename); create(grid); XCTAssertEqual(grid.peerListContext?.creations.count,0)
        }
    }
    func testForeignAndMismatchedStoriesRejected() {
        for story in [item(peer: 11),item(contentId: 9)] {
            let grid = Grid(); create(grid,story: story); XCTAssertEqual(grid.peerListContext?.creations.count,0); XCTAssertEqual(grid.window?.alerts,1)
        }
    }
    func testEmptyTitleDoesNotCreate() {
        let grid = Grid(); create(grid,title: ""); XCTAssertEqual(grid.peerListContext?.creations.count,0)
    }
    func testCancelCreationSuppressesSelectionAndAllowsRetry() {
        let grid = Grid(); create(grid); let late = grid.peerListContext?.creations.first?.callback
        grid.window?.progress.first?.dispose(); late?(9); XCTAssertEqual(grid.state.selectedCollection,-1); XCTAssertTrue(grid.peerListContext?.creations.first?.cancelled == true)
        create(grid); XCTAssertEqual(grid.peerListContext?.creations.count,2)
    }
    func testDisappearCancelsCreationAndRejectsLateResult() {
        let grid = Grid(); create(grid); let late = grid.peerListContext?.creations.first?.callback
        grid.viewWillDisappear(false); late?(9); XCTAssertTrue(grid.peerListContext?.creations.first?.cancelled == true); XCTAssertEqual(grid.state.selectedCollection,-1)
    }
    func testCreateConfirmationCannotStartAfterDisappearance() {
        let grid = Grid(); grid.prepareCreate(); grid.viewWillDisappear(false); grid.createConfirmed?(0)
        XCTAssertEqual(grid.peerListContext?.creations.count,0)
    }
    func testOldCreateConfirmationCannotReviveOnReappearance() {
        let grid = Grid(); grid.prepareCreate(); let stale = grid.createConfirmed; grid.viewWillDisappear(false); grid.viewWillAppear(false); stale?(0)
        XCTAssertEqual(grid.peerListContext?.creations.count,0); create(grid); XCTAssertEqual(grid.peerListContext?.creations.count,1)
    }
    func testOldRenameAndDeleteConfirmationsCannotReviveOnReappearance() {
        for rename in [false,true] {
            let grid = Grid(); grid.prepareRename(.init(id: 7,title: "old")); grid.prepareDelete(.init(id: 7,title: "old")); let stale = rename ? grid.renameConfirmed : grid.deleteConfirmed
            grid.viewWillDisappear(false); grid.viewWillAppear(false); stale?(0); XCTAssertEqual(grid.peerListContext?.requests.count,0)
            submit(grid,rename: rename); XCTAssertEqual(grid.peerListContext?.requests.count,1)
        }
    }
    func testSynchronousCreationSuccessAndFailure() {
        for id: Int64? in [nil,9] {
            let grid = Grid(); grid.peerListContext?.onCreate = { $0.finish(id) }; create(grid); create(grid)
            XCTAssertEqual(grid.peerListContext?.creations.count,2); XCTAssertEqual(grid.window?.alerts,id == nil ? 2 : 0); XCTAssertEqual(grid.state.selectedCollection,id ?? -1)
        }
    }
    func testCreateOwnerReleaseCancelsRequest() {
        var grid: Grid? = Grid(); weak var weakGrid = grid; let source = grid!.peerListContext!; create(grid!); grid = nil
        XCTAssertNil(weakGrid); XCTAssertTrue(source.creations.first?.cancelled == true)
    }
    func testCreateConfirmationDoesNotRetainOwner() {
        var grid: Grid? = Grid(); weak var weakGrid = grid; let source = grid!.peerListContext!; grid!.prepareCreate(); let callback = grid!.createConfirmed; grid = nil
        XCTAssertNil(weakGrid); callback?(0); XCTAssertEqual(source.creations.count,0)
    }
    func testCreateCompletionCannotInterfereWithNewMutation() {
        let grid = Grid(); create(grid); let late = grid.peerListContext?.creations.first?.callback; grid.window?.progress.first?.dispose(); submit(grid,rename: false)
        late?(9); create(grid); XCTAssertEqual(grid.peerListContext?.creations.count,1); XCTAssertEqual(grid.state.selectedCollection,-1)
    }
    func testCreateDisposalReentryCannotRestartAfterLeaving() {
        let grid = Grid(); create(grid); grid.peerListContext?.creations.first?.onDispose = { [weak grid] in if let grid { self.create(grid) } }
        grid.viewWillDisappear(false); XCTAssertEqual(grid.peerListContext?.creations.count,1)
    }
    func testCreationResultDuringReentrantDisappearance() {
        let grid = Grid(); create(grid); grid.onUpdate = { [weak grid] in grid?.viewWillDisappear(false) }
        grid.peerListContext?.creations.first?.finish(9); XCTAssertEqual(grid.state.selectedCollection,9); XCTAssertTrue(grid.peerListContext?.creations.first?.cancelled == true)
        create(grid); XCTAssertEqual(grid.peerListContext?.creations.count,1)
    }
    func testCreateMissingWindowOrContextDoesNotStart() {
        let grid = Grid(); let source = grid.peerListContext!; grid.prepareCreate(); grid.window = nil; grid.createConfirmed?(0)
        XCTAssertEqual(source.creations.count,0); grid.window = Window(); grid.peerListContext = nil; create(grid); XCTAssertEqual(source.creations.count,0)
    }

    func albums(_ grid: Grid, _ ids: [Int64] = [7,8,9]) { grid.receive(.init(availableFolders: ids.map { .init(id: $0,title: "folder") })) }
    func testReorderUsesAlbumIdentitiesAndOmitsControls() {
        let grid = Grid(); albums(grid); grid.reorderCollections(from: 9,to: 7)
        XCTAssertEqual(grid.peerListContext?.reorders.first?.order,[9,7,8]); XCTAssertEqual(grid.state.collections.map(\.stableId),[-1,7,8,9,.max])
    }
    func testReorderFailureAlertsAndAllowsRetry() {
        let grid = Grid(); albums(grid); grid.reorderCollections(from: 9,to: 7); grid.peerListContext?.reorders.first?.finish(false)
        XCTAssertEqual(grid.window?.alerts,1); grid.reorderCollections(from: 8,to: 7); XCTAssertEqual(grid.peerListContext?.reorders.count,2)
    }
    func testReorderRejectsMissingOrControlIdentities() {
        let grid = Grid(); albums(grid)
        for pair: (Int64,Int64) in [(77,7),(7,77),(-1,7),(7,.max),(7,7)] { grid.reorderCollections(from: pair.0,to: pair.1) }
        XCTAssertEqual(grid.peerListContext?.reorders.count,0)
    }
    func testReorderUsesLatestListForValidIdentities() {
        let grid = Grid(); albums(grid,[10,9,8,7]); grid.reorderCollections(from: 7,to: 9)
        XCTAssertEqual(grid.peerListContext?.reorders.first?.order,[10,7,9,8])
    }
    func testReadonlyReorderRejected() {
        let grid = Grid(); grid.state.editable = false; albums(grid); grid.reorderCollections(from: 9,to: 7)
        XCTAssertEqual(grid.peerListContext?.reorders.count,0)
    }
    func testReorderBlocksCreateRenameDeleteAndAnotherReorder() {
        let grid = Grid(); albums(grid); grid.reorderCollections(from: 9,to: 7); create(grid); submit(grid,rename: true); submit(grid,rename: false); grid.reorderCollections(from: 8,to: 7)
        XCTAssertEqual(grid.peerListContext?.reorders.count,1); XCTAssertEqual(grid.peerListContext?.creations.count,0); XCTAssertEqual(grid.peerListContext?.requests.count,0)
    }
    func testOtherAlbumMutationsBlockReorder() {
        for operation in 0...2 {
            let grid = Grid(); albums(grid)
            if operation == 0 { create(grid) } else { submit(grid,rename: operation == 1) }
            grid.reorderCollections(from: 9,to: 7); XCTAssertEqual(grid.peerListContext?.reorders.count,0)
        }
    }
    func testReorderCancelReleasesGuard() {
        let grid = Grid(); albums(grid); grid.reorderCollections(from: 9,to: 7); grid.window?.progress.first?.dispose()
        XCTAssertTrue(grid.peerListContext?.reorders.first?.cancelled == true); grid.reorderCollections(from: 8,to: 7); XCTAssertEqual(grid.peerListContext?.reorders.count,2)
    }
    func testReorderDisappearanceCancelsAndSuppressesLateFailure() {
        let grid = Grid(); albums(grid); grid.reorderCollections(from: 9,to: 7); let late = grid.peerListContext?.reorders.first?.callback
        grid.viewWillDisappear(false); late?(false); XCTAssertTrue(grid.peerListContext?.reorders.first?.cancelled == true); XCTAssertEqual(grid.window?.alerts,0)
        grid.reorderCollections(from: 8,to: 7); XCTAssertEqual(grid.peerListContext?.reorders.count,1)
    }
    func testSynchronousReorderSuccessAndFailure() {
        for success in [false,true] {
            let grid = Grid(); albums(grid); grid.peerListContext?.onReorder = { $0.finish(success) }; grid.reorderCollections(from: 9,to: 7); grid.reorderCollections(from: 8,to: 7)
            XCTAssertEqual(grid.peerListContext?.reorders.count,2); XCTAssertEqual(grid.window?.alerts,success ? 0 : 2)
        }
    }
    func testReorderOwnerReleased() {
        var grid: Grid? = Grid(); albums(grid!); let source = grid!.peerListContext!; weak var weakGrid = grid; grid!.reorderCollections(from: 9,to: 7); grid = nil
        XCTAssertNil(weakGrid); XCTAssertTrue(source.reorders.first?.cancelled == true)
    }
    func testStaleReorderCallbackCannotAffectNewOperation() {
        let grid = Grid(); albums(grid); grid.reorderCollections(from: 9,to: 7); let late = grid.peerListContext?.reorders.first?.callback; grid.window?.progress.first?.dispose(); create(grid); late?(false)
        grid.reorderCollections(from: 8,to: 7); XCTAssertEqual(grid.window?.alerts,0); XCTAssertEqual(grid.peerListContext?.reorders.count,1)
    }

    func membership(_ grid: Grid) -> PeerStoryListContext {
        let source = PeerStoryListContext(); grid.collectionsContexts[7] = source; grid.setupMembership(); return source
    }
    func toggle(_ grid: Grid, story: ListState.Item? = nil) { grid.addToCollection?(.collection(value: .init(id: 7,title: "Album")),story) }
    func testMembershipSingleSuccessWaitsForAcceptance() {
        let grid = Grid(); let source = membership(grid); toggle(grid,story: item()); XCTAssertEqual(grid.window?.texts,[])
        XCTAssertEqual(source.memberships.first?.added.map(\.id),[4]); XCTAssertEqual(source.memberships.first?.removed,[])
        source.memberships.first?.finish(true); XCTAssertEqual(grid.window?.texts,["added Album"])
    }
    func testMembershipRemovalWaitsAndFailureDoesNotShowSuccess() {
        let grid = Grid(); let source = membership(grid); let member = ListState.Item(id: .init(peerId: 10,id: 4),storyItem: .init(id: 4,folderIds: [7]))
        toggle(grid,story: member); XCTAssertEqual(source.memberships.first?.removed,[4]); XCTAssertEqual(grid.window?.texts,[]); source.memberships.first?.finish(false)
        XCTAssertEqual(grid.window?.alerts,1); XCTAssertEqual(grid.window?.texts,[]); toggle(grid,story: member); XCTAssertEqual(source.memberships.count,2)
    }
    func testPickerSubmitsBothChangesInOneRequest() {
        let grid = Grid(); let source = membership(grid); toggle(grid); grid.window?.pickers.first?.callback([.init(id: 4)],[.init(id: 2)])
        XCTAssertEqual(source.memberships.count,1); XCTAssertEqual(source.memberships.first?.added.map(\.id),[4]); XCTAssertEqual(source.memberships.first?.removed,[2])
    }
    func testPickerDuplicateCallbackIgnoredEvenAfterCompletion() {
        let grid = Grid(); let source = membership(grid); source.onMembership = { $0.finish(true) }; toggle(grid); let callback = grid.window?.pickers.first?.callback
        callback?([.init(id: 4)],[]); callback?([.init(id: 4)],[]); XCTAssertEqual(source.memberships.count,1)
    }
    func testPickerEmptySubmissionIsNoOp() {
        let grid = Grid(); let source = membership(grid); toggle(grid); grid.window?.pickers.first?.callback([],[])
        XCTAssertEqual(source.memberships.count,0); XCTAssertEqual(grid.window?.progress.count,0)
    }
    func testPickerCannotSubmitAfterDisappearReappear() {
        let grid = Grid(); let source = membership(grid); toggle(grid); let callback = grid.window?.pickers.first?.callback
        grid.viewWillDisappear(false); grid.viewWillAppear(false); callback?([.init(id: 4)],[]); XCTAssertEqual(source.memberships.count,0)
    }
    func testPickerDeletedContextCannotMutate() {
        let grid = Grid(); let source = membership(grid); toggle(grid); grid.collectionsContexts.removeAll(); grid.window?.pickers.first?.callback([.init(id: 4)],[])
        XCTAssertEqual(source.memberships.count,0)
    }
    func testMembershipForeignStoryRejected() {
        let grid = Grid(); let source = membership(grid); toggle(grid,story: item(peer: 11)); toggle(grid,story: item(contentId: 9))
        XCTAssertEqual(source.memberships.count,0); XCTAssertEqual(grid.window?.alerts,2)
    }
    func testMembershipBlocksOtherAlbumMutations() {
        let grid = Grid(); albums(grid); let source = membership(grid); toggle(grid,story: item()); toggle(grid,story: item()); create(grid); submit(grid,rename: false); grid.reorderCollections(from: 9,to: 7)
        XCTAssertEqual(source.memberships.count,1); XCTAssertEqual(grid.peerListContext?.creations.count,0); XCTAssertEqual(grid.peerListContext?.requests.count,0); XCTAssertEqual(grid.peerListContext?.reorders.count,0)
    }
    func testOtherMutationBlocksMembershipAndPicker() {
        let grid = Grid(); let source = membership(grid); create(grid); toggle(grid,story: item()); toggle(grid)
        XCTAssertEqual(source.memberships.count,0); XCTAssertEqual(grid.window?.pickers.count,0)
    }
    func testMembershipCancelAndRetry() {
        let grid = Grid(); let source = membership(grid); toggle(grid,story: item()); let late = source.memberships.first?.callback; grid.window?.progress.first?.dispose(); late?(true)
        XCTAssertTrue(source.memberships.first?.cancelled == true); XCTAssertEqual(grid.window?.texts,[]); toggle(grid,story: item()); XCTAssertEqual(source.memberships.count,2)
    }
    func testMembershipDisappearCancels() {
        let grid = Grid(); let source = membership(grid); toggle(grid,story: item()); let late = source.memberships.first?.callback; grid.viewWillDisappear(false); late?(false)
        XCTAssertTrue(source.memberships.first?.cancelled == true); XCTAssertEqual(grid.window?.alerts,0); XCTAssertEqual(grid.window?.texts,[])
    }
    func testMembershipOwnerRelease() {
        var grid: Grid? = Grid(); let source = membership(grid!); weak var weakGrid = grid; toggle(grid!,story: item()); grid = nil
        XCTAssertNil(weakGrid); XCTAssertTrue(source.memberships.first?.cancelled == true)
    }
    func testSynchronousMembershipResultsAllowRetry() {
        for success in [false,true] {
            let grid = Grid(); let source = membership(grid); source.onMembership = { $0.finish(success) }; toggle(grid,story: item()); toggle(grid,story: item())
            XCTAssertEqual(source.memberships.count,2); XCTAssertEqual(grid.window?.alerts,success ? 0 : 2); XCTAssertEqual(grid.window?.texts.count,success ? 2 : 0)
        }
    }

}
