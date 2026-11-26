import XCTest
import AppKit
import SwiftSignalKit
import ImageIO
@testable import TextRecognizing

@available(macOS 14.0, *)
final class SubjectLiftingTests: XCTestCase {

    private func drawEmoji(_ emoji: String, size: CGFloat, center: CGPoint, in context: CGContext) {
        let font = NSFont(name: "Apple Color Emoji", size: size) ?? NSFont.systemFont(ofSize: size)
        let string = NSAttributedString(string: emoji, attributes: [.font: font])
        let line = CTLineCreateWithAttributedString(string)
        context.textPosition = .zero
        let bounds = CTLineGetImageBounds(line, context)
        context.textPosition = CGPoint(x: center.x - bounds.midX, y: center.y - bounds.midY)
        CTLineDraw(line, context)
    }

    private func liftSync(_ image: CGImage, at point: CGPoint?) -> TextRecognizing.Subject? {
        let done = DispatchSemaphore(value: 0)
        var subject: TextRecognizing.Subject?
        let disposable = TextRecognizing.liftSubject(image, at: point).start(next: { value in
            subject = value
        }, completed: {
            done.signal()
        })
        _ = done.wait(timeout: .now() + 30)
        disposable.dispose()
        return subject
    }

    private func alpha(_ image: CGImage, x: Int, y: Int) -> UInt8 {
        let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let pixels = context.data!.bindMemory(to: UInt8.self, capacity: image.width * image.height * 4)
        return pixels[(y * image.width + x) * 4 + 3]
    }

    func testLiftsSubjectWithItsFrame() {
        let size = CGSize(width: 1200, height: 900)
        let image = makeCanvas(size) { context in
            context.setFillColor(CGColor(srgbRed: 0.93, green: 0.93, blue: 0.9, alpha: 1))
            context.fill(CGRect(origin: .zero, size: size))
            drawEmoji("🐶", size: 360, center: CGPoint(x: 400, y: 450), in: context)
        }

        guard let subject = liftSync(image, at: nil) else {
            return XCTFail("no subject")
        }
        let frame = CGRect(x: subject.rect.minX * size.width, y: subject.rect.minY * size.height, width: subject.rect.width * size.width, height: subject.rect.height * size.height)
        XCTAssertEqual(frame.midX, 400, accuracy: 40)
        XCTAssertEqual(frame.midY, 450, accuracy: 40)
        XCTAssertLessThan(frame.width, 600)
        XCTAssertEqual(CGFloat(subject.image.width), frame.width, accuracy: 1)
        XCTAssertEqual(CGFloat(subject.image.height), frame.height, accuracy: 1)
        XCTAssertEqual(alpha(subject.image, x: 0, y: 0), 0)
        XCTAssertGreaterThan(alpha(subject.image, x: subject.image.width / 2, y: subject.image.height / 2), 200)
    }

    func testPointPicksTheSubjectUnderIt() {
        let size = CGSize(width: 1400, height: 800)
        let image = makeCanvas(size) { context in
            context.setFillColor(CGColor(srgbRed: 0.93, green: 0.93, blue: 0.9, alpha: 1))
            context.fill(CGRect(origin: .zero, size: size))
            drawEmoji("🐶", size: 300, center: CGPoint(x: 350, y: 400), in: context)
            drawEmoji("🍎", size: 300, center: CGPoint(x: 1050, y: 400), in: context)
        }

        guard let all = liftSync(image, at: nil) else {
            return XCTFail("no subjects")
        }
        guard let right = liftSync(image, at: CGPoint(x: 1050 / size.width, y: 0.5)) else {
            return XCTFail("no right subject")
        }
        let rightFrame = right.rect.applying(CGAffineTransform(scaleX: size.width, y: size.height))
        let allFrame = all.rect.applying(CGAffineTransform(scaleX: size.width, y: size.height))

        XCTAssertGreaterThan(allFrame.width, 900, "both subjects lifted when no point is given")
        XCTAssertGreaterThan(rightFrame.minX, 700, "only the subject under the point is lifted")
        XCTAssertEqual(rightFrame.midX, 1050, accuracy: 40)
    }

    func testZoomedPhotoIsLiftedAtLimitedSize() {
        let size = CGSize(width: 6000, height: 3000)
        let image = makeCanvas(size) { context in
            context.setFillColor(CGColor(srgbRed: 0.93, green: 0.93, blue: 0.9, alpha: 1))
            context.fill(CGRect(origin: .zero, size: size))
            drawEmoji("🐶", size: 1400, center: CGPoint(x: 4500, y: 1500), in: context)
        }
        guard let subject = liftSync(image, at: nil) else {
            return XCTFail("no subject")
        }
        XCTAssertLessThanOrEqual(max(subject.image.width, subject.image.height), 2560)
        XCTAssertEqual(subject.rect.midX * size.width, 4500, accuracy: 150)
        XCTAssertEqual(subject.rect.midY * size.height, 1500, accuracy: 150)
    }
    
    func testEmptyPhotoHasNoSubject() {
        let size = CGSize(width: 600, height: 400)
        let image = makeCanvas(size) { context in
            context.setFillColor(CGColor(srgbRed: 0.5, green: 0.5, blue: 0.5, alpha: 1))
            context.fill(CGRect(origin: .zero, size: size))
        }
        XCTAssertNil(liftSync(image, at: nil))
    }

    func testStickerIsWebPWith512LongSideAndTransparency() throws {
        let cutout = makeCanvas(CGSize(width: 300, height: 600)) { context in
            context.clear(CGRect(x: 0, y: 0, width: 300, height: 600))
            context.setFillColor(CGColor(srgbRed: 0.9, green: 0.2, blue: 0.3, alpha: 1))
            context.fillEllipse(in: CGRect(x: 30, y: 30, width: 240, height: 540))
        }
        let subject = TextRecognizing.Subject(image: cutout, rect: .zero)
        let data = try XCTUnwrap(subject.stickerData())
        XCTAssertEqual(String(data: data.subdata(in: 8 ..< 12), encoding: .ascii), "WEBP")

        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let decoded = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(decoded.width, 256)
        XCTAssertEqual(decoded.height, 512)
        XCTAssertEqual(alpha(decoded, x: 2, y: 2), 0)
        XCTAssertEqual(alpha(decoded, x: 128, y: 256), 255)
    }
}
