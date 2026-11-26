import AppKit
import XCTest
import QuartzCore
import class TGUIKit.TableView
import class TGUIKitBaseline.TableView
import class TGUIKit.TableRowItem
import class TGUIKitBaseline.TableRowItem

final class EnumerationBenchmarkTests: XCTestCase {
    func testCosts() throws {
        guard ProcessInfo.processInfo.environment["ENUMERATION_BENCHMARK"] == "1" else { throw XCTSkip("Opt-in enumeration timing") }
        EnumerationBootstrap.install()
        let reverse = ProcessInfo.processInfo.environment["ENUMERATION_REVERSE"] == "1"
        let finalOnly = ProcessInfo.processInfo.environment["ENUMERATION_FINAL"] == "1"
        var results: [String: [[Double]]] = [:]
        var sink = 0
        func measure(_ name: String, count: Int = 200000, operations: [() -> Int]) {
            let operations = finalOnly ? Array(operations.prefix(2)) : operations
            for operation in operations { for _ in 0..<50 { sink += operation() } }
            CATransaction.flush()
            var batches = Array(repeating: [Double](), count: operations.count)
            for batch in 0..<9 {
                let order = (batch % 2 == 0) != reverse ? Array(operations.indices) : Array(operations.indices.reversed())
                for index in order {
                    autoreleasepool {
                        let start = CACurrentMediaTime()
                        for _ in 0..<count { sink += operations[index]() }
                        batches[index].append((CACurrentMediaTime() - start) * 1e6 / Double(count))
                    }
                }
            }
            results[name] = batches
        }
        for visibleCount in [1, 8, 24, 100] {
            let height = CGFloat(visibleCount * 60)
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: height), styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            let a = TGUIKitBaseline.TableView(frame: NSRect(x: 0, y: 0, width: 320, height: height))
            let b = TGUIKit.TableView(frame: NSRect(x: 320, y: 0, width: 320, height: height))
            window.contentView!.addSubview(a); window.contentView!.addSubview(b)
            a.beginTableUpdates(); b.beginTableUpdates()
            for id in 0..<1000 {
                _ = a.addItem(item: TGUIKitBaseline.TableRowItem(.zero, stableId: id))
                _ = b.addItem(item: TGUIKit.TableRowItem(.zero, stableId: id))
            }
            a.endTableUpdates(); b.endTableUpdates()
            window.contentView!.layoutSubtreeIfNeeded()
            XCTAssertEqual(a.visibleRows().length, visibleCount)
            XCTAssertEqual(b.visibleRows().length, visibleCount)
            for reversed in [false, true] {
                for early in [false, true] {
                    let name = "visible_\(visibleCount)_reversed_\(reversed)_early_\(early)"
                    let baselineEnumerate = a.enumerateVisibleItems
                    var operations: [() -> Int] = [{
                        var value = 0
                        baselineEnumerate(reversed, 0) { value += $0.index + 1; return !early }
                        return value
                    }]
                    for enumerate in [b.enumerateVisibleItems, b.enumerationLabCopied, b.enumerationLabTemporary, b.enumerationLabBulk, b.enumerationLabSlice] {
                        operations.append {
                            var value = 0
                            enumerate(reversed, 0) { value += $0.index + 1; return !early }
                            return value
                        }
                    }
                    measure(name, operations: operations)
                }
            }
            window.close()
        }
        for rows in [100, 10000] {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 600), styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            let a = TGUIKitBaseline.TableView(frame: NSRect(x: 0, y: 0, width: 320, height: 600))
            let b = TGUIKit.TableView(frame: NSRect(x: 320, y: 0, width: 320, height: 600))
            window.contentView!.addSubview(a); window.contentView!.addSubview(b)
            a.beginTableUpdates(); b.beginTableUpdates()
            for id in 0..<rows {
                _ = a.addItem(item: TGUIKitBaseline.TableRowItem(.zero, stableId: id))
                _ = b.addItem(item: TGUIKit.TableRowItem(.zero, stableId: id))
            }
            a.endTableUpdates(); b.endTableUpdates()
            window.contentView!.layoutSubtreeIfNeeded()
            let oldLast = a.lastItem!, newLast = b.lastItem!
            let baselineEnumerate = a.enumerateVisibleItems
            var operations: [() -> Int] = [{
                var count = 0
                baselineEnumerate(false, 0) { _ in
                    if count == 0 { a.remove(at: a.count - 1, redraw: false); _ = a.addItem(item: oldLast, redraw: false) }
                    count += 1
                    return true
                }
                return count
            }]
            for enumerate in [b.enumerateVisibleItems, b.enumerationLabCopied, b.enumerationLabTemporary, b.enumerationLabBulk, b.enumerationLabSlice] {
                operations.append {
                    var count = 0
                    enumerate(false, 0) { _ in
                        if count == 0 { b.remove(at: b.count - 1, redraw: false); _ = b.addItem(item: newLast, redraw: false) }
                        count += 1
                        return true
                    }
                    return count
                }
            }
            measure("mutation_outside_viewport_\(rows)", count: 20000, operations: operations)
            window.close()
        }
        let oldLookup = TGUIKitBaseline.TableView(frame: .zero), newLookup = TGUIKit.TableView(frame: .zero)
        for id in 0..<1000 {
            _ = oldLookup.addItem(item: TGUIKitBaseline.TableRowItem(.zero, stableId: id), redraw: false)
            _ = newLookup.addItem(item: TGUIKit.TableRowItem(.zero, stableId: id), redraw: false)
        }
        for index in [-1, 0, 500, 999, 1000, Int.max] {
            measure("lookup_\(index)", count: 1000000, operations: [
                { oldLookup.optionalItem(at: index)?.index ?? 0 },
                { newLookup.optionalItem(at: index)?.index ?? 0 }
            ])
        }
        XCTAssertGreaterThan(sink, 0)
        try JSONSerialization.data(withJSONObject: ["unit": "microseconds_per_operation", "order": finalOnly ? ["baseline", "bounded"] : ["baseline", "bounded", "copied", "temporary", "bulk", "slice"], "reverse": reverse, "batches": results], options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: "/tmp/visible-enumeration-benchmark.json"))
    }
}
