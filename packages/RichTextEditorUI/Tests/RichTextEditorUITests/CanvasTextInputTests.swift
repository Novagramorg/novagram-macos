#if canImport(AppKit)
import XCTest
import AppKit
@testable import RichTextEditorUI
import RichTextEditorCore

@available(macOS 12, *)
final class CanvasTextInputTests: XCTestCase {
    private func canvas() -> DocumentCanvasView {
        let v = DocumentCanvasView()
        v.setParagraphs([
            ParagraphBlock(id: BlockID("a"), runs: [TextRun(text: "Alpha")]),
            ParagraphBlock(id: BlockID("b"), runs: [TextRun(text: "Beta")]),
        ], width: 300)
        v.frame = CGRect(x: 0, y: 0, width: 300, height: 200); v.layoutSubtreeIfNeeded()
        return v
    }

    func test_insertText_editsCaretBlock_andShiftsLaterSpans() {
        let v = canvas()
        let bStartBefore = v.boxes[1].textStart
        v.selectedGlobalRange = (v.boxes[0].textStart + 5, v.boxes[0].textStart + 5) // end of "Alpha"
        v.commitText("!")
        XCTAssertEqual((v.boxes[0] as! BlockBox).currentParagraph().runs.map(\.text).joined(), "Alpha!")
        XCTAssertEqual(v.boxes[1].textStart, bStartBefore + 1) // later block shifted by +1
    }

    func test_textInRange_concatenatesAcrossBlocks() {
        let v = canvas()
        let lo = v.boxes[0].textStart + 4  // "a" of Alpha
        let hi = v.boxes[1].textStart + 1  // "B" of Beta
        XCTAssertEqual(v.text(inGlobalRange: lo, hi), "aB")
    }

    func test_caretRectInSecondBlock_isBelowFirst() {
        let v = canvas()
        let r0 = v.caretRect(forGlobal: v.boxes[0].textStart)
        let r1 = v.caretRect(forGlobal: v.boxes[1].textStart)
        XCTAssertGreaterThan(r1.minY, r0.minY)
    }
}
#endif
