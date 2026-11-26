import XCTest
import AppKit
import ImageIO
import TelegramMediaUtils

final class WallpaperEightBitTests: XCTestCase {

    private var directory: String!

    override func setUp() {
        super.setUp()
        directory = NSTemporaryDirectory() + "wallpaper-8bit-\(UUID().uuidString)"
        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(atPath: directory)
        super.tearDown()
    }

    private func patternMask(bitsPerComponent: Int) -> CGImage {
        let space = CGColorSpace(name: CGColorSpace.displayP3)!
        let info = bitsPerComponent == 16 ? CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder16Little.rawValue : CGImageAlphaInfo.premultipliedLast.rawValue
        let context = CGContext(data: nil, width: 400, height: 800, bitsPerComponent: bitsPerComponent, bytesPerRow: 0, space: space, bitmapInfo: info)!
        context.setShouldAntialias(true)
        for i in 0 ..< 40 {
            let x = CGFloat((i * 37) % 360), y = CGFloat((i * 53) % 760)
            context.setFillColor(CGColor(colorSpace: space, components: [0, 0, 0, CGFloat(i % 10 + 1) / 10])!)
            context.fillEllipse(in: CGRect(x: x, y: y, width: 23.5, height: 31.25))
            context.setStrokeColor(CGColor(colorSpace: space, components: [0, 0, 0, 0.7])!)
            context.setLineWidth(1.5)
            context.stroke(CGRect(x: y / 2, y: x * 2, width: 17.3, height: 9.7))
        }
        return context.makeImage()!
    }

    private func writePNG(_ image: CGImage, name: String) -> String {
        let path = directory + "/" + name
        let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return path
    }

    private func decode(_ path: String) -> CGImage {
        let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil)!
        return CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCache: false] as CFDictionary)!
    }

    private func displayPixels(_ image: CGImage) -> [UInt8] {
        let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.displayP3)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return Array(UnsafeBufferPointer(start: context.data!.assumingMemoryBound(to: UInt8.self), count: image.width * image.height * 4))
    }

    func testSixteenBitMaskIsRewrittenAsEightBitWithTheSamePixels() {
        let path = writePNG(patternMask(bitsPerComponent: 16), name: "light_isDark__0.png")
        XCTAssertEqual(imageChannelDepth(atPath: path), 16)
        let before = decode(path)
        let pixelsBefore = displayPixels(before)

        XCTAssertTrue(rewritePNGWithEightBitChannels(atPath: path))

        XCTAssertEqual(imageChannelDepth(atPath: path), 8)
        let after = decode(path)
        XCTAssertEqual(after.width, before.width)
        XCTAssertEqual(after.height, before.height)
        XCTAssertEqual(after.colorSpace?.name, before.colorSpace?.name)
        XCTAssertEqual(after.bytesPerRow * after.height * 2, before.bytesPerRow * before.height, "the decoded wallpaper takes half the memory")

        let pixelsAfter = displayPixels(after)
        var maxDifference = 0
        for i in 0 ..< pixelsBefore.count {
            maxDifference = max(maxDifference, abs(Int(pixelsBefore[i]) - Int(pixelsAfter[i])))
        }
        XCTAssertLessThanOrEqual(maxDifference, 1)
        XCTAssertGreaterThan(Set(pixelsAfter).count, 50, "the fixture has real anti-aliased alpha")
        XCTAssertFalse(FileManager.default.fileExists(atPath: path + ".8bit"))
    }

    func testEightBitFilesAreLeftAlone() throws {
        let path = writePNG(patternMask(bitsPerComponent: 8), name: "dark_isDark__1.png")
        let bytes = try Data(contentsOf: URL(fileURLWithPath: path))
        XCTAssertFalse(rewritePNGWithEightBitChannels(atPath: path))
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: path)), bytes)
        XCTAssertNil(imageWithEightBitChannels(decode(path)))
    }

    func testMigrationRewritesOnlySixteenBitPNGs() throws {
        let sixteen = writePNG(patternMask(bitsPerComponent: 16), name: "a_isDark__0.png")
        let eight = writePNG(patternMask(bitsPerComponent: 8), name: "a_isDark__1.png")
        let metadata = directory + "/a-gift-metadata.json"
        try Data("{}".utf8).write(to: URL(fileURLWithPath: metadata))
        let eightBytes = try Data(contentsOf: URL(fileURLWithPath: eight))

        XCTAssertEqual(migrateWallpapersToEightBitChannels(directory: directory), 1)
        XCTAssertEqual(imageChannelDepth(atPath: sixteen), 8)
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: eight)), eightBytes)
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: metadata)), Data("{}".utf8))
        XCTAssertEqual(migrateWallpapersToEightBitChannels(directory: directory), 0, "a second launch has nothing to do")
    }

    func testMissingDirectoryIsHarmless() {
        XCTAssertEqual(migrateWallpapersToEightBitChannels(directory: directory + "/missing"), 0)
    }
}
