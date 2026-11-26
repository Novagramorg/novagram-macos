import XCTest
import SwiftSignalKit

struct Message: Equatable { let id: Int }
typealias SearchMessagesState = Int
struct SearchMessagesResult { let messages: [Message]; let completed: Bool }
struct ChatContextResult: Equatable { let id: String }
struct ChatContextResultCollection { let nextOffset: String?; let results: [ChatContextResult] }
struct RequestResult { let results: ChatContextResultCollection }
struct EnginePeer { let id: Int }
enum Resolved { case progress, result(EnginePeer?) }
enum Scope { case everywhere }
enum Tag { case music }
enum SearchLocation { case general(scope: Scope, groupId: Int?, tags: [Tag], minDate: Int32?, maxDate: Int32?, folderId: Int?, communityId: Int?) }
struct RequestError: Error {}
final class Engine {
    var messages: Engine { self }
    var peers: Engine { self }
    var resolvedPeer: EnginePeer? = EnginePeer(id: 99)
    var searchStates: [Int?] = []
    var searchQueries: [String] = []
    var botOffsets: [String] = []
    var botFailure = false
    var respond: ((String) -> Signal<RequestResult?, RequestError>)?
    func searchMessages(location: SearchLocation, query: String, state: Int?) -> Signal<(SearchMessagesResult, SearchMessagesState), NoError> {
        searchStates.append(state)
        searchQueries.append(query)
        let count = min(5, (state ?? 0) + 2)
        return .single((SearchMessagesResult(messages: (1...count).map { Message(id: $0) }, completed: count == 5), count))
    }
    func resolvePeerByName(name: String, referrer: String?) -> Signal<Resolved, NoError> { .single(.result(resolvedPeer)) }
    func requestChatContextResults(botId: Int, peerId: Int, query: String, offset: String) -> Signal<RequestResult?, RequestError> {
        botOffsets.append(offset)
        if let respond { return respond(offset) }
        if botFailure { return .fail(RequestError()) }
        let ids = offset.isEmpty ? ["a", "b"] : ["b", "c"]
        return .single(RequestResult(results: ChatContextResultCollection(nextOffset: offset.isEmpty ? "next" : nil, results: ids.map { ChatContextResult(id: $0) })))
    }
}
struct Account { let peerId = 1 }
final class Context { let engine = Engine(); let account = Account() }
func shared(context: Context, sharedAudioLoadMore: ValuePipe<Void>) -> Signal<[Message]?, NoError> {
    __SHARED__
}
func search(context: Context, searchLoadMore: ValuePipe<Void>, trimmedQuery: String) -> Signal<[Message], NoError> {
    __SEARCH__
}
func bot(context: Context, searchLoadMore: ValuePipe<Void>, trimmedQuery: String = "music") -> Signal<[ChatContextResult], NoError> {
    let searchBot = "musicbot"
    __BOT__
}
enum Direction { case top, bottom, none }
struct Scroll { let direction: Direction }
struct PickerState { var searchQuery = "" }
final class SavedMusicContext {
    var loads = 0
    func loadMore() { loads += 1 }
}
final class Table {
    var scroll: ((Scroll) -> Void)?
    func setScrollHandler(_ action: @escaping (Scroll) -> Void) { scroll = action }
}
final class Controller {
    var didLoad: ((Controller, Int) -> Void)?
    var onDeinit: (() -> Void)?
    let tableView = Table()
    deinit { onDeinit?() }
}
func install(controller: Controller, stateValue: Atomic<PickerState>, savedMusicContext: SavedMusicContext, sharedAudioLoadMore: ValuePipe<Void>, searchLoadMore: ValuePipe<Void>, actionsDisposable: DisposableSet) {
    let progressOverlay: Int? = nil
    let emptyOverlay: Int? = nil
    __SCROLL__
    __CLOSE__
}

final class AudioPaginationTests: XCTestCase {
    func testSharedAudioLoadsEveryPageAndStops() {
        let context = Context()
        let load = ValuePipe<Void>()
        var counts: [Int] = []
        let subscription = shared(context: context, sharedAudioLoadMore: load).start(next: { if let value = $0 { counts.append(value.count) } })
        for _ in 0..<4 { load.putNext(()) }
        XCTAssertEqual(counts, [2, 4, 5])
        XCTAssertEqual(context.engine.searchStates, [nil, 2, 4])
        XCTAssertEqual(context.engine.searchQueries, ["", "", ""])
        subscription.dispose()
    }

    func testTextSearchKeepsQueryAndContinuationState() {
        let context = Context()
        let load = ValuePipe<Void>()
        var counts: [Int] = []
        let subscription = search(context: context, searchLoadMore: load, trimmedQuery: "song").start(next: { counts.append($0.count) })
        load.putNext(())
        load.putNext(())
        XCTAssertEqual(counts, [2, 4, 5])
        XCTAssertEqual(context.engine.searchQueries, ["song", "song", "song"])
        subscription.dispose()
    }

    func testBotPagesUseOffsetsAndDeduplicateResults() {
        let context = Context()
        let load = ValuePipe<Void>()
        var results: [[String]] = []
        let subscription = bot(context: context, searchLoadMore: load).start(next: { results.append($0.map { $0.id }) })
        load.putNext(())
        load.putNext(())
        XCTAssertEqual(results, [["a", "b"], ["a", "b", "c"]])
        XCTAssertEqual(context.engine.botOffsets, ["", "next"])
        subscription.dispose()
    }

    func testBotFailureRetainsResultsAndRetriesSameOffset() {
        let context = Context()
        let load = ValuePipe<Void>()
        var latest: [String] = []
        let subscription = bot(context: context, searchLoadMore: load).start(next: { latest = $0.map { $0.id } })
        context.engine.botFailure = true
        load.putNext(())
        XCTAssertEqual(latest, ["a", "b"])
        context.engine.botFailure = false
        load.putNext(())
        XCTAssertEqual(latest, ["a", "b", "c"])
        XCTAssertEqual(context.engine.botOffsets, ["", "next", "next"])
        subscription.dispose()
    }

    func testMissingBotCompletesWithEmptyResults() {
        let context = Context()
        context.engine.resolvedPeer = nil
        let load = ValuePipe<Void>()
        var latest: [ChatContextResult]?
        let subscription = bot(context: context, searchLoadMore: load).start(next: { latest = $0 })
        XCTAssertEqual(latest, [])
        XCTAssertEqual(context.engine.botOffsets, [])
        subscription.dispose()
    }

    func testRepeatedBotScrollWhileLoadingDoesNotOverlap() {
        let context = Context()
        context.engine.respond = { _ in .never() }
        let load = ValuePipe<Void>()
        let subscription = bot(context: context, searchLoadMore: load).start()
        for _ in 0..<10 { load.putNext(()) }
        XCTAssertEqual(context.engine.botOffsets, [""])
        subscription.dispose()
    }

    func testBotOffsetCyclesStop() {
        let load = ValuePipe<Void>()
        var requests: [String] = []
        let subscription = sendAudioBotSearchResults(loadMore: load.signal(), request: { offset in
            requests.append(offset)
            let next = offset == "a" ? "b" : "a"
            return .single(ChatContextResultCollection(nextOffset: next, results: [ChatContextResult(id: offset)]))
        }).start()
        for _ in 0..<10 { load.putNext(()) }
        XCTAssertEqual(requests, ["", "a", "b"])
        subscription.dispose()
    }

    func testEmptyOffsetIsTerminal() {
        let load = ValuePipe<Void>()
        var requests = 0
        let subscription = sendAudioBotSearchResults(loadMore: load.signal(), request: { _ in
            requests += 1
            return .single(ChatContextResultCollection(nextOffset: "", results: []))
        }).start()
        load.putNext(())
        XCTAssertEqual(requests, 1)
        subscription.dispose()
    }

    func testEmptyCompletionAllowsRetry() {
        let load = ValuePipe<Void>()
        var requests = 0
        var responses = 0
        let subscription = sendAudioBotSearchResults(loadMore: load.signal(), request: { _ in
            requests += 1
            return .complete()
        }).start(next: { _ in responses += 1 })
        load.putNext(())
        XCTAssertEqual(requests, 2)
        XCTAssertEqual(responses, 2)
        subscription.dispose()
    }

    func testPickerRoutesBottomScrollBySearchState() {
        let controller = Controller()
        let state = Atomic(value: PickerState())
        let saved = SavedMusicContext()
        let shared = ValuePipe<Void>()
        let search = ValuePipe<Void>()
        let actions = DisposableSet()
        var sharedLoads = 0
        var searchLoads = 0
        actions.add(shared.signal().start(next: { sharedLoads += 1 }))
        actions.add(search.signal().start(next: { searchLoads += 1 }))
        install(controller: controller, stateValue: state, savedMusicContext: saved, sharedAudioLoadMore: shared, searchLoadMore: search, actionsDisposable: actions)
        controller.didLoad?(controller, 0)
        controller.tableView.scroll?(Scroll(direction: .top))
        XCTAssertEqual(saved.loads, 0)
        controller.tableView.scroll?(Scroll(direction: .bottom))
        XCTAssertEqual(saved.loads, 1)
        XCTAssertEqual(sharedLoads, 1)
        _ = state.swap(PickerState(searchQuery: "song"))
        controller.tableView.scroll?(Scroll(direction: .bottom))
        XCTAssertEqual(saved.loads, 1)
        XCTAssertEqual(sharedLoads, 1)
        XCTAssertEqual(searchLoads, 1)
    }

    func testPickerDeinitCancelsPendingBotRequest() {
        let context = Context()
        var cancelled = 0
        context.engine.respond = { _ in Signal { _ in ActionDisposable { cancelled += 1 } } }
        let load = ValuePipe<Void>()
        let actions = DisposableSet()
        actions.add(bot(context: context, searchLoadMore: load).start())
        var controller: Controller? = Controller()
        install(controller: controller!, stateValue: Atomic(value: PickerState()), savedMusicContext: SavedMusicContext(), sharedAudioLoadMore: ValuePipe(), searchLoadMore: load, actionsDisposable: actions)
        weak var weakController = controller
        controller = nil
        XCTAssertNil(weakController)
        XCTAssertEqual(cancelled, 1)
        load.putNext(())
        XCTAssertEqual(context.engine.botOffsets, [""])
    }

    func testReentrantNextPageKeepsPendingRequestAlive() {
        let load = ValuePipe<Void>()
        let pending = Promise<ChatContextResultCollection?>()
        var offsets: [String] = []
        var latest: [String] = []
        let signal = sendAudioBotSearchResults(loadMore: load.signal(), request: { offset in
            offsets.append(offset)
            if offset.isEmpty {
                return .single(ChatContextResultCollection(nextOffset: "next", results: [ChatContextResult(id: "a")]))
            }
            return pending.get()
        })
        let subscription = signal.start(next: { results in
            latest = results.map { $0.id }
            if latest == ["a"] { load.putNext(()) }
        })
        pending.set(.single(ChatContextResultCollection(nextOffset: nil, results: [ChatContextResult(id: "b")])))
        XCTAssertEqual(offsets, ["", "next"])
        XCTAssertEqual(latest, ["a", "b"])
        subscription.dispose()
    }

    func testReplacingBotSearchIgnoresLateOldResponse() {
        let old = Context()
        let new = Context()
        var oldSubscriber: Subscriber<RequestResult?, RequestError>?
        old.engine.respond = { _ in Signal { subscriber in
            oldSubscriber = subscriber
            return EmptyDisposable
        } }
        let load = ValuePipe<Void>()
        let disposable = MetaDisposable()
        var oldUpdates = 0
        var newUpdates = 0
        disposable.set(bot(context: old, searchLoadMore: load).start(next: { _ in oldUpdates += 1 }))
        disposable.set(bot(context: new, searchLoadMore: load).start(next: { _ in newUpdates += 1 }))
        oldSubscriber?.putNext(RequestResult(results: ChatContextResultCollection(nextOffset: nil, results: [ChatContextResult(id: "stale")])))
        XCTAssertEqual(oldUpdates, 0)
        XCTAssertEqual(newUpdates, 1)
        disposable.dispose()
    }

    func testDisposedBotPaginationReleasesCapturedRequestContext() {
        final class Token {}
        var token: Token? = Token()
        weak var weakToken = token
        let load = ValuePipe<Void>()
        var signal: Signal<[ChatContextResult], NoError>? = sendAudioBotSearchResults(loadMore: load.signal(), request: { [token] _ in
            _ = token
            return .never()
        })
        token = nil
        let subscription = signal!.start()
        signal = nil
        XCTAssertNotNil(weakToken)
        subscription.dispose()
        XCTAssertNil(weakToken)
    }
}
