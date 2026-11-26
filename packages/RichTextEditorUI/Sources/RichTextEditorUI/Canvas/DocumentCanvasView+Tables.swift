#if canImport(AppKit)
import AppKit
import RichTextEditorCore

/// Table structural commands. Each takes the live table via `currentBlock()`, applies a pure
/// `TableBlock` transform (Core), and rebuilds the one `TableBlockBox` inside `editing { }` so undo
/// is the existing whole-document `[Block]` snapshot. The structural commands below no-op when the
/// caret isn't in a table; `insertTable` is the inverse — it no-ops when the caret IS in a table (or
/// on an image/gap).
@available(macOS 12, *)
extension DocumentCanvasView {
    /// The table box containing the caret (`head`), its index in `boxes`, and the caret's (row, col).
    func activeTable() -> (box: TableBlockBox, index: Int, row: Int, col: Int)? {
        for (i, b) in boxes.enumerated() {
            if let t = b as? TableBlockBox, let loc = t.cellLocation(containing: head) {
                return (t, i, loc.row, loc.column)
            }
        }
        return nil
    }

    /// Swaps a freshly-built box for `newTable` at `index`, recomputes spans, and lands the caret in
    /// cell (caretRow, caretCol) clamped to the new geometry. Call inside `editing { … }`.
    func replaceTable(at index: Int, with newTable: TableBlock, caretRow: Int, caretCol: Int) {
        let newBox = TableBlockBox(table: newTable, mapper: mapper, width: effectiveWidth)
        var nb = boxes
        nb[index] = newBox
        boxes = nb
        recomputeSpans()
        let r = min(max(caretRow, 0), max(newBox.rowCount - 1, 0))
        let c = min(max(caretCol, 0), max(newBox.columnCount - 1, 0))
        if let pos = newBox.cellTextStart(row: r, column: c) { anchor = pos; head = pos }
    }

    /// Flips the table's `bordered` flag (V2: border width participates as 0 when off, so cell gaps
    /// collapse too — a relayout, not a repaint).
    func toggleTableBordered() {
        guard let a = activeTable() else { return }
        editing {
            guard case .table(let table) = a.box.currentBlock() else { return }
            var toggled = table
            toggled.bordered.toggle()
            replaceTable(at: a.index, with: toggled, caretRow: a.row, caretCol: a.col)
        }
    }

    /// Flips the caret's table between compact (halved cell padding) and normal, as one undo step.
    func toggleTableCompact() {
        guard let a = activeTable() else { return }
        editing {
            guard case .table(let table) = a.box.currentBlock() else { return }
            var toggled = table
            toggled.compact.toggle()
            replaceTable(at: a.index, with: toggled, caretRow: a.row, caretCol: a.col)
        }
    }

    func insertTableRowAbove() {
        guard let a = activeTable() else { return }
        editing {
            guard case .table(let table) = a.box.currentBlock() else { return }
            let range = structuralRowRange() ?? (a.row...a.row)
            let at = max(range.lowerBound, 1)   // never above the header (row 0)
            replaceTable(at: a.index, with: table.insertingRow(at: at), caretRow: at, caretCol: a.col)
        }
    }

    func insertTableRowBelow() {
        guard let a = activeTable() else { return }
        editing {
            guard case .table(let table) = a.box.currentBlock() else { return }
            let range = structuralRowRange() ?? (a.row...a.row)
            let at = range.upperBound + 1
            replaceTable(at: a.index, with: table.insertingRow(at: at), caretRow: at, caretCol: a.col)
        }
    }

    func deleteTableRow() {
        guard let a = activeTable() else { return }
        guard case .table(let table) = a.box.currentBlock() else { return }
        let range = structuralRowRange() ?? (a.row...a.row)
        let kept = table.rows.indices.filter { !range.contains($0) }
        editing {
            if kept.isEmpty {
                deleteTableBlock(at: a.index)                      // every row selected → drop the whole table
            } else {
                var rows = kept.map { table.rows[$0] }
                // A table keeps a (bold) header row. Header-ness now lives per-cell (`Row.isHeader` is a
                // computed all-cells-are-headers getter), so promote the row by flagging its cells.
                if !rows[0].isHeader { rows[0].cells = rows[0].cells.map { var c = $0; c.isHeader = true; return c } }
                replaceTable(at: a.index, with: TableBlock(id: table.id, columns: table.columns, rows: rows,
                                                           compact: table.compact, bordered: table.bordered),
                             caretRow: range.lowerBound, caretCol: a.col)
            }
        }
        clearTableSelection()
    }

    /// Removes the whole table block at `index` (used when a row-delete selects every row). Keeps the
    /// document non-empty (a lone empty paragraph) and lands the caret on a real position. Call inside
    /// `editing { … }`.
    func deleteTableBlock(at index: Int) {
        guard boxes.indices.contains(index) else { return }
        var nb = boxes
        nb.remove(at: index)
        if nb.isEmpty {
            nb = [BlockBox(paragraph: ParagraphBlock(id: BlockID.generate(), runs: []), mapper: mapper, width: effectiveWidth)]
        }
        boxes = nb
        recomputeSpans()
        let target = boxes[min(index, boxes.count - 1)].textStart
        let caret = snapToRenderable(target, forward: true)
        anchor = caret; head = caret
    }

    /// Default width for a new column (markdown ignores widths; this keeps proportions sane).
    private func defaultNewColumnWidth(_ table: TableBlock) -> Double {
        guard !table.columns.isEmpty else { return 120 }
        return table.columns.reduce(0) { $0 + $1.width } / Double(table.columns.count)
    }

    func insertTableColumnLeft() {
        guard let a = activeTable() else { return }
        editing {
            guard case .table(let table) = a.box.currentBlock() else { return }
            let range = structuralColumnRange() ?? (a.col...a.col)
            let new = table.insertingColumn(at: range.lowerBound, width: defaultNewColumnWidth(table))
            replaceTable(at: a.index, with: new, caretRow: a.row, caretCol: range.lowerBound)
        }
    }

    func insertTableColumnRight() {
        guard let a = activeTable() else { return }
        editing {
            guard case .table(let table) = a.box.currentBlock() else { return }
            let range = structuralColumnRange() ?? (a.col...a.col)
            let at = range.upperBound + 1
            let new = table.insertingColumn(at: at, width: defaultNewColumnWidth(table))
            replaceTable(at: a.index, with: new, caretRow: a.row, caretCol: at)
        }
    }

    func deleteTableColumn() {
        guard let a = activeTable() else { return }
        guard case .table(let table) = a.box.currentBlock() else { return }
        let structural = structuralColumnRange()
        let range = structural ?? (a.col...a.col)
        let removable = range.filter { table.columns.indices.contains($0) }.count
        // A STRUCTURAL selection covering every column drops the whole table (mirrors deleteTableRow's
        // all-rows case). A caret-based delete of the only column stays a no-op (keeps the table) —
        // guarded before `editing` so it registers no undo.
        let dropsTable = structural != nil && removable >= table.columnCount
        guard dropsTable || table.columnCount > removable else { return }
        editing {
            if dropsTable {
                deleteTableBlock(at: a.index)
            } else {
                replaceTable(at: a.index, with: table.removingColumns(in: range),
                             caretRow: a.row, caretCol: range.lowerBound)
            }
        }
        clearTableSelection()
    }

    /// The inclusive column range the current selection spans within `box`, or nil if an endpoint
    /// isn't in this table (then the caller falls back to the caret's column).
    private func selectedColumnRange(in box: TableBlockBox) -> ClosedRange<Int>? {
        guard let lo = box.cellLocation(containing: selFrom),
              let hi = box.cellLocation(containing: selTo) else { return nil }
        return min(lo.column, hi.column)...max(lo.column, hi.column)
    }

    func setTableColumnAlignment(_ alignment: TextAlignment) {
        setTableColumnAlignment(horizontal: alignment, vertical: nil)
    }

    /// Sets the VERTICAL alignment (top / middle / bottom) of the selected column(s)' cells.
    func setTableColumnVerticalAlignment(_ alignment: VerticalAlignment) {
        setTableColumnAlignment(horizontal: nil, vertical: alignment)
    }

    /// Sets horizontal and/or vertical alignment on every cell of the selected column range (a nil axis is
    /// left unchanged). Alignment now lives on `Cell` (not `ColumnSpec`), so this writes each covered cell.
    /// One undo step; preserves the structural selection.
    private func setTableColumnAlignment(horizontal: TextAlignment?, vertical: VerticalAlignment?) {
        guard let a = activeTable(), horizontal != nil || vertical != nil else { return }
        editing {
            guard case .table(var t) = a.box.currentBlock() else { return }
            let cols = structuralColumnRange() ?? selectedColumnRange(in: a.box) ?? (a.col...a.col)
            for r in t.rows.indices {
                for c in cols where t.rows[r].cells.indices.contains(c) {
                    if let h = horizontal { t.rows[r].cells[c].horizontalAlignment = h }
                    if let v = vertical { t.rows[r].cells[c].verticalAlignment = v }
                }
            }
            replaceTable(at: a.index, with: t, caretRow: a.row, caretCol: a.col)
        }
    }

    /// The inclusive row range the current selection spans within `box`, or nil if an endpoint isn't in
    /// this table (then the caller falls back to the caret's row).
    private func selectedRowRange(in box: TableBlockBox) -> ClosedRange<Int>? {
        guard let lo = box.cellLocation(containing: selFrom),
              let hi = box.cellLocation(containing: selTo) else { return nil }
        return min(lo.row, hi.row)...max(lo.row, hi.row)
    }

    /// Sets (or clears, when `color` is nil) the background fill of the caret's cell — or, when a row/column
    /// is structurally selected (→ the whole row/column) or a multi-cell text selection is active (→ its
    /// bounding cells), every covered cell. Drives the table menu's Highlight / Remove Highlight. No-op
    /// outside a table. `Cell.background` is already a Core field, so this needs no Core change.
    func setTableCellBackground(_ color: RGBAColor?) {
        guard let a = activeTable() else { return }
        editing {
            guard case .table(let table) = a.box.currentBlock() else { return }
            let rows: ClosedRange<Int>
            let cols: ClosedRange<Int>
            if let sr = structuralRowRange() {            // whole row(s) selected → every column
                rows = sr
                cols = 0...max(table.columnCount - 1, 0)
            } else if let sc = structuralColumnRange() {  // whole column(s) selected → every row
                rows = 0...max(table.rowCount - 1, 0)
                cols = sc
            } else {                                      // a multi-cell text selection, or the caret cell
                rows = selectedRowRange(in: a.box) ?? (a.row...a.row)
                cols = selectedColumnRange(in: a.box) ?? (a.col...a.col)
            }
            replaceTable(at: a.index, with: table.settingCellBackground(color, rows: rows, columns: cols),
                         caretRow: a.row, caretCol: a.col)
        }
    }

    /// Creates an empty `rows`×`columns` table (row 0 a header) at the caret, mirroring `insertImage`:
    /// clears any selection, then splits the caret's paragraph if mid-text, else inserts at the block
    /// boundary. No-op unless the caret is in a top-level paragraph (no nested tables; not on an
    /// image/gap) — guarded BEFORE `editing { }` so a no-op registers no undo entry. Caret lands in the
    /// first header cell.
    func insertTable(rows: Int, columns: Int) {
        guard !boxes.isEmpty, !isInsideTable(head),
              let resolved = resolveBox(at: head), resolved.box is BlockBox else { return }
        editing {
            if selFrom != selTo { applySelectionReplace(globalFrom: selFrom, globalTo: selTo, text: "") }
            guard let pos = resolveBox(at: head), let p = pos.box as? BlockBox else { return }
            // A fresh table starts COMPACT (halved cell padding) — the denser look reads better in a
            // message bubble; the table menu's Compact toggle switches back to normal padding.
            var table = TableBlock.empty(rows: rows, columns: columns)
            table.compact = true
            let tableBox = TableBlockBox(table: table, mapper: mapper, width: effectiveWidth)
            var newBoxes = boxes
            if pos.local > 0, pos.local < p.textLength {
                let (upper, lower) = p.currentParagraph().split(at: pos.local, newID: BlockID.generate())
                let upperBox = BlockBox(paragraph: upper, mapper: mapper, width: effectiveWidth)
                let lowerBox = BlockBox(paragraph: lower, mapper: mapper, width: effectiveWidth)
                let replacement: [any CanvasBlock] = [upperBox, tableBox, lowerBox]
                newBoxes.replaceSubrange(pos.index...pos.index, with: replacement)
            } else if pos.local == 0 {
                newBoxes.insert(tableBox, at: pos.index)            // before the caret's block
            } else {
                newBoxes.insert(tableBox, at: pos.index + 1)        // after the caret's block
            }
            boxes = newBoxes
            recomputeSpans()
            if let caret = tableBox.cellTextStart(row: 0, column: 0) { anchor = caret; head = caret }
        }
    }
}

/// Package-local cell-background transform. The Core `TableBlock+Editing` helpers stay upstream-owned;
/// this one lives here because cell highlighting is a macOS-editor affordance (the `Cell.background`
/// field it sets already exists in Core).
@available(macOS 12, *)
extension TableBlock {
    func settingCellBackground(_ color: RGBAColor?, rows: ClosedRange<Int>, columns: ClosedRange<Int>) -> TableBlock {
        var t = self
        for r in rows where t.rows.indices.contains(r) {
            for c in columns where t.rows[r].cells.indices.contains(c) {
                t.rows[r].cells[c].background = color
            }
        }
        return t
    }
}
#endif
