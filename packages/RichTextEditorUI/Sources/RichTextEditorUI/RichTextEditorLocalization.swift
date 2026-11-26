import Foundation

/// Localization seam for the editor's built-in menu titles and placeholders. The package stays free of
/// any host localization dependency (so its own tests run standalone); a host app assigns `localize` once
/// at startup to route these keys through its own localization system. The default returns the English
/// fallback, which is also what the package's tests see.
public enum RichTextEditorLocalization {
    public static var localize: (_ key: String, _ fallback: String) -> String = { _, fallback in fallback }
}

func editorLocalized(_ key: String, _ fallback: String) -> String {
    return RichTextEditorLocalization.localize(key, fallback)
}
