import XCTest
import SwiftSignalKit

enum MessageTags { case photoOrVideo, gif }
struct Message: Equatable { let id: Int; let tags: MessageTags; let threadId: Int64 }
struct ThreadInfo { let message: Message }
struct SearchState { let request: String }
struct ExternalSearchMessages { let messages: [Message] }
struct SearchResult { let result: [Message]? }
struct ChatHistoryViewUpdate { let messages: [Message] }
enum TableSavingSide { case upper }
struct Location { let side: TableSavingSide? = nil }
enum ChatLocation { case peer(Int) }
enum Tag { case tag(MessageTags) }
enum SearchMessagesLocation {
    case peer(peerId: Int, fromId: Int?, tags: MessageTags, reactions: [Int]?, threadId: Int64?, minDate: Int32?, maxDate: Int32?)
}
struct SearchResponse { let messages: [Message]; var completed = true }
typealias SearchMessagesResult = SearchResponse
typealias SearchMessagesState = Int
final class Engine {
    var messages: Engine { self }
    var source: [Message] = []
    var requests = 0
    var requestStates: [Int?] = []
    var pageSize = Int.max
    var respond: ((String, Int?) -> Signal<(SearchResponse, Int), NoError>)?
    func searchMessages(location: SearchMessagesLocation, query: String, state: Int?) -> Signal<(SearchResponse, Int), NoError> {
        requests += 1
        requestStates.append(state)
        if let respond { return respond(query, state) }
        switch location {
        case let .peer(_, _, tags, _, threadId, _, _):
            let matches = source.filter { $0.tags == tags && (threadId == nil || $0.threadId == threadId) }
            let end = min(matches.count, (state ?? 0) + min(pageSize, matches.count))
            return .single((SearchResponse(messages: Array(matches.prefix(end)), completed: end == matches.count), end))
        }
    }
}
final class Context { let engine = Engine(); let contentSettings = 0 }
enum ScrollDirection { case top, bottom, none }
struct Scroll { let direction: ScrollDirection }
struct GridState { let searchState: SearchState }
func chatHistoryViewForLocation(_ location: Location, context: Context, chatLocation: ChatLocation, fixedCombinedReadStates: Int?, tag: Tag, chatLocationInput: Int64?) -> Signal<ChatHistoryViewUpdate, NoError> {
    switch tag {
    case let .tag(tags):
        return .single(ChatHistoryViewUpdate(messages: context.engine.source.filter { $0.tags == tags && (chatLocationInput == nil || $0.threadId == chatLocationInput) }))
    }
}
final class Controller {
    let context = Context()
    let peerId = 1
    var threadInfo: ThreadInfo?
    var tags = MessageTags.photoOrVideo
    let searchState = Promise<SearchState>(SearchState(request: "caption"))
    let location = Promise<Location>(Location())
    let externalSearch = Promise<ExternalSearchMessages?>(nil)
    let searchLoadMore = ValuePipe<Void>()

    func scroll(_ direction: ScrollDirection, query: String = "caption") {
        let scroll = Scroll(direction: direction)
        let stateValue = Atomic(value: GridState(searchState: SearchState(request: query)))
        let handler: (Controller?) -> Void = { [weak self] _ in
            __GRID_SCROLL__
        }
        handler(self)
    }

    func history() -> Signal<(ChatHistoryViewUpdate?, SearchResult?, SearchState, TableSavingSide?), NoError> {
        let context = self.context
        let peerId = self.peerId
        let tags = self.tags
        let chatLocationInput = self.threadInfo?.message.threadId
        let searchLoadMore = self.searchLoadMore.signal()
        __THREAD__
        __HISTORY__
        return history
    }
}

final class PeerMediaSearchTests: XCTestCase {
    let messages = [
        Message(id: 1, tags: .photoOrVideo, threadId: 10),
        Message(id: 2, tags: .gif, threadId: 10),
        Message(id: 3, tags: .photoOrVideo, threadId: 20),
        Message(id: 4, tags: .gif, threadId: 20)
    ]

    func check(tags: MessageTags, thread: Int64?, expected: [Int]) {
        let controller = Controller()
        controller.context.engine.source = messages
        controller.tags = tags
        controller.threadInfo = thread.map { ThreadInfo(message: Message(id: 0, tags: tags, threadId: $0)) }
        let finished = expectation(description: "search completes")
        let subscription = controller.history().start(next: { _, result, state, _ in
            if let messages = result?.result {
                XCTAssertEqual(messages.map { $0.id }, expected)
                XCTAssertEqual(state.request, "caption")
                finished.fulfill()
            }
        })
        wait(for: [finished], timeout: 2)
        XCTAssertEqual(controller.context.engine.requests, 1)
        subscription.dispose()
    }

    func testPhotosAcrossTopics() { check(tags: .photoOrVideo, thread: nil, expected: [1, 3]) }
    func testPhotosWithinTopic() { check(tags: .photoOrVideo, thread: 10, expected: [1]) }
    func testGifsAcrossTopics() { check(tags: .gif, thread: nil, expected: [2, 4]) }
    func testGifsWithinTopic() { check(tags: .gif, thread: 20, expected: [4]) }

    func testExternalResultsAreNotSearchedAgain() {
        let controller = Controller()
        controller.context.engine.source = messages
        controller.externalSearch.set(.single(ExternalSearchMessages(messages: [messages[1]])))
        var result: [Message]?
        let subscription = controller.history().start(next: { _, search, _, _ in result = search?.result })
        XCTAssertEqual(result, [messages[1]])
        XCTAssertEqual(controller.context.engine.requests, 0)
        subscription.dispose()
    }

    func testClearingSearchReturnsScopedHistory() {
        let controller = Controller()
        controller.context.engine.source = messages
        controller.tags = .gif
        controller.threadInfo = ThreadInfo(message: messages[1])
        controller.searchState.set(.single(SearchState(request: "")))
        var result: [Message]?
        let subscription = controller.history().start(next: { history, search, _, _ in
            result = history?.messages
            XCTAssertNil(search)
        })
        XCTAssertEqual(result, [messages[1]])
        XCTAssertEqual(controller.context.engine.requests, 0)
        subscription.dispose()
    }
}
