#if canImport(AppKit)
import XCTest
import AppKit
@testable import RichTextEditorUI
import RichTextEditorCore

/// Orientation de-risk gate: proves that ImageBlockBox draws NSImage right-side-up in a flipped
/// (y-down) NSView. Uses a real flipped NSView + cacheDisplay so `NSGraphicsContext.current?.isFlipped`
/// is true, matching the production canvas.  This test MUST pass before the canvas batch.
@available(macOS 12, *)
final class ImageBlockBoxOrientationTests: AppKitTestCase {
    /// A minimal flipped NSView that draws an ImageBlockBox directly in its draw(_:).
    private final class ImageDrawView: NSView {
        let box: ImageBlockBox
        let testImage: NSImage
        override var isFlipped: Bool { true }
        init(box: ImageBlockBox, image: NSImage, frame: NSRect) {
            self.box = box; self.testImage = image
            super.init(frame: frame)
        }
        required init?(coder: NSCoder) { fatalError() }
        override func draw(_ dirtyRect: NSRect) {
            guard let ctx = NSGraphicsContext.current?.cgContext else { return }
            NSColor.white.setFill(); bounds.fill()
            box.draw(in: ctx, imageProvider: { _ in self.testImage })
        }
    }

    func test_imageDraw_notMirrored_inFlippedView() {
        // Build a 100x100 NSImage: top half teal, bottom half orange.
        // In lockFocus y-up coords: y=50..100 = visual top (teal), y=0..50 = visual bottom (orange).
        let imgSize = CGSize(width: 100, height: 100)
        let img = NSImage(size: imgSize)
        img.lockFocus()
        NSColor.systemTeal.setFill()
        NSRect(x: 0, y: 50, width: 100, height: 50).fill()   // visual top half
        NSColor.systemOrange.setFill()
        NSRect(x: 0, y: 0, width: 100, height: 50).fill()    // visual bottom half
        img.unlockFocus()

        // Build ImageBlockBox. Key: canvasWidth = layoutWidth + pageMargin*2.
        // To keep the image at exactly its natural size (100x100), set
        // layoutWidth = naturalWidth - 2*pageMargin = 100 - 32 = 68.
        // Then canvasWidth = 68 + 32 = 100 = natural width → no scaling; imageAreaHeight = 100.
        // imageRect: x = frame.minX - pageMargin = 0 - 16 = -16, y = verticalInset = 8, w=100, h=100.
        let pageMargin: CGFloat = CanvasMetrics.pageMargin   // 16
        let layoutWidth: CGFloat = max(imgSize.width - pageMargin * 2, 1)   // ≈ 68
        let block = RichTextEditorUI.MediaBlock(id: BlockID("img"), kind: .image, mediaID: "x",
                               naturalSize: Size2D(width: Double(imgSize.width), height: Double(imgSize.height)),
                               caption: [])
        let box = ImageBlockBox(media: block, mapper: AttributedStringMapper(), width: layoutWidth)
        box.nodeStart = 1
        // Frame height = verticalInset + imageAreaHeight + captionGap + captionHeight + verticalInset
        //             = 8 + 100 + 4 + 0 + 8 = 120
        let frameH: CGFloat = box.height  // computed from the layout
        box.frame = CGRect(x: 0, y: 0, width: layoutWidth, height: frameH)

        // Verify the expected imageRect geometry.
        let ir = box.imageRect()
        // The image should be at y = verticalInset = 8, height ≈ 100.
        XCTAssertEqual(ir.minY, 8, accuracy: 1.0, "imageRect should start at verticalInset")
        XCTAssertEqual(ir.height, imgSize.height, accuracy: 1.0, "imageRect height should match natural image height")

        // Draw in a real flipped NSView.
        let viewFrame = CGRect(x: 0, y: 0, width: layoutWidth, height: frameH)
        let view = ImageDrawView(box: box, image: img, frame: viewFrame)
        let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
        view.cacheDisplay(in: view.bounds, to: rep)

        // colorAt(x:y:) uses y-down (y=0=TOP of bitmap). The bitmap may be 2x (Retina),
        // so pixel rows = point rows * scale. The rep's pixelsHigh gives the actual pixel count.
        // imageRect starts at y=8pt (visually, in the flipped y-down view).
        // Image occupies y=8..(8+100)=108 in point coords.
        // Top half of image: y=8..58 (midpoint ≈ 33pt).
        // Bottom half of image: y=58..108 (midpoint ≈ 83pt).
        // Scale: rep.pixelsHigh / frameH
        let scale = CGFloat(rep.pixelsHigh) / frameH
        let topRow = Int((8 + 25) * scale)    // midpoint of top half of image (25pt into image)
        let bottomRow = Int((8 + 75) * scale) // midpoint of bottom half of image (75pt into image)
        let midCol = rep.pixelsWide / 2

        let topPixel = rep.colorAt(x: midCol, y: topRow)
        let bottomPixel = rep.colorAt(x: midCol, y: bottomRow)

        func isTeal(_ color: NSColor?) -> Bool {
            guard let c = color?.usingColorSpace(.sRGB) else { return false }
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            c.getRed(&r, green: &g, blue: &b, alpha: &a)
            return g > 0.3 && b > 0.3 && r < 0.4 && a > 0.5
        }
        func isOrange(_ color: NSColor?) -> Bool {
            guard let c = color?.usingColorSpace(.sRGB) else { return false }
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            c.getRed(&r, green: &g, blue: &b, alpha: &a)
            return r > 0.5 && g > 0.2 && b < 0.3 && a > 0.5
        }

        XCTAssertTrue(isTeal(topPixel),
            "Top half of drawn image should be teal (image must render right-side-up in flipped view). " +
            "scale=\(scale) topRow=\(topRow) got: \(topPixel?.description ?? "nil")")
        XCTAssertTrue(isOrange(bottomPixel),
            "Bottom half of drawn image should be orange (image must render right-side-up). " +
            "scale=\(scale) bottomRow=\(bottomRow) got: \(bottomPixel?.description ?? "nil")")
    }
}
#endif
