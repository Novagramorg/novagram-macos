import AppKit
import XCTest
import ScrollTypes
@testable import LabCode

final class ChatControllerLabTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        _ = NSApplication.shared
    }

    func testLargeCenteredMessageMeasuresFewerRows() {
        let rows = (0 ..< 121).map { TableRowItem($0, height: $0 == 60 ? 500 : 60) }
        let baseline = selectBaseline(rows, state: center(60), viewport: 720)
        let candidate = selectCandidate(rows, state: center(60), viewport: 720)
        XCTAssertEqual(baseline.rows.count, 13)
        XCTAssertEqual(candidate.rows.count, 5)
        XCTAssertEqual(candidate.ids, Array(58 ... 62))
        XCTAssertEqual(visibleGeometry(candidate.rows, anchor: 60, viewport: 720), visibleGeometry(rows, anchor: 60, viewport: 720))
    }

    func testRandomizedCenteredViewportMatchesFullHistory() {
        var seed: UInt64 = 77091
        func next(_ limit: Int) -> Int {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Int((seed >> 32) % UInt64(limit))
        }
        for _ in 0 ..< 4000 {
            let count = next(100) + 1
            let anchor = next(count)
            let viewport = CGFloat(next(900) + 100)
            let rows = (0 ..< count).map { TableRowItem($0, height: CGFloat(next(700) + 1) / 2, ignored: next(12) == 0) }
            var measured: [Int] = []
            let selection = selectCandidate(rows, state: center(anchor), viewport: viewport, measure: { measured.append($0.stableId) })
            XCTAssertEqual(Set(measured).count, measured.count)
            XCTAssertEqual(selection.ids, Array(selection.start ..< selection.start + selection.rows.count))
            XCTAssertEqual(selection.insertions.map { $0.0 }, Array(0 ..< selection.rows.count))
            if !rows[anchor].ignoreAtInitialization && rows[anchor].height < viewport {
                let actual = visibleGeometry(selection.rows, anchor: anchor, viewport: viewport)
                let expected = visibleGeometry(rows, anchor: anchor, viewport: viewport)
                let delta = actual.first(where: { $0.id == anchor })!.y - expected.first(where: { $0.id == anchor })!.y
                XCTAssertLessThanOrEqual(abs(delta), 1)
                XCTAssertEqual(actual, visibleGeometry(rows, anchor: anchor, viewport: viewport, alignmentShift: delta))
            }
            let remaining = remainingCandidate(rows, selection: selection)
            XCTAssertEqual(remaining.completions, 1)
            var completed = selection.rows
            for (index, item) in remaining.transitions[0].inserted { completed.insert(item, at: index) }
            XCTAssertEqual(completed.map { $0.stableId }, rows.map { $0.stableId })
        }
    }

    func testCenterAtHistoryEdgesFillsViewport() {
        let rows = (0 ..< 80).map { TableRowItem($0, height: 60) }
        for anchor in [0, 1, 2, 77, 78, 79] {
            let baseline = selectBaseline(rows, state: center(anchor), viewport: 720)
            let candidate = selectCandidate(rows, state: center(anchor), viewport: 720)
            XCTAssertLessThan(baseline.rows.reduce(0) { $0 + $1.height }, 720)
            XCTAssertGreaterThanOrEqual(candidate.rows.reduce(0) { $0 + $1.height }, 720)
            XCTAssertEqual(visibleGeometry(candidate.rows, anchor: anchor, viewport: 720), visibleGeometry(rows, anchor: anchor, viewport: 720))
        }
    }

    func testWholeRowFocusExcludesTextAndAlbumTargets() {
        XCTAssertTrue(TableScrollFocus(focus: true).isWholeRow)
        XCTAssertTrue(TableScrollFocus(focus: false).isWholeRow)
        XCTAssertFalse(TableScrollFocus(focus: true, string: "search").isWholeRow)
        XCTAssertFalse(TableScrollFocus(focus: true, innerId: 10).isWholeRow)
    }

    func testSpecialCentersRetainBaselineSelection() {
        for anchor in [0, 1, 12, 23, 24] {
            for viewport: CGFloat in [0, 1, 60, 400, 720] {
                let rows = (0 ..< 25).map { TableRowItem($0, height: CGFloat($0 % 5) * 21, ignored: $0 % 7 == 0) }
                for state in [center(anchor, inset: 30), center(anchor, innerId: 10), center(anchor, string: "search"), TableScrollState.center(id: anchor, innerId: nil, animated: false, focus: TableScrollFocus(focus: true, innerId: 10), inset: 0)] {
                    XCTAssertEqual(selectCandidate(rows, state: state, viewport: viewport).ids, selectBaseline(rows, state: state, viewport: viewport).ids)
                }
            }
        }
    }

    func testZeroHeightRowsAndZeroViewportRetainFallbackSelection() {
        for viewport: CGFloat in [0, 1, 720] {
            let rows = (0 ..< 25).map { TableRowItem($0, height: 0) }
            for anchor in 0 ..< rows.count {
                let baseline = selectBaseline(rows, state: center(anchor), viewport: viewport)
                let candidate = selectCandidate(rows, state: center(anchor), viewport: viewport)
                XCTAssertEqual(candidate.ids, baseline.ids)
                XCTAssertEqual(candidate.start, baseline.start)
            }
        }
    }

    func testTallAndIgnoredAnchorsRetainBaselineSelection() {
        for ignored in [true, false] {
            let rows = (0 ..< 30).map { TableRowItem($0, height: $0 == 15 ? 900 : 60, ignored: ignored && $0 == 15) }
            XCTAssertEqual(selectCandidate(rows, state: center(15), viewport: 720).ids, selectBaseline(rows, state: center(15), viewport: 720).ids)
        }
    }

    func testUnchangedTopAndDefaultSelection() {
        for count in [0, 1, 10, 90] {
            let rows = (0 ..< count).map { TableRowItem($0, height: CGFloat($0 % 4) * 48, ignored: $0 % 6 == 0) }
            for viewport: CGFloat in [0, 300, 720] {
                for anchor in [-1, 0, count / 2, count - 1, count] {
                    for state in [TableScrollState.top(id: anchor, innerId: nil, animated: false, focus: .init(focus: false), inset: -42), .saveVisible(.upper, false)] {
                        let old = selectBaseline(rows, state: state, viewport: viewport)
                        let new = selectCandidate(rows, state: state, viewport: viewport)
                        XCTAssertEqual(old.start, new.start)
                        XCTAssertEqual(old.ids, new.ids)
                    }
                }
            }
        }
    }

    func testEmptyHistoryCompletes() {
        let selection = Selection(start: 0, insertions: [])
        XCTAssertEqual(remainingBaseline([], selection: selection).completions, 0)
        let candidate = remainingCandidate([], selection: selection)
        XCTAssertEqual(candidate.completions, 1)
        XCTAssertEqual(candidate.transitions.count, 1)
        XCTAssertTrue(candidate.transitions[0].inserted.isEmpty)
    }

    func testCancellationDoesNotEmitRemainingTransition() {
        let rows = (0 ..< 80).map { TableRowItem($0, height: 60) }
        let selection = selectCandidate(rows, state: center(40), viewport: 720)
        for point in [1, 2, 10, 80] {
            let candidate = remainingCandidate(rows, selection: selection, cancelled: Cancellation(cancelAt: point))
            let baseline = remainingBaseline(rows, selection: selection, cancelled: Cancellation(cancelAt: point))
            XCTAssertTrue(candidate.transitions.isEmpty)
            XCTAssertEqual(candidate.completions, baseline.completions)
        }
    }

    func testMissingAnchorBuildsAllRowsInRemainingTransition() {
        let rows = (0 ..< 80).map { TableRowItem($0, height: 60) }
        let selection = selectCandidate(rows, state: center(-1), viewport: 720)
        XCTAssertTrue(selection.rows.isEmpty)
        let remainder = remainingCandidate(rows, selection: selection)
        XCTAssertEqual(remainder.transitions[0].inserted.map { $0.1.stableId }, Array(0 ..< 80))
    }

    func testRepeatedScrollDoesNotRelayoutControls() {
        let baseline = BaselineScroller()
        let candidate = CandidateScroller()
        let state = ChatHistoryState()
        for offset in 80 ..< 1080 {
            baseline.tableView.documentOffset.y = CGFloat(offset)
            candidate.tableView.documentOffset.y = CGFloat(offset)
            baseline.updateScroller(state)
            candidate.updateScroller(state, onlyIfVisibilityChanged: true)
        }
        XCTAssertEqual(baseline.frameUpdates, 4000)
        XCTAssertEqual(candidate.frameUpdates, 4)
        XCTAssertEqual(candidate.scroller.opacityChanges, 1)
        XCTAssertEqual(candidate.inputView.anchors.count, 1)
        XCTAssertEqual(candidate.scroller.frame, baseline.scroller.frame)
        XCTAssertEqual(candidate.scroller.isHidden, baseline.scroller.isHidden)
    }

    func testScrollerThresholdsAndHistoryChanges() {
        let candidate = CandidateScroller()
        let state = ChatHistoryState()
        for (offset, down, empty, hidden) in [(0, true, false, true), (79, true, false, true), (80, true, false, false), (81, true, false, false), (79, true, false, true), (0, false, false, false), (200, false, true, true)] {
            candidate.tableView.documentOffset.y = CGFloat(offset)
            candidate.tableView.isEmpty = empty
            let current = down ? state : ChatHistoryState(isDownOfHistory: false)
            candidate.updateScroller(current, onlyIfVisibilityChanged: true)
            XCTAssertEqual(candidate.scrollerTargetIsHidden, hidden)
            XCTAssertTrue(candidate.historyState === current)
            XCTAssertEqual(candidate.scroller.layer!.opacity, hidden ? 0 : 1)
        }
    }

    func testSameVisibilityFullUpdateStillLaysOutAfterResize() {
        let candidate = CandidateScroller()
        let state = ChatHistoryState()
        candidate.updateScroller(state)
        let before = candidate.scroller.frame
        candidate.frame.size.width += 100
        candidate.updateScroller(state)
        XCTAssertEqual(candidate.frameUpdates, 8)
        XCTAssertEqual(candidate.scroller.frame.minX, before.minX + 100)
        XCTAssertEqual(candidate.scroller.opacityChanges, 1)
    }

    func testScrollDoesNotPrematurelyFinishFadeOut() {
        let candidate = CandidateScroller()
        let baseline = BaselineScroller()
        let state = ChatHistoryState()
        for fixture in [candidate as ScrollerFixture, baseline] { fixture.tableView.documentOffset.y = 100 }
        candidate.updateScroller(state)
        baseline.updateScroller(state)
        candidate.tableView.documentOffset.y = 0
        baseline.tableView.documentOffset.y = 0
        candidate.updateScroller(state, onlyIfVisibilityChanged: true)
        baseline.updateScroller(state)
        candidate.updateScroller(state, onlyIfVisibilityChanged: true)
        baseline.updateScroller(state)
        XCTAssertTrue(baseline.scroller.isHidden)
        XCTAssertFalse(candidate.scroller.isHidden)
        candidate.scroller.completions.last?(true)
        XCTAssertTrue(candidate.scroller.isHidden)
    }

    func testInterruptedFadeCannotHideShownScroller() {
        let candidate = CandidateScroller()
        let state = ChatHistoryState()
        candidate.tableView.documentOffset.y = 100
        candidate.updateScroller(state)
        candidate.tableView.documentOffset.y = 0
        candidate.updateScroller(state)
        let hideCompletion = candidate.scroller.completions.last!
        candidate.tableView.documentOffset.y = 100
        candidate.updateScroller(state)
        hideCompletion(true)
        XCTAssertFalse(candidate.scroller.isHidden)
        XCTAssertEqual(candidate.scroller.layer!.opacity, 1)
    }

    func testRevealSearchStopsAtFirstMatch() {
        let views = (0 ..< 30).map { _ in RevealView() }
        views[2].hasRevealState = true
        views[6].hasRevealState = true
        let items = views.map(RevealItem.init)
        XCTAssertTrue(baselineReveal(items) === views[2])
        XCTAssertEqual(items.reduce(0) { $0 + $1.lookups }, 30)
        items.forEach { $0.lookups = 0 }
        XCTAssertTrue(candidateReveal(items) === views[2])
        XCTAssertLessThanOrEqual(items.reduce(0) { $0 + $1.lookups }, 4)
    }

    func testRevealSearchHandlesMissingAndNonChatViews() {
        let items = [RevealItem(nil), RevealItem(NSView()), RevealItem(RevealView())]
        XCTAssertNil(baselineReveal(items))
        XCTAssertNil(candidateReveal(items))
    }

    func testRealAppKitViewportMatchesForBothInitialWindows() {
        let rows = (0 ..< 121).map { TableRowItem($0, height: $0 == 60 ? 500 : 60) }
        let full = TableFixture(rows: rows, anchor: 60, viewport: 720)
        for selection in [selectBaseline(rows, state: center(60), viewport: 720), selectCandidate(rows, state: center(60), viewport: 720)] {
            let table = TableFixture(rows: selection.rows, anchor: 60, viewport: 720)
            XCTAssertEqual(table.visibleGeometry, full.visibleGeometry)
        }
    }
    func testRenderedViewportPixelsMatch() {
        let rows = (0 ..< 121).map { TableRowItem($0, height: $0 == 60 ? 500 : 60, text: "Native AppKit message content") }
        func pixels(_ selection: Selection) -> Data {
            let fixture = TableFixture(rows: selection.rows, anchor: 60, viewport: 720)
            let view = fixture.scroll
            let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
            view.cacheDisplay(in: view.bounds, to: bitmap)
            return Data(bytes: bitmap.bitmapData!, count: bitmap.bytesPerRow * bitmap.pixelsHigh)
        }
        XCTAssertEqual(pixels(selectBaseline(rows, state: center(60), viewport: 720)), pixels(selectCandidate(rows, state: center(60), viewport: 720)))
    }

}
