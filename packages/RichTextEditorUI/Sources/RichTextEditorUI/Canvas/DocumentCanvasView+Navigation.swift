#if canImport(AppKit)
import AppKit
import RichTextEditorCore

@available(macOS 12, *)
extension DocumentCanvasView {
    /// Next text position to the right: within the current leaf region, or to the nearest renderable
    /// slot beyond it — the next region's start, an image gap, or a button row's FIRST pill atom.
    /// Handles paragraphs, image captions, and table cells uniformly (regions are in document order).
    func nextTextPosition(after pos: Int) -> Int {
        let regions = allLeafRegions()
        if let i = regions.firstIndex(where: { pos >= $0.globalStart && pos <= $0.globalStart + $0.length }) {
            if pos < regions[i].globalStart + regions[i].length { return pos + 1 }
            return nextRenderableSlot(after: pos, regions: regions) ?? pos
        }
        if let img = imageBox(atGap: pos) { return img.textStart }   // on a gap → into the caption
        // On a button-row pill atom: step to the next pill, or past the row to the nearest renderable
        // slot — an adjacent row's first pill, a media gap, or the next region's start.
        if let row = buttonRowBox(atAtom: pos) {
            if pos < row.nodeStart + max(1, row.buttons.count) { return pos + 1 }
            return nextRenderableSlot(after: pos, regions: regions) ?? pos
        }
        return min(pos + 1, documentSize)
    }

    /// Previous text position to the left: within the current region, or to the nearest renderable
    /// slot before it — the previous region's end, an image gap, or a button row's LAST pill atom.
    func prevTextPosition(before pos: Int) -> Int {
        let regions = allLeafRegions()
        if let i = regions.firstIndex(where: { pos >= $0.globalStart && pos <= $0.globalStart + $0.length }) {
            if pos > regions[i].globalStart { return pos - 1 }
            return prevRenderableSlot(before: pos, regions: regions) ?? pos
        }
        if imageBox(atGap: pos) != nil {   // on a gap → the nearest renderable slot before it,
            return prevRenderableSlot(before: pos, regions: regions) ?? 0   // or doc start (leading image)
        }
        // On a button-row pill atom: step to the previous pill, or back before the row.
        if let row = buttonRowBox(atAtom: pos) {
            if pos > row.nodeStart + 1 { return pos - 1 }
            return prevRenderableSlot(before: pos, regions: regions) ?? pos
        }
        return max(pos - 1, 0)
    }

    /// The nearest renderable caret slot strictly after `boundary`: the next text region's start, an
    /// image/media gap, or a button row's FIRST pill atom — whichever comes first in document order.
    /// Regions alone are not enough: a text-free button row between two regions would be skipped
    /// entirely (its pills unreachable moving right), and adjacent rows must chain pill-by-pill.
    private func nextRenderableSlot(after boundary: Int, regions: [LeafTextRegion]) -> Int? {
        var best: Int?
        func consider(_ candidate: Int) {
            if candidate > boundary, candidate < best ?? Int.max { best = candidate }
        }
        for r in regions { consider(r.globalStart) }
        for box in boxes where box is ImageBlockBox || box is MediaBlockBox { consider(box.nodeStart) }
        for case let row as ButtonRowBox in allBoxesForButtons() { consider(row.nodeStart + 1) }
        return best
    }

    /// Mirror of `nextRenderableSlot`: the nearest renderable slot strictly before `boundary` — a
    /// region's end, an image/media gap, or a button row's LAST pill atom. Also what keeps Left from
    /// a media gap off a preceding text-free row's degenerate `nodeStart` (a non-renderable slot).
    private func prevRenderableSlot(before boundary: Int, regions: [LeafTextRegion]) -> Int? {
        var best: Int?
        func consider(_ candidate: Int) {
            if candidate < boundary, candidate > best ?? Int.min { best = candidate }
        }
        for r in regions { consider(r.globalStart + r.length) }
        for box in boxes where box is ImageBlockBox || box is MediaBlockBox { consider(box.nodeStart) }
        for case let row as ButtonRowBox in allBoxesForButtons() { consider(row.nodeStart + max(1, row.buttons.count)) }
        return best
    }

    /// The table whose cell owns `pos`, if any.
    private func tableBox(containing pos: Int) -> TableBlockBox? {
        boxes.first { ($0 as? TableBlockBox)?.cellLocation(containing: pos) != nil } as? TableBlockBox
    }

    /// A position the caret can actually occupy and be drawn at: inside a leaf text region (incl. its
    /// trailing slot) or on an image gap. Structural token slots (block/table/row/cell open-close) are
    /// NOT renderable — a caret there is invisible.
    func isRenderablePosition(_ pos: Int) -> Bool {
        leafRegion(containingGlobal: pos) != nil || isGapPosition(pos) || buttonRowBox(atAtom: pos) != nil
    }

    /// Snaps an arbitrary (possibly structural) global offset onto the nearest renderable caret slot,
    /// biased by the direction of motion (`forward` → the next renderable at/after `pos`, else the
    /// previous at/before). A no-op on positions that are already renderable. This enforces the
    /// caret-renderable invariant for the system tokenizer's stepping primitive, which otherwise walks
    /// the global axis onto non-renderable structural slots (e.g. Option+Arrow word nav parking the
    /// caret on a paragraph's close-token slot at the document end).
    /// Places a collapsed caret at the last renderable position in the document (used when opening the
    /// editor to edit an existing message, so typing continues after the seeded content).
    func moveCaretToEnd() {
        setCaret(global: snapToRenderable(documentSize, forward: false))
    }

    func snapToRenderable(_ pos: Int, forward: Bool) -> Int {
        let p = clampGlobal(pos)
        if isRenderablePosition(p) { return p }
        // Candidate renderable slots: each leaf region's start and end, plus each image gap.
        var candidates: [Int] = []
        for r in allLeafRegions() { candidates.append(r.globalStart); candidates.append(r.globalStart + r.length) }
        for box in boxes where box is ImageBlockBox || box is MediaBlockBox { candidates.append(box.nodeStart) }
        for case let row as ButtonRowBox in allBoxesForButtons() {
            for atom in 0 ..< max(1, row.buttons.count) { candidates.append(row.nodeStart + 1 + atom) }
        }
        guard !candidates.isEmpty else { return p }
        let atOrAfter = candidates.filter { $0 >= p }.min()
        let atOrBefore = candidates.filter { $0 <= p }.max()
        return forward ? (atOrAfter ?? atOrBefore ?? p) : (atOrBefore ?? atOrAfter ?? p)
    }

    /// The first caret position in the block immediately AFTER `table` (where Tab exits the table to),
    /// or nil when the table is the document's last block. A paragraph → its text start; an image → the
    /// gap before it (the GapCursor); a following table → its first cell.
    private func positionAfterTable(_ table: TableBlockBox) -> Int? {
        guard let idx = boxIndex(of: table), idx + 1 < boxes.count else { return nil }
        let next = boxes[idx + 1]
        if let t = next as? TableBlockBox { return t.cellTextStart(row: 0, column: 0) }
        if next is ImageBlockBox || next is MediaBlockBox { return next.nodeStart }
        return next.textStart
    }

    /// Leave the table the caret is in: move to the start of the block after the table, creating an
    /// empty trailing paragraph first when the table is the document's last block (so there is always a
    /// place to type below a table). Used by Shift+Enter inside a cell.
    func exitTableBelow() {
        guard let table = tableBox(containing: head) else { return }
        if let exit = positionAfterTable(table) {
            setCaret(global: exit)
            return
        }
        editing {
            let newBox = BlockBox(paragraph: ParagraphBlock(id: BlockID.generate(), runs: []),
                                  mapper: mapper, width: effectiveWidth)
            var newBoxes = boxes
            newBoxes.append(newBox)
            boxes = newBoxes
            recomputeSpans()
            anchor = newBox.textStart; head = newBox.textStart
        }
    }

    /// Vertical movement by geometry: from the current leaf region's caret rect, step one line up/down
    /// at the same x, then snap to the closest global position. `closestGlobalPosition` recurses into
    /// table cells (via `TableBlockBox.closestPosition`), so Up/Down always lands in a real text region
    /// — never a structural gap such as a table's degenerate node start.
    func verticalPosition(from pos: Int, down: Bool) -> Int {
        // A button-row atom sits in no text region: step THROUGH the row — Down lands in the block
        // after it, Up at the end of the block above (the collapsed-quote / media-gap rule; without
        // this the arrow keys dead-end on a pill).
        if let row = buttonRowBox(atAtom: pos) ?? buttonRowBox(atBoundary: pos) {
            let target = down ? min(row.nodeStart + row.nodeSize, documentSize) : max(0, row.nodeStart - 1)
            let landed = snapToRenderable(target, forward: down)
            // The snap can fall back onto the row's own atoms at a document edge — that's a no-op.
            return buttonRowBox(atAtom: landed) === row ? pos : landed
        }
        // A gap position (before an image) is not in any text region → vertical nav is a no-op here
        // (v1 bound; Up/Down from a gap is not yet implemented).
        guard let (region, local) = leafRegion(containingGlobal: pos) else { return pos }
        let caret = region.layout.caretRect(atOffset: local).offsetBy(dx: region.canvasOrigin.x, dy: region.canvasOrigin.y)
        let step = max(caret.height, 16)
        let targetY = down ? caret.maxY + step / 2 : caret.minY - step / 2
        let snapped = closestGlobalPosition(to: CGPoint(x: caret.midX, y: targetY))

        // Inside a table cell: stay within the cell while it has more lines; at the cell's edge line,
        // move to the same-column neighbor cell (row above for Up / below for Down) if one exists; only
        // escape past the whole table when already in the edge row (no neighbor cell that direction).
        if let table = tableBox(containing: pos), let loc = table.cellLocation(containing: pos) {
            if snapped != pos, let snapLoc = table.cellLocation(containing: snapped), snapLoc == loc {
                return snapped   // moved to another line within the same cell
            }
            let neighborRow = down ? loc.row + 1 : loc.row - 1
            if neighborRow >= 0, neighborRow < table.rowCount, let rect = table.cellRect(row: neighborRow, column: loc.column) {
                // Land on the neighbor cell's edge line nearest the current cell, at the same x.
                let edgeY = down ? rect.minY + min(step / 2, rect.height / 2) : rect.maxY - min(step / 2, rect.height / 2)
                return table.cells[neighborRow][loc.column].closestPosition(toCanvasPoint: CGPoint(x: caret.midX, y: edgeY))
            }
            // Edge row → escape past the whole table into the block above/below.
            let escapeY = down ? table.frame.maxY + step / 2 : table.frame.minY - step / 2
            let escaped = closestGlobalPosition(to: CGPoint(x: caret.midX, y: escapeY))
            return escaped != pos ? escaped : snapped
        }

        // Top-level: the geometric snap can stall (e.g. just above a table, the one-line step re-snaps
        // to the same paragraph). On no progress, push the target just past the owning top-level box and
        // re-snap so the caret escapes over an adjacent table.
        if let (snapRegion, _) = leafRegion(containingGlobal: snapped),
           snapRegion.globalStart == region.globalStart, snapped == pos,
           let owner = boxes.first(where: { caret.midY >= $0.frame.minY && caret.midY < $0.frame.maxY }) {
            let escapeY = down ? owner.frame.maxY + step / 2 : owner.frame.minY - step / 2
            let escaped = closestGlobalPosition(to: CGPoint(x: caret.midX, y: escapeY))
            if escaped != pos { return escaped }
        }
        return snapped
    }

    /// True when the caret sits on the document's FIRST visual line, so a vertical move up can't reach a
    /// higher line (`verticalPosition` stays on the same line or no-ops). Gates Up-arrow's escape-above.
    func atTopVisualLine() -> Bool {
        let here = caretRect(forGlobal: head)
        let up = verticalPosition(from: head, down: false)
        if up == head { return true }
        return caretRect(forGlobal: up).minY >= here.minY - 0.5
    }

    /// True when the caret sits on the document's LAST visual line, so a vertical move down can't reach a
    /// lower line. Gates Down-arrow's escape-below (the mirror of `atTopVisualLine`).
    func atBottomVisualLine() -> Bool {
        let here = caretRect(forGlobal: head)
        let down = verticalPosition(from: head, down: true)
        if down == head { return true }
        return caretRect(forGlobal: down).maxY <= here.maxY + 0.5
    }

    /// True for a block you can't otherwise start a normal paragraph next to: a non-body paragraph
    /// (quote / heading), a list item, or any non-paragraph block (code / table / media). A plain body
    /// paragraph is NOT trapped (you can just type in it), so Up/Down at the edge stays a no-op there.
    private func blockIsTrapped(_ box: CanvasBlock?) -> Bool {
        guard let box = box else { return false }
        if let b = box as? BlockBox { return b.style != .body || b.listMembership != nil }
        return true
    }

    /// True when the caret sits on the FIRST visual line of a media/image/group block's caption — so Up
    /// should escape the media block rather than move within (or below) the caption.
    private func captionIsOnFirstLine(of box: CanvasBlock) -> Bool {
        let here = caretRect(forGlobal: head)
        let firstLine = caretRect(forGlobal: box.textStart)   // caption start = its first visual line
        return here.minY <= firstLine.minY + 0.5
    }

    /// True when the caret sits on the LAST visual line of `box`'s text, so a Down move exits the box.
    private func caretOnLastLine(of box: CanvasBlock) -> Bool {
        let textBottom = box.textOrigin.y + box.textLayout.boundingHeight
        return caretRect(forGlobal: head).maxY >= textBottom - 1.0
    }

    /// The text position the caret should land on when ENTERING a block from above: a media/image/group
    /// caption start, or a table's first cell. nil for a plain paragraph (use normal geometric nav) — so
    /// Down into a media/table lands in its content, not on a structural gap before it.
    private func firstEditablePosition(of box: CanvasBlock) -> Int? {
        if let t = box as? TableBlockBox { return t.cellTextStart(row: 0, column: 0) }
        if box is MediaBlockBox || box is MediaGroupBlockBox || box is ImageBlockBox { return box.textStart }
        return nil
    }
    func firstBlockIsTrapped() -> Bool { blockIsTrapped(boxes.first) }
    func lastBlockIsTrapped() -> Bool { blockIsTrapped(boxes.last) }

    /// Tab/Shift-Tab: move the caret to the next/previous cell. Tab in the last cell exits to the start
    /// of the block after the table (no-op if the table is the document's last block); Shift-Tab in the
    /// first cell is a no-op. Outside a table, no-op.
    func moveToCell(forward: Bool) {
        guard let table = boxes.first(where: { ($0 as? TableBlockBox)?.cellLocation(containing: head) != nil }) as? TableBlockBox,
              let loc = table.cellLocation(containing: head) else { return }
        let cols = table.columnCount, rows = table.rowCount
        var target: (row: Int, column: Int)?
        if forward {
            if loc.column + 1 < cols { target = (loc.row, loc.column + 1) }
            else if loc.row + 1 < rows { target = (loc.row + 1, 0) }
            else {
                // last cell → exit the table to the start of the block after it. No-op when the table
                // is the document's last block (nothing after to move to).
                if let exit = positionAfterTable(table) { setCaret(global: exit) }
                return
            }
        } else {
            if loc.column > 0 { target = (loc.row, loc.column - 1) }
            else if loc.row > 0 { target = (loc.row - 1, cols - 1) }
            else { return }   // first cell → no-op
        }
        if let t = target, let pos = table.cellTextStart(row: t.row, column: t.column) { setCaret(global: pos) }
    }
}

// MARK: - NSResponder movement selectors

@available(macOS 12, *)
extension DocumentCanvasView {
    // --- Character movement (visual == logical for LTR documents) ---
    override func moveLeft(_ sender: Any?) {
        setCaret(global: prevTextPosition(before: head))
    }
    override func moveRight(_ sender: Any?) {
        setCaret(global: nextTextPosition(after: head))
    }
    override func moveUp(_ sender: Any?) {
        // From a media/image/group CAPTION on its first line, Up escapes the media block upward (you can't
        // navigate up through the media area itself): to the end of the block above it, or — if the media is
        // the document's first block — insert an empty body paragraph above it and land the caret there.
        if selFrom == selTo, let pos = resolveBox(at: head),
           pos.box is MediaBlockBox || pos.box is MediaGroupBlockBox || pos.box is ImageBlockBox,
           captionIsOnFirstLine(of: pos.box) {
            if pos.index > 0 {
                setCaret(global: prevTextPosition(before: pos.box.nodeStart))
            } else {
                editing { insertEmptyBodyParagraphAtTop() }
            }
            return
        }
        // At the document's first visual line Up can't go higher. If the first block is "trapped" (a
        // non-body paragraph / list / code / table / media — anything you can't type a plain paragraph
        // above), insert a fresh empty body paragraph above and land the caret there, so a leading
        // quote/heading isn't a dead end. After inserting, the new top block is a body paragraph (not
        // trapped), so a second Up is a no-op rather than stacking more empty lines.
        if selFrom == selTo, firstBlockIsTrapped(), atTopVisualLine() {
            editing { insertEmptyBodyParagraphAtTop() }
            return
        }
        setCaret(global: verticalPosition(from: head, down: false))
    }
    override func moveDown(_ sender: Any?) {
        // Mirror of moveUp: at the document's last visual line Down can't go lower. If the last block is
        // "trapped" (a non-body paragraph / list / code / table / media — anything you can't type a plain
        // paragraph below), append a fresh empty body paragraph and land the caret there, so a trailing
        // quote/heading isn't a dead end. The appended body paragraph isn't trapped, so a second Down no-ops.
        if selFrom == selTo, lastBlockIsTrapped(), atBottomVisualLine() {
            editing { insertParagraphAfterBlock(at: boxes.count - 1) }
            return
        }
        // Down off the LAST line of a top-level paragraph, into a media/image/group/table block, lands in
        // that block's editable content (media caption / table's first cell) — not on a structural slot
        // before it, which renders as a stray left-edge caret "indicator". The gap/atom stays reachable via
        // Right-arrow or a click. (A caret inside a table resolves to the TableBlockBox, not a BlockBox, so
        // this never hijacks in-table vertical nav.)
        if selFrom == selTo, let pos = resolveBox(at: head), pos.box is BlockBox,
           pos.index + 1 < boxes.count, caretOnLastLine(of: pos.box),
           let entry = firstEditablePosition(of: boxes[pos.index + 1]) {
            setCaret(global: entry)
            return
        }
        setCaret(global: verticalPosition(from: head, down: true))
    }

    // --- Character movement + extend selection ---
    override func moveLeftAndModifySelection(_ sender: Any?) {
        setSelectionHead(global: prevTextPosition(before: head))
    }
    override func moveRightAndModifySelection(_ sender: Any?) {
        setSelectionHead(global: nextTextPosition(after: head))
    }
    override func moveUpAndModifySelection(_ sender: Any?) {
        setSelectionHead(global: verticalPosition(from: head, down: false))
    }
    override func moveDownAndModifySelection(_ sender: Any?) {
        setSelectionHead(global: verticalPosition(from: head, down: true))
    }

    // --- Word movement (Option+Arrow) ---
    override func moveWordLeft(_ sender: Any?) {
        setCaret(global: tokenizer.wordBoundary(fromGlobal: head, forward: false))
    }
    override func moveWordRight(_ sender: Any?) {
        setCaret(global: tokenizer.wordBoundary(fromGlobal: head, forward: true))
    }
    override func moveWordLeftAndModifySelection(_ sender: Any?) {
        setSelectionHead(global: tokenizer.wordBoundary(fromGlobal: head, forward: false))
    }
    override func moveWordRightAndModifySelection(_ sender: Any?) {
        setSelectionHead(global: tokenizer.wordBoundary(fromGlobal: head, forward: true))
    }

    // --- Line movement (⌘+Left / ⌘+Right, or Fn+Arrow on standard keyboards) ---
    override func moveToLeftEndOfLine(_ sender: Any?) {
        setCaret(global: tokenizer.lineBoundary(fromGlobal: head, forward: false))
    }
    override func moveToRightEndOfLine(_ sender: Any?) {
        setCaret(global: tokenizer.lineBoundary(fromGlobal: head, forward: true))
    }
    override func moveToLeftEndOfLineAndModifySelection(_ sender: Any?) {
        setSelectionHead(global: tokenizer.lineBoundary(fromGlobal: head, forward: false))
    }
    override func moveToRightEndOfLineAndModifySelection(_ sender: Any?) {
        setSelectionHead(global: tokenizer.lineBoundary(fromGlobal: head, forward: true))
    }

    // --- Document movement (⌘+Up / ⌘+Down) ---
    override func moveToBeginningOfDocument(_ sender: Any?) {
        setCaret(global: firstRenderableGlobal())
    }
    override func moveToEndOfDocument(_ sender: Any?) {
        setCaret(global: lastRenderableGlobal())
    }
    override func moveToBeginningOfDocumentAndModifySelection(_ sender: Any?) {
        setSelectionHead(global: firstRenderableGlobal())
    }
    override func moveToEndOfDocumentAndModifySelection(_ sender: Any?) {
        setSelectionHead(global: lastRenderableGlobal())
    }
}
#endif
