import Cocoa
import XCTest
import SwiftSignalKit
@testable import TGUIKit

final class ObservedDrawingContext: DrawingContext {
    var onGenerate: (() -> Void)?
    var onRelease: (() -> Void)?

    override func generateDisplayImage() -> CGImage? {
        onGenerate?()
        return super.generateDisplayImage()
    }

    deinit { onRelease?() }
}

final class TransformImageRenderCancellationTests: XCTestCase {
    override func setUp() { TGUIKitTestBootstrap.install() }

    func testSynchronousCancellationSkipsImageFinalization() {
        for clear in [false, true] {
            for protected in [false, true] {
                let view = TransformImageView()
                var generated = 0, cached = 0
                let context = ObservedDrawingContext(size: NSSize(width: 20, height: 20), scale: 1, clear: true)
                context.onGenerate = { generated += 1 }
                view.set(arguments: TransformImageViewTests().arguments())
                view.setSignal(.single(ImageDataTransformation(execute: { [weak view] _, _ in
                    if clear { view?.clear() } else { view?.dispose() }
                    return context
                })), synchronousLoad: true, cacheImage: { _ in cached += 1 }, isProtected: protected)
                XCTAssertEqual(generated, 0)
                XCTAssertEqual(cached, 0)
                XCTAssertNil(view.image)
            }
        }
    }

    func testReplacementDuringTransformSkipsOldFinalization() throws {
        let view = TransformImageView(), replacement = try TransformImageAssignmentTests().makeImage(.blue)
        var generated = 0
        let context = ObservedDrawingContext(size: NSSize(width: 20, height: 20), scale: 1, clear: true)
        context.onGenerate = { generated += 1 }
        view.set(arguments: TransformImageViewTests().arguments())
        view.setSignal(.single(ImageDataTransformation(execute: { [weak view] _, _ in
            view?.setSignal(signal: .single(TransformImageResult(replacement, true)))
            return context
        })), synchronousLoad: true)
        XCTAssertEqual(generated, 0)
        XCTAssertTrue(view.image === replacement)
        XCTAssertTrue(view.isFullyLoaded)
    }

    func testReplacementDuringImageFinalizationKeepsNewBinding() throws {
        let view = TransformImageView(), replacement = try TransformImageAssignmentTests().makeImage(.blue)
        var generated = 0, cached = 0
        let context = ObservedDrawingContext(size: NSSize(width: 20, height: 20), scale: 1, clear: true)
        context.onGenerate = { [weak view] in
            generated += 1
            view?.setSignal(signal: .single(TransformImageResult(replacement, true)))
        }
        view.set(arguments: TransformImageViewTests().arguments())
        view.setSignal(.single(ImageDataTransformation(execute: { _, _ in context })), synchronousLoad: true, cacheImage: { _ in cached += 1 }, isProtected: true)
        XCTAssertEqual(generated, 1)
        XCTAssertEqual(cached, 0)
        XCTAssertTrue(view.image === replacement)
        XCTAssertTrue(view.isFullyLoaded)
    }

    func testCancellationDuringSourceStartSkipsTransformExecution() {
        let view = TransformImageView()
        var executed = 0, disposed = 0
        view.set(arguments: TransformImageViewTests().arguments())
        let signal = Signal<ImageDataTransformation, NoError> { [weak view] subscriber in
            view?.dispose()
            subscriber.putNext(ImageDataTransformation(execute: { _, _ in executed += 1; return nil }))
            return ActionDisposable { disposed += 1 }
        }
        view.setSignal(signal, synchronousLoad: true)
        XCTAssertEqual(executed, 0)
        XCTAssertEqual(disposed, 1)
    }

    func testBackgroundCancellationStopsFinalizationAndReleasesContext() throws {
        for action in ["dispose", "clear", "replace", "deinit"] {
            let started = DispatchSemaphore(value: 0), resume = DispatchSemaphore(value: 0)
            let released = expectation(description: "Cancelled context released: \(action)")
            let generated = Atomic(value: 0)
            var view: TransformImageView?
            let replacement = try TransformImageAssignmentTests().makeImage(.blue)
            autoreleasepool {
                view = TransformImageView()
                view?.set(arguments: TransformImageViewTests().arguments())
                view?.setSignal(.single(ImageDataTransformation(execute: { _, _ in
                    let context = ObservedDrawingContext(size: NSSize(width: 100, height: 100), scale: 1, clear: true)
                    context.onGenerate = { _ = generated.modify { $0 + 1 } }
                    context.onRelease = { released.fulfill() }
                    started.signal()
                    _ = resume.wait(timeout: .now() + 5)
                    return context
                })), cacheImage: { _ in XCTFail("Cancelled result reached cache") }, isProtected: true)
            }
            weak var weakView = view
            XCTAssertEqual(started.wait(timeout: .now() + 2), .success)
            switch action {
            case "dispose": view?.dispose()
            case "clear": view?.clear()
            case "replace": view?.setSignal(signal: .single(TransformImageResult(replacement, true)))
            default: view = nil; XCTAssertNil(weakView)
            }
            resume.signal()
            wait(for: [released], timeout: 3)
            XCTAssertEqual(generated.with { $0 }, 0)
            if action == "replace" { XCTAssertTrue(view?.image === replacement) }
            view?.dispose()
        }
    }

    func testActiveTransformsStillProduceIdenticalPixelsAndProtectedBuffers() throws {
        for protected in [false, true] {
            for synchronous in [false, true] {
                let view = TransformImageView()
                let delivered = expectation(description: "Active render \(protected) \(synchronous)")
                let source = TransformImageSignalTests().transform(.red)
                let arguments = TransformImageViewTests().arguments()
                let expected = try XCTUnwrap(source.execute(arguments, source.data)?.generateDisplayImage())
                view.set(arguments: arguments)
                view.setSignal(.single(source), synchronousLoad: synchronous, cacheImage: { result in
                    XCTAssertTrue(Thread.isMainThread)
                    XCTAssertTrue(result.highQuality)
                    if let actual = result.image { XCTAssertEqual(PixelBuffer(actual), PixelBuffer(expected)) } else { XCTFail("Missing image") }
                    XCTAssertEqual(result.sampleBuffer != nil, protected)
                    delivered.fulfill()
                }, isProtected: protected)
                wait(for: [delivered], timeout: 3)
                view.dispose()
            }
        }
    }

    func testIncompleteDataInvalidatesRenderedShortcutAndLaterDataStillRenders() {
        let view = TransformImageView(), arguments = TransformImageViewTests().arguments()
        var emit: ((ImageDataTransformation) -> Void)?
        let signal = Signal<ImageDataTransformation, NoError> { subscriber in
            emit = { subscriber.putNext($0) }
            return EmptyDisposable
        }
        var executed = 0
        func data(_ complete: Bool) -> ImageDataTransformation {
            ImageDataTransformation(data: ImageRenderData(nil, nil, complete), execute: { _, _ in executed += 1; return nil })
        }
        view.set(arguments: arguments)
        view.setSignal(signal, synchronousLoad: true, alreadyRendered: arguments)
        emit?(data(true)); emit?(data(true))
        XCTAssertEqual(executed, 0)
        emit?(data(false))
        XCTAssertEqual(executed, 1)
        emit?(data(true))
        XCTAssertEqual(executed, 2)
        view.dispose()
        emit = nil
    }
}
