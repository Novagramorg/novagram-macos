import Cocoa
import XCTest
import Darwin
import SwiftSignalKit
@testable import TGUIKit

final class TransformImageRenderBenchmarkTests: XCTestCase {
    func testRenderCancellationAndActivePipelineCosts() throws {
        guard ProcessInfo.processInfo.environment["IMAGE_RENDER_BENCHMARK"] == "1" else { throw XCTSkip("Opt-in render cancellation benchmark") }
        TGUIKitTestBootstrap.install()
        setDisplayColorSpace(CGColorSpace(name: CGColorSpace.displayP3))
        defer { setDisplayColorSpace(nil) }
        let cachedImages = [try TransformImageAssignmentTests().makeImage(.red), try TransformImageAssignmentTests().makeImage(.blue)].map { TransformImageResult($0, true) }
        var results: [String: [[Double]]] = [:]
        var generatedCounts: [String: [Int]] = [:]
        for scenario in ["cached_rebind", "cached_stream", "nil_rebind", "nil_stream", "small_stream", "protected_stream", "cancel_1024", "cancel_protected_1024", "cancel_during_image_protected_1024"] {
            let baseline = LegacyImageRenderView(), candidate = TransformImageView()
            let cancels = scenario.hasPrefix("cancel")
            let protected = scenario.contains("protected")
            let isCached = scenario.hasPrefix("cached")
            let nilContext = scenario.hasPrefix("nil") || isCached
            let size = CGSize(width: cancels ? 1024 : 32, height: cancels ? 1024 : 32)
            let args = TransformImageArguments(corners: .init(), imageSize: size, boundingSize: size, intrinsicInsets: .init(), scale: 1)
            var generated = [0, 0], delivered = [0, 0]
            let disposals: [() -> Void] = [{ [weak baseline] in baseline?.dispose() }, { [weak candidate] in candidate?.dispose() }]
            let transforms = (0..<2).map { variant in
                ImageDataTransformation(data: ImageRenderData(nil, nil, true), execute: { _, _ in
                    if nilContext { return nil }
                    let context = ObservedDrawingContext(size: size, scale: 1, clear: true)
                    context.withContext { ctx in
                        ctx.setFillColor(NSColor.red.cgColor)
                        ctx.fill(CGRect(origin: .zero, size: size))
                    }
                    context.onGenerate = {
                        generated[variant] += 1
                        if scenario.contains("during_image") { disposals[variant]() }
                    }
                    if cancels && !scenario.contains("during_image") { disposals[variant]() }
                    return context
                })
            }
            baseline.set(arguments: args); candidate.set(arguments: args)
            var emit: [((ImageDataTransformation) -> Void)?] = [nil, nil]
            var emitCached: [((TransformImageResult?) -> Void)?] = [nil, nil]
            var cachedIndex = [0, 0]
            if isCached {
                baseline.imageUpdated = { _ in delivered[0] += 1 }
                candidate.imageUpdated = { _ in delivered[1] += 1 }
            }
            if scenario == "cached_stream" {
                baseline.setSignal(signal: Signal { subscriber in emitCached[0] = { subscriber.putNext($0) }; return EmptyDisposable })
                candidate.setSignal(signal: Signal { subscriber in emitCached[1] = { subscriber.putNext($0) }; return EmptyDisposable })
            } else if scenario.hasSuffix("stream") {
                baseline.setSignal(Signal { subscriber in emit[0] = { subscriber.putNext($0) }; return EmptyDisposable }, synchronousLoad: true, cacheImage: { _ in delivered[0] += 1 }, isProtected: protected)
                candidate.setSignal(Signal { subscriber in emit[1] = { subscriber.putNext($0) }; return EmptyDisposable }, synchronousLoad: true, cacheImage: { _ in delivered[1] += 1 }, isProtected: protected)
            }
            let operations: [() -> Void] = [
                {
                    if isCached {
                        let result = cachedImages[cachedIndex[0] % 2]
                        cachedIndex[0] += 1
                        if let next = emitCached[0] { next(result) } else { baseline.setSignal(signal: .single(result)) }
                    } else if let next = emit[0] { next(transforms[0]) }
                    else { baseline.setSignal(.single(transforms[0]), synchronousLoad: true, cacheImage: { _ in delivered[0] += 1 }, isProtected: protected) }
                },
                {
                    if isCached {
                        let result = cachedImages[cachedIndex[1] % 2]
                        cachedIndex[1] += 1
                        if let next = emitCached[1] { next(result) } else { candidate.setSignal(signal: .single(result)) }
                    } else if let next = emit[1] { next(transforms[1]) }
                    else { candidate.setSignal(.single(transforms[1]), synchronousLoad: true, cacheImage: { _ in delivered[1] += 1 }, isProtected: protected) }
                }
            ]
            autoreleasepool { for _ in 0..<10 { operations[0](); operations[1]() } }
            let iterations = cancels ? 20 : nilContext ? 10000 : 1000
            var samples = [[Double](), [Double]()]
            for batch in 0..<9 {
                for variant in batch % 2 == 0 ? [0, 1] : [1, 0] {
                    let start = CACurrentMediaTime()
                    autoreleasepool { for _ in 0..<iterations { operations[variant]() } }
                    samples[variant].append((CACurrentMediaTime() - start) * 1e6 / Double(iterations))
                }
            }
            let calls = 10 + 9 * iterations
            XCTAssertEqual(delivered, cancels ? [0, 0] : [calls, calls])
            XCTAssertEqual(generated, nilContext ? [0, 0] : cancels && !scenario.contains("during_image") ? [calls, 0] : [calls, calls])
            results[scenario] = samples
            generatedCounts[scenario] = generated
            baseline.dispose(); candidate.dispose()
            emit = [nil, nil]
            emitCached = [nil, nil]
        }
        let baseline = LegacyImageRenderView(), candidate = TransformImageView()
        let arguments = TransformImageViewTests().arguments()
        candidate.set(arguments: arguments)
        candidate.setSignal(.single(ImageDataTransformation()), synchronousLoad: true, alreadyRendered: arguments)
        let renderer = try XCTUnwrap(Mirror(reflecting: candidate).children.first { $0.label == "renderer" }?.value)
        let stored = try XCTUnwrap(Mirror(reflecting: renderer).children.first { $0.label == "renderState" }?.value)
        let unwrapped = try XCTUnwrap(Mirror(reflecting: stored).children.first?.value)
        XCTAssertEqual(Mirror(reflecting: unwrapped).displayStyle, .class)
        let state = unwrapped as AnyObject
        let baselineState = Atomic<TransformImageArguments?>(value: arguments)
        let allocations = ["baseline_view_bytes": malloc_size(Unmanaged.passUnretained(baseline).toOpaque()), "candidate_view_bytes": malloc_size(Unmanaged.passUnretained(candidate).toOpaque()), "baseline_state_bytes": malloc_size(Unmanaged.passUnretained(baselineState).toOpaque()), "candidate_state_bytes": malloc_size(Unmanaged.passUnretained(state).toOpaque())]
        candidate.dispose()
        try JSONSerialization.data(withJSONObject: ["unit": "microseconds_per_operation", "batches_baseline_then_candidate": results, "image_generation_calls": generatedCounts, "allocations": allocations], options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: "/tmp/image-render-benchmark.json"))
    }
}
