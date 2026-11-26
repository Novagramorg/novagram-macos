#if canImport(AppKit)
import AppKit
import RichTextEditorCore

/// A table block: a grid of cells, each cell a `BlockStack`. Token size follows the Core model
/// (table = Σrows + 2; row = Σcells + 2; cell = Σblocks + 2). Cells are laid out row-major; the
/// canvas treats the whole table as one `CanvasBlock` and recurses via `leafRegions()`.
@available(macOS 12, *)
final class TableBlockBox: CanvasBlock {
    let id: BlockID
    let compact: Bool
    let bordered: Bool
    let columns: [ColumnSpec]
    var rowIDs: [BlockID]
    var rowIsHeader: [Bool]
    var rowMinHeights: [CGFloat]
    var cellIDs: [[BlockID]]
    var cellBackgrounds: [[RGBAColor?]]
    /// Per-cell alignment (moved off `ColumnSpec` — now a `Cell` field). Horizontal aligns the paragraphs
    /// (render override, like the header bold); vertical positions the content in the cell's free height.
    var cellHAlign: [[TextAlignment]]
    var cellVAlign: [[VerticalAlignment]]
    var cells: [[BlockStack]]
    let mapper: AttributedStringMapper

    var frame: CGRect = .zero
    var nodeStart: Int = 0
    private(set) var layoutWidth: CGFloat
    var columnWidths: [CGFloat] = []
    var rowHeights: [CGFloat] = []
    /// Horizontal scroll offset for a table wider than its host (columns clamp at `minColumnWidth`
    /// instead of squeezing without bound). All content geometry hangs off `contentMinX`, so shifting
    /// this + `recompute()` moves cells, selection, caret and controls together. Clamped to
    /// `0...maxScrollX`.
    var scrollX: CGFloat = 0

    static let cellPadding: CGFloat = 6
    /// A `compact` table halves its cell padding. Derived from the regular value so the two cannot
    /// drift apart, mirroring how the chat-side V2 layout does it.
    private var cellPadding: CGFloat { compact ? TableBlockBox.cellPadding / 2.0 : TableBlockBox.cellPadding }
    static let border: CGFloat = 1
    /// The border width this table lays out and draws with. Mirrors the V2 renderer: `bordered` is NOT
    /// merely a paint toggle — an unbordered table's border width participates as ZERO in all width/
    /// height math, so the 1pt gaps between cells collapse too. Internal so the handle/outline
    /// geometry in `+TableControls` tracks the same width the cell rects were laid out with.
    var borderWidth: CGFloat { bordered ? TableBlockBox.border : 0 }
    /// Columns never squeeze below this — a table that can't fit scrolls horizontally instead.
    static let minColumnWidth: CGFloat = 110
    /// Outer-border corner radius (≈8pt, measured from the reference design).
    static let outerCornerRadius: CGFloat = 8
    /// Space the table reserves below its grid, within its own frame. Doubles as the table's bottom
    /// margin AND the room the ••• column handle needs to stay on-screen/tappable when the table is the
    /// document's last block (the canvas is content-sized to the table's frame). Inter-block separation
    /// from a following block is added on top via `BlockStack.framedNeighborMargin`.
    static let bottomSpacing: CGFloat = 20
    static let gridColor: NSColor = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(white: 0.27, alpha: 1)    // dark mode ≈#454545
            : NSColor(white: 0.88, alpha: 1)    // light mode ≈#E0E0E0
    }
    /// Header-row (row 0) background tint: gray at 0.1 alpha.
    static let headerRowBackground = NSColor(white: 0.5, alpha: 0.1)

    init(table: TableBlock, mapper: AttributedStringMapper, width: CGFloat) {
        id = table.id
        compact = table.compact
        bordered = table.bordered
        columns = table.columns
        rowIDs = table.rows.map { $0.id }
        rowIsHeader = table.rows.map { $0.isHeader }
        rowMinHeights = table.rows.map { CGFloat($0.height ?? 0) }
        cellIDs = table.rows.map { $0.cells.map { $0.id } }
        cellBackgrounds = table.rows.map { $0.cells.map { $0.background } }
        cellHAlign = table.rows.map { $0.cells.map { $0.horizontalAlignment } }
        cellVAlign = table.rows.map { $0.cells.map { $0.verticalAlignment } }
        self.mapper = mapper
        layoutWidth = max(width, 1)
        cells = table.rows.map { row in
            row.cells.map { c in
                BlockStack(boxes: c.blocks.compactMap { block in
                    switch block {
                    case .paragraph(let p): return BlockBox(paragraph: p, mapper: mapper, width: 100)
                    case .media: return nil       // embedded media unsupported inside table cells (v1)
                    case .table: return nil       // no nested tables in v1
                    case .code: return nil        // code blocks unsupported inside table cells
                    case .pullQuote: return nil   // pull quotes unsupported inside table cells
                    case .blockQuote: return nil  // block quotes unsupported inside table cells (v1)
                    case .details: return nil     // details blocks unsupported inside table cells (v1)
                    case .buttonRow: return nil   // button rows unsupported inside table cells (v1)
                    }
                })
            }
        }
        applyRenderOverrides()
    }

    var rowCount: Int { cells.count }
    var columnCount: Int { columns.count }

    // Token size: cell = stack tokens + 2; row = Σcells + 2; table = Σrows + 2.
    var nodeSize: Int {
        var total = 0
        for row in cells {
            var rowTotal = 0
            for stack in row { rowTotal += stackTokens(stack) + 2 }
            total += rowTotal + 2
        }
        return total + 2
    }
    private func stackTokens(_ stack: BlockStack) -> Int { stack.boxes.reduce(0) { $0 + $1.nodeSize } }

    func setWidth(_ width: CGFloat) { layoutWidth = max(width, 1); computeColumnWidths() }

    private func computeColumnWidths() {
        // Columns share the width REMAINING after the (n+1) grid borders — otherwise `totalGridWidth`
        // exceeds `layoutWidth` by the border pixels and every table reads as (barely) overflowing,
        // clipping its right border and enabling pointless horizontal panning.
        let borders = borderWidth * CGFloat(columnCount + 1)
        let avail = max(layoutWidth - borders, CGFloat(columnCount))
        let sum = columns.reduce(0) { $0 + CGFloat($1.width) }
        if sum <= 0 {
            columnWidths = Array(repeating: max(avail / CGFloat(max(columnCount, 1)), TableBlockBox.minColumnWidth), count: columnCount)
        } else {
            let scale = avail / sum
            columnWidths = columns.map { max(CGFloat($0.width) * scale, TableBlockBox.minColumnWidth) }
        }
        scrollX = min(scrollX, maxScrollX)
    }

    /// Full grid width (columns + all borders) — may exceed `layoutWidth` when columns clamp at the minimum.
    var totalGridWidth: CGFloat {
        if columnWidths.isEmpty { computeColumnWidths() }
        return columnWidths.reduce(0) { $0 + $1 + borderWidth } + borderWidth
    }
    var maxScrollX: CGFloat { max(0, totalGridWidth - layoutWidth) }
    /// The content-space left edge: the frame's left edge shifted by the horizontal scroll.
    var contentMinX: CGFloat { frame.minX - scrollX }

    /// Auto-pans a horizontally-overflowing table so `column` is fully visible — keeps the caret's cell
    /// on screen while editing (mirrors the vertical caret-follow). Returns true when `scrollX` changed.
    @discardableResult
    func scrollToReveal(column: Int) -> Bool {
        guard maxScrollX > 0, columnWidths.indices.contains(column) else { return false }
        if columnWidths.isEmpty { computeColumnWidths() }
        var left = borderWidth
        for c in 0..<column { left += columnWidths[c] + borderWidth }
        let right = left + columnWidths[column] + borderWidth
        let margin: CGFloat = 16
        var target = scrollX
        if left - margin < scrollX {
            target = max(0, left - margin)
        } else if right + margin > scrollX + layoutWidth {
            target = min(maxScrollX, right + margin - layoutWidth)
        }
        target = max(0, min(maxScrollX, target))
        guard target != scrollX else { return false }
        scrollX = target
        return true
    }

    /// Cell content width (column width minus the left border and horizontal padding).
    private func cellContentWidth(_ col: Int) -> CGFloat { max(columnWidths[col] - borderWidth - cellPadding * 2, 1) }

    var height: CGFloat {
        if columnWidths.isEmpty { computeColumnWidths() }
        // Grid + a reserved strip below it (bottomSpacing) so the column handle stays on-screen for a
        // trailing table; the gap to the block ABOVE comes from that block's facing inset.
        return borderWidth + rowHeightsComputed().reduce(0) { $0 + $1 + borderWidth } + TableBlockBox.bottomSpacing
    }

    /// Row heights = max cell content height in the row + padding, clamped to the model minimum.
    private func rowHeightsComputed() -> [CGFloat] {
        var heights: [CGFloat] = []
        for (r, row) in cells.enumerated() {
            var maxH: CGFloat = 0
            for (c, stack) in row.enumerated() {
                var probe: CGFloat = 0
                for box in stack.boxes { box.setWidth(cellContentWidth(c)); probe += box.height }
                maxH = max(maxH, probe)
            }
            heights.append(max(maxH + cellPadding * 2, rowMinHeights[r]))
        }
        return heights
    }

    // CanvasBlock
    func currentBlock() -> Block {
        var rows: [Row] = []
        for (r, row) in cells.enumerated() {
            var outCells: [Cell] = []
            for (c, stack) in row.enumerated() {
                var blocks = stack.boxes.map { $0.currentBlock() }
                if r == 0 { blocks = blocks.map { TableBlockBox.strippingBold($0) } }
                outCells.append(Cell(id: cellIDs[r][c], blocks: blocks, background: cellBackgrounds[r][c],
                                     horizontalAlignment: cellHAlign[r][c], verticalAlignment: cellVAlign[r][c]))
            }
            rows.append(Row(id: rowIDs[r], height: rowMinHeights[r] > 0 ? Double(rowMinHeights[r]) : nil,
                            isHeader: rowIsHeader[r], cells: outCells))
        }
        return .table(TableBlock(id: id, columns: columns, rows: rows, compact: compact, bordered: bordered))
    }

    /// Re-applies the render-only overrides to every cell's display layout: per-cell alignment and,
    /// for the first row (r == 0, the header), bold. Idempotent; called at build and on each recompute so it survives edits.
    private func applyRenderOverrides() {
        for (r, row) in cells.enumerated() {
            for (c, stack) in row.enumerated() {
                let alignment = (cellHAlign.indices.contains(r) && cellHAlign[r].indices.contains(c)) ? cellHAlign[r][c] : .natural
                for box in stack.boxes {
                    (box as? BlockBox)?.applyDisplayOverride(alignment: alignment, forceBold: r == 0, mapper: mapper)
                }
            }
        }
    }

    /// Clears the bold trait from a paragraph block's runs (the header row's bold is a render override).
    private static func strippingBold(_ block: Block) -> Block {
        guard case .paragraph(var p) = block else { return block }
        p.runs = p.runs.map { run in var r = run; r.attributes.bold = false; return r }
        return .paragraph(p)
    }

    /// Assigns nodeStarts to every cell stack row-major, matching the Core token walk, and lays out
    /// cell frames. Returns nothing; the canvas reads `nodeSize`/`leafRegions` afterward.
    func recompute() {
        applyRenderOverrides()
        if columnWidths.isEmpty { computeColumnWidths() }
        rowHeights = rowHeightsComputed()
        // Token base: this table's content starts at nodeStart + 1 (the table open token).
        var pos = nodeStart + 1
        var y = frame.minY + borderWidth
        for (r, row) in cells.enumerated() {
            pos += 1                                   // row open token
            var x = contentMinX + borderWidth
            for (c, stack) in row.enumerated() {
                pos += 1                               // cell open token
                let cw = columnWidths[c]
                // Vertical alignment: offset the content within the cell's free vertical space (`.top`
                // default → 0, byte-identical to before). Mirrors the V2 renderer's table cell layout.
                var contentH: CGFloat = 0
                for box in stack.boxes { box.setWidth(cellContentWidth(c)); contentH += box.height }
                let free = max(0, (rowHeights[r] - cellPadding * 2) - contentH)
                let vAlign = (cellVAlign.indices.contains(r) && cellVAlign[r].indices.contains(c)) ? cellVAlign[r][c] : .top
                let vFactor: CGFloat = { switch vAlign { case .top: return 0; case .middle: return 0.5; case .bottom: return 1 } }()
                let contentOrigin = CGPoint(x: x + cellPadding, y: y + cellPadding + free * vFactor)
                _ = stack.recompute(baseOffset: pos - 1)   // cell content begins at (cell open) → baseOffset
                _ = stack.layout(origin: contentOrigin, width: cellContentWidth(c))
                pos += stackTokens(stack)
                pos += 1                               // cell close token
                x += cw + borderWidth
            }
            pos += 1                                   // row close token
            y += rowHeights[r] + borderWidth
        }
    }

    func leafRegions() -> [LeafTextRegion] { cells.flatMap { $0.flatMap { $0.leafRegions() } } }

    /// The cell `BlockStack` that owns global position `pos`, with the box + local offset + index
    /// within that stack. Mirrors `leafRegions()`'s recursion, for the editing engine. Matches by the
    /// box's PRIMARY region (the one starting at `textStart`), like `activeStack`'s leaf loop — an
    /// in-cell code block's FIRST region is its language line, whose positions must resolve to nil here
    /// (the region-aware paths edit them), while its CODE region is no longer `.first` and would
    /// otherwise stop resolving at all.
    func cellStack(containing pos: Int) -> (stack: BlockStack, box: CanvasBlock, local: Int, index: Int)? {
        for row in cells {
            for stack in row {
                for (i, b) in stack.boxes.enumerated() {
                    if let primary = b.leafRegions().first(where: { $0.globalStart == b.textStart }),
                       pos >= primary.globalStart, pos <= primary.globalStart + primary.length {
                        return (stack, b, pos - primary.globalStart, i)
                    }
                }
            }
        }
        return nil
    }

    /// (row, column) of the cell whose stack owns `pos`, or nil. ANY of a box's leaf regions locates the
    /// cell (a language-line position is still "in that cell" for navigation/geometry).
    func cellLocation(containing pos: Int) -> (row: Int, column: Int)? {
        for (r, row) in cells.enumerated() {
            for (c, stack) in row.enumerated() {
                for b in stack.boxes {
                    if b.leafRegions().contains(where: { pos >= $0.globalStart && pos <= $0.globalStart + $0.length }) {
                        return (r, c)
                    }
                }
            }
        }
        return nil
    }

    /// The global text start of cell (row, column)'s first leaf region (where Tab places the caret).
    func cellTextStart(row: Int, column: Int) -> Int? {
        guard cells.indices.contains(row), cells[row].indices.contains(column) else { return nil }
        return cells[row][column].leafRegions().first?.globalStart
    }

    /// The canvas-coordinate rect of cell (row, column), from cached grid geometry (matches `draw` /
    /// `closestPosition`). Used by vertical caret nav to snap into the same-column neighbor cell.
    func cellRect(row: Int, column: Int) -> CGRect? {
        guard cells.indices.contains(row), cells[row].indices.contains(column),
              rowHeights.indices.contains(row), columnWidths.indices.contains(column) else { return nil }
        var y = frame.minY + borderWidth
        for r in 0..<row { y += rowHeights[r] + borderWidth }
        var x = contentMinX + borderWidth
        for c in 0..<column { x += columnWidths[c] + borderWidth }
        return CGRect(x: x, y: y, width: columnWidths[column], height: rowHeights[row])
    }

    /// The row index whose vertical band contains canvas-y `y`, clamped to `0..<rowCount`. The inverse
    /// of `cellRect`'s y math (sum of `rowHeights` + `border`, from `frame.minY + border`). A point in a
    /// border slot resolves to the row above it (half-border slack).
    func rowIndex(atY y: CGFloat) -> Int {
        guard !rowHeights.isEmpty else { return 0 }
        var top = frame.minY + borderWidth
        for r in 0..<rowHeights.count {
            let bottom = top + rowHeights[r]
            if y < bottom + borderWidth / 2 { return r }
            top = bottom + borderWidth
        }
        return rowHeights.count - 1
    }

    /// The column index whose horizontal band contains canvas-x `x`, clamped to `0..<columnCount`.
    func columnIndex(atX x: CGFloat) -> Int {
        guard !columnWidths.isEmpty else { return 0 }
        var left = contentMinX + borderWidth
        for c in 0..<columnWidths.count {
            let right = left + columnWidths[c]
            if x < right + borderWidth / 2 { return c }
            left = right + borderWidth
        }
        return columnWidths.count - 1
    }

    /// The canvas-coordinate band tinted with the header background (row 0): full table width, from the
    /// table top through the divider below row 0. `nil` if the table is empty. `draw` fills it clipped to
    /// the rounded outer border so the top corners stay rounded.
    func headerRowBackgroundRect() -> CGRect? {
        guard rowCount > 0, !rowHeights.isEmpty else { return nil }
        let totalW = columnWidths.reduce(0) { $0 + $1 + borderWidth } + borderWidth
        let height = borderWidth + rowHeights[0] + borderWidth
        return CGRect(x: contentMinX, y: frame.minY, width: totalW, height: height)
    }

    /// Appends a row of `columnCount` empty single-paragraph cells (fresh ids). Caller recomputes + undo.
    func appendRow() {
        let n = max(columnCount, 1)
        var rowStacks: [BlockStack] = []
        var ids: [BlockID] = []
        var bgs: [RGBAColor?] = []
        for _ in 0..<n {
            let para = ParagraphBlock(id: BlockID.generate())
            rowStacks.append(BlockStack(boxes: [BlockBox(paragraph: para, mapper: mapper, width: 100)]))
            ids.append(BlockID.generate()); bgs.append(nil)
        }
        cells.append(rowStacks); cellIDs.append(ids); cellBackgrounds.append(bgs)
        cellHAlign.append(Array(repeating: .center, count: n))
        cellVAlign.append(Array(repeating: .top, count: n))
        rowIDs.append(BlockID.generate()); rowIsHeader.append(false); rowMinHeights.append(0)
    }

    /// Whether row `r` is a header row.
    func isHeaderRow(_ r: Int) -> Bool { rowIsHeader.indices.contains(r) && rowIsHeader[r] }

    func draw(in ctx: CGContext, imageProvider: (String) -> NSImage?) {
        // A horizontally-scrolling table clips to its visible strip so scrolled-out columns don't bleed.
        let clips = maxScrollX > 0
        if clips {
            ctx.saveGState()
            ctx.clip(to: CGRect(x: frame.minX, y: frame.minY, width: layoutWidth, height: frame.height))
        }
        defer { if clips { ctx.restoreGState() } }
        let totalW = columnWidths.reduce(0) { $0 + $1 + borderWidth } + borderWidth
        let totalH = borderWidth + rowHeights.reduce(0) { $0 + $1 + borderWidth }
        // Rounded outer border path (also the clip for fills so corners stay rounded). CG centers
        // strokes, so inset by half the border so the 1pt stroke fills its slot flush with the frame edge.
        let half = borderWidth / 2
        let radius = TableBlockBox.outerCornerRadius - half
        let outer = NSBezierPath(roundedRect: CGRect(x: contentMinX + half, y: frame.minY + half,
                                                     width: totalW - borderWidth,
                                                     height: totalH - borderWidth),
                                 xRadius: radius, yRadius: radius)
        // Header-row tint, clipped to the rounded border so the top corners round with the table.
        if let headerRect = headerRowBackgroundRect() {
            ctx.saveGState(); outer.addClip()
            TableBlockBox.headerRowBackground.setFill(); ctx.fill(headerRect)
            ctx.restoreGState()
        }
        var y = frame.minY + borderWidth
        for (r, row) in cells.enumerated() {
            var x = contentMinX + borderWidth
            for (c, stack) in row.enumerated() {
                let cellRect = CGRect(x: x, y: y, width: columnWidths[c], height: rowHeights[r])
                if let bg = cellBackgrounds[r][c] { bg.nsColor.setFill(); ctx.fill(cellRect) }
                stack.draw(in: ctx, imageProvider: imageProvider)
                x += columnWidths[c] + borderWidth
            }
            y += rowHeights[r] + borderWidth
        }
        // grid lines (interior dividers + outer border), using cached geometry. An unbordered table
        // draws NO grid or outer stroke (a zero line width would still stroke a hairline); the header
        // tint and cell fills above are all its chrome.
        guard bordered else { return }
        TableBlockBox.gridColor.setStroke()
        ctx.setLineWidth(borderWidth)
        if columnWidths.count > 1 {
            var cx = contentMinX + borderWidth
            for w in columnWidths.dropLast() {
                cx += w
                ctx.move(to: CGPoint(x: cx + borderWidth / 2, y: frame.minY))
                ctx.addLine(to: CGPoint(x: cx + borderWidth / 2, y: frame.minY + totalH))
                cx += borderWidth
            }
        }
        if rowHeights.count > 1 {
            var ry = frame.minY + borderWidth
            for h in rowHeights.dropLast() {
                ry += h
                ctx.move(to: CGPoint(x: contentMinX, y: ry + borderWidth / 2))
                ctx.addLine(to: CGPoint(x: contentMinX + totalW, y: ry + borderWidth / 2))
                ry += borderWidth
            }
        }
        ctx.strokePath()
        // Rounded outer border (path built up front, also used to clip the header tint).
        outer.lineWidth = borderWidth
        outer.stroke()
    }

    func closestPosition(toCanvasPoint point: CGPoint) -> Int {
        guard rowCount > 0, columnCount > 0 else { return nodeStart + 1 }
        // Find the cell whose rect contains the point (or the nearest), then recurse.
        var y = frame.minY + borderWidth
        for (r, row) in cells.enumerated() {
            var x = contentMinX + borderWidth
            for (c, stack) in row.enumerated() {
                let cellRect = CGRect(x: x, y: y, width: columnWidths[c], height: rowHeights[r])
                if cellRect.contains(point) || (point.y >= cellRect.minY && point.y < cellRect.maxY && c == row.count - 1) {
                    return stack.closestPosition(toCanvasPoint: point)
                }
                x += columnWidths[c] + borderWidth
            }
            y += rowHeights[r] + borderWidth
        }
        // Fallback: last cell's closest position.
        if let lastStack = cells.last?.last { return lastStack.closestPosition(toCanvasPoint: point) }
        return nodeStart + 1
    }

    // Degenerate single-text-region conformance (unused: the canvas uses leafRegions() for tables).
    // Per-instance (not static): the canvas never edits through a table's `textLayout` — a collapsed
    // caret resting on a table boundary is snapped into a cell first (see `caretSnappedIntoCell`) — but
    // keeping this per-instance contains any future accidental write to one table rather than leaking
    // it into a process-wide shared layout.
    private let emptyLayout = BlockLayout(attributedString: NSAttributedString(string: ""), width: 1)
    var textLayout: BlockLayout { emptyLayout }
    var textStart: Int { nodeStart }
    var textLength: Int { 0 }
    var textRef: TextNodeRef { .paragraph(id) }
    var textOrigin: CGPoint { frame.origin }
}
#endif
