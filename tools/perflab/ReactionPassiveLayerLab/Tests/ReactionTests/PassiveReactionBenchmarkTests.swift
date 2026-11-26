import Cocoa
import Darwin
import QuartzCore
import XCTest
import TGUIKit
@testable import ReactionHarness

final class PassiveReactionBenchmarkTests: XCTestCase {
    private func viewCount(_ view: NSView) -> Int {
        1 + view.subviews.reduce(0) { $0 + viewCount($1) }
    }

    func testConstructionAndBindingCosts() throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["REACTION_PASSIVE_BENCHMARK"] == "1" else { throw XCTSkip("Opt-in passive reaction timing") }
        let setup = PassiveReactionTests()
        setup.setUp()
        defer { setup.tearDown() }
        let reversed = environment["REACTION_PASSIVE_REVERSE"] == "1"
        let frame = CGRect(x: 0, y: 0, width: 120, height: 32)
        var samples: [String: [[Double]]] = [:]
        var counts: [String: [Int]] = [:]
        var sink: CGFloat = 0
        func measure(_ name: String, count: Int, operations: [() -> Void]) {
            for index in reversed ? [1, 0] : [0, 1] {
                autoreleasepool { for _ in 0..<20 { operations[index]() } }
            }
            var pairs = [[Double](), [Double]()]
            for batch in 0..<9 {
                for index in (batch % 2 == 0) != reversed ? [0, 1] : [1, 0] {
                    let elapsed = autoreleasepool { () -> Double in
                        let start = CACurrentMediaTime()
                        for _ in 0..<count { operations[index]() }
                        return (CACurrentMediaTime() - start) * 1_000_000 / Double(count)
                    }
                    pairs[index].append(elapsed)
                }
            }
            samples[name] = pairs
        }
        for tag in [false, true] {
            let label = tag ? "tag" : "full"
            let makers: [() -> ReactionFixture] = tag ? [{ OriginalTag(frame: frame) }, { CurrentTag(frame: frame) }] : [{ OriginalFull(frame: frame) }, { CurrentFull(frame: frame) }]
            let layouts = (0..<2).map { _ in [setup.reaction("123"), setup.reaction("123", selected: true), setup.reaction("24.7K", color: .blue), setup.reaction(nil)] }
            let views = makers.map { $0() }
            for i in 0..<2 { views[i].bind(layouts[i][1], animated: false) }
            counts[label] = views.map(viewCount)
            for selected in [false, true] {
                let index = selected ? 1 : 0
                measure("construct_\(label)_selected_\(selected)", count: 300, operations: (0..<2).map { i in {
                    let view = makers[i]()
                    view.bind(layouts[i][index], animated: false)
                    sink += view.countLayer?.bounds.width ?? 0
                } })
            }
            measure("same_bind_\(label)", count: 1000, operations: (0..<2).map { i in {
                views[i].bind(layouts[i][1], animated: false)
                sink += views[i].textFrame?.width ?? 0
            } })
            var indices = [0, 0]
            measure("changing_bind_\(label)", count: 1000, operations: (0..<2).map { i in {
                indices[i] += 1
                views[i].bind(layouts[i][indices[i] % 3], animated: false)
                sink += views[i].textFrame?.width ?? 0
            } })
            measure("remove_restore_text_\(label)", count: 500, operations: (0..<2).map { i in {
                views[i].bind(layouts[i][3], animated: false)
                views[i].bind(layouts[i][0], animated: false)
                sink += views[i].textFrame?.width ?? 0
            } })
            _ = setup.attach(views)
            measure("attached_resize_\(label)", count: 500, operations: (0..<2).map { i in {
                indices[i] += 1
                views[i].setFrameSize(CGSize(width: CGFloat(120 + indices[i] % 2), height: 32))
                views[i].layoutSubtreeIfNeeded()
                sink += views[i].frame.width
            } })
        }
        XCTAssertGreaterThan(sink, 0)
        let payload: [String: Any] = ["batches": samples, "view_counts": counts, "reversed": reversed, "variant_order": ["native", "layers"], "units": "microseconds_per_operation", "batch_count": 9, "scope": "Extracted passive reaction bindings; premeasured text; icon placeholder; no media/avatar fetches, real effects, full reaction actions, rasterization or full chat scrolling", "iterations": ["construct": 300, "same_bind": 1000, "changing_bind": 1000, "remove_restore_text": 500, "attached_resize": 500]]
        let path = environment["REACTION_PASSIVE_OUTPUT"] ?? "/tmp/reaction-passive-timing.json"
        try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: path))
    }

    func testRetainedAllocationFootprint() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let variant = environment["REACTION_PASSIVE_MEMORY"], ["native", "layers"].contains(variant) else { throw XCTSkip("Opt-in fresh-process reaction footprint") }
        let setup = PassiveReactionTests()
        setup.setUp()
        defer { setup.tearDown() }
        let frame = CGRect(x: 0, y: 0, width: 120, height: 32)
        let native = setup.reaction("123", selected: true), current = setup.reaction("123", selected: true)
        autoreleasepool {
            for _ in 0..<30 {
                OriginalFull(frame: frame).bind(native, animated: false)
                CurrentFull(frame: frame).bind(current, animated: false)
            }
            CATransaction.flush()
        }
        func memory() -> [String: UInt64] {
            var info = task_vm_info_data_t()
            var size = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
            let status = withUnsafeMutablePointer(to: &info) { pointer in
                pointer.withMemoryRebound(to: integer_t.self, capacity: Int(size)) {
                    task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &size)
                }
            }
            XCTAssertEqual(status, KERN_SUCCESS)
            return ["footprint": info.phys_footprint, "resident": info.resident_size]
        }
        var retained: [ReactionFixture] = []
        retained.reserveCapacity(2000)
        let before = memory()
        autoreleasepool {
            for _ in 0..<2000 {
                let view: ReactionFixture = variant == "native" ? OriginalFull(frame: frame) : CurrentFull(frame: frame)
                view.bind(variant == "native" ? native : current, animated: false)
                retained.append(view)
            }
            CATransaction.flush()
        }
        let after = withExtendedLifetime(retained) { memory() }
        let payload: [String: Any] = ["variant": variant, "count": retained.count, "before": before, "after": after, "views": retained.reduce(0) { $0 + viewCount($1) }, "attached": false, "rasterized": false, "shared_premeasured_text": true, "media_placeholder": true, "includes_allocator_and_framework_storage": true]
        let path = environment["REACTION_PASSIVE_OUTPUT"] ?? "/tmp/reaction-passive-memory.json"
        try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: path))
    }
}
