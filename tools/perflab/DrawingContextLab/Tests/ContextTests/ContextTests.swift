import Cocoa
import XCTest
import class TGUIKit.DrawingContext
import struct TGUIKit.System
import struct TGUIKit.DeviceGraphicsContextSettings
import func TGUIKit.setDisplayColorSpace
import class TGUIKitBaseline.DrawingContext
import struct TGUIKitBaseline.System
import struct TGUIKitBaseline.DeviceGraphicsContextSettings
import func TGUIKitBaseline.setDisplayColorSpace

final class ContextTests: XCTestCase {
    override func setUp() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        TGUIKit.System.updateScaleFactor(2)
        TGUIKitBaseline.System.updateScaleFactor(2)
        TGUIKit.setDisplayColorSpace(nil)
        TGUIKitBaseline.setDisplayColorSpace(nil)
    }

    func format(_ space: CFString, floating: Bool = false) -> CGContext {
        let info = floating ? CGBitmapInfo.floatComponents.rawValue | CGBitmapInfo.byteOrder16Little.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue : CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
        return CGContext(data: nil, width: 1, height: 1, bitsPerComponent: floating ? 16 : 8, bytesPerRow: 32, space: CGColorSpace(name: space)!, bitmapInfo: info)!
    }

    func paint(_ context: CGContext, size: CGSize) {
        context.setFillColor(CGColor(red: 0.18, green: 0.72, blue: 0.44, alpha: 0.65))
        context.fill(CGRect(x: 0, y: 0, width: size.width * 0.75, height: size.height * 0.6))
        context.setFillColor(CGColor(red: 0.71, green: 0.23, blue: 0.42, alpha: 0.31))
        context.fillEllipse(in: CGRect(x: 1.5, y: 0.5, width: size.width / 2, height: size.height * 0.8))
    }

    func equal(_ a: CGImage, _ b: CGImage, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(a.width, b.width, file: file, line: line)
        XCTAssertEqual(a.height, b.height, file: file, line: line)
        XCTAssertEqual(a.bytesPerRow, b.bytesPerRow, file: file, line: line)
        XCTAssertEqual(a.bitsPerComponent, b.bitsPerComponent, file: file, line: line)
        XCTAssertEqual(a.bitmapInfo, b.bitmapInfo, file: file, line: line)
        XCTAssertTrue(CFEqual(a.colorSpace!, b.colorSpace!), file: file, line: line)
        XCTAssertTrue((a.dataProvider!.data! as Data) == (b.dataProvider!.data! as Data), "Raw bytes differ", file: file, line: line)
    }

    func testStaticFormatPixelsAndGeometryMatch() {
        defer { TGUIKitBaseline.DeviceGraphicsContextSettings.install(nil); TGUIKitBaseline.setDisplayColorSpace(nil); TGUIKit.DeviceGraphicsContextSettings.install(nil) }
        for format in [format(CGColorSpace.sRGB), format(CGColorSpace.displayP3), format(CGColorSpace.extendedLinearSRGB, floating: true)] {
            TGUIKit.DeviceGraphicsContextSettings.install(format)
            TGUIKitBaseline.DeviceGraphicsContextSettings.install(format)
            for size in [CGSize(width: 16, height: 16), CGSize(width: 15.5, height: 23.25), CGSize(width: 0.5, height: 0.25), CGSize(width: 127, height: 65)] {
                for scale: CGFloat in [0, 1, 1.5, 2, 3] {
                    for flip in [false, true] {
                        let old = TGUIKitBaseline.DrawingContext(size: size, scale: scale, clear: true)
                        let new = TGUIKit.DrawingContext(size: size, scale: scale, clear: true)
                        old.withFlippedContext(horizontal: flip, vertical: !flip) { paint($0, size: old.size) }
                        new.withFlippedContext(horizontal: flip, vertical: !flip) { paint($0, size: new.size) }
                        equal(old.generateImage()!, new.generateImage()!)
                        XCTAssertEqual(old.length, new.length)
                        XCTAssertEqual(old.scale, new.scale)
                        XCTAssertEqual(old.isHighQuality, new.isHighQuality)
                    }
                }
            }
        }
    }

    func testExistingContextKeepsItsRenderingColorSpaceAfterSettingsChange() {
        let srgb = format(CGColorSpace.sRGB), p3 = format(CGColorSpace.displayP3)
        TGUIKit.DeviceGraphicsContextSettings.install(srgb)
        TGUIKitBaseline.DeviceGraphicsContextSettings.install(srgb)
        defer { TGUIKitBaseline.DeviceGraphicsContextSettings.install(nil); TGUIKitBaseline.setDisplayColorSpace(nil); TGUIKit.DeviceGraphicsContextSettings.install(nil) }
        let old = TGUIKitBaseline.DrawingContext(size: CGSize(width: 16, height: 16), scale: 2, clear: true)
        let new = TGUIKit.DrawingContext(size: CGSize(width: 16, height: 16), scale: 2, clear: true)
        old.withContext { paint($0, size: old.size) }
        new.withContext { paint($0, size: new.size) }
        let expected = old.generateImage()!
        TGUIKit.DeviceGraphicsContextSettings.install(p3)
        TGUIKitBaseline.DeviceGraphicsContextSettings.install(p3)
        let incorrectlyTagged = old.generateImage()!
        XCTAssertFalse(CFEqual(expected.colorSpace!, incorrectlyTagged.colorSpace!))
        equal(new.generateImage()!, expected)
        equal(new.generateDisplayImage()!, expected)
    }

    func testDisplayConversionMatchesOriginal() {
        TGUIKit.DeviceGraphicsContextSettings.install(format(CGColorSpace.sRGB))
        TGUIKitBaseline.DeviceGraphicsContextSettings.install(format(CGColorSpace.sRGB))
        defer { TGUIKitBaseline.DeviceGraphicsContextSettings.install(nil); TGUIKitBaseline.setDisplayColorSpace(nil); TGUIKit.DeviceGraphicsContextSettings.install(nil); TGUIKit.setDisplayColorSpace(nil) }
        TGUIKit.setDisplayColorSpace(CGColorSpace(name: CGColorSpace.displayP3))
        TGUIKitBaseline.setDisplayColorSpace(CGColorSpace(name: CGColorSpace.displayP3))
        for size in [CGSize(width: 16, height: 16), CGSize(width: 127, height: 65)] {
            for scale: CGFloat in [1, 2, 3] {
                let old = TGUIKitBaseline.DrawingContext(size: size, scale: scale, clear: true)
                let new = TGUIKit.DrawingContext(size: size, scale: scale, clear: true)
                old.withContext { paint($0, size: size) }
                new.withContext { paint($0, size: size) }
                let expected = old.generateDisplayImage()!
                XCTAssertTrue(CFEqual(expected.colorSpace!, CGColorSpace(name: CGColorSpace.displayP3)!))
                equal(new.generateDisplayImage()!, expected)
            }
        }
    }

    func testConcurrentFormatChangesKeepEachContextInternallyConsistent() {
        let a = format(CGColorSpace.sRGB), b = format(CGColorSpace.extendedLinearSRGB, floating: true)
        TGUIKit.DeviceGraphicsContextSettings.install(a)
        TGUIKitBaseline.DeviceGraphicsContextSettings.install(a)
        defer { TGUIKitBaseline.DeviceGraphicsContextSettings.install(nil); TGUIKitBaseline.setDisplayColorSpace(nil); TGUIKit.DeviceGraphicsContextSettings.install(nil) }
        let lock = NSLock()
        var mismatches = 0
        DispatchQueue.concurrentPerform(iterations: 5) { worker in
            if worker == 0 {
                for index in 0..<2000 { TGUIKit.DeviceGraphicsContextSettings.install(index % 2 == 0 ? a : b) }
            } else {
                for _ in 0..<500 {
                    autoreleasepool {
                        let context = TGUIKit.DrawingContext(size: CGSize(width: 16, height: 16), scale: 2, clear: true)
                        context.withContext { paint($0, size: context.size) }
                        let image = context.generateImage()!
                        let expectedSpace = image.bitsPerComponent == 8 ? a.colorSpace! : b.colorSpace!
                        if context.length != image.bytesPerRow * image.height || !CFEqual(image.colorSpace!, expectedSpace) || ![8, 16].contains(image.bitsPerComponent) {
                            lock.lock(); mismatches += 1; lock.unlock()
                        }
                    }
                }
            }
        }
        XCTAssertEqual(mismatches, 0)
    }

    func testImageKeepsPixelsAliveAfterContextRelease() {
        let image: CGImage = autoreleasepool {
            let context = TGUIKit.DrawingContext(size: CGSize(width: 15, height: 17), scale: 2, clear: true)
            context.withContext { paint($0, size: context.size) }
            return context.generateImage()!
        }
        let reference = TGUIKitBaseline.DrawingContext(size: CGSize(width: 15, height: 17), scale: 2, clear: true)
        reference.withContext { paint($0, size: reference.size) }
        equal(image, reference.generateImage()!)
    }
}
