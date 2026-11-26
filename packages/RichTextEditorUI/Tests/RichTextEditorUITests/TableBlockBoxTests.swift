#if canImport(AppKit)
import XCTest
import AppKit
@testable import RichTextEditorUI
import RichTextEditorCore

@available(macOS 12, *)
final class TableBlockBoxTests: AppKitTestCase {
    private func cell(_ id: String, _ text: String, hAlign: TextAlignment = .left) -> Cell {
        Cell(id: BlockID(id), blocks: [.paragraph(ParagraphBlock(id: BlockID(id + "p"), runs: [TextRun(text: text)]))],
             horizontalAlignment: hAlign)
    }
    private func table2x2() -> TableBlock {
        TableBlock(id: BlockID("t"), columns: [ColumnSpec(width: 100), ColumnSpec(width: 100)],
                   rows: [Row(id: BlockID("r0"), cells: [cell("a", "A"), cell("b", "B")]),
                          Row(id: BlockID("r1"), cells: [cell("c", "C"), cell("d", "D")])])
    }

    func test_mixedDoc_spansMatchCorePositionModel() {
        let v = DocumentCanvasView()
        v.setBlocks([
            .paragraph(ParagraphBlock(id: BlockID("top"), runs: [TextRun(text: "Top")])),
            .table(table2x2()),
            .paragraph(ParagraphBlock(id: BlockID("bot"), runs: [TextRun(text: "Bot")])),
        ], width: 320)
        v.frame = CGRect(x: 0, y: 0, width: 320, height: 600); v.layoutSubtreeIfNeeded()
        let doc = Document(blocks: v.currentBlocks())
        let tree = DocumentTree.build(from: doc)
        XCTAssertEqual(v.documentSizeValue, DocumentTree.documentSize(doc))
        // Each cell's paragraph text node global start matches Core.
        for id in ["ap", "bp", "cp", "dp"] {
            let core = PositionResolver.globalPosition(of: .paragraph(BlockID(id)), offset: 0, in: tree)
            let region = v.allLeafRegions().first { $0.ref == .paragraph(BlockID(id)) }
            XCTAssertNotNil(region)
            XCTAssertEqual(region?.globalStart, core, "cell \(id)")
        }
    }

    func test_tableRoundTripsThroughCurrentBlocks() {
        let v = DocumentCanvasView()
        v.setBlocks([.table(table2x2())], width: 320)
        v.frame = CGRect(x: 0, y: 0, width: 320, height: 400); v.layoutSubtreeIfNeeded()
        guard case .table(let out) = v.currentBlocks()[0] else { return XCTFail("expected table") }
        XCTAssertEqual(out.rowCount, 2); XCTAssertEqual(out.columnCount, 2)
        XCTAssertEqual(out.rows[1].cells[1].blocks.count, 1)
    }

    func test_tableRendersNonBlank() {
        let v = DocumentCanvasView()
        v.setBlocks([.table(table2x2())], width: 320)
        v.frame = CGRect(x: 0, y: 0, width: 320, height: 400); v.layoutSubtreeIfNeeded()
        let image = snapshot(v)
        XCTAssertNotNil(image.cgImage)
    }

    // An EMPTY cell reserves one line of its font's height (so its row doesn't collapse to the insets),
    // matching a single-line filled cell in the same row.
    func test_emptyCellReservesLineHeight() {
        let v = DocumentCanvasView()
        let empty = Cell(id: BlockID("a"), blocks: [.paragraph(ParagraphBlock(id: BlockID("ap"), runs: []))])
        let filled = Cell(id: BlockID("b"), blocks: [.paragraph(ParagraphBlock(id: BlockID("bp"), runs: [TextRun(text: "Beta")]))])
        v.setBlocks([.table(TableBlock(id: BlockID("t"), columns: [ColumnSpec(width: 120), ColumnSpec(width: 120)],
            rows: [Row(id: BlockID("r0"), cells: [empty, filled])]))], width: 320)
        v.frame = CGRect(x: 0, y: 0, width: 320, height: 300); v.layoutSubtreeIfNeeded()
        let table = v.boxes.first as! TableBlockBox
        let emptyBox = table.cells[0][0].boxes[0]
        let filledBox = table.cells[0][1].boxes[0]
        XCTAssertEqual(emptyBox.height, filledBox.height, accuracy: 1.0,
                       "an empty cell reserves a real line, matching a single-line filled cell")
        XCTAssertGreaterThan(emptyBox.height, 20, "not collapsed to just the insets")
    }

    // A wholly-empty row keeps a real line's height (≈ a filled row), not just topInset+bottomInset.
    func test_emptyRowDoesNotCollapse() {
        let v = DocumentCanvasView()
        v.setBlocks([.table(TableBlock(id: BlockID("t"), columns: [ColumnSpec(width: 120), ColumnSpec(width: 120)],
            rows: [
                Row(id: BlockID("r0"), cells: [cell("a", "Alpha"), cell("b", "Beta")]),
                Row(id: BlockID("r1"), cells: [
                    Cell(id: BlockID("c"), blocks: [.paragraph(ParagraphBlock(id: BlockID("cp"), runs: []))]),
                    Cell(id: BlockID("d"), blocks: [.paragraph(ParagraphBlock(id: BlockID("dp"), runs: []))]),
                ]),
            ]))], width: 320)
        v.frame = CGRect(x: 0, y: 0, width: 320, height: 400); v.layoutSubtreeIfNeeded()
        // The empty row's cells lay out at the same height as the filled row's cells.
        let table = v.boxes.first as! TableBlockBox
        let filledRowBox = table.cells[0][0].boxes[0]
        let emptyRowBox = table.cells[1][0].boxes[0]
        XCTAssertEqual(emptyRowBox.height, filledRowBox.height, accuracy: 1.0,
                       "an empty row keeps a real line's height")
    }
}

@available(macOS 12, *)
extension TableBlockBoxTests {
    private func headerTable() -> TableBlock {
        TableBlock(id: BlockID("t"),
                   columns: [ColumnSpec(width: 120), ColumnSpec(width: 120)],
                   rows: [
                       Row(id: BlockID("r0"), isHeader: true, cells: [cell("a", "Name"), cell("b", "Role", hAlign: .center)]),
                       Row(id: BlockID("r1"), cells: [cell("c", "Ada"), cell("d", "Eng", hAlign: .center)]),
                   ])
    }
    private func box(_ v: DocumentCanvasView) -> TableBlockBox { v.boxes.first as! TableBlockBox }
    private func cellFont(_ t: TableBlockBox, _ r: Int, _ c: Int) -> NSFont {
        let b = t.cells[r][c].boxes[0] as! BlockBox
        return b.layout.attributedString.attribute(.font, at: 0, effectiveRange: nil) as! NSFont
    }
    private func cellAlignment(_ t: TableBlockBox, _ r: Int, _ c: Int) -> NSTextAlignment {
        let b = t.cells[r][c].boxes[0] as! BlockBox
        let ps = b.layout.attributedString.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        return ps?.alignment ?? .natural
    }

    func test_firstRowRendersBold_otherRowsDoNot() {
        let v = DocumentCanvasView()
        v.setBlocks([.table(headerTable())], width: 320)
        v.frame = CGRect(x: 0, y: 0, width: 320, height: 400); v.layoutSubtreeIfNeeded()
        let t = box(v)
        // The header row (row 0) renders bold in every column; body rows do not.
        XCTAssertTrue(cellFont(t, 0, 0).fontDescriptor.symbolicTraits.contains(.bold), "header row col 0 bold")
        XCTAssertTrue(cellFont(t, 0, 1).fontDescriptor.symbolicTraits.contains(.bold), "header row col 1 bold")
        XCTAssertFalse(cellFont(t, 1, 0).fontDescriptor.symbolicTraits.contains(.bold), "body row col 0 not bold")
        XCTAssertFalse(cellFont(t, 1, 1).fontDescriptor.symbolicTraits.contains(.bold), "body row col 1 not bold")
    }

    func test_headerRowBackground_coversFirstRowOnly_withGrayTint() {
        let v = DocumentCanvasView()
        v.setBlocks([.table(headerTable())], width: 320)
        v.frame = CGRect(x: 0, y: 0, width: 320, height: 400); v.layoutSubtreeIfNeeded()
        let t = box(v)
        let rect = t.headerRowBackgroundRect()!
        let header = t.cellRect(row: 0, column: 1)!, body = t.cellRect(row: 1, column: 0)!
        XCTAssertEqual(rect.minY, t.frame.minY, accuracy: 0.5)                       // starts at the table top
        XCTAssertTrue(rect.contains(CGPoint(x: header.midX, y: header.midY)))        // covers the header row
        XCTAssertFalse(rect.contains(CGPoint(x: body.midX, y: body.midY)))           // not the body row
        XCTAssertGreaterThan(rect.width, t.cellRect(row: 0, column: 0)!.width)       // spans the full table width
        var alpha: CGFloat = 1
        TableBlockBox.headerRowBackground.getWhite(nil, alpha: &alpha)
        XCTAssertLessThan(alpha, 1)                                                  // a translucent gray tint
    }

    func test_headerBold_isStrippedFromModelOnExtraction() {
        let v = DocumentCanvasView()
        v.setBlocks([.table(headerTable())], width: 320)
        v.frame = CGRect(x: 0, y: 0, width: 320, height: 400); v.layoutSubtreeIfNeeded()
        guard case .table(let out) = v.currentBlocks()[0] else { return XCTFail("expected table") }
        // Header cell runs are NOT bold in the model (render-only; markdown-clean).
        guard case .paragraph(let p) = out.rows[0].cells[0].blocks[0] else { return XCTFail() }
        XCTAssertFalse(p.runs.first?.attributes.bold ?? true)
    }

    func test_columnAlignment_rendersAndRoundTripsClean() {
        let v = DocumentCanvasView()
        v.setBlocks([.table(headerTable())], width: 320)
        v.frame = CGRect(x: 0, y: 0, width: 320, height: 400); v.layoutSubtreeIfNeeded()
        let t = box(v)
        XCTAssertEqual(cellAlignment(t, 1, 1), .center, "column 1 renders centered")
        XCTAssertEqual(cellAlignment(t, 1, 0), .left, "column 0 stays left")
        guard case .table(let out) = v.currentBlocks()[0] else { return XCTFail("expected table") }
        XCTAssertEqual(out.rows[1].cells[1].horizontalAlignment, .center, "alignment lives on the Cell")
        guard case .paragraph(let p) = out.rows[1].cells[1].blocks[0] else { return XCTFail() }
        XCTAssertEqual(p.paragraph.alignment, .natural, "the cell's own paragraph alignment is untouched (render override is separate)")
    }
}
#endif
