#if canImport(AppKit)
import AppKit
import RichTextEditorCore

/// Link commands. Like the character toggles, they operate over the same targets as
/// `characterFormatTargets()` — every leaf region the text selection touches, or every cell of a
/// structurally-selected table row/column — so a link is continuous across cells. A link carries a
/// value, so these build on `applyCharacterAttribute` (a value-set sibling of `applyCharacterToggle`)
/// rather than the toggle engine. A bare collapsed caret (no table selection) is a no-op. The visible
/// blue styling (no underline) is injected into the live storage here AND emitted by the mapper on
/// rebuild, and suppressed on read-back — so the model stays link-only (see `AttributedStringMapper`).
@available(macOS 12, *)
extension DocumentCanvasView {
    /// Runs `mutate` on each (storage, range) `characterFormatTargets()` covers, inside `editing { }`.
    /// No toggle direction — just a per-range mutation. No-op when nothing is targeted.
    func applyCharacterAttribute(_ mutate: (NSTextStorage, NSRange) -> Void) {
        let covered = characterFormatTargets()
        guard !covered.isEmpty else { return }
        editing {
            for c in covered { mutate(c.storage, c.range) }
        }
    }

    /// Sets `url` as the link over the selection, with the render-only blue styling (no underline).
    func setLink(_ url: String) {
        // A code block's language is a plain string on the wire — a link there would be dropped on
        // read-back (an inert edit that still dirties the model).
        if selectionIsEntirelyInCodeLanguageRegion() { return }
        applyCharacterAttribute { storage, range in
            storage.addAttribute(.link, value: url, range: range)
            storage.addAttribute(.foregroundColor, value: editorAppearance.linkColor, range: range)
            // No underline: reference design shows links as blue text only.
        }
    }

    /// Removes the link over the selection and its render-only styling (resets foreground to the
    /// mapper's default so the text renders like any other unlinked run).
    func removeLink() {
        applyCharacterAttribute { storage, range in
            storage.removeAttribute(.link, range: range)
            // Defensive: storage written before 6a may carry a link underline; clear it.
            storage.removeAttribute(.underlineStyle, range: range)
            // Match the mapper's default for unlinked runs (it writes (ca.foreground ?? .black)); don't
            // removeAttribute(.foregroundColor) — that would leave live storage colorless until the next rebuild.
            storage.addAttribute(.foregroundColor, value: editorAppearance.defaultForeground, range: range)
        }
    }

    /// The plain text of the current selection — used to prefill the URL prompt's text field.
    func selectedText() -> String { text(inGlobalRange: selFrom, selTo) }

    /// Sets/updates/removes a link from a two-field URL prompt (link text + url). If `text` matches the
    /// current selection's plain text, the link is toggled in place so the selection's existing
    /// formatting is preserved. Otherwise the selection is replaced with `text` (or, with a collapsed
    /// caret, `text` is inserted) and the link applied to that inserted text. `url == nil` clears the
    /// link, keeping the text. Called synchronously from the prompt's completion, so the replace + link
    /// land in one undo step under the view's (group-by-event) undo manager.
    ///
    /// The replace branch flattens the selection to plain `text`; an inline custom emoji in the
    /// selection is preserved only on the in-place (unchanged-text) path — editing the text around it
    /// drops the emoji's attachment. A link label is single-line, so newlines in `text` are collapsed.
    func applyLink(text rawText: String, url: String?) {
        let text = rawText.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\r", with: " ")
        if !text.isEmpty, text == selectedText() {
            if let url { setLink(url) } else { removeLink() }
            return
        }
        commitText(text)                                 // replaces the selection / inserts at the caret;
        let len = (text as NSString).length              // commitText always lands the caret at the END of
        selectedGlobalRange = (head - len, head)         // the inserted text, so this is snap-proof.
        if let url { setLink(url) } else { removeLink() }
    }

    /// The link the entire target carries (the text selection, or a structurally-selected table
    /// row/column — matching what `setLink` would apply), or nil if nothing is targeted, any covered
    /// text is unlinked, or two different links are mixed. Used to prefill the demo's URL prompt.
    func currentLink() -> String? {
        let targets = characterFormatTargets()
        guard !targets.isEmpty else { return nil }
        var values = Set<String>()
        var sawUnlinked = false
        for t in targets {
            t.storage.enumerateAttribute(.link, in: t.range, options: []) { v, _, _ in
                if let s = (v as? String) ?? (v as? URL)?.absoluteString { values.insert(s) }
                else { sawUnlinked = true }
            }
        }
        guard !sawUnlinked, values.count == 1 else { return nil }
        return values.first
    }
}
#endif
