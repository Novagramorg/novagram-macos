import AppKit
import XCTest
@testable import class TGUIKit.TableView
@testable import class TGUIKit.TGFlipableTableView
import class TGUIKit.TableRowItem
import class TGUIKitBaseline.TableView
import class TGUIKitBaseline.TableRowItem

private final class RangeTable: TGFlipableTableView {
    var forcedRange: NSRange?
    override func rows(in rect: NSRect) -> NSRange {
        if let forcedRange {
            self.forcedRange = nil
            return forcedRange
        }
        return super.rows(in: rect)
    }
}

final class EnumerationTests: XCTestCase {
    override func setUp() {
        super.setUp()
        EnumerationBootstrap.install()
    }

    func testMutationRegressionBaseline() throws {
        guard ProcessInfo.processInfo.environment["ENUMERATION_BASELINE_CRASH"] == "1" else { throw XCTSkip("Isolated original crash reproduction") }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 400), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let table = TGUIKitBaseline.TableView(frame: window.contentView!.bounds)
        window.contentView!.addSubview(table)
        for id in 0..<4 { _ = table.addItem(item: TGUIKitBaseline.TableRowItem(.zero, stableId: id)) }
        table.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(table.visibleRows().length, 1)
        table.enumerateVisibleItems { _ in table.removeAll(); return true }
        window.close()
    }

    func testNativeOrderingInsetsAndEarlyExitMatchOriginal() {
        for flipped in [false, true] {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 240), styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            let a = TGUIKitBaseline.TableView(frame: NSRect(x: 0, y: 0, width: 320, height: 240), isFlipped: flipped)
            let b = TGUIKit.TableView(frame: NSRect(x: 320, y: 0, width: 320, height: 240), isFlipped: flipped)
            window.contentView!.addSubview(a); window.contentView!.addSubview(b)
            for id in 0..<60 {
                _ = a.addItem(item: TGUIKitBaseline.TableRowItem(.zero, stableId: id))
                _ = b.addItem(item: TGUIKit.TableRowItem(.zero, stableId: id))
            }
            window.contentView!.layoutSubtreeIfNeeded()
            for top in [CGFloat(0), 25] {
                a.contentInsets.top = top; b.contentInsets.top = top
                for offset in [CGFloat(0), 40.5, 600, 3000] {
                    a.clipView.updateBounds(to: NSPoint(x: 0, y: offset), cancel: true)
                    b.clipView.updateBounds(to: NSPoint(x: 0, y: offset), cancel: true)
                    for inset in [CGFloat(0), 240, -10] {
                        for reversed in [false, true] {
                            for limit in [1, 3, 100] {
                                var old: [AnyHashable] = []
                                a.enumerateVisibleItems(reversed: reversed, inset: inset) { old.append($0.stableId); return old.count < limit }
                                for enumerate in [b.enumerateVisibleItems, b.enumerationLabCopied, b.enumerationLabTemporary, b.enumerationLabBulk] {
                                    var new: [AnyHashable] = []
                                    enumerate(reversed, inset) { new.append($0.stableId); return new.count < limit }
                                    XCTAssertEqual(old, new)
                                }
                            }
                        }
                    }
                }
            }
            window.close()
        }
    }

    func testCallbacksEnumerateOriginalVisibleRowsDuringMutations() {
        for variant in 0..<4 {
            for reversed in [false, true] {
                for mutation in 0..<4 {
                    let table = TGUIKit.TableView(frame: NSRect(x: 0, y: 0, width: 320, height: 240))
                    let spy = RangeTable(frame: table.bounds)
                    table.tableView = spy
                    table.updateAfterInitialize()
                    for id in 0..<10 { _ = table.addItem(item: TGUIKit.TableRowItem(.zero, stableId: id)) }
                    spy.forcedRange = NSRange(location: 2, length: 4)
                    let enumerate = [table.enumerationLabSlice, table.enumerationLabCopied, table.enumerationLabTemporary, table.enumerationLabBulk][variant]
                    var seen: [Int] = []
                    enumerate(reversed, 0) { item in
                        seen.append(item.stableId.base as! Int)
                        if seen.count == 1 {
                            switch mutation {
                            case 0: table.removeAll()
                            case 1: table.remove(at: 0)
                            case 2: _ = table.insert(item: TGUIKit.TableRowItem(.zero, stableId: 100), at: 0)
                            default:
                                table.remove(at: 4)
                                _ = table.insert(item: TGUIKit.TableRowItem(.zero, stableId: 100), at: 4)
                            }
                        }
                        return true
                    }
                    XCTAssertEqual(seen, reversed ? [5, 4, 3, 2] : [2, 3, 4, 5])
                }
            }
        }
    }

    func testLiveReplacementAndClearingPreserveSafeIteration() {
        for reversed in [false, true] {
            for mutation in 0..<3 {
                let table = TGUIKit.TableView(frame: NSRect(x: 0, y: 0, width: 320, height: 240))
                let spy = RangeTable(frame: table.bounds)
                table.tableView = spy
                table.updateAfterInitialize()
                for id in 0..<10 { _ = table.addItem(item: TGUIKit.TableRowItem(.zero, stableId: id)) }
                spy.forcedRange = NSRange(location: 2, length: 4)
                var seen: [Int] = []
                table.enumerateVisibleItems(reversed: reversed) { item in
                    seen.append(item.stableId.base as! Int)
                    if seen.count == 1 {
                        if mutation == 0 { table.removeAll() }
                        else if mutation == 1 {
                            table.remove(at: 4)
                            _ = table.insert(item: TGUIKit.TableRowItem(.zero, stableId: 100), at: 4)
                        } else { table.remove(at: 9) }
                    }
                    return true
                }
                let expected = mutation == 0 ? (reversed ? [5] : [2]) : mutation == 1 ? (reversed ? [5, 100, 3, 2] : [2, 3, 100, 5]) : (reversed ? [5, 4, 3, 2] : [2, 3, 4, 5])
                XCTAssertEqual(seen, expected)
            }
        }
    }

    func testShrinkingTailAndRegrowingWithinVisibleRange() {
        for regrow in [false, true] {
            let table = TGUIKit.TableView(frame: NSRect(x: 0, y: 0, width: 320, height: 240))
            let spy = RangeTable(frame: table.bounds)
            table.tableView = spy
            table.updateAfterInitialize()
            for id in 0..<4 { _ = table.addItem(item: TGUIKit.TableRowItem(.zero, stableId: id)) }
            spy.forcedRange = NSRange(location: 0, length: 4)
            var seen: [Int] = []
            table.enumerateVisibleItems { item in
                seen.append(item.stableId.base as! Int)
                if seen.count == 1 { table.remove(at: 3) }
                if seen.count == 2 && regrow { _ = table.addItem(item: TGUIKit.TableRowItem(.zero, stableId: 100)) }
                return true
            }
            XCTAssertEqual(seen, regrow ? [0, 1, 2, 100] : [0, 1, 2])
        }
    }

    func testOptionalLookupTracksReplacementRemovalAndInvalidIndexes() {
        let table = TGUIKit.TableView(frame: .zero)
        XCTAssertNil(table.optionalItem(at: 0))
        let first = TGUIKit.TableRowItem(.zero, stableId: 1)
        let second = TGUIKit.TableRowItem(.zero, stableId: 2)
        _ = table.addItem(item: first)
        XCTAssertTrue(table.optionalItem(at: 0) === first)
        for index in [Int.min, -1, 1, Int.max] { XCTAssertNil(table.optionalItem(at: index)) }
        table.remove(at: 0)
        _ = table.addItem(item: second)
        XCTAssertTrue(table.optionalItem(at: 0) === second)
        table.removeAll()
        XCTAssertNil(table.optionalItem(at: 0))
    }

    func testOutsideViewportMutationDoesNotCopyTheWholeList() {
        for count in [100, 10000] {
            let table = TGUIKit.TableView(frame: .zero)
            let spy = RangeTable(frame: .zero)
            table.tableView = spy
            table.updateAfterInitialize()
            for id in 0..<count { _ = table.addItem(item: TGUIKit.TableRowItem(.zero, stableId: id)) }
            let tail = table.lastItem!
            spy.forcedRange = NSRange(location: 2, length: 4)
            let storage = table.enumerationLabStorage
            var visited = 0
            table.enumerateVisibleItems { _ in
                if visited == 0 {
                    table.remove(at: count - 1, redraw: false)
                    _ = table.addItem(item: tail, redraw: false)
                    XCTAssertEqual(table.enumerationLabStorage, storage)
                }
                visited += 1
                return true
            }
            XCTAssertEqual(visited, 4)
        }
    }

    func testEmptyAndStaleRangesAreBounded() {
        let table = TGUIKit.TableView(frame: NSRect(x: 0, y: 0, width: 320, height: 240))
        let spy = RangeTable(frame: table.bounds)
        table.tableView = spy
        table.updateAfterInitialize()
        for id in 0..<4 { _ = table.addItem(item: TGUIKit.TableRowItem(.zero, stableId: id)) }
        let cases: [(NSRange, [Int])] = [(.init(location: NSNotFound, length: 0), []), (.init(location: NSNotFound, length: 1), []), (.init(location: 0, length: 0), []), (.init(location: -1, length: 3), []), (.init(location: 0, length: -1), []), (.init(location: 4, length: 2), []), (.init(location: 2, length: Int.max), [2, 3])]
        for (range, expected) in cases {
            for enumerate in [table.enumerateVisibleItems, table.enumerationLabCopied, table.enumerationLabTemporary, table.enumerationLabBulk] {
                for reversed in [false, true] {
                    spy.forcedRange = range
                    var seen: [Int] = []
                    enumerate(reversed, 0) { seen.append($0.stableId.base as! Int); return true }
                    XCTAssertEqual(seen, reversed ? expected.reversed() : expected)
                }
            }
        }
    }
}
