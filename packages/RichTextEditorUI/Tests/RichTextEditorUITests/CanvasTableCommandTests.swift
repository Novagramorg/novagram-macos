#if canImport(AppKit)
import XCTest
import AppKit
@testable import RichTextEditorUI
import RichTextEditorCore

@available(macOS 12, *)
final class CanvasTableCommandTests: XCTestCase {
    func cell(_ id: String, _ t: String) -> Cell {
        Cell(id: BlockID(id), blocks: [.paragraph(ParagraphBlock(id: BlockID(id + "p"), runs: [TextRun(text: t)]))])
    }
    /// A 2-col table: header row (r0) + one body row (r1), inside a doc with paragraphs around it.
    func canvas() -> DocumentCanvasView {
        let v = DocumentCanvasView()
        v.setBlocks([
            .paragraph(ParagraphBlock(id: BlockID("top"), runs: [TextRun(text: "Top")])),
            .table(TableBlock(id: BlockID("t"), columns: [ColumnSpec(width: 120), ColumnSpec(width: 120)],
                rows: [Row(id: BlockID("r0"), isHeader: true, cells: [cell("a", "Name"), cell("b", "Role")]),
                       Row(id: BlockID("r1"), cells: [cell("c", "Ada"), cell("d", "Eng")])])),
            .paragraph(ParagraphBlock(id: BlockID("bot"), runs: [TextRun(text: "Bot")])),
        ], width: 320)
        v.frame = CGRect(x: 0, y: 0, width: 320, height: 700); v.layoutSubtreeIfNeeded()
        return v
    }
    func table(_ v: DocumentCanvasView) -> TableBlockBox { v.boxes.first { $0 is TableBlockBox } as! TableBlockBox }
    /// Put the caret into cell (row,col).
    func caret(_ v: DocumentCanvasView, row: Int, col: Int) {
        let pos = table(v).cellTextStart(row: row, column: col)!
        v.selectedGlobalRange = (pos, pos)
    }
    /// documentSize must equal the Core token count for the current content.
    func assertSpansMatchCore(_ v: DocumentCanvasView, _ msg: String = "") {
        let doc = Document(blocks: v.currentBlocks())
        XCTAssertEqual(v.documentSizeValue, DocumentTree.documentSize(doc), "span math \(msg)")
    }

    func test_insertRowBelow_addsBodyRow_caretInIt_spansMatch() {
        let v = canvas()
        caret(v, row: 1, col: 0)
        v.insertTableRowBelow()
        v.layoutSubtreeIfNeeded()
        XCTAssertEqual(table(v).rowCount, 3)
        XCTAssertFalse(table(v).isHeaderRow(2))
        XCTAssertEqual(v.head, table(v).cellTextStart(row: 2, column: 0), "caret in the new row")
        assertSpansMatchCore(v, "after insertRowBelow")
    }

    func test_insertRowAbove_fromHeader_insertsBelowHeader() {
        let v = canvas()
        caret(v, row: 0, col: 0)               // in the header
        v.insertTableRowAbove()
        v.layoutSubtreeIfNeeded()
        XCTAssertEqual(table(v).rowCount, 3)
        XCTAssertTrue(table(v).isHeaderRow(0), "row 0 stays the header")
        XCTAssertFalse(table(v).isHeaderRow(1), "the new row landed at index 1, a body row")
    }

    func test_deleteRow_removesBodyRow() {
        let v = canvas()
        caret(v, row: 1, col: 0)
        v.deleteTableRow()
        v.layoutSubtreeIfNeeded()
        XCTAssertEqual(table(v).rowCount, 1, "only the header remains")
        XCTAssertTrue(table(v).isHeaderRow(0))
        assertSpansMatchCore(v, "after deleteRow")
    }

    func test_deleteRow_onHeader_removesItAndPromotesNext() {
        let v = canvas()
        caret(v, row: 0, col: 0)
        v.deleteTableRow()
        v.layoutSubtreeIfNeeded()
        XCTAssertEqual(table(v).rowCount, 1, "the header row is removed")
        XCTAssertTrue(table(v).isHeaderRow(0), "the remaining row is promoted to the new header")
        assertSpansMatchCore(v, "after deleting the header row")
    }

    func test_insertRow_isUndoable() {
        let v = canvas()
        let um = UndoManager(); um.groupsByEvent = false; v.undoManagerOverride = um
        caret(v, row: 1, col: 0)
        um.beginUndoGrouping(); v.insertTableRowBelow(); um.endUndoGrouping()
        XCTAssertEqual(table(v).rowCount, 3)
        um.undo(); v.layoutSubtreeIfNeeded()
        XCTAssertEqual(table(v).rowCount, 2, "undo restores the table")
    }

    func test_rowCommands_noOpWhenCaretOutsideTable() {
        let v = canvas()
        let top = v.allLeafRegions().first { $0.ref == .paragraph(BlockID("top")) }!
        v.selectedGlobalRange = (top.globalStart, top.globalStart)
        v.insertTableRowBelow(); v.deleteTableRow()
        XCTAssertEqual(table(v).rowCount, 2, "no change when caret isn't in a table")
    }
}

@available(macOS 12, *)
extension CanvasTableCommandTests {
    func test_insertColumnRight_addsColumnPerRow_caretInIt_spansMatch() {
        let v = canvas()
        caret(v, row: 1, col: 0)
        v.insertTableColumnRight()
        v.layoutSubtreeIfNeeded()
        XCTAssertEqual(table(v).columnCount, 3)
        for r in 0..<table(v).rowCount { XCTAssertEqual(table(v).cells[r].count, 3) }
        XCTAssertEqual(v.head, table(v).cellTextStart(row: 1, column: 1), "caret in the new column")
        assertSpansMatchCore(v, "after insertColumnRight")
    }

    func test_insertColumnLeft_insertsBeforeCaretColumn() {
        let v = canvas()
        caret(v, row: 1, col: 1)
        v.insertTableColumnLeft()
        v.layoutSubtreeIfNeeded()
        XCTAssertEqual(table(v).columnCount, 3)
        XCTAssertEqual(v.head, table(v).cellTextStart(row: 1, column: 1), "caret in the inserted column")
    }

    func test_deleteColumn_removesColumnPerRow() {
        let v = canvas()
        caret(v, row: 1, col: 0)
        v.deleteTableColumn()
        v.layoutSubtreeIfNeeded()
        XCTAssertEqual(table(v).columnCount, 1)
        for r in 0..<table(v).rowCount { XCTAssertEqual(table(v).cells[r].count, 1) }
        assertSpansMatchCore(v, "after deleteColumn")
    }

    func test_deleteColumn_atOneColumn_isNoOp() {
        let v = canvas()
        caret(v, row: 1, col: 0); v.deleteTableColumn(); v.layoutSubtreeIfNeeded()  // now 1 column
        XCTAssertEqual(table(v).columnCount, 1)
        caret(v, row: 1, col: 0); v.deleteTableColumn(); v.layoutSubtreeIfNeeded()  // guard kicks in
        XCTAssertEqual(table(v).columnCount, 1, "never delete the last column (caret-based)")
    }

    private func hasTable(_ v: DocumentCanvasView) -> Bool { v.boxes.contains { $0 is TableBlockBox } }

    private func tableCount(_ v: DocumentCanvasView) -> Int {
        v.currentBlocks().filter { if case .table = $0 { return true } else { return false } }.count
    }

    func test_copyStructuralRows_extractsSubTable() {
        let v = canvas()
        v.selectTableRows(1...1, in: table(v), extending: false)   // the body row
        guard case .table(let sub) = v.selectedFragment().first else { return XCTFail("expected a table fragment") }
        XCTAssertEqual(sub.rowCount, 1, "only the selected row")
        XCTAssertEqual(sub.columnCount, 2, "all columns")
    }

    func test_copyStructuralColumns_extractsSubTable() {
        let v = canvas()
        v.selectTableColumns(0...0, in: table(v), extending: false)
        guard case .table(let sub) = v.selectedFragment().first else { return XCTFail("expected a table fragment") }
        XCTAssertEqual(sub.columnCount, 1, "only the selected column")
        XCTAssertEqual(sub.rowCount, 2, "all rows")
    }

    func test_pasteTableFragment_inParagraph_insertsNewTable() {
        let v = canvas()
        let frag: [Block] = [.table(TableBlock(id: BlockID("f"), columns: [ColumnSpec(width: 120)],
                                               rows: [Row(id: BlockID("fr"), isHeader: true, cells: [cell("fc", "X")])]))]
        let top = v.allLeafRegions().first { $0.ref == .paragraph(BlockID("top")) }!
        v.setCaret(global: top.globalStart + top.length)
        let before = tableCount(v)
        v.insertFragment(frag)
        v.layoutSubtreeIfNeeded()
        XCTAssertEqual(tableCount(v), before + 1, "a table fragment pasted in a paragraph becomes a new table")
    }

    /// Same doc as `canvas()` but the table is UNBORDERED + COMPACT — flags every table
    /// reconstruction path must thread through (each silently reset them to the Core defaults once).
    func flaggedCanvas() -> DocumentCanvasView {
        let v = DocumentCanvasView()
        v.setBlocks([
            .paragraph(ParagraphBlock(id: BlockID("top"), runs: [TextRun(text: "Top")])),
            .table(TableBlock(id: BlockID("t"), columns: [ColumnSpec(width: 120), ColumnSpec(width: 120)],
                rows: [Row(id: BlockID("r0"), isHeader: true, cells: [cell("a", "Name"), cell("b", "Role")]),
                       Row(id: BlockID("r1"), cells: [cell("c", "Ada"), cell("d", "Eng")]),
                       Row(id: BlockID("r2"), cells: [cell("e", "Lin"), cell("f", "Ops")])],
                compact: true, bordered: false)),
            .paragraph(ParagraphBlock(id: BlockID("bot"), runs: [TextRun(text: "Bot")])),
        ], width: 320)
        v.frame = CGRect(x: 0, y: 0, width: 320, height: 700); v.layoutSubtreeIfNeeded()
        return v
    }
    func tableFlags(_ v: DocumentCanvasView) -> (compact: Bool, bordered: Bool)? {
        for block in v.currentBlocks() {
            if case .table(let t) = block { return (t.compact, t.bordered) }
        }
        return nil
    }

    func test_deleteRow_preservesCompactAndBorderedFlags() {
        let v = flaggedCanvas()
        caret(v, row: 1, col: 0)
        v.deleteTableRow()
        v.layoutSubtreeIfNeeded()
        XCTAssertEqual(table(v).rowCount, 2)
        XCTAssertEqual(tableFlags(v)?.compact, true, "deleting a row keeps compact")
        XCTAssertEqual(tableFlags(v)?.bordered, false, "deleting a row keeps unbordered")
    }

    func test_copyStructuralRowsAndColumns_subTableKeepsFlags() {
        let v = flaggedCanvas()
        v.selectTableRows(1...1, in: table(v), extending: false)
        guard case .table(let rowSub)? = v.selectedFragment().first else { return XCTFail("expected a row sub-table") }
        XCTAssertEqual(rowSub.compact, true)
        XCTAssertEqual(rowSub.bordered, false)
        v.selectTableColumns(0...0, in: table(v), extending: false)
        guard case .table(let colSub)? = v.selectedFragment().first else { return XCTFail("expected a column sub-table") }
        XCTAssertEqual(colSub.compact, true)
        XCTAssertEqual(colSub.bordered, false)
    }

    func test_pasteTableFragment_reidKeepsCompactAndBorderedFlags() {
        let v = canvas()
        let frag: [Block] = [.table(TableBlock(id: BlockID("f"), columns: [ColumnSpec(width: 120)],
                                               rows: [Row(id: BlockID("fr"), isHeader: true, cells: [cell("fc", "X")])],
                                               compact: true, bordered: false))]
        let top = v.allLeafRegions().first { $0.ref == .paragraph(BlockID("top")) }!
        v.setCaret(global: top.globalStart + top.length)
        v.insertFragment(frag)
        v.layoutSubtreeIfNeeded()
        let pasted = v.currentBlocks().compactMap { block -> TableBlock? in
            if case .table(let t) = block, t.id != BlockID("t") { return t }
            return nil
        }.first
        XCTAssertEqual(pasted?.compact, true, "reid keeps compact")
        XCTAssertEqual(pasted?.bordered, false, "an unbordered table pastes back unbordered")
    }

    func test_pasteRowFragment_intoFlaggedTable_mergeKeepsFlags() {
        let v = flaggedCanvas()
        let frag: [Block] = [.table(TableBlock(id: BlockID("f"), columns: [ColumnSpec(width: 120), ColumnSpec(width: 120)],
                                               rows: [Row(id: BlockID("fr"), cells: [cell("fa", "P"), cell("fb", "Q")])]))]
        caret(v, row: 1, col: 0)
        v.insertFragment(frag)
        v.layoutSubtreeIfNeeded()
        XCTAssertEqual(table(v).rowCount, 4, "the fragment merged as a new row")
        XCTAssertEqual(tableFlags(v)?.compact, true, "merging rows keeps compact")
        XCTAssertEqual(tableFlags(v)?.bordered, false, "merging rows does not re-border the table")
    }

    func test_pasteRowFragment_intoMatchingTable_insertsRows() {
        let v = canvas()
        let frag: [Block] = [.table(TableBlock(id: BlockID("f"), columns: [ColumnSpec(width: 120), ColumnSpec(width: 120)],
                                               rows: [Row(id: BlockID("fr"), cells: [cell("fa", "P"), cell("fb", "Q")])]))]
        caret(v, row: 1, col: 0)
        let before = table(v).rowCount
        v.insertFragment(frag)
        v.layoutSubtreeIfNeeded()
        XCTAssertEqual(table(v).rowCount, before + 1, "a same-width table fragment merges as a new row")
        XCTAssertEqual(tableCount(v), 1, "no extra table is created")
    }

    func test_pasteColumnFragment_intoMatchingTable_insertsColumns() {
        let v = canvas()
        let frag: [Block] = [.table(TableBlock(id: BlockID("f"), columns: [ColumnSpec(width: 120)],
                                               rows: [Row(id: BlockID("r0"), isHeader: true, cells: [cell("ca", "H")]),
                                                      Row(id: BlockID("r1"), cells: [cell("cb", "B")])]))]
        caret(v, row: 0, col: 0)
        let before = table(v).columnCount
        v.insertFragment(frag)
        v.layoutSubtreeIfNeeded()
        XCTAssertEqual(table(v).columnCount, before + 1, "a same-height table fragment merges as a new column")
        XCTAssertEqual(tableCount(v), 1, "no extra table is created")
    }

    func test_shiftClickHandle_extendsRowSelection() {
        let v = canvas()
        let t = table(v)
        v.selectTableRows(0...0, in: t, extending: false)
        XCTAssertEqual(v.tableSelection?.kind, .rows(0...0), "first click selects the one row")
        v.selectTableRows(1...1, in: t, extending: true)
        XCTAssertEqual(v.tableSelection?.kind, .rows(0...1), "shift-click grows the selection to span both rows")
    }

    func test_shiftClickHandle_extendsColumnSelection_andGrowsEitherDirection() {
        let v = canvas()
        let t = table(v)
        v.selectTableColumns(1...1, in: t, extending: false)
        v.selectTableColumns(0...0, in: t, extending: true)   // shift-click a column BEFORE the selected one
        XCTAssertEqual(v.tableSelection?.kind, .columns(0...1), "extension grows leftward too")
    }

    func test_clickWithoutShift_replacesSelection() {
        let v = canvas()
        let t = table(v)
        v.selectTableRows(0...1, in: t, extending: false)
        v.selectTableRows(1...1, in: t, extending: false)     // plain click resets to the single row
        XCTAssertEqual(v.tableSelection?.kind, .rows(1...1))
    }

    func test_structuralSelectAllColumns_delete_dropsWholeTable() {
        let v = canvas()
        caret(v, row: 0, col: 0)
        v.selectTableColumns(0...1)        // every column
        v.performDeleteBackward()
        v.layoutSubtreeIfNeeded()
        XCTAssertFalse(hasTable(v), "Delete on an all-columns structural selection removes the whole table")
    }

    func test_structuralSelectAllRows_delete_dropsWholeTable() {
        let v = canvas()
        caret(v, row: 0, col: 0)
        v.selectTableRows(0...1)           // every row
        v.performDeleteBackward()
        v.layoutSubtreeIfNeeded()
        XCTAssertFalse(hasTable(v), "Delete on an all-rows structural selection removes the whole table")
    }

    // The reported scenario: 2×2 → delete a column → 2×1, then select that single column and press Delete.
    func test_singleColumnTable_selectColumn_delete_dropsTable() {
        let v = canvas()
        caret(v, row: 1, col: 0); v.deleteTableColumn(); v.layoutSubtreeIfNeeded()  // 2×2 → 2×1
        XCTAssertEqual(table(v).columnCount, 1)
        caret(v, row: 0, col: 0)
        v.selectTableColumns(0...0)        // the only column, selected via its handle
        v.performDeleteBackward()
        v.layoutSubtreeIfNeeded()
        XCTAssertFalse(hasTable(v), "selecting the only column and pressing Delete drops the whole table")
    }
}

@available(macOS 12, *)
extension CanvasTableCommandTests {
    private func columnAlignment(_ v: DocumentCanvasView, _ col: Int) -> TextAlignment? {
        guard case .table(let out) = v.currentBlocks().first(where: { if case .table = $0 { return true } else { return false } }) else { return nil }
        return out.rows.first.flatMap { col < $0.cells.count ? $0.cells[col].horizontalAlignment : nil }
    }

    func test_setColumnAlignment_collapsed_appliesToCaretColumn() {
        let v = canvas()
        caret(v, row: 1, col: 1)
        v.setTableColumnAlignment(.right)
        v.layoutSubtreeIfNeeded()
        XCTAssertEqual(columnAlignment(v, 1), .right)
        XCTAssertEqual(columnAlignment(v, 0), .center, "other column unchanged (cells default to .center)")
    }

    func test_setColumnAlignment_spansSelectedColumns() {
        let v = canvas()
        // Selection from cell (1,0) to cell (1,1) → spans columns 0 and 1.
        let from = table(v).cellTextStart(row: 1, column: 0)!
        let to = table(v).cellTextStart(row: 1, column: 1)!
        v.selectedGlobalRange = (from, to)
        v.setTableColumnAlignment(.right)
        v.layoutSubtreeIfNeeded()
        XCTAssertEqual(columnAlignment(v, 0), .right)
        XCTAssertEqual(columnAlignment(v, 1), .right)
    }

    func test_setColumnAlignment_isUndoable() {
        let v = canvas()
        let um = UndoManager(); um.groupsByEvent = false; v.undoManagerOverride = um
        caret(v, row: 1, col: 1)
        um.beginUndoGrouping(); v.setTableColumnAlignment(.right); um.endUndoGrouping()
        XCTAssertEqual(columnAlignment(v, 1), .right)
        um.undo(); v.layoutSubtreeIfNeeded()
        XCTAssertEqual(columnAlignment(v, 1), .center, "undo restores alignment (default .center)")
    }
}

@available(macOS 12, *)
extension CanvasTableCommandTests {
    private func cellBackground(_ v: DocumentCanvasView, _ row: Int, _ col: Int) -> RGBAColor? {
        guard case .table(let out) = v.currentBlocks().first(where: { if case .table = $0 { return true } else { return false } }) else { return nil }
        return out.rows[row].cells[col].background
    }
    private var red: RGBAColor { RGBAColor(red: 1, green: 0, blue: 0, alpha: 1) }

    func test_setCellHighlight_collapsed_appliesToCaretCell_only() {
        let v = canvas()
        caret(v, row: 1, col: 1)
        v.setTableCellBackground(red)
        v.layoutSubtreeIfNeeded()
        XCTAssertEqual(cellBackground(v, 1, 1), red, "the caret's cell is highlighted")
        XCTAssertNil(cellBackground(v, 1, 0), "a neighbour cell is untouched")
        XCTAssertNil(cellBackground(v, 0, 1), "a neighbour cell is untouched")
    }

    func test_removeCellHighlight_clearsBackground() {
        let v = canvas()
        caret(v, row: 1, col: 1)
        v.setTableCellBackground(red); v.layoutSubtreeIfNeeded()
        XCTAssertEqual(cellBackground(v, 1, 1), red)
        caret(v, row: 1, col: 1)
        v.setTableCellBackground(nil); v.layoutSubtreeIfNeeded()
        XCTAssertNil(cellBackground(v, 1, 1), "Remove Highlight clears the cell background")
    }

    func test_setCellHighlight_multiCellTextSelection_coversBoundingCells() {
        let v = canvas()
        // Selection from cell (0,0) to cell (1,1) → bounding box covers all four cells.
        let from = table(v).cellTextStart(row: 0, column: 0)!
        let to = table(v).cellTextStart(row: 1, column: 1)!
        v.selectedGlobalRange = (from, to)
        v.setTableCellBackground(red)
        v.layoutSubtreeIfNeeded()
        for r in 0...1 { for c in 0...1 { XCTAssertEqual(cellBackground(v, r, c), red, "cell (\(r),\(c)) highlighted") } }
    }

    func test_setCellHighlight_structuralRowSelection_coversWholeRow() {
        let v = canvas()
        caret(v, row: 1, col: 0)
        v.selectTableRows(1...1)             // the body row, via its handle
        v.setTableCellBackground(red)
        v.layoutSubtreeIfNeeded()
        XCTAssertEqual(cellBackground(v, 1, 0), red)
        XCTAssertEqual(cellBackground(v, 1, 1), red, "every column of the selected row is highlighted")
        XCTAssertNil(cellBackground(v, 0, 0), "the unselected row is untouched")
    }

    func test_setCellHighlight_structuralColumnSelection_coversWholeColumn() {
        let v = canvas()
        caret(v, row: 0, col: 1)
        v.selectTableColumns(1...1)          // the second column, via its handle
        v.setTableCellBackground(red)
        v.layoutSubtreeIfNeeded()
        XCTAssertEqual(cellBackground(v, 0, 1), red)
        XCTAssertEqual(cellBackground(v, 1, 1), red, "every row of the selected column is highlighted")
        XCTAssertNil(cellBackground(v, 0, 0), "the unselected column is untouched")
    }

    func test_setCellHighlight_isUndoable() {
        let v = canvas()
        let um = UndoManager(); um.groupsByEvent = false; v.undoManagerOverride = um
        caret(v, row: 1, col: 1)
        um.beginUndoGrouping(); v.setTableCellBackground(red); um.endUndoGrouping()
        XCTAssertEqual(cellBackground(v, 1, 1), red)
        um.undo(); v.layoutSubtreeIfNeeded()
        XCTAssertNil(cellBackground(v, 1, 1), "undo restores the cleared background")
    }

    func test_rightClickInCell_movesCaretIntoThatCell() {
        let v = canvas()
        let top = v.allLeafRegions().first { $0.ref == .paragraph(BlockID("top")) }!
        v.selectedGlobalRange = (top.globalStart, top.globalStart)   // caret starts outside the table
        XCTAssertNil(v.activeTable(), "precondition: caret outside the table")
        let rect = table(v).cellRect(row: 1, column: 1)!
        v.placeCaretForContextClick(at: CGPoint(x: rect.midX, y: rect.midY))
        XCTAssertEqual(v.activeTable()?.row, 1, "right-click in a cell moves the caret to that row")
        XCTAssertEqual(v.activeTable()?.col, 1, "…and that column")
    }

    func test_rightClickWithSelection_keepsSelection_doesNotMoveCaret() {
        let v = canvas()
        let top = v.allLeafRegions().first { $0.ref == .paragraph(BlockID("top")) }!
        v.selectedGlobalRange = (top.globalStart, top.globalStart + 1)   // an active selection in "Top"
        let rect = table(v).cellRect(row: 1, column: 1)!
        v.placeCaretForContextClick(at: CGPoint(x: rect.midX, y: rect.midY))
        XCTAssertNil(v.activeTable(), "an active selection is preserved; the caret isn't pulled into the table")
    }

    // The predicate the façade's `isCaretInTable` (host's context-aware table menu) reads.
    func test_activeTable_reflectsCaretLocation() {
        let v = canvas()
        caret(v, row: 1, col: 0)
        XCTAssertNotNil(v.activeTable(), "caret in a cell → in a table")
        let top = v.allLeafRegions().first { $0.ref == .paragraph(BlockID("top")) }!
        v.selectedGlobalRange = (top.globalStart, top.globalStart)
        XCTAssertNil(v.activeTable(), "caret in a top-level paragraph → not in a table")
    }

    func test_setCellHighlight_noOpOutsideTable() {
        let v = canvas()
        let top = v.allLeafRegions().first { $0.ref == .paragraph(BlockID("top")) }!
        v.selectedGlobalRange = (top.globalStart, top.globalStart)
        v.setTableCellBackground(red)
        XCTAssertNil(cellBackground(v, 1, 1), "no change when the caret isn't in a table")
    }

    func test_toggleTableBordered_flipsFlag_asOneUndoStep() {
        let v = canvas()
        let um = UndoManager(); um.groupsByEvent = false
        v.undoManagerOverride = um
        caret(v, row: 1, col: 0)
        um.beginUndoGrouping(); v.toggleTableBordered(); um.endUndoGrouping()
        XCTAssertEqual(tableFlags(v)?.bordered, false)
        assertSpansMatchCore(v, "after toggleTableBordered")
        um.undo()
        XCTAssertEqual(tableFlags(v)?.bordered, true, "one undo restores the border")
        um.redo()
        XCTAssertEqual(tableFlags(v)?.bordered, false)
    }

    func test_toggleTableCompact_flipsFlag_leavesBorderedAlone() {
        let v = flaggedCanvas()                          // compact: true, bordered: false
        caret(v, row: 1, col: 0)
        v.toggleTableCompact()
        XCTAssertEqual(tableFlags(v)?.compact, false)
        XCTAssertEqual(tableFlags(v)?.bordered, false, "the compact toggle leaves bordered alone")
        v.toggleTableCompact()
        XCTAssertEqual(tableFlags(v)?.compact, true)
        assertSpansMatchCore(v, "after toggleTableCompact")
    }

    func test_toggleBorderedOrCompact_outsideTable_noops() {
        let v = canvas()
        let top = v.allLeafRegions().first { $0.ref == .paragraph(BlockID("top")) }!
        v.selectedGlobalRange = (top.globalStart, top.globalStart)
        v.toggleTableBordered()
        v.toggleTableCompact()
        XCTAssertEqual(tableFlags(v)?.bordered, true, "no change when the caret isn't in a table")
        XCTAssertEqual(tableFlags(v)?.compact, false)
    }

    func test_insertTable_startsCompact() {
        let v = DocumentCanvasView()
        v.setBlocks([.paragraph(ParagraphBlock(id: BlockID("p"), runs: [TextRun(text: "Hi")]))], width: 320)
        v.frame = CGRect(x: 0, y: 0, width: 320, height: 400); v.layoutSubtreeIfNeeded()
        v.selectedGlobalRange = (v.boxes[0].textStart + 2, v.boxes[0].textStart + 2)
        v.insertTable(rows: 2, columns: 2)
        XCTAssertEqual(tableFlags(v)?.compact, true, "a fresh table starts compact")
        XCTAssertEqual(tableFlags(v)?.bordered, true, "…and bordered (only the padding is compact)")
    }

    func test_unborderedTable_shorterThanBordered_gapsCollapse() {
        // The table stretches to the content WIDTH either way; the collapsed border gaps show in the
        // stacked row HEIGHT — proving the flag is a relayout (border width participates as 0), not a
        // repaint.
        let bordered = canvas()
        let unbordered = canvas()
        caret(unbordered, row: 1, col: 0)
        unbordered.toggleTableBordered()
        unbordered.layoutSubtreeIfNeeded()
        XCTAssertLessThan(table(unbordered).height, table(bordered).height,
                          "row gaps collapse when the border width participates as 0")
    }
}
#endif
