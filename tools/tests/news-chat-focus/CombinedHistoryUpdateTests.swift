import Foundation
import XCTest
import SwiftSignalKit

private struct CombinedHistoryUpdate {
    let view: MessageHistoryView?
    let type: ChatHistoryViewUpdateType
    let scrollPosition: ChatHistoryViewScrollPosition?
}

private func combinedHistoryUpdates(_ historyViewUpdate1: Signal<(ChatHistoryViewUpdate, Int?, Int, Int), NoError>, auxiliary: Signal<Int, NoError>, search: Signal<Bool, NoError> = .single(false)) -> Signal<CombinedHistoryUpdate, NoError> {
__HISTORY_STREAM__
__UPDATE_STATE__
    return combineLatest(historyViewUpdate, auxiliary, search) |> mapToQueue { update, _, searchStateUpdated -> Signal<CombinedHistoryUpdate, NoError> in
__CLASSIFICATION__
        return .single(CombinedHistoryUpdate(view: view, type: updateType, scrollPosition: scrollPosition))
    }
}

private struct InitialRowsView {
    let originalView: MessageHistoryView?
    let filteredEntries: [Int]
}

private func insertsInitialRows(fromView: InitialRowsView?, firstTransition: Bool) -> Bool {
    let scrollToItem: Int? = 1
__INITIAL_CONDITION__
}

final class CombinedHistoryUpdateTests: XCTestCase {
    private func view(loading: Bool) -> MessageHistoryView {
        MessageHistoryView(entries: [Entry(message: Message(id: 50))], isAnchorOnlyWhileLoading: loading, isLoading: loading)
    }

    private func initialUpdate(loading: Bool) -> Signal<ChatHistoryViewUpdate, NoError> {
        initialSearchUpdates(signal: .single((view(loading: loading), .Generic, nil)), cachedAnchor: true, searchLocation: .id(50, nil, nil))
    }

    func testAuxiliaryUpdatesDoNotReplayCachedFocusOrInitialTransition() {
        let auxiliary = ValuePipe<Int>()
        var outputs: [CombinedHistoryUpdate] = []
        let disposable = combinedHistoryUpdates(initialUpdate(loading: true) |> map { ($0, nil, 0, 0) }, auxiliary: auxiliary.signal()).start(next: { outputs.append($0) })
        defer { disposable.dispose() }
        auxiliary.putNext(0)
        auxiliary.putNext(1)
        auxiliary.putNext(2)
        XCTAssertEqual(outputs.count, 3)
        guard case .index? = outputs[0].scrollPosition else { return XCTFail("First update must focus") }
        XCTAssertEqual(outputs[0].type, .Initial(fadeIn: false))
        for output in outputs.dropFirst() {
            guard case nil = output.scrollPosition else { return XCTFail("Auxiliary update replayed focus") }
            XCTAssertEqual(output.type, .Generic(type: .Generic))
            XCTAssertEqual(output.view?.entries.first?.message.id, 50)
        }
    }

    func testLoadedHistoryDoesNotRefocusAfterUserScrolls() {
        let auxiliary = ValuePipe<Int>()
        var output: CombinedHistoryUpdate?
        let disposable = combinedHistoryUpdates(initialUpdate(loading: false) |> map { ($0, nil, 0, 0) }, auxiliary: auxiliary.signal()).start(next: { output = $0 })
        defer { disposable.dispose() }
        auxiliary.putNext(0)
        auxiliary.putNext(1)
        guard case nil = output?.scrollPosition else { return XCTFail("Loaded history must not recenter on UI updates") }
        XCTAssertEqual(output?.type, .Generic(type: .Generic))
    }

    func testNewNavigationCanFocusTheSameMessageAgain() {
        let history = ValuePipe<(ChatHistoryViewUpdate, Int?, Int, Int)>()
        let auxiliary = ValuePipe<Int>()
        var outputs: [CombinedHistoryUpdate] = []
        let disposable = combinedHistoryUpdates(history.signal(), auxiliary: auxiliary.signal()).start(next: { outputs.append($0) })
        defer { disposable.dispose() }
        var initial: ChatHistoryViewUpdate?
        let initialDisposable = initialUpdate(loading: false).start(next: { initial = $0 })
        defer { initialDisposable.dispose() }
        guard let initial else { return XCTFail() }
        auxiliary.putNext(0)
        history.putNext((initial, nil, 0, 0))
        auxiliary.putNext(1)
        history.putNext((initial, nil, 1, 0))
        XCTAssertEqual(outputs.count, 3)
        guard case .index? = outputs[0].scrollPosition, case nil = outputs[1].scrollPosition, case .index? = outputs[2].scrollPosition else {
            return XCTFail("Only fresh history events may request focus")
        }
    }

    func testHistoryFillPreservationIsNotReplayedByPeerUpdates() {
        let history = ValuePipe<(MessageHistoryView, ViewUpdateType, Int?)>()
        let auxiliary = ValuePipe<Int>()
        let mapped = initialSearchUpdates(signal: history.signal(), cachedAnchor: true, searchLocation: .id(50, nil, nil)) |> map { ($0, Optional<Int>.none, 0, 0) }
        var outputs: [CombinedHistoryUpdate] = []
        let disposable = combinedHistoryUpdates(mapped, auxiliary: auxiliary.signal()).start(next: { outputs.append($0) })
        defer { disposable.dispose() }
        auxiliary.putNext(0)
        history.putNext((view(loading: true), .Generic, nil))
        history.putNext((view(loading: false), .FillHole, nil))
        auxiliary.putNext(1)
        guard case .keepInPlace(messageId: 50)? = outputs[1].scrollPosition, case nil = outputs[2].scrollPosition else {
            return XCTFail("History anchor preservation must run once")
        }
    }

    func testSearchSuppressedFocusIsNotReplayedLater() {
        let search = ValuePipe<Bool>()
        var output: CombinedHistoryUpdate?
        let disposable = combinedHistoryUpdates(initialUpdate(loading: false) |> map { ($0, nil, 0, 0) }, auxiliary: .single(0), search: search.signal()).start(next: { output = $0 })
        defer { disposable.dispose() }
        search.putNext(true)
        search.putNext(false)
        guard case nil = output?.scrollPosition else { return XCTFail("Consumed focus must stay consumed") }
    }

    func testCachedRowsAreDiffedEvenWhenAppearanceRequiresMainQueue() {
        XCTAssertFalse(insertsInitialRows(fromView: InitialRowsView(originalView: view(loading: true), filteredEntries: [50]), firstTransition: true))
    }

    func testFirstRowsStillUseFastInitialInsertion() {
        XCTAssertTrue(insertsInitialRows(fromView: nil, firstTransition: true))
        XCTAssertTrue(insertsInitialRows(fromView: InitialRowsView(originalView: nil, filteredEntries: []), firstTransition: true))
        XCTAssertFalse(insertsInitialRows(fromView: nil, firstTransition: false))
    }
}
