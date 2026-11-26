#if canImport(AppKit)
import AppKit
import RichTextEditorCore

/// Invisible attachment reserving a square, font-scaled box for one inline custom emoji (one U+FFFC).
/// Draws nothing; the host-provided NSView is the only visual.
@available(macOS 12, *)
final class EmojiTextAttachment: NSTextAttachment {
    let ref: EmojiRef
    let scale: CGFloat
    /// Points to enlarge the RENDERED host view beyond the reserved glyph box (centered on it). Layout
    /// (line height, caret, selection) is untouched — the extra size bleeds into the line's leading,
    /// matching how the chat's InstantPage rendering draws emoji larger than the run font
    /// (`ascender − descender + 4·pointSize/17`).
    let renderBoost: CGFloat
    private static let spacerImage: NSImage = {
        let img = NSImage(size: CGSize(width: 1, height: 1))
        img.lockFocus(); NSColor.clear.set(); NSBezierPath(rect: CGRect(x: 0, y: 0, width: 1, height: 1)).fill(); img.unlockFocus()
        return img
    }()
    init(ref: EmojiRef, scale: CGFloat, renderBoost: CGFloat = 0) {
        self.ref = ref; self.scale = scale; self.renderBoost = renderBoost
        super.init(data: nil, ofType: nil)
        self.image = Self.spacerImage
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }
    override func attachmentBounds(for attributes: [NSAttributedString.Key: Any], location: NSTextLocation,
                                   textContainer: NSTextContainer?, proposedLineFragment: CGRect, position: CGPoint) -> CGRect {
        let font = (attributes[.font] as? NSFont) ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
        let side = (font.ascender - font.descender) * scale
        return CGRect(x: 0, y: font.descender, width: side, height: side)
    }
}
#endif
