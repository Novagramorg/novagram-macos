#if canImport(AppKit)
import XCTest
import AppKit
@testable import RichTextEditorUI
import RichTextEditorCore

@available(macOS 12, *)
final class RichTextEditorViewTests: XCTestCase {
    // A content-height change after an edit re-flows the host layout (canvas frame), not only on the
    // next external layout pass (e.g. a rotation). Pre-fix the edit never marked the host dirty, so a
    // normal layout pass left the canvas at its old height.
    func test_editGrowingContent_reflowsCanvasHeight() {
        let editor = RichTextEditorView(frame: CGRect(x: 0, y: 0, width: 320, height: 400))
        editor.document = Document(blocks: [.paragraph(ParagraphBlock(id: BlockID("p"), runs: [TextRun(text: "Hello")]))])
        editor.layoutSubtreeIfNeeded()
        let before = editor.canvas.frame.height
        // Add a paragraph at the end (Enter) → taller content.
        editor.canvas.selectedGlobalRange = (editor.canvas.documentSizeValue, editor.canvas.documentSizeValue)
        editor.canvas.insertNewline(nil)
        editor.layoutSubtreeIfNeeded()   // a normal layout pass — the edit must have marked the host dirty
        XCTAssertGreaterThan(editor.canvas.frame.height, before,
                             "host re-sizes the canvas when content height grows after an edit")
    }

    // The canvas notifies its host whenever it invalidates its intrinsic content size.
    func test_canvas_notifiesHostOnContentSizeChange() {
        let v = DocumentCanvasView()
        v.setBlocks([.paragraph(ParagraphBlock(id: BlockID("p"), runs: [TextRun(text: "Hi")]))], width: 320)
        v.frame = CGRect(x: 0, y: 0, width: 320, height: 200); v.layoutSubtreeIfNeeded()
        var fired = false
        v.onContentSizeChange = { fired = true }
        v.selectedGlobalRange = (v.documentSizeValue, v.documentSizeValue)
        v.insertNewline(nil)
        XCTAssertTrue(fired, "a height-changing edit notifies the host to re-layout")
    }
}

@available(macOS 12, *)
extension RichTextEditorViewTests {
    private func editorWithTable() -> RichTextEditorView {
        let e = RichTextEditorView(frame: CGRect(x: 0, y: 0, width: 320, height: 600))
        e.document = Document(blocks: [
            .table(TableBlock(id: BlockID("t"), columns: [ColumnSpec(width: 120), ColumnSpec(width: 120)],
                rows: [Row(id: BlockID("r0"), isHeader: true,
                           cells: [Cell(id: BlockID("a"), blocks: [.paragraph(ParagraphBlock(id: BlockID("ap"), runs: [TextRun(text: "Name")]))]),
                                   Cell(id: BlockID("b"), blocks: [.paragraph(ParagraphBlock(id: BlockID("bp"), runs: [TextRun(text: "Role")]))])]),
                       Row(id: BlockID("r1"),
                           cells: [Cell(id: BlockID("c"), blocks: [.paragraph(ParagraphBlock(id: BlockID("cp"), runs: [TextRun(text: "Ada")]))]),
                                   Cell(id: BlockID("d"), blocks: [.paragraph(ParagraphBlock(id: BlockID("dp"), runs: [TextRun(text: "Eng")]))])])])),
        ])
        e.layoutSubtreeIfNeeded()
        return e
    }

    func test_facadeInsertTableRow_delegatesToCanvas() {
        let e = editorWithTable()
        let t = e.canvas.boxes.first as! TableBlockBox
        let pos = t.cellTextStart(row: 1, column: 0)!
        e.canvas.selectedGlobalRange = (pos, pos)
        e.insertTableRowBelow()
        e.layoutSubtreeIfNeeded()
        XCTAssertEqual((e.canvas.boxes.first as! TableBlockBox).rowCount, 3)
    }

    func test_facadeSetColumnAlignment_delegatesToCanvas() {
        let e = editorWithTable()
        let t = e.canvas.boxes.first as! TableBlockBox
        let pos = t.cellTextStart(row: 1, column: 1)!
        e.canvas.selectedGlobalRange = (pos, pos)
        e.setTableColumnAlignment(.center)
        e.layoutSubtreeIfNeeded()
        guard case .table(let out) = e.document.blocks.first(where: { if case .table = $0 { return true } else { return false } }) else { return XCTFail() }
        XCTAssertEqual(out.rows[1].cells[1].horizontalAlignment, .center)
    }
}
#endif
