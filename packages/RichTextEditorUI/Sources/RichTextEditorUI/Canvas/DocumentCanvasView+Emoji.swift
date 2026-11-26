#if canImport(AppKit)
import AppKit
import RichTextEditorCore

/// A non-interactive overlay so taps pass through to the canvas; hosts every emoji NSView.
@available(macOS 12, *)
final class NonInteractiveOverlayView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override var isFlipped: Bool { true }
}

/// One pooled host emoji view + its last placed canvas frame (used for culling).
@available(macOS 12, *)
final class HostedEmoji {
    let view: NSView
    var canvasFrame: CGRect
    init(view: NSView, canvasFrame: CGRect) { self.view = view; self.canvasFrame = canvasFrame }
}

@available(macOS 12, *)
extension DocumentCanvasView {
    /// True for either of a code block's two leaf regions — its `.codeLanguage` line and its `.code` text.
    /// Neither can carry an inline atom: the language is a plain string and a `.Pre` block carries no
    /// nested entities, so a `U+FFFC` in either is sent as a literal object-replacement character.
    static func regionIsCode(_ ref: TextNodeRef) -> Bool {
        switch ref {
        case .code, .codeLanguage: return true
        default: return false
        }
    }

    /// True when the caret sits in one of a code block's regions (language line or code text). The
    /// atom-inserting commands — `insertEmoji`, `insertFormula` — refuse on it.
    func caretIsInCodeRegion() -> Bool {
        guard let (region, _) = leafRegion(containingGlobal: head) else { return false }
        return Self.regionIsCode(region.ref)
    }

    /// Inserts one inline custom emoji (a single `U+FFFC` atom carrying an `EmojiRef`) at the caret,
    /// replacing any non-empty selection first. The atom inherits the caret's typing attributes plus an
    /// `EmojiTextAttachment`. Caret lands after the atom. The host NSView is realized in the next layout
    /// pass (`syncEmojiViews`).
    func insertEmoji(id: String, altText: String?) {
        guard !boxes.isEmpty else { return }
        // BOTH of a code block's regions are plain strings on the wire (a `.Pre` block carries no nested
        // entities): a custom-emoji U+FFFC would survive into the model as a literal character in the
        // language name or in the code body, with the emoji reference itself dropped on send. Refused
        // BEFORE `editing { }` so a live selection isn't cleared by an insert that then declines to run.
        if selectionIsEntirelyInCodeLanguageRegion() || caretIsInCodeRegion() { return }
        let ref = EmojiRef(id: id, instanceID: BlockID.generate().rawValue, altText: altText)
        editing {
            if selFrom != selTo { applySelectionReplace(globalFrom: selFrom, globalTo: selTo, text: "") }
            // A caret resting on a non-renderable slot (e.g. a table-box structural boundary) is
            // snapped to the nearest real leaf region so the emoji lands in editable text.
            if leafRegion(containingGlobal: head) == nil {
                let snapped = snapToRenderable(head, forward: true); anchor = snapped; head = snapped
            }
            guard let (region, local) = leafRegion(containingGlobal: head) else { return }
            // Re-check after the snap: a caret on a structural slot can land in a code region.
            if Self.regionIsCode(region.ref) { return }
            var attrs = typingAttributeDict(region: region, atLocal: local)
            let font = (attrs[.font] as? NSFont) ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
            attrs[.attachment] = EmojiTextAttachment(ref: ref, scale: mapper.emojiScale,
                                                     renderBoost: mapper.emojiRenderBoost(forFont: font))
            let frag = NSAttributedString(string: "\u{FFFC}", attributes: attrs)
            region.layout.replace(start: local, end: local, with: frag)
            recomputeSpans()
            let caret = region.globalStart + local + 1
            anchor = caret; head = caret
        }
        needsLayout = true
    }

    /// Reconciles host emoji views against the attachments currently present in every leaf region:
    /// pools/realizes by `instanceID`, positions each at its attachment's canvas rect, and removes
    /// views whose attachment no longer exists. Called at the END of the layout pass.
    func syncEmojiViews() {
        var present = Set<String>()
        for region in allLeafRegions() {
            let attr = region.layout.attributedString
            attr.enumerateAttribute(.attachment, in: NSRange(location: 0, length: attr.length), options: []) { value, range, _ in
                guard let att = value as? EmojiTextAttachment,
                      let box = region.layout.selectionRects(start: range.location, end: range.location + range.length).first else { return }
                // The visible host view renders `renderBoost` points larger than the reserved glyph box,
                // centered on it — the layout box (line height, caret, selection) is untouched.
                let canvasRect = box.offsetBy(dx: region.canvasOrigin.x, dy: region.canvasOrigin.y)
                    .insetBy(dx: -att.renderBoost / 2, dy: -att.renderBoost / 2)
                present.insert(att.ref.instanceID)
                let hosted: HostedEmoji
                if let h = emojiViews[att.ref.instanceID] { hosted = h }
                else if let v = emojiViewProvider(att.ref.id, canvasRect.size) {
                    v.frame = canvasRect                 // set the frame BEFORE adding to the window, so the
                    let h = HostedEmoji(view: v, canvasFrame: canvasRect)   // host view sees a non-zero
                    emojiViews[att.ref.instanceID] = h   // visibleRect in viewDidMoveToSuperview/Window and
                    emojiOverlay.addSubview(v)           // begins animating immediately (not on a later re-poke)
                    hosted = h
                } else { return }
                hosted.canvasFrame = canvasRect
                hosted.view.frame = canvasRect
            }
        }
        for (iid, h) in emojiViews where !present.contains(iid) { h.view.removeFromSuperview(); emojiViews[iid] = nil }
        cullEmojiViews()
    }

    /// Hides emoji views whose canvas frame falls outside the visible viewport expanded by
    /// `emojiCullMargin` (so off-screen host views aren't paying layout/animation cost).
    func cullEmojiViews() {
        let visible = enclosingScrollView?.contentView.bounds ?? bounds
        let expanded = visible.insetBy(dx: -emojiCullMargin, dy: -emojiCullMargin)
        for (_, h) in emojiViews { h.view.isHidden = !expanded.intersects(h.canvasFrame) }
    }
}
#endif
