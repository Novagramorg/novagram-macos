import XCTest
import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftSignalKit
@testable import TGUIKit
@testable import TextRecognizing

func makeCanvas(_ size: CGSize, draw: (CGContext) -> Void) -> CGImage {
    let context = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    draw(context)
    return context.makeImage()!
}

func makeQRCode(_ payload: String, side: CGFloat) -> CGImage {
    let filter = CIFilter.qrCodeGenerator()
    filter.message = payload.data(using: .utf8)!
    filter.correctionLevel = "M"
    let output = filter.outputImage!
    let scale = side / output.extent.width
    let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    return CIContext().createCGImage(scaled, from: scaled.extent)!
}

func drawQRCode(_ code: CGImage, in context: CGContext, center: CGPoint, rotation: CGFloat = 0) {
    context.saveGState()
    context.translateBy(x: center.x, y: center.y)
    context.rotate(by: rotation)
    let side = CGFloat(code.width)
    let quiet: CGFloat = side * 0.12
    context.setFillColor(CGColor(gray: 1, alpha: 1))
    context.fill(CGRect(x: -side / 2 - quiet, y: -side / 2 - quiet, width: side + quiet * 2, height: side + quiet * 2))
    context.interpolationQuality = .none
    context.draw(code, in: CGRect(x: -side / 2, y: -side / 2, width: side, height: side))
    context.restoreGState()
}

func photoBackground(_ context: CGContext, _ size: CGSize) {
    let colors = [CGColor(srgbRed: 0.85, green: 0.64, blue: 0.25, alpha: 1), CGColor(srgbRed: 0.18, green: 0.43, blue: 0.56, alpha: 1)] as CFArray
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!, colors: colors, locations: [0, 1])!
    context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])
}

func recognizeSync(_ image: CGImage, timeout: TimeInterval = 30) -> TextRecognizing.Result? {
    let done = DispatchSemaphore(value: 0)
    var finished: TextRecognizing.Result?
    let disposable = TextRecognizing.recognize(image, postbox: nil, stableId: nil).start(next: { result in
        if case .finish = result {
            finished = result
        }
    }, error: { _ in
        done.signal()
    }, completed: {
        done.signal()
    })
    _ = done.wait(timeout: .now() + timeout)
    disposable.dispose()
    return finished
}

final class BarcodeRecognitionTests: XCTestCase {

    func testFindsQRCodeWithPayloadAndPosition() {
        let size = CGSize(width: 1200, height: 900)
        let code = makeQRCode("https://t.me/telegram", side: 240)
        let image = makeCanvas(size) { context in
            photoBackground(context, size)
            drawQRCode(code, in: context, center: CGPoint(x: 900, y: 300))
        }

        guard let result = recognizeSync(image) else {
            return XCTFail("no result")
        }
        XCTAssertEqual(result.barcodes.count, 1)
        guard let barcode = result.barcodes.first else {
            return
        }
        XCTAssertEqual(barcode.payload, "https://t.me/telegram")
        XCTAssertEqual(barcode.link, "https://t.me/telegram")

        let bounds = barcode.bounds(viewSize: size)
        XCTAssertEqual(bounds.midX, 900, accuracy: 12)
        XCTAssertEqual(bounds.midY, 300, accuracy: 12)
        XCTAssertEqual(bounds.width, 240, accuracy: 24)
    }

    func testFindsRotatedQRCode() {
        let size = CGSize(width: 1000, height: 1000)
        let code = makeQRCode("tg://resolve?domain=durov", side: 260)
        let image = makeCanvas(size) { context in
            photoBackground(context, size)
            drawQRCode(code, in: context, center: CGPoint(x: 500, y: 520), rotation: .pi / 9)
        }

        guard let barcode = recognizeSync(image)?.barcodes.first else {
            return XCTFail("no barcode")
        }
        XCTAssertEqual(barcode.payload, "tg://resolve?domain=durov")
        let corners = barcode.corners(viewSize: size)
        let angle = atan2(corners[1].y - corners[0].y, corners[1].x - corners[0].x)
        XCTAssertEqual(angle, .pi / 9, accuracy: 0.08)
    }

    func testPhotoWithoutQRCodeHasNoBarcodes() {
        let size = CGSize(width: 800, height: 600)
        let image = makeCanvas(size) { context in
            photoBackground(context, size)
        }
        guard let result = recognizeSync(image) else {
            return XCTFail("no result")
        }
        XCTAssertTrue(result.barcodes.isEmpty)
    }

    func testLinkClassification() {
        func link(_ payload: String) -> String? {
            return TextRecognizing.Result.Barcode(payload: payload, topLeft: .zero, topRight: .zero, bottomLeft: .zero, bottomRight: .zero).link
        }
        XCTAssertEqual(link("https://telegram.org/"), "https://telegram.org/")
        XCTAssertEqual(link("  https://t.me/durov\n"), "https://t.me/durov")
        XCTAssertEqual(link("tg://login?token=abc"), "tg://login?token=abc")
        XCTAssertEqual(link("ton://transfer/EQ123"), "ton://transfer/EQ123")
        XCTAssertEqual(link("t.me/durov"), "http://t.me/durov")
        XCTAssertNil(link("WIFI:S:Home;T:WPA;P:secret;;"))
        XCTAssertNil(link("Hello, visit telegram.org today"))
        XCTAssertNil(link("4006381333931"))
        XCTAssertNil(link("javascript:alert(1)"))
    }

    func testChipText() {
        func text(_ payload: String) -> String {
            return BarcodeOverlay.displayText(TextRecognizing.Result.Barcode(payload: payload, topLeft: .zero, topRight: .zero, bottomLeft: .zero, bottomRight: .zero))
        }
        XCTAssertEqual(text("https://t.me/durov"), "t.me/durov")
        XCTAssertEqual(text("HTTPS://Telegram.org/"), "Telegram.org")
        XCTAssertEqual(text("tg://resolve?domain=durov"), "tg://resolve?domain=durov")
        XCTAssertEqual(text("WIFI:S:Home;T:WPA;P:secret;;"), "WIFI:S:Home;T:WPA;P:secret;;")
        XCTAssertEqual(text("\nfirst line\nsecond"), "first line")
    }
}
