import Foundation
import XCTest
import SwiftSignalKit

typealias PeerId = Int
extension Int { func toInt64() -> Int64 { Int64(self) } }
struct Peer { let id: Int }
struct EnginePeer: Equatable {
    typealias Id = Int
    let id: Int
    init(_ peer: Peer) { self.id = peer.id }
}
struct EngineStoryPrivacy: Codable, Equatable {
    enum Base: String, Codable, CaseIterable { case everyone, contacts, closeFriends, nobody }
    var base: Base
    var additionallyIncludePeers: [Int]
}
__PRIVACY__

struct StoryPosterState { let privacy: StoryPosterResultPrivacy? }
struct StoryItem { let privacy: EngineStoryPrivacy? }
struct Story { let storyItem: StoryItem }
enum StoryPrivacyReason { case share, upload, settings(Story) }
struct RenderedPeer: Equatable { let peerId: Int }
struct State: Equatable {
    var privacy: StoryPosterResultPrivacy
    var privacyLoaded = false
    var initited = false
    var peers: [Int: EnginePeer] = [:]
    var blockedPeers: [RenderedPeer] = []
    var caption = ""
    var friends: [EnginePeer] = []
    var sendAsPeers: [Int] = []
}
func defaults() -> StoryPosterResultPrivacy {
    .init(sendAsPeerId: 10, privacyEveryone: .init(base: .everyone, additionallyIncludePeers: []), privacyContacts: .init(base: .contacts, additionallyIncludePeers: []), privacyFriends: .init(base: .closeFriends, additionallyIncludePeers: []), privacyNobody: .init(base: .nobody, additionallyIncludePeers: []), selectedPrivacy: .everyone, isForwardingDisabled: false, pin: true)
}
enum TelegramEngine {
    enum EngineData { enum Item { enum Contacts { struct CloseFriends {} } } }
}
final class DataEngine {
    let values = ValuePromise<[EnginePeer]>([], ignoreRepeated: true)
    func get(_ item: TelegramEngine.EngineData.Item.Contacts.CloseFriends) -> Signal<[EnginePeer], NoError> { values.get() |> take(1) }
    func subscribe(_ item: TelegramEngine.EngineData.Item.Contacts.CloseFriends) -> Signal<[EnginePeer], NoError> { values.get() }
}
final class Engine {
    let data = DataEngine()
    let privacy = CloseFriendsService()
    let initial = Promise<StoryPosterState?>()
    var saves: [StoryPosterResultPrivacy] = []
    init() { initial.set(.single(nil)) }
}
func storyPosterState(engine: Engine) -> Signal<StoryPosterState?, NoError> { engine.initial.get() }
func updateStoryPosterStateInteractively(engine: Engine, _ f: @escaping (StoryPosterState?) -> StoryPosterState?) -> Signal<Never, NoError> {
    Signal { subscriber in
        if let value = f(nil)?.privacy { engine.saves.append(value) }
        subscriber.putCompletion()
        return EmptyDisposable
    }
}
struct Transaction { func getPeer(_ id: Int) -> Peer? { Peer(id: id) } }
final class Query {
    var finish: (() -> Void)?
    var cancelled = false
}
final class Postbox {
    var queries: [Query] = []
    var synchronous = false
    func transaction<T>(_ f: @escaping (Transaction) -> T) -> Signal<T, NoError> {
        Signal { subscriber in
            let query = Query()
            query.finish = { subscriber.putNext(f(Transaction())); subscriber.putCompletion() }
            self.queries.append(query)
            if self.synchronous { query.finish?() }
            return ActionDisposable { query.cancelled = true; query.finish = nil }
        }
    }
}
final class Account { let postbox = Postbox() }
final class Context { let engine = Engine(); let account = Account(); let peerId = 10 }
enum SaveError { case generic }
struct BlockedState: Equatable {
    var isLoadingMore: Bool
    var canLoadMore: Bool
    var totalCount: Int?
    var peers: [RenderedPeer]
    init(_ ids: [Int], loading: Bool = false, more: Bool = false, count: Int? = nil) {
        peers = ids.map { RenderedPeer(peerId: $0) }
        isLoadingMore = loading; canLoadMore = more; totalCount = count ?? ids.count
    }
}
final class SaveRequest {
    let ids: [Int]
    var subscriber: Subscriber<Never, SaveError>?
    var cancelled = false
    init(_ ids: [Int]) { self.ids = ids }
    func succeed() { subscriber?.putCompletion() }
    func fail() { subscriber?.putError(.generic) }
}
final class CloseFriendsService {
    var saves: [SaveRequest] = []
    var onStart: ((SaveRequest) -> Void)?
    func updateCloseFriends(peerIds: [Int]) -> Signal<Never, SaveError> {
        Signal { subscriber in
            let request = SaveRequest(peerIds); request.subscriber = subscriber
            self.saves.append(request); self.onStart?(request)
            return ActionDisposable { request.cancelled = true; request.subscriber = nil }
        }
    }
}
final class BlockedPeersContext {
    let values = ValuePromise(BlockedState([], loading: true, more: true), ignoreRepeated: true)
    var state: Signal<BlockedState, NoError> { values.get() }
    var loads = 0
    var nextPages: [BlockedState] = []
    var saves: [SaveRequest] = []
    func loadMore() {
        loads += 1
        if !nextPages.isEmpty { values.set(nextPages.removeFirst()) }
    }
    func updatePeerIds(_ ids: [Int]) -> Signal<Never, SaveError> {
        Signal { subscriber in
            let request = SaveRequest(ids)
            request.subscriber = subscriber
            self.saves.append(request)
            return ActionDisposable { request.cancelled = true; request.subscriber = nil }
        }
    }
}
struct Presentation {}
struct GeneralRowItem { struct Theme { static func initialize(_ presentation: Presentation) -> Int { 0 } } }
struct SelectContactsBehavior { init(customTheme: () -> Int) {} }
struct Strings {
    let unknownError = "error"
    let storyPrivacySelectHideFrom = "hide"
    let storyPrivacySelectTitleCloseFriends = "friends"
    let storyPrivacySelectTitleContacts = "except"
    let storyPrivacySelectTitleNobody = "selected"
}
func strings() -> Strings { Strings() }
final class Picker {
    let selected: Set<Int>
    var subscriber: Subscriber<[Int], NoError>?
    var cancelled = false
    init(_ ids: Set<Int>) { selected = ids }
    func choose(_ ids: [Int]) { subscriber?.putNext(ids); subscriber?.putCompletion() }
    func close() { subscriber?.putCompletion() }
}
final class Window {
    var pickers: [Picker] = []
    var progress: [MetaDisposable] = []
    var alerts = 0
    var onPicker: ((Picker) -> Void)?
}
func alert(for window: Window, info: String) { window.alerts += 1 }
func selectModalPeers(window: Window, context: Context, title: String, behavior: SelectContactsBehavior, selectedPeerIds: Set<Int>) -> Signal<[Int], NoError> {
    let picker = Picker(selectedPeerIds)
    window.pickers.append(picker)
    return Signal { subscriber in
        picker.subscriber = subscriber
        window.onPicker?(picker)
        return ActionDisposable { picker.cancelled = true; picker.subscriber = nil }
    }
}
func showModalProgress<T, E>(signal: Signal<T, E>, for window: Window) -> Signal<T, E> {
    Signal { subscriber in
        let child = MetaDisposable()
        window.progress.append(child)
        child.set(signal.start(next: subscriber.putNext, error: { error in
            subscriber.putError(error); child.dispose()
        }, completed: {
            subscriber.putCompletion(); child.dispose()
        }))
        return child
    }
}
__HELPER__

final class Controller { var willDisappear: (Int) -> Void = { _ in } }

final class Rig {
    let controller = Controller()
    let context = Context()
    let blockedContext = BlockedPeersContext()
    let window = Window()
    let actionsDisposable = DisposableSet()
    let stateValue = Atomic(value: State(privacy: defaults()))
    let statePromise = ValuePromise<State>(ignoreRepeated: true)
    var editBlockList: (() -> Void)?
    var selectAudience: ((EngineStoryPrivacy) -> Void)?
    var value: State { stateValue.with { $0 } }
    func update(_ f: (State) -> State) { statePromise.set(stateValue.modify(f)) }
    func start(_ reason: StoryPrivacyReason = .upload) {
        let controller = self.controller
        let context = self.context
        let blockedContext = self.blockedContext
        let window = self.window
        let presentation = Presentation()
        let stateValue = self.stateValue
        let statePromise = self.statePromise
        let actionsDisposable = self.actionsDisposable
        let updateState: ((State) -> State) -> Void = { f in statePromise.set(stateValue.modify(f)) }
        if case let .settings(story) = reason, let privacy = story.storyItem.privacy {
            _ = stateValue.modify { state in var state = state; state.privacy.selectedPrivacy = privacy.base; return state }
        }
        __INITIAL__
        __FIELDS__
        __SELECT__
        selectAudience = selectPeers
        __DISAPPEAR__
        __OBSERVER__
        let adminedChannelsWithParticipants = Signal<[Int], NoError>.single([])
        __COMBINED__
        editBlockList = {
            __BLOCK__
        }
    }
    var visible: Bool { let predicate: (State) -> Bool = __GATE__; return predicate(value) }
    deinit { actionsDisposable.dispose() }
}

final class StoryPrivacyTests: XCTestCase {

    func ready() -> Rig {
        let rig = Rig(); rig.context.account.postbox.synchronous = true; rig.start()
        return rig
    }
    func testLiveCloseFriendsUpdatesRefreshDisplayedAndSelectedList() {
        let rig = ready()
        rig.context.engine.data.values.set([EnginePeer(Peer(id: 1))])
        XCTAssertEqual(rig.value.friends.map(\.id), [1])
        rig.context.engine.data.values.set([EnginePeer(Peer(id: 2))])
        XCTAssertEqual(rig.value.friends.map(\.id), [2])
        rig.selectAudience?(.init(base: .closeFriends, additionallyIncludePeers: []))
        XCTAssertEqual(rig.window.pickers.first?.selected, Set([2]))
    }
    func testParentDisposalStopsLiveCloseFriendsUpdates() {
        let rig = ready()
        rig.actionsDisposable.dispose()
        rig.context.engine.data.values.set([EnginePeer(Peer(id: 1))])
        XCTAssertTrue(rig.value.friends.isEmpty)
    }
    func testSynchronousCloseFriendsFailureShowsErrorAndAllowsRetry() {
        let rig = ready()
        rig.window.onPicker = { $0.choose([1]) }
        rig.context.engine.privacy.onStart = { $0.fail() }
        rig.selectAudience?(.init(base: .closeFriends, additionallyIncludePeers: []))
        rig.selectAudience?(.init(base: .closeFriends, additionallyIncludePeers: []))
        XCTAssertEqual(rig.window.alerts, 2)
        XCTAssertEqual(rig.context.engine.privacy.saves.count, 2)
    }
    func testAudiencePickerUsesCategorySpecificSelection() {
        for base in [EngineStoryPrivacy.Base.everyone, .contacts, .nobody] {
            let rig = ready()
            rig.selectAudience?(.init(base: base, additionallyIncludePeers: [1, 2]))
            XCTAssertEqual(rig.window.pickers.first?.selected, Set([1, 2]))
            rig.window.pickers.first?.choose([3, 4])
            let privacy = rig.value.privacy
            let selected = base == .everyone ? privacy.privacyEveryone : base == .contacts ? privacy.privacyContacts : privacy.privacyNobody
            XCTAssertEqual(selected.additionallyIncludePeers, [3, 4])
            XCTAssertTrue(rig.context.engine.privacy.saves.isEmpty)
        }
    }
    func testCloseFriendsUsesLiveFriendsInsteadOfCategoryExceptions() {
        let rig = ready()
        rig.update { state in var state = state; state.friends = [EnginePeer(Peer(id: 3))]; return state }
        rig.selectAudience?(.init(base: .closeFriends, additionallyIncludePeers: [1, 2]))
        XCTAssertEqual(rig.window.pickers.first?.selected, Set([3]))
        rig.window.pickers.first?.choose([4, 5])
        XCTAssertEqual(rig.context.engine.privacy.saves.first?.ids, [4, 5])
        XCTAssertEqual(rig.value.friends.map(\.id), [3])
        XCTAssertTrue(rig.value.privacy.privacyFriends.additionallyIncludePeers.isEmpty)
    }
    func testDuplicateAudienceClicksDoNotOpenMultiplePickers() {
        let rig = ready()
        rig.selectAudience?(.init(base: .everyone, additionallyIncludePeers: []))
        rig.selectAudience?(.init(base: .nobody, additionallyIncludePeers: []))
        XCTAssertEqual(rig.window.pickers.count, 1)
    }
    func testCanceledAudiencePickerCanReopen() {
        let rig = ready()
        rig.selectAudience?(.init(base: .everyone, additionallyIncludePeers: []))
        rig.window.pickers.first?.close()
        rig.selectAudience?(.init(base: .contacts, additionallyIncludePeers: []))
        XCTAssertEqual(rig.window.pickers.count, 2)
    }
    func testPendingCloseFriendsSaveBlocksOtherPickers() {
        let rig = ready()
        rig.selectAudience?(.init(base: .closeFriends, additionallyIncludePeers: []))
        rig.window.pickers.first?.choose([1])
        rig.selectAudience?(.init(base: .everyone, additionallyIncludePeers: [])); rig.editBlockList?()
        XCTAssertEqual(rig.window.pickers.count, 1)
        XCTAssertEqual(rig.blockedContext.loads, 0)
        rig.context.engine.privacy.saves.first?.succeed()
        rig.selectAudience?(.init(base: .everyone, additionallyIncludePeers: []))
        XCTAssertEqual(rig.window.pickers.count, 2)
    }
    func testFailedCloseFriendsSaveShowsErrorAndAllowsRetry() {
        let rig = ready()
        rig.selectAudience?(.init(base: .closeFriends, additionallyIncludePeers: []))
        rig.window.pickers.first?.choose([1]); rig.context.engine.privacy.saves.first?.fail()
        XCTAssertEqual(rig.window.alerts, 1)
        rig.selectAudience?(.init(base: .closeFriends, additionallyIncludePeers: []))
        XCTAssertEqual(rig.window.pickers.count, 2)
    }
    func testProgressCancelAllowsAnotherAudienceOperation() {
        let rig = ready()
        rig.selectAudience?(.init(base: .closeFriends, additionallyIncludePeers: []))
        rig.window.pickers.first?.choose([1]); rig.window.progress.last?.dispose()
        XCTAssertTrue(rig.context.engine.privacy.saves.first?.cancelled == true)
        rig.selectAudience?(.init(base: .everyone, additionallyIncludePeers: []))
        XCTAssertEqual(rig.window.pickers.count, 2)
    }
    func testDisappearingParentCancelsAudiencePickerAndCannotReopen() {
        let rig = ready()
        rig.selectAudience?(.init(base: .everyone, additionallyIncludePeers: []))
        rig.controller.willDisappear(0); rig.window.pickers.first?.choose([1])
        XCTAssertTrue(rig.window.pickers.first?.cancelled == true)
        XCTAssertTrue(rig.value.privacy.privacyEveryone.additionallyIncludePeers.isEmpty)
        rig.selectAudience?(.init(base: .everyone, additionallyIncludePeers: [])); rig.editBlockList?()
        XCTAssertEqual(rig.window.pickers.count, 1); XCTAssertEqual(rig.blockedContext.loads, 0)
    }
    func testDisappearingParentCancelsCloseFriendsSave() {
        let rig = ready()
        rig.selectAudience?(.init(base: .closeFriends, additionallyIncludePeers: []))
        rig.window.pickers.first?.choose([1]); rig.controller.willDisappear(0)
        XCTAssertTrue(rig.context.engine.privacy.saves.first?.cancelled == true)
        rig.context.engine.privacy.saves.first?.fail()
        XCTAssertEqual(rig.window.alerts, 0)
    }
    func testDisappearingParentCancelsBlocklistWorkWhileRetained() {
        let rig = ready(); rig.editBlockList?(); rig.controller.willDisappear(0)
        rig.blockedContext.values.set(.init([1]))
        XCTAssertTrue(rig.window.pickers.isEmpty)
    }
    func testSynchronousPickerAndSaveDoNotLeaveOperationBusy() {
        let rig = ready()
        rig.window.onPicker = { $0.choose([1]) }
        rig.context.engine.privacy.onStart = { $0.succeed() }
        rig.selectAudience?(.init(base: .closeFriends, additionallyIncludePeers: []))
        rig.selectAudience?(.init(base: .closeFriends, additionallyIncludePeers: []))
        XCTAssertEqual(rig.context.engine.privacy.saves.count, 2)
    }
    func testAudiencePickerWaitsForInitializationAndBlocklist() {
        let rig = Rig(); rig.start()
        rig.selectAudience?(.init(base: .everyone, additionallyIncludePeers: []))
        XCTAssertTrue(rig.window.pickers.isEmpty)
        rig.context.account.postbox.queries.first?.finish?()
        rig.editBlockList?(); rig.selectAudience?(.init(base: .everyone, additionallyIncludePeers: []))
        XCTAssertTrue(rig.window.pickers.isEmpty)
    }
    func testParentReleaseCancelsAudienceSubscription() {
        var rig: Rig? = ready(); weak var weakRig = rig
        rig?.selectAudience?(.init(base: .everyone, additionallyIncludePeers: []))
        let picker = rig?.window.pickers.first
        rig = nil
        XCTAssertNil(weakRig); XCTAssertTrue(picker?.cancelled == true)
    }

    func testExistingStoryRulesSurviveMissingPostingPreferences() {
        for base in EngineStoryPrivacy.Base.allCases {
            let rig = Rig()
            let privacy = EngineStoryPrivacy(base: base, additionallyIncludePeers: [42, 43])
            rig.start(.settings(.init(storyItem: .init(privacy: privacy))))
            let actual: EngineStoryPrivacy
            switch base {
            case .everyone: actual = rig.value.privacy.privacyEveryone
            case .contacts: actual = rig.value.privacy.privacyContacts
            case .closeFriends: actual = rig.value.privacy.privacyFriends
            case .nobody: actual = rig.value.privacy.privacyNobody
            }
            XCTAssertEqual(actual, privacy)
            XCTAssertNil(rig.value.privacy.sendAsPeerId)
            XCTAssertTrue(rig.context.engine.saves.isEmpty)
        }
    }
    func testExistingStoryCategoryOverridesStoredPostingCategory() {
        let rig = Rig()
        var stored = defaults(); stored.selectedPrivacy = .nobody
        rig.context.engine.initial.set(.single(.init(privacy: stored)))
        rig.start(.settings(.init(storyItem: .init(privacy: .init(base: .contacts, additionallyIncludePeers: [3])))))
        XCTAssertEqual(rig.value.privacy.selectedPrivacy, .contacts)
        XCTAssertEqual(rig.value.privacy.privacyContacts.additionallyIncludePeers, [3])
    }
    func testUploadUsesStoredPreferences() {
        let rig = Rig()
        var stored = defaults(); stored.privacyEveryone.additionallyIncludePeers = [8]; stored.pin = false
        rig.context.engine.initial.set(.single(.init(privacy: stored)))
        rig.start()
        XCTAssertEqual(rig.value.privacy, stored)
    }
    func testScreenWaitsForInitialPrivacyEvenIfOtherDataArrives() {
        let rig = Rig()
        rig.context.engine.initial.set(.never())
        rig.start()
        rig.update { state in var state = state; state.initited = true; return state }
        XCTAssertFalse(rig.visible)
        XCTAssertTrue(rig.context.engine.saves.isEmpty)
        rig.context.engine.initial.set(.single(nil))
        rig.context.account.postbox.queries.last?.finish?()
        XCTAssertTrue(rig.visible)
    }
    func testPreferenceInitializationIsOneShot() {
        let rig = Rig(); rig.start()
        rig.update { state in var state = state; state.privacy.pin = false; return state }
        rig.context.engine.initial.set(.single(.init(privacy: defaults())))
        XCTAssertFalse(rig.value.privacy.pin)
    }
    func testNewPeerLookupCancelsOldAndCannotLoseCurrentNames() {
        let rig = Rig(); rig.start()
        rig.update { state in var state = state; state.privacy.privacyEveryone.additionallyIncludePeers = [2]; return state }
        XCTAssertEqual(rig.context.account.postbox.queries.count, 2)
        XCTAssertTrue(rig.context.account.postbox.queries[0].cancelled)
        rig.context.account.postbox.queries[1].finish?()
        rig.context.account.postbox.queries[0].finish?()
        XCTAssertEqual(Set(rig.value.peers.keys), [2, 10])
    }
    func testSynchronousLookupDoesNotStartDuplicateRead() {
        let rig = Rig(); rig.context.account.postbox.synchronous = true; rig.start()
        XCTAssertEqual(rig.context.account.postbox.queries.count, 1)
        XCTAssertTrue(rig.value.initited)
    }
    func testCaptionAndPeerUpdatesDoNotRewritePrivacyPreferences() {
        let rig = Rig(); rig.start()
        let count = rig.context.engine.saves.count
        rig.context.account.postbox.queries[0].finish?()
        for i in 0..<20 { rig.update { state in var state = state; state.caption = "\(i)"; return state } }
        XCTAssertEqual(rig.context.engine.saves.count, count)
        rig.update { state in var state = state; state.privacy.pin.toggle(); return state }
        XCTAssertEqual(rig.context.engine.saves.count, count + 1)
    }
    func testSynchronousLookupReentryDoesNotPersistOlderPrivacy() {
        let rig = Rig(); rig.context.account.postbox.synchronous = true
        var change = true
        let subscription = rig.statePromise.get().start(next: { state in
            if change, state.initited {
                change = false
                rig.update { state in var state = state; state.privacy.pin = false; return state }
            }
        })
        rig.start()
        XCTAssertFalse(rig.context.engine.saves.last!.pin)
        subscription.dispose()
    }
    func testClosingScreenCancelsOutstandingPeerLookup() {
        var rig: Rig? = Rig(); rig!.start()
        let query = rig!.context.account.postbox.queries[0]
        weak var weakRig = rig
        rig = nil
        XCTAssertNil(weakRig)
        XCTAssertTrue(query.cancelled)
    }
    func testBlockPickerWaitsForEntireList() {
        let rig = Rig(); rig.start(); rig.editBlockList?()
        XCTAssertTrue(rig.window.pickers.isEmpty)
        rig.blockedContext.values.set(.init([1, 2], more: true, count: 3))
        XCTAssertEqual(rig.blockedContext.loads, 1)
        XCTAssertTrue(rig.window.pickers.isEmpty)
        rig.blockedContext.values.set(.init([1, 2, 3]))
        XCTAssertEqual(rig.window.pickers.count, 1)
        XCTAssertEqual(rig.window.pickers.last?.selected, [1, 2, 3])
    }
    func testBlockPickerSupportsSynchronousPageDrain() {
        let rig = Rig(); rig.start()
        rig.blockedContext.values.set(.init([1], more: true, count: 3))
        rig.blockedContext.nextPages = [.init([1, 2], more: true, count: 3), .init([1, 2, 3])]
        rig.editBlockList?()
        XCTAssertEqual(rig.blockedContext.loads, 2)
        XCTAssertEqual(rig.window.pickers.last?.selected, [1, 2, 3])
    }
    func testIncompleteBlockListDoesNotOpenDestructiveReplacementPicker() {
        let rig = Rig(); rig.start()
        rig.blockedContext.values.set(.init([1], count: 3))
        rig.editBlockList?()
        XCTAssertTrue(rig.window.pickers.isEmpty)
        XCTAssertEqual(rig.window.alerts, 1)
        XCTAssertTrue(rig.blockedContext.saves.isEmpty)
    }
    func testRepeatedClickDoesNotOpenDuplicatePicker() {
        let rig = Rig(); rig.start()
        rig.blockedContext.values.set(.init([1]))
        rig.editBlockList?(); rig.editBlockList?()
        XCTAssertEqual(rig.window.pickers.count, 1)
    }
    func testPickerCancellationAllowsReopeningWithoutSave() {
        let rig = Rig(); rig.start(); rig.blockedContext.values.set(.init([1]))
        rig.editBlockList?(); rig.window.pickers[0].close(); rig.editBlockList?()
        XCTAssertEqual(rig.window.pickers.count, 2)
        XCTAssertTrue(rig.blockedContext.saves.isEmpty)
    }
    func testFailedSaveReportsErrorAndAllowsRetry() {
        let rig = Rig(); rig.start(); rig.blockedContext.values.set(.init([1]))
        rig.editBlockList?(); rig.window.pickers[0].choose([2])
        rig.blockedContext.saves[0].fail()
        XCTAssertEqual(rig.window.alerts, 1)
        rig.editBlockList?()
        XCTAssertEqual(rig.window.pickers.count, 2)
        XCTAssertEqual(rig.window.pickers.last?.selected, [1])
    }
    func testSaveMustFinishBeforeAnotherPickerOpens() {
        let rig = Rig(); rig.start(); rig.blockedContext.values.set(.init([1]))
        rig.editBlockList?(); rig.window.pickers[0].choose([2]); rig.editBlockList?()
        XCTAssertEqual(rig.window.pickers.count, 1)
        rig.blockedContext.saves[0].succeed(); rig.editBlockList?()
        XCTAssertEqual(rig.window.pickers.count, 2)
    }
    func testClosingScreenCancelsPendingBlockSave() {
        let rig = Rig(); rig.start(); rig.blockedContext.values.set(.init([1]))
        rig.editBlockList?(); rig.window.pickers[0].choose([2])
        rig.actionsDisposable.dispose()
        XCTAssertTrue(rig.blockedContext.saves[0].cancelled)
        rig.blockedContext.saves[0].fail()
        XCTAssertEqual(rig.window.alerts, 0)
    }
    func testClosingParentIgnoresLatePickerSelection() {
        let rig = Rig(); rig.start(); rig.blockedContext.values.set(.init([1]))
        rig.editBlockList?()
        rig.actionsDisposable.dispose()
        rig.window.pickers[0].choose([2])
        XCTAssertTrue(rig.blockedContext.saves.isEmpty)
        XCTAssertTrue(rig.window.pickers[0].cancelled)
    }
    func testClosingParentDuringLoadingCannotOpenPickerLater() {
        let rig = Rig(); rig.start(); rig.editBlockList?()
        rig.actionsDisposable.dispose()
        rig.blockedContext.values.set(.init([1, 2]))
        XCTAssertTrue(rig.window.pickers.isEmpty)
        XCTAssertTrue(rig.blockedContext.saves.isEmpty)
    }
    func testCancellingProgressAllowsNewBlockOperation() {
        let rig = Rig(); rig.start(); rig.editBlockList?()
        guard let progress = rig.window.progress.first else { XCTFail("No loading progress"); return }
        progress.dispose()
        rig.blockedContext.values.set(.init([1, 2]))
        rig.editBlockList?()
        XCTAssertEqual(rig.window.pickers.count, 1)
        XCTAssertEqual(rig.window.pickers.last?.selected, [1, 2])
    }
    func testCancellingSaveProgressAllowsRetry() {
        let rig = Rig(); rig.start(); rig.blockedContext.values.set(.init([1]))
        rig.editBlockList?(); rig.window.pickers[0].choose([2])
        guard let progress = rig.window.progress.last else { XCTFail("No saving progress"); return }
        progress.dispose()
        XCTAssertTrue(rig.blockedContext.saves[0].cancelled)
        rig.editBlockList?()
        XCTAssertEqual(rig.window.pickers.count, 2)
    }
}
