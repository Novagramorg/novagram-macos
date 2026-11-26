import Cocoa
import XCTest
import QuartzCore
import TGUIKit
@testable import ChatLayerEngine
@testable import FoldingViewHarness

final class LayerCaptionBenchmarkTests: XCTestCase {
    func testBindingCosts() throws {
        guard ProcessInfo.processInfo.environment["CHAT_CAPTION_LAYER_BENCHMARK"] == "1" else { throw XCTSkip("Opt-in caption binding benchmark") }
        TGUIKitTestBootstrap.install()
        let context = BlockContext(), fixtures = CaptionReuseTests()
        var results: [String: [[Double]]] = [:], counts: [String: [Int]] = [:], sink = 0
        for count in [1, 3, 10] {
            for rich in [false, true] {
                let items = (0..<2).map { _ in (0..<2).map { pass in ChatRowItem((0..<count).map { index in fixtures.caption(pass * 20 + index + 1, context: context, quoted: rich, offset: NSPoint(x: 8, y: index * 60)) }) } }
                let same = (0..<2).map { _ in (0..<2).map { _ in ChatRowItem((0..<count).map { index in fixtures.caption(index + 1, context: context, quoted: rich, offset: NSPoint(x: 8, y: index * 60)) }) } }
                let factories: [() -> CaptionRowEnvironment] = [{ ReusedCaptionRow(frame: .zero) }, { LayerCaptionRow(frame: .zero) }]
                let rows = factories.map { $0() }
                for mode in 0..<2 { rows[mode].bind(items[mode][0]) }
                counts["captions_\(count)_rich_\(rich)"] = rows.map(viewTreeCount)
                for operation in ["construct", "same", "recycle"] {
                    var samples = [[Double](), [Double]()], indices = [0, 0]
                    let iterations = count == 10 ? 60 : 200
                    for batch in 0..<9 {
                        for mode in (batch % 2 == 0 ? [0, 1] : [1, 0]) {
                            let elapsed = autoreleasepool { () -> Double in
                                let start = CACurrentMediaTime()
                                for _ in 0..<iterations {
                                    indices[mode] = 1 - indices[mode]
                                    let item = operation == "same" ? same[mode][indices[mode]] : items[mode][indices[mode]]
                                    let row = operation == "construct" ? factories[mode]() : rows[mode]
                                    row.bind(item)
                                    sink += row.rowView.subviews.count
                                }
                                return (CACurrentMediaTime() - start) * 1_000_000 / Double(iterations)
                            }
                            samples[mode].append(elapsed)
                        }
                    }
                    results["\(operation)_captions_\(count)_rich_\(rich)"] = samples
                }
            }
        }
        XCTAssertGreaterThan(sink, 0)
        try JSONSerialization.data(withJSONObject: ["unit": "microseconds", "modes": ["native_reuse_df4acbdc0", "layer_caption"], "batches": results, "view_counts": counts, "sink": sink], options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: "/tmp/chat-layer-caption-benchmark.json"))
    }

    func testRetainedMemory() throws {
        guard let mode = ProcessInfo.processInfo.environment["CHAT_CAPTION_LAYER_MEMORY"], ["native", "layers"].contains(mode) else { throw XCTSkip("Opt-in fresh-process caption memory probe") }
        TGUIKitTestBootstrap.install()
        let context = BlockContext(), fixtures = CaptionReuseTests(), count = 3000
        let items = autoreleasepool { (0..<count).map { ChatRowItem([fixtures.caption($0, context: context)]) } }
        autoreleasepool {
            for item in items.prefix(30) {
                let native = ReusedCaptionRow(frame: .zero), layers = LayerCaptionRow(frame: .zero)
                native.bind(item); layers.bind(item)
            }
            CATransaction.flush()
        }
        func memory() -> UInt64 {
            var info = task_vm_info_data_t()
            var size = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
            let status = withUnsafeMutablePointer(to: &info) { $0.withMemoryRebound(to: integer_t.self, capacity: Int(size)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &size) } }
            XCTAssertEqual(status, KERN_SUCCESS)
            return info.phys_footprint
        }
        let before = memory()
        let rows: [CaptionRowEnvironment] = autoreleasepool {
            items.map { item in
                let row: CaptionRowEnvironment = mode == "native" ? ReusedCaptionRow(frame: .zero) : LayerCaptionRow(frame: .zero)
                row.bind(item)
                if let row = row as? LayerCaptionRow { _ = row.captionViews[0].layerView?.hitNode(at: NSPoint(x: 5, y: 5)) }
                return row
            }
        }
        let after = withExtendedLifetime(rows) { autoreleasepool { CATransaction.flush() }; return memory() }
        try JSONSerialization.data(withJSONObject: ["mode": mode, "count": count, "before": before, "after": after, "unique_premeasured_layouts": true, "attached_to_window": false], options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: "/tmp/chat-layer-caption-memory-\(mode).json"))
    }
}
