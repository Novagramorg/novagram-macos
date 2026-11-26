#if canImport(AppKit)
import AppKit
import RichTextEditorCore

@available(macOS 12, *)
extension DocumentCanvasView {
    /// Max LaTeX length for a formula.
    static let maxFormulaLength = 1024

    /// Inserts (or, when the caret is on / adjacent to an existing formula, replaces) a formula at the
    /// caret — a single `U+FFFC` carrying `CharacterAttributes.formula`, rendered via SwiftMath. Drives the
    /// host's LaTeX modal; formulas are now created ONLY through it (no inline `$…$` / `\(…\)` auto-parsing).
    /// A blank latex on an existing formula removes it. Mirrors `insertEmoji`'s atom-insert chokepoint.
    func insertFormula(latex: String) {
        let trimmed = latex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !boxes.isEmpty, (trimmed as NSString).length <= DocumentCanvasView.maxFormulaLength else { return }
        // Inert in BOTH of a code block's regions — the language line AND the code text (same rule as
        // emoji: a formula U+FFFC would survive into the model as a literal character). The UIKit editor
        // refuses the whole box here too (`activeStack(at: head).box is CodeBlockBox`). Refused BEFORE
        // `editing { }` so a live selection isn't cleared by an insert that then declines to run.
        if caretIsInCodeRegion() { return }
        editing {
            if let (lo, hi) = formulaTargetRange() { anchor = lo; head = hi }   // editing an existing formula → replace it
            if selFrom != selTo { applySelectionReplace(globalFrom: selFrom, globalTo: selTo, text: "") }
            guard !trimmed.isEmpty else { return }                              // blank → just delete the old atom
            // A caret resting on a non-renderable slot (e.g. a table-box structural boundary) is snapped to
            // the nearest real leaf region so the formula lands in editable text.
            if leafRegion(containingGlobal: head) == nil {
                let snapped = snapToRenderable(head, forward: true); anchor = snapped; head = snapped
            }
            guard let (region, local) = leafRegion(containingGlobal: head) else { return }
            // Re-check after the snap: a caret on a structural slot can land in a code region.
            if Self.regionIsCode(region.ref) { return }
            let frag = formulaFrag(latex: trimmed, basedOn: typingAttributeDict(region: region, atLocal: local))
            region.layout.replace(start: local, end: local, with: frag)
            recomputeSpans()
            let caret = region.globalStart + local + 1
            anchor = caret; head = caret
        }
        needsLayout = true
    }

    /// The LaTeX of the formula the caret is acting on — the selected single atom, else the atom immediately
    /// before the caret, else the one just after it. nil when the caret isn't on a formula. Lets the host
    /// pre-fill its modal for editing (like `currentLink()`).
    func currentFormula() -> String? {
        if selFrom != selTo {
            return (selTo - selFrom == 1) ? formulaLatex(atGlobal: selFrom) : nil
        }
        return formulaLatex(atGlobal: head - 1) ?? formulaLatex(atGlobal: head)
    }

    /// The global range of a formula atom whose glyph box (with a little slop) contains the canvas point
    /// `p`, or nil. Drives click-to-select — a single click on a formula selects the atom (accent wash)
    /// rather than dropping a caret beside it.
    func formulaAtomRange(atCanvasPoint p: NSPoint) -> (Int, Int)? {
        let pos = closestGlobalPosition(to: p)
        for atomStart in [pos, pos - 1] where atomStart >= 0 {
            guard formulaLatex(atGlobal: atomStart) != nil else { continue }
            let a = caretRect(forGlobal: atomStart)              // just before the atom
            let b = caretRect(forGlobal: atomStart + 1)          // just after it
            let loX = min(a.minX, b.minX) - 2, hiX = max(a.minX, b.minX) + 2
            if p.x >= loX, p.x <= hiX, p.y >= a.minY - 2, p.y <= a.maxY + 2 { return (atomStart, atomStart + 1) }
        }
        return nil
    }

    /// The single `.rtFormula` atom's LaTeX starting at `pos`, or nil if `pos` isn't a formula atom.
    func formulaLatex(atGlobal pos: Int) -> String? {
        guard pos >= 0, let (region, local) = leafRegion(containingGlobal: pos) else { return nil }
        let ns = region.layout.attributedString
        guard local < ns.length else { return nil }
        return ns.attribute(.rtFormula, at: local, effectiveRange: nil) as? String
    }

    /// The global range of the formula atom `insertFormula` should replace (selected atom, else the atom
    /// before the caret, else the one after), or nil to insert a new one.
    private func formulaTargetRange() -> (Int, Int)? {
        if selFrom != selTo {
            return (selTo - selFrom == 1 && formulaLatex(atGlobal: selFrom) != nil) ? (selFrom, selTo) : nil
        }
        if formulaLatex(atGlobal: head - 1) != nil { return (head - 1, head) }
        if formulaLatex(atGlobal: head) != nil { return (head, head + 1) }
        return nil
    }

    /// Builds a one-`U+FFFC` formula atom carrying `.rtFormula` (the model latex) + a best-effort rendered
    /// image attachment, inheriting the font/colour/paragraph style of `attrs`.
    private func formulaFrag(latex: String, basedOn attrs: [NSAttributedString.Key: Any]) -> NSAttributedString {
        let font = (attrs[.font] as? NSFont) ?? mapper.styleSheet.font(for: .body, attributes: .plain)
        let color = (attrs[.foregroundColor] as? NSColor) ?? editorAppearance.defaultForeground
        var fragAttrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .rtFormula: latex]
        if let att = FormulaTextAttachment(latex: latex, fontSize: font.pointSize, color: color) { fragAttrs[.attachment] = att }
        if let ps = attrs[.paragraphStyle] { fragAttrs[.paragraphStyle] = ps }
        return NSAttributedString(string: "\u{FFFC}", attributes: fragAttrs)
    }
}
#endif
