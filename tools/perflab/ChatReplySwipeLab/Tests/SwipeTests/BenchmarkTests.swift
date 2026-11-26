import Cocoa
import Darwin
import XCTest
import TGUIKit

final class BenchmarkTests: XCTestCase {
    override func setUp() { TGUIKitTestBootstrap.install() }
    private func make(_ native: Bool) -> RowEnvironment {
        let frame = NSRect(x: 0, y: 0, width: 400, height: 80)
        return native ? NativeRow(frame: frame) : CandidateRow(frame: frame)
    }
    private func save(_ result: [String: Any], name: String) throws {
        let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
        let prefix = ProcessInfo.processInfo.environment["SWIPE_RESULT_PREFIX"] ?? "/tmp/chat-reply-swipe"
        try data.write(to: URL(fileURLWithPath: prefix + "-" + name + ".json"))
    }
    func testIdleConstructionAndLayoutBenchmark() throws {
        guard ProcessInfo.processInfo.environment["SWIPE_TIMING"] != nil else { throw XCTSkip("Opt-in swipe fixture timing") }
        let count = 600
        let reverse = ProcessInfo.processInfo.environment["SWIPE_REVERSE"] != nil
        var construction = ["native": [Double](), "candidate": [Double]()]
        var layout = construction
        autoreleasepool { for _ in 0..<30 { _ = make(true); _ = make(false) }; CATransaction.flush() }
        for batch in 0..<9 {
            for native in ((batch % 2 == 0) != reverse ? [true, false] : [false, true]) {
                autoreleasepool {
                    let key = native ? "native" : "candidate"
                    let start = CACurrentMediaTime()
                    let views = (0..<count).map { _ in make(native) }
                    construction[key]!.append((CACurrentMediaTime() - start) * 1_000_000 / Double(count))
                    let layoutStart = CACurrentMediaTime()
                    for index in 0..<60000 {
                        if native { (views[index % count] as! NativeRow).layoutSwipe() }
                        else { (views[index % count] as! CandidateRow).layoutSwipe() }
                    }
                    layout[key]!.append((CACurrentMediaTime() - layoutStart) * 1_000_000 / 60000)
                    withExtendedLifetime(views) { CATransaction.flush() }
                }
            }
        }
        try save(["count": count, "reverse": reverse, "construction_us": construction, "idle_layout_us": layout, "scope": "Native row shell plus production swipe state; not a full chat row"], name: reverse ? "timing-reverse" : "timing")
    }
    func testRetainedIdleRowMemory() throws {
        guard let mode = ProcessInfo.processInfo.environment["SWIPE_MEMORY"], ["native", "candidate"].contains(mode) else { throw XCTSkip("Opt-in fresh-process idle swipe memory") }
        let count = 3000
        autoreleasepool { for _ in 0..<30 { _ = make(true); _ = make(false) }; CATransaction.flush() }
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
        let views = autoreleasepool { (0..<count).map { _ in make(mode == "native") } }
        let after = withExtendedLifetime(views) { autoreleasepool { CATransaction.flush() }; return footprint() }
        try save(["mode": mode, "count": count, "before": before, "after": after, "scope": "Native row shell plus production swipe state; not a full chat row", "attached_to_window": false], name: "memory-" + mode)
    }
}
