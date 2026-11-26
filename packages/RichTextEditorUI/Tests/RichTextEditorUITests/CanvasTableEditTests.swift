#if canImport(AppKit)
import XCTest
import AppKit
@testable import RichTextEditorUI
import RichTextEditorCore

@available(macOS 12, *)
final class CanvasTableEditTests: XCTestCase {
    private func cell(_ id: String, _ text: String) -> Cell {
        Cell(id: BlockID(id), blocks: [.paragraph(ParagraphBlock(id: BlockID(id + "p"), runs: [TextRun(text: text)]))])
    }
    private func canvas() -> DocumentCanvasView {
        let v = DocumentCanvasView()
        v.setBlocks([.table(TableBlock(id: BlockID("t"),
            columns: [ColumnSpec(width: 120), ColumnSpec(width: 120)],
            rows: [Row(id: BlockID("r0"), cells: [cell("a", "Alpha"), cell("b", "Beta")])]))], width: 320)
        v.frame = CGRect(x: 0, y: 0, width: 320, height: 300); v.layoutSubtreeIfNeeded()
        return v
    }
    private func cellText(_ v: DocumentCanvasView, _ ref: TextNodeRef) -> String? {
        v.allLeafRegions().first { $0.ref == ref }.map { $0.layout.attributedString.string }
    }

    func test_typingInCell_editsThatCellOnly() {
        let v = canvas()
        let rA = v.allLeafRegions().first { $0.ref == .paragraph(BlockID("ap")) }!
        v.selectedGlobalRange = (rA.globalStart + 5, rA.globalStart + 5) // end of "Alpha"
        v.commitText("!")
        XCTAssertEqual(cellText(v, .paragraph(BlockID("ap"))), "Alpha!")
        XCTAssertEqual(cellText(v, .paragraph(BlockID("bp"))), "Beta")    // other cell untouched
    }

    func test_typingInCell_isUndoable() {
        let v = canvas()
        let um = UndoManager(); um.groupsByEvent = false
        v.undoManagerOverride = um
        let rA = v.allLeafRegions().first { $0.ref == .paragraph(BlockID("ap")) }!
        v.selectedGlobalRange = (rA.globalStart + 5, rA.globalStart + 5)
        um.beginUndoGrouping(); v.commitText("!"); um.endUndoGrouping()
        XCTAssertEqual(cellText(v, .paragraph(BlockID("ap"))), "Alpha!")
        um.undo()
        XCTAssertEqual(cellText(v, .paragraph(BlockID("ap"))), "Alpha")
    }
}
#endif
