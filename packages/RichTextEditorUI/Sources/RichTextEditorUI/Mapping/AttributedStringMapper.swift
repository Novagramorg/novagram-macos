#if canImport(AppKit)
import AppKit
import CoreText
import RichTextEditorCore

@available(macOS 12, *)
extension NSAttributedString.Key {
    /// Marks a run as inline code (GFM `code`). At render time the mapper swaps in a monospaced font
    /// + subtle background; on read-back it round-trips to `CharacterAttributes.inlineCode` (and
    /// suppresses fontFamily/highlight derivation so the mono font + code background don't leak into
    /// the model).
    static let rtInlineCode = NSAttributedString.Key("RTInlineCode")

    /// Render-only marker for a Telegram spoiler run. Carries NO visible styling here — the visible
    /// HIDE is a TextKit-2 clear-foreground RENDERING attribute applied per region in `BlockLayout`
    /// (so it never enters the model). Round-trips to `CharacterAttributes.spoiler`, mirroring
    /// `rtInlineCode`.
    static let rtSpoiler = NSAttributedString.Key("RTSpoiler")

    /// Round-trip marker for an inline math formula run — the LaTeX source, carried independently of the
    /// rendered image attachment so the model keeps the formula even if rendering is momentarily unavailable.
    static let rtFormula = NSAttributedString.Key("RTFormula")
}

/// Converts between the Core model and `NSAttributedString` for one paragraph block.
@available(macOS 12, *)
public struct AttributedStringMapper {
    public let styleSheet: StyleSheet
    public let appearance: EditorAppearance
    public let emojiScale: CGFloat
    public init(styleSheet: StyleSheet = .default, appearance: EditorAppearance = .default, emojiScale: CGFloat = 1.0) { self.styleSheet = styleSheet; self.appearance = appearance; self.emojiScale = emojiScale }

    /// A copy of this mapper for BLOCK-QUOTE children: body paragraphs drop their trailing/interior
    /// paragraph spacing so quoted lines read tight, matching the chat's quote rendering. Split/merge
    /// replacement boxes inherit it via their source box's `mapper`.
    public func quoteChildrenVariant() -> AttributedStringMapper {
        var s = styleSheet
        s.bodyParagraphSpacingAfter = 0
        return AttributedStringMapper(styleSheet: s, appearance: appearance, emojiScale: emojiScale)
    }

    /// Points to enlarge a rendered inline emoji beyond its glyph box (decoupled from the layout box, so
    /// it never expands the line — see `EmojiTextAttachment.renderBoost`). Matches the chat's InstantPage
    /// emoji sizing (`ascender − descender + 4·pointSize/17`), so the editor is WYSIWYG.
    public func emojiRenderBoost(forFont font: NSFont) -> CGFloat {
        return 4.0 * font.pointSize / 17.0
    }

    public func attributes(for ca: CharacterAttributes, style: ParagraphStyleName) -> [NSAttributedString.Key: Any] {
        if let button = ca.button {
            // A button run is purely the inline atom, like emoji; no other char attribute applies.
            return [.font: styleSheet.font(for: style, attributes: ca),
                    .attachment: buttonAttachment(button: button, isBlockPill: false, maxWidth: nil)]
        }
        if let emoji = ca.emoji {
            let font = styleSheet.font(for: style, attributes: ca)
            return [.font: font,
                    .attachment: EmojiTextAttachment(ref: emoji, scale: emojiScale,
                                                     renderBoost: emojiRenderBoost(forFont: font))]
        }
        if let latex = ca.formula {
            let font = styleSheet.font(for: style, attributes: ca)
            let color = ca.foreground?.nsColor ?? (style == .caption ? appearance.secondaryForeground : appearance.defaultForeground)
            // `.rtFormula` keeps the LaTeX in the model regardless of whether the image renders; the
            // attachment (the visible math image) is best-effort.
            var dict: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .rtFormula: latex]
            if let att = FormulaTextAttachment(latex: latex, fontSize: font.pointSize, color: color) {
                dict[.attachment] = att
            }
            return dict
        }
        var dict: [NSAttributedString.Key: Any] = [:]
        dict[.font] = styleSheet.font(for: style, attributes: ca)
        // Captions (media blocks) default to the secondary/gray color, mirroring the chat's caption look.
        dict[.foregroundColor] = ca.foreground?.nsColor ?? (style == .caption ? appearance.secondaryForeground : appearance.defaultForeground)
        if let hl = ca.highlight { dict[.backgroundColor] = hl.nsColor }
        if ca.underline { dict[.underlineStyle] = NSUnderlineStyle.single.rawValue }
        if ca.strikethrough { dict[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
        if let link = ca.link {
            dict[.link] = link
            // Visible styling is render-derived from the link and suppressed on read-back (see
            // characterAttributes(from:)), mirroring the rtInlineCode precedent — so it never
            // contaminates the model's foreground/underline fields. If a run is also inline-code, the
            // code font/background win visually; both flags still round-trip independently.
            dict[.foregroundColor] = appearance.linkColor
            // No underline: reference design shows links as blue text only.
        }
        if let b = ca.baselineOffset { dict[.baselineOffset] = b }
        if ca.inlineCode {
            let size = styleSheet.font(for: style, attributes: ca).pointSize
            dict[.font] = NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
            dict[.backgroundColor] = appearance.inlineCodeBackground
            dict[.rtInlineCode] = true
        }
        if ca.spoiler { dict[.rtSpoiler] = true }
        return dict
    }

    public func characterAttributes(from dict: [NSAttributedString.Key: Any]) -> CharacterAttributes {
        if let att = dict[.attachment] as? ButtonTextAttachment {
            // Button-only: render-time label typography/colors never enter the model.
            var ca = CharacterAttributes(); ca.button = att.button; return ca
        }
        if let att = dict[.attachment] as? EmojiTextAttachment {
            var ca = CharacterAttributes(); ca.emoji = att.ref; return ca
        }
        if let latex = dict[.rtFormula] as? String {
            var ca = CharacterAttributes(); ca.formula = latex; return ca
        }
        var ca = CharacterAttributes()
        let isCode = (dict[.rtInlineCode] as? Bool) == true
        if let font = dict[.font] as? NSFont {
            let traits = font.fontDescriptor.symbolicTraits
            ca.bold = traits.contains(.bold)
            ca.italic = traits.contains(.italic)
            if !isCode {
                ca.fontSize = Double(font.pointSize)
                let sansDefault = NSFont.systemFont(ofSize: font.pointSize).familyName ?? ""
                let serifDefault = NSFont.systemFont(ofSize: font.pointSize).fontDescriptor
                    .withDesign(.serif).flatMap { NSFont(descriptor: $0, size: font.pointSize) }?.familyName
                if font.familyName != sansDefault && font.familyName != serifDefault {
                    ca.fontFamily = font.familyName
                }
            }
        }
        if isCode { ca.inlineCode = true }
        let hasLink = dict[.link] != nil
        // Don't bake the foreground into the model: the editor has no text-color feature, so a normal
        // run's color is only ever the theme's `defaultForeground`. Storing it would freeze text to the
        // theme it was typed in (dark-typed text renders black in light mode, and vice versa) — instead
        // leave `foreground == nil` so render resolves it to the CURRENT theme's `defaultForeground`.
        // (Linked runs already keep foreground == nil; their blue is render-only.)
        if !isCode, let bg = dict[.backgroundColor] as? NSColor { ca.highlight = bg.rgba }
        if !hasLink, let u = dict[.underlineStyle] as? Int, u != 0 { ca.underline = true }
        if let s = dict[.strikethroughStyle] as? Int, s != 0 { ca.strikethrough = true }
        if let link = dict[.link] as? String { ca.link = link }
        else if let url = dict[.link] as? URL { ca.link = url.absoluteString }
        if let b = dict[.baselineOffset] as? Double { ca.baselineOffset = b }
        else if let b = dict[.baselineOffset] as? CGFloat { ca.baselineOffset = Double(b) }
        if (dict[.rtSpoiler] as? Bool) == true { ca.spoiler = true }
        return ca
    }

    public func attributedString(for block: ParagraphBlock) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let paragraphStyle = styleSheet.paragraphStyle(for: block.style, attributes: block.paragraph,
                                                       list: block.list)
        for run in block.runs {
            var attrs = attributes(for: run.attributes, style: block.style)
            attrs[.paragraphStyle] = paragraphStyle
            result.append(NSAttributedString(string: run.text, attributes: attrs))
        }
        return result
    }

    /// The ONE construction path for both pill kinds (inline `textButton` + row member) — two
    /// independent constructions drifted apart once in the renderer. `horizontalPadding` is passed
    /// only by the row packer's tight-fallback re-measure.
    ///
    /// An INLINE link-styled button is the renderer's `.plain` presentation, not a pill: paragraph
    /// typography (no font push), zero padding, no fill, the link color for the label — plain link
    /// text in the sentence. (A link-styled ROW pill keeps the pill box but is likewise chrome-less.)
    func buttonAttachment(button: ButtonRef, isBlockPill: Bool, maxWidth: CGFloat?,
                          horizontalPadding: CGFloat? = nil) -> ButtonTextAttachment {
        let metrics = RichTextButtonMetrics.default
        let isPlainLink = !isBlockPill && button.isLink
        // A link-styled pill draws no background and takes no inner padding (reads as a link).
        let defaultPad = isBlockPill ? (button.isLink ? 0.0 : metrics.blockHorizontalPadding)
                                     : (isPlainLink ? 0.0 : metrics.inlineHorizontalPadding)
        let hPad = horizontalPadding ?? defaultPad
        let vPad = isPlainLink ? 0.0 : metrics.verticalPadding
        let fontSize = isBlockPill ? metrics.blockFontSize : metrics.inlineFontSize
        let weight = isBlockPill ? metrics.blockFontWeight : metrics.inlineFontWeight
        let font = NSFont.systemFont(ofSize: fontSize, weight: weight)

        let label = NSMutableAttributedString()
        for run in button.label {
            var attrs = attributes(for: run.attributes, style: .body)
            // A nested button is not representable inside a label. The label carries its OWN
            // typography, never the paragraph's — except a plain link, which IS paragraph text.
            if attrs[.attachment] is ButtonTextAttachment { attrs.removeValue(forKey: .attachment) }
            attrs.removeValue(forKey: .paragraphStyle)
            label.append(NSAttributedString(string: run.text, attributes: attrs))
        }
        if !isPlainLink {
            label.addAttribute(.font, value: font, range: NSRange(location: 0, length: label.length))
        }
        let inset = (!isBlockPill && !isPlainLink) ? labelWithInsetEmoji(label) : label
        let fitted = labelWithFittedEmoji(inset, preserveBodyEmojiSize: isPlainLink)

        var effective: NSAttributedString = fitted
        var truncated = false
        if let maxWidth {
            (effective, truncated) = truncatedButtonLabel(fitted, availableWidth: max(0, maxWidth - hPad * 2.0))
        }

        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        let inkWidth = CGFloat(CTLineGetTypographicBounds(CTLineCreateWithAttributedString(effective),
                                                          &ascent, &descent, nil))
        if effective.length == 0 {
            // An empty label still needs a real box, or the pill collapses and cannot be clicked.
            let emptyFont = isPlainLink ? styleSheet.font(for: .body, attributes: CharacterAttributes()) : font
            ascent = emptyFont.ascender
            descent = -emptyFont.descender
        }
        let size = CGSize(width: inkWidth + hPad * 2.0, height: ascent + descent + vPad * 2.0)
        let colors = appearance.resolvedButtonColors(color: button.color,
                                                     isDisabled: button.action == .disabled,
                                                     isLink: button.isLink,
                                                     isBlockPill: isBlockPill)
        return ButtonTextAttachment(button: button, labelString: effective, size: size,
                                    ascent: ascent + vPad, descent: descent + vPad,
                                    horizontalPadding: hPad, isTruncated: truncated, colors: colors)
    }

    /// Port of the renderer's `instantPageInlineButtonLabelWithInsetEmoji`: Apple Color Emoji paints
    /// substantially larger than SF text at the same point size, so an INLINE pill label scales plain
    /// Unicode emoji to 0.75× — matching the visible lettering without inflating the pill box. Custom
    /// emoji attachment runs are untouched, and block rows don't scale on either side.
    private func labelWithInsetEmoji(_ labelString: NSMutableAttributedString) -> NSMutableAttributedString {
        let result = labelString
        let string = result.string as NSString
        string.enumerateSubstrings(in: NSRange(location: 0, length: string.length),
                                   options: .byComposedCharacterSequences) { substring, range, _, _ in
            guard let substring, richTextStringIsSingleEmoji(substring),
                  result.attribute(.attachment, at: range.location, effectiveRange: nil) == nil,
                  let font = result.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont,
                  let scaled = NSFont(descriptor: font.fontDescriptor, size: font.pointSize * 0.75)
            else { return }
            result.addAttribute(.font, value: scaled, range: range)
        }
        return result
    }

    /// Transcription of the renderer's `instantPageButtonLabelWithFittedEmoji`: CoreText never calls
    /// `NSTextAttachment.attachmentBounds`, so a CTLine over an emoji-bearing label would advance by
    /// the bare U+FFFC glyph instead of the emoji square the renderer reserves. Each emoji run gets a
    /// `kCTRunDelegateAttributeName` with the renderer's box (`ascender − descender`; a plain link
    /// label keeps the larger body emoji size, `+ renderBoost`), AND its attachment is swapped for one
    /// whose TextKit bounds equal the same width — so the CTLine measurement, the TextKit draw path,
    /// and the sent message all agree on the reserved advance.
    private func labelWithFittedEmoji(_ labelString: NSAttributedString, preserveBodyEmojiSize: Bool) -> NSAttributedString {
        struct RunStruct {
            let ascent: CGFloat
            let descent: CGFloat
            let width: CGFloat
        }

        var emojiRuns: [(index: Int, attachment: EmojiTextAttachment)] = []
        labelString.enumerateAttribute(.attachment, in: NSRange(location: 0, length: labelString.length),
                                       options: []) { value, range, _ in
            guard let emoji = value as? EmojiTextAttachment else { return }
            for index in range.location ..< range.location + range.length {
                emojiRuns.append((index, emoji))
            }
        }
        guard !emojiRuns.isEmpty else {
            return labelString
        }

        let result = NSMutableAttributedString(attributedString: labelString)
        for (index, emoji) in emojiRuns {
            let font = (labelString.attribute(.font, at: index, effectiveRange: nil) as? NSFont)
                ?? NSFont.systemFont(ofSize: 17.0)
            let base = font.ascender - font.descender
            let side = preserveBodyEmojiSize ? base + emojiRenderBoost(forFont: font) : base
            let extentBuffer = UnsafeMutablePointer<RunStruct>.allocate(capacity: 1)
            extentBuffer.initialize(to: RunStruct(ascent: font.ascender, descent: -font.descender, width: side))
            var callbacks = CTRunDelegateCallbacks(version: kCTRunDelegateVersion1, dealloc: { pointer in
                pointer.assumingMemoryBound(to: RunStruct.self).deallocate()
            }, getAscent: { pointer -> CGFloat in
                return pointer.assumingMemoryBound(to: RunStruct.self).pointee.ascent
            }, getDescent: { pointer -> CGFloat in
                return pointer.assumingMemoryBound(to: RunStruct.self).pointee.descent
            }, getWidth: { pointer -> CGFloat in
                return pointer.assumingMemoryBound(to: RunStruct.self).pointee.width
            })
            let delegate = CTRunDelegateCreate(&callbacks, extentBuffer)
            var attrs: [NSAttributedString.Key: Any] = [
                kCTRunDelegateAttributeName as NSAttributedString.Key: delegate as Any
            ]
            if base > 0 {
                attrs[.attachment] = EmojiTextAttachment(ref: emoji.ref, scale: side / base)
            }
            result.addAttributes(attrs, range: NSRange(location: index, length: 1))
        }
        return result
    }

    /// Tail-ellipsis on CLUSTER boundaries via `CTTypesetterSuggestClusterBreak`; the ellipsis inherits
    /// the LAST character's attributes. `truncated` is returned explicitly, NOT inferred by length (a
    /// 1-char label replaced by a bare ellipsis keeps length 1). A zero/negative budget with a
    /// non-empty label counts as truncated — the renderer's semantics, and what arms the tight-padding
    /// retry for a badge-bearing pill in a very narrow justified column.
    private func truncatedButtonLabel(_ labelString: NSAttributedString, availableWidth: CGFloat)
        -> (label: NSAttributedString, truncated: Bool) {
        guard labelString.length != 0, availableWidth > 0 else {
            return (labelString, labelString.length != 0)
        }
        let fullWidth = CGFloat(CTLineGetTypographicBounds(CTLineCreateWithAttributedString(labelString), nil, nil, nil))
        if fullWidth <= availableWidth {
            return (labelString, false)
        }
        let tailAttributes = labelString.attributes(at: labelString.length - 1, effectiveRange: nil)
        let ellipsis = NSAttributedString(string: "\u{2026}", attributes: tailAttributes)
        let ellipsisWidth = CGFloat(CTLineGetTypographicBounds(CTLineCreateWithAttributedString(ellipsis), nil, nil, nil))
        let widthForText = availableWidth - ellipsisWidth
        guard widthForText > 0 else {
            return (ellipsis, true)
        }
        let typesetter = CTTypesetterCreateWithAttributedString(labelString)
        let fittingCount = CTTypesetterSuggestClusterBreak(typesetter, 0, Double(widthForText))
        guard fittingCount > 0 else {
            return (ellipsis, true)
        }
        let result = NSMutableAttributedString(attributedString:
            labelString.attributedSubstring(from: NSRange(location: 0, length: min(fittingCount, labelString.length))))
        result.append(ellipsis)
        return (result, true)
    }

    public func runs(from attr: NSAttributedString) -> [TextRun] {
        var runs: [TextRun] = []
        let full = NSRange(location: 0, length: attr.length)
        attr.enumerateAttributes(in: full, options: []) { dict, range, _ in
            let text = (attr.string as NSString).substring(with: range)
            runs.append(TextRun(text: text, attributes: characterAttributes(from: dict)))
        }
        return runs
    }
}
#endif
