#if canImport(AppKit)
import AppKit
import CoreText
import RichTextEditorCore

/// A measured inline pill. Mirrors the iOS `ButtonTextAttachment`: the payload carries both the model
/// and the metrics, because the line layout raises ascent/descent from the attachment and cannot
/// re-measure.
///
/// Unlike iOS — whose pills are hosted views so a label emoji stays live — this attachment's `image`
/// IS the rendered pill (capsule fill + recolored label), so TextKit draws it with no overlay
/// machinery. A custom emoji inside an inline label degrades to its reserved blank box (v1).
@available(macOS 12, *)
final class ButtonTextAttachment: NSTextAttachment {
    let button: ButtonRef
    /// The label, already laid out with the pill's own typography (semibold, fixed size).
    let labelString: NSAttributedString
    /// Full pill size — the label's ink box inflated by the padding below.
    let size: CGSize
    let ascent: CGFloat
    let descent: CGFloat
    /// The per-side horizontal padding `size` was inflated by. LOAD-BEARING: the label's ink width is
    /// recovered as `size.width - 2 * horizontalPadding`, so reading a global here instead of the value
    /// that actually built `size` would silently mis-centre the label.
    let horizontalPadding: CGFloat
    /// True when `maxWidth` forced an ellipsis — the label did NOT fit at this padding.
    let isTruncated: Bool
    /// Resolved at construction from the appearance + the button's colour role, kept so a row box can
    /// re-render the same pill at its stretched column width without re-deriving them.
    let colors: (fill: NSColor, label: NSColor)

    init(button: ButtonRef, labelString: NSAttributedString, size: CGSize, ascent: CGFloat,
         descent: CGFloat, horizontalPadding: CGFloat, isTruncated: Bool = false,
         colors: (fill: NSColor, label: NSColor)) {
        self.button = button
        self.labelString = labelString
        self.size = size
        self.ascent = ascent
        self.descent = descent
        self.horizontalPadding = horizontalPadding
        self.isTruncated = isTruncated
        self.colors = colors
        super.init(data: nil, ofType: nil)
        self.image = ButtonTextAttachment.renderPill(size: size, horizontalPadding: horizontalPadding,
                                                     labelString: labelString, colors: colors)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    private func box() -> CGRect {
        CGRect(x: 0, y: -descent, width: max(1.0, size.width), height: max(1.0, size.height))
    }

    override func attachmentBounds(for attributes: [NSAttributedString.Key: Any], location: NSTextLocation,
                                   textContainer: NSTextContainer?, proposedLineFragment: CGRect,
                                   position: CGPoint) -> CGRect {
        box()
    }

    /// Draws one pill into an image the attachment's box size: capsule fill, then the label recolored
    /// to `colors.label` (the mapper baked the PARAGRAPH's foreground) and clipped to the capsule.
    static func renderPill(size: CGSize, horizontalPadding: CGFloat, labelString: NSAttributedString,
                           colors: (fill: NSColor, label: NSColor)) -> NSImage {
        let pillSize = CGSize(width: max(1.0, size.width), height: max(1.0, size.height))
        return NSImage(size: pillSize, flipped: true) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return true }
            let radius = rect.height / 2.0
            let capsule = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
            ctx.addPath(capsule)
            ctx.setFillColor(colors.fill.cgColor)
            ctx.fillPath()
            guard labelString.length != 0 else { return true }
            ctx.addPath(capsule)
            ctx.clip()
            let display = NSMutableAttributedString(attributedString: labelString)
            display.addAttribute(.foregroundColor, value: colors.label,
                                 range: NSRange(location: 0, length: display.length))
            let inkWidth = size.width - horizontalPadding * 2.0
            let x = max(horizontalPadding, (rect.width - inkWidth) / 2.0)
            let y = max(0, (rect.height - display.size().height) / 2.0)
            display.draw(at: CGPoint(x: x, y: y))
            return true
        }
    }
}
#endif
