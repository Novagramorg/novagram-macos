#if canImport(AppKit)
import AppKit
import RichTextEditorCore

/// One code block in the canvas: a monospace TextKit layout (multi-line; interior "\n"s) drawn inside the
/// quote-style bar+fill background (painted by `drawCodeBlockDecorations`). Mirrors `BlockBox` but is a
/// distinct `Block.code` type and builds its own monospace attributed string (so no `ParagraphStyleName`/
/// StyleSheet change). Inline formatting is not represented inside a code block — runs are plain.
///
/// **Language line** (mirrors the UIKit editor): a SECOND editable text region — the always-visible,
/// bold line at the top of the band where the block's language is authored. Modelled on the pull
/// quote's author but LEADING and **never content-gated**: unlike a quote author (which appears only
/// once its quote has content), the language field is always on the position axis, which is also what
/// keeps the code text's offset stable when a language is added or cleared. `.code` maps to a
/// `DocumentTree` CONTAINER of [languagePara, codePara] — see `DocumentTree.node(for:)`.
@available(macOS 12, *)
final class CodeBlockBox {
    let id: BlockID
    let layout: BlockLayout
    /// The language line's own TextKit layout — the editable "Language" region. ALWAYS present, even when
    /// the language is nil/empty (unlike a quote's author region, which appears only once its quote has
    /// content): the field is always visible, which is also what keeps the code text's offset stable.
    let languageLayout: BlockLayout
    let mapper: AttributedStringMapper

    var frame: CGRect = .zero
    var globalStart: Int = 0
    /// Monospace point size — matches the quote's body scale so a code block reads like a quote.
    static let fontSize: CGFloat = 14
    /// Vertical gap between the language line and the code text below it.
    static let languageSpacing: CGFloat = 4
    /// Interior LEFT padding (bar→text gap): the quote text indent, so code text clears the accent bar
    /// exactly like quote text (the quote paragraph style adds +16 — see StyleSheet).
    let leftInset: CGFloat = 16
    let rightInset: CGFloat = 8
    var topInset: CGFloat = BlockBox.defaultVerticalInset
    var bottomInset: CGFloat = BlockBox.defaultVerticalInset

    static func codeAttributes(appearance: EditorAppearance) -> [NSAttributedString.Key: Any] {
        let ps = NSMutableParagraphStyle()
        ps.lineBreakMode = .byWordWrapping
        return [.font: NSFont.monospacedSystemFont(ofSize: CodeBlockBox.fontSize, weight: .regular),
                .paragraphStyle: ps,
                .foregroundColor: appearance.defaultForeground]
    }

    static func attributedString(for code: CodeBlock, appearance: EditorAppearance) -> NSAttributedString {
        NSAttributedString(string: code.text, attributes: codeAttributes(appearance: appearance))
    }

    /// Attributes the language line renders with: a bold sans at the header-label size the old display-only
    /// band used, in the accent the chat's code-header label draws with — so making the line editable
    /// changes nothing visually. NOT lowercased: the field shows what the author typed. The renderer
    /// lowercases at display, so casing is a display concern there, not a model one.
    static func languageAttributes(appearance: EditorAppearance) -> [NSAttributedString.Key: Any] {
        [.font: NSFont.boldSystemFont(ofSize: 12),
         .foregroundColor: appearance.codeLanguageText ?? appearance.codeAccent ?? appearance.linkColor]
    }

    static func languageAttributedString(for language: String?, appearance: EditorAppearance) -> NSAttributedString {
        NSAttributedString(string: language ?? "", attributes: languageAttributes(appearance: appearance))
    }

    init(code: CodeBlock, mapper: AttributedStringMapper, width: CGFloat) {
        self.id = code.id
        self.mapper = mapper
        let inner = max(width - leftInset - rightInset, 1)
        self.languageLayout = BlockLayout(
            attributedString: CodeBlockBox.languageAttributedString(for: code.language, appearance: mapper.appearance),
            width: inner)
        self.layout = BlockLayout(attributedString: CodeBlockBox.attributedString(for: code, appearance: mapper.appearance),
                                  width: inner)
    }

    var length: Int { layout.length }
    var textRef: TextNodeRef { .code(id) }
    var textOrigin: CGPoint { CGPoint(x: frame.minX + leftInset, y: frame.minY + topInset + languageLineExtent) }

    var languageLength: Int { languageLayout.length }

    /// A single empty line's height in the language font. The line is always shown, so an empty language
    /// still reserves a line — that is where the "Language" placeholder is drawn.
    private var languageEmptyLineHeight: CGFloat {
        guard languageLayout.length == 0 else { return 0 }
        let font = (CodeBlockBox.languageAttributes(appearance: mapper.appearance)[.font] as? NSFont)
            ?? NSFont.boldSystemFont(ofSize: 12)
        // Ceil to match TextKit's integral line-fragment height, so an empty and a filled language line
        // reserve the SAME extent (the box must not change height when the first character is typed).
        return ceil(font.ascender - font.descender + font.leading)
    }

    /// Height the language line occupies above the code, gap included. UNCONDITIONAL — a language-less
    /// code block still reserves it, and is therefore about one line taller in the editor than the message
    /// it renders to (which draws no language line at all). That is the cost of an always-visible field.
    var languageLineExtent: CGFloat {
        max(languageLayout.boundingHeight, languageEmptyLineHeight) + CodeBlockBox.languageSpacing
    }

    /// Canvas origin of the language line: the band's top-left text position, above the code.
    var languageOrigin: CGPoint { CGPoint(x: frame.minX + leftInset, y: frame.minY + topInset) }

    private var emptyLineHeight: CGFloat {
        guard layout.length == 0 else { return 0 }
        let font = NSFont.monospacedSystemFont(ofSize: CodeBlockBox.fontSize, weight: .regular)
        return font.ascender - font.descender + font.leading
    }

    /// The tokens currently painted, so an identical answer can be recognised without rebuilding.
    private(set) var syntaxHighlight: [RichTextSyntaxToken] = []

    /// Paint `tokens` over the code text. Returns true when the layout's string actually changed.
    ///
    /// Rebuilding the whole string is lossless HERE specifically: a code block's runs are plain by
    /// construction (no link, emoji, inline-code or spoiler attribute lives inside one), so there is
    /// nothing else in the string to preserve. The rebuilt string is assigned **only when it differs** —
    /// an unconditional re-assign resets the spoiler-hide ranges and re-invalidates the layout.
    ///
    /// A token range that does not fit the current text means the answer describes text the user has since
    /// edited: the WHOLE set is dropped rather than applied partially, which would colour arbitrary spans.
    @discardableResult
    func applySyntaxHighlight(_ tokens: [RichTextSyntaxToken]) -> Bool {
        let text = layout.attributedString.string as NSString
        var accepted = tokens
        for token in tokens {
            if token.range.location < 0 || token.range.length <= 0 || token.range.location + token.range.length > text.length {
                accepted = []
                break
            }
        }
        if accepted == syntaxHighlight { return false }

        let rebuilt = NSMutableAttributedString(attributedString: NSAttributedString(
            string: text as String, attributes: CodeBlockBox.codeAttributes(appearance: mapper.appearance)))
        for token in accepted {
            rebuilt.addAttribute(.foregroundColor, value: token.color, range: token.range)
        }
        guard !rebuilt.isEqual(to: layout.attributedString) else {
            syntaxHighlight = accepted
            return false
        }
        syntaxHighlight = accepted
        layout.attributedString = rebuilt
        return true
    }

    func currentCode() -> CodeBlock {
        // Trim, and normalize an all-whitespace/empty line back to nil — "" and nil are the same state
        // (`languageUTF16Count` treats them identically, and the renderer draws no line for either).
        let typed = languageLayout.attributedString.string.trimmingCharacters(in: .whitespacesAndNewlines)
        return CodeBlock(id: id, language: typed.isEmpty ? nil : typed,
                         runs: [TextRun(text: layout.attributedString.string)])
    }
}

@available(macOS 12, *)
extension CodeBlockBox: CanvasBlock {
    var nodeStart: Int { get { globalStart } set { globalStart = newValue } }
    /// container(2) + language paragraph(lang + 2) + code paragraph(code + 2). Matches `DocumentTree`'s
    /// `.code` mapping — `CodeLanguageRegionTests.test_nodeSize_matchesDocumentTree` is that check.
    var nodeSize: Int { length + languageLength + 6 }
    var textLayout: BlockLayout { layout }
    /// The PRIMARY region stays the CODE text — `activeStack` resolves boxes by it, which is what keeps
    /// every existing code-block edit path inert in the language line. See `DocumentCanvasView+Editing`.
    var textStart: Int { globalStart + languageLength + 3 }
    var textLength: Int { length }
    var height: CGFloat {
        languageLineExtent + max(layout.boundingHeight, emptyLineHeight) + topInset + bottomInset
    }
    func setWidth(_ width: CGFloat) {
        let inner = max(width - leftInset - rightInset, 1)
        layout.setWidth(inner)
        languageLayout.setWidth(inner)
    }
    func currentBlock() -> Block { .code(currentCode()) }
    func closestPosition(toCanvasPoint point: CGPoint) -> Int {
        // A click above the code text routes into the language region, so the always-visible "Language"
        // placeholder is directly clickable. Mirrors `PullQuoteBox`'s author branch, inverted — the
        // language line is LEADING, so the comparison is `<` against the code's origin, not `>=`.
        if point.y < textOrigin.y {
            return (globalStart + 1) + languageLayout.closestOffset(
                toPoint: CGPoint(x: point.x - languageOrigin.x, y: point.y - languageOrigin.y))
        }
        return textStart + layout.closestOffset(toPoint: CGPoint(x: point.x - textOrigin.x, y: point.y - textOrigin.y))
    }
    func leafRegions() -> [LeafTextRegion] {
        // DOCUMENT ORDER — language first. Navigation walks `allLeafRegions()` in order, so a wrong order
        // breaks arrow-key traversal. Note this makes `leafRegions().first` the LANGUAGE region for a code
        // box: any caller that means "the box's primary text" must use `textStart`, not `.first`
        // (see `activeStack`).
        [LeafTextRegion(layout: languageLayout, globalStart: globalStart + 1, length: languageLength,
                        ref: .codeLanguage(id), canvasOrigin: languageOrigin),
         LeafTextRegion(layout: layout, globalStart: textStart, length: length,
                        ref: .code(id), canvasOrigin: textOrigin)]
    }
    func draw(in ctx: CGContext, imageProvider: (String) -> NSImage?) {
        // The chrome (fill, bar) is painted by `drawCodeBlockDecorations`.
        languageLayout.drawText(in: ctx, at: languageOrigin)
        if languageLength == 0 {
            var attrs = CodeBlockBox.languageAttributes(appearance: mapper.appearance)
            attrs[.foregroundColor] = mapper.appearance.codeLanguagePlaceholder ?? NSColor.placeholderTextColor
            NSAttributedString(string: editorLocalized("RichTextEditor.Placeholder.CodeLanguage", "Language"),
                               attributes: attrs).draw(at: languageOrigin)
        }
        layout.drawText(in: ctx, at: textOrigin)
    }
}
#endif
