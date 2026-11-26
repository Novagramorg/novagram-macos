import Cocoa
import XCTest
import TGUIKit
@testable import ChatLayerEngine

final class BenchmarkTests: XCTestCase {
    func testRetainedRowFootprint() throws {
        guard let mode = ProcessInfo.processInfo.environment["CHAT_LAYER_MEMORY_MODE"], ["native", "layers"].contains(mode) else { throw XCTSkip("Opt-in fresh-process memory measurement") }
        TGUIKitTestBootstrap.install()
        System.updateScaleFactor(2)
        let count = 1500
        let fixtures = autoreleasepool { (0..<count).map { PlainRowFixture(width: 400 + CGFloat($0 % 4) * 20, variant: $0 % 4) } }
        autoreleasepool {
            for fixture in fixtures.prefix(20) {
                _ = NativePlainRow(fixture)
                _ = LayerPlainRow(fixture)
            }
            CATransaction.flush()
        }
        func memory() throws -> [String: UInt64] {
            var info = task_vm_info_data_t()
            var size = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
            let result = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: integer_t.self, capacity: Int(size)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &size) }
            }
            XCTAssertEqual(result, KERN_SUCCESS)
            return ["footprint_bytes": info.phys_footprint, "resident_bytes": info.resident_size]
        }
        let before = try memory()
        let rows: [AnyObject] = autoreleasepool {
            fixtures.map { fixture in
                if mode == "native" { return NativePlainRow(fixture) }
                let row = LayerPlainRow(fixture)
                _ = row.view.hitNode(at: NSPoint(x: 80, y: 80))
                return row
            }
        }
        let after = try withExtendedLifetime(rows) {
            autoreleasepool { CATransaction.flush() }
            return try memory()
        }
        let payload: [String: Any] = ["mode": mode, "count": count, "before": before, "after": after, "unique_premeasured_layouts": true, "attached_to_window": false]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: URL(fileURLWithPath: ProcessInfo.processInfo.environment["CHAT_LAYER_MEMORY_RESULT"] ?? "/tmp/chat-layer-engine-memory-\(mode).json"))
        print(String(data: data, encoding: .utf8)!)
    }

    func testRowBenchmarks() throws {
        guard ProcessInfo.processInfo.environment["CHAT_LAYER_BENCHMARK"] == "1" else { throw XCTSkip("Opt-in release benchmark") }
        TGUIKitTestBootstrap.install()
        System.updateScaleFactor(2)
        let fixtures = (0..<4).map { PlainRowFixture(width: 400 + CGFloat($0) * 20, variant: $0) }
        let native = NativePlainRow(fixtures[0]), candidate = LayerPlainRow(fixtures[0])
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 600), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.contentView = nil; window.close() }
        let root = View(frame: window.contentView!.bounds)
        window.contentView = root
        root.addSubview(native.view); root.addSubview(candidate.view)
        candidate.view.setFrameOrigin(NSPoint(x: 500, y: 0))
        var results: [String: [[Double]]] = [:]
        var sink = 0
        func record(_ name: String, count: Int, before: (Int) -> Void, after: (Int) -> Void) {
            var batches = [[Double](), [Double]()]
            for i in 0..<100 { before(i); after(i) }
            for batch in 0..<9 {
                for variant in batch % 2 == 0 ? [0, 1] : [1, 0] {
                    let start = CACurrentMediaTime()
                    autoreleasepool {
                        for i in 0..<count {
                            if variant == 0 { before(i) } else { after(i) }
                        }
                    }
                    batches[variant].append((CACurrentMediaTime() - start) * 1_000_000 / Double(count))
                }
            }
            results[name] = batches
        }
        record("cold_row", count: 300, before: { i in
            autoreleasepool { sink += NativePlainRow(fixtures[i % 4]).view.subviews.count }
        }, after: { i in
            autoreleasepool { sink += LayerPlainRow(fixtures[i % 4]).view.root.children.count }
        })
        record("attached_rebind", count: 1500, before: { i in
            native.bind(fixtures[i % 4]); sink += native.views.count
        }, after: { i in
            candidate.bind(fixtures[i % 4]); sink += candidate.nodes.count
        })
        record("hit_test", count: 20000, before: { i in
            let point = NSPoint(x: CGFloat(i % 400), y: CGFloat(i % 230))
            if native.view.hitTest(point) != nil { sink += 1 }
        }, after: { i in
            let point = NSPoint(x: CGFloat(i % 400), y: CGFloat(i % 230))
            if candidate.view.hitNode(at: point) != nil { sink += 1 }
        })
        XCTAssertGreaterThan(sink, 0)
        let payload: [String: Any] = ["unit": "microseconds_per_operation", "batches": results, "native_view_count": viewTreeCount(native.view), "layer_view_count": viewTreeCount(candidate.view), "sink": sink]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
        let url = URL(fileURLWithPath: ProcessInfo.processInfo.environment["CHAT_LAYER_BENCHMARK_RESULT"] ?? "/tmp/chat-layer-engine-benchmark.json")
        try data.write(to: url)
        print(String(data: data, encoding: .utf8)!)
    }
}
