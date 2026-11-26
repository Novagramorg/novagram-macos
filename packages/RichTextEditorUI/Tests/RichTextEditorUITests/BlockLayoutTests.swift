#if canImport(AppKit)
import XCTest
import AppKit
@testable import RichTextEditorUI

@available(macOS 12, *)
final class BlockLayoutTests: XCTestCase {
    private func layout(_ s: String) -> BlockLayout {
        BlockLayout(attributedString: NSAttributedString(string: s,
            attributes: [.font: NSFont.systemFont(ofSize: 16)]), width: 300)
    }

    func test_lengthAndHeight() {
        let l = layout("Hello")
        XCTAssertEqual(l.length, 5)
        XCTAssertGreaterThan(l.boundingHeight, 0)
    }

    func test_caretAdvancesWithOffset() {
        let l = layout("Hello")
        XCTAssertLessThan(l.caretRect(atOffset: 0).minX, l.caretRect(atOffset: 5).minX)
    }

    func test_selectionRectsNonEmptyForRange() {
        let l = layout("Hello")
        XCTAssertFalse(l.selectionRects(start: 0, end: 5).isEmpty)
    }

    func test_closestOffset_nearStartIsZero() {
        let l = layout("Hello")
        XCTAssertEqual(l.closestOffset(toPoint: CGPoint(x: -50, y: 5)), 0)
    }

    func test_closestOffset_tapRightOfShortLastLine_landsAtLineEnd() {
        // Wraps to a long first line + a short last line at width 300.
        let l = layout("For decades they were just math. Now we photograph them.")
        let endCaret = l.caretRect(atOffset: l.length)
        XCTAssertGreaterThan(endCaret.midY, l.caretRect(atOffset: 0).midY)   // sanity: it wrapped past line 1
        // Tap in the free space to the RIGHT of the short last line, on that line's row.
        let offset = l.closestOffset(toPoint: CGPoint(x: 5000, y: endCaret.midY))
        XCTAssertEqual(offset, l.length)   // end of the last line — not the longer line above it
    }

    func test_replaceUpdatesText() {
        let l = layout("Hello")
        l.replace(start: 5, end: 5, with: NSAttributedString(string: "!"))
        XCTAssertEqual(l.length, 6)
    }

    func test_firstLineBaselineFromTop_nilForEmptyText() {
        XCTAssertNil(layout("").firstLineBaselineFromTop)
    }

    private func baselineLayout(multiple: CGFloat) -> BlockLayout {
        let ps = NSMutableParagraphStyle(); ps.lineHeightMultiple = multiple
        return BlockLayout(attributedString: NSAttributedString(string: "Hi",
            attributes: [.font: NSFont.systemFont(ofSize: 16), .paragraphStyle: ps]), width: 300)
    }

    func test_firstLineBaselineFromTop_growsWithLineHeightMultiple() {
        // A larger line-height multiple pushes the first line's baseline further below the top — this is
        // exactly the shift that the list marker must follow to stay aligned with the text.
        let plain = baselineLayout(multiple: 1.0).firstLineBaselineFromTop ?? 0
        let tall  = baselineLayout(multiple: 1.5).firstLineBaselineFromTop ?? 0
        XCTAssertGreaterThan(tall, plain)
    }

    func test_drawText_isUpright_inFlippedContext() {
        let attr = NSAttributedString(string: "Ag", attributes: [.font: NSFont.systemFont(ofSize: 40)])
        let layout = BlockLayout(attributedString: attr, width: 200)
        let h = max(layout.boundingHeight, 50)
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 200, pixelsHigh: Int(h),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let ctx = NSGraphicsContext(bitmapImageRep: rep)!
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = ctx
        NSColor.white.setFill(); NSRect(x: 0, y: 0, width: 200, height: h).fill()
        layout.drawText(in: ctx.cgContext, at: .zero)
        NSGraphicsContext.restoreGraphicsState()
        // Glyph ink must sit in the TOP half (y-down): more dark pixels above the midline than below.
        func darkPixels(yRange: Range<Int>) -> Int {
            var n = 0
            for y in yRange { for x in 0..<200 { if let c = rep.colorAt(x: x, y: y), c.brightnessComponent < 0.5 { n += 1 } } }
            return n
        }
        let mid = Int(h) / 2
        XCTAssertGreaterThan(darkPixels(yRange: 0..<mid), darkPixels(yRange: mid..<Int(h)),
                             "text rendered upside-down — fragment drawing not upright in flipped space")
    }
}
#endif
