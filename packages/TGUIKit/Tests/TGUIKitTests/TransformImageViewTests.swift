import Cocoa
import XCTest
import SwiftSignalKit
@testable import TGUIKit

final class TransformImageViewTests: XCTestCase {
    override func setUp() { TGUIKitTestBootstrap.install() }

    func arguments(mode: TransformImageResizeMode = .none, insets: NSEdgeInsets = .init()) -> TransformImageArguments {
        TransformImageArguments(corners: .init(), imageSize: NSSize(width: 20, height: 20), boundingSize: NSSize(width: 20, height: 20), intrinsicInsets: insets, resizeMode: mode, scale: 1)
    }

    func transformation(_ execute: @escaping (TransformImageArguments) -> DrawingContext?) -> ImageDataTransformation {
        ImageDataTransformation(data: ImageRenderData(nil, nil, true), execute: { value, _ in execute(value) })
    }

    func testResizeModeAndInsetsChangesTriggerRendering() {
        let view = TransformImageView()
        var rendered: [TransformImageArguments] = []
        view.setSignal(.single(transformation { value in rendered.append(value); return nil }), synchronousLoad: true)
        let values = [arguments(), arguments(mode: .blurBackground), arguments(mode: .fill(.red)), arguments(insets: .init(top: 1, left: 2, bottom: 3, right: 4))]
        for value in values { view.set(arguments: value) }
        XCTAssertEqual(rendered.count, values.count)
    }

    func testArgumentsSurviveLateSubscriptionClearDisposeAndSignalReplacement() {
        let view = TransformImageView(), value = arguments()
        var calls: [Int] = []
        view.set(arguments: value)
        for step in 0..<5 {
            view.setSignal(.single(transformation { _ in calls.append(step); return nil }), synchronousLoad: true)
            for _ in 0..<100 { view.set(arguments: value) }
            if step % 2 == 0 { view.clear() } else { view.dispose() }
        }
        XCTAssertEqual(calls, [0, 1, 2, 3, 4])
    }

    func testNewDataStillRendersWhenArgumentsAreUnchanged() {
        let view = TransformImageView(), value = arguments()
        var emit: ((ImageDataTransformation) -> Void)?
        let signal = Signal<ImageDataTransformation, NoError> { subscriber in
            emit = { subscriber.putNext($0) }
            return EmptyDisposable
        }
        var calls = 0
        view.setSignal(signal, synchronousLoad: true)
        view.set(arguments: value)
        XCTAssertEqual(calls, 0)
        for _ in 0..<4 {
            emit?(transformation { _ in calls += 1; return nil })
            view.set(arguments: value)
        }
        XCTAssertEqual(calls, 4)
        view.dispose()
        emit = nil
    }

    func testRenderedCacheSkipInvalidatesOnResizeModeAndInsets() {
        for changed in [arguments(mode: .blurBackground), arguments(insets: .init(top: 0, left: 3, bottom: 0, right: 0))] {
            let view = TransformImageView(), original = arguments()
            var calls = 0
            view.set(arguments: original)
            view.setSignal(.single(transformation { _ in calls += 1; return nil }), synchronousLoad: true, alreadyRendered: original)
            XCTAssertEqual(calls, 0)
            view.set(arguments: changed)
            XCTAssertEqual(calls, 1)
            view.set(arguments: original)
            XCTAssertEqual(calls, 2)
        }
    }

    func testPipelinePixelsMatchWithChangedArgumentsAndCachedResults() throws {
        let baseline = LegacyTransformImageView(frame: NSRect(x: 0, y: 0, width: 50, height: 50))
        let candidate = TransformImageView(frame: baseline.frame)
        let draw = transformation { value in
            let context = DrawingContext(size: value.drawingSize, scale: value.scale, clear: true)
            context.withContext { ctx in
                let color: NSColor
                if case let .fill(fill) = value.resizeMode { color = fill } else { color = .blue }
                ctx.setFillColor(color.cgColor)
                ctx.fill(value.drawingRect)
            }
            return context
        }
        baseline.setSignal(.single(draw), synchronousLoad: true)
        candidate.setSignal(.single(draw), synchronousLoad: true)
        var previous: PixelBuffer?
        for value in [arguments(), arguments(mode: .fill(.red)), arguments(insets: .init(top: 1, left: 2, bottom: 3, right: 4))] {
            baseline.set(arguments: value); candidate.set(arguments: value)
            let expected = PixelBuffer(try XCTUnwrap(baseline.image)), actual = PixelBuffer(try XCTUnwrap(candidate.image))
            XCTAssertEqual(actual, expected)
            XCTAssertTrue(actual.bytes.contains { $0 != 0 })
            if let previous { XCTAssertNotEqual(actual, previous) }
            previous = actual
            let image = try XCTUnwrap(candidate.image)
            candidate.set(arguments: value)
            XCTAssertTrue(candidate.image === image)
        }
        let cached = try XCTUnwrap(candidate.image)
        candidate.setSignal(signal: .single(TransformImageResult(cached, true)))
        XCTAssertTrue(candidate.image === cached)
        XCTAssertTrue(candidate.isFullyLoaded)
    }

    func testBackgroundTransformsAndProtectedBuffersStillDeliver() {
        for protected in [false, true] {
            let view = TransformImageView()
            let rendered = expectation(description: "rendered \(protected)")
            rendered.expectedFulfillmentCount = 2
            var sizes: [Int] = []
            view.setSignal(.single(transformation { value in
                let context = DrawingContext(size: value.drawingSize, scale: 1, clear: true)
                context.withContext { ctx in
                    ctx.setFillColor(NSColor.red.cgColor)
                    ctx.fill(CGRect(origin: .zero, size: value.drawingSize))
                }
                return context
            }), synchronousLoad: false, cacheImage: { result in
                XCTAssertTrue(Thread.isMainThread)
                XCTAssertNotNil(result.image)
                XCTAssertEqual(result.sampleBuffer != nil, protected)
                sizes.append(result.image?.width ?? 0)
                rendered.fulfill()
            }, isProtected: protected)
            view.set(arguments: arguments())
            view.set(arguments: arguments())
            view.set(arguments: arguments(insets: .init(top: 0, left: 3, bottom: 0, right: 0)))
            wait(for: [rendered], timeout: 5)
            XCTAssertEqual(sizes, [20, 23])
            view.dispose()
        }
    }

    func testSynchronousReentrantArgumentUpdateKeepsLatestValue() {
        let view = TransformImageView(), first = arguments(), second = arguments(mode: .fill(.red))
        var seen: [TransformImageArguments] = []
        view.setSignal(.single(transformation { [weak view] value in
            seen.append(value)
            if value == first { view?.set(arguments: second) }
            return nil
        }), synchronousLoad: true)
        view.set(arguments: first)
        XCTAssertEqual(seen, [first, second])
        view.dispose()
        var latest: TransformImageArguments?
        view.setSignal(.single(transformation { value in latest = value; return nil }), synchronousLoad: true)
        XCTAssertEqual(latest, second)
    }

}
