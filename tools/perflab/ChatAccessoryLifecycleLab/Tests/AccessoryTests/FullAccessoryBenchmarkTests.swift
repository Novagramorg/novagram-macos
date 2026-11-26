import Cocoa
import Darwin
import XCTest
import TGUIKit

final class FullAccessoryBenchmarkTests: XCTestCase {
    override func setUp() { TGUIKitTestBootstrap.install() }

    private func fixture(_ index: Int, rich: Bool) -> ChatAccessoryModel {
        let model = ChatAccessoryModel()
        func text(_ value: String) -> TextViewLayout {
            let attributed = NSMutableAttributedString(attributedString: .initialize(string: value, color: .black, font: .normal(13)))
            if rich { attributed.addAttribute(TextInputAttributes.embedded, value: InlineStickerItem(42), range: NSRange(location: 0, length: 2)) }
            let layout = TextViewLayout(attributed, maximumNumberOfLines: 1)
            layout.measure(width: 200)
            return layout
        }
        model.header = text("🐥 Reply author \(index)")
        model.message = text("🐥 Message preview \(index) with longer content")
        return model
    }

    private func makeView(_ model: ChatAccessoryModel, native: Bool) -> NSView {
        if native {
            let view = NativeAccessoryView(frame: model.size.bounds)
            view.updateModel(model, animated: false)
            return view
        }
        let view = ChatAccessoryView(frame: model.size.bounds)
        view.updateModel(model, animated: false)
        return view
    }

    private func report(_ data: [String: Any], suffix: String) throws {
        let encoded = try JSONSerialization.data(withJSONObject: data, options: [.prettyPrinted, .sortedKeys])
        let prefix = ProcessInfo.processInfo.environment["ACCESSORY_RESULT_PREFIX"] ?? "/tmp/chat-accessory"
        try encoded.write(to: URL(fileURLWithPath: prefix + "-" + suffix + ".json"))
        print(String(data: encoded, encoding: .utf8)!)
    }

    func testConstructionAndRebindingBenchmark() throws {
        guard ProcessInfo.processInfo.environment["ACCESSORY_TIMING"] != nil else { throw XCTSkip("Opt-in full accessory benchmark") }
        var results: [String: Any] = [:]
        let count = 400
        let reverse = ProcessInfo.processInfo.environment["ACCESSORY_REVERSE"] != nil
        for fraction in [0, 50, 100] {
            let models = (0..<count).map { fixture($0, rich: $0 % 100 < fraction) }
            for native in [true, false] {
                autoreleasepool {
                    for model in models.prefix(20) { _ = makeView(model, native: native) }
                    CATransaction.flush()
                }
            }
            var construction = ["native": [Double](), "layers": [Double]()]
            var rebind = ["native": [Double](), "layers": [Double]()]
            for batch in 0..<9 {
                let order = ((batch % 2 == 0) != reverse) ? [true, false] : [false, true]
                for native in order {
                    let key = native ? "native" : "layers"
                    autoreleasepool {
                        let start = CACurrentMediaTime()
                        let views = models.map { makeView($0, native: native) }
                        let elapsed = CACurrentMediaTime() - start
                        construction[key]!.append(elapsed * 1_000_000 / Double(count))
                        XCTAssertEqual(views.count, count)
                        let updateStart = CACurrentMediaTime()
                        for index in 0..<2000 {
                            let model = models[(index + 1) % count]
                            if native { (views[index % count] as! NativeAccessoryView).updateModel(model, animated: false) }
                            else { (views[index % count] as! ChatAccessoryView).updateModel(model, animated: false) }
                        }
                        rebind[key]!.append((CACurrentMediaTime() - updateStart) * 1_000_000 / 2000)
                        withExtendedLifetime(views) { CATransaction.flush() }
                    }
                }
            }
            results["rich_percent_\(fraction)"] = ["construction_us": construction, "rebind_us": rebind]
        }
        try report(["measurements": results, "count": count, "reverse": reverse, "premeasured_layouts": true, "attached_to_window": false], suffix: reverse ? "timing-reverse" : "timing")
    }

    func testRetainedMemory() throws {
        guard let mode = ProcessInfo.processInfo.environment["ACCESSORY_MEMORY"], ["native", "layers"].contains(mode) else { throw XCTSkip("Opt-in fresh-process retained memory benchmark") }
        let rich = ProcessInfo.processInfo.environment["ACCESSORY_RICH"] == "1"
        let count = 2000
        let models = autoreleasepool { (0..<count).map { fixture($0, rich: rich) } }
        autoreleasepool {
            for model in models.prefix(20) {
                _ = makeView(model, native: true)
                _ = makeView(model, native: false)
            }
            CATransaction.flush()
        }
        func memory() -> [String: UInt64] {
            var info = task_vm_info_data_t()
            var size = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
            let result = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: integer_t.self, capacity: Int(size)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &size) }
            }
            XCTAssertEqual(result, KERN_SUCCESS)
            return ["footprint": info.phys_footprint, "resident": info.resident_size]
        }
        let before = memory()
        let views = autoreleasepool { models.map { makeView($0, native: mode == "native") } }
        let after = withExtendedLifetime(views) {
            autoreleasepool { CATransaction.flush() }
            return memory()
        }
        try report(["mode": mode, "rich": rich, "count": count, "views": views.reduce(0) { $0 + viewTreeCount($1) }, "before": before, "after": after, "premeasured_layouts": true, "attached_to_window": false], suffix: "memory-\(mode)-\(rich ? "rich" : "plain")")
    }
}
