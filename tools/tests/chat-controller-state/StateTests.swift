import Foundation
import XCTest
import SwiftSignalKit

typealias PeerId = Int64
typealias MessageId = Int
struct Message: Equatable { let id: MessageId }
struct EngineMessageReplySubject: Equatable {
    let messageId: MessageId
    var quote: String? = nil
}
enum ChatMode { case history, thread, scheduled, pinned
    var isThreadMode: Bool { self == .thread }
}
struct ChatLocation { var threadId: Int64? }
struct History { var filteredEntries = [1, 2] }
struct HistoryState { var isDownOfHistory = true }
struct Scroll { var rect = CGRect(x: 0, y: 600, width: 800, height: 600) }
final class ClipView { var isAnimateScrolling = false }
final class TableView { let clipView = ClipView()
    func notifyScrollHandlers() {}
    var frame = CGRect(x: 0, y: 0, width: 800, height: 600) }
final class View { var scroll = Scroll(); let tableView = TableView() }
final class Window { var isKeyWindow = true; var alerts: [String] = [] }
func alert(for window: Window, info: String) { window.alerts.append(info) }
struct Strings { var unknownError: String { "Unknown error" } }
func strings() -> Strings { Strings() }
enum EditMedia { case keep, update }
enum LoadingState: Equatable { case none, loading, progress(Float) }
enum EditResult { case progress(Float), done(Bool) }
enum EditError: Error { case generic, restricted }
final class EditObservation {
    enum Blocker { case permission, requestFailed }
    enum Result { case applied, failed(Blocker) }
    func complete(buildResult: () -> Result?) {}
    func discard() {}
}
struct EditState {
    let message: Message
    var editMedia = EditMedia.keep
    var inputText = "draft"
    var loadingState = LoadingState.loading
    func withUpdatedLoadingState(_ value: LoadingState) -> Self {
        var result = self; result.loadingState = value; return result
    }
}
final class ChatUIHooks {
    static let shared = ChatUIHooks()
    let locked = ValuePromise<Bool>(false, ignoreRepeated: true)
    var lockedValue = false
    func appIsLocked() -> Signal<Bool, NoError>? { locked.get() }
    func appIsLockedValue() -> Bool? { lockedValue }
    func setLocked(_ value: Bool) { lockedValue = value; locked.set(value) }
}
final class EngineMessages {
    var activeMessageHooks = 0
    var activeReactionHooks = 0
    var installations = 0
    var readMessages: [Int] = []
    func installInteractiveReadMessagesAction(peerId: PeerId, threadId: Int64?) -> Disposable {
        activeMessageHooks += 1
        installations += 1
        return ActionDisposable { [weak self] in self?.activeMessageHooks -= 1 }
    }
    func installInteractiveReadReactionsAction(peerId: PeerId, getVisibleRange: @escaping () -> Int?, didReadReactionsInMessages: @escaping ([Int: [Int]]) -> Void) -> Disposable {
        activeReactionHooks += 1
        return ActionDisposable { [weak self] in self?.activeReactionHooks -= 1 }
    }
    func receive(_ id: Int) {
        if activeMessageHooks > 0 { readMessages.append(id) }
    }
}
final class Engine { let messages = EngineMessages() }
final class Postbox {
    var subscribers: [Int: Subscriber<Message?, NoError>] = [:]
    var requests: [Int] = []
    var canceled: [Int] = []
    func messageAtId(_ id: MessageId) -> Signal<Message?, NoError> {
        return Signal { subscriber in
            self.requests.append(id)
            self.subscribers[id] = subscriber
            return ActionDisposable { self.canceled.append(id) }
        }
    }
    func complete(_ id: Int, found: Bool = true) {
        subscribers[id]?.putNext(found ? Message(id: id) : nil)
        subscribers[id]?.putCompletion()
    }
}
final class Account { let postbox = Postbox() }
final class Context { let window = Window(); let engine = Engine(); let account = Account() }
struct Peer {
    var canSend = true
    func canSendMessage(_ thread: Bool, threadData: Int?, cachedData: Int?) -> Bool { canSend }
}
struct KeyboardMessage { var replyAttribute: EngineMessageReplySubject? }
struct InterfaceState {
    var replyMessageId: EngineMessageReplySubject?
    var replyMessage: Message?
    var dismissedForceReplyId: MessageId?
    var editState: EditState?
    var composeDisableUrlPreview: String?
    func updatedEditState(_ f: (EditState?) -> EditState?) -> Self {
        var result = self; result.editState = f(editState); return result
    }
    func withUpdatedComposeDisableUrlPreview(_ value: String?) -> Self {
        var result = self; result.composeDisableUrlPreview = value; return result
    }
    func withUpdatedReplyMessageId(_ subject: EngineMessageReplySubject?) -> Self {
        var result = self; result.replyMessageId = subject; result.replyMessage = nil; return result
    }
    func withUpdatedReplyMessage(_ message: Message?) -> Self {
        var result = self; result.replyMessage = message; return result
    }
    func withUpdatedDismissedForceReplyId(_ id: MessageId?) -> Self {
        var result = self; result.dismissedForceReplyId = id; return result
    }
}
struct Presentation {
    var mainPeer: Peer? = Peer()
    var threadInfo: Int?
    var cachedData: Int?
    var interfaceState = InterfaceState()
    var keyboardButtonsMessage: KeyboardMessage?
    func updatedInterfaceState(_ f: (InterfaceState) -> InterfaceState) -> Self {
        var result = self; result.interfaceState = f(interfaceState); return result
    }
}
final class ChatInteraction {
    let peerId: PeerId = 1
    let interactionContext: Context
    var presentation = Presentation()
    var setupReplyMessage: (Message?, EngineMessageReplySubject?) -> Void = { _, _ in }
    var redirected: [EngineMessageReplySubject] = []
    let editDisposable = MetaDisposable()
    var mediaEditSubmissionId: UUID?
__EDIT_IDENTITY__
    init(context: Context) { interactionContext = context }
    func focusInputField() {}
    func replyToAnother(_ subject: EngineMessageReplySubject, _ flag: Bool) { redirected.append(subject) }
    func update(_ f: (Presentation) -> Presentation) { presentation = f(presentation) }
    func beginEditingMessage(_ message: Message?) { presentation.interfaceState.editState = message.map { EditState(message: $0) } }
    deinit { editDisposable.dispose() }
}
final class Harness {
    let context: Context
    let chatInteraction: ChatInteraction
    var mode = ChatMode.history
    var chatLocation = ChatLocation()
    let genericView = View()
    var historyState = HistoryState()
    let previousView = Atomic<History?>(value: History())
    let visibleMessageRange = Atomic<Int?>(value: 1)
    let isKeyWindow = Promise<Bool>(false)
    let interactiveReadStateDisposable = MetaDisposable()
    let interactiveReadingDisposable = MetaDisposable()
    let interactiveReadReactionsDisposable = MetaDisposable()
    let replyMessageDisposable = MetaDisposable()
    var interactiveReadEnabled = false
    init() {
        let context = Context()
        self.context = context
        self.chatInteraction = ChatInteraction(context: context)
__READ_SETUP__
__REPLY_SETUP__
    }
__READ_METHODS__
    func playUnseenReactions(_ ids: Set<Int>) {}
    func refresh() { updateInteractiveReading() }
    func appear() { isKeyWindow.set(.single(true)); refresh() }
    func disappear() { isKeyWindow.set(.single(false)) }
    func edit(_ state: EditState, signal: Signal<EditResult, EditError>) {
        let context = self.context
        let editSubmissionId = UUID()
        chatInteraction.mediaEditSubmissionId = editSubmissionId
        let mediaEditSubmission: EditObservation? = nil
        chatInteraction.presentation.interfaceState.editState = state
__EDIT_REQUEST__
    }
    func cleanup() {
__CLEANUP__
    }
    deinit { cleanup() }
}

final class StateTests: XCTestCase {
    override func setUp() { ChatUIHooks.shared.setLocked(false) }
    func testPreloadedChatCannotInstallReadHooks() {
        let h = Harness()
        h.refresh()
        XCTAssertEqual(h.context.engine.messages.activeMessageHooks, 0)
        XCTAssertEqual(h.context.engine.messages.activeReactionHooks, 0)
    }
    func testLeavingChatRemovesBothHooksWithoutAnotherHistoryUpdate() {
        let h = Harness()
        h.appear()
        XCTAssertEqual(h.context.engine.messages.activeMessageHooks, 1)
        h.disappear()
        XCTAssertTrue(h.context.window.isKeyWindow)
        XCTAssertEqual(h.context.engine.messages.activeMessageHooks, 0)
        XCTAssertEqual(h.context.engine.messages.activeReactionHooks, 0)
        h.context.engine.messages.receive(2)
        XCTAssertEqual(h.context.engine.messages.readMessages, [])
    }
    func testBackgroundHistoryUpdateCannotReinstallReadHooks() {
        let h = Harness()
        h.appear()
        h.disappear()
        h.refresh()
        XCTAssertEqual(h.context.engine.messages.activeMessageHooks, 0)
    }
    func testLockRemovesHooksImmediatelyAndUnlockRestoresThem() {
        let h = Harness()
        h.appear()
        ChatUIHooks.shared.setLocked(true)
        XCTAssertEqual(h.context.engine.messages.activeMessageHooks, 0)
        XCTAssertEqual(h.context.engine.messages.activeReactionHooks, 0)
        ChatUIHooks.shared.setLocked(false)
        XCTAssertEqual(h.context.engine.messages.activeMessageHooks, 1)
        XCTAssertEqual(h.context.engine.messages.activeReactionHooks, 1)
    }
    func testUnlockCannotActivateHiddenChat() {
        let h = Harness()
        h.appear()
        h.disappear()
        ChatUIHooks.shared.setLocked(true)
        ChatUIHooks.shared.setLocked(false)
        XCTAssertEqual(h.context.engine.messages.activeMessageHooks, 0)
    }
    func testReturningToChatRestoresExactlyOnePairOfHooks() {
        let h = Harness()
        h.appear()
        h.disappear()
        h.appear()
        h.refresh()
        XCTAssertEqual(h.context.engine.messages.activeMessageHooks, 1)
        XCTAssertEqual(h.context.engine.messages.activeReactionHooks, 1)
        XCTAssertEqual(h.context.engine.messages.installations, 2)
    }
    func testAnimatedJumpSuspendsReadHooksUntilItSettles() {
        let h = Harness()
        h.appear()
        h.genericView.tableView.clipView.isAnimateScrolling = true
        h.refresh()
        XCTAssertEqual(h.context.engine.messages.activeMessageHooks, 0)
        XCTAssertEqual(h.context.engine.messages.activeReactionHooks, 0)
        h.genericView.tableView.clipView.isAnimateScrolling = false
        h.refresh()
        XCTAssertEqual(h.context.engine.messages.activeMessageHooks, 1)
        XCTAssertEqual(h.context.engine.messages.activeReactionHooks, 1)
    }
    func testScrollingUpDisablesHooks() {
        let h = Harness()
        h.appear()
        h.historyState.isDownOfHistory = false
        h.refresh()
        XCTAssertEqual(h.context.engine.messages.activeMessageHooks, 0)
        h.historyState.isDownOfHistory = true
        h.refresh()
        XCTAssertEqual(h.context.engine.messages.activeMessageHooks, 1)
    }
    func testScheduledHistoryNeverInstallsHooks() {
        let h = Harness()
        h.mode = .scheduled
        h.appear()
        XCTAssertEqual(h.context.engine.messages.activeMessageHooks, 0)
    }
    func testCleanupStopsSubscriptionsAndReadHooks() {
        let h = Harness()
        h.appear()
        h.chatInteraction.setupReplyMessage(nil, .init(messageId: 1))
        h.cleanup()
        XCTAssertEqual(h.context.engine.messages.activeMessageHooks, 0)
        XCTAssertEqual(h.context.engine.messages.activeReactionHooks, 0)
        XCTAssertEqual(h.context.account.postbox.canceled, [1])
        ChatUIHooks.shared.setLocked(true)
        ChatUIHooks.shared.setLocked(false)
        XCTAssertEqual(h.context.engine.messages.activeMessageHooks, 0)
    }
    func testKnownReplyIsAvailableImmediatelyWithoutLookup() {
        let h = Harness()
        h.chatInteraction.setupReplyMessage(Message(id: 1), .init(messageId: 1, quote: "quote"))
        XCTAssertEqual(h.chatInteraction.presentation.interfaceState.replyMessage, Message(id: 1))
        XCTAssertEqual(h.chatInteraction.presentation.interfaceState.replyMessageId?.quote, "quote")
        XCTAssertEqual(h.context.account.postbox.requests, [])
    }
    func testUnknownReplyPublishesSubjectBeforeLookupCompletes() {
        let h = Harness()
        h.chatInteraction.setupReplyMessage(nil, .init(messageId: 1))
        XCTAssertEqual(h.chatInteraction.presentation.interfaceState.replyMessageId?.messageId, 1)
        h.context.account.postbox.complete(1)
        XCTAssertEqual(h.chatInteraction.presentation.interfaceState.replyMessage, Message(id: 1))
    }
    func testOlderLookupCannotReplaceNewerReply() {
        let h = Harness()
        h.chatInteraction.setupReplyMessage(nil, .init(messageId: 1))
        h.chatInteraction.setupReplyMessage(nil, .init(messageId: 2))
        h.context.account.postbox.complete(2)
        h.context.account.postbox.complete(1)
        XCTAssertEqual(h.chatInteraction.presentation.interfaceState.replyMessageId?.messageId, 2)
        XCTAssertEqual(h.chatInteraction.presentation.interfaceState.replyMessage, Message(id: 2))
    }
    func testLateLookupCannotRestoreCanceledReply() {
        let h = Harness()
        h.chatInteraction.setupReplyMessage(nil, .init(messageId: 1))
        h.chatInteraction.setupReplyMessage(nil, nil)
        h.context.account.postbox.complete(1)
        XCTAssertNil(h.chatInteraction.presentation.interfaceState.replyMessageId)
        XCTAssertNil(h.chatInteraction.presentation.interfaceState.replyMessage)
    }
    func testAccessoryDismissalOrSendCannotRestoreReply() {
        let h = Harness()
        h.chatInteraction.setupReplyMessage(nil, .init(messageId: 1))
        h.chatInteraction.update { $0.updatedInterfaceState { $0.withUpdatedReplyMessageId(nil) } }
        h.context.account.postbox.complete(1)
        XCTAssertNil(h.chatInteraction.presentation.interfaceState.replyMessageId)
        XCTAssertNil(h.chatInteraction.presentation.interfaceState.replyMessage)
    }
    func testLateLookupCannotReplaceUpdatedQuoteForSameMessage() {
        let h = Harness()
        h.chatInteraction.setupReplyMessage(nil, .init(messageId: 1, quote: "first"))
        h.chatInteraction.update { $0.updatedInterfaceState { $0.withUpdatedReplyMessageId(.init(messageId: 1, quote: "second")) } }
        h.context.account.postbox.complete(1)
        XCTAssertEqual(h.chatInteraction.presentation.interfaceState.replyMessageId?.quote, "second")
    }
    func testMismatchedKnownMessageIsLoadedUsingSubject() {
        let h = Harness()
        h.chatInteraction.setupReplyMessage(Message(id: 9), .init(messageId: 1))
        XCTAssertNil(h.chatInteraction.presentation.interfaceState.replyMessage)
        h.context.account.postbox.complete(1)
        XCTAssertEqual(h.chatInteraction.presentation.interfaceState.replyMessage, Message(id: 1))
    }
    func testDeletedReplyCanBeCleared() {
        let h = Harness()
        h.chatInteraction.setupReplyMessage(nil, .init(messageId: 1))
        h.context.account.postbox.complete(1, found: false)
        h.chatInteraction.setupReplyMessage(nil, nil)
        XCTAssertNil(h.chatInteraction.presentation.interfaceState.replyMessageId)
    }
    func testCannotReplyInScheduledMode() {
        let h = Harness()
        h.mode = .scheduled
        h.chatInteraction.setupReplyMessage(Message(id: 1), .init(messageId: 1))
        XCTAssertNil(h.chatInteraction.presentation.interfaceState.replyMessageId)
        XCTAssertEqual(h.context.account.postbox.requests, [])
    }
    func testReadOnlyChatRedirectsReply() {
        let h = Harness()
        h.chatInteraction.presentation.mainPeer = Peer(canSend: false)
        h.chatInteraction.setupReplyMessage(Message(id: 1), .init(messageId: 1))
        XCTAssertEqual(h.chatInteraction.redirected, [.init(messageId: 1)])
        XCTAssertNil(h.chatInteraction.presentation.interfaceState.replyMessageId)
    }
    func testForceReplyIsDismissedWhenSelected() {
        let h = Harness()
        h.chatInteraction.presentation.keyboardButtonsMessage = .init(replyAttribute: .init(messageId: 1))
        h.chatInteraction.setupReplyMessage(Message(id: 1), .init(messageId: 1))
        h.context.account.postbox.complete(1)
        XCTAssertEqual(h.chatInteraction.presentation.interfaceState.dismissedForceReplyId, 1)
    }
    func testScheduledEditFailureClearsSpinnerAndKeepsDraft() {
        let h = Harness()
        h.edit(EditState(message: Message(id: 1)), signal: .fail(.generic))
        XCTAssertEqual(h.chatInteraction.presentation.interfaceState.editState?.loadingState, LoadingState.none)
        XCTAssertEqual(h.chatInteraction.presentation.interfaceState.editState?.inputText, "draft")
        XCTAssertEqual(h.context.window.alerts.count, 1)
    }
    func testScheduledMediaEditFailureClearsProgress() {
        let h = Harness()
        h.edit(EditState(message: Message(id: 1), editMedia: .update, loadingState: .progress(0.2)), signal: .fail(.generic))
        XCTAssertEqual(h.chatInteraction.presentation.interfaceState.editState?.loadingState, LoadingState.none)
    }
    func testScheduledEditCompletionClearsCurrentEdit() {
        let h = Harness()
        h.edit(EditState(message: Message(id: 1)), signal: .complete())
        XCTAssertNil(h.chatInteraction.presentation.interfaceState.editState)
    }
    func testScheduledMediaProgressHasMinimumAndThenUpdates() {
        let h = Harness()
        var subscriber: Subscriber<EditResult, EditError>?
        h.edit(EditState(message: Message(id: 1), editMedia: .update), signal: Signal { subscriber = $0; return EmptyDisposable })
        subscriber?.putNext(.progress(0.01))
        XCTAssertEqual(h.chatInteraction.presentation.interfaceState.editState?.loadingState, .progress(0.2))
        subscriber?.putNext(.progress(0.7))
        XCTAssertEqual(h.chatInteraction.presentation.interfaceState.editState?.loadingState, .progress(0.7))
    }
    func testOldEditCompletionDoesNotClearNewEdit() {
        let h = Harness()
        var subscriber: Subscriber<EditResult, EditError>?
        h.edit(EditState(message: Message(id: 1)), signal: Signal { subscriber = $0; return EmptyDisposable })
        h.chatInteraction.beginEditingMessage(Message(id: 2))
        subscriber?.putCompletion()
        XCTAssertEqual(h.chatInteraction.presentation.interfaceState.editState?.message.id, 2)
    }
    func testOldEditProgressDoesNotChangeNewEdit() {
        let h = Harness()
        var subscriber: Subscriber<EditResult, EditError>?
        h.edit(EditState(message: Message(id: 1), editMedia: .update), signal: Signal { subscriber = $0; return EmptyDisposable })
        h.chatInteraction.beginEditingMessage(Message(id: 2))
        subscriber?.putNext(.progress(0.8))
        XCTAssertEqual(h.chatInteraction.presentation.interfaceState.editState?.loadingState, .loading)
    }
    func testOldEditFailureDoesNotChangeNewEditOrShowAlert() {
        let h = Harness()
        var subscriber: Subscriber<EditResult, EditError>?
        h.edit(EditState(message: Message(id: 1)), signal: Signal { subscriber = $0; return EmptyDisposable })
        h.chatInteraction.beginEditingMessage(Message(id: 2))
        subscriber?.putError(.generic)
        XCTAssertEqual(h.chatInteraction.presentation.interfaceState.editState?.message.id, 2)
        XCTAssertEqual(h.chatInteraction.presentation.interfaceState.editState?.loadingState, .loading)
        XCTAssertTrue(h.context.window.alerts.isEmpty)
    }
    func testSupersededUploadCompletionDoesNotClearSameMessageDraft() {
        let h = Harness()
        var subscriber: Subscriber<EditResult, EditError>?
        h.edit(EditState(message: Message(id: 1)), signal: Signal { subscriber = $0; return EmptyDisposable })
        h.chatInteraction.mediaEditSubmissionId = UUID()
        subscriber?.putCompletion()
        XCTAssertEqual(h.chatInteraction.presentation.interfaceState.editState?.message.id, 1)
        XCTAssertEqual(h.chatInteraction.presentation.interfaceState.editState?.inputText, "draft")
    }
    func testSupersededUploadProgressDoesNotChangeSameMessageDraft() {
        let h = Harness()
        var subscriber: Subscriber<EditResult, EditError>?
        h.edit(EditState(message: Message(id: 1), editMedia: .update, loadingState: .none), signal: Signal { subscriber = $0; return EmptyDisposable })
        h.chatInteraction.mediaEditSubmissionId = nil
        subscriber?.putNext(.progress(0.8))
        XCTAssertEqual(h.chatInteraction.presentation.interfaceState.editState?.loadingState, LoadingState.none)
    }
    func testSupersededUploadFailureDoesNotChangeSameMessageDraftOrShowAlert() {
        let h = Harness()
        var subscriber: Subscriber<EditResult, EditError>?
        h.edit(EditState(message: Message(id: 1), loadingState: .progress(0.4)), signal: Signal { subscriber = $0; return EmptyDisposable })
        h.chatInteraction.mediaEditSubmissionId = UUID()
        subscriber?.putError(.generic)
        XCTAssertEqual(h.chatInteraction.presentation.interfaceState.editState?.loadingState, .progress(0.4))
        XCTAssertTrue(h.context.window.alerts.isEmpty)
    }
}
