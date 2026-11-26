import Cocoa
import XCTest
import QuartzCore
import TGUIKit
@testable import ChatLayerEngine
@testable import FoldingViewHarness

final class LiveChatTextBenchmarkTests: XCTestCase {
    func testRetainedLiveTextMemory() throws {
        guard let mode = ProcessInfo.processInfo.environment["CHAT_LIVE_TEXT_MEMORY"], ["native", "layers"].contains(mode) else { throw XCTSkip("Opt-in fresh-process live text memory probe") }
        TGUIKitTestBootstrap.install()
        let context = BlockContext(), factory = ChatTextReuseTests(), count = 3000
        let linked = ProcessInfo.processInfo.environment["CHAT_LIVE_TEXT_LINKED"] == "1"
        let quoted = ProcessInfo.processInfo.environment["CHAT_LIVE_TEXT_QUOTED"] == "1"
        let blocks = Int(ProcessInfo.processInfo.environment["CHAT_LIVE_TEXT_BLOCKS"] ?? "1") ?? 1
        let items = autoreleasepool { (0..<count).map { factory.item($0, count: blocks, quoted: quoted, context: context, linked: linked) } }
        autoreleasepool {
            for item in items.prefix(30) {
                let native = PreviousNativeChatTextRow(frame: .zero), current = LayerChatTextRow(frame: .zero)
                native.bind(item); current.bind(item)
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
        let rows: [ChatTextRow] = autoreleasepool {
            items.map { item in
                let row: ChatTextRow = mode == "native" ? PreviousNativeChatTextRow(frame: .zero) : LayerChatTextRow(frame: .zero)
                row.bind(item)
                _ = row.layerText?.hitNode(at: NSPoint(x: 5, y: 5))
                return row
            }
        }
        let after = try withExtendedLifetime(rows) {
            autoreleasepool { CATransaction.flush() }
            return try memory()
        }
        let payload: [String: Any] = ["mode": mode, "count": count, "before": before, "after": after, "unique_premeasured_layouts": true, "attached_to_window": false, "linked": linked, "quoted": quoted, "blocks": blocks]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: URL(fileURLWithPath: "/tmp/chat-live-text-memory-\(mode).json"))
    }

    func testLiveTextBindingCosts() throws {
        guard ProcessInfo.processInfo.environment["CHAT_LIVE_TEXT_BENCHMARK"] == "1" else { throw XCTSkip("Opt-in live text binding benchmark") }
        TGUIKitTestBootstrap.install()
        let fixtures = ChatTextReuseTests()
        let attached = ProcessInfo.processInfo.environment["CHAT_LIVE_TEXT_ATTACHED"] == "1"
        let windows: [Window] = attached ? (0..<2).map { _ in
            let window = Window(contentRect: NSRect(x: 0, y: 0, width: 260, height: 600), styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            return window
        } : []
        defer { windows.forEach { $0.contentView = nil; $0.close() } }
        let context = BlockContext()
        var results: [String: [[Double]]] = [:]
        var viewCounts: [String: [Int]] = [:]
        var sink = 0
        func measure(_ name: String, count: Int, operations: [() -> Void]) {
            for operation in operations { for _ in 0..<20 { operation() } }
            var batches = [[Double](), [Double]()]
            for batch in 0..<9 {
                let reverse = ProcessInfo.processInfo.environment["CHAT_LIVE_TEXT_REVERSE"] == "1"
                for mode in (batch % 2 == 0) != reverse ? [0, 1] : [1, 0] {
                    let operation = operations[mode]
                    let start = CACurrentMediaTime()
                    for _ in 0..<count { autoreleasepool { operation() } }
                    batches[mode].append((CACurrentMediaTime() - start) * 1e6 / Double(count))
                }
            }
            results[name] = batches
        }
        for blocks in [1, 3, 12] {
            for variant in 0..<3 {
                let quoted = variant == 1, linked = variant == 2
                let items = (0..<2).map { _ in (0..<2).map { fixtures.item($0, count: blocks, quoted: quoted, context: context, linked: linked) } }
                let same = (0..<2).map { _ in (0..<2).map { _ in fixtures.item(0, count: blocks, quoted: quoted, context: context, linked: linked) } }
                let frame = NSRect(x: 0, y: 0, width: 260, height: 600)
                let factories: [() -> ChatTextRow] = [{ PreviousNativeChatTextRow(frame: frame) }, { LayerChatTextRow(frame: frame) }]
                let rows = factories.map { $0() }
                for mode in 0..<2 { rows[mode].bind(items[mode][0]) }
                viewCounts["blocks_\(blocks)_quoted_\(quoted)_linked_\(linked)"] = rows.map(viewTreeCount)
                for operation in ["construct", "same_message", "reuse"] {
                    if attached { for mode in 0..<2 { windows[mode].contentView = rows[mode] } }
                    var indices = [0, 0]
                    let operations = (0..<2).map { mode -> () -> Void in
                        let factory = factories[mode]
                        return {
                            indices[mode] = 1 - indices[mode]
                            let item = operation == "same_message" ? same[mode][indices[mode]] : items[mode][indices[mode]]
                            if operation == "construct" {
                                let row = factory()
                                if attached { windows[mode].contentView = row }
                                row.bind(item)
                                if attached { row.layoutSubtreeIfNeeded() }
                                sink += row.subviews.count
                            } else {
                                rows[mode].bind(item)
                                if attached { rows[mode].layoutSubtreeIfNeeded() }
                                sink += rows[mode].subviews.count
                            }
                        }
                    }
                    measure("\(operation)_blocks_\(blocks)_quoted_\(quoted)_linked_\(linked)", count: blocks == 12 ? 100 : 500, operations: operations)
                }
            }
        }
        XCTAssertGreaterThan(sink, 0)
        try JSONSerialization.data(withJSONObject: ["unit": "microseconds_per_binding", "modes": ["native_reuse", "live_layers_with_native_fallback"], "batches": results, "view_counts_including_row": viewCounts, "sink": sink, "attached_to_window": attached, "completed_layout": attached], options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: "/tmp/chat-live-text-benchmark.json"))
    }
}
