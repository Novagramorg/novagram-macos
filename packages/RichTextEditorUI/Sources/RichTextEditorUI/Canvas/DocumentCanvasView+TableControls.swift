#if canImport(AppKit)
import AppKit
import RichTextEditorCore

/// A whole-row or whole-column structural selection within a table — a contiguous, ≥1-wide range.
@available(macOS 12, *)
enum TableStructuralSelection: Equatable { case rows(ClosedRange<Int>); case columns(ClosedRange<Int>) }

/// What a tap on a table handle does: select its row/column, or — if that one is already selected —
/// open the context menu.
@available(macOS 12, *)
enum TableHandleTap: Equatable { case select(TableStructuralSelection); case menu }

/// Which end of a structural range a resize knob moves: the lower bound (left/top) or upper (right/bottom).
@available(macOS 12, *)
enum TableRangeEnd: Equatable { case lower, upper }

@available(macOS 12, *)
extension DocumentCanvasView {
    /// The two handles for the caret's current cell in its table: a vertical ⋮ row handle in the left
    /// gutter, and a horizontal ••• column handle just below the table bottom (matching the reference).
    /// Empty when the caret isn't in a table. `rect` is the hit/draw rect in canvas coordinates.
    func tableHandles() -> [(rect: CGRect, kind: TableStructuralSelection)] {
        guard showsTableControls, let a = activeTable() else { return [] }
        let b = a.box.borderWidth
        // The grip spans the active structural RANGE when one is selected, else the caret's single cell.
        let rowRange = structuralRowRange() ?? (a.row...a.row)
        let colRange = structuralColumnRange() ?? (a.col...a.col)
        var out: [(rect: CGRect, kind: TableStructuralSelection)] = []
        if let top = a.box.cellRect(row: rowRange.lowerBound, column: 0),
           let bot = a.box.cellRect(row: rowRange.upperBound, column: 0) {
            let y = top.minY - b
            out.append((CGRect(x: 1, y: y, width: 17, height: bot.maxY + b - y), .rows(rowRange)))
        }
        if let lo = a.box.cellRect(row: 0, column: colRange.lowerBound),
           let hi = a.box.cellRect(row: 0, column: colRange.upperBound) {
            let tableBottom = (a.box.cellRect(row: a.box.rowCount - 1, column: colRange.lowerBound)?.maxY ?? a.box.frame.maxY) + b
            let x = lo.minX - b
            out.append((CGRect(x: x, y: tableBottom, width: hi.maxX + b - x, height: 17), .columns(colRange)))
        }
        return out
    }

    /// The handle hit by `point` (with its center, for anchoring the menu), or nil.
    func tableHandle(at point: CGPoint) -> (kind: TableStructuralSelection, center: CGPoint)? {
        for h in tableHandles() where h.rect.contains(point) {
            return (h.kind, CGPoint(x: h.rect.midX, y: h.rect.midY))
        }
        return nil
    }

    /// The two resize knobs (◇) at the structural selection's ends, in canvas coordinates. Column
    /// selection → left/right edges (vertically centered); row selection → top/bottom edges
    /// (horizontally centered). `rect` is a generous square hit/anchor rect centered on the knob.
    /// Empty when there is no structural selection.
    func tableResizeKnobs() -> [(rect: CGRect, end: TableRangeEnd)] {
        guard let sel = tableSelection, let outline = tableSelectionOutlineRect() else { return [] }
        let hit: CGFloat = 44
        func box(_ center: CGPoint) -> CGRect {
            CGRect(x: center.x - hit / 2, y: center.y - hit / 2, width: hit, height: hit)
        }
        switch sel.kind {
        case .columns:
            let y = outline.midY
            return [(box(CGPoint(x: outline.minX, y: y)), .lower),
                    (box(CGPoint(x: outline.maxX, y: y)), .upper)]
        case .rows:
            let x = outline.midX
            return [(box(CGPoint(x: x, y: outline.minY)), .lower),
                    (box(CGPoint(x: x, y: outline.maxY)), .upper)]
        }
    }

    /// Which resize knob (if any) `point` hits.
    func tableResizeKnob(at point: CGPoint) -> TableRangeEnd? {
        tableResizeKnobs().first { $0.rect.contains(point) }?.end
    }

    /// Draws the two resize knobs as plain `systemBlue` filled circles (diameter 8, no inner dot),
    /// centered on each knob's hit rect. Calibrated against ReferenceDesign/TexEditor_8.
    func drawTableResizeKnobs(in ctx: CGContext) {
        let radius: CGFloat = 4
        for knob in tableResizeKnobs() {
            let c = CGPoint(x: knob.rect.midX, y: knob.rect.midY)
            let circle = CGRect(x: c.x - radius, y: c.y - radius, width: radius * 2, height: radius * 2)
            NSColor.systemBlue.setFill(); NSBezierPath(ovalIn: circle).fill()
        }
    }

    /// Outcome of a click on `point`: select the hit handle's row/column, or open the menu when that
    /// row/column is already the structural selection. nil if the point isn't on a handle.
    func tableHandleTap(at point: CGPoint) -> TableHandleTap? {
        guard let hit = tableHandle(at: point) else { return nil }
        return tableSelection?.kind == hit.kind ? .menu : .select(hit.kind)
    }

    /// Resolves a click in a table's handle gutter to a row/column GEOMETRICALLY (by position), so the
    /// FIRST click on the ⋮ row handle (the left gutter) or the ••• column handle (the strip below the
    /// grid) selects that row/column — even when the caret isn't in the table yet (the drawn handles only
    /// track the caret's cell, which is why a cold click otherwise fell through to a text selection).
    func geometricTableHandleHit(at point: CGPoint) -> (box: TableBlockBox, kind: TableStructuralSelection)? {
        let slack: CGFloat = 8
        for t in boxes.compactMap({ $0 as? TableBlockBox }) {
            let gridBottom = t.frame.maxY - TableBlockBox.bottomSpacing
            // Left gutter — the whole left margin + the table's left border (where the ⋮ handle sits), kept
            // just shy of the first cell's text — within the grid's vertical span → the row at the click's y.
            if point.x >= 0, point.x < t.frame.minX + 4, point.y >= t.frame.minY - slack, point.y < gridBottom {
                let r = t.rowIndex(atY: min(max(point.y, t.frame.minY), gridBottom - 1))
                return (t, .rows(r...r))
            }
            // The reserved strip below the grid (where the ••• handle sits), spanning the table width →
            // the column at the click's x. Generous so a near-miss still selects rather than text.
            if point.y >= gridBottom, point.y <= t.frame.maxY + slack,
               point.x >= t.frame.minX - slack, point.x <= t.frame.maxX + slack {
                let c = t.columnIndex(atX: point.x)
                return (t, .columns(c...c))
            }
        }
        return nil
    }

    /// Selects the row range `range` (single-row click → `r...r`); parks the caret in the range's first
    /// cell so the structural commands resolve to it. The structural selection bypasses the text caret.
    func selectTableRows(_ range: ClosedRange<Int>) {
        guard let a = activeTable(), let pos = a.box.cellTextStart(row: range.lowerBound, column: 0) else { return }
        anchor = pos; head = pos
        tableSelection = (a.box.id, .rows(range))
        notifySelectionChanged(); needsDisplay = true
    }

    func selectTableColumns(_ range: ClosedRange<Int>) {
        guard let a = activeTable(), let pos = a.box.cellTextStart(row: 0, column: range.lowerBound) else { return }
        anchor = pos; head = pos
        tableSelection = (a.box.id, .columns(range))
        notifySelectionChanged(); needsDisplay = true
    }

    /// Convenience: select a single row / column (the 6d entry points; demo + tests use these).
    func selectTableRow(_ r: Int) { selectTableRows(r...r) }
    func selectTableColumn(_ c: Int) { selectTableColumns(c...c) }

    /// Handle-click row selection: select `clicked`, or — when `extending` (Shift-click) and a row selection
    /// already exists in `box` — grow the selection to span the existing range and the clicked rows. Sets the
    /// caret into `box` first so `selectTableRows`' `activeTable()` resolves to it on the first click.
    func selectTableRows(_ clicked: ClosedRange<Int>, in box: TableBlockBox, extending: Bool) {
        if let pos = box.cellTextStart(row: clicked.lowerBound, column: 0) { anchor = pos; head = pos }
        if extending, let sel = tableSelection, sel.table == box.id, case .rows(let existing) = sel.kind {
            selectTableRows(min(existing.lowerBound, clicked.lowerBound) ... max(existing.upperBound, clicked.upperBound))
        } else {
            selectTableRows(clicked)
        }
    }

    /// Handle-click column selection — the column analogue of the row version above.
    func selectTableColumns(_ clicked: ClosedRange<Int>, in box: TableBlockBox, extending: Bool) {
        if let pos = box.cellTextStart(row: 0, column: clicked.lowerBound) { anchor = pos; head = pos }
        if extending, let sel = tableSelection, sel.table == box.id, case .columns(let existing) = sel.kind {
            selectTableColumns(min(existing.lowerBound, clicked.lowerBound) ... max(existing.upperBound, clicked.upperBound))
        } else {
            selectTableColumns(clicked)
        }
    }

    /// All leaf text regions inside the currently structurally-selected table row or column range, or nil if
    /// there is no structural table selection. Lets a character-format command apply to the whole
    /// row/column (every cell's text) instead of the collapsed caret it parks in.
    func tableStructuralSelectionRegions() -> [LeafTextRegion]? {
        guard let sel = tableSelection,
              let box = boxes.compactMap({ $0 as? TableBlockBox }).first(where: { $0.id == sel.table }) else { return nil }
        switch sel.kind {
        case .rows(let range):
            return range.filter { box.cells.indices.contains($0) }.flatMap { box.cells[$0].flatMap { $0.leafRegions() } }
        case .columns(let range):
            return box.cells.flatMap { row in range.compactMap { row.indices.contains($0) ? row[$0] : nil } }
                            .flatMap { $0.leafRegions() }
        }
    }

    func clearTableSelection() {
        guard tableSelection != nil else { return }
        tableSelection = nil
        notifySelectionChanged(); needsDisplay = true
    }

    /// The selected row range, when a row structural selection is active (else nil → commands use the caret row).
    func structuralRowRange() -> ClosedRange<Int>? {
        if let s = tableSelection, case .rows(let r) = s.kind { return r }
        return nil
    }
    /// The selected column range, when a column structural selection is active.
    func structuralColumnRange() -> ClosedRange<Int>? {
        if let s = tableSelection, case .columns(let c) = s.kind { return c }
        return nil
    }

    /// The selected row/column range's bounding rect, expanded by the border so its outer edge is flush
    /// with the table's outer border (cells are inset from the grid by `border`). nil if nothing is selected.
    func tableSelectionOutlineRect() -> CGRect? {
        guard let sel = tableSelection, let a = activeTable(), a.box.id == sel.table else { return nil }
        let rect: CGRect
        switch sel.kind {
        case .rows(let range):
            guard let lo = a.box.cellRect(row: range.lowerBound, column: 0),
                  let hi = a.box.cellRect(row: range.upperBound, column: a.box.columnCount - 1) else { return nil }
            rect = lo.union(hi)
        case .columns(let range):
            guard let lo = a.box.cellRect(row: 0, column: range.lowerBound),
                  let hi = a.box.cellRect(row: a.box.rowCount - 1, column: range.upperBound) else { return nil }
            rect = lo.union(hi)
        }
        return rect.insetBy(dx: -a.box.borderWidth, dy: -a.box.borderWidth)
    }

    /// Which corners of the selection outline round to match the table's rounded OUTER corners. Interior
    /// corners stay square; so do the corners ADJACENT to the selection handle (the handle bar abuts the
    /// outline there with a square edge). Empty = a fully-square selection.
    func tableSelectionOutlineCorners() -> RectCorner {
        guard let sel = tableSelection, let a = activeTable(), a.box.id == sel.table else { return [] }
        var corners: RectCorner = []
        switch sel.kind {
        case .columns(let range):
            // Column grip sits at the BOTTOM → bottom corners square; round the top corners where the
            // range reaches the table's rounded outer corners.
            if range.lowerBound == 0 { corners.insert(.topLeft) }
            if range.upperBound == a.box.columnCount - 1 { corners.insert(.topRight) }
        case .rows(let range):
            // Row grip sits at the LEFT → left corners square; round the right corners.
            if range.lowerBound == 0 { corners.insert(.topRight) }
            if range.upperBound == a.box.rowCount - 1 { corners.insert(.bottomRight) }
        }
        return corners
    }

    func drawTableSelectionOutline(in ctx: CGContext) {
        guard let outer = tableSelectionOutlineRect() else { return }
        let lineWidth: CGFloat = 2
        // CG centers a stroke on its path, so inset by half the line width to keep the stroke's OUTER
        // edge flush with the table's outer border (the rect that `tableSelectionOutlineRect` aligns to).
        let rect = outer.insetBy(dx: lineWidth / 2, dy: lineWidth / 2)
        // Round only the corners meeting the table's rounded outer border (concentric: table radius −
        // the half-line-width inset); interior corners stay square. systemBlue — from TexEditor_8.
        let corners = tableSelectionOutlineCorners()
        let r = max(TableBlockBox.outerCornerRadius - lineWidth / 2, 0)
        let path = corners.isEmpty
            ? NSBezierPath(rect: rect)
            : NSBezierPath(roundedRect: rect, byRoundingCorners: corners, cornerRadius: r)
        NSColor.systemBlue.setStroke(); path.lineWidth = lineWidth; path.stroke()
    }

    // tableHandles() returns the handles for the caret's cell; the one matching tableSelection.kind is tinted blue.
    // Row handle = vertical ⋮ (left gutter); column handle = horizontal ••• (below the table).
    func drawTableHandles(in ctx: CGContext) {
        for h in tableHandles() {
            let active = tableSelection?.kind == h.kind
            let horizontal: Bool
            if case .columns = h.kind { horizontal = true } else { horizontal = false }
            drawHandleDots(in: h.rect, active: active, horizontal: horizontal)
        }
    }

    /// Three dots centered in `rect` — along x when `horizontal` (column ⋯), else along y (row ⋮).
    /// When `active` (its row/column is selected) the dots sit on a `systemBlue` rounded pill and turn
    /// `textBackgroundColor` (white in light) — matching the reference's highlighted handle.
    private func drawHandleDots(in rect: CGRect, active: Bool, horizontal: Bool) {
        if active {
            // accent bar spanning the whole selection (rect = column width / row height), rounded ends
            NSColor.systemBlue.setFill()
            if horizontal {
                NSBezierPath(roundedRect: rect, byRoundingCorners: [.bottomLeft, .bottomRight],
                             cornerRadius: min(rect.width, rect.height)).fill()
            } else {
                NSBezierPath(roundedRect: rect, byRoundingCorners: [.topLeft, .bottomLeft],
                             cornerRadius: min(rect.width, rect.height)).fill()
            }
        }
        (active ? NSColor.textBackgroundColor : .secondaryLabelColor).setFill()
        let d: CGFloat = 4, gap: CGFloat = 3
        let cx = rect.midX, cy = rect.midY
        for i in -1...1 {
            let off = CGFloat(i) * (d + gap)
            let x = horizontal ? cx + off : cx
            let y = horizontal ? cy : cy + off
            NSBezierPath(ovalIn: CGRect(x: x - d / 2, y: y - d / 2, width: d, height: d)).fill()
        }
    }

    /// The standard structural-action handler: run a command, then clear the selection.
    private func structuralAction(_ run: @escaping (DocumentCanvasView) -> Void) -> () -> Void {
        { [weak self] in guard let self else { return }; run(self); self.clearTableSelection() }
    }

    /// Makes a `ClosureMenuItem`, then sets its image (SF symbol). Convenience so the caller stays one line.
    /// Internal (not private): the button-row "…" menu builds its items through the same helper.
    func menuItem(title: String, symbolName: String?, handler: @escaping () -> Void) -> ClosureMenuItem {
        let item = ClosureMenuItem(title: title, handler: handler)
        if let name = symbolName {
            item.image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
        }
        return item
    }

    /// The Add/Delete/Align menu for the current `tableSelection`, adapted to the table state
    /// (header row → no Delete/Add-Above; single-column → no Delete Column). Each action runs the
    /// existing Phase 3c command then clears the selection. nil if there is no structural selection.
    func structuralMenu() -> NSMenu? {
        guard let sel = tableSelection, let a = activeTable(), a.box.id == sel.table else { return nil }
        let menu = NSMenu()
        switch sel.kind {
        case .columns(let range):
            let multi = range.count > 1
            menu.addItem(menuItem(title: editorLocalized("RichTextEditor.Table.AddColumnLeft", "Add Column Left"), symbolName: "arrow.left.to.line",
                                  handler: structuralAction { $0.insertTableColumnLeft() }))
            menu.addItem(menuItem(title: editorLocalized("RichTextEditor.Table.AddColumnRight", "Add Column Right"), symbolName: "arrow.right.to.line",
                                  handler: structuralAction { $0.insertTableColumnRight() }))
            // Hide Delete when the range covers every column (deleting all would empty the table).
            let coversAll = range.lowerBound == 0 && range.upperBound == a.box.columnCount - 1
            if !coversAll {
                menu.addItem(menuItem(title: multi ? editorLocalized("RichTextEditor.Table.DeleteColumns", "Delete Columns") : editorLocalized("RichTextEditor.Table.DeleteColumn", "Delete Column"),
                                      symbolName: "trash",
                                      handler: structuralAction { $0.deleteTableColumn() }))
            }
            menu.addItem(.separator())
            menu.addItem(menuItem(title: editorLocalized("RichTextEditor.Table.AlignLeft", "Align Left"), symbolName: "text.alignleft",
                                  handler: structuralAction { $0.setTableColumnAlignment(.left) }))
            menu.addItem(menuItem(title: editorLocalized("RichTextEditor.Table.AlignCenter", "Align Center"), symbolName: "text.aligncenter",
                                  handler: structuralAction { $0.setTableColumnAlignment(.center) }))
            menu.addItem(menuItem(title: editorLocalized("RichTextEditor.Table.AlignRight", "Align Right"), symbolName: "text.alignright",
                                  handler: structuralAction { $0.setTableColumnAlignment(.right) }))

        case .rows(let range):
            let multi = range.count > 1
            let includesHeader = range.contains { a.box.isHeaderRow($0) }
            let hasBodyRow = range.contains { a.box.cells.indices.contains($0) && !a.box.isHeaderRow($0) }
            if !includesHeader {                       // can't insert above the header
                menu.addItem(menuItem(title: editorLocalized("RichTextEditor.Table.AddRowAbove", "Add Row Above"), symbolName: "arrow.up.to.line",
                                      handler: structuralAction { $0.insertTableRowAbove() }))
            }
            menu.addItem(menuItem(title: editorLocalized("RichTextEditor.Table.AddRowBelow", "Add Row Below"), symbolName: "arrow.down.to.line",
                                  handler: structuralAction { $0.insertTableRowBelow() }))
            if hasBodyRow {                             // at least one deletable (non-header) row
                menu.addItem(menuItem(title: multi ? editorLocalized("RichTextEditor.Table.DeleteRows", "Delete Rows") : editorLocalized("RichTextEditor.Table.DeleteRow", "Delete Row"),
                                      symbolName: "trash",
                                      handler: structuralAction { $0.deleteTableRow() }))
            }
        }
        menu.addItem(.separator())
        menu.addItem(menuItem(title: a.box.bordered
                                  ? editorLocalized("RichTextEditor.Table.BordersOff", "Hide Borders")
                                  : editorLocalized("RichTextEditor.Table.BordersOn", "Show Borders"),
                              symbolName: "squareshape.split.3x3",
                              handler: structuralAction { $0.toggleTableBordered() }))
        menu.addItem(menuItem(title: a.box.compact
                                  ? editorLocalized("RichTextEditor.Table.CompactOff", "Normal Padding")
                                  : editorLocalized("RichTextEditor.Table.CompactOn", "Compact"),
                              symbolName: "rectangle.compress.vertical",
                              handler: structuralAction { $0.toggleTableCompact() }))
        return menu
    }

    /// Moves the structural selection's `end` knob to the row/column under `point`, keeping the other
    /// end fixed. The dragged end cannot cross the fixed end (minimum range width 1; no swap); both are
    /// bounded to the grid. Live (`needsDisplay = true`) for outline/knob/bar feedback.
    func extendTableSelection(end: TableRangeEnd, toward point: CGPoint) {
        guard let sel = tableSelection,
              let box = boxes.compactMap({ $0 as? TableBlockBox }).first(where: { $0.id == sel.table }) else { return }
        switch sel.kind {
        case .rows(let range):
            if end == .upper {
                let fixed = range.lowerBound
                let moved = max(min(box.rowIndex(atY: point.y), box.rowCount - 1), fixed)
                tableSelection = (sel.table, .rows(fixed...moved))
            } else {
                let fixed = range.upperBound
                let moved = min(max(box.rowIndex(atY: point.y), 0), fixed)
                tableSelection = (sel.table, .rows(moved...fixed))
            }
        case .columns(let range):
            if end == .upper {
                let fixed = range.lowerBound
                let moved = max(min(box.columnIndex(atX: point.x), box.columnCount - 1), fixed)
                tableSelection = (sel.table, .columns(fixed...moved))
            } else {
                let fixed = range.upperBound
                let moved = min(max(box.columnIndex(atX: point.x), 0), fixed)
                tableSelection = (sel.table, .columns(moved...fixed))
            }
        }
        needsDisplay = true
    }

    /// Demo helper: place the caret in the first table's (0,0) cell and select column 0 (shows handles + outline).
    func selectFirstTableColumn() {
        guard let t = boxes.compactMap({ $0 as? TableBlockBox }).first,
              let pos = t.cellTextStart(row: 0, column: 0) else { return }
        anchor = pos; head = pos
        selectTableColumn(0)
    }
}
#endif
