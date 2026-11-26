#if canImport(AppKit)
import AppKit
import RichTextEditorCore

/// Injectable editor theming. Defaults reproduce the editor's built-in look exactly; a host can map
/// its own theme into this without touching editor internals.
@available(macOS 12, *)
public struct EditorAppearance {
    public var caretColor: NSColor
    public var selectionFocused: NSColor
    public var selectionUnfocused: NSColor
    /// Retained for API compatibility, but NOT applied to the editor surface — the canvas and its scroll
    /// view are always transparent so the host's background shows through.
    public var background: NSColor
    public var linkColor: NSColor
    public var inlineCodeBackground: NSColor
    public var defaultForeground: NSColor
    /// Secondary/gray text color — used for media-block captions (mirrors the chat's caption color).
    public var secondaryForeground: NSColor
    /// The cover/dust color for hidden spoiler runs.
    public var spoilerCoverColor: NSColor
    /// Accent for code-block chrome (left bar, language line), matching the chat's code rendering.
    /// nil → `linkColor`.
    public var codeAccent: NSColor?
    /// A code block's language-line text colour. nil → `codeAccent`/`linkColor` — the colour the old
    /// display-only header label used, so making the line editable changes nothing visually.
    public var codeLanguageText: NSColor?
    /// The "Language" placeholder colour on an EMPTY language line. nil → `NSColor.placeholderTextColor`.
    public var codeLanguagePlaceholder: NSColor?
    /// Dark-appearance flag: a dark host renders the code-block body fill from black (mirroring the
    /// chat's code bubble), a light one from the accent.
    public var isDark: Bool
    /// Neutral (colorless) INLINE button pill fill (the renderer's `panelBackgroundColor`).
    public var buttonNeutralFill: NSColor
    /// Neutral INLINE pill label color (the renderer's `panelAccentColor`). nil → `linkColor`.
    public var buttonNeutralLabel: NSColor?
    /// Neutral BLOCK-row pill fill (the renderer's `tableHeaderColor`). nil → `buttonNeutralFill`.
    public var buttonNeutralBlockFill: NSColor?
    /// Neutral BLOCK-row pill label color (the renderer's `panelPrimaryColor` — the primary text
    /// color, NOT the accent). nil → `defaultForeground`.
    public var buttonNeutralBlockLabel: NSColor?
    /// `.primary` button fill (the renderer's `checkboxFill`). nil → `linkColor`.
    public var buttonPrimaryFill: NSColor?
    /// `.primary` button label (the renderer's `checkboxForeground`). nil → white.
    public var buttonPrimaryLabel: NSColor?
    /// Danger button LABEL color; the fill is this at 15% alpha.
    public var buttonDanger: NSColor
    /// Success button LABEL color; the fill is this at 15% alpha.
    public var buttonSuccess: NSColor

    public init(
        caretColor: NSColor = .labelColor,
        selectionFocused: NSColor = .selectedTextBackgroundColor,
        selectionUnfocused: NSColor = .unemphasizedSelectedTextBackgroundColor,
        background: NSColor = .textBackgroundColor,
        linkColor: NSColor = .linkColor,
        inlineCodeBackground: NSColor = NSColor.systemGray.withAlphaComponent(0.15),
        defaultForeground: NSColor = NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 1),
        secondaryForeground: NSColor = .secondaryLabelColor,
        spoilerCoverColor: NSColor = .secondaryLabelColor,
        codeAccent: NSColor? = nil,
        codeLanguageText: NSColor? = nil,
        codeLanguagePlaceholder: NSColor? = nil,
        isDark: Bool = false,
        buttonNeutralFill: NSColor = NSColor(white: 0.5, alpha: 0.12),
        buttonNeutralLabel: NSColor? = nil,
        buttonNeutralBlockFill: NSColor? = nil,
        buttonNeutralBlockLabel: NSColor? = nil,
        buttonPrimaryFill: NSColor? = nil,
        buttonPrimaryLabel: NSColor? = nil,
        buttonDanger: NSColor = .systemRed,
        buttonSuccess: NSColor = .systemGreen
    ) {
        self.caretColor = caretColor
        self.selectionFocused = selectionFocused
        self.selectionUnfocused = selectionUnfocused
        self.background = background
        self.linkColor = linkColor
        self.inlineCodeBackground = inlineCodeBackground
        self.defaultForeground = defaultForeground
        self.secondaryForeground = secondaryForeground
        self.spoilerCoverColor = spoilerCoverColor
        self.codeAccent = codeAccent
        self.codeLanguageText = codeLanguageText
        self.codeLanguagePlaceholder = codeLanguagePlaceholder
        self.isDark = isDark
        self.buttonNeutralFill = buttonNeutralFill
        self.buttonNeutralLabel = buttonNeutralLabel
        self.buttonNeutralBlockFill = buttonNeutralBlockFill
        self.buttonNeutralBlockLabel = buttonNeutralBlockLabel
        self.buttonPrimaryFill = buttonPrimaryFill
        self.buttonPrimaryLabel = buttonPrimaryLabel
        self.buttonDanger = buttonDanger
        self.buttonSuccess = buttonSuccess
    }

    /// The one resolution point for InstantPage button pill colors, so an inline pill and a row pill
    /// cannot derive different colors for the same button. Precedence mirrors the renderer:
    /// link > primary > danger > success — `isLink` wins over `color`, which is still CARRIED
    /// (lossless round-trip) but not read when link. The neutral pair splits on `isBlockPill` exactly
    /// as the renderer's `instantPageButtonPillColors` splits on `isInline`: an inline pill sits in
    /// running text and takes a lighter fill with the accent label; a block pill takes the
    /// table-header-like fill with the PRIMARY text label. Disabled = 40% label alpha, fill unchanged.
    func resolvedButtonColors(color: ButtonColor?, isDisabled: Bool, isLink: Bool = false,
                              isBlockPill: Bool = false) -> (fill: NSColor, label: NSColor) {
        if isLink {
            return (.clear, isDisabled ? linkColor.withAlphaComponent(0.4) : linkColor)
        }
        let fill: NSColor
        let label: NSColor
        switch color {
        case .none:
            if isBlockPill {
                fill = buttonNeutralBlockFill ?? buttonNeutralFill
                label = buttonNeutralBlockLabel ?? defaultForeground
            } else {
                fill = buttonNeutralFill
                label = buttonNeutralLabel ?? linkColor
            }
        case .some(.primary):
            fill = buttonPrimaryFill ?? linkColor
            label = buttonPrimaryLabel ?? .white
        case .some(.danger):
            fill = buttonDanger.withAlphaComponent(0.15)
            label = buttonDanger
        case .some(.success):
            fill = buttonSuccess.withAlphaComponent(0.15)
            label = buttonSuccess
        }
        return isDisabled ? (fill, label.withAlphaComponent(0.4)) : (fill, label)
    }

    public static let `default` = EditorAppearance()
}
#endif
