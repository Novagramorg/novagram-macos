#if canImport(AppKit)
import AppKit
import XCTest
@testable import RichTextEditorUI
import RichTextEditorCore

/// Applying a list to a paragraph carrying interior soft "\n"s splits it into one item per line
/// (blank lines dropped) instead of making one tall multi-line item.
@available(macOS 12, *)
final class CanvasListNormalizeTests: AppKitTestCase {
    func test_setListOnMultilineParagraph_splitsIntoOneItemPerLine() {
        let v = DocumentCanvasView()
        v.setBlocks([.paragraph(ParagraphBlock(id: BlockID("a"), runs: [TextRun(text: "one\ntwo\n\nthree")]))], width: 400)
        _ = hostInWindow(v)
        v.layoutSubtreeIfNeeded()
        v.setCaret(global: v.boxes[0].textStart)
        v.selectAllText()
        v.setList(.ordered)
        let items = v.boxes.compactMap { $0 as? BlockBox }
        XCTAssertEqual(items.count, 3, "three text lines → three list items (the blank line is dropped)")
        XCTAssertEqual(items.map { $0.currentParagraph().text }, ["one", "two", "three"])
        XCTAssertTrue(items.allSatisfy { $0.listMembership?.marker == .ordered })
        XCTAssertEqual(v.head, items[2].textStart + items[2].textLength, "caret lands at the end of the last item")
    }

    func test_setListOnSingleLineParagraph_keepsOneItem() {
        let v = DocumentCanvasView()
        v.setBlocks([.paragraph(ParagraphBlock(id: BlockID("a"), runs: [TextRun(text: "solo")]))], width: 400)
        _ = hostInWindow(v)
        v.layoutSubtreeIfNeeded()
        v.setCaret(global: v.boxes[0].textStart)
        v.setList(.bullet)
        let items = v.boxes.compactMap { $0 as? BlockBox }
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].listMembership?.marker, .bullet)
    }
}
#endif
