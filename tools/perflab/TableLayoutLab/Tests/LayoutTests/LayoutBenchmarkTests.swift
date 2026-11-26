import AppKit
import XCTest
import QuartzCore
import class TGUIKit.TableView
import class TGUIKitBaseline.TableView
import class TGUIKit.TableRowItem
import class TGUIKitBaseline.TableRowItem
import class TGUIKit.TableStickItem
import class TGUIKitBaseline.TableStickItem

private final class BenchmarkHeader: TGUIKit.TableStickItem {}
private final class BaselineBenchmarkHeader: TGUIKitBaseline.TableStickItem {}

final class LayoutBenchmarkTests: XCTestCase {
    func testLayoutCosts() throws {
        guard ProcessInfo.processInfo.environment["TABLE_LAYOUT_BENCHMARK"] == "1" else { throw XCTSkip("Opt-in table layout timing") }
        LayoutBootstrap.install()
        let reverse = ProcessInfo.processInfo.environment["TABLE_LAYOUT_REVERSE"] == "1"
        var results: [String: [[Double]]] = [:]
        var sink = 0
        func measure(_ name: String, count: Int = 1000, operations: [() -> Int]) {
            for op in operations { for _ in 0..<20 { autoreleasepool { sink += op() } } }
            CATransaction.flush()
            var batches = [[Double](), [Double]()]
            for batch in 0..<9 {
                for index in ((batch % 2 == 0) != reverse ? [0, 1] : [1, 0]) {
                    CATransaction.begin()
                    let start = CACurrentMediaTime()
                    for _ in 0..<count { autoreleasepool { sink += operations[index]() } }
                    batches[index].append((CACurrentMediaTime() - start) * 1e6 / Double(count))
                    CATransaction.commit()
                    CATransaction.flush()
                }
            }
            results[name] = batches
        }
        for rows in [0, 40, 1000, 10000] {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 840, height: 600), styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            let a = TGUIKitBaseline.TableView(frame: NSRect(x: 0, y: 0, width: 420, height: 600))
            let b = TGUIKit.TableView(frame: NSRect(x: 420, y: 0, width: 420, height: 600))
            window.contentView!.addSubview(a); window.contentView!.addSubview(b)
            a.beginTableUpdates(); b.beginTableUpdates()
            for id in 0..<rows {
                if id % 20 == 0 {
                    _ = a.addItem(item: BaselineBenchmarkHeader(.zero)); _ = b.addItem(item: BenchmarkHeader(.zero))
                } else {
                    _ = a.addItem(item: TGUIKitBaseline.TableRowItem(.zero, stableId: id)); _ = b.addItem(item: TGUIKit.TableRowItem(.zero, stableId: id))
                }
            }
            a.endTableUpdates(); b.endTableUpdates()
            window.contentView!.layoutSubtreeIfNeeded()
            measure("layout_\(rows)", operations: [
                { a.needsLayout = true; a.layoutSubtreeIfNeeded(); return a.count },
                { b.needsLayout = true; b.layoutSubtreeIfNeeded(); return b.count }
            ])
            a.set(stickClass: BaselineBenchmarkHeader.self, handler: { _ in }); b.set(stickClass: BenchmarkHeader.self, handler: { _ in })
            measure("layout_and_sticky_\(rows)", operations: [
                { a.needsLayout = true; a.layoutSubtreeIfNeeded(); a.updateStickAfterScroll(false); return a.count },
                { b.needsLayout = true; b.layoutSubtreeIfNeeded(); b.updateStickAfterScroll(false); return b.count }
            ])
            if rows == 40 || rows == 1000 {
                var oldWide = false, newWide = false
                measure("resize_width_\(rows)", count: 300, operations: [
                    { oldWide.toggle(); a.setFrameSize(NSSize(width: oldWide ? 420 : 400, height: 600)); a.layoutSubtreeIfNeeded(); a.updateStickAfterScroll(false); return a.count },
                    { newWide.toggle(); b.setFrameSize(NSSize(width: newWide ? 420 : 400, height: 600)); b.layoutSubtreeIfNeeded(); b.updateStickAfterScroll(false); return b.count }
                ])
            }
            window.close()
        }
        XCTAssertGreaterThan(sink, 0)
        try JSONSerialization.data(withJSONObject: ["unit": "microseconds_per_operation", "reverse": reverse, "batches_before_after": results], options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: "/tmp/table-layout-benchmark.json"))
    }
}
