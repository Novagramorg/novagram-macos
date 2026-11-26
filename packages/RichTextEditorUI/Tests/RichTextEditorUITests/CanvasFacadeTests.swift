#if canImport(AppKit)
import XCTest
import AppKit
@testable import RichTextEditorUI
import RichTextEditorCore

@available(macOS 12, *)
final class CanvasFacadeTests: AppKitTestCase {
    func test_multiParagraphRoundTrips() {
        let editor = RichTextEditorView(frame: CGRect(x: 0, y: 0, width: 320, height: 400))
        let doc = Document(blocks: [
            .paragraph(ParagraphBlock(id: BlockID("a"), style: .heading1, runs: [TextRun(text: "Title")])),
            .paragraph(ParagraphBlock(id: BlockID("b"), runs: [TextRun(text: "Body one.")])),
            .paragraph(ParagraphBlock(id: BlockID("c"), runs: [TextRun(text: "Body two.")])),
        ])
        editor.document = doc
        editor.layoutSubtreeIfNeeded()
        let out = editor.document
        XCTAssertEqual(out.blocks.count, 3)
        guard case .paragraph(let p0) = out.blocks[0] else { return XCTFail() }
        XCTAssertEqual(p0.style, .heading1)
        XCTAssertEqual(out.blocks.compactMap { if case .paragraph(let p) = $0 { return p.runs.map(\.text).joined() } else { return nil } },
                       ["Title", "Body one.", "Body two."])
    }

    func test_nonParagraphBlocksArePreserved() {
        let editor = RichTextEditorView(frame: CGRect(x: 0, y: 0, width: 320, height: 400))
        let table = TableBlock(id: BlockID("t"), columns: [ColumnSpec(width: 10)],
                               rows: [Row(id: BlockID("r"), cells: [Cell(id: BlockID("c"))])])
        editor.document = Document(blocks: [.paragraph(ParagraphBlock(id: BlockID("a"), runs: [TextRun(text: "P")])),
                                            .table(table)])
        editor.layoutSubtreeIfNeeded()
        XCTAssertTrue(editor.document.blocks.contains { if case .table = $0 { return true } else { return false } })
    }

    func test_interleavedTableSurvivesStructuralEdits() {
        let editor = RichTextEditorView(frame: CGRect(x: 0, y: 0, width: 320, height: 400))
        let table = TableBlock(id: BlockID("t"), columns: [ColumnSpec(width: 10)],
                               rows: [Row(id: BlockID("r"), cells: [Cell(id: BlockID("c"))])])
        editor.document = Document(
            blocks: [
                .paragraph(ParagraphBlock(id: BlockID("a"), runs: [TextRun(text: "Alpha")])),
                .table(table),
                .paragraph(ParagraphBlock(id: BlockID("b"), runs: [TextRun(text: "Beta")])),
            ])
        editor.layoutSubtreeIfNeeded()

        // Split "Alpha" via the canvas, then merge it back via Backspace.
        editor.canvas.selectedGlobalRange = (editor.canvas.boxes[0].textStart + 2, editor.canvas.boxes[0].textStart + 2)
        editor.canvas.insertNewline(nil)

        let afterSplit = editor.document
        XCTAssertEqual(afterSplit.blocks.count, 4)                       // 3 paragraphs + table, none lost
        XCTAssertTrue(afterSplit.blocks.contains { if case .table = $0 { return true } else { return false } })
        // Table stays in its original document position (canvas renders it in place at blocks[2],
        // after the two halves of the split paragraph; blocks[1] = preservedBlocks anchor is retired).
        guard case .table = afterSplit.blocks[2] else { return XCTFail("table not at expected position after split") }

        // Now merge the two halves back; the table must still be present exactly once.
        // boxes[1] = BlockBox("pha") — the second paragraph half after the split.
        editor.canvas.selectedGlobalRange = (editor.canvas.boxes[1].textStart, editor.canvas.boxes[1].textStart)
        editor.canvas.performDeleteBackward()
        let afterMerge = editor.document
        XCTAssertEqual(afterMerge.blocks.filter { if case .table = $0 { return true } else { return false } }.count, 1)
    }

    func test_facadeSetList_appliesAcrossSelection() {
        let editor = RichTextEditorView(frame: CGRect(x: 0, y: 0, width: 320, height: 400))
        editor.document = Document(
            blocks: [.paragraph(ParagraphBlock(id: BlockID("a"), runs: [TextRun(text: "Item")]))])
        editor.layoutSubtreeIfNeeded()
        editor.selectAll()
        editor.setList(.bullet)
        guard case .paragraph(let p) = editor.document.blocks[0] else { return XCTFail() }
        XCTAssertEqual(p.list?.marker, .bullet)
    }

    func test_roundTrip_preservesLeadingAndAdjacentNonParagraphBlocks() {
        let editor = RichTextEditorView(frame: CGRect(x: 0, y: 0, width: 320, height: 400))
        func table(_ id: String) -> Block {
            .table(TableBlock(id: BlockID(id), columns: [ColumnSpec(width: 10)],
                              rows: [Row(id: BlockID(id + "r"), cells: [Cell(id: BlockID(id + "c"))])]))
        }
        editor.document = Document(
            blocks: [
                table("t0"),                                                       // leading non-paragraph
                .paragraph(ParagraphBlock(id: BlockID("a"), runs: [TextRun(text: "Alpha")])),
                table("t1"), table("t2"),                                          // two adjacent at same anchor
                .paragraph(ParagraphBlock(id: BlockID("b"), runs: [TextRun(text: "Beta")])),
            ])
        editor.layoutSubtreeIfNeeded()
        let out = editor.document.blocks
        func isTable(_ b: Block, _ id: String) -> Bool {
            if case .table(let t) = b { return t.id == BlockID(id) } else { return false }
        }
        XCTAssertEqual(out.count, 5)
        XCTAssertTrue(isTable(out[0], "t0"))
        if case .paragraph(let p) = out[1] { XCTAssertEqual(p.id, BlockID("a")) } else { XCTFail("out[1] should be paragraph a") }
        XCTAssertTrue(isTable(out[2], "t1"))
        XCTAssertTrue(isTable(out[3], "t2"))
        if case .paragraph(let p) = out[4] { XCTAssertEqual(p.id, BlockID("b")) } else { XCTFail("out[4] should be paragraph b") }
    }

    func test_imageRoundTripsThroughCanvas_withPreservedTable() {
        let editor = RichTextEditorView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        let table = TableBlock(id: BlockID("t"), columns: [ColumnSpec(width: 10)],
                               rows: [Row(id: BlockID("r"), cells: [Cell(id: BlockID("c"))])])
        // Images are macOS-only (`CanvasModelBlock.image`) and dropped from the public `[Block]` document,
        // so the mixed sequence round-trips through the canvas's internal model, not `editor.document`.
        editor.canvas.setModelBlocks([
            .core(.paragraph(ParagraphBlock(id: BlockID("a"), runs: [TextRun(text: "Alpha")]))),
            .media(MediaBlock(id: BlockID("img"), kind: .image, mediaID: "x", naturalSize: Size2D(width: 80, height: 50),
                              caption: [TextRun(text: "Cap")])),
            .core(.table(table)),
            .core(.paragraph(ParagraphBlock(id: BlockID("b"), runs: [TextRun(text: "Beta")]))),
        ], width: editor.bounds.width)
        editor.layoutSubtreeIfNeeded()
        let out = editor.canvas.currentModelBlocks()
        XCTAssertEqual(out.count, 4)
        guard case .core(.paragraph) = out[0], case .media(let img) = out[1],
              case .core(.table) = out[2], case .core(.paragraph) = out[3]
        else { return XCTFail("order/type not preserved") }
        XCTAssertEqual(img.caption.map(\.text).joined(), "Cap")
    }

    func test_facadeInsertImage_addsImageBlock() {
        let editor = RichTextEditorView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        editor.document = Document(
            blocks: [.paragraph(ParagraphBlock(id: BlockID("a"), runs: [TextRun(text: "Alpha")]))])
        editor.layoutSubtreeIfNeeded()
        editor.selectAll()
        let s = CGSize(width: 60, height: 40)
        editor.insertImage(image(of: s, fill: .systemPink), naturalSize: s)
        XCTAssertTrue(editor.canvas.boxes.contains { $0 is MediaBlockBox })   // images are hosted media boxes (like video), not the public document
    }

    func test_tableRoundTripsThroughCanvas_inOrder() {
        let editor = RichTextEditorView(frame: CGRect(x: 0, y: 0, width: 340, height: 600))
        let table = TableBlock(id: BlockID("t"), columns: [ColumnSpec(width: 100), ColumnSpec(width: 100)],
            rows: [Row(id: BlockID("r0"), cells: [
                Cell(id: BlockID("a"), blocks: [.paragraph(ParagraphBlock(id: BlockID("ap"), runs: [TextRun(text: "A")]))]),
                Cell(id: BlockID("b"), blocks: [.paragraph(ParagraphBlock(id: BlockID("bp"), runs: [TextRun(text: "B")]))])])])
        editor.document = Document(
            blocks: [
                .paragraph(ParagraphBlock(id: BlockID("p0"), runs: [TextRun(text: "Above")])),
                .table(table),
                .paragraph(ParagraphBlock(id: BlockID("p1"), runs: [TextRun(text: "Below")])),
            ])
        editor.layoutSubtreeIfNeeded()
        let out = editor.document.blocks
        XCTAssertEqual(out.count, 3)
        guard case .paragraph = out[0], case .table(let t) = out[1], case .paragraph = out[2]
        else { return XCTFail("order/type not preserved") }
        XCTAssertEqual(t.rowCount, 1); XCTAssertEqual(t.columnCount, 2)
    }
}
#endif
