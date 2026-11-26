import AppKit
import XCTest
import TGUIKit
@testable import Effects

final class EffectsTests: XCTestCase {
    override func setUp() { _ = NSApplication.shared; NSApp.setActivationPolicy(.accessory); System.updateScaleFactor(2) }
    private func emitters(_ layer: CALayer) -> [CAEmitterLayer] { layer.sublayers!.compactMap { $0 as? CAEmitterLayer } }
    private func colors(_ emitter: CAEmitterLayer) -> [CGColor] {
        let behavior = (emitter.emitterCells![0].value(forKey: "emitterBehaviors") as! [NSObject])[0]
        return behavior.value(forKey: "colors") as! [CGColor]
    }
    private func behavior(_ emitter: CAEmitterLayer) -> NSObject {
        (emitter.emitterCells![0].value(forKey: "emitterBehaviors") as! [NSObject])[0]
    }
    private func assertEqual(_ old: CALayer, _ new: CALayer, file: StaticString = #filePath, line: UInt = #line) {
        let a = emitters(old), b = emitters(new)
        XCTAssertEqual(a.count, b.count, file: file, line: line)
        for (first, second) in zip(a, b) {
            XCTAssertEqual(first.frame, second.frame, file: file, line: line)
            XCTAssertEqual(first.emitterPosition, second.emitterPosition, file: file, line: line)
            XCTAssertEqual(first.emitterSize, second.emitterSize, file: file, line: line)
            XCTAssertEqual(first.emitterShape, second.emitterShape, file: file, line: line)
            XCTAssertEqual(first.emitterMode, second.emitterMode, file: file, line: line)
            XCTAssertEqual(first.birthRate, second.birthRate, file: file, line: line)
            XCTAssertEqual(colors(first), colors(second), file: file, line: line)
            let x = first.emitterCells![0], y = second.emitterCells![0]
            for key in ["birthRate", "lifetime", "velocity", "velocityRange", "scale", "scaleRange", "alphaRange", "emissionRange", "mass", "massRange"] {
                XCTAssertEqual(x.value(forKey: key) as? NSNumber, y.value(forKey: key) as? NSNumber, key, file: file, line: line)
            }
            let image = x.contents as! CGImage, other = y.contents as! CGImage
            XCTAssertEqual(image.width, other.width, file: file, line: line)
            XCTAssertEqual(image.height, other.height, file: file, line: line)
            XCTAssertEqual(image.dataProvider!.data! as Data, other.dataProvider!.data! as Data, file: file, line: line)
        }
    }
    func testInitialConfigurationMatchesRepairedReference() {
        for color in [NSColor.red, .white, .clear, NSColor(displayP3Red: 0.8, green: 0.2, blue: 0.4, alpha: 0.3)] {
            for size in [CGSize.zero, CGSize(width: 30, height: 20), CGSize(width: 100, height: 30), CGSize(width: 123.5, height: 45.25)] {
                let old = ReferenceButton(), new = CandidateButton()
                old.color = color; new.color = color
                old.update(size: size); new.update(size: size)
                assertEqual(old, new)
                let oldBadge = ReferenceBadge(frame: .zero), newBadge = CandidateBadge(frame: .zero)
                oldBadge.color = color; newBadge.color = color
                let position = CGPoint(x: size.width / 3, y: size.height / 2)
                oldBadge.update(size: size, emitterPosition: position)
                newBadge.update(size: size, emitterPosition: position)
                assertEqual(oldBadge.layer!, newBadge.layer!)
            }
        }
    }
    func testSharedParticleAssetIsNonblankAndHasIdentityAcrossEffects() {
        let button = CandidateButton(), badge = CandidateBadge(frame: .zero)
        button.update(size: CGSize(width: 40, height: 30))
        badge.update(size: CGSize(width: 40, height: 30), emitterPosition: .zero)
        let image = button.emitterLayer.emitterCells![0].contents as! CGImage
        XCTAssertTrue((image.dataProvider!.data! as Data).contains { $0 != 0 })
        for emitter in emitters(badge.layer!) {
            XCTAssertTrue(emitter.emitterCells![0].contents as! CGImage === image)
        }
    }
    func testOriginalSelfReferenceProducesMissingParticleTextures() {
        let broken = BrokenBadge(frame: .zero)
        broken.update(size: CGSize(width: 100, height: 30), emitterPosition: .zero)
        XCTAssertEqual(emitters(broken.layer!).count, 2)
        XCTAssertTrue(emitters(broken.layer!).allSatisfy { $0.emitterCells![0].contents == nil })
    }
    func testUnchangedGeometryAndColorsKeepCellsBehaviorsAndTimeline() {
        let button = CandidateButton(), badge = CandidateBadge(frame: .zero)
        let size = CGSize(width: 100, height: 30), position = CGPoint(x: 50, y: 15)
        button.update(size: size); badge.update(size: size, emitterPosition: position)
        let layers = [button.emitterLayer] + emitters(badge.layer!)
        let behaviors = layers.map(behavior)
        for (index, layer) in layers.enumerated() { layer.seed = UInt32(index + 10); layer.beginTime = 42 }
        for _ in 0..<1000 {
            button.update(size: size); badge.update(size: size, emitterPosition: position)
            button.color = NSColor(0xffbe27); badge.color = NSColor(0xffbe27)
        }
        for (index, layer) in layers.enumerated() {
            XCTAssertTrue(behavior(layer) === behaviors[index])
            XCTAssertEqual(layer.seed, UInt32(index + 10))
            XCTAssertEqual(layer.beginTime, 42)
        }
    }
    func testResizeAndMovementMatchReferenceWithoutReplacingColorBehavior() {
        let old = ReferenceBadge(frame: .zero), new = CandidateBadge(frame: .zero)
        let oldButton = ReferenceButton(), newButton = CandidateButton()
        for width in [CGFloat(100), 40, 200, 100] {
            let size = CGSize(width: width, height: 30)
            for x in [CGFloat(0), 15, 100] {
                let point = CGPoint(x: x, y: 15)
                old.update(size: size, emitterPosition: point); new.update(size: size, emitterPosition: point)
                assertEqual(old.layer!, new.layer!)
                let attractor = (new.layer!.sublayers![0].value(forKey: "emitterBehaviors") as! [NSObject])[0]
                XCTAssertEqual(attractor.value(forKey: "position") as? CGPoint, point)
            }
            oldButton.update(size: size); newButton.update(size: size)
            assertEqual(oldButton, newButton)
        }
    }
    func testColorChangesRefreshBothEffectsAndPreservePlaybackAndMotion() {
        let button = CandidateButton(), badge = CandidateBadge(frame: .zero)
        let size = CGSize(width: 100, height: 30)
        button.update(size: size); badge.update(size: size, emitterPosition: .zero)
        button.isPlaying = false
        badge.update(speed: 40, delta: -1)
        let dynamic = emitters(badge.layer!)[1]
        let before = ["birthRate", "lifetime", "velocity", "emissionLongitude", "emissionRange"].map { dynamic.value(forKeyPath: "emitterCells.emitter." + $0) as! NSNumber }
        button.color = .red; badge.color = .red
        XCTAssertEqual(button.emitterLayer.birthRate, 0)
        XCTAssertEqual(dynamic.birthRate, 1)
        XCTAssertEqual(emitters(badge.layer!)[0].birthRate, 0)
        XCTAssertEqual(before, ["birthRate", "lifetime", "velocity", "emissionLongitude", "emissionRange"].map { dynamic.value(forKeyPath: "emitterCells.emitter." + $0) as! NSNumber })
        XCTAssertEqual(colors(button.emitterLayer)[1], NSColor.red.cgColor)
        for emitter in emitters(badge.layer!) { XCTAssertEqual(colors(emitter)[2], NSColor.red.cgColor) }
    }
    func testDynamicAppearanceRefreshesOnLayout() {
        let old = NSAppearance.current
        defer { NSAppearance.current = old }
        let color = NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .white : .black }
        XCTAssertEqual(color.type, .catalog)
        let button = CandidateButton(), badge = CandidateBadge(frame: .zero)
        NSAppearance.current = NSAppearance(named: .aqua)
        button.color = color; badge.color = color
        button.update(size: CGSize(width: 100, height: 30)); badge.update(size: CGSize(width: 100, height: 30), emitterPosition: .zero)
        let first = colors(button.emitterLayer)[1]
        NSAppearance.current = NSAppearance(named: .darkAqua)
        button.update(size: CGSize(width: 100, height: 30)); badge.update(size: CGSize(width: 100, height: 30), emitterPosition: .zero)
        XCTAssertNotEqual(first, colors(button.emitterLayer)[1])
        XCTAssertEqual(colors(button.emitterLayer)[1], color.cgColor)
        XCTAssertEqual(colors(emitters(badge.layer!)[0])[2], color.cgColor)
    }
    func testClearedEmittersAreRebuiltAtSameGeometry() {
        let button = CandidateButton(), badge = CandidateBadge(frame: .zero)
        let size = CGSize(width: 100, height: 30)
        button.update(size: size); badge.update(size: size, emitterPosition: .zero)
        button.emitterLayer.emitterCells = nil
        emitters(badge.layer!)[1].emitterCells = nil
        button.update(size: size); badge.update(size: size, emitterPosition: .zero)
        XCTAssertEqual(button.emitterLayer.emitterCells?.count, 1)
        XCTAssertTrue(emitters(badge.layer!).allSatisfy { $0.emitterCells?.count == 1 })
    }
    func testGradientArgumentsAreAppliedAndEffectColorsUpdate() {
        let old = ReferenceSlider(), new = CandidateSlider(), bubble = CandidateBubble()
        let gradient = [NSColor.blue, .purple]
        new.effectLayer.update(size: CGSize(width: 100, height: 30), emitterPosition: .zero)
        bubble.effectLayer.update(size: CGSize(width: 100, height: 30))
        old.updateColors(gradient, effect: .white)
        new.updateColors(gradient, effect: .white); bubble.updateColors(gradient, effect: .white)
        XCTAssertNotEqual(old.foregroundLayer.colors as! [CGColor], gradient.map(\.cgColor))
        XCTAssertEqual(new.foregroundLayer.colors as! [CGColor], gradient.map(\.cgColor))
        XCTAssertEqual(bubble.foregroundLayer.colors as! [CGColor], gradient.map(\.cgColor))
        XCTAssertEqual(colors(emitters(new.effectLayer.layer!)[0])[2], NSColor.white.cgColor)
        XCTAssertEqual(colors(bubble.effectLayer.emitterLayer)[1], NSColor.white.cgColor)
    }
    func testBenchmark() throws {
        guard ProcessInfo.processInfo.environment["STARS_WIDGET_BENCHMARK"] == "1" else { throw XCTSkip("Opt-in release benchmark") }
        for scenario in ["button_same", "badge_same", "badge_move", "badge_resize", "button_cold", "badge_cold"] {
            for pass in 0..<5 {
                func run(_ current: Bool) -> Double {
                    var oldButton = ReferenceButton(), newButton = CandidateButton()
                    var oldBadge = ReferenceBadge(frame: .zero), newBadge = CandidateBadge(frame: .zero)
                    let start = CFAbsoluteTimeGetCurrent()
                    for i in 0..<10000 {
                        autoreleasepool {
                            let size = CGSize(width: scenario == "badge_resize" ? CGFloat(100 + i % 2) : 100, height: 30)
                            let point = CGPoint(x: scenario == "badge_move" ? CGFloat(i % 100) : 50, y: 15)
                            if current {
                                if scenario == "button_cold" { newButton = CandidateButton() }
                                if scenario == "badge_cold" { newBadge = CandidateBadge(frame: .zero) }
                                if scenario.hasPrefix("button") { newButton.update(size: size) } else { newBadge.update(size: size, emitterPosition: point) }
                            } else {
                                if scenario == "button_cold" { oldButton = ReferenceButton() }
                                if scenario == "badge_cold" { oldBadge = ReferenceBadge(frame: .zero) }
                                if scenario.hasPrefix("button") { oldButton.update(size: size) } else { oldBadge.update(size: size, emitterPosition: point) }
                            }
                        }
                    }
                    return (CFAbsoluteTimeGetCurrent() - start) * 100
                }
                let old: Double, new: Double
                if pass % 2 == 0 { old = run(false); new = run(true) } else { new = run(true); old = run(false) }
                print("BENCH \(scenario) pass=\(pass) baseline_us=\(old) current_us=\(new)")
            }
        }
    }
}
