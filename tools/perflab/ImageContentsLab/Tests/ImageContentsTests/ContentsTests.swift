import Cocoa
import XCTest
import SwiftSignalKit
@testable import TGUIKit

private final class CountingLayer: CALayer {
    struct Animation: Equatable {
        let key: String?
        let path: String?
        let duration: Double
    }
    var writes = 0
    var reads = 0
    var added: [Animation] = []
    override var contents: Any? {
        get { reads += 1; return super.contents }
        set { writes += 1; super.contents = newValue }
    }
    override func add(_ animation: CAAnimation, forKey key: String?) {
        added.append(Animation(key: key, path: (animation as? CAPropertyAnimation)?.keyPath, duration: animation.duration))
        super.add(animation, forKey: key)
    }
}

final class ContentsTests: XCTestCase {
    private var windows: [NSWindow] = []
    override func setUp() { TGUIKitTestBootstrap.install() }
    override func tearDown() {
        windows.forEach { $0.contentView = nil; $0.close() }
        windows.removeAll()
        CATransaction.flush()
    }
    private struct Subject {
        let object: AnyObject
        let view: NSView?
        let layer: CALayer
        let set: (CGImage?) -> Void
        let get: () -> CGImage?
        let sizeToFit: () -> Void
    }
    private func subject(_ kind: Int, reference: Bool = false, counting: Bool = true) -> Subject {
        if kind == 0 {
            if reference {
                let view = ReferenceImageView(frame: NSRect(x: 7, y: 9, width: 20, height: 20))
                if counting { view.layer = CountingLayer() }
                return Subject(object: view, view: view, layer: view.layer!, set: { view.image = $0 }, get: { view.image }, sizeToFit: { view.sizeToFit() })
            }
            let view = ImageView(frame: NSRect(x: 7, y: 9, width: 20, height: 20))
            if counting { view.layer = CountingLayer() }
            return Subject(object: view, view: view, layer: view.layer!, set: { view.image = $0 }, get: { view.image }, sizeToFit: { view.sizeToFit() })
        }
        if kind == 1 {
            if reference {
                let view = ReferenceTransformImageView()
                view.frame = NSRect(x: 7, y: 9, width: 20, height: 20)
                if counting { view.layer = CountingLayer() }
                return Subject(object: view, view: view, layer: view.layer!, set: { view.image = $0 }, get: { view.image }, sizeToFit: {})
            }
            let view = TransformImageView()
            view.frame = NSRect(x: 7, y: 9, width: 20, height: 20)
            if counting { view.layer = CountingLayer() }
            return Subject(object: view, view: view, layer: view.layer!, set: { view.image = $0 }, get: { view.image }, sizeToFit: {})
        }
        if reference {
            let layer = ReferenceChatRightIconLayer(frame: NSRect(x: 7, y: 9, width: 20, height: 20))
            return Subject(object: layer, view: nil, layer: layer, set: { layer.image = $0 }, get: { layer.image }, sizeToFit: { layer.sizeToFit() })
        }
        let layer = CandidateChatRightIconLayer(frame: NSRect(x: 7, y: 9, width: 20, height: 20))
        return Subject(object: layer, view: nil, layer: layer, set: { layer.image = $0 }, get: { layer.image }, sizeToFit: { layer.sizeToFit() })
    }
    private func image(_ color: NSColor, size: Int = 16) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(color.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: size, height: size))
        context.setFillColor(NSColor.green.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: size / 2, height: size / 2))
        return try XCTUnwrap(context.makeImage())
    }
    private func pixels(_ layer: CALayer, scale: Int) throws -> [UInt8] {
        let size = 24 * scale
        let context = try XCTUnwrap(CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
        layer.render(in: context)
        return Array(UnsafeRawBufferPointer(start: context.data, count: size * size * 4))
    }
    private func host() -> NSView {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 400), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 400))
        view.wantsLayer = true
        window.contentView = view
        windows.append(window)
        return view
    }

    func testRepeatedImmutableImagesKeepDisplayedContents() throws {
        let image = try image(.red)
        for kind in 0...2 {
            let item = subject(kind)
            item.set(image)
            for _ in 0..<100 { item.set(image) }
            XCTAssertTrue(item.get() === image)
            XCTAssertTrue(item.layer.contents as AnyObject? === image)
        }
    }

    func testNonanimatedImagesAvoidContentsReadsButStillWriteEveryImage() throws {
        let old = ReferenceImageView(frame: .zero), new = ImageView(frame: .zero)
        let oldLayer = CountingLayer(), newLayer = CountingLayer()
        old.layer = oldLayer; new.layer = newLayer
        let first = try image(.red), second = try image(.blue)
        oldLayer.reads = 0; oldLayer.writes = 0
        newLayer.reads = 0; newLayer.writes = 0
        for index in 0..<100 {
            let value = index % 2 == 0 ? first : second
            old.image = value; new.image = value
        }
        XCTAssertEqual(oldLayer.reads, 100)
        XCTAssertEqual(newLayer.reads, 0)
        XCTAssertEqual(oldLayer.writes, 100)
        XCTAssertEqual(newLayer.writes, 100)
        XCTAssertTrue(newLayer.contents as AnyObject? === second)
    }

    func testAnimationPolicyChangesPreserveContentsAndExplicitAnimations() throws {
        let old = ReferenceImageView(frame: .zero), new = ImageView(frame: .zero)
        let oldLayer = CountingLayer(), newLayer = CountingLayer()
        old.layer = oldLayer; new.layer = newLayer
        let first = try image(.red), second = try image(.blue)
        for animates in [false, true, false, true] {
            old.animates = animates; new.animates = animates
            for value in [nil, first, first, second, nil, nil] {
                old.image = value; new.image = value
                XCTAssertTrue(oldLayer.contents as AnyObject? === newLayer.contents as AnyObject?)
                XCTAssertEqual(oldLayer.added, newLayer.added)
            }
        }
        XCTAssertEqual(newLayer.added.count, 12)
    }

    func testRepeatedNilAvoidsWritesButStillClearsForeignContents() throws {
        let image = try image(.red)
        for kind in 0...2 {
            let item = subject(kind)
            let counted = item.layer as? CountingLayer
            let initial = counted?.writes
            for _ in 0..<100 { item.set(nil) }
            if let initial { XCTAssertEqual(counted?.writes, initial) }
            item.layer.contents = image
            item.set(nil)
            XCTAssertNil(item.layer.contents)
            XCTAssertNil(item.get())
        }
    }

    func testSameImageRepairsExternallyChangedOrClearedLayer() throws {
        let first = try image(.red), second = try image(.blue)
        let native = NSImage(cgImage: second, size: NSSize(width: 16, height: 16))
        for kind in 0...2 {
            let item = subject(kind)
            item.set(first)
            for other: Any? in [second, native, nil] {
                item.layer.contents = other
                item.set(first)
                XCTAssertTrue(item.layer.contents as AnyObject? === first)
                XCTAssertTrue(item.get() === first)
            }
        }
    }

    func testImageAndNSImagePropertiesCanRestoreTheirOwnContent() throws {
        let first = try image(.red), second = try image(.blue)
        let native = NSImage(cgImage: second, size: NSSize(width: 16, height: 16))
        let view = ImageView(frame: .zero), counted = CountingLayer()
        view.layer = counted
        view.image = first
        view.nsImage = native
        view.image = first
        XCTAssertTrue(counted.contents as AnyObject? === first)
        view.nsImage = native
        XCTAssertTrue(counted.contents as AnyObject? === native)
        view.image = nil
        XCTAssertNil(counted.contents)
        view.nsImage = native
        XCTAssertTrue(counted.contents as AnyObject? === native)
    }

    func testMutableNSImageAssignmentsContinueWritingContents() throws {
        let native = NSImage(cgImage: try image(.red), size: NSSize(width: 16, height: 16))
        let view = ImageView(frame: .zero), counted = CountingLayer()
        view.layer = counted
        let initial = counted.writes
        for index in 0..<10 {
            native.size = NSSize(width: 16 + index, height: 16 + index)
            view.nsImage = native
        }
        XCTAssertEqual(counted.writes, initial + 10)
        XCTAssertTrue(counted.contents as AnyObject? === native)
    }

    func testExplicitImageAnimationsRemainIdenticalForRepeatedValues() throws {
        let old = ReferenceImageView(frame: .zero), new = ImageView(frame: .zero)
        let oldLayer = CountingLayer(), newLayer = CountingLayer()
        old.layer = oldLayer; new.layer = newLayer
        old.animates = true; new.animates = true
        let image = try image(.red)
        for value in [nil, image, image, nil, nil] {
            old.image = value; new.image = value
        }
        XCTAssertEqual(oldLayer.writes, newLayer.writes)
        XCTAssertEqual(oldLayer.added, newLayer.added)
        XCTAssertEqual(newLayer.added.count, 5)
    }

    func testTransformCallbacksAndReentrantReplacementKeepLatestImage() throws {
        let view = TransformImageView(), first = try image(.red), second = try image(.blue)
        var calls = 0
        view.imageUpdated = { [weak view] value in
            calls += 1
            if calls == 1 {
                view?.image = first
                view?.image = second
            }
        }
        view.image = first
        XCTAssertEqual(calls, 2)
        XCTAssertTrue(view.image === second)
        XCTAssertTrue(view.layer?.contents as AnyObject? === second)
        view.imageUpdated = nil
    }

    func testCaptureProtectionKeepsPlainLayerEmptyAndRestoresImage() throws {
        let view = TransformImageView(), image = try image(.red)
        view.image = image
        view.preventsCapture = true
        for _ in 0..<20 { view.image = image }
        XCTAssertNil(view.layer?.contents)
        XCTAssertTrue(view.image === image)
        XCTAssertTrue(view.layer?.sublayers?.contains { $0 is CaptureProtectedContentLayer } == true)
        view.preventsCapture = false
        XCTAssertTrue(view.layer?.contents as AnyObject? === image)
        view.preventsCapture = true
        view.image = nil
        view.preventsCapture = false
        XCTAssertNil(view.image); XCTAssertNil(view.layer?.contents)
    }

    func testRepeatedSignalsKeepExplicitAnimationsAndCallbackCounts() throws {
        let old = ReferenceTransformImageView(), new = TransformImageView()
        let oldLayer = CountingLayer(), newLayer = CountingLayer()
        old.layer = oldLayer; new.layer = newLayer
        var oldCalls = 0, newCalls = 0
        old.imageUpdated = { _ in oldCalls += 1 }; new.imageUpdated = { _ in newCalls += 1 }
        let image = try image(.red)
        for _ in 0..<3 {
            old.setSignal(signal: .single(TransformImageResult(image, true)), animate: true)
            new.setSignal(signal: .single(TransformImageResult(image, true)), animate: true)
        }
        XCTAssertEqual(oldLayer.added, newLayer.added)
        XCTAssertEqual(newLayer.added.count, 3)
        XCTAssertEqual(oldCalls, newCalls); XCTAssertEqual(newCalls, 1)
        XCTAssertTrue(new.isFullyLoaded)
    }

    func testDistinctImagesWithIdenticalPixelsStillAssignAndNotify() throws {
        let first = try image(.red), second = try image(.red)
        XCTAssertFalse(first === second)
        let view = TransformImageView(), counted = CountingLayer()
        view.layer = counted
        var calls = 0
        view.imageUpdated = { _ in calls += 1 }
        let initial = counted.writes
        view.image = first; view.image = second
        XCTAssertEqual(calls, 2)
        XCTAssertEqual(counted.writes, initial + 2)
        XCTAssertTrue(counted.contents as AnyObject? === second)
    }

    func testRasterAndSizingMatchReferenceAcrossRepeatedAssignments() throws {
        let first = try image(.red), second = try image(.blue, size: 24)
        var pairs = 0
        for kind in 0...2 {
            for scale in [1, 2, 3] {
                let old = subject(kind, reference: true, counting: false), new = subject(kind, counting: false)
                old.layer.contentsScale = CGFloat(scale); new.layer.contentsScale = CGFloat(scale)
                for image in [first, first, second, second] {
                    old.set(image); new.set(image)
                    old.sizeToFit(); new.sizeToFit()
                    XCTAssertEqual(old.layer.bounds, new.layer.bounds)
                    XCTAssertEqual(old.layer.frame, new.layer.frame)
                    XCTAssertEqual(old.view?.frame, new.view?.frame)
                    let oldPixels = try pixels(old.layer, scale: scale), newPixels = try pixels(new.layer, scale: scale)
                    XCTAssertTrue(newPixels.contains { $0 != 0 })
                    XCTAssertEqual(oldPixels, newPixels)
                    pairs += 1
                }
            }
        }
        XCTAssertEqual(pairs, 36)
    }

    func testNativeAssignmentBenchmark() throws {
        guard ProcessInfo.processInfo.environment["IMAGE_CONTENTS_BENCHMARK"] != nil else { throw XCTSkip("Opt-in image assignment benchmark") }
        let first = try image(.red), second = try image(.blue)
        var report: [String: Any] = [:]
        for kind in 0...2 {
            let oldHost = host(), newHost = host()
            let old = (0..<40).map { _ in subject(kind, reference: true, counting: false) }
            let new = (0..<40).map { _ in subject(kind, counting: false) }
            for (host, items) in [(oldHost, old), (newHost, new)] {
                for item in items {
                    if let view = item.view { host.addSubview(view) }
                    else { host.layer?.addSublayer(item.layer) }
                }
            }
            for scenario in ["repeated", "alternating", "empty"] {
                func measure(_ items: [Subject]) -> Double {
                    items.forEach { $0.set(scenario == "empty" ? nil : first) }
                    CATransaction.flush()
                    let start = CFAbsoluteTimeGetCurrent()
                    for index in 0..<500 {
                        let value = scenario == "empty" ? nil : (scenario == "alternating" && index % 2 == 0 ? second : first)
                        for item in items { item.set(value) }
                    }
                    CATransaction.flush()
                    let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000000 / Double(500 * items.count)
                    for item in items {
                        if scenario == "empty" { XCTAssertNil(item.layer.contents) }
                        else { XCTAssertTrue(item.layer.contents as AnyObject? === first) }
                    }
                    return elapsed
                }
                _ = measure(old); _ = measure(new)
                var baseline: [Double] = [], candidate: [Double] = []
                let reverse = ProcessInfo.processInfo.environment["IMAGE_CONTENTS_REVERSE"] != nil
                for batch in 0..<9 {
                    if batch % 2 == (reverse ? 1 : 0) { baseline.append(measure(old)); candidate.append(measure(new)) }
                    else { candidate.append(measure(new)); baseline.append(measure(old)) }
                }
                let name = "\(kind)-\(scenario)"
                report[name] = ["baseline_us": baseline, "candidate_us": candidate, "baseline_median_us": baseline.sorted()[4], "candidate_median_us": candidate.sorted()[4]]
                print("IMAGE_CONTENTS \(name): \(baseline.sorted()[4]) -> \(candidate.sorted()[4]) us/assignment")
            }
        }
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: "/tmp/image-contents-benchmark.json"))
    }
}
