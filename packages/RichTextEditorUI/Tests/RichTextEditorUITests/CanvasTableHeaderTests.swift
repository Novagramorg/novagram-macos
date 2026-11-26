#if canImport(AppKit)
import XCTest
import AppKit
@testable import RichTextEditorUI
import RichTextEditorCore

@available(macOS 12, *)
final class CanvasTableHeaderTests: AppKitTestCase {
    func cell(_ id: String, _ t: String) -> Cell {
        Cell(id: BlockID(id), blocks: [.paragraph(ParagraphBlock(id: BlockID(id + "p"), runs: [TextRun(text: t)]))])
    }
    func test_headerRowFlagAndRendersNonBlank() {
        let v = DocumentCanvasView()
        v.setBlocks([.table(TableBlock(id: BlockID("t"), columns: [ColumnSpec(width: 140), ColumnSpec(width: 140)],
            rows: [Row(id: BlockID("r0"), isHeader: true, cells: [cell("a", "Name"), cell("b", "Role")]),
                   Row(id: BlockID("r1"), cells: [cell("c", "Ada"), cell("d", "Eng")])]))], width: 340)
        v.frame = CGRect(x: 0, y: 0, width: 340, height: 400); v.layoutSubtreeIfNeeded()
        let t = v.boxes.first as! TableBlockBox
        XCTAssertTrue(t.isHeaderRow(0))
        XCTAssertFalse(t.isHeaderRow(1))
        let image = snapshot(v)
        XCTAssertNotNil(image.cgImage)
    }

    func test_firstRowBold_othersNot_modelStaysClean() {
        let v = DocumentCanvasView()
        v.setBlocks([.table(TableBlock(id: BlockID("t"), columns: [ColumnSpec(width: 140), ColumnSpec(width: 140)],
            rows: [Row(id: BlockID("r0"), isHeader: true, cells: [cell("a","Name"), cell("b","Role")]),
                   Row(id: BlockID("r1"), cells: [cell("c","Ada"), cell("d","Eng")])]))], width: 340)
        v.frame = CGRect(x: 0, y: 0, width: 340, height: 400); v.layoutSubtreeIfNeeded()
        let t = v.boxes[0] as! TableBlockBox
        func bold(_ r: Int, _ c: Int) -> Bool {
            let s = t.cells[r][c].boxes[0] as! BlockBox
            let f = s.layout.attributedString.attribute(.font, at: 0, effectiveRange: nil) as! NSFont
            return f.fontDescriptor.symbolicTraits.contains(.bold)
        }
        XCTAssertTrue(bold(0, 0))    // header row → bold (render-only)
        XCTAssertTrue(bold(0, 1))    // header row → bold
        XCTAssertFalse(bold(1, 0))   // body row → not bold
        XCTAssertFalse(bold(1, 1))   // body row → not bold
        // model stays clean: no synthetic bold persisted in the header row
        guard case .table(let tb) = t.currentBlock(),
              case .paragraph(let p) = tb.rows[0].cells[0].blocks[0] else { return XCTFail() }
        XCTAssertFalse(p.runs[0].attributes.bold)
    }
}
#endif
