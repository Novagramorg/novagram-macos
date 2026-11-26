import Cocoa
import XCTest
import QuartzCore
import enum TGUIKit.ContainedViewLayoutTransition
import enum TGUIKitBaseline.ContainedViewLayoutTransition
import class TGUIKit.View
import class TGUIKitBaseline.View
import class TGUIKit.TextView
import class TGUIKitBaseline.TextView

final class FrameBenchmarkTests: XCTestCase {
    func testCosts() throws {
        guard ProcessInfo.processInfo.environment["FRAME_BENCHMARK"] == "1" else { throw XCTSkip("Opt-in frame benchmark") }
        FrameBootstrap.install()
        let reverse = ProcessInfo.processInfo.environment["FRAME_REVERSE"] == "1"
        var results: [String: [[Double]]] = [:]
        var sink = 0
        func measure(_ name: String, count: Int = 10000, operations: [() -> Int]) {
            for op in operations { for _ in 0..<50 { autoreleasepool { sink += op() } } }
            CATransaction.flush()
            var batches = [[Double](), [Double]()]
            for batch in 0..<9 {
                for index in ((batch % 2 == 0) != reverse ? [0, 1] : [1, 0]) {
                    CATransaction.begin()
                    let start = CACurrentMediaTime()
                    for _ in 0..<count { autoreleasepool { sink += operations[index]() } }
                    batches[index].append((CACurrentMediaTime() - start) * 1e6 / Double(count))
                    CATransaction.commit()
                    CATransaction.flush()
                }
            }
            results[name] = batches
        }
        let frame = CGRect(x: 12, y: 8, width: 60, height: 40)
        let old = TGUIKitBaseline.View(frame: frame), new = TGUIKit.View(frame: frame)
        measure("same_frame", operations: [
            { TGUIKitBaseline.ContainedViewLayoutTransition.immediate.updateFrame(view: old, frame: frame); return 1 },
            { TGUIKit.ContainedViewLayoutTransition.immediate.updateFrame(view: new, frame: frame); return 1 }
        ])
        measure("same_frame_with_completion", operations: [
            { var count = 0; TGUIKitBaseline.ContainedViewLayoutTransition.immediate.updateFrame(view: old, frame: frame) { if $0 { count += 1 } }; return count },
            { var count = 0; TGUIKit.ContainedViewLayoutTransition.immediate.updateFrame(view: new, frame: frame) { if $0 { count += 1 } }; return count }
        ])
        let shifted = frame.offsetBy(dx: 1, dy: 1)
        measure("changing_frame", count: 3000, operations: [
            { TGUIKitBaseline.ContainedViewLayoutTransition.immediate.updateFrame(view: old, frame: frame); TGUIKitBaseline.ContainedViewLayoutTransition.immediate.updateFrame(view: old, frame: shifted); return 2 },
            { TGUIKit.ContainedViewLayoutTransition.immediate.updateFrame(view: new, frame: frame); TGUIKit.ContainedViewLayoutTransition.immediate.updateFrame(view: new, frame: shifted); return 2 }
        ])
        old.frame = frame; new.frame = frame
        measure("animated_same_frame", operations: [
            { TGUIKitBaseline.ContainedViewLayoutTransition.animated(duration: 0.2, curve: .easeOut).updateFrame(view: old, frame: frame); return 1 },
            { TGUIKit.ContainedViewLayoutTransition.animated(duration: 0.2, curve: .easeOut).updateFrame(view: new, frame: frame); return 1 }
        ])
        for view in [old as NSView, new as NSView] {
            let animation = CABasicAnimation(keyPath: "position")
            animation.fromValue = NSValue(point: view.layer!.position)
            animation.toValue = NSValue(point: CGPoint(x: view.layer!.position.x + 50, y: view.layer!.position.y))
            animation.duration = 100
            animation.isRemovedOnCompletion = false
            view.layer!.add(animation, forKey: "position")
        }
        measure("same_model_frame_pending_animation", operations: [
            { TGUIKitBaseline.ContainedViewLayoutTransition.immediate.updateFrame(view: old, frame: frame); return 1 },
            { TGUIKit.ContainedViewLayoutTransition.immediate.updateFrame(view: new, frame: frame); return 1 }
        ])
        old.layer!.removeAllAnimations(); new.layer!.removeAllAnimations()
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 500, height: 500), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let oldRoot = TGUIKitBaseline.View(frame: CGRect(x: 0, y: 0, width: 200, height: 400))
        let newRoot = TGUIKit.View(frame: CGRect(x: 200, y: 0, width: 200, height: 400))
        window.contentView!.addSubview(oldRoot); window.contentView!.addSubview(newRoot)
        var oldViews = [NSView](), newViews = [NSView](), frames = [CGRect]()
        for index in 0..<16 {
            let frame = CGRect(x: 10, y: index * 22, width: 150, height: 20)
            let a: NSView = index % 4 == 0 ? TGUIKitBaseline.TextView(frame: frame) : TGUIKitBaseline.View(frame: frame)
            let b: NSView = index % 4 == 0 ? TGUIKit.TextView(frame: frame) : TGUIKit.View(frame: frame)
            oldRoot.addSubview(a); newRoot.addSubview(b)
            oldViews.append(a); newViews.append(b); frames.append(frame)
        }
        oldRoot.layoutSubtreeIfNeeded(); newRoot.layoutSubtreeIfNeeded()
        measure("attached_16_controls_same_frames", count: 1500, operations: [
            { for index in frames.indices { TGUIKitBaseline.ContainedViewLayoutTransition.immediate.updateFrame(view: oldViews[index], frame: frames[index]) }; oldRoot.layoutSubtreeIfNeeded(); return frames.count },
            { for index in frames.indices { TGUIKit.ContainedViewLayoutTransition.immediate.updateFrame(view: newViews[index], frame: frames[index]) }; newRoot.layoutSubtreeIfNeeded(); return frames.count }
        ])
        var oldCycle = false, newCycle = false
        measure("attached_16_controls_4_change", count: 1500, operations: [
            { oldCycle.toggle(); for index in frames.indices { let frame = index % 4 == 0 && oldCycle ? frames[index].offsetBy(dx: 1, dy: 0) : frames[index]; TGUIKitBaseline.ContainedViewLayoutTransition.immediate.updateFrame(view: oldViews[index], frame: frame) }; oldRoot.layoutSubtreeIfNeeded(); return frames.count },
            { newCycle.toggle(); for index in frames.indices { let frame = index % 4 == 0 && newCycle ? frames[index].offsetBy(dx: 1, dy: 0) : frames[index]; TGUIKit.ContainedViewLayoutTransition.immediate.updateFrame(view: newViews[index], frame: frame) }; newRoot.layoutSubtreeIfNeeded(); return frames.count }
        ])
        for resize in [false, true] {
            measure("attached_16_controls_all_change_\(resize ? "size" : "origin")", count: 1500, operations: [
                { oldCycle.toggle(); for index in frames.indices { var frame = frames[index]; if oldCycle { frame.origin.x += 1; if resize { frame.size.width += 1 } }; TGUIKitBaseline.ContainedViewLayoutTransition.immediate.updateFrame(view: oldViews[index], frame: frame) }; oldRoot.layoutSubtreeIfNeeded(); return frames.count },
                { newCycle.toggle(); for index in frames.indices { var frame = frames[index]; if newCycle { frame.origin.x += 1; if resize { frame.size.width += 1 } }; TGUIKit.ContainedViewLayoutTransition.immediate.updateFrame(view: newViews[index], frame: frame) }; newRoot.layoutSubtreeIfNeeded(); return frames.count }
            ])
        }
        XCTAssertGreaterThan(sink, 0)
        try JSONSerialization.data(withJSONObject: ["unit": "microseconds_per_operation", "reverse": reverse, "batches_before_after": results, "sink": sink], options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: "/tmp/frame-transition-benchmark.json"))
    }
}
