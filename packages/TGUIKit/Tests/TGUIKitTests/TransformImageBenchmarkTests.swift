import Cocoa
import XCTest
import SwiftSignalKit
@testable import TGUIKit

final class TransformImageBenchmarkTests: XCTestCase {
    func testArgumentDeliveryCosts() throws {
        guard ProcessInfo.processInfo.environment["TRANSFORM_IMAGE_BENCHMARK"] == "1" else { throw XCTSkip("Opt-in transformed-image argument benchmark") }
        TGUIKitTestBootstrap.install()
        let fixture = TransformImageViewTests()
        let values = [fixture.arguments(), fixture.arguments(insets: .init(top: 0, left: 1, bottom: 0, right: 0))]
        var results: [String: [[Double]]] = [:]
        for scenario in ["idle_repeated", "subscribed_repeated", "subscribed_changed", "construct"] {
            let baseline = LegacyTransformImageView(), candidate = TransformImageView()
            var counts = [0, 0]
            if scenario.hasPrefix("subscribed") {
                baseline.setSignal(.single(fixture.transformation { _ in counts[0] += 1; return nil }), synchronousLoad: true)
                candidate.setSignal(.single(fixture.transformation { _ in counts[1] += 1; return nil }), synchronousLoad: true)
            }
            let operations: [(Int) -> Void] = [
                { index in
                    if scenario == "construct" { withExtendedLifetime(LegacyTransformImageView()) {} }
                    else { baseline.set(arguments: values[scenario == "subscribed_changed" ? index % 2 : 0]) }
                },
                { index in
                    if scenario == "construct" { withExtendedLifetime(TransformImageView()) {} }
                    else { candidate.set(arguments: values[scenario == "subscribed_changed" ? index % 2 : 0]) }
                }
            ]
            for i in 0..<100 { operations[0](i); operations[1](i) }
            var samples = [[Double](), [Double]()]
            let iterations = scenario == "construct" ? 2000 : 20000
            for batch in 0..<9 {
                for variant in batch % 2 == 0 ? [0, 1] : [1, 0] {
                    let start = CFAbsoluteTimeGetCurrent()
                    autoreleasepool { for i in 0..<iterations { operations[variant](i) } }
                    samples[variant].append((CFAbsoluteTimeGetCurrent() - start) * 1_000_000 / Double(iterations))
                }
            }
            XCTAssertEqual(counts[0], counts[1])
            if scenario == "subscribed_repeated" { XCTAssertEqual(counts, [1, 1]) }
            if scenario == "subscribed_changed" { XCTAssertEqual(counts, [180100, 180100]) }
            results[scenario] = samples
        }
        try JSONSerialization.data(withJSONObject: ["unit": "microseconds_per_operation", "batches_baseline_then_candidate": results], options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: "/tmp/transform-image-benchmark.json"))
    }
}
