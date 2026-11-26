import Cocoa
import XCTest
import QuartzCore
import Darwin
import TGUIKit
@testable import ChatLayerEngine

final class RowHeaderBenchmarkTests: XCTestCase {
    func testHeaderBindingCosts() throws {
        guard ProcessInfo.processInfo.environment["CHAT_HEADER_BENCHMARK"] == "1" else { throw XCTSkip("Opt-in shared row header benchmark") }
        TGUIKitTestBootstrap.install()
        let factory = RowHeaderTests(), frame = NSRect(x: 0, y: 0, width: 300, height: 100)
        var results: [String: [[Double]]] = [:], sink = 0
        for present in [false, true] {
            let items = (0..<2).map { index in HeaderBindingItem(present ? factory.layout("Forwarded message \(index)") : nil, frame: NSRect(x: 14, y: 10, width: 150, height: 20)) }
            let native = NativeHeaderBindingRow(frame: frame), current = LayerHeaderBindingRow(frame: frame)
            native.fillForwardHeader(items[0], animated: false)
            current.fillForwardHeader(items[0], animated: false)
            for operation in ["construct", "update", "toggle"] {
                let absent = HeaderBindingItem(nil, frame: .zero)
                var indices = [0, 0]
                let operations: [() -> Void] = (0..<2).map { mode in
                    return {
                        indices[mode] = 1 - indices[mode]
                        let item = operation == "toggle" && indices[mode] == 0 ? absent : items[indices[mode]]
                        if mode == 0 {
                            let row = operation == "construct" ? NativeHeaderBindingRow(frame: frame) : native
                            row.fillForwardHeader(item, animated: false)
                            sink += row.rowView.subviews.count
                        } else {
                            let row = operation == "construct" ? LayerHeaderBindingRow(frame: frame) : current
                            row.fillForwardHeader(item, animated: false)
                            sink += row.rowView.subviews.count
                        }
                    }
                }
                for operation in operations { for _ in 0..<30 { autoreleasepool { operation() } } }
                var samples = [[Double](), [Double]()]
                for batch in 0..<9 {
                    let reverse = ProcessInfo.processInfo.environment["CHAT_HEADER_REVERSE"] == "1"
                    for mode in (batch % 2 == 0) != reverse ? [0, 1] : [1, 0] {
                        let begin = CACurrentMediaTime()
                        for _ in 0..<1000 { autoreleasepool { operations[mode]() } }
                        samples[mode].append((CACurrentMediaTime() - begin) * 1000)
                    }
                }
                results["\(operation)_header_\(present)"] = samples
            }
        }
        let payload: [String: Any] = ["unit": "microseconds_per_binding", "modes": ["native", "layer_header"], "batches": results, "sink": sink, "native_host_instance_bytes": class_getInstanceSize(View.self), "deferred_host_instance_bytes": class_getInstanceSize(ChatLayerRowView.self)]
        try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: "/tmp/chat-header-benchmark.json"))
    }

    func testRetainedHeaderMemory() throws {
        guard let mode = ProcessInfo.processInfo.environment["CHAT_HEADER_MEMORY"], ["native", "layers"].contains(mode) else { throw XCTSkip("Opt-in fresh-process header memory probe") }
        TGUIKitTestBootstrap.install()
        let present = ProcessInfo.processInfo.environment["CHAT_HEADER_PRESENT"] == "1", count = 5000
        let factory = RowHeaderTests(), frame = NSRect(x: 0, y: 0, width: 300, height: 100)
        let items = autoreleasepool { (0..<count).map { HeaderBindingItem(present ? factory.layout("Forwarded message \($0)") : nil, frame: NSRect(x: 14, y: 10, width: 150, height: 20)) } }
        autoreleasepool {
            for item in items.prefix(30) {
                NativeHeaderBindingRow(frame: frame).fillForwardHeader(item, animated: false)
                LayerHeaderBindingRow(frame: frame).fillForwardHeader(item, animated: false)
            }
            CATransaction.flush()
        }
        func memory() -> UInt64 {
            var info = task_vm_info_data_t(), size = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
            let result = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: integer_t.self, capacity: Int(size)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &size) }
            }
            XCTAssertEqual(result, KERN_SUCCESS)
            return info.phys_footprint
        }
        let before = memory()
        let rows: [View] = autoreleasepool {
            items.map { item in
                if mode == "native" {
                    let row = NativeHeaderBindingRow(frame: frame)
                    row.fillForwardHeader(item, animated: false)
                    return row
                } else {
                    let row = LayerHeaderBindingRow(frame: frame)
                    row.fillForwardHeader(item, animated: false)
                    return row
                }
            }
        }
        let after = withExtendedLifetime(rows) { autoreleasepool { CATransaction.flush() }; return memory() }
        let payload: [String: Any] = ["count": count, "mode": mode, "header": present, "before_bytes": before, "after_bytes": after, "unique_premeasured_layouts": true, "attached_to_window": false]
        try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: "/tmp/chat-header-memory-\(mode).json"))
    }
}
