import Cocoa
import XCTest
import class TGUIKit.ShimmerLayer
import class TGUIKit.ShimmerView
import class TGUIKit.StickerShimmerEffectView
import class TGUIKit.SilhouetteShimmerLayer
import struct TGUIKit.System
import enum TGUIKit.ShimmerRasterProbe
import class TGUIKitBaseline.ShimmerLayer
import class TGUIKitBaseline.ShimmerView
import class TGUIKitBaseline.StickerShimmerEffectView
import class TGUIKitBaseline.SilhouetteShimmerLayer
import struct TGUIKitBaseline.System
import enum TGUIKitBaseline.ShimmerRasterProbe

final class LockedCounts {
    private let lock = NSLock()
    private var values: [String: Int] = [:]
    func add(_ size: CGSize) { lock.lock(); values[NSStringFromSize(size), default: 0] += 1; lock.unlock() }
    func get(_ size: CGSize) -> Int { lock.lock(); defer { lock.unlock() }; return values[NSStringFromSize(size), default: 0] }
}

enum ShimmerKind: CaseIterable { case layer, view, sticker, silhouette }

struct ShimmerInput {
    var background: NSColor? = nil
    var foreground = NSColor(calibratedRed: 0.4, green: 0.5, blue: 0.6, alpha: 0.2)
    var shimmering = NSColor(calibratedRed: 0.6, green: 0.7, blue: 0.8, alpha: 0.35)
    var data: Data? = nil
    var size = CGSize(width: 64, height: 48)
    var imageSize = CGSize(width: 64, height: 64)
    var radius: CGFloat? = nil
}

struct ShimmerHarness {
    let object: AnyObject
    let update: (ShimmerInput) -> Void
    let image: () -> CGImage?
    let imageLayer: () -> CALayer?
    let maskFrame: () -> CGRect?
}

func shimmer(_ kind: ShimmerKind, baseline: Bool) -> ShimmerHarness {
    if baseline {
        switch kind {
        case .layer:
            let v = TGUIKitBaseline.ShimmerLayer()
            return ShimmerHarness(object: v, update: { v.update(backgroundColor: $0.background, foregroundColor: $0.foreground, shimmeringColor: $0.shimmering, data: $0.data, size: $0.size, imageSize: $0.imageSize, cornerRadius: $0.radius) }, image: { v.imageForLab }, imageLayer: { v.imageLayerForLab }, maskFrame: { v.maskFrameForLab })
        case .view:
            let v = TGUIKitBaseline.ShimmerView()
            return ShimmerHarness(object: v, update: { v.update(backgroundColor: $0.background, foregroundColor: $0.foreground, shimmeringColor: $0.shimmering, data: $0.data, size: $0.size, imageSize: $0.imageSize, cornerRadius: $0.radius) }, image: { v.imageForLab }, imageLayer: { v.imageLayerForLab }, maskFrame: { v.maskFrameForLab })
        case .sticker:
            let v = TGUIKitBaseline.StickerShimmerEffectView()
            return ShimmerHarness(object: v, update: { v.update(backgroundColor: $0.background, foregroundColor: $0.foreground, shimmeringColor: $0.shimmering, data: $0.data, size: $0.size) }, image: { v.imageForLab }, imageLayer: { v.imageLayerForLab }, maskFrame: { v.maskFrameForLab })
        case .silhouette:
            let v = TGUIKitBaseline.SilhouetteShimmerLayer()
            return ShimmerHarness(object: v, update: { v.update(foregroundColor: $0.foreground, shimmeringColor: $0.shimmering, data: $0.data, size: $0.size, imageSize: $0.imageSize) }, image: { v.imageForLab }, imageLayer: { v.imageLayerForLab }, maskFrame: { nil })
        }
    } else {
        switch kind {
        case .layer:
            let v = TGUIKit.ShimmerLayer()
            return ShimmerHarness(object: v, update: { v.update(backgroundColor: $0.background, foregroundColor: $0.foreground, shimmeringColor: $0.shimmering, data: $0.data, size: $0.size, imageSize: $0.imageSize, cornerRadius: $0.radius) }, image: { v.imageForLab }, imageLayer: { v.imageLayerForLab }, maskFrame: { v.maskFrameForLab })
        case .view:
            let v = TGUIKit.ShimmerView()
            return ShimmerHarness(object: v, update: { v.update(backgroundColor: $0.background, foregroundColor: $0.foreground, shimmeringColor: $0.shimmering, data: $0.data, size: $0.size, imageSize: $0.imageSize, cornerRadius: $0.radius) }, image: { v.imageForLab }, imageLayer: { v.imageLayerForLab }, maskFrame: { v.maskFrameForLab })
        case .sticker:
            let v = TGUIKit.StickerShimmerEffectView()
            return ShimmerHarness(object: v, update: { v.update(backgroundColor: $0.background, foregroundColor: $0.foreground, shimmeringColor: $0.shimmering, data: $0.data, size: $0.size) }, image: { v.imageForLab }, imageLayer: { v.imageLayerForLab }, maskFrame: { v.maskFrameForLab })
        case .silhouette:
            let v = TGUIKit.SilhouetteShimmerLayer()
            return ShimmerHarness(object: v, update: { v.update(foregroundColor: $0.foreground, shimmeringColor: $0.shimmering, data: $0.data, size: $0.size, imageSize: $0.imageSize) }, image: { v.imageForLab }, imageLayer: { v.imageLayerForLab }, maskFrame: { nil })
        }
    }
}

func shimmerPixels(_ image: CGImage) -> [UInt8] {
    var result = [UInt8](repeating: 0, count: image.width * image.height * 4)
    result.withUnsafeMutableBytes { bytes in
        let c = CGContext(data: bytes.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        c.setBlendMode(.copy)
        c.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    }
    return result
}

final class ShimmerTests: XCTestCase {
    let rectangle = Data([0, 128, 203, 50, 128, 203, 50, 178, 203, 0, 178])
    let curve = Data([0, 128, 194, 50, 128, 178, 178, 128, 178])

    override func setUp() {
        MeasureBootstrap.install()
        TGUIKit.System.updateScaleFactor(1); TGUIKitBaseline.System.updateScaleFactor(1)
    }
    override func tearDown() {
        TGUIKit.ShimmerRasterProbe.configure(before: nil)
        TGUIKitBaseline.ShimmerRasterProbe.configure(before: nil)
    }
    func until(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) {
        let end = CACurrentMediaTime() + 5
        while !condition() && CACurrentMediaTime() < end { _ = RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.001)) }
        XCTAssertTrue(condition(), file: file, line: line)
    }
    func pump() {
        let end = CACurrentMediaTime() + 0.05
        while CACurrentMediaTime() < end { _ = RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.001)) }
    }

    func testFreshRasterPixelsMatchAcrossModesColorsDataSizesAndScales() throws {
        var pairs = 0
        for scale: CGFloat in [1, 2, 3] {
            TGUIKit.System.updateScaleFactor(scale); TGUIKitBaseline.System.updateScaleFactor(scale)
            for kind in ShimmerKind.allCases {
                let backgrounds: [NSColor?] = kind == .silhouette ? [nil] : [nil, .white, NSColor(calibratedRed: 0.2, green: 0.3, blue: 0.6, alpha: 0.5)]
                for background in backgrounds {
                    for data: Data? in [nil, rectangle, curve] {
                        for size in [CGSize(width: 64, height: 48), CGSize(width: 31.5, height: 27.5)] {
                            var input = ShimmerInput(); input.background = background; input.data = data; input.size = size
                            let a = shimmer(kind, baseline: true), b = shimmer(kind, baseline: false)
                            a.update(input); b.update(input)
                            until { a.image() != nil && b.image() != nil }
                            let old = try XCTUnwrap(a.image()), new = try XCTUnwrap(b.image())
                            XCTAssertEqual(old.width, new.width); XCTAssertEqual(old.height, new.height)
                            let pixels = shimmerPixels(old)
                            XCTAssertTrue(pixels.contains { $0 != 0 })
                            XCTAssertEqual(pixels, shimmerPixels(new), "\(kind) scale=\(scale) size=\(size)")
                            pairs += 1
                        }
                    }
                }
            }
        }
        XCTAssertEqual(pairs, 180)
    }

    func testTransparentRepeatedUpdatesRenderOnlyOnce() throws {
        for kind in [ShimmerKind.layer, .view, .sticker] {
            let oldCounts = LockedCounts(), newCounts = LockedCounts()
            TGUIKitBaseline.ShimmerRasterProbe.configure(before: { oldCounts.add($0) })
            TGUIKit.ShimmerRasterProbe.configure(before: { newCounts.add($0) })
            let a = shimmer(kind, baseline: true), b = shimmer(kind, baseline: false)
            var input = ShimmerInput(); input.data = rectangle
            for _ in 0..<30 { a.update(input); b.update(input) }
            until { oldCounts.get(input.size) == 30 && newCounts.get(input.size) == 1 && a.image() != nil && b.image() != nil }
            pump()
            XCTAssertEqual(newCounts.get(input.size), 1)
            XCTAssertEqual(shimmerPixels(try XCTUnwrap(a.image())), shimmerPixels(try XCTUnwrap(b.image())))
        }
    }

    func testResizedMasksMatchTheLatestBounds() {
        for kind in [ShimmerKind.layer, .view, .sticker] {
            let a = shimmer(kind, baseline: true), b = shimmer(kind, baseline: false)
            var input = ShimmerInput(); a.update(input); b.update(input)
            until { a.image() != nil && b.image() != nil }
            let oldSize = input.size
            input.size = CGSize(width: 92, height: 71)
            a.update(input); b.update(input)
            until { a.image()?.width == 92 && b.image()?.width == 92 }
            XCTAssertEqual(a.maskFrame()?.size, oldSize)
            XCTAssertEqual(b.maskFrame()?.size, input.size)
        }
    }

    func testImageDimensionsAndCornerRadiusInvalidateTheMask() throws {
        for kind in [ShimmerKind.layer, .view, .silhouette] {
            let a = shimmer(kind, baseline: true), b = shimmer(kind, baseline: false)
            var input = ShimmerInput(); input.data = rectangle; input.background = .white
            a.update(input); b.update(input)
            until { a.image() != nil && b.image() != nil }
            let old = try XCTUnwrap(a.image()), previous = try XCTUnwrap(b.image())
            input.imageSize = CGSize(width: 128, height: 128)
            a.update(input); b.update(input)
            until { b.image() !== previous }
            XCTAssertTrue(a.image() === old)
            XCTAssertNotEqual(shimmerPixels(old), shimmerPixels(try XCTUnwrap(b.image())))
            let fresh = shimmer(kind, baseline: true); fresh.update(input)
            until { fresh.image() != nil }
            XCTAssertEqual(shimmerPixels(try XCTUnwrap(fresh.image())), shimmerPixels(try XCTUnwrap(b.image())))
        }
        for kind in [ShimmerKind.layer, .view] {
            let a = shimmer(kind, baseline: true), b = shimmer(kind, baseline: false)
            var input = ShimmerInput(); input.background = .white; input.radius = 2
            a.update(input); b.update(input)
            until { a.image() != nil && b.image() != nil }
            let old = try XCTUnwrap(a.image()), previous = try XCTUnwrap(b.image())
            input.radius = 20; a.update(input); b.update(input)
            until { b.image() !== previous }
            XCTAssertTrue(a.image() === old)
            XCTAssertNotEqual(shimmerPixels(old), shimmerPixels(try XCTUnwrap(b.image())))
        }
    }

    func testScaleChangeUpdatesEveryRasterWithoutChangingLogicalGeometry() throws {
        for kind in ShimmerKind.allCases {
            TGUIKit.System.updateScaleFactor(1); TGUIKitBaseline.System.updateScaleFactor(1)
            let a = shimmer(kind, baseline: true), b = shimmer(kind, baseline: false)
            var input = ShimmerInput(); input.background = .white
            a.update(input); b.update(input)
            until { a.image() != nil && b.image() != nil }
            TGUIKit.System.updateScaleFactor(2); TGUIKitBaseline.System.updateScaleFactor(2)
            a.update(input); b.update(input)
            until { b.image()?.width == 128 }
            XCTAssertEqual(a.image()?.width, 64)
            XCTAssertEqual(b.image()?.height, 96)
        }
    }

    func testOutOfOrderResultsCannotReplaceTheLatestImageOrMask() throws {
        for kind in [ShimmerKind.layer, .view] {
            for oldBackground: NSColor? in [nil, .white] {
                for baseline in [true, false] {
                    let started = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0)
                    let done = LockedCounts()
                    let firstSize = CGSize(width: 64, height: 48)
                    let before: (CGSize) -> Void = { size in
                        if size == firstSize { started.signal(); _ = release.wait(timeout: .now() + 5) }
                    }
                    if baseline { TGUIKitBaseline.ShimmerRasterProbe.configure(before: before, after: { done.add($0) }) }
                    else { TGUIKit.ShimmerRasterProbe.configure(before: before, after: { done.add($0) }) }
                    let value = shimmer(kind, baseline: baseline)
                    var input = ShimmerInput(); input.background = oldBackground
                    value.update(input)
                    XCTAssertEqual(started.wait(timeout: .now() + 3), .success)
                    input.background = nil; input.size = CGSize(width: 90, height: 70)
                    value.update(input)
                    until { value.image()?.width == 90 }
                    release.signal()
                    until { done.get(firstSize) == 1 }
                    pump()
                    if baseline { until { value.image()?.width == 64 } }
                    else { XCTAssertEqual(value.image()?.width, 90) }
                    TGUIKit.ShimmerRasterProbe.configure(before: nil)
                    TGUIKitBaseline.ShimmerRasterProbe.configure(before: nil)
                }
            }
        }
    }

    func testSilhouetteOpacityAnimationChangesWithColors() throws {
        let old = TGUIKitBaseline.SilhouetteShimmerLayer(), new = TGUIKit.SilhouetteShimmerLayer()
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 200, height: 120), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let host = NSView(frame: CGRect(x: 0, y: 0, width: 200, height: 120))
        host.wantsLayer = true
        window.contentView = host
        host.layer!.addSublayer(old); host.layer!.addSublayer(new)
        defer { window.close() }
        var input = ShimmerInput()
        old.update(foregroundColor: input.foreground, shimmeringColor: input.shimmering, data: nil, size: input.size, imageSize: input.imageSize)
        new.update(foregroundColor: input.foreground, shimmeringColor: input.shimmering, data: nil, size: input.size, imageSize: input.imageSize)
        until { old.imageForLab != nil && new.imageForLab != nil }
        let previous = try XCTUnwrap(old.animationForLab?.values as? [NSNumber])
        input.foreground = input.foreground.withAlphaComponent(0.6)
        input.shimmering = input.shimmering.withAlphaComponent(0.8)
        old.update(foregroundColor: input.foreground, shimmeringColor: input.shimmering, data: nil, size: input.size, imageSize: input.imageSize)
        new.update(foregroundColor: input.foreground, shimmeringColor: input.shimmering, data: nil, size: input.size, imageSize: input.imageSize)
        XCTAssertEqual(old.animationForLab?.values as? [NSNumber], previous)
        let values = try XCTUnwrap(new.animationForLab?.values as? [NSNumber])
        XCTAssertEqual(values[0].floatValue, 0.6, accuracy: 0.00001)
        XCTAssertEqual(values[2].floatValue, 0.92, accuracy: 0.00001)
        pump()
    }

    func testResolvedBackgroundColorInvalidatesSynchronousMask() throws {
        if #available(macOS 11, *) {
            let color = NSColor(name: nil, dynamicProvider: { appearance in
                appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .black : .white
            })
            let old = shimmer(.sticker, baseline: true), new = shimmer(.sticker, baseline: false)
            var input = ShimmerInput(); input.background = color
            NSAppearance(named: .aqua)!.performAsCurrentDrawingAppearance {
                old.update(input); new.update(input)
            }
            let before = shimmerPixels(try XCTUnwrap(old.image()))
            NSAppearance(named: .darkAqua)!.performAsCurrentDrawingAppearance {
                old.update(input); new.update(input)
            }
            XCTAssertEqual(before, shimmerPixels(try XCTUnwrap(old.image())))
            XCTAssertNotEqual(before, shimmerPixels(try XCTUnwrap(new.image())))
            let fresh = shimmer(.sticker, baseline: true)
            NSAppearance(named: .darkAqua)!.performAsCurrentDrawingAppearance { fresh.update(input) }
            XCTAssertEqual(shimmerPixels(try XCTUnwrap(fresh.image())), shimmerPixels(try XCTUnwrap(new.image())))
        }
    }

    func testNamedColorChangesWithoutAppearanceChange() throws {
        if #available(macOS 11, *) {
            var dark = false
            let color = NSColor(name: nil, dynamicProvider: { _ in dark ? .black : .white })
            let old = shimmer(.sticker, baseline: true), new = shimmer(.sticker, baseline: false)
            var input = ShimmerInput(); input.background = color
            old.update(input); new.update(input)
            let before = shimmerPixels(try XCTUnwrap(new.image()))
            dark = true
            old.update(input); new.update(input)
            XCTAssertEqual(before, shimmerPixels(try XCTUnwrap(old.image())))
            XCTAssertNotEqual(before, shimmerPixels(try XCTUnwrap(new.image())))
            let fresh = shimmer(.sticker, baseline: true); fresh.update(input)
            XCTAssertEqual(shimmerPixels(try XCTUnwrap(fresh.image())), shimmerPixels(try XCTUnwrap(new.image())))
        }
    }

    func testPendingRenderingDoesNotRetainItsOwner() {
        for kind in [ShimmerKind.layer, .view, .silhouette] {
            let started = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0)
            let done = LockedCounts(), size = CGSize(width: 64, height: 48)
            TGUIKit.ShimmerRasterProbe.configure(before: { current in
                if current == size { started.signal(); _ = release.wait(timeout: .now() + 5) }
            }, after: { done.add($0) })
            weak var owner: AnyObject?
            autoreleasepool {
                var value: ShimmerHarness? = shimmer(kind, baseline: false)
                owner = value?.object
                value?.update(ShimmerInput())
                XCTAssertEqual(started.wait(timeout: .now() + 3), .success)
                value = nil
                CATransaction.flush()
            }
            XCTAssertNil(owner)
            release.signal()
            until { done.get(size) == 1 }
            pump()
            TGUIKit.ShimmerRasterProbe.configure(before: nil)
        }
    }

    func testCandidateRapidRequestsPublishTheLatestMask() throws {
        for kind in [ShimmerKind.layer, .view, .silhouette] {
            let value = shimmer(kind, baseline: false)
            for cycle in 0..<10 {
                var input = ShimmerInput()
                for index in 0..<100 {
                    input.size = CGSize(width: 30 + index % 20, height: 20 + index % 15)
                    input.data = index % 3 == 0 ? nil : rectangle
                    input.background = index % 2 == 0 ? nil : .white
                    value.update(input)
                }
                input.size = CGSize(width: 100 + cycle, height: 60 + cycle)
                input.background = nil
                input.data = curve
                value.update(input)
                until { value.image()?.width == 100 + cycle }
                let expected = shimmer(kind, baseline: false)
                expected.update(input)
                until { expected.image() != nil }
                pump()
                XCTAssertEqual(shimmerPixels(try XCTUnwrap(value.image())), shimmerPixels(try XCTUnwrap(expected.image())))
            }
        }
    }

    func testChangingAndClearingInputsMatchesFreshRendering() throws {
        for kind in ShimmerKind.allCases {
            let reused = shimmer(kind, baseline: false)
            for i in 0..<12 {
                var input = ShimmerInput()
                input.background = i % 2 == 0 ? nil : .white
                input.data = i % 3 == 0 ? nil : i % 3 == 1 ? rectangle : curve
                input.size = CGSize(width: 40 + i * 2, height: 30 + i)
                input.imageSize = CGSize(width: 64 + i * 4, height: 64 + i * 4)
                input.radius = CGFloat(i)
                let fresh = shimmer(kind, baseline: true)
                let previous = reused.image()
                reused.update(input); fresh.update(input)
                until { reused.image() != nil && reused.image() !== previous && fresh.image() != nil }
                XCTAssertEqual(shimmerPixels(try XCTUnwrap(reused.image())), shimmerPixels(try XCTUnwrap(fresh.image())))
                if kind != .silhouette { XCTAssertEqual(reused.maskFrame() != nil, input.background == nil) }
            }
        }
    }
}
