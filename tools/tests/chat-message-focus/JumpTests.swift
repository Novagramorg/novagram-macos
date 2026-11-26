import Foundation
import XCTest
import SwiftSignalKit

private enum JumpCase {
    struct MessageId: Equatable { var peerId = 1; let id: Int }
    struct Message { let id: MessageId; var replyAttribute: ReplyAttribute? }
    struct ReplyAttribute { var innerSubject: InnerSubject? }
    enum InnerSubject { case todoItem(Int), pollOption(Data) }
    struct MessageIndex: Equatable { let id: MessageId; init(_ message: Message) { id = message.id } }
    enum Anchor: Equatable { case message(MessageIndex), lowerBound }
    struct ChatFocusTarget { let messageId: MessageId; var string: String?; var range: NSRange?; var pollOptionId: Data? }
    struct Focus { let focus: Bool }
    struct Scroll {
        static func top(id: Int, innerId: Int?, animated: Bool, focus: Focus, inset: Int) -> Self { Self(id: id, animated: animated) }
        var id: Int?
        var string: String?
        var range: NSRange?
        var innerId: AnyHashable?
        var animated = true
        var action: ((Int) -> Void)?
        func swap(to id: Int) -> Self { var s = self; s.id = id; return s }
        func text(string: String?, range: NSRange?, innerId: AnyHashable?) -> Self { var s = self; s.string = string; s.range = range; s.innerId = innerId; return s }
        func focus(action: @escaping (Int) -> Void) -> Self { var s = self; s.action = action; return s }
        static func up(_ animated: Bool) -> Self { Self(animated: animated) }
        static var CenterEmpty: Self { Self() }
        static func none(_ value: Int?) -> Self { Self() }
    }
    enum ChatHistoryEntryId { static func message(_ message: Message) -> Int { message.id.id } }
    enum ChatHistoryLocation {
        enum Search { case id(MessageId, String?, NSRange?) }
        case InitialSearch(location: Search, count: Int)
        case Scroll(index: Anchor, anchorIndex: Anchor, sourceIndex: Anchor, scrollPosition: Scroll, count: Int, animated: Bool)
    }
    enum ChatLocation: Equatable {
        case peer(Int), thread(Int)
        var threadId: Int? { if case let .thread(id) = self { return id }; return nil }
    }
    struct ChatHistoryLocationInput {
        let content: ChatHistoryLocation
        let chatLocation: ChatLocation
        let tag: Int?
        let id: Int32
    }
    enum Mode { case history, thread, customChatContents, scheduled, pinned, customLink, preview }
    struct HistoryState {
        var replies: [MessageId] = []
        func withAddingReply(_ id: MessageId) -> Self { var s = self; s.replies.append(id); return s }
    }
    struct Entry { let message: Message }
    struct HistoryView { let entries: [Entry]; var isLoading = false }
    enum HistoryUpdate { case Loading, HistoryView(HistoryView, Int, Int, Int) }
    final class Interaction {
        let peerId = 1
        let loadingMessage = Promise<Bool>(false)
        var focusMessageId: (MessageId?, ChatFocusTarget, Scroll) -> Void = { _, _, _ in }
        var jumpToDate: (Date) -> Void = { _ in }
        var scrollToTheFirst: () -> Void = {}
        var mentionPressed: () -> Void = {}
        var reactionPressed: () -> Void = {}
    }
    enum Participation { case member, left }
    struct Channel { var participationStatus = Participation.member }
    enum Membership { case Member, Left }
    struct Group { var membership = Membership.Member }
    struct Peer { var isChannel = false; var isGroup = false; var isSupergroup = false }
    enum EnginePeer {
        case channel(Channel), legacyGroup(Group), user
        var addressName: String? { nil }
        func _asPeer() -> Peer { Peer() }
    }
    enum TelegramEngine { enum EngineData { enum Item { enum Peer { struct Peer { let id: Int } } } } }
    final class DataEngine {
        var subscribers: [Int: Subscriber<EnginePeer?, NoError>] = [:]
        func get(_ item: TelegramEngine.EngineData.Item.Peer.Peer) -> Signal<EnginePeer?, NoError> {
            Signal { subscriber in self.subscribers[item.id] = subscriber; return EmptyDisposable }
        }
    }
    enum UnseenResult { case loading, result(MessageId?) }
    final class MessagesEngine {
        var dates: [Int32: Subscriber<MessageId?, NoError>] = [:]
        func searchMessageIdByTimestamp(peerId: Int, threadId: Int?, timestamp: Int32) -> Signal<MessageId?, NoError> {
            Signal { self.dates[timestamp] = $0; return EmptyDisposable }
        }
        var mentions: Subscriber<UnseenResult, NoError>?
        var reactions: Subscriber<UnseenResult, NoError>?
        func earliestUnseenPersonalMentionMessage(peerId: Int, threadId: Int?) -> Signal<UnseenResult, NoError> {
            Signal { self.mentions = $0; return EmptyDisposable }
        }
        func earliestUnseenPersonalReactionMessage(peerId: Int, threadId: Int?) -> Signal<UnseenResult, NoError> {
            Signal { self.reactions = $0; return EmptyDisposable }
        }
    }
    final class Engine { let data = DataEngine(); let messages = MessagesEngine() }
    final class Window { var notices: [String] = [] }
    final class Context {
        let engine = Engine()
        let window = Window()
        var subscribers: [Int: Subscriber<HistoryUpdate, NoError>] = [:]
        var requests: [Int] = []
        func emit(_ target: Int, found: Bool = true, loading: Bool = false) {
            subscribers[target]?.putNext(loading ? .Loading : .HistoryView(.init(entries: found ? [.init(message: .init(id: .init(id: target)))] : []), 0, 0, 0))
        }
    }
    struct Strings {
        let chatToastQuoteChatUnavailbalePrivateChannel = "channel"
        let chatToastQuoteChatUnavailbalePrivateGroup = "group"
        let chatToastQuoteChatUnavailbalePrivateChat = "chat"
    }
    static func strings() -> Strings { Strings() }
    static func showModalText(for window: Window, text: String) { window.notices.append(text) }
    static func showModalProgress<T>(signal: Signal<T, NoError>, for window: Window) -> Signal<T, NoError> { signal }
    static func preloadedChatHistoryViewForLocation(_ location: ChatHistoryLocation, context: Context, chatLocation: ChatLocation, chatLocationContextHolder: Int, tag: Int?, additionalData: [Int]) -> Signal<HistoryUpdate, NoError> {
        let target: MessageId
        switch location {
        case let .InitialSearch(.id(id, _, _), _): target = id
        case .Scroll: target = .init(id: 0)
        }
        return Signal { subscriber in
            context.requests.append(target.id)
            context.subscribers[target.id] = subscriber
            return EmptyDisposable
        }
    }
    final class Navigation {
        var controller: Any?
        var pushed: [ChatAdditionController] = []
        func push(_ controller: ChatAdditionController) { pushed.append(controller) }
        func back() {}
    }
    struct ChatAdditionController {
        init(context: Context, chatLocation: ChatLocation, focusTarget: ChatFocusTarget) {}
    }
    class ChatRowItem { var stableId = 0; init(_ id: Int = 0) { stableId = id } }
    class ChatDateStickItem { var timestamp: Int32; init(_ timestamp: Int32) { self.timestamp = timestamp } }
    enum CalendarUtils { static func monthDay(_ day: Int, date: Date) -> Date { date } }
    static func chatDateId(for timestamp: Int32) -> Int64 {
        Int64(Calendar.current.startOfDay(for: Date(timeIntervalSince1970: Double(timestamp))).timeIntervalSince1970)
    }
    class Table {
        var items: [Any] = []
        var scrolls: [Scroll] = []
        func enumerateItems(with body: (Any) -> Bool) {
            for item in items { if !body(item) { break } }
        }
        func scroll(to state: Scroll) { scrolls.append(state) }
    }
    class GenericView { let tableView = Table() }
    typealias ChatController = Harness
    final class Harness {
        let context = Context()
        var window: Window? { context.window }
        let genericView = GenericView()
        let chatInteraction = Interaction()
        let messageIndexDisposable = MetaDisposable()
        let focusMessageDisposable = MetaDisposable()
        let navigationActionDisposable = MetaDisposable()
        let dateDisposable = MetaDisposable()
        let loadingDisposable = MetaDisposable()
        var messageFocusRequestId = 0
        var mode = Mode.history
        var chatLocation = ChatLocation.peer(1)
        var locationValue: ChatHistoryLocationInput?
        let chatLocationContextHolder = 0
        let requestCount = 30
        var historyState = HistoryState()
        var anchor: Message? = .init(id: .init(id: 1))
        var known: [Int: Message] = [:]
        let navigationController: Navigation? = Navigation()
        var applied: [ChatHistoryLocationInput] = []
        var nextId: Int32 = 0
        var loading = false
        func takeNextHistoryLocationId() -> Int32 { nextId += 1; return nextId }
        func messageInCurrentHistoryView(_ id: MessageId) -> Message? { known[id.id] }
        func anchorMessageInCurrentHistoryView() -> Message? { anchor }
        func setLocation(_ location: ChatHistoryLocation) {
            setLocation(.init(content: location, chatLocation: chatLocation, tag: locationValue?.tag, id: takeNextHistoryLocationId()))
        }
        func setLocation(_ input: ChatHistoryLocationInput) { locationValue = input; applied.append(input) }
        init() {
            let context = self.context
            let chatInteraction = self.chatInteraction
            loadingDisposable.set(chatInteraction.loadingMessage.get().start(next: { [weak self] value in self?.loading = value }))
            let peerId = chatInteraction.peerId
            let threadId64: () -> Int? = { [weak self] in self?.chatLocation.threadId }
__FOCUS_SETUP__
__MENTION_SETUP__
__REACTION_SETUP__
__FIRST_SETUP__
__DATE_SETUP__
        }
__CANCEL_FOCUS__
        func cancel() { cancelMessageFocus() }
        func jump(_ id: Int, from: MessageId? = nil, peer: Int = 1, string: String? = nil, range: NSRange? = nil, inner: Data? = nil, action: ((Int) -> Void)? = nil) {
            chatInteraction.focusMessageId(from, .init(messageId: .init(peerId: peer, id: id), string: string, range: range, pollOptionId: inner), Scroll(action: action))
        }
        var lastScroll: Scroll? {
            guard let content = applied.last?.content, case let .Scroll(_, _, _, scroll, _, _) = content else { return nil }
            return scroll
        }
        deinit { messageIndexDisposable.dispose(); focusMessageDisposable.dispose(); loadingDisposable.dispose() }
    }
}

final class JumpTests: XCTestCase {
    func testScheduledDateJumpUsesRequestedDay() {
        let h = JumpCase.Harness()
        h.mode = .scheduled
        let today = Calendar.current.startOfDay(for: Date())
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today)!
        h.genericView.tableView.items = [JumpCase.ChatRowItem(30), JumpCase.ChatRowItem(20), JumpCase.ChatDateStickItem(Int32(today.timeIntervalSince1970)), JumpCase.ChatRowItem(10), JumpCase.ChatDateStickItem(Int32(yesterday.timeIntervalSince1970))]
        h.chatInteraction.jumpToDate(yesterday.addingTimeInterval(3600))
        XCTAssertEqual(h.genericView.tableView.scrolls.last?.id, 10)
    }
    func testScheduledDateJumpChoosesFirstMessageInDay() {
        let h = JumpCase.Harness()
        h.mode = .scheduled
        let today = Calendar.current.startOfDay(for: Date())
        h.genericView.tableView.items = [JumpCase.ChatRowItem(30), JumpCase.ChatRowItem(20), JumpCase.ChatDateStickItem(Int32(today.timeIntervalSince1970))]
        h.chatInteraction.jumpToDate(today)
        XCTAssertEqual(h.genericView.tableView.scrolls.last?.id, 20)
    }
    func testScheduledMissingDateDoesNotJumpToAnotherDay() {
        let h = JumpCase.Harness()
        h.mode = .scheduled
        let today = Calendar.current.startOfDay(for: Date())
        h.genericView.tableView.items = [JumpCase.ChatRowItem(20), JumpCase.ChatDateStickItem(Int32(today.timeIntervalSince1970))]
        h.chatInteraction.jumpToDate(Calendar.current.date(byAdding: .day, value: 1, to: today)!)
        XCTAssertTrue(h.genericView.tableView.scrolls.isEmpty)
    }
    func testScheduledEmptyDayDoesNotReusePreviousDayMessage() {
        let h = JumpCase.Harness()
        h.mode = .scheduled
        let today = Calendar.current.startOfDay(for: Date())
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today)!
        h.genericView.tableView.items = [JumpCase.ChatRowItem(20), JumpCase.ChatDateStickItem(Int32(today.timeIntervalSince1970)), JumpCase.ChatDateStickItem(Int32(yesterday.timeIntervalSince1970))]
        h.chatInteraction.jumpToDate(yesterday)
        XCTAssertTrue(h.genericView.tableView.scrolls.isEmpty)
    }
    func testSearchJumpCancelsPendingCalendarLookup() {
        let h = JumpCase.Harness()
        h.chatInteraction.jumpToDate(Date(timeIntervalSince1970: 100))
        h.jump(60)
        h.context.emit(60)
        h.context.engine.messages.dates[100]?.putNext(.init(id: 50))
        RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        h.context.emit(50)
        XCTAssertEqual(h.lastScroll?.id, 60)
        XCTAssertEqual(h.context.requests, [60])
    }
    func testCalendarLookupFromPreviousTopicCannotMoveNewTopic() {
        let h = JumpCase.Harness()
        h.chatInteraction.jumpToDate(Date(timeIntervalSince1970: 100))
        h.chatLocation = .thread(2)
        h.context.engine.messages.dates[100]?.putNext(.init(id: 50))
        RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        XCTAssertTrue(h.context.requests.isEmpty)
    }
    func testCalendarJumpSupersedesPendingMessageJump() {
        let h = JumpCase.Harness()
        h.jump(60)
        h.chatInteraction.jumpToDate(Date(timeIntervalSince1970: 100))
        h.context.emit(60)
        XCTAssertTrue(h.applied.isEmpty)
        h.context.engine.messages.dates[100]?.putNext(.init(id: 50))
        RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        h.context.emit(50)
        XCTAssertEqual(h.lastScroll?.id, 50)
    }
    func testCurrentCalendarLookupStillFocusesResolvedMessage() {
        let h = JumpCase.Harness()
        h.chatInteraction.jumpToDate(Date(timeIntervalSince1970: 100))
        h.context.engine.messages.dates[100]?.putNext(.init(id: 50))
        RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        h.context.emit(50)
        XCTAssertEqual(h.lastScroll?.id, 50)
    }
    func testJumpToFirstWaitsForLoadedHistoryAndClearsLoading() {
        let h = JumpCase.Harness()
        h.chatInteraction.scrollToTheFirst()
        h.context.emit(0, loading: true)
        XCTAssertTrue(h.applied.isEmpty)
        h.context.emit(0)
        RunLoop.main.run(until: Date().addingTimeInterval(0.25))
        XCTAssertEqual(h.applied.count, 1)
        XCTAssertFalse(h.loading)
    }
    func testSearchSupersedesJumpToFirst() {
        let h = JumpCase.Harness()
        h.chatInteraction.scrollToTheFirst()
        h.jump(60)
        h.context.emit(0)
        h.context.emit(60)
        XCTAssertEqual(h.applied.count, 1)
        XCTAssertEqual(h.lastScroll?.id, 60)
    }

    func testSearchJumpCancelsPendingMentionLookup() {
        let h = JumpCase.Harness()
        h.chatInteraction.mentionPressed()
        h.jump(60)
        h.context.emit(60)
        h.context.engine.messages.mentions?.putNext(.result(.init(id: 50)))
        RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        h.context.emit(50)
        XCTAssertEqual(h.lastScroll?.id, 60)
        XCTAssertEqual(h.context.requests, [60])
    }
    func testReactionClickSupersedesPendingSearchBeforeReactionLookupFinishes() {
        let h = JumpCase.Harness()
        h.jump(60)
        h.chatInteraction.reactionPressed()
        h.context.emit(60)
        XCTAssertTrue(h.applied.isEmpty)
        h.context.engine.messages.reactions?.putNext(.result(.init(id: 50)))
        RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        h.context.emit(50)
        XCTAssertEqual(h.lastScroll?.id, 50)
    }
    func testMentionResultFromOldTopicDoesNotNavigate() {
        let h = JumpCase.Harness()
        h.chatInteraction.mentionPressed()
        h.chatLocation = .thread(2)
        h.context.engine.messages.mentions?.putNext(.result(.init(id: 50)))
        RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        XCTAssertTrue(h.context.requests.isEmpty)
    }
    func testReactionResultFromOldFilterDoesNotNavigate() {
        let h = JumpCase.Harness()
        h.chatInteraction.reactionPressed()
        h.locationValue = .init(content: .InitialSearch(location: .id(.init(id: 1), nil, nil), count: 30), chatLocation: .peer(1), tag: 7, id: 1)
        h.context.engine.messages.reactions?.putNext(.result(.init(id: 50)))
        RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        XCTAssertTrue(h.context.requests.isEmpty)
    }
    func testReactionClickCancelsMentionLookup() {
        let h = JumpCase.Harness()
        h.chatInteraction.mentionPressed()
        let old = h.context.engine.messages.mentions
        h.chatInteraction.reactionPressed()
        old?.putNext(.result(.init(id: 50)))
        RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        h.context.engine.messages.reactions?.putNext(.result(.init(id: 60)))
        RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        h.context.emit(60)
        XCTAssertEqual(h.context.requests, [60])
        XCTAssertEqual(h.lastScroll?.id, 60)
    }
    func testFocusCompletionDoesNotReplaceNewerPaginationLocation() {
        let h = JumpCase.Harness()
        var actions = 0
        h.jump(50, action: { _ in actions += 1 })
        h.context.emit(50)
        let action = h.lastScroll?.action
        h.setLocation(.InitialSearch(location: .id(.init(id: 50), nil, nil), count: 60))
        action?(0)
        XCTAssertEqual(h.applied.count, 2)
        XCTAssertEqual(actions, 1)
    }

    func testJumpBeforeInitialHistoryHasRowsStillResolvesTarget() {
        let h = JumpCase.Harness()
        h.anchor = nil
        h.jump(50)
        h.context.emit(50)
        XCTAssertEqual(h.lastScroll?.id, 50)
    }
    func testNewerJumpWinsWhenLookupResultsArriveOutOfOrder() {
        let h = JumpCase.Harness()
        h.jump(50)
        h.jump(60)
        h.context.emit(60)
        h.context.emit(50)
        XCTAssertEqual(h.lastScroll?.id, 60)
        XCTAssertEqual(h.applied.count, 1)
    }
    func testOlderAnimationCompletionCannotOverwritePendingNewJump() {
        let h = JumpCase.Harness()
        var actions = 0
        h.jump(50, action: { _ in actions += 1 })
        h.context.emit(50)
        let oldAction = h.lastScroll?.action
        h.jump(60)
        oldAction?(0)
        XCTAssertEqual(h.applied.count, 1)
        XCTAssertEqual(actions, 0)
        h.context.emit(60)
        XCTAssertEqual(h.lastScroll?.id, 60)
    }
    func testOlderAnimationCompletionCannotOverwriteResolvedNewJump() {
        let h = JumpCase.Harness()
        h.jump(50)
        h.context.emit(50)
        let oldAction = h.lastScroll?.action
        h.jump(60)
        h.context.emit(60)
        oldAction?(0)
        XCTAssertEqual(h.lastScroll?.id, 60)
        XCTAssertEqual(h.applied.count, 2)
    }
    func testMissingTargetClearsDelayedLoadingWithoutMoving() {
        let h = JumpCase.Harness()
        h.jump(50)
        h.context.emit(50, found: false)
        RunLoop.main.run(until: Date().addingTimeInterval(0.25))
        XCTAssertFalse(h.loading)
        XCTAssertTrue(h.applied.isEmpty)
    }
    func testMissingTargetDoesNotAddReplyReturnPosition() {
        let h = JumpCase.Harness()
        h.jump(50, from: .init(id: 1))
        h.context.emit(50, found: false)
        XCTAssertTrue(h.historyState.replies.isEmpty)
    }
    func testCancelStopsLoadingAndLateResult() {
        let h = JumpCase.Harness()
        h.jump(50)
        h.cancel()
        h.context.emit(50)
        RunLoop.main.run(until: Date().addingTimeInterval(0.25))
        XCTAssertFalse(h.loading)
        XCTAssertTrue(h.applied.isEmpty)
    }
    func testChangingTopicWhileLoadingDoesNotApplyOldTarget() {
        let h = JumpCase.Harness()
        h.jump(50)
        h.chatLocation = .thread(20)
        h.context.emit(50)
        XCTAssertTrue(h.applied.isEmpty)
    }
    func testChangingFilterWhileLoadingDoesNotApplyOldTarget() {
        let h = JumpCase.Harness()
        h.jump(50)
        h.locationValue = .init(content: .InitialSearch(location: .id(.init(id: 1), nil, nil), count: 30), chatLocation: .peer(1), tag: 7, id: 1)
        h.context.emit(50)
        XCTAssertTrue(h.applied.isEmpty)
    }
    func testNewLocalJumpCancelsPendingCrossChatLookup() {
        let h = JumpCase.Harness()
        h.jump(50, peer: 2)
        h.jump(60)
        h.context.engine.data.subscribers[2]?.putNext(.channel(.init()))
        XCTAssertTrue(h.navigationController?.pushed.isEmpty == true)
    }
    func testFocusRetainsQuoteRangeInnerTargetAndReturnPosition() {
        let h = JumpCase.Harness()
        let range = NSRange(location: 3, length: 5)
        let inner = Data([1, 2])
        h.jump(50, from: .init(id: 1), string: "quote", range: range, inner: inner)
        h.context.emit(50)
        XCTAssertEqual(h.lastScroll?.string, "quote")
        XCTAssertEqual(h.lastScroll?.range, range)
        XCTAssertEqual(h.lastScroll?.innerId, AnyHashable(inner))
        XCTAssertEqual(h.historyState.replies.map(\.id), [1])
    }
    func testUnchangedFocusCompletionInvokesOriginalActionOnce() {
        let h = JumpCase.Harness()
        var actions = 0
        h.jump(50, action: { _ in actions += 1 })
        h.context.emit(50)
        h.lastScroll?.action?(0)
        XCTAssertEqual(actions, 1)
        XCTAssertEqual(h.applied.count, 2)
    }
}
