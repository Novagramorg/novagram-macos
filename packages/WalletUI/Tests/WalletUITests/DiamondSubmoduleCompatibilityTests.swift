import XCTest
import Cocoa
import Foundation
import simd
import Metal
@testable import SceneEffects

private struct SubmoduleRotationPulse {
    private static let rotationInterval: Float = .pi
    private static let probability: Float = 0.6
    private static let highSpeedThreshold: Float = 2 * .pi
    private static let highSpeedProbability: Float = 0.05
    private static let rise: Float = 0.08
    private static let duration: Float = rise + 33.0 / 60.0
    private var rotation: Float = 0
    private var age: Float = 0

    var isActive: Bool {
        return self.age < Self.duration
    }

    mutating func advance(rotation: Float, dt: Float) {
        self.age = min(Self.duration, self.age + dt)
        self.rotation += abs(rotation)
        let speed = dt > 0 ? abs(rotation) / dt : 0
        let probability = speed >= Self.highSpeedThreshold ? Self.highSpeedProbability : Self.probability
        while self.rotation >= Self.rotationInterval {
            self.rotation -= Self.rotationInterval
            if Float.random(in: 0 ..< 1) < probability, self.age >= Self.rise {
                self.age = 0
            }
        }
    }
}

private func submoduleFacetProjection(_ geometry: DiamondGeometry) -> SIMD4<Float> {
    let referenceModel = DiamondMath.rotation(x: DiamondMotion.referencePitch, y: 0)
    let referencePoints = geometry.vertices.map { DiamondMath.cameraPoint(referenceModel * $0.position) }
    let referenceWidth = referencePoints.reduce(Float(0)) { max($0, abs($1.x)) }
    let referenceTop = referencePoints.reduce(-Float.infinity) { max($0, $1.y) }
    return SIMD4(cos(DiamondMotion.referencePitch), sin(DiamondMotion.referencePitch), 223.95 / referenceWidth, referenceTop)
}

private func submoduleLensVertices(_ geometry: DiamondGeometry) -> [SIMD4<Float>] {
    var seen = Set<SIMD3<Int32>>()
    var result: [SIMD4<Float>] = []
    for vertex in geometry.vertices {
        let p = vertex.position
        let key = SIMD3<Int32>(Int32((p.x * 40).rounded()), Int32((p.y * 40).rounded()), Int32((p.z * 40).rounded()))
        if seen.insert(key).inserted { result.append(p) }
    }
    return result
}

private func bytes<T>(_ values: [T]) -> Data {
    return values.withUnsafeBytes { Data($0) }
}

private struct SubmoduleTransferAnimation {
    enum Phase {
        case sending
        case receiving
        case completion
    }

    let phase: Phase
    let startTime: Float

    func presentation(at time: Float) -> (energy: Float, scale: Float, offset: Float) {
        let t = max(0, time - self.startTime)
        let energy: Float
        let hit: Float
        let breath: Float
        let blow: Float
        switch self.phase {
        case .sending, .receiving:
            energy = pow(min(t / 0.45, 1), 0.65)
            hit = self.phase == .sending && t < 0.42 ? sin(.pi * t / 0.42) * (1 - 0.3 * t / 0.42) : 0
            breath = sin(2 * .pi * 1.1 * t)
            blow = 0
        case .completion:
            energy = pow(1 - min(t / 0.7, 1), 2.2)
            hit = 0
            breath = 0
            blow = t < 0.9 ? sin(2 * .pi * 1.6 * t) * exp(-t / 0.2) : 0
        }
        let offset: Float = self.phase != .completion ? -1.6 * energy * sin(2 * .pi * 1.1 * (t - 0.18)) : 0
        return (energy, 1 + 0.32 * hit + 0.07 * energy * breath + blow, offset)
    }
}

private struct SubmoduleDiamondUse {
    let name: String
    let size: CGSize
    let diamondWidth: CGFloat
    let isDark: Bool
    let appearance: InteractiveDiamondView.Appearance
    let expansionStyle: InteractiveDiamondView.ExpansionStyle
    let expandedCenter: CGPoint?
    let animationMode: InteractiveDiamondView.AnimationMode
    let animateOnAppear: Bool
    let tapToSpin: Bool
    let metricsScale: CGFloat
}

private func submoduleInitialStyle() -> DiamondStyle {
    var style = DiamondStyle()
    style.animationMode = .continuous
    style.rotationSpeed = 2 * .pi / 26
    style.swayScale = 1
    style.backgroundStars = false
    style.mainSparkleOnRotation = true
    style.releaseTilt = 2.6
    return style
}

private func submoduleStyle(_ use: SubmoduleDiamondUse) -> (style: DiamondStyle, lightBackground: Bool, highlightBoost: Float) {
    var style = submoduleInitialStyle()
    let isInteractive = use.animationMode == .continuous
    style.animateOnAppear = use.animateOnAppear
    switch use.animationMode {
    case .continuous:
        style.animationMode = .continuous
        style.referenceAnimationLoops = true
    case let .lottie(loop):
        style.animationMode = .reference
        style.referenceAnimationLoops = loop
    }
    style.swayScale = isInteractive ? 1.0 : 0.0
    style.floatAmplitude = isInteractive && use.expansionStyle == .downward ? Float(1.5 * use.metricsScale) : 0.0
    style.floatPeriod = 3.2
    let highlightBoost: Float = isInteractive ? 0.4 : 0.0
    style.mainSparkleOnRotation = isInteractive
    style.widthPoints = Float(use.diamondWidth)
    style.appearance = use.appearance
    style.widthCompensation = use.expansionStyle != .wallet
    style.dragGrow = use.expansionStyle == .wallet ? 2.6 : (use.expansionStyle == .downward ? 3.0 : 1.0)
    style.growShift = use.expansionStyle == .downward && use.expandedCenter == nil ? 12.0 : 0.0
    style.growDamping = use.expansionStyle != .centered ? 0.62 : 0.42
    style.releaseDecay = use.expansionStyle != .centered ? 1.1 : 0.0
    style.releaseTilt = use.expansionStyle != .centered ? 0.0 : 2.6
    style.tapToSpin = isInteractive && use.tapToSpin
    style.starOpacity = use.expansionStyle == .wallet ? 0.0 : 1.0
    style.rightwardStars = use.expansionStyle == .wallet
    style.starReferenceSize = use.expansionStyle == .wallet ? 240.0 : 0.0
    if use.expansionStyle != .wallet {
        style.tilt = 0.0
        style.lean = 0.0
    }
    return (style, use.expansionStyle == .centered && !use.isDark, highlightBoost)
}

private func submoduleLandingPower(_ power: CGFloat, isHolding: Bool, hasListener: Bool) -> CGFloat? {
    guard power > 0.0, (power > 0.2 || hasListener), !isHolding else { return nil }
    return hasListener ? min(1.0, power) : nil
}

private let submoduleExpandedRenderSide: CGFloat = 220.0
private let submoduleTransferRenderSide: CGFloat = 96.0
private let submoduleStarRenderSide: CGFloat = 240.0

private let diamondUses: [SubmoduleDiamondUse] = [
    SubmoduleDiamondUse(name: "send field", size: CGSize(width: 96 * 34 / 48, height: 96 * 34 / 48), diamondWidth: 34 * 34 / 48, isDark: false, appearance: .blue, expansionStyle: .centered, expandedCenter: nil, animationMode: .continuous, animateOnAppear: false, tapToSpin: false, metricsScale: 34 / 48),
    SubmoduleDiamondUse(name: "send field at night", size: CGSize(width: 96 * 34 / 48, height: 96 * 34 / 48), diamondWidth: 34 * 34 / 48, isDark: true, appearance: .blue, expansionStyle: .centered, expandedCenter: nil, animationMode: .continuous, animateOnAppear: false, tapToSpin: false, metricsScale: 34 / 48),
    SubmoduleDiamondUse(name: "chat transfer card", size: CGSize(width: 64, height: 64), diamondWidth: 38, isDark: false, appearance: .cool, expansionStyle: .downward, expandedCenter: nil, animationMode: .continuous, animateOnAppear: false, tapToSpin: true, metricsScale: 1),
    SubmoduleDiamondUse(name: "wallet card", size: CGSize(width: 96, height: 96), diamondWidth: 26 * 1.09 * 0.8, isDark: false, appearance: .white, expansionStyle: .wallet, expandedCenter: nil, animationMode: .continuous, animateOnAppear: false, tapToSpin: true, metricsScale: 1),
    SubmoduleDiamondUse(name: "transaction header", size: CGSize(width: 110, height: 110), diamondWidth: 78 * 110 / 118, isDark: false, appearance: .blue, expansionStyle: .centered, expandedCenter: nil, animationMode: .lottie(loop: false), animateOnAppear: true, tapToSpin: false, metricsScale: 1),
    SubmoduleDiamondUse(name: "transaction header at night", size: CGSize(width: 110, height: 110), diamondWidth: 78 * 110 / 118, isDark: true, appearance: .blue, expansionStyle: .centered, expandedCenter: nil, animationMode: .lottie(loop: false), animateOnAppear: true, tapToSpin: false, metricsScale: 1),
    SubmoduleDiamondUse(name: "looping intro", size: CGSize(width: 118, height: 118), diamondWidth: 78, isDark: false, appearance: .blue, expansionStyle: .centered, expandedCenter: nil, animationMode: .lottie(loop: true), animateOnAppear: true, tapToSpin: false, metricsScale: 1)
]

private struct SubmoduleTapSpin {
    private(set) var tapStreak = 0
    private var lastTapTime: CFTimeInterval?

    mutating func tap(current: Float, direction: Float, at time: CFTimeInterval, releaseDecay: Float) -> (velocity: Float, decay: Float, burst: Bool) {
        let sign: Float = abs(current) > 0.5 ? (current < 0 ? -1 : 1) : direction
        let top: Float = 16.0
        self.tapStreak = self.lastTapTime.map { time - $0 < 1.0 } == true ? self.tapStreak + 1 : 1
        self.lastTapTime = time
        let streakSpeed = top * Float(self.tapStreak) / 4.0
        let speed = min(top, max(abs(current) + 5.0, streakSpeed))
        let reachedTop = speed >= top * 0.95
        if reachedTop { self.tapStreak = 0 }
        let decay: Float = reachedTop ? 2.5 : max(releaseDecay, 0.05)
        return (sign * speed, max(decay, 0.05), reachedTop)
    }
}

private func submoduleTapDirection(pressStart: (position: CGPoint, time: CFTimeInterval), position: CGPoint, now: CFTimeInterval, bounds: CGRect, layerPosition: CGPoint, expansionStyle: InteractiveDiamondView.ExpansionStyle, tapToSpin: Bool) -> Float? {
    if tapToSpin, now - pressStart.time < 0.25,
       hypot(position.x - pressStart.position.x, position.y - pressStart.position.y) < 10.0 {
        let centerX = expansionStyle == .wallet ? layerPosition.x : bounds.midX
        return position.x < centerX ? -1.0 : 1.0
    } else {
        return nil
    }
}

private func submoduleWalletTilt(_ style: DiamondStyle, diamondWidth: CGFloat, pitch: CGFloat, roll: CGFloat, scale: CGFloat) -> DiamondStyle {
    var style = style
    style.tilt = Float(-pitch * 2.8)
    style.lean = Float(roll * 2.6)
    style.widthPoints = Float(diamondWidth * scale)
    return style
}

private func submoduleWalletCenterX(restingSize: CGSize, diamondWidth: CGFloat, grow: Float, zoom: Float, walletScale: CGFloat, walletLeftInset: CGFloat) -> CGFloat {
    let halfWidth = diamondWidth * CGFloat(grow * zoom) * walletScale * 0.55
    return restingSize.width * 0.5 + max(0.0, halfWidth - walletLeftInset)
}

private func submoduleWalletPointInside(_ point: CGPoint, restingSize: CGSize, layerPosition: CGPoint, walletScale: CGFloat) -> Bool {
    let radius = restingSize.width * (30.0 * 0.9 / 96.0) * walletScale
    return hypot(point.x - layerPosition.x, point.y - layerPosition.y) <= radius
}

private struct SubmodulePinchZoom {
    private(set) var zoom: Float = 1
    private var initialZoom: Float?

    mutating func pinch(isActive: Bool, scale: CGFloat) {
        if isActive {
            if self.initialZoom == nil { self.initialZoom = self.zoom }
            self.zoom = min(1.6, max(0.6, (self.initialZoom ?? 1.0) * Float(scale)))
        } else {
            self.initialZoom = nil
        }
    }
}

private struct SubmoduleLean {
    var targetLean: Float = 0
    private(set) var lean: Float = 0
    private var leanVelocity: Float = 0

    mutating func step(dt: Float, reduceMotion: Bool) {
        let dt = min(max(dt, 0), 0.05)
        if reduceMotion {
            lean = targetLean
            leanVelocity = 0
            return
        }
        var leanRemaining = dt
        while leanRemaining > 0 && (lean != targetLean || leanVelocity != 0) {
            let step = min(leanRemaining, 1 / Float(240))
            leanVelocity += ((targetLean - lean) * 110 - 2 * 0.55 * 10.5 * leanVelocity) * step
            lean += leanVelocity * step
            leanRemaining = max(0, leanRemaining - step)
        }
        if abs(lean - targetLean) < 0.0001 && abs(leanVelocity) < 0.0001 {
            lean = targetLean
            leanVelocity = 0
        }
    }
}

private func mirrored<T>(_ subject: Any, _ label: String) -> T? {
    var mirror: Mirror? = Mirror(reflecting: subject)
    while let current = mirror {
        if let child = current.children.first(where: { $0.label == label }) {
            return child.value as? T
        }
        mirror = current.superclassMirror
    }
    return nil
}

private func actualDiamondView(_ use: SubmoduleDiamondUse) -> InteractiveDiamondView {
    let view = InteractiveDiamondView(frame: CGRect(origin: .zero, size: use.size))
    view.update(size: use.size, diamondWidth: use.diamondWidth, isVisible: true, lightBackground: !use.isDark, appearance: use.appearance, expansionStyle: use.expansionStyle, expandedCenter: use.expandedCenter, animationMode: use.animationMode, animateOnAppear: use.animateOnAppear, tapToSpin: use.tapToSpin, metricsScale: use.metricsScale)
    return view
}

final class DiamondSubmoduleCompatibilityTests: XCTestCase {
    private func repositoryRoot() -> URL {
        return URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    private func submoduleSource(_ name: String) throws -> String {
        let url = repositoryRoot().appendingPathComponent("submodules/telegram-ios/submodules/TelegramUI/Components/Premium/PremiumDiamondComponent/Sources/InteractiveDiamond").appendingPathComponent(name)
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func submoduleConstant(_ pattern: String, in source: String) throws -> Float {
        let regex = try NSRegularExpression(pattern: pattern)
        let match = try XCTUnwrap(regex.firstMatch(in: source, range: NSRange(source.startIndex..., in: source)), pattern)
        let range = try XCTUnwrap(Range(match.range(at: 1), in: source))
        return try XCTUnwrap(Float(source[range]), pattern)
    }

    private func actualPulses(_ steps: [(rotation: Float, dt: Float)]) -> Bool {
        var pulse = DiamondSparkleAnimation.RotationPulse()
        pulse.advance(rotation: 0, dt: 10)
        for step in steps {
            pulse.advance(rotation: step.rotation, dt: step.dt)
        }
        pulse.advance(rotation: 0, dt: 0.02)
        return pulse.state.shape != .zero
    }

    private func submodulePulses(_ steps: [(rotation: Float, dt: Float)]) -> Bool {
        var pulse = SubmoduleRotationPulse()
        pulse.advance(rotation: 0, dt: 10)
        for step in steps {
            pulse.advance(rotation: step.rotation, dt: step.dt)
        }
        pulse.advance(rotation: 0, dt: 0.02)
        return pulse.isActive
    }

    func testRotationSparkleChanceMatchesSubmodule() {
        XCTAssertNotEqual(DiamondSparkleAnimation.state(time: 0).shape, .zero)
        var idle = DiamondSparkleAnimation.RotationPulse()
        idle.advance(rotation: 0, dt: 10)
        XCTAssertEqual(idle.state.shape, .zero)

        let trials = 4000
        let scenarios: [(name: String, steps: [(rotation: Float, dt: Float)], expected: Double, tolerance: Double)] = [
            ("just under half a turn", [(0.99 * .pi, 1.0)], 0.0, 0.0),
            ("half a turn, slow", [(.pi, 1.0)], 0.6, 0.05),
            ("half a turn in two quarter turns", [(.pi / 2, 1.0), (.pi / 2, 1.0)], 0.6, 0.05),
            ("half a turn just under one turn per second", [(.pi, 0.52)], 0.6, 0.05),
            ("half a turn at one turn per second", [(.pi, 0.5)], 0.05, 0.025),
            ("a full turn at two turns per second", [(2 * .pi, 0.5)], 1.0 - 0.95 * 0.95, 0.03)
        ]
        for scenario in scenarios {
            let actual = Double((0 ..< trials).filter { _ in actualPulses(scenario.steps) }.count) / Double(trials)
            let submodule = Double((0 ..< trials).filter { _ in submodulePulses(scenario.steps) }.count) / Double(trials)
            XCTAssertEqual(actual, scenario.expected, accuracy: scenario.tolerance, scenario.name)
            XCTAssertEqual(submodule, scenario.expected, accuracy: scenario.tolerance, scenario.name)
            XCTAssertEqual(actual, submodule, accuracy: scenario.tolerance * 1.5, scenario.name)
        }
    }

    private func yawTravel(_ motion: inout DiamondMotion, seconds: Float) -> Float {
        var total: Float = 0
        var previous = motion.yaw
        for _ in 0 ..< Int(seconds * 120) {
            motion.step(dt: 1 / 120, speed: 0, reduceMotion: false)
            var delta = motion.yaw - previous
            if delta > .pi {
                delta -= 2 * .pi
            } else if delta < -.pi {
                delta += 2 * .pi
            }
            total += delta
            previous = motion.yaw
        }
        return total
    }

    private func motionsBeforeFling() -> [(name: String, motion: DiamondMotion)] {
        var resting = DiamondMotion()
        resting.step(dt: 0.1, speed: 0, reduceMotion: false)

        var spinning = DiamondMotion()
        spinning.spin(6, decay: 0.4)
        spinning.step(dt: 0.1, speed: 0, reduceMotion: false)

        var tapped = DiamondMotion()
        _ = tapped.tap(direction: -1, speed: 0, mode: .continuous, time: 0)
        tapped.step(dt: 0.1, speed: 0, reduceMotion: false)

        var released = DiamondMotion()
        released.releaseTilt = 2.6
        released.begin(at: 0)
        released.drag(dx: 40, dy: 6, scale: 220, at: 0.02)
        released.drag(dx: 55, dy: -3, scale: 220, at: 0.04)
        released.step(dt: 0, speed: 0, reduceMotion: false)
        released.end(at: 0.05)

        var releasedWithDecay = DiamondMotion()
        releasedWithDecay.releaseDecay = 0.9
        releasedWithDecay.begin(at: 0)
        releasedWithDecay.drag(dx: -60, dy: 0, scale: 220, at: 0.02)
        releasedWithDecay.step(dt: 0, speed: 0, reduceMotion: false)
        releasedWithDecay.end(at: 0.03)

        return [("resting", resting), ("spinning", spinning), ("tapped", tapped), ("released", released), ("released with decay", releasedWithDecay)]
    }

    func testFlingPushMatchesSubmoduleSpinWhateverRanBefore() {
        let impulse: Float = 3.0 * 6.5
        for direction: Float in [1, -1] {
            var submodule = DiamondMotion()
            submodule.spin(direction * impulse, decay: 0.7)
            let expected = yawTravel(&submodule, seconds: 6)
            XCTAssertEqual(expected, direction * impulse * 0.7, accuracy: 0.02)

            for (name, before) in motionsBeforeFling() {
                var motion = before
                motion.fling(direction: direction, impulse: impulse)
                XCTAssertEqual(yawTravel(&motion, seconds: 6), expected, accuracy: 1e-3, name)
            }
        }
    }

    func testFlingIsIgnoredWhileDragging() {
        var motion = DiamondMotion()
        motion.begin(at: 0)
        motion.fling(direction: 1, impulse: 19.5)
        XCTAssertEqual(yawTravel(&motion, seconds: 1), 0, accuracy: 1e-6)
    }

    func testMeshTessellationMatchesSubmodule() throws {
        let source = try submoduleSource("DiamondGeometry.swift")
        XCTAssertEqual(Float(DiamondRounding.segments), try submoduleConstant("static let segments = (\\d+)", in: source))
        XCTAssertEqual(DiamondRounding.edgeStep, try submoduleConstant("static let edgeStep: Float = ([0-9.]+)", in: source))
        XCTAssertEqual(Float(DiamondRounding.radialSteps), try submoduleConstant("static let radialSteps = (\\d+)", in: source))
        XCTAssertTrue(source.contains("segments: Int = DiamondRounding.segments"))
        XCTAssertTrue(source.contains("/ Self.edgeStep)))"))
        XCTAssertTrue(source.contains("let radialSteps = Self.radialSteps"))

        let geometry = DiamondGeometry()
        XCTAssertEqual(geometry.planes.count, 17)
        XCTAssertFalse(geometry.vertices.isEmpty)
        XCTAssertTrue(geometry.vertices.count.isMultiple(of: 3))
    }

    func testRenderDataMatchesSubmoduleAndSurvivesTheCache() throws {
        let built = DiamondRenderData()
        XCTAssertEqual(built.facetProjection, submoduleFacetProjection(built.geometry))
        XCTAssertEqual(built.lensVertices, submoduleLensVertices(built.geometry))
        XCTAssertEqual(bytes(built.anchors), bytes(DiamondSparkleGeometry.anchors(on: built.geometry)))
        let fresh = DiamondSparkleGeometry()
        XCTAssertEqual(bytes(built.sparkles.main), bytes(fresh.main))
        XCTAssertEqual(bytes(built.sparkles.small), bytes(fresh.small))
        XCTAssertEqual(bytes(built.sparkles.streakVertices), bytes(fresh.streakVertices))

        let cacheURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("GramDiamond_v1")
        XCTAssertTrue(try submoduleSource("DiamondGeometry.swift").contains("appendingPathComponent(\"GramDiamond_v\\(self.cacheVersion)\")"))
        try? FileManager.default.removeItem(at: cacheURL)
        defer { try? FileManager.default.removeItem(at: cacheURL) }
        XCTAssertNil(DiamondRenderData.load())

        built.store()
        let deadline = Date().addingTimeInterval(20)
        while !FileManager.default.fileExists(atPath: cacheURL.path) && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        let loaded = try XCTUnwrap(DiamondRenderData.load())
        XCTAssertEqual(bytes(loaded.geometry.vertices), bytes(built.geometry.vertices))
        XCTAssertEqual(loaded.geometry.planes, built.geometry.planes)
        XCTAssertEqual(bytes(loaded.sparkles.main), bytes(built.sparkles.main))
        XCTAssertEqual(bytes(loaded.sparkles.small), bytes(built.sparkles.small))
        XCTAssertEqual(bytes(loaded.sparkles.streakVertices), bytes(built.sparkles.streakVertices))
        XCTAssertEqual(bytes(loaded.anchors), bytes(built.anchors))
        XCTAssertEqual(loaded.facetProjection, built.facetProjection)
        XCTAssertEqual(loaded.lensVertices, built.lensVertices)
        for yawStep in 0 ... 36 {
            for pitch: Float in [-1.0, -0.4, -0.104458, 0, 0.3, 0.9] {
                let yaw = Float(yawStep) * .pi / 18
                XCTAssertEqual(loaded.silhouette.horizontalScale(yaw: yaw, pitch: pitch), built.silhouette.horizontalScale(yaw: yaw, pitch: pitch))
            }
        }

        try Data("not a diamond".utf8).write(to: cacheURL)
        XCTAssertNil(DiamondRenderData.load())
        try Data().write(to: cacheURL)
        XCTAssertNil(DiamondRenderData.load())
    }

    func testOnlyTheSendDiamondDropsBackgroundStars() {
        XCTAssertTrue(InteractiveDiamondLayer().diamondStyle.backgroundStars)
        XCTAssertFalse(InteractiveDiamondLayer(backgroundStars: false).diamondStyle.backgroundStars)
        XCTAssertTrue(InteractiveDiamondLayer(backgroundStars: true).diamondStyle.backgroundStars)
    }

    func testTransferMotionMatchesSubmodule() throws {
        let source = try submoduleSource("DiamondAnimation.swift")
        XCTAssertEqual(DiamondTransferAnimation.completionDuration, try submoduleConstant("static let completionDuration: Float = ([0-9.]+)", in: source))
        for (phase, submodulePhase) in [(DiamondTransferAnimation.Phase.sending, SubmoduleTransferAnimation.Phase.sending), (.receiving, .receiving), (.completion, .completion)] {
            let actual = DiamondTransferAnimation(phase: phase, startTime: 0.3)
            let submodule = SubmoduleTransferAnimation(phase: submodulePhase, startTime: 0.3)
            for step in 0 ... 300 {
                let time = Float(step) / 120
                let a = actual.presentation(at: time)
                let b = submodule.presentation(at: time)
                XCTAssertEqual(a.energy, b.energy, accuracy: 1e-6, "\(phase) energy at \(time)")
                XCTAssertEqual(a.scale, b.scale, accuracy: 1e-6, "\(phase) scale at \(time)")
                XCTAssertEqual(a.offset, b.offset, accuracy: 1e-6, "\(phase) offset at \(time)")
            }
        }
    }

    func testIntroHoldsTheSubmoduleLastFrame() throws {
        let source = try submoduleSource("DiamondAnimation.swift")
        let frame = try submoduleConstant("static let lastFrameTime: Float = ([0-9.]+) / [0-9.]+", in: source)
        let rate = try submoduleConstant("static let lastFrameTime: Float = [0-9.]+ / ([0-9.]+)", in: source)
        XCTAssertEqual(DiamondReferenceHighlights.lastFrameTime, frame / rate)
    }

    func testAppearanceHopMatchesSubmoduleSpring() throws {
        try assertPushFollowsSubmoduleSpring(strength: nil)
    }

    func testHighlightPushFollowsSubmoduleSpring() throws {
        let bubble = try String(contentsOf: repositoryRoot().appendingPathComponent("submodules/telegram-ios/submodules/TelegramUI/Components/Chat/ChatMessageTransferBubbleContentNode/Sources/ChatMessageTransferBubbleContentNode.swift"), encoding: .utf8)
        let strength = try submoduleConstant("\\?\\.pushFromBelow\\(strength: ([0-9.]+)\\)", in: bubble)
        let delay = try submoduleConstant("func animateHighlightBump\\(\\) \\{[\\s\\S]*?let delay = ([0-9.]+)", in: bubble)
        let card = try String(contentsOf: repositoryRoot().appendingPathComponent("packages/WalletUI/Sources/WalletUI/WalletCardView.swift"), encoding: .utf8)
        XCTAssertTrue(card.contains("Queue.mainQueue().after(\(delay), {"))
        XCTAssertTrue(card.contains("self.gramDiamondView.pushFromBelow(strength: \(strength))"))
        try assertPushFollowsSubmoduleSpring(strength: strength)
    }

    private func assertPushFollowsSubmoduleSpring(strength: Float?) throws {
        let source = try submoduleSource("DiamondAnimation.swift")
        XCTAssertTrue(source.contains("mutating func pushFromBelow(strength: Float = 1.0)"))
        XCTAssertTrue(source.contains("pitchSpringVelocity -= strength"))
        XCTAssertTrue(source.contains("private static let springFrequency: Float = 3 * 2 * .pi"))
        XCTAssertTrue(source.contains("private static let springDamping: Float = 0.8"))
        XCTAssertTrue(source.contains("let pitchFrequency = isAppearanceImpulseActive ? 2 * Float.pi * 1.25 : Self.springFrequency"))
        XCTAssertTrue(source.contains("let pitchDamping = 2 * (isAppearanceImpulseActive ? 0.13 : Self.springDamping) * pitchFrequency"))
        let springFrequency: Float = 3 * 2 * .pi
        let springDamping: Float = 0.8
        var motion = DiamondMotion()
        if let strength {
            motion.pushFromBelow(strength: strength)
        } else {
            motion.pushFromBelow()
        }
        XCTAssertTrue(motion.isAppearanceImpulseActive)

        let reference = DiamondMotion.referencePitch
        var pitch = reference
        var velocity: Float = -(strength ?? 1.0)
        var active = true
        var lowest = reference
        var settledAt: Float?
        for frame in 1 ... 600 {
            motion.step(dt: 1 / 60, speed: 0, reduceMotion: false)
            var remaining: Float = 1 / 60
            while remaining > 0 {
                let step = min(remaining, 1 / Float(active ? 240 : 120))
                let frequency = active ? 2 * Float.pi * 1.25 : springFrequency
                let damping = 2 * (active ? 0.13 : springDamping) * frequency
                velocity += ((reference - pitch) * frequency * frequency - damping * velocity) * step
                pitch += velocity * step
                if active && abs(pitch - reference) < 0.0001 && abs(velocity) < 0.0001 {
                    pitch = reference
                    velocity = 0
                    active = false
                }
                remaining = max(0, remaining - step)
            }
            if abs(pitch - reference) < 0.0001 && abs(velocity) < 0.0001 {
                pitch = reference
                velocity = 0
            }
            XCTAssertEqual(motion.pitch, pitch, accuracy: 1e-5, "frame \(frame)")
            XCTAssertEqual(motion.isAppearanceImpulseActive, active, "frame \(frame)")
            lowest = min(lowest, motion.pitch)
            if !active && settledAt == nil {
                settledAt = Float(frame) / 60
            }
        }
        XCTAssertLessThan(lowest, reference - 0.05)
        XCTAssertNotNil(settledAt)
    }

    func testAppearanceHopIsIgnoredWhileDragging() {
        var motion = DiamondMotion()
        motion.begin(at: 0)
        motion.pushFromBelow()
        XCTAssertFalse(motion.isAppearanceImpulseActive)
    }

    func testDiamondSettingsMatchSubmoduleForEveryUse() {
        for use in diamondUses {
            let view = actualDiamondView(use)
            let expected = submoduleStyle(use)
            XCTAssertEqual(view.diamondLayer.diamondStyle, expected.style, use.name)
            XCTAssertEqual(view.diamondLayer.lightBackground, expected.lightBackground, use.name)
            XCTAssertEqual(view.diamondLayer.highlightBoost, expected.highlightBoost, use.name)
            XCTAssertEqual(view.diamondLayer.renderSize, use.size, use.name)
            XCTAssertEqual(view.diamondLayer.position, CGPoint(x: use.size.width / 2, y: use.size.height / 2), use.name)
        }
    }

    func testHeldDiamondDrawsInTheSubmoduleArea() {
        for use in diamondUses where use.animationMode == .continuous {
            let view = actualDiamondView(use)
            let side = submoduleExpandedRenderSide * use.metricsScale
            view.diamondLayer.onHold?(true)
            XCTAssertTrue(view.isExpanded, use.name)
            XCTAssertEqual(view.diamondLayer.renderSize, CGSize(width: side, height: side), use.name)
        }
    }

    func testSendingTransferDrawsInTheSubmoduleArea() throws {
        try XCTSkipIf(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, "reduce motion stops the transfer motion")
        let use = diamondUses.first(where: { $0.name == "chat transfer card" })!
        let view = actualDiamondView(use)
        view.updateTransferState(isSending: true, animateCompletion: false)
        XCTAssertTrue(view.diamondLayer.hasTransferAnimation)
        XCTAssertTrue(view.diamondLayer.usesHighFrameRate)
        XCTAssertEqual(view.diamondLayer.renderSize, CGSize(width: submoduleTransferRenderSide, height: submoduleTransferRenderSide))
        view.updateTransferState(isSending: false, animateCompletion: true)
        XCTAssertFalse(view.diamondLayer.hasTransferAnimation)
        XCTAssertEqual(view.diamondLayer.renderSize, use.size)
    }

    private func chatCardDiamond() -> InteractiveDiamondView {
        let view = actualDiamondView(diamondUses.first(where: { $0.name == "chat transfer card" })!)
        view.diamondLayer.isInHierarchy = true
        return view
    }

    private func actualSpin(_ view: InteractiveDiamondView) -> (velocity: Float, decay: Float, atPress: Float) {
        let motion: DiamondMotion = mirrored(view.diamondLayer, "motion")!
        let velocity: Float = mirrored(motion, "spinVelocity")!
        let decay: Float = mirrored(motion, "spinDecay")!
        return (velocity, decay, motion.spinAtPress)
    }

    private func tapBursts(_ view: InteractiveDiamondView) -> [DiamondStarBurst] {
        let bursts: [DiamondStarBurst] = mirrored(view.diamondLayer, "starBursts") ?? []
        return bursts.filter { $0.isFromTap }
    }

    private func tap(_ view: InteractiveDiamondView, direction: Float) -> CFTimeInterval {
        view.diamondLayer.updateDrag(state: .began)
        let time = CACurrentMediaTime()
        view.diamondLayer.updateDrag(state: .ended, tapSpinDirection: direction)
        return time
    }

    func testTapSpinMatchesSubmodule() throws {
        try XCTSkipIf(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, "reduce motion turns tap spin off")
        let view = chatCardDiamond()
        defer { view.diamondLayer.isInHierarchy = false }
        let releaseDecay = view.diamondLayer.diamondStyle.releaseDecay
        XCTAssertEqual(releaseDecay, 1.1)
        var submodule = SubmoduleTapSpin()
        for (index, direction) in [Float(-1), 1, 1, -1].enumerated() {
            let time = tap(view, direction: direction)
            let actual = actualSpin(view)
            let expected = submodule.tap(current: actual.atPress, direction: direction, at: time, releaseDecay: releaseDecay)
            XCTAssertEqual(actual.velocity, expected.velocity, accuracy: 1e-5, "tap \(index + 1)")
            XCTAssertEqual(actual.decay, expected.decay, accuracy: 1e-6, "tap \(index + 1)")
            XCTAssertEqual(!tapBursts(view).isEmpty, expected.burst, "tap \(index + 1)")
            XCTAssertLessThan(actual.velocity, 0, "tap \(index + 1) keeps the direction of the first tap")
        }
        XCTAssertEqual(actualSpin(view).velocity, -16, accuracy: 1e-5)
        XCTAssertEqual(actualSpin(view).decay, 2.5)
        XCTAssertEqual(submodule.tapStreak, 0)
        XCTAssertEqual(tapBursts(view).count, 1)
        XCTAssertTrue(view.diamondLayer.hasStarBursts)
        XCTAssertEqual(view.diamondLayer.renderSize, CGSize(width: 240, height: 240))
    }

    func testTapStreakRestartsAfterASecondLikeSubmodule() throws {
        try XCTSkipIf(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, "reduce motion turns tap spin off")
        let view = chatCardDiamond()
        defer { view.diamondLayer.isInHierarchy = false }
        let releaseDecay = view.diamondLayer.diamondStyle.releaseDecay
        var submodule = SubmoduleTapSpin()
        for direction: Float in [1, 1] {
            let time = tap(view, direction: direction)
            _ = submodule.tap(current: actualSpin(view).atPress, direction: direction, at: time, releaseDecay: releaseDecay)
        }
        XCTAssertEqual(submodule.tapStreak, 2)
        Thread.sleep(forTimeInterval: 1.1)
        let time = tap(view, direction: -1)
        let actual = actualSpin(view)
        let expected = submodule.tap(current: actual.atPress, direction: -1, at: time, releaseDecay: releaseDecay)
        XCTAssertEqual(submodule.tapStreak, 1)
        XCTAssertEqual(actual.velocity, expected.velocity, accuracy: 1e-5)
        XCTAssertEqual(actual.decay, expected.decay, accuracy: 1e-6)
        XCTAssertTrue(tapBursts(view).isEmpty)
    }

    func testTapSpinStopsWhenHiddenOrSendingLikeSubmodule() throws {
        try XCTSkipIf(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, "reduce motion turns tap spin off")
        let hidden = chatCardDiamond()
        for _ in 0 ..< 4 {
            _ = tap(hidden, direction: 1)
        }
        XCTAssertEqual(actualSpin(hidden).velocity, 16, accuracy: 1e-5)
        XCTAssertFalse(tapBursts(hidden).isEmpty)
        hidden.isRenderingEnabled = false
        XCTAssertEqual(actualSpin(hidden).velocity, 0)
        XCTAssertTrue(tapBursts(hidden).isEmpty)
        hidden.diamondLayer.isInHierarchy = false

        let sending = chatCardDiamond()
        defer { sending.diamondLayer.isInHierarchy = false }
        _ = tap(sending, direction: 1)
        XCTAssertEqual(actualSpin(sending).velocity, 5, accuracy: 1e-5)
        sending.updateTransferState(isSending: true, animateCompletion: false)
        XCTAssertEqual(actualSpin(sending).velocity, 0)
        _ = tap(sending, direction: 1)
        XCTAssertEqual(actualSpin(sending).velocity, 0)
        XCTAssertTrue(tapBursts(sending).isEmpty)
    }

    func testOnlyTheCardDiamondsSpinOnTapLikeSubmodule() throws {
        try XCTSkipIf(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, "reduce motion turns tap spin off")
        for use in diamondUses where use.animationMode == .continuous && !use.tapToSpin {
            let view = actualDiamondView(use)
            view.diamondLayer.isInHierarchy = true
            _ = tap(view, direction: 1)
            XCTAssertEqual(actualSpin(view).velocity, 0, use.name)
            XCTAssertTrue(tapBursts(view).isEmpty, use.name)
            view.diamondLayer.isInHierarchy = false
        }
    }

    private func mouseEvent(_ type: NSEvent.EventType, at point: CGPoint, window: NSWindow) -> NSEvent {
        return NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: type == .leftMouseUp ? 0 : 1)!
    }

    private func clickDiamond(_ useName: String = "chat transfer card", at points: [CGPoint], holdFor delay: TimeInterval = 0, prepare: ((InteractiveDiamondView) -> Void)? = nil, inspect: ((InteractiveDiamondView) -> Void)? = nil) -> (direction: Float?, velocity: Float, lastTapTime: CFTimeInterval?, bounds: CGRect) {
        _ = NSApplication.shared
        let use = diamondUses.first(where: { $0.name == useName })!
        let window = NSWindow(contentRect: CGRect(x: 200, y: 200, width: 200, height: 200), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let view = actualDiamondView(use)
        window.contentView?.addSubview(view)
        defer {
            view.removeFromSuperview()
            window.close()
        }
        prepare?(view)
        let layerPosition = view.diamondLayer.position
        let down = mouseEvent(.leftMouseDown, at: points[0], window: window)
        var followUps = points.dropFirst().dropLast().map { mouseEvent(.leftMouseDragged, at: $0, window: window) }
        followUps.append(mouseEvent(.leftMouseUp, at: points[points.count - 1], window: window))
        if delay > 0 {
            DispatchQueue.global().asyncAfter(deadline: .now() + delay) {
                for event in followUps {
                    NSApp.postEvent(event, atStart: false)
                }
            }
        } else {
            for event in followUps {
                NSApp.postEvent(event, atStart: false)
            }
        }
        let pressTime = CACurrentMediaTime()
        view.mouseDown(with: down)
        let releaseTime = CACurrentMediaTime()
        let start = view.convert(points[0], from: nil)
        let end = view.convert(points[points.count - 1], from: nil)
        let direction = submoduleTapDirection(pressStart: (start, pressTime), position: end, now: releaseTime, bounds: view.bounds, layerPosition: layerPosition, expansionStyle: use.expansionStyle, tapToSpin: use.tapToSpin)
        let lastTapTime: CFTimeInterval? = mirrored(view.diamondLayer, "lastTapTime")
        inspect?(view)
        return (direction, actualSpin(view).velocity, lastTapTime, view.bounds)
    }

    private func walletCardDiamond() -> InteractiveDiamondView {
        let view = actualDiamondView(diamondUses.first(where: { $0.name == "wallet card" })!)
        view.diamondLayer.isInHierarchy = true
        return view
    }

    func testWalletTiltMatchesSubmodule() throws {
        let use = diamondUses.first(where: { $0.name == "wallet card" })!
        let view = walletCardDiamond()
        defer { view.diamondLayer.isInHierarchy = false }
        for (pitch, roll, scale) in [(CGFloat(0.08), CGFloat(-0.05), CGFloat(1.1)), (-0.12, 0.2, 1.0), (0, 0, 1.16)] {
            let expected = submoduleWalletTilt(view.diamondLayer.diamondStyle, diamondWidth: use.diamondWidth, pitch: pitch, roll: roll, scale: scale)
            view.updateWalletTilt(pitch: pitch, roll: roll, scale: scale, leftInset: .greatestFiniteMagnitude)
            XCTAssertEqual(view.diamondLayer.diamondStyle, expected, "pitch \(pitch) roll \(roll) scale \(scale)")
        }

        view.updateWalletTilt(pitch: 0.08, roll: -0.05, scale: 1.1, leftInset: .greatestFiniteMagnitude)
        view.update(size: use.size, diamondWidth: use.diamondWidth, isVisible: true, lightBackground: true, appearance: use.appearance, expansionStyle: use.expansionStyle, tapToSpin: use.tapToSpin)
        XCTAssertEqual(view.diamondLayer.diamondStyle.widthPoints, Float(use.diamondWidth * 1.1))
        XCTAssertEqual(view.diamondLayer.diamondStyle.tilt, Float(-0.08 * 2.8))
        XCTAssertEqual(view.diamondLayer.diamondStyle.lean, Float(-0.05 * 2.6))

        let chat = chatCardDiamond()
        defer { chat.diamondLayer.isInHierarchy = false }
        let chatStyle = chat.diamondLayer.diamondStyle
        chat.updateWalletTilt(pitch: 0.08, roll: -0.05, scale: 1.1, leftInset: 0)
        XCTAssertEqual(chat.diamondLayer.diamondStyle, chatStyle)
        XCTAssertEqual(chat.diamondLayer.position, CGPoint(x: 32, y: 32))
    }

    func testWalletDiamondStaysClearOfTheCardEdgeLikeSubmodule() {
        let use = diamondUses.first(where: { $0.name == "wallet card" })!
        let view = walletCardDiamond()
        defer { view.diamondLayer.isInHierarchy = false }
        for (leftInset, scale, zoom) in [(CGFloat(400), CGFloat(1), Float(1)), (8, 1, 1), (8, 1.16, 1), (8, 1, 1.6), (2, 1.16, 0.6), (40, 1, 1.6)] {
            view.updateWalletTilt(pitch: 0, roll: 0, scale: scale, leftInset: leftInset)
            view.diamondLayer.zoom = zoom
            let expected = submoduleWalletCenterX(restingSize: use.size, diamondWidth: use.diamondWidth, grow: view.diamondLayer.pose.grow, zoom: view.diamondLayer.zoom, walletScale: scale, walletLeftInset: leftInset)
            XCTAssertEqual(view.diamondLayer.position.x, expected, accuracy: 1e-9, "inset \(leftInset) scale \(scale) zoom \(zoom)")
            XCTAssertEqual(view.diamondLayer.position.y, use.size.height / 2)
        }
        view.updateWalletTilt(pitch: 0, roll: 0, scale: 1, leftInset: 8)
        view.diamondLayer.zoom = 1
        XCTAssertGreaterThan(view.diamondLayer.position.x, use.size.width / 2)
    }

    func testWalletDiamondTakesClicksOnACircleLikeSubmodule() {
        let use = diamondUses.first(where: { $0.name == "wallet card" })!
        let container = NSView(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
        let view = walletCardDiamond()
        defer { view.diamondLayer.isInHierarchy = false }
        container.addSubview(view)
        for (scale, leftInset) in [(CGFloat(1), CGFloat(400)), (1.16, 400), (1, 6)] {
            view.updateWalletTilt(pitch: 0, roll: 0, scale: scale, leftInset: leftInset)
            let center = view.diamondLayer.position
            let radius = use.size.width * (30.0 * 0.9 / 96.0) * scale
            for step in 0 ..< 16 {
                let angle = CGFloat(step) * .pi / 8
                for distance in [radius - 0.5, radius + 0.5] {
                    let point = CGPoint(x: center.x + cos(angle) * distance, y: center.y + sin(angle) * distance)
                    let expected = submoduleWalletPointInside(point, restingSize: use.size, layerPosition: center, walletScale: scale)
                    let hit = view.hitTest(container.convert(point, from: view))
                    XCTAssertEqual(hit === view, expected, "scale \(scale) inset \(leftInset) angle \(angle) distance \(distance)")
                }
            }
        }
        view.isInteractionEnabled = false
        XCTAssertNil(view.hitTest(container.convert(view.diamondLayer.position, from: view)))
    }

    func testClickOnTheWalletDiamondSpinsTowardTheStoneLikeSubmodule() throws {
        try XCTSkipIf(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, "reduce motion turns tap spin off")
        let shift: (InteractiveDiamondView) -> Void = { view in
            view.updateWalletTilt(pitch: 0, roll: 0, scale: 1, leftInset: 4)
        }
        let beforeStone = clickDiamond("wallet card", at: [CGPoint(x: 53, y: 48), CGPoint(x: 54, y: 48)], prepare: shift)
        XCTAssertEqual(beforeStone.direction, -1)
        XCTAssertEqual(beforeStone.velocity, -5, accuracy: 1e-5)
        XCTAssertGreaterThan(53, beforeStone.bounds.midX)

        let afterStone = clickDiamond("wallet card", at: [CGPoint(x: 64, y: 48), CGPoint(x: 64, y: 49)], prepare: shift)
        XCTAssertEqual(afterStone.direction, 1)
        XCTAssertEqual(afterStone.velocity, 5, accuracy: 1e-5)

        let dragged = clickDiamond("wallet card", at: [CGPoint(x: 40, y: 48), CGPoint(x: 46, y: 48), CGPoint(x: 52, y: 48)])
        XCTAssertNil(dragged.direction)
        XCTAssertNil(dragged.lastTapTime)
    }

    func testFlungCardDiamondsThrowNoStarsLikeSubmodule() throws {
        try XCTSkipIf(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, "reduce motion turns flings off")
        for name in ["wallet card", "chat transfer card"] {
            let use = diamondUses.first(where: { $0.name == name })!
            let allowsFlingBurst = use.expansionStyle == .wallet
            var bursts: [DiamondStarBurst] = []
            var burstsAfterTilt: [DiamondStarBurst] = []
            var spin: Float = 0
            var hasTapRotation = false
            _ = clickDiamond(name, at: [CGPoint(x: 10, y: 30), CGPoint(x: 30, y: 30), CGPoint(x: 50, y: 30)], inspect: { view in
                bursts = mirrored(view.diamondLayer, "starBursts") ?? []
                spin = self.actualSpin(view).velocity
                let motion: DiamondMotion = mirrored(view.diamondLayer, "motion")!
                hasTapRotation = Mirror(reflecting: motion).children.first(where: { $0.label == "tapRotation" }).map { String(describing: $0.value) != "nil" } ?? false
                view.updateWalletTilt(pitch: 0.1, roll: 0.1, scale: 1.1, leftInset: 400)
                burstsAfterTilt = mirrored(view.diamondLayer, "starBursts") ?? []
            })
            if allowsFlingBurst {
                XCTAssertTrue(hasTapRotation, name)
                XCTAssertEqual(spin, 5, accuracy: 1e-5, name)
            } else {
                XCTAssertFalse(hasTapRotation, name)
                XCTAssertEqual(spin, 3.0 * 6.5, accuracy: 1e-5, name)
            }
            XCTAssertTrue(bursts.isEmpty, name)
            XCTAssertTrue(burstsAfterTilt.isEmpty, name)
        }
    }

    private func assertStarsKeepTheSubmoduleScale(_ view: InteractiveDiamondView, file: StaticString = #filePath, line: UInt = #line) {
        let canvas = view.diamondLayer.renderSize ?? .zero
        let submodule = DiamondMath.projection(aspect: 1, zoom: 1, perspective: false)
        let submoduleSide = submoduleStarRenderSide
        let referenceSize = view.diamondLayer.diamondStyle.starReferenceSize
        let zoom = referenceSize > 0 ? referenceSize / Float(max(1, min(canvas.width, canvas.height))) : 1
        let actual = DiamondMath.projection(aspect: Float(canvas.width / max(canvas.height, 1)), zoom: zoom, perspective: false)
        XCTAssertEqual(CGFloat(actual.columns.0.x) * canvas.width / 2, CGFloat(submodule.columns.0.x) * submoduleSide / 2, accuracy: 1e-3, file: file, line: line)
        XCTAssertEqual(CGFloat(actual.columns.1.y) * canvas.height / 2, CGFloat(submodule.columns.1.y) * submoduleSide / 2, accuracy: 1e-3, file: file, line: line)
        XCTAssertEqual(CGFloat(actual.columns.3.y) * canvas.height / 2, CGFloat(submodule.columns.3.y) * submoduleSide / 2, accuracy: 1e-3, file: file, line: line)
    }

    func testOnlyTheChatCardDiamondThrowsStarsLikeSubmodule() throws {
        try XCTSkipIf(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, "reduce motion turns tap spin off")
        let view = walletCardDiamond()
        view.starContainer = CGRect(x: -2, y: -10, width: 360, height: 216)
        for _ in 0 ..< 4 {
            _ = tap(view, direction: 1)
        }
        XCTAssertFalse(view.diamondLayer.hasStarBursts)
        view.diamondLayer.isInHierarchy = false

        let chat = chatCardDiamond()
        defer { chat.diamondLayer.isInHierarchy = false }
        for _ in 0 ..< 4 {
            _ = tap(chat, direction: 1)
        }
        XCTAssertTrue(chat.diamondLayer.hasStarBursts)
        XCTAssertEqual(chat.diamondLayer.renderSize, CGSize(width: submoduleStarRenderSide, height: submoduleStarRenderSide))
        XCTAssertEqual(chat.diamondLayer.diamondStyle.starReferenceSize, 0)
        assertStarsKeepTheSubmoduleScale(chat)
    }

    func testWalletPinchZoomMatchesSubmodule() {
        let view = walletCardDiamond()
        defer { view.diamondLayer.isInHierarchy = false }
        var submodule = SubmodulePinchZoom()
        var magnification: CGFloat = 0
        let gestures: [[(NSEvent.Phase, CGFloat)]] = [
            [(.began, 0.1), (.changed, 0.2), (.changed, 0.15), (.ended, 0)],
            [(.began, 0.2), (.changed, 0.4), (.ended, 0)],
            [(.began, -0.3), (.changed, -0.4), (.changed, -0.2), (.cancelled, 0)],
            [(.began, 0.05), (.changed, 0.1), (.ended, 0)]
        ]
        for (index, gesture) in gestures.enumerated() {
            for (phase, delta) in gesture {
                XCTAssertTrue(view.updateMagnification(phase: phase, delta: delta))
                if phase == .began {
                    magnification = 0
                }
                let isActive = phase == .began || phase == .changed
                if isActive {
                    magnification += delta
                }
                submodule.pinch(isActive: isActive, scale: 1 + magnification)
                XCTAssertEqual(view.diamondLayer.zoom, submodule.zoom, accuracy: 1e-6, "gesture \(index + 1)")
            }
        }
        XCTAssertEqual(view.diamondLayer.zoom, submodule.zoom, accuracy: 1e-6)

        XCTAssertTrue(view.updateMagnification(phase: .began, delta: 0.1))
        let zoomBeforeCancel = view.diamondLayer.zoom
        view.cancelInteraction()
        XCTAssertTrue(view.updateMagnification(phase: .changed, delta: 0.3))
        XCTAssertEqual(view.diamondLayer.zoom, zoomBeforeCancel)

        let chat = chatCardDiamond()
        defer { chat.diamondLayer.isInHierarchy = false }
        XCTAssertFalse(chat.updateMagnification(phase: .began, delta: 0.3))
        XCTAssertEqual(chat.diamondLayer.zoom, 1)
        view.isInteractionEnabled = false
        XCTAssertFalse(view.updateMagnification(phase: .began, delta: 0.3))
    }

    func testLeanFollowsSubmoduleSpring() throws {
        let source = try submoduleSource("DiamondAnimation.swift")
        XCTAssertTrue(source.contains("leanVelocity += ((targetLean - lean) * 110 - 2 * 0.55 * 10.5 * leanVelocity) * step"))
        XCTAssertTrue(source.contains("let step = min(leanRemaining, 1 / Float(240))"))
        for target: Float in [0.3, -0.18, 0] {
            var motion = DiamondMotion()
            var submodule = SubmoduleLean()
            motion.targetLean = 0.2
            submodule.targetLean = 0.2
            for _ in 0 ..< 30 {
                motion.step(dt: 1 / 60, speed: 0, reduceMotion: false)
                submodule.step(dt: 1 / 60, reduceMotion: false)
            }
            motion.targetLean = target
            submodule.targetLean = target
            for frame in 1 ... 240 {
                motion.step(dt: 1 / 60, speed: 0, reduceMotion: false)
                submodule.step(dt: 1 / 60, reduceMotion: false)
                XCTAssertEqual(motion.lean, submodule.lean, accuracy: 1e-6, "target \(target) frame \(frame)")
            }
            XCTAssertEqual(motion.lean, target)
        }
        var reduced = DiamondMotion()
        reduced.targetLean = 0.4
        reduced.step(dt: 1 / 60, speed: 0, reduceMotion: true)
        XCTAssertEqual(reduced.lean, 0.4)
    }

    func testWalletLeanTurnsThePoseLikeSubmodule() {
        let view = walletCardDiamond()
        defer { view.diamondLayer.isInHierarchy = false }
        view.updateWalletTilt(pitch: 0, roll: 0.1, scale: 1, leftInset: 400)
        let motion: DiamondMotion = mirrored(view.diamondLayer, "motion")!
        XCTAssertEqual(motion.targetLean, Float(0.1 * 2.6))
        XCTAssertEqual(view.diamondLayer.pose.yaw, motion.yaw + motion.lean)
    }

    func testClickOnTheChatCardDiamondDetectsTapsLikeSubmodule() throws {
        try XCTSkipIf(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, "reduce motion turns tap spin off")
        let left = clickDiamond(at: [CGPoint(x: 12, y: 30), CGPoint(x: 14, y: 33)])
        XCTAssertEqual(left.direction, -1)
        XCTAssertEqual(left.velocity, -5, accuracy: 1e-5)
        XCTAssertNotNil(left.lastTapTime)

        let right = clickDiamond(at: [CGPoint(x: 50, y: 30), CGPoint(x: 52, y: 28)])
        XCTAssertEqual(right.direction, 1)
        XCTAssertEqual(right.velocity, 5, accuracy: 1e-5)

        let dragged = clickDiamond(at: [CGPoint(x: 12, y: 30), CGPoint(x: 20, y: 30), CGPoint(x: 26, y: 30)])
        XCTAssertNil(dragged.direction)
        XCTAssertNil(dragged.lastTapTime)

        let held = clickDiamond(at: [CGPoint(x: 12, y: 30), CGPoint(x: 12, y: 30)], holdFor: 0.35)
        XCTAssertNil(held.direction)
        XCTAssertNil(held.lastTapTime)
        XCTAssertEqual(held.velocity, 0, accuracy: 1e-5)
    }

    func testHighlightPushMatchesSubmodule() throws {
        try XCTSkipIf(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, "reduce motion turns the push off")
        var pushed = DiamondMotion()
        pushed.pushFromBelow(strength: 1.5)
        let velocity: Float = try XCTUnwrap(mirrored(pushed, "pitchSpringVelocity"))
        XCTAssertEqual(velocity, -1.5, accuracy: 1e-6)
        XCTAssertTrue(pushed.isAppearanceImpulseActive)

        let view = chatCardDiamond()
        defer { view.diamondLayer.isInHierarchy = false }
        let before: DiamondMotion = try XCTUnwrap(mirrored(view.diamondLayer, "motion"))
        XCTAssertFalse(before.isAppearanceImpulseActive)
        view.pushFromBelow(strength: 1.5)
        let after: DiamondMotion = try XCTUnwrap(mirrored(view.diamondLayer, "motion"))
        XCTAssertTrue(after.isAppearanceImpulseActive)
        XCTAssertFalse(view.diamondLayer.usesHighFrameRate)
        XCTAssertEqual(view.diamondLayer.renderSize, diamondUses.first(where: { $0.name == "chat transfer card" })!.size)

        let hidden = chatCardDiamond()
        hidden.isRenderingEnabled = false
        hidden.pushFromBelow(strength: 1.5)
        let hiddenMotion: DiamondMotion = try XCTUnwrap(mirrored(hidden.diamondLayer, "motion"))
        XCTAssertFalse(hiddenMotion.isAppearanceImpulseActive)
        hidden.diamondLayer.isInHierarchy = false
    }

    func testRefractionSourceKeepsTheCardColorsLikeSubmodule() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: 4, height: 4, mipmapped: false)
        let texture = try XCTUnwrap(device.makeTexture(descriptor: descriptor))
        let rect = CGRect(x: -20, y: 10, width: 40, height: 20)
        let source = InteractiveDiamondView.RefractionSource(texture: texture, uv: SIMD4(0, 0, 1, 1), rect: rect, preservesColors: true)
        XCTAssertEqual(source, InteractiveDiamondView.RefractionSource(texture: texture, uv: SIMD4(0, 0, 1, 1), rect: rect, preservesColors: true))
        XCTAssertNotEqual(source, InteractiveDiamondView.RefractionSource(texture: texture, uv: SIMD4(0, 0, 1, 1), rect: rect))

        let view = chatCardDiamond()
        defer { view.diamondLayer.isInHierarchy = false }
        view.updateRefractionSource(source)
        XCTAssertEqual(view.diamondLayer.refractionSource?.preservesColors, true)
        XCTAssertEqual(view.diamondLayer.refractionSource?.rect, rect)
    }

    private func landingDiamond(_ useName: String = "chat transfer card") -> (view: InteractiveDiamondView, window: NSWindow) {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: CGRect(x: 200, y: 200, width: 200, height: 200), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let view = actualDiamondView(diamondUses.first(where: { $0.name == useName })!)
        window.contentView?.addSubview(view)
        return (view, window)
    }

    private func waitForLanding(_ seconds: TimeInterval = 0.35) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    func testLandingFeedbackMatchesSubmodule() throws {
        let (view, window) = landingDiamond()
        defer {
            view.removeFromSuperview()
            window.close()
        }
        let canLand = NSApp.isActive
        var landed: [CGFloat] = []
        view.onLanding = { landed.append($0) }
        for power: CGFloat in [-0.1, 0.0, 0.05, 0.2, 0.5, 1.0, 1.7] {
            landed.removeAll()
            let expected = submoduleLandingPower(power, isHolding: false, hasListener: true)
            view.scheduleLandingFeedback(power: power)
            let scheduled: DispatchWorkItem? = mirrored(view, "landingFeedback")
            XCTAssertEqual(scheduled != nil, expected != nil, "power \(power)")
            waitForLanding(0.1)
            XCTAssertTrue(landed.isEmpty, "power \(power) lands only after 0.2 s")
            waitForLanding()
            XCTAssertEqual(landed, canLand ? expected.map { [$0] } ?? [] : [], "power \(power)")
            XCTAssertNil(mirrored(view, "landingFeedback") as DispatchWorkItem?, "power \(power)")
        }

        view.diamondLayer.updateDrag(state: .began)
        view.scheduleLandingFeedback(power: 0.6)
        XCTAssertNil(submoduleLandingPower(0.6, isHolding: true, hasListener: true))
        XCTAssertNil(mirrored(view, "landingFeedback") as DispatchWorkItem?)
        view.diamondLayer.updateDrag(state: .cancelled)

        view.onLanding = nil
        view.scheduleLandingFeedback(power: 0.6)
        XCTAssertNil(mirrored(view, "landingFeedback") as DispatchWorkItem?)
    }

    func testLandingIsCancelledLikeSubmodule() {
        let (view, window) = landingDiamond()
        defer {
            view.removeFromSuperview()
            window.close()
        }
        var landed: [CGFloat] = []
        view.onLanding = { landed.append($0) }

        view.scheduleLandingFeedback(power: 0.6)
        XCTAssertNotNil(mirrored(view, "landingFeedback") as DispatchWorkItem?)
        view.cancelInteraction()
        XCTAssertNil(mirrored(view, "landingFeedback") as DispatchWorkItem?)

        view.scheduleLandingFeedback(power: 0.6)
        view.isInteractionEnabled = false
        XCTAssertNil(mirrored(view, "landingFeedback") as DispatchWorkItem?)
        view.isInteractionEnabled = true

        view.scheduleLandingFeedback(power: 0.6)
        view.removeFromSuperview()
        XCTAssertNil(mirrored(view, "landingFeedback") as DispatchWorkItem?)

        waitForLanding()
        XCTAssertTrue(landed.isEmpty)
    }

    func testHeldReleaseSchedulesLandingOnlyOffTheWalletCardLikeSubmodule() throws {
        try XCTSkipIf(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, "reduce motion keeps the stone from growing")
        for name in ["chat transfer card", "wallet card"] {
            var scheduled: DispatchWorkItem?
            var strength: Float = 0
            _ = clickDiamond(name, at: [CGPoint(x: 32, y: 32), CGPoint(x: 36, y: 32), CGPoint(x: 36, y: 32)], holdFor: 0.4, prepare: { view in
                view.onLanding = { _ in }
                view.onMotionUpdated = { [weak view] _ in
                    if let view, view.isExpanded {
                        strength = max(strength, view.diamondLayer.refractionStrength)
                    }
                }
            }, inspect: { view in
                scheduled = mirrored(view, "landingFeedback")
            })
            XCTAssertGreaterThan(strength, 0, name)
            if name == "wallet card" {
                XCTAssertNil(scheduled, name)
            } else {
                XCTAssertNotNil(scheduled, name)
            }
        }
    }

    func testSubmoduleLandingStillUsesTheCopiedRules() throws {
        let component = try String(contentsOf: repositoryRoot().appendingPathComponent("submodules/telegram-ios/submodules/TelegramUI/Components/Premium/PremiumDiamondComponent/Sources/PremiumDiamondComponent.swift"), encoding: .utf8)
        for line in [
            "if gesture.state == .ended, wasHolding, self.expansionStyle != .wallet {",
            "self.scheduleLandingFeedback(power: releasePower)",
            "let releasePower = CGFloat(self.diamondLayer.refractionStrength)",
            "guard power > 0.0, (power > 0.2 || self.onLanding != nil), !self.isHolding else { return }",
            "!self.isHolding, UIApplication.shared.applicationState == .active else { return }",
            "self.onLanding?(min(1.0, power))",
            "DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: impact)",
            "style.starOpacity = component.expansionStyle == .wallet ? 0.0 : 1.0",
            "style.rightwardStars = component.expansionStyle == .wallet",
            "style.starReferenceSize = component.expansionStyle == .wallet ? 240.0 : 0.0"
        ] {
            XCTAssertTrue(component.contains(line), line)
        }
    }

    func testChatCardLandingBumpMatchesSubmodule() throws {
        let submodule = try String(contentsOf: repositoryRoot().appendingPathComponent("submodules/telegram-ios/submodules/TelegramUI/Components/Chat/ChatMessageTransferBubbleContentNode/Sources/ChatMessageTransferBubbleContentNode.swift"), encoding: .utf8)
        let actual = try String(contentsOf: repositoryRoot().appendingPathComponent("packages/ChatUI/Sources/ChatUI/ChatServiceItem.swift"), encoding: .utf8)
        let submoduleBump = try XCTUnwrap(submodule.range(of: "private func animateDiamondLandingBump(power: CGFloat) {").map { String(submodule[$0.lowerBound...].prefix(900)) })
        let actualBump = try XCTUnwrap(actual.range(of: "private func animateDiamondLandingBump(power: CGFloat) {").map { String(actual[$0.lowerBound...].prefix(1300)) })
        for line in [
            "!self.isSendingTransfer",
            "!UIAccessibility.isReduceMotionEnabled",
            "let duration = 1.0",
            "let frameCount = Int(duration * 120.0)",
            "let bounce = index == frameCount ? 0.0 : sin(2.0 * .pi * 2.4 * time) * exp(-time / 0.2)",
            "return NSNumber(value: 1.0 - 0.05 * Double(power) * bounce)",
            "self.mediaContainerNode.layer.animateKeyframes(",
            "keyPath: \"sublayerTransform.scale\""
        ] {
            XCTAssertTrue(submoduleBump.contains(line), line)
        }
        for line in [
            "!NSWorkspace.shared.accessibilityDisplayShouldReduceMotion",
            "let center = NSMakePoint(frame.width / 2, frame.height / 2)",
            "let duration = 1.0",
            "let frameCount = Int(duration * 120)",
            "let bounce = index == frameCount ? 0 : sin(2 * Double.pi * 2.4 * time) * exp(-time / 0.2)",
            "let scale = 1 - 0.05 * power * CGFloat(bounce)",
            "bump.timingFunction = CAMediaTimingFunction(name: .linear)",
            "bump.isAdditive = true"
        ] {
            XCTAssertTrue(actualBump.contains(line), line)
        }
        XCTAssertTrue(submodule.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).contains("diamond.onLanding = { [weak self] power in self?.animateDiamondLandingBump(power: power) }"))
        XCTAssertTrue(submodule.contains("self.mediaContainerNode.layer.removeAnimation(forKey: \"sublayerTransform.scale\")"))
        XCTAssertTrue(actual.contains("cardView.onDiamondLanding = { [weak self] power in\n            self?.animateDiamondLandingBump(power: power)"))
    }

    func testDiamondKeepsAnimatingWhileTheAppIsInactiveLikeSubmodule() throws {
        let source = try submoduleSource("InteractiveDiamondLayer.swift").replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        XCTAssertTrue(source.contains("guard self.isInHierarchy, self.isApplicationInForeground, self.isRenderingEnabled, !self.reduceMotion else { return nil }"))
        XCTAssertTrue(source.contains("private var isApplicationInForeground = UIApplication.shared.applicationState != .background"))
        XCTAssertTrue(source.contains("name: UIApplication.didEnterBackgroundNotification"))
        XCTAssertFalse(source.contains("UIApplication.willResignActiveNotification"))
        XCTAssertFalse(source.contains("isApplicationActive"))

        let view = chatCardDiamond()
        XCTAssertNotNil(view.diamondLayer.animationState)
        NotificationCenter.default.post(name: NSApplication.willResignActiveNotification, object: NSApp)
        XCTAssertNotNil(view.diamondLayer.animationState)
        NotificationCenter.default.post(name: NSApplication.didResignActiveNotification, object: NSApp)
        XCTAssertNotNil(view.diamondLayer.animationState)
        view.diamondLayer.isInHierarchy = false
        XCTAssertNil(view.diamondLayer.animationState)
    }

    func testExternalYawAddsToTheRenderedYawLikeSubmodule() {
        var motion = DiamondMotion()
        let resting = motion.renderedYaw
        XCTAssertEqual(resting, motion.yaw + motion.lean, accuracy: 1e-6)
        motion.externalYaw = 0.37
        XCTAssertEqual(motion.renderedYaw, motion.yaw + motion.lean + 0.37, accuracy: 1e-6)
        XCTAssertEqual(motion.renderedYaw - resting, 0.37, accuracy: 1e-6)
        motion.externalYaw = 0
        XCTAssertEqual(motion.renderedYaw, resting, accuracy: 1e-6)
    }
}
