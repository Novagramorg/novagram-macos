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

__PRODUCTION__

final class DateCountTests: XCTestCase {
    func location(day: Int32 = 100, thread: Int64? = 77, tag: MessageTags? = nil) -> SearchMessagesLocation {
        .peer(peerId: 10, fromId: nil, tags: tag, reactions: nil, threadId: thread, minDate: day, maxDate: day + 99)
    }
    func message(_ id: Int, timestamp: Int32 = 150, secret: Bool = false) -> Message {
        Message(id: MessageId(id: id), timestamp: timestamp, containsSecretMedia: secret)
    }
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
}
