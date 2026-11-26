import Cocoa
import XCTest
import SwiftSignalKit
@testable import TGUIKit

final class TransformImageAssignmentBenchmarkTests: XCTestCase {
    func testAssignmentCosts() throws {
        guard ProcessInfo.processInfo.environment["IMAGE_ASSIGNMENT_BENCHMARK"] == "1" else { throw XCTSkip("Opt-in image assignment benchmark") }
        TGUIKitTestBootstrap.install()
        let fixture = TransformImageAssignmentTests()
        let images = [try fixture.makeImage(.red), try fixture.makeImage(.blue)]
        let caches = (0..<6).map { _ in ScopedImageCache(countLimit: 10, byteLimit: 1_000_000, idleTimeout: 300, closedScopeGrace: 15, sweepInterval: 3600) }
        let cache = caches[0]
        for (index, image) in images.enumerated() { cache.setImage(image, sampleBuffer: nil, forKey: index) }
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 100, height: 100), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        var results: [String: [[Double]]] = [:]
        for scenario in ["repeat", "alternate", "empty", "restore", "cached_repeat", "protected_repeat", "fresh_render"] {
            let baseline = LegacyImageAssignmentView(), candidate = TransformImageView()
            window.contentView?.addSubview(baseline)
            window.contentView?.addSubview(candidate)
            var notifications = [0, 0]
            baseline.imageUpdated = { _ in notifications[0] += 1 }
            candidate.imageUpdated = { _ in notifications[1] += 1 }
            if scenario == "protected_repeat" { baseline.preventsCapture = true; candidate.preventsCapture = true }
            let cached = Signal<TransformImageResult?, NoError>.single(TransformImageResult(images[0], true))
            let rendering = ImageDataTransformation(data: ImageRenderData(nil, nil, true), execute: { arguments, _ in
                let context = DrawingContext(size: arguments.drawingSize, scale: 1, clear: true)
                context.withContext { context in
                    context.setFillColor(NSColor.red.cgColor)
                    context.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
                }
                return context
            })
            let renderSignal = Signal<ImageDataTransformation, NoError>.single(rendering)
            let arguments = TransformImageArguments(corners: .init(), imageSize: NSSize(width: 16, height: 16), boundingSize: NSSize(width: 16, height: 16), intrinsicInsets: .init(), scale: 1)
            baseline.set(arguments: arguments); candidate.set(arguments: arguments)
            let store: (TransformImageResult) -> Void = { result in
                if let image = result.image { cache.setImage(image, sampleBuffer: nil, forKey: 2) }
            }
            let operations: [(Int) -> Void] = [
                { index in
                    if scenario == "restore" { baseline.layer?.contents = images[1] }
                    if scenario == "fresh_render" { baseline.setSignal(renderSignal, synchronousLoad: true, cacheImage: store) }
                    else if scenario == "cached_repeat" { baseline.setSignal(signal: cached) }
                    else { baseline.image = scenario == "empty" ? nil : images[scenario == "alternate" ? index % 2 : 0] }
                },
                { index in
                    if scenario == "restore" { candidate.layer?.contents = images[1] }
                    if scenario == "fresh_render" { candidate.setSignal(renderSignal, synchronousLoad: true, cacheImage: store) }
                    else if scenario == "cached_repeat" { candidate.setSignal(signal: cached) }
                    else { candidate.image = scenario == "empty" ? nil : images[scenario == "alternate" ? index % 2 : 0] }
                }
            ]
            for i in 0..<100 { operations[0](i); operations[1](i) }
            var samples = [[Double](), [Double]()]
            let iterations = scenario == "fresh_render" ? 2000 : 20000
            for batch in 0..<9 {
                for variant in batch % 2 == 0 ? [0, 1] : [1, 0] {
                    let start = CFAbsoluteTimeGetCurrent()
                    autoreleasepool { for i in 0..<iterations { operations[variant](i) } }
                    samples[variant].append((CFAbsoluteTimeGetCurrent() - start) * 1_000_000 / Double(iterations))
                }
            }
            XCTAssertEqual(notifications[0], notifications[1])
            XCTAssertEqual(notifications[1], scenario == "empty" ? 0 : scenario == "alternate" || scenario == "fresh_render" ? iterations * 9 + 100 : 1)
            if scenario == "fresh_render" {
                XCTAssertEqual(PixelBuffer(try XCTUnwrap(candidate.image)), PixelBuffer(try XCTUnwrap(baseline.image)))
            } else {
                XCTAssertEqual(candidate.image, baseline.image)
                XCTAssertTrue(candidate.layer?.contents as AnyObject? === baseline.layer?.contents as AnyObject?)
            }
            results[scenario] = samples
            baseline.removeFromSuperview(); candidate.removeFromSuperview()
        }
        withExtendedLifetime(caches) {}
        try JSONSerialization.data(withJSONObject: ["unit": "microseconds_per_operation", "batches_baseline_then_candidate": results], options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: "/tmp/image-assignment-benchmark.json"))
    }
}
