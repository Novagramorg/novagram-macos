#if canImport(AppKit)
import AppKit
import RichTextEditorCore

/// One block-quote container in the canvas: a `CanvasBlock` that branches on `collapsed`.
///
/// **Expanded** (`collapsed == false`): a container hosting one child `BlockStack` built via `makeBox`,
/// so any block type nests — including nested block quotes (the factory is recursive). Token size =
/// children + 2; `recompute()` assigns child `nodeStart`s and lays out frames; `leafRegions()` /
/// `closestPosition` delegate to the child stack. The fill (accent bar + tinted background) is painted
/// by `drawBlockquoteDecorations` — this box draws only its children.
///
/// **Collapsed** (`collapsed == true`): a non-editable ATOM (nodeSize 3, empty leafRegions) drawing a
/// ≤3-line folded preview + a trailing expand glyph. Children are still built (for `currentBlock()`
/// round-trip + expand); the collapsed branch only changes the axis/geometry/draw. This matches
/// `DocumentTree`, which maps a collapsed blockQuote to a `.mediaBlock`+`.mediaAtom` atom (nodeSize 3)
/// — so the box's nodeSize MUST also be 3 when collapsed.
@available(macOS 12, *)
final class BlockQuoteBox {
    static let maxPreviewLines: Int = 3
    static let expandGlyphSize: CGFloat = 16
    static let expandGlyphGap: CGFloat = 6
    /// Interior LEFT padding (bar→text gap) — matches the code block's quote-style indent.
    static let leadingInset: CGFloat = 16
    static let trailingInset: CGFloat = 8

    static func previewAttributes(mapper: AttributedStringMapper) -> [NSAttributedString.Key: Any] {
        let base = mapper.styleSheet.paragraphStyle(for: .body, attributes: .default)
        let ps = (base.mutableCopy() as! NSMutableParagraphStyle)
        ps.lineBreakMode = .byTruncatingTail
        return [.font: mapper.styleSheet.font(for: .body, attributes: .plain),
                .foregroundColor: mapper.appearance.defaultForeground,
                .paragraphStyle: ps]
    }

    let id: BlockID
    let mapper: AttributedStringMapper
    /// Whether the block quote is collapsed. When true the box is a non-editable atom (nodeSize 3).
    let collapsed: Bool

    var frame: CGRect = .zero
    var globalStart: Int = 0
    private(set) var layoutWidth: CGFloat

    var topInset: CGFloat = BlockBox.defaultVerticalInset
    var bottomInset: CGFloat = BlockBox.defaultVerticalInset

    /// The single child stack — one `BlockStack` analogous to a single table cell. Children are built via
    /// `makeBox`, so any block type (paragraph, code, nested block quote, …) can appear here.
    let children: BlockStack

    /// Display-only preview layout for collapsed mode (nil when expanded). NOT part of the position axis.
    private let previewLayout: BlockLayout?
    /// Degenerate empty layout for the unused single-text-region protocol members. Per-instance (not
    /// static) so any accidental write touches one quote, not all — mirrors `TableBlockBox`.
    private let emptyLayout = BlockLayout(attributedString: NSAttributedString(string: ""), width: 1)

    init(blockQuote: BlockQuote, mapper: AttributedStringMapper, width: CGFloat) {
        self.id = blockQuote.id
        self.mapper = mapper
        self.collapsed = blockQuote.collapsed
        self.layoutWidth = max(width, 1)

        let inner = max(width - BlockQuoteBox.leadingInset - BlockQuoteBox.trailingInset, 1)
        // Children render with the quote variant (body paragraph spacing 0) so quoted lines read tight,
        // matching the chat's quote rendering; nested quotes re-derive the same variant (idempotent).
        let childMapper = mapper.quoteChildrenVariant()
        let stack = BlockStack(boxes: blockQuote.children.compactMap {
            makeBox(for: $0, mapper: childMapper, width: inner)
        })
        // 0 inset base: the container's own topInset/bottomInset are the sole outer padding, so an
        // empty one-child quote stays one line tall. Inter-child spacing comes from each paragraph's
        // own paragraphSpacing.
        stack.verticalInsetBase = 0
        self.children = stack

        if blockQuote.collapsed {
            let joined = blockQuote.children.map { blockPlainText($0) }.joined(separator: "\n")
            let previewText = joined.replacingOccurrences(of: "\n", with: " ")
            let tw = max(width - BlockQuoteBox.leadingInset
                         - (BlockQuoteBox.trailingInset + BlockQuoteBox.expandGlyphSize + BlockQuoteBox.expandGlyphGap), 1)
            let attrs = BlockQuoteBox.previewAttributes(mapper: mapper)
            self.previewLayout = BlockLayout(
                attributedString: NSAttributedString(string: previewText, attributes: attrs),
                width: tw)
        } else {
            self.previewLayout = nil
        }
        // Pre-lay the children so `height` is valid before the parent assigns a frame.
        layoutChildren(atContentOrigin: .zero)
    }

    // MARK: - Collapsed preview helpers

    private var leadingPad: CGFloat { BlockQuoteBox.leadingInset }
    private var trailingPad: CGFloat {
        BlockQuoteBox.trailingInset + BlockQuoteBox.expandGlyphSize + BlockQuoteBox.expandGlyphGap
    }
    private func previewTextWidth(_ width: CGFloat) -> CGFloat {
        max(width - leadingPad - trailingPad, 1)
    }
    private var lineHeight: CGFloat {
        let font = mapper.styleSheet.font(for: .body, attributes: .plain)
        return font.ascender - font.descender + font.leading
    }
    private var previewHeight: CGFloat {
        guard let layout = previewLayout else { return 0 }
        return min(layout.boundingHeight, lineHeight * CGFloat(BlockQuoteBox.maxPreviewLines))
    }

    /// Whether the collapse control should appear: only when the quote's content is TALLER than the
    /// ≤3-line collapsed preview would show. A short quote gets no collapse glyph.
    var isCollapsible: Bool {
        children.contentHeight > CGFloat(BlockQuoteBox.maxPreviewLines) * lineHeight
    }

    /// The trailing "expand" glyph rect in canvas coordinates (collapsed mode; tap toggles).
    func expandGlyphRect() -> CGRect {
        CGRect(x: frame.maxX - 4 - BlockQuoteBox.expandGlyphSize,
               y: frame.minY + 4,
               width: BlockQuoteBox.expandGlyphSize, height: BlockQuoteBox.expandGlyphSize)
    }

    /// The top-right "collapse" glyph rect for an EXPANDED box (shown only when `isCollapsible`).
    func collapseGlyphRect() -> CGRect {
        expandGlyphRect()
    }

    // MARK: - Internal helpers

    private func innerWidth(_ w: CGFloat) -> CGFloat {
        max(w - BlockQuoteBox.leadingInset - BlockQuoteBox.trailingInset, 1)
    }

    /// Lays the child stack out at `origin` (the CONTENT origin, past the leading inset / top pad).
    private func layoutChildren(atContentOrigin origin: CGPoint) {
        guard !collapsed else { return }
        _ = children.layout(origin: origin, width: innerWidth(layoutWidth))
    }

    /// Draws the collapse/expand chevron glyph (a small accent circle + chevron) — macOS draws its
    /// canvas chrome directly rather than via host-injected images.
    private func drawGlyph(in ctx: CGContext, rect: CGRect, pointingDown: Bool) {
        ctx.saveGState()
        ctx.setFillColor(NSColor.systemBlue.withAlphaComponent(0.15).cgColor)
        ctx.fillEllipse(in: rect)
        ctx.setStrokeColor(NSColor.systemBlue.cgColor)
        ctx.setLineWidth(1.5)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        let w = rect.width, h = rect.height
        let midX = rect.midX
        let dy: CGFloat = pointingDown ? h * 0.12 : -h * 0.12
        ctx.move(to: CGPoint(x: midX - w * 0.2, y: rect.midY - dy / 2))
        ctx.addLine(to: CGPoint(x: midX, y: rect.midY + dy / 2 + dy))
        ctx.addLine(to: CGPoint(x: midX + w * 0.2, y: rect.midY - dy / 2))
        ctx.strokePath()
        ctx.restoreGState()
    }
}

@available(macOS 12, *)
extension BlockQuoteBox: CanvasBlock {
    var nodeStart: Int { get { globalStart } set { globalStart = newValue } }

    /// Collapsed → 3 (non-editable atom, matching DocumentTree's collapsed mapping).
    /// Expanded → open + children tokens + close (Σchildren + 2).
    var nodeSize: Int {
        collapsed ? 3 : children.boxes.reduce(0) { $0 + $1.nodeSize } + 2
    }

    func setWidth(_ width: CGFloat) {
        layoutWidth = max(width, 1)
        if collapsed {
            previewLayout?.setWidth(previewTextWidth(layoutWidth))
        } else {
            // Re-lay children at the new width so `height` (read next by the parent) is correct;
            // `recompute()` repositions them at the real frame origin afterwards.
            layoutChildren(atContentOrigin: CGPoint(x: frame.minX + BlockQuoteBox.leadingInset,
                                                    y: frame.minY + topInset))
        }
    }

    var height: CGFloat {
        if collapsed {
            return previewHeight + topInset + bottomInset
        }
        return topInset + children.contentHeight + bottomInset
    }

    /// Assigns `nodeStart` to every child box and lays out child frames. Called by the canvas from
    /// `recomputeSpans()` and layout after the root layout has set `self.frame` and `self.nodeStart`.
    /// Recursively recomputes nested `BlockQuoteBox` / `TableBlockBox` children.
    /// Collapsed → early return (children are off the position axis).
    func recompute() {
        if collapsed { return }
        children.recompute(baseOffset: globalStart)
        layoutChildren(atContentOrigin: CGPoint(x: frame.minX + BlockQuoteBox.leadingInset,
                                                y: frame.minY + topInset))
        for case let nested as BlockQuoteBox in children.boxes { nested.recompute() }
        for case let t as TableBlockBox in children.boxes { t.recompute() }
    }

    func currentBlock() -> Block {
        .blockQuote(BlockQuote(id: id,
                               children: children.boxes.map { $0.currentBlock() },
                               collapsed: collapsed))
    }

    /// Collapsed → [] (non-editable atom, off the position axis).
    /// Expanded → delegates to the child stack (recurses into nested quotes).
    func leafRegions() -> [LeafTextRegion] {
        collapsed ? [] : children.leafRegions()
    }

    func closestPosition(toCanvasPoint point: CGPoint) -> Int {
        collapsed ? globalStart : children.closestPosition(toCanvasPoint: point)
    }

    func draw(in ctx: CGContext, imageProvider: (String) -> NSImage?) {
        if collapsed {
            guard let layout = previewLayout else { return }
            let textOrigin = CGPoint(x: frame.minX + leadingPad, y: frame.minY + topInset)
            let tw = previewTextWidth(frame.width)
            let ph = previewHeight
            ctx.saveGState()
            ctx.clip(to: CGRect(x: textOrigin.x, y: textOrigin.y, width: tw, height: ph))
            layout.drawText(in: ctx, at: textOrigin)
            ctx.restoreGState()
            drawGlyph(in: ctx, rect: expandGlyphRect(), pointingDown: true)
            return
        }
        children.draw(in: ctx, imageProvider: imageProvider)
        if isCollapsible {
            drawGlyph(in: ctx, rect: collapseGlyphRect(), pointingDown: false)
        }
    }

    // MARK: - Degenerate single-text-region members (unused: the canvas uses leafRegions())
    var textLayout: BlockLayout { emptyLayout }
    var textStart: Int { globalStart }
    var textLength: Int { 0 }
    var textRef: TextNodeRef { .paragraph(id) }
    var textOrigin: CGPoint { frame.origin }
}
#endif
