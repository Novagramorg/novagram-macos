#if canImport(AppKit)
import AppKit

/// One highlighted token range in a code block. A package-local value type on purpose: the editor cannot
/// see the app's highlighter (libprisma lives behind the `CodeSyntax` framework, and this package must
/// stay SwiftPM-testable with no app dependency), so no app type may cross this boundary. The HOST turns
/// (language, text) into these.
public struct RichTextSyntaxToken: Equatable {
    /// A range in the code block's text, in UTF-16 units.
    public let range: NSRange
    public let color: NSColor

    public init(range: NSRange, color: NSColor) {
        self.range = range
        self.color = color
    }
}

/// The cache key for one highlight request: a normalized language plus the exact code text.
struct CodeHighlightSpec: Hashable {
    let language: String
    let text: String
}

/// One cached answer, stamped with the palette it was produced under.
///
/// The UIKit editor stores the bare token list because both of its hosts bake a FIXED light palette
/// (`asyncStanaloneSyntaxHighlight`), which makes (language, text) a complete identity. The macOS host
/// deliberately does the opposite — it builds its `SyntaxterTheme` from the LIVE app theme at request
/// time — so the same (language, text) answers different colours per theme, and an answer is only
/// reusable while the palette that produced it is still the one on screen.
struct CachedSyntaxHighlight {
    let paletteToken: String
    let tokens: [RichTextSyntaxToken]
}

/// A value identity for the palette the host bakes into its answers, derived from the injected
/// appearance (the only theme signal the editor gets — `canvas` is package-internal, so a host cannot
/// stamp the palette itself).
///
/// Deliberately VALUE-based, not identity- or assignment-based: the inline chat composer re-assigns a
/// freshly built, colour-identical `EditorAppearance` on every update pass, and bumping a generation
/// counter there would re-request every spec on every layout — a request storm. Components are compared
/// numerically in sRGB rather than by `NSColor ==` so two equal colours built by different routes (a
/// dynamic catalog colour vs. a component colour) still agree.
@available(macOS 12, *)
func richTextSyntaxPaletteToken(_ appearance: EditorAppearance) -> String {
    func component(_ color: NSColor?) -> String {
        guard let color else { return "-" }
        guard let rgb = color.usingColorSpace(.sRGB) else { return String(describing: color) }
        return String(format: "%.4f/%.4f/%.4f/%.4f",
                      Double(rgb.redComponent), Double(rgb.greenComponent),
                      Double(rgb.blueComponent), Double(rgb.alphaComponent))
    }
    // The fields that feed the host's `SyntaxterTheme`: its `dark` flag, its `textColor`, and the theme
    // colours `generateSyntaxThemeParams` derives its per-token brushes from (text / gray / link / accent).
    return [
        appearance.isDark ? "dark" : "light",
        component(appearance.defaultForeground),
        component(appearance.secondaryForeground),
        component(appearance.linkColor),
        component(appearance.codeAccent),
        component(appearance.codeLanguageText),
        component(appearance.inlineCodeBackground),
    ].joined(separator: "|")
}

/// A code block's language, trimmed and lowercased, or nil when it carries none usable. **Must agree with
/// the host's normalization** — libprisma's grammar lookup is an exact lowercase-keyed map ("Swift"
/// produces zero tokens with no error), so the editor sends the normalized value and the host keys any
/// shared cache with it; a divergence here means every lookup misses.
func richTextNormalizedCodeLanguage(_ language: String?) -> String? {
    guard let language else { return nil }
    let normalized = language.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return normalized.isEmpty ? nil : normalized
}
#endif
