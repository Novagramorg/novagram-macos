import XCTest
import AppKit
@testable import TGUIKit
@testable import TextRecognizing

final class BarcodeOverlayTests: XCTestCase {

    override func setUp() {
        super.setUp()
        _ = TestBootstrap.installed
    }

    private func barcode(_ payload: String, rect: CGRect) -> TextRecognizing.Result.Barcode {
        return TextRecognizing.Result.Barcode(payload: payload, topLeft: CGPoint(x: rect.minX, y: rect.maxY), topRight: CGPoint(x: rect.maxX, y: rect.maxY), bottomLeft: CGPoint(x: rect.minX, y: rect.minY), bottomRight: CGPoint(x: rect.maxX, y: rect.minY))
    }

    private func selector(size: NSSize, barcodes: [TextRecognizing.Result.Barcode]) -> TextRecognizing.ImageTextSelector {
        let view = TextRecognizing.ImageTextSelector(frame: NSMakeRect(0, 0, size.width, size.height))
        let image = makeCanvas(size) { context in
            photoBackground(context, size)
        }
        view.set(.finish(image: image, text: [], barcodes: barcodes))
        view.layoutSubtreeIfNeeded()
        return view
    }

    private func controls(_ view: TextRecognizing.ImageTextSelector) -> [Control] {
        return view.barcodeOverlays.flatMap { [$0.area, $0.chip] as [Control] }
    }

    func testChipSitsBelowCodeAndOpensIt() {
        let code = barcode("https://t.me/durov", rect: CGRect(x: 0.4, y: 0.4, width: 0.2, height: 0.2))
        let view = selector(size: NSMakeSize(1000, 800), barcodes: [code])
        var opened: [String] = []
        view.openBarcode = { opened.append($0.payload) }

        let controls = self.controls(view)
        XCTAssertEqual(controls.count, 2)
        let area = controls[0]
        let chip = controls[1]

        XCTAssertEqual(area.frame, NSMakeRect(392, 312, 216, 176))
        XCTAssertEqual(chip.frame.maxY, 320 - 24)
        XCTAssertTrue(area.superview === view && chip.superview === view)
        XCTAssertEqual(chip.frame.midX, 500, accuracy: 1)
        XCTAssertEqual(chip.frame.height, 28)

        area.send(event: .Click)
        chip.send(event: .Click)
        XCTAssertEqual(opened, ["https://t.me/durov", "https://t.me/durov"])
    }

    func testChipMovesAboveWhenCodeTouchesBottom() {
        let code = barcode("https://telegram.org", rect: CGRect(x: 0.1, y: 0.0, width: 0.2, height: 0.2))
        let view = selector(size: NSMakeSize(1000, 800), barcodes: [code])
        let chip = controls(view)[1]
        XCTAssertEqual(chip.frame.minY, 160 + 24)
    }

    func testChipStaysInsideWhenCodeFillsPhoto() {
        let code = barcode("https://telegram.org", rect: CGRect(x: 0, y: 0, width: 1, height: 1))
        let view = selector(size: NSMakeSize(400, 400), barcodes: [code])
        let chip = controls(view)[1]
        XCTAssertEqual(chip.frame.midY, 200, accuracy: 1)
        XCTAssertGreaterThanOrEqual(chip.frame.minX, 6)
        XCTAssertLessThanOrEqual(chip.frame.maxX, 394)
    }

    func testChipIsClampedToPhotoEdges() {
        let code = barcode("https://example.com/a/very/long/path/that/will/not/fit/in/the/chip/at/all/even/when/truncated", rect: CGRect(x: 0.9, y: 0.5, width: 0.1, height: 0.1))
        let view = selector(size: NSMakeSize(500, 500), barcodes: [code])
        let chip = controls(view)[1]
        XCTAssertLessThanOrEqual(chip.frame.maxX, 494)
        XCTAssertLessThanOrEqual(chip.frame.width, 280)
    }

    func testChipShowsOnlyWhilePointerIsNearTheCode() {
        let code = barcode("https://t.me/durov", rect: CGRect(x: 0.4, y: 0.4, width: 0.2, height: 0.2))
        let view = selector(size: NSMakeSize(1000, 800), barcodes: [code])
        let overlay = view.barcodeOverlays[0]
        XCTAssertTrue(overlay.chip.isHidden)
        XCTAssertFalse(overlay.isRevealed)
        
        view.updateBarcodeProximity(NSMakePoint(100, 100), animated: false)
        XCTAssertTrue(overlay.chip.isHidden)
        
        view.updateBarcodeProximity(NSMakePoint(500, 400), animated: false)
        XCTAssertFalse(overlay.chip.isHidden)
        XCTAssertEqual(overlay.chip.layer?.opacity, 1)
        
        view.updateBarcodeProximity(NSMakePoint(392 - 20, 400), animated: false)
        XCTAssertTrue(overlay.isRevealed, "close to the code counts")
        
        view.updateBarcodeProximity(NSMakePoint(500, overlay.chip.frame.minY + 2), animated: false)
        XCTAssertTrue(overlay.isRevealed, "moving onto the chip keeps it")
        
        view.updateBarcodeProximity(NSMakePoint(100, 100), animated: false)
        XCTAssertTrue(overlay.chip.isHidden)
        XCTAssertEqual(overlay.chip.layer?.opacity, 0)
        
        view.updateBarcodeProximity(NSMakePoint(500, overlay.chip.frame.minY + 2), animated: false)
        XCTAssertFalse(overlay.isRevealed, "the hidden chip's spot does not reveal it")
        
        view.updateBarcodeProximity(NSMakePoint(500, 400), animated: false)
        view.updateBarcodeProximity(nil, animated: false)
        XCTAssertFalse(overlay.isRevealed, "leaving the photo hides it")
    }
    
    func testHiddenChipDoesNotTakeClicksOrCursor() {
        let code = barcode("https://t.me/durov", rect: CGRect(x: 0.4, y: 0.4, width: 0.2, height: 0.2))
        let view = selector(size: NSMakeSize(1000, 800), barcodes: [code])
        let overlay = view.barcodeOverlays[0]
        let onChip = NSMakePoint(overlay.chip.frame.midX, overlay.chip.frame.midY)
        XCTAssertFalse(overlay.contains(onChip))
        XCTAssertFalse(view.hitTest(onChip) === overlay.chip)
        XCTAssertTrue(overlay.contains(NSMakePoint(500, 400)))
        
        overlay.reveal(true, animated: false)
        XCTAssertTrue(overlay.contains(onChip))
        XCTAssertTrue(view.hitTest(onChip) === overlay.chip)
    }
    
    func testHoverOnAreaOrChipShowsOutline() {
        let code = barcode("https://t.me/durov", rect: CGRect(x: 0.4, y: 0.4, width: 0.2, height: 0.2))
        let overlay = selector(size: NSMakeSize(1000, 800), barcodes: [code]).barcodeOverlays[0]
        XCTAssertEqual(overlay.area.outline.opacity, 0)
        overlay.chip.controlState = .Hover
        XCTAssertEqual(overlay.area.outline.opacity, 1)
        overlay.chip.controlState = .Normal
        XCTAssertEqual(overlay.area.outline.opacity, 0)
        overlay.area.controlState = .Highlight
        XCTAssertEqual(overlay.area.outline.opacity, 1)
    }

    func testOverlaysFollowResult() {
        let code = barcode("https://t.me/durov", rect: CGRect(x: 0.4, y: 0.4, width: 0.2, height: 0.2))
        let view = selector(size: NSMakeSize(1000, 800), barcodes: [code])
        XCTAssertEqual(controls(view).count, 2)

        let first = controls(view)
        view.set(.finish(image: makeCanvas(NSMakeSize(10, 10)) { _ in }, text: [], barcodes: [code]))
        XCTAssertTrue(controls(view).elementsEqual(first, by: ===))

        view.set(nil)
        XCTAssertTrue(view.barcodeOverlays.isEmpty)
    }

    func testLayoutFollowsResize() {
        let code = barcode("https://t.me/durov", rect: CGRect(x: 0.4, y: 0.4, width: 0.2, height: 0.2))
        let view = selector(size: NSMakeSize(1000, 800), barcodes: [code])
        view.setFrameSize(NSMakeSize(500, 400))
        view.needsLayout = true
        view.layoutSubtreeIfNeeded()
        XCTAssertEqual(controls(view)[0].frame, NSMakeRect(192, 152, 116, 96))
    }

    func testNormalizedPoint() {
        let view = TextRecognizing.ImageTextSelector(frame: NSMakeRect(0, 0, 400, 200))
        let window = NSWindow(contentRect: NSMakeRect(0, 0, 600, 400), styleMask: [.borderless], backing: .buffered, defer: true)
        window.contentView?.addSubview(view)
        view.setFrameOrigin(NSMakePoint(100, 50))
        let point = view.normalizedPoint(fromWindow: NSMakePoint(200, 200))
        XCTAssertEqual(point?.x ?? -1, 0.25, accuracy: 0.001)
        XCTAssertEqual(point?.y ?? -1, 0.75, accuracy: 0.001)
        XCTAssertNil(view.normalizedPoint(fromWindow: NSMakePoint(50, 50)))
    }
}
