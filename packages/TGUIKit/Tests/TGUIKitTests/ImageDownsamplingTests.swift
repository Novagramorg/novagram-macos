import XCTest
import AppKit
import ImageIO
@testable import TGUIKit

final class ImageDownsamplingTests: XCTestCase {

    private func writePNG(width: Int, height: Int) -> String {
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(NSColor.red.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = ctx.makeImage()!
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("downsample-\(width)x\(height)-\(UUID().uuidString).png")
        let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
        return url.path
    }

    private func pixels(_ image: NSImage?) -> (width: Int, height: Int)? {
        guard let cg = image?.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        return (cg.width, cg.height)
    }

    func testDownsamplesOversizedImageToCap() {
        let path = writePNG(width: 4000, height: 6000)
        defer { try? FileManager.default.removeItem(atPath: path) }
        let image = downsampledImage(contentsOfFile: path, maxPixelSize: 3160)
        guard let size = pixels(image) else { return XCTFail("no image") }
        XCTAssertLessThanOrEqual(max(size.width, size.height), 3160)
        XCTAssertGreaterThan(max(size.width, size.height), 3156, "should cap near maxPixelSize, not a tiny thumbnail")
        XCTAssertEqual(Double(size.width) / Double(size.height), 4000.0 / 6000.0, accuracy: 0.01, "aspect ratio preserved")
    }

    func testDoesNotUpscaleSmallImage() {
        let path = writePNG(width: 400, height: 800)
        defer { try? FileManager.default.removeItem(atPath: path) }
        let image = downsampledImage(contentsOfFile: path, maxPixelSize: 3160)
        guard let size = pixels(image) else { return XCTFail("no image") }
        XCTAssertEqual(size.width, 400)
        XCTAssertEqual(size.height, 800)
    }

    func testMissingFileReturnsNil() {
        XCTAssertNil(downsampledImage(contentsOfFile: NSTemporaryDirectory() + "no-such-\(UUID().uuidString).png", maxPixelSize: 100))
    }

    func testZeroMaxPixelSizeReturnsNil() {
        let path = writePNG(width: 10, height: 10)
        defer { try? FileManager.default.removeItem(atPath: path) }
        XCTAssertNil(downsampledImage(contentsOfFile: path, maxPixelSize: 0))
    }
}
