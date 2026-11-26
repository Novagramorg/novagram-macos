import XCTest
import SwiftSignalKit

enum PeerMediaUpdateState { case search, history, loading }
struct PeerMediaUpdate {
    var messages: [Message] = []
    var updateType = PeerMediaUpdateState.loading
    var laterId: Int?
    var earlierId: Int?
    var searchState = SearchState(request: "")
    var contentSettings = 0
    func withUpdatedUpdatedType(_ type: PeerMediaUpdateState) -> PeerMediaUpdate {
        var result = self
        result.updateType = type
        return result
    }
}
enum ChatHistoryLocation: Equatable { case Initial(count: Int, scrollPosition: Int?) }
final class Table {
    var scroll: ((Scroll) -> Void)?
    func setScrollHandler(_ handler: @escaping (Scroll) -> Void) { scroll = handler }
}
final class ListController {
    let context = Context()
    let peerId = 1
    let tagMask = MessageTags.photoOrVideo
    let threadId: Int64? = 10
    var isSearch = true
    let updateView = Atomic<PeerMediaUpdate?>(value: nil)
    let searchLoadMore = ValuePipe<Void>()
    let genericView = Table()
    let location = ValuePromise<ChatHistoryLocation>(ignoreRepeated: true)

    func search(_ query: String) -> Signal<PeerMediaUpdate, NoError> {
        let searchState = SearchState(request: query)
        let strongSelf = self
        let context = self.context
        let searchLoadMore = self.searchLoadMore.signal()
        let isFirst = true
        __LIST_SEARCH__
    }

    func installScroll() {
        let animated = Atomic(value: false)
        let location = self.location
        var requestCount = 5
        let perPageCount = { 10 }
        __LIST_SCROLL__
    }
}

final class ListPaginationTests: XCTestCase {
    func testBottomScrollLoadsNextSearchPageWithoutReplacingRows() {
        let controller = ListController()
        controller.context.engine.source = (1...5).map { Message(id: $0, tags: .photoOrVideo, threadId: 10) }
        controller.context.engine.pageSize = 2
        controller.installScroll()
        var counts: [Int] = []
        let disposable = controller.search("caption").start(next: { update in
            _ = controller.updateView.swap(update)
            if update.updateType == .search { counts.append(update.messages.count) }
        })
        controller.genericView.scroll?(Scroll(direction: .top))
        XCTAssertEqual(controller.context.engine.requests, 1)
        controller.genericView.scroll?(Scroll(direction: .bottom))
        controller.genericView.scroll?(Scroll(direction: .bottom))
        controller.genericView.scroll?(Scroll(direction: .bottom))
        XCTAssertEqual(counts, [2, 4, 5])
        XCTAssertEqual(controller.context.engine.requestStates, [nil, 2, 4])
        disposable.dispose()
    }

    func testFocusedEmptySearchStillLoadsHistory() {
        let controller = ListController()
        controller.installScroll()
        _ = controller.updateView.swap(PeerMediaUpdate())
        var historyLoads = 0
        let disposable = controller.location.get().start(next: { _ in historyLoads += 1 })
        controller.genericView.scroll?(Scroll(direction: .bottom))
        XCTAssertEqual(historyLoads, 1)
        XCTAssertEqual(controller.context.engine.requests, 0)
        disposable.dispose()
    }
}
