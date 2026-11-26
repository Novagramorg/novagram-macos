import AppKit
import XCTest
import func TGUIKit.imageRequiresInversion
@testable import func TGUIKit.imageHasTransparency
import func TGUIKit.analysisLabSamplingSize
import func TGUIKit.generateTintedImage
import struct TGUIKit.System
import struct TGUIKit.DeviceGraphicsContextSettings
import func TGUIKitBaseline.imageRequiresInversion
import func TGUIKitBaseline.analysisLabSamplingSize
import func TGUIKitBaseline.generateTintedImage
import struct TGUIKitBaseline.System

final class AnalysisIntegrationTests: XCTestCase {
    private func bytes(_ image: CGImage) throws -> Data {
        let context = try XCTUnwrap(CGContext(data: nil, width: 32, height: 32, bitsPerComponent: 8, bytesPerRow: 128, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
        context.clear(CGRect(x: 0, y: 0, width: 32, height: 32))
        context.draw(image, in: CGRect(x: 0, y: 0, width: 32, height: 32))
        return Data(bytes: try XCTUnwrap(context.data), count: 4096)
    }

    func testActualTintPipelinePreservesVisibleArtwork() throws {
        TGUIKit.System.updateScaleFactor(1)
        TGUIKitBaseline.System.updateScaleFactor(1)
        for subject in [Pixel.black, Pixel.white, Pixel(255, 0, 0)] {
            let image = try fixture(width: 32, height: 32) { x, y in x >= 14 && x < 18 && y >= 14 && y < 18 ? subject : .clear }
            let old = TGUIKitBaseline.imageRequiresInversion(image) ? try XCTUnwrap(TGUIKitBaseline.generateTintedImage(image: image, color: .blue)) : image
            let new = TGUIKit.imageRequiresInversion(image) ? try XCTUnwrap(TGUIKit.generateTintedImage(image: image, color: .blue)) : image
            let actual = try bytes(new)
            let expectedCenter: [UInt8] = subject.red == 0 ? [0, 0, 255, 255] : subject.green == 255 ? [255, 255, 255, 255] : [255, 0, 0, 255]
            XCTAssertEqual(Array(actual[(16 * 128 + 16 * 4)..<(16 * 128 + 16 * 4 + 4)]), expectedCenter)
            XCTAssertEqual(Array(actual.prefix(4)), [0, 0, 0, 0])
            if subject.red == 0 { XCTAssertEqual(try bytes(old), actual) }
            else { XCTAssertNotEqual(try bytes(old), actual); XCTAssertEqual(actual, try bytes(image)) }
        }
    }

    func testSamplingDimensionsMatchTheExistingPath() throws {
        for (width, height) in [(16, 16), (2048, 32), (32, 2048), (128, 512), (512, 128), (129, 1024), (513, 129), (512, 512)] {
            let image = try fixture(width: width, height: height) { _, _ in .black }
            XCTAssertEqual(TGUIKit.analysisLabSamplingSize(image), TGUIKitBaseline.analysisLabSamplingSize(image))
        }
    }

    func testClassificationDoesNotDependOnInstalledDrawingFormat() throws {
        defer { TGUIKit.DeviceGraphicsContextSettings.install(nil) }
        let dark = try fixture(width: 32, height: 32) { x, _ in x == 0 ? .clear : .black }
        let white = try fixture(width: 32, height: 32) { x, _ in x == 0 ? .clear : .white }
        for space in [CGColorSpaceCreateDeviceRGB(), try XCTUnwrap(CGColorSpace(name: CGColorSpace.displayP3))] {
            for alpha in [CGImageAlphaInfo.premultipliedFirst, .premultipliedLast] {
                let context = try XCTUnwrap(CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 32, space: space, bitmapInfo: alpha.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
                TGUIKit.DeviceGraphicsContextSettings.install(context)
                XCTAssertTrue(TGUIKit.imageRequiresInversion(dark))
                XCTAssertFalse(TGUIKit.imageRequiresInversion(white))
            }
        }
    }

    func testRandomizedColorAndAlphaDistributionsMatchVisibleSubjects() throws {
        var state: UInt64 = 0x326ab548e8
        func next(_ bound: Int) -> Int { state = state &* 6364136223846793005 &+ 1442695040888963407; return Int((state >> 32) % UInt64(bound)) }
        let spaces = [CGColorSpaceCreateDeviceRGB(), try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB)), try XCTUnwrap(CGColorSpace(name: CGColorSpace.displayP3))]
        for iteration in 0..<512 {
            let width = 1 + next(31), height = 1 + next(19), proportion = next(101)
            var matching = 0, total = 0
            var transparency = false
            let image = try fixture(width: width, height: height, format: PixelFormat.allCases[iteration % 8], space: spaces[iteration % 3]) { _, _ in
                let alpha: UInt8 = [0, 32, 128, 255][next(4)]
                let dark = next(100) < proportion
                if alpha < 255 { transparency = true }
                if alpha > 0 { total += 1; if dark { matching += 1 } }
                if dark { return Pixel(20, 20, 20, alpha) }
                return next(2) == 0 ? Pixel(240, 240, 240, alpha) : Pixel(220, 0, 0, alpha)
            }
            XCTAssertEqual(TGUIKit.imageHasTransparency(image), transparency)
            XCTAssertEqual(TGUIKit.imageRequiresInversion(image), transparency && total > 0 && Double(matching) / Double(total) > 0.85, "Randomized case \(iteration)")
        }
    }

    func testConcurrentClassificationIsDeterministic() throws {
        let images = try [Pixel.black, .white, Pixel(220, 0, 0), Pixel(255, 255, 255, 32)].map { color in try fixture(width: 128, height: 128) { x, y in x > 30 && x < 90 && y > 30 && y < 90 ? color : .clear } }
        let lock = NSLock()
        var failures: [Int] = []
        DispatchQueue.concurrentPerform(iterations: 400) { iteration in
            let index = iteration % images.count
            if TGUIKit.imageRequiresInversion(images[index]) != (index == 0) {
                lock.lock(); failures.append(iteration); lock.unlock()
            }
        }
        XCTAssertTrue(failures.isEmpty)
    }
    func testImageMasksAndDecodeArraysAreAppliedBeforeClassification() throws {
        let source = try fixture(width: 32, height: 32) { _, _ in .black }
        var maskData = Data(repeating: 255, count: 1024)
        for y in 14..<18 { for x in 14..<18 { maskData[y * 32 + x] = 0 } }
        let maskProvider = try XCTUnwrap(CGDataProvider(data: maskData as CFData))
        let mask = try XCTUnwrap(CGImage(maskWidth: 32, height: 32, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: 32, provider: maskProvider, decode: nil, shouldInterpolate: false))
        let masked = try XCTUnwrap(source.masking(mask))
        XCTAssertTrue(TGUIKit.imageHasTransparency(masked))
        XCTAssertTrue(TGUIKit.imageRequiresInversion(masked))
        let white = try fixture(width: 32, height: 32, format: .rgba) { x, _ in x == 0 ? .clear : .white }
        let decode: [CGFloat] = [1, 0, 1, 0, 1, 0]
        let decoded = try decode.withUnsafeBufferPointer { values in
            try XCTUnwrap(CGImage(width: white.width, height: white.height, bitsPerComponent: white.bitsPerComponent, bitsPerPixel: white.bitsPerPixel, bytesPerRow: white.bytesPerRow, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: white.bitmapInfo, provider: try XCTUnwrap(white.dataProvider), decode: values.baseAddress, shouldInterpolate: false, intent: .defaultIntent))
        }
        XCTAssertFalse(TGUIKit.imageRequiresInversion(white))
        XCTAssertTrue(TGUIKit.imageRequiresInversion(decoded))
    }

    func testUnsupportedImageFormatsRemainExcluded() throws {
        let data = Data(repeating: 0, count: 8)
        let provider = try XCTUnwrap(CGDataProvider(data: data as CFData))
        let specifications: [(Int, Int, Int, CGColorSpace, UInt32)] = [
            (8, 8, 1, CGColorSpaceCreateDeviceGray(), CGImageAlphaInfo.none.rawValue),
            (8, 32, 4, CGColorSpaceCreateDeviceRGB(), CGImageAlphaInfo.noneSkipLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
            (16, 64, 8, CGColorSpaceCreateDeviceRGB(), CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder16Big.rawValue)
        ]
        for (componentBits, pixelBits, rowBytes, space, info) in specifications {
            let image = try XCTUnwrap(CGImage(width: 1, height: 1, bitsPerComponent: componentBits, bitsPerPixel: pixelBits, bytesPerRow: rowBytes, space: space, bitmapInfo: CGBitmapInfo(rawValue: info), provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
            XCTAssertFalse(TGUIKit.imageHasTransparency(image))
            XCTAssertFalse(TGUIKit.imageRequiresInversion(image))
        }
    }

}
