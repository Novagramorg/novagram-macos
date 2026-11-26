import AppKit
import QuartzCore
import Darwin
import XCTest
import TGUIKit
import OriginalInkDust

final class InkDustBenchmarkTests: XCTestCase {
    func testConstructionAndUpdateCosts() throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["INK_DUST_BENCHMARK"] == "1" else { throw XCTSkip("Opt-in dust construction benchmark") }
        InkDustTests().setUp()
        let size = NSSize(width: 180, height: 24)
        let rects = [CGRect(origin: .zero, size: size)]
        let words = [rects[0].insetBy(dx: 2, dy: 2)]
        let original = OriginalInvisibleInkDustView(), current = InvisibleInkDustView()
        let reversed = environment["INK_DUST_REVERSE"] == "1"
        var sink = 0
        var batches: [String: [[Double]]] = [:]
        func measure(_ name: String, count: Int, operations: [() -> Void]) {
            for index in reversed ? [1, 0] : [0, 1] {
                autoreleasepool { for _ in 0..<20 { operations[index]() } }
            }
            var samples = [[Double](), [Double]()]
            for batch in 0..<9 {
                for index in (batch % 2 == 0) != reversed ? [0, 1] : [1, 0] {
                    let elapsed = autoreleasepool { () -> Double in
                        let start = CACurrentMediaTime()
                        for _ in 0..<count { operations[index]() }
                        return (CACurrentMediaTime() - start) * 1_000_000 / Double(count)
                    }
                    samples[index].append(elapsed)
                }
            }
            batches[name] = samples
        }
        measure("construct", count: 300, operations: [
            { let view = OriginalInvisibleInkDustView(); sink &+= view.subviews.count },
            { let view = InvisibleInkDustView(); sink &+= view.subviews.count }
        ])
        measure("construct_configure", count: 300, operations: [
            { let view = OriginalInvisibleInkDustView(); view.update(size: size, color: .blue, textColor: .white, rects: rects, wordRects: words); sink &+= view.subviews.count },
            { let view = InvisibleInkDustView(); view.update(size: size, color: .blue, textColor: .white, rects: rects, wordRects: words); sink &+= view.subviews.count }
        ])
        measure("same_update", count: 1000, operations: [
            { original.update(size: size, color: .blue, textColor: .white, rects: rects, wordRects: words); sink &+= original.subviews.count },
            { current.update(size: size, color: .blue, textColor: .white, rects: rects, wordRects: words); sink &+= current.subviews.count }
        ])
        XCTAssertGreaterThan(sink, 0)
        let payload: [String: Any] = ["batches": batches, "order": ["original", "current"], "reversed": reversed, "units": "microseconds_per_operation", "iterations": ["construct": 300, "construct_configure": 300, "same_update": 1000], "owned_views_including_self": [7, 2], "attached_view_tree": [2, 2], "attached": false, "rasterized": false]
        let output = environment["INK_DUST_OUTPUT"] ?? "/tmp/ink-dust-benchmark.json"
        try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: output))
    }

    func testRetainedAllocationFootprint() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let mode = environment["INK_DUST_MEMORY"], ["original", "current"].contains(mode) else { throw XCTSkip("Opt-in fresh-process dust allocation footprint") }
        InkDustTests().setUp()
        let count = 2000
        let size = NSSize(width: 180, height: 24)
        let rects = [CGRect(origin: .zero, size: size)]
        let words = [rects[0].insetBy(dx: 2, dy: 2)]
        autoreleasepool {
            for _ in 0..<30 {
                let a = OriginalInvisibleInkDustView(), b = InvisibleInkDustView()
                a.update(size: size, color: .blue, textColor: .white, rects: rects, wordRects: words)
                b.update(size: size, color: .blue, textColor: .white, rects: rects, wordRects: words)
            }
            CATransaction.flush()
        }
        func memory() -> [String: UInt64] {
            var info = task_vm_info_data_t()
            var size = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
            let status = withUnsafeMutablePointer(to: &info) { pointer in
                pointer.withMemoryRebound(to: integer_t.self, capacity: Int(size)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &size) }
            }
            XCTAssertEqual(status, KERN_SUCCESS)
            return ["footprint": info.phys_footprint, "resident": info.resident_size]
        }
        var views: [NSView] = []
        views.reserveCapacity(count)
        let before = memory()
        autoreleasepool {
            for _ in 0..<count {
                if mode == "original" {
                    let view = OriginalInvisibleInkDustView()
                    view.update(size: size, color: .blue, textColor: .white, rects: rects, wordRects: words)
                    views.append(view)
                } else {
                    let view = InvisibleInkDustView()
                    view.update(size: size, color: .blue, textColor: .white, rects: rects, wordRects: words)
                    views.append(view)
                }
            }
            CATransaction.flush()
        }
        let after = withExtendedLifetime(views) { memory() }
        let payload: [String: Any] = ["mode": mode, "count": count, "before": before, "after": after, "attached": false, "rasterized": false, "includes_allocator_and_framework_storage": true]
        let output = environment["INK_DUST_OUTPUT"] ?? "/tmp/ink-dust-memory-\(mode).json"
        try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: output))
    }
}
