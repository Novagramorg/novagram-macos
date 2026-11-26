import XCTest
import QuartzCore
import Metal
@testable import UniqueGiftRenderer

struct Bitmap {
    let width: Int
    let height: Int
    let bytes: [UInt8]

    init(image: CGImage) {
        self.width = image.width
        self.height = image.height
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        bytes.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4, space: UniqueGiftBackgroundRenderer.colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            context?.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        self.bytes = bytes
    }

    init(width: Int, height: Int, bytes: [UInt8]) {
        self.width = width
        self.height = height
        self.bytes = bytes
    }

    func pixel(_ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int, a: Int) {
        let offset = (y * self.width + x) * 4
        return (Int(self.bytes[offset]), Int(self.bytes[offset + 1]), Int(self.bytes[offset + 2]), Int(self.bytes[offset + 3]))
    }
}

func makeCircleGlyph(asymmetric: Bool = false) -> CGImage {
    let size = UniqueGiftBackgroundRenderer.glyphPixelSize
    let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: UniqueGiftBackgroundRenderer.colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
    context.setFillColor(UniqueGiftBackgroundRenderer.color(0x204080))
    if asymmetric {
        context.fill(CGRect(x: 0, y: size / 2, width: size, height: size / 2))
    } else {
        context.fillEllipse(in: CGRect(x: 8, y: 8, width: size - 16, height: size - 16))
    }
    return UniqueGiftBackgroundRenderer.makeGlyphTemplate(from: context.makeImage()!)!
}

private func channels(_ rgb: UInt32) -> (Int, Int, Int) {
    return (Int((rgb >> 16) & 0xff), Int((rgb >> 8) & 0xff), Int(rgb & 0xff))
}

final class UniqueGiftBackgroundRendererTests: XCTestCase {
    let colors = UniqueGiftColors(centerRGB: 0xd18c96, edgeRGB: 0x8a4a5a, patternRGB: 0x3d1520)

    func assertColor(_ pixel: (r: Int, g: Int, b: Int, a: Int), _ expected: (Int, Int, Int), tolerance: Int, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertLessThanOrEqual(abs(pixel.r - expected.0), tolerance, "r \(pixel) vs \(expected)", file: file, line: line)
        XCTAssertLessThanOrEqual(abs(pixel.g - expected.1), tolerance, "g \(pixel) vs \(expected)", file: file, line: line)
        XCTAssertLessThanOrEqual(abs(pixel.b - expected.2), tolerance, "b \(pixel) vs \(expected)", file: file, line: line)
        XCTAssertEqual(pixel.a, 255, file: file, line: line)
    }

    func testGradientRunsFromCenterToEdgeColor() {
        let geometry = UniqueGiftBackgroundGeometry.item(size: CGSize(width: 110.0, height: 154.0), giftCenterY: 60.0, cornerRadius: 0.0)
        let bitmap = Bitmap(image: UniqueGiftBackgroundRenderer.makeImage(geometry: geometry, colors: colors, glyph: nil, scale: 2.0)!)
        XCTAssertEqual(bitmap.width, 220)
        XCTAssertEqual(bitmap.height, 308)
        assertColor(bitmap.pixel(110, 120), channels(colors.center), tolerance: 2)
        assertColor(bitmap.pixel(219, 307), channels(colors.edge), tolerance: 1)
        let topLeft = bitmap.pixel(0, 0)
        let rho = sqrt(pow(55.0 / 77.0, 2.0) + pow(60.0 / 94.0, 2.0))
        let centerChannels = channels(colors.center)
        let edgeChannels = channels(colors.edge)
        assertColor(topLeft, (Int((CGFloat(centerChannels.0) + CGFloat(edgeChannels.0 - centerChannels.0) * rho).rounded()), Int((CGFloat(centerChannels.1) + CGFloat(edgeChannels.1 - centerChannels.1) * rho).rounded()), Int((CGFloat(centerChannels.2) + CGFloat(edgeChannels.2 - centerChannels.2) * rho).rounded())), tolerance: 2)
        let midway = bitmap.pixel(110, 120 + 94)
        let center = channels(colors.center)
        let edge = channels(colors.edge)
        assertColor(midway, ((center.0 + edge.0) / 2, (center.1 + edge.1) / 2, (center.2 + edge.2) / 2), tolerance: 3)
    }

    func testPatternStrengthAtAnItemMatchesTheTintFormula() {
        let geometry = UniqueGiftBackgroundGeometry.item(size: CGSize(width: 114.0, height: 114.0), giftCenterY: 57.0, cornerRadius: 0.0)
        let plain = Bitmap(image: UniqueGiftBackgroundRenderer.makeImage(geometry: geometry, colors: colors, glyph: nil, scale: 2.0)!)
        let patterned = Bitmap(image: UniqueGiftBackgroundRenderer.makeImage(geometry: geometry, colors: colors, glyph: makeCircleGlyph(), scale: 2.0)!)
        let item = geometry.patternItems()[0]
        let x = Int(item.frame.midX * 2.0)
        let y = Int(item.frame.midY * 2.0)
        let rho = abs(item.frame.midY - 57.0) / 57.0
        let alpha = 0.6 * (1.0 - rho) * 0.8
        let base = plain.pixel(x, y)
        let pattern = channels(colors.pattern)
        let expected = (
            Int((CGFloat(base.r) * (1.0 - alpha) + CGFloat(pattern.0) * alpha).rounded()),
            Int((CGFloat(base.g) * (1.0 - alpha) + CGFloat(pattern.1) * alpha).rounded()),
            Int((CGFloat(base.b) * (1.0 - alpha) + CGFloat(pattern.2) * alpha).rounded())
        )
        assertColor(patterned.pixel(x, y), expected, tolerance: 3)
        let untouched = plain.pixel(114, 114)
        assertColor(patterned.pixel(114, 114), (untouched.r, untouched.g, untouched.b), tolerance: 0)
    }

    func testGlyphsAreDrawnUpright() {
        let geometry = UniqueGiftBackgroundGeometry.item(size: CGSize(width: 200.0, height: 200.0), giftCenterY: 100.0, cornerRadius: 0.0)
        let plain = Bitmap(image: UniqueGiftBackgroundRenderer.makeImage(geometry: geometry, colors: colors, glyph: nil, scale: 1.0)!)
        let patterned = Bitmap(image: UniqueGiftBackgroundRenderer.makeImage(geometry: geometry, colors: colors, glyph: makeCircleGlyph(asymmetric: true), scale: 1.0)!)
        let item = geometry.patternItems()[0].frame
        let top = (Int(item.midX), Int(item.minY + item.height * 0.25))
        let bottom = (Int(item.midX), Int(item.minY + item.height * 0.75))
        XCTAssertNotEqual(patterned.pixel(top.0, top.1).r, plain.pixel(top.0, top.1).r)
        XCTAssertEqual(patterned.pixel(bottom.0, bottom.1).r, plain.pixel(bottom.0, bottom.1).r)
    }

    func testCornersAreTransparentWithARadius() {
        let geometry = UniqueGiftBackgroundGeometry.item(size: CGSize(width: 100.0, height: 100.0), giftCenterY: 50.0, cornerRadius: 16.0)
        let bitmap = Bitmap(image: UniqueGiftBackgroundRenderer.makeImage(geometry: geometry, colors: colors, glyph: nil, scale: 2.0)!)
        XCTAssertEqual(bitmap.pixel(0, 0).a, 0)
        XCTAssertEqual(bitmap.pixel(199, 199).a, 0)
        XCTAssertEqual(bitmap.pixel(100, 0).a, 255)
    }

    func testCacheEvictsTheLeastRecentlyUsed() {
        let geometry = UniqueGiftBackgroundGeometry.item(size: CGSize(width: 100.0, height: 100.0), giftCenterY: 50.0, cornerRadius: 0.0)
        let sample = UniqueGiftBackgroundRenderer.makeImage(geometry: geometry, colors: colors, glyph: nil, scale: 1.0)!
        let limit = sample.bytesPerRow * sample.height * 3
        let cache = UniqueGiftBackgroundCache(byteLimit: limit)
        func key(_ edge: UInt32) -> UniqueGiftBackgroundKey {
            return UniqueGiftBackgroundKey(geometry: geometry, colors: UniqueGiftColors(centerRGB: 0x808080, edgeRGB: edge, patternRGB: 0), glyphId: nil, scale: 1.0)
        }
        XCTAssertNotNil(cache.image(for: key(1), glyph: nil))
        XCTAssertNotNil(cache.image(for: key(2), glyph: nil))
        XCTAssertNotNil(cache.image(for: key(3), glyph: nil))
        XCTAssertNotNil(cache.cachedImage(for: key(1)))
        XCTAssertNotNil(cache.image(for: key(4), glyph: nil))
        XCTAssertNotNil(cache.cachedImage(for: key(1)))
        XCTAssertNil(cache.cachedImage(for: key(2)))
        XCTAssertNotNil(cache.cachedImage(for: key(3)))
        XCTAssertLessThanOrEqual(cache.byteCount, limit)
    }

    func testCacheDropsIdleEntries() {
        let geometry = UniqueGiftBackgroundGeometry.item(size: CGSize(width: 40.0, height: 40.0), giftCenterY: 20.0, cornerRadius: 0.0)
        let cache = UniqueGiftBackgroundCache(byteLimit: 1024 * 1024, idleTimeout: 60.0)
        let old = UniqueGiftBackgroundKey(geometry: geometry, colors: UniqueGiftColors(centerRGB: 0x808080, edgeRGB: 1, patternRGB: 0), glyphId: nil, scale: 1.0)
        let fresh = UniqueGiftBackgroundKey(geometry: geometry, colors: UniqueGiftColors(centerRGB: 0x808080, edgeRGB: 2, patternRGB: 0), glyphId: nil, scale: 1.0)
        XCTAssertNotNil(cache.image(for: old, glyph: nil))
        XCTAssertNotNil(cache.image(for: fresh, glyph: nil))
        cache.sweepIdleEntries(now: CFAbsoluteTimeGetCurrent() + 30.0)
        XCTAssertNotNil(cache.cachedImage(for: old))
        cache.sweepIdleEntries(now: CFAbsoluteTimeGetCurrent() + 61.0)
        XCTAssertNil(cache.cachedImage(for: old))
        XCTAssertNil(cache.cachedImage(for: fresh))
        XCTAssertEqual(cache.byteCount, 0)
    }

    func testGrayGlyphMaskRendersTheSameAsTheTemplate() {
        let geometry = UniqueGiftBackgroundGeometry.item(size: CGSize(width: 112.0, height: 133.0), giftCenterY: 44.0, cornerRadius: 10.0)
        let template = makeCircleGlyph()
        let glyph = UniqueGiftGlyph(template: template, mask: UniqueGiftBackgroundRenderer.makeGlyphMask(from: template)!)
        XCTAssertEqual(glyph.mask.colorSpace?.model, .monochrome)
        XCTAssertEqual(glyph.mask.alphaInfo, .none)
        let fromTemplate = Bitmap(image: UniqueGiftBackgroundRenderer.makeImage(geometry: geometry, colors: colors, glyph: template, scale: 2.0)!)
        let fromMask = Bitmap(image: UniqueGiftBackgroundRenderer.makeImage(geometry: geometry, colors: colors, glyph: glyph.mask, scale: 2.0)!)
        XCTAssertEqual(fromTemplate.bytes, fromMask.bytes)
    }

    func testOverlappingGlyphsAccumulateLikeSourceOver() {
        let template = makeCircleGlyph()
        let mask = UniqueGiftBackgroundRenderer.makeGlyphMask(from: template)!
        let context = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        context.setBlendMode(.screen)
        for _ in 0 ..< 2 {
            context.saveGState()
            context.setAlpha(0.5)
            context.draw(mask, in: CGRect(x: -48.0, y: -48.0, width: 96.0, height: 96.0))
            context.restoreGState()
        }
        let value = context.data!.load(as: UInt8.self)
        XCTAssertLessThanOrEqual(abs(Int(value) - 191), 1)
    }

    func testRendersIntoTheTargetColorSpace() {
        let geometry = UniqueGiftBackgroundGeometry.item(size: CGSize(width: 60.0, height: 60.0), giftCenterY: 30.0, cornerRadius: 0.0)
        let displayP3 = CGColorSpace(name: CGColorSpace.displayP3)!
        let image = UniqueGiftBackgroundRenderer.makeImage(geometry: geometry, colors: colors, glyph: nil, scale: 1.0, colorSpace: displayP3)!
        XCTAssertEqual(image.colorSpace?.name, CGColorSpace.displayP3)
        let converted = Bitmap(image: image)
        let reference = Bitmap(image: UniqueGiftBackgroundRenderer.makeImage(geometry: geometry, colors: colors, glyph: nil, scale: 1.0)!)
        for (x, y) in [(30, 30), (0, 0), (59, 59), (10, 45)] {
            let a = converted.pixel(x, y)
            assertColor(a, (reference.pixel(x, y).r, reference.pixel(x, y).g, reference.pixel(x, y).b), tolerance: 2)
        }
        let gray = CGColorSpaceCreateDeviceGray()
        XCTAssertEqual(UniqueGiftBackgroundRenderer.makeImage(geometry: geometry, colors: colors, glyph: nil, scale: 1.0, colorSpace: gray)!.colorSpace?.name, CGColorSpace.sRGB)
    }

    func testCacheKeysDifferByColorSpace() {
        let geometry = UniqueGiftBackgroundGeometry.item(size: CGSize(width: 60.0, height: 60.0), giftCenterY: 30.0, cornerRadius: 0.0)
        let srgb = UniqueGiftBackgroundKey(geometry: geometry, colors: colors, glyphId: 1, scale: 2.0)
        let p3 = UniqueGiftBackgroundKey(geometry: geometry, colors: colors, glyphId: 1, scale: 2.0, colorSpace: CGColorSpace(name: CGColorSpace.displayP3)!)
        XCTAssertNotEqual(srgb, p3)
        XCTAssertEqual(srgb, UniqueGiftBackgroundKey(geometry: geometry, colors: colors, glyphId: 1, scale: 2.0, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!))
        XCTAssertEqual(srgb, UniqueGiftBackgroundKey(geometry: geometry, colors: colors, glyphId: 1, scale: 2.0, colorSpace: CGColorSpaceCreateDeviceGray()))
    }
}

final class UniqueGiftCoreAnimationReferenceTests: XCTestCase {
    let colors = UniqueGiftColors(centerRGB: 0x7cc06e, edgeRGB: 0x3f8a52, patternRGB: 0x1d4a26)

    private func makeIOSLayerTree(geometry: UniqueGiftBackgroundGeometry, glyph: CGImage) -> CALayer {
        let root = CALayer()
        root.isGeometryFlipped = true
        root.frame = CGRect(origin: .zero, size: geometry.size)
        root.masksToBounds = true
        root.backgroundColor = UniqueGiftBackgroundRenderer.color(colors.edge)

        let gradient = CAGradientLayer()
        gradient.type = .radial
        let gradientFrame = geometry.gradientFrame
        gradient.frame = gradientFrame
        gradient.startPoint = CGPoint(x: 0.5, y: geometry.patternCenter.y / gradientFrame.height)
        gradient.endPoint = CGPoint(x: 1.0, y: 1.0)
        gradient.colors = [UniqueGiftBackgroundRenderer.color(colors.center), UniqueGiftBackgroundRenderer.color(colors.edge)]
        root.addSublayer(gradient)

        let tint = CAGradientLayer()
        tint.type = .radial
        tint.startPoint = CGPoint(x: 0.5, y: 0.5)
        tint.endPoint = CGPoint(x: 1.0, y: 1.0)
        tint.frame = geometry.patternTintFrame
        tint.colors = [UniqueGiftBackgroundRenderer.color(colors.pattern, alpha: 0.6), UniqueGiftBackgroundRenderer.color(colors.pattern, alpha: 0.0)]
        let mask = CALayer()
        mask.frame = tint.bounds
        for item in geometry.patternItems() {
            let itemLayer = CALayer()
            itemLayer.contents = glyph
            itemLayer.frame = item.frame.offsetBy(dx: -tint.frame.minX, dy: -tint.frame.minY)
            itemLayer.setValue(CGColor(gray: 0.0, alpha: 0.8), forKey: "contentsMultiplyColor")
            mask.addSublayer(itemLayer)
        }
        tint.mask = mask
        root.addSublayer(tint)
        return root
    }

    private func renderWithCoreAnimation(_ layer: CALayer, size: CGSize, scale: CGFloat) throws -> Bitmap {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            throw XCTSkip("no Metal device")
        }
        let width = Int(size.width * scale)
        let height = Int(size.height * scale)
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .private
        let texture = device.makeTexture(descriptor: descriptor)!
        let top = CALayer()
        top.frame = CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height))
        top.isGeometryFlipped = true
        layer.anchorPoint = .zero
        layer.position = .zero
        layer.transform = CATransform3DMakeScale(scale, scale, 1.0)
        top.addSublayer(layer)
        let renderer = CARenderer(mtlTexture: texture, options: [kCARendererMetalCommandQueue as String: queue, kCARendererColorSpace as String: UniqueGiftBackgroundRenderer.colorSpace])
        renderer.layer = top
        renderer.bounds = top.bounds
        CATransaction.flush()
        renderer.beginFrame(atTime: CACurrentMediaTime(), timeStamp: nil)
        renderer.addUpdate(renderer.bounds)
        renderer.render()
        renderer.endFrame()
        let bytesPerRow = width * 4
        let buffer = device.makeBuffer(length: bytesPerRow * height, options: .storageModeShared)!
        let commandBuffer = queue.makeCommandBuffer()!
        let blit = commandBuffer.makeBlitCommandEncoder()!
        blit.copy(from: texture, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0), sourceSize: MTLSize(width: width, height: height, depth: 1), to: buffer, destinationOffset: 0, destinationBytesPerRow: bytesPerRow, destinationBytesPerImage: bytesPerRow * height)
        blit.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        renderer.layer = nil
        let bgra = Array(UnsafeBufferPointer(start: buffer.contents().assumingMemoryBound(to: UInt8.self), count: bytesPerRow * height))
        var rgba = [UInt8](repeating: 0, count: bgra.count)
        for index in stride(from: 0, to: bgra.count, by: 4) {
            rgba[index] = bgra[index + 2]
            rgba[index + 1] = bgra[index + 1]
            rgba[index + 2] = bgra[index]
            rgba[index + 3] = bgra[index + 3]
        }
        return Bitmap(width: width, height: height, bytes: rgba)
    }

    private func compare(geometry: UniqueGiftBackgroundGeometry, name: String) throws {
        let glyph = makeCircleGlyph()
        let scale: CGFloat = 2.0
        let reference = try renderWithCoreAnimation(makeIOSLayerTree(geometry: geometry, glyph: glyph), size: geometry.size, scale: scale)
        let ours = Bitmap(image: UniqueGiftBackgroundRenderer.makeImage(geometry: geometry, colors: colors, glyph: glyph, scale: scale)!)
        XCTAssertEqual(ours.width, reference.width)
        XCTAssertEqual(ours.height, reference.height)
        var maxDifference = 0
        var total = 0
        var over4 = 0
        for index in 0 ..< min(ours.bytes.count, reference.bytes.count) where index % 4 != 3 {
            let difference = abs(Int(ours.bytes[index]) - Int(reference.bytes[index]))
            maxDifference = max(maxDifference, difference)
            total += difference
            if difference > 4 {
                over4 += 1
            }
        }
        let mean = Double(total) / Double(ours.bytes.count / 4 * 3)
        print("\(name): max \(maxDifference), mean \(String(format: "%.3f", mean)), channels over 4: \(over4)")
        XCTAssertLessThanOrEqual(mean, 1.0, name)
        XCTAssertLessThanOrEqual(Double(over4) / Double(ours.bytes.count / 4 * 3), 0.01, name)
    }

    func testOptionCellMatchesTheIOSLayerTree() throws {
        try compare(geometry: .item(size: CGSize(width: 110.0, height: 154.0), giftCenterY: 60.0, cornerRadius: 0.0), name: "option cell 110x154")
    }

    func testProfileGridCellMatchesTheIOSLayerTree() throws {
        try compare(geometry: .item(size: CGSize(width: 114.0, height: 114.0), giftCenterY: 57.0, cornerRadius: 0.0), name: "profile cell 114x114")
    }

    func testHeaderMatchesTheIOSLayerTree() throws {
        try compare(geometry: .header(size: CGSize(width: 390.0, height: 240.0)), name: "header 390x240")
    }

    func testSmallTileMatchesTheIOSLayerTree() throws {
        try compare(geometry: .item(size: CGSize(width: 60.0, height: 60.0), giftCenterY: 30.0, cornerRadius: 0.0), name: "tile 60x60")
    }
}
