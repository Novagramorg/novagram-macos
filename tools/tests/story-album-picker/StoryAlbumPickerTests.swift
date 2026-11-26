import Foundation
import XCTest
import SwiftSignalKit

typealias PeerId = Int
struct StoryId: Equatable, Hashable { let peerId: PeerId; let id: Int32 }
struct EngineStoryItem: Equatable { let id: Int32; var folderIds: [Int64]? = nil; var isPending = false; var text = "" }
struct PeerReference: Equatable { let id: PeerId }
final class Account {
    var initial: [Int64: PeerStoryListContext.State] = [:]
    var onCreate: ((PeerStoryListContext, Int64?) -> Void)?
}
final class PeerStoryListContext {
    struct State: Equatable {
        struct Item: Equatable { let id: StoryId; var storyItem: EngineStoryItem }
        var items: [Item] = []
        var peerReference: PeerReference? = .init(id: 10)
        var isCached = false
        var isLoading = false
        var loadMoreToken: AnyHashable?
        var totalCount = 0
    }
    var value: State
    private let promise: ValuePromise<State>
    var subscribers = 0
    var loads = 0
    var onLoad: (() -> Void)?
    var onDispose: (() -> Void)?
    var state: Signal<State, NoError> {
        Signal { [weak self] subscriber in
            guard let self else { return EmptyDisposable }
            self.subscribers += 1
            let disposable = self.promise.get().start(next: subscriber.putNext)
            return ActionDisposable { [weak self] in
                disposable.dispose()
                self?.subscribers -= 1
                self?.onDispose?()
            }
        }
    }
    init(_ state: State = .init()) { value = state; promise = ValuePromise(state, ignoreRepeated: true) }
    convenience init(account: Account, peerId: PeerId, isArchived: Bool, folderId: Int64?) {
        self.init(account.initial[folderId ?? -1] ?? .init())
        account.onCreate?(self,folderId)
    }
    func emit(_ state: State) { value = state; promise.set(state) }
    func loadMore() { loads += 1; onLoad?() }
}
final class Window { var texts: [String] = [] }
struct Configuration { var limit = 3; func getGeneralValue(_ key: String, orElse: Int32) -> Int32 { Int32(limit) } }
protocol AccountContextProtocol: AnyObject { var account: Account { get }; var appConfiguration: Configuration { get }; var window: Window { get } }
final class Context: AccountContextProtocol { let account = Account(); var appConfiguration = Configuration(); let window = Window() }
func bestWindow(_ context: any AccountContextProtocol, _ controller: ViewController?) -> Window { context.window }
func showModalText(for window: Window, text: String) { window.texts.append(text) }
struct Strings { let selectStoryLimitReached = "limit"; let selectStoryTitle = "pick"; let selectStoryAccept = "done" }
func strings() -> Strings { Strings() }
func deliverOnPrepareQueue<T,E>(_ signal: Signal<T,E>) -> Signal<T,E> { signal }
struct Theme { struct Icons { let modalClose = 0 }; let icons = Icons() }
let theme = Theme()
struct ModalHeaderData { let image: Int; let handler: () -> Void }
struct ScrollPosition { enum Direction { case bottom, top }; let direction: Direction }
final class Table {
    var handler: ((ScrollPosition) -> Void)?
    func setScrollHandler(_ handler: @escaping (ScrollPosition) -> Void) { self.handler = handler }
}
class ViewController {}
enum Validation { enum Failure { case none }; case none, fail(Failure) }
enum Screen { case storiesAlbumPicker }
private struct InputDataSignalValue { let state: State; let arguments: Arguments }
private final class InputDataController: ViewController {
    var contextObject: Any?
    var analyticsScreen: Screen?
    var validateData: ((Int) -> Validation)?
    var afterDisappear: (() -> Void)?
    var onDeinit: (() -> Void)?
    var didLoad: ((InputDataController, Int) -> Void)?
    var leftModalHeader: ModalHeaderData?
    var latest: InputDataSignalValue?
    var onData: (() -> Void)?
    let tableView = Table()
    private var disposable: Disposable?
    init(dataSignal: Signal<InputDataSignalValue, NoError>, title: String) {
        super.init()
        disposable = dataSignal.start(next: { [weak self] value in self?.latest = value; self?.onData?() })
    }
    func returnKeyAction() -> Validation { validateData?(0) ?? .none }
    deinit { onDeinit?(); disposable?.dispose() }
}
struct ModalInteractions {
    let acceptTitle: String; let accept: () -> Void; let inset: Int; let singleButton: Bool
}
private final class InputDataModalController {
    let controller: InputDataController
    var closes = 0
    let interactions: ModalInteractions
    init(_ controller: InputDataController, modalInteractions: ModalInteractions, size: NSSize) { self.controller = controller; interactions = modalInteractions }
    func close() { closes += 1 }
}

__PRODUCTION__

private func item(_ id: Int32, member: Bool = false, peer: Int = 10, text: String = "", pending: Bool = false) -> PeerStoryListContext.State.Item {
    .init(id: .init(peerId: peer,id: id),storyItem: .init(id: id,folderIds: member ? [7] : [],isPending: pending,text: text))
}
private func list(_ items: [PeerStoryListContext.State.Item], total: Int? = nil, token: Int? = nil, cached: Bool = false, loading: Bool = false, peer: Int? = 10) -> PeerStoryListContext.State {
    .init(items: items,peerReference: peer.map(PeerReference.init),isCached: cached,isLoading: loading,loadMoreToken: token.map(AnyHashable.init),totalCount: total ?? items.count)
}
private final class Result {
    var added: [[EngineStoryItem]] = []
    var removed: [[EngineStoryItem]] = []
    var onSubmit: (() -> Void)?
}
private final class Harness {
    let context = Context()
    let main: PeerStoryListContext
    let album: PeerStoryListContext
    let result = Result()
    var modal: InputDataModalController!
    var controller: InputDataController { modal.controller }
    init(main: PeerStoryListContext.State = list([item(1),item(2),item(3),item(4)]), album: PeerStoryListContext.State = list([]), limit: Int = 3) {
        self.main = PeerStoryListContext(main); self.album = PeerStoryListContext(album)
        context.appConfiguration.limit = limit
        let result = result
        modal = SelectStoryModalController(context: context,folderId: 7,peerId: 10,listContext: self.main,albumContext: self.album,callback: { added, removed in
            result.added.append(added); result.removed.append(removed); result.onSubmit?()
        })
        controller.didLoad?(controller,0)
    }
    func toggle(_ id: Int32, peer: Int = 10) { controller.latest?.arguments.toggleSelected(.init(peerId: peer,id: id)) }
    func submit() { _ = controller.returnKeyAction() }
    func retry() { controller.latest?.arguments.retry() }
    func close() { controller.afterDisappear?() }
    func selected(_ id: Int32) -> Bool { controller.latest?.state.selected(item(id).storyItem) == true }
}

final class StoryAlbumPickerTests: XCTestCase {
    func testExactlyAtLimitRejectsAnotherSelection() {
        let h = Harness(limit: 2); h.toggle(1); h.toggle(2); h.toggle(3); h.submit()
        XCTAssertEqual(h.result.added.first?.map(\.id),[1,2]); XCTAssertEqual(h.context.window.texts,["limit"])
    }
    func testExistingMembersCountTowardLimit() {
        let h = Harness(album: list([item(1),item(2)]),limit: 2); h.toggle(3); h.submit()
        XCTAssertEqual(h.result.added.first,[]); XCTAssertEqual(h.context.window.texts,["limit"])
    }
    func testTotalCountIncludesUnrenderedAlbumMembers() {
        let h = Harness(album: list([item(1)],total: 3),limit: 3); h.toggle(2); h.submit()
        XCTAssertEqual(h.result.added.first,[]); XCTAssertEqual(h.context.window.texts,["limit"])
    }
    func testRemovalFreesOneSlot() {
        let h = Harness(album: list([item(1),item(2)]),limit: 2); h.toggle(1); h.toggle(3); h.submit()
        XCTAssertEqual(h.result.added.first?.map(\.id),[3]); XCTAssertEqual(h.result.removed.first?.map(\.id),[1])
    }
    func testZeroLimitStillAllowsRemoval() {
        let h = Harness(album: list([item(1)]),limit: 0); h.toggle(1); h.toggle(2); h.submit()
        XCTAssertEqual(h.result.added.first,[]); XCTAssertEqual(h.result.removed.first?.map(\.id),[1])
    }
    func testNegativeLimitRejectsAdditions() {
        let h = Harness(limit: -1); h.toggle(1); h.submit(); XCTAssertEqual(h.result.added.first,[])
    }
    func testStaleProfileMembershipDoesNotPreselectRemovedMember() {
        let h = Harness(main: list([item(1,member: true)])); XCTAssertFalse(h.selected(1)); h.toggle(1); h.submit()
        XCTAssertEqual(h.result.added.first?.map(\.id),[1]); XCTAssertEqual(h.result.removed.first,[])
    }
    func testAlbumMembershipOverridesMissingProfileMetadata() {
        let h = Harness(album: list([item(1)])); XCTAssertTrue(h.selected(1)); h.toggle(1); h.submit()
        XCTAssertEqual(h.result.removed.first?.map(\.id),[1]); XCTAssertEqual(h.result.added.first,[])
    }
    func testToggleTwiceCancelsIntent() {
        let h = Harness(); h.toggle(1); h.toggle(1); h.submit(); XCTAssertEqual(h.result.added.first,[]); XCTAssertEqual(h.result.removed.first,[])
    }
    func testLatestStoryMetadataIsSubmitted() {
        let h = Harness(); h.toggle(1); h.main.emit(list([item(1,text: "updated")])); h.submit()
        XCTAssertEqual(h.result.added.first?.first?.text,"updated")
    }
    func testLiveAdditionBecomesNoOpAndCanThenBeRemoved() {
        let h = Harness(); h.toggle(1); h.album.emit(list([item(1)])); h.toggle(1); h.submit()
        XCTAssertEqual(h.result.added.first,[]); XCTAssertEqual(h.result.removed.first?.map(\.id),[1])
    }
    func testLiveRemovalCanThenBeAddedWithoutConflictingArrays() {
        let h = Harness(main: list([item(1,member: true)]),album: list([item(1)])); h.toggle(1)
        h.main.emit(list([item(1)])); h.album.emit(list([])); h.toggle(1); h.submit()
        XCTAssertEqual(h.result.added.first?.map(\.id),[1]); XCTAssertEqual(h.result.removed.first,[])
    }
    func testRemoteAlreadyAppliedIntentDoesNotResubmit() {
        let h = Harness(); h.toggle(1); h.album.emit(list([item(1)])); h.submit()
        XCTAssertEqual(h.result.added.first,[]); XCTAssertEqual(h.result.removed.first,[])
    }
    func testLiveGrowthRevalidatesLimitAtSubmit() {
        let h = Harness(limit: 2); h.toggle(3); h.album.emit(list([item(1),item(2)])); h.submit()
        XCTAssertTrue(h.result.added.isEmpty); XCTAssertEqual(h.modal.closes,0); XCTAssertEqual(h.context.window.texts,["limit"])
    }
    func testAboveLimitRemovalStillSubmits() {
        let h = Harness(main: list([item(1,member: true)]),album: list([item(1),item(2),item(3)]),limit: 1)
        h.toggle(1); h.submit(); XCTAssertEqual(h.result.removed.first?.map(\.id),[1])
    }
    func testForeignPeerCannotToggle() {
        let h = Harness(main: list([item(1,peer: 20)])); h.toggle(1,peer: 20); h.submit(); XCTAssertEqual(h.result.added.first,[])
    }
    func testPendingStoryCannotToggle() {
        let h = Harness(main: list([item(1,pending: true)])); h.toggle(1); h.submit(); XCTAssertEqual(h.result.added.first,[])
    }
    func testMismatchedStoryIdentityCannotToggle() {
        let value = PeerStoryListContext.State.Item(id: .init(peerId: 10,id: 1),storyItem: .init(id: 2))
        let h = Harness(main: list([value])); h.toggle(1); h.submit(); XCTAssertEqual(h.result.added.first,[])
    }
    func testAlbumPagesDrainBeforeToggleOrSubmit() {
        let h = Harness(album: list([item(1)],total: 2,token: 100)); XCTAssertEqual(h.album.loads,1)
        h.toggle(2); h.submit(); XCTAssertTrue(h.result.added.isEmpty)
        h.album.emit(list([item(1),item(2)])); h.toggle(2); h.submit(); XCTAssertEqual(h.result.removed.first?.map(\.id),[2])
    }
    func testFailedAlbumPageRetriesOnlyOnDemand() {
        let h = Harness(album: list([],total: 4,token: 100)); XCTAssertEqual(h.album.loads,1)
        h.album.emit(list([],total: 4,token: 100,loading: true)); h.album.emit(list([],total: 4,token: 100))
        XCTAssertEqual(h.album.loads,1); h.retry(); XCTAssertEqual(h.album.loads,2)
    }
    func testSynchronousDrainOwnsEverySuccessivePage() {
        let h = Harness(album: list([],token: 100,loading: true))
        h.album.onLoad = { [weak album = h.album] in
            guard let album else { return }
            if album.loads == 1 { album.emit(list([item(1)],total: 2,token: 200)) }
            else { album.emit(list([item(1),item(2)])) }
        }
        h.album.emit(list([],token: 100)); XCTAssertEqual(h.album.loads,2); h.toggle(2); h.submit()
        XCTAssertEqual(h.result.removed.first?.map(\.id),[2]); XCTAssertEqual(h.album.subscribers,1)
    }
    func testAlbumReloadCanRequestSameOffsetsAgain() {
        let h = Harness(album: list([],token: 100)); XCTAssertEqual(h.album.loads,1)
        h.album.emit(list([],token: 0,cached: true,loading: true)); h.album.emit(list([],token: 100))
        XCTAssertEqual(h.album.loads,2)
    }
    func testCachedFailureNeedsRetry() {
        let h = Harness(main: list([],token: 0,cached: true),album: list([],token: 0,cached: true))
        XCTAssertEqual(h.album.loads,0); h.submit(); XCTAssertTrue(h.result.added.isEmpty)
        XCTAssertEqual(h.main.loads,1); XCTAssertEqual(h.album.loads,1)
    }
    func testWrongAlbumPeerCannotSubmit() {
        let h = Harness(album: list([],peer: 20)); h.toggle(1); h.submit(); XCTAssertTrue(h.result.added.isEmpty)
    }
    func testMissingPeerCannotSubmit() {
        let h = Harness(main: list([item(1)],peer: nil)); h.submit(); XCTAssertTrue(h.result.added.isEmpty)
    }
    func testSubmitIsOneShotDuringClosingAnimation() {
        let h = Harness(); h.toggle(1); h.submit(); h.submit(); h.toggle(2)
        XCTAssertEqual(h.result.added.count,1); XCTAssertEqual(h.modal.closes,1)
    }
    func testReentrantSubmitIsOneShot() {
        let h = Harness(); h.result.onSubmit = { [weak h] in h?.result.onSubmit = nil; h?.submit() }; h.toggle(1); h.submit()
        XCTAssertEqual(h.result.added.count,1); XCTAssertEqual(h.modal.closes,1)
    }
    func testDisappearDisposesBothSubscriptionsAndRetainedActions() {
        let h = Harness(); let action = h.controller.latest!.arguments.toggleSelected
        let scroll = h.controller.tableView.handler; h.close()
        XCTAssertEqual(h.main.subscribers,0); XCTAssertEqual(h.album.subscribers,0); XCTAssertNil(h.controller.contextObject)
        action(.init(peerId: 10,id: 1)); h.submit(); scroll?(.init(direction: .bottom)); h.retry()
        XCTAssertTrue(h.result.added.isEmpty); XCTAssertEqual(h.main.loads,0); XCTAssertEqual(h.album.loads,0)
    }
    func testReentrantCloseOnStatePublicationPreventsSubmit() {
        let h = Harness(); h.toggle(1)
        var closed = false
        h.controller.onData = { [weak h] in if !closed { closed = true; h?.close() } }
        h.submit(); XCTAssertTrue(h.result.added.isEmpty); XCTAssertEqual(h.main.subscribers,0)
    }
    func testCloseBeforeDisposalPreventsReentrantRetry() {
        let h = Harness(album: list([],token: 100))
        h.album.onDispose = { [weak h] in h?.retry(); h?.submit() }; let loads = h.album.loads; h.close()
        XCTAssertEqual(h.album.loads,loads); XCTAssertTrue(h.result.added.isEmpty)
    }
    func testDeletedSelectedStoryDoesNotWedgeSubmission() {
        let h = Harness(); h.toggle(1); h.main.emit(list([item(2)])); h.submit()
        XCTAssertEqual(h.result.added.first,[]); XCTAssertEqual(h.modal.closes,1)
    }
    func testSelectedStoryReloadsBeyondFirstPageBeforeSubmission() {
        let h = Harness(); h.toggle(1)
        h.main.emit(list([item(2)],token: 100,cached: true,loading: true))
        h.main.emit(list([item(2)],token: 100)); XCTAssertEqual(h.main.loads,1)
        h.submit(); XCTAssertTrue(h.result.added.isEmpty)
        h.main.emit(list([item(2),item(1,text: "fresh page")]))
        h.submit(); XCTAssertEqual(h.result.added.first?.first?.text,"fresh page")
    }
    func testMissingSelectionPageFailureRequiresExplicitRetry() {
        let h = Harness(); h.toggle(1); h.main.emit(list([item(2)],token: 100)); XCTAssertEqual(h.main.loads,1)
        h.main.emit(list([item(2)],token: 100,loading: true)); h.main.emit(list([item(2)],token: 100))
        XCTAssertEqual(h.main.loads,1); h.retry(); XCTAssertEqual(h.main.loads,2)
    }
    func testSynchronousSelectionPageDrainFindsLatestStory() {
        let h = Harness(); h.toggle(1)
        h.main.onLoad = { [weak main = h.main] in
            guard let main else { return }
            if main.loads == 1 { main.emit(list([item(2),item(3)],token: 200)) }
            else { main.emit(list([item(2),item(3),item(1,text: "last")])) }
        }
        h.main.emit(list([item(2)],token: 100)); h.submit()
        XCTAssertEqual(h.main.loads,2); XCTAssertEqual(h.result.added.first?.first?.text,"last")
    }
    func testSelectedStoryChangedToPendingIsDiscarded() {
        let h = Harness(); h.toggle(1); h.main.emit(list([item(1,pending: true),item(2)])); h.submit()
        XCTAssertEqual(h.result.added.first,[]); XCTAssertEqual(h.modal.closes,1)
    }
    func testInvalidStoryIdsCannotToggle() {
        let h = Harness(main: list([item(0),item(-1)])); h.toggle(0); h.toggle(-1); h.submit()
        XCTAssertEqual(h.result.added.first,[])
    }
    func testNoAlbumPaginationAfterSubmit() {
        let h = Harness(); h.submit(); h.album.emit(list([item(1)],token: 100)); XCTAssertEqual(h.album.loads,0)
    }
    func testAlbumFinishingRefreshStartsMissingSelectionLookup() {
        let h = Harness(); h.toggle(1)
        h.album.emit(list([],token: 0,cached: true,loading: true))
        h.main.emit(list([item(2)],token: 100)); XCTAssertEqual(h.main.loads,0)
        h.album.emit(list([])); XCTAssertEqual(h.main.loads,1)
    }
    func testRetryDoesNotStartAlbumLoadAfterReentrantClose() {
        let h = Harness(main: list([],token: 0,cached: true),album: list([],token: 0,cached: true))
        h.main.onLoad = { [weak h] in h?.close() }; h.retry()
        XCTAssertEqual(h.main.loads,1); XCTAssertEqual(h.album.loads,0)
    }
    func testDeinitReleasesSubscriptionsWithoutDisappear() {
        var h: Harness? = Harness(); let main = h!.main; let album = h!.album
        weak var controller = h!.controller; weak var modal = h!.modal; h = nil
        XCTAssertNil(controller); XCTAssertNil(modal); XCTAssertEqual(main.subscribers,0); XCTAssertEqual(album.subscribers,0)
    }
    func testOwnedContextsReleaseAfterDisappearWhileModalRetained() {
        let context = Context(); weak var main: PeerStoryListContext?; weak var album: PeerStoryListContext?
        context.account.onCreate = { value, folder in if folder == nil { main = value } else { album = value } }
        let modal = SelectStoryModalController(context: context,folderId: 7,peerId: 10,listContext: nil,callback: { _,_ in })
        XCTAssertNotNil(main); XCTAssertNotNil(album); modal.controller.afterDisappear?(); XCTAssertNil(main); XCTAssertNil(album)
    }
}
