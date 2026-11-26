import XCTest
import Cocoa
import TGUIKit
import AvatarUI
@testable import StoriesUI

final class StoryMorphSpringTests: XCTestCase {
    private func integrate(_ spring: StoryMorphSpring, x0: Double, v0: Double, until t: Double) -> (x: Double, v: Double) {
        let k = spring.omega * spring.omega
        let c = 2 * spring.damping * spring.omega
        func acceleration(_ x: Double, _ v: Double) -> Double {
            return -k * x - c * v
        }
        var x = x0
        var v = v0
        let dt = 1e-5
        var time = 0.0
        while time < t - dt / 2 {
            let k1x = v, k1v = acceleration(x, v)
            let k2x = v + 0.5 * dt * k1v, k2v = acceleration(x + 0.5 * dt * k1x, v + 0.5 * dt * k1v)
            let k3x = v + 0.5 * dt * k2v, k3v = acceleration(x + 0.5 * dt * k2x, v + 0.5 * dt * k2v)
            let k4x = v + dt * k3v, k4v = acceleration(x + dt * k3x, v + dt * k3v)
            x += dt / 6 * (k1x + 2 * k2x + 2 * k3x + k4x)
            v += dt / 6 * (k1v + 2 * k2v + 2 * k3v + k4v)
            time += dt
        }
        return (x, v)
    }

    func testAnalyticSolutionMatchesNumericalIntegration() {
        let springs: [StoryMorphSpring] = [.position, .width, .height, .roundness, .openness, .collapse, StoryMorphSpring(omega: 10, damping: 1.6)]
        for spring in springs {
            for (x0, v0) in [(100.0, 0.0), (-37.5, 800.0), (250.0, -1200.0), (0.0, 300.0)] {
                for t in [0.016, 0.05, 0.13, 0.31, 0.6] {
                    let analytic = spring.solve(t, displacement: x0, velocity: v0)
                    let numeric = self.integrate(spring, x0: x0, v0: v0, until: t)
                    XCTAssertEqual(analytic.x, numeric.x, accuracy: 1e-4, "x \(spring) x0=\(x0) v0=\(v0) t=\(t)")
                    XCTAssertEqual(analytic.v, numeric.v, accuracy: 1e-3, "v \(spring) x0=\(x0) v0=\(v0) t=\(t)")
                }
            }
        }
    }

    private func overshoot(_ spring: StoryMorphSpring) -> Double {
        var minimum = 1.0
        var t = 0.0
        while t < 2 {
            minimum = min(minimum, spring.solve(t, displacement: 1, velocity: 0).x)
            t += 0.0005
        }
        return -minimum
    }

    func testExpandSpringsBounceLikeAContextMenuAndCollapseLandsWithoutBounce() {
        XCTAssertGreaterThan(self.overshoot(.width), 0.01)
        XCTAssertLessThan(self.overshoot(.width), 0.05)
        XCTAssertGreaterThan(self.overshoot(.height), 0.01)
        XCTAssertLessThan(self.overshoot(.height), 0.05)
        XCTAssertLessThan(self.overshoot(.position), 0.012)
        XCTAssertEqual(self.overshoot(.openness), 0, accuracy: 1e-9)
        XCTAssertEqual(self.overshoot(.collapse), 0, accuracy: 1e-9)
    }

    func testSettlingTimeIsTheLastExcursionOutsideTolerance() {
        for spring in [StoryMorphSpring.width, .height, .collapse] {
            let settle = spring.settlingTime(displacement: 600, velocity: 0, tolerance: 0.2)
            XCTAssertGreaterThan(settle, 0.1)
            var t = settle
            while t < settle + 1.5 {
                XCTAssertLessThanOrEqual(abs(spring.solve(t, displacement: 600, velocity: 0).x), 0.2 + 1e-9)
                t += 0.0005
            }
        }
        XCTAssertEqual(StoryMorphSpring.collapse.settlingTime(displacement: 0.1, velocity: 0, tolerance: 0.2), 0)
    }
}

final class StoryMorphPlanTests: XCTestCase {
    let avatar = StoryMorphShape(rect: CGRect(x: 32, y: 410, width: 50, height: 50), cornerRadius: 25)
    let story = StoryMorphShape(rect: CGRect(x: 397.5, y: 20, width: 405, height: 720), cornerRadius: 10)
    let contentSize = CGSize(width: 405, height: 720)

    private func openTimeline(snapshot: Bool = true) -> StoryMorphTimeline {
        let plan = StoryMorphPlan(from: self.avatar.state(openness: 0), to: self.story.state(openness: 1), springs: .expand)
        return StoryMorphTimeline(plan: plan, contentSize: self.contentSize, fades: .opening(hasSnapshot: snapshot))
    }

    func testOpenStartsExactlyOnTheSourceAndEndsExactlyOnTheStory() {
        let timeline = self.openTimeline()
        let first = timeline.samples[0]
        let last = timeline.samples[timeline.samples.count - 1]
        XCTAssertEqual(first.time, 0)
        XCTAssertEqual(first.geometry.bubble, self.avatar.rect)
        XCTAssertEqual(first.geometry.cornerRadius, 25, accuracy: 1e-9)
        XCTAssertEqual(last.time, timeline.plan.duration, accuracy: 1e-12)
        XCTAssertEqual(last.geometry.bubble, self.story.rect)
        XCTAssertEqual(last.geometry.cornerRadius, 10, accuracy: 1e-6)
        XCTAssertEqual(last.geometry.contentScale, 1, accuracy: 1e-9)
        XCTAssertEqual(last.geometry.contentFrame, CGRect(origin: .zero, size: self.contentSize))
        XCTAssertEqual(timeline.keyTimes.first?.doubleValue, 0)
        XCTAssertEqual(timeline.keyTimes.last?.doubleValue ?? 0, 1, accuracy: 1e-12)
    }

    func testDurationsStayInteractive() {
        let open = self.openTimeline().plan.duration
        XCTAssertGreaterThan(open, 0.35)
        XCTAssertLessThan(open, 0.75)
        let close = StoryMorphPlan(from: self.story.state(openness: 1), to: self.avatar.state(openness: 0), springs: .collapse).duration
        XCTAssertGreaterThan(close, 0.25)
        XCTAssertLessThan(close, 0.5)
    }

    func testContentAlwaysFillsTheBubbleWithoutDistortion() {
        for timeline in [self.openTimeline(), StoryMorphTimeline(plan: StoryMorphPlan(from: self.story.state(openness: 1), to: self.avatar.state(openness: 0), springs: .collapse), contentSize: self.contentSize, fades: .opening(hasSnapshot: true))] {
            for sample in timeline.samples {
                let geometry = sample.geometry
                let bounds = CGRect(origin: .zero, size: geometry.bubble.size)
                XCTAssertTrue(geometry.contentFrame.insetBy(dx: -1e-6, dy: -1e-6).contains(bounds), "gap at t=\(sample.time)")
                XCTAssertEqual(geometry.contentFrame.width / self.contentSize.width, geometry.contentFrame.height / self.contentSize.height, accuracy: 1e-9)
                XCTAssertEqual(geometry.contentFrame.midX, bounds.midX, accuracy: 1e-9)
                XCTAssertEqual(geometry.contentFrame.midY, bounds.midY, accuracy: 1e-9)
                XCTAssertGreaterThanOrEqual(geometry.cornerRadius, 0)
                XCTAssertLessThanOrEqual(geometry.cornerRadius, min(geometry.bubble.width, geometry.bubble.height) / 2 + 1e-9)
                XCTAssertTrue(geometry.snapshotFrame.insetBy(dx: -1e-6, dy: -1e-6).contains(bounds))
            }
        }
    }

    func testBubbleStaysRoundWhileItGrowsThenSettlesWithASmallBounce() {
        let timeline = self.openTimeline()
        let story = self.story.rect
        var maxHeight: CGFloat = 0
        var maxWidth: CGFloat = 0
        var checkedHalfway = false
        for sample in timeline.samples {
            let bubble = sample.geometry.bubble
            maxHeight = max(maxHeight, bubble.height)
            maxWidth = max(maxWidth, bubble.width)
            let progress = (bubble.height - 50) / (story.height - 50)
            if !checkedHalfway, progress >= 0.5 {
                checkedHalfway = true
                let linearRadius = 25 + (10 - 25) * progress
                XCTAssertGreaterThan(sample.geometry.cornerRadius, linearRadius * 2, "the shape should still read as a bubble halfway")
            }
        }
        XCTAssertTrue(checkedHalfway)
        XCTAssertGreaterThan(maxHeight, story.height + 2)
        XCTAssertLessThan(maxHeight, story.height * 1.05)
        XCTAssertGreaterThan(maxWidth, story.width + 2)
        XCTAssertLessThan(maxWidth, story.width * 1.05)
    }

    func testSamplesHaveNoJumpsOrKinks() {
        let timeline = self.openTimeline()
        let samples = timeline.samples
        let travel = max(abs(self.story.rect.midX - self.avatar.rect.midX), abs(self.story.rect.height - self.avatar.rect.height))
        for i in 1 ..< samples.count {
            let a = samples[i - 1].geometry.bubble
            let b = samples[i].geometry.bubble
            let step = max(abs(b.midX - a.midX), abs(b.midY - a.midY), abs(b.width - a.width), abs(b.height - a.height))
            XCTAssertLessThan(step, travel * 0.12, "teleport between samples \(i - 1) and \(i)")
            if i >= 2, i < samples.count - 1 {
                let p = samples[i - 2].geometry.bubble
                let curvature = abs(b.height - 2 * a.height + p.height)
                XCTAssertLessThan(curvature, travel * 0.03, "kink at sample \(i - 1)")
            }
        }
    }

    func testPlanSettlesAndVelocityIsTheDerivative() {
        let plan = self.openTimeline().plan
        XCTAssertEqual(plan.state(at: 0), plan.from)
        XCTAssertEqual(plan.state(at: plan.duration), plan.to)
        var t = plan.duration * 0.98
        while t < plan.duration {
            let state = plan.state(at: t)
            XCTAssertEqual(state.size.height, plan.to.size.height, accuracy: 0.25)
            XCTAssertEqual(state.center.x, plan.to.center.x, accuracy: 0.25)
            t += 0.001
        }
        for t in stride(from: 0.01, to: plan.duration - 0.01, by: 0.037) {
            let h = 1e-6
            let numeric = (plan.state(at: t + h).size.height - plan.state(at: t - h).size.height) / (2 * h)
            XCTAssertEqual(plan.velocity(at: t).size.height, numeric, accuracy: abs(numeric) * 1e-4 + 1e-2)
        }
    }

    func testInterruptedOpenReversesWithContinuousPositionAndVelocity() {
        let open = self.openTimeline().plan
        for interruptAt in [0.02, 0.08, 0.16, 0.3] {
            let state = open.state(at: interruptAt)
            let velocity = open.velocity(at: interruptAt)
            let close = StoryMorphPlan(from: state, to: self.avatar.state(openness: 0), velocity: velocity, springs: .collapse)
            XCTAssertEqual(close.state(at: 0), state)
            XCTAssertEqual(close.velocity(at: 0), velocity)
            let dt = 1.0 / 2000.0
            let after = close.state(at: dt)
            let spring = StoryMorphSprings.collapse.position
            func predicted(_ x: CGFloat, _ v: CGFloat, _ target: CGFloat) -> CGFloat {
                let acceleration = -spring.omega * spring.omega * Double(x - target) - 2 * spring.damping * spring.omega * Double(v)
                return x + CGFloat(Double(v) * dt + 0.5 * acceleration * dt * dt)
            }
            XCTAssertEqual(after.center.x, predicted(state.center.x, velocity.center.x, self.avatar.rect.midX), accuracy: 0.01)
            XCTAssertEqual(after.center.y, predicted(state.center.y, velocity.center.y, self.avatar.rect.midY), accuracy: 0.01)
            XCTAssertEqual(close.state(at: close.duration).rect, self.avatar.rect)
            XCTAssertLessThan(close.duration, 0.6)
        }
    }

    func testDegenerateInputsDoNotProduceBrokenTimelines() {
        let same = StoryMorphPlan(from: self.story.state(openness: 1), to: self.story.state(openness: 1), springs: .collapse)
        XCTAssertEqual(same.duration, 0)
        let timeline = StoryMorphTimeline(plan: same, contentSize: self.contentSize, fades: .opening(hasSnapshot: false))
        XCTAssertEqual(timeline.samples.count, 1)
        XCTAssertEqual(timeline.keyTimes, [0])

        XCTAssertFalse(StoryMorphShape(rect: .zero, cornerRadius: 0).isValid)
        XCTAssertFalse(StoryMorphShape(rect: CGRect(x: CGFloat.nan, y: 0, width: 10, height: 10), cornerRadius: 0).isValid)
        XCTAssertFalse(StoryMorphShape(rect: CGRect(x: 0, y: 0, width: 10, height: CGFloat.infinity), cornerRadius: 0).isValid)

        let tiny = StoryMorphGeometry(state: StoryMorphState(center: .zero, size: CGSize(width: -5, height: 0), roundness: 3, openness: 0), contentSize: self.contentSize)
        XCTAssertEqual(tiny.bubble.size, CGSize(width: 1, height: 1))
        XCTAssertEqual(tiny.cornerRadius, 0.5)
        let noContent = StoryMorphGeometry(state: self.story.state(openness: 1), contentSize: .zero)
        XCTAssertEqual(noContent.contentScale, 1)
    }
}

final class StoryMorphFadeTests: XCTestCase {
    func testOpeningWithAvatarSnapshotCrossfadesTheAvatarIntoTheStory() {
        let fades = StoryMorphFades.opening(hasSnapshot: true)
        XCTAssertEqual(fades.values(openness: 0), .init(snapshot: 1, chrome: 0, bubble: 1, source: 0))
        XCTAssertGreaterThan(fades.values(openness: 0.15).snapshot, 0.6)
        XCTAssertEqual(fades.values(openness: 0.42).snapshot, 0)
        XCTAssertEqual(fades.values(openness: 1), .init(snapshot: 0, chrome: 1, bubble: 1, source: 0))
        XCTAssertEqual(fades.values(openness: 1.4), fades.values(openness: 1))
        XCTAssertEqual(fades.values(openness: -0.2), fades.values(openness: 0))
    }

    func testOpeningWithoutSnapshotCrossfadesTheRealSource() {
        let fades = StoryMorphFades.opening(hasSnapshot: false)
        XCTAssertEqual(fades.values(openness: 0), .init(snapshot: 0, chrome: 0, bubble: 0, source: 1))
        XCTAssertEqual(fades.values(openness: 1), .init(snapshot: 0, chrome: 1, bubble: 1, source: 0))
    }

    func testClosingStartsExactlyWhereTheInterruptedOpeningWas() {
        for openSnapshot in [true, false] {
            for closeSnapshot in [true, false] {
                for hasDestination in [true, false] {
                    for q in stride(from: CGFloat(0.02), through: 1.0, by: 0.07) {
                        let current = StoryMorphFades.opening(hasSnapshot: openSnapshot).values(openness: q)
                        let closing = StoryMorphFades.closing(hasSnapshot: closeSnapshot && hasDestination, hasDestination: hasDestination, startOpenness: q, start: current)
                        let start = closing.values(openness: q)
                        XCTAssertEqual(start.chrome, current.chrome, accuracy: 1e-9)
                        XCTAssertEqual(start.bubble, current.bubble, accuracy: 1e-9)
                        if closeSnapshot && hasDestination || !hasDestination {
                            XCTAssertEqual(start.snapshot, current.snapshot, accuracy: 1e-9)
                        }
                        if hasDestination && !closeSnapshot {
                            XCTAssertEqual(start.source, current.source, accuracy: 1e-9)
                        }
                        let end = closing.values(openness: 0)
                        XCTAssertEqual(end.chrome, 0, accuracy: 1e-9)
                        if !hasDestination {
                            XCTAssertEqual(end.bubble, 0, accuracy: 1e-9)
                        } else if closeSnapshot {
                            XCTAssertEqual(end.snapshot, 1, accuracy: 1e-9)
                            XCTAssertEqual(end.bubble, 1, accuracy: 1e-9)
                        } else {
                            XCTAssertEqual(end.bubble, 0, accuracy: 1e-9)
                            XCTAssertEqual(end.source, 1, accuracy: 1e-9)
                        }
                    }
                }
            }
        }
    }

    func testClosingFromRestHidesChromeFirstAndRevealsTheAvatarLast() {
        let closing = StoryMorphFades.closing(hasSnapshot: true, hasDestination: true, startOpenness: 1, start: .init(snapshot: 0, chrome: 1, bubble: 1, source: 0))
        XCTAssertEqual(closing.values(openness: 0.7).chrome, 0)
        XCTAssertEqual(closing.values(openness: 0.5).snapshot, 0)
        XCTAssertGreaterThan(closing.values(openness: 0.2).snapshot, 0.3)
        XCTAssertEqual(closing.values(openness: 0).snapshot, 1)
    }
}

final class StoryMorphImageShapeTests: XCTestCase {
    static func image(side: Int, radius: CGFloat) -> CGImage {
        let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(NSColor.systemPink.cgColor)
        let rect = CGRect(x: 0, y: 0, width: side, height: side)
        context.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
        context.fillPath()
        return context.makeImage()!
    }

    func testDetectsCircleForumAndSquareShapes() {
        let display = CGSize(width: 50, height: 50)
        XCTAssertEqual(StoryMorphImageShape.cornerRadius(of: Self.image(side: 100, radius: 50), displaySize: display) ?? -1, 25, accuracy: 0.8)
        XCTAssertEqual(StoryMorphImageShape.cornerRadius(of: Self.image(side: 100, radius: 25), displaySize: display) ?? -1, 12.5, accuracy: 0.8)
        XCTAssertEqual(StoryMorphImageShape.cornerRadius(of: Self.image(side: 168, radius: 56), displaySize: CGSize(width: 56, height: 56)) ?? -1, 18.67, accuracy: 0.8)
        XCTAssertEqual(StoryMorphImageShape.cornerRadius(of: Self.image(side: 100, radius: 0), displaySize: display) ?? -1, 0, accuracy: 0.8)
    }

    func testTransparentImageHasNoShape() {
        let context = CGContext(data: nil, width: 10, height: 10, bitsPerComponent: 8, bytesPerRow: 40, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        XCTAssertNil(StoryMorphImageShape.cornerRadius(of: context.makeImage()!, displaySize: CGSize(width: 50, height: 50)))
    }
}

final class StoryMorphHoldTests: XCTestCase {
    func testHoldsAreReferenceCountedAndRestoreTheOriginalAlpha() {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 10, height: 10))
        view.wantsLayer = true
        view.alphaValue = 0.6
        let first = StoryMorphHold(view)
        XCTAssertEqual(view.alphaValue, 0)
        XCTAssertTrue(StoryMorphHold.isHeld(view))
        XCTAssertEqual(StoryMorphHold.originalAlpha(of: view), 0.6, accuracy: 1e-6)
        let second = StoryMorphHold(view)
        first.release()
        first.release()
        XCTAssertEqual(view.alphaValue, 0)
        second.release()
        XCTAssertEqual(view.alphaValue, 0.6, accuracy: 1e-6)
        XCTAssertFalse(StoryMorphHold.isHeld(view))
    }

    func testAStaleHoldNeverTouchesANewViewAtTheSameAddress() throws {
        var stale: StoryMorphHold?
        var address: ObjectIdentifier?
        autoreleasepool {
            let dying = NSView(frame: NSRect(x: 0, y: 0, width: 10, height: 10))
            dying.wantsLayer = true
            address = ObjectIdentifier(dying)
            stale = StoryMorphHold(dying)
        }
        var reused: NSView?
        var spare: [NSView] = []
        for _ in 0 ..< 2000 {
            let candidate = NSView(frame: NSRect(x: 0, y: 0, width: 10, height: 10))
            candidate.wantsLayer = true
            if ObjectIdentifier(candidate) == address {
                reused = candidate
                break
            }
            spare.append(candidate)
        }
        guard let fresh = reused else {
            stale?.release()
            throw XCTSkip("allocator did not reuse the address")
        }
        let hold = StoryMorphHold(fresh)
        XCTAssertEqual(fresh.alphaValue, 0)
        stale?.release()
        stale = nil
        XCTAssertEqual(fresh.alphaValue, 0)
        XCTAssertTrue(StoryMorphHold.isHeld(fresh))
        hold.release()
        XCTAssertEqual(fresh.alphaValue, 1)
        XCTAssertFalse(StoryMorphHold.isHeld(fresh))
        _ = spare
    }

    func testHoldingDuringAReleaseFadeCancelsTheFade() {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 10, height: 10))
        view.wantsLayer = true
        let first = StoryMorphHold(view)
        first.release(fadeDuration: 0.2)
        XCTAssertNotNil(view.layer?.animation(forKey: StoryMorphHold.fadeKey))
        let second = StoryMorphHold(view)
        XCTAssertNil(view.layer?.animation(forKey: StoryMorphHold.fadeKey), "a new hold must not keep fading the avatar in")
        XCTAssertEqual(view.alphaValue, 0)
        second.release()
        XCTAssertEqual(view.alphaValue, 1)
    }

    func testAbandonedHoldRestoresOnDeinit() {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 10, height: 10))
        view.wantsLayer = true
        do {
            _ = StoryMorphHold(view)
        }
        XCTAssertEqual(view.alphaValue, 1)
        XCTAssertFalse(StoryMorphHold.isHeld(view))
    }
}

final class StoryMorphTransitionTests: XCTestCase {
    private var window: NSWindow!
    private var home: View!
    private var content: View!
    private var media: View!
    private var chrome: View!

    private static let registerThemeImages: Void = {
        for name in ["Icon_SearchField", "Icon_SearchClear", "Icon_Quote", "Icon_Quote_Collapse", "Icon_Quote_Expand"] where NSImage(named: name) == nil {
            let image = NSImage(size: NSSize(width: 10, height: 10))
            image.lockFocus()
            NSColor.gray.setFill()
            NSRect(x: 0, y: 0, width: 10, height: 10).fill()
            image.unlockFocus()
            image.setName(name)
        }
    }()

    override func setUp() {
        super.setUp()
        _ = NSApplication.shared
        _ = StoryMorphTransitionTests.registerThemeImages
        self.window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 760), styleMask: [.titled], backing: .buffered, defer: false)
        self.window.isReleasedWhenClosed = false
        let root = View(frame: NSRect(x: 0, y: 0, width: 1200, height: 760))
        self.window.contentView = root
        self.home = View(frame: NSRect(x: 397, y: 20, width: 406, height: 740))
        root.addSubview(self.home)
        let sibling = View(frame: NSRect(x: 0, y: 700, width: 406, height: 40))
        self.home.addSubview(sibling)
        self.content = View(frame: NSRect(x: 0.5, y: 0, width: 405, height: 720))
        self.home.addSubview(self.content, positioned: .below, relativeTo: sibling)
        self.media = View(frame: self.content.bounds)
        self.chrome = View(frame: NSRect(x: 0, y: 0, width: 405, height: 60))
        self.content.addSubview(self.media)
        self.content.addSubview(self.chrome)
        self.window.orderFrontRegardless()
    }

    override func tearDown() {
        self.window.orderOut(nil)
        self.window = nil
        super.tearDown()
    }

    private func avatar(frame: NSRect, radius: CGFloat? = nil) -> AvatarControl {
        let avatar = AvatarControl(font: .systemFont(ofSize: 13))
        avatar.frame = frame
        avatar.imageContents = StoryMorphImageShapeTests.image(side: Int(frame.width * 2), radius: (radius ?? frame.width / 2) * 2)
        self.window.contentView!.addSubview(avatar)
        return avatar
    }

    private func spin(until condition: () -> Bool, timeout: TimeInterval = 3) {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.005))
        }
    }

    private func startPending() {
        RunLoop.current.run(until: Date().addingTimeInterval(0.001))
    }

    private func spin(_ seconds: TimeInterval) {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.005))
        }
    }

    private func restore(_ content: NSView) {
        self.home.addSubview(content, positioned: .below, relativeTo: self.home.subviews.first)
        content.frame = NSRect(x: 0.5, y: 0, width: 405, height: 720)
    }

    func testResolvesAvatarControlsWithTheirRealShape() {
        let circle = self.avatar(frame: NSRect(x: 30, y: 400, width: 50, height: 50))
        let resolvedCircle = StoryMorphEndpoint.resolve(circle, in: self.window.contentView!)
        XCTAssertEqual(resolvedCircle?.shape.rect, NSRect(x: 30, y: 400, width: 50, height: 50))
        XCTAssertEqual(resolvedCircle?.shape.cornerRadius ?? -1, 25, accuracy: 1)
        XCTAssertNotNil(resolvedCircle?.snapshot)
        XCTAssertTrue(resolvedCircle?.view === circle)

        let forum = self.avatar(frame: NSRect(x: 30, y: 300, width: 48, height: 48), radius: 12)
        XCTAssertEqual(StoryMorphEndpoint.resolve(forum, in: self.window.contentView!)?.shape.cornerRadius ?? -1, 12, accuracy: 1)

        let story = AvatarStoryControl(font: .systemFont(ofSize: 13), size: NSSize(width: 56, height: 56))
        story.frame = NSRect(x: 100, y: 100, width: 56, height: 56)
        self.window.contentView!.addSubview(story)
        story.avatar.frame = NSRect(x: 3, y: 3, width: 50, height: 50)
        story.avatar.imageContents = StoryMorphImageShapeTests.image(side: 100, radius: 50)
        let resolvedStory = StoryMorphEndpoint.resolve(story, in: self.window.contentView!)
        XCTAssertTrue(resolvedStory?.view === story.avatar)
        XCTAssertEqual(resolvedStory?.shape.rect, self.window.contentView!.convert(story.avatar.bounds, from: story.avatar))
        XCTAssertEqual(resolvedStory?.shape.cornerRadius ?? -1, 25, accuracy: 1)
    }

    func testResolvesGenericViewsWithTheirLayerCornerRadius() {
        let thumb = View(frame: NSRect(x: 200, y: 200, width: 90, height: 160))
        thumb.layer?.cornerRadius = 8
        self.window.contentView!.addSubview(thumb)
        let resolved = StoryMorphEndpoint.resolve(thumb, in: self.window.contentView!)
        XCTAssertEqual(resolved?.shape, StoryMorphShape(rect: NSRect(x: 200, y: 200, width: 90, height: 160), cornerRadius: 8))
        XCTAssertNil(resolved?.snapshot)
    }

    func testRejectsSourcesThatCannotBeMorphedFrom() {
        let host = self.window.contentView!
        let hidden = self.avatar(frame: NSRect(x: 30, y: 400, width: 50, height: 50))
        hidden.isHidden = true
        XCTAssertNil(StoryMorphEndpoint.resolve(hidden, in: host))

        let empty = View(frame: NSRect(x: 10, y: 10, width: 0, height: 30))
        host.addSubview(empty)
        XCTAssertNil(StoryMorphEndpoint.resolve(empty, in: host))

        let detached = View(frame: NSRect(x: 0, y: 0, width: 40, height: 40))
        XCTAssertNil(StoryMorphEndpoint.resolve(detached, in: host))

        let other = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
        other.isReleasedWhenClosed = false
        let foreign = View(frame: NSRect(x: 10, y: 10, width: 40, height: 40))
        other.contentView!.addSubview(foreign)
        XCTAssertNil(StoryMorphEndpoint.resolve(foreign, in: host))

        let scroll = NSScrollView(frame: NSRect(x: 600, y: 600, width: 100, height: 100))
        let document = View(frame: NSRect(x: 0, y: 0, width: 100, height: 1000))
        scroll.documentView = document
        host.addSubview(scroll)
        let clipped = View(frame: NSRect(x: 0, y: 900, width: 50, height: 50))
        document.addSubview(clipped)
        scroll.contentView.scroll(to: .zero)
        XCTAssertNil(StoryMorphEndpoint.resolve(clipped, in: host))

        let offscreen = View(frame: NSRect(x: -400, y: -400, width: 50, height: 50))
        host.addSubview(offscreen)
        XCTAssertNil(StoryMorphEndpoint.resolve(offscreen, in: host))
    }

    func testVisibilityFollowsClippingRowsNotVisibleRect() {
        let host = self.window.contentView!
        let row = View(frame: NSRect(x: 0, y: 600, width: 300, height: 70))
        row.layer?.masksToBounds = true
        host.addSubview(row)
        let half = self.avatar(frame: NSRect(x: 10, y: 40, width: 50, height: 50))
        row.addSubview(half)
        XCTAssertEqual(StoryMorphEndpoint.visibleFraction(of: half), 0.6, accuracy: 1e-6)
        XCTAssertNotNil(StoryMorphEndpoint.resolve(half, in: host))
        let sliver = self.avatar(frame: NSRect(x: 100, y: 60, width: 50, height: 50))
        row.addSubview(sliver)
        XCTAssertEqual(StoryMorphEndpoint.visibleFraction(of: sliver), 0.2, accuracy: 1e-6)
        XCTAssertNil(StoryMorphEndpoint.resolve(sliver, in: host))
        let inside = self.avatar(frame: NSRect(x: 200, y: 10, width: 50, height: 50))
        row.addSubview(inside)
        XCTAssertEqual(StoryMorphEndpoint.visibleFraction(of: inside), 1, accuracy: 1e-6)
    }

    func testOpenMorphsFromTheAvatarAboveTheModalAndHandsTheContentBack() throws {
        let avatar = self.avatar(frame: NSRect(x: 30, y: 400, width: 50, height: 50))
        let siblingAbove = self.home.subviews[1]
        let transition = try XCTUnwrap(StoryMorphTransition.open(content: self.content, from: avatar, targetRadius: 10, chrome: { [chrome] in [chrome!] }, restore: { [weak self] content in self?.restore(content) }))
        XCTAssertNil(transition.bubble.layer?.animation(forKey: "storyMorph.bounds"), "keyframes start right before the commit, not mid-turn")
        self.startPending()
        let host = transition.host
        XCTAssertTrue(self.window.contentView!.subviews.last === host)
        XCTAssertNil(host.hitTest(NSPoint(x: 600, y: 300)))
        XCTAssertTrue(self.content.superview === transition.bubble)
        XCTAssertEqual(avatar.alphaValue, 0)
        XCTAssertEqual(transition.bubble.frame, self.window.contentView!.convert(NSRect(x: 0.5, y: 0, width: 405, height: 720), from: self.home))
        XCTAssertEqual(transition.phase, .opening)
        XCTAssertEqual(StoryMorphTransition.activeCount, 1)

        self.window.displayIfNeeded()
        CATransaction.flush()
        let bubbleSublayers = try XCTUnwrap(transition.bubble.layer?.sublayers)
        let contentIndex = try XCTUnwrap(bubbleSublayers.firstIndex { $0 === self.content.layer })
        let snapshotIndex = try XCTUnwrap(bubbleSublayers.firstIndex { $0 === transition.snapshotHost.layer })
        XCTAssertGreaterThan(snapshotIndex, contentIndex, "the avatar snapshot must draw above the story")
        XCTAssertTrue(transition.snapshotLayer.superlayer === transition.snapshotHost.layer)
        XCTAssertTrue(transition.bubble.subviews.last === transition.snapshotHost)

        let timeline = try XCTUnwrap(transition.timeline)
        let first = timeline.samples[0].geometry
        XCTAssertEqual(first.bubble, avatar.frame)
        let animation = try XCTUnwrap(transition.bubble.layer?.animation(forKey: "storyMorph.bounds") as? CAKeyframeAnimation)
        XCTAssertEqual((animation.values?.first as? NSValue)?.rectValue.size, avatar.frame.size)
        XCTAssertEqual(animation.duration, timeline.plan.duration, accuracy: 1e-9)
        XCTAssertNotNil(self.content.layer?.animation(forKey: "storyMorph.transform"))
        XCTAssertNotNil(self.chrome.layer?.animation(forKey: "storyMorph.opacity"))
        XCTAssertEqual(transition.snapshotLayer.animation(forKey: "storyMorph.opacity").flatMap { ($0 as? CAKeyframeAnimation)?.values?.first as? NSNumber }?.doubleValue, 1)

        CATransaction.flush()
        self.spin(0.03)
        let presentation = try XCTUnwrap(transition.bubble.layer?.presentation())
        let size = presentation.bounds.size
        XCTAssertLessThan(size.height, 720)
        XCTAssertGreaterThanOrEqual(size.height, 49)
        let target = transition.bubble.frame
        XCTAssertGreaterThan(presentation.frame.midY, target.midY, "the bubble must start at the avatar (below the story centre in flipped coordinates), not mirrored")
        XCTAssertLessThan(presentation.frame.midY, avatar.frame.midY + 1)
        XCTAssertGreaterThan(presentation.frame.midX, avatar.frame.midX - 1)
        XCTAssertLessThan(presentation.frame.midX, target.midX)
        let contentPresentation = try XCTUnwrap(self.content.layer?.presentation())
        let contentScale = contentPresentation.transform.m11
        XCTAssertGreaterThan(contentScale, 0.12)
        XCTAssertLessThan(contentScale, 1)
        XCTAssertEqual(contentPresentation.transform.m22, contentScale, accuracy: 1e-9)
        XCTAssertGreaterThanOrEqual(contentPresentation.bounds.width * contentScale, size.width - 0.5)
        XCTAssertGreaterThanOrEqual(contentPresentation.bounds.height * contentScale, size.height - 0.5)

        var completedPhase: StoryMorphTransition.Phase?
        transition.onPhaseCompleted = { completedPhase = $0 }
        self.spin(until: { completedPhase != nil })
        XCTAssertEqual(completedPhase, .open)
        XCTAssertEqual(transition.phase, .open)
        XCTAssertTrue(self.content.superview === self.home)
        XCTAssertEqual(self.home.subviews.firstIndex(of: self.content), 0)
        XCTAssertTrue(self.home.subviews[1] === siblingAbove)
        XCTAssertEqual(self.content.frame, NSRect(x: 0.5, y: 0, width: 405, height: 720))
        XCTAssertNil(host.superview)
        XCTAssertEqual(avatar.alphaValue, 1)
        XCTAssertFalse(StoryMorphHold.isHeld(avatar))
        XCTAssertNil(self.content.layer?.animation(forKey: "storyMorph.transform"))
        XCTAssertNil(self.chrome.layer?.animation(forKey: "storyMorph.opacity"))
        XCTAssertEqual(StoryMorphTransition.activeCount, 0)
    }

    func testAnimationContextLeakedByTablesDoesNotWarpTheMorph() throws {
        let avatar = self.avatar(frame: NSRect(x: 30, y: 400, width: 50, height: 50))
        let leak = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.beforeWaiting.rawValue, true, 1_000_000, { _, _ in
            NSAnimationContext.current.duration = 0
            NSAnimationContext.current.timingFunction = CAMediaTimingFunction(name: .easeOut)
        })
        CFRunLoopAddObserver(CFRunLoopGetMain(), leak, .commonModes)
        defer {
            CFRunLoopObserverInvalidate(leak)
        }
        NSAnimationContext.current.duration = 0
        NSAnimationContext.current.timingFunction = CAMediaTimingFunction(name: .easeOut)
        let transition = try XCTUnwrap(StoryMorphTransition.open(content: self.content, from: avatar, targetRadius: 10, chrome: { [] }, restore: { [weak self] content in self?.restore(content) }))
        self.startPending()
        CATransaction.flush()
        let plan = try XCTUnwrap(transition.timeline?.plan)
        var worst: CGFloat = 0
        for _ in 0 ..< 6 {
            self.spin(0.03)
            let presented = try XCTUnwrap(transition.bubble.layer?.presentation()).bounds.size.height
            let expected = plan.state(at: CACurrentMediaTime() - transition.startTime).size.height
            worst = max(worst, abs(presented - expected))
        }
        XCTAssertLessThan(worst, 12, "keyframes must follow the spring even when the run loop's implicit transaction carries an ease-out curve")
        transition.finish()
    }

    func testCloseDuringOpenReversesFromWhereTheBubbleIs() throws {
        let avatar = self.avatar(frame: NSRect(x: 30, y: 400, width: 50, height: 50))
        let transition = try XCTUnwrap(StoryMorphTransition.open(content: self.content, from: avatar, targetRadius: 10, chrome: { [chrome] in [chrome!] }, restore: { [weak self] content in self?.restore(content) }))
        CATransaction.flush()
        self.spin(0.1)
        let openPlan = try XCTUnwrap(transition.timeline?.plan)
        var closed = false
        transition.close(to: avatar, completion: { closed = true })
        XCTAssertEqual(transition.phase, .closing)
        XCTAssertTrue(transition.isStartPending)
        self.startPending()
        let closePlan = try XCTUnwrap(transition.timeline?.plan)
        XCTAssertNotEqual(openPlan, closePlan)
        let elapsed = closePlan.from
        XCTAssertGreaterThan(elapsed.size.height, 50)
        XCTAssertLessThan(elapsed.size.height, 760)
        XCTAssertGreaterThan(elapsed.openness, 0)
        XCTAssertLessThan(elapsed.openness, 1)
        XCTAssertGreaterThan(closePlan.centerY.velocity * (openPlan.to.center.y - openPlan.from.center.y), 0, "the bubble keeps its momentum when the close starts")
        XCTAssertEqual(closePlan.to.rect, avatar.frame)
        XCTAssertEqual(avatar.alphaValue, 0)
        XCTAssertTrue(StoryMorphHold.isHeld(avatar))

        self.spin(until: { closed })
        XCTAssertTrue(closed)
        XCTAssertEqual(transition.phase, .closed)
        XCTAssertNil(transition.host.superview)
        XCTAssertNil(self.content.window)
        XCTAssertEqual(avatar.alphaValue, 1)
        XCTAssertFalse(StoryMorphHold.isHeld(avatar))
        XCTAssertEqual(StoryMorphTransition.activeCount, 0)
    }

    func testCloseFromRestLandsOnTheAvatarAsTheAvatar() throws {
        let avatar = self.avatar(frame: NSRect(x: 30, y: 400, width: 50, height: 50))
        var closed = false
        let transition = try XCTUnwrap(StoryMorphTransition.close(content: self.content, to: avatar, targetRadius: 10, chrome: { [chrome] in [chrome!] }, completion: { closed = true }))
        XCTAssertTrue(self.content.superview === transition.bubble)
        XCTAssertEqual(avatar.alphaValue, 0)
        self.startPending()
        let timeline = try XCTUnwrap(transition.timeline)
        let first = timeline.samples[0]
        let last = timeline.samples[timeline.samples.count - 1]
        XCTAssertEqual(first.geometry.bubble, self.window.contentView!.convert(NSRect(x: 0.5, y: 0, width: 405, height: 720), from: self.home))
        XCTAssertEqual(first.fades.chrome, 1)
        XCTAssertEqual(first.fades.snapshot, 0)
        XCTAssertEqual(last.geometry.bubble, avatar.frame)
        XCTAssertEqual(last.geometry.cornerRadius, 25, accuracy: 1)
        XCTAssertEqual(last.fades.snapshot, 1)
        XCTAssertEqual(last.fades.chrome, 0)
        XCTAssertNotNil(transition.snapshotLayer.contents)

        self.spin(until: { closed })
        XCTAssertTrue(closed)
        XCTAssertNil(transition.host.superview)
        XCTAssertEqual(avatar.alphaValue, 1)
        XCTAssertEqual(StoryMorphTransition.activeCount, 0)
    }

    func testCloseToAGenericViewCrossfadesIntoTheRealView() throws {
        let thumb = View(frame: NSRect(x: 200, y: 200, width: 90, height: 160))
        thumb.layer?.cornerRadius = 8
        self.window.contentView!.addSubview(thumb)
        var closed = false
        let transition = try XCTUnwrap(StoryMorphTransition.close(content: self.content, to: thumb, targetRadius: 10, chrome: { [] }, completion: { closed = true }))
        self.startPending()
        let timeline = try XCTUnwrap(transition.timeline)
        let last = timeline.samples[timeline.samples.count - 1]
        XCTAssertEqual(last.geometry.bubble, thumb.frame)
        XCTAssertEqual(last.fades.bubble, 0)
        XCTAssertEqual(last.fades.source, 1)
        let fade = try XCTUnwrap(thumb.layer?.animation(forKey: "storyMorph.opacity") as? CAKeyframeAnimation)
        XCTAssertEqual((fade.values?.first as? NSNumber)?.doubleValue ?? -1, 0, accuracy: 1e-9)
        XCTAssertEqual((fade.values?.last as? NSNumber)?.doubleValue ?? -1, 1, accuracy: 1e-9)
        self.spin(until: { closed })
        XCTAssertEqual(thumb.alphaValue, 1)
        XCTAssertNil(thumb.layer?.animation(forKey: "storyMorph.opacity"))
    }

    func testCloseWithoutDestinationShrinksAndFadesInPlace() throws {
        var closed = false
        let transition = try XCTUnwrap(StoryMorphTransition.close(content: self.content, to: nil, targetRadius: 10, chrome: { [] }, completion: { closed = true }))
        self.startPending()
        let timeline = try XCTUnwrap(transition.timeline)
        let first = timeline.samples[0].geometry.bubble
        let last = timeline.samples[timeline.samples.count - 1]
        XCTAssertEqual(last.geometry.bubble.midX, first.midX, accuracy: 1e-6)
        XCTAssertEqual(last.geometry.bubble.midY, first.midY, accuracy: 1e-6)
        XCTAssertEqual(last.geometry.bubble.width, first.width * 0.9, accuracy: 1e-6)
        XCTAssertEqual(last.fades.bubble, 0)
        self.spin(until: { closed })
        XCTAssertNil(transition.host.superview)
    }

    func testReopeningDuringACloseNeverLeavesTheAvatarHidden() throws {
        let avatar = self.avatar(frame: NSRect(x: 30, y: 400, width: 50, height: 50))
        var closed = false
        _ = try XCTUnwrap(StoryMorphTransition.close(content: self.content, to: avatar, targetRadius: 10, chrome: { [] }, completion: { closed = true }))
        self.spin(0.05)

        let secondHome = View(frame: NSRect(x: 397, y: 20, width: 406, height: 740))
        self.window.contentView!.addSubview(secondHome)
        let secondContent = View(frame: NSRect(x: 0.5, y: 0, width: 405, height: 720))
        secondHome.addSubview(secondContent)
        let reopened = try XCTUnwrap(StoryMorphTransition.open(content: secondContent, from: avatar, targetRadius: 10, chrome: { [] }, restore: { content in
            secondHome.addSubview(content)
            content.frame = NSRect(x: 0.5, y: 0, width: 405, height: 720)
        }))
        XCTAssertEqual(avatar.alphaValue, 0)
        var opened = false
        reopened.onPhaseCompleted = { _ in opened = true }
        self.spin(until: { closed && opened })
        XCTAssertTrue(closed)
        XCTAssertTrue(opened)
        XCTAssertEqual(avatar.alphaValue, 1)
        XCTAssertFalse(StoryMorphHold.isHeld(avatar))
        XCTAssertTrue(secondContent.superview === secondHome)
        XCTAssertEqual(StoryMorphTransition.activeCount, 0)
    }

    func testReopeningDuringALandingTakesOverTheSameBubble() throws {
        let avatar = self.avatar(frame: NSRect(x: 30, y: 400, width: 50, height: 50))
        var closed = false
        let closing = try XCTUnwrap(StoryMorphTransition.close(content: self.content, to: avatar, targetRadius: 10, chrome: { [] }, completion: { closed = true }))
        CATransaction.flush()
        self.spin(0.12)
        let closingPlan = try XCTUnwrap(closing.timeline?.plan)
        let secondHome = View(frame: NSRect(x: 397, y: 20, width: 406, height: 740))
        self.window.contentView!.addSubview(secondHome)
        let secondContent = View(frame: NSRect(x: 0.5, y: 0, width: 405, height: 720))
        secondHome.addSubview(secondContent)
        let before = CACurrentMediaTime() - closing.startTime
        let reopened = try XCTUnwrap(StoryMorphTransition.open(content: secondContent, from: avatar, targetRadius: 10, chrome: { [] }, restore: { content in
            secondHome.addSubview(content)
        }))
        XCTAssertEqual(closing.phase, .closing, "the takeover happens at the commit, while the landing keeps rendering")
        self.startPending()
        let after = CACurrentMediaTime() - closing.startTime
        XCTAssertTrue(closed)
        XCTAssertEqual(closing.phase, .closed)
        XCTAssertNil(closing.host.superview)
        XCTAssertEqual(self.window.contentView!.subviews.filter { $0 is StoryMorphHostView }.count, 1)
        XCTAssertEqual(avatar.alphaValue, 0)
        let openPlan = try XCTUnwrap(reopened.timeline?.plan)
        let expectedLow = closingPlan.state(at: after)
        let expectedHigh = closingPlan.state(at: before)
        XCTAssertGreaterThan(openPlan.from.size.height, avatar.frame.height + 1, "the new open starts where the landing bubble was, not at the avatar")
        XCTAssertLessThanOrEqual(openPlan.from.size.height, expectedHigh.size.height + 0.5)
        XCTAssertGreaterThanOrEqual(openPlan.from.size.height, expectedLow.size.height - 0.5)
        XCTAssertLessThan(openPlan.height.velocity, 0, "the landing momentum carries into the reopen")
        let firstFades = try XCTUnwrap(reopened.timeline?.samples.first?.fades)
        let landingFades = StoryMorphFades.closing(hasSnapshot: true, hasDestination: true, startOpenness: 1, start: .init(snapshot: 0, chrome: 1, bubble: 1, source: 0)).values(openness: openPlan.from.openness)
        XCTAssertEqual(firstFades.snapshot, landingFades.snapshot, accuracy: 1e-6)
        XCTAssertEqual(firstFades.chrome, landingFades.chrome, accuracy: 1e-6)
        var opened = false
        reopened.onPhaseCompleted = { _ in opened = true }
        self.spin(until: { opened })
        XCTAssertEqual(avatar.alphaValue, 1)
        XCTAssertFalse(StoryMorphHold.isHeld(avatar))
        XCTAssertEqual(StoryMorphTransition.activeCount, 0)
    }

    func testViewsAddedDuringTheMorphJoinTheChromeFadeInSync() throws {
        let avatar = self.avatar(frame: NSRect(x: 30, y: 400, width: 50, height: 50))
        let home = View(frame: NSRect(x: 397, y: 20, width: 406, height: 740))
        self.window.contentView!.addSubview(home)
        let content = StoryMorphContentView(frame: NSRect(x: 0.5, y: 0, width: 405, height: 720))
        home.addSubview(content)
        let media = View(frame: content.bounds)
        content.addSubview(media)
        let transition = try XCTUnwrap(StoryMorphTransition.open(content: content, from: avatar, targetRadius: 10, chrome: { [weak content, weak media] in
            content?.subviews.filter { $0 !== media } ?? []
        }, restore: { content in
            home.addSubview(content)
        }))
        content.didAddSubviewHandler = { [weak transition] in
            transition?.syncChrome()
        }
        CATransaction.flush()
        self.spin(0.05)
        let begin = try XCTUnwrap(transition.bubble.layer?.animation(forKey: "storyMorph.position")).beginTime
        XCTAssertEqual(begin, transition.bubble.layer!.convertTime(transition.startTime, from: nil), accuracy: 1e-9)
        let caption = View(frame: NSRect(x: 0, y: 600, width: 405, height: 80))
        content.addSubview(caption)
        let fade = try XCTUnwrap(caption.layer?.animation(forKey: "storyMorph.opacity") as? CAKeyframeAnimation)
        XCTAssertEqual(fade.beginTime, caption.layer!.convertTime(transition.startTime, from: nil), accuracy: 1e-6)
        XCTAssertEqual((fade.values?.first as? NSNumber)?.doubleValue ?? -1, 0, accuracy: 1e-9)
        XCTAssertEqual(fade.duration, transition.timeline!.plan.duration, accuracy: 1e-9)
        XCTAssertNil(media.layer?.animation(forKey: "storyMorph.opacity"))
        content.addSubview(View(frame: .zero))
        XCTAssertNotNil(caption.layer?.animation(forKey: "storyMorph.opacity"))
        transition.finish()
        XCTAssertNil(caption.layer?.animation(forKey: "storyMorph.opacity"))
    }

    func testClosingBeforeTheOpenRendersEndsWhereItStarted() throws {
        let avatar = self.avatar(frame: NSRect(x: 30, y: 400, width: 50, height: 50))
        let transition = try XCTUnwrap(StoryMorphTransition.open(content: self.content, from: avatar, targetRadius: 10, chrome: { [] }, restore: { _ in }))
        var closed = false
        transition.close(to: avatar, completion: { closed = true })
        self.startPending()
        XCTAssertTrue(closed)
        XCTAssertEqual(transition.phase, .closed)
        XCTAssertNil(transition.host.superview)
        XCTAssertEqual(avatar.alphaValue, 1)
        XCTAssertEqual(StoryMorphTransition.activeCount, 0)
    }

    func testFinishSnapsToTheEndImmediately() throws {
        let avatar = self.avatar(frame: NSRect(x: 30, y: 400, width: 50, height: 50))
        let transition = try XCTUnwrap(StoryMorphTransition.open(content: self.content, from: avatar, targetRadius: 10, chrome: { [chrome] in [chrome!] }, restore: { [weak self] content in self?.restore(content) }))
        transition.finish()
        XCTAssertEqual(transition.phase, .open)
        XCTAssertTrue(self.content.superview === self.home)
        XCTAssertNil(transition.host.superview)
        XCTAssertEqual(avatar.alphaValue, 1)
        XCTAssertNil(self.content.layer?.animation(forKey: "storyMorph.position"))
        transition.finish()
        var called = false
        transition.close(to: avatar, completion: { called = true })
        XCTAssertTrue(called)
        XCTAssertEqual(StoryMorphTransition.activeCount, 0)
    }

    func testInvalidSourceLeavesNothingBehind() {
        let before = self.window.contentView!.subviews.count
        let hidden = self.avatar(frame: NSRect(x: 30, y: 400, width: 50, height: 50))
        hidden.isHidden = true
        XCTAssertNil(StoryMorphTransition.open(content: self.content, from: hidden, targetRadius: 10, chrome: { [] }, restore: { _ in }))
        XCTAssertEqual(self.window.contentView!.subviews.count, before + 1)
        XCTAssertTrue(self.content.superview === self.home)
        XCTAssertEqual(hidden.alphaValue, 1)
        XCTAssertEqual(StoryMorphTransition.activeCount, 0)
    }
}
