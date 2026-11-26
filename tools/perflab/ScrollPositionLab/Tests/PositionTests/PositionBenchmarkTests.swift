import Cocoa
import XCTest
import QuartzCore
@testable import class TGUIKit.ScrollView
@testable import class TGUIKitBaseline.ScrollView
import class TGUIKit.TableView
import class TGUIKitBaseline.TableView
import class TGUIKit.TableRowItem
import class TGUIKitBaseline.TableRowItem

final class PositionBenchmarkTests: XCTestCase {
    func testCosts() throws {
        guard ProcessInfo.processInfo.environment["POSITION_BENCHMARK"] == "1" else { throw XCTSkip("Opt-in scroll benchmark") }
        PositionBootstrap.install()
        let reverse = ProcessInfo.processInfo.environment["POSITION_REVERSE"] == "1"
        var results: [String: [[Double]]] = [:]
        var sink: CGFloat = 0
        func measure(_ name: String, count: Int = 1000000, operations: [() -> CGFloat]) {
            for operation in operations { for _ in 0..<100 { sink += operation() } }
            CATransaction.flush()
            var batches = [[Double](), [Double]()]
            for batch in 0..<9 {
                for index in ((batch % 2 == 0) != reverse ? [0, 1] : [1, 0]) {
                    autoreleasepool {
                        CATransaction.begin()
                        let start = CACurrentMediaTime()
                        for _ in 0..<count { sink += operations[index]() }
                        batches[index].append((CACurrentMediaTime() - start) * 1e6 / Double(count))
                        CATransaction.commit()
                        CATransaction.flush()
                    }
                }
            }
            results[name] = batches
        }
        let frame = NSRect(x: 0, y: 0, width: 420, height: 600)
        let old = TGUIKitBaseline.ScrollView(frame: frame), new = TGUIKit.ScrollView(frame: frame)
        for scroll in [old as NSScrollView, new as NSScrollView] {
            scroll.documentView = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 60000))
        }
        measure("scroll_position", operations: [{ old.scrollPosition().current.rect.height }, { new.scrollPosition().current.rect.height }])
        measure("reset_scroll", operations: [{ old.resetScroll(); return 1 }, { new.resetScroll(); return 1 }])
        let a = TGUIKitBaseline.TableView(frame: frame), b = TGUIKit.TableView(frame: frame)
        for index in 0..<1000 {
            _ = a.addItem(item: TGUIKitBaseline.TableRowItem(.zero, stableId: index))
            _ = b.addItem(item: TGUIKit.TableRowItem(.zero, stableId: index))
        }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 840, height: 600), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        b.frame.origin.x = 420
        window.contentView!.addSubview(a); window.contentView!.addSubview(b)
        window.contentView!.layoutSubtreeIfNeeded()
        measure("attached_table_unobserved", operations: [{ a.scrollDidChangedBounds(); return 1 }, { b.scrollDidChangedBounds(); return 1 }])
        var oldObserved: CGFloat = 0, newObserved: CGFloat = 0
        a.scrollDidUpdate = { oldObserved = $0.rect.height }; b.scrollDidUpdate = { newObserved = $0.rect.height }
        measure("attached_table_observed", operations: [{ a.scrollDidChangedBounds(); return oldObserved }, { b.scrollDidChangedBounds(); return newObserved }])
        a.updateScrollPoint = { NSPoint(x: $0.x, y: $0.y + 10) }; b.updateScrollPoint = { NSPoint(x: $0.x, y: $0.y + 10) }
        measure("attached_table_transformed_observed", operations: [{ a.scrollDidChangedBounds(); return oldObserved }, { b.scrollDidChangedBounds(); return newObserved }])
        a.updateScrollPoint = nil; b.updateScrollPoint = nil
        var oldOffset = 0, newOffset = 0
        for observed in [true, false] {
            if !observed { a.scrollDidUpdate = nil; b.scrollDidUpdate = nil }
            measure("attached_move_and_report_observed_\(observed)", count: 20000, operations: [
                { oldOffset = (oldOffset + 17) % 50000; a.contentView.scroll(to: NSPoint(x: 0, y: oldOffset)); a.scrollDidChangedBounds(); return a.scrollPosition().current.rect.minY },
                { newOffset = (newOffset + 17) % 50000; b.contentView.scroll(to: NSPoint(x: 0, y: newOffset)); b.scrollDidChangedBounds(); return b.scrollPosition().current.rect.minY }
            ])
        }
        XCTAssertGreaterThan(sink, 0)
        try JSONSerialization.data(withJSONObject: ["unit": "microseconds_per_operation", "reverse": reverse, "batches_before_after": results, "sink": sink], options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: "/tmp/scroll-position-benchmark.json"))
    }
}
