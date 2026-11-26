import XCTest
import SceneEffects

final class ReactionBurstPatternTests: XCTestCase {
    private func iosPattern() throws -> [[String: Any]] {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let url = root.appendingPathComponent("submodules/telegram-ios/submodules/TelegramUI/Resources/Animations/generic_reaction_inline_pattern.json")
        guard let data = try? Data(contentsOf: url), let json = try JSONSerialization.jsonObject(with: data) as? [String: Any], let layers = json["layers"] as? [[String: Any]] else {
            throw XCTSkip("telegram-ios pattern not available at \(url.path)")
        }
        return layers.filter { ($0["nm"] as? String)?.hasPrefix("placeholder_") == true }.sorted { ($0["nm"] as! String) < ($1["nm"] as! String) }
    }

    private func keyframes(_ layer: [String: Any], _ key: String) -> [(CGFloat, [CGFloat])] {
        let transform = layer["ks"] as! [String: Any]
        let property = transform[key] as! [String: Any]
        return (property["k"] as! [[String: Any]]).map { keyframe in
            (CGFloat((keyframe["t"] as! NSNumber).doubleValue), (keyframe["s"] as! [NSNumber]).map { CGFloat($0.doubleValue) })
        }
    }

    func testKeyframesMatchTheIOSPattern() throws {
        let layers = try iosPattern()
        XCTAssertEqual(layers.count, ReactionBurstPattern.copyCount)
        for (copy, layer) in layers.enumerated() {
            let inPoint = CGFloat((layer["ip"] as! NSNumber).doubleValue)
            let outPoint = CGFloat((layer["op"] as! NSNumber).doubleValue)
            for (time, value) in keyframes(layer, "p") {
                let sample = ReactionBurstPattern.sample(copy: copy, frame: time)
                XCTAssertEqual(sample.position.x, value[0] * 0.99, accuracy: 1e-6, "copy \(copy) position at \(time)")
                XCTAssertEqual(sample.position.y, -value[1] * 0.99, accuracy: 1e-6, "copy \(copy) position at \(time)")
            }
            for (time, value) in keyframes(layer, "s") {
                let sample = ReactionBurstPattern.sample(copy: copy, frame: time)
                XCTAssertEqual(sample.scale.width, value[0] / 100 * 0.99, accuracy: 1e-6, "copy \(copy) scale at \(time)")
                XCTAssertEqual(sample.scale.height, value[1] / 100 * 0.99, accuracy: 1e-6, "copy \(copy) scale at \(time)")
            }
            for (time, value) in keyframes(layer, "o") where time >= inPoint && time < outPoint {
                XCTAssertEqual(ReactionBurstPattern.sample(copy: copy, frame: time).opacity, value[0] / 100, accuracy: 1e-6, "copy \(copy) opacity at \(time)")
            }
            XCTAssertEqual(ReactionBurstPattern.sample(copy: copy, frame: inPoint - 0.01).opacity, 0, "copy \(copy) before its in point")
            XCTAssertEqual(ReactionBurstPattern.sample(copy: copy, frame: outPoint).opacity, 0, "copy \(copy) at its out point")
        }
    }

    func testCopiesBurstUpThenFallAway() {
        for copy in 0 ..< ReactionBurstPattern.copyCount {
            let appear = stride(from: CGFloat(0), through: 20, by: 0.25).first { ReactionBurstPattern.sample(copy: copy, frame: $0).opacity > 0 }!
            let start = ReactionBurstPattern.sample(copy: copy, frame: appear)
            let peak = (Int(appear) ... 30).map { ReactionBurstPattern.sample(copy: copy, frame: CGFloat($0)).position.y }.max()!
            let end = ReactionBurstPattern.sample(copy: copy, frame: ReactionBurstPattern.frameCount)
            XCTAssertGreaterThan(peak, start.position.y + 50, "copy \(copy)")
            XCTAssertLessThan(end.position.y, start.position.y - 200, "copy \(copy)")
            XCTAssertEqual(end.opacity, 0, "copy \(copy)")
            XCTAssertGreaterThan(ReactionBurstPattern.sample(copy: copy, frame: 12).opacity, 0, "copy \(copy)")
        }
        let flipped = (0 ..< ReactionBurstPattern.copyCount).filter { ReactionBurstPattern.sample(copy: $0, frame: 20).scale.width < 0 }
        XCTAssertEqual(flipped, [1, 3, 5])
    }

    func testMotionIsContinuousAt120Hz() {
        let step = ReactionBurstPattern.frameRate / 120
        for copy in 0 ..< ReactionBurstPattern.copyCount {
            var steps: [CGFloat] = []
            var scales: [CGFloat] = []
            var previous = ReactionBurstPattern.sample(copy: copy, frame: 0)
            var frame = step
            while frame <= ReactionBurstPattern.frameCount {
                let sample = ReactionBurstPattern.sample(copy: copy, frame: frame)
                steps.append(hypot(sample.position.x - previous.position.x, sample.position.y - previous.position.y))
                scales.append(abs(sample.scale.height - previous.scale.height))
                previous = sample
                frame += step
            }
            for index in 1 ..< steps.count - 1 {
                XCTAssertLessThanOrEqual(steps[index], max(steps[index - 1], steps[index + 1]) * 2 + 1, "copy \(copy) step \(index)")
                XCTAssertLessThanOrEqual(scales[index], max(scales[index - 1], scales[index + 1]) * 2 + 0.005, "copy \(copy) step \(index)")
            }
            XCTAssertLessThan(steps.max()!, 40, "copy \(copy)")
        }
    }
}
