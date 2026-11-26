import Cocoa
import CoreMedia
import AVFoundation
import SwiftSignalKit
import XCTest

class TestAsset {
    var duration = CMTime(seconds: 10, preferredTimescale: 1000)
    var onGenerate: ((TestImageGenerator) -> Void)?
    var onCancel: (() -> Void)?
    var copyImage: CGImage? = testImage()
}
final class TestComposition: TestAsset {}
final class TestImageGenerator {
    enum Result { case succeeded, failed, cancelled }
    let asset: TestAsset
    var appliesPreferredTrackTransform = false
    var maximumSize = CGSize.zero
    var requestedTimeToleranceBefore = CMTime.zero, requestedTimeToleranceAfter = CMTime.zero
    var videoComposition: AVVideoComposition?
    var times: [CMTime] = []
    var callback: ((CMTime, CGImage?, CMTime, Result, Error?) -> Void)?
    var cancellations = 0
    init(asset: TestAsset) { self.asset = asset }
    func generateCGImagesAsynchronously(forTimes times: [NSValue], completionHandler: @escaping (CMTime, CGImage?, CMTime, Result, Error?) -> Void) {
        self.times = times.map { $0.timeValue }; callback = completionHandler; asset.onGenerate?(self)
    }
    func cancelAllCGImageGeneration() { cancellations += 1; asset.onCancel?() }
    func copyCGImage(at time: CMTime, actualTime: UnsafeMutablePointer<CMTime>?) throws -> CGImage {
        times = [time]; asset.onGenerate?(self)
        guard let image = asset.copyImage else { throw NSError(domain: "test", code: 1) }
        return image
    }
    func emit(_ index: Int, image: CGImage? = testImage(), result: Result = .succeeded) { callback?(times[index], image, times[index], result, nil) }
}
final class Output<T> {
    private let lock = NSLock()
    private var stored: [T] = []
    var values: [T] { lock.lock(); defer { lock.unlock() }; return stored }
    func add(_ value: T) { lock.lock(); stored.append(value); lock.unlock() }
}
final class ControlledTests: XCTestCase {
    func runStrip(_ count: Int = 3, gradually: Bool = true, blur: Bool = false, asset: TestAsset = TestAsset(), composition: AVVideoComposition? = nil, body: (TestImageGenerator, Output<([CGImage], Bool)>, XCTestExpectation) -> Void) {
        let started = expectation(description: "generator started"), done = expectation(description: "completed")
        let result = Output<([CGImage], Bool)>()
        var generator: TestImageGenerator?
        asset.onGenerate = { generator = $0; started.fulfill() }
        let disposable = generateVideoScrubberThumbs(for: asset, composition: composition, size: CGSize(width: 40, height: 20), count: count, gradually: gradually, blur: blur).start(next: { result.add($0) }, completed: { done.fulfill() })
        defer { disposable.dispose(); asset.onGenerate = nil }
        wait(for: [started], timeout: 2)
        guard let generator else { return }
        body(generator, result, done)
    }
    func testReverseCallbacksKeepTimelineOrder() { runStrip { g, output, done in g.emit(2, image: testImage(82)); g.emit(1, image: testImage(81)); g.emit(0, image: testImage(80)); self.wait(for: [done], timeout: 1); XCTAssertEqual(output.values.last?.0.map { $0.width }, [80, 81, 82]) } }
    func testMixedFailuresStillCompleteAndKeepSlotCount() { runStrip { g, output, done in g.emit(0, image: testImage(80)); g.emit(1, image: nil, result: .failed); g.emit(2, image: testImage(82)); self.wait(for: [done], timeout: 1); XCTAssertEqual(output.values.last?.0.count, 3); XCTAssertEqual(output.values.last?.1, true); XCTAssertEqual(output.values.last?.0.last?.width, 82) } }
    func testAllFailedFramesCompleteEmpty() { runStrip { g, output, done in for i in 0..<3 { g.emit(i, image: nil, result: .failed) }; self.wait(for: [done], timeout: 1); XCTAssertEqual(output.values.last?.1, true); XCTAssertEqual(output.values.last?.0.count, 0) } }
    func testCancelledFrameIsTerminalForItsSlot() { runStrip { g, output, done in g.emit(0); g.emit(1, image: nil, result: .cancelled); g.emit(2); self.wait(for: [done], timeout: 1); XCTAssertEqual(output.values.last?.1, true) } }
    func testSuccessWithoutImageStillCompletes() { runStrip { g, output, done in for i in 0..<3 { g.emit(i, image: nil) }; self.wait(for: [done], timeout: 1); XCTAssertEqual(output.values.last?.1, true) } }
    func testErrorResultDoesNotPublishItsImage() { runStrip { g, output, done in g.emit(0, image: testImage(99), result: .failed); g.emit(1, image: testImage(81)); g.emit(2, image: testImage(82)); self.wait(for: [done], timeout: 1); XCTAssertFalse(output.values.last!.0.contains { $0.width == 99 }) } }
    func testNonGradualOutputContainsOnlyFinalResult() { runStrip(3, gradually: false) { g, output, done in g.emit(2); g.emit(0); g.emit(1); self.wait(for: [done], timeout: 1); XCTAssertEqual(output.values.count, 1); XCTAssertEqual(output.values.first?.1, true) } }
    func testDuplicateCallbackDoesNotFinishEarlyOrReplaceFrame() { runStrip { g, output, done in g.emit(0, image: testImage(80)); g.emit(0, image: testImage(99)); g.emit(1, image: testImage(81)); g.emit(2, image: testImage(82)); self.wait(for: [done], timeout: 1); XCTAssertEqual(output.values.last?.0.map { $0.width }, [80, 81, 82]); XCTAssertEqual(output.values.filter { $0.1 }.count, 1) } }
    func testUnexpectedCallbackCannotConsumeRequestedSlot() { runStrip { g, output, done in g.callback?(CMTime(seconds: 999, preferredTimescale: 1000), testImage(99), .zero, .succeeded, nil); for i in 0..<3 { g.emit(i, image: testImage(80 + i)) }; self.wait(for: [done], timeout: 1); XCTAssertEqual(output.values.last?.0.map { $0.width }, [80, 81, 82]) } }
    func testEquivalentTimescalesMatchRequestedSlot() { runStrip { g, output, done in for i in (0..<3).reversed() { let t = CMTime(value: g.times[i].value * 2, timescale: g.times[i].timescale * 2); g.callback?(t, testImage(80 + i), .zero, .succeeded, nil) }; self.wait(for: [done], timeout: 1); XCTAssertEqual(output.values.last?.0.map { $0.width }, [80, 81, 82]) } }
    func testConcurrentCallbacksAreSerialized() throws { if baseline { throw XCTSkip("Original unsynchronized array mutation can trap") }; runStrip(64) { g, output, done in DispatchQueue.concurrentPerform(iterations: 64) { g.emit($0, image: testImage(80 + $0)) }; self.wait(for: [done], timeout: 2); XCTAssertEqual(output.values.last?.0.map { $0.width }, Array(80..<144)); XCTAssertEqual(output.values.filter { $0.1 }.count, 1) } }
    func testBlurredMissingSlotsDoNotMoveSuccessfulFrames() { runStrip(3, blur: true) { g, output, done in g.emit(2, image: testImage(82)); g.emit(0, image: nil, result: .failed); g.emit(1, image: testImage(81)); self.wait(for: [done], timeout: 1); XCTAssertEqual(output.values.last?.0.count, 3); XCTAssertEqual(output.values.last?.0[1].width, 81); XCTAssertEqual(output.values.last?.0[2].width, 82) } }
    func testGeneratorReceivesScaleTransformAndComposition() { let composition = AVMutableVideoComposition(); runStrip(composition: composition) { g, _, done in XCTAssertTrue(g.videoComposition === composition); XCTAssertEqual(g.maximumSize, CGSize(width: 80, height: 40)); XCTAssertTrue(g.appliesPreferredTrackTransform); XCTAssertEqual(g.requestedTimeToleranceBefore, .zero); XCTAssertEqual(g.requestedTimeToleranceAfter, .zero); for i in 0..<3 { g.emit(i) }; self.wait(for: [done], timeout: 1) } }
    func testFractionalDurationSamplesStayBeforeEnd() { let a = TestAsset(); a.duration = CMTime(value: 1, timescale: 600); runStrip(8, asset: a) { g, output, done in XCTAssertTrue(g.times.allSatisfy { CMTimeCompare($0, a.duration) < 0 }); XCTAssertEqual(Set(g.times.map { $0.seconds }).count, g.times.count); for i in g.times.indices { g.emit(i) }; self.wait(for: [done], timeout: 1); XCTAssertEqual(output.values.last?.0.count, 8) } }
    func testZeroAndNegativeCountsCompleteWithoutGenerator() throws { if baseline { throw XCTSkip("Original count division/array range can trap") }; for count in [0, -1, Int.max] { let done = expectation(description: "invalid count"); let a = TestAsset(); a.onGenerate = { _ in XCTFail("unexpected generator") }; let d = generateVideoScrubberThumbs(for: a, composition: nil, size: CGSize(width: 40, height: 20), count: count, gradually: true, blur: true).start(next: { XCTAssertTrue($0.0.isEmpty); XCTAssertTrue($0.1) }, completed: { done.fulfill() }); wait(for: [done], timeout: 1); d.dispose() } }
    func testInvalidSizesCompleteWithoutAllocation() throws { if baseline { throw XCTSkip("Original DrawingContext allocation is unchecked") }; for size in [CGSize.zero, CGSize(width: -1, height: 10), CGSize(width: CGFloat.nan, height: 10), CGSize(width: CGFloat.infinity, height: 10), CGSize(width: 1e100, height: 10)] { let done = expectation(description: "invalid size"); let d = generateVideoScrubberThumbs(for: TestAsset(), composition: nil, size: size, count: 3, gradually: true, blur: true).start(next: { XCTAssertTrue($0.0.isEmpty); XCTAssertTrue($0.1) }, completed: { done.fulfill() }); wait(for: [done], timeout: 1); d.dispose() } }
    func testInvalidDurationsCompleteWithoutGenerator() throws { if baseline { throw XCTSkip("Original invalid CMTime to Int conversion can trap") }; for duration in [CMTime.zero, .invalid, .indefinite, .positiveInfinity, CMTime(value: -1, timescale: 1)] { let done = expectation(description: "invalid duration"); let a = TestAsset(); a.duration = duration; a.onGenerate = { _ in XCTFail("unexpected generator") }; let d = generateVideoScrubberThumbs(for: a, composition: nil, size: CGSize(width: 40, height: 20), count: 3, gradually: true, blur: true).start(next: { XCTAssertTrue($0.0.isEmpty); XCTAssertTrue($0.1) }, completed: { done.fulfill() }); wait(for: [done], timeout: 1); d.dispose() } }
    func testCancellationCancelsDecoderAndDropsLateCallbacks() {
        let a = TestAsset(), output = Output<([CGImage], Bool)>()
        let start = expectation(description: "start"), cancel = expectation(description: "cancel")
        var generator: TestImageGenerator?
        a.onGenerate = { generator = $0; start.fulfill() }; a.onCancel = { cancel.fulfill() }
        let d = generateVideoScrubberThumbs(for: a, composition: nil, size: CGSize(width: 40, height: 20), count: 3, gradually: true, blur: false).start(next: { output.add($0) })
        wait(for: [start], timeout: 1); d.dispose(); wait(for: [cancel], timeout: 1)
        generator?.emit(0); generator?.emit(1); generator?.emit(2)
        XCTAssertTrue(output.values.isEmpty); XCTAssertEqual(generator?.cancellations, 1)
    }
    func testTwoSubscribersOwnSeparateGenerators() {
        let a = TestAsset(); let starts = expectation(description: "two starts"); starts.expectedFulfillmentCount = 2
        var generators: [TestImageGenerator] = []; let lock = NSLock()
        a.onGenerate = { lock.lock(); generators.append($0); lock.unlock(); starts.fulfill() }
        let signal = generateVideoScrubberThumbs(for: a, composition: nil, size: CGSize(width: 40, height: 20), count: 3, gradually: true, blur: false)
        let d1 = signal.start(), d2 = signal.start(); wait(for: [starts], timeout: 1)
        XCTAssertEqual(generators.count, 2); XCTAssertFalse(generators[0] === generators[1]); d1.dispose(); d2.dispose()
    }
    func testSingleTickDurationCoalescesUnrepresentableSampleTimes() { let a = TestAsset(); a.duration = CMTime(value: 1, timescale: Int32.max); runStrip(8, asset: a) { g, output, done in XCTAssertTrue(g.times.allSatisfy { CMTimeCompare($0, a.duration) < 0 }); XCTAssertEqual(Set(g.times.map { $0.seconds }).count, g.times.count); for i in g.times.indices { g.emit(i) }; self.wait(for: [done], timeout: 1); XCTAssertEqual(output.values.last?.0.count, 8) } }
    func testGeneratorReleasedOnCompletionWhileSubscriptionIsRetained() {
        let a = TestAsset(); let started = expectation(description: "owned generator"), done = expectation(description: "release")
        weak var generator: TestImageGenerator?
        a.onGenerate = { generator = $0; started.fulfill() }
        let d = generateVideoScrubberThumbs(for: a, composition: nil, size: CGSize(width: 40, height: 20), count: 1, gradually: false, blur: false).start(completed: { done.fulfill() })
        wait(for: [started], timeout: 1)
        generator?.emit(0)
        wait(for: [done], timeout: 1)
        XCTAssertNil(generator)
        d.dispose()
    }
    func testCancellationReleasesGeneratorWithoutBackendCallback() {
        let a = TestAsset(); let started = expectation(description: "owned generator"), cancelled = expectation(description: "cancelled")
        weak var generator: TestImageGenerator?
        a.onGenerate = { generator = $0; started.fulfill() }; a.onCancel = { cancelled.fulfill() }
        let d = generateVideoScrubberThumbs(for: a, composition: nil, size: CGSize(width: 40, height: 20), count: 3, gradually: false, blur: false).start()
        wait(for: [started], timeout: 1); d.dispose(); wait(for: [cancelled], timeout: 1)
        let drained = expectation(description: "release queue")
        DispatchQueue.global().async { for _ in 0..<1000 { if generator == nil { break }; Thread.sleep(forTimeInterval: 0.001) }; drained.fulfill() }
        wait(for: [drained], timeout: 2); XCTAssertNil(generator)
    }
    func testSynchronousGeneratorCallbackCanCancelFromFirstValue() {
        let a = TestAsset(); let done = expectation(description: "first image"), cancelled = expectation(description: "decoder cancelled")
        a.onGenerate = { $0.emit(0) }; a.onCancel = { cancelled.fulfill() }
        let d = (generateVideoScrubberThumbs(for: a, composition: nil, size: CGSize(width: 40, height: 20), count: 3, gradually: true, blur: false) |> take(1)).start(completed: { done.fulfill() })
        wait(for: [done, cancelled], timeout: 1); d.dispose()
    }
    func testColdSignalDoesNotStartGenerator() { let a = TestAsset(); a.onGenerate = { _ in XCTFail("cold signal started") }; _ = generateVideoScrubberThumbs(for: a, composition: nil, size: CGSize(width: 40, height: 20), count: 3, gradually: true, blur: false) }
    func preview(_ asset: TestComposition = TestComposition(), body: (TestImageGenerator, Output<(CGImage?, CGImage?)>, XCTestExpectation, Disposable) -> Void) {
        let start = expectation(description: "preview start"), done = expectation(description: "preview complete")
        var generator: TestImageGenerator?; let output = Output<(CGImage?, CGImage?)>()
        asset.onGenerate = { generator = $0; start.fulfill() }
        let d = generateVideoAvatarPreview(for: asset, composition: nil, highSize: CGSize(width: 40, height: 20), lowSize: CGSize(width: 10, height: 10), at: 3).start(next: { output.add($0) }, completed: { done.fulfill() })
        defer { d.dispose(); asset.onGenerate = nil }; wait(for: [start], timeout: 1)
        guard let generator else { return }; body(generator, output, done, d)
    }
    func testPreviewProducesSeparateAspectFittedSmallImage() { preview { g, output, done, _ in g.emit(0); self.wait(for: [done], timeout: 1); XCTAssertEqual(output.values.last?.0?.width, 80); XCTAssertEqual(output.values.last?.1?.width, 20); XCTAssertEqual(output.values.last?.1?.height, 10) } }
    func testPreviewFailureCompletesWithNilImages() { let a = TestComposition(); a.copyImage = nil; preview(a) { g, output, done, _ in g.emit(0, image: nil, result: .failed); self.wait(for: [done], timeout: 1); XCTAssertNil(output.values.last?.0); XCTAssertNil(output.values.last?.1) } }
    func testPreviewCancellationCancelsActualGenerator() { let a = TestComposition(); let cancel = expectation(description: "preview cancel"); a.onCancel = { cancel.fulfill() }; preview(a) { _, _, done, d in done.isInverted = true; d.dispose(); self.wait(for: [cancel], timeout: 1); self.wait(for: [done], timeout: 0.03) } }
    func testInvalidPreviewSizesTerminateWithoutDecoding() throws {
        if baseline { throw XCTSkip("Original decoder size validation is absent") }
        for size in [CGSize.zero, CGSize(width: CGFloat.nan, height: 10), CGSize(width: 10, height: -1)] {
            for invalidHigh in [true, false] {
                let a = TestComposition(); let done = expectation(description: "invalid preview size")
                a.onGenerate = { _ in XCTFail("invalid size decoded") }
                let valid = CGSize(width: 10, height: 10)
                let d = generateVideoAvatarPreview(for: a, composition: nil, highSize: invalidHigh ? size : valid, lowSize: invalidHigh ? valid : size, at: 3).start(next: { XCTAssertNil($0.0); XCTAssertNil($0.1) }, completed: { done.fulfill() })
                wait(for: [done], timeout: 1); d.dispose()
            }
        }
    }
    func testPreviewResizePreservesImageOrientationAndColors() {
        preview { g, output, done, _ in
            g.emit(0); self.wait(for: [done], timeout: 1)
            let image = output.values.last!.1!
            let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            let pixels = context.data!.assumingMemoryBound(to: UInt8.self)
            let left = (image.height / 2 * image.width + 1) * 4
            let right = (image.height / 2 * image.width + image.width - 2) * 4
            XCTAssertGreaterThan(pixels[left], 200); XCTAssertLessThan(pixels[left + 2], 30)
            XCTAssertGreaterThan(pixels[right + 2], 200); XCTAssertLessThan(pixels[right], 30)
        }
    }
    func testPreviewDuplicateCallbackCompletesOnce() { preview { g, output, done, _ in g.emit(0); g.emit(0); self.wait(for: [done], timeout: 1); XCTAssertEqual(output.values.count, 1) } }
    func testInvalidPreviewTimeCompletesWithoutGenerator() throws { if baseline { throw XCTSkip("Original non-finite time conversion is unchecked") }; for seconds in [-1, Double.nan, Double.infinity, Double.greatestFiniteMagnitude, 10, 11] { let a = TestComposition(); let done = expectation(description: "invalid preview"); a.onGenerate = { _ in XCTFail("invalid request decoded") }; let d = generateVideoAvatarPreview(for: a, composition: nil, highSize: CGSize(width: 40, height: 20), lowSize: CGSize(width: 10, height: 10), at: seconds).start(next: { XCTAssertNil($0.0); XCTAssertNil($0.1) }, completed: { done.fulfill() }); wait(for: [done], timeout: 1); d.dispose() } }
}
