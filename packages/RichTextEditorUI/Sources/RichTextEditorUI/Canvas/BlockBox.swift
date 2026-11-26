#if canImport(AppKit)
import AppKit
import RichTextEditorCore

/// One paragraph block in the canvas: a TextKit 2 layout plus the structural
/// fields not stored in the attributed string, its frame in canvas coordinates, and its start in the
/// document-wide global position space.
@available(macOS 12, *)
final class BlockBox {
    let id: BlockID
    var style: ParagraphStyleName
    var listMembership: ListMembership?
    var paragraphAttributes: ParagraphAttributes
    let layout: BlockLayout
    let mapper: AttributedStringMapper

    var frame: CGRect = .zero
    var globalStart: Int = 0
    /// Default vertical inset above/below a block's text — half of the full gap between two
    /// default-spaced blocks. The owning `BlockStack` may shrink the facing inset for adjacent blocks.
    static let defaultVerticalInset: CGFloat = 8
    // x is always 0 — the horizontal page margin lives in frame.minX (set by the root BlockStack layout
    // origin); inside a table cell the frame already starts past the cell padding.
    let textInset = CGPoint(x: 0, y: BlockBox.defaultVerticalInset)
    // Vertical insets above/below the text, set per-layout by the owning `BlockStack`. They default to
    // `defaultVerticalInset`, but the facing inset shrinks between adjacent blocks (0 between list items
    // so they stack like paragraph lines; half between two body paragraphs).
    var topInset: CGFloat = BlockBox.defaultVerticalInset
    var bottomInset: CGFloat = BlockBox.defaultVerticalInset

    /// A plain body paragraph (not a list item) — the spacing between two of these is tightened.
    var isBodyParagraph: Bool { style == .body && listMembership == nil }

    /// A plain text paragraph — body OR heading (not a list item). Adjacent text paragraphs stack tight
    /// (line pitch), so stacked headings don't read as separated by a paragraph break (they differ by
    /// font size, not a big gap) — matching the compact chat/InstantPage rendering.
    var isTextParagraph: Bool {
        guard listMembership == nil else { return false }
        switch style {
        case .body, .heading1, .heading2, .heading3, .heading4, .heading5, .heading6: return true
        default: return false
        }
    }

    init(paragraph: ParagraphBlock, mapper: AttributedStringMapper, width: CGFloat) {
        id = paragraph.id
        style = paragraph.style
        listMembership = paragraph.list
        paragraphAttributes = paragraph.paragraph
        self.mapper = mapper
        layout = BlockLayout(attributedString: mapper.attributedString(for: paragraph),
                             width: max(width, 1))
    }

    var length: Int { layout.length }
    var textRef: TextNodeRef { .paragraph(id) }
    var height: CGFloat { max(layout.boundingHeight, emptyLineHeight) + topInset + bottomInset }
    var textOrigin: CGPoint { CGPoint(x: frame.minX + textInset.x, y: frame.minY + topInset) }

    /// Per-style measured single-line height, so an empty paragraph reserves EXACTLY what one typed line
    /// becomes. Keyed by the metrics that affect a line's height (style + line/paragraph spacing).
    private static var measuredLineHeights: [String: CGFloat] = [:]

    /// Height of one line, reserved only when the paragraph is EMPTY (TextKit 2 lays out no fragment for
    /// empty text, so `boundingHeight` is ~0). Keeps a blank paragraph — and a blank table cell, which
    /// collapses its row otherwise — at a real line's height. MEASURED through the same layout pipeline a
    /// typed line uses (the old ascender/descender × multiple approximation didn't match TextKit's real
    /// line metrics, so an empty line reserved too much and snapped smaller once a glyph was typed).
    private var emptyLineHeight: CGFloat {
        guard layout.length == 0 else { return 0 }
        let pa = paragraphAttributes
        let key = "\(style.rawValue)|\(pa.lineHeightMultiple)|\(pa.paragraphSpacingBefore)|\(pa.paragraphSpacingAfter)"
        if let cached = BlockBox.measuredLineHeights[key] { return cached }
        let probe = ParagraphBlock(id: BlockID.generate(), style: style, paragraph: pa, list: listMembership, runs: [TextRun(text: "x")])
        let measured = BlockLayout(attributedString: mapper.attributedString(for: probe), width: 100_000).boundingHeight
        BlockBox.measuredLineHeights[key] = measured
        return measured
    }

    func setWidth(_ width: CGFloat) { layout.setWidth(max(width - textInset.x * 2, 1)) }

    /// Y (relative to `textOrigin.y`) at which a list marker's baseline must sit to align with this
    /// paragraph's first text line. Uses the real laid-out baseline when text exists; for an empty list
    /// item it falls back to the style's line metrics, so the marker doesn't jump when the first glyph
    /// is typed (an empty TextKit 2 layout has no fragment to measure).
    func listMarkerBaselineFromTop(markerFont: NSFont) -> CGFloat {
        if let baseline = layout.firstLineBaselineFromTop { return baseline }
        let ps = mapper.styleSheet.paragraphStyle(for: style, attributes: paragraphAttributes, list: listMembership)
        let mult = ps.lineHeightMultiple > 0 ? ps.lineHeightMultiple : 1
        let naturalLineHeight = markerFont.ascender - markerFont.descender
        return markerFont.ascender + (mult - 1) * naturalLineHeight
    }

    /// Applies a RENDER-ONLY override to the display layout: paragraph `alignment` (overriding the
    /// cell's own, for table column alignment) and, when `forceBold`, a bold font trait on every run
    /// (for an emphasized column/row, e.g. a table's first column). The stored model is NOT changed —
    /// alignment is read back from `paragraphAttributes` (untouched here), and
    /// `TableBlockBox.currentBlock()` strips the synthetic bold from the emphasized cells. Idempotent.
    /// No-op on empty text (the override re-applies once text exists).
    func applyDisplayOverride(alignment: TextAlignment, forceBold: Bool, mapper: AttributedStringMapper) {
        let storage = layout.attributedString
        guard storage.length > 0 else { return }
        let m = NSMutableAttributedString(attributedString: storage)
        let full = NSRange(location: 0, length: m.length)
        // Alignment: rebuild the paragraph style from this box's own attributes but with the override
        // alignment, preserving list/indent properties.
        var pa = paragraphAttributes
        pa.alignment = alignment
        let ps = mapper.styleSheet.paragraphStyle(for: style, attributes: pa, list: listMembership)
        m.addAttribute(.paragraphStyle, value: ps, range: full)
        // Bold: only ADD the trait (e.g. the first row). Never remove — other cells keep user bold.
        if forceBold {
            m.enumerateAttribute(.font, in: full, options: []) { value, range, _ in
                guard let font = value as? NSFont,
                      !font.fontDescriptor.symbolicTraits.contains(.bold) else { return }
                let traits = font.fontDescriptor.symbolicTraits.union(.bold)
                let d = font.fontDescriptor.withSymbolicTraits(traits)
                if let newFont = NSFont(descriptor: d, size: font.pointSize) {
                    m.addAttribute(.font, value: newFont, range: range)
                }
            }
        }
        if !layout.attributedString.isEqual(to: m) { layout.attributedString = m }
    }

    func currentParagraph() -> ParagraphBlock {
        ParagraphBlock(id: id, style: style, paragraph: paragraphAttributes, list: listMembership,
                       runs: mapper.runs(from: layout.attributedString))
    }
}

@available(macOS 12, *)
extension BlockBox: CanvasBlock {
    var nodeStart: Int { get { globalStart } set { globalStart = newValue } }
    var nodeSize: Int { length + 2 }
    var textLayout: BlockLayout { layout }
    var textStart: Int { globalStart }
    var textLength: Int { length }
    func currentBlock() -> Block { .paragraph(currentParagraph()) }
    func closestPosition(toCanvasPoint point: CGPoint) -> Int {
        textStart + layout.closestOffset(toPoint: CGPoint(x: point.x - textOrigin.x, y: point.y - textOrigin.y))
    }
    func leafRegions() -> [LeafTextRegion] {
        [LeafTextRegion(layout: layout, globalStart: globalStart, length: length,
                        ref: .paragraph(id), canvasOrigin: textOrigin)]
    }
    func draw(in ctx: CGContext, imageProvider: (String) -> NSImage?) {
        layout.drawText(in: ctx, at: textOrigin)
    }
}
#endif
