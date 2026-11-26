#if canImport(AppKit)
import AppKit
import XCTest
@testable import RichTextEditorUI
import RichTextEditorCore

/// Return-key semantics in list items: Enter adds a new item (and outdents / leaves the list on an
/// empty item), Shift+Enter is a soft line break, and a new (empty) list item's caret sits after the
/// marker (at firstLineHeadIndent) rather than in the marker gutter.
@available(macOS 12, *)
final class CanvasListReturnTests: AppKitTestCase {
    private func host(_ blocks: [ParagraphBlock]) -> (DocumentCanvasView, NSWindow) {
        let v = DocumentCanvasView()
        v.setBlocks(blocks.map { .paragraph($0) }, width: 400)
        let win = hostInWindow(v)
        v.layoutSubtreeIfNeeded()
        return (v, win)
    }
    private func pressReturn(_ v: DocumentCanvasView, shift: Bool, in win: NSWindow) {
        let flags: NSEvent.ModifierFlags = shift ? [.shift] : []
        let e = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags,
            timestamp: 0, windowNumber: win.windowNumber, context: nil,
            characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36)!
        v.keyDown(with: e)
    }
    private func listBoxes(_ v: DocumentCanvasView) -> [BlockBox] { v.boxes.compactMap { $0 as? BlockBox } }

    func test_enterInListItem_addsNewListItem() {
        let (v, win) = host([
            ParagraphBlock(id: BlockID("a"), list: ListMembership(marker: .ordered, level: 0), runs: [TextRun(text: "One")]),
        ])
        v.setCaret(global: v.boxes[0].textStart + 3)        // end of "One"
        pressReturn(v, shift: false, in: win)
        let boxes = listBoxes(v)
        XCTAssertEqual(boxes.count, 2, "Enter splits the item into two list paragraphs")
        XCTAssertEqual(boxes[1].listMembership?.marker, .ordered, "the new paragraph continues the list")
        XCTAssertEqual(v.head, boxes[1].textStart, "caret lands in the new item")
    }

    func test_shiftEnterInListItem_startsFreshBodyParagraph() {
        let (v, win) = host([
            ParagraphBlock(id: BlockID("a"), list: ListMembership(marker: .bullet, level: 0), runs: [TextRun(text: "One")]),
        ])
        v.setCaret(global: v.boxes[0].textStart + 3)        // end of "One"
        pressReturn(v, shift: true, in: win)
        let boxes = listBoxes(v)
        XCTAssertEqual(boxes.count, 2, "Shift+Enter splits off a new paragraph")
        XCTAssertEqual(boxes[0].listMembership?.marker, .bullet, "the original item stays a bullet")
        XCTAssertNil(boxes[1].listMembership, "the new paragraph breaks out of the list")
        XCTAssertEqual(boxes[1].style, .body, "the new paragraph is a plain body paragraph")
        XCTAssertEqual(v.head, boxes[1].textStart, "caret lands in the new paragraph")
        XCTAssertEqual(v.placeholderDraws().count, 1, "the new empty body paragraph shows 'Type something…'")
    }

    func test_shiftEnterInHeading_startsFreshBodyParagraph() {
        let (v, win) = host([
            ParagraphBlock(id: BlockID("a"), style: .heading1, runs: [TextRun(text: "Title")]),
        ])
        v.setCaret(global: v.boxes[0].textStart + 5)
        pressReturn(v, shift: true, in: win)
        let boxes = listBoxes(v)
        XCTAssertEqual(boxes.count, 2)
        XCTAssertEqual(boxes[0].style, .heading1, "the heading stays a heading")
        XCTAssertEqual(boxes[1].style, .body, "Shift+Enter breaks out of the heading into a body paragraph")
    }

    func test_enterOnEmptyTopLevelItem_leavesTheList() {
        let (v, win) = host([
            ParagraphBlock(id: BlockID("a"), list: ListMembership(marker: .ordered, level: 0), runs: []),
        ])
        v.setCaret(global: v.boxes[0].textStart)
        pressReturn(v, shift: false, in: win)
        XCTAssertEqual(listBoxes(v).count, 1, "no new item is created")
        XCTAssertNil(listBoxes(v)[0].listMembership, "Enter on an empty top-level item leaves the list")
    }

    func test_enterOnEmptyNestedItem_outdentsOneLevel() {
        let (v, win) = host([
            ParagraphBlock(id: BlockID("a"), list: ListMembership(marker: .bullet, level: 2), runs: []),
        ])
        v.setCaret(global: v.boxes[0].textStart)
        pressReturn(v, shift: false, in: win)
        XCTAssertEqual(listBoxes(v).count, 1)
        XCTAssertEqual(listBoxes(v)[0].listMembership?.level, 1, "Enter on an empty nested item outdents one level")
    }

    func test_emptyListItemCaret_sitsAtTextIndent_notInMarkerGutter() {
        let (v, _) = host([
            ParagraphBlock(id: BlockID("a"), list: ListMembership(marker: .ordered, level: 0), runs: []),
        ])
        v.setCaret(global: v.boxes[0].textStart)
        let region = v.allLeafRegions().first { $0.ref == .paragraph(BlockID("a")) }!
        let indent = AttributedStringMapper().styleSheet.paragraphStyle(
            for: .body, attributes: .default, list: ListMembership(marker: .ordered, level: 0)).firstLineHeadIndent
        let caret = v.caretRect(forGlobal: v.head)
        XCTAssertGreaterThan(indent, 1, "an ordered list item is indented")
        XCTAssertEqual(caret.minX, region.canvasOrigin.x + indent, accuracy: 0.5,
                       "an empty list item's caret sits at the text indent, after the marker — not at x = 0")
    }

    func test_emptyListItem_showsNoBodyPlaceholder() {
        let (v, _) = host([
            ParagraphBlock(id: BlockID("a"), list: ListMembership(marker: .bullet, level: 0), runs: []),
        ])
        XCTAssertTrue(v.placeholderDraws().isEmpty, "an empty list item shows its marker, not the 'Type something…' placeholder")
    }

    func test_emptyBodyParagraph_keepsPlaceholder() {
        let (v, _) = host([ParagraphBlock(id: BlockID("a"), runs: [])])
        v.setCaret(global: v.boxes[0].textStart)
        XCTAssertEqual(v.placeholderDraws().count, 1, "the caret's empty plain paragraph shows its placeholder")
    }

    func test_enterInList_newEmptyItemHasNoPlaceholderOverMarker() {
        let (v, win) = host([
            ParagraphBlock(id: BlockID("a"), list: ListMembership(marker: .bullet, level: 0), runs: [TextRun(text: "qwef")]),
        ])
        v.setCaret(global: v.boxes[0].textStart + 4)
        pressReturn(v, shift: false, in: win)
        XCTAssertEqual(listBoxes(v).count, 2)
        XCTAssertTrue(v.placeholderDraws().isEmpty, "the new empty bullet shows no placeholder overlapping its marker")
    }

    func test_enterInPlainParagraph_staysSoftBreak() {
        let (v, win) = host([
            ParagraphBlock(id: BlockID("a"), runs: [TextRun(text: "One")]),
        ])
        v.setCaret(global: v.boxes[0].textStart + 3)
        pressReturn(v, shift: false, in: win)
        XCTAssertEqual(listBoxes(v).count, 1, "Enter in a plain paragraph stays in the block (soft break, unchanged)")
    }

    // MARK: Backspace removes an empty quote / list (was a no-op when it's the only block)

    private func hostQuote(_ children: [ParagraphBlock]) -> (DocumentCanvasView, NSWindow) {
        let v = DocumentCanvasView()
        v.setBlocks([.blockQuote(BlockQuote(id: BlockID("q"), children: children.map { .paragraph($0) }))], width: 400)
        let win = hostInWindow(v)
        v.layoutSubtreeIfNeeded()
        return (v, win)
    }

    func test_backspaceInEmptyQuote_unquotesToBody() {
        let (v, _) = hostQuote([ParagraphBlock(id: BlockID("qc"), runs: [])])
        guard let bq = v.boxes[0] as? BlockQuoteBox, let child = bq.children.boxes.first else {
            return XCTFail("expected a block-quote container")
        }
        v.setCaret(global: child.textStart)
        v.performDeleteBackward()
        XCTAssertTrue(v.boxes[0] is BlockBox, "an empty lone-child quote unwraps to a plain paragraph")
    }

    func test_backspaceInEmptyListItem_leavesTheList() {
        let (v, _) = host([ParagraphBlock(id: BlockID("l"), list: ListMembership(marker: .bullet, level: 0), runs: [])])
        v.setCaret(global: v.boxes[0].textStart)
        v.performDeleteBackward()
        XCTAssertNil(listBoxes(v).first?.listMembership, "an empty top-level list item leaves the list")
    }

    func test_backspaceInEmptyNestedListItem_outdents() {
        let (v, _) = host([ParagraphBlock(id: BlockID("l"), list: ListMembership(marker: .bullet, level: 1), runs: [])])
        v.setCaret(global: v.boxes[0].textStart)
        v.performDeleteBackward()
        XCTAssertEqual(listBoxes(v).first?.listMembership?.level, 0, "an empty nested item outdents one level")
    }

    func test_quoteContainer_childrenEditInPlace() {
        let (v, _) = hostQuote([
            ParagraphBlock(id: BlockID("q1"), runs: [TextRun(text: "ab")]),
            ParagraphBlock(id: BlockID("q2"), runs: [TextRun(text: "x")]),
        ])
        guard let bq = v.boxes[0] as? BlockQuoteBox, bq.children.boxes.count == 2 else {
            return XCTFail("expected two quote children")
        }
        let second = bq.children.boxes[1]
        v.setCaret(global: second.textStart + 1)            // after "x"
        v.performDeleteBackward()                           // delete "x" inside the quote child
        guard let bq2 = v.boxes[0] as? BlockQuoteBox else { return XCTFail("quote survives an in-child delete") }
        XCTAssertEqual(bq2.children.boxes.count, 2)
        XCTAssertEqual(bq2.children.boxes[1].textLength, 0, "the child's char was deleted in place")
    }

    func test_backspaceAtStartOfNonEmptyLoneQuoteChild_unwrapsKeepingText() {
        let (v, _) = hostQuote([ParagraphBlock(id: BlockID("qc"), runs: [TextRun(text: "hi")])])
        guard let bq = v.boxes[0] as? BlockQuoteBox, let child = bq.children.boxes.first else {
            return XCTFail("expected a block-quote container")
        }
        v.setCaret(global: child.textStart)   // start of the NON-empty lone child
        v.performDeleteBackward()
        guard let p = v.boxes[0] as? BlockBox else { return XCTFail("lone-child quote unwraps on backspace") }
        XCTAssertEqual(p.currentParagraph().text, "hi", "the content survives the unwrap")
    }
}
#endif
