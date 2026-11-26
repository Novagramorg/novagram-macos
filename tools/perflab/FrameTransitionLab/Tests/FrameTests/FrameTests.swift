import Cocoa
import XCTest
import enum TGUIKit.ContainedViewLayoutTransition
import enum TGUIKitBaseline.ContainedViewLayoutTransition
import class TGUIKit.View
import class TGUIKitBaseline.View
import class TGUIKit.VisualEffect
import class TGUIKitBaseline.VisualEffect

final class FrameLayer: CALayer {
    var lookups = 0
    override func animation(forKey key: String) -> CAAnimation? {
        lookups += 1
        return super.animation(forKey: key)
    }
}

final class FrameView: NSView {
    var writes = 0
    override var frame: NSRect {
        get { super.frame }
        set { writes += 1; super.frame = newValue }
    }
}

final class FrameTests: XCTestCase {
    let initial = CGRect(x: 12, y: 8, width: 60, height: 40)
    override func setUp() {
        FrameBootstrap.install()
    }

    func view(layered: Bool = true) -> FrameView {
        let view = FrameView(frame: initial)
        if layered {
            view.wantsLayer = true
            view.layer = FrameLayer()
        }
        view.writes = 0
        (view.layer as? FrameLayer)?.lookups = 0
        return view
    }

    func addAnimations(_ view: FrameView, position: Bool, bounds: Bool) -> CGRect {
        let layer = view.layer!
        let targetPosition = position ? CGPoint(x: layer.position.x + 15, y: layer.position.y + 7) : layer.position
        let targetBounds = bounds ? CGRect(x: 3, y: 5, width: layer.bounds.width + 20, height: layer.bounds.height + 9) : layer.bounds
        if position {
            let animation = CABasicAnimation(keyPath: "position")
            animation.fromValue = NSValue(point: layer.position)
            animation.toValue = NSValue(point: targetPosition)
            animation.duration = 100
            animation.isRemovedOnCompletion = false
            layer.add(animation, forKey: "position")
        }
        if bounds {
            let animation = CABasicAnimation(keyPath: "bounds")
            animation.fromValue = NSValue(rect: layer.bounds)
            animation.toValue = NSValue(rect: targetBounds)
            animation.duration = 100
            animation.isRemovedOnCompletion = false
            layer.add(animation, forKey: "bounds")
        }
        (layer as? FrameLayer)?.lookups = 0
        return CGRect(x: targetPosition.x - layer.anchorPoint.x * targetBounds.width, y: targetPosition.y - layer.anchorPoint.y * targetBounds.height, width: targetBounds.width, height: targetBounds.height)
    }

    func equal(_ old: FrameView, _ new: FrameView, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(old.frame, new.frame, file: file, line: line)
        XCTAssertEqual(old.bounds, new.bounds, file: file, line: line)
        XCTAssertEqual(old.writes, new.writes, file: file, line: line)
        XCTAssertEqual(old.layer?.animationKeys()?.sorted(), new.layer?.animationKeys()?.sorted(), file: file, line: line)
        for key in ["position", "bounds"] {
            let a = old.layer?.animation(forKey: key) as? CABasicAnimation
            let b = new.layer?.animation(forKey: key) as? CABasicAnimation
            XCTAssertEqual(a?.fromValue as? NSValue, b?.fromValue as? NSValue, file: file, line: line)
            XCTAssertEqual(a?.toValue as? NSValue, b?.toValue as? NSValue, file: file, line: line)
            XCTAssertEqual(a?.duration, b?.duration, file: file, line: line)
        }
    }

    func testMatchingImmediateFrameAvoidsAnimationLookupsAndWrites() {
        let old = view(), new = view()
        var a = [Bool](), b = [Bool]()
        TGUIKitBaseline.ContainedViewLayoutTransition.immediate.updateFrame(view: old, frame: initial) { a.append($0) }
        TGUIKit.ContainedViewLayoutTransition.immediate.updateFrame(view: new, frame: initial) { b.append($0) }
        XCTAssertEqual((old.layer as! FrameLayer).lookups, 2)
        XCTAssertEqual((new.layer as! FrameLayer).lookups, 0)
        XCTAssertEqual(a, [true]); XCTAssertEqual(a, b)
        XCTAssertEqual(new.writes, 0)
        equal(old, new)
    }

    func testImmediateMatchesForLayerlessAndChangedFrames() {
        for layered in [true, false] {
            let old = view(layered: layered), new = view(layered: layered)
            for frame in [initial, CGRect(x: 5.5, y: -3.25, width: 20, height: 30), .zero, initial, initial] {
                var a = [Bool](), b = [Bool]()
                TGUIKitBaseline.ContainedViewLayoutTransition.immediate.updateFrame(view: old, frame: frame) { a.append($0) }
                TGUIKit.ContainedViewLayoutTransition.immediate.updateFrame(view: new, frame: frame) { b.append($0) }
                XCTAssertEqual(a, [true]); XCTAssertEqual(a, b)
                equal(old, new)
            }
        }
    }

    func testPendingAnimationTargetsPreserveImmediateBehavior() {
        for position in [false, true] {
            for bounds in [false, true] {
                for target in 0..<3 {
                    let old = view(), new = view()
                    let endpoint = addAnimations(old, position: position, bounds: bounds)
                    XCTAssertEqual(endpoint, addAnimations(new, position: position, bounds: bounds))
                    let frame = target == 0 ? initial : target == 1 ? endpoint : CGRect(x: 90, y: 70, width: 130, height: 80)
                    var a = [Bool](), b = [Bool]()
                    TGUIKitBaseline.ContainedViewLayoutTransition.immediate.updateFrame(view: old, frame: frame) { a.append($0) }
                    TGUIKit.ContainedViewLayoutTransition.immediate.updateFrame(view: new, frame: frame) { b.append($0) }
                    XCTAssertEqual(a, [true]); XCTAssertEqual(a, b)
                    equal(old, new)
                }
            }
        }
    }

    func testAnimatedPathPreservesEndpointsAndCompletionDelivery() {
        for pending in [false, true] {
            for target in 0..<3 {
                let old = view(), new = view()
                let endpoint = addAnimations(old, position: pending, bounds: pending)
                _ = addAnimations(new, position: pending, bounds: pending)
                let frame = target == 0 ? initial : target == 1 ? endpoint : CGRect(x: 30, y: 20, width: 100, height: 90)
                var a = [Bool](), b = [Bool]()
                TGUIKitBaseline.ContainedViewLayoutTransition.animated(duration: 0.2, curve: .easeOut).updateFrame(view: old, frame: frame) { a.append($0) }
                TGUIKit.ContainedViewLayoutTransition.animated(duration: 0.2, curve: .easeOut).updateFrame(view: new, frame: frame) { b.append($0) }
                equal(old, new)
                old.layer?.removeAllAnimations(); new.layer?.removeAllAnimations()
                CATransaction.flush()
                RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.01))
                XCTAssertEqual(a, b)
                if target == 1 { XCTAssertEqual(a, [true]) }
            }
        }
    }

    func testMatchingTransformedAndAnchoredViewsPreserveLayers() {
        for anchor in [CGPoint.zero, CGPoint(x: 0.5, y: 0.5), CGPoint(x: 1, y: 0.25)] {
            let old = view(), new = view()
            for view in [old, new] {
                view.layer!.anchorPoint = anchor
                view.layer!.transform = CATransform3DMakeScale(0.8, 1.3, 1)
                view.bounds.origin = CGPoint(x: 5, y: 7)
            }
            let target = old.frame
            TGUIKitBaseline.ContainedViewLayoutTransition.immediate.updateFrame(view: old, frame: target)
            TGUIKit.ContainedViewLayoutTransition.immediate.updateFrame(view: new, frame: target)
            equal(old, new)
            XCTAssertTrue(CATransform3DEqualToTransform(old.layer!.transform, new.layer!.transform))
        }
    }

    func testAttachedViewsAndReentrantCompletionMatch() {
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 400, height: 200), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let old = view(), new = view()
        window.contentView!.addSubview(old); window.contentView!.addSubview(new)
        window.contentView!.layoutSubtreeIfNeeded()
        let target = CGRect(x: 25, y: 30, width: 80, height: 60)
        var a = [Bool](), b = [Bool]()
        TGUIKitBaseline.ContainedViewLayoutTransition.immediate.updateFrame(view: old, frame: initial) {
            a.append($0)
            TGUIKitBaseline.ContainedViewLayoutTransition.immediate.updateFrame(view: old, frame: target) { a.append($0) }
        }
        TGUIKit.ContainedViewLayoutTransition.immediate.updateFrame(view: new, frame: initial) {
            b.append($0)
            TGUIKit.ContainedViewLayoutTransition.immediate.updateFrame(view: new, frame: target) { b.append($0) }
        }
        XCTAssertEqual(a, [true, true]); XCTAssertEqual(a, b)
        equal(old, new)
    }
    func testRealToolkitViewResizeCallbacksAndCompletionOrderMatch() {
        let old = TGUIKitBaseline.View(frame: initial), new = TGUIKit.View(frame: initial)
        var a = [String](), b = [String]()
        old.customHandler.size = { a.append("size \($0)") }
        old.customHandler.origin = { a.append("origin \($0)") }
        new.customHandler.size = { b.append("size \($0)") }
        new.customHandler.origin = { b.append("origin \($0)") }
        for target in [initial, CGRect(x: 4, y: 5, width: 100, height: 80), initial] {
            a.removeAll(); b.removeAll()
            TGUIKitBaseline.ContainedViewLayoutTransition.immediate.updateFrame(view: old, frame: target) { a.append("complete \($0)") }
            TGUIKit.ContainedViewLayoutTransition.immediate.updateFrame(view: new, frame: target) { b.append("complete \($0)") }
            XCTAssertEqual(a, b)
            XCTAssertEqual(a.last, "complete true")
            XCTAssertEqual(old.frame, new.frame)
        }
    }

    func testVisualEffectImmediateAndAnimatedNoOpMatch() {
        let old = TGUIKitBaseline.VisualEffect(frame: initial), new = TGUIKit.VisualEffect(frame: initial)
        for target in [initial, CGRect(x: 30, y: 40, width: 90, height: 70), initial] {
            var a = [Bool](), b = [Bool]()
            TGUIKitBaseline.ContainedViewLayoutTransition.immediate.updateFrame(view: old, frame: target) { a.append($0) }
            TGUIKit.ContainedViewLayoutTransition.immediate.updateFrame(view: new, frame: target) { b.append($0) }
            TGUIKitBaseline.ContainedViewLayoutTransition.animated(duration: 0.2, curve: .easeOut).updateFrame(view: old, frame: target) { a.append($0) }
            TGUIKit.ContainedViewLayoutTransition.animated(duration: 0.2, curve: .easeOut).updateFrame(view: new, frame: target) { b.append($0) }
            XCTAssertEqual(a, [true, true]); XCTAssertEqual(a, b)
            XCTAssertEqual(old.frame, new.frame)
        }
    }

}
