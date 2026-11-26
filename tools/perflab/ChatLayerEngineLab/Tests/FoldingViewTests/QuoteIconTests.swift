import Cocoa
import XCTest
import TGUIKit
@testable import FoldingViewHarness

final class QuoteIconTests: XCTestCase {
    override func setUp() { TGUIKitTestBootstrap.install() }

    func bitmap(_ variant: Int = 0, size: Int = 16) -> CGImage {
        let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(gray: 1, alpha: 0.6))
        context.fill(CGRect(x: 1, y: 2, width: size - 3, height: size - 4))
        context.setBlendMode(.copy)
        context.setFillColor(CGColor(gray: 0.3, alpha: 0.2))
        context.fillEllipse(in: CGRect(x: 2 + variant % 5, y: 1, width: size / 2, height: size / 2))
        return context.makeImage()!
    }

    func source(_ bitmap: CGImage, size: NSSize = NSSize(width: 16, height: 16)) -> NSImage { NSImage(cgImage: bitmap, size: size) }

    func quotes(_ count: Int = 1, code: Bool = true, color: NSColor = .blue) -> [TextViewBlockQuote] {
        let content = QuoteMaskTests().content(count, code: code)
        return content.1.enumerated().flatMap { index, text -> [TextViewBlockQuote] in
            text.measure(width: 240)
            for block in text.blockQuotes { block.frame = NSRect(x: 0, y: index * 110, width: 240, height: 100); block.colors = .init(main: color) }
            return text.blockQuotes
        }
    }

    func render(_ layer: CALayer, count: Int = 1, scale: CGFloat = 2) -> PixelBuffer {
        let context = CGContext(data: nil, width: Int(260 * scale), height: Int(CGFloat(count * 110) * scale), bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.scaleBy(x: scale, y: scale)
        layer.draw(in: context)
        return PixelBuffer(context.makeImage()!)
    }

    func testExactTintPixelsAndReuseAcrossSizesColorsAndScale() {
        let cache = FoldingTextQuoteLayer.CopyIconCache()
        let bitmap = bitmap()
        for scale: CGFloat in [1, 2, 3] {
            for size in [NSSize(width: 16, height: 16), NSSize(width: 15.5, height: 17.25)] {
                for color in [NSColor.red, NSColor.blue.withAlphaComponent(0.35), NSColor(calibratedRed: 0.13, green: 0.71, blue: 0.27, alpha: 0.83)] {
                    let image = source(bitmap, size: size)
                    let expected = image.precomposed(color, flipVertical: true, scale: scale)
                    let actual = cache.image(image, color: color, scale: scale)
                    XCTAssertEqual(PixelBuffer(actual), PixelBuffer(expected))
                    XCTAssertTrue(actual === cache.image(source(bitmap, size: size), color: color, scale: scale))
                }
            }
        }
    }

    func testDifferentSourceAndSizeCannotReuseAnOldTint() {
        let cache = FoldingTextQuoteLayer.CopyIconCache(), a = source(bitmap()), b = source(bitmap(3))
        let first = cache.image(a, color: .red, scale: 2), second = cache.image(b, color: .red, scale: 2)
        XCTAssertFalse(first === second)
        XCTAssertNotEqual(PixelBuffer(first), PixelBuffer(second))
        a.size = NSSize(width: 12, height: 18)
        let resized = cache.image(a, color: .red, scale: 2)
        XCTAssertFalse(first === resized)
        XCTAssertEqual(PixelBuffer(resized), PixelBuffer(a.precomposed(.red, flipVertical: true, scale: 2)))
    }

    func testEvictionOversizedBypassAndSourceLifetime() {
        let cache = FoldingTextQuoteLayer.CopyIconCache()
        let original = source(bitmap())
        let first = cache.image(original, color: .red, scale: 2)
        for i in 0..<100 {
            autoreleasepool {
                let image = source(bitmap(i))
                let actual = cache.image(image, color: .blue, scale: 2)
                XCTAssertEqual(PixelBuffer(actual).differingPixels(from: PixelBuffer(image.precomposed(.blue, flipVertical: true, scale: 2)), tolerance: 0), 0)
                XCTAssertLessThanOrEqual(cache.images.count, 16)
                XCTAssertEqual(cache.images.count, cache.order.count)
                XCTAssertLessThanOrEqual(cache.images.values.reduce(0) { $0 + $1.source.bytesPerRow * $1.source.height + $1.image.bytesPerRow * $1.image.height }, 256 * 1024)
            }
        }
        XCTAssertEqual(PixelBuffer(first), PixelBuffer(original.precomposed(.red, flipVertical: true, scale: 2)))
        let large = source(bitmap(size: 256), size: NSSize(width: 256, height: 256))
        let before = cache.images.count
        let a = cache.image(large, color: .blue, scale: 2), b = cache.image(large, color: .blue, scale: 2)
        XCTAssertFalse(a === b)
        XCTAssertEqual(cache.images.count, before)
    }

    func testDynamicColorsBypassReuseAcrossAppearances() {
        let old = NSAppearance.current
        defer { NSAppearance.current = old }
        let cache = FoldingTextQuoteLayer.CopyIconCache(), image = source(bitmap())
        let color = NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? NSColor.red : NSColor.blue
        }
        for appearance in [NSAppearance.Name.aqua, .darkAqua, .aqua] {
            NSAppearance.current = NSAppearance(named: appearance)
            let actual = cache.image(image, color: color, scale: 2)
            XCTAssertEqual(PixelBuffer(actual), PixelBuffer(image.precomposed(color, flipVertical: true, scale: 2)))
            XCTAssertFalse(actual === cache.image(image, color: color, scale: 2))
        }
        XCTAssertEqual(cache.images.count, 0)
    }

    func testCompleteQuotePainterMatchesWithChangingIconsAndColors() {
        let oldScale = System.backingScale, previous = TelegramThemeHooks.imageOverride
        defer { System.updateScaleFactor(oldScale); TelegramThemeHooks.imageOverride = previous }
        let current = FoldingTextQuoteLayer(), reference = ReferenceIconQuoteLayer()
        System.updateScaleFactor(3)
        current.blockQuotes = quotes(code: false)
        _ = render(current, scale: 3)
        for scale: CGFloat in [1, 2, 3] {
            System.updateScaleFactor(scale)
            for code in [false, true] {
                for variant in 0..<3 {
                    let icon = source(bitmap(variant))
                    TelegramThemeHooks.imageOverride = { name in name == .iconCopyCode ? icon : NSImage(named: "Icon_Quote")! }
                    let blocks = quotes(3, code: code, color: variant % 2 == 0 ? .red : .blue)
                    current.blockQuotes = blocks; reference.blockQuotes = blocks
                    XCTAssertEqual(render(current, count: 3, scale: scale).differingPixels(from: render(reference, count: 3, scale: scale), tolerance: 0), 0, "code=\(code) scale=\(scale) variant=\(variant)")
                }
            }
        }
    }

    func testDrawingSettingsInvalidateCachedImages() throws {
        let original = DeviceGraphicsContextSettings.shared
        let restore = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: original.bitsPerComponent, bytesPerRow: original.bytesPerRow(forWidth: 1), space: original.colorSpace, bitmapInfo: original.opaqueBitmapInfo.rawValue)!
        defer { DeviceGraphicsContextSettings.install(restore) }
        let cache = FoldingTextQuoteLayer.CopyIconCache()
        let source = source(bitmap())
        let first = try XCTUnwrap(cache.image(source, color: .red, scale: 2))
        let different = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 32, space: CGColorSpace(name: CGColorSpace.displayP3)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        DeviceGraphicsContextSettings.install(different)
        XCTAssertNotEqual(original, DeviceGraphicsContextSettings.shared)
        let second = try XCTUnwrap(cache.image(source, color: .red, scale: 2))
        XCTAssertFalse(first === second)
        XCTAssertEqual(cache.images.count, 1)
        XCTAssertEqual(PixelBuffer(second), PixelBuffer(source.precomposed(.red, flipVertical: true, scale: 2)))
        DeviceGraphicsContextSettings.install(restore)
        XCTAssertEqual(original, DeviceGraphicsContextSettings.shared)
        let third = try XCTUnwrap(cache.image(source, color: .red, scale: 2))
        XCTAssertFalse(second === third)
        XCTAssertEqual(PixelBuffer(first), PixelBuffer(third))
    }

    func testEqualComponentColorsShareWithoutMixingColorSpaces() {
        let cache = FoldingTextQuoteLayer.CopyIconCache(), image = source(bitmap())
        let a = NSColor(srgbRed: 0.23, green: 0.57, blue: 0.81, alpha: 0.63)
        let b = NSColor(srgbRed: 0.23, green: 0.57, blue: 0.81, alpha: 0.63)
        XCTAssertTrue(cache.image(image, color: a, scale: 2) === cache.image(image, color: b, scale: 2))
        for color in [a, NSColor(displayP3Red: 0.23, green: 0.57, blue: 0.81, alpha: 0.63), NSColor(deviceWhite: 0.4, alpha: 0.5), NSColor(calibratedWhite: 0.4, alpha: 0.5)] {
            XCTAssertEqual(PixelBuffer(cache.image(image, color: color, scale: 2)), PixelBuffer(image.precomposed(color, flipVertical: true, scale: 2)))
        }
    }

    func testActualCopyAssetMatchesOriginalTintAndPainter() {
        let oldScale = System.backingScale, previous = TelegramThemeHooks.imageOverride
        defer { System.updateScaleFactor(oldScale); TelegramThemeHooks.imageOverride = previous }
        let cache = FoldingTextQuoteLayer.CopyIconCache(), image = makeRealCopyIconFixture()
        TelegramThemeHooks.imageOverride = { name in name == .iconCopyCode ? image : NSImage(named: "Icon_Quote")! }
        let current = FoldingTextQuoteLayer(), reference = ReferenceIconQuoteLayer()
        for scale: CGFloat in [1, 2, 3] {
            System.updateScaleFactor(scale)
            for color in [NSColor.red, NSColor.blue.withAlphaComponent(0.5), NSColor(calibratedRed: 0.31, green: 0.55, blue: 0.72, alpha: 1)] {
                XCTAssertEqual(PixelBuffer(cache.image(image, color: color, scale: scale)), PixelBuffer(image.precomposed(color, flipVertical: true, scale: scale)))
                let blocks = quotes(3, color: color)
                current.blockQuotes = blocks; reference.blockQuotes = blocks
                XCTAssertEqual(render(current, count: 3, scale: scale).differingPixels(from: render(reference, count: 3, scale: scale), tolerance: 0), 0, "scale=\(scale)")
            }
        }
    }

    func testGeneratedAppLoaderMatchesOriginalTintAndPainter() throws {
        guard let path = ProcessInfo.processInfo.environment["CHAT_COPY_ICON_BUNDLE"], let bundle = Bundle(path: path) else { throw XCTSkip("Supply the asset-only probe bundle") }
        let oldScale = System.backingScale, previous = TelegramThemeHooks.imageOverride, oldAppearance = NSAppearance.current
        defer { System.updateScaleFactor(oldScale); TelegramThemeHooks.imageOverride = previous; NSAppearance.current = oldAppearance }
        let cache = FoldingTextQuoteLayer.CopyIconCache()
        let makeSource = { bundle.image(forResource: NSImage.Name("Icon_CopyCode"))! }
        TelegramThemeHooks.imageOverride = { name in name == .iconCopyCode ? makeSource() : NSImage(named: "Icon_Quote")! }
        let current = FoldingTextQuoteLayer(), reference = ReferenceIconQuoteLayer()
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            NSAppearance.current = NSAppearance(named: appearance)
            for scale: CGFloat in [1, 2, 3] {
                System.updateScaleFactor(scale)
                for color in [NSColor.red, NSColor.blue.withAlphaComponent(0.5), NSColor.labelColor] {
                    let expected = PixelBuffer(makeSource().precomposed(color, flipVertical: true, scale: scale))
                    for _ in 0..<3 {
                        XCTAssertEqual(PixelBuffer(cache.image(makeSource(), color: color, scale: scale)).differingPixels(from: expected, tolerance: 0), 0)
                    }
                    let blocks = quotes(3, color: color)
                    current.blockQuotes = blocks; reference.blockQuotes = blocks
                    XCTAssertEqual(render(current, count: 3, scale: scale).differingPixels(from: render(reference, count: 3, scale: scale), tolerance: 0), 0, "appearance=\(appearance) scale=\(scale)")
                }
            }
        }
    }

    func testConcurrentImmutableBitmapReuseAndEviction() {
        let cache = FoldingTextQuoteLayer.CopyIconCache()
        let bitmaps = (0..<23).map { bitmap($0) }
        let lock = NSLock()
        var failures = 0
        DispatchQueue.concurrentPerform(iterations: 600) { index in
            let image = source(bitmaps[index % bitmaps.count])
            let scale = CGFloat(1 + index % 3)
            let actual = cache.image(image, color: .red, scale: scale)
            let expected = image.precomposed(.red, flipVertical: true, scale: scale)
            if PixelBuffer(actual) != PixelBuffer(expected) { lock.lock(); failures += 1; lock.unlock() }
        }
        XCTAssertEqual(failures, 0)
        XCTAssertLessThanOrEqual(cache.images.count, 16)
    }
}
