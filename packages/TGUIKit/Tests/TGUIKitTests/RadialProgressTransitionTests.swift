import XCTest
import AppKit
@testable import TGUIKit

final class RadialProgressTransitionTests: XCTestCase {
    private var now: CFTimeInterval = 1000

    override func setUp() {
        super.setUp()
        TGUIKitTestBootstrap.install()
        now = 1000
        RadialProgressView.currentTime = { [unowned self] in self.now }
        RadialProgressView.reduceMotion = { false }
    }

    override func tearDown() {
        RadialProgressView.currentTime = { CACurrentMediaTime() }
        RadialProgressView.reduceMotion = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
        super.tearDown()
    }

    private let icon = testImage(CGSize(width: 16, height: 18))

    private var themes: [(String, RadialProgressTheme)] {
        return [
            ("plain", RadialProgressTheme(backgroundColor: NSColor(srgbRed: 0.2, green: 0.5, blue: 0.9, alpha: 1), foregroundColor: .white)),
            ("overlay", RadialProgressTheme(backgroundColor: NSColor.black.withAlphaComponent(0.5), foregroundColor: .white)),
            ("cutout", RadialProgressTheme(backgroundColor: NSColor(srgbRed: 0.1, green: 0.6, blue: 0.3, alpha: 1), foregroundColor: .white, blendMode: .clear)),
        ]
    }

    private var states: [(String, RadialProgressState)] {
        return [("none", .None), ("remote", .Remote), ("fetching", .Fetching(progress: 0.42, force: true)), ("impossible", .ImpossibleFetching(progress: 0.42, force: true)), ("play", .Play), ("icon", .Icon(image: icon)), ("success", .Success)]
    }

    private func render(_ view: NSView) -> PixelBuffer {
        if let view = view as? RadialProgressView {
            view.setNeedsDisplay()
        }
        return ViewSnapshot.render(view)
    }

    private func legacy(_ theme: RadialProgressTheme, size: CGFloat, twist: Bool = true, state: RadialProgressState) -> PixelBuffer {
        let view = LegacyRadialProgressView(theme: theme, twist: twist, size: NSMakeSize(size, size))
        view.state = state
        return ViewSnapshot.render(view)
    }

    private func advance(_ view: RadialProgressView, by seconds: Double) {
        now += seconds
        view.advanceForTesting(to: now)
    }

    func testRestStatesDrawLikeTheOldView() {
        for (themeName, theme) in themes {
            for size in [CGFloat(40), 22, 50] {
                for twist in [true, false] {
                    for (stateName, state) in states {
                        let view = RadialProgressView(theme: theme, twist: twist, size: NSMakeSize(size, size))
                        view.state = state
                        let new = render(view)
                        let old = legacy(theme, size: size, twist: twist, state: state)
                        let inner = RadialProgressGlyphGeometry.ringInnerRadius(diameter: size, lineWidth: theme.lineWidth, twist: twist)
                        if stateName == "fetching", RadialProgressGlyphGeometry.cross(diameter: size, ringInnerRadius: inner).first.length < RadialProgressGlyphGeometry.cross(diameter: size, ringInnerRadius: .greatestFiniteMagnitude).first.length {
                            XCTAssertGreaterThan(new.differingPixels(from: old, tolerance: 0), 0, "\(themeName) \(size) twist \(twist) clamped cross")
                            continue
                        }
                        if themeName == "cutout", stateName == "fetching" || stateName == "impossible" {
                            var cut = 0
                            for index in stride(from: 3, to: new.bytes.count, by: 4) {
                                XCTAssertLessThanOrEqual(new.bytes[index], old.bytes[index], "\(size) \(stateName)")
                                if new.bytes[index] < old.bytes[index] {
                                    cut += 1
                                }
                            }
                            XCTAssertGreaterThan(cut, Int(size) * 2, "\(size) twist \(twist) \(stateName)")
                        } else {
                            XCTAssertEqual(new.differingPixels(from: old, tolerance: 0), 0, "\(themeName) \(size) twist \(twist) \(stateName)")
                        }
                    }
                }
            }
        }
    }

    func testGlyphsKeepClearOfTheRingAtEverySize() {
        let sizes: [CGFloat] = Array(stride(from: CGFloat(18), through: 64, by: 1)) + [18.5, 22.5, 30.5]
        for diameter in sizes {
            for (lineWidth, twists) in [(CGFloat(1), [true, false]), (2, [true, false]), (3, [false]), (4, [false])] {
                for twist in twists {
                    let inner = RadialProgressGlyphGeometry.ringInnerRadius(diameter: diameter, lineWidth: lineWidth, twist: twist)
                    let ringCenter = CGPoint(x: diameter / 2, y: floorToScreenPixels(System.backingScale, diameter / 2))
                    for step in 0 ... 60 {
                        let value = CGFloat(step) / 60
                        let geometry = RadialProgressGlyphGeometry.morph(diameter: diameter, ringInnerRadius: inner, value: value)
                        var reach: CGFloat = 0
                        for segment in [geometry.stem, geometry.first, geometry.second] where segment.length > 0 {
                            for point in [segment.from, segment.to] {
                                reach = max(reach, hypot(point.x - ringCenter.x, point.y - ringCenter.y) + geometry.lineWidth / 2)
                            }
                        }
                        XCTAssertLessThanOrEqual(reach, inner - 0.5, "diameter \(diameter) ring \(lineWidth) twist \(twist) morph \(value)")
                    }
                }
            }
        }
    }

    func testSmallCrossesShrinkAndLargeOnesKeepTheirSize() {
        for (diameter, expected) in [(CGFloat(40), CGFloat(14)), (30, 9), (50, 14)] {
            let inner = RadialProgressGlyphGeometry.ringInnerRadius(diameter: diameter, lineWidth: 2, twist: true)
            let cross = RadialProgressGlyphGeometry.cross(diameter: diameter, ringInnerRadius: inner)
            XCTAssertEqual(cross.first.to.x - cross.first.from.x, expected, accuracy: 1e-6, "\(diameter)")
        }
        for diameter in [CGFloat(18), 20, 22, 24] {
            let inner = RadialProgressGlyphGeometry.ringInnerRadius(diameter: diameter, lineWidth: 2, twist: true)
            let cross = RadialProgressGlyphGeometry.cross(diameter: diameter, ringInnerRadius: inner)
            let width = cross.first.to.x - cross.first.from.x
            XCTAssertLessThan(width, 9, "\(diameter)")
            XCTAssertGreaterThan(width, 4, "\(diameter)")
            let reach = hypot(cross.first.from.x - diameter / 2, cross.first.from.y - diameter / 2) + cross.lineWidth / 2
            XCTAssertEqual(inner - reach, RadialProgressGlyphGeometry.ringGap, accuracy: 1e-6, "\(diameter)")
        }
    }

    func testMorphEndsAreTheArrowAndTheCross() {
        for diameter in [CGFloat(40), 22, 50] {
            let factor = diameter / 50
            let roomy = RadialProgressGlyphGeometry.ringInnerRadius(diameter: diameter, lineWidth: 2, twist: false)
            let arrow = RadialProgressGlyphGeometry.morph(diameter: diameter, ringInnerRadius: roomy, value: 0)
            XCTAssertEqual(arrow.stem.from, CGPoint(x: diameter / 2, y: diameter / 2 - 9 * factor + factor))
            XCTAssertEqual(arrow.first.to, CGPoint(x: diameter / 2, y: diameter / 2 + 9 * factor + factor))
            XCTAssertEqual(arrow.first.from, CGPoint(x: diameter / 2 - 7.5 * factor, y: diameter / 2 + 9 * factor - 7.5 * factor + factor))
            XCTAssertEqual(arrow.lineWidth, diameter < 24 ? 1.3 : 2)
            let cross = RadialProgressGlyphGeometry.morph(diameter: diameter, ringInnerRadius: roomy, value: 1)
            let half: CGFloat = diameter < 40 ? 4.5 : 7
            XCTAssertEqual(cross.first.from, CGPoint(x: diameter / 2 - half, y: diameter / 2 - half))
            XCTAssertEqual(cross.second.to, CGPoint(x: diameter / 2 - half, y: diameter / 2 + half))
            XCTAssertEqual(cross.stem.length, 0)
        }
    }

    func testDownloadFlowsTheStemIntoTheOrbit() {
        let theme = themes[0].1
        let view = RadialProgressView(theme: theme)
        view.state = .Remote
        let arrow = render(view)
        view.setState(.Fetching(progress: 0.3, force: false), animated: true)
        XCTAssertEqual(view.flowValueForTesting, 0)
        XCTAssertLessThan(render(view).differingPixels(from: arrow, tolerance: 24), 16)
        var previous = view.displayedValuesForTesting
        var previousFlow: CGFloat = 0
        var middle: PixelBuffer?
        var handoffStep: Int?
        for step in 1 ... 120 {
            advance(view, by: 1.0 / 120.0)
            let values = view.displayedValuesForTesting
            XCTAssertGreaterThanOrEqual(values.morph, previous.morph)
            XCTAssertLessThanOrEqual(values.morph - previous.morph, 0.12, "step \(step)")
            if let flow = view.flowValueForTesting {
                XCTAssertGreaterThanOrEqual(flow, previousFlow, "step \(step)")
                XCTAssertLessThanOrEqual(flow - previousFlow, 0.06, "step \(step)")
                XCTAssertEqual(values.ring, 0, "step \(step)")
                if step == 2 {
                    XCTAssertGreaterThan(flow, 0.01)
                }
                if step == 20 {
                    middle = render(view)
                }
                previousFlow = flow
            } else if handoffStep == nil {
                handoffStep = step
                XCTAssertEqual(values.ring, 1)
                XCTAssertEqual(values.progress, view.flowPathForTesting.handoffProgress, accuracy: 0.03)
                XCTAssertEqual(view.rotationForTesting.phase, view.flowPathForTesting.entryAngle + CGFloat.pi / 2, accuracy: 1e-9)
            }
            previous = values
        }
        XCTAssertEqual(Double(handoffStep ?? 0), 48, accuracy: 2)
        XCTAssertEqual(previous.morph, 1)
        XCTAssertEqual(previous.progress, 0.3, accuracy: 1e-6)
        let end = render(view)
        XCTAssertEqual(end.differingPixels(from: legacy(theme, size: 40, state: .Fetching(progress: 0.3, force: true)), tolerance: 0), 0)
        XCTAssertGreaterThan(middle!.differingPixels(from: end, tolerance: 0), 50)
        XCTAssertGreaterThan(middle!.differingPixels(from: arrow, tolerance: 0), 50)
    }

    func testFlowHandsOffToTheRingWithoutAJump() {
        let view = RadialProgressView(theme: themes[2].1)
        view.state = .Remote
        let handoff = view.flowPathForTesting.handoffProgress
        view.setState(.Fetching(progress: Float(handoff), force: false), animated: true)
        var lastFlowing: PixelBuffer?
        var firstRing: PixelBuffer?
        for _ in 1 ... 240 {
            advance(view, by: 1.0 / 480.0)
            if view.flowValueForTesting != nil {
                lastFlowing = render(view)
            } else {
                firstRing = render(view)
                break
            }
        }
        XCTAssertNotNil(lastFlowing)
        XCTAssertNotNil(firstRing)
        if let lastFlowing = lastFlowing, let firstRing = firstRing {
            XCTAssertLessThan(lastFlowing.differingPixels(from: firstRing, tolerance: 48), 24)
        }
    }

    func testRingRotationStartsWhereTheFlowArrives() {
        let container = NSView(frame: NSMakeRect(0, 0, 60, 60))
        let view = RadialProgressView(theme: themes[0].1)
        container.addSubview(view)
        view.state = .Remote
        view.setState(.Fetching(progress: 0.3, force: false), animated: true)
        XCTAssertNil(view.rotationForTesting.animationFrom)
        advance(view, by: 0.5)
        XCTAssertNil(view.flowValueForTesting)
        let rotation = view.rotationForTesting
        let expected = view.flowPathForTesting.entryAngle + CGFloat.pi / 2
        XCTAssertEqual(rotation.phase, expected, accuracy: 1e-9)
        XCTAssertEqual(rotation.animationFrom ?? -100, expected, accuracy: 1e-9)
    }

    func testFlowArrivesAtTheRingSpeed() {
        let view = RadialProgressView(theme: themes[0].1)
        view.state = .Remote
        view.setState(.Fetching(progress: 0.3, force: false), animated: true)
        let path = view.flowPathForTesting
        var samples: [CGFloat] = []
        for _ in 1 ... 120 {
            advance(view, by: 1.0 / 240.0)
            guard let flow = view.flowValueForTesting else {
                break
            }
            samples.append(path.travel(flow))
        }
        XCTAssertGreaterThan(samples.count, 10)
        let arrival = (samples[samples.count - 1] - samples[samples.count - 2]) * 240
        let ring = RadialProgressView.rotationSpeed * path.radius
        XCTAssertEqual(arrival, ring, accuracy: ring * 0.2)
        let departure = (samples[1] - samples[0]) * 240
        XCTAssertGreaterThan(departure, ring)
    }

    func testCancelDuringTheFlowSlidesTheStemBack() {
        let theme = themes[0].1
        let view = RadialProgressView(theme: theme)
        view.state = .Remote
        view.setState(.Fetching(progress: 0.3, force: false), animated: true)
        advance(view, by: 0.2)
        let before = view.flowValueForTesting ?? 0
        XCTAssertGreaterThan(before, 0.2)
        view.setState(.Remote, animated: true)
        XCTAssertEqual(view.flowValueForTesting ?? -1, before, accuracy: 1e-9)
        var previous = before
        while let flow = view.flowValueForTesting {
            XCTAssertLessThanOrEqual(flow, previous + 1e-9)
            previous = flow
            advance(view, by: 1.0 / 120.0)
        }
        advance(view, by: 0.4)
        XCTAssertEqual(view.displayedValuesForTesting.ring, 0)
        XCTAssertEqual(render(view).differingPixels(from: legacy(theme, size: 40, state: .Remote), tolerance: 0), 0)
        view.setState(.Fetching(progress: 0.3, force: false), animated: true)
        XCTAssertEqual(view.flowValueForTesting, 0)
    }

    func testSmallControlsAndReduceMotionSkipTheFlow() {
        let small = RadialProgressView(theme: themes[0].1, size: NSMakeSize(22, 22))
        small.state = .Remote
        small.setState(.Fetching(progress: 0.3, force: false), animated: true)
        XCTAssertNil(small.flowValueForTesting)
        RadialProgressView.reduceMotion = { true }
        let calm = RadialProgressView(theme: themes[0].1)
        calm.state = .Remote
        calm.setState(.Fetching(progress: 0.3, force: false), animated: true)
        XCTAssertNil(calm.flowValueForTesting)
        let icon = RadialProgressView(theme: RadialProgressTheme(backgroundColor: .black, foregroundColor: .white, cancelFetchingIcon: self.icon))
        icon.state = .Remote
        RadialProgressView.reduceMotion = { false }
        icon.setState(.Fetching(progress: 0.3, force: false), animated: true)
        XCTAssertNil(icon.flowValueForTesting)
    }

    func testCancelReversesFromTheCurrentShape() {
        let theme = themes[0].1
        let view = RadialProgressView(theme: theme)
        view.state = .Remote
        view.setState(.Fetching(progress: 0.6, force: false), animated: true)
        advance(view, by: 0.12)
        let before = view.displayedValuesForTesting
        XCTAssertGreaterThan(before.morph, 0.2)
        XCTAssertLessThan(before.morph, 1)
        view.setState(.Remote, animated: true)
        let after = view.displayedValuesForTesting
        XCTAssertEqual(after.morph, before.morph, accuracy: 1e-9)
        XCTAssertEqual(after.ring, before.ring, accuracy: 1e-9)
        var previous = after
        for _ in 1 ... 80 {
            advance(view, by: 1.0 / 120.0)
            let values = view.displayedValuesForTesting
            XCTAssertLessThanOrEqual(values.morph, previous.morph + 1e-9)
            XCTAssertLessThanOrEqual(values.ring, previous.ring + 1e-9)
            previous = values
        }
        XCTAssertEqual(previous.morph, 0)
        XCTAssertEqual(previous.ring, 0)
        XCTAssertEqual(previous.progress, 0)
        XCTAssertEqual(render(view).differingPixels(from: legacy(theme, size: 40, state: .Remote), tolerance: 0), 0)
    }

    func testProgressUpdatesDoNotInterruptTheMorph() {
        let view = RadialProgressView(theme: themes[0].1)
        view.state = .Remote
        view.setState(.Fetching(progress: 0.1, force: false), animated: true)
        advance(view, by: 0.08)
        let before = view.displayedValuesForTesting
        view.setState(.Fetching(progress: 0.5, force: false), animated: true)
        XCTAssertEqual(view.displayedValuesForTesting.morph, before.morph, accuracy: 1e-9)
        XCTAssertEqual(view.displayedValuesForTesting.ring, 0)
        advance(view, by: 0.9)
        XCTAssertEqual(view.displayedValuesForTesting.morph, 1)
        XCTAssertEqual(view.displayedValuesForTesting.progress, 0.5, accuracy: 1e-6)
    }

    func testFinishingCompletesTheRingThenSettlesOnTheIcon() {
        for (name, theme) in themes {
            let view = RadialProgressView(theme: theme)
            view.state = .Fetching(progress: 0.8, force: true)
            view.setState(.Icon(image: icon), animated: true)
            var reachedFull = false
            var previousRing: CGFloat = 1
            for _ in 1 ... 80 {
                advance(view, by: 1.0 / 120.0)
                let values = view.displayedValuesForTesting
                if values.progress >= 0.999 && values.ring > 0.5 {
                    reachedFull = true
                }
                XCTAssertLessThanOrEqual(values.ring, previousRing + 1e-9)
                previousRing = values.ring
            }
            XCTAssertTrue(reachedFull, name)
            XCTAssertEqual(view.displayedValuesForTesting.ring, 0, name)
            XCTAssertNil(view.displayedValuesForTesting.swap, name)
            XCTAssertEqual(render(view).differingPixels(from: legacy(theme, size: 40, state: .Icon(image: icon)), tolerance: 0), 0, name)
        }
    }

    func testCutoutThemeFadesTheIconPartially() {
        let theme = themes[2].1
        let view = RadialProgressView(theme: theme)
        view.state = .Fetching(progress: 1, force: true)
        view.setState(.Icon(image: icon), animated: true)
        advance(view, by: 0.11)
        let frame = render(view)
        let start = legacy(theme, size: 40, state: .Fetching(progress: 1, force: true))
        let end = legacy(theme, size: 40, state: .Icon(image: icon))
        XCTAssertGreaterThan(frame.differingPixels(from: start, tolerance: 0), 50)
        XCTAssertGreaterThan(frame.differingPixels(from: end, tolerance: 0), 50)
        let center = (frame.height / 2 * frame.width + frame.width / 2) * 4 + 3
        XCTAssertEqual(start.bytes[center], 0)
        XCTAssertEqual(end.bytes[center], 0)
        XCTAssertGreaterThan(frame.bytes[center], 0)
        XCTAssertLessThan(frame.bytes[center], 255)
    }

    func testCutoutRingRotatesWhileFetching() {
        let view = RadialProgressView(theme: themes[2].1)
        let container = NSView(frame: view.bounds)
        container.addSubview(view)
        view.state = .Fetching(progress: 0.3, force: true)
        func shot() -> PixelBuffer {
            view.setNeedsDisplay()
            return ViewSnapshot.render(container)
        }
        let first = shot()
        now += 0.5
        let quarter = shot()
        now += 1.5
        let full = shot()
        XCTAssertGreaterThan(first.differingPixels(from: quarter, tolerance: 0), 50)
        XCTAssertEqual(first.differingPixels(from: full, tolerance: 2), 0)
    }

    func testPlainStateChangesStayImmediate() {
        let theme = themes[0].1
        let view = RadialProgressView(theme: theme)
        view.state = .Fetching(progress: 0.5, force: true)
        view.state = .Remote
        let values = view.displayedValuesForTesting
        XCTAssertEqual(values.ring, 0)
        XCTAssertEqual(values.progress, 0)
        XCTAssertNil(values.swap)
        XCTAssertEqual(render(view).differingPixels(from: legacy(theme, size: 40, state: .Remote), tolerance: 0), 0)
    }

    func testReduceMotionFadesInsteadOfMorphing() {
        RadialProgressView.reduceMotion = { true }
        let view = RadialProgressView(theme: themes[0].1)
        view.state = .Remote
        view.setState(.Fetching(progress: 0.3, force: false), animated: true)
        XCTAssertEqual(view.displayedValuesForTesting.morph, 1)
        XCTAssertNotNil(view.displayedValuesForTesting.swap)
        advance(view, by: 0.5)
        XCTAssertNil(view.displayedValuesForTesting.swap)
    }
}
