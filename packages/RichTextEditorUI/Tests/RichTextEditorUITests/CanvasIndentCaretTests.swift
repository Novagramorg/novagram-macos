#if canImport(AppKit)
import AppKit
import XCTest
@testable import RichTextEditorUI
import RichTextEditorCore

/// The caret on an EMPTY indented line must sit at the paragraph's head indent, not the container's
/// left edge (TextKit 2 lays out no fragment for empty text, so the raw caretRect reports x = 0).
@available(macOS 12, *)
final class CanvasIndentCaretTests: AppKitTestCase {
    private func host(_ blocks: [ParagraphBlock]) -> (DocumentCanvasView, NSWindow) {
        let v = DocumentCanvasView()
        v.setBlocks(blocks.map { .paragraph($0) }, width: 400)
        let win = hostInWindow(v)
        v.layoutSubtreeIfNeeded()
        return (v, win)
    }

    func test_indentTwiceOnEmptyLine_caretSitsAtIndent() {
        let (v, _) = host([ParagraphBlock(id: BlockID("a"), runs: [])])
        v.setCaret(global: v.boxes[0].textStart)
        let before = v.caretRect(forGlobal: v.head)
        v.indent()
        v.indent()
        let after = v.caretRect(forGlobal: v.head)
        XCTAssertEqual(after.minX, before.minX + 48, accuracy: 0.5,
                       "two indents move the empty-line caret right by 2×24pt")
    }

    func test_indentTwiceOnEmptyQuoteChild_caretSitsAtIndentInsideQuote() {
        let v = DocumentCanvasView()
        v.setBlocks([.blockQuote(BlockQuote(id: BlockID("q"), children: [
            .paragraph(ParagraphBlock(id: BlockID("a"), runs: []))
        ]))], width: 400)
        _ = hostInWindow(v)
        v.layoutSubtreeIfNeeded()
        guard let quote = v.boxes[0] as? BlockQuoteBox, let child = quote.children.boxes.first as? BlockBox else {
            return XCTFail("expected a block quote hosting one paragraph")
        }
        v.setCaret(global: child.textStart)
        let before = v.caretRect(forGlobal: v.head)
        v.indent()
        v.indent()
        let after = v.caretRect(forGlobal: v.head)
        XCTAssertEqual(before.minX, child.textOrigin.x, accuracy: 0.5,
                       "the empty quote-child caret starts at the quote's text inset, not the canvas edge")
        XCTAssertEqual(after.minX, before.minX + 48, accuracy: 0.5,
                       "two indents move the empty quote-child caret right by 2×24pt")
    }

    func test_indentOnEmptyTrailingSoftLine_caretSitsAtIndent() {
        let (v, _) = host([ParagraphBlock(id: BlockID("a"), runs: [TextRun(text: "hello\n")])])
        v.setCaret(global: v.boxes[0].textStart + 6)
        v.indent()
        let after = v.caretRect(forGlobal: v.head)
        XCTAssertEqual(after.minX, v.boxes[0].textOrigin.x + 24, accuracy: 0.5,
                       "the caret on the trailing soft line honors the paragraph indent")
    }
}
#endif
