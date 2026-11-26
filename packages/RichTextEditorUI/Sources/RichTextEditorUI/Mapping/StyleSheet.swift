#if canImport(AppKit)
import AppKit
import RichTextEditorCore

/// Resolves a paragraph style name to concrete fonts/paragraph layout (AppKit-only, hence here
/// rather than in Core).
@available(macOS 12, *)
public struct StyleSheet {
    public init() {}
    public static let `default` = StyleSheet()

    /// Spacing after a body paragraph — applied by TextKit at every "\n". Kept at 0 so a soft line break
    /// (Enter) reads at line pitch (a plain new line), NOT with a paragraph gap; the gap BETWEEN paragraphs
    /// (Shift+Enter → a new block) comes separately from `BlockStack.facingInset`. Block-quote children were
    /// already 0 so quoted lines join tight, matching the chat's quote rendering.
    public var bodyParagraphSpacingAfter: CGFloat = 0

    /// Points of indentation per list nesting level (where each level's marker hangs).
    public static let listIndentStep: CGFloat = 24
    /// Horizontal gap reserved between a list marker and its text — the text hangs this far past the
    /// marker's column. Half the per-level indent step, so it's decoupled from nesting depth.
    public static let listMarkerSpacing: CGFloat = listIndentStep / 2
    /// Extra text inset applied to ORDERED (numbered) list items on top of `listMarkerSpacing`. A
    /// number marker ("1.", "iii.") is much wider than a bullet, so its text needs more breathing room
    /// after the marker than a bullet's does. The marker itself stays in its level's column; only the
    /// item text shifts right by this amount.
    public static let orderedListTextInset: CGFloat = 4
    /// Side of the square checklist checkbox. Sized to the editor's 14pt body text (not iOS's absolute
    /// 18pt, which is proportioned for its larger InstantPage body) so stacked items keep a visible gap
    /// — line height ≈ 18.6pt, so the inter-box gap is (lineHeight − checkboxSize).
    public static let checkboxSize: CGFloat = 15
    /// Gap between a checklist checkbox and its text.
    public static let checkboxTextGap: CGFloat = 6

    // Sizes match the chat's InstantPage heading ladder so the editor is WYSIWYG. Body and caption
    // retain their existing sizes; only H1-H6 use the expanded heading scale.
    private func baseSize(_ style: ParagraphStyleName) -> CGFloat {
        switch style {
        case .heading1: return 24
        case .heading2: return 22
        case .heading3: return 20
        case .heading4: return 19
        case .heading5: return 18
        case .heading6: return 17
        case .body, .pullQuote: return 14
        case .caption: return 12
        }
    }

    /// Render-only per-style spacing/line-height (model values are 0/1.0). Validated against the reference design.
    private struct StyleMetrics { var spacingBefore: CGFloat; var spacingAfter: CGFloat; var lineHeightMultiple: CGFloat }
    private func metrics(for style: ParagraphStyleName) -> StyleMetrics {
        switch style {
        // Compact/WYSIWYG heading spacing: match the chat's InstantPage rendering, where a heading is NOT
        // separated by a big paragraph gap. The inter-block inset already spaces blocks; the old
        // spacingBefore/After (18/6) stacked on top of it and read as a paragraph break between stacked
        // headings. Kept at 0 so headings sit at line pitch like the sent message; the tight inter-heading
        // inset comes from BlockStack.facingInset (headings are `isTextParagraph`).
        case .heading1: return StyleMetrics(spacingBefore: 0, spacingAfter: 0, lineHeightMultiple: 1.05)
        case .heading2: return StyleMetrics(spacingBefore: 0, spacingAfter: 0, lineHeightMultiple: 1.05)
        case .heading3: return StyleMetrics(spacingBefore: 0, spacingAfter: 0, lineHeightMultiple: 1.05)
        case .heading4: return StyleMetrics(spacingBefore: 0, spacingAfter: 0, lineHeightMultiple: 1.05)
        case .heading5: return StyleMetrics(spacingBefore: 0, spacingAfter: 0, lineHeightMultiple: 1.05)
        case .heading6: return StyleMetrics(spacingBefore: 0, spacingAfter: 0, lineHeightMultiple: 1.05)
        case .body:     return StyleMetrics(spacingBefore: 0,  spacingAfter: bodyParagraphSpacingAfter, lineHeightMultiple: 1.10)
        case .caption:  return StyleMetrics(spacingBefore: 0,  spacingAfter: 0, lineHeightMultiple: 1.10)   // interior "\n"s read at line pitch, like the chat's caption rendering; the media box provides outer spacing
        case .pullQuote: return StyleMetrics(spacingBefore: 0, spacingAfter: 0, lineHeightMultiple: 1.10)   // box insets provide padding; runs read close together
        }
    }

    public func font(for style: ParagraphStyleName, attributes: CharacterAttributes) -> NSFont {
        let size = attributes.fontSize.map { CGFloat($0) } ?? baseSize(style)
        // The chat renders headings in the system SERIF (New York) at MEDIUM weight and body text sans
        // (ChatRichTextRowItem's `header`/`subheader` categories); the composer mirrors that for WYSIWYG.
        // Bold/italic stay user emphasis only, and a bold heading keeps the serif family (weight .bold).
        let bold = attributes.bold
        let italic = attributes.italic || style == .pullQuote   // pull quotes render forced-italic (render-only)
        let serif = isHeading(style)
        let weight: NSFont.Weight = serif ? (bold ? .bold : .medium) : .regular
        return FontResolver.font(family: attributes.fontFamily, size: size, bold: bold, italic: italic, serif: serif, weight: weight)
    }

    private func isHeading(_ style: ParagraphStyleName) -> Bool {
        switch style {
        case .heading1, .heading2, .heading3, .heading4, .heading5, .heading6:
            return true
        case .body, .pullQuote, .caption:
            return false
        }
    }

    public func paragraphStyle(for style: ParagraphStyleName, attributes: ParagraphAttributes,
                               list: ListMembership? = nil) -> NSParagraphStyle {
        let ps = NSMutableParagraphStyle()
        switch attributes.alignment {
        case .left: ps.alignment = .left
        case .center: ps.alignment = .center
        case .right: ps.alignment = .right
        case .justified: ps.alignment = .justified
        case .natural: ps.alignment = .natural
        }
        ps.firstLineHeadIndent = CGFloat(attributes.firstLineIndent)
        ps.headIndent = CGFloat(attributes.headIndent)
        ps.paragraphSpacingBefore = CGFloat(attributes.paragraphSpacingBefore)
        ps.paragraphSpacing = CGFloat(attributes.paragraphSpacingAfter)
        ps.lineHeightMultiple = CGFloat(attributes.lineHeightMultiple)
        let m = metrics(for: style)
        ps.paragraphSpacingBefore += m.spacingBefore
        ps.paragraphSpacing += m.spacingAfter
        if ps.lineHeightMultiple == 1 { ps.lineHeightMultiple = m.lineHeightMultiple }
        if let list = list {
            // Marker sits at the level's indent; text hangs past it. Ordered (numbered) items get extra
            // inset (a number is wider than a bullet); a checklist's text must clear the wider checkbox.
            var indent = StyleSheet.listIndentStep * CGFloat(list.level)
            switch list.marker {
            case .bullet:    indent += StyleSheet.listMarkerSpacing
            case .ordered:   indent += StyleSheet.listMarkerSpacing + StyleSheet.orderedListTextInset
            case .checklist: indent += StyleSheet.checkboxSize + StyleSheet.checkboxTextGap
            }
            ps.firstLineHeadIndent += indent
            ps.headIndent += indent
        }
        if style == .pullQuote { ps.alignment = .center }
        return ps
    }
}
#endif
