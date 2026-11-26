import Cocoa
import XCTest
import QuartzCore
import Darwin
import TGUIKit
@testable import ChatLayerEngine

final class ForwardNameBenchmarkTests: XCTestCase {
    func testForwardBindingCosts() throws {
        guard ProcessInfo.processInfo.environment["CHAT_FORWARD_BENCHMARK"] == "1" else { throw XCTSkip("Opt-in forwarded name benchmark") }
        TGUIKitTestBootstrap.install()
        let factory = ForwardNameTests(), frame = NSRect(x: 0, y: 0, width: 300, height: 120)
        let photo = ProcessInfo.processInfo.environment["CHAT_FORWARD_PHOTO"] == "1"
        var results: [String: [[Double]]] = [:], sink = 0
        for present in [false, true] {
            let items = (0..<2).map { index in ForwardBindingItem(present ? factory.layout("Sender \(index)", link: "peer-\(index)") : nil, photo: photo) }
            let native = NativeForwardBindingRow(frame: frame), current = LayerForwardBindingRow(frame: frame)
            native.bind(items[0], animated: false)
            current.bind(items[0], animated: false)
            for operation in ["construct", "update", "toggle"] {
                let absent = ForwardBindingItem(nil)
                var indices = [0, 0]
                let operations: [() -> Void] = (0..<2).map { mode in
                    return {
                        indices[mode] = 1 - indices[mode]
                        let item = operation == "toggle" && indices[mode] == 0 ? absent : items[indices[mode]]
                        if mode == 0 {
                            let row = operation == "construct" ? NativeForwardBindingRow(frame: frame) : native
                            row.bind(item, animated: false)
                            sink += row.rowView.subviews.count
                        } else {
                            let row = operation == "construct" ? LayerForwardBindingRow(frame: frame) : current
                            row.bind(item, animated: false)
                            sink += row.rowView.subviews.count
                        }
                    }
                }
                for operation in operations { for _ in 0..<30 { autoreleasepool { operation() } } }
                var samples = [[Double](), [Double]()]
                for batch in 0..<9 {
                    let reverse = ProcessInfo.processInfo.environment["CHAT_FORWARD_REVERSE"] == "1"
                    for mode in (batch % 2 == 0) != reverse ? [0, 1] : [1, 0] {
                        let begin = CACurrentMediaTime()
                        for _ in 0..<1000 { autoreleasepool { operations[mode]() } }
                        samples[mode].append((CACurrentMediaTime() - begin) * 1000)
                    }
                }
                results["\(operation)_name_\(present)"] = samples
            }
        }
        let payload: [String: Any] = ["unit": "microseconds_per_binding", "modes": ["native", "layer_forward"], "batches": results, "sink": sink, "avatar": photo, "native_row_instance_bytes": class_getInstanceSize(NativeForwardBindingRow.self), "layer_row_instance_bytes": class_getInstanceSize(LayerForwardBindingRow.self), "native_host_instance_bytes": class_getInstanceSize(BeforeForwardNameRowView.self), "deferred_host_instance_bytes": class_getInstanceSize(ChatLayerRowView.self)]
        try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: "/tmp/chat-forward-benchmark.json"))
    }

    func testRetainedSenderMemory() throws {
        guard let mode = ProcessInfo.processInfo.environment["CHAT_FORWARD_MEMORY"], ["native", "layers"].contains(mode) else { throw XCTSkip("Opt-in fresh-process forwarded name memory probe") }
        TGUIKitTestBootstrap.install()
        let present = ProcessInfo.processInfo.environment["CHAT_FORWARD_PRESENT"] == "1", count = 5000
        let factory = ForwardNameTests(), frame = NSRect(x: 0, y: 0, width: 300, height: 120)
        let photo = ProcessInfo.processInfo.environment["CHAT_FORWARD_PHOTO"] == "1"
        let items = autoreleasepool { (0..<count).map { ForwardBindingItem(present ? factory.layout("Sender \($0)", link: "peer-\($0)") : nil, photo: photo) } }
        autoreleasepool {
            for item in items.prefix(30) {
                NativeForwardBindingRow(frame: frame).bind(item, animated: false)
                LayerForwardBindingRow(frame: frame).bind(item, animated: false)
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
                    let row = NativeForwardBindingRow(frame: frame)
                    row.bind(item, animated: false)
                    return row
                } else {
                    let row = LayerForwardBindingRow(frame: frame)
                    row.bind(item, animated: false)
                    return row
                }
            }
        }
        let after = withExtendedLifetime(rows) { autoreleasepool { CATransaction.flush() }; return memory() }
        let payload: [String: Any] = ["count": count, "mode": mode, "name": present, "avatar": photo, "before_bytes": before, "after_bytes": after, "unique_premeasured_layouts": true, "attached_to_window": false]
        try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: "/tmp/chat-forward-memory-\(mode).json"))
    }
}
