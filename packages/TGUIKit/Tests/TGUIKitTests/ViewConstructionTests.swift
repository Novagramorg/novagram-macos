import Cocoa
import XCTest
import QuartzCore
import ObjcUtils
@testable import TGUIKit

private let cachedDisabledActions: [String: CAAction] = ["onOrderIn": NSNull(), "sublayers": NSNull(), "bounds": NSNull(), "frame": NSNull(), "background": NSNull(), "position": NSNull(), "contents": NSNull(), "backgroundColor": NSNull(), "border": NSNull(), "shadowOffset": NSNull()]

private let foundationDisabledActions: NSDictionary = {
    let result = NSMutableDictionary()
    for key in cachedDisabledActions.keys { result[key] = NSNull() }
    return result.copy() as! NSDictionary
}()
private let bridgedDisabledActions = foundationDisabledActions as! [String: CAAction]

private func legacyDisableActions(_ layer: CALayer) {
    layer.actions = ["onOrderIn": NSNull(), "sublayers": NSNull(), "bounds": NSNull(), "frame": NSNull(), "background": NSNull(), "position": NSNull(), "contents": NSNull(), "backgroundColor": NSNull(), "border": NSNull(), "shadowOffset": NSNull()]
    layer.removeAllAnimations()
}

final class ViewConstructionTests: XCTestCase {
    override func setUp() { TGUIKitTestBootstrap.install() }

    func testConstructionCosts() throws {
        guard ProcessInfo.processInfo.environment["VIEW_CONSTRUCTION_BENCHMARK"] == "1" else { throw XCTSkip("Opt-in view construction benchmark") }
        let layout = TextViewLayout(NSAttributedString(string: "Chat message مرحبا 👩🏽‍💻", attributes: [.font: NSFont.systemFont(ofSize: 14), .foregroundColor: NSColor.black]))
        layout.measure(width: 240)
        let layers = (0..<6).map { _ in CALayer() }
        var sink = 0
        var results: [String: [Double]] = [:]
        let cases: [(String, Int, () -> Void)] = [
            ("legacy_disable_actions", 10000, { legacyDisableActions(layers[0]) }),
            ("cached_disable_actions", 10000, { layers[1].actions = cachedDisabledActions; layers[1].removeAllAnimations() }),
            ("foundation_disable_actions", 10000, { layers[2].actions = bridgedDisabledActions; layers[2].removeAllAnimations() }),
            ("kvc_disable_actions", 10000, { layers[3].setValue(foundationDisabledActions, forKey: "actions"); layers[3].removeAllAnimations() }),
            ("objc_disable_actions", 10000, { TGDisableLayerActions(layers[4]) }),
            ("production_disable_actions", 10000, { layers[5].disableActions() }),
            ("view", 1000, { let view = View(); sink += view.subviews.count }),
            ("control", 1000, { let view = Control(); sink += view.subviews.count }),
            ("text_view", 1000, { let view = TextView(); sink += view.layer?.sublayers?.count ?? 0 }),
            ("text_view_and_layout", 1000, { let view = TextView(); view.update(layout); sink += view.layer?.sublayers?.count ?? 0 })
        ]
        for (_, _, body) in cases { for _ in 0..<100 { autoreleasepool(invoking: body) } }
        for batch in 0..<9 {
            for (name, count, body) in batch % 2 == 0 ? cases : cases.reversed() {
                let start = CACurrentMediaTime()
                for _ in 0..<count { autoreleasepool(invoking: body) }
                results[name, default: []].append((CACurrentMediaTime() - start) * 1e6 / Double(count))
            }
        }
        XCTAssertGreaterThan(sink, 0)
        try JSONSerialization.data(withJSONObject: ["unit": "microseconds_per_operation", "batches": results], options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: "/tmp/view-construction-benchmark.json"))
    }

    func testConstructionProfile() throws {
        guard ProcessInfo.processInfo.environment["VIEW_CONSTRUCTION_PROFILE"] == "1" else { throw XCTSkip("Opt-in view construction sampling") }
        try String(ProcessInfo.processInfo.processIdentifier).write(toFile: "/tmp/view-construction-profile.pid", atomically: true, encoding: .utf8)
        let end = CACurrentMediaTime() + 20
        var count = 0
        while CACurrentMediaTime() < end {
            autoreleasepool { let view = TextView(); count += view.layer?.sublayers?.count ?? 0 }
        }
        XCTAssertGreaterThan(count, 0)
    }

    func testRetainedActionStorage() throws {
        guard let mode = ProcessInfo.processInfo.environment["LAYER_ACTIONS_MEMORY_MODE"], ["legacy", "native"].contains(mode) else { throw XCTSkip("Opt-in layer action footprint benchmark") }
        func memory() -> [String: UInt64] {
            var info = task_vm_info_data_t()
            var size = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
            let result = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: integer_t.self, capacity: Int(size)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &size) }
            }
            XCTAssertEqual(result, KERN_SUCCESS)
            return ["footprint_bytes": info.phys_footprint, "resident_bytes": info.resident_size]
        }
        autoreleasepool {
            for _ in 0..<100 { let layer = CALayer(); legacyDisableActions(layer); TGDisableLayerActions(layer) }
            CATransaction.flush()
        }
        let before = memory()
        let count = 20000
        let layers = autoreleasepool { (0..<count).map { _ -> CALayer in
            let layer = CALayer()
            if mode == "legacy" { legacyDisableActions(layer) } else { TGDisableLayerActions(layer) }
            return layer
        } }
        let after = withExtendedLifetime(layers) { () -> [String: UInt64] in
            autoreleasepool { CATransaction.flush() }
            return memory()
        }
        let payload: [String: Any] = ["mode": mode, "count": count, "before": before, "after": after, "attached_to_window": false]
        try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: "/tmp/layer-actions-memory-\(mode).json"))
    }


    func testRetainedTextContainers() throws {
        guard let mode = ProcessInfo.processInfo.environment["TEXT_CONTAINER_MEMORY_MODE"], ["lazy", "eager"].contains(mode) else { throw XCTSkip("Opt-in text container footprint benchmark") }
        func memory() -> [String: UInt64] {
            var info = task_vm_info_data_t()
            var size = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
            let result = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: integer_t.self, capacity: Int(size)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &size) }
            }
            XCTAssertEqual(result, KERN_SUCCESS)
            return ["footprint_bytes": info.phys_footprint, "resident_bytes": info.resident_size]
        }
        autoreleasepool {
            for _ in 0..<100 { let view = TextView(); _ = view.embeddedContainer }
            CATransaction.flush()
        }
        let before = memory()
        let count = 10000
        let views = autoreleasepool { (0..<count).map { _ -> TextView in
            let view = TextView()
            if mode == "eager" { _ = view.embeddedContainer }
            return view
        } }
        let after = withExtendedLifetime(views) { () -> [String: UInt64] in
            autoreleasepool { CATransaction.flush() }
            return memory()
        }
        let payload: [String: Any] = ["mode": mode, "count": count, "before": before, "after": after, "attached_to_window": false]
        try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: "/tmp/text-container-memory-\(mode).json"))
    }

}
