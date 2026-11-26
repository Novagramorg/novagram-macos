import XCTest
import AppKit
@testable import TGUIKit
@testable import TextRecognizing

final class RecognitionSnapshotTests: XCTestCase {

    private var directory: URL!

    override func setUpWithError() throws {
        _ = TestBootstrap.installed
        guard let path = ProcessInfo.processInfo.environment["RECOGNITION_SNAPSHOTS"] else {
            throw XCTSkip("set TEST_RUNNER_RECOGNITION_SNAPSHOTS to a folder to write snapshots")
        }
        directory = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func snapshot(_ name: String, photo: CGImage, size: NSSize, configure: (TextRecognizing.ImageTextSelector) -> Void) throws {
        let window = NSWindow(contentRect: NSMakeRect(0, 0, size.width, size.height), styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        let content = NSView(frame: NSMakeRect(0, 0, size.width, size.height))
        content.wantsLayer = true
        content.layer?.contents = photo
        window.contentView = content

        let selector = TextRecognizing.ImageTextSelector(frame: content.bounds)
        content.addSubview(selector)
        configure(selector)
        selector.needsLayout = true
        selector.layoutSubtreeIfNeeded()
        CATransaction.flush()

        let scale: CGFloat = 2
        let context = CGContext(data: nil, width: Int(size.width * scale), height: Int(size.height * scale), bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.scaleBy(x: scale, y: scale)
        content.layer!.render(in: context)
        let image = context.makeImage()!
        let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
        try data.write(to: directory.appendingPathComponent("\(name).png"))
    }

    private func photo(_ size: CGSize, codes: [(String, CGPoint, CGFloat, CGFloat)]) -> CGImage {
        return makeCanvas(size) { context in
            photoBackground(context, size)
            for (payload, center, side, rotation) in codes {
                drawQRCode(makeQRCode(payload, side: side), in: context, center: center, rotation: rotation)
            }
        }
    }

    func testSnapshots() throws {
        let size = NSMakeSize(900, 600)

        let centered = photo(size, codes: [("https://t.me/telegram", CGPoint(x: 450, y: 330), 180, 0)])
        let centeredResult = try XCTUnwrap(recognizeSync(centered))
        try snapshot("1-idle", photo: centered, size: size) { selector in
            selector.set(centeredResult)
        }
        try snapshot("2-hover", photo: centered, size: size) { selector in
            selector.set(centeredResult)
            selector.updateBarcodeProximity(NSMakePoint(450, 330), animated: false)
            selector.barcodeOverlays.first?.area.controlState = .Hover
        }

        let bottom = photo(size, codes: [("https://telegram.org/blog/a-very-long-article-name-that-keeps-going", CGPoint(x: 120, y: 95), 150, 0)])
        try snapshot("3-bottom-edge", photo: bottom, size: size) { selector in
            selector.set(try? XCTUnwrap(recognizeSync(bottom)))
            selector.barcodeOverlays.forEach { $0.reveal(true, animated: false) }
        }

        let wifi = photo(size, codes: [("WIFI:S:Home Network;T:WPA;P:secret;;", CGPoint(x: 640, y: 380), 200, .pi / 10), ("https://t.me/durov", CGPoint(x: 220, y: 380), 140, -.pi / 14)])
        try snapshot("4-rotated-two-codes", photo: wifi, size: size) { selector in
            selector.set(try? XCTUnwrap(recognizeSync(wifi)))
            selector.barcodeOverlays.forEach { $0.reveal(true, animated: false) }
        }

        if #available(macOS 14.0, *) {
            let pet = makeCanvas(size) { context in
                photoBackground(context, size)
                let font = NSFont(name: "Apple Color Emoji", size: 300)!
                let line = CTLineCreateWithAttributedString(NSAttributedString(string: "🐶", attributes: [.font: font]))
                context.textPosition = CGPoint(x: 300, y: 160)
                CTLineDraw(line, context)
            }
            let done = expectation(description: "lift")
            var lifted: TextRecognizing.Subject?
            _ = TextRecognizing.liftSubject(pet, at: nil).start(next: { lifted = $0 }, completed: { done.fulfill() })
            wait(for: [done], timeout: 30)
            let subject = try XCTUnwrap(lifted)
            try snapshot("5-subject-lift", photo: pet, size: size) { selector in
                selector.showLiftedSubject(subject.image, rect: subject.rect, completion: {})
            }
            let sticker = try XCTUnwrap(subject.stickerData())
            try sticker.write(to: directory.appendingPathComponent("6-sticker.webp"))
        }
    }
}
