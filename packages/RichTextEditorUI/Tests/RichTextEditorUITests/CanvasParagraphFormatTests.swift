#if canImport(AppKit)
import XCTest
import AppKit
@testable import RichTextEditorUI
import RichTextEditorCore

@available(macOS 12, *)
final class CanvasParagraphFormatTests: XCTestCase {
    func canvas() -> DocumentCanvasView {
        let v = DocumentCanvasView()
        v.setBlocks([
            .paragraph(ParagraphBlock(id: BlockID("a"), runs: [TextRun(text: "First")])),
            .paragraph(ParagraphBlock(id: BlockID("b"), runs: [TextRun(text: "Second")])),
        ], width: 320)
        v.frame = CGRect(x: 0, y: 0, width: 320, height: 400); v.layoutSubtreeIfNeeded()
        return v
    }
    func para(_ v: DocumentCanvasView, _ id: String) -> ParagraphBlock? {
        for b in v.currentBlocks() { if case .paragraph(let p) = b, p.id == BlockID(id) { return p } }
        return nil
    }
    func caret(_ v: DocumentCanvasView, _ id: String) {
        let r = v.allLeafRegions().first { $0.ref == .paragraph(BlockID(id)) }!
        v.anchor = r.globalStart + 1; v.head = r.globalStart + 1
    }

    func test_setParagraphStyle_collapsedCaret_setsStyle() {
        let v = canvas(); caret(v, "a")
        v.setParagraphStyle(.heading1)
        XCTAssertEqual(para(v, "a")?.style, .heading1)
        XCTAssertEqual(para(v, "b")?.style, .body, "other paragraph unchanged")
    }
    func test_setParagraphStyle_multiParagraphSelection() {
        let v = canvas()
        let a = v.allLeafRegions().first { $0.ref == .paragraph(BlockID("a")) }!
        let b = v.allLeafRegions().first { $0.ref == .paragraph(BlockID("b")) }!
        v.anchor = a.globalStart + 1; v.head = b.globalStart + 2
        v.setParagraphStyle(.heading2)
        XCTAssertEqual(para(v, "a")?.style, .heading2)
        XCTAssertEqual(para(v, "b")?.style, .heading2)
    }
    func test_setParagraphStyle_isUndoable() {
        let v = canvas()
        let um = UndoManager(); um.groupsByEvent = false; v.undoManagerOverride = um
        caret(v, "a")
        um.beginUndoGrouping(); v.setParagraphStyle(.heading1); um.endUndoGrouping()
        XCTAssertEqual(para(v, "a")?.style, .heading1)
        um.undo()
        XCTAssertEqual(para(v, "a")?.style, .body, "undo restores body")
    }
    func test_setAlignment_setsAlignment() {
        let v = canvas(); caret(v, "a")
        v.setAlignment(.center)
        XCTAssertEqual(para(v, "a")?.paragraph.alignment, .center)
    }
    func test_setAlignment_isUndoable() {
        let v = canvas()
        let um = UndoManager(); um.groupsByEvent = false; v.undoManagerOverride = um
        caret(v, "a")
        um.beginUndoGrouping(); v.setAlignment(.right); um.endUndoGrouping()
        XCTAssertEqual(para(v, "a")?.paragraph.alignment, .right)
        um.undo()
        XCTAssertEqual(para(v, "a")?.paragraph.alignment, .natural, "undo restores the .natural default")
    }
}

// MARK: - currentParagraphFormatState (drives the toolbar's selected-item marks)

@available(macOS 12, *)
extension CanvasParagraphFormatTests {
    private func selectBoth(_ v: DocumentCanvasView) {
        let a = v.allLeafRegions().first { $0.ref == .paragraph(BlockID("a")) }!
        let b = v.allLeafRegions().first { $0.ref == .paragraph(BlockID("b")) }!
        v.anchor = a.globalStart + 1; v.head = b.globalStart + 2
    }

    func test_formatState_bodyCaret() {
        let v = canvas(); caret(v, "a")
        let s = v.currentParagraphFormatState()
        XCTAssertEqual(s.style, .body)
        XCTAssertEqual(s.list, .none)
    }

    func test_formatState_reflectsHeading() {
        let v = canvas(); caret(v, "a"); v.setParagraphStyle(.heading2)
        XCTAssertEqual(v.currentParagraphFormatState().style, .heading2)
    }

    func test_formatState_mixedStyle_isNil() {
        let v = canvas(); caret(v, "a"); v.setParagraphStyle(.heading1)
        selectBoth(v)
        XCTAssertNil(v.currentParagraphFormatState().style, "a selection spanning two styles marks none")
    }

    func test_formatState_bulletAndOrdered() {
        let v = canvas(); caret(v, "a"); v.setList(.bullet)
        XCTAssertEqual(v.currentParagraphFormatState().list, .marker(.bullet))
        caret(v, "a"); v.setList(.ordered)
        XCTAssertEqual(v.currentParagraphFormatState().list, .marker(.ordered))
    }

    func test_formatState_mixedList_isMixed() {
        let v = canvas(); caret(v, "a"); v.setList(.bullet)   // "a" bullet, "b" plain
        selectBoth(v)
        XCTAssertEqual(v.currentParagraphFormatState().list, .mixed)
    }

    func test_formatState_alignment() {
        let v = canvas(); caret(v, "a"); v.setAlignment(.center)
        XCTAssertEqual(v.currentParagraphFormatState().alignment, .center)
    }
}
#endif
