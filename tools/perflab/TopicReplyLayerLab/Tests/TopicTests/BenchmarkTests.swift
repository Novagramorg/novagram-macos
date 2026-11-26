import Cocoa
import Darwin
import XCTest
import TGUIKit

final class BenchmarkTests: XCTestCase {
    override func setUp() { TGUIKitTestBootstrap.install() }
    private func model(_ index: Int) -> TopicReplyItemLayout {
        TopicReplyItemLayout("Topic \(index) with a longer title", width: 120 + CGFloat(index % 3) * 40, lines: index % 2 == 0 ? 1 : 3)
    }
    private func make(_ item: TopicReplyItemLayout, native: Bool) -> Control {
        if native {
            let view = NativeTopicView(frame: item.size.bounds)
            view.update(item: item, animated: false)
            view.updateLayout(size: item.size, transition: .immediate)
            return view
        }
        let view = CandidateTopicView(frame: item.size.bounds)
        view.update(item: item, animated: false)
        view.updateLayout(size: item.size, transition: .immediate)
        return view
    }
    private func save(_ payload: [String: Any], name: String) throws {
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
        let prefix = ProcessInfo.processInfo.environment["TOPIC_RESULT_PREFIX"] ?? "/tmp/topic-reply"
        try data.write(to: URL(fileURLWithPath: prefix + "-" + name + ".json"))
    }
    func testConstructionAndRebindingBenchmark() throws {
        guard ProcessInfo.processInfo.environment["TOPIC_TIMING"] != nil else { throw XCTSkip("Opt-in topic rendering benchmark") }
        let count = 400
        let items = (0..<count).map(model)
        let reverse = ProcessInfo.processInfo.environment["TOPIC_REVERSE"] != nil
        var construction = ["native": [Double](), "layers": [Double]()]
        var updates = construction
        autoreleasepool {
            for item in items.prefix(20) { _ = make(item, native: true); _ = make(item, native: false) }
            CATransaction.flush()
        }
        for batch in 0..<9 {
            for native in ((batch % 2 == 0) != reverse ? [true, false] : [false, true]) {
                autoreleasepool {
                    let key = native ? "native" : "layers"
                    let start = CACurrentMediaTime()
                    let views = items.map { make($0, native: native) }
                    construction[key]!.append((CACurrentMediaTime() - start) * 1_000_000 / Double(count))
                    let rebind = CACurrentMediaTime()
                    for index in 0..<2000 {
                        let item = items[(index + 1) % count]
                        if native { (views[index % count] as! NativeTopicView).update(item: item, animated: false); (views[index % count] as! NativeTopicView).updateLayout(size: item.size, transition: .immediate) }
                        else { (views[index % count] as! CandidateTopicView).update(item: item, animated: false); (views[index % count] as! CandidateTopicView).updateLayout(size: item.size, transition: .immediate) }
                    }
                    updates[key]!.append((CACurrentMediaTime() - rebind) * 1_000_000 / 2000)
                    withExtendedLifetime(views) { CATransaction.flush() }
                }
            }
        }
        try save(["construction_us": construction, "rebind_us": updates, "count": count, "reverse": reverse, "premeasured_layouts": true, "scope": "Full topic view with generated static fixture icons; no real emoji decoding"], name: reverse ? "timing-reverse" : "timing")
    }
    func testRetainedMemory() throws {
        guard let mode = ProcessInfo.processInfo.environment["TOPIC_MEMORY"], ["native", "layers"].contains(mode) else { throw XCTSkip("Opt-in fresh-process topic memory") }
        let count = 2000
        let items = autoreleasepool { (0..<count).map(model) }
        autoreleasepool { for item in items.prefix(20) { _ = make(item, native: true); _ = make(item, native: false) }; CATransaction.flush() }
        func footprint() -> UInt64 {
            var info = task_vm_info_data_t()
            var size = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
            let result = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: integer_t.self, capacity: Int(size)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &size) }
            }
            XCTAssertEqual(result, KERN_SUCCESS)
            return info.phys_footprint
        }
        let before = footprint()
        let views = autoreleasepool { items.map { make($0, native: mode == "native") } }
        let after = withExtendedLifetime(views) { autoreleasepool { CATransaction.flush() }; return footprint() }
        try save(["mode": mode, "count": count, "before": before, "after": after, "premeasured_layouts": true, "attached_to_window": false, "scope": "Full topic view with static fixture icons; no real emoji decoding"], name: "memory-" + mode)
    }
}
