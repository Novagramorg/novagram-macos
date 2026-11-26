import XCTest
import AppKit
import QuartzCore
@testable import TGUIKit

final class ModalMorphTransitionTests: XCTestCase {
    private var savedReduceMotion: (() -> Bool)!

    override func setUp() {
        super.setUp()
        TGUIKitTestBootstrap.install()
        savedReduceMotion = ModalMorphTransition.reduceMotion
        ModalMorphTransition.reduceMotion = { false }
    }

    override func tearDown() {
        ModalMorphTransition.reduceMotion = savedReduceMotion
        super.tearDown()
    }

    private let control = NSMakeRect(40, 40, 40, 40)
    private let modal = NSMakeRect(300, 200, 420, 520)

    private func dummyImage() -> CGImage {
        let ctx = CGContext(data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(NSColor.red.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        return ctx.makeImage()!
    }

    func testGlassButtonUsesItsConfiguredRadius() {
        let button = Control(frame: NSMakeRect(0, 0, 100, 60))
        let glass = LiquidGlassView(frame: button.bounds, cornerRadius: 20)
        button.addSubview(glass)
        XCTAssertEqual(morphControlShape(button).radius, 20)
        XCTAssertEqual(morphControlShape(button).corners, morphAllCorners)
        glass.cornerRadius = 12
        XCTAssertEqual(morphControlShape(button).radius, 12)
        glass.cornerRadius = 50
        XCTAssertEqual(morphControlShape(button).radius, 30)
    }

    func testSmallDecorationsDoNotOverrideButtonShape() {
        let button = Control(frame: NSMakeRect(0, 0, 100, 60))
        button.layer?.cornerRadius = 20
        button.addSubview(LiquidGlassView(frame: NSMakeRect(0, 0, 16, 16), cornerRadius: 8))
        XCTAssertEqual(morphControlShape(button).radius, 20)
        let circle = LiquidGlassView(frame: NSMakeRect(0, 0, 36, 36), cornerRadius: 18)
        XCTAssertEqual(morphControlShape(circle).radius, 18)
    }

    func testClosingGeometrySettlesWithoutCrossingTheControl() {
        for spring in [ModalMorphTransition.Spring.closePosition, .closeWidth, .closeHeight] {
            for (from, to): (CGFloat, CGFloat) in [(520, 60), (40, 300)] {
                let channel = ModalMorphTransition.Channel(from: from, to: to, spring: spring, tolerance: ModalMorphTransition.geometryTolerance)
                var previousDistance = abs(from - to)
                for step in 0...180 {
                    let value = channel.value(at: Double(step) / 120)
                    XCTAssertGreaterThanOrEqual(value, min(from, to))
                    XCTAssertLessThanOrEqual(value, max(from, to))
                    let distance = abs(value - to)
                    XCTAssertLessThanOrEqual(distance, previousDistance + 0.00001)
                    previousDistance = distance
                }
                XCTAssertLessThan(previousDistance, ModalMorphTransition.geometryTolerance)
            }
        }
    }

    func testCloseEndsAtExactButtonShape() throws {
        let window = NSWindow(contentRect: NSMakeRect(0, 0, 800, 800), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let host = View(frame: NSMakeRect(0, 0, 800, 800))
        window.contentView?.addSubview(host)
        let button = NSMakeRect(40, 40, 100, 60)
        let transition = ModalMorphTransition.close(host: host, realView: nil, liveContent: nil, controlImage: dummyImage(), modalImage: dummyImage(), backgroundColor: NSColor.black.cgColor, cornerRadius: 30, controlCornerRadius: 20, to: button, from: modal, completion: {})
        let bubble = try XCTUnwrap(host.subviews.last?.layer)
        let bounds = try XCTUnwrap(bubble.animation(forKey: "modalMorph.bounds") as? CAKeyframeAnimation)
        let corners = try XCTUnwrap(bubble.animation(forKey: "modalMorph.cornerRadius") as? CAKeyframeAnimation)
        XCTAssertEqual((bounds.values?.last as? NSValue)?.rectValue.size, button.size)
        XCTAssertEqual((corners.values?.last as? NSNumber)?.doubleValue, 20)
        XCTAssertFalse(bounds.isRemovedOnCompletion)
        XCTAssertEqual(bounds.fillMode, .forwards)
        transition?.cancel()
    }

    func testChannelStartsAtFromAndSettlesOnTarget() {
        let channel = ModalMorphTransition.Channel(from: 40, to: 420, spring: .openWidth, tolerance: ModalMorphTransition.geometryTolerance)
        XCTAssertEqual(channel.value(at: 0), 40, accuracy: 0.5, "a channel starts at its from value")
        XCTAssertEqual(channel.value(at: ModalMorphTransition.maximumDuration), 420, accuracy: 1.0, "and settles on its to value")
    }

    func testUnderdampedSpringOvershoots() {
        // An underdamped spring's remaining must dip below zero (the value bounces past the target).
        var sawNegative = false
        var t = 0.0
        while t <= 1 {
            if ModalMorphTransition.Spring.openWidth.remaining(at: t) < -0.001 { sawNegative = true; break }
            t += 0.005
        }
        XCTAssertTrue(sawNegative, "open width spring should overshoot (bounce)")
    }

    func testCriticallyDampedSpringNeverOvershoots() {
        var t = 0.0
        while t <= 1.5 {
            XCTAssertGreaterThanOrEqual(ModalMorphTransition.Spring.openFade.remaining(at: t), -1e-6, "critically damped fade must not overshoot")
            t += 0.01
        }
    }

    func testSettlingTimeIsPositiveAndBounded() {
        let channel = ModalMorphTransition.Channel(from: 0, to: 1, spring: .openPosition, tolerance: ModalMorphTransition.unitTolerance)
        let settling = channel.settlingTime
        XCTAssertGreaterThan(settling, 0.1, "the morph takes a visible amount of time")
        XCTAssertLessThanOrEqual(settling, ModalMorphTransition.maximumDuration, "but is bounded")
    }

    func testSmoothstepClamps() {
        XCTAssertEqual(ModalMorphTransition.smoothstep(0, 1, -5), 0)
        XCTAssertEqual(ModalMorphTransition.smoothstep(0, 1, 5), 1)
        XCTAssertEqual(ModalMorphTransition.smoothstep(0, 1, 0.5), 0.5, accuracy: 0.0001)
    }

    func testReduceMotionSkipsTheMorphAndCallsCompletion() {
        ModalMorphTransition.reduceMotion = { true }
        let window = NSWindow(contentRect: NSMakeRect(0, 0, 800, 800), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let host = View(frame: NSMakeRect(0, 0, 800, 800))
        window.contentView?.addSubview(host)
        var completed = false
        let transition = ModalMorphTransition.open(host: host, realView: nil, liveContent: nil, controlImage: nil, modalImage: dummyImage(), backgroundColor: nil, cornerRadius: 10, controlCornerRadius: 20, from: control, to: modal, completion: { completed = true })
        XCTAssertNil(transition, "reduce motion must skip the morph")
        XCTAssertTrue(completed, "completion still fires so the modal appears")
    }

    func testOpenAddsBubbleHidesRealViewAndRestoresOnCancel() {
        let window = NSWindow(contentRect: NSMakeRect(0, 0, 800, 800), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let host = View(frame: NSMakeRect(0, 0, 800, 800))
        window.contentView?.addSubview(host)
        let realView = View(frame: modal)
        host.addSubview(realView)
        let transition = ModalMorphTransition.open(host: host, realView: realView, liveContent: nil, controlImage: dummyImage(), modalImage: dummyImage(), backgroundColor: nil, cornerRadius: 10, controlCornerRadius: 20, from: control, to: modal, completion: {})
        XCTAssertNotNil(transition)
        XCTAssertTrue(realView.isHidden, "the real modal is hidden while the morph plays")
        XCTAssertEqual(host.subviews.count, 3, "a bubble and a shadow view are added above the real view")
        let bubbleView = host.subviews.last
        XCTAssertNotNil(bubbleView?.layer?.animation(forKey: "modalMorph.position"))
        transition?.cancel()
        XCTAssertFalse(realView.isHidden, "the real modal is restored after the morph")
        XCTAssertEqual(host.subviews.count, 1, "the bubble and shadow views are removed after the morph")
    }

    func testGrowingLiveModalKeepsHeaderVisibleDuringMorph() throws {
        let window = NSWindow(contentRect: NSMakeRect(0, 0, 1000, 1000), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let host = View(frame: NSMakeRect(0, 0, 1000, 1000))
        window.contentView = host
        let initial = NSMakeRect(300, 300, 380, 300)
        let expanded = NSMakeRect(300, 173, 380, 654)
        let realView = View(frame: initial)
        host.addSubview(realView)
        let content = View(frame: realView.bounds)
        realView.addSubview(content)
        let header = View(frame: NSMakeRect(0, 0, 380, 304))
        content.addSubview(header)
        let transition = try XCTUnwrap(ModalMorphTransition.open(host: host, realView: realView, liveContent: content, controlImage: dummyImage(), modalImage: nil, backgroundColor: NSColor.black.cgColor, cornerRadius: 20, controlCornerRadius: 20, from: control, to: initial, completion: {}))
        transition.retarget(to: expanded, contentSize: expanded.size)
        XCTAssertEqual(content.superview?.frame, expanded)
        XCTAssertTrue(content.visibleRect.contains(content.bounds))
        XCTAssertTrue(header.visibleRect.contains(header.bounds))
        XCTAssertNotNil(content.layer?.animation(forKey: "modalMorph.transform"))
        transition.retarget(to: initial, contentSize: initial.size)
        XCTAssertEqual(content.superview?.frame, initial)
        XCTAssertTrue(content.visibleRect.contains(content.bounds))
        transition.cancel()
        XCTAssertTrue(content.superview === realView)
        XCTAssertFalse(realView.isHidden)
    }
}
