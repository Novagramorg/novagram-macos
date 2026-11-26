import Cocoa
import XCTest
import QuartzCore
import ObjectiveC
import TGUIKit
@testable import ChatLayerEngine
@testable import ChatLayerEngineBaseline
@testable import FoldingViewHarness
@testable import FoldingViewHarnessBaseline

final class LiveFoldingBenchmarkTests: XCTestCase {
    let currentContext = FoldingViewHarness.BlockContext()
    let originalContext = FoldingViewHarnessBaseline.BlockContext()

    func items(_ id: Int, count: Int, kind: String) -> (FoldingViewHarness.ChatMessageItem, FoldingViewHarnessBaseline.ChatMessageItem) {
        let value = "Message \(id)\nSecond quoted line\nThird quoted line\nFourth quoted line\nLast quoted line"
        let current = ChatTextReuseTests().item(id, count: count, quoted: kind != "plain", context: currentContext, text: value, collapsable: kind == "folded" || kind == "expanded")
        if kind == "expanded" { current.textLayout.revealed = Set(0..<count); current.textLayout.measure(width: 240) }
        let blocks = current.textLayout.blocks.map { block -> TextViewLayout in
            let text = TextViewLayout(block.text.attributedString, disableTooltips: true)
            text.interactions.resolveLink = { $0 as? String }
            return text
        }
        let layout = FoldingViewHarnessBaseline.FoldingTextLayout(attributedString: current.textLayout.attributedString, blocks: blocks, blockRanges: current.textLayout.blockRanges, context: originalContext, revealed: current.textLayout.revealed)
        layout.measure(width: 240)
        return (current, FoldingViewHarnessBaseline.ChatMessageItem(id: id, layout: layout))
    }

    func testCompleteBindingAndConstructionCosts() throws {
        guard ProcessInfo.processInfo.environment["CHAT_FOLD_BENCHMARK"] == "1" else { throw XCTSkip("Opt-in folded quote binding benchmark") }
        TGUIKitTestBootstrap.install()
        var batches: [String: [[Double]]] = [:], counts: [String: [Int]] = [:]
        var sink = 0
        let reversed = ProcessInfo.processInfo.environment["CHAT_FOLD_REVERSE"] == "1"
        func measure(_ name: String, count: Int, operations: [() -> Void]) {
            for action in operations { autoreleasepool { for _ in 0..<20 { action() } } }
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
        for kind in ["plain", "static", "folded", "expanded"] {
            for count in [1, 3, 12] {
                let first = items(1, count: count, kind: kind), next = items(2, count: count, kind: kind)
                let original = FoldingViewHarnessBaseline.LayerChatTextRow(frame: .zero)
                let current = FoldingViewHarness.LayerChatTextRow(frame: .zero)
                original.bind(first.1); current.bind(first.0)
                XCTAssertEqual(first.0.textLayout.size, first.1.textLayout.size)
                XCTAssertNotNil(current.layerText)
                if kind == "folded" || kind == "expanded" { XCTAssertNotNil(original.text) }
                else { XCTAssertNotNil(original.layerText) }
                counts["\(kind)_\(count)"] = [viewTreeCount(original), viewTreeCount(current)]
                measure("construct_\(kind)_\(count)", count: 150, operations: [
                    { let row = FoldingViewHarnessBaseline.LayerChatTextRow(frame: .zero); row.bind(first.1); sink &+= row.subviews.count },
                    { let row = FoldingViewHarness.LayerChatTextRow(frame: .zero); row.bind(first.0); sink &+= row.subviews.count }
                ])
                measure("same_\(kind)_\(count)", count: 400, operations: [
                    { original.bind(first.1); sink &+= original.subviews.count },
                    { current.bind(first.0); sink &+= current.subviews.count }
                ])
                var oldIndex = 0, newIndex = 0
                measure("recycle_\(kind)_\(count)", count: 400, operations: [
                    { oldIndex &+= 1; original.bind(oldIndex % 2 == 0 ? first.1 : next.1); sink &+= original.subviews.count },
                    { newIndex &+= 1; current.bind(newIndex % 2 == 0 ? first.0 : next.0); sink &+= current.subviews.count }
                ])
                if kind == "folded" || kind == "plain" {
                    let originalCaption = FoldingViewHarnessBaseline.LayerCaptionRow(frame: .zero)
                    let currentCaption = FoldingViewHarness.LayerCaptionRow(frame: .zero)
                    let oldItem = FoldingViewHarnessBaseline.ChatRowItem([.init(messageId: 1, id: 1, layout: first.1.textLayout)])
                    let newItem = FoldingViewHarness.ChatRowItem([.init(messageId: 1, id: 1, layout: first.0.textLayout)])
                    originalCaption.bind(oldItem); currentCaption.bind(newItem)
                    measure("caption_construct_\(kind)_\(count)", count: 150, operations: [
                        { let row = FoldingViewHarnessBaseline.LayerCaptionRow(frame: .zero); row.bind(oldItem); sink &+= row.subviews.count },
                        { let row = FoldingViewHarness.LayerCaptionRow(frame: .zero); row.bind(newItem); sink &+= row.subviews.count }
                    ])
                    measure("caption_same_\(kind)_\(count)", count: 400, operations: [
                        { originalCaption.bind(oldItem); sink &+= originalCaption.subviews.count },
                        { currentCaption.bind(newItem); sink &+= currentCaption.subviews.count }
                    ])
                }
            }
        }
        XCTAssertGreaterThan(sink, 0)
        let payload: [String: Any] = ["batches": batches, "view_counts": counts, "reversed": reversed, "node_runtime_bytes": [class_getInstanceSize(ChatLayerEngineBaseline.ChatLayerMessageTextNode.self), class_getInstanceSize(ChatLayerEngine.ChatLayerMessageTextNode.self)], "premeasured": true, "attached": false]
        try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: "/tmp/chat-fold-binding-benchmark.json"))
    }

    func testRetainedFoldedRowMemory() throws {
        guard let mode = ProcessInfo.processInfo.environment["CHAT_FOLD_MEMORY"], ["original", "layers"].contains(mode) else { throw XCTSkip("Opt-in fresh-process folded row memory probe") }
        TGUIKitTestBootstrap.install()
        let count = 2000
        let samples = autoreleasepool { (0..<count).map { items($0, count: 3, kind: "folded") } }
        autoreleasepool {
            for sample in samples.prefix(30) {
                let old = FoldingViewHarnessBaseline.LayerChatTextRow(frame: .zero), new = FoldingViewHarness.LayerChatTextRow(frame: .zero)
                old.bind(sample.1); new.bind(sample.0)
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
        var rows: [NSView] = []
        rows.reserveCapacity(count)
        let before = memory()
        autoreleasepool {
            for sample in samples {
                if mode == "original" {
                    let row = FoldingViewHarnessBaseline.LayerChatTextRow(frame: .zero); row.bind(sample.1); rows.append(row)
                } else {
                    let row = FoldingViewHarness.LayerChatTextRow(frame: .zero); row.bind(sample.0); rows.append(row)
                }
            }
            CATransaction.flush()
        }
        let after = withExtendedLifetime(rows) { memory() }
        let payload: [String: Any] = ["mode": mode, "count": count, "before": before, "after": after, "premeasured": true, "attached": false]
        try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: "/tmp/chat-fold-memory-\(mode).json"))
    }
}
