import Cocoa
import XCTest
@testable import TGUIKit
@testable import SwipeLab

final class TableSwipeTests: XCTestCase {
    override func setUp() { TGUIKitTestBootstrap.install() }

    private func fixture(_ count: Int) -> (NSWindow, TableView) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 500), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let table = TableView(frame: window.contentView!.bounds)
        window.contentView!.addSubview(table)
        for index in 0..<count { _ = table.addItem(item: ChatListRowItem(.zero, stableId: index), redraw: false) }
        table.view.reloadData()
        table.layoutSubtreeIfNeeded()
        table.enumerateVisibleViews(with: { _ in }, force: true)
        return (window, table)
    }

    private func existing(_ table: TableView, optimized: Bool) -> [ObjectIdentifier] {
        var views: [ObjectIdentifier] = []
        if optimized {
            table.enumerateExistingItemViews { _, view in views.append(ObjectIdentifier(view)) }
        } else {
            table.enumerateViews { view in views.append(ObjectIdentifier(view)); return true }
        }
        return views.sorted { $0.hashValue < $1.hashValue }
    }

    func testAvailableRowsMatchFullScanAcrossScrollingAndRemoval() {
        let (window, table) = fixture(1000)
        defer { window.contentView = nil; window.close() }
        for offset: CGFloat in [0, 500, 15000, 0] {
            table.contentView.scroll(to: NSPoint(x: 0, y: offset))
            table.layoutSubtreeIfNeeded()
            table.enumerateVisibleViews(with: { _ in }, force: true)
            let reference = existing(table, optimized: false)
            XCTAssertFalse(reference.isEmpty)
            XCTAssertLessThan(reference.count, 100)
            XCTAssertEqual(existing(table, optimized: true), reference)
        }
        table.removeAll()
        XCTAssertTrue(existing(table, optimized: true).isEmpty)
    }

    func testStaleIndexesRetainExistingFallback() {
        let (window, table) = fixture(60)
        defer { window.contentView = nil; window.close() }
        let first = table.item(at: 0)
        first._index = 1
        var reference: [ObjectIdentifier] = []
        for item in table.allItems {
            if let view = table.viewNecessary(at: item.index) { reference.append(ObjectIdentifier(view)) }
        }
        var current: [ObjectIdentifier] = []
        table.enumerateExistingItemViews { _, view in current.append(ObjectIdentifier(view)) }
        XCTAssertEqual(current, reference)
        first._index = 0
    }

    func testControllerUpdatesExistingRowsWithoutRebinding() {
        let (window, table) = fixture(1000)
        defer { window.contentView = nil; window.close() }
        let controller = CandidateController(table)
        for item in table.allItems {
            (item as! ChatListRowItem).getHideProgress = { [weak controller] in controller?.getSwipeProgress() }
        }
        var rows: [CandidateRow] = []
        table.enumerateExistingItemViews { _, view in if let row = view as? CandidateRow { rows.append(row) } }
        XCTAssertFalse(rows.isEmpty)
        let counts = rows.map(\.bindings)
        let badgeDisplays = rows.map { ($0.item as! ChatListRowItem).ctxShortBadgeNode!.displays }
        for step in 0..<121 {
            controller.updateSwipingState(.swiping(delta: CGFloat(step) * 250 / 120), controller: ControllerTarget(), isPrevious: true)
        }
        XCTAssertEqual(rows.map(\.bindings), counts)
        XCTAssertEqual(rows.map { ($0.item as! ChatListRowItem).ctxShortBadgeNode!.displays }, badgeDisplays)
        XCTAssertEqual(controller.genericView.updates, 121)
        for row in rows {
            XCTAssertEqual(row.contentView.layer?.opacity, 1)
            XCTAssertEqual(row.badgeShortView?.layer?.opacity, 0)
        }
        XCTAssertEqual(controller.genericView.backgroundView.layer?.opacity, 0)
        controller.updateSwipingState(.failed(delta: 0), controller: ControllerTarget(), isPrevious: true)
        for row in rows {
            XCTAssertEqual(row.contentView.layer?.opacity, 0)
            XCTAssertEqual(row.badgeShortView?.layer?.opacity, 1)
        }
    }

    func testControllerKeepsEligibilityChecks() {
        let (window, table) = fixture(5)
        defer { window.contentView = nil; window.close() }
        let controller = CandidateController(table)
        controller.updateSwipingState(.start, controller: ControllerTarget(), isPrevious: false)
        var target = ControllerTarget(); target.stake.keepLeft = 0
        controller.updateSwipingState(.start, controller: target, isPrevious: true)
        XCTAssertEqual(controller.genericView.updates, 0)
        XCTAssertNil(controller.swipeState)
    }

    func testAvailableRowEnumerationBenchmark() throws {
        guard ProcessInfo.processInfo.environment["SWIPE_BENCHMARK"] != nil else { throw XCTSkip("Opt-in native table benchmark") }
        var report: [String: Any] = [:]
        for count in [100, 1000, 10000] {
            let (window, table) = fixture(count)
            let expected = existing(table, optimized: false).count
            XCTAssertGreaterThan(expected, 0)
            var baseline: [Double] = [], candidate: [Double] = []
            var visits = 0
            for batch in 0..<11 {
                for optimized in batch % 2 == 0 ? [false, true] : [true, false] {
                    let start = CACurrentMediaTime()
                    for _ in 0..<200 {
                        if optimized {
                            table.enumerateExistingItemViews { _, _ in visits += 1 }
                        } else {
                            table.enumerateViews { _ in visits += 1; return true }
                        }
                    }
                    let elapsed = (CACurrentMediaTime() - start) * 1e6 / 200
                    if optimized { candidate.append(elapsed) } else { baseline.append(elapsed) }
                }
            }
            XCTAssertEqual(visits, expected * 200 * 22)
            report[String(count)] = ["existing_rows": expected, "baseline_us": baseline, "candidate_us": candidate]
            window.contentView = nil; window.close()
        }
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: "/tmp/chat-swipe-enumeration.json"))
    }
}
