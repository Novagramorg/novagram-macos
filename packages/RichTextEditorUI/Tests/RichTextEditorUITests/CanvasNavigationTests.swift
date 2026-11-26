#if canImport(AppKit)
import XCTest
import AppKit
@testable import RichTextEditorUI
import RichTextEditorCore

@available(macOS 12, *)
final class CanvasNavigationTests: XCTestCase {
    private func canvas() -> DocumentCanvasView {
        let v = DocumentCanvasView()
        v.setParagraphs([
            ParagraphBlock(id: BlockID("a"), runs: [TextRun(text: "Alpha")]),
            ParagraphBlock(id: BlockID("b"), runs: [TextRun(text: "Beta")]),
        ], width: 300)
        v.frame = CGRect(x: 0, y: 0, width: 300, height: 200); v.layoutSubtreeIfNeeded()
        return v
    }

    func test_rightAtBlockEnd_jumpsToNextBlockStart() {
        let v = canvas()
        let endOfA = v.boxes[0].textStart + v.boxes[0].textLength
        let next = v.nextTextPosition(after: endOfA)
        XCTAssertEqual(next, v.boxes[1].textStart)
    }

    func test_leftAtBlockStart_jumpsToPrevBlockEnd() {
        let v = canvas()
        let prev = v.prevTextPosition(before: v.boxes[1].textStart)
        XCTAssertEqual(prev, v.boxes[0].textStart + v.boxes[0].textLength)
    }

    func test_downFromFirstBlock_landsInSecondBlock() {
        let v = canvas()
        let down = v.verticalPosition(from: v.boxes[0].textStart + 1, down: true)
        XCTAssertNotNil(v.box(containingGlobal: down))
        XCTAssertEqual(v.box(containingGlobal: down)!.box.id, BlockID("b"))
    }

    func test_toggleBold_overSelectionInABlock() {
        let v = canvas()
        v.anchor = v.boxes[0].textStart; v.head = v.boxes[0].textStart + 5
        v.toggleBold()
        XCTAssertTrue((v.boxes[0] as! BlockBox).currentParagraph().runs.allSatisfy { $0.attributes.bold })
    }

    // MARK: Up at the top of a trapped leading block inserts a body paragraph above (the only way to type
    // a normal paragraph above a leading quote / heading — which is otherwise a dead end).

    private func leadingQuoteDoc() -> DocumentCanvasView {
        let v = DocumentCanvasView()
        v.setParagraphs([
            ParagraphBlock(id: BlockID("q"), style: .heading2, runs: [TextRun(text: "quote line")]),
            ParagraphBlock(id: BlockID("b"), runs: [TextRun(text: "body")]),
        ], width: 300)
        v.frame = CGRect(x: 0, y: 0, width: 300, height: 200); v.layoutSubtreeIfNeeded()
        return v
    }

    func test_upAtTopOfLeadingQuote_insertsBodyParagraphAbove() {
        let v = leadingQuoteDoc()
        v.setCaret(global: v.boxes[0].textStart)        // start of the quote
        v.moveUp(nil)
        XCTAssertEqual(v.boxes.count, 3, "a new paragraph was inserted above the quote")
        let top = v.boxes[0] as? BlockBox
        XCTAssertEqual(top?.style, .body, "the new top block is a plain body paragraph")
        XCTAssertEqual(top?.textLength, 0, "it's empty, ready to type")
        XCTAssertEqual(v.boxes[1].id, BlockID("q"), "the quote moved down to second")
        XCTAssertEqual(v.head, v.boxes[0].textStart, "caret landed in the new top paragraph")
    }

    func test_upAgainAfterEscape_doesNotStackMoreEmptyLines() {
        let v = leadingQuoteDoc()
        v.setCaret(global: v.boxes[0].textStart)
        v.moveUp(nil)                                   // escapes above → now a body first block
        XCTAssertEqual(v.boxes.count, 3)
        v.moveUp(nil)                                   // body first block is not trapped → no-op
        XCTAssertEqual(v.boxes.count, 3, "a second Up does not insert another empty line")
    }

    func test_upAtTopOfLeadingHeading_insertsBodyParagraphAbove() {
        let v = DocumentCanvasView()
        v.setParagraphs([
            ParagraphBlock(id: BlockID("h"), style: .heading1, runs: [TextRun(text: "Title")]),
        ], width: 300)
        v.frame = CGRect(x: 0, y: 0, width: 300, height: 200); v.layoutSubtreeIfNeeded()
        v.setCaret(global: v.boxes[0].textStart)
        v.moveUp(nil)
        XCTAssertEqual(v.boxes.count, 2)
        XCTAssertEqual((v.boxes[0] as? BlockBox)?.style, .body)
        XCTAssertEqual(v.head, v.boxes[0].textStart, "caret in the new top paragraph")
    }

    func test_upAtTopOfBodyParagraph_doesNotInsert() {
        let v = canvas()                                // two plain body paragraphs
        v.setCaret(global: v.boxes[0].textStart)
        let count = v.boxes.count
        v.moveUp(nil)
        XCTAssertEqual(v.boxes.count, count, "no paragraph is inserted above a plain body first block")
    }

    func test_upFromSecondBlock_navigatesIntoQuote_doesNotInsert() {
        let v = leadingQuoteDoc()
        v.setCaret(global: v.boxes[1].textStart + 1)    // in the body block below the quote
        let count = v.boxes.count
        v.moveUp(nil)
        XCTAssertEqual(v.boxes.count, count, "Up from a lower block navigates up, it doesn't insert")
        XCTAssertNotNil(v.box(containingGlobal: v.head))
        XCTAssertEqual(v.box(containingGlobal: v.head)!.box.id, BlockID("q"), "caret moved into the quote")
    }

    // MARK: Down at the bottom of a trapped trailing block appends a body paragraph below (mirror of Up).

    private func trailingQuoteDoc() -> DocumentCanvasView {
        let v = DocumentCanvasView()
        v.setParagraphs([
            ParagraphBlock(id: BlockID("b"), runs: [TextRun(text: "body")]),
            ParagraphBlock(id: BlockID("q"), style: .heading2, runs: [TextRun(text: "quote line")]),
        ], width: 300)
        v.frame = CGRect(x: 0, y: 0, width: 300, height: 200); v.layoutSubtreeIfNeeded()
        return v
    }

    func test_downAtBottomOfTrailingQuote_appendsBodyParagraphBelow() {
        let v = trailingQuoteDoc()
        v.setCaret(global: v.boxes[1].textStart + v.boxes[1].textLength)   // end of the quote (last line)
        v.moveDown(nil)
        XCTAssertEqual(v.boxes.count, 3, "a new paragraph was appended below the quote")
        let bottom = v.boxes[2] as? BlockBox
        XCTAssertEqual(bottom?.style, .body, "the new bottom block is a plain body paragraph")
        XCTAssertEqual(bottom?.textLength, 0, "it's empty, ready to type")
        XCTAssertEqual(v.boxes[1].id, BlockID("q"), "the quote stays second")
        XCTAssertEqual(v.head, v.boxes[2].textStart, "caret landed in the new bottom paragraph")
    }

    func test_downAgainAfterEscapeBelow_doesNotStackMoreEmptyLines() {
        let v = trailingQuoteDoc()
        v.setCaret(global: v.boxes[1].textStart + v.boxes[1].textLength)
        v.moveDown(nil)                                 // escapes below → now a body last block
        XCTAssertEqual(v.boxes.count, 3)
        v.moveDown(nil)                                 // body last block is not trapped → no-op
        XCTAssertEqual(v.boxes.count, 3, "a second Down does not append another empty line")
    }

    func test_downAtBottomOfBodyParagraph_doesNotInsert() {
        let v = canvas()                                // two plain body paragraphs; last is body
        v.setCaret(global: v.boxes[1].textStart + v.boxes[1].textLength)
        let count = v.boxes.count
        v.moveDown(nil)
        XCTAssertEqual(v.boxes.count, count, "no paragraph is appended below a plain body last block")
    }
}
#endif
