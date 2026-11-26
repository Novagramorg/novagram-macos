import AppKit
import QuartzCore
import XCTest
import TGUIKit
@testable import Effects

final class EffectsTests: XCTestCase {
    override func setUp() {
        super.setUp()
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        System.updateScaleFactor(2)
    }

    private func emitter(_ layer: CALayer) -> CAEmitterLayer {
        layer.sublayers!.compactMap { $0 as? CAEmitterLayer }.first!
    }

    private func behavior(_ layer: CALayer) -> NSObject {
        (emitter(layer).emitterCells![0].value(forKey: "emitterBehaviors") as! [NSObject])[0]
    }

    private func colors(_ layer: CALayer) -> [CGColor] {
        behavior(layer).value(forKey: "colors") as! [CGColor]
    }

    private func assertEquivalent(_ first: CALayer, _ second: CALayer, file: StaticString = #filePath, line: UInt = #line) {
        let a = emitter(first), b = emitter(second)
        XCTAssertEqual(a.emitterSize, b.emitterSize, file: file, line: line)
        XCTAssertEqual(a.emitterShape, b.emitterShape, file: file, line: line)
        XCTAssertEqual(a.emitterMode, b.emitterMode, file: file, line: line)
        XCTAssertEqual(a.frame, b.frame, file: file, line: line)
        XCTAssertEqual(a.emitterPosition, b.emitterPosition, file: file, line: line)
        XCTAssertEqual(a.birthRate, b.birthRate, file: file, line: line)
        XCTAssertEqual(a.emitterCells!.count, b.emitterCells!.count, file: file, line: line)
        let x = a.emitterCells![0], y = b.emitterCells![0]
        XCTAssertEqual(x.name, y.name, file: file, line: line)
        XCTAssertEqual(x.birthRate, y.birthRate, file: file, line: line)
        XCTAssertEqual(x.lifetime, y.lifetime, file: file, line: line)
        XCTAssertEqual(x.velocity, y.velocity, file: file, line: line)
        XCTAssertEqual(x.scale, y.scale, file: file, line: line)
        XCTAssertEqual(x.scaleRange, y.scaleRange, file: file, line: line)
        XCTAssertEqual(x.alphaRange, y.alphaRange, file: file, line: line)
        XCTAssertEqual(x.emissionRange, y.emissionRange, file: file, line: line)
        XCTAssertEqual(colors(first), colors(second), file: file, line: line)
        XCTAssertNotNil(x.contents, file: file, line: line)
        XCTAssertNotNil(y.contents, file: file, line: line)
        let image = x.contents as! CGImage, other = y.contents as! CGImage
        XCTAssertEqual(image.width, other.width, file: file, line: line)
        XCTAssertEqual(image.height, other.height, file: file, line: line)
        XCTAssertEqual(image.dataProvider!.data! as Data, other.dataProvider!.data! as Data, file: file, line: line)
    }

    func testInitialConfigurationAndParticleAssetMatchOriginal() {
        for color in [NSColor.red, .blue, .white, .clear, NSColor(displayP3Red: 0.8, green: 0.2, blue: 0.4, alpha: 0.3)] {
            for size in [CGSize.zero, CGSize(width: 25, height: 25), CGSize(width: 40, height: 30), CGSize(width: 81.5, height: 22.25)] {
                let old = ReferenceStarsEffectLayer(), new = CandidateStarsEffectLayer()
                old.update(color: color, size: size); new.update(color: color, size: size)
                assertEquivalent(old, new)
            }
        }
    }

    func testUnchangedUpdatesKeepBehaviorAndSeed() {
        let old = ReferenceStarsEffectLayer(), new = CandidateStarsEffectLayer()
        let size = CGSize(width: 25, height: 25)
        old.update(color: .red, size: size); new.update(color: .red, size: size)
        let oldBehavior = behavior(old), newBehavior = behavior(new)
        let e = emitter(new), seed = emitter(new).seed
        var oldReplacements = 0, newReplacements = 0
        var previousOld = oldBehavior, previousNew = newBehavior
        for _ in 0..<1000 {
            old.update(color: .red, size: size); new.update(color: .red, size: size)
            let currentOld = behavior(old), currentNew = behavior(new)
            if currentOld !== previousOld { oldReplacements += 1 }
            if currentNew !== previousNew { newReplacements += 1 }
            previousOld = currentOld; previousNew = currentNew
        }
        XCTAssertTrue(behavior(new) === newBehavior)
        XCTAssertFalse(behavior(old) === oldBehavior)
        XCTAssertEqual(e.seed, seed)
        XCTAssertEqual(oldReplacements, 1000)
        XCTAssertEqual(newReplacements, 0)
        assertEquivalent(old, new)
    }

    func testColorChangesMatchOriginalAndDoNotChangeGeometry() {
        let old = ReferenceStarsEffectLayer(), new = CandidateStarsEffectLayer()
        let size = CGSize(width: 32, height: 20)
        for color in [NSColor.red, .green, .blue, .white, .black, .clear, .red] {
            old.update(color: color, size: size); new.update(color: color, size: size)
            assertEquivalent(old, new)
        }
    }

    func testEquivalentColorObjectsReuseBehavior() {
        let layer = CandidateStarsEffectLayer()
        let size = CGSize(width: 25, height: 25)
        layer.update(color: NSColor(srgbRed: 0.4, green: 0.6, blue: 0.2, alpha: 0.7), size: size)
        let retained = behavior(layer), seed = emitter(layer).seed
        for _ in 0..<1000 {
            layer.update(color: NSColor(srgbRed: 0.4, green: 0.6, blue: 0.2, alpha: 0.7), size: size)
        }
        XCTAssertTrue(behavior(layer) === retained)
        XCTAssertEqual(emitter(layer).seed, seed)
    }

    func testSizeChangesRefreshParticleScaleAndKeepColorBehavior() {
        let layer = CandidateStarsEffectLayer(), original = ReferenceStarsEffectLayer()
        layer.update(color: .red, size: CGSize(width: 25, height: 25))
        original.update(color: .red, size: CGSize(width: 25, height: 25))
        let retained = behavior(layer)
        for size in [CGSize(width: 40, height: 30), .zero, CGSize(width: 80, height: 80), CGSize(width: 25, height: 25)] {
            layer.update(color: .red, size: size)
            let fresh = ReferenceStarsEffectLayer()
            fresh.update(color: .red, size: size)
            assertEquivalent(fresh, layer)
            XCTAssertTrue(behavior(layer) === retained)
        }
        original.update(color: .red, size: CGSize(width: 80, height: 80))
        XCTAssertEqual(emitter(original).emitterCells![0].scale, (25.0 / 32.0) * 0.12)
    }

    func testDynamicColorsInvalidateForAppearanceChanges() {
        let saved = NSAppearance.current
        defer { NSAppearance.current = saved }
        let color = NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .white : .black
        }
        let old = ReferenceStarsEffectLayer(), new = CandidateStarsEffectLayer()
        var snapshots: [[CGColor]] = []
        for name in [NSAppearance.Name.aqua, .darkAqua, .aqua] {
            NSAppearance.current = NSAppearance(named: name)!
            old.update(color: color, size: CGSize(width: 25, height: 25))
            new.update(color: color, size: CGSize(width: 25, height: 25))
            assertEquivalent(old, new)
            snapshots.append(colors(new))
        }
        XCTAssertNotEqual(snapshots[0], snapshots[1])
        XCTAssertEqual(snapshots[0], snapshots[2])
    }

    func testPauseBeforeSetupAndThroughUpdatesRetainsBirthRate() {
        let old = ReferenceStarsEffectLayer(), new = CandidateStarsEffectLayer()
        for playing in [false, false, true, true, false, true] {
            old.isPlaying = playing; new.isPlaying = playing
            for color in [NSColor.red, .blue, .blue] {
                old.update(color: color, size: CGSize(width: 25, height: 25))
                new.update(color: color, size: CGSize(width: 25, height: 25))
                assertEquivalent(old, new)
                XCTAssertEqual(emitter(new).birthRate, playing ? 1 : 0)
            }
        }
    }

    func testClearedEmitterCellsAreRestoredWithoutRestartingPlayback() {
        let layer = CandidateStarsEffectLayer(), reference = ReferenceStarsEffectLayer()
        let size = CGSize(width: 25, height: 25)
        layer.update(color: .red, size: size)
        reference.update(color: .red, size: size)
        layer.isPlaying = false; reference.isPlaying = false
        emitter(layer).emitterCells = nil
        layer.update(color: .red, size: size)
        assertEquivalent(reference, layer)
        XCTAssertEqual(emitter(layer).birthRate, 0)
    }

    func testEffectBenchmark() throws {
        guard ProcessInfo.processInfo.environment["STARS_EFFECT_BENCHMARK"] == "1" else { throw XCTSkip("Opt-in release benchmark") }
        let iterations = 5000
        var results: [[String: Any]] = []
        for scenario in ["unchanged", "color_changes", "size_changes", "new_layer", "paused_unchanged"] {
            let old = ReferenceStarsEffectLayer(), new = CandidateStarsEffectLayer()
            old.isPlaying = scenario != "paused_unchanged"; new.isPlaying = old.isPlaying
            let size = CGSize(width: 25, height: 25)
            old.update(color: .red, size: size); new.update(color: .red, size: size)
            var checksum: Double = 0
            func measure(_ baseline: Bool) -> Double {
                let start = DispatchTime.now().uptimeNanoseconds
                for index in 0..<iterations {
                    autoreleasepool {
                        let color: NSColor = scenario == "color_changes" && index % 2 == 0 ? .blue : .red
                        let size = scenario == "size_changes" ? CGSize(width: index % 2 == 0 ? 25 : 40, height: 25) : size
                        if baseline {
                            let layer = scenario == "new_layer" ? ReferenceStarsEffectLayer() : old
                            layer.update(color: color, size: size)
                            checksum += emitter(layer).emitterSize.width
                        } else {
                            let layer = scenario == "new_layer" ? CandidateStarsEffectLayer() : new
                            layer.update(color: color, size: size)
                            checksum += emitter(layer).emitterSize.width
                        }
                    }
                }
                return Double(DispatchTime.now().uptimeNanoseconds - start) / Double(iterations) / 1000
            }
            _ = measure(true); _ = measure(false)
            var before: [Double] = [], after: [Double] = []
            for batch in 0..<9 {
                if batch % 2 == 0 { before.append(measure(true)); after.append(measure(false)) }
                else { after.append(measure(false)); before.append(measure(true)) }
            }
            XCTAssertGreaterThan(checksum, 0)
            results.append(["scenario": scenario, "baseline_us": before.sorted()[4], "candidate_us": after.sorted()[4], "baseline_trials_us": before, "candidate_trials_us": after])
        }
        let data = try JSONSerialization.data(withJSONObject: ["iterations_per_batch": iterations, "batches": 9, "results": results], options: [.prettyPrinted, .sortedKeys])
        try data.write(to: URL(fileURLWithPath: "/tmp/stars-effect-benchmark.json"))
        print(String(data: data, encoding: .utf8)!)
    }
}
