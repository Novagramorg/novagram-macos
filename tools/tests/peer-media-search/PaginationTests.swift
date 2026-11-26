import XCTest
import SwiftSignalKit

final class PaginationTests: XCTestCase {
    let messages = (1...5).map { Message(id: $0, tags: .photoOrVideo, threadId: 10) }

    func testSearchLoadsCumulativePagesAndStopsAtCompletion() {
        let controller = Controller()
        controller.context.engine.source = messages
        controller.context.engine.pageSize = 2
        let first = expectation(description: "first page")
        let second = expectation(description: "second page")
        let third = expectation(description: "third page")
        var counts: [Int] = []
        let disposable = controller.history().start(next: { _, result, _, _ in
            guard let messages = result?.result else { return }
            counts.append(messages.count)
            if messages.count == 2 { first.fulfill() }
            if messages.count == 4 { second.fulfill() }
            if messages.count == 5 { third.fulfill() }
        })
        wait(for: [first], timeout: 2)
        controller.scroll(.bottom)
        wait(for: [second], timeout: 2)
        controller.scroll(.bottom)
        wait(for: [third], timeout: 2)
        controller.scroll(.bottom)
        XCTAssertEqual(counts, [2, 4, 5])
        XCTAssertEqual(controller.context.engine.requestStates, [nil, 2, 4])
        disposable.dispose()
    }

    func testRepeatedScrollDoesNotOverlapRequests() {
        let controller = Controller()
        controller.context.engine.source = Array(messages.prefix(4))
        controller.context.engine.pageSize = 2
        let first = expectation(description: "first")
        let second = expectation(description: "second")
        let disposable = controller.history().start(next: { _, result, _, _ in
            if result?.result?.count == 2 { first.fulfill() }
            if result?.result?.count == 4 { second.fulfill() }
        })
        for _ in 0..<10 { controller.searchLoadMore.putNext(()) }
        XCTAssertEqual(controller.context.engine.requests, 1)
        wait(for: [first], timeout: 2)
        for _ in 0..<10 { controller.searchLoadMore.putNext(()) }
        XCTAssertEqual(controller.context.engine.requests, 2)
        wait(for: [second], timeout: 2)
        disposable.dispose()
    }

    func testNewQueryDropsPendingPageAndResetsCursor() {
        let controller = Controller()
        let initial = Array(messages.prefix(2))
        let replacement = Array(messages.suffix(1))
        controller.context.engine.respond = { query, state in
            .single((SearchResponse(messages: query == "new" ? replacement : initial, completed: query == "new"), state == nil ? 2 : 4))
        }
        let first = expectation(description: "old first page")
        let new = expectation(description: "new query")
        var queries: [String] = []
        let disposable = controller.history().start(next: { _, result, search, _ in
            guard result?.result != nil else { return }
            queries.append(search.request)
            if search.request == "new" { new.fulfill() } else { first.fulfill() }
        })
        wait(for: [first], timeout: 2)
        controller.searchLoadMore.putNext(())
        controller.searchState.set(.single(SearchState(request: "new")))
        wait(for: [new], timeout: 2)
        XCTAssertEqual(queries, ["caption", "new"])
        XCTAssertEqual(controller.context.engine.requestStates, [nil, 2, nil])
        disposable.dispose()
    }

    func testDisposeCancelsPendingRequestAndScrollSubscription() {
        let loadMore = ValuePipe<Void>()
        var cancelled = 0
        var requests = 0
        var results = 0
        let signal = peerMediaSearchMessages(loadMore: loadMore.signal(), request: { _ in
            requests += 1
            return Signal { _ in ActionDisposable { cancelled += 1 } }
        })
        let disposable = signal.start(next: { value in if value != nil { results += 1 } })
        disposable.dispose()
        loadMore.putNext(())
        XCTAssertEqual(cancelled, 1)
        XCTAssertEqual(requests, 1)
        XCTAssertEqual(results, 0)
    }

    func testEmptyCompletionClearsLoadingAndAllowsRetry() {
        let loadMore = ValuePipe<Void>()
        var requests = 0
        var counts: [Int?] = []
        let signal = peerMediaSearchMessages(loadMore: loadMore.signal(), request: { _ in
            requests += 1
            return .complete()
        })
        let disposable = signal.start(next: { counts.append($0?.count) })
        loadMore.putNext(())
        XCTAssertEqual(counts, [nil, 0, 0])
        XCTAssertEqual(requests, 2)
        disposable.dispose()
    }

    func testReentrantLoadMoreKeepsNextRequestAlive() {
        let loadMore = ValuePipe<Void>()
        let next = Promise<(SearchResponse, Int)>()
        var requests = 0
        var counts: [Int] = []
        let signal = peerMediaSearchMessages(loadMore: loadMore.signal(), request: { _ in
            requests += 1
            return requests == 1 ? .single((SearchResponse(messages: [], completed: false), 1)) : next.get()
        })
        let disposable = signal.start(next: { messages in
            guard let messages else { return }
            counts.append(messages.count)
            if counts.count == 1 { loadMore.putNext(()) }
        })
        next.set(.single((SearchResponse(messages: messages), 2)))
        XCTAssertEqual(counts, [0, 5])
        XCTAssertEqual(requests, 2)
        disposable.dispose()
    }

    func testGridTopAndEmptyQueryDoNotRequestSearchPages() {
        let controller = Controller()
        var calls = 0
        let disposable = controller.searchLoadMore.signal().start(next: { calls += 1 })
        controller.scroll(.top)
        controller.scroll(.none)
        controller.scroll(.bottom, query: "")
        XCTAssertEqual(calls, 0)
        controller.scroll(.bottom)
        XCTAssertEqual(calls, 1)
        disposable.dispose()
    }

    func testDisposedPaginationReleasesRequestContext() {
        final class Token {}
        var token: Token? = Token()
        weak var weakToken = token
        let loadMore = ValuePipe<Void>()
        var signal: Signal<[Message]?, NoError>? = peerMediaSearchMessages(loadMore: loadMore.signal(), request: { [token] _ in
            _ = token
            return .never()
        })
        token = nil
        let disposable = signal!.start()
        signal = nil
        XCTAssertNotNil(weakToken)
        disposable.dispose()
        XCTAssertNil(weakToken)
    }
}
