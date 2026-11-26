import Cocoa
import XCTest
import SwiftSignalKit
@testable import TGUIKit

private final class ImageSignalSource<T> {
    var initial: T?
    var subscriber: Subscriber<T, NoError>?
    var onStart: (() -> Void)?
    var onDispose: (() -> Void)?
    var starts = 0
    var disposals = 0

    init(_ initial: T? = nil) { self.initial = initial }

    var signal: Signal<T, NoError> {
        Signal { [weak self] subscriber in
            guard let self else { return EmptyDisposable }
            self.starts += 1
            self.subscriber = subscriber
            self.onStart?()
            if let initial = self.initial { subscriber.putNext(initial) }
            return ActionDisposable { [weak self, weak subscriber] in
                guard let self else { return }
                self.disposals += 1
                if self.subscriber === subscriber { self.subscriber = nil }
                self.onDispose?()
            }
        }
    }

    func emit(_ value: T) { subscriber?.putNext(value) }
}

final class TransformImageSignalTests: XCTestCase {
    override func setUp() { TGUIKitTestBootstrap.install() }

    func image(_ color: NSColor) throws -> CGImage { try TransformImageAssignmentTests().makeImage(color) }

    func transform(_ color: NSColor, execute: @escaping () -> Void = {}) -> ImageDataTransformation {
        TransformImageViewTests().transformation { arguments in
            execute()
            let context = DrawingContext(size: arguments.drawingSize, scale: 1, clear: true)
            context.withContext { context in
                context.setFillColor(color.cgColor)
                context.fill(CGRect(origin: .zero, size: arguments.drawingSize))
            }
            return context
        }
    }

    func testCachedCallbackReplacementKeepsLatestSubscriptionAndQuality() throws {
        let view = TransformImageView(), red = try image(.red), blue = try image(.blue), green = try image(.green)
        let old = ImageSignalSource<TransformImageResult?>(TransformImageResult(red, false))
        let next = ImageSignalSource<TransformImageResult?>(TransformImageResult(blue, true))
        view.imageUpdated = { [weak view] value in
            if value as AnyObject? === red { view?.setSignal(signal: next.signal) }
        }
        view.setSignal(signal: old.signal)
        XCTAssertEqual(old.disposals, 1)
        XCTAssertEqual(next.disposals, 0)
        XCTAssertTrue(view.image === blue)
        XCTAssertTrue(view.isFullyLoaded)
        next.emit(TransformImageResult(green, true))
        XCTAssertTrue(view.image === green)
        old.emit(TransformImageResult(red, false))
        XCTAssertTrue(view.image === green)
        view.dispose()
        XCTAssertEqual(next.disposals, 1)
    }

    func testClearDuringSynchronousStartCancelsSourceBeforeReturning() throws {
        let view = TransformImageView(), red = try image(.red), blue = try image(.blue)
        let source = ImageSignalSource<TransformImageResult?>(TransformImageResult(red, true))
        view.imageUpdated = { [weak view] value in if value != nil { view?.clear() } }
        view.setSignal(signal: source.signal)
        XCTAssertEqual(source.disposals, 1)
        XCTAssertNil(view.image)
        XCTAssertFalse(view.isFullyLoaded)
        view.imageUpdated = nil
        source.emit(TransformImageResult(blue, true))
        XCTAssertNil(view.image)
        view.dispose()
    }

    func testClearCallbackCanInstallANewSubscription() throws {
        let view = TransformImageView(), red = try image(.red), blue = try image(.blue), green = try image(.green)
        let old = ImageSignalSource<TransformImageResult?>(TransformImageResult(red, false))
        let next = ImageSignalSource<TransformImageResult?>(TransformImageResult(blue, true))
        view.setSignal(signal: old.signal)
        view.imageUpdated = { [weak view] value in if value == nil { view?.setSignal(signal: next.signal) } }
        view.clear()
        XCTAssertEqual(old.disposals, 1)
        XCTAssertEqual(next.disposals, 0)
        XCTAssertTrue(view.image === blue)
        XCTAssertTrue(view.isFullyLoaded)
        next.emit(TransformImageResult(green, true))
        XCTAssertTrue(view.image === green)
        view.dispose()
    }

    func testTransformedCallbackDisposalStopsFurtherRenderingAndCaching() {
        let view = TransformImageView()
        var renders = 0, cached = 0
        let source = ImageSignalSource(transform(.red, execute: { renders += 1 }))
        view.set(arguments: TransformImageViewTests().arguments())
        view.imageUpdated = { [weak view] value in if value != nil { view?.dispose() } }
        view.setSignal(source.signal, synchronousLoad: true, cacheImage: { _ in cached += 1 })
        XCTAssertEqual(source.disposals, 1)
        XCTAssertEqual(renders, 1)
        XCTAssertEqual(cached, 0)
        source.emit(transform(.blue, execute: { renders += 1 }))
        view.set(arguments: TransformImageViewTests().arguments(mode: .blurBackground))
        XCTAssertEqual(renders, 1)
        XCTAssertEqual(cached, 0)
        view.dispose()
    }

    func testReplacementDuringTransformCannotOverwriteNewImage() throws {
        let view = TransformImageView(), blue = try image(.blue), green = try image(.green)
        let next = ImageSignalSource<TransformImageResult?>(TransformImageResult(blue, true))
        let old = ImageSignalSource(transform(.red, execute: { [weak view] in view?.setSignal(signal: next.signal) }))
        var cached = 0
        view.set(arguments: TransformImageViewTests().arguments())
        view.setSignal(old.signal, synchronousLoad: true, cacheImage: { _ in cached += 1 })
        XCTAssertTrue(view.image === blue)
        XCTAssertEqual(old.disposals, 1)
        XCTAssertEqual(next.disposals, 0)
        XCTAssertEqual(cached, 0)
        next.emit(TransformImageResult(green, true))
        XCTAssertTrue(view.image === green)
        view.dispose()
    }

    func testReplacementDisposesOldSourceBeforeStartingNext() throws {
        let view = TransformImageView(), red = try image(.red), blue = try image(.blue)
        let old = ImageSignalSource<TransformImageResult?>(TransformImageResult(red, false))
        let next = ImageSignalSource<TransformImageResult?>(TransformImageResult(blue, true))
        next.onStart = { XCTAssertEqual(old.disposals, 1) }
        view.setSignal(signal: old.signal)
        view.setSignal(signal: next.signal)
        XCTAssertTrue(view.image === blue)
        view.dispose()
    }

    func testRebindingFromDisposalTakesPrecedenceOverInterruptedReplacement() throws {
        let view = TransformImageView(), red = try image(.red), blue = try image(.blue), green = try image(.green)
        let old = ImageSignalSource<TransformImageResult?>(TransformImageResult(red, false))
        let interrupted = ImageSignalSource<TransformImageResult?>(TransformImageResult(blue, false))
        let newest = ImageSignalSource<TransformImageResult?>(TransformImageResult(green, true))
        view.setSignal(signal: old.signal)
        old.onDispose = { [weak view] in view?.setSignal(signal: newest.signal) }
        view.setSignal(signal: interrupted.signal)
        XCTAssertEqual(interrupted.starts, 0)
        XCTAssertTrue(view.image === green)
        XCTAssertTrue(view.isFullyLoaded)
        XCTAssertEqual(newest.disposals, 0)
        view.dispose()
    }

    func testCachedQualityIsCommittedBeforeImageCallback() throws {
        let view = TransformImageView(), red = try image(.red)
        var calls = 0
        view.imageUpdated = { [weak view] _ in
            calls += 1
            XCTAssertTrue(view?.isFullyLoaded == true)
        }
        view.setSignal(signal: .single(TransformImageResult(red, true)))
        XCTAssertEqual(calls, 1)
        view.dispose()
    }

    func testQueuedCachedResultCannotReplaceNewBinding() throws {
        let view = TransformImageView(), red = try image(.red), blue = try image(.blue)
        let old = ImageSignalSource<TransformImageResult?>()
        view.setSignal(signal: old.signal)
        let queued = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            old.emit(TransformImageResult(red, false))
            queued.signal()
        }
        XCTAssertEqual(queued.wait(timeout: .now() + 2), .success)
        view.setSignal(signal: .single(TransformImageResult(blue, true)))
        let drained = expectation(description: "queued old delivery drained")
        DispatchQueue.main.async { drained.fulfill() }
        wait(for: [drained], timeout: 2)
        XCTAssertTrue(view.image === blue)
        XCTAssertTrue(view.isFullyLoaded)
        XCTAssertEqual(old.disposals, 1)
        view.dispose()
    }

    func testBackgroundTransformFinishingAfterReplacementIsDiscarded() throws {
        let view = TransformImageView(), blue = try image(.blue)
        let started = DispatchSemaphore(value: 0), resume = DispatchSemaphore(value: 0)
        let executed = expectation(description: "old transform returned")
        let cached = expectation(description: "old result must not be cached")
        cached.isInverted = true
        let old = ImageSignalSource(transform(.red, execute: {
            started.signal()
            _ = resume.wait(timeout: .now() + 5)
            executed.fulfill()
        }))
        view.set(arguments: TransformImageViewTests().arguments())
        view.setSignal(old.signal, cacheImage: { _ in cached.fulfill() })
        XCTAssertEqual(started.wait(timeout: .now() + 2), .success)
        view.setSignal(signal: .single(TransformImageResult(blue, true)))
        resume.signal()
        wait(for: [executed], timeout: 2)
        wait(for: [cached], timeout: 0.2)
        XCTAssertTrue(view.image === blue)
        XCTAssertTrue(view.isFullyLoaded)
        XCTAssertEqual(old.disposals, 1)
        view.dispose()
    }

    func testInstantClearCallbackCanReplacePendingTransformSubscription() throws {
        let view = TransformImageView(), red = try image(.red), blue = try image(.blue)
        view.image = red
        view.set(arguments: TransformImageViewTests().arguments())
        let interrupted = ImageSignalSource(transform(.green))
        let newest = ImageSignalSource<TransformImageResult?>(TransformImageResult(blue, true))
        view.imageUpdated = { [weak view] value in if value == nil { view?.setSignal(signal: newest.signal) } }
        view.setSignal(interrupted.signal, clearInstantly: true, synchronousLoad: true)
        XCTAssertEqual(interrupted.starts, 0)
        XCTAssertEqual(newest.disposals, 0)
        XCTAssertTrue(view.image === blue)
        view.dispose()
    }

    func testFullyLoadedCacheStillSkipsTransformSubscription() throws {
        let view = TransformImageView(), red = try image(.red)
        let cached = ImageSignalSource<TransformImageResult?>(TransformImageResult(red, true))
        let rendering = ImageSignalSource(transform(.blue))
        view.setSignal(signal: cached.signal)
        view.setSignal(rendering.signal, synchronousLoad: true)
        XCTAssertEqual(cached.disposals, 1)
        XCTAssertEqual(rendering.starts, 0)
        XCTAssertTrue(view.image === red)
        XCTAssertFalse(view.isFullyLoaded)
        view.dispose()
    }

    func testDeinitDisposesActiveSource() throws {
        let source = ImageSignalSource<TransformImageResult?>(TransformImageResult(try image(.red), false))
        weak var released: TransformImageView?
        autoreleasepool {
            let view = TransformImageView()
            released = view
            view.setSignal(signal: source.signal)
        }
        XCTAssertNil(released)
        XCTAssertEqual(source.disposals, 1)
        XCTAssertNil(source.subscriber)
    }

    func testCancellationRemovesWastedTransformWorkComparedWithOriginal() {
        let baseline = LegacyImageSignalView(), candidate = TransformImageView()
        var counts = [0, 0], cached = [0, 0]
        let sources = [ImageSignalSource(transform(.red, execute: { counts[0] += 1 })), ImageSignalSource(transform(.red, execute: { counts[1] += 1 }))]
        let fixture = TransformImageViewTests()
        baseline.set(arguments: fixture.arguments()); candidate.set(arguments: fixture.arguments())
        baseline.imageUpdated = { [weak baseline] _ in baseline?.dispose() }
        candidate.imageUpdated = { [weak candidate] _ in candidate?.dispose() }
        baseline.setSignal(sources[0].signal, synchronousLoad: true, cacheImage: { _ in cached[0] += 1 })
        candidate.setSignal(sources[1].signal, synchronousLoad: true, cacheImage: { _ in cached[1] += 1 })
        baseline.imageUpdated = nil; candidate.imageUpdated = nil
        for index in 0..<100 {
            let value = fixture.arguments(mode: index % 2 == 0 ? .blurBackground : .none)
            baseline.set(arguments: value); candidate.set(arguments: value)
        }
        XCTAssertEqual(counts, [101, 1])
        XCTAssertEqual(cached, [101, 0])
        XCTAssertEqual(sources[0].disposals, 0)
        XCTAssertEqual(sources[1].disposals, 1)
        baseline.dispose(); candidate.dispose()
    }
}
