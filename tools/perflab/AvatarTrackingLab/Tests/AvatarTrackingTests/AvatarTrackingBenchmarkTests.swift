import Cocoa
import XCTest
import AvatarTrackingCurrent
import AvatarTrackingOriginal

final class AvatarTrackingBenchmarkTests: XCTestCase {
    func testTrackingRefreshScrollAndAttachmentCosts() throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["AVATAR_TRACKING_BENCHMARK"] == "1" else { throw XCTSkip("Opt-in avatar tracking timing") }
        _ = NSApplication.shared
        let reversed = environment["AVATAR_TRACKING_REVERSE"] == "1"
        var batches: [String: [[Double]]] = [:]
        var operations: [String: Int] = [:]
        var registrations: [String: [[Int]]] = [:]
        var sink = 0
        func measure(_ name: String, count: Int, actions: [() -> Void]) {
            for index in reversed ? [1, 0] : [0, 1] {
                autoreleasepool { for _ in 0..<20 { actions[index]() } }
            }
            var samples = [[Double](), [Double]()]
            for batch in 0..<9 {
                for index in (batch % 2 == 0) != reversed ? [0, 1] : [1, 0] {
                    let elapsed = autoreleasepool { () -> Double in
                        let start = CACurrentMediaTime()
                        for _ in 0..<count { actions[index]() }
                        return (CACurrentMediaTime() - start) * 1_000_000 / Double(count)
                    }
                    samples[index].append(elapsed)
                }
            }
            batches[name] = samples
            operations[name] = count
        }
        for rowCount in [1, 50, 200] {
            let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 300, height: 160), styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            let parent = NSView(frame: CGRect(x: 0, y: 0, width: 300, height: 160))
            window.contentView = parent
            let scrolls = [NSScrollView(frame: CGRect(x: 0, y: 0, width: 100, height: 120)), NSScrollView(frame: CGRect(x: 140, y: 0, width: 100, height: 120))]
            let documents = (0..<2).map { _ in NSView(frame: CGRect(x: 0, y: 0, width: 100, height: max(1000, CGFloat(rowCount * 48)))) }
            for index in 0..<2 {
                scrolls[index].documentView = documents[index]
                parent.addSubview(scrolls[index])
            }
            let original = (0..<rowCount).map { index -> OriginalAvatar in
                let avatar = OriginalAvatar(font: .systemFont(ofSize: 16))
                avatar.frame = CGRect(x: 12, y: CGFloat(index * 48), width: 36, height: 36)
                avatar.userInteractionEnabled = false
                documents[0].addSubview(avatar)
                avatar.updateTrackingAreas()
                return avatar
            }
            let current = (0..<rowCount).map { index -> CurrentAvatar in
                let avatar = CurrentAvatar(font: .systemFont(ofSize: 16))
                avatar.frame = CGRect(x: 12, y: CGFloat(index * 48), width: 36, height: 36)
                avatar.userInteractionEnabled = false
                documents[1].addSubview(avatar)
                avatar.updateTrackingAreas()
                return avatar
            }
            let originalBefore = [original.reduce(0) { $0 + $1.additions }, original.reduce(0) { $0 + $1.removals }]
            let currentBefore = [current.reduce(0) { $0 + $1.additions }, current.reduce(0) { $0 + $1.removals }]
            for _ in 0..<100 {
                original.forEach { $0.updateTrackingAreas() }
                current.forEach { $0.updateTrackingAreas() }
            }
            let originalDelta = [original.reduce(0) { $0 + $1.additions } - originalBefore[0], original.reduce(0) { $0 + $1.removals } - originalBefore[1]]
            let currentDelta = [current.reduce(0) { $0 + $1.additions } - currentBefore[0], current.reduce(0) { $0 + $1.removals } - currentBefore[1]]
            XCTAssertEqual(originalDelta, [rowCount * 100, rowCount * 100])
            XCTAssertEqual(currentDelta, [0, 0])
            registrations[String(rowCount)] = [originalDelta, currentDelta]
            measure("refresh_\(rowCount)", count: 100, actions: [
                { original.forEach { $0.updateTrackingAreas() }; sink += original.count },
                { current.forEach { $0.updateTrackingAreas() }; sink += current.count }
            ])
            var indices = [0, 0]
            let variants: [[NSView]] = [original, current]
            let scrollActions: [() -> Void] = (0..<2).map { variant in
                return {
                    indices[variant] += 1
                    scrolls[variant].contentView.scroll(to: CGPoint(x: 0, y: CGFloat(indices[variant] % 80) * 8))
                    scrolls[variant].reflectScrolledClipView(scrolls[variant].contentView)
                    variants[variant].forEach { $0.updateTrackingAreas() }
                    sink += variants[variant].count
                }
            }
            measure("scroll_and_refresh_\(rowCount)", count: 100, actions: scrollActions)
            let attachmentActions: [() -> Void] = (0..<2).map { variant in
                return {
                    scrolls[variant].removeFromSuperview()
                    parent.addSubview(scrolls[variant])
                    variants[variant].forEach { $0.updateTrackingAreas() }
                    sink += variants[variant].count
                }
            }
            measure("ancestor_detach_attach_\(rowCount)", count: 30, actions: attachmentActions)
            window.close()
        }
        XCTAssertGreaterThan(sink, 0)
        let payload: [String: Any] = [
            "batches": batches, "iterations_per_batch": operations,
            "registration_add_remove_counts_for_100_refreshes": registrations,
            "variant_order": ["captured_avatar_tracking", "current"], "reversed": reversed,
            "units": "microseconds_per_complete_row_set_operation", "batch_count": 9,
            "warmup_iterations": 20, "attached": true, "avatars_rendered": false,
            "scope": "Real AppKit tracking lifecycle and explicit scrolling plus refresh; excludes avatar images, account/media work, full row construction, event-loop presentation and whole-app FPS"
        ]
        let output = environment["AVATAR_TRACKING_OUTPUT"] ?? "/tmp/avatar-tracking-benchmark.json"
        try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: output))
    }
}
