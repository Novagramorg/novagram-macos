import Foundation
import XCTest
import SwiftSignalKit

struct MessageTags: Equatable {
    let value: Int
    static let photoOrVideo = Self(value: 1)
    static let file = Self(value: 2)
    static let music = Self(value: 3)
    static let voiceOrInstantVideo = Self(value: 4)
    static let gif = Self(value: 5)
    static let webPage = Self(value: 6)
}
enum SearchMessagesLocation: Equatable {
    case peer(peerId: Int, fromId: Int?, tags: MessageTags?, reactions: [Int]?, threadId: Int64?, minDate: Int32?, maxDate: Int32?)
}
struct SearchMessagesState: Equatable { let page: Int }
struct MessageId: Hashable { let id: Int }
struct Message {
    let id: MessageId
    let timestamp: Int32
    var text = ""
    var media: [Any] = []
    var containsSecretMedia = false
    var index: Int { id.id }
}
struct TelegramMediaFile { let fileName: String? }
struct SearchMessagesResult {
    let messages: [Message]
    let totalCount: Int32
    let completed: Bool
}
final class SearchRequest {
    let location: SearchMessagesLocation
    let state: SearchMessagesState?
    let limit: Int32
    let subscriber: Subscriber<(SearchMessagesResult, SearchMessagesState), NoError>
    var disposed = false
    init(_ location: SearchMessagesLocation, _ state: SearchMessagesState?, _ limit: Int32, _ subscriber: Subscriber<(SearchMessagesResult, SearchMessagesState), NoError>) {
        self.location = location
        self.state = state
        self.limit = limit
        self.subscriber = subscriber
    }
    func reply(_ messages: [Message], count: Int32 = 1, completed: Bool = true, page: Int = 1) {
        subscriber.putNext((SearchMessagesResult(messages: messages, totalCount: count, completed: completed), SearchMessagesState(page: page)))
        subscriber.putCompletion()
    }
}
final class MessagesEngine {
    var requests: [SearchRequest] = []
    func searchMessages(location: SearchMessagesLocation, query: String, state: SearchMessagesState?, limit: Int32) -> Signal<(SearchMessagesResult, SearchMessagesState), NoError> {
        Signal { subscriber in
            let request = SearchRequest(location, state, limit, subscriber)
            self.requests.append(request)
            return ActionDisposable { request.disposed = true }
        }
    }
}
final class Engine { let messages = MessagesEngine() }
protocol AccountContextProtocol: AnyObject {
    var engine: Engine { get }
    var window: Int { get }
    var timeDifference: TimeInterval { get }
}
final class Context: AccountContextProtocol {
    let engine = Engine()
    let window = 1
    let timeDifference: TimeInterval = 0
}
struct ChatLocation { var peerId = 10; var threadId: Int64? = 77 }
struct Target { let messageId: MessageId; let string: String? }
struct Focus { let focus: Bool }
enum Scroll { case top(id: Int, innerId: Int?, animated: Bool, focus: Focus, inset: Int) }
final class ChatLocationContextHolder {}
struct Presentation { var cachedData: Int? = 42 }
final class ChatInteraction {
    let interactionContext = Context()
    var chatLocation = ChatLocation()
    var peerId: Int { chatLocation.peerId }
    let mode = 0
    let presentation = Presentation()
    let dateHeaderActions = ChatDateHeaderActions()
    var dates: [Date] = []
    var focused: [MessageId] = []
    var notices: [String] = []
    func jumpToDate(_ date: Date) { dates.append(date) }
    func focusMessageId(_ from: MessageId?, _ target: Target, _ scroll: Scroll) { focused.append(target.messageId) }
    func contextHolder() -> Atomic<ChatLocationContextHolder?> { Atomic(value: nil) }
    func showToaster(_ text: NSAttributedString) { notices.append(text.string) }
}
final class ContextMenu {
    var items: [ContextMenuItem] = []
    var onShow: (ContextMenu) -> Void = { _ in }
    var onClose: () -> Void = {}
    var loadMore: (() -> Void)?
}
final class ContextMenuItem {
    let title: String
    var handler: (() -> Void)?
    var submenu: ContextMenu?
    var isEnabled = true
    init(_ title: String, handler: (() -> Void)? = nil) { self.title = title; self.handler = handler }
}
enum GalleryType { case messages([Message]) }
final class ChatNavigationHooks {
    static let shared = ChatNavigationHooks()
    var galleries: [[Message]] = []
    var cachedData: Int?
    func showChatGallery(_ context: any AccountContextProtocol, _ message: Message, _ delegate: Int?, _ content: Int?, _ type: GalleryType, _ reversed: Bool, _ mode: Int, _ location: ChatLocation, _ holder: Atomic<ChatLocationContextHolder?>, _ cachedData: Int?) {
        if case let .messages(messages) = type { galleries.append(messages) }
        self.cachedData = cachedData
    }
}
func showModalProgress<T>(signal: Signal<T, NoError>, for window: Int) -> Signal<T, NoError> { signal }
enum TestStrings {
    static let voiceOverCommonLoading = "Loading"
    static let requestJoinListSearchEmptyHeader = "No results"
    static func sharedMediaFileCountOther(_ n: Int) -> String { "\(n) files" }
    static func sharedMediaMusicCountOther(_ n: Int) -> String { "\(n) music" }
    static func sharedMediaVoiceCountOther(_ n: Int) -> String { "\(n) voice" }
    static func sharedMediaGifCountOther(_ n: Int) -> String { "\(n) GIFs" }
    static func sharedMediaLinkCountOther(_ n: Int) -> String { "\(n) links" }
}
func strings() -> TestStrings.Type { TestStrings.self }
func translate(key: String, _ args: [Int]) -> String { "\(args[0]) photos and videos" }

__PRODUCTION__

final class DateActionsTests: XCTestCase {
    func location(day: Int32 = 100, thread: Int64? = 77, tag: MessageTags? = nil) -> SearchMessagesLocation {
        .peer(peerId: 10, fromId: nil, tags: tag, reactions: nil, threadId: thread, minDate: day, maxDate: day + 99)
    }
    func message(_ id: Int, timestamp: Int32 = 150, secret: Bool = false) -> Message {
        Message(id: MessageId(id: id), timestamp: timestamp, containsSecretMedia: secret)
    }
    func drain() { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02)) }
    func menu(_ interaction: ChatInteraction) -> ContextMenu {
        let menu = interaction.dateHeaderActions.makeMenu(location: location(), interaction: interaction)
        menu.onShow(menu)
        return menu
    }
    func fillCounts(_ interaction: ChatInteraction, photos: Int32 = 3, files: Int32 = 5) {
        let requests = interaction.interactionContext.engine.messages.requests
        for (index, request) in requests.prefix(6).enumerated() {
            let count = index == 0 ? photos : index == 1 ? files : 0
            request.reply((0..<Int(count)).map { message($0) }, count: count)
        }
        drain()
    }
    override func setUp() { ChatNavigationHooks.shared.galleries = [] }

    func testCountUsesUniqueMessagesWithinDayInsteadOfReportedTotal() {
        let context = Context()
        var counts: [Int?] = []
        let disposable = chatDateMessageCount(context: context, location: location()).start(next: { counts.append($0) })
        let engine = context.engine.messages
        XCTAssertEqual(engine.requests[0].location, location())
        XCTAssertEqual(engine.requests[0].limit, 100)
        engine.requests[0].reply([message(3), message(2)], count: 180, completed: false)
        XCTAssertTrue(counts.isEmpty)
        XCTAssertEqual(engine.requests[1].state, SearchMessagesState(page: 1))
        engine.requests[1].reply([message(3), message(2), message(2), message(1), message(0, timestamp: 99), message(4, timestamp: 200)], count: 180, page: 2)
        XCTAssertEqual(counts, [3])
        disposable.dispose()
    }
    func testCountIncludesDayBoundariesAndEmptyDays() {
        let context = Context()
        var counts: [Int?] = []
        let first = chatDateMessageCount(context: context, location: location()).start(next: { counts.append($0) })
        context.engine.messages.requests.last!.reply([message(1, timestamp: 100), message(2, timestamp: 199)], count: 180)
        let second = chatDateMessageCount(context: context, location: location()).start(next: { counts.append($0) })
        context.engine.messages.requests.last!.reply([message(0, timestamp: 99), message(3, timestamp: 200)], count: 180)
        XCTAssertEqual(counts, [2, 0])
        first.dispose()
        second.dispose()
    }
    func testCountDoesNotPublishPartialTotalWhenPaginationStalls() {
        let context = Context()
        var counts: [Int?] = []
        let disposable = chatDateMessageCount(context: context, location: location()).start(next: { counts.append($0) })
        context.engine.messages.requests.last!.reply([message(1)], count: 180, completed: false)
        context.engine.messages.requests.last!.reply([message(1)], count: 180, completed: false)
        XCTAssertEqual(counts.count, 1)
        XCTAssertNil(counts[0])
        XCTAssertEqual(context.engine.messages.requests.count, 2)
        disposable.dispose()
    }
    func testCancellingCountStopsPaginationAndSuppressesLateReply() {
        let context = Context()
        var counts: [Int?] = []
        let disposable = chatDateMessageCount(context: context, location: location()).start(next: { counts.append($0) })
        context.engine.messages.requests.last!.reply([message(1)], count: 180, completed: false)
        let pending = context.engine.messages.requests.last!
        disposable.dispose()
        XCTAssertTrue(pending.disposed)
        pending.reply([message(1), message(2)], count: 180, completed: false, page: 2)
        XCTAssertTrue(counts.isEmpty)
        XCTAssertEqual(context.engine.messages.requests.count, 2)
    }
    func testMediaMenuUsesActualDayCount() {
        let interaction = ChatInteraction()
        let menu = menu(interaction)
        let requests = interaction.interactionContext.engine.messages.requests
        requests[0].reply([message(1), message(2), message(3), message(4, timestamp: 200)], count: 180)
        for request in requests.dropFirst() {
            request.reply([], count: 180)
        }
        drain()
        XCTAssertEqual(menu.items.map(\.title), ["3 photos and videos"])
    }

    func testFirstClickJumpsToStartSecondClickOpensMenu() {
        let interaction = ChatInteraction()
        XCTAssertFalse(interaction.dateHeaderActions.shouldShowMenu(location: location(), interaction: interaction))
        XCTAssertEqual(interaction.dates.map(\.timeIntervalSince1970), [100])
        XCTAssertTrue(interaction.dateHeaderActions.shouldShowMenu(location: location(), interaction: interaction))
        XCTAssertEqual(interaction.dates.count, 1)
        XCTAssertFalse(interaction.dateHeaderActions.shouldShowMenu(location: location(day: 200), interaction: interaction))
    }
    func testRightClickDoesNotConsumeFirstLeftClick() {
        let interaction = ChatInteraction()
        let menu = menu(interaction)
        XCTAssertEqual(interaction.dates.count, 0)
        XCTAssertFalse(interaction.dateHeaderActions.shouldShowMenu(location: location(), interaction: interaction))
        menu.onClose()
    }
    func testMenuCategoriesKeepDateAndTopicBounds() {
        let interaction = ChatInteraction()
        let menu = menu(interaction)
        let requests = interaction.interactionContext.engine.messages.requests
        XCTAssertEqual(requests.count, 6)
        XCTAssertEqual(requests[0].location, location(tag: .photoOrVideo))
        XCTAssertEqual(requests[1].location, location(tag: .file))
        XCTAssertEqual(requests[5].location, location(tag: .webPage))
        fillCounts(interaction)
        XCTAssertEqual(menu.items.map(\.title), ["3 photos and videos", "5 files"])
    }
    func testClosingMenuCancelsCounts() {
        let interaction = ChatInteraction()
        let menu = menu(interaction)
        menu.onClose()
        XCTAssertTrue(interaction.interactionContext.engine.messages.requests.allSatisfy(\.disposed))
        fillCounts(interaction)
        XCTAssertEqual(menu.items.first?.title, "Loading")
    }
    func testGalleryLoadsEveryPageAndFiltersDayAndSecretMedia() {
        let interaction = ChatInteraction()
        let menu = menu(interaction)
        fillCounts(interaction)
        menu.items[0].handler?()
        menu.onClose()
        let engine = interaction.interactionContext.engine.messages
        XCTAssertEqual(engine.requests.last?.limit, 100)
        engine.requests.last!.reply([message(3)], count: 3, completed: false)
        drain()
        XCTAssertTrue(ChatNavigationHooks.shared.galleries.isEmpty)
        XCTAssertEqual(engine.requests.last?.state, SearchMessagesState(page: 1))
        engine.requests.last!.reply([message(3), message(1), message(1), message(0, timestamp: 99), message(4, timestamp: 200), message(2, secret: true)], page: 2)
        drain()
        XCTAssertEqual(ChatNavigationHooks.shared.galleries.first?.map { $0.id.id }, [1, 3])
        XCTAssertEqual(ChatNavigationHooks.shared.cachedData, 42)
    }
    func testResetCancelsGalleryAndClickState() {
        let interaction = ChatInteraction()
        _ = interaction.dateHeaderActions.shouldShowMenu(location: location(), interaction: interaction)
        let menu = menu(interaction)
        fillCounts(interaction)
        menu.items[0].handler?()
        let request = interaction.interactionContext.engine.messages.requests.last!
        interaction.dateHeaderActions.reset()
        XCTAssertTrue(request.disposed)
        request.reply([message(1)])
        drain()
        XCTAssertTrue(ChatNavigationHooks.shared.galleries.isEmpty)
        XCTAssertFalse(interaction.dateHeaderActions.shouldShowMenu(location: location(), interaction: interaction))
    }
    func testStaleMenuCannotActAfterTopicChange() {
        let interaction = ChatInteraction()
        let menu = menu(interaction)
        fillCounts(interaction)
        interaction.chatLocation.threadId = 88
        menu.items[0].handler?()
        XCTAssertEqual(interaction.interactionContext.engine.messages.requests.count, 6)
    }
    func testFilesSubmenuPaginatesAndFocusesSelectedMessage() {
        let interaction = ChatInteraction()
        let menu = menu(interaction)
        fillCounts(interaction)
        let files = menu.items[1].submenu!
        files.onShow(files)
        let engine = interaction.interactionContext.engine.messages
        XCTAssertEqual(engine.requests.last?.location, location(tag: .file))
        engine.requests.last!.reply([message(3)], count: 5, completed: false)
        drain()
        files.loadMore?()
        engine.requests.last!.reply([message(3), message(2), message(1, timestamp: 99)], page: 2)
        drain()
        XCTAssertEqual(files.items.count, 2)
        files.items[1].handler?()
        XCTAssertEqual(interaction.focused, [MessageId(id: 2)])
    }
    func testStalledPaginationStopsWithoutPartialGallery() {
        let interaction = ChatInteraction()
        let menu = menu(interaction)
        fillCounts(interaction)
        menu.items[0].handler?()
        let engine = interaction.interactionContext.engine.messages
        engine.requests.last!.reply([message(3)], completed: false)
        drain()
        engine.requests.last!.reply([message(3)], completed: false)
        drain()
        XCTAssertEqual(engine.requests.count, 8)
        XCTAssertTrue(ChatNavigationHooks.shared.galleries.isEmpty)
        XCTAssertEqual(interaction.notices, ["No results"])
    }
    func testOpenMenuDoesNotRetainChat() {
        var interaction: ChatInteraction? = ChatInteraction()
        weak var weakInteraction = interaction
        let menu = menu(interaction!)
        interaction = nil
        XCTAssertNil(weakInteraction)
        menu.onClose()
    }
}
