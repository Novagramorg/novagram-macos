import Cocoa
import ImageIO
import XCTest
import TGUIKit

final class TintTests: XCTestCase {
    override func setUp() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        System.updateScaleFactor(2)
    }

    func bitmap(_ variant: Int = 0, width: Int = 32) -> CGImage {
        let context = CGContext(data: nil, width: width, height: width, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(gray: 0.5, alpha: 0.4))
        context.fill(CGRect(x: 1, y: 2, width: width - 3, height: width / 2))
        context.setFillColor(CGColor(gray: 0.9, alpha: 0.8))
        context.fillEllipse(in: CGRect(x: 2 + variant % 7, y: 3, width: width / 2, height: width / 2))
        return context.makeImage()!
    }

    func source(_ variant: Int = 0, size: NSSize = NSSize(width: 16, height: 16)) -> NSImage { NSImage(cgImage: bitmap(variant), size: size) }

    func pixels(_ image: CGImage) -> Data {
        let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return Data(bytes: context.data!, count: image.width * image.height * 4)
    }

    func equal(_ actual: CGImage, _ reference: CGImage, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.width, reference.width, file: file, line: line)
        XCTAssertEqual(actual.height, reference.height, file: file, line: line)
        XCTAssertTrue(pixels(actual) == pixels(reference), "Pixels differ", file: file, line: line)
        XCTAssertEqual(actual.bitsPerComponent, reference.bitsPerComponent, file: file, line: line)
        XCTAssertEqual(actual.bitmapInfo, reference.bitmapInfo, file: file, line: line)
        XCTAssertEqual(actual.bytesPerRow, reference.bytesPerRow, file: file, line: line)
        XCTAssertTrue(CFEqual(actual.colorSpace!, reference.colorSpace!), file: file, line: line)
        XCTAssertTrue((actual.dataProvider!.data! as Data) == (reference.dataProvider!.data! as Data), "Raw pixels differ", file: file, line: line)
    }

    func testExactPixelMatrixAndReuse() {
        let cache = TintCache()
        for size in [NSSize(width: 16, height: 16), NSSize(width: 15.5, height: 17.25), NSSize(width: 0.25, height: 0.5)] {
            let image = source(size: size)
            for scale: CGFloat in [0, 1, 1.5, 2, 3] {
                for horizontal in [false, true] {
                    for vertical in [false, true] {
                        for color in [NSColor.red, .blue.withAlphaComponent(0.35), NSColor(displayP3Red: 0.2, green: 0.7, blue: 0.3, alpha: 0.75)] {
                            let actual = cache.image(image, color: color, flipVertical: vertical, flipHorizontal: horizontal, scale: scale)
                            equal(actual, image.referencePrecomposed(color, flipVertical: vertical, flipHorizontal: horizontal, scale: scale))
                            XCTAssertTrue(actual === cache.image(image, color: color, flipVertical: vertical, flipHorizontal: horizontal, scale: scale))
                        }
                    }
                }
            }
        }
    }

    func testUntintedGradientZoomAndLargeImagesKeepOriginalBehavior() {
        let cache = TintCache()
        for size in [NSSize(width: 16, height: 16), NSSize(width: 65, height: 70)] {
            let image = source(size: size)
            for zoom: CGFloat in [0.5, 1, 1.75] {
                for scale: CGFloat in [1, 2, 3] {
                    for horizontal in [false, true] {
                        for (color, bottom) in [(nil, nil), (NSColor.red, NSColor.blue), (NSColor.green, nil)] as [(NSColor?, NSColor?)] {
                            equal(cache.image(image, color: color, bottomColor: bottom, flipVertical: true, flipHorizontal: horizontal, scale: scale, zoom: zoom), image.referencePrecomposed(color, bottomColor: bottom, flipVertical: true, flipHorizontal: horizontal, scale: scale, zoom: zoom))
                        }
                    }
                }
            }
        }
    }

    func testSourceAndLogicalSizeMutationsCannotReuseStalePixels() {
        let cache = TintCache(), image = source()
        let first = cache.image(image, color: .red)
        image.size = NSSize(width: 19.25, height: 12.5)
        let resized = cache.image(image, color: .red)
        XCTAssertFalse(first === resized)
        equal(resized, image.referencePrecomposed(.red))
        image.representations.forEach { image.removeRepresentation($0) }
        let rep = NSBitmapImageRep(cgImage: bitmap(6)); rep.size = image.size
        image.addRepresentation(rep)
        let replaced = cache.image(image, color: .red)
        XCTAssertFalse(resized === replaced)
        equal(replaced, image.referencePrecomposed(.red))
        image.isTemplate = true
        equal(cache.image(image, color: .red), image.referencePrecomposed(.red))
        System.updateScaleFactor(3)
        equal(cache.image(image, color: .red, scale: 0), image.referencePrecomposed(.red, scale: 0))
    }

    func testBitmapRepresentationPixelMutation() throws {
        let cache = TintCache()
        let rep = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 16, pixelsHigh: 16, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 64, bitsPerPixel: 32))
        memset(rep.bitmapData!, 0xff, rep.bytesPerRow * rep.pixelsHigh)
        let image = NSImage(size: NSSize(width: 16, height: 16))
        image.addRepresentation(rep)
        let first = cache.image(image, color: .red)
        _ = image.precomposed(.red)
        memset(rep.bitmapData!, 0, rep.bytesPerRow * 8)
        let expected = image.referencePrecomposed(.red)
        XCTAssertNotEqual(pixels(first), pixels(expected))
        equal(cache.image(image, color: .red), expected)
        equal(image.precomposed(.red), expected)
    }

    func testAnimatedBitmapFrameChanges() throws {
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, "com.compuserve.gif" as CFString, 2, nil))
        CGImageDestinationAddImage(destination, bitmap(0), nil)
        CGImageDestinationAddImage(destination, bitmap(6), nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let image = try XCTUnwrap(NSImage(data: data as Data))
        let representation = try XCTUnwrap(image.representations.first as? NSBitmapImageRep)
        representation.setProperty(.currentFrame, withValue: 0)
        let first = image.precomposed(.red)
        representation.setProperty(.currentFrame, withValue: 1)
        let expected = image.referencePrecomposed(.red)
        XCTAssertNotEqual(pixels(first), pixels(expected))
        equal(image.precomposed(.red), expected)
        representation.setProperty(.currentFrame, withValue: 0)
        equal(image.precomposed(.red), first)
    }

    func testDynamicAppearanceAndPatternColorsUseOriginalRenderer() {
        let old = NSAppearance.current
        defer { NSAppearance.current = old }
        let image = source(), cache = TintCache()
        let dynamic = NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .red : .blue }
        for appearance in [NSAppearance.Name.aqua, .darkAqua, .aqua] {
            NSAppearance.current = NSAppearance(named: appearance)
            for color in [dynamic, NSColor.labelColor, NSColor(patternImage: source(3))] {
                equal(cache.image(image, color: color), image.referencePrecomposed(color))
            }
        }
        XCTAssertTrue(cache.entries.isEmpty)
    }

    func testEvictionByteLimitAndOversizedBypass() {
        let cache = TintCache()
        let images = (0..<150).map { source($0, size: NSSize(width: 64, height: 64)) }
        for image in images {
            equal(cache.image(image, color: .red, scale: 2), image.referencePrecomposed(.red, scale: 2))
            XCTAssertLessThanOrEqual(cache.entries.count, 64)
            XCTAssertLessThanOrEqual(cache.retainedBytes, 1024 * 1024)
            XCTAssertEqual(cache.retainedBytes, cache.entries.values.reduce(0) { $0 + $1.cost })
            XCTAssertEqual(cache.count, cache.entries.count)
        }
        let before = cache.retainedBytes
        let a = cache.image(images[0], color: .blue, scale: 3), b = cache.image(images[0], color: .blue, scale: 3)
        XCTAssertFalse(a === b)
        XCTAssertEqual(cache.retainedBytes, before)
    }

    func testWeakSourceDoesNotRetainLargeCroppedBackingStorage() {
        final class ReleaseState { var released = false }
        let state = ReleaseState(), cache = TintCache()
        weak var weakSource: CGImage?
        var output: CGImage?
        autoreleasepool {
            let length = 2048 * 2048 * 4
            let bytes = malloc(length)!
            memset(bytes, 0xff, length)
            let provider = CGDataProvider(dataInfo: Unmanaged.passRetained(state).toOpaque(), data: bytes, size: length, releaseData: { info, data, _ in
                Unmanaged<ReleaseState>.fromOpaque(info!).takeRetainedValue().released = true
                free(UnsafeMutableRawPointer(mutating: data))
            })!
            let large = CGImage(width: 2048, height: 2048, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 2048 * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
            let cropped = large.cropping(to: CGRect(x: 50, y: 50, width: 16, height: 16))!
            let image = NSImage(cgImage: cropped, size: NSSize(width: 16, height: 16))
            weakSource = cropped
            output = cache.image(image, color: .red)
            _ = image.precomposed(.red)
            XCTAssertNotNil(weakSource)
        }
        XCTAssertNil(weakSource)
        XCTAssertTrue(state.released)
        XCTAssertEqual(cache.entries.count, 1)
        XCTAssertTrue(cache.entries.values.allSatisfy { $0.source == nil })
        XCTAssertNotNil(output)
        for variant in 0..<200 {
            autoreleasepool {
                let image = source(variant)
                equal(cache.image(image, color: .red), image.referencePrecomposed(.red))
            }
        }
    }

    func testSettingsInvalidateCache() {
        let original = DeviceGraphicsContextSettings.shared
        let restore = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: original.bitsPerComponent, bytesPerRow: original.bytesPerRow(forWidth: 1), space: original.colorSpace, bitmapInfo: original.opaqueBitmapInfo.rawValue)!
        defer { DeviceGraphicsContextSettings.install(restore) }
        let cache = TintCache(), image = source()
        let first = cache.image(image, color: .red)
        let changed = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 32, space: CGColorSpace(name: CGColorSpace.displayP3)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        DeviceGraphicsContextSettings.install(changed)
        let second = cache.image(image, color: .red)
        XCTAssertFalse(first === second)
        equal(second, image.referencePrecomposed(.red))
        XCTAssertEqual(cache.entries.count, 1)
    }

    func testConcurrentHitsAndEvictions() {
        let cache = TintCache(), bitmaps = (0..<80).map { bitmap($0) }
        let lock = NSLock()
        var mismatches = 0
        DispatchQueue.concurrentPerform(iterations: 1200) { index in
            let image = NSImage(cgImage: bitmaps[index % bitmaps.count], size: NSSize(width: 16, height: 16))
            let scale = CGFloat(index % 3 + 1)
            let actual = cache.image(image, color: .red, flipVertical: index % 2 == 0, scale: scale)
            let expected = image.referencePrecomposed(.red, flipVertical: index % 2 == 0, scale: scale)
            if pixels(actual) != pixels(expected) || pixels(image.precomposed(.red, flipVertical: index % 2 == 0, scale: scale)) != pixels(expected) { lock.lock(); mismatches += 1; lock.unlock() }
        }
        XCTAssertEqual(mismatches, 0)
        XCTAssertLessThanOrEqual(cache.entries.count, 64)
        XCTAssertEqual(cache.entries.count, cache.count)
        XCTAssertLessThanOrEqual(cache.retainedBytes, 1024 * 1024)
    }

    func testRepeatedResourceTintSharesBitmapStorage() throws {
        guard let path = ProcessInfo.processInfo.environment["TINT_ASSET_BUNDLE"], let bundle = Bundle(path: path) else { throw XCTSkip("Provide the asset probe bundle") }
        var original: [CGImage] = [], current: [CGImage] = []
        for _ in 0..<1000 {
            autoreleasepool {
                original.append(bundle.image(forResource: "Icon_CopyCode")!.referencePrecomposed(.red, scale: 2))
                current.append(bundle.image(forResource: "Icon_CopyCode")!.precomposed(.red, scale: 2))
            }
        }
        let oldUnique = Dictionary(original.map { (ObjectIdentifier($0), $0) }, uniquingKeysWith: { first, _ in first })
        let newUnique = Dictionary(current.map { (ObjectIdentifier($0), $0) }, uniquingKeysWith: { first, _ in first })
        XCTAssertEqual(oldUnique.count, 1000)
        XCTAssertEqual(newUnique.count, 1)
        let oldBytes = oldUnique.values.reduce(0) { $0 + $1.bytesPerRow * $1.height }
        let newBytes = newUnique.values.reduce(0) { $0 + $1.bytesPerRow * $1.height }
        XCTAssertEqual(oldBytes, newBytes * 1000)
        print("TINT_BITMAP_STORAGE original=\(oldBytes) current=\(newBytes) images=1000")
        for (old, new) in zip(original, current) { equal(new, old) }
    }

    func testPublicAPIThroughRealTGUIKit() {
        for size in [NSSize(width: 16, height: 16), NSSize(width: 15.5, height: 17.25), NSSize(width: 65, height: 70)] {
            let image = source(size: size)
            for scale: CGFloat in [0, 1, 2, 3] {
                for zoom: CGFloat in [0.5, 1, 1.5] {
                    for horizontal in [false, true] {
                        for (color, bottom) in [(nil, nil), (NSColor.red, nil), (NSColor.green, NSColor.blue)] as [(NSColor?, NSColor?)] {
                            let expected = image.referencePrecomposed(color, bottomColor: bottom, flipVertical: true, flipHorizontal: horizontal, scale: scale, zoom: zoom)
                            equal(image.precomposed(color, bottomColor: bottom, flipVertical: true, flipHorizontal: horizontal, scale: scale, zoom: zoom), expected)
                        }
                    }
                }
            }
        }
        let image = source()
        let first = image.precomposed(.red)
        XCTAssertTrue(first === image.precomposed(.red))
        image.size = NSSize(width: 18, height: 19)
        equal(image.precomposed(.red), image.referencePrecomposed(.red))
    }

    func testHalfFloatOutputMatchesOriginal() throws {
        let original = DeviceGraphicsContextSettings.shared
        let restore = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: original.bitsPerComponent, bytesPerRow: original.bytesPerRow(forWidth: 1), space: original.colorSpace, bitmapInfo: original.opaqueBitmapInfo.rawValue)!
        defer { DeviceGraphicsContextSettings.install(restore) }
        let context = try XCTUnwrap(CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 16, bytesPerRow: 32, space: CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!, bitmapInfo: CGBitmapInfo.floatComponents.rawValue | CGBitmapInfo.byteOrder16Little.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue))
        DeviceGraphicsContextSettings.install(context)
        let image = source(), cache = TintCache()
        for scale: CGFloat in [1, 2, 3] {
            for color in [NSColor.red, .blue.withAlphaComponent(0.3), NSColor(displayP3Red: 0.3, green: 0.8, blue: 0.1, alpha: 0.7)] {
                let expected = image.referencePrecomposed(color, scale: scale)
                XCTAssertEqual(expected.bitsPerComponent, 16)
                equal(cache.image(image, color: color, scale: scale), expected)
                equal(image.precomposed(color, scale: scale), expected)
            }
        }
    }

    func testBundledRasterAndVectorAssets() throws {
        guard let path = ProcessInfo.processInfo.environment["TINT_ASSET_BUNDLE"], let bundle = Bundle(path: path) else { throw XCTSkip("Provide the asset probe bundle") }
        let names = try String(contentsOfFile: path + "/asset-names.txt").split(separator: "\n").map(String.init)
        let cache = TintCache(), oldAppearance = NSAppearance.current
        defer { NSAppearance.current = oldAppearance }
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            NSAppearance.current = NSAppearance(named: appearance)
            for name in names {
                for scale: CGFloat in [1, 2, 3] {
                    for horizontal in [false, true] {
                        let image = try XCTUnwrap(bundle.image(forResource: NSImage.Name(name)))
                        for size in [image.size, NSSize(width: 16, height: 16)] {
                            image.size = size
                            let actual = cache.image(image, color: .red, flipVertical: true, flipHorizontal: horizontal, scale: scale)
                            equal(actual, image.referencePrecomposed(.red, flipVertical: true, flipHorizontal: horizontal, scale: scale))
                            equal(image.precomposed(.red, flipVertical: true, flipHorizontal: horizontal, scale: scale), actual)
                            equal(cache.image(image, color: .red, flipVertical: true, flipHorizontal: horizontal, scale: scale), actual)
                        }
                    }
                }
            }
        }
    }
}
