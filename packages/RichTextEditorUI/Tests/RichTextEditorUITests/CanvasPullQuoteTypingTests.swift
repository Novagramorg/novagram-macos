#if canImport(AppKit)
import AppKit
import XCTest
@testable import RichTextEditorUI
import RichTextEditorCore

/// An EMPTY pull quote (e.g. made from an empty paragraph) is a centered pill: the caret must sit at
/// the pill's mid-x (not the layout's left edge), and the first typed character must take the pull
/// quote's own style (italic + centered), not body-upright-left.
@available(macOS 12, *)
final class CanvasPullQuoteTypingTests: AppKitTestCase {
    private func hostEmptyPullQuote() -> (DocumentCanvasView, PullQuoteBox) {
        let v = DocumentCanvasView()
        v.setBlocks([.paragraph(ParagraphBlock(id: BlockID("a"), runs: []))], width: 400)
        _ = hostInWindow(v)
        v.layoutSubtreeIfNeeded()
        v.setCaret(global: v.boxes[0].textStart)
        v.makePullQuote()
        v.layoutSubtreeIfNeeded()
        guard let pq = v.boxes[0] as? PullQuoteBox else {
            XCTFail("expected the empty paragraph to become a pull quote")
            fatalError()
        }
        return (v, pq)
    }

    func test_emptyPullQuote_caretSitsAtPillCenter() {
        let (v, pq) = hostEmptyPullQuote()
        let caret = v.caretRect(forGlobal: v.head)
        XCTAssertEqual(caret.minX, pq.frame.midX, accuracy: 1,
                       "the empty pull quote's caret sits at the centered pill's mid-x")
    }

    func test_backspaceInEmptyPullQuote_removesItToBodyParagraph() {
        let (v, _) = hostEmptyPullQuote()
        v.performDeleteBackward()
        XCTAssertEqual(v.boxes.count, 1)
        let p = v.boxes[0] as? BlockBox
        XCTAssertNotNil(p, "the empty pull quote collapses to a plain paragraph")
        XCTAssertEqual(p?.textLength, 0)
        XCTAssertEqual(p?.style, .body)
    }

    func test_typingIntoEmptyPullQuote_usesPullQuoteStyle() {
        let (v, pq) = hostEmptyPullQuote()
        v.insertText("q", replacementRange: NSRange(location: NSNotFound, length: 0))
        let storage = pq.layout.attributedString
        XCTAssertEqual(storage.string, "q")
        let attrs = storage.attributes(at: 0, effectiveRange: nil)
        let font = attrs[.font] as? NSFont
        XCTAssertTrue(font?.fontDescriptor.symbolicTraits.contains(.italic) == true,
                      "pull quote text renders forced-italic")
        let ps = attrs[.paragraphStyle] as? NSParagraphStyle
        XCTAssertEqual(ps?.alignment, .center, "pull quote text is centered")
    }
}
#endif
