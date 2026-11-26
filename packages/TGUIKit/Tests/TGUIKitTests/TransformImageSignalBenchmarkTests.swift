import Cocoa
import XCTest
import SwiftSignalKit
@testable import TGUIKit

final class TransformImageSignalBenchmarkTests: XCTestCase {
    func testSignalDeliveryCosts() throws {
        guard ProcessInfo.processInfo.environment["IMAGE_SIGNAL_BENCHMARK"] == "1" else { throw XCTSkip("Opt-in image signal lifecycle benchmark") }
        TGUIKitTestBootstrap.install()
        let fixture = TransformImageAssignmentTests()
        let images = [try fixture.makeImage(.red), try fixture.makeImage(.blue)]
        let values = images.map { TransformImageResult($0, true) }
        let signals = values.map { Signal<TransformImageResult?, NoError>.single($0) }
        let transform = Signal<ImageDataTransformation, NoError>.single(TransformImageViewTests().transformation { _ in nil })
        var results: [String: [[Double]]] = [:]
        for scenario in ["cached_rebind", "cached_stream", "transform_rebind", "transform_stream"] {
            let baseline = LegacyImageSignalView(), candidate = TransformImageView()
            var emitCached: [((TransformImageResult?) -> Void)?] = [nil, nil]
            var emitTransform: [((ImageDataTransformation) -> Void)?] = [nil, nil]
            var notifications = [0, 0], cached = [0, 0]
            baseline.imageUpdated = { _ in notifications[0] += 1 }
            candidate.imageUpdated = { _ in notifications[1] += 1 }
            let args = TransformImageViewTests().arguments()
            baseline.set(arguments: args); candidate.set(arguments: args)
            if scenario == "cached_stream" {
                baseline.setSignal(signal: Signal { subscriber in emitCached[0] = { subscriber.putNext($0) }; return EmptyDisposable })
                candidate.setSignal(signal: Signal { subscriber in emitCached[1] = { subscriber.putNext($0) }; return EmptyDisposable })
            } else if scenario == "transform_stream" {
                baseline.setSignal(Signal { subscriber in emitTransform[0] = { subscriber.putNext($0) }; return EmptyDisposable }, synchronousLoad: true, cacheImage: { _ in cached[0] += 1 })
                candidate.setSignal(Signal { subscriber in emitTransform[1] = { subscriber.putNext($0) }; return EmptyDisposable }, synchronousLoad: true, cacheImage: { _ in cached[1] += 1 })
            }
            let data = TransformImageViewTests().transformation { _ in nil }
            let operations: [(Int) -> Void] = [
                { index in
                    switch scenario {
                    case "cached_rebind": baseline.setSignal(signal: signals[index % 2])
                    case "cached_stream": emitCached[0]?(values[index % 2])
                    case "transform_rebind": baseline.setSignal(transform, synchronousLoad: true, cacheImage: { _ in cached[0] += 1 })
                    default: emitTransform[0]?(data)
                    }
                },
                { index in
                    switch scenario {
                    case "cached_rebind": candidate.setSignal(signal: signals[index % 2])
                    case "cached_stream": emitCached[1]?(values[index % 2])
                    case "transform_rebind": candidate.setSignal(transform, synchronousLoad: true, cacheImage: { _ in cached[1] += 1 })
                    default: emitTransform[1]?(data)
                    }
                }
            ]
            for i in 0..<100 { operations[0](i); operations[1](i) }
            var samples = [[Double](), [Double]()]
            let iterations = 20000
            for batch in 0..<9 {
                for variant in batch % 2 == 0 ? [0, 1] : [1, 0] {
                    let start = CFAbsoluteTimeGetCurrent()
                    autoreleasepool { for i in 0..<iterations { operations[variant](i) } }
                    samples[variant].append((CFAbsoluteTimeGetCurrent() - start) * 1_000_000 / Double(iterations))
                }
            }
            let deliveries = 100 + 9 * iterations
            XCTAssertEqual(notifications, scenario.hasPrefix("cached") ? [deliveries, deliveries] : [0, 0])
            XCTAssertEqual(cached, scenario.hasPrefix("transform") ? [deliveries, deliveries] : [0, 0])
            XCTAssertEqual(baseline.image, candidate.image)
            results[scenario] = samples
            baseline.dispose(); candidate.dispose()
        }
        try JSONSerialization.data(withJSONObject: ["unit": "microseconds_per_operation", "batches_baseline_then_candidate": results], options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: "/tmp/image-signal-benchmark.json"))
    }
}
