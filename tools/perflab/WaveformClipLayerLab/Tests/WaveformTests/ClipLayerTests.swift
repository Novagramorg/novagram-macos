import Cocoa
import QuartzCore
import XCTest
import TGUIKit
@testable import WaveformCurrent
@testable import WaveformOriginal

func waveformOwnedLayerCount(_ view: NSView) -> Int {
    var identities = Set<ObjectIdentifier>()
    func collectLayer(_ layer: CALayer) {
        guard identities.insert(ObjectIdentifier(layer)).inserted else { return }
        layer.sublayers?.forEach(collectLayer)
    }
    func collectView(_ view: NSView) {
        if let layer = view.layer { collectLayer(layer) }
        view.subviews.forEach(collectView)
    }
    collectView(view)
    return identities.count
}

final class ClipEventParent: View {
    var received: [NSEvent.EventType] = []
    var points: [CGPoint] = []
    weak var waveform: NSView?

    private func record(_ event: NSEvent) {
        received.append(event.type)
        if let waveform { points.append(waveform.convert(event.locationInWindow, from: nil)) }
    }

    override func mouseDown(with event: NSEvent) { record(event) }
    override func mouseDragged(with event: NSEvent) { record(event) }
    override func mouseUp(with event: NSEvent) { record(event) }
    override func rightMouseDown(with event: NSEvent) { record(event) }
    override func rightMouseUp(with event: NSEvent) { record(event) }
    override func scrollWheel(with event: NSEvent) { record(event) }
}

final class ClipLayerTests: XCTestCase {
    override func setUp() {
        super.setUp()
        _ = NSApplication.shared
    }

    private func samples() -> Data {
        (0..<100).map { UInt16(($0 * 13) % 32) }.withUnsafeBytes { Data($0) }
    }

    private func window() -> NSWindow {
        let window = NSWindow(contentRect: CGRect(x: 60, y: 60, width: 320, height: 140), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = View(frame: CGRect(x: 0, y: 0, width: 320, height: 140))
        return window
    }

    private func pair() -> (WaveformCurrent.AudioWaveformView, WaveformOriginal.AudioWaveformView) {
        let frame = CGRect(x: 17, y: 23, width: 170, height: 20)
        let current = WaveformCurrent.AudioWaveformView(frame: frame)
        let original = WaveformOriginal.AudioWaveformView(frame: frame)
        let data = samples()
        current.waveform = WaveformCurrent.AudioWaveform(samples: data, peak: 31)
        original.waveform = WaveformOriginal.AudioWaveform(samples: data, peak: 31)
        current.set(foregroundColor: .red, backgroundColor: .blue)
        original.set(foregroundColor: .red, backgroundColor: .blue)
        current.layout()
        original.layout()
        return (current, original)
    }

    private func render(_ view: NSView, scale: CGFloat) throws -> Data {
        view.layoutSubtreeIfNeeded()
        view.window?.displayIfNeeded()
        let layer = try XCTUnwrap(view.layer)
        func prepare(_ layer: CALayer) {
            layer.contentsScale = scale
            layer.displayIfNeeded()
            layer.sublayers?.forEach(prepare)
        }
        prepare(layer)
        let width = max(1, Int(ceil(view.bounds.width * scale)))
        let height = max(1, Int(ceil(view.bounds.height * scale)))
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.scaleBy(x: scale, y: scale)
        layer.render(in: context)
        return Data(bytes: context.data!, count: height * width * 4)
    }

    func testCompositePixelsAndClippingCoordinatesMatchImmediateBaseline() throws {
        let window = window()
        defer { window.close() }
        let (current, original) = pair()
        window.contentView!.addSubview(original)
        window.contentView!.addSubview(current)
        var comparisons = 0
        for data: Data? in [nil, Data(), samples()] {
            current.waveform = data.map { WaveformCurrent.AudioWaveform(samples: $0, peak: 31) }
            original.waveform = data.map { WaveformOriginal.AudioWaveform(samples: $0, peak: 31) }
            for size in [CGSize(width: 3, height: 20), CGSize(width: 99.5, height: 20), CGSize(width: 170, height: 29)] {
                current.setFrameSize(size)
                original.setFrameSize(size)
                current.layout()
                original.layout()
                for clip in [CGSize(width: 0, height: size.height), CGSize(width: size.width * 0.37, height: size.height), size, CGSize(width: size.width * 1.2, height: size.height / 2)] {
                    current.testSetClip(clip, animated: false)
                    original.testSetClip(clip, animated: false)
                    XCTAssertEqual(current.testClipLayer.convert(current.testForegroundLayer.bounds, from: current.testForegroundLayer), original.testClipLayer.convert(original.testForegroundLayer.bounds, from: original.testForegroundLayer))
                    for reveal: CGFloat in [0, 0.4, 1] {
                        current.testProgress(reveal)
                        original.testProgress(reveal)
                        for scale: CGFloat in [1, 2, 3] {
                            XCTAssertEqual(try render(current, scale: scale), try render(original, scale: scale), "size=\(size) clip=\(clip) reveal=\(reveal) scale=\(scale)")
                            comparisons += 1
                        }
                    }
                }
            }
        }
        XCTAssertEqual(comparisons, 324)
    }

    func testClipRemainsIndependentOfParentLayoutAndNegativeSizeIsEmpty() throws {
        let window = window()
        defer { window.close() }
        let (current, original) = pair()
        window.contentView!.addSubview(current)
        window.contentView!.addSubview(original)
        current.testSetClip(CGSize(width: 37.5, height: 12), animated: false)
        original.testSetClip(CGSize(width: 37.5, height: 12), animated: false)
        for size in [CGSize(width: 200, height: 31), CGSize(width: 8, height: 20), CGSize(width: 170, height: 20)] {
            current.setFrameSize(size)
            original.setFrameSize(size)
            current.layout()
            original.layout()
            XCTAssertEqual(current.testClipLayer.bounds.size, CGSize(width: 37.5, height: 12))
            XCTAssertEqual(current.testForegroundLayer.frame, original.testForegroundLayer.frame)
            let fresh = WaveformOriginal.AudioWaveformView(frame: CGRect(origin: original.frame.origin, size: size))
            fresh.waveform = WaveformOriginal.AudioWaveform(samples: samples(), peak: 31)
            fresh.set(foregroundColor: .red, backgroundColor: .blue)
            fresh.layout()
            fresh.testSetClip(CGSize(width: 37.5, height: 12), animated: false)
            window.contentView!.addSubview(fresh)
            let expected = try render(fresh, scale: 2)
            XCTAssertEqual(try render(current, scale: 2), expected, "Layer resize size=\(size), clip=\(current.testClipLayer.frame)")
            XCTAssertEqual(try render(original, scale: 2), expected, "Native resize size=\(size), clip=\(original.testClipLayer.frame)")
            fresh.removeFromSuperview()
        }
        current.testSetClip(CGSize(width: -4, height: -2), animated: false)
        original.foregroundClipingView.setFrameSize(CGSize(width: -4, height: -2))
        XCTAssertEqual(current.testClipLayer.bounds.size, .zero)
        XCTAssertEqual(try render(current, scale: 2), try render(original, scale: 2))
    }

    func testAnimationParametersRepeatedTargetsAndImmediateCancellation() throws {
        let (current, original) = pair()
        for target in [CGSize(width: 80, height: 20), CGSize(width: 120, height: 20), CGSize(width: 10, height: 13)] {
            current.testClipLayer.removeAllAnimations()
            original.testClipLayer.removeAllAnimations()
            let before = current.testClipLayer.bounds
            current.testSetClip(target, animated: true)
            original.testSetClip(target, animated: true)
            let actual = try XCTUnwrap(current.testClipLayer.animation(forKey: "bounds") as? CABasicAnimation)
            let expected = try XCTUnwrap(original.testClipLayer.animation(forKey: "bounds") as? CABasicAnimation)
            XCTAssertEqual((actual.fromValue as? NSValue)?.rectValue, before)
            XCTAssertEqual((actual.fromValue as? NSValue)?.rectValue, (expected.fromValue as? NSValue)?.rectValue)
            XCTAssertEqual((actual.toValue as? NSValue)?.rectValue, (expected.toValue as? NSValue)?.rectValue)
            XCTAssertEqual(actual.duration, expected.duration)
            XCTAssertEqual(actual.duration, 0.2)
            XCTAssertEqual(actual.fillMode, expected.fillMode)
            XCTAssertEqual(actual.isRemovedOnCompletion, expected.isRemovedOnCompletion)
            let actualTiming = try XCTUnwrap(actual.timingFunction)
            let expectedTiming = try XCTUnwrap(expected.timingFunction)
            for index in 0...3 {
                var a = [Float](repeating: 0, count: 2)
                var b = [Float](repeating: 0, count: 2)
                a.withUnsafeMutableBufferPointer { actualTiming.getControlPoint(at: index, values: $0.baseAddress!) }
                b.withUnsafeMutableBufferPointer { expectedTiming.getControlPoint(at: index, values: $0.baseAddress!) }
                XCTAssertEqual(a, b)
            }
            XCTAssertEqual(current.testClipLayer.bounds.size, target)
            current.testSetClip(target, animated: true)
            let repeated = try XCTUnwrap(current.testClipLayer.animation(forKey: "bounds") as? CABasicAnimation)
            XCTAssertEqual((repeated.fromValue as? NSValue)?.rectValue, (actual.fromValue as? NSValue)?.rectValue)
            current.testSetClip(target, animated: false)
            original.testSetClip(target, animated: false)
            XCTAssertNil(current.testClipLayer.animation(forKey: "bounds"))
            XCTAssertNotNil(original.testClipLayer.animation(forKey: "bounds"))
            XCTAssertEqual(current.testClipLayer.bounds.size, target)
        }
        current.testSetClip(CGSize(width: 150, height: 20), animated: true)
        current.testSetClip(CGSize(width: 30, height: 20), animated: false)
        XCTAssertNil(current.testClipLayer.animation(forKey: "bounds"))
        XCTAssertEqual(current.testClipLayer.bounds.size, CGSize(width: 30, height: 20))
    }

    func testAttachedRetargetUsesPresentationAndCompletesAfterReattachment() throws {
        let window = window()
        defer { window.close() }
        let (current, original) = pair()
        window.contentView!.addSubview(current)
        window.contentView!.addSubview(original)
        window.orderFront(nil)
        window.displayIfNeeded()
        CATransaction.flush()
        let ready = expectation(description: "attached layers commit")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) { ready.fulfill() }
        wait(for: [ready], timeout: 3)
        for layer in [current.testClipLayer, original.testClipLayer] {
            let animation = CABasicAnimation(keyPath: "bounds")
            animation.fromValue = NSValue(rect: CGRect(x: 0, y: 0, width: 170, height: 20))
            animation.toValue = NSValue(rect: CGRect(x: 0, y: 0, width: 20, height: 20))
            animation.duration = 10
            animation.speed = 0
            animation.timeOffset = 4
            animation.fillMode = .both
            animation.isRemovedOnCompletion = false
            layer.bounds.size = CGSize(width: 20, height: 20)
            layer.add(animation, forKey: "bounds")
        }
        CATransaction.flush()
        let presented = expectation(description: "paused progress is presented")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) { presented.fulfill() }
        wait(for: [presented], timeout: 3)
        let visible = try XCTUnwrap(current.testClipLayer.presentation()).bounds
        let baselineVisible = try XCTUnwrap(original.testClipLayer.presentation()).bounds
        XCTAssertGreaterThan(visible.width, 20)
        XCTAssertLessThan(visible.width, 170)
        XCTAssertEqual(visible.size, baselineVisible.size)
        current.testSetClip(CGSize(width: 135, height: 20), animated: true)
        original.testSetClip(CGSize(width: 135, height: 20), animated: true)
        let actual = try XCTUnwrap(current.testClipLayer.animation(forKey: "bounds") as? CABasicAnimation)
        let expected = try XCTUnwrap(original.testClipLayer.animation(forKey: "bounds") as? CABasicAnimation)
        XCTAssertEqual((actual.fromValue as? NSValue)?.rectValue.size, visible.size)
        XCTAssertEqual((actual.fromValue as? NSValue)?.rectValue.size, (expected.fromValue as? NSValue)?.rectValue.size)
        current.removeFromSuperview()
        original.removeFromSuperview()
        window.contentView!.addSubview(current)
        window.contentView!.addSubview(original)
        current.setFrameSize(CGSize(width: 200, height: 25))
        original.setFrameSize(CGSize(width: 200, height: 25))
        current.layout()
        original.layout()
        CATransaction.flush()
        let completed = expectation(description: "retargeted progress completes")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { completed.fulfill() }
        wait(for: [completed], timeout: 3)
        XCTAssertEqual(current.testClipLayer.bounds.size, CGSize(width: 135, height: 20))
        XCTAssertEqual(try render(current, scale: 2), try render(original, scale: 2))
        if let presentation = current.testClipLayer.presentation() {
            XCTAssertEqual(presentation.bounds, current.testClipLayer.bounds)
        }
    }

    func testRetargetToPausedPresentationCancelsPreviousEndpoint() throws {
        let window = window()
        defer { window.close() }
        let (current, original) = pair()
        window.contentView!.addSubview(current)
        window.contentView!.addSubview(original)
        window.orderFront(nil)
        window.displayIfNeeded()
        CATransaction.flush()
        let ready = expectation(description: "layers attach before paused retarget")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) { ready.fulfill() }
        wait(for: [ready], timeout: 3)
        for layer in [current.testClipLayer, original.testClipLayer] {
            let animation = CABasicAnimation(keyPath: "bounds")
            animation.fromValue = NSValue(rect: CGRect(x: 0, y: 0, width: 170, height: 20))
            animation.toValue = NSValue(rect: CGRect(x: 0, y: 0, width: 20, height: 20))
            animation.duration = 10
            animation.speed = 0
            animation.timeOffset = 4
            animation.fillMode = .both
            animation.isRemovedOnCompletion = false
            layer.bounds.size = CGSize(width: 20, height: 20)
            layer.add(animation, forKey: "bounds")
        }
        CATransaction.flush()
        let presented = expectation(description: "paused clipping has an intermediate size")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) { presented.fulfill() }
        wait(for: [presented], timeout: 3)
        let visible = try XCTUnwrap(current.testClipLayer.presentation()).bounds
        let originalVisible = try XCTUnwrap(original.testClipLayer.presentation()).bounds
        XCTAssertGreaterThan(visible.width, 20)
        XCTAssertLessThan(visible.width, 170)
        XCTAssertEqual(visible, originalVisible)
        current.testSetClip(visible.size, animated: true)
        original.testSetClip(originalVisible.size, animated: true)
        XCTAssertEqual(current.testClipLayer.bounds, visible)
        XCTAssertNil(current.testClipLayer.animation(forKey: "bounds"))
        let stale = try XCTUnwrap(original.testClipLayer.animation(forKey: "bounds") as? CABasicAnimation)
        XCTAssertEqual((stale.toValue as? NSValue)?.rectValue.size, CGSize(width: 20, height: 20))
        CATransaction.flush()
        let committed = expectation(description: "visible target remains committed")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) { committed.fulfill() }
        wait(for: [committed], timeout: 3)
        XCTAssertEqual(try XCTUnwrap(current.testClipLayer.presentation()).bounds, visible)
        XCTAssertNil(current.testClipLayer.animation(forKey: "bounds"))
    }

    func testHitTestingForwardsEventsAndPreservesWaveformCoordinates() throws {
        let window = window()
        defer { window.close() }
        let parent = ClipEventParent(frame: CGRect(x: 0, y: 0, width: 320, height: 140))
        window.contentView = parent
        let (current, original) = pair()
        for fraction: CGFloat in [0, 0.4, 1] {
            current.testSetClip(CGSize(width: 170 * fraction, height: 20), animated: false)
            original.testSetClip(CGSize(width: 170 * fraction, height: 20), animated: false)
            var histories: [[NSEvent.EventType]] = []
            var locations: [[CGPoint]] = []
            for view: NSView in [original, current] {
                parent.addSubview(view)
                parent.waveform = view
                parent.received = []
                parent.points = []
                for x: CGFloat in [5, 90, 165] {
                    let point = CGPoint(x: x, y: 9)
                    let hit = try XCTUnwrap(parent.hitTest(view.convert(point, to: parent.superview)))
                    XCTAssertTrue(hit === view || hit.isDescendant(of: view))
                    for type: NSEvent.EventType in [.leftMouseDown, .leftMouseDragged, .leftMouseUp, .rightMouseDown, .rightMouseUp] {
                        let local = type == .leftMouseDragged ? CGPoint(x: 190, y: 30) : point
                        let event = try XCTUnwrap(NSEvent.mouseEvent(with: type, location: view.convert(local, to: nil), modifierFlags: [], timestamp: 1, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
                        switch type {
                        case .leftMouseDown: hit.mouseDown(with: event)
                        case .leftMouseDragged: hit.mouseDragged(with: event)
                        case .leftMouseUp: hit.mouseUp(with: event)
                        case .rightMouseDown: hit.rightMouseDown(with: event)
                        case .rightMouseUp: hit.rightMouseUp(with: event)
                        default: XCTFail("Unexpected mouse event")
                        }
                    }
                    let scroll = try XCTUnwrap(CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: 12, wheel2: 0, wheel3: 0))
                    hit.scrollWheel(with: try XCTUnwrap(NSEvent(cgEvent: scroll)))
                    XCTAssertFalse(hit.isAccessibilityElement())
                    XCTAssertEqual(hit.acceptsFirstMouse(for: nil), view.acceptsFirstMouse(for: nil))
                }
                XCTAssertEqual(parent.received.count, 18)
                histories.append(parent.received)
                locations.append(parent.points)
                view.removeFromSuperview()
            }
            XCTAssertEqual(histories[0], histories[1])
            XCTAssertEqual(locations[0], locations[1])
            XCTAssertTrue(locations[1].contains(CGPoint(x: 190, y: 30)))
        }
    }

    func testLayerOwnershipViewCountAndRemovalReleaseResources() throws {
        let window = window()
        defer { window.close() }
        weak var weakView: NSView?
        weak var weakClip: CALayer?
        weak var weakForeground: CALayer?
        weak var weakWaveform: WaveformCurrent.AudioWaveform?
        autoreleasepool {
            let (current, original) = pair()
            XCTAssertEqual(current.subviews.count, 0)
            XCTAssertEqual(original.subviews.count, 1)
            XCTAssertEqual(waveformOwnedLayerCount(current), 4)
            XCTAssertEqual(waveformOwnedLayerCount(original), 4)
            XCTAssertEqual(current.layer?.sublayers?.count, 2)
            XCTAssertTrue(current.layer?.sublayers?.first === current.testBackgroundLayer)
            XCTAssertTrue(current.layer?.sublayers?.last === current.testClipLayer)
            XCTAssertTrue(current.testForegroundLayer.superlayer === current.testClipLayer)
            XCTAssertTrue(current.testClipLayer.masksToBounds)
            window.contentView!.addSubview(current)
            window.contentView!.addSubview(original)
            window.displayIfNeeded()
            XCTAssertEqual(waveformOwnedLayerCount(current), 4)
            XCTAssertEqual(waveformOwnedLayerCount(original), 4)
            current.testSetClip(CGSize(width: 30, height: 20), animated: true)
            weakView = current
            weakClip = current.testClipLayer
            weakForeground = current.testForegroundLayer
            weakWaveform = current.waveform
            current.removeFromSuperview()
            original.removeFromSuperview()
        }
        CATransaction.flush()
        let released = expectation(description: "removed animation releases layers")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { released.fulfill() }
        wait(for: [released], timeout: 3)
        XCTAssertNil(weakView)
        XCTAssertNil(weakClip)
        XCTAssertNil(weakForeground)
        XCTAssertNil(weakWaveform)
    }
}
