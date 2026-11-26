import Cocoa
import XCTest
import TGUIKit
@testable import FoldingViewHarness

final class QuoteMaskTests: XCTestCase {
    override func setUp() { TGUIKitTestBootstrap.install() }

    func pixels(_ image: CGImage) -> Data {
        let bytes = image.width * image.height * 4
        var data = Data(count: bytes)
        data.withUnsafeMutableBytes { buffer in
            let ctx = CGContext(data: buffer.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.setBlendMode(.copy)
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return data
    }

    func content(_ count: Int = 1, text: String = "Long quote مرحبا 👩🏽‍💻 with words to wrap into multiple lines. ", font: CGFloat = 14, code: Bool = false) -> (NSAttributedString, [TextViewLayout], [NSRange]) {
        let full = NSMutableAttributedString()
        var blocks: [TextViewLayout] = [], ranges: [NSRange] = []
        for index in 0..<count {
            let value = NSMutableAttributedString(string: String(repeating: text, count: 8), attributes: [.font: NSFont.systemFont(ofSize: font), .foregroundColor: NSColor.black])
            let header = code ? TextNode.layoutText(NSAttributedString(string: "Swift", attributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.blue]), nil, 1, .end, NSSize(width: 200, height: 40), nil, false, .left) : nil
            value.addAttribute(TextInputAttributes.quote, value: TextViewBlockQuoteData(id: index, colors: .init(main: .blue), isCode: code, header: header, collapsable: true), range: value.range)
            ranges.append(NSRange(location: full.length, length: value.length))
            full.append(value)
            blocks.append(TextViewLayout(value))
        }
        return (full, blocks, ranges)
    }

    func testExactPixelsAcrossGeometryAndScale() throws {
        let cache = FoldingQuoteMaskCache()
        for scale: CGFloat in [1, 2, 3] {
            for width: CGFloat in [1, 57.25, 180, 280.5, 403] {
                for height: CGFloat in [1, 30.25, 53] {
                    for y: CGFloat in [-2, 0, 16.75, 26, 60] {
                        let size = NSSize(width: width, height: height)
                        let expected = try XCTUnwrap(referenceMaskImage(size: size, y: y, scale: scale))
                        let actual = try XCTUnwrap(cache.image(size: size, y: y, scale: scale))
                        XCTAssertEqual(actual.width, expected.width)
                        XCTAssertEqual(actual.height, expected.height)
                        XCTAssertEqual(pixels(actual), pixels(expected))
                        XCTAssertTrue(actual === cache.image(size: size, y: y, scale: scale))
                    }
                }
            }
        }
        XCTAssertNil(cache.image(size: .zero, y: 0, scale: 2))
    }

    func testKeysPreserveFractionalCoordinatesAndScale() throws {
        let cache = FoldingQuoteMaskCache()
        let first = try XCTUnwrap(cache.image(size: NSSize(width: 220, height: 40), y: 19, scale: 2))
        for (width, height, y, scale): (CGFloat, CGFloat, CGFloat, CGFloat) in [(220.1, 40, 19, 2), (220, 40.1, 19, 2), (220, 40, 19.1, 2), (220, 40, 19, 1)] {
            XCTAssertFalse(first === cache.image(size: NSSize(width: width, height: height), y: y, scale: scale))
        }
        XCTAssertTrue(first === cache.image(size: NSSize(width: 220, height: 40), y: 19, scale: 2))
    }

    func testBoundedRetentionAndOversizedBypass() throws {
        let cache = FoldingQuoteMaskCache(maximumCount: 3, maximumBytes: 50000)
        let first = try XCTUnwrap(cache.image(size: NSSize(width: 80, height: 20), y: 10, scale: 1))
        for width in 81...300 {
            _ = cache.image(size: NSSize(width: width, height: 20), y: 10, scale: 1)
            XCTAssertLessThanOrEqual(cache.images.count, 3)
            XCTAssertLessThanOrEqual(cache.retainedBytes, 50000)
            XCTAssertEqual(cache.images.count, cache.order.count)
            XCTAssertEqual(cache.retainedBytes, cache.images.values.reduce(0) { $0 + $1.bytesPerRow * $1.height })
        }
        XCTAssertEqual(pixels(first), pixels(try XCTUnwrap(referenceMaskImage(size: NSSize(width: 80, height: 20), y: 10, scale: 1))))
        XCTAssertFalse(first === cache.image(size: NSSize(width: 80, height: 20), y: 10, scale: 1))
        let before = cache.retainedBytes
        let large = try XCTUnwrap(cache.image(size: NSSize(width: 800, height: 100), y: 20, scale: 2))
        XCTAssertEqual(cache.retainedBytes, before)
        XCTAssertFalse(large === cache.image(size: NSSize(width: 800, height: 100), y: 20, scale: 2))
    }

    func testConcurrentAccessAndEviction() {
        let cache = FoldingQuoteMaskCache(maximumCount: 8, maximumBytes: 300000)
        let failureLock = NSLock()
        var failures = 0
        DispatchQueue.concurrentPerform(iterations: 600) { index in
            let size = NSSize(width: 80 + index % 23, height: 30)
            let scale = CGFloat(1 + index % 3)
            let actual = cache.image(size: size, y: 17.25, scale: scale)!
            let expected = referenceMaskImage(size: size, y: 17.25, scale: scale)!
            if pixels(actual) != pixels(expected) { failureLock.lock(); failures += 1; failureLock.unlock() }
        }
        XCTAssertEqual(failures, 0)
        XCTAssertLessThanOrEqual(cache.images.count, 8)
        XCTAssertLessThanOrEqual(cache.retainedBytes, 300000)
    }

    func testDrawingSettingsInvalidateCachedImages() throws {
        let original = DeviceGraphicsContextSettings.shared
        let restore = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: original.bitsPerComponent, bytesPerRow: original.bytesPerRow(forWidth: 1), space: original.colorSpace, bitmapInfo: original.opaqueBitmapInfo.rawValue)!
        defer { DeviceGraphicsContextSettings.install(restore) }
        let cache = FoldingQuoteMaskCache()
        let size = NSSize(width: 240, height: 40)
        let first = try XCTUnwrap(cache.image(size: size, y: 20, scale: 2))
        let different = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 32, space: CGColorSpace(name: CGColorSpace.displayP3)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        DeviceGraphicsContextSettings.install(different)
        XCTAssertNotEqual(original, DeviceGraphicsContextSettings.shared)
        let second = try XCTUnwrap(cache.image(size: size, y: 20, scale: 2))
        XCTAssertFalse(first === second)
        XCTAssertEqual(cache.images.count, 1)
        XCTAssertEqual(pixels(second), pixels(try XCTUnwrap(referenceMaskImage(size: size, y: 20, scale: 2))))
        DeviceGraphicsContextSettings.install(restore)
        XCTAssertEqual(original, DeviceGraphicsContextSettings.shared)
        let third = try XCTUnwrap(cache.image(size: size, y: 20, scale: 2))
        XCTAssertFalse(second === third)
        XCTAssertEqual(pixels(first), pixels(third))
    }

    func testIndependentRowsShareImmutableMasks() throws {
        var actual: [FoldingTextLayout] = []
        var expected: [ReferenceMaskFoldingTextLayout] = []
        for _ in 0..<100 {
            let a = content(), b = content()
            let current = FoldingTextLayout(attributedString: a.0, blocks: a.1, blockRanges: a.2, context: BlockContext(), revealed: [])
            let reference = ReferenceMaskFoldingTextLayout(attributedString: b.0, blocks: b.1, blockRanges: b.2, context: BlockContext(), revealed: [])
            current.measure(width: 240); reference.measure(width: 240)
            actual.append(current); expected.append(reference)
        }
        XCTAssertEqual(Set(actual.compactMap { $0.blocks[0].mask }.map(ObjectIdentifier.init)).count, 1)
        XCTAssertEqual(Set(expected.compactMap { $0.blocks[0].mask }.map(ObjectIdentifier.init)).count, 100)
        func uniqueBytes(_ images: [CGImage]) -> Int {
            var seen = Set<ObjectIdentifier>()
            return images.reduce(0) { total, image in
                total + (seen.insert(ObjectIdentifier(image)).inserted ? image.bytesPerRow * image.height : 0)
            }
        }
        let storage = ["rows": 100, "original_unique_bitmap_bytes": uniqueBytes(expected.compactMap { $0.blocks[0].mask }), "cached_unique_bitmap_bytes": uniqueBytes(actual.compactMap { $0.blocks[0].mask })]
        try JSONSerialization.data(withJSONObject: storage, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: "/tmp/chat-quote-mask-sharing.json"))
        let previous = try XCTUnwrap(actual[1].blocks[0].mask)
        actual[0].measure(width: 180)
        actual[0].toggle(0)
        XCTAssertTrue(previous === actual[1].blocks[0].mask)
        XCTAssertEqual(pixels(previous), pixels(try XCTUnwrap(expected[1].blocks[0].mask)))
    }

    func testFullMeasureRevealReflowAndMutableText() throws {
        let oldScale = System.backingScale
        defer { System.updateScaleFactor(oldScale) }
        for code in [false, true] {
            for font: CGFloat in [11, 14, 20] {
                let a = content(3, font: font, code: code), b = content(3, font: font, code: code)
                let actual = FoldingTextLayout(attributedString: a.0, blocks: a.1, blockRanges: a.2, context: BlockContext(), revealed: [])
                let expected = ReferenceMaskFoldingTextLayout(attributedString: b.0, blocks: b.1, blockRanges: b.2, context: BlockContext(), revealed: [])
                for index in 0..<24 {
                    System.updateScaleFactor(index % 2 == 0 ? 1 : 2)
                    let width = CGFloat([120, 240, 240, 400, 187, 240][index % 6])
                    actual.revealed = index % 4 == 0 ? [1] : []
                    expected.revealed = actual.revealed
                    actual.measure(width: width)
                    expected.measure(width: width)
                    XCTAssertEqual(actual.size, expected.size)
                    for i in actual.blocks.indices {
                        let lhs = actual.blocks[i], rhs = expected.blocks[i]
                        XCTAssertEqual(lhs.size, rhs.size)
                        XCTAssertEqual(lhs.isRevealed, rhs.isRevealed)
                        XCTAssertEqual(lhs.mask == nil, rhs.mask == nil)
                        if let l = lhs.mask, let r = rhs.mask { XCTAssertEqual(pixels(l), pixels(r)) }
                    }
                    actual.blocks[0].text.measure(width: 91)
                    expected.blocks[0].text.measure(width: 91)
                }
                let changedA = content(font: font + 3), changedB = content(font: font + 3)
                actual.blocks[0].text.setAttributedString(changedA.1[0].attributedString)
                expected.blocks[0].text.setAttributedString(changedB.1[0].attributedString)
                actual.measure(width: 240); expected.measure(width: 240)
                XCTAssertEqual(pixels(try XCTUnwrap(actual.blocks[0].mask)), pixels(try XCTUnwrap(expected.blocks[0].mask)))
            }
        }
    }
}
