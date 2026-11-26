#if canImport(AppKit)
import AppKit
import RichTextEditorCore

/// The active character formats at the caret/selection — what a host toolbar highlights.
@available(macOS 12, *)
public struct CharacterFormatState: Equatable {
    public var bold = false
    public var italic = false
    public var strikethrough = false
    public var underline = false
    public var inlineCode = false
    public var spoiler = false
    public init() {}
}

/// Character-format toggles. Each works over EVERY leaf text region the selection touches — body
/// paragraphs, image captions, and table cells (via `allLeafRegions`) — so formatting is continuous
/// across cells like selection itself. Attribute-only (no span change), wrapped in `editing { }` so
/// undo is the existing whole-document `[Block]` snapshot. A collapsed caret is a no-op (collapsed
/// "typing attributes" are deferred).
@available(macOS 12, *)
extension DocumentCanvasView {
    /// The (storage, range) pairs a character-format command applies to. When a table row/column is
    /// structurally selected, that's every cell's full text in the row/column (so toolbar formatting
    /// works on the whole row/column). Otherwise it's the text selection's intersection with each leaf
    /// region — body paragraphs, captions, and table cells alike. Empty when nothing applies (e.g. a
    /// bare collapsed caret).
    func characterFormatTargets() -> [(storage: NSTextStorage, range: NSRange)] {
        if let regions = tableStructuralSelectionRegions() {
            return regions.compactMap { r in
                guard r.length > 0, let storage = r.layout.contentStorage.textStorage else { return nil }
                return (storage, NSRange(location: 0, length: r.length))
            }
        }
        guard selFrom < selTo else { return [] }
        return allLeafRegions().compactMap { r in
            let a = max(selFrom, r.globalStart), b = min(selTo, r.globalStart + r.length)
            guard a < b, let storage = r.layout.contentStorage.textStorage else { return nil }
            return (storage, NSRange(location: a - r.globalStart, length: b - a))
        }
    }

    /// True when every character-format target lies in a `.codeLanguage` region. A code block's language
    /// is a PLAIN string on the wire (`.Pre` carries no nested entities), so every inline format there is
    /// either dropped on read-back — an inert edit that still dirties the model — or survives in the
    /// layout and corrupts what `currentCode()` reads back. Each format toggle returns early on it.
    func selectionIsEntirelyInCodeLanguageRegion() -> Bool {
        let targets = characterFormatTargets()
        guard !targets.isEmpty else {
            // Collapsed caret (no format targets): check the region under `head`.
            return isCollapsedTextCaret && isCodeLanguagePosition(head)
        }
        let regions = allLeafRegions()
        return targets.allSatisfy { target in
            guard let region = regions.first(where: { $0.layout.contentStorage.textStorage === target.storage }) else { return false }
            if case .codeLanguage = region.ref { return true }
            return false
        }
    }

    /// The toggle engine. `isSet` reports whether a storage range already fully carries the format;
    /// the direction is decided once globally (all covered ranges set → remove, else add) and passed
    /// to `setOn` as `allOn`.
    func applyCharacterToggle(isSet: (NSTextStorage, NSRange) -> Bool,
                              setOn: (NSTextStorage, NSRange, _ allOn: Bool) -> Void) {
        let covered = characterFormatTargets()
        guard !covered.isEmpty else { return }
        let allOn = covered.allSatisfy { isSet($0.storage, $0.range) }
        editing {
            for c in covered { setOn(c.storage, c.range, allOn) }
        }
    }

    func toggleBold() {
        if selectionIsEntirelyInCodeLanguageRegion() { return }   // a language is a plain string on the wire
        if isCollapsedTextCaret { pendingFormatToggles.formSymmetricDifference([.bold]); needsDisplay = true; onSelectionOrFormatChange?(); return }
        applyCharacterToggle(isSet: { storage, range in
            var all = true
            storage.enumerateAttribute(.font, in: range, options: []) { v, _, stop in
                let f = (v as? NSFont) ?? NSFont.systemFont(ofSize: 16)
                if !f.fontDescriptor.symbolicTraits.contains(.bold) { all = false; stop.pointee = true }
            }
            return all
        }, setOn: { storage, range, allOn in
            storage.enumerateAttribute(.font, in: range, options: []) { v, sub, _ in
                let f = (v as? NSFont) ?? NSFont.systemFont(ofSize: 16)
                var t = f.fontDescriptor.symbolicTraits
                if allOn { t.remove(.bold) } else { t.insert(.bold) }
                let d = f.fontDescriptor.withSymbolicTraits(t)
                if let nf = NSFont(descriptor: d, size: f.pointSize) {
                    storage.addAttribute(.font, value: nf, range: sub)
                }
            }
        })
    }

    func toggleItalic() {
        if selectionIsEntirelyInCodeLanguageRegion() { return }   // a language is a plain string on the wire
        if isCollapsedTextCaret { pendingFormatToggles.formSymmetricDifference([.italic]); needsDisplay = true; onSelectionOrFormatChange?(); return }
        applyCharacterToggle(isSet: { storage, range in
            var all = true
            storage.enumerateAttribute(.font, in: range, options: []) { v, _, stop in
                let f = (v as? NSFont) ?? NSFont.systemFont(ofSize: 16)
                if !f.fontDescriptor.symbolicTraits.contains(.italic) { all = false; stop.pointee = true }
            }
            return all
        }, setOn: { storage, range, allOn in
            storage.enumerateAttribute(.font, in: range, options: []) { v, sub, _ in
                let f = (v as? NSFont) ?? NSFont.systemFont(ofSize: 16)
                var t = f.fontDescriptor.symbolicTraits
                if allOn { t.remove(.italic) } else { t.insert(.italic) }
                let d = f.fontDescriptor.withSymbolicTraits(t)
                if let nf = NSFont(descriptor: d, size: f.pointSize) {
                    storage.addAttribute(.font, value: nf, range: sub)
                }
            }
        })
    }

    func toggleStrikethrough() {
        if selectionIsEntirelyInCodeLanguageRegion() { return }   // a language is a plain string on the wire
        if isCollapsedTextCaret { pendingFormatToggles.formSymmetricDifference([.strikethrough]); needsDisplay = true; onSelectionOrFormatChange?(); return }
        applyCharacterToggle(isSet: { storage, range in
            var all = true
            storage.enumerateAttribute(.strikethroughStyle, in: range, options: []) { v, _, stop in
                if ((v as? Int) ?? 0) == 0 { all = false; stop.pointee = true }
            }
            return all
        }, setOn: { storage, range, allOn in
            if allOn { storage.removeAttribute(.strikethroughStyle, range: range) }
            else { storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range) }
        })
    }

    func toggleUnderline() {
        if selectionIsEntirelyInCodeLanguageRegion() { return }   // a language is a plain string on the wire
        if isCollapsedTextCaret { pendingFormatToggles.formSymmetricDifference([.underline]); needsDisplay = true; onSelectionOrFormatChange?(); return }
        applyCharacterToggle(isSet: { storage, range in
            var all = true
            storage.enumerateAttribute(.underlineStyle, in: range, options: []) { v, _, stop in
                if ((v as? Int) ?? 0) == 0 { all = false; stop.pointee = true }
            }
            return all
        }, setOn: { storage, range, allOn in
            if allOn { storage.removeAttribute(.underlineStyle, range: range) }
            else { storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range) }
        })
    }

    /// Telegram spoiler: a render-only marker (`.rtSpoiler`) over the selection. It carries NO visible
    /// styling in storage — the visible HIDE is a TextKit-2 clear-foreground rendering attribute applied
    /// per region in `BlockLayout` (see `syncSpoilers`). Toggling round-trips to
    /// `CharacterAttributes.spoiler`. Mirrors `toggleStrikethrough`.
    func toggleSpoiler() {
        if selectionIsEntirelyInCodeLanguageRegion() { return }   // a language is a plain string on the wire
        if isCollapsedTextCaret { pendingFormatToggles.formSymmetricDifference([.spoiler]); needsDisplay = true; onSelectionOrFormatChange?(); return }
        applyCharacterToggle(isSet: { storage, range in
            var all = true
            storage.enumerateAttribute(.rtSpoiler, in: range, options: []) { v, _, stop in
                if ((v as? Bool) ?? false) == false { all = false; stop.pointee = true }
            }
            return all
        }, setOn: { storage, range, allOn in
            if allOn { storage.removeAttribute(.rtSpoiler, range: range) }
            else { storage.addAttribute(.rtSpoiler, value: true, range: range) }
        })
    }

    /// Inline code swaps the run's font for a monospaced one (and marks it). GFM code spans can't
    /// carry emphasis, so toggling off restores a plain system font at the same size (any bold/italic
    /// inside is intentionally dropped); the named-style font returns on the next model round-trip.
    func toggleInlineCode() {
        if selectionIsEntirelyInCodeLanguageRegion() { return }   // a language is a plain string on the wire
        if isCollapsedTextCaret { pendingFormatToggles.formSymmetricDifference([.inlineCode]); needsDisplay = true; onSelectionOrFormatChange?(); return }
        applyCharacterToggle(isSet: { storage, range in
            var all = true
            storage.enumerateAttribute(.rtInlineCode, in: range, options: []) { v, _, stop in
                if ((v as? Bool) ?? false) == false { all = false; stop.pointee = true }
            }
            return all
        }, setOn: { storage, range, allOn in
            storage.enumerateAttribute(.font, in: range, options: []) { v, sub, _ in
                let size = ((v as? NSFont) ?? NSFont.systemFont(ofSize: 16)).pointSize
                if allOn {
                    storage.removeAttribute(.rtInlineCode, range: sub)
                    storage.removeAttribute(.backgroundColor, range: sub)
                    storage.addAttribute(.font, value: NSFont.systemFont(ofSize: size), range: sub)
                } else {
                    storage.addAttribute(.rtInlineCode, value: true, range: sub)
                    storage.addAttribute(.backgroundColor, value: editorAppearance.inlineCodeBackground, range: sub)
                    storage.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: size, weight: .regular), range: sub)
                }
            }
        })
    }

    /// Applies the pending bare-caret format toggles to a typing-attributes dict (the insert path uses
    /// this). Each toggle flips the corresponding attribute relative to the inherited dict — so "click B"
    /// in normal text yields bold, and in already-bold text yields normal. No-op when nothing is pending.
    func applyPendingFormat(to dict: [NSAttributedString.Key: Any]) -> [NSAttributedString.Key: Any] {
        guard !pendingFormatToggles.isEmpty else { return dict }
        var d = dict
        var font = (d[.font] as? NSFont) ?? NSFont.systemFont(ofSize: 16)
        func flip(_ trait: NSFontDescriptor.SymbolicTraits) {
            var t = font.fontDescriptor.symbolicTraits
            if t.contains(trait) { t.remove(trait) } else { t.insert(trait) }
            font = NSFont(descriptor: font.fontDescriptor.withSymbolicTraits(t), size: font.pointSize) ?? font
        }
        if pendingFormatToggles.contains(.bold) { flip(.bold) }
        if pendingFormatToggles.contains(.italic) { flip(.italic) }
        if pendingFormatToggles.contains(.inlineCode) {
            if (d[.rtInlineCode] as? Bool) == true {
                d.removeValue(forKey: .rtInlineCode); d.removeValue(forKey: .backgroundColor)
                font = NSFont.systemFont(ofSize: font.pointSize)
            } else {
                d[.rtInlineCode] = true
                d[.backgroundColor] = editorAppearance.inlineCodeBackground
                font = NSFont.monospacedSystemFont(ofSize: font.pointSize, weight: .regular)
            }
        }
        d[.font] = font
        if pendingFormatToggles.contains(.strikethrough) {
            let on = ((d[.strikethroughStyle] as? Int) ?? 0) != 0
            if on { d.removeValue(forKey: .strikethroughStyle) }
            else { d[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
        }
        if pendingFormatToggles.contains(.underline) {
            let on = ((d[.underlineStyle] as? Int) ?? 0) != 0
            if on { d.removeValue(forKey: .underlineStyle) }
            else { d[.underlineStyle] = NSUnderlineStyle.single.rawValue }
        }
        if pendingFormatToggles.contains(.spoiler) {
            if (d[.rtSpoiler] as? Bool) == true { d.removeValue(forKey: .rtSpoiler) }
            else { d[.rtSpoiler] = true }
        }
        return d
    }

    /// The active character formats at the caret/selection — what a toolbar highlights. For a bare caret
    /// it's what the NEXT typed char would carry (inherited + pending); for a selection (or table
    /// row/column) it's the formats EVERY covered run carries.
    func currentCharacterFormatState() -> CharacterFormatState {
        var s = CharacterFormatState()
        if isCollapsedTextCaret {
            let d = typingAttributesAtGlobal(head)
            let traits = (d[.font] as? NSFont)?.fontDescriptor.symbolicTraits ?? []
            s.bold = traits.contains(.bold)
            s.italic = traits.contains(.italic)
            s.strikethrough = ((d[.strikethroughStyle] as? Int) ?? 0) != 0
            s.underline = ((d[.underlineStyle] as? Int) ?? 0) != 0
            s.inlineCode = (d[.rtInlineCode] as? Bool) ?? false
            s.spoiler = (d[.rtSpoiler] as? Bool) ?? false
            return s
        }
        let targets = characterFormatTargets()
        guard !targets.isEmpty else { return s }
        func allTrait(_ trait: NSFontDescriptor.SymbolicTraits) -> Bool {
            targets.allSatisfy { st, r in
                var ok = true
                st.enumerateAttribute(.font, in: r, options: []) { v, _, stop in
                    if !(((v as? NSFont)?.fontDescriptor.symbolicTraits ?? []).contains(trait)) { ok = false; stop.pointee = true }
                }
                return ok
            }
        }
        func allSet(_ key: NSAttributedString.Key, bool: Bool = false) -> Bool {
            targets.allSatisfy { st, r in
                var ok = true
                st.enumerateAttribute(key, in: r, options: []) { v, _, stop in
                    let present = bool ? ((v as? Bool) ?? false) : (((v as? Int) ?? 0) != 0)
                    if !present { ok = false; stop.pointee = true }
                }
                return ok
            }
        }
        s.bold = allTrait(.bold)
        s.italic = allTrait(.italic)
        s.strikethrough = allSet(.strikethroughStyle)
        s.underline = allSet(.underlineStyle)
        s.inlineCode = allSet(.rtInlineCode, bool: true)
        s.spoiler = allSet(.rtSpoiler, bool: true)
        return s
    }
}
#endif
