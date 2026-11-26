import Cocoa
import XCTest
import SwiftSignalKit
@testable import TGUIKit

private final class ManualSource<T> {
    var subscriber: Subscriber<T, NoError>?
    var disposals = 0

    var signal: Signal<T, NoError> {
        Signal { [weak self] subscriber in
            self?.subscriber = subscriber
            return ActionDisposable { [weak self] in
                self?.disposals += 1
            }
        }
    }

    func emit(_ value: T) { subscriber?.putNext(value) }
}

private enum Contents: Equatable {
    case none
    case shared(ObjectIdentifier)
    case pixels(PixelBuffer)
}

private struct Snapshot: Equatable {
    let contents: Contents
    let image: Contents
    let contentsIsImage: Bool
    let hasImage: Bool
    let isFullyLoaded: Bool
    let animationKeys: [String]
    let updates: [Contents]
}

private final class Subject {
    let view: TransformImageView?
    let host: TransformImageLayer?
    var shared: [CGImage] = []
    private(set) var updates: [Contents] = []

    init(view: TransformImageView) {
        self.view = view
        self.host = nil
        view.imageUpdated = { [unowned self] value in self.updates.append(self.describe(value)) }
    }

    init(layer: TransformImageLayer) {
        self.view = nil
        self.host = layer
        layer.imageUpdated = { [unowned self] value in self.updates.append(self.describe(value)) }
    }

    static func both(frame: NSRect = NSRect(x: 0, y: 0, width: 20, height: 20)) -> [Subject] {
        [Subject(view: TransformImageView(frame: frame)), Subject(layer: TransformImageLayer(frame: frame))]
    }

    var hostLayer: CALayer { view?.layer ?? host! }

    var image: CGImage? {
        get { view?.image ?? host?.image }
        set { if let view { view.image = newValue } else { host?.image = newValue } }
    }

    var animatesAlphaOnFirstTransition: Bool {
        get { view?.animatesAlphaOnFirstTransition ?? host!.animatesAlphaOnFirstTransition }
        set { view?.animatesAlphaOnFirstTransition = newValue; host?.animatesAlphaOnFirstTransition = newValue }
    }

    var ignoreFullyLoad: Bool {
        get { view?.ignoreFullyLoad ?? host!.ignoreFullyLoad }
        set { view?.ignoreFullyLoad = newValue; host?.ignoreFullyLoad = newValue }
    }

    var isFullyLoaded: Bool { view?.isFullyLoaded ?? host!.isFullyLoaded }
    var hasImage: Bool { view?.hasImage ?? host!.hasImage }

    func clear() { view?.clear(); host?.clear() }
    func dispose() { view?.dispose(); host?.dispose() }
    func set(arguments: TransformImageArguments) { view?.set(arguments: arguments); host?.set(arguments: arguments) }

    func setSignal(signal: Signal<TransformImageResult?, NoError>, clearInstantly: Bool = true, animate: Bool = false) {
        view?.setSignal(signal: signal, clearInstantly: clearInstantly, animate: animate)
        host?.setSignal(signal: signal, clearInstantly: clearInstantly, animate: animate)
    }

    func setSignal(_ signal: Signal<ImageDataTransformation, NoError>, clearInstantly: Bool = false, animate: Bool = false, synchronousLoad: Bool = true, cacheImage: @escaping (TransformImageResult) -> Void = { _ in }, alreadyRendered: TransformImageArguments? = nil) {
        view?.setSignal(signal, clearInstantly: clearInstantly, animate: animate, synchronousLoad: synchronousLoad, cacheImage: cacheImage, alreadyRendered: alreadyRendered)
        host?.setSignal(signal, clearInstantly: clearInstantly, animate: animate, synchronousLoad: synchronousLoad, cacheImage: cacheImage, alreadyRendered: alreadyRendered)
    }

    func describe(_ value: Any?) -> Contents {
        guard let value else { return .none }
        let object = value as AnyObject
        if shared.contains(where: { $0 === object }) { return .shared(ObjectIdentifier(object)) }
        return .pixels(PixelBuffer(value as! CGImage))
    }

    func snapshot() -> Snapshot {
        let keys = (hostLayer.animationKeys() ?? []).sorted()
        hostLayer.removeAllAnimations()
        let result = Snapshot(contents: describe(hostLayer.contents), image: describe(image), contentsIsImage: hostLayer.contents as AnyObject? === image, hasImage: hasImage, isFullyLoaded: isFullyLoaded, animationKeys: keys, updates: updates)
        updates = []
        return result
    }
}

final class TransformImageLayerTests: XCTestCase {
    override func setUp() { TGUIKitTestBootstrap.install() }

    private func image(_ color: NSColor) throws -> CGImage { try TransformImageAssignmentTests().makeImage(color) }

    private func arguments(mode: TransformImageResizeMode = .none, insets: NSEdgeInsets = .init()) -> TransformImageArguments {
        TransformImageViewTests().arguments(mode: mode, insets: insets)
    }

    private func draw(highQuality: Bool = true, calls: @escaping () -> Void = {}) -> ImageDataTransformation {
        ImageDataTransformation(data: ImageRenderData(nil, nil, true), execute: { value, _ in
            calls()
            let context = DrawingContext(size: value.drawingSize, scale: 1, clear: true)
            context.withContext(isHighQuality: highQuality) { ctx in
                let color: NSColor
                if case let .fill(fill) = value.resizeMode { color = fill } else { color = .blue }
                ctx.setFillColor(color.cgColor)
                ctx.fill(CGRect(origin: .zero, size: value.drawingSize))
            }
            return context
        })
    }

    private func assertEquivalent(_ script: (Subject) throws -> [Snapshot], file: StaticString = #filePath, line: UInt = #line) rethrows {
        let subjects = Subject.both()
        let traces = try subjects.map { subject in try autoreleasepool { try script(subject) } }
        XCTAssertFalse(traces[0].isEmpty, file: file, line: line)
        XCTAssertEqual(traces[0], traces[1], file: file, line: line)
    }

    func testCachedResultsMatchAcrossHosts() throws {
        let red = try image(.red), blue = try image(.blue)
        for clearInstantly in [true, false] {
            for animate in [true, false] {
                try assertEquivalent { subject in
                    subject.shared = [red, blue]
                    let source = ManualSource<TransformImageResult?>()
                    subject.setSignal(signal: source.signal, clearInstantly: clearInstantly, animate: animate)
                    var trace = [subject.snapshot()]
                    for value in [TransformImageResult(red, false), TransformImageResult(blue, true), nil, TransformImageResult(nil, false), TransformImageResult(red, true)] {
                        source.emit(value)
                        trace.append(subject.snapshot())
                    }
                    XCTAssertTrue(subject.image === red)
                    XCTAssertTrue(subject.hostLayer.contents as AnyObject? === red)
                    subject.dispose()
                    XCTAssertEqual(source.disposals, 1)
                    return trace
                }
            }
        }
    }

    func testTransformedResultsMatchAcrossHosts() throws {
        for animate in [true, false] {
            for first in [true, false] {
                try assertEquivalent { subject in
                    subject.animatesAlphaOnFirstTransition = first
                    var cached: [PixelBuffer?] = []
                    subject.setSignal(.single(draw()), animate: animate, cacheImage: { cached.append($0.image.map(PixelBuffer.init)) })
                    var trace = [subject.snapshot()]
                    for value in [arguments(), arguments(mode: .fill(.red)), arguments(insets: .init(top: 1, left: 2, bottom: 3, right: 4)), arguments(insets: .init(top: 1, left: 2, bottom: 3, right: 4))] {
                        subject.set(arguments: value)
                        trace.append(subject.snapshot())
                    }
                    XCTAssertEqual(cached.count, 3)
                    XCTAssertTrue(subject.hostLayer.contents as AnyObject? === subject.image)
                    return trace
                }
            }
        }
    }

    func testAnimationKeysForFirstTransitionAndContentUpdates() throws {
        for subject in Subject.both() {
            subject.animatesAlphaOnFirstTransition = true
            subject.setSignal(.single(draw()), animate: true)
            subject.set(arguments: arguments())
            XCTAssertEqual(subject.snapshot().animationKeys, ["opacity"])
            subject.set(arguments: arguments(mode: .fill(.red)))
            XCTAssertEqual(subject.snapshot().animationKeys, ["contents"])
            let red = try image(.red)
            let source = ManualSource<TransformImageResult?>()
            subject.setSignal(signal: source.signal, animate: true)
            source.emit(TransformImageResult(red, false))
            XCTAssertEqual(subject.snapshot().animationKeys, ["contents"])
            subject.clear()
            subject.setSignal(signal: source.signal, animate: true)
            source.emit(TransformImageResult(red, false))
            XCTAssertEqual(subject.snapshot().animationKeys, ["opacity"])
        }
    }

    func testClearInstantlyMatchesAcrossHosts() throws {
        let red = try image(.red)
        for clearInstantly in [true, false] {
            try assertEquivalent { subject in
                subject.shared = [red]
                subject.image = red
                var trace = [subject.snapshot()]
                let source = ManualSource<ImageDataTransformation>()
                subject.setSignal(source.signal, clearInstantly: clearInstantly)
                trace.append(subject.snapshot())
                XCTAssertEqual(subject.image == nil, clearInstantly)
                subject.set(arguments: arguments())
                trace.append(subject.snapshot())
                source.emit(draw())
                trace.append(subject.snapshot())
                subject.clear()
                trace.append(subject.snapshot())
                XCTAssertNil(subject.hostLayer.contents)
                return trace
            }
        }
    }

    func testNewerSignalCancelsOlderAcrossHosts() throws {
        let red = try image(.red), blue = try image(.blue), green = try image(.green)
        try assertEquivalent { subject in
            subject.shared = [red, blue, green]
            let old = ManualSource<TransformImageResult?>(), next = ManualSource<TransformImageResult?>()
            subject.setSignal(signal: old.signal)
            old.emit(TransformImageResult(red, false))
            var trace = [subject.snapshot()]
            subject.setSignal(signal: next.signal)
            XCTAssertEqual(old.disposals, 1)
            old.emit(TransformImageResult(green, true))
            trace.append(subject.snapshot())
            XCTAssertTrue(subject.image === red)
            next.emit(TransformImageResult(blue, true))
            trace.append(subject.snapshot())
            let transform = ManualSource<ImageDataTransformation>()
            subject.ignoreFullyLoad = true
            subject.setSignal(transform.signal)
            XCTAssertEqual(next.disposals, 1)
            next.emit(TransformImageResult(green, true))
            subject.set(arguments: arguments())
            transform.emit(draw())
            trace.append(subject.snapshot())
            subject.dispose()
            XCTAssertEqual(transform.disposals, 1)
            transform.emit(draw(highQuality: false))
            trace.append(subject.snapshot())
            return trace
        }
    }

    func testFullyLoadedSkipMatchesAcrossHosts() throws {
        let red = try image(.red)
        try assertEquivalent { subject in
            subject.shared = [red]
            subject.setSignal(signal: .single(TransformImageResult(red, true)))
            var trace = [subject.snapshot()]
            var calls = 0
            subject.set(arguments: arguments())
            subject.setSignal(.single(draw(calls: { calls += 1 })))
            trace.append(subject.snapshot())
            XCTAssertEqual(calls, 0)
            subject.setSignal(.single(draw(calls: { calls += 1 })))
            trace.append(subject.snapshot())
            XCTAssertEqual(calls, 1)
            return trace
        }
    }

    func testAlreadyRenderedShortCircuitMatchesAcrossHosts() throws {
        var counts: [[Int]] = []
        try assertEquivalent { subject in
            var calls = 0
            var steps: [Int] = []
            let original = arguments()
            subject.set(arguments: original)
            subject.setSignal(.single(draw(calls: { calls += 1 })), alreadyRendered: original)
            steps.append(calls)
            var trace = [subject.snapshot()]
            subject.set(arguments: arguments(mode: .blurBackground))
            steps.append(calls)
            trace.append(subject.snapshot())
            subject.set(arguments: original)
            steps.append(calls)
            trace.append(subject.snapshot())
            counts.append(steps)
            return trace
        }
        XCTAssertEqual(counts, [[0, 1, 2], [0, 1, 2]])
    }

    func testBackgroundRenderingMatchesAcrossHosts() throws {
        var results: [[Int]] = []
        for subject in Subject.both() {
            let rendered = expectation(description: "rendered")
            rendered.expectedFulfillmentCount = 2
            var sizes: [Int] = []
            subject.setSignal(.single(draw()), synchronousLoad: false, cacheImage: { result in
                XCTAssertTrue(Thread.isMainThread)
                XCTAssertNil(result.sampleBuffer)
                sizes.append(result.image?.width ?? 0)
                rendered.fulfill()
            })
            subject.set(arguments: arguments())
            subject.set(arguments: arguments(insets: .init(top: 0, left: 3, bottom: 0, right: 0)))
            wait(for: [rendered], timeout: 5)
            results.append(sizes)
            subject.dispose()
        }
        XCTAssertEqual(results, [[20, 23], [20, 23]])
    }

    func testLayerHostRefusesProtectedResults() throws {
        let red = try image(.red), blue = try image(.blue)
        for clearInstantly in [true, false] {
            let layer = TransformImageLayer()
            var updates: [Any?] = []
            layer.imageUpdated = { updates.append($0) }
            layer.setSignal(signal: .single(TransformImageResult(blue, true, nil)), clearInstantly: clearInstantly)
            XCTAssertTrue(layer.contents as AnyObject? === blue)
            layer.setSignal(signal: .single(TransformImageResult(red, true, red.cmSampleBuffer)), clearInstantly: clearInstantly)
            XCTAssertFalse(layer.contents as AnyObject? === red)
            XCTAssertFalse(layer.image === red)
            XCTAssertFalse(layer.isFullyLoaded)
            XCTAssertFalse(updates.contains { ($0 as AnyObject?) === red })
            XCTAssertNil(layer.sublayers)
            if clearInstantly {
                XCTAssertNil(layer.contents)
                XCTAssertNil(layer.image)
            } else {
                XCTAssertTrue(layer.contents as AnyObject? === blue)
            }
        }
    }

    func testLayerHostDefaultsMatchTheBackingLayer() {
        let window = NSWindow(contentRect: NSMakeRect(0, 0, 100, 100), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let view = TransformImageView(frame: NSMakeRect(10, 10, 40, 30))
        window.contentView?.addSubview(view)
        let backing = view.layer!
        let layer = TransformImageLayer(frame: NSMakeRect(10, 10, 40, 30))
        XCTAssertEqual(layer.anchorPoint, backing.anchorPoint)
        XCTAssertEqual(layer.contentsGravity, backing.contentsGravity)
        XCTAssertEqual(layer.masksToBounds, backing.masksToBounds)
        XCTAssertEqual(layer.bounds, backing.bounds)
        XCTAssertEqual(layer.frame.size, backing.frame.size)
        XCTAssertEqual(layer.position, NSPoint(x: 10, y: 10))
        XCTAssertNil(layer.action(forKey: "contents") as? CABasicAnimation)
        view.removeFromSuperview()
    }

    func testScopedImageCacheIsNotedThroughTheVisibilityView() throws {
        for attached in [true, false] {
            let window = NSWindow(contentRect: NSMakeRect(0, 0, 400, 400), styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = NSView(frame: NSMakeRect(0, 0, 400, 400))
            let cache = ScopedImageCache(countLimit: 100, byteLimit: 100 * 1024 * 1024, idleTimeout: 300, closedScopeGrace: 0, sweepInterval: 3600)
            let image = testImage(CGSize(width: 8, height: 8))
            cache.setImage(image, sampleBuffer: nil, forKey: 1)
            weak var scrollView: NSScrollView?
            let layer = TransformImageLayer(frame: NSMakeRect(0, 0, 50, 50))
            autoreleasepool {
                let scroll = NSScrollView(frame: NSMakeRect(0, 0, 200, 200))
                let document = NSView(frame: NSMakeRect(0, 0, 200, 800))
                document.wantsLayer = true
                scroll.documentView = document
                window.contentView?.addSubview(scroll)
                document.layer?.addSublayer(layer)
                if attached { layer.visibilityView = document }
                layer.image = image
                scrollView = scroll
                scroll.removeFromSuperview()
            }
            waitUntilReleased { scrollView }
            if attached {
                XCTAssertNil(cache.image(forKey: 1))
            } else {
                XCTAssertNotNil(cache.image(forKey: 1))
            }
            layer.removeFromSuperlayer()
            window.contentView = nil
        }
    }

    func testHostDidMoveToWindowAttributesAnImageShownBeforeAttach() throws {
        let window = NSWindow(contentRect: NSMakeRect(0, 0, 400, 400), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSView(frame: NSMakeRect(0, 0, 400, 400))
        let cache = ScopedImageCache(countLimit: 100, byteLimit: 100 * 1024 * 1024, idleTimeout: 300, closedScopeGrace: 0, sweepInterval: 3600)
        let image = testImage(CGSize(width: 8, height: 8))
        cache.setImage(image, sampleBuffer: nil, forKey: 1)
        weak var scrollView: NSScrollView?
        let layer = TransformImageLayer(frame: NSMakeRect(0, 0, 50, 50))
        autoreleasepool {
            let scroll = NSScrollView(frame: NSMakeRect(0, 0, 200, 200))
            let document = NSView(frame: NSMakeRect(0, 0, 200, 800))
            scroll.documentView = document
            let row = NSView(frame: NSMakeRect(0, 0, 50, 50))
            layer.visibilityView = row
            layer.image = image
            window.contentView?.addSubview(scroll)
            document.addSubview(row)
            layer.hostDidMoveToWindow()
            scrollView = scroll
            scroll.removeFromSuperview()
        }
        waitUntilReleased { scrollView }
        XCTAssertNil(cache.image(forKey: 1))
        window.contentView = nil
    }

    private func waitUntilReleased(_ object: () -> AnyObject?) {
        let deadline = Date().addingTimeInterval(3)
        while object() != nil && Date() < deadline {
            autoreleasepool {
                CATransaction.flush()
                RunLoop.current.run(until: Date().addingTimeInterval(0.01))
            }
        }
        XCTAssertNil(object())
    }
}
