import Cocoa
import CoreImage
import XCTest
import class TGUIKit.BlurEdgeView
import class TGUIKitBaseline.BlurEdgeView
import enum TGUIKit.BlurEdgeCacheInspection
import enum TGUIKit.ContainedViewLayoutTransition
import enum TGUIKitBaseline.ContainedViewLayoutTransition

final class BlurEdgeTests: XCTestCase {
    let context = CIContext(options: [.cacheIntermediates: false])
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

    override func setUp() { TGUIKitTestBootstrap.install() }

    func pixels(_ image: CIImage, rect: CGRect) -> [UInt8] {
        var data = [UInt8](repeating: 0, count: Int(rect.width * rect.height) * 4)
        data.withUnsafeMutableBytes { context.render(image, toBitmap: $0.baseAddress!, rowBytes: Int(rect.width) * 4, bounds: rect, format: .RGBA8, colorSpace: colorSpace) }
        return data
    }

    func pair(size: CGSize, padding: CGFloat = 0, top: Bool = false) -> (TGUIKitBaseline.BlurEdgeView, TGUIKit.BlurEdgeView) {
        let a = TGUIKitBaseline.BlurEdgeView(frame: CGRect(origin: .zero, size: size))
        let b = TGUIKit.BlurEdgeView(frame: a.frame)
        a.padding = padding; b.padding = padding
        a.update(edge: top ? .top : .bottom, edgeSize: 10, rect: a.frame, transition: .immediate)
        b.update(edge: top ? .top : .bottom, edgeSize: 10, rect: b.frame, transition: .immediate)
        return (a, b)
    }

    func filter(_ view: NSView) throws -> CIFilter { try XCTUnwrap(view.layer?.backgroundFilters?.first as? CIFilter) }
    func mask(_ view: NSView) throws -> CIImage { try XCTUnwrap(try filter(view).value(forKey: "inputMask") as? CIImage) }

    func testMaskPixelsMatchOriginalAcrossGeometryPaddingAndEdges() throws {
        var cases = 0
        for width: CGFloat in [1, 2, 17, 320, 640.25] {
            for height: CGFloat in [1, 2, 17.5, 40.25] {
                for padding: CGFloat in [-5, 0, 4.25] {
                    for top in [false, true] {
                        let size = CGSize(width: width, height: height)
                        let (a, b) = pair(size: size, padding: padding, top: top)
                        let x = try XCTUnwrap(a.maskForLab(size: size)), y = try XCTUnwrap(b.maskForLab(size: size))
                        XCTAssertEqual(x.extent, y.extent)
                        let baseline = pixels(x, rect: x.extent), candidate = pixels(y, rect: y.extent)
                        XCTAssertEqual(baseline, candidate)
                        XCTAssertTrue(candidate.contains { $0 != 0 })
                        XCTAssertTrue(b.maskForLab(size: size) === y)
                        cases += 1
                    }
                }
            }
        }
        XCTAssertEqual(cases, 120)
    }

    func testCompleteVariableBlurPixelsMatchAndActuallyBlur() throws {
        let pattern = try XCTUnwrap(CIFilter(name: "CICheckerboardGenerator"))
        pattern.setValue(7, forKey: "inputWidth")
        pattern.setValue(CIColor(red: 1, green: 0.1, blue: 0.2), forKey: "inputColor0")
        pattern.setValue(CIColor(red: 0.1, green: 0.5, blue: 1), forKey: "inputColor1")
        let input = try XCTUnwrap(pattern.outputImage)
        var cases = 0
        for width: CGFloat in [64, 320] {
            for padding: CGFloat in [-5, 0, 4.25] {
                for top in [false, true] {
                    let (a, b) = pair(size: CGSize(width: width, height: 40.25), padding: padding, top: top)
                    let rect = try mask(a).extent
                    let unblurred = pixels(input, rect: rect)
                    for radius in [0.0, 8.0, 20.0] {
                        a.blurRadius = radius; b.blurRadius = radius
                        a.layout(); b.layout()
                        let x = try filter(a), y = try filter(b)
                        x.setValue(input, forKey: kCIInputImageKey); y.setValue(input, forKey: kCIInputImageKey)
                        let baseline = pixels(try XCTUnwrap(x.outputImage), rect: rect)
                        let candidate = pixels(try XCTUnwrap(y.outputImage), rect: rect)
                        XCTAssertEqual(baseline, candidate)
                        if radius > 0 { XCTAssertNotEqual(candidate, unblurred) }
                        cases += 1
                    }
                }
            }
        }
        XCTAssertEqual(cases, 36)
    }

    func testUpdatesResetForeignFilterChangesAndPreserveTintAndGeometry() throws {
        let (a, b) = pair(size: CGSize(width: 240, height: 48))
        let original = try mask(b)
        for view: NSView in [a, b] {
            let f = try filter(view)
            f.setValue(999, forKey: kCIInputRadiusKey)
            f.setValue(CIImage(color: .black), forKey: "inputMask")
            f.setValue(CIImage(color: .red), forKey: kCIInputImageKey)
        }
        a.blurRadius = 11; b.blurRadius = 11
        a.bgColor = .systemBlue; b.bgColor = .systemBlue
        a.layout(); b.layout()
        XCTAssertEqual(try filter(b).value(forKey: kCIInputRadiusKey) as? Double, 11)
        XCTAssertNil(try filter(b).value(forKey: kCIInputImageKey))
        XCTAssertTrue(try mask(b) === original)
        XCTAssertEqual(pixels(try mask(a), rect: original.extent), pixels(try mask(b), rect: original.extent))
        let first = try XCTUnwrap(a.layer?.sublayers?.first as? CAGradientLayer)
        let second = try XCTUnwrap(b.layer?.sublayers?.first as? CAGradientLayer)
        XCTAssertEqual(first.frame, second.frame)
        XCTAssertEqual(first.colors as? [CGColor], second.colors as? [CGColor])
        let old = try filter(b)
        b.layer?.backgroundFilters = nil
        b.layout()
        XCTAssertFalse(try filter(b) === old)
        XCTAssertEqual(try mask(b).extent, original.extent)
    }

    func testCacheKeysFollowSizePaddingAndEdgeButNotTintOrRadius() throws {
        let (_, b) = pair(size: CGSize(width: 211.25, height: 37.75), padding: 2.5)
        let first = try mask(b)
        b.bgColor = .systemRed; b.blurRadius = 13; b.layout()
        XCTAssertTrue(try mask(b) === first)
        b.padding = 3.5; b.layout()
        let padded = try mask(b); XCTAssertFalse(padded === first)
        b.update(edge: .top, edgeSize: 10, rect: b.frame, transition: .immediate)
        let top = try mask(b); XCTAssertFalse(top === padded)
        b.frame.size.width += 0.25; b.layout()
        XCTAssertFalse(try mask(b) === top)
        b.frame.size.height += 2; b.layout()
        XCTAssertEqual(try mask(b).extent.height, round(b.bounds.height))
        b.frame = CGRect(x: 0, y: 0, width: 0, height: 0)
        let old = try mask(b); b.layout(); XCTAssertTrue(try mask(b) === old)
    }

    func testEqualLiveViewsShareSourceBitmapAndCacheIsBounded() throws {
        let size = CGSize(width: 420, height: 48)
        let pairs = (0..<16).map { _ in pair(size: size) }
        let originals = try pairs.map { try mask($0.0) }, candidates = try pairs.map { try mask($0.1) }
        XCTAssertEqual(Set(originals.map(ObjectIdentifier.init)).count, 16)
        XCTAssertEqual(Set(candidates.map(ObjectIdentifier.init)).count, 1)
        let source = try XCTUnwrap(candidates[0].cgImage)
        XCTAssertGreaterThan(source.bytesPerRow * source.height, 0)
        let b = pairs[0].1
        let images = try (0..<32).map { try XCTUnwrap(b.maskForLab(size: CGSize(width: 701 + $0, height: 19))) }
        XCTAssertLessThanOrEqual(TGUIKit.BlurEdgeCacheInspection.count, 16)
        XCTAssertFalse(b.maskForLab(size: CGSize(width: 701, height: 19)) === images[0])
        XCTAssertEqual(images[0].extent, CGRect(x: 0, y: 0, width: 701, height: 19))
    }

    func testWeakCacheDoesNotKeepUnusedMaskAlive() throws {
        weak var weakMask: CIImage?
        try autoreleasepool {
            var b: TGUIKit.BlurEdgeView? = TGUIKit.BlurEdgeView(frame: CGRect(x: 0, y: 0, width: 913, height: 31))
            weakMask = try mask(b!)
            XCTAssertNotNil(weakMask)
            b?.layer?.backgroundFilters = nil
            b = nil
        }
        CATransaction.flush()
        XCTAssertNil(weakMask)
    }

    func testConcurrentCacheMissesKeepKeysAndLiveImagesConsistent() throws {
        let lock = NSLock()
        var images = [CIImage]()
        DispatchQueue.concurrentPerform(iterations: 64) { _ in
            let image = TGUIKit.BlurEdgeCacheInspection.image(size: CGSize(width: 1087, height: 23), padding: 21, bottom: true) {
                CIImage(color: .white).cropped(to: CGRect(x: 0, y: 0, width: 1087, height: 23))
            }!
            lock.lock(); images.append(image); lock.unlock()
        }
        XCTAssertEqual(images.count, 64)
        XCTAssertEqual(Set(images.map(ObjectIdentifier.init)).count, 1)
        XCTAssertEqual(images[0].extent, CGRect(x: 0, y: 0, width: 1087, height: 23))
        XCTAssertLessThanOrEqual(TGUIKit.BlurEdgeCacheInspection.count, 16)
    }
    func testConcurrentEvictionKeepsMasksMatchedToKeys() throws {
        let lock = NSLock()
        var results = [(Int, CIImage)]()
        DispatchQueue.concurrentPerform(iterations: 128) { iteration in
            let index = iteration % 64
            let size = CGSize(width: 1200 + index, height: 17)
            let image = TGUIKit.BlurEdgeCacheInspection.image(size: size, padding: CGFloat(index), bottom: index % 2 == 0) {
                CIImage(color: .white).cropped(to: CGRect(origin: .zero, size: size))
            }!
            lock.lock(); results.append((index, image)); lock.unlock()
        }
        XCTAssertEqual(results.count, 128)
        for (index, image) in results { XCTAssertEqual(image.extent, CGRect(x: 0, y: 0, width: 1200 + index, height: 17)) }
        XCTAssertLessThanOrEqual(TGUIKit.BlurEdgeCacheInspection.count, 16)
    }

}
