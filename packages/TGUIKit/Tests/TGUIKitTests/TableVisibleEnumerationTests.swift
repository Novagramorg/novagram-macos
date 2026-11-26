import AppKit
import XCTest
@testable import TGUIKit

private final class VisibleEnumerationRangeTable: TGFlipableTableView {
    var nextRange: NSRange?
    override func rows(in rect: NSRect) -> NSRange {
        if let nextRange {
            self.nextRange = nil
            return nextRange
        }
        return super.rows(in: rect)
    }
}

final class TableVisibleEnumerationTests: XCTestCase {
    override func setUp() {
        super.setUp()
        TGUIKitTestBootstrap.install()
    }

    func testClearingRowsInsideCallbackStopsBothDirections() {
        for reversed in [false, true] {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 400), styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            let table = TableView(frame: window.contentView!.bounds)
            window.contentView!.addSubview(table)
            for id in 0..<4 { _ = table.addItem(item: TableRowItem(.zero, stableId: id)) }
            table.layoutSubtreeIfNeeded()
            XCTAssertEqual(table.visibleRows(), NSRange(location: 0, length: 4))
            var seen: [Int] = []
            table.enumerateVisibleItems(reversed: reversed) { item in
                seen.append(item.stableId.base as! Int)
                table.removeAll()
                return true
            }
            XCTAssertEqual(seen, reversed ? [3] : [0])
            XCTAssertEqual(table.count, 0)
            window.close()
        }
    }

    func testReplacementsRemainVisibleToLaterCallbacks() {
        for reversed in [false, true] {
            let table = TableView(frame: NSRect(x: 0, y: 0, width: 320, height: 240))
            let spy = VisibleEnumerationRangeTable(frame: table.bounds)
            table.tableView = spy
            table.updateAfterInitialize()
            for id in 0..<10 { _ = table.addItem(item: TableRowItem(.zero, stableId: id)) }
            spy.nextRange = NSRange(location: 2, length: 4)
            var seen: [Int] = []
            table.enumerateVisibleItems(reversed: reversed) { item in
                seen.append(item.stableId.base as! Int)
                if seen.count == 1 {
                    table.remove(at: 4)
                    _ = table.insert(item: TableRowItem(.zero, stableId: 100), at: 4)
                }
                return true
            }
            XCTAssertEqual(seen, reversed ? [5, 100, 3, 2] : [2, 3, 100, 5])
        }
    }

    func testStaleRangesStayWithinCurrentRowsAndHonorEarlyExit() {
        let table = TableView(frame: NSRect(x: 0, y: 0, width: 320, height: 240))
        let spy = VisibleEnumerationRangeTable(frame: table.bounds)
        table.tableView = spy
        table.updateAfterInitialize()
        for id in 0..<4 { _ = table.addItem(item: TableRowItem(.zero, stableId: id)) }
        let cases: [(NSRange, [Int])] = [(.init(location: NSNotFound, length: 0), []), (.init(location: NSNotFound, length: 1), []), (.init(location: 0, length: 0), []), (.init(location: -1, length: 3), []), (.init(location: 0, length: -1), []), (.init(location: 4, length: 2), []), (.init(location: 2, length: Int.max), [2, 3])]
        for (range, expected) in cases {
            for reversed in [false, true] {
                for stopAfterFirst in [false, true] {
                    spy.nextRange = range
                    var seen: [Int] = []
                    table.enumerateVisibleItems(reversed: reversed) { seen.append($0.stableId.base as! Int); return !stopAfterFirst }
                    let ordered = reversed ? Array(expected.reversed()) : expected
                    XCTAssertEqual(seen, stopAfterFirst ? Array(ordered.prefix(1)) : ordered)
                }
            }
        }
    }

    func testShrinkingTailAndRegrowingWithinVisibleRange() {
        for regrow in [false, true] {
            let table = TableView(frame: NSRect(x: 0, y: 0, width: 320, height: 240))
            let spy = VisibleEnumerationRangeTable(frame: table.bounds)
            table.tableView = spy
            table.updateAfterInitialize()
            for id in 0..<4 { _ = table.addItem(item: TableRowItem(.zero, stableId: id)) }
            spy.nextRange = NSRange(location: 0, length: 4)
            var seen: [Int] = []
            table.enumerateVisibleItems { item in
                seen.append(item.stableId.base as! Int)
                if seen.count == 1 { table.remove(at: 3) }
                if seen.count == 2 && regrow { _ = table.addItem(item: TableRowItem(.zero, stableId: 100)) }
                return true
            }
            XCTAssertEqual(seen, regrow ? [0, 1, 2, 100] : [0, 1, 2])
        }
    }

    func testOptionalLookupTracksReplacementRemovalAndInvalidIndexes() {
        let table = TableView(frame: .zero)
        XCTAssertNil(table.optionalItem(at: 0))
        let first = TableRowItem(.zero, stableId: 1)
        let second = TableRowItem(.zero, stableId: 2)
        _ = table.addItem(item: first)
        XCTAssertTrue(table.optionalItem(at: 0) === first)
        for index in [Int.min, -1, 1, Int.max] { XCTAssertNil(table.optionalItem(at: index)) }
        table.remove(at: 0)
        _ = table.addItem(item: second)
        XCTAssertTrue(table.optionalItem(at: 0) === second)
        table.removeAll()
        XCTAssertNil(table.optionalItem(at: 0))
    }

    func testNestedEnumerationSeesCurrentListWhileOuterCallStopsSafely() {
        let table = TableView(frame: NSRect(x: 0, y: 0, width: 320, height: 240))
        let spy = VisibleEnumerationRangeTable(frame: table.bounds)
        table.tableView = spy
        table.updateAfterInitialize()
        for id in 0..<4 { _ = table.addItem(item: TableRowItem(.zero, stableId: id)) }
        spy.nextRange = NSRange(location: 0, length: 4)
        var outer: [Int] = []
        var inner: [Int] = []
        table.enumerateVisibleItems { item in
            outer.append(item.stableId.base as! Int)
            if outer.count == 1 {
                table.removeAll()
                _ = table.addItem(item: TableRowItem(.zero, stableId: 100))
                spy.nextRange = NSRange(location: 0, length: 1)
                table.enumerateVisibleItems { inner.append($0.stableId.base as! Int); return true }
            }
            return true
        }
        XCTAssertEqual(outer, [0])
        XCTAssertEqual(inner, [100])
    }
}
