#if canImport(AppKit)
import AppKit
import RichTextEditorCore

/// One pull-quote block in the canvas: a rich TextKit layout (centered, forced-italic) drawn inside a
/// content-hugging tinted pill with corner quote marks, optionally followed by an attribution ("author")
/// line. Mirrors `CodeBlockBox` but builds its attributed string via the mapper (rich runs + forced
/// italic/center) instead of a plain monospace string. The pill background + corner marks are drawn by
/// `drawPullQuoteDecorations` — this box only lays out and draws the (centered, italic) text + author.
///
/// **Author line** (mirrors the UIKit editor): a SECOND editable text region rendered as a centered,
/// bold+italic `.caption` below the quote text. It is present only when the quote has content (author
/// text OR pull text — see `shouldShowAuthor`); a fresh/empty pull quote hides it entirely (no
/// placeholder, no reserved height, no position tokens). The author text region is appended AFTER the
/// pull region in the position model, so an author-less pull quote's positions are byte-identical to
/// before this line existed. The bold/italic/author-color are all ambient (forced via
/// `quoteAuthorRenderRuns`, stripped on read-back via `quoteAuthorStripAmbientStyle`).
@available(macOS 12, *)
final class PullQuoteBox {
    static let horizontalPadding: CGFloat = 12
    static let verticalPadding: CGFloat = 8
    static let cornerRadius: CGFloat = 2.5
    static let fillAlpha: CGFloat = 0.10
    static let markSize: CGFloat = 14
    static let markInset: CGFloat = 6
    static let minWidth: CGFloat = 160
    /// Vertical gap between the quote text and the author line.
    static let authorSpacing: CGFloat = 2

    let id: BlockID
    let layout: BlockLayout
    let mapper: AttributedStringMapper

    var frame: CGRect = .zero
    var globalStart: Int = 0

    let leftInset: CGFloat = PullQuoteBox.horizontalPadding
    let rightInset: CGFloat = PullQuoteBox.horizontalPadding
    var topInset: CGFloat = PullQuoteBox.verticalPadding
    var bottomInset: CGFloat = PullQuoteBox.verticalPadding

    /// The author (attribution) line's own TextKit layout — a bold+ITALIC centered `.caption`. Bold,
    /// italic, and the text color are all ambient (forced via `quoteAuthorRenderRuns`, stripped on
    /// read-back). Empty (`[]`) until the quote has content.
    let authorLayout: BlockLayout
    /// The author renders centered (matching the pull text).
    private static let authorParagraph = ParagraphAttributes(alignment: .center)

    /// The most-recently-configured outer box width (from `init`/`setWidth`), so geometry that must be
    /// correct before the canvas assigns `frame` reads it instead of the not-yet-set `frame.width`.
    private(set) var layoutWidth: CGFloat

    init(pullQuote: PullQuote, mapper: AttributedStringMapper, width: CGFloat) {
        self.id = pullQuote.id
        self.mapper = mapper
        self.layoutWidth = width
        let inner = max(width - PullQuoteBox.horizontalPadding * 2, 1)
        self.layout = BlockLayout(
            attributedString: mapper.attributedString(for: ParagraphBlock(id: pullQuote.id, style: .pullQuote, runs: pullQuote.runs)),
            width: inner)
        self.authorLayout = BlockLayout(
            attributedString: mapper.attributedString(for: ParagraphBlock(
                id: pullQuote.id, style: .caption, paragraph: PullQuoteBox.authorParagraph,
                runs: quoteAuthorRenderRuns(pullQuote.author, textColor: PullQuoteBox.authorColor(mapper), italic: true))),
            width: inner)
    }

    /// The ambient author text color — the accent (link) color by design, matching the IV2 render and the
    /// quote's corner marks.
    private static func authorColor(_ mapper: AttributedStringMapper) -> RGBAColor? {
        mapper.appearance.linkColor.rgba
    }

    var length: Int { layout.length }
    var textOrigin: CGPoint { CGPoint(x: frame.minX + leftInset, y: frame.minY + topInset) }

    var authorLength: Int { authorLayout.length }
    /// The author line sits below the quote text, inside the same horizontal padding.
    var authorOrigin: CGPoint {
        CGPoint(x: frame.minX + leftInset,
                y: textOrigin.y + max(layout.boundingHeight, emptyLineHeight) + PullQuoteBox.authorSpacing)
    }

    private var emptyLineHeight: CGFloat {
        guard layout.length == 0 else { return 0 }
        let font = mapper.styleSheet.font(for: .pullQuote, attributes: CharacterAttributes())
        return font.ascender - font.descender + font.leading
    }

    private var authorEmptyLineHeight: CGFloat {
        guard authorLayout.length == 0 else { return 0 }
        let font = mapper.styleSheet.font(for: .caption, attributes: CharacterAttributes(bold: true, italic: true))
        return font.ascender - font.descender + font.leading
    }

    /// Placeholder width measured in the BOLD+ITALIC caption font (matches the rendered author weight).
    private var authorPlaceholderTextWidth: CGFloat {
        let font = mapper.styleSheet.font(for: .caption, attributes: CharacterAttributes(bold: true, italic: true))
        return (quoteAuthorPlaceholderText as NSString).size(withAttributes: [.font: font]).width
    }

    /// Attributes for the FIRST char typed into an empty author line (bold+italic caption, centered, in
    /// the author color). Used by `typingAttributeDict`.
    func authorTypingAttributes() -> [NSAttributedString.Key: Any] {
        var ca = CharacterAttributes(); ca.bold = true; ca.italic = true
        ca.foreground = PullQuoteBox.authorColor(mapper)
        var attrs = mapper.attributes(for: ca, style: .caption)
        attrs[.paragraphStyle] = mapper.styleSheet.paragraphStyle(for: .caption, attributes: PullQuoteBox.authorParagraph)
        return attrs
    }

    /// Widest laid-out line width (glyph-hugging) of the quote text, for the content-hugging pill.
    var contentWidth: CGFloat {
        guard length > 0 else { return 0 }
        return layout.selectionRects(start: 0, end: length).map(\.width).max() ?? 0
    }

    /// Widest laid-out line of the AUTHOR line (or the "Add author" placeholder when empty).
    private var authorContentWidth: CGFloat {
        guard shouldShowAuthor else { return 0 }
        if authorLength == 0 { return authorPlaceholderTextWidth }
        return authorLayout.selectionRects(start: 0, end: authorLength).map(\.width).max() ?? 0
    }

    /// The content-hugging width for the PILL: the WIDER of the quote text and the author line, so a long
    /// author — or the "Add author" placeholder — under a short quote isn't clipped by the pill.
    var pillContentWidth: CGFloat { max(contentWidth, authorContentWidth) }

    /// Attributes for text typed into a pull quote (italic + centered paragraph style). Used by
    /// `typingAttributeDict` and `insertPullQuoteNewline` so the first character typed into an
    /// empty pull quote is italic/centered, not body-upright-left.
    static func pullQuoteTypingAttributes(_ mapper: AttributedStringMapper) -> [NSAttributedString.Key: Any] {
        let probe = mapper.attributedString(for: ParagraphBlock(id: BlockID("pq-typing"), style: .pullQuote,
                                                                runs: [TextRun(text: " ")]))
        return probe.attributes(at: 0, effectiveRange: nil)
    }
}

@available(macOS 12, *)
extension PullQuoteBox: CanvasBlock {
    var nodeStart: Int { get { globalStart } set { globalStart = newValue } }
    /// The author line is shown only when the quote has content — the author itself has text, OR the pull
    /// text is non-empty. A fresh/empty pull quote hides the author region entirely.
    var shouldShowAuthor: Bool { authorLength > 0 || length > 0 }
    /// Base (author-less) tokens are `length + 2` — identical to before the author line existed. When the
    /// author is shown, its region + gap tokens (`authorLength + 2`) are appended.
    var nodeSize: Int { length + 2 + (shouldShowAuthor ? authorLength + 2 : 0) }
    var textLayout: BlockLayout { layout }
    var textStart: Int { globalStart }
    var textLength: Int { length }
    var textRef: TextNodeRef { .pullQuote(id) }
    /// Global start of the author region (valid only when `shouldShowAuthor`): after the quote text and
    /// its two gap tokens.
    var authorRegionStart: Int { globalStart + length + 2 }
    var height: CGFloat {
        shouldShowAuthor
            ? quoteOnlyHeight + PullQuoteBox.authorSpacing + max(authorLayout.boundingHeight, authorEmptyLineHeight)
            : quoteOnlyHeight
    }
    /// The box's height AS IF there were no author line. Used to bracket the corner marks around the
    /// QUOTE TEXT only (the pill background still spans the full `height`, author included).
    var quoteOnlyHeight: CGFloat {
        topInset + max(layout.boundingHeight, emptyLineHeight) + bottomInset
    }
    func setWidth(_ width: CGFloat) {
        layoutWidth = width
        let inner = max(width - leftInset - rightInset, 1)
        layout.setWidth(inner)
        authorLayout.setWidth(inner)
    }
    func currentBlock() -> Block {
        .pullQuote(PullQuote(id: id,
                             runs: mapper.runs(from: layout.attributedString),
                             author: quoteAuthorStripAmbientStyle(mapper.runs(from: authorLayout.attributedString),
                                                                  textColor: PullQuoteBox.authorColor(mapper), italic: true)))
    }
    func closestPosition(toCanvasPoint point: CGPoint) -> Int {
        // A tap at/below the author line's top routes into the author region (so the author — including
        // its empty "Add author" placeholder — is directly tappable); otherwise into the quote text.
        if shouldShowAuthor, point.y >= authorOrigin.y {
            return authorRegionStart
                + authorLayout.closestOffset(toPoint: CGPoint(x: point.x - authorOrigin.x, y: point.y - authorOrigin.y))
        }
        return textStart + layout.closestOffset(toPoint: CGPoint(x: point.x - textOrigin.x, y: point.y - textOrigin.y))
    }
    func leafRegions() -> [LeafTextRegion] {
        var regions = [LeafTextRegion(layout: layout, globalStart: globalStart, length: length,
                                      ref: .pullQuote(id), canvasOrigin: textOrigin)]
        if shouldShowAuthor {
            regions.append(LeafTextRegion(layout: authorLayout, globalStart: authorRegionStart, length: authorLength,
                                          ref: .quoteAuthor(id), canvasOrigin: authorOrigin))
        }
        return regions
    }
    func draw(in ctx: CGContext, imageProvider: (String) -> NSImage?) {
        // The pill background + corner marks are drawn by the decorations pass; only the text here.
        layout.drawText(in: ctx, at: textOrigin)
        guard shouldShowAuthor else { return }
        authorLayout.drawText(in: ctx, at: authorOrigin)
        if authorLength == 0 {
            let font = mapper.styleSheet.font(for: .caption, attributes: CharacterAttributes(bold: true, italic: true))
            let ps = NSMutableParagraphStyle(); ps.alignment = .center
            let rect = CGRect(x: frame.minX + leftInset, y: authorOrigin.y,
                              width: max(frame.width - leftInset - rightInset, 1), height: authorEmptyLineHeight)
            NSAttributedString(string: quoteAuthorPlaceholderText,
                               attributes: [.font: font, .foregroundColor: NSColor.placeholderTextColor,
                                            .paragraphStyle: ps]).draw(in: rect)
        }
    }
}
#endif
